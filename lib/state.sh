#!/usr/bin/env bash
# lib/state.sh — cache unico de `content_hash` (RF-38, RF-42, RF-52, RF-61, RF-62).
#
# Camada: adaptadores. Depende de lib/errors.sh, lib/hash.sh (a
# definicao unica da identidade do arquivo) e de `dbx_config_caminho_de_estado`
# (lib/config.sh, carregada por quem chama).
#
# ESTE COMPONENTE NAO DECIDE NADA, e isso e a propriedade central, nao um detalhe
# de implementacao.
#
#   `DP-27b` rebaixou a linha de base a memoria de desempenho. Ela guarda
#   `content_hash` ja calculado para dispensar reler arquivo cuja identidade nao
#   mudou — e so. Perdida, corrompida ou obsoleta, o `sync` e o `upload` decidem
#   igual e apenas trabalham mais. No `upload`, quem decide dispensar o envio e
#   a comparacao com o `content_hash` REMOTO (RF-60); o cache so poupa o calculo
#   do lado local.
#
# DOIS NAMESPACES, NUNCA MISTURADOS (fase 3, `DP-34`)
#
#   `memoria-<resumo>`  memoria do `sync`, uma por tripla (conta, origem, destino).
#                       A EXISTENCIA dela responde a `RF-48` ("par ja visto").
#   `upload-<resumo>`   cache do `upload` de arquivo, um por caminho canonico da
#                       origem (RF-62), SEM conta (RF-52(b)): guarda so dado local.
#
#   O `upload` nunca cria nem le `memoria-*`: se criasse, um par de raizes nunca
#   sincronizado passaria por "ja visto" e o reconhecimento de `RF-48` seria
#   dispensado. O `lib/db` (SQLite) saiu nesta fase; este e o UNICO cache.
#
# IDENTIDADE FORTE (RF-38(e), RF-61(b) a (d))
#
#   Reaproveitar exige que a identidade inteira coincida (`mtime` e `ctime` com
#   nanossegundos, dispositivo, inode e tamanho; formato em `lib/hash`). Registrar
#   exige mais: `stat` antes e depois do calculo identicos e `mtime` com pelo
#   menos 2 s de idade — a regra anti-corrida do "racy git", porque um arquivo
#   reescrito no mesmo instante do registro pode manter a identidade.
#
# POR QUE A CORRUPCAO DESCARTA EM VEZ DE RECUSAR (`RF-42`, invertido por `DP-27b`)
#
#   Recusar um comando por causa de um cache transformaria artefato descartavel
#   em ponto unico de falha. Qualquer anomalia — versao desconhecida, registro
#   truncado, conta divergente, campo malformado — resulta em cache VAZIO e
#   execucao normal.
#
# DIRETORIO DE ESTADO (RNF-25(b), (b1), (c))
#
#   Criado em 0700. Existente e do usuario: corrigido para 0700 na gravacao.
#   De outro dono: nada e lido dele e nada e escrito nele; a gravacao devolve o
#   codigo da classe `permissao`. Um diretorio alheio poderia plantar resumos
#   com a identidade de um arquivo do usuario e fazer o `sync` omitir envio.
#
# FORMATO, e por que nao e JSON
#
#   Registros terminados em byte nulo, com o caminho por ultimo. `lib/json` monta
#   a arvore inteira em memoria, e uma raiz com dezenas de milhares de arquivos
#   pagaria isso a cada execucao para ler um cache que existe para economizar
#   trabalho. Nome de arquivo nao aceita nulo, entao o formato suporta qualquer
#   nome sem escape.
#
# O NOME DO ARQUIVO E DERIVADO POR RESUMO, e nao montado com os caminhos.
#
#   Raizes e origens vem do operador e conteriam barra, `..` e quebra de linha.
#   Compor nome de arquivo a partir delas seria derivar caminho de escrita de
#   origem externa. O resumo identifica sem carregar nada do texto original.

[[ -n ${DBX_STATE_CARREGADO:-} ]] && return 0
DBX_STATE_CARREGADO=1

