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
#       grava em disco o diagnostico dos casos;
#     - nem permanece nos canais do TRANSPORTE apos a troca: `DBX_HTTP_CORPO` e
#       os canais vizinhos sao limpos ao fim da renovacao. Ver
#       `_dbx_auth_limpar_transporte`.
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
#   curta duracao e mantem o arquivo de credencial como o unico lugar em disco
#   com segredo (a memoria de hash de `lib/state` nao guarda segredo).

[[ -n ${DBX_AUTH_CARREGADO:-} ]] && return 0
DBX_AUTH_CARREGADO=1

DBX_AUTH_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_AUTH_ERRO_AUTENTICACAO=$(dbx_errors_codigo_saida autenticacao)
DBX_AUTH_ERRO_REMOTO=$(dbx_errors_codigo_saida erro_remoto)
# RF-63(a): segredo ausente e credencial incompleta, com a classe e o codigo de
# RF-03 (`configuracao`) — manda reconfigurar, e nao revisar a linha de comando.
DBX_AUTH_ERRO_CONFIGURACAO=$(dbx_errors_codigo_saida configuracao)

readonly DBX_AUTH_URL_TOKEN='https://api.dropbox.com/oauth2/token'
readonly DBX_AUTH_URL_AUTORIZAR='https://www.dropbox.com/oauth2/authorize'
readonly DBX_AUTH_URL_REVOGAR='https://api.dropboxapi.com/2/auth/token/revoke'

# Conjunto de caracteres NAO RESERVADOS da RFC 3986. A chave de aplicativo entra
# numa URL que o operador vai colar num navegador, e por isso a validacao deriva
# da GRAMATICA da URL, e nao do formato que as chaves da Dropbox hoje aparentam
# ter. Restringir ao que se observa criaria recusa de chave legitima no dia em
# que o emissor mudar o alfabeto; restringir ao nao reservado garante que nao ha
# o que escapar, que e a propriedade de que precisamos.
readonly DBX_AUTH_ALFABETO_CHAVE='A-Za-z0-9._~-'

# Margem antes do vencimento. Um token que expira em transito produz falha que
# parece do servico e nao da credencial; trocar antes custa uma chamada e evita
# a classe inteira.
readonly DBX_AUTH_MARGEM_SEGUNDOS=60

# Canais publicos: consumidos pelo chamador, nao dentro deste arquivo.
DBX_AUTH_TOKEN=''
DBX_AUTH_EXPIRA_EM=0
# shellcheck disable=SC2034  # canal publico
DBX_AUTH_MOTIVO=''
# Publicados apenas pela troca do codigo de autorizacao.
# shellcheck disable=SC2034  # canais publicos: lidos por commands/config e pela
# suite; a analise estatica nao cruza arquivos e os ve como escrita sem leitura.
DBX_AUTH_REFRESH_TOKEN=''
# shellcheck disable=SC2034  # idem
DBX_AUTH_CONTA=''
# shellcheck disable=SC2034  # canal publico
DBX_AUTH_RENOVOU='nao'
# Escopos declarados pela ultima renovacao (DIV-35), lidos pelo `diagnostico`.
# shellcheck disable=SC2034  # canais publicos, lidos por commands/diagnostico
DBX_AUTH_ESCOPOS=''
# shellcheck disable=SC2034  # idem
DBX_AUTH_ESCOPOS_INFORMADOS='nao'
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

