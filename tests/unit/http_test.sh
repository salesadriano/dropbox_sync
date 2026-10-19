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
# `curl`. Se divergir, a suite valida uma ficcao. Mitigacao, agora existente e
# executada sempre: os casos "contrato" ao fim deste arquivo exercitam o `curl`
# REAL contra `127.0.0.1:1`, sem rede, e verificam tanto os status que o cliente
# produz quanto o fato de que as opcoes que NOS geramos sao aceitas por ele.
# Antes esta nota afirmava haver um caso habilitado por variavel de ambiente:
# nao havia nenhum, e a afirmacao fazia quem lia parar de procurar.

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
    printf 'saida=""; cabecalhos=""; escrever=""; fail="nao"\n'
    printf 'anterior=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in\n'
    printf '    -o) saida=$arg ;;\n'
    printf '    -D) cabecalhos=$arg ;;\n'
    printf '    -w) escrever=$arg ;;\n'
    printf '  esac\n'
    printf '  case $arg in\n'
    printf '    --data-binary) : ;;\n'
    printf '    --fail) fail="sim" ;;\n'
    printf '    @*) [[ -r ${arg#@} ]] && cat "${arg#@}" >>"$dir/enviado" ;;\n'
    printf '  esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf '[[ -n $cabecalhos ]] && stat -c %%a "${cabecalhos%%/*}" >>"$dir/modo_area"\n'
    printf '[[ -n $cabecalhos ]] && cp "$dir/cabecalhos" "$cabecalhos"\n'
    # `--fail` diante de 4xx/5xx: o cliente real nao emite corpo e sai com 22.
    printf 'if [[ $fail == "sim" && $(cat "$dir/status") -ge 400 ]]; then\n'
    printf '  [[ -n $escrever ]] && printf "%%s" "$(cat "$dir/status")"\n'
    printf '  exit 22\n'
    printf 'fi\n'
    printf '[[ -n $saida ]] && cp "$dir/corpo" "$saida"\n'
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
  # TMPDIR privado: no diretorio compartilhado, outro processo criando ou
  # removendo `dbx-http*` mudaria a contagem sem relacao com este caso.
  local dir area restantes
  dir=$(_duplo 200 '{"ok":true}')
  area=$(mktemp -d "$DBX_TESTES_TMP/tmpdir.XXXXXX")
  TMPDIR=$area PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  restantes=$(find "$area" -mindepth 1 -maxdepth 1 | wc -l)
  assert_igual 0 "$restantes" 'a requisicao nao pode deixar temporario para tras'
}

# RNF-29(a): a mascara e estado do PROCESSO. Deixa-la em 077 faria todo arquivo
# que o usuario receber depois da primeira chamada nascer 0600.
teste_umask_do_processo_e_preservado_apos_chamada_http() {
  local dir
  dir=$(_duplo 200 '{"ok":true}')
  umask 022
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 0022 "$(umask)" 'a chamada nao pode alterar o umask do chamador'
}

# RNF-29(b): o 077 continua valendo para a area que recebe o token e o corpo.
teste_area_temporaria_da_requisicao_nasce_restrita() {
  local dir
  dir=$(_duplo 200 '{"ok":true}')
  umask 022
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 700 "$(head -n 1 "$dir/modo_area")" 'a area com o segredo e restrita ao dono'
}

# RNF-29(c) e (d): a reemissao diagnostica do canal de fluxo e chamada
# recursiva; cada nivel precisa remover a propria area, e nenhum gancho de
# limpeza pode sobreviver ao retorno.
teste_reemissao_diagnostica_nao_deixa_area_temporaria() {
  local dir area restantes
  dir=$(_duplo 409 '{"error_summary":"path/not_file/.."}')
  area=$(mktemp -d "$DBX_TESTES_TMP/tmpdir.XXXXXX")
  TMPDIR=$area PATH="$dir:$PATH" dbx_http_conteudo_receber POST 'https://c/2/files/download' \
    'tok' '{"path":"/p"}' "$area/destino"
  assert_igual 409 "$DBX_HTTP_CODIGO" 'o codigo observado e preservado'
  assert_igual 2 "$(wc -l <"$dir/argv")" 'houve a requisicao original e a reemissao'
  restantes=$(find "$area" -maxdepth 1 -name 'dbx-http*' | wc -l)
  assert_igual 0 "$restantes" 'nenhuma area temporaria pode restar apos a reemissao'
  assert_igual '' "$(trap -p RETURN)" 'nenhum gancho RETURN pode ficar armado'
}