_dbx_state_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_state_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_state_diretorio=.
_dbx_state_diretorio=$(cd -P -- "$_dbx_state_diretorio" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_state_diretorio/errors.sh"
# shellcheck source=lib/hash.sh
. "$_dbx_state_diretorio/hash.sh"
# shellcheck source=lib/tmp.sh
. "$_dbx_state_diretorio/tmp.sh"
unset _dbx_state_diretorio

DBX_STATE_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_STATE_ERRO_PERMISSAO=$(dbx_errors_codigo_saida permissao)
DBX_STATE_ERRO_CONFLITO=$(dbx_errors_codigo_saida conflito)
readonly DBX_STATE_ERRO_USO DBX_STATE_ERRO_PERMISSAO DBX_STATE_ERRO_CONFLITO

# Versao 2: identidade forte no lugar de tamanho e `mtime`. A memoria de versao
# 1 e descartada na carga (versao desconhecida), e o par continua "visto".
readonly DBX_STATE_VERSAO=2
# Idade minima do `mtime`, em segundos, para um registro ser gravado.
readonly DBX_STATE_ANTI_CORRIDA_S=2
# Poda do upload (RF-61(i)): acima do teto, sai o que nao e usado ha mais de N dias.
readonly DBX_STATE_TETO_UPLOAD=10000
readonly DBX_STATE_DIAS_SEM_USO=90
# Marca de caminho presente sem resumo reaproveitavel (ver `dbx_state_registrar`).
readonly DBX_STATE_SEM_RESUMO='-'

# shellcheck disable=SC2034  # canais publicos, consumidos pelos comandos e pela suite
DBX_STATE_RESULTADO=''
DBX_STATE_HASH=''
DBX_STATE_MOTIVO=''
DBX_STATE_VISTO='nao'
# QA-P3-01: a memoria EXISTIA e foi descartada na carga (versao anterior,
# truncada, cabecalho divergente). O par continua "visto" (RF-48), mas a linha
# de base sumiu e a guarda de RF-41(b) nao tem com o que comparar: quem consome
# desabilita a exclusao naquela execucao.
DBX_STATE_DESCARTADA='nao'

declare -gA DBX_STATE_ENTRADA=()
# Caminhos consultados ou registrados nesta execucao (RF-38(b)).
declare -gA DBX_STATE_VISITADA=()

_dbx_state_limpar() {
  DBX_STATE_ENTRADA=()
  DBX_STATE_VISITADA=()
  DBX_STATE_HASH=''
  return 0
}

# ---------------------------------------------------------------------------
# Diretorio de estado
# ---------------------------------------------------------------------------

# _dbx_state_base — diretorio de estado em DBX_STATE_RESULTADO.
_dbx_state_base() {
  DBX_STATE_RESULTADO=''
  dbx_config_caminho_de_estado || return $?
  DBX_STATE_RESULTADO=$DBX_CONFIG_RESULTADO
  return 0
}

# _dbx_state_diretorio_confiavel <dir> — 0 quando o diretorio existe e pertence
# ao usuario. `-O` segue ligacao simbolica: um `dbx` que aponta para diretorio
# alheio e tratado como alheio.
_dbx_state_diretorio_confiavel() {
  [[ -d $1 && -O $1 ]]
}

# _dbx_state_preparar_diretorio <dir> — garante o diretorio para gravacao.
#
# Inexistente: criado em 0700, independente do `umask` (o `-m` vale para o
# ultimo componente; os intermediarios sao do XDG, nao deste componente).
# Existente e do usuario: modo corrigido para 0700. Alheio: codigo de
# `permissao`, sem tocar em nada. Temporarios orfaos com mais de 1 dia saem.
_dbx_state_preparar_diretorio() {
  local diretorio=$1
  if [[ ! -e $diretorio && ! -L $diretorio ]]; then
    # shellcheck disable=SC2174  # deliberado: so o ultimo componente e deste modulo
    mkdir -p -m 700 -- "$diretorio" 2>/dev/null || return 1
  fi
  if ! _dbx_state_diretorio_confiavel "$diretorio"; then
    # shellcheck disable=SC2034  # canal publico
    DBX_STATE_MOTIVO='diretorio de estado pertence a outro usuario: memoria nao gravada'
    return "$DBX_STATE_ERRO_PERMISSAO"
  fi
  chmod -- 700 "$diretorio" 2>/dev/null || return 1
  # RNF-25(c): `-mtime +0` e "mais de 24 h". Os recentes podem ser gravacao
  # concorrente de outro processo e ficam.
  # RF-69(o): `.trava.*` entra na mesma regra; `trava-*` nunca e varrido.
  # RNF-25(c) emendado (fase 7a): `.retomada.*` tambem; (fase 7b) `.cursor.*`.
  find "$diretorio" -maxdepth 1 -type f \( -name '.memoria.*' -o -name '.upload.*' -o -name '.trava.*' \
    -o -name '.retomada.*' -o -name '.cursor.*' \) \
    -mtime +0 -exec rm -f -- {} + 2>/dev/null
  return 0
}

# _dbx_state_gravar_arquivo <arquivo> <prefixo_temporario> <funcao_de_conteudo>
#   [funcao_de_rodape]
#
# Gravacao atomica UNICA, para todos os namespaces (RNF-25(a)): temporario no
# MESMO diretorio, criado em 0600 e registrado por `lib/tmp`, e renomeacao.
# Falha em qualquer etapa preserva o arquivo anterior; sinal remove o
# temporario. Com <funcao_de_rodape> (fase 7b, `cursor-*`), ela recebe o
# caminho do temporario ja escrito e acrescenta o rodape de integridade antes
# do `mv`: o rodape cobre exatamente os bytes que serao publicados.
_dbx_state_gravar_arquivo() {
  local arquivo=$1 prefixo=$2 conteudo=$3 rodape=${4:-} temporario
  # Estado hostil: diretorio no lugar do registro. `mv` moveria o temporario
  # para dentro dele e devolveria sucesso.
  [[ -d $arquivo ]] && return 1
  dbx_tmp_arquivo "${arquivo%/*}/$prefixo.$$.XXXXXXXX" || return 1
  temporario=$DBX_TMP_CAMINHO
  "$conteudo" >"$temporario" 2>/dev/null || {
    dbx_tmp_remover "$temporario"
    return 1
  }
  if [[ -n $rodape ]] && ! "$rodape" "$temporario" 2>/dev/null; then
    dbx_tmp_remover "$temporario"
    return 1
  fi
  mv -f -- "$temporario" "$arquivo" 2>/dev/null || {
    dbx_tmp_remover "$temporario"
    return 1
  }
  dbx_tmp_esquecer "$temporario"
  return 0
}

# ---------------------------------------------------------------------------
# Identidade (formato e definicao em lib/hash)
# ---------------------------------------------------------------------------

# _dbx_state_identidade_valida <identidade> — seis campos, os numericos numericos.
_dbx_state_identidade_valida() {
  [[ $1 =~ ^[0-9]+\|[^|]+\|[^|]+\|[0-9]+\|[0-9]+\|[0-9]+$ ]]
}

# dbx_state_registravel <identidade_antes> <identidade_depois>
#
# 0 quando um resumo calculado entre as duas leituras pode ser registrado:
# leituras identicas e bem formadas (RF-61(c)), tamanho maior que zero (RF-61(e):
# arquivo vazio e fila nomeada ficam fora) e `mtime` com pelo menos 2 s de idade
# no relogio de agora (RF-61(d)).
dbx_state_registravel() {
  [[ $# -eq 2 ]] || return "$DBX_STATE_ERRO_USO"
  local antes=$1 depois=$2 agora mtime
  [[ -n $antes && $antes == "$depois" ]] || return 1
  _dbx_state_identidade_valida "$antes" || return 1
  [[ ${antes##*|} -gt 0 ]] || return 1
  printf -v agora '%(%s)T' -1
  mtime=${antes%%|*}
  [[ $((agora - mtime)) -ge $DBX_STATE_ANTI_CORRIDA_S ]] || return 1
  return 0
}

# ---------------------------------------------------------------------------
# Leitor NUL limitado (fase 7a, C3 do parecer do DBA)
# ---------------------------------------------------------------------------

# Teto de um registro de `upload-*` ou `retomada-*`: 16 KiB.
readonly DBX_STATE_LIMITE_REGISTRO=16384
_DBX_STATE_CAMPOS=()

# _dbx_state_ler_limitado <arquivo> <campos_maximos> — campos terminados em NUL
# em _DBX_STATE_CAMPOS. 0 lido; 1 recusado (ligacao simbolica, nao regular, de
# outro dono, acima de 16 KiB, ultimo campo sem terminador, campos demais); 2
# ausente.
#
# Um descritor so: o que e conferido (`-f`, `-O` pelo `/dev/fd`) e o que e
# lido sao o mesmo arquivo. Cada leitura pede no maximo o que falta para o teto
# mais um byte (`-n`, sob `LC_ALL=C`, onde caractere e byte): o leitor nunca
# guarda nem le alem do limite, qualquer que seja o tamanho do arquivo. Nada e
# executado nem ecoado; a validacao de cada campo e de quem chama.
_dbx_state_ler_limitado() {
  local arquivo=$1 maximo=$2 fd campo consumido=0 restante estado=0 LC_ALL=C
  _DBX_STATE_CAMPOS=()
  [[ -L $arquivo ]] && return 1
  [[ -e $arquivo ]] || return 2
  # QA-B7A-01 (ciclo 2): so arquivo regular e aberto. Abrir uma FIFO bloqueia
  # para sempre; a conferencia pelo descritor, abaixo, vem tarde demais.
  [[ -f $arquivo ]] || return 1  # nao regular
  { exec {fd}<"$arquivo"; } 2>/dev/null || return 1
  if [[ ! -f /dev/fd/$fd || ! -O /dev/fd/$fd ]]; then
    exec {fd}<&-
    return 1
  fi
  while :; do
    restante=$((DBX_STATE_LIMITE_REGISTRO + 1 - consumido))
    campo=''
    if IFS= read -r -d '' -n "$restante" campo <&"$fd"; then
      consumido=$((consumido + ${#campo} + 1))
      if [[ $consumido -gt $DBX_STATE_LIMITE_REGISTRO || ${#_DBX_STATE_CAMPOS[@]} -ge $maximo ]]; then
        estado=1
        break
      fi
      _DBX_STATE_CAMPOS+=("$campo")
    else
      # Fim do arquivo: um resto sem NUL e campo truncado.
      [[ -n $campo ]] && estado=1
      break
    fi
  done
  exec {fd}<&-
  [[ $estado -eq 0 ]] || _DBX_STATE_CAMPOS=()
  return "$estado"
}

# ---------------------------------------------------------------------------
# Namespace do sync: `memoria-*`
# ---------------------------------------------------------------------------

# dbx_state_caminho <conta> <origem> <destino> — arquivo da memoria, por resumo.
dbx_state_caminho() {
  [[ $# -eq 3 ]] || return "$DBX_STATE_ERRO_USO"
  local base resumo
  _dbx_state_base || return $?
  base=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  # A tripla inteira entra no resumo: `RF-52` exige que a identidade da conta
  # participe, e nao so o par de raizes. `dbx_hash_conteudo_fluxo` e usado aqui
  # apenas como funcao de resumo — nao ha nada de remoto nisto.
  resumo=$(printf '%s\n%s\n%s' "$1" "$2" "$3" | dbx_hash_conteudo_fluxo) || return $?
  DBX_STATE_RESULTADO="$base/memoria-${resumo:0:32}"
  return 0
}

# dbx_state_carregar <conta> <origem> <destino>
#
# NUNCA falha por causa do conteudo. Devolve zero com memoria vazia diante de
# qualquer anomalia, e publica o motivo para o relatorio.
dbx_state_carregar() {
  [[ $# -eq 3 ]] || return "$DBX_STATE_ERRO_USO"
  local conta=$1 origem=$2 destino=$3
  local arquivo registro resumo resto identidade

  _dbx_state_limpar
  DBX_STATE_MOTIVO=''
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_STATE_VISTO='nao'
  DBX_STATE_DESCARTADA='nao'

  dbx_state_caminho "$conta" "$origem" "$destino" || {
    DBX_STATE_MOTIVO='nao foi possivel determinar o caminho da memoria'
    return 0
  }
  arquivo=$DBX_STATE_RESULTADO
  # Diretorio alheio nao e lido nem prova execucao anterior.
  _dbx_state_diretorio_confiavel "${arquivo%/*}" || return 0
  [[ -e $arquivo || -L $arquivo ]] || return 0
  # Arquivo (ou alvo de ligacao) de outro dono nao e lido nem prova execucao
  # anterior: pode ter sido plantado.
  [[ -O $arquivo ]] || return 0
  # QA-P3-07: memoria do usuario que EXISTE e nao pode ser usada — ilegivel ou
  # que nao e arquivo regular — nao e memoria AUSENTE: o par ja foi visto e a
  # linha de base sumiu. Conta como descartada.
  if [[ ! -f $arquivo || ! -r $arquivo ]]; then
    # shellcheck disable=SC2034  # canais publicos, ver nota no topo
    DBX_STATE_VISTO='sim'
    DBX_STATE_DESCARTADA='sim'
    DBX_STATE_MOTIVO='memoria ilegivel: descartada'
    return 0
  fi

  # `VISTO` responde a pergunta de `RF-48` — este par de raizes ja foi
  # sincronizado antes? —, e ela e sobre a EXISTENCIA do arquivo, nao sobre o
  # conteudo dele. Memoria corrompida ainda prova execucao anterior.
  # shellcheck disable=SC2034  # canais publicos, ver nota no topo
  DBX_STATE_VISTO='sim'
  # Ate a carga chegar ao fim valida, a memoria conta como descartada: todo
  # ramo de descarte abaixo a deixa assim, e so o retorno final a limpa.
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_STATE_DESCARTADA='sim'

  local -a cabecalho=()
  local contados=0
  while IFS= read -r -d '' registro; do
    if [[ $contados -lt 4 ]]; then
      cabecalho+=("$registro")
      contados=$((contados + 1))
      continue
    fi
    # Resumo, identidade e o caminho, que leva TUDO o que sobra: ele pode conter
    # tabulacao e quebra de linha. Registro malformado e ignorado, e nao aborta
    # a carga: cache que nao acerta apenas trabalha mais.
    [[ $registro == *$'\t'*$'\t'* ]] || continue
    resumo=${registro%%$'\t'*}
    resto=${registro#*$'\t'}
    identidade=${resto%%$'\t'*}
    if [[ $resumo != "$DBX_STATE_SEM_RESUMO" || $identidade != "$DBX_STATE_SEM_RESUMO" ]]; then
      dbx_hash_formato_valido "$resumo" || continue
      _dbx_state_identidade_valida "$identidade" || continue
    fi
    DBX_STATE_ENTRADA["${resto#*$'\t'}"]="$resumo"$'\t'"$identidade"
  done <"$arquivo"

  if [[ ${#cabecalho[@]} -ne 4 ]]; then
    _dbx_state_limpar
    DBX_STATE_MOTIVO='memoria truncada: descartada'
    return 0
  fi
  if [[ ${cabecalho[0]} != "$DBX_STATE_VERSAO" ]]; then
    _dbx_state_limpar
    DBX_STATE_MOTIVO="versao de memoria desconhecida (${cabecalho[0]}): descartada"
    return 0
  fi
  # Verificacao redundante com o resumo do nome, e deliberadamente redundante:
  # `RF-52` e a unica regra do componente cuja violacao nao produz sintoma.
  if [[ ${cabecalho[1]} != "$conta" || ${cabecalho[2]} != "$origem" || ${cabecalho[3]} != "$destino" ]]; then
    _dbx_state_limpar
    # shellcheck disable=SC2034  # canais publicos, ver nota no topo
    DBX_STATE_MOTIVO='memoria de outra conta ou de outro par de raizes: descartada'
    return 0
  fi
  # shellcheck disable=SC2034  # canal publico, lido por commands/sync
  DBX_STATE_DESCARTADA='nao'
  return 0
}

# dbx_state_consultar <caminho> <identidade>
#
# Publica DBX_STATE_HASH e devolve zero quando o resumo guardado pode ser
# reaproveitado: a identidade guardada e a atual sao identicas. Toda consulta
# marca o caminho como visitado; entrada que nao casa sai do mapa, porque ja nao
# descreve o arquivo.
dbx_state_consultar() {
  [[ $# -eq 2 ]] || return "$DBX_STATE_ERRO_USO"
  local caminho=$1 identidade=$2 entrada
  DBX_STATE_HASH=''
  DBX_STATE_VISITADA["$caminho"]=1
  entrada=${DBX_STATE_ENTRADA[$caminho]:-}
  [[ -n $entrada ]] || return 1
  if [[ -z $identidade || ${entrada#*$'\t'} != "$identidade" ]]; then
    unset 'DBX_STATE_ENTRADA[$caminho]'
    return 1
  fi
  # shellcheck disable=SC2034  # canais publicos, ver nota no topo
  DBX_STATE_HASH=${entrada%%$'\t'*}
  return 0
}

# dbx_state_registrar <caminho> <resumo> <identidade_antes> <identidade_depois>
#
# Registra no mapa em memoria so o que `dbx_state_registravel` admite. Status 1
# quando nao registra — o que nao e erro: o resumo continua valido para esta
# execucao, so nao e guardado para a proxima.
#
# O caminho entra na memoria mesmo quando o resumo nao e admissivel, com a marca
# `-` no lugar do resumo e da identidade: nada e reaproveitado dele, mas a
# memoria continua registrando que o caminho existia. E isso que `RF-41(b)` le
# para recusar a origem que ficou vazia — sem a marca, uma arvore de arquivos
# recem-criados (todos dentro da janela anti-corrida) deixaria a memoria vazia
# e a recusa nunca dispararia.
dbx_state_registrar() {
  [[ $# -eq 4 ]] || return "$DBX_STATE_ERRO_USO"
  DBX_STATE_VISITADA["$1"]=1
  if dbx_hash_formato_valido "$2" && dbx_state_registravel "$3" "$4"; then
    DBX_STATE_ENTRADA["$1"]="$2"$'\t'"$3"
    return 0
  fi
  DBX_STATE_ENTRADA["$1"]="$DBX_STATE_SEM_RESUMO"$'\t'"$DBX_STATE_SEM_RESUMO"
  return 1
}

# Conteudo da memoria do sync, para `_dbx_state_gravar_arquivo`.
_DBX_STATE_CABECALHO=()
_DBX_STATE_SO_VISITADAS='nao'
_dbx_state_conteudo_memoria() {
  local caminho
  printf '%s\0' "$DBX_STATE_VERSAO" "${_DBX_STATE_CABECALHO[@]}"
  for caminho in "${!DBX_STATE_ENTRADA[@]}"; do
    if [[ $_DBX_STATE_SO_VISITADAS == 'sim' && -z ${DBX_STATE_VISITADA[$caminho]:-} ]]; then
      continue
    fi
    printf '%s\t%s\0' "${DBX_STATE_ENTRADA[$caminho]}" "$caminho"
  done
}

# dbx_state_gravar <conta> <origem> <destino> [travessia_completa]
#
# Com `sim` no quarto argumento (travessia completa), so as entradas visitadas
# nesta execucao sao gravadas: arquivo apagado na origem sai da memoria
# (RF-38(b)). Com travessia parcial, NADA e gravado (RF-38(b) emendado, RF-41(f)):
# quem chama nao deve invocar esta funcao nesse caso. O unico chamador passa
# sempre `sim`; o ramo sem `sim` (mapa carregado mais os novos) e legado, sem
# chamador, e nao e o contrato. Falha de gravacao NAO e falha da execucao;
# diretorio alheio devolve o codigo de `permissao` para quem quiser avisar.
dbx_state_gravar() {
  [[ $# -eq 3 || $# -eq 4 ]] || return "$DBX_STATE_ERRO_USO"
  local conta=$1 origem=$2 destino=$3 arquivo estado

  dbx_state_caminho "$conta" "$origem" "$destino" || return 1
  arquivo=$DBX_STATE_RESULTADO
  _dbx_state_preparar_diretorio "${arquivo%/*}"
  estado=$?
  [[ $estado -eq 0 ]] || return "$estado"

  _DBX_STATE_CABECALHO=("$conta" "$origem" "$destino")
  _DBX_STATE_SO_VISITADAS=${4:-nao}
  _dbx_state_gravar_arquivo "$arquivo" .memoria _dbx_state_conteudo_memoria
}

# ---------------------------------------------------------------------------
# Namespace do upload: `upload-*` (RF-61)
# ---------------------------------------------------------------------------

# dbx_state_upload_caminho <chave_canonica> — arquivo do cache, por resumo.
#
# A chave e o caminho fisico canonico da origem (RF-62(a)), resolvido por quem
# chama. Sem conta: o registro guarda so dado local (RF-52(b)).
dbx_state_upload_caminho() {
  [[ $# -eq 1 && -n $1 ]] || return "$DBX_STATE_ERRO_USO"
  local base resumo
  _dbx_state_base || return $?
  base=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  resumo=$(printf 'upload\n%s' "$1" | dbx_hash_conteudo_fluxo) || return $?
  DBX_STATE_RESULTADO="$base/upload-${resumo:0:32}"
  return 0
}

# dbx_state_upload_consultar <chave_canonica> <identidade>
#
# Publica DBX_STATE_HASH e devolve zero quando ha registro valido com a mesma
# identidade. Qualquer anomalia — arquivo ausente, alheio, versao, tipo ou chave
# divergentes, numero de campos, resumo ou identidade malformados — e status 1,
# nunca falha do comando (RF-42).
dbx_state_upload_consultar() {
  [[ $# -eq 2 ]] || return "$DBX_STATE_ERRO_USO"
  local chave=$1 identidade=$2 arquivo registro
  DBX_STATE_HASH=''
  dbx_state_upload_caminho "$chave" || return 1
  arquivo=$DBX_STATE_RESULTADO
  _dbx_state_diretorio_confiavel "${arquivo%/*}" || return 1
  [[ -f $arquivo && -r $arquivo && -O $arquivo ]] || return 1

  # C3 (fase 7a, emenda de RF-61): leitor LIMITADO. O laco antigo limitava o
  # numero de campos, nao o tamanho de um campo: 1 GB sem nulo ia inteiro para
  # a memoria. Acima de 16 KiB, sem terminador ou com campo a mais: ausente.
  _dbx_state_ler_limitado "$arquivo" 4 || return 1
  local -a campos=(${_DBX_STATE_CAMPOS[@]+"${_DBX_STATE_CAMPOS[@]}"})
  [[ ${#campos[@]} -eq 4 ]] || return 1
  [[ ${campos[0]} == "$DBX_STATE_VERSAO" && ${campos[1]} == 'upload' && ${campos[2]} == "$chave" ]] ||
    return 1
  registro=${campos[3]}
  [[ $registro == *$'\t'* ]] || return 1
  dbx_hash_formato_valido "${registro%%$'\t'*}" || return 1
  _dbx_state_identidade_valida "${registro#*$'\t'}" || return 1
  [[ -n $identidade && ${registro#*$'\t'} == "$identidade" ]] || return 1
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_STATE_HASH=${registro%%$'\t'*}
  return 0
}

# Conteudo do registro do upload, para `_dbx_state_gravar_arquivo`.
_DBX_STATE_REGISTRO_UPLOAD=()
_dbx_state_conteudo_upload() {
  printf '%s\0%s\0%s\0%s\t%s\0' "$DBX_STATE_VERSAO" upload "${_DBX_STATE_REGISTRO_UPLOAD[@]}"
}

# _dbx_state_podar_upload <diretorio> — RF-61(i). Conta os registros JA
# existentes (antes da gravacao corrente) sem processo externo; so acima do
# teto o diretorio e varrido para remover os nao usados ha mais de 90 dias.
_dbx_state_podar_upload() {
  local diretorio=$1
  local -a registros=()
  local tinha_nullglob='nao'
  shopt -q nullglob && tinha_nullglob='sim'
  shopt -s nullglob
  registros=("$diretorio"/upload-*)
  [[ $tinha_nullglob == 'sim' ]] || shopt -u nullglob
  [[ ${#registros[@]} -gt $DBX_STATE_TETO_UPLOAD ]] || return 0
  find "$diretorio" -maxdepth 1 -type f -name 'upload-*' \
    -mtime "+$DBX_STATE_DIAS_SEM_USO" -exec rm -f -- {} + 2>/dev/null
  return 0
}

# dbx_state_upload_gravar <chave_canonica> <resumo> <identidade_antes> <identidade_depois>
#
# Uma gravacao por `upload` (RF-61(g)): apos o envio bem-sucedido, ou apos a
# dispensa — inclusive quando o resumo veio do proprio cache, porque o acerto
# conta como uso e a regravacao renova o carimbo que a poda le. Status 1 quando
# o registro nao e admissivel ou a gravacao falha; codigo de `permissao` para
# diretorio alheio. Nenhum desses muda o resultado do `upload`.
dbx_state_upload_gravar() {
  [[ $# -eq 4 ]] || return "$DBX_STATE_ERRO_USO"
  local chave=$1 resumo=$2 arquivo estado
  dbx_hash_formato_valido "$resumo" || return 1
  dbx_state_registravel "$3" "$4" || return 1
  dbx_state_upload_caminho "$chave" || return 1
  arquivo=$DBX_STATE_RESULTADO
  _dbx_state_preparar_diretorio "${arquivo%/*}"
  estado=$?
  [[ $estado -eq 0 ]] || return "$estado"
  _dbx_state_podar_upload "${arquivo%/*}"

  _DBX_STATE_REGISTRO_UPLOAD=("$chave" "$resumo" "$3")
  _dbx_state_gravar_arquivo "$arquivo" .upload _dbx_state_conteudo_upload
}

# ---------------------------------------------------------------------------
# Trava de concorrencia: `trava-*` (RF-69; parecer do DBA de 2026-10-19)
# ---------------------------------------------------------------------------
#
# UM `sync` OU `verificar` POR VEZ PARA O MESMO PAR. Estado TRANSITORIO que nao
# decide nada (RNF-26 emendado): so impede a execucao concorrente. Quem cria e
# remove e este componente (DIV-41); `lib/tmp` so guarda a acao de liberar.
#
# CRIACAO EXCLUSIVA SEM CONTEUDO PARCIAL (RF-69(g)(j))
#
#   A linha inteira e gravada num temporario do MESMO diretorio e publicada por
#   `ln`, que falha se o nome existe: ninguem ve a trava vazia. O SUCESSO E O
#   INODE (`-ef`), nunca o codigo do `ln`: com um diretorio no nome o `ln` cria
#   o elo DENTRO dele e devolve zero, e em NFS a resposta perdida faz o `ln`
#   devolver erro tendo criado o elo. `noclobber` mostraria o arquivo vazio, e
#   `mkdir` nao e atomico no uutils.
#
# RETOMADA SERIALIZADA (RF-69(m))
#
#   Apagar a orfa e criar a nova tem corrida: dois retomadores leem a mesma
#   orfa, e o segundo apagaria a trava VIVA do primeiro. Por isso a retomada
#   passa por uma segunda trava exclusiva, `trava-<resumo>.r`: quem a obtem le
#   de novo, confirma a mesma orfa, apaga, cria a sua e solta a `.r`. A `.r` que
#   sobra de um processo morto nessa janela nunca e retomada sozinha.
#
# LEITURA HOSTIL (RF-69(k))
#
#   Nada do arquivo e executado nem ecoado: uma linha, no maximo 512 bytes, lida
#   por descritor, com cada campo validado. Qualquer falha e "ilegivel", e trava
#   ilegivel nunca e apagada nem retomada. Pid de 2 a 7 digitos sem zero a
#   esquerda: `kill -0 0` e `kill -0 -1` alcancam grupos de processos.
#
# MESMO HOST (RF-69(l))
#
#   Nome do host e namespace de pid iguais. Dois containers com o mesmo nome e o
#   estado compartilhado nao podem fazer o `kill -0` de um mentir sobre o outro.
#   `boot_id` diferente no mesmo host prova que houve reinicio: orfa. Relogio e
#   `mtime` nunca decidem.
#
# DIRETORIO DE ESTADO
#
#   Ausente, ele (e o que faltar acima dele) e criado em 0700 e REMOVIDO na
#   liberacao, por `rmdir`, se continuar vazio: o `verificar` e a simulacao
#   terminam com tudo como estava (RF-69(e)). Existente, o modo nao e tocado
#   aqui, pelo mesmo motivo; quem grava memoria o corrige (RNF-25(b1)).

readonly DBX_STATE_TRAVA_LIMITE=512
readonly DBX_STATE_TRAVA_SEM_CONTA='sem-conta'

# shellcheck disable=SC2034  # canais publicos, lidos pelos comandos e pela suite
DBX_STATE_HOST_ID=''
DBX_STATE_HOST_NOME=''
DBX_STATE_HOST_BOOT=''
DBX_STATE_HOST_NS=''
# Trava detida por este processo e aviso de orfa retomada.
DBX_STATE_TRAVA=''
DBX_STATE_AVISO=''
# Campos da ultima trava lida (so validados) e o estado apurado.
DBX_STATE_TRAVA_PID=''
DBX_STATE_TRAVA_HOST=''
DBX_STATE_TRAVA_INICIO=''
DBX_STATE_TRAVA_COMANDO=''
DBX_STATE_TRAVA_ESTADO=''
# Listagem para o `diagnostico` e o `unlink` (RF-71, RF-69(h2)).
DBX_STATE_TRAVAS_ARQUIVO=()
DBX_STATE_TRAVAS_ESTADO=()
DBX_STATE_TRAVAS_PID=()
DBX_STATE_TRAVAS_HOST=()
DBX_STATE_TRAVAS_INICIO=()
DBX_STATE_TRAVAS_COMANDO=()

_dbx_state_trava_inicio=''
_dbx_state_trava_acao=''
_dbx_state_trava_criados=()
# Fase 7a (RF-105): `par` (sync, verificar) ou `registro` (retomada). Um
# processo pode deter uma de cada; so a de par e unica por processo.
_dbx_state_trava_modo='par'
DBX_STATE_TRAVA_REGISTRO=''
# Textos da recusa: o par (padrao) ou a raiz local (fase 8, RF-132).
_dbx_state_t_deste='deste par'
_dbx_state_t_neste='neste par'
_dbx_state_t_este='este par'
_dbx_state_trava_registro_inicio=''
_dbx_state_trava_registro_acao=''

# dbx_state_host_id — identidade do host, uma vez por processo: nome (do shell,
# com recuo para o kernel), `boot_id` e inode do namespace de pid, cada um
# quando existir (`x` quando nao). Nenhum utilitario fora do preflight.
dbx_state_host_id() {
  [[ -n $DBX_STATE_HOST_ID ]] && return 0
  local nome=${HOSTNAME:-} boot='' ns=''
  if [[ -z $nome && -r /proc/sys/kernel/hostname ]]; then
    IFS= read -r nome </proc/sys/kernel/hostname || :
  fi
  nome=${nome//[!A-Za-z0-9._-]/_}
  nome=${nome:0:64}
  [[ -n $nome ]] || nome=x
  if [[ -r /proc/sys/kernel/random/boot_id ]]; then
    IFS= read -r boot </proc/sys/kernel/random/boot_id || :
  fi
  [[ $boot =~ ^[A-Za-z0-9-]{1,64}$ ]] || boot=x
  [[ -e /proc/self/ns/pid ]] && dbx_atributo -L ino /proc/self/ns/pid && ns=$DBX_ATRIBUTO
  [[ $ns =~ ^[0-9]{1,20}$ ]] || ns=x
  DBX_STATE_HOST_NOME=$nome
  DBX_STATE_HOST_BOOT=$boot
  DBX_STATE_HOST_NS=$ns
  DBX_STATE_HOST_ID="$nome:$boot:$ns"
}

# _dbx_state_minusculas_ascii <texto> — so A-Z viram a-z; o resto fica byte a
# byte. Em DBX_STATE_RESULTADO, sem captura.
_dbx_state_minusculas_ascii() {
  local LC_ALL=C
  DBX_STATE_RESULTADO=${1,,}
}

# dbx_state_trava_caminho <identidade> <raiz_local_canonica> <raiz_remota>
#
# Chave do par SEM ORDEM entre os sentidos (DIV-38): entra a raiz local e a
# remota, nunca a origem e o destino; a remota sem caixa. Identidade vazia vira
# o marcador `sem-conta` (DIV-40). Nome por resumo, sem dado externo cru.
dbx_state_trava_caminho() {
  [[ $# -eq 3 ]] || return "$DBX_STATE_ERRO_USO"
  local base resumo remoto
  _dbx_state_base || return $?
  base=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  # Dobra de caixa SO no ASCII, sob `C` (QA-B2-03, como RNF-20(b4) na fase 1b):
  # a mesma grafia gera a mesma chave no agendador (`C`) e no terminal
  # (`C.UTF-8`); `${x,,}` na localidade do usuario dobraria `Ç` so numa delas.
  _dbx_state_minusculas_ascii "$3"
  remoto=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  resumo=$(printf 'trava\n%s\n%s\n%s' "${1:-$DBX_STATE_TRAVA_SEM_CONTA}" "$2" "$remoto" |
    dbx_hash_conteudo_fluxo) || return $?
  DBX_STATE_RESULTADO="$base/trava-${resumo:0:32}"
  return 0
}

# dbx_state_trava_ler <arquivo> — 0 legivel (campos em DBX_STATE_TRAVA_*),
# 1 ilegivel, 2 ausente.
dbx_state_trava_ler() { _dbx_state_trava_ler "$1"; }

_dbx_state_trava_ler() {
  local arquivo=$1 linha='' resto fd estado=1 LC_ALL=C
  local -a campos=()
  DBX_STATE_TRAVA_PID='' DBX_STATE_TRAVA_HOST='' DBX_STATE_TRAVA_INICIO='' DBX_STATE_TRAVA_COMANDO=''
  [[ -L $arquivo ]] && return 1
  [[ -e $arquivo ]] || return 2
  # QA-B7A-01 (ciclo 2): FIFO ou outro nao regular no lugar da trava e
  # ilegivel, como o diretorio ja era; abri-lo poderia bloquear.
  [[ -f $arquivo ]] || return 1
  # Um descritor so: o que e conferido e o que e lido sao o mesmo arquivo,
  # ainda que o nome seja trocado ou apagado no meio. Sem utilitario externo:
  # o `diagnostico` le a trava so com o shell (RF-66(e)).
  # A redirecao do erro fica no GRUPO: em `exec` puro ela valeria para o resto
  # do processo e calaria todo diagnostico dali em diante.
  { exec {fd}<"$arquivo"; } 2>/dev/null || {
    [[ -e $arquivo || -L $arquivo ]] && return 1
    return 2
  }
  if [[ -f /dev/fd/$fd && -O /dev/fd/$fd ]]; then
    # A leitura tem de chegar ao FIM DO ARQUIVO (status diferente de zero) em
    # ate 513 bytes: se ela para antes, achou um nulo (o delimitador) ou o
    # limite, e ha bytes que a linha nao contem (QA-B2-01). Depois disso, a
    # linha termina no unico `\n`: qualquer byte apos ele torna a trava ilegivel.
    IFS= read -r -d '' -n "$((DBX_STATE_TRAVA_LIMITE + 1))" linha <&"$fd" || estado=0
  fi
  exec {fd}<&-
  [[ $estado -eq 0 && ${#linha} -le $DBX_STATE_TRAVA_LIMITE && $linha == *$'\n' ]] || return 1
  linha=${linha%$'\n'}
  [[ $linha == *$'\n'* ]] && return 1
  resto=$linha
  while [[ $resto == *$'\t'* ]]; do
    campos+=("${resto%%$'\t'*}")
    resto=${resto#*$'\t'}
  done
  campos+=("$resto")
  [[ ${#campos[@]} -eq 7 && ${campos[0]} == 'dbx-trava' && ${campos[1]} == '1' && ${campos[6]} == 'fim' ]] ||
    return 1
  [[ ${campos[2]} =~ ^[1-9][0-9]{1,6}$ ]] || return 1
  [[ ${campos[3]} =~ ^[A-Za-z0-9._:-]{1,255}$ ]] || return 1
  [[ ${campos[4]} =~ ^[0-9]{1,19}$ ]] || return 1
  # RF-105(a) (fase 7a): `retomada` e a trava de registro de upload/download.
  [[ ${campos[5]} == 'sync' || ${campos[5]} == 'verificar' || ${campos[5]} == 'retomada' ]] || return 1
  DBX_STATE_TRAVA_PID=${campos[2]}
  DBX_STATE_TRAVA_HOST=${campos[3]}
  DBX_STATE_TRAVA_INICIO=${campos[4]}
  DBX_STATE_TRAVA_COMANDO=${campos[5]}
  return 0
}

# _dbx_state_trava_classificar — estado da trava lida: viva, orfa, outro-host.
# Permissao negada no `kill -0` conta como viva (o processo existe).
_dbx_state_trava_classificar() {
  local host=$DBX_STATE_TRAVA_HOST nome resto boot ns
  dbx_state_host_id
  DBX_STATE_TRAVA_ESTADO='outro-host'
  [[ $host == *:*:* ]] || return 0
  nome=${host%%:*}
  resto=${host#*:}
  boot=${resto%%:*}
  ns=${resto#*:}
  [[ $ns == *:* || $nome != "$DBX_STATE_HOST_NOME" || $ns != "$DBX_STATE_HOST_NS" ]] && return 0
  if [[ $boot != "$DBX_STATE_HOST_BOOT" ]]; then
    DBX_STATE_TRAVA_ESTADO='orfa'
  elif kill -0 "$DBX_STATE_TRAVA_PID" 2>/dev/null || [[ -e /proc/$DBX_STATE_TRAVA_PID ]]; then
    DBX_STATE_TRAVA_ESTADO='viva'
  else
    DBX_STATE_TRAVA_ESTADO='orfa'
  fi
  return 0
}

# _dbx_state_trava_quem — "o <comando> pid <pid> no host <nome>, iniciado em
# <ISO UTC>", so com campos validados, em DBX_STATE_RESULTADO.
_dbx_state_trava_quem() {
  # Exportada: o `printf` do shell so honra o fuso que esta no ambiente.
  local -x TZ=UTC
  local iso
  printf -v iso '%(%Y-%m-%dT%H:%M:%SZ)T' "$DBX_STATE_TRAVA_INICIO"
  DBX_STATE_RESULTADO="o $DBX_STATE_TRAVA_COMANDO pid $DBX_STATE_TRAVA_PID no host ${DBX_STATE_TRAVA_HOST%%:*}, iniciado em $iso"
}

# _dbx_state_trava_publicar <destino> <comando> — receita de RF-69(j). 0
# publicada, 1 sem temporario, 2 nome ocupado (ou `ln` sem elo).
_dbx_state_trava_publicar() {
  local destino=$1 temporario resultado=2
  dbx_tmp_arquivo "${destino%/*}/.trava.$$.${DBX_STATE_HOST_ID//:/.}.XXXXXXXX" || return 1
  temporario=$DBX_TMP_CAMINHO
  if ! printf 'dbx-trava\t1\t%s\t%s\t%s\t%s\tfim\n' "$$" "$DBX_STATE_HOST_ID" \
    "$_dbx_state_trava_inicio" "$2" >"$temporario" 2>/dev/null; then
    dbx_tmp_remover "$temporario"
    return 1
  fi
  ln -- "$temporario" "$destino" 2>/dev/null
  if [[ $temporario -ef $destino ]]; then
    resultado=0
  elif [[ -d $destino && ! -L $destino && ${destino}/${temporario##*/} -ef $temporario ]]; then
    # Diretorio surgido no nome entre a checagem e o `ln`: o elo foi parar
    # dentro dele, e e nosso.
    rm -f -- "${destino}/${temporario##*/}"
  fi
  dbx_tmp_remover "$temporario"
  return "$resultado"
}

# _dbx_state_trava_ocupada <arquivo> <resultado_da_leitura> — monta a recusa.
_dbx_state_trava_ocupada() {
  local arquivo=$1
  if [[ $2 -ne 0 ]]; then
    DBX_STATE_MOTIVO="trava ilegivel: $arquivo nunca e retomada nem apagada automaticamente; confirme que nenhum sync ou verificar $_dbx_state_t_deste esta em curso e remova-a com: rm $arquivo"
  elif [[ $DBX_STATE_TRAVA_ESTADO == 'outro-host' ]]; then
    _dbx_state_trava_quem
    DBX_STATE_MOTIVO="trava de outro host: $DBX_STATE_RESULTADO, detem $_dbx_state_t_este e nunca e retomada automaticamente; confirme que essa execucao terminou e remova a trava com: rm $arquivo"
  else
    _dbx_state_trava_quem
    DBX_STATE_MOTIVO="trava ocupada: $DBX_STATE_RESULTADO, esta trabalhando $_dbx_state_t_neste; rode de novo depois ou use --esperar N (--wait N) para aguardar ate N segundos"
  fi
  DBX_STATE_RESULTADO=''
  return "$DBX_STATE_ERRO_CONFLITO"
}

# _dbx_state_trava_tentar <arquivo> <comando> — uma sondagem, em secao critica
# de `lib/tmp`: entre a publicacao e o registro da liberacao nenhum sinal
# encerra o processo. 0 adquirida, conflito, 1 falha local, 3 tentar de novo.
_dbx_state_trava_tentar() {
  local estado
  dbx_tmp_critico_inicio
  _dbx_state_trava_sondar "$@"
  estado=$?
  dbx_tmp_critico_fim
  return "$estado"
}

_dbx_state_trava_sondar() {
  local arquivo=$1 comando=$2 leitura
  if [[ -L $arquivo || -d $arquivo ]]; then
    _dbx_state_trava_ocupada "$arquivo" 1
    return $?
  fi
  _dbx_state_trava_publicar "$arquivo" "$comando"
  case $? in
    0)
      _dbx_state_trava_detida "$arquivo"
      return 0
      ;;
    1)
      _dbx_state_trava_sem_escrita "$arquivo"
      return $?
      ;;
  esac
  _dbx_state_trava_ler "$arquivo"
  leitura=$?
  [[ $leitura -eq 2 ]] && return 3
  [[ $leitura -eq 0 ]] && _dbx_state_trava_classificar
  if [[ $leitura -eq 0 && $DBX_STATE_TRAVA_ESTADO == 'orfa' ]]; then
    _dbx_state_trava_retomar "$arquivo" "$comando"
    return $?
  fi
  _dbx_state_trava_ocupada "$arquivo" "$leitura"
}

# _dbx_state_trava_sem_escrita <arquivo> — nao deu para criar o temporario
# (DIV-50): a trava que JA existe ainda decide. Viva, de outro host ou
# ilegivel: conflito, como em qualquer diretorio. Ausente ou orfa (que ninguem
# consegue retomar ali): permissao, e o comando segue sem trava, com aviso.
_dbx_state_trava_sem_escrita() {
  local arquivo=$1 leitura
  _dbx_state_trava_ler "$arquivo"
  leitura=$?
  [[ $leitura -eq 0 ]] && _dbx_state_trava_classificar
  if [[ $leitura -eq 1 || ($leitura -eq 0 && $DBX_STATE_TRAVA_ESTADO != 'orfa') ]]; then
    _dbx_state_trava_ocupada "$arquivo" "$leitura"
    return $?
  fi
  DBX_STATE_MOTIVO="diretorio de estado sem escrita: ${arquivo%/*}"
  return "$DBX_STATE_ERRO_PERMISSAO"
}

# _dbx_state_trava_detida <arquivo> — a trava e deste processo: a liberacao
# entra no registro de `lib/tmp` (RNF-35(h)).
_dbx_state_trava_detida() {
  if [[ $_dbx_state_trava_modo == 'raiz' ]]; then
    DBX_STATE_TRAVA_RAIZ=$1
    _dbx_state_trava_raiz_inicio=$_dbx_state_trava_inicio
    dbx_tmp_acao_registrar _dbx_state_trava_raiz_soltar "$1"
    _dbx_state_trava_raiz_acao=$DBX_TMP_ID
    return 0
  fi
  if [[ $_dbx_state_trava_modo == 'registro' ]]; then
    DBX_STATE_TRAVA_REGISTRO=$1
    _dbx_state_trava_registro_inicio=$_dbx_state_trava_inicio
    dbx_tmp_acao_registrar _dbx_state_trava_registro_soltar "$1"
    _dbx_state_trava_registro_acao=$DBX_TMP_ID
    return 0
  fi
  DBX_STATE_TRAVA=$1
  dbx_tmp_acao_registrar _dbx_state_trava_soltar "$1"
  _dbx_state_trava_acao=$DBX_TMP_ID
}

# _dbx_state_trava_retomar <arquivo> <comando> — RF-69(m), com a orfa ja lida.
_dbx_state_trava_retomar() {
  local arquivo=$1 comando=$2 r="$1.r" leitura
  local pid=$DBX_STATE_TRAVA_PID host=$DBX_STATE_TRAVA_HOST inicio=$DBX_STATE_TRAVA_INICIO
  local boot_atual
  _dbx_state_trava_quem
  local quem=$DBX_STATE_RESULTADO
  dbx_state_host_id
  boot_atual=$DBX_STATE_HOST_BOOT

  if [[ -L $r || -d $r ]]; then
    DBX_STATE_MOTIVO="retomada de trava interrompida: $r nunca e retomada automaticamente; confirme que nenhum sync ou verificar deste par esta em curso e remova-a com: rm $r"
    return "$DBX_STATE_ERRO_CONFLITO"
  fi
  _dbx_state_trava_publicar "$r" "$comando"
  case $? in
    1)
      DBX_STATE_MOTIVO="diretorio de estado sem escrita: ${arquivo%/*}"
      return "$DBX_STATE_ERRO_PERMISSAO"
      ;;
    2)
      _dbx_state_trava_ler "$r"
      leitura=$?
      [[ $leitura -eq 2 ]] && return 3
      [[ $leitura -eq 0 ]] && _dbx_state_trava_classificar
      if [[ $leitura -eq 0 && $DBX_STATE_TRAVA_ESTADO == 'viva' ]]; then
        _dbx_state_trava_quem
        DBX_STATE_MOTIVO="trava ocupada: $DBX_STATE_RESULTADO, esta retomando a trava deste par; rode de novo depois ou use --esperar N (--wait N) para aguardar ate N segundos"
      else
        DBX_STATE_MOTIVO="retomada de trava interrompida: $r nunca e retomada automaticamente; confirme que nenhum sync ou verificar deste par esta em curso e remova-a com: rm $r"
      fi
      DBX_STATE_RESULTADO=''
      return "$DBX_STATE_ERRO_CONFLITO"
      ;;
  esac

  # Com a `.r`: a orfa precisa ser a MESMA da primeira leitura.
  _dbx_state_trava_ler "$arquivo"
  leitura=$?
  if [[ $leitura -ne 0 || $DBX_STATE_TRAVA_PID != "$pid" || $DBX_STATE_TRAVA_HOST != "$host" ||
    $DBX_STATE_TRAVA_INICIO != "$inicio" ]]; then
    rm -f -- "$r"
    return 3
  fi
  # Receita de RF-69(m): apaga a orfa e cria a nova por (j). Entre o `rm` e o
  # `ln` o nome fica livre, e uma aquisicao comum pode entrar; a exclusao vale
  # (um so detem a trava). DIV-53: por isso o aviso e de quem APAGOU a orfa,
  # dado aqui, antes do `ln`, e mantido ainda que este processo perca o `ln` e
  # saia com conflito: um aviso por orfa removida, que nao afirma quem ficou
  # com a trava.
  rm -f -- "$arquivo"
  if [[ ${host#*:} != "$boot_atual:"* ]]; then
    DBX_STATE_AVISO="trava orfa de pid $pid removida ($quem; nao terminou neste boot do host, houve reinicio)"
  else
    DBX_STATE_AVISO="trava orfa de pid $pid removida ($quem; terminou sem libera-la)"
  fi
  _dbx_state_trava_publicar "$arquivo" "$comando"
  leitura=$?
  rm -f -- "$r"
  case $leitura in
    0) ;;
    1)
      DBX_STATE_MOTIVO="diretorio de estado sem escrita: ${arquivo%/*}"
      return "$DBX_STATE_ERRO_PERMISSAO"
      ;;
    *) return 3 ;;
  esac
  _dbx_state_trava_detida "$arquivo"
  return 0
}

# _dbx_state_trava_soltar <arquivo> — acao de liberacao: apaga SO a propria
# (pid, host e inicio gravados) e remove o diretorio que a aquisicao criou, se
# ficou vazio.
_dbx_state_trava_soltar() {
  local arquivo=$1
  if _dbx_state_trava_ler "$arquivo" && [[ $DBX_STATE_TRAVA_PID == "$$" &&
    $DBX_STATE_TRAVA_HOST == "$DBX_STATE_HOST_ID" && $DBX_STATE_TRAVA_INICIO == "$_dbx_state_trava_inicio" ]]; then
    rm -f -- "$arquivo"
  fi
  [[ $DBX_STATE_TRAVA == "$arquivo" ]] && DBX_STATE_TRAVA=''
  _dbx_state_trava_desfazer_diretorio
  return 0
}

_dbx_state_trava_desfazer_diretorio() {
  local indice
  for ((indice = ${#_dbx_state_trava_criados[@]} - 1; indice >= 0; indice--)); do
    rmdir -- "${_dbx_state_trava_criados[indice]}" 2>/dev/null || break
  done
  _dbx_state_trava_criados=()
}

# _dbx_state_trava_diretorio <dir> — garante o diretorio, guardando o que criou.
_dbx_state_trava_diretorio() {
  local diretorio=$1 acima=$1
  local -a faltam=()
  _dbx_state_trava_criados=()
  while [[ -n $acima && ! -e $acima && ! -L $acima ]]; do
    faltam=("$acima" "${faltam[@]}")
    acima=${acima%/*}
  done
  if [[ ${#faltam[@]} -gt 0 ]]; then
    # shellcheck disable=SC2174  # deliberado: cada componente criado aqui nasce 0700
    mkdir -p -m 700 -- "$diretorio" 2>/dev/null || {
      DBX_STATE_MOTIVO="diretorio de estado sem escrita: $diretorio"
      return "$DBX_STATE_ERRO_PERMISSAO"
    }
    _dbx_state_trava_criados=("${faltam[@]}")
  fi
  if ! _dbx_state_diretorio_confiavel "$diretorio"; then
    DBX_STATE_MOTIVO='diretorio de estado pertence a outro usuario'
    return "$DBX_STATE_ERRO_PERMISSAO"
  fi
  return 0
}

# dbx_state_trava_adquirir <identidade> <raiz_local_canonica> <raiz_remota>
#   <comando> <espera_s>
#
#   0          adquirida (DBX_STATE_TRAVA; DBX_STATE_AVISO se retomou orfa)
#   conflito   ocupada, de outro host, ilegivel, `.r` presa ou nome instavel
#              (DBX_STATE_MOTIVO)
#   permissao  diretorio de estado alheio ou sem escrita (DIV-48/DIV-50: quem
#              chama segue sem trava, com aviso)
#   outro      uso invalido ou falha local, com o proprio codigo
#
# Com espera, sonda a cada 1 s (`sleep`, sem rede e sem memoria) ate N
# sondagens. Uma trava por processo.
dbx_state_trava_adquirir() {
  [[ $# -eq 5 && ($4 == 'sync' || $4 == 'verificar') && $5 =~ ^[0-9]{1,4}$ ]] ||
    return "$DBX_STATE_ERRO_USO"
  [[ -z $DBX_STATE_TRAVA ]] || return "$DBX_STATE_ERRO_USO"
  local comando=$4 espera=$((10#$5)) arquivo estado sondagens=0 repeticoes=0
  DBX_STATE_MOTIVO=''
  # shellcheck disable=SC2034  # canal publico, lido por lib/cmd
  DBX_STATE_AVISO=''
  dbx_state_trava_caminho "$1" "$2" "$3" || {
    DBX_STATE_MOTIVO='nao foi possivel determinar o diretorio de estado'
    return 1
  }
  arquivo=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  _dbx_state_trava_diretorio "${arquivo%/*}" || return $?
  dbx_state_host_id
  printf -v _dbx_state_trava_inicio '%(%s)T' -1

  while :; do
    _dbx_state_trava_tentar "$arquivo" "$comando"
    estado=$?
    [[ $estado -eq 0 ]] && return 0
    if [[ $estado -eq 3 ]]; then
      # O nome sumiu ou a orfa mudou entre as leituras: de novo, na hora.
      repeticoes=$((repeticoes + 1))
      [[ $repeticoes -lt 50 ]] && continue
      # DIV-50: esgotado, recusa como ocupada; nunca segue sem trava.
      DBX_STATE_MOTIVO="trava instavel: o nome mudou a cada tentativa de obte-la; rode de novo depois ou use --esperar N (--wait N)"
      estado=$DBX_STATE_ERRO_CONFLITO
    fi
    if [[ $estado -ne $DBX_STATE_ERRO_CONFLITO || $sondagens -ge $espera ]]; then
      [[ $estado -eq $DBX_STATE_ERRO_CONFLITO && $espera -gt 0 ]] &&
        DBX_STATE_MOTIVO="esperou $espera s; $DBX_STATE_MOTIVO"
      _dbx_state_trava_desfazer_diretorio
      return "$estado"
    fi
    sleep 1
    sondagens=$((sondagens + 1))
    repeticoes=0
  done
}

# dbx_state_trava_liberar — libera agora a trava deste processo (idempotente).
dbx_state_trava_liberar() {
  [[ -n $DBX_STATE_TRAVA ]] || return 0
  dbx_tmp_acao_cancelar "$_dbx_state_trava_acao"
  _dbx_state_trava_acao=''
  _dbx_state_trava_soltar "$DBX_STATE_TRAVA"
}

# ---------------------------------------------------------------------------
# Trava por raiz local canonica (fase 8, RF-132, DIV-250; risco R1 do DBA)
# ---------------------------------------------------------------------------
#
# A trava do par inclui a identidade da credencial; duas credenciais diferentes
# tem travas do par diferentes, e dois `sync --receber` rodariam juntos sobre a
# MESMA arvore local. Esta trava e chaveada pela identidade FISICA da raiz
# (`dev:inode`, nunca pela grafia: `..`, ligacao simbolica, barra final e ponto
# de montagem alternativo resolvem a mesma), sem credencial, conta nem perfil na
# chave nem no conteudo. Mesmo registro, mesma aquisicao atomica, mesma orfa,
# mesmos sinais; o nome comeca por `trava-` para `unlink` e `diagnostico` a
# tratarem como as demais (nenhum formato novo, C9 do DBA).

DBX_STATE_TRAVA_RAIZ=''
_dbx_state_trava_raiz_inicio=''
_dbx_state_trava_raiz_acao=''
_dbx_state_trava_raiz_criados=()

# dbx_state_trava_raiz_caminho <raiz_local_canonica> — arquivo da trava em
# DBX_STATE_RESULTADO. Falha (1) quando a raiz nao existe ou nao e identificavel.
dbx_state_trava_raiz_caminho() {
  [[ $# -eq 1 ]] || return "$DBX_STATE_ERRO_USO"
  local base devino resumo
  _dbx_state_base || return $?
  base=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  dbx_atributo -L dev_ino "$1" || return 1; devino=${DBX_ATRIBUTO/|/:}
  [[ $devino =~ ^[0-9]+:[0-9]+$ ]] || return 1
  resumo=$(printf 'trava-raiz\n%s' "$devino" | dbx_hash_conteudo_fluxo) || return $?
  DBX_STATE_RESULTADO="$base/trava-${resumo:0:32}"
  return 0
}

# _dbx_state_trava_raiz_garantir_diretorio <diretorio> — cria o que faltar do
# diretorio de estado (0700), anota o criado em `_criados` e confere o dono.
_dbx_state_trava_raiz_garantir_diretorio() {
  local diretorio=$1 acima
  local -a faltam=()
  acima=$diretorio
  while [[ -n $acima && ! -e $acima && ! -L $acima ]]; do
    faltam=("$acima" ${faltam[@]+"${faltam[@]}"})
    acima=${acima%/*}
  done
  if [[ ${#faltam[@]} -gt 0 ]]; then
    # shellcheck disable=SC2174  # deliberado: cada componente criado aqui nasce 0700
    mkdir -p -m 700 -- "$diretorio" 2>/dev/null || {
      DBX_STATE_MOTIVO="diretorio de estado sem escrita: $diretorio"
      return "$DBX_STATE_ERRO_PERMISSAO"
    }
    _dbx_state_trava_raiz_criados+=("${faltam[@]}")
  fi
  if ! _dbx_state_diretorio_confiavel "$diretorio"; then
    DBX_STATE_MOTIVO='diretorio de estado pertence a outro usuario'
    _dbx_state_trava_raiz_desfazer_diretorio
    return "$DBX_STATE_ERRO_PERMISSAO"
  fi
  return 0
}

# dbx_state_trava_raiz_adquirir <raiz_local_canonica> <espera_s>
#
# Mesmos codigos de `dbx_state_trava_adquirir`: 0 adquirida (DBX_STATE_AVISO se
# retomou orfa), conflito (ocupada, de outro host, ilegivel; a mensagem nomeia a
# raiz e o detentor, nunca perfil nem identidade), permissao (diretorio de
# estado alheio ou sem escrita), outro codigo para falha local. Independe da
# trava do par: pode ser detida junto com ela.
dbx_state_trava_raiz_adquirir() {
  [[ $# -eq 2 && $2 =~ ^[0-9]{1,4}$ ]] || return "$DBX_STATE_ERRO_USO"
  [[ -z $DBX_STATE_TRAVA_RAIZ ]] || return "$DBX_STATE_ERRO_USO"
  local raiz=$1 espera=$((10#$2)) arquivo diretorio estado sondagens=0 repeticoes=0 exibida
  DBX_STATE_MOTIVO=''
  # shellcheck disable=SC2034  # canal publico, lido por lib/cmd
  DBX_STATE_AVISO=''
  dbx_state_trava_raiz_caminho "$raiz" || {
    DBX_STATE_MOTIVO='nao foi possivel identificar a raiz local para a trava'
    return 1
  }
  arquivo=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  diretorio=${arquivo%/*}
  _dbx_state_trava_raiz_criados=()
  _dbx_state_trava_raiz_garantir_diretorio "$diretorio" || return $?
  dbx_state_host_id
  [[ -n $_dbx_state_trava_inicio ]] || printf -v _dbx_state_trava_inicio '%(%s)T' -1
  _dbx_state_trava_modo='raiz'
  _dbx_state_t_deste='desta raiz local' _dbx_state_t_neste='nesta raiz local' _dbx_state_t_este='esta raiz local'

  while :; do
    _dbx_state_trava_tentar "$arquivo" sync
    estado=$?
    [[ $estado -eq 0 ]] && break
    if [[ $estado -eq 3 ]]; then
      repeticoes=$((repeticoes + 1))
      [[ $repeticoes -lt 50 ]] && continue
      DBX_STATE_MOTIVO='trava instavel: o nome mudou a cada tentativa de obte-la; rode de novo depois ou use --esperar N (--wait N)'
      estado=$DBX_STATE_ERRO_CONFLITO
    fi
    if [[ $estado -ne $DBX_STATE_ERRO_CONFLITO || $sondagens -ge $espera ]]; then
      if [[ $estado -eq $DBX_STATE_ERRO_CONFLITO ]]; then
        exibida=$raiz
        [[ $exibida == *[$'\001'-$'\037\177']* ]] && printf -v exibida '%q' "$exibida"
        [[ $espera -gt 0 ]] && DBX_STATE_MOTIVO="esperou $espera s; $DBX_STATE_MOTIVO"
        DBX_STATE_MOTIVO="raiz local $exibida em uso por outra execucao: $DBX_STATE_MOTIVO"
      fi
      _dbx_state_trava_raiz_desfazer_diretorio
      break
    fi
    sleep 1
    sondagens=$((sondagens + 1))
    repeticoes=0
    # O detentor, ao soltar, remove o diretorio que ele proprio criou: quem
    # espera tem de recria-lo antes de cada nova sondagem, ou a trava liberada
    # viraria "sem escrita" (permissao) em vez de adquirida.
    _dbx_state_trava_raiz_garantir_diretorio "$diretorio" || {
      estado=$?
      _dbx_state_trava_raiz_desfazer_diretorio
      break
    }
  done
  _dbx_state_trava_modo='par'
  _dbx_state_t_deste='deste par' _dbx_state_t_neste='neste par' _dbx_state_t_este='este par'
  return "$estado"
}

_dbx_state_trava_raiz_desfazer_diretorio() {
  local indice
  for ((indice = ${#_dbx_state_trava_raiz_criados[@]} - 1; indice >= 0; indice--)); do
    rmdir -- "${_dbx_state_trava_raiz_criados[indice]}" 2>/dev/null || break
  done
  _dbx_state_trava_raiz_criados=()
}

# _dbx_state_trava_raiz_soltar <arquivo> — apaga SO a propria (pid, host,
# inicio desta aquisicao) e desfaz o diretorio que a aquisicao criou, se vazio.
_dbx_state_trava_raiz_soltar() {
  local arquivo=$1
  if _dbx_state_trava_ler "$arquivo" && [[ $DBX_STATE_TRAVA_PID == "$$" &&
    $DBX_STATE_TRAVA_HOST == "$DBX_STATE_HOST_ID" && $DBX_STATE_TRAVA_INICIO == "$_dbx_state_trava_raiz_inicio" ]]; then
    rm -f -- "$arquivo"
  fi
  [[ $DBX_STATE_TRAVA_RAIZ == "$arquivo" ]] && DBX_STATE_TRAVA_RAIZ=''
  _dbx_state_trava_raiz_desfazer_diretorio
  return 0
}

# dbx_state_trava_raiz_liberar — libera agora a trava de raiz (idempotente).
dbx_state_trava_raiz_liberar() {
  [[ -n $DBX_STATE_TRAVA_RAIZ ]] || return 0
  dbx_tmp_acao_cancelar "$_dbx_state_trava_raiz_acao"
  _dbx_state_trava_raiz_acao=''
  _dbx_state_trava_raiz_soltar "$DBX_STATE_TRAVA_RAIZ"
}

# dbx_state_trava_descrever <indice> — "o <comando> pid <pid> no host <nome>,
# iniciado em <ISO UTC>" da entrada da listagem, em DBX_STATE_RESULTADO; vazio
# para a ilegivel. So campos validados.
dbx_state_trava_descrever() {
  DBX_STATE_RESULTADO=''
  [[ ${1:-} =~ ^[0-9]+$ && -n ${DBX_STATE_TRAVAS_PID[$1]:-} ]] || return 0
  DBX_STATE_TRAVA_PID=${DBX_STATE_TRAVAS_PID[$1]}
  DBX_STATE_TRAVA_HOST=${DBX_STATE_TRAVAS_HOST[$1]}
  DBX_STATE_TRAVA_INICIO=${DBX_STATE_TRAVAS_INICIO[$1]}
  DBX_STATE_TRAVA_COMANDO=${DBX_STATE_TRAVAS_COMANDO[$1]}
  _dbx_state_trava_quem
}

# dbx_state_trava_examinar <arquivo> — le e classifica UMA trava: estado em
# DBX_STATE_TRAVA_ESTADO (`viva`, `orfa`, `outro-host`, `ilegivel` ou
# `ausente`) e a identidade "pid|host|inicio" em DBX_STATE_RESULTADO (vazia
# para ilegivel e ausente). So le.
dbx_state_trava_examinar() {
  DBX_STATE_RESULTADO=''
  _dbx_state_trava_ler "$1"
  case $? in
    0)
      _dbx_state_trava_classificar
      DBX_STATE_RESULTADO="$DBX_STATE_TRAVA_PID|$DBX_STATE_TRAVA_HOST|$DBX_STATE_TRAVA_INICIO"
      ;;
    2) DBX_STATE_TRAVA_ESTADO='ausente' ;;
    *) DBX_STATE_TRAVA_ESTADO='ilegivel' ;;
  esac
  return 0
}

# dbx_state_travas_listar — uma entrada por `trava-*` (inclusive `.r`) do
# diretorio de estado, com o estado apurado. So le: nao cria o diretorio, nao
# remove e nao retoma nada (RF-71).
dbx_state_travas_listar() {
  local diretorio arquivo tinha_nullglob='nao'
  local -a arquivos=()
  DBX_STATE_TRAVAS_ARQUIVO=() DBX_STATE_TRAVAS_ESTADO=() DBX_STATE_TRAVAS_PID=()
  DBX_STATE_TRAVAS_HOST=() DBX_STATE_TRAVAS_INICIO=() DBX_STATE_TRAVAS_COMANDO=()
  _dbx_state_base || return 0
  diretorio=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  _dbx_state_diretorio_confiavel "$diretorio" || return 0
  shopt -q nullglob && tinha_nullglob='sim'
  shopt -s nullglob
  arquivos=("$diretorio"/trava-*)
  [[ $tinha_nullglob == 'sim' ]] || shopt -u nullglob
  for arquivo in ${arquivos[@]+"${arquivos[@]}"}; do
    _dbx_state_trava_ler "$arquivo"
    case $? in
      2) continue ;;
      0) _dbx_state_trava_classificar ;;
      *) DBX_STATE_TRAVA_ESTADO='ilegivel' ;;
    esac
    DBX_STATE_TRAVAS_ARQUIVO+=("$arquivo")
    DBX_STATE_TRAVAS_ESTADO+=("$DBX_STATE_TRAVA_ESTADO")
    DBX_STATE_TRAVAS_PID+=("$DBX_STATE_TRAVA_PID")
    DBX_STATE_TRAVAS_HOST+=("$DBX_STATE_TRAVA_HOST")
    DBX_STATE_TRAVAS_INICIO+=("$DBX_STATE_TRAVA_INICIO")
    DBX_STATE_TRAVAS_COMANDO+=("$DBX_STATE_TRAVA_COMANDO")
  done
  return 0
}

# ---------------------------------------------------------------------------
# Namespace da retomada: `retomada-*` (fase 7a, F-03; RF-101, RF-105, RF-107)
# ---------------------------------------------------------------------------
#
# O ESTADO SO ACELERA (P1). O registro diz onde uma transferencia interrompida
# parou; ele nunca decide a integridade nem uma exclusao. Quem prova a
# integridade e a execucao corrente: o prefixo relido e conferido, o
# deslocamento do servidor conferido, o `content_hash` final e o `.part` inteiro
# antes do `mv`. Apagar `retomada-*` a mao so muda o custo (RF-101(j)).
#
# ESTADO INVALIDO NUNCA FAZ FALHAR (P2). Qualquer anomalia — vazio, truncado,
# lixo, magia ou versao desconhecida, contagem, campo fora da regex, acima de
# 16 KiB, conta, sentido, host ou caminho divergentes — DESCARTA: o registro e
# apagado (so o do usuario) e quem chama recomeca do zero, com um motivo de uma
# linha sem byte cru e sem `session_id`.
#
# FORMATO v1 (C3, C4; versao DO NAMESPACE, `DBX_STATE_VERSAO` nao muda):
#   magia, versao, sentido, conta, host, remoto, <campos do sentido>, local
# com NUL terminando cada campo e o caminho local fisico canonico por ultimo.
#   upload:   session_id, confirmado, voo_tamanho, voo_sha256, total,
#             identidade, criado_em, prefixo_hash
#   download: rev, tamanho, content_hash, nome do .part, dev|inode, criado_em
# Nenhum segredo (P3): o `session_id` e identificador operacional sensivel (C6),
# fica so neste arquivo 0600 e nunca sai em mensagem.
#
# CHAVE (C4, DIV-182): SHA-256 de `retomada` NUL sentido NUL conta NUL local NUL
# remoto-dobrado NUL, truncado em 32 hexadecimais. O resumo so LOCALIZA; a
# reconferencia byte a byte do cabecalho, na carga, e o que autentica.

readonly DBX_STATE_RETOMADA_MAGIA='dbx-retomada'
readonly DBX_STATE_RETOMADA_VERSAO=1
readonly DBX_STATE_RETOMADA_TETO=1000
readonly DBX_STATE_RETOMADA_DIAS=8
readonly DBX_STATE_RETOMADA_PARTE=4194304
readonly DBX_STATE_RETOMADA_CAMPOS_UPLOAD=15
readonly DBX_STATE_RETOMADA_CAMPOS_DOWNLOAD=13

# Contexto da transferencia corrente (`dbx_state_retomada_contexto`).
DBX_STATE_RETOMADA_SENTIDO=''
DBX_STATE_RETOMADA_CONTA=''
DBX_STATE_RETOMADA_HOST=''
DBX_STATE_RETOMADA_REMOTO=''
DBX_STATE_RETOMADA_LOCAL=''
DBX_STATE_RETOMADA_ARQUIVO=''
# Campos do sentido do ultimo registro valido carregado.
DBX_STATE_RETOMADA_CAMPOS=()
# Listagem para o `diagnostico` e o `unlink` (RF-107(c)(d)).
DBX_STATE_RETOMADAS_ARQUIVO=()
DBX_STATE_RETOMADAS_ESTADO=()
DBX_STATE_RETOMADAS_SENTIDO=()
DBX_STATE_RETOMADAS_LOCAL=()
DBX_STATE_RETOMADAS_REMOTO=()
DBX_STATE_RETOMADAS_BYTES=()
DBX_STATE_RETOMADAS_IDADE=()
DBX_STATE_RETOMADAS_PART=()
DBX_STATE_RETOMADAS_DEVINO=()
# Identidade `cred-` do cabecalho (fase 8, RF-125(b)): lida so do cabecalho, vazia
# para registro ilegivel. Sai so para o `unlink` atribuir o registro a uma
# credencial; nunca em saida ao operador.
DBX_STATE_RETOMADAS_CRED=()

# Diretorio ja preparado e podado nesta execucao (DIV-191: uma poda por
# execucao, na primeira gravacao, e nao a cada parte de 4 MiB).
_dbx_state_retomada_preparado=''
_DBX_STATE_REGISTRO_RETOMADA=()

# dbx_state_retomada_contexto <sentido> <conta> <local_canonico> <remoto>
#
# Fixa o contexto e o arquivo do registro, sem ler nem criar nada. Sem rede: a
# conta e o resumo local da credencial (`dbx_config_identidade`, DIV-47), e o
# host e so o nome (RF-101(h)).
dbx_state_retomada_contexto() {
  [[ $# -eq 4 && ($1 == 'upload' || $1 == 'download') && $2 =~ ^cred-[0-9a-f]{32}$ && -n $3 && -n $4 ]] ||
    return "$DBX_STATE_ERRO_USO"
  local sentido=$1 conta=$2 local_=$3 remoto=$4 base dobrado resumo
  DBX_STATE_RETOMADA_ARQUIVO=''
  _dbx_state_base || return $?
  base=$DBX_STATE_RESULTADO
  _dbx_state_minusculas_ascii "$remoto"
  dobrado=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  dbx_hash_verificar_dependencias || return 1
  # Separador NUL (DIV-d do parecer do DBA): `a\nb`+`c` e `a`+`b\nc` nao colidem.
  resumo=$(printf 'retomada\0%s\0%s\0%s\0%s\0' "$sentido" "$conta" "$local_" "$dobrado" |
    _dbx_hash_sha256_hex) || return 1
  [[ $resumo =~ ^[0-9a-f]{64}$ ]] || return 1
  dbx_state_host_id
  DBX_STATE_RETOMADA_SENTIDO=$sentido
  DBX_STATE_RETOMADA_CONTA=$conta
  DBX_STATE_RETOMADA_HOST=$DBX_STATE_HOST_NOME
  DBX_STATE_RETOMADA_REMOTO=$remoto
  DBX_STATE_RETOMADA_LOCAL=$local_
  DBX_STATE_RETOMADA_ARQUIVO="$base/retomada-${resumo:0:32}"
  return 0
}

# dbx_state_retomada_diretorio_utilizavel — 0 quando o diretorio de estado e do
# usuario e gravavel (criado em 0700 se faltar). Senao 1, com o motivo: quem
# chama segue SEM retomada, com aviso e codigo normal (RF-101(i), DIV-190).
dbx_state_retomada_diretorio_utilizavel() {
  local diretorio
  DBX_STATE_MOTIVO=''
  _dbx_state_base || {
    DBX_STATE_MOTIVO='diretorio de estado indeterminado'
    return 1
  }
  diretorio=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  if [[ ! -e $diretorio && ! -L $diretorio ]]; then
    # shellcheck disable=SC2174  # deliberado: so o ultimo componente e deste modulo
    mkdir -p -m 700 -- "$diretorio" 2>/dev/null || {
      DBX_STATE_MOTIVO='nao foi possivel criar o diretorio de estado'
      return 1
    }
  fi
  if ! _dbx_state_diretorio_confiavel "$diretorio"; then
    DBX_STATE_MOTIVO='o diretorio de estado pertence a outro usuario'
    return 1
  fi
  if [[ ! -w $diretorio || ! -x $diretorio ]]; then
    DBX_STATE_MOTIVO='o diretorio de estado nao aceita escrita'
    return 1
  fi
  return 0
}

# _dbx_state_retomada_formato <campos...> — 0 quando os campos formam um
# registro v1 bem formado de algum sentido (sem comparar com o processo).
# Publica o sentido em DBX_STATE_RESULTADO; o motivo do descarte em
# DBX_STATE_MOTIVO.
_dbx_state_retomada_formato() {
  local LC_ALL=C
  local -a c=("$@")
  local n=${#c[@]}
  DBX_STATE_RESULTADO=''
  if [[ $n -lt 3 || ${c[0]} != "$DBX_STATE_RETOMADA_MAGIA" || ${c[1]} != "$DBX_STATE_RETOMADA_VERSAO" ]]; then
    DBX_STATE_MOTIVO='registro de formato ou versao desconhecidos'
    return 1
  fi
  case ${c[2]} in
    upload) [[ $n -eq $DBX_STATE_RETOMADA_CAMPOS_UPLOAD ]] ;;
    download) [[ $n -eq $DBX_STATE_RETOMADA_CAMPOS_DOWNLOAD ]] ;;
    *) false ;;
  esac || {
    DBX_STATE_MOTIVO='registro com contagem de campos errada'
    return 1
  }
  DBX_STATE_MOTIVO='registro com campo invalido'
  [[ ${c[3]} =~ ^cred-[0-9a-f]{32}$ && ${c[4]} =~ ^[A-Za-z0-9._-]{1,64}$ && -n ${c[5]} && -n ${c[n - 1]} ]] ||
    return 1
  if [[ ${c[2]} == 'upload' ]]; then
    [[ ${c[6]} =~ ^[A-Za-z0-9:_-]{1,256}$ && ${c[7]} =~ ^[0-9]{1,18}$ && ${c[8]} =~ ^[0-9]{1,18}$ &&
      ${c[10]} =~ ^[0-9]{1,18}$ && ${c[12]} =~ ^[0-9]{1,18}$ && ${c[13]} =~ ^[0-9a-f]{64}$ ]] || return 1
    _dbx_state_identidade_valida "${c[11]}" || return 1
    local confirmado=$((10#${c[7]})) voo=$((10#${c[8]})) total=$((10#${c[10]}))
    ((confirmado % DBX_STATE_RETOMADA_PARTE == 0 && voo <= DBX_STATE_RETOMADA_PARTE &&
      confirmado + voo <= total)) || return 1
    if [[ $voo -eq 0 ]]; then
      [[ ${c[9]} == '-' ]] || return 1
    else
      [[ ${c[9]} =~ ^[0-9a-f]{64}$ ]] || return 1
    fi
  else
    [[ ${c[6]} =~ ^[0-9a-f]{9,64}$ && ${c[7]} =~ ^[0-9]{1,18}$ && ${c[8]} =~ ^[0-9a-f]{64}$ &&
      ${c[9]} =~ ^\.[^/]+\.dbx-part\.[A-Za-z0-9]{6}$ && ${c[10]} =~ ^[0-9]{1,20}\|[0-9]{1,20}$ &&
      ${c[11]} =~ ^[0-9]{1,18}$ ]] || return 1
  fi
  DBX_STATE_MOTIVO=''
  DBX_STATE_RESULTADO=${c[2]}
  return 0
}

# _dbx_state_retomada_descartar <motivo> — apaga o registro do contexto, so se
# for arquivo regular do usuario, e devolve 2 (descartado) com o motivo.
_dbx_state_retomada_descartar() {
  local arquivo=$DBX_STATE_RETOMADA_ARQUIVO
  DBX_STATE_MOTIVO=$1
  DBX_STATE_RETOMADA_CAMPOS=()
  [[ -f $arquivo && ! -L $arquivo && -O $arquivo ]] && rm -f -- "$arquivo" 2>/dev/null
  return 2
}

# _dbx_state_retomada_descartar_part <campos do registro...> — registro de
# download bem formado E do alvo desta execucao (mesmo caminho local; o que
# diverge e outra parte do cabecalho, como o remoto): o `.part` que ele aponta
# sai so pela barreira. Registro de OUTRO alvo (copiado ou plantado) nunca leva
# a apagar nada fora do alvo desta execucao (QA-B7A-02 x qa_d12).
_dbx_state_retomada_descartar_part() {
  local -a c=("$@")
  [[ ${#c[@]} -eq $DBX_STATE_RETOMADA_CAMPOS_DOWNLOAD && ${c[2]} == 'download' &&
    $DBX_STATE_RETOMADA_SENTIDO == 'download' && ${c[12]} == "$DBX_STATE_RETOMADA_LOCAL" ]] || return 0
  _dbx_state_retomada_dir_local "${c[12]}"
  dbx_state_retomada_part_apagar "$DBX_STATE_RESULTADO" "${c[9]}" "${c[10]}" || :
  DBX_STATE_RESULTADO=''
  return 0
}

# dbx_state_retomada_carregar — le o registro do contexto pelo leitor limitado.
#
#   0  valido: campos do sentido em DBX_STATE_RETOMADA_CAMPOS
#   1  ausente
#   2  descartado: apagado, motivo em DBX_STATE_MOTIVO (segue do zero)
#   3  intocavel: ligacao simbolica, nao regular ou de outro dono — nao e lido
#      nem apagado, e quem chama segue SEM retomada (nao grava por cima)
#
# Quem chama ja detem a trava do registro (RF-105(a)).
dbx_state_retomada_carregar() {
  local arquivo=$DBX_STATE_RETOMADA_ARQUIVO esperado LC_ALL=C
  DBX_STATE_RETOMADA_CAMPOS=()
  DBX_STATE_MOTIVO=''
  [[ -n $arquivo ]] || return "$DBX_STATE_ERRO_USO"
  [[ -L $arquivo ]] && return 3
  [[ -e $arquivo ]] || return 1
  _dbx_state_diretorio_confiavel "${arquivo%/*}" || return 3
  [[ -f $arquivo && -O $arquivo ]] || return 3
  esperado=$DBX_STATE_RETOMADA_CAMPOS_UPLOAD
  [[ $DBX_STATE_RETOMADA_SENTIDO == 'download' ]] && esperado=$DBX_STATE_RETOMADA_CAMPOS_DOWNLOAD
  _dbx_state_ler_limitado "$arquivo" "$DBX_STATE_RETOMADA_CAMPOS_UPLOAD"
  case $? in
    0) ;;
    2) return 1 ;;
    *)
      _dbx_state_retomada_descartar 'registro ilegivel, truncado ou acima de 16 KiB'
      return $?
      ;;
  esac
  local -a c=(${_DBX_STATE_CAMPOS[@]+"${_DBX_STATE_CAMPOS[@]}"})
  if ! _dbx_state_retomada_formato ${c[@]+"${c[@]}"}; then
    _dbx_state_retomada_descartar "$DBX_STATE_MOTIVO"
    return $?
  fi
  # Reconferencia byte a byte (C4): o resumo do nome so localiza.
  if [[ ${#c[@]} -ne $esperado || ${c[2]} != "$DBX_STATE_RETOMADA_SENTIDO" ||
    ${c[3]} != "$DBX_STATE_RETOMADA_CONTA" || ${c[4]} != "$DBX_STATE_RETOMADA_HOST" ||
    ${c[5]} != "$DBX_STATE_RETOMADA_REMOTO" || ${c[esperado - 1]} != "$DBX_STATE_RETOMADA_LOCAL" ]]; then
    # QA-B7A-02 (ciclo 2): o registro legivel diz qual `.part` era dele; sai
    # junto, so pela barreira de identidade, para nao ficar parcial invisivel.
    _dbx_state_retomada_descartar_part "${c[@]}"
    _dbx_state_retomada_descartar 'registro de outra conta, host, sentido ou caminho'
    return $?
  fi
  # shellcheck disable=SC2034  # canal publico, lido por lib/cmd e lib/transfer
  DBX_STATE_RETOMADA_CAMPOS=("${c[@]:6:esperado-7}")
  return 0
}

_dbx_state_conteudo_retomada() {
  printf '%s\0' "${_DBX_STATE_REGISTRO_RETOMADA[@]}"
}

# dbx_state_retomada_gravar <campos do sentido...> — gravacao atomica do
# registro do contexto (temporario `.retomada.*` no mesmo diretorio e `mv`), sem
# `fsync`: o estado e advisorio. 0 gravado; diferente de zero quando o campo e
# invalido, o lugar e de outro dono ou nao e arquivo, ou a gravacao falha —
# quem chama segue sem retomada (RF-103(a)).
dbx_state_retomada_gravar() {
  local arquivo=$DBX_STATE_RETOMADA_ARQUIVO diretorio estado primeira='nao'
  [[ -n $arquivo ]] || return "$DBX_STATE_ERRO_USO"
  local -a registro=("$DBX_STATE_RETOMADA_MAGIA" "$DBX_STATE_RETOMADA_VERSAO" "$DBX_STATE_RETOMADA_SENTIDO"
    "$DBX_STATE_RETOMADA_CONTA" "$DBX_STATE_RETOMADA_HOST" "$DBX_STATE_RETOMADA_REMOTO" "$@"
    "$DBX_STATE_RETOMADA_LOCAL")
  _dbx_state_retomada_formato "${registro[@]}" || return "$DBX_STATE_ERRO_USO"
  [[ $DBX_STATE_RESULTADO == "$DBX_STATE_RETOMADA_SENTIDO" ]] || return "$DBX_STATE_ERRO_USO"
  DBX_STATE_RESULTADO=''
  diretorio=${arquivo%/*}
  if [[ $_dbx_state_retomada_preparado != "$diretorio" ]]; then
    _dbx_state_preparar_diretorio "$diretorio"
    estado=$?
    [[ $estado -eq 0 ]] || return "$estado"
    primeira='sim'
  fi
  # O que nao foi lido nao e sobrescrito: ligacao, diretorio ou alheio.
  if [[ -L $arquivo ]] || { [[ -e $arquivo ]] && ! [[ -f $arquivo && -O $arquivo ]]; }; then
    return 1
  fi
  _DBX_STATE_REGISTRO_RETOMADA=("${registro[@]}")
  _dbx_state_gravar_arquivo "$arquivo" .retomada _dbx_state_conteudo_retomada || return 1
  if [[ $primeira == 'sim' ]]; then
    _dbx_state_retomada_preparado=$diretorio
    _dbx_state_retomada_podar "$diretorio"
  fi
  return 0
}

# dbx_state_retomada_remover — apaga o registro do contexto (so o do usuario).
dbx_state_retomada_remover() {
  local arquivo=$DBX_STATE_RETOMADA_ARQUIVO
  [[ -n $arquivo ]] || return 0
  [[ -f $arquivo && ! -L $arquivo && -O $arquivo ]] && rm -f -- "$arquivo" 2>/dev/null
  return 0
}

# dbx_state_retomada_part_barreira <diretorio_do_alvo> <nome> <dev|inode>
#
# A BARREIRA DE IDENTIDADE do `.part` (RF-104(c)(e)): 0 so quando o nome segue
# o padrao `.*.dbx-part.??????` sem barra, e o arquivo no diretorio do alvo nao
# e ligacao simbolica, e regular, e do usuario e tem o MESMO dispositivo e
# inode gravados. Nenhum arquivo do usuario e apagado por causa do estado: o
# que reprova fica onde esta.
dbx_state_retomada_part_barreira() {
  local diretorio=$1 nome=$2 devino=$3 caminho atual LC_ALL=C
  [[ -n $diretorio && $nome =~ ^\.[^/]+\.dbx-part\.[A-Za-z0-9]{6}$ && $devino =~ ^[0-9]{1,20}\|[0-9]{1,20}$ ]] ||
    return 1
  caminho="$diretorio/$nome"
  [[ -L $caminho ]] && return 1
  [[ -f $caminho && -O $caminho ]] || return 1
  dbx_atributo dev_ino "$caminho" || return 1; atual=$DBX_ATRIBUTO
  [[ $atual == "$devino" ]]
}

# dbx_state_retomada_part_apagar <diretorio_do_alvo> <nome> <dev|inode> — apaga
# o `.part` so pela barreira. 0 apagado; 1 reprovado (intocado).
dbx_state_retomada_part_apagar() {
  dbx_state_retomada_part_barreira "$@" || return 1
  rm -f -- "$1/$2" 2>/dev/null
  return 0
}

# _dbx_state_retomada_dir_local <caminho_local> — diretorio do alvo em
# DBX_STATE_RESULTADO.
_dbx_state_retomada_dir_local() {
  DBX_STATE_RESULTADO=${1%/*}
  [[ $DBX_STATE_RESULTADO == "$1" ]] && DBX_STATE_RESULTADO=.
  [[ -z $DBX_STATE_RESULTADO ]] && DBX_STATE_RESULTADO=/
  return 0
}

# _dbx_state_retomada_podar_um <arquivo> — poda UM registro (RF-107(a)(b)): com
# trava viva, fica; de download legivel, o `.part` sai so pela barreira; o
# registro sai. 0 removido, 1 mantido.
_dbx_state_retomada_podar_um() {
  local arquivo=$1 resumo trava
  [[ -f $arquivo && ! -L $arquivo && -O $arquivo ]] || return 1
  resumo=${arquivo##*/retomada-}
  trava="${arquivo%/*}/trava-$resumo"
  if [[ -e $trava || -L $trava ]]; then
    dbx_state_trava_examinar "$trava"
    [[ $DBX_STATE_TRAVA_ESTADO == 'viva' ]] && return 1
  fi
  if _dbx_state_ler_limitado "$arquivo" "$DBX_STATE_RETOMADA_CAMPOS_UPLOAD" &&
    _dbx_state_retomada_formato "${_DBX_STATE_CAMPOS[@]}" && [[ $DBX_STATE_RESULTADO == 'download' ]]; then
    _dbx_state_retomada_dir_local "${_DBX_STATE_CAMPOS[12]}"
    dbx_state_retomada_part_apagar "$DBX_STATE_RESULTADO" "${_DBX_STATE_CAMPOS[9]}" "${_DBX_STATE_CAMPOS[10]}" || :
  fi
  DBX_STATE_RESULTADO=''
  DBX_STATE_MOTIVO=''
  rm -f -- "$arquivo" 2>/dev/null
  return 0
}

# _dbx_state_retomada_podar <diretorio> — RF-107(a), DIV-184: registros com
# modificacao ha mais de 8 dias (idade do ARQUIVO, nunca o `criado_em`) e, acima
# de 1.000, os mais antigos por modificacao ate o teto. Nunca casa `memoria-*`,
# `upload-*` nem `trava-*`; o registro do contexto nunca sai por aqui. O relogio
# decide so o que TENTAR limpar, nunca a validade de um registro em uso.
_dbx_state_retomada_podar() {
  local diretorio=$1 arquivo antigo tinha_nullglob='nao'
  local -a registros=()
  while IFS= read -r -d '' arquivo; do
    [[ $arquivo == "$DBX_STATE_RETOMADA_ARQUIVO" ]] && continue
    _dbx_state_retomada_podar_um "$arquivo" || :
  done < <(find "$diretorio" -maxdepth 1 -type f -name 'retomada-*' -mtime "+$DBX_STATE_RETOMADA_DIAS" -print0 2>/dev/null)

  shopt -q nullglob && tinha_nullglob='sim'
  shopt -s nullglob
  registros=("$diretorio"/retomada-*)
  [[ $tinha_nullglob == 'sim' ]] || shopt -u nullglob
  local excesso=$((${#registros[@]} - DBX_STATE_RETOMADA_TETO)) voltas=0
  local -A mantidos=()
  while [[ $excesso -gt 0 && $voltas -lt $((excesso + 50)) ]]; do
    voltas=$((voltas + 1))
    # O mais antigo sai do teste `-ot` do bash sobre a lista do glob, sem `find
    # -printf` (RF-168): o utilitario do FreeBSD nao o conhece.
    antigo=''
    for arquivo in "${registros[@]}"; do
      [[ $arquivo == "$DBX_STATE_RETOMADA_ARQUIVO" || -n ${mantidos[$arquivo]:-} ]] && continue
      [[ -f $arquivo && ! -L $arquivo ]] || continue
      if [[ -z $antigo || $arquivo -ot $antigo ]]; then
        antigo=$arquivo
      fi
    done
    [[ -n $antigo ]] || break
    if _dbx_state_retomada_podar_um "$antigo"; then
      excesso=$((excesso - 1))
    else
      mantidos[$antigo]=1
    fi
  done
  return 0
}

# dbx_state_retomada_travar — trava do registro (RF-105(a), C2): `trava-<o mesmo
# resumo>` pela receita de RF-69(j), comando `retomada`, ALEM de uma eventual
# trava de par. Adquirida antes de ler o registro e mantida ate a remocao ou a
# ultima regravacao; liberada em todo caminho de saida (`lib/tmp`).
#
#   0          adquirida (DBX_STATE_AVISO quando retomou orfa do mesmo host)
#   conflito   ocupada, de outro host ou ilegivel: quem chama segue SEM
#              retomada, sem esperar e sem recusar (RF-105(b)); DBX_STATE_MOTIVO
#   permissao  diretorio de estado alheio ou sem escrita
#   outro      uso invalido ou falha local
dbx_state_retomada_travar() {
  local arquivo resumo estado repeticoes=0
  [[ -n $DBX_STATE_RETOMADA_ARQUIVO && -z $DBX_STATE_TRAVA_REGISTRO ]] || return "$DBX_STATE_ERRO_USO"
  DBX_STATE_MOTIVO=''
  # shellcheck disable=SC2034  # canal publico, lido por lib/cmd
  DBX_STATE_AVISO=''
  resumo=${DBX_STATE_RETOMADA_ARQUIVO##*/retomada-}
  arquivo="${DBX_STATE_RETOMADA_ARQUIVO%/*}/trava-$resumo"
  if ! _dbx_state_diretorio_confiavel "${arquivo%/*}"; then
    DBX_STATE_MOTIVO='diretorio de estado ausente ou de outro usuario'
    return "$DBX_STATE_ERRO_PERMISSAO"
  fi
  dbx_state_host_id
  [[ -n $_dbx_state_trava_inicio ]] || printf -v _dbx_state_trava_inicio '%(%s)T' -1
  _dbx_state_trava_modo='registro'
  while :; do
    _dbx_state_trava_tentar "$arquivo" retomada
    estado=$?
    [[ $estado -eq 3 && $repeticoes -lt 50 ]] || break
    repeticoes=$((repeticoes + 1))
  done
  _dbx_state_trava_modo='par'
  [[ $estado -eq 3 ]] && estado=$DBX_STATE_ERRO_CONFLITO
  if [[ $estado -eq $DBX_STATE_ERRO_CONFLITO ]]; then
    # O texto da trava de par fala de sync e de `--esperar`; aqui nao se espera.
    _dbx_state_trava_ler "$arquivo"
    case $? in
      0)
        _dbx_state_trava_classificar
        _dbx_state_trava_quem
        if [[ $DBX_STATE_TRAVA_ESTADO == 'outro-host' ]]; then
          DBX_STATE_MOTIVO="trava do registro de outro host: $DBX_STATE_RESULTADO"
        else
          DBX_STATE_MOTIVO="trava do registro ocupada: $DBX_STATE_RESULTADO"
        fi
        DBX_STATE_RESULTADO=''
        ;;
      *) DBX_STATE_MOTIVO='trava do registro ilegivel ou instavel' ;;
    esac
  fi
  return "$estado"
}

# _dbx_state_trava_registro_soltar <arquivo> — apaga so a propria trava de
# registro (pid, host e inicio desta aquisicao).
_dbx_state_trava_registro_soltar() {
  local arquivo=$1
  if _dbx_state_trava_ler "$arquivo" && [[ $DBX_STATE_TRAVA_PID == "$$" &&
    $DBX_STATE_TRAVA_HOST == "$DBX_STATE_HOST_ID" && $DBX_STATE_TRAVA_INICIO == "$_dbx_state_trava_registro_inicio" &&
    $DBX_STATE_TRAVA_COMANDO == 'retomada' ]]; then
    rm -f -- "$arquivo"
  fi
  [[ $DBX_STATE_TRAVA_REGISTRO == "$arquivo" ]] && DBX_STATE_TRAVA_REGISTRO=''
  return 0
}

# dbx_state_retomada_soltar — libera agora a trava de registro (idempotente).
dbx_state_retomada_soltar() {
  [[ -n $DBX_STATE_TRAVA_REGISTRO ]] || return 0
  dbx_tmp_acao_cancelar "$_dbx_state_trava_registro_acao"
  _dbx_state_trava_registro_acao=''
  _dbx_state_trava_registro_soltar "$DBX_STATE_TRAVA_REGISTRO"
}

# dbx_state_retomada_listar — uma entrada por `retomada-*`, so lendo, pelo
# leitor limitado: nao cria o diretorio, nao remove nada (RF-107(d)). Estado
# `pendente`, `ilegivel` ou `orfa` (modificado ha mais de 8 dias); bytes
# confirmados (upload) ou recebidos (tamanho atual do `.part` que passa a
# barreira); idade em dias. Nenhum `session_id` sai daqui (C6).
dbx_state_retomada_listar() {
  local diretorio arquivo agora mtime idade tinha_nullglob='nao' bytes part devino
  local -a arquivos=() c=()
  DBX_STATE_RETOMADAS_ARQUIVO=() DBX_STATE_RETOMADAS_ESTADO=() DBX_STATE_RETOMADAS_SENTIDO=()
  DBX_STATE_RETOMADAS_LOCAL=() DBX_STATE_RETOMADAS_REMOTO=() DBX_STATE_RETOMADAS_BYTES=()
  DBX_STATE_RETOMADAS_IDADE=() DBX_STATE_RETOMADAS_PART=() DBX_STATE_RETOMADAS_DEVINO=()
  DBX_STATE_RETOMADAS_CRED=()
  _dbx_state_base || return 0
  diretorio=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  _dbx_state_diretorio_confiavel "$diretorio" || return 0
  shopt -q nullglob && tinha_nullglob='sim'
  shopt -s nullglob
  arquivos=("$diretorio"/retomada-*)
  [[ $tinha_nullglob == 'sim' ]] || shopt -u nullglob
  printf -v agora '%(%s)T' -1
  for arquivo in ${arquivos[@]+"${arquivos[@]}"}; do
    [[ -e $arquivo || -L $arquivo ]] || continue
    dbx_atributo mtime "$arquivo" && mtime=$DBX_ATRIBUTO || mtime=$agora
    [[ $mtime =~ ^[0-9]+$ ]] || mtime=$agora
    idade=$(((agora - mtime) / 86400))
    DBX_STATE_RETOMADAS_ARQUIVO+=("$arquivo")
    DBX_STATE_RETOMADAS_IDADE+=("$idade")
    if _dbx_state_ler_limitado "$arquivo" "$DBX_STATE_RETOMADA_CAMPOS_UPLOAD" &&
      _dbx_state_retomada_formato "${_DBX_STATE_CAMPOS[@]}"; then
      c=("${_DBX_STATE_CAMPOS[@]}")
      part='' devino='' bytes=0
      if [[ ${c[2]} == 'upload' ]]; then
        bytes=$((10#${c[7]}))
        DBX_STATE_RETOMADAS_LOCAL+=("${c[14]}")
      else
        _dbx_state_retomada_dir_local "${c[12]}"
        part="$DBX_STATE_RESULTADO/${c[9]}"
        devino=${c[10]}
        if dbx_state_retomada_part_barreira "$DBX_STATE_RESULTADO" "${c[9]}" "$devino"; then
          dbx_atributo tamanho "$part" && bytes=$DBX_ATRIBUTO || bytes=0
        fi
        DBX_STATE_RETOMADAS_LOCAL+=("${c[12]}")
      fi
      DBX_STATE_RESULTADO=''
      if [[ $((agora - mtime)) -gt $((DBX_STATE_RETOMADA_DIAS * 86400)) ]]; then
        DBX_STATE_RETOMADAS_ESTADO+=(orfa)
      else
        DBX_STATE_RETOMADAS_ESTADO+=(pendente)
      fi
      DBX_STATE_RETOMADAS_SENTIDO+=("${c[2]}")
      DBX_STATE_RETOMADAS_REMOTO+=("${c[5]}")
      DBX_STATE_RETOMADAS_BYTES+=("$bytes")
      DBX_STATE_RETOMADAS_PART+=("$part")
      DBX_STATE_RETOMADAS_DEVINO+=("$devino")
      DBX_STATE_RETOMADAS_CRED+=("${c[3]}")
    else
      DBX_STATE_RETOMADAS_ESTADO+=(ilegivel)
      DBX_STATE_RETOMADAS_SENTIDO+=('')
      DBX_STATE_RETOMADAS_LOCAL+=('')
      DBX_STATE_RETOMADAS_REMOTO+=('')
      DBX_STATE_RETOMADAS_BYTES+=(0)
      DBX_STATE_RETOMADAS_PART+=('')
      DBX_STATE_RETOMADAS_DEVINO+=('')
      DBX_STATE_RETOMADAS_CRED+=('')
    fi
  done
  DBX_STATE_MOTIVO=''
  return 0
}

# ---------------------------------------------------------------------------
# Namespace do cursor de listagem: `cursor-*` (fase 7b, F-14; RF-111, RF-113,
# RF-117; parecer do DBA, C1 a C4, C6, C10, C11)
# ---------------------------------------------------------------------------
#
# O ESTADO SO ACELERA (P1). O registro guarda o cursor do `list_folder` e o
# RETRATO remoto sem filtro do instante dele (C3): o `sync --receber` aplica o
# delta do `list_folder/continue` ao retrato e reconstroi a tabela remota. Ele
# nunca decide uma exclusao (toda candidata e confirmada no servidor, RF-114,
# em `lib/sync`) nem a integridade (o download confere `rev` e `content_hash`).
# Apagar `cursor-*` a mao so muda o custo.
#
# ESTADO INVALIDO NUNCA FAZ FALHAR (P3). Qualquer anomalia descarta: o registro
# e apagado (so o do usuario, e nunca em simulacao) e quem chama faz a
# varredura completa na mesma execucao, com um motivo de uma linha sem byte cru
# e SEM o cursor (C10).
#
# FORMATO v1 (C1; versao DO NAMESPACE, `DBX_STATE_VERSAO` nao muda), cada campo
# terminado em NUL:
#   cabecalho (12): magia, versao, cred-, account_id, assinatura da listagem,
#     raiz remota (sem dobra), raiz local canonica, cursor,
#     varredura_completa_em, incrementais_desde, gravado_em, n_entradas
#   corpo (n x 2): "tag<TAB>id<TAB>rev<TAB>content_hash<TAB>tamanho<TAB>
#     server_modified<TAB>path_display" e "path_lower"; pasta com `-` em rev,
#     hash e data; arquivo sem `content_hash` com `-` (DIV-223) e sem data com
#     `-` (a data so e lida quando filtra o escopo, RF-39; DIV-225)
#   rodape: `fim` e o SHA-256 hexadecimal de todos os bytes anteriores a `fim`
#
# CHAVE (C2): SHA-256 de `cursor` NUL cred- NUL local NUL remoto-dobrado NUL
# assinatura NUL, truncado em 32 hexadecimais. O resumo so LOCALIZA; a
# reconferencia byte a byte do cabecalho, mais o `account_id` desta execucao, e
# o que autentica. Filtros fora da chave: o retrato e sem filtro (DIV-213).
#
# LEITOR EM FLUXO (C4): um descritor, so arquivo regular do usuario, campo de
# ate 8 KiB, ate 1.000.000 de entradas e 512 MiB, regex por campo, e o rodape
# conferido ANTES de o chamador usar o retrato (quem chama so monta a tabela
# em memoria; o descarte a zera). Cada entrada passa pela funcao do chamador,
# que confina o caminho (`dbx_sync_relativo`) e recusa `path_lower` repetido.

readonly DBX_STATE_CURSOR_MAGIA='dbx-cursor'
readonly DBX_STATE_CURSOR_VERSAO=1
readonly DBX_STATE_CURSOR_CABECALHO=12
readonly DBX_STATE_CURSOR_CAMPO=8192
readonly DBX_STATE_CURSOR_ENTRADAS=1000000
readonly DBX_STATE_CURSOR_BYTES=536870912
readonly DBX_STATE_CURSOR_TETO=100
readonly DBX_STATE_CURSOR_DIAS=8
# Varredura completa obrigatoria (C8, DIV-208): 7 dias, 100 incrementais, ou
# relogio que voltou mais de 5 minutos. O relogio so decide fazer MAIS trabalho.
readonly DBX_STATE_CURSOR_VALIDADE_S=604800
readonly DBX_STATE_CURSOR_INCREMENTAIS=100
readonly DBX_STATE_CURSOR_FOLGA_S=300
readonly DBX_STATE_CURSOR_RE_CURSOR='^[A-Za-z0-9_=+/.-]{1,8192}$'
readonly DBX_STATE_CURSOR_RE_CONTA='^dbid:[A-Za-z0-9_-]{1,128}$'
readonly DBX_STATE_CURSOR_RE_ASSINATURA='^[A-Za-z0-9_;=.-]{1,256}$'
readonly DBX_STATE_CURSOR_RE_ENTRADA=$'^(f|d)\t(id:[A-Za-z0-9_-]{1,64})\t([0-9a-f]{9,64}|-)\t([0-9a-f]{64}|-)\t([0-9]{1,18})\t([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|-)\t(.+)$'

# Contexto (`dbx_state_cursor_contexto`).
DBX_STATE_CURSOR_ARQUIVO=''
DBX_STATE_CURSOR_CONTA=''
DBX_STATE_CURSOR_ACCOUNT=''
DBX_STATE_CURSOR_ASSINATURA=''
DBX_STATE_CURSOR_REMOTO=''
DBX_STATE_CURSOR_LOCAL=''
# Cabecalho do registro valido carregado. O cursor e identificador operacional
# sensivel (C10): fica so neste canal e no arquivo 0600, nunca em mensagem.
DBX_STATE_CURSOR_VALOR=''
DBX_STATE_CURSOR_COMPLETA_EM=''
DBX_STATE_CURSOR_INCREMENTAIS_DESDE=''
DBX_STATE_CURSOR_N=''
# Listagem para o `diagnostico` (RF-117(e)), so do cabecalho.
DBX_STATE_CURSORES_ARQUIVO=()
DBX_STATE_CURSORES_ESTADO=()
DBX_STATE_CURSORES_REMOTO=()
DBX_STATE_CURSORES_LOCAL=()
DBX_STATE_CURSORES_ENTRADAS=()
DBX_STATE_CURSORES_IDADE=()
# Identidade `cred-` do cabecalho (fase 8, RF-125(b)); vazia se ilegivel.
DBX_STATE_CURSORES_CRED=()

_DBX_STATE_CURSOR_REG=()
_DBX_STATE_CURSOR_LIDO=''
_dbx_state_cursor_corpo=''
_dbx_state_cursor_podado=''
_dbx_state_cursor_consumido=0
_dbx_state_cursor_fd=''

# dbx_state_cursor_contexto <cred> <account_id> <local_canonico> <remoto>
#   <assinatura>
#
# Fixa o contexto e o arquivo do registro, sem ler nem criar nada. Sem `cred-`
# ou sem `account_id` nao ha contexto, e portanto nao ha cursor (C2, RF-52(a)).
# O <remoto> e o caminho da API e pode ser VAZIO: e a raiz `/` da credencial
# (QA-B7B-01); o campo vazio entra na chave e no cabecalho como qualquer outro.
dbx_state_cursor_contexto() {
  local LC_ALL=C
  DBX_STATE_CURSOR_ARQUIVO=''
  [[ $# -eq 5 && $1 =~ ^cred-[0-9a-f]{32}$ && $2 =~ $DBX_STATE_CURSOR_RE_CONTA && -n $3 &&
    $5 =~ $DBX_STATE_CURSOR_RE_ASSINATURA ]] || return "$DBX_STATE_ERRO_USO"
  local conta=$1 account=$2 local_=$3 remoto=$4 assinatura=$5 base dobrado resumo
  _dbx_state_base || return $?
  base=$DBX_STATE_RESULTADO
  _dbx_state_minusculas_ascii "$remoto"
  dobrado=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  dbx_hash_verificar_dependencias || return 1
  resumo=$(printf 'cursor\0%s\0%s\0%s\0%s\0' "$conta" "$local_" "$dobrado" "$assinatura" |
    _dbx_hash_sha256_hex) || return 1
  [[ $resumo =~ ^[0-9a-f]{64}$ ]] || return 1
  DBX_STATE_CURSOR_CONTA=$conta
  DBX_STATE_CURSOR_ACCOUNT=$account
  DBX_STATE_CURSOR_ASSINATURA=$assinatura
  DBX_STATE_CURSOR_REMOTO=$remoto
  DBX_STATE_CURSOR_LOCAL=$local_
  DBX_STATE_CURSOR_ARQUIVO="$base/cursor-${resumo:0:32}"
  return 0
}

# _dbx_state_cursor_cabecalho_formato <12 campos> — 0 quando o cabecalho e um
# v1 bem formado (sem comparar com o processo); motivo em DBX_STATE_MOTIVO.
_dbx_state_cursor_cabecalho_formato() {
  local LC_ALL=C
  if [[ $# -ne $DBX_STATE_CURSOR_CABECALHO || $1 != "$DBX_STATE_CURSOR_MAGIA" || $2 != "$DBX_STATE_CURSOR_VERSAO" ]]; then
    DBX_STATE_MOTIVO='registro de listagem de formato ou versao desconhecidos'
    return 1
  fi
  # O remoto ($6) vazio e a raiz `/` (QA-B7B-01); o local ($7) nunca e vazio.
  if [[ ! $3 =~ ^cred-[0-9a-f]{32}$ || ! $4 =~ $DBX_STATE_CURSOR_RE_CONTA || ! $5 =~ $DBX_STATE_CURSOR_RE_ASSINATURA ||
    -z $7 || ! $8 =~ $DBX_STATE_CURSOR_RE_CURSOR || ! $9 =~ ^[0-9]{1,12}$ || ! ${10} =~ ^[0-9]{1,7}$ ||
    ! ${11} =~ ^[0-9]{1,12}$ || ! ${12} =~ ^[0-9]{1,7}$ ]] || ((10#${12} > DBX_STATE_CURSOR_ENTRADAS)); then
    DBX_STATE_MOTIVO='registro de listagem com campo invalido'
    return 1
  fi
  DBX_STATE_MOTIVO=''
  return 0
}

# _dbx_state_cursor_descartar <motivo> <apagar> — apaga o registro do contexto
# (so arquivo regular do usuario, e so com <apagar> = sim: a simulacao nunca
# apaga, RF-117(a)) e devolve 2 com o motivo.
_dbx_state_cursor_descartar() {
  local arquivo=$DBX_STATE_CURSOR_ARQUIVO
  DBX_STATE_MOTIVO=$1
  DBX_STATE_CURSOR_VALOR='' DBX_STATE_CURSOR_COMPLETA_EM='' DBX_STATE_CURSOR_INCREMENTAIS_DESDE='' DBX_STATE_CURSOR_N=''
  if [[ $2 == 'sim' && -f $arquivo && ! -L $arquivo && -O $arquivo ]]; then
    rm -f -- "$arquivo" 2>/dev/null
  fi
  return 2
}

# _dbx_state_cursor_campo <fd> — le UM campo terminado em NUL do descritor, no
# maximo 8 KiB, em _DBX_STATE_CURSOR_LIDO, e soma os bytes consumidos. 0 lido;
# 1 fim, campo truncado, acima de 8 KiB ou acima de 512 MiB no total.
_dbx_state_cursor_campo() {
  local LC_ALL=C
  _DBX_STATE_CURSOR_LIDO=''
  IFS= read -r -d '' -n "$((DBX_STATE_CURSOR_CAMPO + 1))" _DBX_STATE_CURSOR_LIDO <&"$1" || return 1
  [[ ${#_DBX_STATE_CURSOR_LIDO} -le $DBX_STATE_CURSOR_CAMPO ]] || return 1
  _dbx_state_cursor_consumido=$((_dbx_state_cursor_consumido + ${#_DBX_STATE_CURSOR_LIDO} + 1))
  [[ $_dbx_state_cursor_consumido -le $DBX_STATE_CURSOR_BYTES ]]
}

# _dbx_state_cursor_abrir <arquivo> — abre o registro num descritor, so se for
# arquivo regular do usuario e nao ligacao simbolica, em _dbx_state_cursor_fd.
# 0 aberto; 1 intocavel (nem lido, nem apagado); 2 ausente.
_dbx_state_cursor_abrir() {
  local arquivo=$1 fd
  _dbx_state_cursor_fd=''
  [[ -L $arquivo ]] && return 1
  [[ -e $arquivo ]] || return 2
  # Como no leitor da 7a (QA-B7A-01): FIFO nunca e aberta, pois bloquearia.
  [[ -f $arquivo && -O $arquivo ]] || return 1
  { exec {fd}<"$arquivo"; } 2>/dev/null || return 1
  if [[ ! -f /dev/fd/$fd || ! -O /dev/fd/$fd ]]; then
    exec {fd}<&-
    return 1
  fi
  _dbx_state_cursor_fd=$fd
  return 0
}

# _dbx_state_cursor_entrada_valida <registro> <path_lower> — regex por campo;
# arquivo com `rev` (a data remota e `-` quando nao foi lida, RF-39), pasta so
# com `-`.
_dbx_state_cursor_entrada_valida() {
  local LC_ALL=C
  [[ $1 =~ $DBX_STATE_CURSOR_RE_ENTRADA && $2 == /* ]] || return 1
  if [[ ${BASH_REMATCH[1]} == 'f' ]]; then
    [[ ${BASH_REMATCH[3]} != '-' ]]
  else
    [[ ${BASH_REMATCH[3]} == '-' && ${BASH_REMATCH[4]} == '-' && ${BASH_REMATCH[6]} == '-' ]]
  fi
}

# _dbx_state_cursor_rodape_confere <fd> <bytes_do_prefixo> — 0 quando os dois
# campos seguintes sao `fim` e o SHA-256 dos <bytes_do_prefixo> primeiros bytes
# do MESMO arquivo, e nada vem depois. 1 truncado ou ausente; 2 divergente.
_dbx_state_cursor_rodape_confere() {
  local fd=$1 prefixo=$2 resumo conferido resto='' LC_ALL=C
  _dbx_state_cursor_campo "$fd" && [[ $_DBX_STATE_CURSOR_LIDO == 'fim' ]] || return 1
  _dbx_state_cursor_campo "$fd" && [[ $_DBX_STATE_CURSOR_LIDO =~ ^[0-9a-f]{64}$ ]] || return 1
  resumo=$_DBX_STATE_CURSOR_LIDO
  _DBX_STATE_CURSOR_LIDO=''
  if IFS= read -r -d '' -n 1 resto <&"$fd" || [[ -n $resto ]]; then
    return 1
  fi
  dbx_hash_verificar_dependencias || return 1
  # `/dev/fd/N` aberto pelo `head` reabre o inode DO DESCRITOR, e nao o nome,
  # que poderia ter sido trocado desde a abertura.
  conferido=$(_dbx_hash_sha256_hex < <(head -c "$prefixo" -- "/dev/fd/$fd" 2>/dev/null)) || return 2
  [[ $conferido == "$resumo" ]] || return 2
  return 0
}

# dbx_state_cursor_carregar <funcao_de_entrada> [apagar]
#
# Le o registro do contexto em fluxo. Para cada entrada bem formada chama
# `<funcao_de_entrada> <registro> <path_lower> <tag> <id> <path_display>`; um
# status diferente de zero dela descarta o registro (caminho fora da raiz,
# `path_lower` repetido). Com [apagar] = nao (simulacao), o descarte nao apaga.
#
#   0  valido e conferido: cabecalho em DBX_STATE_CURSOR_*; o retrato foi
#      entregue a funcao e o rodape conferiu
#   1  ausente
#   2  descartado: motivo em DBX_STATE_MOTIVO; quem chama zera o que montou
#   3  intocavel: ligacao simbolica, nao regular ou de outro dono — nao e lido
#      nem apagado, e quem chama segue SEM cursor (nao grava por cima)
#
# Quem chama ja detem a trava do par (C7).
dbx_state_cursor_carregar() {
  [[ $# -ge 1 && -n $DBX_STATE_CURSOR_ARQUIVO ]] || return "$DBX_STATE_ERRO_USO"
  local funcao=$1 apagar=${2:-sim} arquivo=$DBX_STATE_CURSOR_ARQUIVO fd tamanho n indice registro lower
  local estado=0 LC_ALL=C
  local -a cab=()
  DBX_STATE_MOTIVO=''
  DBX_STATE_CURSOR_VALOR='' DBX_STATE_CURSOR_COMPLETA_EM='' DBX_STATE_CURSOR_INCREMENTAIS_DESDE='' DBX_STATE_CURSOR_N=''
  if ! _dbx_state_diretorio_confiavel "${arquivo%/*}"; then
    [[ -e $arquivo || -L $arquivo ]] && return 3
    return 1
  fi
  _dbx_state_cursor_abrir "$arquivo"
  case $? in
    0) fd=$_dbx_state_cursor_fd ;;
    2) return 1 ;;
    *) return 3 ;;
  esac
  dbx_atributo -L tamanho "/dev/fd/$fd" && tamanho=$DBX_ATRIBUTO || tamanho=-1
  _dbx_state_cursor_consumido=0
  if [[ ! $tamanho =~ ^[0-9]+$ || $tamanho -gt $DBX_STATE_CURSOR_BYTES ]]; then
    exec {fd}<&-
    _dbx_state_cursor_descartar 'registro de listagem ilegivel ou acima de 512 MiB' "$apagar"
    return $?
  fi
  for ((indice = 0; indice < DBX_STATE_CURSOR_CABECALHO; indice++)); do
    _dbx_state_cursor_campo "$fd" || {
      estado=1
      break
    }
    cab+=("$_DBX_STATE_CURSOR_LIDO")
  done
  if [[ $estado -ne 0 ]]; then
    exec {fd}<&-
    _dbx_state_cursor_descartar 'registro de listagem ilegivel, truncado ou com campo acima de 8 KiB' "$apagar"
    return $?
  fi
  if ! _dbx_state_cursor_cabecalho_formato "${cab[@]}"; then
    exec {fd}<&-
    _dbx_state_cursor_descartar "$DBX_STATE_MOTIVO" "$apagar"
    return $?
  fi
  # Reconferencia byte a byte (C2): o resumo do nome so localiza.
  if [[ ${cab[2]} != "$DBX_STATE_CURSOR_CONTA" || ${cab[3]} != "$DBX_STATE_CURSOR_ACCOUNT" ||
    ${cab[4]} != "$DBX_STATE_CURSOR_ASSINATURA" || ${cab[5]} != "$DBX_STATE_CURSOR_REMOTO" ||
    ${cab[6]} != "$DBX_STATE_CURSOR_LOCAL" ]]; then
    exec {fd}<&-
    _dbx_state_cursor_descartar 'registro de listagem de outra conta, raiz ou listagem' "$apagar"
    return $?
  fi
  n=$((10#${cab[11]}))
  for ((indice = 0; indice < n; indice++)); do
    if ! _dbx_state_cursor_campo "$fd"; then
      estado=1
      break
    fi
    registro=$_DBX_STATE_CURSOR_LIDO
    if ! _dbx_state_cursor_campo "$fd"; then
      estado=1
      break
    fi
    lower=$_DBX_STATE_CURSOR_LIDO
    if ! _dbx_state_cursor_entrada_valida "$registro" "$lower"; then
      estado=2
      break
    fi
    if ! "$funcao" "$registro" "$lower" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[7]}"; then
      estado=3
      break
    fi
  done
  if [[ $estado -eq 0 ]]; then
    _dbx_state_cursor_rodape_confere "$fd" "$_dbx_state_cursor_consumido"
    case $? in
      0) ;;
      1) estado=1 ;;
      *) estado=4 ;;
    esac
  fi
  exec {fd}<&-
  _DBX_STATE_CURSOR_LIDO=''
  case $estado in
    0) ;;
    1)
      _dbx_state_cursor_descartar 'registro de listagem truncado, sem rodape ou com contagem errada' "$apagar"
      return $?
      ;;
    2)
      _dbx_state_cursor_descartar 'registro de listagem com entrada invalida' "$apagar"
      return $?
      ;;
    3)
      _dbx_state_cursor_descartar 'registro de listagem com caminho fora da raiz ou repetido' "$apagar"
      return $?
      ;;
    *)
      _dbx_state_cursor_descartar 'registro de listagem com rodape de integridade divergente' "$apagar"
      return $?
      ;;
  esac
  # shellcheck disable=SC2034  # canais publicos, lidos por commands/sync
  DBX_STATE_CURSOR_VALOR=${cab[7]}
  # shellcheck disable=SC2034
  DBX_STATE_CURSOR_COMPLETA_EM=$((10#${cab[8]}))
  # shellcheck disable=SC2034
  DBX_STATE_CURSOR_INCREMENTAIS_DESDE=$((10#${cab[9]}))
  # shellcheck disable=SC2034
  DBX_STATE_CURSOR_N=$n
  return 0
}

# dbx_state_cursor_vencido <varredura_completa_em> <incrementais_desde> [agora]
# — 0 quando a varredura completa e obrigatoria (C8, DIV-208): ultima completa
# ha mais de 7 dias, 100 incrementais, ou relogio mais de 5 min no passado.
dbx_state_cursor_vencido() {
  local completa=${1-} incrementais=${2-} agora=${3:-}
  [[ -n $agora ]] || printf -v agora '%(%s)T' -1
  [[ $completa =~ ^[0-9]+$ && $incrementais =~ ^[0-9]+$ ]] || return 0
  ((agora - completa > DBX_STATE_CURSOR_VALIDADE_S)) && return 0
  ((completa - agora > DBX_STATE_CURSOR_FOLGA_S)) && return 0
  ((incrementais >= DBX_STATE_CURSOR_INCREMENTAIS)) && return 0
  return 1
}

_dbx_state_conteudo_cursor() {
  printf '%s\0' "${_DBX_STATE_CURSOR_REG[@]}"
  "$_dbx_state_cursor_corpo"
}

# _dbx_state_rodape_cursor <temporario> — acrescenta `fim` e o SHA-256 dos bytes
# ja escritos; recusa o que passaria do teto de 512 MiB (nao persiste).
_dbx_state_rodape_cursor() {
  local temporario=$1 tamanho resumo
  dbx_atributo tamanho "$temporario" || return 1; tamanho=$DBX_ATRIBUTO
  [[ $tamanho =~ ^[0-9]+$ && $tamanho -le $((DBX_STATE_CURSOR_BYTES - 80)) ]] || return 1
  resumo=$(_dbx_hash_sha256_hex <"$temporario") || return 1
  [[ $resumo =~ ^[0-9a-f]{64}$ ]] || return 1
  printf 'fim\0%s\0' "$resumo" >>"$temporario"
}

# dbx_state_cursor_gravar <cursor> <varredura_completa_em> <incrementais_desde>
#   <n_entradas> <funcao_de_corpo>
#
# Gravacao atomica do registro do contexto (C1, C6): temporario `.cursor.*` no
# mesmo diretorio, rodape e `mv`, sem `fsync`. <funcao_de_corpo> escreve as
# <n_entradas> entradas, dois campos NUL cada. Cursor fora da regex, retrato
# acima de 1.000.000 de entradas ou de 512 MiB: NAO persiste (diferente de
# zero), e quem chama segue normal. Lugar de outro dono, ligacao ou diretorio
# no lugar do registro: nada e escrito. A poda (C11) corre uma vez por execucao.
dbx_state_cursor_gravar() {
  [[ $# -eq 5 && -n $DBX_STATE_CURSOR_ARQUIVO ]] || return "$DBX_STATE_ERRO_USO"
  local arquivo=$DBX_STATE_CURSOR_ARQUIVO diretorio estado agora LC_ALL=C
  printf -v agora '%(%s)T' -1
  local -a registro=("$DBX_STATE_CURSOR_MAGIA" "$DBX_STATE_CURSOR_VERSAO" "$DBX_STATE_CURSOR_CONTA"
    "$DBX_STATE_CURSOR_ACCOUNT" "$DBX_STATE_CURSOR_ASSINATURA" "$DBX_STATE_CURSOR_REMOTO"
    "$DBX_STATE_CURSOR_LOCAL" "$1" "$2" "$3" "$agora" "$4")
  _dbx_state_cursor_cabecalho_formato "${registro[@]}" || return 1
  declare -F -- "$5" >/dev/null || return "$DBX_STATE_ERRO_USO"
  diretorio=${arquivo%/*}
  _dbx_state_preparar_diretorio "$diretorio"
  estado=$?
  [[ $estado -eq 0 ]] || return "$estado"
  if [[ -L $arquivo ]] || { [[ -e $arquivo ]] && ! [[ -f $arquivo && -O $arquivo ]]; }; then
    return 1
  fi
  _DBX_STATE_CURSOR_REG=("${registro[@]}")
  _dbx_state_cursor_corpo=$5
  _dbx_state_gravar_arquivo "$arquivo" .cursor _dbx_state_conteudo_cursor _dbx_state_rodape_cursor
  estado=$?
  _DBX_STATE_CURSOR_REG=()
  _dbx_state_cursor_corpo=''
  [[ $estado -eq 0 ]] || return 1
  if [[ $_dbx_state_cursor_podado != "$diretorio" ]]; then
    _dbx_state_cursor_podado=$diretorio
    _dbx_state_cursor_podar "$diretorio"
  fi
  return 0
}

# dbx_state_cursor_remover — apaga o registro do contexto (so o do usuario).
dbx_state_cursor_remover() {
  local arquivo=$DBX_STATE_CURSOR_ARQUIVO
  [[ -n $arquivo ]] || return 0
  [[ -f $arquivo && ! -L $arquivo && -O $arquivo ]] && rm -f -- "$arquivo" 2>/dev/null
  return 0
}

# _dbx_state_cursor_podar <diretorio> — C11: `cursor-*` com modificacao ha mais
# de 8 dias e, acima de 100, os mais antigos por modificacao. So arquivo
# regular do usuario; nunca o registro do contexto; nunca outro namespace.
_dbx_state_cursor_podar() {
  local diretorio=$1 arquivo antigo tinha_nullglob='nao'
  local -a registros=()
  while IFS= read -r -d '' arquivo; do
    [[ $arquivo == "$DBX_STATE_CURSOR_ARQUIVO" ]] && continue
    [[ -f $arquivo && ! -L $arquivo && -O $arquivo ]] && rm -f -- "$arquivo" 2>/dev/null
  done < <(find "$diretorio" -maxdepth 1 -type f -name 'cursor-*' -mtime "+$DBX_STATE_CURSOR_DIAS" -print0 2>/dev/null)

  shopt -q nullglob && tinha_nullglob='sim'
  shopt -s nullglob
  registros=("$diretorio"/cursor-*)
  [[ $tinha_nullglob == 'sim' ]] || shopt -u nullglob
  local excesso=$((${#registros[@]} - DBX_STATE_CURSOR_TETO)) voltas=0
  local -A mantidos=()
  while [[ $excesso -gt 0 && $voltas -lt $((excesso + 50)) ]]; do
    voltas=$((voltas + 1))
    # Mesmo criterio da poda de `retomada-*`: `-ot` sobre o glob (RF-168).
    antigo=''
    for arquivo in "${registros[@]}"; do
      [[ $arquivo == "$DBX_STATE_CURSOR_ARQUIVO" || -n ${mantidos[$arquivo]:-} ]] && continue
      [[ -f $arquivo && ! -L $arquivo ]] || continue
      if [[ -z $antigo || $arquivo -ot $antigo ]]; then
        antigo=$arquivo
      fi
    done
    [[ -n $antigo ]] || break
    if [[ -f $antigo && ! -L $antigo && -O $antigo ]] && rm -f -- "$antigo" 2>/dev/null; then
      excesso=$((excesso - 1))
    else
      mantidos[$antigo]=1
    fi
  done
  return 0
}

# dbx_state_cursor_listar — uma entrada por `cursor-*`, lendo SO o cabecalho
# (C4, RF-117(e)): nao cria o diretorio, nao remove nada, nunca le o retrato
# (vale para registro de qualquer tamanho). Estado `valido`, `vencido`
# (varredura completa obrigatoria, C8) ou `ilegivel`; remoto, local, entradas e
# idade em dias da ultima varredura completa. O cursor NUNCA sai daqui (C10).
dbx_state_cursor_listar() {
  local diretorio arquivo agora indice fd tinha_nullglob='nao' estado
  local -a arquivos=() cab=()
  DBX_STATE_CURSORES_ARQUIVO=() DBX_STATE_CURSORES_ESTADO=() DBX_STATE_CURSORES_REMOTO=()
  DBX_STATE_CURSORES_LOCAL=() DBX_STATE_CURSORES_ENTRADAS=() DBX_STATE_CURSORES_IDADE=()
  DBX_STATE_CURSORES_CRED=()
  _dbx_state_base || return 0
  diretorio=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  _dbx_state_diretorio_confiavel "$diretorio" || return 0
  shopt -q nullglob && tinha_nullglob='sim'
  shopt -s nullglob
  arquivos=("$diretorio"/cursor-*)
  [[ $tinha_nullglob == 'sim' ]] || shopt -u nullglob
  printf -v agora '%(%s)T' -1
  for arquivo in ${arquivos[@]+"${arquivos[@]}"}; do
    [[ -e $arquivo || -L $arquivo ]] || continue
    cab=()
    estado='ilegivel'
    if _dbx_state_cursor_abrir "$arquivo"; then
      fd=$_dbx_state_cursor_fd
      _dbx_state_cursor_consumido=0
      for ((indice = 0; indice < DBX_STATE_CURSOR_CABECALHO; indice++)); do
        _dbx_state_cursor_campo "$fd" || break
        cab+=("$_DBX_STATE_CURSOR_LIDO")
      done
      exec {fd}<&-
      _DBX_STATE_CURSOR_LIDO=''
      if _dbx_state_cursor_cabecalho_formato ${cab[@]+"${cab[@]}"}; then
        estado='valido'
        dbx_state_cursor_vencido "$((10#${cab[8]}))" "$((10#${cab[9]}))" "$agora" && estado='vencido'
      fi
    fi
    DBX_STATE_CURSORES_ARQUIVO+=("$arquivo")
    DBX_STATE_CURSORES_ESTADO+=("$estado")
    if [[ $estado != 'ilegivel' ]]; then
      DBX_STATE_CURSORES_REMOTO+=("${cab[5]}")
      DBX_STATE_CURSORES_LOCAL+=("${cab[6]}")
      DBX_STATE_CURSORES_ENTRADAS+=("$((10#${cab[11]}))")
      DBX_STATE_CURSORES_IDADE+=("$(((agora - 10#${cab[8]}) / 86400))")
      DBX_STATE_CURSORES_CRED+=("${cab[2]}")
    else
      DBX_STATE_CURSORES_REMOTO+=('') DBX_STATE_CURSORES_LOCAL+=('')
      DBX_STATE_CURSORES_ENTRADAS+=(0) DBX_STATE_CURSORES_IDADE+=(0)
      DBX_STATE_CURSORES_CRED+=('')
    fi
  done
  cab=()
  DBX_STATE_MOTIVO=''
  return 0
}
