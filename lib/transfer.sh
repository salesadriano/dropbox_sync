#!/usr/bin/env bash
# lib/transfer.sh — envio em partes por sessao (RF-08, RF-09, RF-31).
#
# Camada: orquestracao. Fica entre `commands/upload` e o transporte: decide
# QUANDO ha sessao, conduz a sequencia e conta os bytes; nao monta cabecalho,
# nao fala com o cliente de rede e nao decide o que publicar — o objeto de
# publicacao (`commit`) chega pronto do comando.
#
# Depende de lib/errors, lib/json, lib/hash e lib/auth. Nao e carregado por
# `bin/dbx`: `commands/upload` o carrega sob demanda, no unico caminho que o usa.
#
# ---------------------------------------------------------------------------
# SEQUENCIA
# ---------------------------------------------------------------------------
#   start  -> corpo VAZIO, sessao SEQUENCIAL (o tipo omitido e o padrao)
#   append -> um por parte CHEIA, com o deslocamento acumulado no cursor
#   finish -> ultimo bloco (possivelmente vazio) mais o `commit`
#
# O deslocamento e a chave de deduplicacao do servico: o contrato documenta
# `offset` como "the amount of data that has been uploaded so far", e existe
# para que uma retentativa nao perca nem duplique dado. Por isso a retentativa
# repete a MESMA requisicao com o MESMO deslocamento — e nao um deslocamento
# recalculado.
#
# PROCEDENCIA DO CONTRATO: o desenho acima segue o `files.stone` publicado pela
# Dropbox (repositorio `dropbox-api-spec`, ramo `main`). E contrato DOCUMENTADO,
# lido, NAO exercitado contra o servico real. Onde o texto e ambiguo, este
# componente escolhe a alternativa que falha fechada, e a ambiguidade fica
# escrita ao lado da escolha.
#
# ---------------------------------------------------------------------------
# TAMANHO DE PARTE FIXO — LACUNA DE RF-08 DECLARADA
# ---------------------------------------------------------------------------
# RF-08 pede tamanho de parte CONFIGURAVEL. Esta entrega NAO o torna
# configuravel, e a lacuna fica declarada aqui em vez de silenciada.
#
# Motivo: o tamanho da parte e a MESMA grandeza que o bloco do `content_hash`.
# Uma parte de outro tamanho montaria a cadeia de resumos sobre fatias que nao
# sao blocos, e o `content_hash` sairia bem formado e errado. Para a entrada
# padrao, o teto de ocupacao de RF-31 e exatamente UM BLOCO, e a igualdade o
# torna estrutural. Expor o valor exige antes separar `parte de rede` de
# `bloco de resumo`.
#
# ---------------------------------------------------------------------------
# TETO DE OCUPACAO EM DISCO (RF-31)
# ---------------------------------------------------------------------------
# Um unico arquivo de bloco, reaproveitado a cada volta, em area propria criada
# por `lib/tmp` (0700) e usada sob `umask 077`. A ocupacao nao acompanha o tamanho do
# conteudo: ela e a de uma parte, seja o fluxo de 8 MiB ou de 800 GiB.
#
# LIMITE DECLARADO, herdado de lib/hash: no encerramento o mesmo arquivo recebe
# a CADEIA de resumos, que tem 32 bytes por bloco. Logo o pico real e o maior
# entre uma parte e 32 x N. Ultrapassar uma parte exigiria 131.072 blocos, isto
# e 512 GiB de conteudo. Nao e "sempre uma parte"; e uma parte ate essa marca.
#
# ---------------------------------------------------------------------------
# LEITURA SEM CANO
# ---------------------------------------------------------------------------
# `head -c N >arquivo`, com o status observado diretamente, e `wc -c <arquivo`
# para o tamanho: por cano, so o status do ultimo comando e observavel, e uma
# leitura truncada produziria resumo bem formado de conteudo INCOMPLETO.
#
# LIMITE DECLARADO (RSK-36): quando a origem e um cano anonimo, produtor que
# morre no meio e indistinguivel de fim de fluxo legitimo — o status dele
# pertence ao shell do operador. O criterio de RF-31 ("nenhum arquivo parcial e
# publicado") vale para FALHA DE LEITURA, que aqui e observavel e aborta a
# sessao, e NAO para produtor que encerrou mal depois de escrever um prefixo:
# esse prefixo e publicado como arquivo inteiro. Por isso a recomendacao ao
# operador e `set -o pipefail`. Medicao em
# docs/registros/2026-10-19-historico-comentarios-http-transfer.md.
#
# ---------------------------------------------------------------------------
# INTEGRIDADE PONTA A PONTA, E O QUE NAO SE ENVIA POR PARTE
# ---------------------------------------------------------------------------
# O `content_hash` e acumulado localmente parte a parte e comparado com o que o
# `finish` devolve no metadado. Divergencia e classe `integridade`.
#
# NAO enviamos `content_hash` por parte no `append`, embora o campo exista no
# argumento: a interpretacao exata dele por chamada nao pode ser validada fora
# do servico, e um erro quebraria todo envio em partes sem que a suite o visse.
# A comparacao com o `content_hash` do `finish` da a mesma garantia de ponta a
# ponta sem arriscar contrato.
#
# ---------------------------------------------------------------------------
# NADA PARCIAL PUBLICADO
# ---------------------------------------------------------------------------
# O arquivo so existe no destino quando o `finish` retorna. Qualquer falha antes
# disso encerra sem `finish`, e a sessao abandonada expira sozinha no servico —
# nao ha chamada de aborto de sessao no contrato, e inventar uma seria fabricar
# API. O que se perde e cota de sessao aberta, nao dado do operador.

