#!/usr/bin/env bash
# lib/http.sh — ponto UNICO de saida de rede.
#
# Camada: adaptadores. Depende de lib/errors.sh (dominio) e de lib/json.sh.
#
# Concentrar toda a rede aqui e o que permite auditar num so lugar a circulacao
# do segredo, a politica de retentativa e o mapeamento de erro. Ha caso de teste
# que reprova se qualquer outro componente invocar o cliente.
#
# CONTRATO EXIGIDO DO CLIENTE HTTP, declarado porque a suite o substitui:
#   -K -            le opcoes da entrada padrao (e por onde o segredo passa)
#   -o <arquivo>    grava o corpo da resposta
#   -D <arquivo>    grava os cabecalhos da resposta
#   -w '%{http_code}'  imprime o codigo HTTP na saida padrao
#   --data-binary @<arquivo>  envia o corpo a partir de arquivo
#   status de saida diferente de zero quando NAO houve resposta HTTP
# Qualquer substituto de teste precisa honrar exatamente isto; divergir faria a
# suite validar uma ficcao.
#
# RNF-03 — o segredo NUNCA vai em argv. Ele viaja pela entrada padrao, em
# arquivo de opcoes lido pelo cliente, porque a tabela de processos e legivel
# por qualquer usuario do host. O corpo da requisicao vai por arquivo
# temporario, justamente para deixar a entrada padrao livre para o segredo.
#
# RSK-23 — `lib/http` nao persiste nada: nenhum cursor e guardado "para
# retomar", porque a camada de adaptadores e onde esse cache pareceria
# inofensivo. Todo estado persistente do projeto passa so por `lib/state`
# (RF-38, RF-61, RNF-26).

[[ -n ${DBX_HTTP_CARREGADO:-} ]] && return 0
DBX_HTTP_CARREGADO=1

