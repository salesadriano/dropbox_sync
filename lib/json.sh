#!/usr/bin/env bash
# lib/json.sh — interpretacao de resposta JSON, sem `jq`.
#
# Camada: adaptadores. Depende apenas de lib/errors.sh, de dominio, para nao
# manter uma segunda tabela de codigos de saida. NAO e o contrario: lib/errors
# nao conhece este componente (invariante fixada por teste na Etapa 1 e
# corrigida no System Design v0.4, DIV-A.1).
#
# Este componente le resposta de servico externo NAO CONFIAVEL em shell puro.
# E o ponto exato em que o projeto de referencia falha (DIV-04), extraindo campo
# por expressao regular com `sed`: qualquer valor contendo o delimitador
# procurado corrompe a extracao em silencio. Aqui a entrada e interpretada por
# um analisador real, e entrada malformada falha FECHADA e CLASSIFICADA.
#
# Desenho: mesma varredura em passada unica adotada em `dbx_errors_redigir`,
# pelo mesmo motivo. Medido antes de escolher, com o corpus realista de uma
# resposta de listagem:
#
#   leitura caractere a caractere : 3.947/7.897/15.799/31.899 chars -> 17/22/48/98 ms
#   marcacao + divisao unica      : os mesmos tamanhos            ->  4/ 4/ 8/16 ms
#
# Ambas lineares; a segunda e cerca de seis vezes mais rapida. Nao se usa
# indexacao de cadeia longa (`${cadeia:indice:1}`), que e quadratica em `bash`
# mesmo sob `LC_ALL=C` — armadilha medida e registrada na Etapa 1.
#
# Contrato de status, alinhado a taxonomia de RF-29 para que um status propagado
# nunca signifique duas coisas:
#   0   sucesso
#   2   uso invalido (argumento ausente)
#   10  erro remoto: corpo inutilizavel — malformado, ou alem dos limites
#
# `DBX_JSON_MOTIVO` distingue a causa sem inventar codigo de saida novo:
# `malformado`, `profundidade`, `tamanho`, `controle`.
#
# O valor e devolvido em DBX_JSON_RESULTADO, e nao apenas impresso: a
# substituicao de comando remove quebras de linha finais, e um valor JSON pode
# terminar em quebra de linha. Licao fixada na Etapa 1 (defeito D1/C2-01).

[[ -n ${DBX_JSON_CARREGADO:-} ]] && return 0
DBX_JSON_CARREGADO=1

_dbx_json_diretorio=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_json_diretorio/errors.sh"
unset _dbx_json_diretorio

DBX_JSON_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_JSON_ERRO_REMOTO=$(dbx_errors_codigo_saida erro_remoto)
readonly DBX_JSON_ERRO_USO DBX_JSON_ERRO_REMOTO

# Limites defensivos. Sao `readonly` de proposito: um teto que venha do ambiente
# nao e teto (licao do defeito C2-10).
#
# Profundidade 32: as respostas da Dropbox aninham em torno de 4 niveis; 32 da
# folga larga e ainda limita a recursao do analisador.
#
# Entrada 256 KiB: o teto e dimensionado pelo CUSTO MEDIDO, e nao por folga
# abstrata. Medicao com corpus realista de listagem: 100 entradas / 5.100 chars
# = 88 ms · 200 / 10.500 = 195 ms · 400 / 21.300 = 411 ms · 800 / 42.900 =
# 882 ms. O crescimento NAO e linear: o expoente medido fica em torno de 1,45,
# e a afirmacao de linearidade da versao anterior estava errada. A estimativa de
# pior caso na ordem de 5 s no teto se sustenta. Um teto de 4 MiB, considerado a
# principio, extrapolaria para dezenas de segundos — o mesmo defeito de teto
# desproporcional ja corrigido em `dbx_errors_redigir` (R-04).
#
# REQUISITO DE ENTRADA PARA lib/http (RNF-23): toda chamada que retorne colecao
# precisa ser paginada com `limit` explicito. Medida de referencia: 488 bytes
# por entrada, entao 256 KiB comportam cerca de 537 entradas, enquanto
# `list_folder` sem `limit` pode devolver 2.000 (~976 KB, quase quatro vezes o
# teto). Recomendacao: `limit` de no maximo 100, que da ~49 KB e ~0,41 s por
# pagina. E, ao receber `DBX_JSON_MOTIVO=tamanho`, o chamador deve REDUZIR o
# limite e repetir, e nao abortar a operacao.
readonly DBX_JSON_MAXIMO_PROFUNDIDADE=32
readonly DBX_JSON_MAXIMO_ENTRADA=262144