# _dbx_auth_limpar_transporte — apaga os canais do transporte que a renovacao
# encheu com dado derivado de credencial.
#
# QH-01, o canal ADJACENTE. Eu descartava o contexto JSON proprio exatamente
# para o segredo nao permanecer, e nao fazia o equivalente para `DBX_HTTP_CORPO`
# — canal publico declarado, que apos renovar com sucesso guarda o access token
# em claro e, apos falhar contra um servico que ecoe a requisicao, guarda o
# refresh token e o segredo do aplicativo. O cabecalho afirmava que o refresh
# "nunca chega ao diario": era verdade para o canal em que pensei e falso para o
# vizinho. Limpei onde doeu e nao no gemeo, pela sexta vez.
#
# Limpo APENAS no caminho de renovacao. Em `dbx_auth_requisitar` o corpo e a
# resposta que o chamador precisa ler; apaga-lo ali quebraria o componente e
# seria zelo transformado em defeito.
_dbx_auth_limpar_transporte() {
  # shellcheck disable=SC2034  # canais publicos de lib/http, limpos aqui
  DBX_HTTP_CORPO=''
  # shellcheck disable=SC2034  # canais publicos de lib/http, limpos aqui
  DBX_HTTP_RESUMO_DE_ERRO=''
  # shellcheck disable=SC2034  # canais publicos de lib/http, limpos aqui
  DBX_HTTP_DIAGNOSTICO=''
  # O resultado do analisador guarda o ULTIMO valor lido. Hoje o ultimo e
  # inofensivo por acidente de ordem — `expires_in` no sucesso, `error` na
  # falha — e depender de ordem de leitura para nao vazar segredo e garantia
  # que a proxima edicao desfaz sem perceber.
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_RESULTADO=''
  return 0
}

# dbx_auth_renovar — troca o refresh token por um access token de curta duracao.
dbx_auth_renovar() {
  # shellcheck disable=SC2034  # canal publico
  DBX_AUTH_MOTIVO=''
  DBX_AUTH_CODIGO_HTTP=''
  # Recusa antes de sair na rede: credencial incompleta e erro de uso, e nao
  # erro do servico. Distinguir os dois e o que impede diagnostico enganoso.
  [[ -n ${DBX_CONFIG_REFRESH_TOKEN:-} && -n ${DBX_CONFIG_APP_KEY:-} ]] || {
    _dbx_auth_falhar "$DBX_AUTH_ERRO_USO" 'credencial ausente ou incompleta'
    return $?
  }
  # RF-63: o segredo do aplicativo e obrigatorio tambem aqui, e nao so no
  # `config`. Sem PKCE, nao ha caminho de token sem ele; a recusa vem antes da
  # rede e nomeia o que falta, sem valor algum.
  [[ -n ${DBX_CONFIG_APP_SECRET:-} ]] || {
    _dbx_auth_falhar "$DBX_AUTH_ERRO_CONFIGURACAO" 'credencial incompleta: segredo do aplicativo (app secret) ausente'
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
    "client_secret=$DBX_CONFIG_APP_SECRET"
  )

  local estado
  dbx_http_formulario "$DBX_AUTH_URL_TOKEN" campos
  estado=$?

  if [[ $estado -ne 0 ]]; then
    local erro=''
    DBX_AUTH_CODIGO_HTTP=${DBX_HTTP_CODIGO:-0}
    _dbx_auth_interpretar "$DBX_HTTP_CORPO" error && erro=$DBX_AUTH_LIDO
    # `invalid_grant` significa refresh revogado ou invalido: terminal. Repetir
    # nao muda o resultado e a cascata ja invalidou todo access derivado.
    _dbx_auth_limpar_transporte
    if [[ $erro == 'invalid_grant' ]]; then
      _dbx_auth_falhar "$DBX_AUTH_ERRO_AUTENTICACAO" \
        'renovacao recusada: invalid_grant (refresh token invalido ou revogado; autorize de novo)'
      return $?
    fi
    _dbx_auth_falhar "$estado" "renovacao falhou (codigo ${DBX_HTTP_CODIGO:-0}${erro:+, $erro})"
    return $?
  fi

  _dbx_auth_interpretar "$DBX_HTTP_CORPO" access_token || {
    _dbx_auth_limpar_transporte
    _dbx_auth_falhar "$DBX_AUTH_ERRO_REMOTO" 'resposta de token sem access_token'
    return $?
  }
  local token=$DBX_AUTH_LIDO
  [[ -n $token ]] || {
    _dbx_auth_limpar_transporte
    _dbx_auth_falhar "$DBX_AUTH_ERRO_REMOTO" 'access_token vazio na resposta'
    return $?
  }

  local validade=0
  _dbx_auth_interpretar "$DBX_HTTP_CORPO" expires_in && validade=$DBX_AUTH_LIDO
  [[ $validade =~ ^[0-9]+$ ]] || validade=0

  # DIV-35: escopos que a resposta declara, lidos aqui porque o corpo e limpo
  # logo abaixo. Sem o campo, `nao`: quem consome trata como nao informado, e
  # nunca como "nenhum escopo".
  DBX_AUTH_ESCOPOS=''
  DBX_AUTH_ESCOPOS_INFORMADOS='nao'
  if _dbx_auth_interpretar "$DBX_HTTP_CORPO" scope; then
    # shellcheck disable=SC2034  # canais publicos, lidos por commands/diagnostico
    DBX_AUTH_ESCOPOS=$DBX_AUTH_LIDO
    # shellcheck disable=SC2034  # idem
    DBX_AUTH_ESCOPOS_INFORMADOS='sim'
  fi

  DBX_AUTH_TOKEN=$token
  DBX_AUTH_EXPIRA_EM=$((SECONDS + validade - DBX_AUTH_MARGEM_SEGUNDOS))
  [[ $DBX_AUTH_EXPIRA_EM -lt 0 ]] && DBX_AUTH_EXPIRA_EM=0
  _dbx_auth_limpar_transporte
  return 0
}

