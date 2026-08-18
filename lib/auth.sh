#!/usr/bin/env bash
# auth.sh — troca do refresh token de longa duracao por access token de curta
# duracao, e requisicao autenticada com renovacao no meio do caminho.
#
# POSICAO DO COMPONENTE
#   Depende de lib/http, lib/json, lib/errors e dos campos publicados por
#   lib/config. lib/http NAO depende deste componente: a direcao e sempre da
#   politica de credencial para o transporte, nunca o contrario. Por isso a
#   renovacao no meio de uma sequencia paginada e feita AQUI, envolvendo cada
#   chamada, e nao por um gancho dentro do cliente.
#
# O SEGREDO DE MAIOR VALOR
#   O refresh token nao expira e vale acesso indefinido a conta. Ele:
#     - nunca aparece em `argv` — vai por `curl -K -`, na entrada padrao;
#     - nunca e escrito em arquivo de corpo — sao campos `data-urlencode`, e nao
#       `--data-binary @arquivo`, justamente para nao existir janela de
#       credencial em disco;
#     - nunca entra em `DBX_AUTH_MOTIVO`, que e montado a partir do campo
#       `error` da resposta e passa pela redacao antes de ser publicado;
#     - por consequencia, nunca chega ao diario de reprovacoes da suite, que
#       grava em disco o diagnostico dos casos.
#
# SEM COORDENACAO ENTRE PROCESSOS, E SEM ESTADO NOVO
#   A Dropbox nao rotaciona o refresh token: a resposta da troca nao devolve um
#   token novo e o mesmo refresh pode ser reusado indefinidamente. Duas
#   renovacoes simultaneas sao portanto idempotentes — cada processo recebe seu
#   proprio access token e nada se invalida. Nao ha arquivo de trava, nao ha
#   reescrita do arquivo de credencial e `PRJ-DEC-07` fica preservado sem
#   esforco. Se o contrato mudasse para refresh rotativo, a resposta ainda nao
#   seria trava: seria a substituicao atomica que lib/config ja faz.
#
# CASCATA DE INVALIDACAO (RF-06a)
#   Revogar o refresh desabilita todos os access derivados dele. Logo `401` nao
#   e sinonimo de "renove": `expired_access_token` no endpoint da API renova uma
#   vez; `invalid_grant` no endpoint de token e terminal e retentar e inutil —
#   o usuario precisa autorizar de novo.
#
# O QUE ESTE COMPONENTE NAO PROMETE: SOBREVIVENCIA DO CURSOR
#   Eu havia afirmado que o cursor de paginacao e estado do servidor associado a
#   conta e que por isso sobreviveria a uma renovacao de token. Fui verificar na
#   fonte primaria e a afirmacao NAO se sustenta: a documentacao da Dropbox e
#   silenciosa sobre o assunto — cursor e access token nunca sao mencionados um
#   em relacao ao outro, nem na referencia da API, nem no guia de deteccao de
#   mudancas, nem no guia de OAuth. O unico texto normativo sobre `reset` diz
#   apenas "Indicates that the cursor has been invalidated. Call list_folder to
#   obtain a new cursor", e a unica causa documentada e expiracao por desuso.
#   A posicao atual do suporte da Dropbox e ainda mais conservadora, e nao
#   documentada: nao ha garantia de validade e cursores devem ser tratados como
#   de vida curta.
#
#   Consequencia de projeto: quem for dono do laco de paginacao trata `reset`
#   como CAMINHO PREVISTO, com a politica `reiniciar` que ja existe na
#   taxonomia, e nao como excecao. Este componente nao promete continuidade de
#   cursor apos renovar, porque nao ha fonte que a sustente.
#
# O ACCESS TOKEN VIVE SO EM MEMORIA
#   Em variavel de shell do processo corrente, nunca em disco. Ao terminar o
#   processo ele desaparece, o que e o comportamento desejado para credencial de
#   curta duracao e mantem a unica escrita persistente do projeto sendo o
#   arquivo de credencial.

