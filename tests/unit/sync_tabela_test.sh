#!/usr/bin/env bash
# Testes diretos da tabela remota de lib/sync.sh (fase 7b, F-14; DIV-g; RF-112,
# RF-114, RF-115; parecer do DBA, secao 5 e C3, C4, C5).
#
# A tabela e o ponto onde a varredura completa e a incremental se encontram: o
# retrato carregado e o delta aplicado montam a MESMA estrutura que a listagem
# viva, e o escopo filtrado e emitido depois, pelo mesmo codigo. Estes casos
# provam a receita do servico (Context7, `list_folder`), a coerencia exigida do
# delta, o confinamento do retrato e o agrupamento das confirmacoes de exclusao.
#
# A unica fronteira dublada e a rede (`dbx_auth_requisitar`), redefinida por
# caso na confirmacao.
#
# shellcheck disable=SC2034
# Justificativa: vetores e canais sao lidos por nome por lib/sync.
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
. "$DBX_HARNESS_RAIZ/lib/sync.sh"

readonly H1=1111111111111111111111111111111111111111111111111111111111111111

_arq_json() { # <caminho_display> [id] [rev] — entrada `file` em T_E
  local baixo=${1,,}
  printf -v T_E '{".tag":"file","id":"%s","path_lower":"%s","path_display":"%s","rev":"%s","size":3,"content_hash":"%s"}' \
    "${2:-id:${1//[^A-Za-z0-9]/_}}" "$baixo" "$1" "${3:-0123456789a}" "$H1"
}

_pasta_json() {
  local baixo=${1,,}
  printf -v T_E '{".tag":"folder","id":"id:d%s","path_lower":"%s","path_display":"%s"}' "${1//[^A-Za-z0-9]/_}" "$baixo" "$1"
}

_apagado_json() {
  local baixo=${1,,}
  printf -v T_E '{".tag":"deleted","name":"x","path_lower":"%s","path_display":"%s"}' "$baixo" "$1"
}

# _aplicar <modo> <entradas...> — aplica uma pagina a tabela; status da
# primeira entrada recusada (delta) em T_ESTADO.
_aplicar() {
  local modo=$1 lista='' e i n
  shift
  for e in "$@"; do lista+=${lista:+,}$e; done
  printf -v DBX_HTTP_CORPO '{"entries":[%s],"has_more":false}' "$lista"
  dbx_json_contexto comando
  dbx_json_analisar "$DBX_HTTP_CORPO" || _harness_falhar 'pagina malformada no proprio teste'
  n=$(dbx_json_tamanho_arranjo entries)
  T_ESTADO=0
  for ((i = 0; i < n; i++)); do
    _dbx_sync_entrada /r "$i" "$modo" || { T_ESTADO=1; break; }
  done
  _dbx_cmd_encerrar_consulta
}

_chaves() { # chaves presentes, ordenadas
  printf '%s\n' "${!DBX_SYNC_TAB[@]}" | LC_ALL=C sort | tr '\n' ' '
}

teste_receita_do_servico_deleted_file_e_folder() {
  local -a e=()
  dbx_sync_tabela_zerar
  _pasta_json /r/p && e+=("$T_E")
  _arq_json /r/p/a.txt && e+=("$T_E")
  _arq_json /r/p/b.txt && e+=("$T_E")
  _arq_json /r/q && e+=("$T_E")
  _pasta_json /r/s && e+=("$T_E")
  _arq_json /r/s/f.txt && e+=("$T_E")
  _aplicar completa "${e[@]}"
  assert_igual '/r/p /r/p/a.txt /r/p/b.txt /r/q /r/s /r/s/f.txt ' "$(_chaves)" 'varredura: tabela inteira, sem filtro'
  assert_igual sim "$DBX_SYNC_TAB_PERSISTIVEL" 'entradas no formato: persistivel'
  e=()
  # deleted de pasta remove os descendentes; deleted desconhecido e ignorado;
  # pasta sobre arquivo remove o arquivo; arquivo sobre pasta remove os filhos.
  _apagado_json /r/p && e+=("$T_E")
  _apagado_json /r/nunca && e+=("$T_E")
  _pasta_json /r/q && e+=("$T_E")
  _arq_json /r/s '' 'bbbbbbbbbbb' && e+=("$T_E")
  # lib/sync zera a contagem no inicio de cada delta (dbx_sync_listar_delta).
  DBX_SYNC_DELTA_MUDANCAS=0
  _aplicar delta "${e[@]}"
  assert_igual 0 "$T_ESTADO" 'delta coerente'
  assert_igual '/r/q /r/s ' "$(_chaves)" 'receita aplicada'
  [[ ${DBX_SYNC_TAB[/r/q]} == d$'\t'* ]] || _harness_falhar 'q virou pasta'
  [[ ${DBX_SYNC_TAB[/r/s]} == f$'\t'* ]] || _harness_falhar 's virou arquivo'
  assert_igual '/r/p' "${!DBX_SYNC_DELTA_APAGADAS[*]}" 'so a raiz apagada que existia e registrada'
  assert_igual 4 "$DBX_SYNC_DELTA_MUDANCAS" 'quatro mudancas'
}

