#!/usr/bin/env bash
# Testes de lib/auth.sh — troca de refresh token por access token de curta duracao.
#
# O refresh token e o segredo de maior valor do sistema: com ele se obtem acesso
# indefinido a conta. As provas de nao vazamento usam `assert_segredo_ausente`,
# que reprova sem imprimir a agulha — `assert_nao_contem` imprimiria o segredo
# exatamente quando ha falha, e desde que o diario grava em disco isso seria um
# deposito de credencial.
#
# shellcheck disable=SC2016
# Justificativa: casos escrevem o substituto de `curl`, que precisa chegar sem
# expansao.
#
# shellcheck disable=SC2034
# Justificativa: os casos ATRIBUEM os canais publicos que o componente sob teste
# consome (`DBX_CONFIG_*`, `DBX_AUTH_EXPIRA_EM`). A analise estatica nao cruza os
# arquivos e os ve como escrita sem leitura; a leitura esta em lib/auth.sh.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"
. "$DBX_HARNESS_RAIZ/lib/auth.sh"

readonly REFRESH='RT_9pQrStUvWxYz_refresh_de_teste'
readonly APP_KEY='ak_publico_de_teste'
readonly APP_SECRET='as_segredo_de_teste'

# _duplo <status> <corpo> — substituto de `curl` que registra argv e entrada.
_duplo() {
  local status=$1 corpo=$2 dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/duplo.XXXXXX")
  printf '%s' "$corpo" >"$dir/corpo"
  printf '%s\n' "$status" >"$dir/status"
  : >"$dir/cabecalhos"
  : >"$dir/argv"
  : >"$dir/entrada"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'dir=%s\n' "$dir"
    printf 'printf "%%s\\n" "$*" >>"$dir/argv"\n'
    printf 'cat >>"$dir/entrada" 2>/dev/null\n'
    printf 'saida=""; cabecalhos=""; escrever=""; anterior=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in\n'
    printf '    -o) saida=$arg ;;\n'
    printf '    -D) cabecalhos=$arg ;;\n'
    printf '    -w) escrever=$arg ;;\n'
    printf '  esac\n'
    printf '  case $arg in\n'
    printf '    @*) [[ -r ${arg#@} ]] && cat "${arg#@}" >>"$dir/enviado" ;;\n'
    printf '  esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf '[[ -n $saida ]] && cp "$dir/corpo" "$saida"\n'
    printf '[[ -n $cabecalhos ]] && cp "$dir/cabecalhos" "$cabecalhos"\n'
    printf '[[ -n $escrever ]] && printf "%%s" "$(cat "$dir/status")"\n'
    printf 'exit 0\n'
  } >"$dir/curl"
  chmod +x "$dir/curl"
  printf '%s' "$dir"
}

_credencial() {
  DBX_CONFIG_APP_KEY=$APP_KEY
  DBX_CONFIG_APP_SECRET=$APP_SECRET
  DBX_CONFIG_REFRESH_TOKEN=$REFRESH
  dbx_auth_esquecer
}

_ler_arquivo() {
  DBX_LIDO=''
  [[ -r $1 ]] && IFS= read -r -d '' DBX_LIDO <"$1"
  return 0
}

_resposta_de_token() { printf '{"access_token":"sl.AC_token_curto","token_type":"bearer","expires_in":14400}'; }

# ---------------------------------------------------------------------------
# Contrato
# ---------------------------------------------------------------------------

teste_status_seguem_a_taxonomia_de_erro() {
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_AUTH_ERRO_USO"
  assert_igual "$(dbx_errors_codigo_saida autenticacao)" "$DBX_AUTH_ERRO_AUTENTICACAO"
}

teste_nao_invoca_o_cliente_de_rede_diretamente() {
  # A saida de rede continua unica: lib/auth passa por lib/http.
  assert_arquivo_existe "$DBX_HARNESS_RAIZ/lib/auth.sh" 'sem o arquivo a auditoria seria vacua'
  local achados
  achados=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/auth.sh" |
    grep -nE '(^|[^-_a-zA-Z/])curl' || true)
  [[ -n $achados ]] && _harness_falhar "lib/auth invoca o cliente diretamente: $achados"
  return 0
}