[[ -n ${DBX_AUTH_CARREGADO:-} ]] && return 0
DBX_AUTH_CARREGADO=1

DBX_AUTH_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_AUTH_ERRO_AUTENTICACAO=$(dbx_errors_codigo_saida autenticacao)
DBX_AUTH_ERRO_REMOTO=$(dbx_errors_codigo_saida erro_remoto)

readonly DBX_AUTH_URL_TOKEN='https://api.dropbox.com/oauth2/token'

# Margem antes do vencimento. Um token que expira em transito produz falha que
# parece do servico e nao da credencial; trocar antes custa uma chamada e evita
# a classe inteira.
readonly DBX_AUTH_MARGEM_SEGUNDOS=60

# Canais publicos: consumidos pelo chamador, nao dentro deste arquivo.
DBX_AUTH_TOKEN=''
DBX_AUTH_EXPIRA_EM=0
# shellcheck disable=SC2034  # canal publico
DBX_AUTH_MOTIVO=''
# shellcheck disable=SC2034  # canal publico
DBX_AUTH_RENOVOU='nao'
DBX_AUTH_LIDO=''

# dbx_auth_esquecer — descarta o token curto da memoria.
dbx_auth_esquecer() {
  DBX_AUTH_TOKEN=''
  DBX_AUTH_EXPIRA_EM=0
  return 0
}

# dbx_auth_expirado — verdadeiro quando nao ha token ou ele esta dentro da
# margem de vencimento.
dbx_auth_expirado() {
  [[ -n $DBX_AUTH_TOKEN ]] || return 0
  [[ $DBX_AUTH_EXPIRA_EM =~ ^[0-9]+$ ]] || return 0
  [[ $SECONDS -ge $DBX_AUTH_EXPIRA_EM ]]
}

# _dbx_auth_falhar <codigo> <motivo> — publica o motivo ja redigido.
#
# Chamada SEMPRE em `{ ...; return $?; }`, nunca em `return "$(...)"`. A segunda
# forma roda num subshell: o motivo seria atribuido e perdido junto com o
# subshell, e a funcao devolveria cadeia vazia em vez de codigo. E o defeito
# C2-01, ja corrigido em lib/json, que eu reintroduzi aqui — e que a suite
# apanhou.
_dbx_auth_falhar() {
  local codigo=$1 motivo=$2
  dbx_errors_redigir "$motivo" >/dev/null
  DBX_AUTH_MOTIVO=$DBX_ERRORS_REDIGIDO
  return "$codigo"
}

# _dbx_auth_interpretar <corpo> <campo> — le um campo do corpo em contexto
# nomeado proprio, para nao destruir uma analise em curso do chamador.
_dbx_auth_interpretar() {
  local corpo=$1 campo=$2
  DBX_AUTH_LIDO=''
  [[ -n $corpo ]] || return 1
  dbx_json_contexto auth || return 1
  local achou=1
  if dbx_json_analisar "$corpo"; then
    if dbx_json_valor "$campo" >/dev/null; then
      DBX_AUTH_LIDO=$DBX_JSON_RESULTADO
      achou=0
    fi
  fi
  dbx_json_descartar auth
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  return $achou
}

