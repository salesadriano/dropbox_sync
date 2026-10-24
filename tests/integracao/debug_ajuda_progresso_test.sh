#!/usr/bin/env bash
# Integracao do --debug de transferencias, parte 3 (RF-156, RF-159(d), RF-165):
# convivencia com o progresso, DBX_DEBUG, ajuda/README/completions e o resultado
# do envio por fluxo (`upload -`).
#
# TC-DBG-33, TC-DBG-34, TC-DBG-35 e RF-159(d) do `upload -`.
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

_dbg_ler() { # <arquivo> — conteudo inteiro em DBX_LIDO
  DBX_LIDO=''
  IFS= read -r -d '' DBX_LIDO <"$1"
  return 0
}

# _dbg_conferir_linhas <texto> — nenhuma linha mistura `debug:` com outro texto.
_dbg_conferir_linhas() {
  local linha
  while IFS= read -r linha; do
    linha=${linha%$'\r'}
    if [[ $linha == *'debug:'* && $linha != 'debug: '* ]]; then
      _harness_falhar "linha mistura progresso e debug: $linha"
    fi
  done <<<"$1"
}

# _dbg_contar_http1 <texto> — linhas `http` com tentativa=1.
_dbg_contar_http1() {
  local linha n=0
  while IFS= read -r linha; do
    linha=${linha%$'\r'}
    [[ $linha == 'debug: http '* && $linha == *' tentativa=1 '* ]] && n=$((n + 1))
  done <<<"$1"
  printf '%s' "$n"
}