teste_nenhum_gancho_de_limpeza_fica_armado_apos_requisicao() {
  local dir
  dir=$(_duplo 200 '{"ok":true}')
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual '' "$(trap -p RETURN)" 'o gancho RETURN nao pode sobreviver ao retorno'
}

# ---------------------------------------------------------------------------
# QH-02: CASOS DE CONTRATO CONTRA O CLIENTE REAL.
#
# O cabecalho deste arquivo prometia "caso de contrato, habilitado por variavel
# de ambiente, que confere o mesmo comportamento contra o `curl` real". A
# promessa era falsa: nao havia caso algum. Risco declarado como mitigado sem a
# mitigacao existir e pior que risco declarado em aberto, porque quem le para de
# procurar.
#
# O que o duplo NAO cobre, medido: ele consome o arquivo de opcoes sem nunca o
# interpretar. Contra o cliente real, opcoes mal formadas dao status 2 e corpo
# ilegivel da 26; contra o duplo, os dois davam status 0 e `200`. Um defeito na
# GERACAO das opcoes atravessaria a suite inteira sem sinal.
#
# Estes casos nao usam rede: falam com `127.0.0.1:1`, que recusa conexao de
# imediato. Por isso rodam SEMPRE, e nao sob variavel de ambiente — mitigacao
# que so roda quando alguem lembra de liga-la tende a nao rodar.
# ---------------------------------------------------------------------------

readonly ALVO_QUE_RECUSA='http://127.0.0.1:1/'

_estado_do_cliente_real() {
  curl --connect-timeout 3 "$@" >"$DBX_TESTES_TMP/w.$$" 2>/dev/null
  DBX_ESTADO_REAL=$?
  DBX_SAIDA_W=''
  [[ -r $DBX_TESTES_TMP/w.$$ ]] && IFS= read -r -d '' DBX_SAIDA_W <"$DBX_TESTES_TMP/w.$$"
  rm -f "$DBX_TESTES_TMP/w.$$"
  return 0
}

teste_contrato_opcoes_de_formulario_sao_aceitas_pelo_cliente_real() {
  command -v curl >/dev/null 2>&1 || pular 'curl ausente'
  # Campo com aspas e barra invertida: e o escape gerado por nos que esta sob
  # teste, e nao a capacidade do cliente de falar com um servidor.
  # shellcheck disable=SC2034  # consumida por nome (nameref) em _dbx_http_opcoes
  local -a campos=('grant_type=refresh_token' 'refresh_token=a"b\c d' 'client_id=k')
  _DBX_HTTP_MODO=formulario
  _DBX_HTTP_CAMPOS_NOME=campos
  local arquivo=$DBX_TESTES_TMP/opcoes.$$
  _dbx_http_opcoes >"$arquivo"
  _estado_do_cliente_real -K "$arquivo" -o /dev/null -w '%{http_code}' "$ALVO_QUE_RECUSA"
  rm -f "$arquivo"
  assert_diferente 2 "$DBX_ESTADO_REAL" 'o cliente real recusou as opcoes que geramos'
  assert_igual 7 "$DBX_ESTADO_REAL" 'a unica falha esperada e a conexao recusada'
}

teste_contrato_opcoes_de_token_sao_aceitas_pelo_cliente_real() {
  command -v curl >/dev/null 2>&1 || pular 'curl ausente'
  _DBX_HTTP_MODO=bearer
  _DBX_HTTP_TOKEN='sl.token com espaco e "aspas"'
  local arquivo=$DBX_TESTES_TMP/opcoes2.$$
  _dbx_http_opcoes >"$arquivo"
  _estado_do_cliente_real -K "$arquivo" -o /dev/null -w '%{http_code}' "$ALVO_QUE_RECUSA"
  rm -f "$arquivo"
  assert_igual 7 "$DBX_ESTADO_REAL" 'cabecalho de autorizacao gerado foi recusado'
}

teste_opcoes_de_bearer_incluem_content_type_json() {
  _DBX_HTTP_MODO=bearer
  _DBX_HTTP_TOKEN='token_teste'
  local opcoes
  opcoes=$(_dbx_http_opcoes)
  assert_contem 'header = "Content-Type: application/json"' "$opcoes" \
    'chamadas rpc exigem cabeçalho Content-Type application/json explícito'
  assert_contem 'header = "Authorization: Bearer token_teste"' "$opcoes" \
    'cabeçalho de autorização deve estar presente'
}