teste_nao_recebe_identificador_de_conta_ou_perfil() {
  # DP-05: conta unica, sem nocao de perfil.
  assert_arquivo_existe "$DBX_HARNESS_RAIZ/lib/auth.sh" 'sem o arquivo a auditoria seria vacua'
  local achados
  achados=$(grep -nE '(perfil|profile|account_id|conta=)' "$DBX_HARNESS_RAIZ/lib/auth.sh" |
    grep -vE '^[0-9]*:[[:space:]]*#' || true)
  [[ -n $achados ]] && _harness_falhar "nocao de conta ou perfil em lib/auth: $achados"
  return 0
}

# ---------------------------------------------------------------------------
# Renovacao
# ---------------------------------------------------------------------------

teste_renovacao_obtem_token_de_curta_duracao() {
  local dir
  dir=$(_duplo 200 "$(_resposta_de_token)")
  _credencial
  PATH=$dir:$PATH dbx_auth_renovar
  assert_igual 0 $? 'renovacao deve concluir'
  assert_igual 'sl.AC_token_curto' "$DBX_AUTH_TOKEN" 'token curto deve ficar em memoria'
}

teste_refresh_token_nunca_aparece_na_linha_de_comando() {
  local dir
  dir=$(_duplo 200 "$(_resposta_de_token)")
  _credencial
  PATH=$dir:$PATH dbx_auth_renovar
  _ler_arquivo "$dir/argv"
  assert_segredo_ausente "$REFRESH" "$DBX_LIDO" 'refresh token em argv (visivel em /proc)'
  assert_segredo_ausente "$APP_SECRET" "$DBX_LIDO" 'segredo do aplicativo em argv'
}

teste_refresh_token_chega_pela_entrada_padrao() {
  local dir
  dir=$(_duplo 200 "$(_resposta_de_token)")
  _credencial
  PATH=$dir:$PATH dbx_auth_renovar
  _ler_arquivo "$dir/entrada"
  assert_contem "$REFRESH" "$DBX_LIDO" 'o segredo tem de trafegar pela entrada padrao'
  assert_contem 'grant_type' "$DBX_LIDO" 'o tipo de concessao deve ser enviado'
}

teste_refresh_token_nunca_e_escrito_em_arquivo_de_corpo() {
  local dir
  dir=$(_duplo 200 "$(_resposta_de_token)")
  _credencial
  PATH=$dir:$PATH dbx_auth_renovar
  _ler_arquivo "$dir/enviado"
  assert_segredo_ausente "$REFRESH" "$DBX_LIDO" 'refresh token gravado em disco no corpo'
  assert_arquivo_ausente "$dir/enviado" 'a renovacao nao deve usar corpo em arquivo'
}

teste_refresh_token_nao_vaza_nos_canais_publicos_apos_renovar() {
  local dir
  dir=$(_duplo 200 "$(_resposta_de_token)")
  _credencial
  PATH=$dir:$PATH dbx_auth_renovar
  assert_segredo_ausente "$REFRESH" "$DBX_HTTP_CORPO" 'corpo publicado'
  assert_segredo_ausente "$REFRESH" "$DBX_HTTP_RESUMO_DE_ERRO" 'resumo de erro'
  assert_segredo_ausente "$REFRESH" "$DBX_AUTH_MOTIVO" 'motivo publicado'
}

teste_falha_de_renovacao_nao_vaza_o_refresh_token_no_motivo() {
  local dir
  dir=$(_duplo 400 '{"error":"invalid_grant","error_description":"refresh token is invalid"}')
  _credencial
  PATH=$dir:$PATH dbx_auth_renovar
  assert_diferente 0 $? 'concessao invalida deve falhar'
  assert_segredo_ausente "$REFRESH" "$DBX_AUTH_MOTIVO" 'motivo de falha'
  assert_segredo_ausente "$APP_SECRET" "$DBX_AUTH_MOTIVO" 'segredo do aplicativo no motivo'
}

