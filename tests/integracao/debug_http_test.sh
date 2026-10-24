#!/usr/bin/env bash
# Integracao do --debug de transferencias, parte 1 (RF-156, RF-157, RF-163,
# RF-164): linha por tentativa HTTP, sentinelas de segredo, stdout identico com
# e sem --debug, ausencia de linhas sem --debug.
#
# TC-DBG-01..07 e TC-DBG-22..30. Duplo de curl: tests/support/disponibilidade.sh
# (estendido com `<papel>.fila`, `-D`, `content_corpo` e o `-w` ampliado).
#
# shellcheck disable=SC2016
# Justificativa: scripts auxiliares sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"
# shellcheck source=tests/support/disponibilidade.sh
. "$DBX_HARNESS_RAIZ/tests/support/disponibilidade.sh"

# Caminho so para host `*.dropboxapi.com`; o token (`api.dropbox.com`) sai so com o host (RF-157(b)).
DBG_REGEX_HTTP='^debug: http [A-Z]+ [a-z.]+(/[a-z0-9_/]+)? tentativa=[0-9]+ status=[0-9]+ duracao_ms=[0-9]+ enviados=[0-9]+ recebidos=[0-9]+'

_dbg_cenario() {
  local base
  base=$(_cenario)
  head -c 10240 /dev/zero >"$base/arq.bin"
  printf '10240' >"$base/enviados"
  printf '409' >"$base/rpc"
  printf '%s' '{"error_summary":"path/not_found/.","error":{".tag":"path","path":{".tag":"not_found"}}}' >"$base/rpc_corpo"
  printf '%s' '{"name":"arq.bin","path_display":"/arq.bin","size":10240,"content_hash":"0000"}' >"$base/content_corpo"
  printf '200' >"$base/content"
  printf '%s' "$base"
}

