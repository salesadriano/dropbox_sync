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

# ---------------------------------------------------------------------------
# dbx_cmd_ler_corpo_silencioso (O-5)
# ---------------------------------------------------------------------------

teste_ler_corpo_silencioso_publica_campos_sem_emitir_nada() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/silencioso.XXXXXX")
  DBX_HTTP_CORPO='{".tag":"file","content_hash":"abc"}'
  dbx_cmd_ler_corpo_silencioso .tag content_hash ausente >"$area/out" 2>"$area/err"
  assert_igual 0 $? 'corpo valido le sem falha'
  assert_igual '' "$(cat "$area/out")$(cat "$area/err")" 'nada e emitido'
  assert_igual 'file' "${DBX_CMD_CAMPOS[0]}" 'primeiro campo'
  assert_igual 'abc' "${DBX_CMD_CAMPOS[1]}" 'segundo campo'
  assert_igual '' "${DBX_CMD_CAMPOS[2]}" 'campo ausente fica vazio, sem falha'
  assert_igual '' "$DBX_CMD_FALHA_CLASSE" 'sem classe de falha'
}

teste_ler_corpo_silencioso_nomeia_classe_e_motivo_na_falha() {
  local area anterior=$DBX_JSON_CONTEXTO
  area=$(mktemp -d "$DBX_TESTES_TMP/silencioso.XXXXXX")
  DBX_HTTP_CORPO='{"name":'
  dbx_cmd_ler_corpo_silencioso .tag >"$area/out" 2>"$area/err"
  assert_igual 1 $? 'corpo ilegivel falha'
  assert_igual '' "$(cat "$area/out")$(cat "$area/err")" 'a falha tambem nao emite'
  assert_igual 'erro_remoto' "$DBX_CMD_FALHA_CLASSE" 'classe nomeada'
  assert_contem 'resposta nao interpretavel:' "$DBX_CMD_FALHA_MOTIVO" 'motivo nomeado'
  assert_igual "$anterior" "$DBX_JSON_CONTEXTO" 'contexto anterior restaurado'
  assert_igual '' "$DBX_HTTP_CORPO" 'corpo bruto descartado'
}

teste_ler_corpo_silencioso_le_campo_aninhado_por_segmentos() {
  DBX_HTTP_CORPO='{"allocation":{".tag":"team","allocated":10}}'
  dbx_cmd_ler_corpo_silencioso 'allocation .tag' 'allocation allocated'
  assert_igual 0 $? 'corpo valido le sem falha'
  assert_igual 'team' "${DBX_CMD_CAMPOS[0]}" 'segmentos separados por espaco'
  assert_igual '10' "${DBX_CMD_CAMPOS[1]}" 'segundo campo aninhado'
}

# ---------------------------------------------------------------------------
# Espaco livre (RF-66 `espaco`, RF-67)
# ---------------------------------------------------------------------------

# _duplo_de_espaco <status> <corpo> — substituto de `curl` que responde a
# `get_space_usage` e conta as chamadas.
_duplo_de_espaco() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/espaco.XXXXXX")
  printf '%s' "$2" >"$dir/corpo"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'dir=%s\n' "$dir"
    printf 'cat >/dev/null\n'
    printf 'printf "x\\n" >>"$dir/chamadas"\n'
    printf 'saida=""; escrever=""; anterior=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf '[[ -n $saida ]] && cat "$dir/corpo" >"$saida"\n'
    printf '[[ -n $escrever ]] && printf %s\n' "$1"
    printf 'exit 0\n'
  } >"$dir/curl"
  chmod +x "$dir/curl"
  printf '%s' "$dir"
}

teste_espaco_individual_e_alocado_menos_usado() {
  local dir
  dir=$(_duplo_de_espaco 200 '{"used":300,"allocation":{".tag":"individual","allocated":1000}}')
  _token_valido
  PATH=$dir:$PATH dbx_cmd_espaco_consultar
  assert_igual 0 $? 'consulta conclui'
  assert_igual 700 "$DBX_CMD_ESPACO_LIVRE" 'folga individual'
  assert_igual 300 "$DBX_CMD_ESPACO_USADO" 'usado'
  assert_igual 1000 "$DBX_CMD_ESPACO_ALOCADO" 'alocado'
}