_dbx_http_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_http_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_http_diretorio=.
_dbx_http_diretorio=$(cd -P -- "$_dbx_http_diretorio" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_http_diretorio/errors.sh"
# shellcheck source=lib/debug.sh
. "$_dbx_http_diretorio/debug.sh"
# shellcheck source=lib/json.sh
. "$_dbx_http_diretorio/json.sh"
# shellcheck source=lib/progress.sh
. "$_dbx_http_diretorio/progress.sh"
# shellcheck source=lib/tmp.sh
. "$_dbx_http_diretorio/tmp.sh"
unset _dbx_http_diretorio

DBX_HTTP_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_HTTP_ERRO_REDE=$(dbx_errors_codigo_saida rede)
readonly DBX_HTTP_ERRO_USO DBX_HTTP_ERRO_REDE

# RNF-23: teto de itens por pagina, para a pagina caber com folga no teto de
# entrada de `lib/json` (256 KiB).
readonly DBX_HTTP_LIMITE_MAXIMO=100
# Piso da reducao: abaixo disto, insistir nao ajuda e a falha precisa aparecer.
readonly DBX_HTTP_LIMITE_MINIMO=5
# Teto do valor de cabecalho: uma ordem de grandeza abaixo do ponto em que o
# cliente passa a truncar sem aviso, e com folga para um caminho remoto
# codificado em JSON.
readonly DBX_HTTP_LIMITE_CABECALHO=8192

# ---------------------------------------------------------------------------
# AJUSTES POR AMBIENTE (RNF-07, RNF-30, RF-09)
# ---------------------------------------------------------------------------
# Padroes decididos pelo solicitante: 5 tentativas contando a primeira, recuo com
# base de 1 s e teto de 60 s por espera, `Retry-After` limitado a 300 s, conexao
# em 15 s e corte abaixo de 1 KB/s por 60 s. Cada um pode ser trocado pela
# variavel de mesmo nome sem o sufixo `_PADRAO`.
#
# Lidos A CADA requisicao, e nao na carga: o ambiente da chamada e o que vale, e
# a suite ajusta por atribuicao no proprio comando.
readonly DBX_HTTP_TENTATIVAS_MAXIMAS_PADRAO=5
readonly DBX_HTTP_ESPERA_BASE_MS_PADRAO=1000
readonly DBX_HTTP_ESPERA_TETO_MS_PADRAO=60000
readonly DBX_HTTP_RETRY_AFTER_TETO_S_PADRAO=300
readonly DBX_HTTP_CONNECT_TIMEOUT_S_PADRAO=15
readonly DBX_HTTP_VELOCIDADE_MINIMA_BPS_PADRAO=1024
readonly DBX_HTTP_VELOCIDADE_JANELA_S_PADRAO=60
readonly DBX_HTTP_AJUSTES='DBX_HTTP_TENTATIVAS_MAXIMAS DBX_HTTP_ESPERA_BASE_MS
  DBX_HTTP_ESPERA_TETO_MS DBX_HTTP_RETRY_AFTER_TETO_S DBX_HTTP_CONNECT_TIMEOUT_S
  DBX_HTTP_VELOCIDADE_MINIMA_BPS DBX_HTTP_VELOCIDADE_JANELA_S'

# Valores em vigor, publicados pela ultima validacao. Canal publico: `lib/transfer`
# le daqui o limite de tentativas que cada retomada consome (RF-58).
declare -gA DBX_HTTP_EFETIVO=(
  [DBX_HTTP_TENTATIVAS_MAXIMAS]=$DBX_HTTP_TENTATIVAS_MAXIMAS_PADRAO
  [DBX_HTTP_ESPERA_BASE_MS]=$DBX_HTTP_ESPERA_BASE_MS_PADRAO
  [DBX_HTTP_ESPERA_TETO_MS]=$DBX_HTTP_ESPERA_TETO_MS_PADRAO
  [DBX_HTTP_RETRY_AFTER_TETO_S]=$DBX_HTTP_RETRY_AFTER_TETO_S_PADRAO
  [DBX_HTTP_CONNECT_TIMEOUT_S]=$DBX_HTTP_CONNECT_TIMEOUT_S_PADRAO
  [DBX_HTTP_VELOCIDADE_MINIMA_BPS]=$DBX_HTTP_VELOCIDADE_MINIMA_BPS_PADRAO
  [DBX_HTTP_VELOCIDADE_JANELA_S]=$DBX_HTTP_VELOCIDADE_JANELA_S_PADRAO
)
# Motivo da ultima recusa de ajuste: nomeia a variavel e o valor. Canal publico,
# lido por `bin/dbx` para o diagnostico.
DBX_HTTP_MOTIVO_AMBIENTE=''

# Modo de autorizacao da chamada corrente e nome do vetor de campos do modo
# formulario. Internos: nao fazem parte do contrato publico do componente.
_DBX_HTTP_MODO='bearer'
# Canal do corpo da chamada corrente. Interno.
_DBX_HTTP_CANAL='padrao'
_DBX_HTTP_DESTINO=''
_DBX_HTTP_ARG=''
_DBX_HTTP_ARQUIVO_CORPO=''
_DBX_HTTP_TOKEN=''
_DBX_HTTP_CAMPOS_NOME=''
# Limite de banda das requisicoes de CONTEUDO (RF-82(d)(e)), inteiro de bytes
# por segundo, ou vazio. Interno, iniciado aqui para o ambiente nao o trazer:
# so `dbx_http_limite_banda` o escreve.
_DBX_HTTP_LIMITE_BANDA=''
# Fase 7a (RF-104(c)(d)): deslocamento do recebimento retomado (`continue-at`
# do cliente, que pede `Range: bytes=N-` e anexa ao destino). Vazio fora dele.
_DBX_HTTP_FAIXA_INICIO=''
_DBX_HTTP_FAIXA_FIM=''
# `sim` quando o cliente recusou a resposta a um pedido de faixa (status 33:
# `200` no lugar de `206`, ou `206` com inicio diferente) SEM escrever o corpo.
# shellcheck disable=SC2034  # canal publico, lido por lib/cmd
DBX_HTTP_FAIXA_IGNORADA='nao'
# `Content-Range` da ultima resposta (aparado, no maximo 128 bytes).
# shellcheck disable=SC2034  # canal publico, lido por lib/cmd
DBX_HTTP_FAIXA_CABECALHO=''

# Status do cliente que denuncia defeito NOSSO, e nao da rede; e a mensagem que
# o cliente emitiu, ja redigida. Canais publicos.
DBX_HTTP_DEFEITO_CLIENTE=''
DBX_HTTP_DIAGNOSTICO=''

# shellcheck disable=SC2034  # canais publicos, lidos pelo chamador e pela suite
# Motivo da ultima recusa de cabecalho. Descreve a CAUSA, nunca o valor: ecoar o
# valor levaria o proprio terminador para dentro do registro, transportando o
# vetor do ponto onde foi barrado ate o log.
DBX_HTTP_MOTIVO_CABECALHO=''
# shellcheck disable=SC2034
DBX_HTTP_CODIGO=''
# shellcheck disable=SC2034
DBX_HTTP_CORPO=''
# shellcheck disable=SC2034
DBX_HTTP_RESUMO_DE_ERRO=''
# shellcheck disable=SC2034
DBX_HTTP_CLASSE=''
# shellcheck disable=SC2034
DBX_HTTP_POLITICA=''
# shellcheck disable=SC2034
DBX_HTTP_CORRELACAO=''
# shellcheck disable=SC2034
# Valor cru do `Retry-After` da ultima resposta; quem o valida e a espera.
DBX_HTTP_RETRY_AFTER=''
# shellcheck disable=SC2034
# Valor do cabecalho `Date` da ultima resposta, aparado e sem CR (DIV-134, fase
# 6): o `reter --dias` confere o relogio local contra ele. Quem o valida e o
# consumidor; aqui so se le, como o `Retry-After`.
DBX_HTTP_DATA=''
# shellcheck disable=SC2034
# `error_summary` da ultima resposta, SO quando veio do JSON do servico. O
# `DBX_HTTP_RESUMO_DE_ERRO` cai na primeira linha do corpo quando ele nao e JSON,
# e corpo bruto nao pode ir para relatorio por item (RF-59(c)).
DBX_HTTP_RESUMO_DO_SERVICO=''
# shellcheck disable=SC2034
# Quantas requisicoes este processo ja conduziu. Quem precisa saber se os canais
# acima descrevem uma operacao SUA compara o valor antes e depois dela (RF-59).
DBX_HTTP_REQUISICOES=0

# shellcheck disable=SC2034
# Quantas respostas `429` este processo observou (RF-135(d)). O `sync` com
# `--paralelo` soma as dos auxiliares ao resumo de `--debug`; nao ha estado
# entre execucoes.
DBX_HTTP_LIMITES_429=0

# shellcheck disable=SC2034
# Corpo do cabecalho `Dropbox-API-Result`, que o modo de conteudo usa para
# devolver metadado quando o corpo da resposta e o proprio arquivo.
DBX_HTTP_RESULTADO_CABECALHO=''

_dbx_http_limpar() {
  DBX_HTTP_CODIGO=''
  DBX_HTTP_CORPO=''
  DBX_HTTP_RESUMO_DE_ERRO=''
  DBX_HTTP_RESUMO_DO_SERVICO=''
  DBX_HTTP_CLASSE=''
  DBX_HTTP_POLITICA=''
  DBX_HTTP_CORRELACAO=''
}

# dbx_http_validar_ambiente — confere os ajustes e publica os valores em vigor.
#
# RNF-07(e), RNF-30(c): valor invalido e RECUSADO como uso invalido, nunca
# ignorado nem trocado pelo padrao. Valido e inteiro positivo, sem zero a
# esquerda — a aritmetica do shell leria `010` como octal e `08` como erro — e
# com no maximo nove digitos, para nenhuma conta derivada transbordar.
# Variavel AUSENTE vale o padrao; variavel presente e vazia e invalida.
dbx_http_validar_ambiente() {
  local nome padrao valor exibido
  DBX_HTTP_MOTIVO_AMBIENTE=''
  for nome in $DBX_HTTP_AJUSTES; do
    padrao=${nome}_PADRAO
    valor=${!nome-${!padrao}}
    if [[ ! $valor =~ ^[1-9][0-9]{0,8}$ ]]; then
      # O valor vai para o diagnostico: byte de controle sairia como segunda
      # linha, entao ele e citado em vez de ecoado.
      exibido=${valor:0:64}
      [[ $exibido == *[$'\001'-$'\037\177']* ]] && printf -v exibido '%q' "$exibido"
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      printf -v DBX_HTTP_MOTIVO_AMBIENTE \
        'variavel de ambiente %s invalida: [%s]; use inteiro positivo, sem zero a esquerda' \
        "$nome" "$exibido"
      return "$DBX_HTTP_ERRO_USO"
    fi
    DBX_HTTP_EFETIVO[$nome]=$valor
  done
  return 0
}


# _dbx_http_retry_after_efetivo — publica em _DBX_HTTP_RETRY_AFTER_S o
# `Retry-After` valido apos o teto (vazio quando ausente ou invalido).
_dbx_http_retry_after_efetivo() {
  local teto_servidor=${DBX_HTTP_EFETIVO[DBX_HTTP_RETRY_AFTER_TETO_S]}
  _DBX_HTTP_RETRY_AFTER_S=''
  [[ $DBX_HTTP_RETRY_AFTER =~ ^[0-9]+$ ]] || return 0
  # Inteiro grande demais para a aritmetica ainda e inteiro valido: vale o teto.
  if ((${#DBX_HTTP_RETRY_AFTER} > 9 || 10#$DBX_HTTP_RETRY_AFTER > teto_servidor)); then
    _DBX_HTTP_RETRY_AFTER_S=$teto_servidor
  else
    _DBX_HTTP_RETRY_AFTER_S=$((10#$DBX_HTTP_RETRY_AFTER))
  fi
}

# _dbx_http_espera_calcular <tentativa> — publica em _DBX_HTTP_ESPERA_MS a
# espera antes da tentativa seguinte (RNF-07), sem dormir.
_dbx_http_espera_calcular() {
  local tentativa=$1 milissegundos indice
  local base=${DBX_HTTP_EFETIVO[DBX_HTTP_ESPERA_BASE_MS]}
  local teto=${DBX_HTTP_EFETIVO[DBX_HTTP_ESPERA_TETO_MS]}

  _dbx_http_retry_after_efetivo
  if [[ -n $_DBX_HTTP_RETRY_AFTER_S ]]; then
    milissegundos=$((_DBX_HTTP_RETRY_AFTER_S * 1000))
  else
    # Dobra ate o expoente ou ate o teto, o que vier antes: o deslocamento
    # direto transbordaria com muitas tentativas.
    milissegundos=$base
    for ((indice = 1; indice < tentativa && milissegundos < teto; indice++)); do
      milissegundos=$((milissegundos * 2))
    done
    # Variacao aleatoria para nao sincronizar varios hosts na mesma janela. Dois
    # sorteios compostos porque um so vai ate 32767, abaixo da base padrao.
    milissegundos=$((milissegundos + ((RANDOM << 15) | RANDOM) % (base + 1)))
    [[ $milissegundos -gt $teto ]] && milissegundos=$teto
  fi
  _DBX_HTTP_ESPERA_MS=$milissegundos
}

# _dbx_http_dormir — dorme a espera calculada. A espera e o `sleep` do sistema,
# chamado por nome: e o que deixa a suite observa-la por um substituto, sem
# dormir (RNF-07(g)).
_dbx_http_dormir() {
  local texto
  printf -v texto '%d.%03d' "$((_DBX_HTTP_ESPERA_MS / 1000))" "$((_DBX_HTTP_ESPERA_MS % 1000))"
  sleep "$texto"
}

# _dbx_http_esperar <tentativa> — espera antes da tentativa seguinte (RNF-07).
#
# O `Retry-After` do servidor PREVALECE, limitado ao seu teto, mesmo acima do
# teto do recuo: e o servico dizendo quando volta. Valido e so o inteiro de
# segundos; a forma de data HTTP cai no recuo (decisao do Tech Lead). Sem ele,
# `base * 2^(n-1)` mais variacao de 0 a `base`, limitado ao teto por espera.
_dbx_http_esperar() {
  _dbx_http_espera_calcular "$1"
  _dbx_http_dormir
}

# _dbx_http_endpoint_debug <url> — publica em _DBX_HTTP_ENDPOINT_DEBUG o host
# mais o caminho fixo da API (DIV-335): sem esquema, userinfo, porta, query nem
# fragmento. Host fora de `dropboxapi.com` sai so como host.
_dbx_http_endpoint_debug() {
  local resto=${1#*://} autoridade caminho=''
  autoridade=${resto%%[/?#]*}
  if [[ $resto == "$autoridade" ]]; then
    caminho=''
  else
    caminho=${resto#"$autoridade"}
    [[ $caminho == /* ]] || caminho=''
    caminho=${caminho%%[?#]*}
  fi
  autoridade=${autoridade##*@}
  autoridade=${autoridade%%:*}
  autoridade=${autoridade,,}
  if [[ $autoridade == dropboxapi.com || $autoridade == *.dropboxapi.com ]]; then
    _DBX_HTTP_ENDPOINT_DEBUG=$autoridade$caminho
  else
    _DBX_HTTP_ENDPOINT_DEBUG=$autoridade
  fi
}

# _dbx_http_debug_preparar <metodo> <url> <tentativa> <codigo> <estado> <medidas>
#
# RF-157: monta, sem escrever, a linha da tentativa em _DBX_HTTP_LINHA_DEBUG
# (vetor). `medidas` e o que o `-w` ampliado devolveu apos o codigo: tempo
# total em segundos, bytes enviados e bytes recebidos; ausente vale zero.
_dbx_http_debug_preparar() {
  local metodo=$1 url=$2 tentativa=$3 codigo=$4 estado=$5 medidas=$6
  local tempo='' enviados='' recebidos='' inteiro fracao duracao_ms=0
  read -r tempo enviados recebidos <<<"$medidas"
  [[ $enviados =~ ^[0-9]+$ ]] || enviados=0
  [[ $recebidos =~ ^[0-9]+$ ]] || recebidos=0
  if [[ $tempo =~ ^([0-9]+)(\.([0-9]*))?$ ]]; then
    inteiro=${BASH_REMATCH[1]}
    fracao=${BASH_REMATCH[3]}000
    duracao_ms=$((10#$inteiro * 1000 + 10#${fracao:0:3}))
  fi
  _dbx_http_endpoint_debug "$url"
  _DBX_HTTP_LINHA_DEBUG=("$metodo" "$_DBX_HTTP_ENDPOINT_DEBUG" "tentativa=$tentativa" "status=$codigo")
  [[ $codigo -eq 0 ]] && _DBX_HTTP_LINHA_DEBUG+=("curl=$estado")
  _DBX_HTTP_LINHA_DEBUG+=("duracao_ms=$duracao_ms" "enviados=$enviados" "recebidos=$recebidos")
  _dbx_http_retry_after_efetivo
  [[ -n $_DBX_HTTP_RETRY_AFTER_S ]] && _DBX_HTTP_LINHA_DEBUG+=("retry_after=$_DBX_HTTP_RETRY_AFTER_S")
  # RF-160(b): requisicao com `Range` leva a faixa pedida.
  [[ -n $_DBX_HTTP_FAIXA_INICIO ]] && _DBX_HTTP_LINHA_DEBUG+=("faixa=$_DBX_HTTP_FAIXA_INICIO-")
  return 0
}

# _dbx_http_debug_emitir [espera_ms] — escreve a linha pendente, uma vez.
_dbx_http_debug_emitir() {
  [[ ${#_DBX_HTTP_LINHA_DEBUG[@]} -gt 0 ]] || return 0
  [[ -n ${1-} ]] && _DBX_HTTP_LINHA_DEBUG+=("espera_ms=$1")
  dbx_debug_linha http "${_DBX_HTTP_LINHA_DEBUG[@]}"
  _DBX_HTTP_LINHA_DEBUG=()
}

# _dbx_http_correlacao_de <arquivo_de_cabecalhos>
#
# O identificador de correlacao e capturado nos DOIS caminhos, sucesso e erro:
# perde-lo apenas no de erro seria a assimetria que RF-30 nao tolera, ja que e
# no erro que ele serve.
#
# Le tambem o `Retry-After` (RNF-07), o `Date` (DIV-134) e o `Dropbox-API-Result`. A leitura
# percorre todos os cabecalhos e nao para no identificador de correlacao, para
# nao perder o que vier depois dele.
_dbx_http_correlacao_de() {
  local arquivo=$1 linha nome valor
  DBX_HTTP_CORRELACAO=''
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_HTTP_RESULTADO_CABECALHO=''
  DBX_HTTP_RETRY_AFTER=''
  DBX_HTTP_DATA=''
  DBX_HTTP_FAIXA_CABECALHO=''
  [[ -r $arquivo ]] || return 0
  while IFS= read -r linha; do
    linha=${linha%$'\r'}
    nome=${linha%%:*}
    [[ $nome == "$linha" ]] && continue
    valor=${linha#*:}
    valor=${valor# }
    case ${nome,,} in
      dropbox-api-result)
        # shellcheck disable=SC2034  # canal publico, ver nota no topo
        DBX_HTTP_RESULTADO_CABECALHO=$valor
        ;;
      x-dropbox-request-id | x-request-id | x-server-response)
        # O primeiro identificador vence.
        # shellcheck disable=SC2034  # canal publico, ver nota no topo
        [[ -n $DBX_HTTP_CORRELACAO ]] || DBX_HTTP_CORRELACAO=$valor
        ;;
      retry-after)
        # So as pontas sao aparadas: espaco INTERNO invalida o valor — `5 0`
        # nao e 50 s — e ele cai no recuo.
        [[ $valor =~ ^[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]] && valor=${BASH_REMATCH[1]}
        DBX_HTTP_RETRY_AFTER=$valor
        ;;
      content-range)
        [[ $valor =~ ^[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]] && valor=${BASH_REMATCH[1]}
        # shellcheck disable=SC2034  # canal publico, lido por lib/cmd
        DBX_HTTP_FAIXA_CABECALHO=${valor:0:128}
        ;;
      date)
        [[ $valor =~ ^[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]] && valor=${BASH_REMATCH[1]}
        # shellcheck disable=SC2034  # canal publico, lido por commands/reter
        DBX_HTTP_DATA=${valor:0:64}
        ;;
    esac
  done <"$arquivo"
  return 0
}

# _dbx_http_interpretar_erro <corpo> — extrai o resumo de erro do corpo.
#
# Interpreta em CONTEXTO NOMEADO proprio: usar o contexto padrao destruiria uma
# listagem em curso, que e precisamente o modo de falha que o contexto nomeado
# existe para impedir. O nome e literal — derivar de tag do erro produziria
# colisao com perda de documento entre duas respostas de mesma tag.
_dbx_http_interpretar_erro() {
  local corpo=$1
  DBX_HTTP_RESUMO_DE_ERRO=''
  DBX_HTTP_RESUMO_DO_SERVICO=''
  [[ -n $corpo ]] || return 0
  dbx_json_contexto http_erro || return 0
  if dbx_json_analisar "$corpo"; then
    if dbx_json_valor error_summary >/dev/null; then
      DBX_HTTP_RESUMO_DE_ERRO=$DBX_JSON_RESULTADO
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_HTTP_RESUMO_DO_SERVICO=$DBX_JSON_RESULTADO
    fi
  else
    local primeira_linha=''
    IFS= read -r primeira_linha <<<"$corpo"
    primeira_linha=${primeira_linha//$'\r'/}
    if [[ -n $primeira_linha ]]; then
      dbx_errors_redigir "$primeira_linha" >/dev/null
      DBX_HTTP_RESUMO_DE_ERRO=${DBX_ERRORS_REDIGIDO:0:120}
    fi
  fi
  dbx_json_descartar http_erro
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  # Um servico que ecoe a requisicao no corpo de erro poe credencial no canal
  # escalar do analisador; o resumo ja foi copiado, e o canal nao precisa reter.
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_RESULTADO=''
  return 0
}

# _dbx_http_opcoes — emite as linhas de configuracao lidas por `curl -K -`.
#
# Tudo que e sensivel sai por AQUI, isto e, pela entrada padrao: nem token nem
# campo de formulario aparecem em `argv`, que e legivel por qualquer processo em
# `/proc/<pid>/cmdline` (RNF-03).
#
# O modo `formulario` existe para a troca de refresh token por token curto: o
# segredo vai em campos `data-urlencode`, tambem pela entrada padrao, e nao por
# arquivo de corpo. Escrever o refresh token em arquivo temporario criaria uma
# janela de credencial em disco que nenhuma permissao elimina — melhor nao
# existir a superficie do que protege-la.
_dbx_http_opcoes() {
  # DIV-293: a barra propria do cURL nunca e repassada; o progresso e o da linha do arquivo.
  printf 'silent\n'
  printf 'show-error\n'
  # RNF-30: sem estes tres, um servidor que aceita a conexao e nao responde
  # prende o processo para sempre. O corte por velocidade cobre tambem a
  # resposta que goteja abaixo do minimo.
  printf 'connect-timeout = %s\n' "${DBX_HTTP_EFETIVO[DBX_HTTP_CONNECT_TIMEOUT_S]}"
  printf 'speed-limit = %s\n' "${DBX_HTTP_EFETIVO[DBX_HTTP_VELOCIDADE_MINIMA_BPS]}"
  printf 'speed-time = %s\n' "${DBX_HTTP_EFETIVO[DBX_HTTP_VELOCIDADE_JANELA_S]}"
  case $_DBX_HTTP_MODO in
    formulario)
      printf 'header = "Content-Type: application/x-www-form-urlencoded"\n'
      local -n _campos=$_DBX_HTTP_CAMPOS_NOME
      local campo escapado
      for campo in "${_campos[@]}"; do
        escapado=${campo//\\/\\\\}
        escapado=${escapado//\"/\\\"}
        printf 'data-urlencode = "%s"\n' "$escapado"
      done
      ;;
    conteudo)
      printf 'header = "Authorization: Bearer %s"\n' "$_DBX_HTTP_TOKEN"
      printf 'header = "Content-Type: application/octet-stream"\n'
      # O valor vai dentro de cadeia entre aspas no arquivo de configuracao: uma
      # aspa crua ENCERRARIA a cadeia e o resto do JSON seria descartado em
      # silencio. Mesmo escape do modo formulario.
      local _arg_escapado=${_DBX_HTTP_ARG//\\/\\\\}
      _arg_escapado=${_arg_escapado//\"/\\\"}
      printf 'header = "Dropbox-API-Arg: %s"\n' "$_arg_escapado"
      # RF-82(e)(f): so o conteudo, por requisicao — cada parte de sessao e cada
      # retentativa passam por aqui. Metadado e controle ficam sem limite.
      if [[ -n $_DBX_HTTP_LIMITE_BANDA ]]; then
        printf 'limit-rate = %s\n' "$_DBX_HTTP_LIMITE_BANDA"
      fi
      # RF-104(c): o cliente pede `Range: bytes=N-`, ANEXA ao destino e recusa
      # (status 33, sem escrever) resposta sem `Content-Range` que comece em N.
      if [[ -n $_DBX_HTTP_FAIXA_FIM && $_DBX_HTTP_CANAL == 'fluxo' ]]; then
        # F-100 (RF-180): faixa FECHADA para um arquivo proprio de quem pede. O
        # teto de tamanho faz o cliente recusar (status 63, nada escrito) um
        # `200` com o arquivo inteiro, que de outro modo encheria o destino.
        printf 'range = "%s-%s"\n' "$_DBX_HTTP_FAIXA_INICIO" "$_DBX_HTTP_FAIXA_FIM"
        printf 'max-filesize = %s\n' $((_DBX_HTTP_FAIXA_FIM - _DBX_HTTP_FAIXA_INICIO + 1))
      elif [[ -n $_DBX_HTTP_FAIXA_INICIO && $_DBX_HTTP_CANAL == 'fluxo' ]]; then
        printf 'continue-at = %s\n' "$_DBX_HTTP_FAIXA_INICIO"
      fi
      ;;
    *)
      printf 'header = "Authorization: Bearer %s"\n' "$_DBX_HTTP_TOKEN"
      printf 'header = "Content-Type: application/json"\n'
      ;;
  esac
}

# dbx_http_limite_banda <bytes_por_segundo|vazio> — RF-82(d).
#
# So aceita o INTEIRO ja convertido (`lib/cli`): o texto do operador nunca chega
# a configuracao do cliente nem ao `argv`. Vazio desliga.
dbx_http_limite_banda() {
  [[ ${1-} =~ ^([1-9][0-9]{0,18})?$ ]] || return "$DBX_HTTP_ERRO_USO"
  _DBX_HTTP_LIMITE_BANDA=${1-}
  return 0
}

# dbx_http_cabecalho_valido <valor> — status 0 aceita, uso invalido recusa.
#
# A recusa e NOSSA: o cliente transmite um valor com `\n` ou `\r\n` sem aviso, e
# o servidor le o que vem depois da quebra como cabecalho proprio. Como o valor
# vem de nome de arquivo do usuario, seria injecao de cabecalho HTTP com entrada
# controlada.
#
# Conjunto onde incide: todo valor que va para um cabecalho — hoje o argumento do
# modo de conteudo, e qualquer outro que venha a existir.
dbx_http_cabecalho_valido() {
  local valor=${1-} indice byte
  DBX_HTTP_MOTIVO_CABECALHO=''

  if [[ ${#valor} -gt $DBX_HTTP_LIMITE_CABECALHO ]]; then
    printf -v DBX_HTTP_MOTIVO_CABECALHO \
      'valor de cabecalho excede o teto: %s bytes, maximo %s' \
      "${#valor}" "$DBX_HTTP_LIMITE_CABECALHO"
    return "$DBX_HTTP_ERRO_USO"
  fi

  # Byte de controle de 0x01 a 0x1f, mais 0x7f. O NUL nao entra na faixa porque
  # cadeia de shell nao o carrega — nao e omissao, e impossibilidade do canal.
  if [[ $valor == *[$'\001'-$'\037\177']* ]]; then
    # A posicao e o codigo bastam para diagnosticar. O valor NAO entra no motivo:
    # ele carrega o proprio terminador, e o motivo vai para registro em disco.
    for ((indice = 0; indice < ${#valor}; indice++)); do
      byte=${valor:indice:1}
      if [[ $byte == [$'\001'-$'\037\177'] ]]; then
        printf -v DBX_HTTP_MOTIVO_CABECALHO \
          'byte de controle 0x%02x na posicao %s do valor de cabecalho' \
          "'$byte" "$indice"
        return "$DBX_HTTP_ERRO_USO"
      fi
    done
  fi

  # UTF-8 sobrelongo de CR e LF: sequencia invalida que alguns decodificadores
  # mapeiam de volta para o caractere, contornando a verificacao acima.
  local sobrelongo
  for sobrelongo in $'\300\215' $'\300\212' $'\340\200\215' $'\340\200\212'; do
    if [[ $valor == *"$sobrelongo"* ]]; then
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_HTTP_MOTIVO_CABECALHO='sequencia UTF-8 sobrelonga de terminador no valor de cabecalho'
      return "$DBX_HTTP_ERRO_USO"
    fi
  done

  return 0
}

# dbx_http_conteudo <metodo> <url> <token> <arg_json> <arquivo> <idempotente>
#
# Modo de conteudo da Dropbox: parametros em `Dropbox-API-Arg`, corpo binario.
# A validacao ocorre ANTES de qualquer invocacao do cliente — valor inseguro e
# recusado sem que o cliente chegue a ser chamado.
dbx_http_conteudo() {
  [[ $# -ge 6 ]] || return "$DBX_HTTP_ERRO_USO"
  local metodo=$1 url=$2 token=$3 arg=$4 arquivo=$5 idempotente=$6
  [[ -n $metodo && -n $url && -n $token ]] || return "$DBX_HTTP_ERRO_USO"

  dbx_http_cabecalho_valido "$arg" || return "$DBX_HTTP_ERRO_USO"

  _DBX_HTTP_MODO=conteudo
  _DBX_HTTP_CANAL=padrao
  _DBX_HTTP_TOKEN=$token
  _DBX_HTTP_ARG=$arg
  _DBX_HTTP_ARQUIVO_CORPO=$arquivo
  _DBX_HTTP_DESTINO=''
  _DBX_HTTP_FAIXA_INICIO=''
  _DBX_HTTP_FAIXA_FIM=''
  _dbx_http_executar "$metodo" "$url" '' "$idempotente"
}

# dbx_http_conteudo_receber <metodo> <url> <token> <arg_json> <destino> [inicio]
#
# Com <inicio> maior que zero (fase 7a, RF-104), o pedido e de FAIXA: o cliente
# envia `Range: bytes=<inicio>-` e anexa o corpo ao destino; resposta que nao
# seja `206` comecando em <inicio> nao e escrita (DBX_HTTP_FAIXA_IGNORADA).
#
# Recebimento em fluxo: o corpo vai direto para <destino> — arquivo ou descritor,
# tipicamente `/dev/stdout` — sem materializar copia intermediaria. Nao ha teto de
# tamanho, por decisao de emitir e validar em paralelo.
#
# NAO e idempotente para efeito de retentativa: o canal e de fluxo, e o laco so
# repete quando nada foi emitido. Ver a nota no laco.
dbx_http_conteudo_receber() {
  [[ $# -ge 5 ]] || return "$DBX_HTTP_ERRO_USO"
  local metodo=$1 url=$2 token=$3 arg=$4 destino=$5 inicio=${6:-}
  [[ -n $metodo && -n $url && -n $token && -n $destino ]] || return "$DBX_HTTP_ERRO_USO"
  [[ -z $inicio || $inicio =~ ^[1-9][0-9]{0,17}$ ]] || return "$DBX_HTTP_ERRO_USO"

  dbx_http_cabecalho_valido "$arg" || return "$DBX_HTTP_ERRO_USO"

  _DBX_HTTP_FAIXA_INICIO=$inicio
  _DBX_HTTP_MODO=conteudo
  _DBX_HTTP_CANAL=fluxo
  _DBX_HTTP_TOKEN=$token
  _DBX_HTTP_ARG=$arg
  _DBX_HTTP_ARQUIVO_CORPO=''
  _DBX_HTTP_DESTINO=$destino
  _dbx_http_executar "$metodo" "$url" '' sim
  local estado=$?
  _DBX_HTTP_FAIXA_INICIO=''
  _DBX_HTTP_FAIXA_FIM=''
  return "$estado"
}

# dbx_http_conteudo_receber_faixa <metodo> <url> <token> <arg_json> <arquivo> <inicio> <fim>
#
# F-100 (RF-180): UMA faixa fechada `Range: bytes=<inicio>-<fim>` gravada em
# <arquivo> (caminho, nunca descritor; truncado a cada tentativa). Resposta que
# nao seja a faixa (um `200` com o corpo inteiro) e recusada pelo teto de tamanho
# do cliente: DBX_HTTP_FAIXA_IGNORADA=sim, sem repeticao. Quem pediu confere o
# `206`, o `Content-Range` e a revisao.
dbx_http_conteudo_receber_faixa() {
  [[ $# -ge 7 ]] || return "$DBX_HTTP_ERRO_USO"
  local metodo=$1 url=$2 token=$3 arg=$4 destino=$5 inicio=$6 fim=$7
  [[ -n $metodo && -n $url && -n $token && -n $destino ]] || return "$DBX_HTTP_ERRO_USO"
  [[ $inicio =~ ^(0|[1-9][0-9]{0,17})$ && $fim =~ ^[1-9][0-9]{0,17}$ ]] || return "$DBX_HTTP_ERRO_USO"
  ((10#$fim >= 10#$inicio)) || return "$DBX_HTTP_ERRO_USO"

  dbx_http_cabecalho_valido "$arg" || return "$DBX_HTTP_ERRO_USO"

  _DBX_HTTP_FAIXA_INICIO=$inicio
  _DBX_HTTP_FAIXA_FIM=$fim
  _DBX_HTTP_MODO=conteudo
  _DBX_HTTP_CANAL=fluxo
  _DBX_HTTP_TOKEN=$token
  _DBX_HTTP_ARG=$arg
  _DBX_HTTP_ARQUIVO_CORPO=''
  _DBX_HTTP_DESTINO=$destino
  _dbx_http_executar "$metodo" "$url" '' sim
  local estado=$?
  _DBX_HTTP_FAIXA_INICIO=''
  _DBX_HTTP_FAIXA_FIM=''
  return "$estado"
}

# dbx_http_requisitar <metodo> <url> <token> <corpo> <idempotente>
dbx_http_requisitar() {
  [[ $# -ge 5 ]] || return "$DBX_HTTP_ERRO_USO"
  _DBX_HTTP_MODO=bearer
  _DBX_HTTP_CANAL=padrao
  _DBX_HTTP_TOKEN=$3
  # DIV-95: o arquivo de corpo do modo de conteudo e da chamada ANTERIOR. Sem
  # esta limpeza, toda chamada JSON depois de um envio levava o arquivo enviado
  # como corpo (o `delete_v2` do espelhamento, por exemplo).
  _DBX_HTTP_ARQUIVO_CORPO=''
  _DBX_HTTP_DESTINO=''
  _DBX_HTTP_FAIXA_INICIO=''
  _DBX_HTTP_FAIXA_FIM=''
  _dbx_http_executar "$1" "$2" "$4" "$5"
}

# dbx_http_formulario <url> <nome_do_vetor_de_campos>
#
# O vetor e passado por NOME, como em lib/output: campo com quebra de linha ou
# aspas nao sobreviveria a uma passagem por cadeia unica, e o nome mantem a
# procedencia visivel no ponto de chamada.
dbx_http_formulario() {
  [[ $# -ge 2 ]] || return "$DBX_HTTP_ERRO_USO"
  [[ -n $1 && -n $2 ]] || return "$DBX_HTTP_ERRO_USO"
  _DBX_HTTP_MODO=formulario
  _DBX_HTTP_CANAL=padrao
  _DBX_HTTP_CAMPOS_NOME=$2
  # DIV-95: idem ao modo bearer; a renovacao no meio de um envio nao pode
  # levar o arquivo da chamada anterior.
  _DBX_HTTP_ARQUIVO_CORPO=''
  _DBX_HTTP_DESTINO=''
  _DBX_HTTP_FAIXA_INICIO=''
  _DBX_HTTP_FAIXA_FIM=''
  # Sem corpo em arquivo: os campos vao pela entrada padrao.
  # Nao idempotente: uma troca de token repetida as cegas nao e desejavel.
  _dbx_http_executar POST "$1" '' nao
}

# dbx_http_sondar <url> — sonda de disponibilidade (RF-149): um GET simples,
# SEM token, SEM corpo, SEM repeticao e SEM seguir redirecionamento, com
# `connect-timeout 5` e `max-time 10` fixos (DIV-312). Devolve 0 quando HOUVE
# resposta HTTP completa, de qualquer status (DNS, TCP e TLS funcionaram), e
# publica o status em DBX_HTTP_SONDA_CODIGO; sem resposta devolve nao zero e o
# codigo e 0. O corpo da resposta e descartado. Mesmo transporte, proxy e TLS do
# resto (variaveis padrao do cURL); sem arquivos temporarios.
readonly DBX_HTTP_ESQUEMA_SONDA='https://'
dbx_http_sondar() {
  local url=${1-} codigo estado
  DBX_HTTP_SONDA_CODIGO=0
  [[ $url == "$DBX_HTTP_ESQUEMA_SONDA"* ]] || return "$DBX_HTTP_ERRO_USO"
  DBX_HTTP_REQUISICOES=$((DBX_HTTP_REQUISICOES + 1))
  codigo=$(
    {
      printf '%s\n' silent show-error 'connect-timeout = 5' 'max-time = 10' |
        curl -K - -X GET -o /dev/null -w '%{http_code}' "$url"
    } 2>/dev/null
  )
  estado=$?
  [[ $codigo =~ ^[1-9][0-9][0-9]$ ]] || codigo=0
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_HTTP_SONDA_CODIGO=$codigo
  # RF-149(c)(f): com --debug, a requisicao mascarada (so esquema e host, sem
  # caminho nem parametros) e o status recebido; nunca o segredo.
  if [[ ${DBX_CLI_DEBUG:-nao} == 'sim' ]]; then
    # RF-162: a sonda e uma chamada; `chamadas` do resumo bate com DBX_HTTP_REQUISICOES.
    dbx_debug_somar_http 1 0 0
    # R4: com `@` na URL, so ha host identificavel se nada de `/`, `?` ou `#`
    # vier antes do primeiro `@` (senao a senha pode conter o delimitador sem
    # encoding e qualquer corte vazaria um pedaco dela): ai so o esquema sai.
    local anfitriao=${url#"$DBX_HTTP_ESQUEMA_SONDA"}
    if [[ $anfitriao == *@* ]]; then
      if [[ ${anfitriao%%@*} == *[/?#]* ]]; then
        anfitriao='<host omitido>'
      else
        # Como o curl: a autoridade vai ate o primeiro delimitador e o userinfo
        # ate o ULTIMO `@` dela (a senha pode conter `@`).
        anfitriao=${anfitriao%%[/?#]*}
        anfitriao=${anfitriao##*@}
      fi
    else
      anfitriao=${anfitriao%%[/?#]*}
    fi
    dbx_errors_redigir "$(printf 'debug: sonda GET %s%s -> status %s' "$DBX_HTTP_ESQUEMA_SONDA" "$anfitriao" "$codigo")" >/dev/null
    printf '%s\n' "$DBX_ERRORS_REDIGIDO" >&2
  fi
  [[ $estado -eq 0 && $codigo != 0 ]]
}

# _dbx_http_executar <metodo> <url> <corpo> <idempotente>
#
# Dono do ciclo de vida da area temporaria de UMA requisicao: cria, entrega a
# `_dbx_http_conduzir` e remove no retorno, com o status preservado. A remocao e
# explicita, e nao por `trap ... RETURN`: o gancho e estado global do shell,
# continua armado depois do retorno e, na reemissao diagnostica (chamada
# recursiva), apontaria para a area do nivel interno e deixaria a externa.
#
# A area e de `lib/tmp` (RNF-35): nasce 0700 sem mexer na mascara do processo
# (o arquivo que o usuario recebe nasce com a dele) e fica registrada desde a
# criacao, entao sinal em qualquer ponto — inclusive na renovacao do token,
# OBS-02 — a remove. Cada nivel da reemissao registra e remove a sua.
_dbx_http_executar() {
  local metodo=$1 url=$2 corpo=$3 idempotente=$4
  local area estado

  case $idempotente in
    sim | nao) ;;
    *) return "$DBX_HTTP_ERRO_USO" ;;
  esac
  [[ -n $metodo && -n $url ]] || return "$DBX_HTTP_ERRO_USO"

  _dbx_http_limpar
  # Antes de qualquer area ou chamada: ajuste invalido nao chega a rede.
  dbx_http_validar_ambiente || return "$DBX_HTTP_ERRO_USO"

  DBX_HTTP_REQUISICOES=$((DBX_HTTP_REQUISICOES + 1))
  dbx_tmp_area http || return "$DBX_HTTP_ERRO_REDE"
  area=$DBX_TMP_CAMINHO
  # Canal alheio lido por componente que lida com o segredo: esvaziado aqui.
  DBX_TMP_CAMINHO=''
  _dbx_http_conduzir "$area" "$metodo" "$url" "$corpo" "$idempotente"
  estado=$?
  dbx_tmp_remover "$area"
  return "$estado"
}

# _dbx_http_conduzir <area> <metodo> <url> <corpo> <idempotente>
_dbx_http_conduzir() {
  local area=$1 metodo=$2 url=$3 corpo=$4 idempotente=$5
  local tentativa=1 estado codigo politica
  local destino=$_DBX_HTTP_DESTINO saida_padrao='' saida_e_cano='nao'
  # RF-157(f) / DIV-334 A: so com --debug o cliente informa tempo e bytes.
  local formato_w='%{http_code}' medidas=''
  [[ ${DBX_CLI_DEBUG:-nao} == 'sim' ]] &&
    formato_w='%{http_code} %{time_total} %{size_upload} %{size_download}'
  _DBX_HTTP_LINHA_DEBUG=()

  # QA-B5-05: o arquivo de corpo nasce 0600 (pode levar a senha do link,
  # RF-86(e)), alem da area 0700. A mascara muda so no subshell: a do
  # processo, que vale para o arquivo baixado, fica intacta (RNF-29(a)).
  [[ -n $corpo ]] && (umask 077 && printf '%s' "$corpo" >"$area/requisicao")

  # RF-32(b): o cliente roda DENTRO da substituicao que captura o codigo HTTP,
  # onde `/dev/stdout` (ou `-`) seria o cano da captura e o conteudo se
  # misturaria ao codigo. A saida padrao do processo e duplicada antes e o
  # cliente escreve nela pelo descritor.
  #
  # O destino `fd:<n>` (RF-171(a), DIV-352) e um descritor JA ABERTO do
  # processo. Nunca se monta `/dev/fd/<n>`: no FreeBSD, sem `fdescfs`, nao
  # existe para n>2 e, com ele, nao e o arquivo. O cliente escreve em
  # `/dev/stderr` (sempre presente no devfs), e a saida de erro do COMANDO e
  # redirecionada para o descritor (`2>&<n>`); o `-w` segue na saida padrao
  # capturada.
  #
  # NUNCA `--stderr <arquivo>` neste modo: o cliente REABRE o stderr do processo
  # antes de abrir a saida, e `-o /dev/stderr` passaria a ser o arquivo de erros;
  # o conteudo baixado iria para la e o `.part` ficaria com 0 bytes. Por isso o
  # cliente roda com `--no-show-error`: nenhuma mensagem sua pode cair no
  # descritor do conteudo. A mensagem textual do cliente NAO e capturada neste
  # modo; a classificacao segue pelo status do cliente e pelo `--fail`.
  #
  # LIMITE DECLARADO: o cliente REABRE `/dev/stderr`. Cano e terminal se
  # comportam como a saida padrao; arquivo regular e reaberto do inicio e
  # truncado (com faixa, `continue-at` anexa), e socket nao reabre. Por isso
  # `download` recusa saida padrao em arquivo nao vazio (o `>>` sobre conteudo
  # existente).
  local rele='' pid_rele='' estado_rele=0
  if [[ $_DBX_HTTP_CANAL == 'fluxo' && ($destino == '-' || $destino == '/dev/stdout') ]]; then
    exec {saida_padrao}>&1
    destino="fd:$saida_padrao"
    # Teste de tipo, sem captura: e o que distingue consumidor de disco.
    [[ -p /dev/stdout ]] && saida_e_cano='sim'
    # SOCKET (DIV-51, OBS-04): o cliente nao escreve direto em socket. Ele
    # escreve num cano e um `cat` repassa ao socket. Socket vivo
    # recebe tudo e o comando sai 0; so a falha de escrita do repasse (EPIPE ou
    # SIGPIPE: o consumidor encerrou de fato) vira `consumidor_encerrou`.
    if [[ -S /dev/stdout ]]; then
      saida_e_cano='sim'
      exec {rele}> >(exec cat >&"$saida_padrao")
      pid_rele=$!
      destino="fd:$rele"
    fi
  fi

  while :; do
    : >"$area/resposta"
    : >"$area/cabecalhos"
    : >"$area/erro_cliente"
    # A redirecao do stderr fica DENTRO da substituicao: aplicada do lado de
    # fora, a substituicao ja teria sido expandida com o stderr original e a
    # mensagem do cliente se perderia.
    # shellcheck disable=SC2094  # `--stderr` e o grupo apontam o mesmo arquivo de proposito: so o cliente escreve nele
    codigo=$(
      {
        _dbx_http_opcoes | if [[ $_DBX_HTTP_CANAL == 'fluxo' ]]; then
          # `--fail` impede a resposta de ERRO de sair como se fosse o conteudo
          # do arquivo (um 409 sairia com status zero e um JSON dentro): com
          # ele, zero bytes emitidos e status 22.
          if [[ $destino == fd:* ]]; then
            # O descritor do destino e a SAIDA DE ERRO deste comando (`2>&<n>`) e
            # o cliente escreve em `/dev/stderr`, que existe sempre (devfs), ao
            # contrario de `/dev/fd/<n>`. Sem `--stderr` (reabriria o stderr e
            # desviaria o conteudo) e com `--no-show-error` depois do `-K -`, que
            # vence o `show-error` de `_dbx_http_opcoes`. O `-w` segue na saida
            # padrao capturada.
            curl -K - --no-show-error --fail -X "$metodo" \
              -o /dev/stderr -D "$area/cabecalhos" -w "$formato_w" "$url" 2>&"${destino#fd:}"
          else
            curl -K - --fail -X "$metodo" \
              -o "$destino" -D "$area/cabecalhos" -w "$formato_w" "$url"
          fi
        elif [[ -n $_DBX_HTTP_ARQUIVO_CORPO ]]; then
          curl -K - -X "$metodo" --data-binary "@$_DBX_HTTP_ARQUIVO_CORPO" \
            -o "$area/resposta" -D "$area/cabecalhos" -w "$formato_w" "$url"
        elif [[ -n $corpo ]]; then
          curl -K - -X "$metodo" --data-binary "@$area/requisicao" \
            -o "$area/resposta" -D "$area/cabecalhos" -w "$formato_w" "$url"
        else
          curl -K - -X "$metodo" \
            -o "$area/resposta" -D "$area/cabecalhos" -w "$formato_w" "$url"
        fi
      } 2>"$area/erro_cliente"
    )
    estado=$?
    medidas=''
    if [[ $codigo == *[[:space:]]* ]]; then
      medidas=${codigo#*[[:space:]]}
      codigo=${codigo%%[[:space:]]*}
    fi


    # DEFEITO NOSSO NAO PODE CHEGAR AO OPERADOR COMO PROBLEMA DE REDE.
    #
    # Estes status do cliente sao emitidos ANTES de qualquer tentativa de
    # conversa com o servidor e nao dependem da rede:
    #   2  falha de inicializacao, inclusive arquivo de opcoes mal formado
    #   3  URL mal formada
    #   26 erro de leitura do arquivo indicado ao corpo
    #   43 argumento interno invalido
    # O stderr do cliente e guardado, redigido, para o diagnostico.
    DBX_HTTP_DEFEITO_CLIENTE=''
    DBX_HTTP_FAIXA_IGNORADA='nao'
    if [[ -n $_DBX_HTTP_FAIXA_INICIO && ($estado -eq 33 || ($estado -eq 63 && -n $_DBX_HTTP_FAIXA_FIM)) ]]; then
      # Fase 7a (RF-104(d), DIV-176): HOUVE resposta, e o cliente se recusou a
      # anexa-la — `200` a um pedido de faixa, ou `206` que nao comeca no
      # deslocamento pedido. Nada foi escrito; o codigo observado fica.
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_HTTP_FAIXA_IGNORADA='sim'
    elif [[ $estado -eq 22 ]]; then
      # `--fail` no canal de fluxo: HOUVE resposta HTTP e o codigo e conhecido; o
      # cliente apenas se recusou a emitir o corpo de erro como se fosse
      # conteudo. Nao e falha de rede.
      :
    elif [[ $estado -ne 0 ]]; then
      # Sem resposta HTTP: codigo zero, e nao um codigo inventado.
      codigo=0
      case $estado in
        2 | 3 | 26 | 43) DBX_HTTP_DEFEITO_CLIENTE=$estado ;;
      esac
    fi
    [[ $codigo =~ ^[0-9]+$ ]] || codigo=0
    [[ $codigo == 429 ]] && DBX_HTTP_LIMITES_429=$((DBX_HTTP_LIMITES_429 + 1))
    # Marca de pausa (DIV-365 A) no PRIMEIRO ponto que sabe do 429, antes de ler
    # cabecalhos ou decidir repeticao: fecha a janela em que o coordenador ainda
    # despacharia parte nova.
    [[ $codigo == 429 && -n ${DBX_HTTP_MARCA_PAUSA:-} ]] && : >"$DBX_HTTP_MARCA_PAUSA"

    DBX_HTTP_DIAGNOSTICO=''
    if [[ -s $area/erro_cliente ]]; then
      local bruto=''
      IFS= read -r -d '' bruto <"$area/erro_cliente"
      # Redigido antes de publicar: as opcoes que o cliente reclama podem conter
      # o segredo, e este canal e lido por quem depura.
      dbx_errors_redigir "$bruto" >/dev/null
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_HTTP_DIAGNOSTICO=$DBX_ERRORS_REDIGIDO
    elif [[ $_DBX_HTTP_CANAL == 'fluxo' && $destino == fd:* && $estado -ne 0 && $estado -ne 22 ]]; then
      # Modo `fd:` roda sem mensagem textual do cliente (`--no-show-error`):
      # a falha continua com motivo legivel, pelo status.
      DBX_HTTP_DIAGNOSTICO="cliente HTTP falhou com codigo $estado"
    fi

    # shellcheck disable=SC2034  # canal publico, ver nota no topo
    DBX_HTTP_CODIGO=$codigo
    # Leitura byte a byte, e nao por substituicao de comando, que removeria
    # quebras de linha finais do corpo.
    #
    # LIMITE DECLARADO: este canal e para corpo TEXTUAL. Conteudo binario nao
    # transita por variavel de shell, que nao carrega o byte nulo; o recebimento
    # de arquivo usa o canal de fluxo, por arquivo ou descritor.
    DBX_HTTP_CORPO=''
    [[ -r $area/resposta ]] && IFS= read -r -d '' DBX_HTTP_CORPO <"$area/resposta"

    _dbx_http_correlacao_de "$area/cabecalhos"
    if [[ ${DBX_CLI_DEBUG:-nao} == 'sim' ]]; then
      _dbx_http_debug_preparar "$metodo" "$url" "$tentativa" "$codigo" "$estado" "$medidas"
    fi

    DBX_HTTP_RESUMO_DE_ERRO=''
    if [[ $codigo -eq 0 || $codigo -ge 400 ]]; then
      _dbx_http_interpretar_erro "$DBX_HTTP_CORPO"
    fi

    # A decisao de repetir CONSULTA a taxonomia de `lib/errors`, para classe e
    # politica nunca se contradizerem; por variavel, sem subshell a cada
    # tentativa.
    dbx_errors_classificar "$codigo" "$DBX_HTTP_RESUMO_DE_ERRO" >/dev/null
    DBX_HTTP_CLASSE=$DBX_ERRORS_CLASSE
    dbx_errors_politica_retentativa "$codigo" "$DBX_HTTP_RESUMO_DE_ERRO" "$idempotente" >/dev/null
    politica=$DBX_ERRORS_POLITICA
    # shellcheck disable=SC2034  # canal publico, ver nota no topo
    DBX_HTTP_POLITICA=$politica

    if [[ $DBX_HTTP_FAIXA_IGNORADA == 'sim' ]]; then
      # Resposta incoerente com o pedido de faixa: quem pediu decide (recomeca
      # do zero); nunca e repetida aqui nem passa por sucesso.
      DBX_HTTP_CLASSE='erro_remoto'
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_HTTP_POLITICA='nenhuma'
      break
    fi

    if [[ -n $DBX_HTTP_DEFEITO_CLIENTE ]]; then
      # Erro de uso do proprio programa: nao e retentavel e nao e da rede.
      DBX_HTTP_CLASSE='uso_invalido'
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_HTTP_POLITICA='nenhuma'
      break
    fi

    # RF-32: erro de escrita (23) no fluxo para a saida padrao. So e
    # consumidor que fechou quando ela e CANO ou FIFO; em arquivo ou dispositivo
    # (`/dev/full`, disco cheio) e falha local de escrita, a mesma classe que o
    # recebimento em arquivo usa (`configuracao`). Nos dois casos nunca se
    # repete: bytes podem ja ter sido entregues. Em fluxo para arquivo de
    # recebimento o 23 segue o tratamento comum abaixo.
    if [[ -n $saida_padrao && $estado -eq 23 ]]; then
      if [[ $saida_e_cano == 'sim' ]]; then
        DBX_HTTP_CLASSE='consumidor_encerrou'
      else
        DBX_HTTP_CLASSE='configuracao'
        # shellcheck disable=SC2034  # canal publico, ver nota no topo
        DBX_HTTP_DIAGNOSTICO='falha de escrita na saida padrao: o arquivo ou dispositivo de destino recusou os dados (sem espaco ou sem permissao)'
      fi
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_HTTP_POLITICA='nenhuma'
      break
    fi

    case $politica in
      recuo_exponencial | respeitar_retry_after)
        [[ $tentativa -lt ${DBX_HTTP_EFETIVO[DBX_HTTP_TENTATIVAS_MAXIMAS]} ]] || break
        # RETENTATIVA E PROPRIEDADE DO CANAL, NAO DO TRANSPORTE.
        #
        # No canal de fluxo os bytes ja foram entregues ao consumidor e nao
        # voltam: repetir entregaria o inicio do conteudo duas vezes — corrupcao
        # produzida pela nossa propria politica de confiabilidade, e
        # indistinguivel de conteudo legitimo do lado de fora.
        #
        # Repetir so e seguro quando NADA foi emitido: sob `--fail`, uma recusa
        # HTTP emite zero bytes (status 22), e conexao recusada tambem (status
        # 7). Ja o erro de escrita (23) significa que houve transferencia — e ai
        # nao se repete.
        if [[ $_DBX_HTTP_CANAL == 'fluxo' && $estado -ne 22 && $estado -ne 7 ]]; then
          break
        fi
        # Marca opcional de pausa (DIV-365 A): quem chamou em paralelo define o
        # arquivo, e o 429 o cria ANTES da espera, para o coordenador nao
        # despachar faixa nova durante o `Retry-After`. Sem a variavel, sem custo.
        [[ $codigo == 429 && -n ${DBX_HTTP_MARCA_PAUSA:-} ]] && : >"$DBX_HTTP_MARCA_PAUSA"
        if [[ ${#_DBX_HTTP_LINHA_DEBUG[@]} -gt 0 ]]; then
          # RF-157(a): a linha sai antes da espera e a leva em `espera_ms`.
          _dbx_http_espera_calcular "$tentativa"
          _dbx_http_debug_emitir "$_DBX_HTTP_ESPERA_MS"
          _dbx_http_dormir
        else
          _dbx_http_esperar "$tentativa"
        fi
        tentativa=$((tentativa + 1))
        continue
        ;;
      *)
        break
        ;;
    esac
  done
  _dbx_http_debug_emitir
  if [[ -n $rele ]]; then
    # Fim do repasse: fechado o cano, o `cat` termina, e o status dele diz se o
    # socket aceitou tudo.
    exec {rele}>&-
    wait "$pid_rele" 2>/dev/null || estado_rele=$?
    if [[ $estado_rele -ne 0 ]]; then
      # shellcheck disable=SC2034  # canais publicos, ver nota no topo
      DBX_HTTP_CLASSE='consumidor_encerrou'
      # shellcheck disable=SC2034
      DBX_HTTP_POLITICA='nenhuma'
      # Sem codigo HTTP a diagnosticar: nenhuma reemissao (nada se repete).
      DBX_HTTP_CODIGO=0
    fi
  fi
  [[ -n $saida_padrao ]] && exec {saida_padrao}>&-

  # DIAGNOSTICO DO CANAL DE FLUXO: reemissao sem fluxo para obter o corpo do erro.
  #
  # `--fail` impede o corpo de erro de sair como se fosse conteudo — sem ele um
  # 409 vira arquivo local com JSON dentro — mas o preco e ficarmos sem o
  # `error_summary`, e a classificacao cai em `desconhecido` diante de um 404
  # perfeitamente informativo.
  #
  # A reemissao ocorre so no caminho de erro; o caminho feliz nao paga nada.
  # `--fail-with-body` devolveria o corpo, mas pela saida padrao — resolveria o
  # diagnostico reintroduzindo exatamente o problema.
  #
  # LIMITE DECLARADO: o corpo vem de uma requisicao POSTERIOR. Se o recurso mudou
  # entre as duas, o diagnostico descreve outro instante. Diagnostico que descreve
  # outro momento e pior que diagnostico ausente, entao a divergencia fica
  # registrada em vez de silenciada.
  # Fase 7a: a faixa recusada (33) e o `416` sao respostas que quem pediu a
  # faixa interpreta; nao ha corpo de erro a buscar.
  if [[ $_DBX_HTTP_CANAL == 'fluxo' && $DBX_HTTP_CLASSE != 'sucesso' && -n $DBX_HTTP_CODIGO && $DBX_HTTP_CODIGO != '0' &&
    $DBX_HTTP_FAIXA_IGNORADA != 'sim' && ! (-n $_DBX_HTTP_FAIXA_INICIO && $DBX_HTTP_CODIGO == '416') && -z $_DBX_HTTP_FAIXA_FIM ]]; then
    local _canal_original=$_DBX_HTTP_CANAL _destino_original=$_DBX_HTTP_DESTINO _faixa_original=$_DBX_HTTP_FAIXA_INICIO
    local _codigo_observado=$DBX_HTTP_CODIGO
    _DBX_HTTP_CANAL=padrao
    _DBX_HTTP_DESTINO=''
    _DBX_HTTP_FAIXA_INICIO=''
    _DBX_HTTP_FAIXA_FIM=''
    # Nao idempotente: a reemissao existe para diagnosticar, nunca para repetir a
    # operacao. Uma retentativa aqui seria uma segunda tentativa disfarcada.
    _dbx_http_executar "$metodo" "$url" '' nao >/dev/null 2>&1 || true
    _DBX_HTTP_CANAL=$_canal_original
    _DBX_HTTP_DESTINO=$_destino_original
    _DBX_HTTP_FAIXA_INICIO=$_faixa_original
    if [[ $DBX_HTTP_CODIGO != "$_codigo_observado" ]]; then
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_HTTP_DIAGNOSTICO="diagnostico obtido em reemissao posterior; o codigo mudou de ${_codigo_observado} para ${DBX_HTTP_CODIGO} entre as duas requisicoes"
    fi
  fi

  [[ $DBX_HTTP_CLASSE == 'sucesso' ]] && return 0
  # O codigo vem da tabela da taxonomia, numa consulta so. Classe fora da
  # tabela devolve o status de uso.
  dbx_errors_classe_valida "$DBX_HTTP_CLASSE" || return "$DBX_ERRORS_STATUS_USO"
  return "${DBX_ERRORS_CODIGO[$DBX_HTTP_CLASSE]}"
}

# dbx_http_colecao <metodo> <url> <token> <corpo> <limite>
#
# RNF-23: toda chamada que retorne colecao exige limite EXPLICITO. Sem ele, uma
# pasta grande produz corpo acima do teto do analisador e a operacao falha por
# recusa de analise, e nao por erro do servico.
#
# Ao receber `tamanho` como motivo, o limite e REDUZIDO e a chamada repetida —
# abortar deixaria a operacao impossivel para pastas grandes, quando bastava
# pedir menos por pagina.
dbx_http_colecao() {
  [[ $# -ge 5 ]] || return "$DBX_HTTP_ERRO_USO"
  local metodo=$1 url=$2 token=$3 corpo=$4 limite=$5
  local estado corpo_com_limite

  [[ $limite =~ ^[0-9]+$ ]] || return "$DBX_HTTP_ERRO_USO"
  [[ $limite -ge 1 && $limite -le $DBX_HTTP_LIMITE_MAXIMO ]] || return "$DBX_HTTP_ERRO_USO"

  while :; do
    if [[ $corpo == '{'* ]]; then
      corpo_com_limite="{\"limit\":$limite,${corpo#\{}"
    else
      corpo_com_limite="{\"limit\":$limite}"
    fi

    dbx_http_requisitar "$metodo" "$url" "$token" "$corpo_com_limite" sim
    estado=$?

    # O corpo veio bem, mas o analisador recusou por tamanho: peca menos.
    if [[ $estado -eq 0 ]]; then
      dbx_json_contexto http_colecao || return "$DBX_HTTP_ERRO_USO"
      if dbx_json_analisar "$DBX_HTTP_CORPO"; then
        dbx_json_descartar http_colecao
        dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
        return 0
      fi
      local motivo=$DBX_JSON_MOTIVO
      dbx_json_descartar http_colecao
      dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
      if [[ $motivo == 'tamanho' && $limite -gt $DBX_HTTP_LIMITE_MINIMO ]]; then
        limite=$((limite / 2))
        [[ $limite -lt $DBX_HTTP_LIMITE_MINIMO ]] && limite=$DBX_HTTP_LIMITE_MINIMO
        continue
      fi
      return "$(dbx_errors_codigo_saida erro_remoto)"
    fi
    return "$estado"
  done
}