# Guarda de obsolescencia de estado (E2-09).
#
# O estado do analisador e global. Uma analise feita dentro de `$( )` ou `( )`
# se perde ao voltar, e as consultas seguintes no processo de origem devolvem o
# DOCUMENTO ANTERIOR com status 0 — obsolescencia silenciosa, o pior modo de
# falha. A recusa e precisa: analisar em subshell so e proibido quando JA existe
# analise pertencente a outro processo, porque e exatamente essa a combinacao
# que deixa estado obsoleto para tras.
#
# O observavel que caracteriza o defeito nao e o processo pai conservar o
# documento antigo — isso e semantica correta de shell — e sim o componente
# reportar SUCESSO para uma analise cujo resultado seria descartado. Hoje esse
# caso devolve status 2 com motivo `subshell`.
#
# A guarda e avaliada POR CONTEXTO, e o contexto nomeado nao a afrouxa: analisar
# em subshell sobre estado que pertence a outro processo continua recusado, em
# qualquer contexto.
#
# PRECISAO IMPORTANTE, corrigindo justificativa anterior. Ja se afirmou aqui que
# "o caso legitimo e o perigoso sao distinguiveis". ISSO E FALSO. No momento da
# analise a guarda nao tem como saber se o chamador consultara dentro do
# subshell ou no processo pai — e exatamente a mesma indistinguibilidade
# registrada logo abaixo, na limitacao conhecida.
#
# O que ocorre e diferente, e melhor: pelo caminho do CONTEXTO NOVO o caso
# indistinguivel foi tornado INOFENSIVO. O estado nao volta ao pai, entao a
# consulta la nao encontra o documento em vez de responder com valor de outro.
# A consequencia migrou de "valor errado" para "falha fechada"; o que resta e um
# status que mente para o pai, sem janela em que dado errado seja devolvido.
#
# A distincao nao e academica. O raciocinio errado — "os casos sao
# distinguiveis" — poderia justificar, no futuro, relaxar TAMBEM a guarda do
# MESMO contexto. La a metade perigosa nao esta fechada, o estado anterior segue
# consultavel, e o E2-09 voltaria inteiro.
#
# LIMITACAO CONHECIDA, e nao promessa. Havendo documento corrente NAQUELE
# contexto, analisar dentro de subshell e recusado mesmo quando a consulta
# tambem ocorre ali dentro: a guarda nao tem como saber, no momento da analise,
# se havera consulta interna, e permitir o caso reabriria a obsolescencia
# silenciosa. A redacao original deste comentario prometia que o subshell
# autocontido continuava valido — o texto e que estava errado, nao a guarda
# (E3-01).
#
# O caso legitimo que motivava aquela promessa — interpretar um corpo de erro
# sem destruir uma listagem em curso — passou a ser atendido pelo CONTEXTO
# NOMEADO, e nao por subshell. Ver `dbx_json_contexto`.
#
# Consultar e sempre permitido, por ser leitura: leitura nao deixa estado
# obsoleto para tras.
DBX_JSON_PROCESSO_ANALISE=''

# Indice hierarquico por NO, e nao caminho concatenado.
#
# A versao anterior juntava os segmentos numa cadeia delimitada por `0x1f`.
# Isso reintroduzia internamente exatamente o que a API publica evita ao receber
# os segmentos separados: delimitador **em banda com o dado**. Um nome de chave
# contendo o separador — cru ou, pior, por escape unicode decodificado DEPOIS da
# verificacao — passava a designar outro campo, e quem controla a resposta podia
# substituir `content_hash`, `rev` ou `cursor`. E a mesma classe de DIV-04, que
# este componente existe para eliminar.
#
# Agora cada no tem um identificador inteiro e a unica composicao e
# `<id do pai><0x1f><segmento>`. Essa composicao e INJETIVA, e por isso segura:
# o lado esquerdo e sempre uma sequencia de digitos, entao a primeira ocorrencia
# do separador determina univocamente onde termina o pai e onde comeca o
# segmento. Dois pares distintos nao podem produzir a mesma cadeia, qualquer que
# seja o conteudo do segmento — inclusive se ele contiver o proprio separador.
# Nao ha, portanto, ordem de operacoes a acertar entre decodificar e validar.
#
# A raiz e o no `0`, o que tambem elimina o sentinela de documento da versao
# anterior e o sequestro de raiz que ele permitia.
readonly DBX_JSON_SEP_INDICE=$'\x1f'

readonly DBX_JSON_DELIMITADORES=('{' '}' '[' ']' ':' ',' '"' $'\\' ' ' $'\t' $'\n' $'\r')

# shellcheck disable=SC2034  # canal de diagnostico lido pelo chamador e pela
# suite; o analisador nao enxerga o uso porque ele esta em outro arquivo.
DBX_JSON_ERRO=''
# shellcheck disable=SC2034
DBX_JSON_MOTIVO=''
DBX_JSON_RESULTADO=''
DBX_JSON_ANALISADO=0
# Contexto nomeado.
#
# `lib/http` precisa interpretar um corpo de erro sem destruir uma listagem em
# curso. Cada contexto tem raiz propria, e o POOL DE NOS e compartilhado: os
# identificadores sao globalmente unicos, entao a composicao de chave continua
# sendo exatamente `<id do pai><separador><segmento>`, com o mesmo argumento de
# injetividade ja validado. O contexto nao entra na chave, e portanto nao abre
# porta nova para a classe do E2-01.
#
# O nome do contexto e escolhido pelo PROJETO e nunca vem de dado externo. A
# restricao a letras minusculas e sublinhado e verificada em tempo de execucao,
# e nao apenas por convencao.
readonly DBX_JSON_CONTEXTO_PADRAO='padrao'
DBX_JSON_CONTEXTO=$DBX_JSON_CONTEXTO_PADRAO
DBX_JSON_CONTEXTO_ANTERIOR=''
declare -gA DBX_JSON_RAIZ_DO_CONTEXTO=()
declare -gA DBX_JSON_ANALISADO_DO_CONTEXTO=()
declare -gA DBX_JSON_PROCESSO_DO_CONTEXTO=()
declare -gA DBX_JSON_ERRO_DO_CONTEXTO=()
declare -gA DBX_JSON_MOTIVO_DO_CONTEXTO=()
declare -gA DBX_JSON_INICIO_DO_CONTEXTO=()
declare -gA DBX_JSON_FIM_DO_CONTEXTO=()
declare -gA DBX_JSON_CHAVE_DO_NO=()