teste_delta_incoerente_e_recusado_e_a_varredura_so_marca() {
  local caso
  for caso in sem_id sem_rev fora ponto controle; do
    dbx_sync_tabela_zerar
    case $caso in
      sem_id) T_E='{".tag":"file","path_lower":"/r/a","path_display":"/r/a","rev":"0123456789a","size":1}' ;;
      sem_rev) T_E='{".tag":"file","id":"id:a","path_lower":"/r/a","path_display":"/r/a","size":1}' ;;
      fora) _arq_json /outra/a ;;
      ponto) _arq_json /r/../a ;;
      controle) printf -v T_E '{".tag":"file","id":"id:a","path_lower":"/r/a\\u0001","path_display":"/r/a\\u0001","rev":"0123456789a","size":1}' ;;
    esac
    _aplicar delta "$T_E"
    assert_igual 1 "$T_ESTADO" "$caso: o delta recusa (RF-112(e))"
    dbx_sync_tabela_zerar
    _aplicar completa "$T_E"
    assert_igual 0 "$T_ESTADO" "$caso: a varredura segue como hoje"
    assert_igual nao "$DBX_SYNC_TAB_PERSISTIVEL" "$caso: mas o retrato nao e gravavel"
  done
}

teste_ids_unicos_detecta_movimento_sem_deleted() {
  local -a e=()
  dbx_sync_tabela_zerar
  _arq_json /r/a.txt id:X && e+=("$T_E")
  _aplicar completa "${e[@]}"
  _arq_json /r/b.txt id:X
  _aplicar delta "$T_E"
  _dbx_sync_ids_unicos && _harness_falhar 'mesmo id em dois caminhos deveria reprovar'
  _apagado_json /r/a.txt
  _aplicar delta "$T_E"
  _dbx_sync_ids_unicos || _harness_falhar 'com o deleted do antigo, ids unicos'
  return 0
}

teste_emitir_aplica_o_escopo_depois_e_conta_como_antes() {
  local -a e=() caminhos=() metas=() conteudo=()
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/tabela.XXXXXX")
  dbx_sync_tabela_zerar
  _pasta_json /r/p && e+=("$T_E")
  _arq_json /r/p/a.txt && e+=("$T_E")
  _arq_json /r/b.txt && e+=("$T_E")
  _arq_json /r/c.log && e+=("$T_E")
  _pasta_json /r/vazia && e+=("$T_E")
  _aplicar completa "${e[@]}"
  caminhos=(--excluir p --excluir '*.log' --excluir vazia)
  dbx_cmd_filtros_preparar caminhos metas || _harness_falhar "filtros: $DBX_CMD_FILTRO_MOTIVO"
  dbx_sync_filtrados_zerar
  dbx_sync_tabela_emitir /r "$area/remoto" "$area/revs" origem
  assert_igual 3 "$DBX_SYNC_REMOTOS_ANTES" 'arquivos antes do filtro'
  assert_igual 3 "$DBX_SYNC_FILTRADOS" 'pasta excluida conta 1 (inclusive vazia), o .log 1 (RF-80(i))'
  mapfile -d '' -t conteudo <"$area/remoto"
  assert_igual "$H1"$'\t3\tb.txt' "${conteudo[*]}" 'so b.txt no escopo, no formato de lib/walk'
  mapfile -d '' -t conteudo <"$area/revs"
  assert_igual $'0123456789a\tb.txt' "${conteudo[*]}" 'rev em arquivo proprio'
}

teste_retrato_confina_cada_caminho_e_recusa_repetido() {
  dbx_sync_tabela_zerar
  DBX_SYNC_RETRATO_RAIZ=/r
  dbx_sync_retrato_entrada $'f\tid:a\t0123456789a\t-\t1\t-\t/r/a' /r/a f id:a /r/a ||
    _harness_falhar 'entrada valida recusada'
  dbx_sync_retrato_entrada $'f\tid:b\t0123456789a\t-\t1\t-\t/r/a' /r/a f id:b /r/a &&
    _harness_falhar 'path_lower repetido deveria ser recusado'
  dbx_sync_retrato_entrada $'f\tid:c\t0123456789a\t-\t1\t-\t/r/../x' /r/../x f id:c /r/../x &&
    _harness_falhar '.. deveria ser recusado (RF-50)'
  dbx_sync_retrato_entrada $'f\tid:d\t0123456789a\t-\t1\t-\t/fora/x' /fora/x f id:d /fora/x &&
    _harness_falhar 'fora da raiz deveria ser recusado'
  dbx_sync_retrato_entrada $'f\tid:e\t0123456789a\t-\t1\t-\t/r/ok' /outra/ok f id:e /r/ok &&
    _harness_falhar 'path_lower fora da raiz deveria ser recusado'
  return 0
}