# Gancho da disponibilidade (RF-151(c), DIV-313): nome de uma funcao que o ponto de
# entrada define para os comandos de nivel `credencial`. E chamada na falha da
# obtencao de token enquanto nenhum token foi obtido (antes de qualquer efeito), com
# o codigo da falha; devolve o codigo final (0 = token obtido). Vazio = sem gancho.
DBX_AUTH_GANCHO_FALHA=''
# Gancho da falha de requisicao depois da obtencao do token (RF-151(e)): so
# enriquece a mensagem; nunca muda o codigo, repete efeito ou oferece config.
DBX_AUTH_GANCHO_MEIO=''
DBX_AUTH_PRIMEIRA_OBTENCAO='sim'
# Codigo HTTP da ultima renovacao que falhou na rede/servico (vazio quando a
# falha foi de credencial local ou nao houve falha): permite classificar 5xx pelo
# codigo, e nao pelo texto do motivo.
DBX_AUTH_CODIGO_HTTP=''

# dbx_auth_registrar_ganchos <falha_do_token> <falha_da_chamada> — arma os
# ganchos da disponibilidade (nomes de funcao; vazio desarma). Ponto unico de
# escrita: o ponto de entrada nao atribui os canais crus.
dbx_auth_registrar_ganchos() {
  DBX_AUTH_GANCHO_FALHA=${1-}
  DBX_AUTH_GANCHO_MEIO=${2-}
}

# dbx_auth_definir_motivo <texto> — substitui o motivo da ultima falha do token
# (redigido), para a disponibilidade nomear a causa sem escrever o canal.
dbx_auth_definir_motivo() {
  dbx_errors_redigir "${1-}" >/dev/null
  DBX_AUTH_MOTIVO=$DBX_ERRORS_REDIGIDO
}

# dbx_auth_enriquecer_motivo <texto> — poe a causa na frente do motivo da ultima
# falha do token e preserva o original entre parenteses (redigido).
dbx_auth_enriquecer_motivo() {
  local original=$DBX_AUTH_MOTIVO
  dbx_errors_redigir "${1-}${original:+ ($original)}" >/dev/null
  DBX_AUTH_MOTIVO=$DBX_ERRORS_REDIGIDO
}

# dbx_auth_falha_de_servidor — a ultima renovacao falhou com HTTP 5xx?
dbx_auth_falha_de_servidor() {
  [[ ${DBX_AUTH_CODIGO_HTTP:-} == 5?? ]]
}