declare -ga DBX_JSON_TIPOS=()
declare -ga DBX_JSON_VALORES=()
declare -ga DBX_JSON_TAMANHO=()
declare -ga DBX_JSON_NFILHOS=()
declare -gA DBX_JSON_FILHO=()
declare -gA DBX_JSON_SEGMENTO=()
DBX_JSON_PROXIMO_ID=0

# ---------------------------------------------------------------------------
# Apoio interno
# ---------------------------------------------------------------------------

_dbx_json_falhar() {
  DBX_JSON_MOTIVO=$1
  DBX_JSON_ERRO=$2
  DBX_JSON_ANALISADO=0
  DBX_JSON_MOTIVO_DO_CONTEXTO[$DBX_JSON_CONTEXTO]=$1
  DBX_JSON_ERRO_DO_CONTEXTO[$DBX_JSON_CONTEXTO]=$2
  DBX_JSON_ANALISADO_DO_CONTEXTO[$DBX_JSON_CONTEXTO]=0
  return "$DBX_JSON_ERRO_REMOTO"
}

# _dbx_json_avancar — posiciona no proximo elemento significativo.
_dbx_json_avancar() {
  while [[ $_dbx_json_pos -lt $_dbx_json_total ]]; do
    case ${_dbx_json_e[$_dbx_json_pos]} in
      '') ;;
      ' ' | $'\t' | $'\n' | $'\r') ;;
      *) return 0 ;;
    esac
    _dbx_json_pos=$((_dbx_json_pos + 1))
  done
  return 1
}

_dbx_json_definir() {
  local no=$1 tipo=$2 valor=$3
  DBX_JSON_TIPOS[no]=$tipo
  DBX_JSON_VALORES[no]=$valor
}

# _dbx_json_criar_filho <no_pai> <segmento> — deixa o id em _dbx_json_filho_id.
# Nao imprime: o canal de chave nunca passa por `$( )`, que removeria quebras de
# linha finais e entregaria outro campo (defeito E2-04, terceira ocorrencia
# desta classe no projeto).
_dbx_json_criar_filho() {
  local pai=$1 segmento=$2 chave="$1$DBX_JSON_SEP_INDICE$2" indice
  _dbx_json_filho_id=$((++DBX_JSON_PROXIMO_ID))
  DBX_JSON_CHAVE_DO_NO[$_dbx_json_filho_id]=$chave
  DBX_JSON_TIPOS[_dbx_json_filho_id]=''
  DBX_JSON_VALORES[_dbx_json_filho_id]=''
  DBX_JSON_TAMANHO[_dbx_json_filho_id]=0
  DBX_JSON_NFILHOS[_dbx_json_filho_id]=0
  if [[ -n ${DBX_JSON_FILHO[$chave]:-} ]]; then
    # Chave duplicada: vence a ultima ocorrencia, e o no anterior fica
    # inalcancavel junto com toda a sua descendencia. Sem trocar o no, as
    # filhas da primeira ocorrencia sobreviveriam como fantasmas (E2-08).
    DBX_JSON_FILHO[$chave]=$_dbx_json_filho_id
    return 0
  fi
  DBX_JSON_FILHO[$chave]=$_dbx_json_filho_id
  indice=${DBX_JSON_NFILHOS[pai]}
  DBX_JSON_SEGMENTO[$pai$DBX_JSON_SEP_INDICE$indice]=$segmento
  DBX_JSON_NFILHOS[pai]=$((indice + 1))
}