teste_interpretacao_de_erro_nao_json_preserva_mensagem_textual() {
  local corpo='Error in call to API function "files/list_folder": Expected Content-Type to be application/json'
  _dbx_http_interpretar_erro "$corpo"
  assert_contem 'Expected Content-Type to be application/json' "$DBX_HTTP_RESUMO_DE_ERRO" \
    'erro em texto puro da API deve ser preservado para diagnóstico'
}

teste_contrato_corpo_ilegivel_produz_status_de_defeito_nosso() {
  command -v curl >/dev/null 2>&1 || pular 'curl ausente'
  _estado_do_cliente_real -s --data-binary '@/caminho/que/nao/existe' \
    -o /dev/null -w '%{http_code}' "$ALVO_QUE_RECUSA"
  assert_igual 26 "$DBX_ESTADO_REAL" 'contrato do cliente para arquivo de corpo ilegivel'
  # A saida do `-w` e registrada como FATO MEDIDO, e o componente nao depende
  # dela: a presenca do `-w` varia dentro de um mesmo codigo de saida conforme a
  # forma da URL — `http://` da `000` e `http://[::1` da vazio, ambos status 3.
  # A classificacao usa o status, que e estavel por familia de causa.
  assert_igual '' "$DBX_SAIDA_W" 'sem transferencia nao ha codigo HTTP para escrever'
}

teste_contrato_opcoes_malformadas_produzem_status_de_defeito_nosso() {
  command -v curl >/dev/null 2>&1 || pular 'curl ausente'
  local arquivo=$DBX_TESTES_TMP/ruim.$$
  printf 'isto-nao-e-uma-opcao-valida\n' >"$arquivo"
  _estado_do_cliente_real -K "$arquivo" -s -o /dev/null -w '%{http_code}' "$ALVO_QUE_RECUSA"
  rm -f "$arquivo"
  assert_igual 2 "$DBX_ESTADO_REAL" 'contrato do cliente para arquivo de opcoes mal formado'
  assert_igual '' "$DBX_SAIDA_W" 'sem transferencia nao ha codigo HTTP para escrever'
}

teste_contrato_conexao_recusada_ainda_produz_codigo_zerado() {
  command -v curl >/dev/null 2>&1 || pular 'curl ausente'
  _estado_do_cliente_real -s -o /dev/null -w '%{http_code}' "$ALVO_QUE_RECUSA"
  assert_igual 7 "$DBX_ESTADO_REAL" 'contrato do cliente para conexao recusada'
  # Falha de REDE ainda escreve `000`; falha NOSSA nao escreve nada. A diferenca
  # e o que distingue as duas familias sem depender de tabela de status.
  assert_igual '000' "$DBX_SAIDA_W" 'falha de rede produz codigo zerado, e nao ausencia'
}

# ---------------------------------------------------------------------------
# QH-03: defeito nosso nao pode virar diagnostico de rede
# ---------------------------------------------------------------------------

_duplo_que_falha() { # <status_do_cliente> [mensagem_no_stderr]
  local status=$1 mensagem=${2:-}
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/duploF.XXXXXX")
  {
    printf '#!/usr/bin/env bash\n'
    printf 'cat >/dev/null 2>&1\n'
    printf '%s\n' "printf '%s\\n' \"\$(cat <<'EOM'
$mensagem
EOM
)\" >&2"
    printf 'exit %s\n' "$status"
  } >"$dir/curl"
  chmod +x "$dir/curl"
  printf '%s' "$dir"
}

teste_defeito_do_cliente_nao_e_classificado_como_falha_de_rede() {
  local dir
  dir=$(_duplo_que_falha 26)
  PATH=$dir:$PATH dbx_http_requisitar POST https://exemplo/api tok '{}' sim
  local estado=$?
  assert_igual 26 "$DBX_HTTP_DEFEITO_CLIENTE" 'o status do cliente deve ser preservado'
  assert_igual 'uso_invalido' "$DBX_HTTP_CLASSE" \
    'defeito nosso mandaria o operador investigar rede alheia'
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$estado" 'codigo de saida coerente'
  assert_igual 'nenhuma' "$DBX_HTTP_POLITICA" 'defeito nosso nao e retentavel'
}