teste_espaco_de_equipe_e_a_menor_das_folgas() {
  local dir
  dir=$(_duplo_de_espaco 200 '{"used":100,"allocation":{".tag":"team","used":900,"allocated":1000,"user_within_team_space_allocated":500}}')
  _token_valido
  PATH=$dir:$PATH dbx_cmd_espaco_consultar
  assert_igual 100 "$DBX_CMD_ESPACO_LIVRE" 'equipe 100 contra membro 400: vale a menor'
  dir=$(_duplo_de_espaco 200 '{"used":450,"allocation":{".tag":"team","used":100,"allocated":1000,"user_within_team_space_allocated":500}}')
  PATH=$dir:$PATH dbx_cmd_espaco_consultar
  assert_igual 50 "$DBX_CMD_ESPACO_LIVRE" 'membro 50 contra equipe 900'
  dir=$(_duplo_de_espaco 200 '{"used":450,"allocation":{".tag":"team","used":100,"allocated":1000,"user_within_team_space_allocated":0}}')
  PATH=$dir:$PATH dbx_cmd_espaco_consultar
  assert_igual 900 "$DBX_CMD_ESPACO_LIVRE" 'sem limite de membro, vale a equipe'
}

teste_espaco_sem_alocacao_interpretavel_fica_desconhecido() {
  local dir corpo
  for corpo in '{"used":1}' '{"used":1,"allocation":{".tag":"other"}}' \
    '{"used":1,"allocation":{".tag":"individual","allocated":"muito"}}'; do
    dir=$(_duplo_de_espaco 200 "$corpo")
    _token_valido
    PATH=$dir:$PATH dbx_cmd_espaco_consultar
    assert_igual 0 $? "consulta conclui: $corpo"
    assert_igual '' "$DBX_CMD_ESPACO_LIVRE" "folga desconhecida: $corpo"
  done
}

teste_checar_espaco_recusa_so_quando_o_total_excede_a_folga() {
  local dir area
  area=$(mktemp -d "$DBX_TESTES_TMP/checar.XXXXXX")
  dir=$(_duplo_de_espaco 200 '{"used":300,"allocation":{".tag":"individual","allocated":1000}}')
  _token_valido
  PATH=$dir:$PATH dbx_cmd_espaco_checar 700
  assert_igual 0 $? 'igual a folga cabe'
  assert_igual sim "$DBX_CMD_ESPACO_VERIFICADO" 'verificado'
  PATH=$dir:$PATH dbx_cmd_espaco_checar 701
  assert_igual 1 $? 'um byte acima nao cabe'
  assert_contem '701' "$DBX_CMD_ESPACO_MOTIVO" 'o motivo nomeia o necessario'
  assert_contem '700' "$DBX_CMD_ESPACO_MOTIVO" 'a folga'
  assert_contem 'faltam 1 bytes' "$DBX_CMD_ESPACO_MOTIVO" 'a diferenca'
  assert_contem '--forcar' "$DBX_CMD_ESPACO_MOTIVO" 'e a saida'
  assert_igual 2 "$(_harness_contar x "$dir/chamadas")" 'uma consulta por checagem'
}

teste_checar_espaco_sem_nada_a_enviar_ou_pulado_nao_consulta() {
  local dir
  dir=$(_duplo_de_espaco 200 '{"used":0,"allocation":{".tag":"individual","allocated":1}}')
  _token_valido
  PATH=$dir:$PATH dbx_cmd_espaco_checar 0
  assert_igual 0 $? 'total zero passa'
  assert_igual nao "$DBX_CMD_ESPACO_VERIFICADO" 'nada verificado'
  PATH=$dir:$PATH dbx_cmd_espaco_checar 999 sim
  assert_igual 0 $? 'pulado passa'
  assert_igual pulado "$DBX_CMD_ESPACO_VERIFICADO" 'declarado pulado'
  assert_arquivo_ausente "$dir/chamadas" 'zero consultas'
}

teste_checar_espaco_com_consulta_falha_avisa_uma_vez_e_segue() {
  local dir area
  area=$(mktemp -d "$DBX_TESTES_TMP/checar.XXXXXX")
  dir=$(_duplo_de_espaco 500 '{"error_summary":"internal/"}')
  _token_valido
  DBX_HTTP_TENTATIVAS_MAXIMAS=1 PATH=$dir:$PATH dbx_cmd_espaco_checar 10 >"$area/out" 2>"$area/err"
  assert_igual 0 $? 'a falha da consulta nao bloqueia'
  assert_igual nao "$DBX_CMD_ESPACO_VERIFICADO" 'nao verificado'
  assert_igual 1 "$(_harness_contar 'aviso' "$area/err")" 'um aviso em stderr'
  assert_igual '' "$(cat "$area/out")" 'stdout limpo'
}

harness_executar "$@"