teste_concessao_invalida_e_terminal_e_nao_e_retentada() {
  local dir
  dir=$(_duplo 400 '{"error":"invalid_grant","error_description":"revogado"}')
  _credencial
  PATH=$dir:$PATH dbx_auth_renovar
  local estado=$?
  assert_igual "$DBX_AUTH_ERRO_AUTENTICACAO" "$estado" 'concessao invalida e erro de autenticacao'
  assert_contem 'invalid_grant' "$DBX_AUTH_MOTIVO" 'o motivo deve identificar a concessao invalida'
  assert_igual 1 "$(grep -c . "$dir/argv")" 'nao pode haver retentativa de concessao invalida'
}

teste_renovacao_falha_sem_credencial_carregada() {
  DBX_CONFIG_APP_KEY=''
  DBX_CONFIG_APP_SECRET=''
  DBX_CONFIG_REFRESH_TOKEN=''
  dbx_auth_esquecer
  dbx_auth_renovar
  assert_igual "$DBX_AUTH_ERRO_USO" $? 'sem credencial a renovacao deve recusar antes de sair na rede'
}

teste_esquecer_apaga_o_token_da_memoria() {
  local dir
  dir=$(_duplo 200 "$(_resposta_de_token)")
  _credencial
  PATH=$dir:$PATH dbx_auth_renovar
  assert_diferente '' "$DBX_AUTH_TOKEN" 'token deve existir antes'
  dbx_auth_esquecer
  assert_igual '' "$DBX_AUTH_TOKEN" 'token deve sumir da memoria'
}

teste_nao_grava_estado_em_disco_ao_renovar() {
  # PRJ-DEC-07: o MVP nao tem estado local persistente; a unica escrita prevista
  # em todo o projeto e o arquivo de credencial, e a renovacao nao o reescreve
  # porque a Dropbox nao rotaciona o refresh token.
  local dir marca
  dir=$(_duplo 200 "$(_resposta_de_token)")
  marca=$DBX_TESTES_TMP/marca.$$
  mkdir -p "$marca"
  _credencial
  HOME=$marca XDG_CONFIG_HOME=$marca/config PATH=$dir:$PATH dbx_auth_renovar
  local achados
  achados=$(find "$marca" -type f 2>/dev/null || true)
  [[ -n $achados ]] && _harness_falhar 'a renovacao escreveu estado em disco' "$achados"
  return 0
}

# ---------------------------------------------------------------------------
# Token em memoria e validade
# ---------------------------------------------------------------------------

teste_token_valido_e_reaproveitado_sem_nova_renovacao() {
  local dir
  dir=$(_duplo 200 "$(_resposta_de_token)")
  _credencial
  PATH=$dir:$PATH dbx_auth_token
  PATH=$dir:$PATH dbx_auth_token
  assert_igual 1 "$(grep -c . "$dir/argv")" 'token ainda valido nao pode disparar nova troca'
}

teste_token_expirado_dispara_nova_renovacao() {
  local dir
  dir=$(_duplo 200 "$(_resposta_de_token)")
  _credencial
  PATH=$dir:$PATH dbx_auth_token
  DBX_AUTH_EXPIRA_EM=0
  PATH=$dir:$PATH dbx_auth_token
  assert_igual 2 "$(grep -c . "$dir/argv")" 'token expirado tem de ser trocado'
}

teste_validade_respeita_margem_antes_do_vencimento() {
  local dir
  dir=$(_duplo 200 '{"access_token":"sl.curto","token_type":"bearer","expires_in":10}'
  )
  _credencial
  PATH=$dir:$PATH dbx_auth_renovar
  # Com validade menor que a margem, o token ja nasce vencido: melhor trocar de
  # novo que emitir requisicao com token que expira em transito.
  assert_igual 'sim' "$(dbx_auth_expirado && printf sim || printf nao)" \
    'token com validade abaixo da margem deve ser tratado como expirado'
}