# dbx_auth_renovar — troca o refresh token por um access token de curta duracao.
dbx_auth_renovar() {
  # shellcheck disable=SC2034  # canal publico
  DBX_AUTH_MOTIVO=''
  # Recusa antes de sair na rede: credencial incompleta e erro de uso, e nao
  # erro do servico. Distinguir os dois e o que impede diagnostico enganoso.
  [[ -n ${DBX_CONFIG_REFRESH_TOKEN:-} && -n ${DBX_CONFIG_APP_KEY:-} ]] || {
    _dbx_auth_falhar "$DBX_AUTH_ERRO_USO" 'credencial ausente ou incompleta'
    return $?
  }

  # Campos por NOME, e nunca por argv. `client_secret` no corpo evita a
  # autenticacao basica, que exigiria codificacao em base64 — utilitario externo
  # novo, que teria de entrar no preflight e na auditoria de comandos por uma
  # conveniencia que o proprio protocolo dispensa.
  local -a campos=(
    "grant_type=refresh_token"
    "refresh_token=$DBX_CONFIG_REFRESH_TOKEN"
    "client_id=$DBX_CONFIG_APP_KEY"
  )
  [[ -n ${DBX_CONFIG_APP_SECRET:-} ]] && campos+=("client_secret=$DBX_CONFIG_APP_SECRET")

  local estado
  dbx_http_formulario "$DBX_AUTH_URL_TOKEN" campos
  estado=$?

  if [[ $estado -ne 0 ]]; then
    local erro=''
    _dbx_auth_interpretar "$DBX_HTTP_CORPO" error && erro=$DBX_AUTH_LIDO
    # `invalid_grant` significa refresh revogado ou invalido: terminal. Repetir
    # nao muda o resultado e a cascata ja invalidou todo access derivado.
    if [[ $erro == 'invalid_grant' ]]; then
      _dbx_auth_falhar "$DBX_AUTH_ERRO_AUTENTICACAO" \
        'renovacao recusada: invalid_grant (refresh token invalido ou revogado; autorize de novo)'
      return $?
    fi
    _dbx_auth_falhar "$estado" "renovacao falhou (codigo ${DBX_HTTP_CODIGO:-0}${erro:+, $erro})"
    return $?
  fi

  _dbx_auth_interpretar "$DBX_HTTP_CORPO" access_token || {
    _dbx_auth_falhar "$DBX_AUTH_ERRO_REMOTO" 'resposta de token sem access_token'
    return $?
  }
  local token=$DBX_AUTH_LIDO
  [[ -n $token ]] || {
    _dbx_auth_falhar "$DBX_AUTH_ERRO_REMOTO" 'access_token vazio na resposta'
    return $?
  }

  local validade=0
  _dbx_auth_interpretar "$DBX_HTTP_CORPO" expires_in && validade=$DBX_AUTH_LIDO
  [[ $validade =~ ^[0-9]+$ ]] || validade=0

  DBX_AUTH_TOKEN=$token
  DBX_AUTH_EXPIRA_EM=$((SECONDS + validade - DBX_AUTH_MARGEM_SEGUNDOS))
  [[ $DBX_AUTH_EXPIRA_EM -lt 0 ]] && DBX_AUTH_EXPIRA_EM=0
  return 0
}

# dbx_auth_token — garante um token curto valido em memoria.
dbx_auth_token() {
  dbx_auth_expirado || return 0
  dbx_auth_renovar
}

# dbx_auth_requisitar <metodo> <url> <corpo> <idempotente>
#
# Renova NO MAXIMO uma vez por requisicao. A garantia contra laco entre renovar
# e receber `401` de novo e o sinalizador, e nao a esperanca de que a segunda
# tentativa va dar certo.
dbx_auth_requisitar() {
  [[ $# -ge 4 ]] || return "$DBX_AUTH_ERRO_USO"
  local metodo=$1 url=$2 corpo=$3 idempotente=$4
  local estado
  DBX_AUTH_RENOVOU='nao'

  while :; do
    dbx_auth_token || return $?
    dbx_http_requisitar "$metodo" "$url" "$DBX_AUTH_TOKEN" "$corpo" "$idempotente"
    estado=$?
    [[ $estado -eq 0 ]] && return 0
    [[ $DBX_HTTP_POLITICA == 'renovar_token_uma_vez' && $DBX_AUTH_RENOVOU == 'nao' ]] || return $estado
    DBX_AUTH_RENOVOU='sim'
    dbx_auth_esquecer
  done
}