teste_tabela_datada_so_com_filtro_de_data() {
  dbx_sync_tabela_zerar
  _arq_json /r/a.txt
  _aplicar completa "$T_E"
  DBX_FILTRO_DESDE='' DBX_FILTRO_ATE=''
  dbx_sync_tabela_datada || _harness_falhar 'sem filtro de data, sempre serve'
  DBX_FILTRO_DESDE='2026-01-01T00:00:00Z'
  dbx_sync_tabela_datada && _harness_falhar 'filtro de data com entrada sem data: varredura completa'
  DBX_FILTRO_DESDE=''
  return 0
}

# Dublagem da rede na confirmacao: cada pedido em T_PEDIDOS, resposta por
# T_RESPOSTA (`nf` not_found, `existe`, `5xx`, `outro409`).
# shellcheck disable=SC2317  # a funcao dublada e chamada por lib/sync
_rede_dublada() {
  dbx_auth_requisitar() {
    T_PEDIDOS+=("$3")
    DBX_HTTP_RESUMO_DO_SERVICO='' DBX_HTTP_CLASSE='' DBX_HTTP_CODIGO=''
    case $T_RESPOSTA in
      nf) DBX_HTTP_CODIGO=409 DBX_HTTP_CLASSE=nao_encontrado DBX_HTTP_RESUMO_DO_SERVICO='path/not_found/..'; return 4 ;;
      existe) DBX_HTTP_CODIGO=200 DBX_HTTP_CORPO='{".tag":"file","id":"id:outro"}'; return 0 ;;
      5xx) DBX_HTTP_CODIGO=503 DBX_HTTP_CLASSE=erro_remoto; return 10 ;;
      outro409) DBX_HTTP_CODIGO=409 DBX_HTTP_CLASSE=nao_encontrado DBX_HTTP_RESUMO_DO_SERVICO='path/malformed_path/'; return 4 ;;
    esac
  }
}

teste_confirmacao_agrupa_por_raiz_apagada_e_respeita_o_teto() {
  local -a candidatas=(p/x.txt P/Y.txt z.txt) muitas=()
  local i
  _rede_dublada
  dbx_sync_tabela_zerar
  DBX_SYNC_DELTA_APAGADAS=([/r/p]=$'d\tid:p\t-\t-\t0\t-\t/r/p')
  T_PEDIDOS=() T_RESPOSTA=nf
  dbx_sync_confirmar_exclusoes /r candidatas
  assert_igual 0 $? 'confirmadas por not_found'
  assert_igual 2 "${#T_PEDIDOS[@]}" 'uma por raiz apagada (p) e uma avulsa (z.txt)'
  assert_contem '"path":"/r/p"' "${T_PEDIDOS[*]}" 'a raiz confirma os descendentes, sem caixa'
  assert_contem '"path":"/r/z.txt"' "${T_PEDIDOS[*]}" 'ausencia no retrato tambem e confirmada (DIV-m)'
  assert_igual 2 "$DBX_SYNC_CONFIRMADAS" 'contagem'
  for ((i = 0; i < 51; i++)); do muitas+=("f$i.txt"); done
  T_PEDIDOS=()
  dbx_sync_confirmar_exclusoes /r muitas
  assert_igual 1 $? '51 alvos: varredura completa'
  assert_igual 0 "${#T_PEDIDOS[@]}" 'nenhuma confirmacao emitida (TC-CUF-10)'
  unset 'muitas[50]'
  T_PEDIDOS=()
  dbx_sync_confirmar_exclusoes /r muitas
  assert_igual 0 $? '50 alvos: confirmados'
  assert_igual 50 "${#T_PEDIDOS[@]}" '50 confirmacoes sequenciais'
}

teste_so_not_found_confirma() {
  local -a candidatas=(a.txt)
  local estado
  _rede_dublada
  dbx_sync_tabela_zerar
  T_PEDIDOS=() T_RESPOSTA=existe
  dbx_sync_confirmar_exclusoes /r candidatas
  estado=$?
  assert_igual 1 "$estado" 'metadado presente: contradicao'
  assert_igual contradicao "$DBX_SYNC_CURSOR_MOTIVO" 'motivo'
  T_RESPOSTA=outro409
  dbx_sync_confirmar_exclusoes /r candidatas
  assert_igual 1 $? 'outro 409 nao prova a ausencia'
  T_RESPOSTA=5xx
  dbx_sync_confirmar_exclusoes /r candidatas
  assert_igual 2 $? 'transporte: falha da fase de enumeracao (RF-114(b))'
}