teste_resposta_sem_token_e_recusada() {
  local dir
  dir=$(_duplo 200 '{"token_type":"bearer","expires_in":14400}')
  _credencial
  PATH=$dir:$PATH dbx_auth_renovar
  assert_diferente 0 $? 'resposta sem token nao pode ser aceita como sucesso'
  assert_igual '' "$DBX_AUTH_TOKEN" 'nada pode ser guardado de resposta invalida'
}

# ---------------------------------------------------------------------------
# Requisicao autenticada e renovacao no meio do caminho
# ---------------------------------------------------------------------------

teste_requisicao_usa_o_token_curto_e_nao_o_refresh() {
  local dir
  dir=$(_duplo 200 "$(_resposta_de_token)")
  _credencial
  PATH=$dir:$PATH dbx_auth_token
  local dir2
  dir2=$(_duplo 200 '{"ok":true}')
  PATH=$dir2:$PATH dbx_auth_requisitar POST https://exemplo/api '{"a":1}' sim
  _ler_arquivo "$dir2/entrada"
  assert_contem 'sl.AC_token_curto' "$DBX_LIDO" 'a requisicao deve portar o token curto'
  assert_segredo_ausente "$REFRESH" "$DBX_LIDO" 'refresh token na requisicao comum'
}

teste_token_expirado_no_meio_do_caminho_renova_uma_vez_e_repete() {
  local dir
  dir=$(_duplo 401 '{"error_summary":"expired_access_token/..."}')
  _credencial
  DBX_AUTH_TOKEN='sl.velho'
  DBX_AUTH_EXPIRA_EM=$((SECONDS + 3600))
  PATH=$dir:$PATH dbx_auth_requisitar POST https://exemplo/api '{}' sim
  # Uma renovacao e no maximo uma repeticao: sem laco entre renovar e 401.
  assert_igual 'sim' "$DBX_AUTH_RENOVOU" 'deve ter havido renovacao'
  local chamadas
  chamadas=$(grep -c . "$dir/argv")
  [[ $chamadas -le 4 ]] || _harness_falhar 'laco entre renovacao e 401' "chamadas: $chamadas"
  return 0
}

teste_renovacao_no_meio_do_caminho_nao_repete_indefinidamente() {
  local dir
  dir=$(_duplo 401 '{"error_summary":"expired_access_token/..."}')
  _credencial
  DBX_AUTH_TOKEN='sl.velho'
  DBX_AUTH_EXPIRA_EM=$((SECONDS + 3600))
  PATH=$dir:$PATH dbx_auth_requisitar POST https://exemplo/api '{}' sim
  assert_diferente 0 $? 'apos renovar e falhar de novo, tem de desistir'
}

# _duplo_por_url — responde conforme o destino: sucesso no endpoint de token,
# `401` no da API. E a unica configuracao que produz o laco de verdade —
# renovacao BEM SUCEDIDA seguida de novo `401`. Com um duplo que falha tambem na
# renovacao, remover a garantia de "uma vez" nao muda nada e a prova nao
# discrimina; foi medido, o caso passava com a garantia removida.
#
# O proprio duplo recusa depois de um teto de chamadas, para que o laco, se
# existir, termine e vire reprovacao em vez de travar a suite.
_duplo_por_url() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/duploURL.XXXXXX")
  : >"$dir/argv"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'dir=%s\n' "$dir"
    printf 'printf "%%s\\n" "$*" >>"$dir/argv"\n'
    printf 'cat >/dev/null 2>&1\n'
    printf 'if [[ $(grep -c . "$dir/argv") -gt 8 ]]; then exit 7; fi\n'
    printf 'saida=""; escrever=""; anterior=""; url=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac\n'
    printf '  case $arg in http*) url=$arg ;; esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf 'if [[ $url == *oauth2/token* ]]; then\n'
    printf '  corpo=%s; codigo=200\n' "'{\"access_token\":\"sl.novo\",\"token_type\":\"bearer\",\"expires_in\":14400}'"
    printf 'else\n'
    printf '  corpo=%s; codigo=401\n' "'{\"error_summary\":\"expired_access_token/...\"}'"
    printf 'fi\n'
    printf '[[ -n $saida ]] && printf "%%s" "$corpo" >"$saida"\n'
    printf '[[ -n $escrever ]] && printf "%%s" "$codigo"\n'
    printf 'exit 0\n'
  } >"$dir/curl"
  chmod +x "$dir/curl"
  printf '%s' "$dir"
}