_dbg_chamadas_do_resumo() { # <texto>
  local linha
  while IFS= read -r linha; do
    linha=${linha%$'\r'}
    if [[ $linha == 'debug: resumo '* && $linha =~ ' chamadas='([0-9]+) ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <<<"$1"
}

# ---------------------------------------------------------------------------
# RF-165 / TC-DBG-33
# ---------------------------------------------------------------------------

teste_tc_dbg_33_sem_terminal_progresso_e_debug_nao_se_misturam() {
  local base
  base=$(_dbg_cenario)
  _dbg_executar "$base" --debug --progresso upload "$base/arq.bin" /arq.bin
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_contem 'debug: http' "$DBX_ERRO"
  assert_contem '[1/1]' "$DBX_ERRO" 'o progresso por arquivo continua saindo'
  assert_nao_contem $'\r' "$DBX_ERRO" 'sem retorno de carro'
  _dbg_conferir_linhas "$DBX_ERRO"
  assert_igual "$(_dbg_contar_http1 "$DBX_ERRO")" "$(_dbg_chamadas_do_resumo "$DBX_ERRO")" 'chamadas = linhas http tentativa=1'
}

teste_tc_dbg_33_semente_de_terminal_nao_reabilita_o_retorno_de_carro() {
  local base
  base=$(_dbg_cenario)
  DBX_T_EXTRAS=(DBX_PROGRESS_TERMINAL=sim)
  _dbg_executar "$base" --debug --progresso upload "$base/arq.bin" /arq.bin
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_nao_contem $'\r' "$DBX_ERRO"
  assert_nao_contem $'\033[' "$DBX_ERRO"
  _dbg_conferir_linhas "$DBX_ERRO"
  DBX_T_EXTRAS=()
}

teste_tc_dbg_33_com_terminal_progresso_e_debug_nao_se_misturam() {
  local base saida
  base=$(_dbg_cenario)
  _rodar_tty "$base" - --debug --progresso upload "$base/arq.bin" /arq.bin
  _dbg_ler "$base/out"
  saida=${DBX_LIDO//$'\r\n'/$'\n'}
  assert_contem 'debug: http' "$saida"
  assert_contem 'debug: resumo' "$saida"
  assert_nao_contem $'\r' "$saida" 'o pty so converte o fim de linha'
  assert_nao_contem $'\033[' "$saida" 'sem desenho no lugar'
  _dbg_conferir_linhas "$saida"
  assert_igual "$(_dbg_contar_http1 "$saida")" "$(_dbg_chamadas_do_resumo "$saida")" 'chamadas = linhas http tentativa=1'
}

# ---------------------------------------------------------------------------
# TC-DBG-34: DBX_DEBUG
# ---------------------------------------------------------------------------

teste_tc_dbg_34_dbx_debug_1_ativa() {
  local base
  base=$(_dbg_cenario)
  DBX_T_EXTRAS=(DBX_DEBUG=1)
  _dbg_executar "$base" upload "$base/arq.bin" /arq.bin
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_contem 'debug: http' "$DBX_ERRO"
  DBX_T_EXTRAS=()
}

teste_tc_dbg_34_dbx_debug_0_e_nao_nao_ativam() {
  local base valor
  for valor in 0 nao; do
    base=$(_dbg_cenario)
    DBX_T_EXTRAS=("DBX_DEBUG=$valor")
    _dbg_executar "$base" upload "$base/arq.bin" /arq.bin
    assert_igual 0 "$DBX_ESTADO" "DBX_DEBUG=$valor: $DBX_ERRO"
    assert_nao_contem 'debug:' "$DBX_SAIDA$DBX_ERRO" "DBX_DEBUG=$valor"
  done
  DBX_T_EXTRAS=()
}

# ---------------------------------------------------------------------------
# TC-DBG-35: ajuda, README e completions
# ---------------------------------------------------------------------------

teste_tc_dbg_35_ajuda_de_cada_comando_e_a_geral_descrevem_o_debug() {
  local base comando
  base=$(_dbg_cenario)
  for comando in upload download sync; do
    _dbg_executar "$base" help "$comando"
    assert_igual 0 "$DBX_ESTADO" "help $comando: $DBX_ERRO"
    assert_contem 'debug: <categoria>' "$DBX_SAIDA" "help $comando"
    assert_contem 'stderr' "$DBX_SAIDA" "help $comando"
    assert_contem 'resumo' "$DBX_SAIDA" "help $comando"
    assert_contem 'cursor' "$DBX_SAIDA" "help $comando"
    assert_contem 'token' "$DBX_SAIDA" "help $comando"
  done
  _dbg_executar "$base" help
  assert_contem 'debug: <categoria>' "$DBX_SAIDA" 'ajuda geral'
  assert_contem 'DBX_DEBUG=1' "$DBX_SAIDA" 'ajuda geral'
}

teste_tc_dbg_35_readme_e_completions() {
  _dbg_ler "$DBX_HARNESS_RAIZ/README.md"
  assert_contem 'debug: <categoria> chave=valor' "$DBX_LIDO"
  assert_contem 'URL temporária' "$DBX_LIDO"
  _dbg_ler "$DBX_HARNESS_RAIZ/completions/dbx.bash"
  assert_contem '--debug' "$DBX_LIDO"
}

# ---------------------------------------------------------------------------
# RF-159(d): upload - (envio por fluxo)
# ---------------------------------------------------------------------------

teste_tc_dbg_rf159_upload_de_fluxo_falho_emite_resultado_falha_com_classe() {
  local base
  base=$(_dbg_cenario)
  printf '503' >"$base/content"
  _dbg_executar "$base" --debug upload - /arq.bin
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'o 503 deveria falhar o upload'
  assert_contem 'debug: upload resultado=falha classe=' "$DBX_ERRO"
  assert_nao_contem 'resultado=ok' "$DBX_ERRO"
}

teste_tc_dbg_rf159_upload_de_fluxo_bem_sucedido_emite_resultado_ok() {
  local base
  base=$(_dbg_cenario)
  printf '%s' '{"session_id":"SESSAO_SENTINELA_77aa"}' >"$base/content_corpo"
  _dbg_executar "$base" --debug upload - /arq.bin
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_contem 'debug: upload resultado=ok' "$DBX_ERRO"
  assert_nao_contem 'SESSAO_SENTINELA_77aa' "$DBX_SAIDA$DBX_ERRO"
}

harness_executar "$@"