[[ -n ${DBX_TRANSFER_CARREGADO:-} ]] && return 0
DBX_TRANSFER_CARREGADO=1

_dbx_transfer_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_transfer_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_transfer_diretorio=.
_dbx_transfer_diretorio=$(cd -P -- "$_dbx_transfer_diretorio" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_transfer_diretorio/errors.sh"
# shellcheck source=lib/hash.sh
. "$_dbx_transfer_diretorio/hash.sh"
# shellcheck source=lib/progress.sh
. "$_dbx_transfer_diretorio/progress.sh"
# shellcheck source=lib/tmp.sh
. "$_dbx_transfer_diretorio/tmp.sh"
unset _dbx_transfer_diretorio

# Parte de 4 MiB — a MESMA grandeza do bloco do `content_hash`. A igualdade e
# verificada em teste: separa-las sem separar as nocoes quebraria a cadeia.
readonly DBX_TRANSFER_TAMANHO_PARTE=4194304
# Teto por requisicao publicado pela Dropbox. Acima dele o servico devolve
# `payload_too_large`. E tambem o limiar de roteamento de RF-08: arquivo local
# maior que isto nao cabe em requisicao unica.
readonly DBX_TRANSFER_LIMITE_REQUISICAO=157286400

readonly DBX_TRANSFER_URL_INICIAR='https://content.dropboxapi.com/2/files/upload_session/start'
readonly DBX_TRANSFER_URL_ANEXAR='https://content.dropboxapi.com/2/files/upload_session/append_v2'
readonly DBX_TRANSFER_URL_CONCLUIR='https://content.dropboxapi.com/2/files/upload_session/finish'

DBX_TRANSFER_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
readonly DBX_TRANSFER_ERRO_USO

# Canais publicos, consumidos por `commands/upload` e pela suite.
# shellcheck disable=SC2034
# Justificativa: classe da taxonomia da ultima falha, lida pelo comando.
DBX_TRANSFER_CLASSE=''
# shellcheck disable=SC2034
# Justificativa: diagnostico ja redigido da ultima falha, lido pelo comando.
DBX_TRANSFER_MOTIVO=''
# shellcheck disable=SC2034
# Justificativa: `content_hash` acumulado localmente, lido pelo comando.
DBX_TRANSFER_CONTENT_HASH=''
# shellcheck disable=SC2034
# Justificativa: total de bytes lidos da origem, exigido por RF-31.
DBX_TRANSFER_BYTES=0
# shellcheck disable=SC2034
# Justificativa: `conferida` ou `nao_aplicavel`; o comando publica o valor.
DBX_TRANSFER_INTEGRIDADE='nao_aplicavel'
# shellcheck disable=SC2034
# Justificativa: tamanho medido por `dbx_transfer_tamanho_de_arquivo`.
DBX_TRANSFER_TAMANHO=0
DBX_TRANSFER_LIDO=''

# Area da sessao em curso, registrada em `lib/tmp`; global porque as funcoes da
# sessao a compartilham.
DBX_TRANSFER_AREA_TEMP=''

# RF-58 — estado da retomada, SO EM MEMORIA e so durante a sessao: a origem
# posicionavel (vazia para a entrada padrao), o tamanho medido no inicio, o
# descritor de onde as partes sao lidas e o deslocamento pedido pelo servico.
# Nenhum deles e gravado em disco; uma nova execucao recomeca do zero (F-03
# fora de escopo).
_DBX_TRANSFER_ORIGEM=''
_DBX_TRANSFER_TAMANHO_INICIAL=0
_DBX_TRANSFER_FONTE=0
_DBX_TRANSFER_RETOMAR_EM=''
_DBX_TRANSFER_EXIBIDO=''

# ---------------------------------------------------------------------------
# Roteamento por tamanho (RF-08)
# ---------------------------------------------------------------------------

# dbx_transfer_precisa_de_sessao <bytes> — 0 quando o conteudo nao cabe em uma
# requisicao unica.
#
# Predicado PURO, sobre numero. O tamanho e medido por quem tem o arquivo; aqui
# so se compara, para que o limiar tenha um unico dono e um caso de teste possa
# exercitar a fronteira sem materializar 150 MiB.
dbx_transfer_precisa_de_sessao() {
  local bytes=${1-}
  [[ $bytes =~ ^[0-9]+$ ]] || return "$DBX_TRANSFER_ERRO_USO"
  [[ $bytes -gt $DBX_TRANSFER_LIMITE_REQUISICAO ]]
}

# dbx_transfer_tamanho_de_arquivo <caminho> — publica o tamanho em
# DBX_TRANSFER_TAMANHO.
#
# MEDIDO, nunca declarado: o roteamento decide sobre o arquivo que existe agora,
# e nao sobre o que o chamador supoe.
dbx_transfer_tamanho_de_arquivo() {
  local caminho=${1-} bytes
  DBX_TRANSFER_TAMANHO=0
  [[ -n $caminho && -r $caminho ]] || return "$DBX_TRANSFER_ERRO_USO"
  bytes=$(wc -c <"$caminho") || return "$DBX_TRANSFER_ERRO_USO"
  bytes=${bytes//[^0-9]/}
  [[ -n $bytes ]] || return "$DBX_TRANSFER_ERRO_USO"
  # shellcheck disable=SC2034
  # Justificativa: canal publico lido por `commands/upload` para decidir o
  # roteamento. A analise estatica nao cruza arquivos.
  DBX_TRANSFER_TAMANHO=$bytes
  return 0
}

# ---------------------------------------------------------------------------
# Diagnostico e leitura de resposta
# ---------------------------------------------------------------------------

# _dbx_transfer_falhar <classe> <motivo> — publica classe e motivo redigido.
#
# Chamada SEMPRE em `{ ...; return $?; }`, nunca em `return "$(...)"`: a segunda
# forma roda em subshell e a publicacao se perderia junto com ele.
_dbx_transfer_falhar() {
  local classe=$1 motivo=$2
  dbx_errors_redigir "$motivo" >/dev/null
  DBX_TRANSFER_CLASSE=$classe
  DBX_TRANSFER_MOTIVO=$DBX_ERRORS_REDIGIDO
  return "$(dbx_errors_codigo_saida "$classe")"
}

# _dbx_transfer_ler_campo <segmentos...> — le um campo do corpo da ultima
# resposta em CONTEXTO NOMEADO PROPRIO.
#
# Contexto proprio, e nome literal: usar o contexto do comando destruiria a
# analise que ele mantem, e derivar o nome de dado externo e o defeito que a
# auditoria de contexto nomeado existe para impedir. O corpo bruto permanece em
# DBX_HTTP_CORPO para quem quiser reanalisa-lo — e o que `commands/upload` faz
# com o metadado do `finish`.
_dbx_transfer_ler_campo() {
  local estado=1
  DBX_TRANSFER_LIDO=''
  [[ -n ${DBX_HTTP_CORPO:-} ]] || return 1
  dbx_json_contexto transferencia || return 1
  if dbx_json_analisar "$DBX_HTTP_CORPO"; then
    if dbx_json_valor "$@" >/dev/null; then
      DBX_TRANSFER_LIDO=$DBX_JSON_RESULTADO
      estado=0
    fi
  fi
  dbx_json_descartar transferencia
  # A restauracao usa o canal DIRETAMENTE, e nao uma copia local: a auditoria
  # de procedencia de contexto (RNF-24) so aceita nome literal ou este canal.
  # Seguro aqui: nada entre a selecao e esta linha troca de contexto.
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  # shellcheck disable=SC2034  # canal publico alheio, limpo por quem o encheu
  DBX_JSON_RESULTADO=''
  return $estado
}

# _dbx_transfer_deslocamento_correto — le `correct_offset` do corpo de erro.
#
# DUAS FORMAS ACEITAS: o contrato declara `incorrect_offset` como membro de
# uniao carregando `UploadSessionOffsetError{correct_offset}`, mas a
# serializacao da carga — achatada no objeto `error` ou aninhada sob a tag — nao
# foi verificada contra o servico. Se nenhuma estiver presente, a funcao falha e
# a sessao aborta fechada.
_dbx_transfer_deslocamento_correto() {
  _dbx_transfer_ler_campo error correct_offset && return 0
  _dbx_transfer_ler_campo error incorrect_offset correct_offset && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Ciclo de vida da area temporaria
# ---------------------------------------------------------------------------

_dbx_transfer_remover_area() {
  dbx_tmp_remover "${DBX_TRANSFER_AREA_TEMP:-}"
  DBX_TRANSFER_AREA_TEMP=''
  return 0
}

# Sinal no meio da sessao encerra o PROCESSO, e nao apenas a funcao, pelo
# tratador unico de `lib/tmp` (RNF-35): sem `finish` nada foi publicado, a
# sessao abandonada expira sozinha, e continuar depois de um sinal produziria
# envio parcial travestido de sucesso. O codigo e o de operacao nao concluida, e
# as areas desta sessao, de `lib/http` e de quem chamou saem juntas. Historico
# do paliativo anterior em
# docs/registros/2026-10-19-historico-comentarios-http-transfer.md.

# ---------------------------------------------------------------------------
# Emissao
# ---------------------------------------------------------------------------

# _dbx_transfer_emitir <url> <argumento> <arquivo_de_corpo> <idempotente>
#
# A entrada padrao da chamada e desviada de `/dev/null` DE PROPOSITO: a entrada
# padrao desta funcao e o FLUXO DE DADOS do operador, e qualquer comando da
# cadeia de autenticacao que a lesse consumiria bytes do conteudo em silencio.
_dbx_transfer_emitir() {
  local url=$1 argumento=$2 corpo=$3 idempotente=$4
  dbx_auth_conteudo POST "$url" "$argumento" "$corpo" "$idempotente" </dev/null
}

# _dbx_transfer_anexar <sessao_json> <deslocamento> <tamanho> <arquivo_de_corpo>
#
# RF-09 em duas camadas, e a segunda e a que importa:
#
#   1. `idempotente=sim` deixa lib/http repetir a MESMA requisicao, com o MESMO
#      deslocamento e o MESMO corpo, ate o limite de tentativas (5 por padrao,
#      RNF-07). Repetir uma parte nao reinicia o arquivo — e o que RF-09 pede.
#
#   2. RECONCILIACAO DE DESLOCAMENTO. Se o servico recusa com `incorrect_offset`
#      e informa um `correct_offset` igual ao FIM desta parte, entao esta parte
#      ja foi aceita numa tentativa anterior cuja resposta se perdeu: insistir
#      duplicaria conteudo. Tratamos como progresso e avancamos.
#
# A reconciliacao torna a retentativa correta INDEPENDENTEMENTE de a primeira
# tentativa ter chegado ou nao: depende so de o servico dizer onde acha que
# esta.
#
# Qualquer outro valor de `correct_offset` significa discordancia real sobre o
# que ja chegou. Com a entrada padrao, que nao e posicionavel, abortamos, e o
# diagnostico diz os dois numeros. Com arquivo regular (RF-58) o deslocamento e
# validado e o laco rele a partir dele.
#
# QUEM RECONHECE A CONDICAO DE SESSAO E `lib/errors.sh`, E SO ELE: esta funcao
# le a POLITICA que `lib/http` publica em `DBX_HTTP_POLITICA`, vinda inteira da
# taxonomia (prefixo casado em fronteira de componente), para a regra ter um
# dono so.
#
# `reiniciar` (tag `reset`) tem tratamento proprio: reiniciar exige reler a
# origem desde o inicio, impossivel com entrada padrao, entao o envio aborta
# dizendo isso em vez de publicar conteudo embaralhado.
_dbx_transfer_anexar() {
  local sessao=$1 deslocamento=$2 tamanho=$3 corpo=$4
  local argumento esperado=$((deslocamento + tamanho)) correto

  argumento="{\"cursor\":{\"session_id\":\"$sessao\",\"offset\":$deslocamento},\"close\":false}"
  _dbx_transfer_emitir "$DBX_TRANSFER_URL_ANEXAR" "$argumento" "$corpo" sim && return 0

  case ${DBX_HTTP_POLITICA:-} in
    retomar)
      if _dbx_transfer_deslocamento_correto; then
        correto=$DBX_TRANSFER_LIDO
        # Ate 18 digitos a comparacao cabe na aritmetica; `10#` impede a leitura
        # em octal de um valor com zero a esquerda.
        if [[ $correto =~ ^[0-9]{1,18}$ ]] && ((10#$correto == esperado)); then
          return 0
        fi
        # RF-58: arquivo regular e posicionavel, e reler a partir do deslocamento
        # do servico e possivel. Quem rele e o laco; aqui so se valida e avisa.
        if [[ -n $_DBX_TRANSFER_ORIGEM ]]; then
          _dbx_transfer_validar_retomada "$correto" "$deslocamento" || return $?
          _DBX_TRANSFER_RETOMAR_EM=$((10#$correto))
          return 0
        fi
        _dbx_transfer_exibir "$correto"
        {
          _dbx_transfer_falhar nao_concluida \
            "deslocamento divergente na parte que comeca em $deslocamento: apos esta parte o deslocamento seria $esperado e o servico informou $_DBX_TRANSFER_EXIBIDO; a entrada padrao nao e posicionavel e reler nao e opcao"
          return $?
        }
      fi
      {
        _dbx_transfer_falhar nao_concluida \
          "o servico recusou a parte que comeca em $deslocamento por deslocamento incorreto e nao informou o deslocamento correto"
        return $?
      }
      ;;
    reiniciar)
      {
        _dbx_transfer_falhar nao_concluida \
          "o servico invalidou a sessao na parte que comeca em $deslocamento e exige reiniciar o envio desde o inicio; a entrada padrao nao e posicionavel e reler nao e opcao, entao nada foi publicado no destino"
        return $?
      }
      ;;
  esac

  # RF-09 emendado: falha transitoria que resistiu a todas as tentativas e
  # operacao NAO CONCLUIDA — a classe original fica no diagnostico.
  case ${DBX_HTTP_POLITICA:-} in
    recuo_exponencial | respeitar_retry_after)
      {
        _dbx_transfer_falhar nao_concluida \
          "parte que comeca em $deslocamento recusada em todas as ${DBX_HTTP_EFETIVO[DBX_HTTP_TENTATIVAS_MAXIMAS]} tentativas (${DBX_HTTP_CLASSE:-erro_remoto}: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}); nada foi publicado no destino"
        return $?
      }
      ;;
  esac
  {
    _dbx_transfer_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
      "parte que comeca em $deslocamento recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return $?
  }
}

# _dbx_transfer_exibir <valor> — publica em _DBX_TRANSFER_EXIBIDO uma forma do
# valor vindo do servico que cabe numa linha de diagnostico: digitos passam como
# estao (truncados), o resto sai citado. Um `correct_offset` com quebra de linha
# nao pode virar segunda linha no diagnostico.
_dbx_transfer_exibir() {
  local valor=${1:0:32}
  if [[ $valor =~ ^[0-9]+$ ]]; then
    _DBX_TRANSFER_EXIBIDO=$valor
    [[ ${#1} -gt 32 ]] && _DBX_TRANSFER_EXIBIDO+='...'
  else
    printf -v _DBX_TRANSFER_EXIBIDO '%q' "$valor"
  fi
  return 0
}

# _dbx_transfer_validar_retomada <correct_offset> <enviado> — RF-58(b): so
# inteiro em [0, bytes ja confirmados pelo servico], que nunca passa do tamanho
# do arquivo. Acima do confirmado o servico alega ter bytes que nunca mandamos:
# hostil ou inconsistente, e reler dali publicaria um arquivo com buraco
# (decisao do Tech Lead). Fora da faixa o envio aborta antes de
# qualquer `finish` e a mensagem nomeia o valor recusado.
_dbx_transfer_validar_retomada() {
  local correto=$1 enviado=$2
  [[ $enviado -gt $_DBX_TRANSFER_TAMANHO_INICIAL ]] && enviado=$_DBX_TRANSFER_TAMANHO_INICIAL
  if [[ $correto =~ ^[0-9]{1,18}$ ]] && ((10#$correto <= enviado)); then
    return 0
  fi
  _dbx_transfer_exibir "$correto"
  _dbx_transfer_falhar nao_concluida \
    "deslocamento informado pelo servico recusado: $_DBX_TRANSFER_EXIBIDO; o valido e um inteiro entre 0 e $enviado, o que ja foi confirmado do arquivo de $_DBX_TRANSFER_TAMANHO_INICIAL bytes; nada foi publicado no destino"
}

# _dbx_transfer_reposicionar <bloco> <deslocamento> — reabre a origem e descarta
# os primeiros <deslocamento> bytes, uma parte por vez.
#
# Por parte, e nao de uma vez, para a ocupacao continuar a de um bloco (RF-31).
# Cada fatia e CONTADA: um arquivo que encolheu entre o inicio e a retomada
# faria a releitura comecar no lugar errado sem que nada parecesse falhar.
_dbx_transfer_reposicionar() {
  local bloco=$1 restante=$2 fatia lido nova
  exec {nova}<"$_DBX_TRANSFER_ORIGEM" || {
    _dbx_transfer_falhar nao_concluida \
      'a origem nao pode ser reaberta para a retomada; nada foi publicado no destino'
    return $?
  }
  while [[ $restante -gt 0 ]]; do
    fatia=$DBX_TRANSFER_TAMANHO_PARTE
    [[ $restante -lt $fatia ]] && fatia=$restante
    lido=''
    head -c "$fatia" <&"$nova" >"$bloco" && lido=$(wc -c <"$bloco")
    lido=${lido//[^0-9]/}
    if [[ -z $lido || $lido -ne $fatia ]]; then
      exec {nova}<&-
      _dbx_transfer_falhar nao_concluida \
        'a origem terminou antes do deslocamento da retomada; o arquivo mudou durante o envio e nada foi publicado no destino'
      return $?
    fi
    restante=$((restante - lido))
  done
  [[ $_DBX_TRANSFER_FONTE -ne 0 ]] && exec {_DBX_TRANSFER_FONTE}<&-
  _DBX_TRANSFER_FONTE=$nova
  return 0
}

# _dbx_transfer_conferir_tamanho <lidos> — arquivo que muda de tamanho durante o
# envio e recusado (decisao do Tech Lead): o tamanho de agora e o total lido tem
# de ser os do inicio. Sem origem posicionavel nao ha o que conferir.
_dbx_transfer_conferir_tamanho() {
  local lidos=$1
  [[ -n $_DBX_TRANSFER_ORIGEM ]] || return 0
  if dbx_transfer_tamanho_de_arquivo "$_DBX_TRANSFER_ORIGEM" &&
    [[ $DBX_TRANSFER_TAMANHO -eq $_DBX_TRANSFER_TAMANHO_INICIAL &&
      $lidos -eq $_DBX_TRANSFER_TAMANHO_INICIAL ]]; then
    return 0
  fi
  _dbx_transfer_falhar nao_concluida \
    "o arquivo mudou de tamanho durante o envio: tinha $_DBX_TRANSFER_TAMANHO_INICIAL bytes no inicio e foram lidos $lidos; nada foi publicado no destino"
}

# ---------------------------------------------------------------------------
# Sessao
# ---------------------------------------------------------------------------

# dbx_transfer_sessao <argumento_de_commit> — le a ENTRADA PADRAO e publica.
#
# Ha um unico laco de sessao, e ele nao sabe de onde vem o fluxo: para a entrada
# padrao o chamador nao redireciona nada, e para arquivo local acima do teto o
# chamador redireciona a entrada do arquivo. Um laco so, para uma correcao de
# deslocamento nunca valer para um lado so.
#
# O `argumento_de_commit` chega PRONTO do comando: e o mesmo objeto que a
# requisicao unica envia a `files/upload`. Monta-lo aqui criaria a segunda copia
# da regra de publicacao.
#
# `origem`, opcional, e o caminho do ARQUIVO REGULAR que o chamador redirecionou
# para a entrada padrao. So com ele a sessao retoma diante de `incorrect_offset`
# (RF-58); a entrada padrao e qualquer origem nao posicionavel seguem sem
# retomada.
dbx_transfer_sessao() {
  local commit=${1-} origem=${2-} estado

  [[ -n $commit ]] || {
    _dbx_transfer_falhar uso_invalido 'envio em partes sem objeto de publicacao'
    return $?
  }

  # RF-15, SEGUNDA LINHA DE DEFESA. O gate de simulacao vive no comando, ANTES
  # da bifurcacao entre requisicao unica e sessao; esta guarda falha fechada
  # para um chamador que o esqueca.
  [[ ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]] || {
    _dbx_transfer_falhar uso_invalido \
      'sessao em partes alcancada em modo de simulacao: nenhuma escrita e emitida'
    return $?
  }

  # shellcheck disable=SC2034
  # Justificativa: classe da taxonomia, lida por `commands/upload` para redigir
  # o diagnostico e escolher o codigo de saida.
  DBX_TRANSFER_CLASSE=''
  # shellcheck disable=SC2034
  # Justificativa: motivo ja redigido, lido por `commands/upload`.
  DBX_TRANSFER_MOTIVO=''
  DBX_TRANSFER_CONTENT_HASH=''
  # shellcheck disable=SC2034
  # Justificativa: total de bytes, publicado na saida do comando (RF-31).
  DBX_TRANSFER_BYTES=0
  # shellcheck disable=SC2034
  # Justificativa: veredito de integridade, publicado na saida do comando.
  DBX_TRANSFER_INTEGRIDADE='nao_aplicavel'

  _DBX_TRANSFER_ORIGEM=''
  _DBX_TRANSFER_TAMANHO_INICIAL=0
  _DBX_TRANSFER_FONTE=0
  _DBX_TRANSFER_RETOMAR_EM=''
  if [[ -n $origem && -f $origem ]]; then
    dbx_transfer_tamanho_de_arquivo "$origem" || {
      _dbx_transfer_falhar nao_encontrado "tamanho do arquivo local indeterminado: $origem"
      return $?
    }
    _DBX_TRANSFER_ORIGEM=$origem
    _DBX_TRANSFER_TAMANHO_INICIAL=$DBX_TRANSFER_TAMANHO
  fi

  # `umask` SALVA E RESTAURADA, e nao apenas endurecida: a mascara e estado do
  # PROCESSO, e deixa-la em 077 alteraria a permissao de tudo que o chamador
  # criar depois. Mesmo par salvar/restaurar de `lib/config.sh`.
  local mascara_anterior
  mascara_anterior=$(umask)
  umask 077
  # Area temporaria indisponivel e problema do HOST, e nao recurso remoto
  # ausente: classificar como `nao_encontrado` mandaria investigar a Dropbox por
  # falha de disco local.
  dbx_tmp_area transfer || {
    umask "$mascara_anterior"
    _dbx_transfer_falhar configuracao 'area temporaria indisponivel para o envio em partes'
    return $?
  }
  DBX_TRANSFER_AREA_TEMP=$DBX_TMP_CAMINHO

  # Ponto UNICO de limpeza no caminho normal: o corpo da sessao pode sair por
  # muitas portas, e uma limpeza por porta seria a forma de esquecer uma.
  _dbx_transfer_conduzir "$commit"
  estado=$?
  # O descritor da releitura e estado do processo emprestado pela sessao.
  [[ $_DBX_TRANSFER_FONTE -ne 0 ]] && exec {_DBX_TRANSFER_FONTE}<&-
  _DBX_TRANSFER_FONTE=0
  _DBX_TRANSFER_ORIGEM=''
  _dbx_transfer_remover_area
  # A mascara e estado do processo emprestado pela sessao, e a sessao a devolve.
  umask "$mascara_anterior"
  return $estado
}

_dbx_transfer_conduzir() {
  local commit=$1
  local bloco="$DBX_TRANSFER_AREA_TEMP/parte"
  local sessao deslocamento=0 tamanho=0 argumento remoto parte=1
  local retomadas=0 maior_confirmado=0 resumo_pelo_arquivo='nao'

  : >"$bloco" || {
    _dbx_transfer_falhar configuracao 'area temporaria nao gravavel'
    return $?
  }

  dbx_hash_acumular_iniciar || {
    _dbx_transfer_falhar configuracao 'utilitario de resumo SHA-256 indisponivel'
    return $?
  }

  # Inicio com corpo VAZIO. Em sessao sequencial e permitido mandar dado ja no
  # inicio, mas nao mandar mantem UMA forma de enviar parte — a do `append` — em
  # vez de duas, e a regra de deslocamento fica com um dono so.
  _dbx_transfer_emitir "$DBX_TRANSFER_URL_INICIAR" '{"close":false}' "$bloco" nao || {
    _dbx_transfer_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
      "inicio de sessao recusado: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return $?
  }
  _dbx_transfer_ler_campo session_id || {
    _dbx_transfer_falhar erro_remoto 'inicio de sessao sem identificador de sessao'
    return $?
  }
  dbx_json_escapar_cadeia "$DBX_TRANSFER_LIDO"
  sessao=$DBX_JSON_ESCAPADO
  # Canal publico ALHEIO, esvaziado por quem o encheu, mesmo sem segredo: a
  # disciplina e "quem enche o canal de outro componente o esvazia".
  # shellcheck disable=SC2034  # canal publico alheio, limpo por quem o encheu
  DBX_JSON_ESCAPADO=''

  while :; do
    # Sem cano: o status abaixo e o do proprio leitor. Falha de leitura aborta a
    # sessao ANTES de qualquer `finish`, e portanto nada e publicado.
    head -c "$DBX_TRANSFER_TAMANHO_PARTE" <&"$_DBX_TRANSFER_FONTE" >"$bloco" || {
      _dbx_transfer_falhar nao_concluida \
        "falha ao ler a origem no deslocamento $deslocamento; nada foi publicado no destino"
      return $?
    }
    tamanho=$(wc -c <"$bloco") || {
      _dbx_transfer_falhar nao_concluida 'tamanho do bloco lido indeterminado'
      return $?
    }
    tamanho=${tamanho//[^0-9]/}
    [[ -n $tamanho ]] || {
      _dbx_transfer_falhar nao_concluida 'tamanho do bloco lido indeterminado'
      return $?
    }

    # Depois de uma retomada as partes deixam de coincidir com os blocos do
    # resumo (RF-58(f)); o resumo passa a ser o do arquivo, no fim.
    if [[ $tamanho -gt 0 && $resumo_pelo_arquivo == 'nao' ]]; then
      dbx_hash_acumular_bloco "$bloco" || {
        _dbx_transfer_falhar nao_concluida \
          "resumo do bloco no deslocamento $deslocamento nao pode ser calculado"
        return $?
      }
    fi

    # Leitura curta so ocorre no fim da entrada: este e o ultimo bloco e ele vai
    # no `finish`, mesmo quando tem zero bytes.
    [[ $tamanho -lt $DBX_TRANSFER_TAMANHO_PARTE ]] && break

    _DBX_TRANSFER_RETOMAR_EM=''
    _dbx_transfer_anexar "$sessao" "$deslocamento" "$tamanho" "$bloco" || return $?
    if [[ -n $_DBX_TRANSFER_RETOMAR_EM ]]; then
      # RF-58: cada retomada consome uma das tentativas (decisao do Tech Lead),
      # o que limita o laco mesmo diante de um servico que recusa sempre.
      retomadas=$((retomadas + 1))
      if [[ $retomadas -ge ${DBX_HTTP_EFETIVO[DBX_HTTP_TENTATIVAS_MAXIMAS]} ]]; then
        _dbx_transfer_falhar nao_concluida \
          "deslocamento incorreto repetido: esgotadas as ${DBX_HTTP_EFETIVO[DBX_HTTP_TENTATIVAS_MAXIMAS]} tentativas na parte que comeca em $deslocamento; nada foi publicado no destino"
        return $?
      fi
      _dbx_transfer_reposicionar "$bloco" "$_DBX_TRANSFER_RETOMAR_EM" || return $?
      deslocamento=$_DBX_TRANSFER_RETOMAR_EM
      _DBX_TRANSFER_RETOMAR_EM=''
      resumo_pelo_arquivo='sim'
      continue
    fi
    deslocamento=$((deslocamento + tamanho))
    # As tentativas sao DA PARTE (RF-09, RF-58(e)). O contador zera
    # so quando o confirmado passa do maior ja visto: um servico que manda
    # voltar e depois aceita de novo o mesmo trecho nao renova as tentativas, e
    # o laco continua limitado.
    if [[ $deslocamento -gt $maior_confirmado ]]; then
      maior_confirmado=$deslocamento
      retomadas=0
    fi
    dbx_progress_transferencia 'upload' "$deslocamento" "${DBX_TRANSFER_TAMANHO:-0}" "parte $parte enviada"
    parte=$((parte + 1))
  done

  local str_total_sessao='' str_barra_concluida=''
  dbx_progress_formatar_bytes "$((deslocamento + tamanho))" str_total_sessao
  dbx_progress_barra_gerar 100 20 str_barra_concluida
  dbx_progress_mensagem "[upload] concluindo sessao em partes ($str_total_sessao)... $str_barra_concluida (100%)"

  _dbx_transfer_conferir_tamanho "$((deslocamento + tamanho))" || return $?

  argumento="{\"cursor\":{\"session_id\":\"$sessao\",\"offset\":$deslocamento},\"commit\":$commit}"
  _dbx_transfer_emitir "$DBX_TRANSFER_URL_CONCLUIR" "$argumento" "$bloco" nao || {
    _dbx_transfer_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
      "conclusao da sessao recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return $?
  }
  # shellcheck disable=SC2034
  # Justificativa: total de bytes lidos da origem, publicado pelo comando (RF-31).
  DBX_TRANSFER_BYTES=$((deslocamento + tamanho))

  # O bloco ja foi enviado: o arquivo vira area de trabalho da cadeia de
  # resumos. Reaproveitar em vez de criar um segundo arquivo e o que mantem o
  # teto de ocupacao.
  if [[ $resumo_pelo_arquivo == 'sim' ]]; then
    # O bloco ja enviado e esvaziado antes: o calculo sobre o arquivo usa area
    # propria, e os dois juntos passariam do teto de um bloco (RF-31).
    : >"$bloco"
    dbx_hash_publicar_arquivo "$_DBX_TRANSFER_ORIGEM" || {
      _dbx_transfer_falhar integridade \
        'o resumo local do arquivo enviado nao pode ser calculado; a integridade nao foi conferida'
      return $?
    }
  else
    dbx_hash_acumular_encerrar "$bloco" || {
      _dbx_transfer_falhar integridade \
        'o resumo local do conteudo enviado nao pode ser calculado; a integridade nao foi conferida'
      return $?
    }
  fi
  DBX_TRANSFER_CONTENT_HASH=$DBX_HASH_RESULTADO

  if _dbx_transfer_ler_campo content_hash; then
    remoto=$DBX_TRANSFER_LIDO
    if dbx_hash_iguais "$DBX_TRANSFER_CONTENT_HASH" "$remoto"; then
      DBX_TRANSFER_INTEGRIDADE='conferida'
    else
      # O arquivo EXISTE no destino: o `finish` retornou. O que nao se pode
      # fazer e chamar isto de sucesso — quem consome a saida decidiria manter
      # um arquivo que nao confere.
      {
        _dbx_transfer_falhar integridade \
          'o resumo devolvido pelo servico nao confere com o resumo do conteudo enviado; nao considere o item integro'
        return $?
      }
    fi
  else
    # Sem resumo publicado pelo servico a verificacao NAO ocorreu. Afirmar
    # conferencia que nao houve e pior que nao conferir.
    # shellcheck disable=SC2034
    # Justificativa: veredito publicado pelo comando; sem leitor neste arquivo.
    DBX_TRANSFER_INTEGRIDADE='nao_aplicavel'
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Envio de arquivo local: objeto de publicacao e roteamento (RF-57)
# ---------------------------------------------------------------------------

# shellcheck disable=SC2034
# Justificativa: objeto de publicacao montado, lido por quem envia.
DBX_TRANSFER_COMMIT=''
# shellcheck disable=SC2034
# Justificativa: `sim` quando o ultimo envio de arquivo foi por sessao.
DBX_TRANSFER_POR_SESSAO='nao'

# dbx_transfer_objeto_de_publicacao <remoto> <modo> <rev> <origem> [mute]
#
# UNICO lugar que monta o objeto de publicacao, para `upload` e para `sync`.
# Resultado em DBX_TRANSFER_COMMIT. Um lugar so, para o metadado (`mode`,
# `client_modified`) nunca diferir conforme o comando.
#
# Com `rev`, o modo e `update` sobre ele (RF-49): alteracao remota entre a
# leitura e o envio vira conflito, e nao sobrescrita do que mudou.
#
# RNF-27 — `client_modified` a partir do `mtime` local, para que o que esta
# aplicacao enviou tenha carimbo da mesma origem de relogio nos dois lados; o
# servico nao o recalcula depois. Fluxo pela entrada padrao nao tem `mtime` e
# sai sem o carimbo, em vez de um inventado com o horario da execucao.
#
# `mute` e do chamador: o `upload` de um arquivo notifica os dispositivos do
# usuario, o `sync` de uma arvore nao, para nao gerar uma notificacao por item.
dbx_transfer_objeto_de_publicacao() {
  local remoto=$1 modo=$2 rev=$3 origem=$4 mute=${5:-false} carimbo='' mtime=''
  [[ $mute == 'true' ]] || mute='false'

  # `stat` devolve so digitos e o carimbo e formatado pelo proprio shell, em UTC
  # local a funcao: capturar `date` seria captura fora do alfabeto fechado
  # (RNF-24). `TZ` precisa ser EXPORTADA: o shell so reaplica o fuso quando a
  # variavel esta no ambiente, e sem `-x` o carimbo sairia na hora local.
  if [[ $origem != '-' ]] && mtime=$(stat -c %Y -- "$origem" 2>/dev/null) &&
    [[ $mtime =~ ^[0-9]+$ ]]; then
    local -x TZ=UTC
    printf -v carimbo '%(%Y-%m-%dT%H:%M:%SZ)T' "$mtime"
  fi

  dbx_json_escapar_cadeia "$remoto"
  DBX_TRANSFER_COMMIT="{\"path\":\"$DBX_JSON_ESCAPADO\",\"mode\":"
  if [[ -n $rev ]]; then
    dbx_json_escapar_cadeia "$rev"
    DBX_TRANSFER_COMMIT+="{\".tag\":\"update\",\"update\":\"$DBX_JSON_ESCAPADO\"}"
  else
    DBX_TRANSFER_COMMIT+="\"$modo\""
  fi
  if [[ -n $carimbo ]]; then
    dbx_json_escapar_cadeia "$carimbo"
    DBX_TRANSFER_COMMIT+=",\"client_modified\":\"$DBX_JSON_ESCAPADO\""
  fi
  DBX_TRANSFER_COMMIT+=",\"autorename\":false,\"mute\":$mute}"
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  return 0
}

# dbx_transfer_enviar_arquivo <origem> <objeto_de_publicacao> [rotulo]
#
# UNICO ponto de escolha entre requisicao unica e sessao para arquivo local,
# usado por `upload` e por `sync` (RF-08, RF-57). O tamanho e MEDIDO aqui; a
# forma `&&` do predicado so e segura porque a medicao ja recusou o que nao
# fosse numero — sem isso um status de uso cairia em "nao precisa de sessao".
#
# Falha publica DBX_TRANSFER_CLASSE e DBX_TRANSFER_MOTIVO nos dois caminhos; o
# corpo da resposta de sucesso fica em DBX_HTTP_CORPO para quem o le.
dbx_transfer_enviar_arquivo() {
  local origem=${1-} commit=${2-} rotulo=${3:-envio} str_tam='' str_barra=''
  DBX_TRANSFER_POR_SESSAO='nao'
  # shellcheck disable=SC2034  # canais publicos, lidos pelos comandos
  DBX_TRANSFER_CLASSE=''
  # shellcheck disable=SC2034
  DBX_TRANSFER_MOTIVO=''

  [[ -n $commit ]] || {
    _dbx_transfer_falhar uso_invalido 'envio de arquivo sem objeto de publicacao'
    return $?
  }
  # RF-15, segunda linha de defesa, pelo mesmo motivo da sessao.
  [[ ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]] || {
    _dbx_transfer_falhar uso_invalido \
      'envio de arquivo alcancado em modo de simulacao: nenhuma escrita e emitida'
    return $?
  }
  dbx_transfer_tamanho_de_arquivo "$origem" || {
    _dbx_transfer_falhar nao_encontrado "tamanho do arquivo local indeterminado: $origem"
    return $?
  }

  if dbx_transfer_precisa_de_sessao "$DBX_TRANSFER_TAMANHO"; then
    # shellcheck disable=SC2034  # canal publico, lido por commands/upload
    DBX_TRANSFER_POR_SESSAO='sim'
    # shellcheck disable=SC2094  # `origem` e so lida: o nome viaja para a retomada
    dbx_transfer_sessao "$commit" "$origem" <"$origem"
    return $?
  fi

  dbx_progress_barra_gerar 0 20 str_barra
  dbx_progress_formatar_bytes "$DBX_TRANSFER_TAMANHO" str_tam
  dbx_progress_mensagem "[$rotulo] enviando arquivo ($str_tam) via requisicao unica... $str_barra (0%)"
  dbx_auth_conteudo POST 'https://content.dropboxapi.com/2/files/upload' \
    "$commit" "$origem" nao && return 0
  _dbx_transfer_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
    "envio recusado: ${DBX_HTTP_RESUMO_DE_ERRO:-sem detalhe}"
}