# _dbx_json_cadeia — le uma cadeia a partir da aspa de abertura.
# Deixa o texto decodificado em _dbx_json_cadeia_valor.
_dbx_json_cadeia() {
  _dbx_json_cadeia_valor=''
  local elemento termo escape resto codigo alto baixo codificado
  _dbx_json_pos=$((_dbx_json_pos + 1)) # consome a aspa de abertura

  while [[ $_dbx_json_pos -lt $_dbx_json_total ]]; do
    elemento=${_dbx_json_e[$_dbx_json_pos]}
    if [[ -z $elemento ]]; then
      _dbx_json_pos=$((_dbx_json_pos + 1))
      continue
    fi
    if [[ $elemento == '"' ]]; then
      _dbx_json_pos=$((_dbx_json_pos + 1))
      return 0
    fi
    if [[ $elemento == $'\\' ]]; then
      _dbx_json_pos=$((_dbx_json_pos + 1))
      while [[ $_dbx_json_pos -lt $_dbx_json_total && -z ${_dbx_json_e[$_dbx_json_pos]} ]]; do
        _dbx_json_pos=$((_dbx_json_pos + 1))
      done
      [[ $_dbx_json_pos -lt $_dbx_json_total ]] ||
        { _dbx_json_falhar malformado 'escape truncado no fim da entrada'; return $?; }
      termo=${_dbx_json_e[$_dbx_json_pos]}
      case $termo in
        '"' | $'\\' | '/')
          _dbx_json_cadeia_valor+=$termo
          _dbx_json_pos=$((_dbx_json_pos + 1))
          continue
          ;;
      esac
      escape=${termo:0:1}
      resto=${termo:1}
      case $escape in
        # `/` nao e delimitador da marcacao, entao `\/` chega colado ao resto do
        # termo e precisa ser tratado aqui, e nao no ramo de delimitador acima.
        '/' | '"' | $'\\') _dbx_json_cadeia_valor+=$escape ;;
        n) _dbx_json_cadeia_valor+=$'\n' ;;
        t) _dbx_json_cadeia_valor+=$'\t' ;;
        r) _dbx_json_cadeia_valor+=$'\r' ;;
        b) _dbx_json_cadeia_valor+=$'\b' ;;
        f) _dbx_json_cadeia_valor+=$'\f' ;;
        u)
          codigo=${termo:1:4}
          [[ $codigo =~ ^[0-9a-fA-F]{4}$ ]] ||
            { _dbx_json_falhar malformado "escape unicode invalido"; return $?; }
          resto=${termo:5}
          alto=$((16#$codigo))
          if [[ $alto -ge 55296 && $alto -le 56319 ]]; then
            # Surrogate alto: em JSON o par e obrigatorio e imediato. Qualquer
            # texto entre os dois escapes torna o par invalido.
            [[ -z $resto ]] ||
              { _dbx_json_falhar malformado 'surrogate alto sem par imediato'; return $?; }
            _dbx_json_pos=$((_dbx_json_pos + 1))
            while [[ $_dbx_json_pos -lt $_dbx_json_total && -z ${_dbx_json_e[$_dbx_json_pos]} ]]; do
              _dbx_json_pos=$((_dbx_json_pos + 1))
            done
            [[ ${_dbx_json_e[$_dbx_json_pos]:-} == $'\\' ]] ||
              { _dbx_json_falhar malformado 'surrogate alto sem par'; return $?; }
            _dbx_json_pos=$((_dbx_json_pos + 1))
            while [[ $_dbx_json_pos -lt $_dbx_json_total && -z ${_dbx_json_e[$_dbx_json_pos]} ]]; do
              _dbx_json_pos=$((_dbx_json_pos + 1))
            done
            termo=${_dbx_json_e[$_dbx_json_pos]:-}
            [[ ${termo:0:1} == 'u' ]] ||
              { _dbx_json_falhar malformado 'surrogate alto sem par'; return $?; }
            codigo=${termo:1:4}
            [[ $codigo =~ ^[0-9a-fA-F]{4}$ ]] ||
              { _dbx_json_falhar malformado 'par surrogate invalido'; return $?; }
            baixo=$((16#$codigo))
            [[ $baixo -ge 56320 && $baixo -le 57343 ]] ||
              { _dbx_json_falhar malformado 'surrogate baixo fora da faixa'; return $?; }
            resto=${termo:5}
            alto=$((65536 + (alto - 55296) * 1024 + (baixo - 56320)))
          elif [[ $alto -ge 56320 && $alto -le 57343 ]]; then
            { _dbx_json_falhar malformado 'surrogate baixo sem surrogate alto'; return $?; }
          fi
          # shellcheck disable=SC2059  # a sequencia `\U` precisa estar NO formato:
          # e o proprio `printf` do shell que converte o ponto de codigo em UTF-8,
          # e passar o valor como argumento nao produziria essa conversao.
          printf -v codificado "\\U$(printf '%08x' "$alto")"
          _dbx_json_cadeia_valor+=$codificado
          ;;
        *)
          { _dbx_json_falhar malformado "escape desconhecido: \\$escape"; return $?; }
          ;;
      esac
      if [[ -n $resto ]]; then
        _dbx_json_e[_dbx_json_pos]=$resto
      else
        _dbx_json_pos=$((_dbx_json_pos + 1))
      fi
      continue
    fi
    _dbx_json_cadeia_valor+=$elemento
    _dbx_json_pos=$((_dbx_json_pos + 1))
  done
  { _dbx_json_falhar malformado 'cadeia sem aspa de fechamento'; return $?; }
}

# _dbx_json_ler_valor <id_do_no> <profundidade>
_dbx_json_ler_valor() {
  local chave=$1 profundidade=$2 elemento termo

  # `-lt` deixava o teto efetivo em 31; a comparacao correta e `-le` sobre a
  # profundidade do valor que esta sendo lido (E2-11).
  [[ $profundidade -le $DBX_JSON_MAXIMO_PROFUNDIDADE ]] ||
    { _dbx_json_falhar profundidade "aninhamento acima de $DBX_JSON_MAXIMO_PROFUNDIDADE niveis"; return $?; }

  _dbx_json_avancar || { _dbx_json_falhar malformado 'valor ausente'; return $?; }
  elemento=${_dbx_json_e[$_dbx_json_pos]}

  case $elemento in
    '"')
      _dbx_json_cadeia || return $?
      _dbx_json_definir "$chave" cadeia "$_dbx_json_cadeia_valor"
      return 0
      ;;
    '{')
      _dbx_json_objeto "$chave" "$profundidade"
      return $?
      ;;
    '[')
      _dbx_json_arranjo "$chave" "$profundidade"
      return $?
      ;;
    '}' | ']' | ',' | ':')
      { _dbx_json_falhar malformado "valor esperado, encontrado '$elemento'"; return $?; }
      ;;
  esac

  termo=$elemento
  _dbx_json_pos=$((_dbx_json_pos + 1))
  case $termo in
    true | false)
      _dbx_json_definir "$chave" booleano "$termo"
      ;;
    null)
      _dbx_json_definir "$chave" nulo ''
      ;;
    *)
      # Numero segundo o RFC: sem zero a esquerda, sem sinal de mais inicial.
      [[ $termo =~ ^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$ ]] ||
        { _dbx_json_falhar malformado "token invalido: '$termo'"; return $?; }
      _dbx_json_definir "$chave" numero "$termo"
      ;;
  esac
  return 0
}