# dbx_auth_token — garante um token curto valido em memoria.
dbx_auth_token() {
  local estado
  dbx_auth_expirado || return 0
  dbx_auth_renovar
  estado=$?
  if [[ $DBX_AUTH_PRIMEIRA_OBTENCAO == 'sim' ]]; then
    # Enquanto nenhum token foi obtido, cada falha passa pelo gancho (a oferta de
    # config e a sonda sao de uma vez so, no proprio gancho): o `download` pede o
    # token duas vezes antes de qualquer efeito e a causa nomeada nao pode se perder.
    if [[ $estado -ne 0 && -n $DBX_AUTH_GANCHO_FALHA ]]; then
      "$DBX_AUTH_GANCHO_FALHA" "$estado"
      estado=$?
    fi
    [[ $estado -eq 0 ]] && DBX_AUTH_PRIMEIRA_OBTENCAO='nao'
  fi
  return "$estado"
}

# dbx_auth_preparar — `dbx_auth_token` que, na falha, publica tambem a CLASSE da
# taxonomia em DBX_AUTH_CLASSE (o motivo ja esta em DBX_AUTH_MOTIVO).
#
# Conjunto onde incide: comando cuja primeira chamada falha em SILENCIO por
# desenho — o `get_metadata` do `upload` (RF-60(d): falha leva ao envio) e a
# identificacao de conta do `sync` (RF-52(a): falha segue sem memoria). Sem a
# preparacao explicita, credencial incompleta (RF-63(a)) chegava ao operador
# como `erro_remoto` sem motivo, ou como sucesso (QA-P3-02). A classe sai da
# MESMA tabela da taxonomia, percorrida aqui sem substituicao de comando.
DBX_AUTH_CLASSE=''
dbx_auth_preparar() {
  DBX_AUTH_CLASSE=''
  dbx_auth_token && return 0
  local estado=$?
  _dbx_auth_classe_de "$estado"
  return "$estado"
}

# dbx_auth_falha_e_do_token — a ultima falha de `dbx_auth_requisitar` (e irmas)
# veio da obtencao do token (DIV-327)? Quem chama nao le o canal: usa isto e
# `dbx_auth_falhar_com`, que entrega classe e motivo (ja redigido) a uma funcao.
dbx_auth_falha_e_do_token() {
  [[ -n ${DBX_AUTH_CLASSE:-} && $DBX_AUTH_CLASSE != 'desconhecido' ]]
}

# dbx_auth_falhar_com <funcao> — chama `<funcao> <classe> <motivo>` com a classe
# e o motivo da falha do token e devolve o que ela devolver.
dbx_auth_falhar_com() {
  "$1" "$DBX_AUTH_CLASSE" "${DBX_AUTH_MOTIVO:-autenticacao recusada}"
}

# _dbx_auth_classe_de <codigo> — publica em DBX_AUTH_CLASSE a classe da taxonomia
# cujo codigo de saida e <codigo> (`desconhecido` quando nenhuma).
_dbx_auth_classe_de() {
  local candidata
  # shellcheck disable=SC2034  # canal publico, lido por dbx_auth_falhar_com
  DBX_AUTH_CLASSE='desconhecido'
  for candidata in "${DBX_ERRORS_CLASSES[@]}"; do
    if [[ ${DBX_ERRORS_CODIGO[$candidata]} == "$1" ]]; then
      # shellcheck disable=SC2034  # canal publico, lido por commands/upload, commands/sync e lib/cmd
      DBX_AUTH_CLASSE=$candidata
      break
    fi
  done
}