teste_renovacao_bem_sucedida_seguida_de_401_nao_entra_em_laco() {
  local dir
  dir=$(_duplo_por_url)
  _credencial
  DBX_AUTH_TOKEN='sl.velho'
  DBX_AUTH_EXPIRA_EM=$((SECONDS + 3600))
  PATH=$dir:$PATH dbx_auth_requisitar POST https://exemplo/api '{}' sim
  assert_diferente 0 $? 'apos renovar e receber 401 de novo, tem de desistir'
  local chamadas
  chamadas=$(grep -c . "$dir/argv")
  # Requisicao, renovacao, requisicao: tres. Mais que isso e laco.
  [[ $chamadas -le 3 ]] ||
    _harness_falhar 'laco entre renovacao e 401' "chamadas ao cliente: $chamadas"
  return 0
}

# ---------------------------------------------------------------------------
# QH-01: o canal adjacente
# ---------------------------------------------------------------------------

teste_canal_de_corpo_do_transporte_nao_retem_o_token_apos_renovar() {
  local dir
  dir=$(_duplo 200 "$(_resposta_de_token)")
  _credencial
  PATH=$dir:$PATH dbx_auth_renovar
  assert_igual 0 $? 'renovacao deve concluir'
  assert_segredo_ausente 'sl.AC_token_curto' "$DBX_HTTP_CORPO" \
    'access token retido no canal de corpo do transporte'
  assert_segredo_ausente 'sl.AC_token_curto' "$DBX_JSON_RESULTADO" \
    'access token retido no canal de resultado do analisador'
}

teste_canal_de_corpo_nao_retem_segredo_quando_o_servico_ecoa_a_requisicao() {
  # Servico que devolve no corpo o que recebeu: caminho realista de depuracao
  # em servidor mal configurado, e o pior caso para canal publico esquecido.
  local dir eco
  eco="{\"error\":\"invalid_request\",\"echo\":\"refresh_token $REFRESH client_secret=$APP_SECRET\"}"
  dir=$(_duplo 400 "$eco")
  _credencial
  PATH=$dir:$PATH dbx_auth_renovar
  assert_diferente 0 $? 'a chamada deve falhar'
  assert_segredo_ausente "$REFRESH" "$DBX_HTTP_CORPO" 'refresh token retido no corpo publicado'
  assert_segredo_ausente "$APP_SECRET" "$DBX_HTTP_CORPO" 'segredo do aplicativo retido no corpo'
  assert_segredo_ausente "$REFRESH" "$DBX_HTTP_RESUMO_DE_ERRO" 'refresh token no resumo'
  assert_segredo_ausente "$REFRESH" "$DBX_JSON_RESULTADO" 'refresh token no resultado do analisador'
}

teste_limpeza_do_transporte_nao_apaga_a_resposta_que_o_chamador_precisa() {
  # A limpeza tem de ser SELETIVA: no caminho de requisicao comum o corpo e o
  # dado util. Zelo aplicado sem criterio viraria defeito.
  local dir
  dir=$(_duplo 200 "$(_resposta_de_token)")
  _credencial
  PATH=$dir:$PATH dbx_auth_token
  local dir2
  dir2=$(_duplo 200 '{"entries":[],"has_more":false}')
  PATH=$dir2:$PATH dbx_auth_requisitar POST https://exemplo/api '{}' sim
  assert_igual 0 $? 'requisicao deve concluir'
  assert_contem 'has_more' "$DBX_HTTP_CORPO" 'a resposta da API tem de continuar disponivel'
}

harness_executar "$@"
