#!/usr/bin/env bash
# Testes de lib/http.sh — ponto unico de saida de rede.
#
# DECISAO DO DUPLO (RNF-14: a suite padrao nao usa rede).
#
# Adotado: SUBSTITUTO DE `curl` INJETADO NO CAMINHO DE BUSCA. O componente
# invoca `curl` normalmente; um script nosso, colocado antes no caminho, produz
# a resposta canonizada.
#
# Criterio decisivo: o duplo precisa exercitar O CODIGO REAL de interpretacao de
# resposta, senao testa a si mesmo. Com este desenho, tudo a jusante do processo
# de rede e real — separacao de cabecalhos e corpo, extracao de codigo HTTP,
# interpretacao de JSON pelo analisador proprio, classificacao de erro,
# politica de retentativa e paginacao. So os BYTES sao fabricados.
#
# Alternativas descartadas:
#   - servidor local: exercitaria tambem a pilha de rede, mas exige utilitario
#     de escuta que hoje nao existe no projeto e teria de passar pelo preflight
#     e pela auditoria; acrescenta porta, espera e uma classe nova de
#     intermitencia, logo depois de uma intermitencia sem causa estabelecida;
#   - gravacao e reproducao por ponto de injecao interno: o componente leria de
#     um arquivo em vez de invocar rede, o que faria a suite exercitar o ponto
#     de injecao e NAO o caminho real de invocacao — a armadilha do QF-01, em
#     que o teste media a si mesmo.
#
# RISCO ACEITO E MITIGADO: o substituto precisa honrar o contrato real do
# `curl`. Se divergir, a suite valida uma ficcao. Mitigacao: a superficie de
# invocacao e minima e concentrada numa unica funcao, o contrato exigido esta
# declarado no cabecalho de lib/http.sh, e ha caso de contrato, habilitado por
# variavel de ambiente, que confere o mesmo comportamento contra o `curl` real.

# shellcheck disable=SC2016
# Justificativa: casos entregam script literal a "bash -c" e escrevem o
# substituto de `curl`, que precisa chegar sem expansao.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"