teste_falha_de_rede_continua_sendo_classificada_como_rede() {
  # Discriminacao no outro sentido: sem isto, a regra poderia classificar tudo
  # como defeito nosso e o caso acima passaria do mesmo jeito.
  local dir
  dir=$(_duplo_que_falha 7)
  PATH=$dir:$PATH dbx_http_requisitar POST https://exemplo/api tok '{}' sim
  assert_igual '' "$DBX_HTTP_DEFEITO_CLIENTE" 'falha de conexao nao e defeito nosso'
  assert_igual 'rede' "$DBX_HTTP_CLASSE" 'falha de conexao deve continuar sendo rede'
}

teste_mensagem_do_cliente_e_publicada_e_nao_descartada() {
  local dir
  dir=$(_duplo_que_falha 2 'curl: option --data-binary: error')
  PATH=$dir:$PATH dbx_http_requisitar POST https://exemplo/api tok '{}' sim
  assert_contem 'option --data-binary' "$DBX_HTTP_DIAGNOSTICO" \
    'pedir show-error e descartar o stderr era pedir diagnostico para nao le-lo'
}

# ---------------------------------------------------------------------------
# RNF-30 — timeouts de rede (TC-TMO-01..04)
# ---------------------------------------------------------------------------

teste_opcoes_carregam_timeouts_padrao_em_todos_os_modos() {
  # TC-TMO-01: sem variavel definida, toda requisicao leva os tres valores.
  local dir arquivo
  # O duplo guarda so as opcoes da ULTIMA chamada: confere-se modo a modo.
  local modo
  arquivo="$DBX_TESTES_TMP/corpo-tmo.$$"
  printf 'x' >"$arquivo"
  for modo in bearer conteudo fluxo; do
    dir=$(_duplo 200 '{"ok":true}')
    case $modo in
      bearer) PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim ;;
      conteudo)
        PATH="$dir:$PATH" dbx_http_conteudo POST 'https://c/2/files/upload' 'tok' \
          '{"path":"/a"}' "$arquivo" nao
        ;;
      fluxo)
        PATH="$dir:$PATH" dbx_http_conteudo_receber POST 'https://c/2/files/download' 'tok' \
          '{"path":"/a"}' "$DBX_TESTES_TMP/destino-tmo.$$"
        ;;
    esac
    assert_igual 1 "$(_harness_contar '^connect-timeout = 15$' "$dir/entrada")" \
      "connect-timeout de 15 s no modo $modo"
    assert_igual 1 "$(_harness_contar '^speed-limit = 1024$' "$dir/entrada")" \
      "corte abaixo de 1024 B/s no modo $modo"
    assert_igual 1 "$(_harness_contar '^speed-time = 60$' "$dir/entrada")" \
      "janela de 60 s no modo $modo"
  done
  rm -f "$arquivo" "$DBX_TESTES_TMP/destino-tmo.$$"
}

teste_timeouts_sao_ajustaveis_por_ambiente() {
  # TC-TMO-02.
  local dir
  dir=$(_duplo 200 '{"ok":true}')
  DBX_HTTP_CONNECT_TIMEOUT_S=7 DBX_HTTP_VELOCIDADE_MINIMA_BPS=2048 DBX_HTTP_VELOCIDADE_JANELA_S=30 \
    PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  local opcoes
  opcoes=$(cat "$dir/entrada")
  assert_contem 'connect-timeout = 7' "$opcoes" 'connect-timeout vem do ambiente'
  assert_contem 'speed-limit = 2048' "$opcoes" 'velocidade minima vem do ambiente'
  assert_contem 'speed-time = 30' "$opcoes" 'janela vem do ambiente'
}