# dbx_auth_requisitar <metodo> <url> <corpo> <idempotente>
#
# Renova NO MAXIMO uma vez por requisicao. A garantia contra laco entre renovar
# e receber `401` de novo e o sinalizador, e nao a esperanca de que a segunda
# tentativa va dar certo.
# _dbx_auth_com_renovacao <funcao> <metodo> <url> <resto...>
#
# GEMEOS: `dbx_auth_requisitar` e `dbx_auth_colecao` chamam funcoes diferentes
# de lib/http com a MESMA politica de renovacao. Escrever o laco duas vezes
# faria a proxima correcao na garantia contra laco valer para um lado so — a
# forma exata das oito ocorrencias anteriores. O laco mora aqui, uma vez.
#
# O token entra sempre na TERCEIRA posicao, que e onde as duas funcoes de
# lib/http o esperam; o restante e repassado sem interpretacao.
_dbx_auth_com_renovacao() {
  local funcao=$1 metodo=$2 url=$3
  shift 3
  local estado
  DBX_AUTH_RENOVOU='nao'
  # DIV-327: a falha do TOKEN sai pela classe do token (DBX_AUTH_CLASSE preenchida),
  # nao pela da requisicao; falha da requisicao deixa a classe vazia.
  DBX_AUTH_CLASSE=''

  while :; do
    dbx_auth_token || {
      estado=$?
      _dbx_auth_classe_de "$estado"
      return "$estado"
    }
    "$funcao" "$metodo" "$url" "$DBX_AUTH_TOKEN" "$@"
    estado=$?
    [[ $estado -eq 0 ]] && return 0
    if ! [[ $DBX_HTTP_POLITICA == 'renovar_token_uma_vez' && $DBX_AUTH_RENOVOU == 'nao' ]]; then
      # RF-151(e): falha no meio da execucao; o gancho so enriquece a mensagem.
      [[ -n $DBX_AUTH_GANCHO_MEIO ]] && "$DBX_AUTH_GANCHO_MEIO" "$estado"
      return "$estado"
    fi
    DBX_AUTH_RENOVOU='sim'
    dbx_auth_esquecer
  done
}

