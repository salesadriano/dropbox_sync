#!/usr/bin/env bash
# Testes diretos de lib/cmd.sh — servicos comuns aos comandos (RNF-32(d)).
#
# Ate a fase 3 `lib/cmd` so era exercitada pelos comandos ponta a ponta e pela
# auditoria de `composicao`. Aqui o modulo e carregado diretamente, e cada
# funcao publica usada pelos comandos tem caso proprio: `dbx_cmd_falhar`,
# `dbx_cmd_iniciar_saida`, `dbx_cmd_bytes_legiveis`,
# `dbx_cmd_content_hash_do_resultado` e `dbx_cmd_receber_arquivo`.
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e escrito sem expansao.
#
# shellcheck disable=SC2034
# Justificativa: canais de lib/cli, lib/auth e lib/http ajustados pelos casos.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/path.sh"
. "$DBX_HARNESS_RAIZ/lib/output.sh"
. "$DBX_HARNESS_RAIZ/lib/progress.sh"
. "$DBX_HARNESS_RAIZ/lib/config.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"
. "$DBX_HARNESS_RAIZ/lib/auth.sh"
. "$DBX_HARNESS_RAIZ/lib/cmd.sh"

_saidas() { # publica SAIDA e ERRO do comando dado
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/cmd.XXXXXX")
  "$@" >"$area/out" 2>"$area/err"
  ESTADO=$?
  SAIDA=''
  ERRO=''
  IFS= read -r -d '' SAIDA <"$area/out"
  IFS= read -r -d '' ERRO <"$area/err"
  return 0
}

# ---------------------------------------------------------------------------
# dbx_cmd_falhar e dbx_cmd_iniciar_saida
# ---------------------------------------------------------------------------

teste_falhar_devolve_o_codigo_da_classe_e_escreve_so_no_stderr() {
  local classe
  for classe in nao_encontrado uso_invalido permissao conflito; do
    _saidas dbx_cmd_falhar "$classe" "motivo de $classe"
    assert_igual "$(dbx_errors_codigo_saida "$classe")" "$ESTADO" "codigo da classe $classe"
    assert_igual '' "$SAIDA" 'a saida padrao continua limpa'
    assert_contem "motivo de $classe" "$ERRO" 'o diagnostico vai ao stderr'
  done
}

teste_falhar_redige_segredo_no_diagnostico() {
  _saidas dbx_cmd_falhar erro_remoto 'recusado com Authorization: Bearer sl.SEGREDO_DO_CASO'
  assert_segredo_ausente 'sl.SEGREDO_DO_CASO' "$ERRO" 'o diagnostico passa pela redacao'
}

teste_iniciar_saida_aplica_os_modos_globais() {
  DBX_CLI_ESTRUTURADA=sim
  _saidas _emitir_um_campo
  assert_contem 'contrato=' "$SAIDA" 'com --json a saida declara o contrato'
  assert_contem 'chave=valor' "$SAIDA" 'e emite pares chave=valor'
  DBX_CLI_NULO=sim
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/nulo.XXXXXX")
  _emitir_um_campo >"$area/out"
  assert_igual 2 "$(tr -cd '\0' <"$area/out" | wc -c)" 'com --null cada registro termina em NUL'
  assert_igual 0 "$(tr -cd '\n' <"$area/out" | wc -c)" 'e nenhum em quebra de linha'
}

_emitir_um_campo() {
  dbx_cmd_iniciar_saida
  dbx_output_campo chave valor
  dbx_output_render
}

# ---------------------------------------------------------------------------
# dbx_cmd_bytes_legiveis e dbx_cmd_content_hash_do_resultado
# ---------------------------------------------------------------------------

teste_bytes_legiveis_por_unidade_binaria() {
  assert_igual '0 B' "$(dbx_cmd_bytes_legiveis 0)"
  assert_igual '1023 B' "$(dbx_cmd_bytes_legiveis 1023)"
  assert_igual '1 KiB' "$(dbx_cmd_bytes_legiveis 1536)"
  assert_igual '5 GiB' "$(dbx_cmd_bytes_legiveis $((5 * 1024 * 1024 * 1024)))"
  assert_igual 'abc' "$(dbx_cmd_bytes_legiveis abc)" 'valor nao numerico sai como veio'
}

teste_content_hash_do_resultado_le_o_cabecalho_ou_fica_vazio() {
  DBX_HTTP_RESULTADO_CABECALHO='{"name":"a","content_hash":"abc123"}'
  dbx_cmd_content_hash_do_resultado
  assert_igual 'abc123' "$DBX_CMD_LIDO" 'resumo publicado pelo servico'
  DBX_HTTP_RESULTADO_CABECALHO=''
  dbx_cmd_content_hash_do_resultado
  assert_igual '' "$DBX_CMD_LIDO" 'sem cabecalho, vazio'
  DBX_HTTP_RESULTADO_CABECALHO='nao e json'
  dbx_cmd_content_hash_do_resultado
  assert_igual 0 $? 'cabecalho ilegivel nao falha'
  assert_igual '' "$DBX_CMD_LIDO" 'e nao publica nada'
}