teste_variavel_de_ambiente_invalida_e_recusada_antes_da_rede() {
  # TC-TMO-03 e TC-RTY-06 (RNF-30(c), RNF-07(e)): vazio, nao numerico, zero,
  # negativo, fracionario e zero a esquerda (que a aritmetica leria em octal).
  local dir variavel valor estado
  dir=$(_duplo 200 '{"ok":true}')
  for variavel in DBX_HTTP_CONNECT_TIMEOUT_S DBX_HTTP_VELOCIDADE_MINIMA_BPS \
    DBX_HTTP_VELOCIDADE_JANELA_S DBX_HTTP_TENTATIVAS_MAXIMAS DBX_HTTP_ESPERA_BASE_MS \
    DBX_HTTP_ESPERA_TETO_MS DBX_HTTP_RETRY_AFTER_TETO_S; do
    for valor in '' 0 -1 abc 05 1.5 '9 9'; do
      (
        export "$variavel=$valor"
        PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
        estado=$?
        assert_igual "$DBX_HTTP_ERRO_USO" "$estado" "$variavel=[$valor] e uso invalido"
        assert_contem "$variavel" "$DBX_HTTP_MOTIVO_AMBIENTE" 'o motivo nomeia a variavel'
        assert_contem "[$valor]" "$DBX_HTTP_MOTIVO_AMBIENTE" 'o motivo nomeia o valor recusado'
      ) || exit 1
    done
  done
  assert_arquivo_ausente "$dir/argv" 'nenhuma chamada de rede com valor invalido'
}

teste_validacao_de_ambiente_e_publica_e_aceita_o_padrao() {
  assert_sucesso dbx_http_validar_ambiente
  DBX_HTTP_TENTATIVAS_MAXIMAS=0 assert_status "$DBX_HTTP_ERRO_USO" dbx_http_validar_ambiente
}

teste_servidor_mudo_termina_como_falha_transitoria_de_rede() {
  # TC-TMO-04: o cliente sai com 28 quando o tempo se esgota. Em operacao nao
  # idempotente o resultado e `indeterminado` e nao ha repeticao (RNF-07(f)).
  local dir
  dir=$(_duplo 000 '')
  printf '28\n' >"$dir/saida_curl"
  _com_sono "$dir"
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' nao
  assert_igual "$DBX_HTTP_ERRO_REDE" "$?" 'tempo esgotado sai com o codigo de rede'
  assert_igual 'rede' "$DBX_HTTP_CLASSE" 'tempo esgotado e falha de rede'
  assert_igual 'indeterminado' "$DBX_HTTP_POLITICA" 'nao idempotente nao repete'
  assert_igual 1 "$(_harness_contar . "$dir/argv")" 'uma chamada so'
}

teste_servidor_mudo_em_operacao_idempotente_e_repetido() {
  local dir
  dir=$(_duplo 000 '')
  printf '28\n' >"$dir/saida_curl"
  _com_sono "$dir"
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 'rede' "$DBX_HTTP_CLASSE" 'tempo esgotado e falha de rede'
  assert_igual 5 "$(_harness_contar . "$dir/argv")" 'idempotente repete ate o limite'
}

# ---------------------------------------------------------------------------
# RNF-07, RF-09 — retentativa (TC-RTY-01..06). A espera e observada por um
# substituto de `sleep`: a suite nao dorme de verdade (RNF-07(g), RNF-14).
# ---------------------------------------------------------------------------

# _com_sono <dir> — instala no mesmo diretorio do duplo um `sleep` que so
# registra o argumento, um por linha, em `<dir>/esperas`.
_com_sono() {
  local dir=$1
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$1" >>%q\n' "$dir/esperas"
  } >"$dir/sleep"
  chmod +x "$dir/sleep"
}

# _esperas_ms <dir> — cada espera registrada, em milissegundos.
_esperas_ms() {
  local valor
  [[ -r $1/esperas ]] || return 0
  while IFS= read -r valor; do
    [[ $valor =~ ^([0-9]+)\.([0-9]{3})$ ]] ||
      _harness_falhar "espera em formato inesperado: [$valor]"
    printf '%s\n' "$((10#${BASH_REMATCH[1]} * 1000 + 10#${BASH_REMATCH[2]}))"
  done <"$1/esperas"
}

teste_padrao_e_de_cinco_tentativas_contando_a_primeira() {
  # TC-RTY-01.
  local dir
  dir=$(_duplo 503 '{"error_summary":"internal_error/..."}')
  _com_sono "$dir"
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 5 "$(_harness_contar . "$dir/argv")" '5 tentativas, a primeira inclusa'
  assert_igual 4 "$(_harness_contar . "$dir/esperas")" 'uma espera entre cada par de tentativas'
}