teste_raiz_apagada_e_recriada_nao_cobre_ninguem() {
  local -a candidatas=(p/x.txt)
  _rede_dublada
  dbx_sync_tabela_zerar
  _pasta_json /r/p
  _aplicar completa "$T_E"
  DBX_SYNC_DELTA_APAGADAS=([/r/p]=$'d\tid:p\t-\t-\t0\t-\t/r/p')
  T_PEDIDOS=() T_RESPOSTA=nf
  dbx_sync_confirmar_exclusoes /r candidatas
  assert_contem '"path":"/r/p/x.txt"' "${T_PEDIDOS[*]}" 'a pasta voltou: confirma o proprio item'
}

teste_qa_b7b_02_entrada_da_propria_raiz_e_ignorada_sem_bloquear_o_retrato() {
  # Context7 (`list_folder`): listar /Homework/math devolve a entrada
  # /homework/math. Reconhecida pela estrutura (pasta, `path_lower` igual a
  # raiz pedida), ela nao entra na tabela nem reprova a persistencia.
  local -a e=()
  dbx_sync_tabela_zerar
  _pasta_json /r && e+=("$T_E")
  _arq_json /r/a.txt && e+=("$T_E")
  _aplicar completa "${e[@]}"
  assert_igual 0 "$T_ESTADO" 'completa aceita'
  assert_igual sim "$DBX_SYNC_TAB_PERSISTIVEL" 'a propria pasta nao bloqueia o retrato (QA-B7B-02)'
  assert_igual '/r/a.txt ' "$(_chaves)" 'a raiz nao entra na tabela'
  _pasta_json /R
  _aplicar delta "$T_E"
  assert_igual 0 "$T_ESTADO" 'no delta, a propria pasta tambem e ignorada'
  assert_igual '/r/a.txt ' "$(_chaves)" 'tabela intacta'
  # Qualquer outra entrada fora da raiz continua reprovando.
  _pasta_json /rr
  _aplicar delta "$T_E"
  assert_igual 1 "$T_ESTADO" 'pasta irma com prefixo parecido reprova'
  _arq_json /r
  _aplicar delta "$T_E"
  assert_igual 1 "$T_ESTADO" 'arquivo com o caminho da raiz reprova'
  _apagado_json /r
  _aplicar delta "$T_E"
  assert_igual 1 "$T_ESTADO" 'a raiz apagada no delta reprova (varredura completa)'
}

teste_qa_b7b_03_delta_confina_tambem_o_path_lower() {
  local caso
  for caso in ponto fora; do
    dbx_sync_tabela_zerar
    case $caso in
      ponto) T_E='{".tag":"file","id":"id:ok","path_lower":"/r/../ok.txt","path_display":"/r/ok.txt","rev":"0123456789a","size":1}' ;;
      fora) T_E='{".tag":"file","id":"id:ok","path_lower":"/outra/ok.txt","path_display":"/r/ok.txt","rev":"0123456789a","size":1}' ;;
    esac
    _aplicar delta "$T_E"
    assert_igual 1 "$T_ESTADO" "$caso: path_lower fora do confinamento reprova o delta (RF-112(e), RF-115(h))"
    dbx_sync_tabela_zerar
    _aplicar completa "$T_E"
    assert_igual nao "$DBX_SYNC_TAB_PERSISTIVEL" "$caso: na completa, o retrato nao e gravavel"
  done
}

teste_qa_b7b_01_raiz_vazia_da_api_confina_e_ignora_nada() {
  # A raiz `/` da credencial e "" na API: todo caminho absoluto esta nela.
  dbx_sync_tabela_zerar
  printf -v DBX_HTTP_CORPO '{"entries":[{".tag":"file","id":"id:a","path_lower":"/a.txt","path_display":"/A.txt","rev":"0123456789a","size":1,"content_hash":"%s"}],"has_more":false}' "$H1"
  dbx_json_contexto comando
  dbx_json_analisar "$DBX_HTTP_CORPO" || _harness_falhar 'pagina malformada'
  _dbx_sync_entrada '' 0 delta || _harness_falhar 'raiz vazia: arquivo na raiz e coerente'
  _dbx_cmd_encerrar_consulta
  assert_igual '/a.txt ' "$(_chaves)" 'chave pelo path_lower'
  DBX_SYNC_RETRATO_RAIZ=''
  dbx_sync_retrato_entrada $'f\tid:b\t0123456789a\t-\t1\t-\t/b' /b f id:b /b || _harness_falhar 'retrato da raiz vazia aceito'
}

harness_executar "$@"