# ---------------------------------------------------------------------------
# dbx_cmd_receber_arquivo (RF-55) — recebimento atomico com conferencia
# ---------------------------------------------------------------------------

# _duplo_de_recebimento <conteudo> <content_hash_publicado> — substituto de
# `curl` que entrega o conteudo em `-o` e o resumo no cabecalho `-D`.
_duplo_de_recebimento() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/duplo.XXXXXX")
  printf '%s' "$1" >"$dir/corpo"
  printf '{"name":"a","content_hash":"%s"}' "$2" >"$dir/resultado"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'dir=%s\n' "$dir"
    printf 'cat >/dev/null\n'
    printf 'saida=""; cabecalhos=""; escrever=""; anterior=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -D) cabecalhos=$arg ;; -w) escrever=$arg ;; esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf '[[ -n $saida ]] && cat "$dir/corpo" >"$saida"\n'
    printf '[[ -n $cabecalhos ]] && printf "Dropbox-API-Result: %%s\\r\\n" "$(cat "$dir/resultado")" >"$cabecalhos"\n'
    printf '[[ -n $escrever ]] && printf 200\n'
    printf 'exit 0\n'
  } >"$dir/curl"
  chmod +x "$dir/curl"
  printf '%s' "$dir"
}

_token_valido() {
  DBX_AUTH_TOKEN='sl.token_de_teste'
  DBX_AUTH_EXPIRA_EM=$((SECONDS + 3600))
}

_hash_de_texto() { printf '%s' "$1" | dbx_hash_conteudo_fluxo; }

teste_receber_arquivo_confere_e_substitui_sem_temporario() {
  local area dir
  area=$(mktemp -d "$DBX_TESTES_TMP/receber.XXXXXX")
  printf 'antigo' >"$area/alvo.txt"
  dir=$(_duplo_de_recebimento 'novo conteudo' "$(_hash_de_texto 'novo conteudo')")
  _token_valido
  TMPDIR=$area PATH=$dir:$PATH dbx_cmd_receber_arquivo /r/a.txt "$area/alvo.txt"
  assert_igual 0 $? 'recebimento conferido conclui'
  assert_igual 'novo conteudo' "$(cat "$area/alvo.txt")" 'o alvo foi substituido'
  assert_igual 'conferida' "$DBX_CMD_INTEGRIDADE" 'a integridade foi conferida'
  assert_igual '' "$(find "$area" -name '*.dbx-part.*')" 'nenhum temporario sobra'
}

teste_receber_arquivo_com_resumo_divergente_preserva_o_alvo() {
  local area dir estado
  area=$(mktemp -d "$DBX_TESTES_TMP/receber.XXXXXX")
  printf 'antigo' >"$area/alvo.txt"
  dir=$(_duplo_de_recebimento 'conteudo adulterado' "$(_hash_de_texto 'outro')")
  _token_valido
  TMPDIR=$area PATH=$dir:$PATH dbx_cmd_receber_arquivo /r/a.txt "$area/alvo.txt"
  estado=$?
  assert_igual "$(dbx_errors_codigo_saida integridade)" "$estado" 'divergencia e falha de integridade'
  assert_igual 'antigo' "$(cat "$area/alvo.txt")" 'o alvo continua o anterior'
  assert_igual 'integridade' "$DBX_CMD_FALHA_CLASSE" 'classe publicada'
  assert_igual '' "$(find "$area" -name '*.dbx-part.*')" 'o temporario e descartado'
}

teste_receber_arquivo_nao_substitui_alvo_somente_leitura() {
  [[ $EUID -ne 0 ]] || pular 'root escreve em arquivo somente leitura'
  local area dir estado
  area=$(mktemp -d "$DBX_TESTES_TMP/receber.XXXXXX")
  printf 'protegido' >"$area/alvo.txt"
  chmod 444 "$area/alvo.txt"
  dir=$(_duplo_de_recebimento 'novo' "$(_hash_de_texto 'novo')")
  _token_valido
  TMPDIR=$area PATH=$dir:$PATH dbx_cmd_receber_arquivo /r/a.txt "$area/alvo.txt"
  estado=$?
  assert_igual "$(dbx_errors_codigo_saida permissao)" "$estado" 'alvo sem escrita e recusado'
  assert_igual 'protegido' "$(cat "$area/alvo.txt")" 'conteudo intacto'
  assert_igual 444 "$(stat -c '%a' "$area/alvo.txt")" 'modo intacto'
}

harness_executar "$@"