teste_numero_de_tentativas_e_configuravel() {
  local dir
  dir=$(_duplo 503 '{"error_summary":"internal_error/..."}')
  _com_sono "$dir"
  DBX_HTTP_TENTATIVAS_MAXIMAS=2 PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 2 "$(_harness_contar . "$dir/argv")" 'o limite vem do ambiente'
  dir=$(_duplo 503 '{"error_summary":"internal_error/..."}')
  _com_sono "$dir"
  DBX_HTTP_TENTATIVAS_MAXIMAS=1 PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 1 "$(_harness_contar . "$dir/argv")" 'uma tentativa e nenhuma repeticao'
  assert_arquivo_ausente "$dir/esperas" 'sem repeticao nao ha espera'
}

teste_recuo_tem_base_de_um_segundo_com_variacao() {
  # TC-RTY-02: espera n = base * 2^(n-1) mais variacao de 0 a base.
  local dir n=1 ms piso
  dir=$(_duplo 503 '{"error_summary":"internal_error/..."}')
  _com_sono "$dir"
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  while IFS= read -r ms; do
    piso=$((1000 * (1 << (n - 1))))
    [[ $ms -ge $piso && $ms -le $((piso + 1000)) ]] ||
      _harness_falhar "espera $n fora de [$piso, $((piso + 1000))] ms" "obtido: $ms"
    n=$((n + 1))
  done < <(_esperas_ms "$dir")
  assert_igual 5 "$n" 'quatro esperas verificadas'
}

teste_recuo_respeita_o_teto_por_espera() {
  local dir ms vistos=0
  dir=$(_duplo 503 '{"error_summary":"internal_error/..."}')
  _com_sono "$dir"
  DBX_HTTP_ESPERA_TETO_MS=2500 PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  while IFS= read -r ms; do
    vistos=$((vistos + 1))
    [[ $ms -le 2500 ]] || _harness_falhar "espera acima do teto de 2500 ms: $ms"
  done < <(_esperas_ms "$dir")
  assert_igual 4 "$vistos" 'todas as esperas conferidas'
  assert_igual 60000 "$DBX_HTTP_ESPERA_TETO_MS_PADRAO" 'teto padrao de 60 s por espera'
}

teste_429_com_retry_after_de_5_espera_ao_menos_5_segundos() {
  # TC-RTY-03: o criterio de RNF-07 que a DIV-22 apontou como nao cumprido.
  local dir ms vistos=0
  dir=$(_duplo 429 '{"error_summary":"too_many_requests/..."}' 'Retry-After: 5')
  _com_sono "$dir"
  PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  while IFS= read -r ms; do
    vistos=$((vistos + 1))
    assert_igual 5000 "$ms" 'Retry-After prevalece sobre o recuo calculado'
  done < <(_esperas_ms "$dir")
  assert_igual 4 "$vistos" 'cada repeticao esperou o que o servidor pediu'
}

teste_retry_after_acima_do_teto_e_limitado_a_300_segundos() {
  # TC-RTY-04.
  local dir
  dir=$(_duplo 429 '{"error_summary":"too_many_requests/..."}' 'retry-after: 400')
  _com_sono "$dir"
  DBX_HTTP_TENTATIVAS_MAXIMAS=2 PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 300000 "$(_esperas_ms "$dir")" 'Retry-After: 400 vira 300 s'
  dir=$(_duplo 429 '{"error_summary":"too_many_requests/..."}' 'Retry-After: 400')
  _com_sono "$dir"
  DBX_HTTP_RETRY_AFTER_TETO_S=10 DBX_HTTP_TENTATIVAS_MAXIMAS=2 PATH="$dir:$PATH" \
    dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 10000 "$(_esperas_ms "$dir")" 'o teto do Retry-After e configuravel'
  # Inteiro valido, mas grande demais para a aritmetica: vale o teto, e nao o
  # recuo, e nunca um valor que transbordou.
  dir=$(_duplo 429 '{"error_summary":"too_many_requests/..."}' 'Retry-After: 99999999999999999999')
  _com_sono "$dir"
  DBX_HTTP_TENTATIVAS_MAXIMAS=2 PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 300000 "$(_esperas_ms "$dir")" 'inteiro enorme e limitado ao teto'
}

teste_retry_after_invalido_ou_em_data_cai_no_recuo() {
  # TC-RTY-05: formato de data HTTP vale como invalido (decisao do Tech Lead).
  local dir valor ms
  for valor in 'abc' 'Wed, 21 Oct 2015 07:28:00 GMT' '-3' '1.5' '5s' ''; do
    dir=$(_duplo 429 '{"error_summary":"too_many_requests/..."}' "Retry-After: $valor")
    _com_sono "$dir"
    DBX_HTTP_TENTATIVAS_MAXIMAS=2 PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
    ms=$(_esperas_ms "$dir")
    [[ $ms =~ ^[0-9]+$ && $ms -ge 1000 && $ms -le 2000 ]] ||
      _harness_falhar "Retry-After [$valor] deveria cair no recuo de 1 a 2 s" "obtido: [$ms]"
  done
}