_dbx_json_objeto() {
  local chave=$1 profundidade=$2 nome quantidade=0
  _dbx_json_definir "$chave" objeto ''
  _dbx_json_pos=$((_dbx_json_pos + 1)) # consome '{'

  _dbx_json_avancar || { _dbx_json_falhar malformado 'objeto sem fechamento'; return $?; }
  if [[ ${_dbx_json_e[$_dbx_json_pos]} == '}' ]]; then
    _dbx_json_pos=$((_dbx_json_pos + 1))
    DBX_JSON_TAMANHO[chave]=0
    return 0
  fi

  while :; do
    _dbx_json_avancar || { _dbx_json_falhar malformado 'objeto sem fechamento'; return $?; }
    [[ ${_dbx_json_e[$_dbx_json_pos]} == '"' ]] ||
      { _dbx_json_falhar malformado 'chave de objeto precisa ser cadeia'; return $?; }
    _dbx_json_cadeia || return $?
    nome=$_dbx_json_cadeia_valor

    _dbx_json_avancar || { _dbx_json_falhar malformado 'dois-pontos ausente'; return $?; }
    [[ ${_dbx_json_e[$_dbx_json_pos]} == ':' ]] ||
      { _dbx_json_falhar malformado 'dois-pontos ausente apos a chave'; return $?; }
    _dbx_json_pos=$((_dbx_json_pos + 1))

    _dbx_json_criar_filho "$chave" "$nome"
    _dbx_json_ler_valor "$_dbx_json_filho_id" $((profundidade + 1)) || return $?
    quantidade=$((quantidade + 1))

    _dbx_json_avancar || { _dbx_json_falhar malformado 'objeto sem fechamento'; return $?; }
    case ${_dbx_json_e[$_dbx_json_pos]} in
      ',')
        _dbx_json_pos=$((_dbx_json_pos + 1))
        _dbx_json_avancar || { _dbx_json_falhar malformado 'objeto sem fechamento'; return $?; }
        [[ ${_dbx_json_e[$_dbx_json_pos]} == '}' ]] &&
          { _dbx_json_falhar malformado 'virgula sobrando antes de }'; return $?; }
        ;;
      '}')
        _dbx_json_pos=$((_dbx_json_pos + 1))
        # Chaves distintas, e nao ocorrencias sintaticas: com chave duplicada,
        # o contador divergia da enumeracao (E3-03).
        DBX_JSON_TAMANHO[chave]=${DBX_JSON_NFILHOS[chave]}
        return 0
        ;;
      *)
        { _dbx_json_falhar malformado "virgula ou } esperados, encontrado '${_dbx_json_e[$_dbx_json_pos]}'"; return $?; }
        ;;
    esac
  done
}

_dbx_json_arranjo() {
  local chave=$1 profundidade=$2 indice=0
  _dbx_json_definir "$chave" arranjo ''
  _dbx_json_pos=$((_dbx_json_pos + 1)) # consome '['

  _dbx_json_avancar || { _dbx_json_falhar malformado 'arranjo sem fechamento'; return $?; }
  if [[ ${_dbx_json_e[$_dbx_json_pos]} == ']' ]]; then
    _dbx_json_pos=$((_dbx_json_pos + 1))
    DBX_JSON_TAMANHO[chave]=0
    return 0
  fi

  while :; do
    _dbx_json_criar_filho "$chave" "$indice"
    _dbx_json_ler_valor "$_dbx_json_filho_id" $((profundidade + 1)) || return $?
    indice=$((indice + 1))

    _dbx_json_avancar || { _dbx_json_falhar malformado 'arranjo sem fechamento'; return $?; }
    case ${_dbx_json_e[$_dbx_json_pos]} in
      ',')
        _dbx_json_pos=$((_dbx_json_pos + 1))
        _dbx_json_avancar || { _dbx_json_falhar malformado 'arranjo sem fechamento'; return $?; }
        [[ ${_dbx_json_e[$_dbx_json_pos]} == ']' ]] &&
          { _dbx_json_falhar malformado 'virgula sobrando antes de ]'; return $?; }
        ;;
      ']')
        _dbx_json_pos=$((_dbx_json_pos + 1))
        DBX_JSON_TAMANHO[chave]=$indice
        return 0
        ;;
      *)
        { _dbx_json_falhar malformado "virgula ou ] esperados, encontrado '${_dbx_json_e[$_dbx_json_pos]}'"; return $?; }
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# API publica
# ---------------------------------------------------------------------------