# _dbg_executar <base> <argumentos...> — como _rodar, com variaveis extras de
# DBX_T_EXTRAS (espera curta, tentativas).
_dbg_executar() {
  local base=$1
  shift
  env -i PATH="$base/bin" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
    TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=2 \
    "${DBX_T_EXTRAS[@]}" "$BASH_ABSOLUTO" "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err" </dev/null
  DBX_ESTADO=$?
  DBX_SAIDA='' DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_dbg_linhas_http() { # <base> — as linhas `debug: http` do stderr
  local linha saida=''
  while IFS= read -r linha; do
    [[ $linha == 'debug: http '* ]] && saida+="$linha"$'\n'
  done <"$1/err"
  printf '%s' "$saida"
}

_conta_linhas() { # <arquivo> — numero de linhas
  local n=0 linha
  while IFS= read -r linha || [[ -n $linha ]]; do n=$((n + 1)); done <"$1"
  printf '%s' "$n"
}

_dbg_conta() { # <texto> — numero de linhas nao vazias
  local n=0 linha
  while IFS= read -r linha; do [[ -n $linha ]] && n=$((n + 1)); done <<<"$1"
  printf '%s' "$n"
}

# ---------------------------------------------------------------------------
# RF-157: uma linha por tentativa
# ---------------------------------------------------------------------------

teste_tc_dbg_01_upload_emite_linha_http_com_medidas() {
  local base linhas
  base=$(_dbg_cenario)
  _dbg_executar "$base" --debug upload "$base/arq.bin" /arq.bin
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  linhas=$(_dbg_linhas_http "$base")
  assert_contem 'debug: http POST content.dropboxapi.com/2/files/upload tentativa=1 status=200 duracao_ms=250 enviados=10240 recebidos=' "$linhas"
  assert_contem 'debug: http POST api.dropbox.com tentativa=1 status=200' "$linhas"
  local linha
  while IFS= read -r linha; do
    [[ $linha =~ $DBG_REGEX_HTTP ]] || _harness_falhar "linha fora do formato: $linha"
  done <<<"$linhas"
}

teste_tc_dbg_02_retentativa_5xx_gera_uma_linha_por_tentativa() {
  local base linhas
  base=$(_dbg_cenario)
  printf '503\n503\n200\n' >"$base/content.fila"
  DBX_T_EXTRAS=(DBX_HTTP_TENTATIVAS_MAXIMAS=4)
  _dbg_executar "$base" --debug download /arq.bin -
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  linhas=$(_dbg_linhas_http "$base")
  assert_contem 'files/download tentativa=1 status=503' "$linhas"
  assert_contem 'files/download tentativa=2 status=503' "$linhas"
  assert_contem 'files/download tentativa=3 status=200' "$linhas"
  assert_nao_contem 'tentativa=4' "$linhas"
  assert_contem 'espera_ms=' "$(grep -F 'tentativa=1 ' <<<"$linhas")"
  assert_contem 'espera_ms=' "$(grep -F 'tentativa=2 ' <<<"$linhas")"
  assert_nao_contem 'espera_ms=' "$(grep -F 'tentativa=3 ' <<<"$linhas")"
  DBX_T_EXTRAS=()
}

teste_tc_dbg_03_429_com_retry_after_vem_depois_de_recebidos() {
  local base linhas
  base=$(_dbg_cenario)
  printf '429 1\n200\n' >"$base/content.fila"
  DBX_T_EXTRAS=(DBX_HTTP_TENTATIVAS_MAXIMAS=3)
  _dbg_executar "$base" --debug download /arq.bin -
  linhas=$(_dbg_linhas_http "$base")
  assert_contem 'status=429 duracao_ms=250 enviados=0 recebidos=' "$(grep -F 'tentativa=1 ' <<<"$linhas")"
  [[ $(grep -F 'tentativa=1 ' <<<"$linhas") =~ recebidos=[0-9]+\ retry_after=1\ espera_ms= ]] ||
    _harness_falhar "retry_after fora de ordem: $linhas"
  DBX_T_EXTRAS=()
}

teste_tc_dbg_04_retry_after_acima_do_teto_mostra_o_valor_efetivo() {
  local base linhas
  base=$(_dbg_cenario)
  printf '429 99999\n200\n' >"$base/content.fila"
  DBX_T_EXTRAS=(DBX_HTTP_TENTATIVAS_MAXIMAS=3 DBX_HTTP_RETRY_AFTER_TETO_S=1)
  _dbg_executar "$base" --debug download /arq.bin -
  linhas=$(_dbg_linhas_http "$base")
  assert_contem 'retry_after=1 ' "$linhas"
  assert_nao_contem '99999' "$linhas"
  DBX_T_EXTRAS=()
}

teste_tc_dbg_05_falha_de_transporte_tem_status_zero_e_curl() {
  local base linhas
  base=$(_dbg_cenario)
  printf 'falha:7' >"$base/content"
  _dbg_executar "$base" --debug upload "$base/arq.bin" /arq.bin
  linhas=$(_dbg_linhas_http "$base")
  assert_contem 'files/upload tentativa=1 status=0 curl=7 ' "$linhas"
}

teste_tc_dbg_06_endpoint_nao_tem_esquema_userinfo_porta_query_nem_fragmento() {
  _dbx_http_endpoint_debug 'https://usuario:senha@content.dropboxapi.com:443/2/files/upload?arg=segredo#frag'
  assert_igual 'content.dropboxapi.com/2/files/upload' "$_DBX_HTTP_ENDPOINT_DEBUG"
}

teste_tc_dbg_07_host_fora_de_dropboxapi_sai_so_como_host() {
  _dbx_http_endpoint_debug 'https://uc123.dl.example.com/cd/0/get/caminho/privado?token=segredo'
  assert_igual 'uc123.dl.example.com' "$_DBX_HTTP_ENDPOINT_DEBUG"
}

# ---------------------------------------------------------------------------
# RF-164: segredos
# ---------------------------------------------------------------------------

teste_tc_dbg_22_26_sentinelas_ausentes_de_stdout_e_stderr_com_retentativa_e_falha() {
  local base tudo
  base=$(_dbg_cenario)
  printf '503\n503\n503\n' >"$base/content.fila"
  DBX_T_EXTRAS=(DBX_HTTP_TENTATIVAS_MAXIMAS=3)
  _dbg_executar "$base" --debug download /arq.bin -
  assert_contem 'debug: http' "$DBX_ERRO"
  tudo="$DBX_SAIDA$DBX_ERRO"
  assert_nao_contem "$SENTINELA_TOKEN" "$tudo"
  assert_nao_contem "$SENTINELA_REFRESH" "$tudo"
  assert_nao_contem "$SENTINELA_SEGREDO" "$tudo"
  assert_nao_contem "$SENTINELA_CHAVE" "$tudo"
  assert_nao_contem 'Authorization' "$tudo"
  assert_nao_contem 'Bearer' "$tudo"
  DBX_T_EXTRAS=()
}

teste_tc_dbg_24_26_id_de_sessao_query_e_url_temporaria_ficam_fora_da_linha() {
  local base saida
  base=$(_dbg_cenario)
  printf '%s' '{"session_id":"SESSAO_SENTINELA_77aa"}' >"$base/content_corpo"
  _dbg_executar "$base" --debug upload "$base/arq.bin" /arq.bin
  assert_nao_contem 'SESSAO_SENTINELA_77aa' "$DBX_SAIDA$DBX_ERRO"
  saida=$(DBX_CLI_DEBUG=sim PATH="$base/bin" dbx_http_conteudo POST \
    'https://content.dropboxapi.com/2/files/upload_session/append_v2?cursor=CURSOR_SENTINELA_55&t=URL_TEMP_SENTINELA_66' \
    "$SENTINELA_TOKEN" '{"p":"SENHA_LINK_SENTINELA_88"}' sim 2>&1 >/dev/null)
  assert_nao_contem 'CURSOR_SENTINELA_55' "$saida"
  assert_nao_contem 'URL_TEMP_SENTINELA_66' "$saida"
  assert_nao_contem 'SENHA_LINK_SENTINELA_88' "$saida"
  assert_nao_contem "$SENTINELA_TOKEN" "$saida"
}

# ---------------------------------------------------------------------------
# RF-163: invariantes
# ---------------------------------------------------------------------------

teste_tc_dbg_28_29_stdout_e_requisicoes_iguais_com_e_sem_debug_no_upload() {
  local base_a base_b
  base_a=$(_dbg_cenario)
  base_b=$(_dbg_cenario)
  _dbg_executar "$base_a" --json upload "$base_a/arq.bin" /arq.bin
  assert_igual 0 "$DBX_ESTADO" "upload sem --debug: $DBX_ERRO"
  _dbg_executar "$base_b" --debug --json upload "$base_b/arq.bin" /arq.bin
  assert_igual 0 "$DBX_ESTADO" "upload com --debug: $DBX_ERRO"
  # So o diretorio temporario de cada cenario difere (`origem=`); o resto e byte a byte.
  local saida_a saida_b
  saida_a=$(cat "$base_a/out") saida_b=$(cat "$base_b/out")
  assert_igual "${saida_a//"$base_a"/BASE}" "${saida_b//"$base_b"/BASE}"
  assert_igual "$(cat "$base_a/chamadas")" "$(cat "$base_b/chamadas")"
  assert_nao_contem 'debug:' "$(cat "$base_a/err")"
  assert_contem 'debug: http' "$(cat "$base_b/err")"
}

teste_tc_dbg_28_29_stdout_e_requisicoes_iguais_com_e_sem_debug_no_download() {
  local base_a base_b
  base_a=$(_dbg_cenario)
  base_b=$(_dbg_cenario)
  printf 'conteudo remoto' >"$base_a/content_corpo"
  printf 'conteudo remoto' >"$base_b/content_corpo"
  _dbg_executar "$base_a" download /arq.bin -
  _dbg_executar "$base_b" --debug download /arq.bin -
  assert_igual 'conteudo remoto' "$(cat "$base_a/out")"
  cmp -s "$base_a/out" "$base_b/out" || _harness_falhar 'stdout do download difere com --debug'
  assert_igual "$(cat "$base_a/chamadas")" "$(cat "$base_b/chamadas")"
  assert_nao_contem 'debug:' "$(cat "$base_a/err")"
}

teste_tc_dbg_28_29_stdout_e_requisicoes_iguais_com_e_sem_debug_no_sync() {
  local base_a base_b dir_a dir_b
  base_a=$(_dbg_cenario)
  base_b=$(_dbg_cenario)
  printf '200' >"$base_a/rpc"
  printf '200' >"$base_b/rpc"
  printf '%s' '{"entries":[],"cursor":"C1","has_more":false}' >"$base_a/rpc_corpo"
  printf '%s' '{"entries":[],"cursor":"C1","has_more":false}' >"$base_b/rpc_corpo"
  dir_a="$base_a/loc" dir_b="$base_b/loc"
  mkdir "$dir_a" "$dir_b"
  local estado_a saida_a saida_b
  _dbg_executar "$base_a" sync --enviar --origem "$dir_a" --destino /r
  estado_a=$DBX_ESTADO
  [[ -s $base_a/chamadas ]] || _harness_falhar "o sync nao fez requisicao (estado $estado_a): $DBX_ERRO"
  _dbg_executar "$base_b" --debug sync --enviar --origem "$dir_b" --destino /r
  assert_igual "$estado_a" "$DBX_ESTADO" 'codigo de saida igual com e sem --debug'
  saida_a=$(cat "$base_a/out") saida_b=$(cat "$base_b/out")
  assert_igual "${saida_a//"$base_a"/BASE}" "${saida_b//"$base_b"/BASE}" 'stdout do sync igual com --debug'
  assert_contem 'debug: http' "$(cat "$base_b/err")"
  assert_igual "$(cat "$base_a/chamadas")" "$(cat "$base_b/chamadas")"
  assert_nao_contem 'debug:' "$(cat "$base_a/err")"
}

teste_tc_dbg_30_sem_debug_nenhuma_linha_nos_tres_comandos() {
  local base
  base=$(_dbg_cenario)
  _dbg_executar "$base" upload "$base/arq.bin" /arq.bin
  assert_nao_contem 'debug:' "$DBX_SAIDA$DBX_ERRO"
  _dbg_executar "$base" download /arq.bin -
  assert_nao_contem 'debug:' "$DBX_SAIDA$DBX_ERRO"
  _dbg_executar "$base" sync --enviar "$base/tmp" /r
  assert_nao_contem 'debug:' "$DBX_SAIDA$DBX_ERRO"
}

teste_tc_dbg_27_nome_com_controle_sai_em_uma_so_linha() {
  local linhas
  linhas=$(DBX_CLI_DEBUG=sim dbx_debug_linha upload $'arquivo=a\nb\x01c' 2>&1 >/dev/null)
  assert_igual 1 "$(_dbg_conta "$linhas")"
  assert_contem 'a?b?c' "$linhas"
}

# ---------------------------------------------------------------------------
# RF-162: resumo no fim (TC-DBG-31, TC-DBG-32, RF-162(e))
# ---------------------------------------------------------------------------

teste_tc_dbg_rf162_upload_tem_um_resumo_com_totais_das_linhas_http() {
  local base linha n=0 env=0 rec=0 resumo=''
  base=$(_dbg_cenario)
  _dbg_executar "$base" --debug upload "$base/arq.bin" /arq.bin
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  while IFS= read -r linha; do
    if [[ $linha == 'debug: http '* ]]; then
      [[ $linha == *' tentativa=1 '* ]] && n=$((n + 1))
      [[ $linha =~ ' enviados='([0-9]+) ]] && env=$((env + BASH_REMATCH[1]))
      [[ $linha =~ ' recebidos='([0-9]+) ]] && rec=$((rec + BASH_REMATCH[1]))
    fi
    [[ $linha == 'debug: resumo '* ]] && resumo+="$linha"$'\n'
  done <"$base/err"
  assert_igual 1 "$(_dbg_conta "$resumo")" 'um so resumo'
  assert_igual "$n" "$(_conta_linhas "$base/chamadas")" 'chamadas = requisicoes feitas'
  # RF-162(a)(e): os totais sao a soma das linhas http.
  assert_contem "debug: resumo comando=upload chamadas=$n tentativas_extras=0 limites_429=0 enviados=$env recebidos=$rec " "$resumo"
  assert_contem ' saida=0' "$resumo"
  assert_nao_contem 'paralelo=' "$resumo" 'fora do sync paralelo o resumo omite paralelo'
}

teste_tc_dbg_32_download_com_falha_tem_resumo_com_o_codigo_e_a_mensagem_de_sempre() {
  local base
  base=$(_dbg_cenario)
  printf '503' >"$base/content"
  _dbg_executar "$base" download /arq.bin -
  local estado_sem=$DBX_ESTADO erro_sem=$DBX_ERRO
  base=$(_dbg_cenario)
  printf '503' >"$base/content"
  _dbg_executar "$base" --debug download /arq.bin -
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'o 503 deveria falhar o download'
  assert_igual "$estado_sem" "$DBX_ESTADO" 'mesmo codigo com e sem --debug'
  assert_contem "debug: resumo comando=download " "$DBX_ERRO"
  assert_contem " saida=$DBX_ESTADO" "$DBX_ERRO" 'resumo traz o codigo real'
  # A mensagem de erro de sempre continua (sem as linhas debug, igual a sem --debug).
  local linha sem_debug=''
  while IFS= read -r linha; do
    [[ $linha == 'debug: '* ]] || sem_debug+="$linha"$'\n'
  done <"$base/err"
  assert_igual "$erro_sem" "$sem_debug" 'stderr sem as linhas debug e o de sempre'
}

# ---------------------------------------------------------------------------
# Achados da conformidade (rodada 1): resumo armado antes do requisito, sonda
# contada, codigo de saida que nao vem do ambiente
# ---------------------------------------------------------------------------

teste_rf162a_credencial_ausente_tambem_tem_resumo_com_o_codigo() {
  local base
  base=$(_dbg_cenario)
  rm -f "$base/config/dbx/credencial.json"
  _dbg_executar "$base" --debug download /arq.bin -
  assert_igual 3 "$DBX_ESTADO" "credencial ausente sem terminal sai 3: $DBX_ERRO"
  assert_contem 'debug: resumo comando=download chamadas=0 ' "$DBX_ERRO" 'resumo mesmo antes de qualquer requisicao'
  assert_contem ' saida=3' "$DBX_ERRO" 'com o codigo real'
}

teste_rf162e_sonda_entra_em_chamadas() {
  local base n=0
  base=$(_dbg_cenario)
  printf 'falha' >"$base/content"
  _dbg_executar "$base" --debug download /arq.bin -
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'a falha de rede deveria falhar o download'
  assert_contem 'debug: sonda ' "$DBX_ERRO" 'a sonda rodou'
  n=$(_conta_linhas "$base/chamadas")
  assert_contem "debug: resumo comando=download chamadas=$n " "$DBX_ERRO" 'chamadas = requisicoes feitas, sonda inclusive'
}

teste_rf162_codigo_do_resumo_nao_vem_do_ambiente() {
  local base
  base=$(_dbg_cenario)
  printf '503' >"$base/content"
  DBX_T_EXTRAS=(DBX_TMP_SAIDA_CODIGO=0)
  _dbg_executar "$base" --debug download /arq.bin -
  DBX_T_EXTRAS=()
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'o 503 deveria falhar o download'
  assert_contem " saida=$DBX_ESTADO" "$DBX_ERRO" 'o codigo real, nao o semeado no ambiente'
  assert_nao_contem ' saida=0' "$DBX_ERRO"
}

harness_executar "$@"
