#!/usr/bin/env bash
# Integracao do --debug de transferencias, parte 2 (RF-159, RF-160, RF-164):
# etapas do upload e do download.
#
# TC-DBG-08, 09, 16 e 24 (id de sessao em sessao real). Os casos de retomada
# (TC-DBG-10..15) ficam junto dos duplos com estado:
# tests/integracao/retomada_upload_test.sh (upload) e
# tests/integracao/retomada_download_test.sh (download).
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

readonly DBT_PARTE=4194304
readonly DBT_SESSAO='SESSAO_SENTINELA_123'

_dbt_cenario() {
  local base
  base=$(_cenario)
  head -c 10240 /dev/zero >"$base/arq.bin"
  printf '10240' >"$base/enviados"
  printf '%s' '{"name":"arq.bin","path_display":"/arq.bin","size":10240,"content_hash":"0000"}' >"$base/content_corpo"
  printf '200' >"$base/content"
  printf '%s' "$base"
}

# _dbt_executar <base> <argumentos...> — stdin vem de $base/stdin quando existe.
_dbt_executar() {
  local base=$1 entrada=/dev/null
  shift
  [[ -f $base/stdin ]] && entrada=$base/stdin
  env -i PATH="$base/bin" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
    TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=2 \
    "$BASH_ABSOLUTO" "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err" <"$entrada"
  DBX_ESTADO=$?
  DBX_SAIDA='' DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _dbt_indice <arquivo> <prefixo> — numero (1..) da primeira linha que comeca
# com o prefixo; 0 quando nao ha.
_dbt_indice() {
  local n=0 linha
  while IFS= read -r linha || [[ -n $linha ]]; do
    n=$((n + 1))
    if [[ $linha == "$2"* ]]; then
      printf '%s' "$n"
      return 0
    fi
  done <"$1"
  printf '0'
}

teste_tc_dbg_08_upload_simples_emite_modalidade_antes_da_chamada_de_conteudo() {
  local base modalidade chamada
  base=$(_dbt_cenario)
  _dbt_executar "$base" --debug upload "$base/arq.bin" /arq.bin
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_contem 'debug: upload modalidade=simples arquivo=' "$DBX_ERRO"
  assert_contem 'bytes=10240' "$DBX_ERRO"
  modalidade=$(_dbt_indice "$base/err" 'debug: upload modalidade=simples')
  chamada=$(_dbt_indice "$base/err" 'debug: http POST content.dropboxapi.com/2/files/upload')
  [[ $modalidade -gt 0 && $chamada -gt $modalidade ]] ||
    _harness_falhar "modalidade (linha $modalidade) deveria vir antes da chamada de conteudo (linha $chamada)"
}

teste_tc_dbg_08_sem_debug_o_upload_nao_emite_linha_de_etapa() {
  local base
  base=$(_dbt_cenario)
  _dbt_executar "$base" upload "$base/arq.bin" /arq.bin
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_nao_contem 'debug:' "$DBX_ERRO"
}

# Sessao REAL: entrada padrao (sempre por sessao), 3 blocos de 4 MiB e um resto.
_dbt_cenario_sessao() {
  local base
  base=$(_dbt_cenario)
  printf '%s' "{\"session_id\":\"$DBT_SESSAO\",\"name\":\"arq.bin\",\"path_display\":\"/arq.bin\",\"size\":12582922,\"content_hash\":\"0000\"}" >"$base/content_corpo"
  truncate -s $((3 * DBT_PARTE + 10)) "$base/stdin"
  printf '%s' "$base"
}

teste_tc_dbg_08_09_upload_em_sessao_tem_modalidade_e_blocos_com_confirmado_acumulado() {
  local base
  base=$(_dbt_cenario_sessao)
  _dbt_executar "$base" --debug upload - /arq.bin
  assert_contem 'debug: upload modalidade=sessao arquivo=- bytes=desconhecido bloco_tamanho=4194304' "$DBX_ERRO"
  assert_contem 'debug: upload bloco=1 deslocamento=0 tamanho=4194304' "$DBX_ERRO"
  assert_contem 'debug: upload bloco=1 confirmado=4194304' "$DBX_ERRO"
  assert_contem 'debug: upload bloco=2 deslocamento=4194304 tamanho=4194304' "$DBX_ERRO"
  assert_contem 'debug: upload bloco=2 confirmado=8388608' "$DBX_ERRO"
  assert_contem 'debug: upload bloco=3 deslocamento=8388608 tamanho=4194304' "$DBX_ERRO"
  assert_contem 'debug: upload bloco=3 confirmado=12582912' "$DBX_ERRO"
}

teste_tc_dbg_24_id_de_sessao_real_nunca_aparece_em_stdout_nem_stderr() {
  local base
  base=$(_dbt_cenario_sessao)
  _dbt_executar "$base" --debug upload - /arq.bin
  assert_contem 'debug: upload bloco=3 confirmado=' "$DBX_ERRO" 'a sessao precisa ter ocorrido'
  assert_nao_contem "$DBT_SESSAO" "$DBX_SAIDA"
  assert_nao_contem "$DBT_SESSAO" "$DBX_ERRO"
}

teste_tc_dbg_16_download_para_stdout_emite_o_plano_em_stderr_e_so_o_conteudo_em_stdout() {
  local base
  base=$(_dbt_cenario)
  _dbt_executar "$base" --debug download /arq.bin -
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_contem 'debug: download bytes=desconhecido retomada=nenhuma' "$DBX_ERRO"
  assert_nao_contem 'debug:' "$DBX_SAIDA"
  assert_nao_contem 'debug: download destino=' "$DBX_ERRO"
}

harness_executar "$@"