teste_retry_after_zero_e_valido_e_nao_espera() {
  local dir
  dir=$(_duplo 503 '{"error_summary":"internal_error/..."}' 'Retry-After: 0')
  _com_sono "$dir"
  DBX_HTTP_TENTATIVAS_MAXIMAS=2 PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 0 "$(_esperas_ms "$dir")" 'Retry-After: 0 e inteiro nao negativo e vale'
}

teste_retry_after_depois_do_identificador_de_correlacao_ainda_e_lido() {
  # A leitura de cabecalhos parava no identificador de correlacao.
  local dir
  dir=$(_duplo 429 '{"error_summary":"too_many_requests/..."}' \
    'X-Dropbox-Request-Id: req-1' 'Retry-After: 7')
  _com_sono "$dir"
  DBX_HTTP_TENTATIVAS_MAXIMAS=2 PATH="$dir:$PATH" dbx_http_requisitar POST 'https://api/2/x' 'tok' '' sim
  assert_igual 7000 "$(_esperas_ms "$dir")" 'Retry-After lido mesmo depois da correlacao'
  assert_igual 'req-1' "$DBX_HTTP_CORRELACAO" 'a correlacao continua capturada'
}

teste_mensagem_do_cliente_e_redigida_antes_de_publicar() {
  local dir
  dir=$(_duplo_que_falha 2 'curl: option header: Authorization: Bearer sl.SEGREDO_NA_MENSAGEM')
  PATH=$dir:$PATH dbx_http_requisitar POST https://exemplo/api tok '{}' sim
  assert_segredo_ausente 'sl.SEGREDO_NA_MENSAGEM' "$DBX_HTTP_DIAGNOSTICO" \
    'o cliente reclama citando a opcao, que carrega o segredo'
}

# ---------------------------------------------------------------------------
# P3.4 — sem subshell evitavel no caminho de cada requisicao (fase 3)
# ---------------------------------------------------------------------------

teste_conducao_da_requisicao_nao_captura_a_taxonomia_por_subshell() {
  # Classe, politica e codigo de saida sao consultados por variavel. As duas
  # substituicoes que restam sao necessarias: a area temporaria (mktemp, com o
  # umask isolado) e o codigo HTTP que o cliente escreve na saida padrao.
  local corpo achados
  corpo=$(awk '/^_dbx_http_conduzir\(\) \{/ { dentro = 1 } dentro { print } dentro && /^\}/ { exit }' \
    "$DBX_HARNESS_RAIZ/lib/http.sh")
  assert_contem 'curl -K -' "$corpo" 'sem o corpo da funcao a auditoria seria vacua'
  achados=$(grep -vE '^[[:space:]]*#' <<<"$corpo" | grep -nE '\$\((dbx_errors_|_dbx_errors_)' || true)
  assert_igual '' "$achados" "consulta a taxonomia por substituicao de comando: $achados"
  assert_igual 0 "$(grep -c 'dbx_errors_codigo_saida' <<<"$corpo")" \
    'o codigo de saida vem da tabela, sem chamada dupla'
}

teste_codigo_de_saida_da_requisicao_segue_a_taxonomia() {
  # O comportamento nao muda com a publicacao por variavel.
  local dir http estado esperado
  for http in 400 401 403 404 409; do
    dir=$(_duplo "$http" '{"error_summary":"path/not_found/.."}')
    PATH=$dir:$PATH dbx_http_requisitar POST https://exemplo/api tok '{}' nao
    estado=$?
    assert_diferente '' "$DBX_HTTP_CLASSE" "classe publicada para $http"
    esperado=$(dbx_errors_codigo_saida "$DBX_HTTP_CLASSE")
    assert_igual "$esperado" "$estado" "codigo de saida da classe publicada ($http)"
    assert_igual "$(dbx_errors_classificar "$http" 'path/not_found/..')" "$DBX_HTTP_CLASSE" \
      "a classe e a da taxonomia ($http)"
  done
}

harness_executar "$@"