# dbx_json_analisar <texto> — interpreta a resposta inteira.
dbx_json_analisar() {
  local texto=${1-} sem_quebras delimitador marcado separador=$'\x01'

  # shellcheck disable=SC2034  # DBX_JSON_ERRO e DBX_JSON_MOTIVO sao o canal de
  # diagnostico da falha, consumido pelo chamador e pela suite; o analisador nao
  # enxerga esse uso porque ele ocorre em outro arquivo.
  # Guarda de obsolescencia, avaliada POR CONTEXTO e nao afrouxada pelo recurso:
  # o contexto nomeado separa documentos, mas nao autoriza analisar em subshell
  # sobre estado que pertence a outro processo.
  local _dbx_ctx=$DBX_JSON_CONTEXTO
  if [[ ${DBX_JSON_ANALISADO_DO_CONTEXTO[$_dbx_ctx]:-0} -eq 1 &&
    -n ${DBX_JSON_PROCESSO_DO_CONTEXTO[$_dbx_ctx]:-} &&
    $BASHPID != "${DBX_JSON_PROCESSO_DO_CONTEXTO[$_dbx_ctx]}" ]]; then
    _dbx_json_falhar subshell 'analise em subshell sobre estado de outro processo: o resultado se perderia ao voltar e as consultas seguintes devolveriam o documento anterior'
    return "$DBX_JSON_ERRO_USO"
  fi

  # shellcheck disable=SC2034  # canal de diagnostico lido pelo chamador e pela
  # suite; o uso ocorre em outro arquivo e o analisador nao o enxerga.
  DBX_JSON_ERRO=''
  # shellcheck disable=SC2034
  DBX_JSON_MOTIVO=''
  DBX_JSON_ERRO_DO_CONTEXTO[$_dbx_ctx]=''
  DBX_JSON_MOTIVO_DO_CONTEXTO[$_dbx_ctx]=''
  DBX_JSON_RESULTADO=''
  DBX_JSON_ANALISADO=0
  DBX_JSON_ANALISADO_DO_CONTEXTO[$_dbx_ctx]=0
  # Libera os nos da analise anterior DESTE contexto. Sem isso, uma listagem
  # paginada acumularia os nos de todas as paginas ate o fim do processo.
  _dbx_json_liberar_contexto "$_dbx_ctx"

  [[ $# -ge 1 ]] || return "$DBX_JSON_ERRO_USO"
  [[ -n $texto ]] || { _dbx_json_falhar malformado 'entrada vazia'; return $?; }
  [[ ${#texto} -le $DBX_JSON_MAXIMO_ENTRADA ]] ||
    { _dbx_json_falhar tamanho "entrada acima de $DBX_JSON_MAXIMO_ENTRADA bytes"; return $?; }

  # Caractere de controle cru e invalido dentro de cadeia JSON e, alem disso,
  # colidiria com o separador usado na marcacao — mesma classe de defeito
  # corrigida em `dbx_errors_redigir` (R-01).
  sem_quebras=${texto//[$'\t\n\r']/}
  if [[ $sem_quebras == *[[:cntrl:]]* ]]; then
    _dbx_json_falhar controle 'caractere de controle cru na entrada'
    return $?
  fi

  marcado=$texto
  for delimitador in "${DBX_JSON_DELIMITADORES[@]}"; do
    marcado=${marcado//"$delimitador"/$separador$delimitador$separador}
  done
  _dbx_json_e=()
  IFS=$separador read -r -d '' -a _dbx_json_e < <(printf '%s' "$marcado") || true
  _dbx_json_total=${#_dbx_json_e[@]}
  _dbx_json_pos=0

  # Raiz propria do contexto, alocada no mesmo pool global de nos.
  local _dbx_raiz=$((++DBX_JSON_PROXIMO_ID))
  DBX_JSON_INICIO_DO_CONTEXTO[$_dbx_ctx]=$_dbx_raiz
  DBX_JSON_RAIZ_DO_CONTEXTO[$_dbx_ctx]=$_dbx_raiz
  DBX_JSON_TIPOS[_dbx_raiz]=''
  DBX_JSON_VALORES[_dbx_raiz]=''
  DBX_JSON_TAMANHO[_dbx_raiz]=0
  DBX_JSON_NFILHOS[_dbx_raiz]=0

  _dbx_json_ler_valor "$_dbx_raiz" 1
  local _dbx_status=$?

  # A faixa de nos e fechada aqui, em UM UNICO ponto, valendo para todos os
  # caminhos — sucesso, falha do analisador e lixo apos o fim do documento.
  #
  # Antes, o ramo de lixo retornava sem registrar o fim da faixa. Sem esse
  # registro, toda liberacao futura daquele contexto retorna cedo e o inicio e
  # sobrescrito, orfanando as faixas anteriores em definitivo: cinco analises de
  # um documento pequeno com lixo no fim deixavam 35 nos vivos, contra 7 na
  # reanalise valida. O vazamento e ilimitado em processo de vida longa, que e
  # exatamente o cenario de listagem paginada que motivou o contexto nomeado.
  DBX_JSON_FIM_DO_CONTEXTO[$_dbx_ctx]=$DBX_JSON_PROXIMO_ID

  [[ $_dbx_status -eq 0 ]] || return "$_dbx_status"

  if _dbx_json_avancar; then
    _dbx_json_falhar malformado "conteudo apos o fim do documento: '${_dbx_json_e[$_dbx_json_pos]}'"
    return $?
  fi
  DBX_JSON_ANALISADO=1
  DBX_JSON_ANALISADO_DO_CONTEXTO[$_dbx_ctx]=1
  # shellcheck disable=SC2034  # canal publico, lido pelo chamador e pela suite
  DBX_JSON_PROCESSO_ANALISE=$BASHPID
  DBX_JSON_PROCESSO_DO_CONTEXTO[$_dbx_ctx]=$BASHPID
  return 0
}

# _dbx_json_localizar <segmentos...> — percorre a arvore por comparacao de
# segmento, deixando o id em _dbx_json_no. Status 1 se o caminho nao existir.
_dbx_json_localizar() {
  local no=${DBX_JSON_RAIZ_DO_CONTEXTO[$DBX_JSON_CONTEXTO]:-} segmento filho
  [[ -n $no ]] || return 1
  for segmento in "$@"; do
    filho=${DBX_JSON_FILHO[$no$DBX_JSON_SEP_INDICE$segmento]:-}
    [[ -n $filho ]] || return 1
    no=$filho
  done
  _dbx_json_no=$no
}

# _dbx_json_pronto — ha documento corrente analisado com sucesso. A consulta em
# subshell e permitida: leitura nao deixa estado obsoleto para tras. O comentario
# anterior afirmava restricao de processo que o codigo nao aplica (E3-05).
_dbx_json_pronto() {
  [[ ${DBX_JSON_ANALISADO_DO_CONTEXTO[$DBX_JSON_CONTEXTO]:-0} -eq 1 ]]
}

# dbx_json_valor <segmentos...> — resultado exato em DBX_JSON_RESULTADO.
dbx_json_valor() {
  DBX_JSON_RESULTADO=''
  _dbx_json_pronto || return 1
  _dbx_json_localizar "$@" || return 1
  DBX_JSON_RESULTADO=${DBX_JSON_VALORES[_dbx_json_no]}
  printf '%s\n' "$DBX_JSON_RESULTADO"
}

# dbx_json_tipo <segmentos...>
dbx_json_tipo() {
  _dbx_json_pronto || return 1
  _dbx_json_localizar "$@" || return 1
  printf '%s\n' "${DBX_JSON_TIPOS[_dbx_json_no]}"
}

# dbx_json_existe <segmentos...>
dbx_json_existe() {
  _dbx_json_pronto || return 1
  _dbx_json_localizar "$@"
}

# dbx_json_tamanho_arranjo <segmentos...> — itens de arranjo ou chaves de objeto.
dbx_json_tamanho_arranjo() {
  _dbx_json_pronto || return 1
  _dbx_json_localizar "$@" || return 1
  printf '%s\n' "${DBX_JSON_TAMANHO[_dbx_json_no]}"
}

# dbx_json_chaves <segmentos...> — filhas diretas, uma por linha.
#
# Conveniencia para uso interativo. Nome contendo quebra de linha torna a
# enumeracao AMBIGUA: duas filhas podem sair como tres linhas. Para percurso
# programatico use `dbx_json_nome_da_filha`, que devolve o nome exato por
# variavel, ou `dbx_json_chaves_nul`, terminada por byte nulo.
dbx_json_chaves() {
  local indice total
  _dbx_json_pronto || return 1
  _dbx_json_localizar "$@" || return 1
  total=${DBX_JSON_NFILHOS[_dbx_json_no]}
  for ((indice = 0; indice < total; indice++)); do
    printf '%s\n' "${DBX_JSON_SEGMENTO[$_dbx_json_no$DBX_JSON_SEP_INDICE$indice]}"
  done
}

# dbx_json_nome_da_filha <indice> <segmentos...>
#
# Canal EXATO de enumeracao: devolve o nome da i-esima filha em
# DBX_JSON_RESULTADO, byte a byte. E o que permite percorrer chaves sem depender
# de delimitador nenhum — uma chave contendo quebra de linha fazia
# `dbx_json_chaves` emitir tres linhas para duas filhas, consulta correta mas
# enumeracao ambigua (E3-02). Combina com `dbx_json_tamanho_arranjo` para o
# total.
dbx_json_nome_da_filha() {
  local indice=${1-}
  DBX_JSON_RESULTADO=''
  [[ $indice =~ ^[0-9]+$ ]] || return "$DBX_JSON_ERRO_USO"
  shift
  _dbx_json_pronto || return 1
  _dbx_json_localizar "$@" || return 1
  [[ $indice -lt ${DBX_JSON_NFILHOS[_dbx_json_no]} ]] || return 1
  DBX_JSON_RESULTADO=${DBX_JSON_SEGMENTO[$_dbx_json_no$DBX_JSON_SEP_INDICE$indice]}
  printf '%s\n' "$DBX_JSON_RESULTADO"
}

# dbx_json_chaves_nul <segmentos...> — filhas diretas terminadas por byte nulo,
# no mesmo padrao de `find -print0` que `lib/output` adotou por DIV-16b. E a
# forma segura de encadear a enumeracao com outro processo quando o nome pode
# conter quebra de linha.
dbx_json_chaves_nul() {
  local indice total
  _dbx_json_pronto || return 1
  _dbx_json_localizar "$@" || return 1
  total=${DBX_JSON_NFILHOS[_dbx_json_no]}
  for ((indice = 0; indice < total; indice++)); do
    printf '%s\0' "${DBX_JSON_SEGMENTO[$_dbx_json_no$DBX_JSON_SEP_INDICE$indice]}"
  done
}

# ---------------------------------------------------------------------------
# Contexto nomeado
# ---------------------------------------------------------------------------

# _dbx_json_nome_de_contexto_valido <nome>
#
# O nome do contexto e escolhido pelo PROJETO e nunca vem de dado externo. A
# restricao e verificada em execucao, e nao deixada como convencao: se um nome
# pudesse vir de fora, a classe do E2-01 voltaria por outra porta.
_dbx_json_nome_de_contexto_valido() {
  local nome=${1-}
  [[ $nome =~ ^[a-z_]+$ ]]
}

# _dbx_json_liberar_contexto <nome> — devolve ao pool os nos da ultima analise
# do contexto. Os identificadores sao alocados em sequencia durante uma analise,
# entao os nos de um contexto formam uma faixa continua.
_dbx_json_liberar_contexto() {
  local nome=${1-} inicio fim id chave
  inicio=${DBX_JSON_INICIO_DO_CONTEXTO[$nome]:-}
  fim=${DBX_JSON_FIM_DO_CONTEXTO[$nome]:-}
  [[ -n $inicio && -n $fim ]] || return 0
  for ((id = inicio; id <= fim; id++)); do
    chave=${DBX_JSON_CHAVE_DO_NO[$id]:-}
    [[ -n $chave ]] && unset "DBX_JSON_FILHO[$chave]"
    unset "DBX_JSON_CHAVE_DO_NO[$id]"
    unset "DBX_JSON_TIPOS[$id]" "DBX_JSON_VALORES[$id]"
    unset "DBX_JSON_TAMANHO[$id]" "DBX_JSON_NFILHOS[$id]"
  done
  unset "DBX_JSON_INICIO_DO_CONTEXTO[$nome]" "DBX_JSON_FIM_DO_CONTEXTO[$nome]"
  unset "DBX_JSON_RAIZ_DO_CONTEXTO[$nome]"
}

# dbx_json_contexto <nome> — seleciona o contexto corrente.
#
# Devolve o nome anterior em DBX_JSON_CONTEXTO_ANTERIOR, para que o chamador
# possa restaurar. Uso previsto em lib/http:
#
#   dbx_json_contexto erro
#   dbx_json_analisar "$corpo_de_erro"
#   dbx_json_valor error_summary
#   dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
#
# A listagem em curso no contexto anterior permanece intacta.
dbx_json_contexto() {
  local nome=${1-}
  _dbx_json_nome_de_contexto_valido "$nome" || return "$DBX_JSON_ERRO_USO"
  # shellcheck disable=SC2034  # canal publico: e por ele que o chamador
  # restaura o contexto anterior apos interpretar um corpo de erro.
  DBX_JSON_CONTEXTO_ANTERIOR=$DBX_JSON_CONTEXTO
  DBX_JSON_CONTEXTO=$nome
  # Espelha o estado do contexto selecionado nas variaveis de diagnostico, para
  # que elas descrevam sempre o contexto corrente.
  # shellcheck disable=SC2034  # espelhos de diagnostico do contexto corrente
  DBX_JSON_ANALISADO=${DBX_JSON_ANALISADO_DO_CONTEXTO[$nome]:-0}
  # shellcheck disable=SC2034
  DBX_JSON_ERRO=${DBX_JSON_ERRO_DO_CONTEXTO[$nome]:-}
  # shellcheck disable=SC2034
  DBX_JSON_MOTIVO=${DBX_JSON_MOTIVO_DO_CONTEXTO[$nome]:-}
  DBX_JSON_RESULTADO=''
}

# dbx_json_descartar [nome] — libera o contexto indicado, ou o corrente.
dbx_json_descartar() {
  local nome=${1:-$DBX_JSON_CONTEXTO}
  _dbx_json_nome_de_contexto_valido "$nome" || return "$DBX_JSON_ERRO_USO"
  _dbx_json_liberar_contexto "$nome"
  DBX_JSON_ANALISADO_DO_CONTEXTO[$nome]=0
  unset "DBX_JSON_PROCESSO_DO_CONTEXTO[$nome]"
  [[ $nome == "$DBX_JSON_CONTEXTO" ]] && {
    # shellcheck disable=SC2034  # espelho de diagnostico do contexto corrente
    DBX_JSON_ANALISADO=0
    DBX_JSON_RESULTADO=''
  }
  return 0
}