# _duplo <status> <corpo> [cabecalhos...] — instala o substituto e devolve o
# caminho a antepor. Grava tambem o que foi invocado, para inspecao.
_duplo() {
  local status=$1 corpo=$2
  shift 2
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/duplo.XXXXXX")
  printf '%s' "$corpo" >"$dir/corpo"
  printf '%s\n' "$status" >"$dir/status"
  : >"$dir/cabecalhos"
  local cabecalho
  for cabecalho in "$@"; do printf '%s\r\n' "$cabecalho" >>"$dir/cabecalhos"; done
  {
    printf '#!/usr/bin/env bash\n'
    printf 'dir=%s\n' "$dir"
    printf 'printf "%%s\\n" "$*" >>"$dir/argv"\n'
    printf 'cat >"$dir/entrada" 2>/dev/null\n'
    printf 'saida=""; cabecalhos=""; escrever=""\n'
    printf 'anterior=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in\n'
    printf '    -o) saida=$arg ;;\n'
    printf '    -D) cabecalhos=$arg ;;\n'
    printf '    -w) escrever=$arg ;;\n'
    printf '  esac\n'
    printf '  case $arg in\n'
    printf '    --data-binary) : ;;\n'
    printf '    @*) [[ -r ${arg#@} ]] && cat "${arg#@}" >>"$dir/enviado" ;;\n'
    printf '  esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf '[[ -n $saida ]] && cp "$dir/corpo" "$saida"\n'
    printf '[[ -n $cabecalhos ]] && cp "$dir/cabecalhos" "$cabecalhos"\n'
    printf 'if [[ -n $escrever ]]; then printf "%%s" "$(cat "$dir/status")"; fi\n'
    printf 'exit "$(cat "$dir/saida_curl" 2>/dev/null || printf 0)"\n'
  } >"$dir/curl"
  chmod +x "$dir/curl"
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# Contrato de status e dependencia
# ---------------------------------------------------------------------------

teste_status_seguem_a_taxonomia_de_erro() {
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_HTTP_ERRO_USO"
  assert_igual "$(dbx_errors_codigo_saida rede)" "$DBX_HTTP_ERRO_REDE"
}

teste_e_o_unico_ponto_de_saida_de_rede() {
  # Verificavel por auditoria estatica: nenhum outro componente invoca o cliente.
  local arquivo achados
  for arquivo in "$DBX_HARNESS_RAIZ"/lib/*.sh; do
    [[ ${arquivo##*/} == 'http.sh' ]] && continue
    [[ ${arquivo##*/} == 'preflight.sh' ]] && continue
    achados=$(grep -vE '^[[:space:]]*#' "$arquivo" | grep -nE '(^|[^-_a-zA-Z/])curl' || true)
    [[ -n $achados ]] && _harness_falhar "componente fora de lib/http invoca o cliente: ${arquivo##*/}: $achados"
  done
  return 0
}

# ---------------------------------------------------------------------------
# RNF-03 — segredo nunca em argv
# ---------------------------------------------------------------------------

teste_segredo_nunca_aparece_na_linha_de_comando() {
  local dir
  dir=$(_duplo 200 '{"ok":true}')
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'sl.TokenSecretoTotal' '' sim
  assert_arquivo_existe "$dir/argv"
  assert_nao_contem 'sl.TokenSecretoTotal' "$(cat "$dir/argv")" \
    'o segredo na tabela de processos e visivel a qualquer usuario do host'
}

teste_segredo_chega_ao_cliente_por_canal_fora_de_argv() {
  local dir
  dir=$(_duplo 200 '{"ok":true}')
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'sl.TokenSecretoTotal' '' sim
  assert_contem 'sl.TokenSecretoTotal' "$(cat "$dir/entrada")" \
    'o segredo precisa chegar, so que por canal que nao seja a linha de comando'
}

# ---------------------------------------------------------------------------
# Resposta de sucesso e de erro — GEMEOS
# ---------------------------------------------------------------------------

teste_resposta_de_sucesso_expoe_codigo_e_corpo() {
  local dir
  dir=$(_duplo 200 '{"cursor":"C1"}')
  PATH="$dir:$PATH" assert_sucesso dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual '200' "$DBX_HTTP_CODIGO"
  assert_igual '{"cursor":"C1"}' "$DBX_HTTP_CORPO"
}

teste_resposta_de_erro_expoe_resumo_ja_extraido() {
  local dir
  dir=$(_duplo 409 '{"error_summary":"path/not_found/.","error":{".tag":"path"}}')
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual '409' "$DBX_HTTP_CODIGO"
  assert_igual 'path/not_found/.' "$DBX_HTTP_RESUMO_DE_ERRO" \
    'lib/errors recebe texto ja extraido; quem interpreta JSON e lib/json'
  assert_igual 'nao_encontrado' "$DBX_HTTP_CLASSE"
}

teste_ambos_os_caminhos_registram_o_identificador_de_correlacao() {
  # Gemeos: sucesso e erro. RF-30 existe para preservar esse identificador, e
  # perde-lo num dos dois caminhos e o modo de falha que RNF-22 enderec a.
  local dir
  for dir in "$(_duplo 200 '{"ok":true}' 'X-Dropbox-Request-Id: req-ok')" \
    "$(_duplo 409 '{"error_summary":"path/not_found/."}' 'X-Dropbox-Request-Id: req-erro')"; do
    PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
    assert_diferente '' "$DBX_HTTP_CORRELACAO" \
      'o identificador de correlacao precisa ser capturado nos dois caminhos'
  done
}

teste_requisicao_com_e_sem_corpo_sao_tratadas_igualmente() {
  # Gemeos: com corpo e sem corpo.
  local dir
  dir=$(_duplo 200 '{"ok":true}')
  PATH="$dir:$PATH" assert_sucesso dbx_http_requisitar POST 'https://api/2/x' 'tok' '{"a":1}' sim
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '{"a":1}' sim
  assert_igual '200' "$DBX_HTTP_CODIGO"
  PATH="$dir:$PATH" assert_sucesso dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual '200' "$DBX_HTTP_CODIGO"
}

# ---------------------------------------------------------------------------
# Falha de transporte — sem resposta HTTP
# ---------------------------------------------------------------------------

teste_falha_de_transporte_e_classificada_como_rede() {
  local dir
  dir=$(_duplo 000 '')
  printf '7\n' >"$dir/saida_curl"
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 'rede' "$DBX_HTTP_CLASSE"
  assert_igual '0' "$DBX_HTTP_CODIGO" 'ausencia de resposta e codigo zero, nao um codigo inventado'
}

# ---------------------------------------------------------------------------
# Retentativa — consulta a classificacao, nao reimplementa
# ---------------------------------------------------------------------------

teste_politica_vem_de_lib_errors_e_nao_de_decisao_propria() {
  local arquivo codigo
  arquivo="$DBX_HARNESS_RAIZ/lib/http.sh"
  codigo=$(grep -vE '^[[:space:]]*#' "$arquivo")
  if ! grep -q 'dbx_errors_politica_retentativa' <<<"$codigo"; then
    _harness_falhar 'lib/http precisa consultar a politica, e nao decidir por status'
  fi
  if grep -qE 'case[[:space:]]+"?\$\{?(codigo|DBX_HTTP_CODIGO)' <<<"$codigo"; then
    _harness_falhar 'decisao de retentativa por codigo HTTP reimplementa lib/errors'
  fi
}

teste_operacao_nao_idempotente_sem_resposta_nao_repete() {
  local dir tentativas
  dir=$(_duplo 000 '')
  printf '7\n' >"$dir/saida_curl"
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' nao
  tentativas=$(wc -l <"$dir/argv")
  assert_igual 1 "$tentativas" \
    'indeterminado significa "nao da para saber se foi aplicada", e repetir pode duplicar'
  assert_igual 'indeterminado' "$DBX_HTTP_POLITICA"
}

teste_operacao_idempotente_sem_resposta_repete_com_recuo() {
  local dir tentativas
  dir=$(_duplo 000 '')
  printf '7\n' >"$dir/saida_curl"
  DBX_HTTP_ESPERA_BASE_MS=1 PATH="$dir:$PATH" dbx_http_requisitar GET 'https://api/2/x' 'tok' '' sim
  tentativas=$(wc -l <"$dir/argv")
  if [[ $tentativas -lt 2 ]]; then
    _harness_falhar "operacao idempotente deveria repetir; tentativas=$tentativas"
  fi
  assert_igual 'recuo_exponencial' "$DBX_HTTP_POLITICA"
}

teste_erro_definitivo_nao_repete() {
  local dir tentativas
  dir=$(_duplo 409 '{"error_summary":"path/not_found/."}')
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  tentativas=$(wc -l <"$dir/argv")
  assert_igual 1 "$tentativas" 'erro definitivo nao pode ser repetido'
}

# ---------------------------------------------------------------------------
# E3-01 — corpo de erro nao destroi documento em curso
# ---------------------------------------------------------------------------

teste_corpo_de_erro_nao_destroi_listagem_em_curso() {
  local dir
  dbx_json_contexto padrao
  dbx_json_analisar '{"entries":[{"name":"a.txt"}],"cursor":"EM-CURSO"}'
  dir=$(_duplo 409 '{"error_summary":"path/not_found/."}')
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 'path/not_found/.' "$DBX_HTTP_RESUMO_DE_ERRO"
  dbx_json_valor cursor >/dev/null
  assert_igual 'EM-CURSO' "$DBX_JSON_RESULTADO" 'a listagem em curso precisa sobreviver'
  assert_igual 'padrao' "$DBX_JSON_CONTEXTO" 'o contexto precisa ser restaurado'
}

teste_nome_de_contexto_e_literal() {
  local achados
  achados=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/http.sh" |
    grep -nE 'dbx_json_contexto[[:space:]]+' |
    grep -vE 'dbx_json_contexto[[:space:]]+([a-z_]+|"\$DBX_JSON_CONTEXTO_ANTERIOR")([[:space:]]|$)' || true)
  assert_igual '' "$achados" "nome de contexto derivado de dado externo: $achados"
}

# ---------------------------------------------------------------------------
# RNF-23 — colecao exige limite explicito, e motivo=tamanho reduz
# ---------------------------------------------------------------------------

teste_chamada_de_colecao_sem_limite_e_recusada() {
  assert_status "$DBX_HTTP_ERRO_USO" dbx_http_colecao POST 'https://api/2/files/list_folder' 'tok' '{"path":"/x"}' ''
}

teste_limite_acima_do_maximo_e_recusado() {
  assert_status "$DBX_HTTP_ERRO_USO" dbx_http_colecao POST 'https://api/2/files/list_folder' 'tok' '{"path":"/x"}' 500
}

teste_corpo_acima_do_teto_reduz_o_limite_e_repete() {
  # A acao correta ao receber motivo=tamanho e REDUZIR o limite, nao abortar.
  local dir grande tentativas
  printf -v grande 'x%.0s' $(seq 1 $((DBX_JSON_MAXIMO_ENTRADA + 100)))
  dir=$(_duplo 200 "{\"v\":\"$grande\"}")
  PATH="$dir:$PATH" dbx_http_colecao POST 'https://api/2/files/list_folder' 'tok' '{"path":"/x"}' 100
  tentativas=$(wc -l <"$dir/argv")
  if [[ $tentativas -lt 2 ]]; then
    _harness_falhar "resposta acima do teto deveria reduzir o limite e repetir; tentativas=$tentativas"
  fi
  assert_contem '"limit":' "$(cat "$dir/enviado" 2>/dev/null)" \
    'o limite reduzido precisa chegar ao servico, no corpo da requisicao'
  # E precisa ser MENOR que o pedido originalmente: reduzir e a acao correta.
  assert_nao_contem '"limit":100,"limit"' "$(cat "$dir/enviado" 2>/dev/null)" \
    'o corpo nao pode acumular limites a cada reducao'
}

teste_reducao_de_limite_tem_piso_e_desiste() {
  local dir grande
  printf -v grande 'x%.0s' $(seq 1 $((DBX_JSON_MAXIMO_ENTRADA + 100)))
  dir=$(_duplo 200 "{\"v\":\"$grande\"}")
  PATH="$dir:$PATH" dbx_http_colecao POST 'https://api/2/files/list_folder' 'tok' '{"path":"/x"}' 100
  assert_diferente 0 "$?" 'esgotada a reducao, a operacao precisa falhar de forma classificada'
}

# ---------------------------------------------------------------------------
# RSK-23 — nenhum estado local persistente
# ---------------------------------------------------------------------------

teste_nao_introduz_estado_local_persistente() {
  local codigo achados
  codigo=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/http.sh")
  achados=$(grep -nEi '(cache|indice_local|cursor_salvo|arquivo_de_trava|lockfile)' <<<"$codigo" || true)
  [[ -n $achados ]] && _harness_falhar "indicio de estado local em lib/http: $achados"
  achados=$(grep -nE '>[[:space:]]*"?\$(HOME|XDG)' <<<"$codigo" || true)
  [[ -n $achados ]] && _harness_falhar "escrita no diretorio do usuario: $achados"
  return 0
}

teste_nao_deixa_residuo_temporario() {
  local dir antes depois
  dir=$(_duplo 200 '{"ok":true}')
  antes=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'dbx-http*' 2>/dev/null | wc -l)
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  depois=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'dbx-http*' 2>/dev/null | wc -l)
  assert_igual "$antes" "$depois" 'a requisicao nao pode deixar temporario para tras'
}

harness_executar "$@"