dbx_auth_requisitar() {
  [[ $# -ge 4 ]] || return "$DBX_AUTH_ERRO_USO"
  _dbx_auth_com_renovacao dbx_http_requisitar "$1" "$2" "$3" "$4"
}

# dbx_auth_colecao <metodo> <url> <corpo> <limite>
#
# RNF-23: o limite e EXPLICITO e a reducao por `motivo=tamanho` acontece dentro
# de lib/http. A renovacao de token vale igual, pelo mesmo laco.
dbx_auth_colecao() {
  [[ $# -ge 4 ]] || return "$DBX_AUTH_ERRO_USO"
  _dbx_auth_com_renovacao dbx_http_colecao "$1" "$2" "$3" "$4"
}

# dbx_auth_conteudo <metodo> <url> <arg_json> <arquivo> <idempotente>
#
# Modo de conteudo pelo mesmo envoltorio de renovacao: escrever o laco de novo
# faria a proxima correcao na garantia contra laco valer para um caminho so.
dbx_auth_conteudo() {
  [[ $# -ge 5 ]] || return "$DBX_AUTH_ERRO_USO"
  _dbx_auth_com_renovacao dbx_http_conteudo "$1" "$2" "$3" "$4" "$5"
}

# dbx_auth_conteudo_receber <metodo> <url> <arg_json> <destino> [inicio]
#
# Com <inicio> (fase 7a), pedido de faixa: ver `dbx_http_conteudo_receber`.
#
# A renovacao aqui tem uma restricao que os outros caminhos nao tem: so pode
# ocorrer se NADA foi emitido ao consumidor. Repetir depois do primeiro byte
# entregaria o inicio do conteudo duas vezes. A guarda vive em `lib/http`, no
# laco de retentativa, e vale igualmente para a repeticao por renovacao — que
# passa pelo mesmo caminho.
dbx_auth_conteudo_receber() {
  [[ $# -ge 4 ]] || return "$DBX_AUTH_ERRO_USO"
  _dbx_auth_com_renovacao dbx_http_conteudo_receber "$1" "$2" "$3" "$4" ${5:+"$5"}
}

# dbx_auth_conteudo_receber_faixa <metodo> <url> <arg_json> <arquivo> <inicio> <fim>
#
# F-100 (RF-180): faixa fechada gravada em arquivo proprio; ver
# `dbx_http_conteudo_receber_faixa`. Mesma renovacao de token.
dbx_auth_conteudo_receber_faixa() {
  [[ $# -ge 6 ]] || return "$DBX_AUTH_ERRO_USO"
  _dbx_auth_com_renovacao dbx_http_conteudo_receber_faixa "$1" "$2" "$3" "$4" "$5" "$6"
}

# ---------------------------------------------------------------------------
# Vinculo e desvinculo (RF-01, RF-04, RF-06a)
# ---------------------------------------------------------------------------

# dbx_auth_chave_de_aplicativo_valida <chave>
dbx_auth_chave_de_aplicativo_valida() {
  local chave=${1-}
  [[ -n $chave ]] || return 1
  [[ $chave == *[!$DBX_AUTH_ALFABETO_CHAVE]* ]] && return 1
  return 0
}

# dbx_auth_url_de_autorizacao <app_key> — imprime a URL que o operador abre.
#
# `token_access_type=offline` E O PARAMETRO QUE DECIDE TUDO. Sem ele a Dropbox
# devolve so um access token de quatro horas e NENHUM refresh token, e a
# aplicacao inteira — que se sustenta em renovar sozinha — para de funcionar no
# dia seguinte, com sintoma que aparece longe da causa. Por isso ele nao e opcao
# nem parametro: e literal desta funcao, e ha caso que reprova se sair da URL.
dbx_auth_url_de_autorizacao() {
  local chave=${1-}
  dbx_auth_chave_de_aplicativo_valida "$chave" || return "$DBX_AUTH_ERRO_USO"
  printf '%s?client_id=%s&response_type=code&token_access_type=offline' \
    "$DBX_AUTH_URL_AUTORIZAR" "$chave"
}

# dbx_auth_trocar_codigo <app_key> <app_secret> <codigo>
#
# GEMEA de `dbx_auth_renovar`: as duas postam no mesmo endpoint de token, com o
# mesmo transporte por entrada padrao, e as duas precisam limpar os canais do
# transporte antes de retornar — o corpo da resposta contem o refresh token, que
# e o segredo de maior valor do projeto. Escrever a limpeza so numa delas seria a
# forma exata das ocorrencias anteriores; por isso `_dbx_auth_limpar_transporte`
# e chamada em TODAS as saidas daqui, inclusive nas de erro.
#
# O codigo de autorizacao e de USO UNICO e expira em minutos. Isso muda o
# diagnostico: `invalid_grant` aqui NAO significa credencial revogada, como
# significa na renovacao — significa codigo expirado ou ja usado, e o remedio e
# abrir a URL de novo para obter um codigo NOVO. Dar a mesma mensagem nos dois
# lugares mandaria o operador refazer o aplicativo por um codigo vencido.
dbx_auth_trocar_codigo() {
  [[ $# -ge 3 ]] || return "$DBX_AUTH_ERRO_USO"
  local chave=$1 segredo=$2 codigo=$3
  # shellcheck disable=SC2034  # canais publicos
  DBX_AUTH_MOTIVO=''
  DBX_AUTH_REFRESH_TOKEN=''
  DBX_AUTH_CONTA=''

  [[ -n $chave && -n $codigo ]] || {
    _dbx_auth_falhar "$DBX_AUTH_ERRO_USO" 'chave de aplicativo ou codigo ausente'
    return $?
  }
  # RF-63: gemea da renovacao, a mesma recusa antes da rede.
  [[ -n $segredo ]] || {
    _dbx_auth_falhar "$DBX_AUTH_ERRO_CONFIGURACAO" 'credencial incompleta: segredo do aplicativo (app secret) ausente'
    return $?
  }

  # shellcheck disable=SC2034  # passado por nome a dbx_http_formulario
  local -a campos=(
    "grant_type=authorization_code"
    "code=$codigo"
    "client_id=$chave"
    "client_secret=$segredo"
  )

  local estado
  dbx_http_formulario "$DBX_AUTH_URL_TOKEN" campos
  estado=$?

  if [[ $estado -ne 0 ]]; then
    local erro=''
    _dbx_auth_interpretar "$DBX_HTTP_CORPO" error && erro=$DBX_AUTH_LIDO
    _dbx_auth_limpar_transporte
    if [[ $erro == 'invalid_grant' ]]; then
      _dbx_auth_falhar "$DBX_AUTH_ERRO_AUTENTICACAO" \
        'codigo de autorizacao recusado: invalid_grant (codigo expirado ou ja usado; abra a URL de autorizacao de novo e informe um codigo novo)'
      return $?
    fi
    _dbx_auth_falhar "$estado" "troca de codigo falhou (codigo ${DBX_HTTP_CODIGO:-0}${erro:+, $erro})"
    return $?
  fi

  # AUSENCIA DE REFRESH TOKEN NAO E ERRO DE SERVICO: e autorizacao pedida sem
  # `token_access_type=offline`. A resposta chega com 200 e um access token
  # perfeitamente valido, entao tratar isto como sucesso gravaria credencial que
  # funciona hoje e para de funcionar em quatro horas. O diagnostico nomeia a
  # causa em vez de descrever o sintoma.
  if ! _dbx_auth_interpretar "$DBX_HTTP_CORPO" refresh_token || [[ -z $DBX_AUTH_LIDO ]]; then
    _dbx_auth_limpar_transporte
    _dbx_auth_falhar "$DBX_AUTH_ERRO_REMOTO" \
      'resposta sem refresh_token: a autorizacao foi concedida sem token_access_type=offline'
    return $?
  fi
  DBX_AUTH_REFRESH_TOKEN=$DBX_AUTH_LIDO

  # `account_id` e informativo aqui e obrigatorio adiante: RF-52 vincula a linha
  # de base a IDENTIDADE DA CONTA, para que religar a outra conta com base antiga
  # nao apague arquivo local do operador. Registrar quando o campo vem e ausencia
  # tolerada, e o que faz a informacao existir antes de `lib/state` precisar dela.
  _dbx_auth_interpretar "$DBX_HTTP_CORPO" account_id && DBX_AUTH_CONTA=$DBX_AUTH_LIDO

  # O access token que veio junto e aproveitado: e valido, e descarta-lo obrigaria
  # a uma renovacao imediata e desnecessaria.
  local validade=0
  _dbx_auth_interpretar "$DBX_HTTP_CORPO" access_token && DBX_AUTH_TOKEN=$DBX_AUTH_LIDO
  _dbx_auth_interpretar "$DBX_HTTP_CORPO" expires_in && validade=$DBX_AUTH_LIDO
  [[ $validade =~ ^[0-9]+$ ]] || validade=0
  DBX_AUTH_EXPIRA_EM=$((SECONDS + validade - DBX_AUTH_MARGEM_SEGUNDOS))
  [[ $DBX_AUTH_EXPIRA_EM -lt 0 ]] && DBX_AUTH_EXPIRA_EM=0

  # `DBX_AUTH_LIDO` guarda o ULTIMO valor lido e passou pelo refresh token no
  # caminho acima. E o canal vizinho da mesma classe ja corrigida em lib/config.
  DBX_AUTH_LIDO=''
  _dbx_auth_limpar_transporte
  return 0
}

# dbx_auth_esquecer_vinculo — apaga da memoria o que a troca publicou.
#
# Conjunto onde incide: todo caminho que termine de usar `DBX_AUTH_REFRESH_TOKEN`
# — hoje so `commands/config`, depois qualquer religamento.
dbx_auth_esquecer_vinculo() {
  # shellcheck disable=SC2034  # canais publicos, ver nota na declaracao
  DBX_AUTH_REFRESH_TOKEN=''
  # shellcheck disable=SC2034  # canais publicos, ver nota na declaracao
  DBX_AUTH_CONTA=''
  return 0
}

# dbx_auth_revogar — revoga o token corrente junto a Dropbox (RF-04).
#
# CASCATA (RES-12, RF-06a): a revogacao NAO se limita ao access token com que a
# chamada e feita. Ela invalida o refresh token de onde ele saiu e, com ele, todo
# access token derivado — inclusive os de outras maquinas e de outros processos
# em curso. Advertir sobre isso e exigir confirmacao e obrigacao de quem chama;
# esta funcao supoe a decisao ja tomada.
#
# Sem corpo: o endpoint identifica o token pelo cabecalho de autorizacao. Marcada
# como NAO idempotente porque e escrita; repetir depois de revogar nao causa dano,
# mas a taxonomia decide retentativa por essa propriedade, e declarar escrita como
# idempotente aqui abriria excecao que o proximo caso de escrita herdaria.
dbx_auth_revogar() {
  dbx_auth_requisitar POST "$DBX_AUTH_URL_REVOGAR" '' nao
}
