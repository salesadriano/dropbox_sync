#!/usr/bin/env bash
# Testes da base do sync em blocos (secao 5.24: RF-186, RF-187, RF-189).
#
# Etapa 1: validacao de --bloco/DBX_BLOCO, planejador de ciclos (puro) e listagem
# remota de UM diretorio. Nada aqui toca rede: a camada de autenticacao e
# substituida por funcoes locais que devolvem paginas sinteticas.
#
# shellcheck disable=SC2034
# Justificativa: vetores passados por nome e canais publicos lidos pela lib.
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
. "$DBX_HARNESS_RAIZ/lib/cli.sh"
. "$DBX_HARNESS_RAIZ/lib/cmd.sh"
. "$DBX_HARNESS_RAIZ/lib/sync.sh"

readonly H1=1111111111111111111111111111111111111111111111111111111111111111

# ---------------------------------------------------------------------------
# RF-186: faixa, validacao e precedencia
# ---------------------------------------------------------------------------

teste_validar_bloco_aceita_a_faixa_1_a_1000000() {
  local valor
  for valor in 1 7 50000 999999 1000000; do
    dbx_cli_validar_bloco --bloco "$valor" opcao
    assert_igual 0 "$?" "aceita [$valor]"
    assert_igual "$valor" "$DBX_CLI_BLOCO" "publica [$valor]"
  done
}

teste_validar_bloco_recusa_fora_da_faixa_e_formato_invalido() {
  local valor
  for valor in 0 1000001 9999999 -1 +1 01 '' ' 1' '1 ' a 1.5 1e3 $'1\n'; do
    dbx_cli_validar_bloco --bloco "$valor" opcao
    assert_igual "$DBX_CLI_ERRO_USO" "$?" "recusa [$valor]"
    assert_igual '' "$DBX_CLI_BLOCO" "nada publicado para [$valor]"
    assert_contem '--bloco' "$DBX_CLI_MOTIVO" 'nomeia a opcao'
  done
  dbx_cli_validar_bloco DBX_BLOCO 0 variavel
  assert_contem 'variavel de ambiente DBX_BLOCO' "$DBX_CLI_MOTIVO" 'nomeia a variavel'
}

teste_bloco_padrao_sem_opcao_nem_variavel() {
  unset DBX_BLOCO
  dbx_cmd_bloco nao '' ''
  assert_igual 0 "$?" 'resolve'
  assert_igual 50000 "$DBX_CMD_BLOCO" 'padrao 50000'
  assert_igual padrao "$DBX_CMD_BLOCO_ORIGEM" 'origem padrao'
}

teste_bloco_variavel_valida_vale_e_invalida_recusa() {
  DBX_BLOCO=100 dbx_cmd_bloco nao '' ''
  assert_igual 100 "$DBX_CMD_BLOCO" 'variavel vale'
  assert_igual ambiente "$DBX_CMD_BLOCO_ORIGEM" 'origem ambiente'
  local estado
  DBX_BLOCO=abc dbx_cmd_bloco nao '' ''
  estado=$?
  assert_igual "$DBX_CLI_ERRO_USO" "$estado" 'variavel invalida recusa'
  assert_contem 'DBX_BLOCO' "$DBX_CLI_MOTIVO" 'nomeia a variavel'
  DBX_BLOCO= dbx_cmd_bloco nao '' ''
  assert_igual "$DBX_CLI_ERRO_USO" "$?" 'variavel vazia recusa'
}

teste_bloco_opcao_vence_e_a_variavel_nao_e_lida() {
  DBX_BLOCO=abc dbx_cmd_bloco sim --bloco 100
  assert_igual 0 "$?" 'opcao valida vence variavel invalida'
  assert_igual 100 "$DBX_CMD_BLOCO" 'valor da opcao'
  assert_igual opcao "$DBX_CMD_BLOCO_ORIGEM" 'origem opcao'
  dbx_cmd_bloco sim --batch 0
  assert_igual "$DBX_CLI_ERRO_USO" "$?" 'opcao invalida recusa'
  assert_contem '--batch' "$DBX_CLI_MOTIVO" 'nomeia a opcao como digitada'
}

# ---------------------------------------------------------------------------
# RF-187: planejador de ciclos (puro)
# ---------------------------------------------------------------------------

# _ciclos <n> <nome:contagem>... — ciclos em `ini-fim` (indices, fim exclusivo).
_ciclos() {
  local n=$1 par
  shift
  local -a nomes=() contagens=()
  for par in "$@"; do
    nomes+=("${par%%:*}")
    contagens+=("${par##*:}")
  done
  dbx_sync_blocos_planejar nomes contagens "$n"
  assert_igual 0 "$?" 'planeja'
  printf '%s ' "${DBX_SYNC_BLOCOS_CICLOS[@]}"
}

teste_planejador_arvore_que_cabe_forma_um_ciclo() {
  assert_igual '0-3 ' "$(_ciclos 100 /a:10 /b:20 /c:30)" 'total menor que N: um ciclo'
}

teste_planejador_diretorio_que_cruza_n_entra_inteiro_e_fecha() {
  assert_igual '0-2 2-3 ' "$(_ciclos 10 /a:6 /b:6 /c:1)" 'b cruza N=10 (12), entra inteiro e fecha'
}

teste_planejador_total_exato_em_n_fecha_o_ciclo() {
  assert_igual '0-2 2-3 ' "$(_ciclos 10 /a:6 /b:4 /c:1)" 'atingir N fecha o ciclo'
}

teste_planejador_diretorio_maior_que_n_fica_sozinho() {
  assert_igual '0-1 1-2 2-3 ' "$(_ciclos 10 /a:3 /b:50 /c:1)" 'b > N: ciclo proprio; a fecha antes'
}

teste_planejador_diretorio_vazio_conta_zero_e_e_unidade() {
  assert_igual '0-4 ' "$(_ciclos 10 /a:0 /b:0 /c:3 /d:0)" 'zero arquivos nao fecha ciclo'
}

teste_planejador_cada_diretorio_em_exatamente_um_ciclo() {
  local -a nomes=() contagens=()
  local i
  for i in {0..39}; do
    nomes+=("/d$i")
    contagens+=($(((i * 7) % 13)))
  done
  dbx_sync_blocos_planejar nomes contagens 17
  local ciclo cobertos='' esperado=''
  for ciclo in "${DBX_SYNC_BLOCOS_CICLOS[@]}"; do
    for ((i = ${ciclo%-*}; i < ${ciclo#*-}; i++)); do cobertos+="$i "; done
  done
  for i in {0..39}; do esperado+="$i "; done
  assert_igual "$esperado" "$cobertos" 'nenhum omitido, nenhum duplicado, ordem preservada'
}

teste_planejador_lista_vazia_e_entrada_invalida() {
  local -a nomes=() contagens=()
  dbx_sync_blocos_planejar nomes contagens 10
  assert_igual 0 "$?" 'lista vazia planeja'
  assert_igual 0 "${#DBX_SYNC_BLOCOS_CICLOS[@]}" 'nenhum ciclo'
  nomes=(/a)
  contagens=(x)
  dbx_sync_blocos_planejar nomes contagens 10
  assert_igual "$DBX_SYNC_ERRO_USO" "$?" 'contagem nao numerica e uso invalido'
  contagens=(1 2)
  dbx_sync_blocos_planejar nomes contagens 10
  assert_igual "$DBX_SYNC_ERRO_USO" "$?" 'vetores de tamanhos diferentes'
}

# ---------------------------------------------------------------------------
# RF-189: listagem remota de UM diretorio, nao recursiva
# ---------------------------------------------------------------------------

T_CORPOS=()
T_PEDIDOS=()
T_FALHA_NA_PAGINA=0
T_RESUMO_ERRO=''

# Dobros da camada de autenticacao: devolvem a proxima pagina sintetica.
dbx_auth_colecao() { _dobro "$2" "$3"; }
dbx_auth_requisitar() { _dobro "$2" "$3"; }
_dobro() {
  T_PEDIDOS+=("$1 $2")
  local indice=$((${#T_PEDIDOS[@]} - 1))
  if ((T_FALHA_NA_PAGINA == indice + 1)); then
    DBX_HTTP_CODIGO=500
    DBX_HTTP_CLASSE=erro_remoto
    DBX_HTTP_RESUMO_DE_ERRO=$T_RESUMO_ERRO
    return 1
  fi
  DBX_HTTP_CORPO=${T_CORPOS[indice]}
  return 0
}

_reiniciar_dobro() {
  T_CORPOS=()
  T_PEDIDOS=()
  T_FALHA_NA_PAGINA=0
  T_RESUMO_ERRO=''
  dbx_sync_tabela_zerar
}

_arq() { printf '{".tag":"file","id":"id:%s","path_lower":"%s","path_display":"%s","rev":"0123456789a","size":3,"content_hash":"%s"}' "$2" "${1,,}" "$1" "$H1"; }
_pasta() { printf '{".tag":"folder","id":"id:%s","path_lower":"%s","path_display":"%s"}' "$2" "${1,,}" "$1"; }

teste_listar_diretorio_pede_nao_recursivo_e_alimenta_a_tabela() {
  _reiniciar_dobro
  T_CORPOS=("{\"entries\":[$(_arq /r/d/A.txt a1),$(_pasta /r/d/Sub s1)],\"has_more\":false}")
  dbx_sync_listar_diretorio /r /r/d
  assert_igual 0 "$?" 'lista'
  assert_contem '"recursive":false' "${T_PEDIDOS[0]}" 'nao recursivo'
  assert_contem 'list_folder' "${T_PEDIDOS[0]}" 'endpoint list_folder'
  [[ ${DBX_SYNC_TAB[/r/d/a.txt]-} == f$'\t'* ]] || _harness_falhar 'arquivo entrou na tabela'
  [[ ${DBX_SYNC_TAB[/r/d/sub]-} == d$'\t'* ]] || _harness_falhar 'subpasta entrou na tabela'
}

teste_listar_diretorio_acumula_entre_chamadas_e_segue_continue() {
  _reiniciar_dobro
  T_CORPOS=("{\"entries\":[$(_arq /r/d/a.txt a1)],\"has_more\":true,\"cursor\":\"c1\"}"
    "{\"entries\":[$(_arq /r/d/b.txt b1)],\"has_more\":false,\"cursor\":\"c2\"}"
    "{\"entries\":[$(_arq /r/e/c.txt c1)],\"has_more\":false}")
  dbx_sync_listar_diretorio /r /r/d
  assert_igual 0 "$?" 'diretorio d lista'
  assert_contem 'list_folder/continue' "${T_PEDIDOS[1]}" 'segue por continue'
  dbx_sync_listar_diretorio /r /r/e
  assert_igual 0 "$?" 'diretorio e lista sem zerar a tabela'
  local _chaves_ordenadas _chave _lista=
  mapfile -t _chaves_ordenadas < <(printf '%s\n' "${!DBX_SYNC_TAB[@]}" | LC_ALL=C sort)
  for _chave in "${_chaves_ordenadas[@]}"; do _lista+="$_chave "; done
  assert_igual '/r/d/a.txt /r/d/b.txt /r/e/c.txt ' "$_lista" 'tabela acumulada'
}

teste_listar_diretorio_inexistente_e_vazio_legitimo() {
  _reiniciar_dobro
  T_FALHA_NA_PAGINA=1
  T_RESUMO_ERRO='path/not_found/'
  dbx_sync_listar_diretorio /r /r/nada
  assert_igual 0 "$?" 'not_found nao e falha'
  assert_igual 0 "${#DBX_SYNC_TAB[@]}" 'nada na tabela'
}

teste_listar_diretorio_falha_remota_sinaliza_parcialidade() {
  _reiniciar_dobro
  T_FALHA_NA_PAGINA=1
  T_RESUMO_ERRO='too_many_requests'
  dbx_sync_listar_diretorio /r /r/d
  assert_diferente 0 "$?" 'falha devolve o codigo da classe'
  assert_contem 'enumeracao remota' "$DBX_SYNC_MOTIVO" 'motivo'
}

teste_listar_diretorio_falha_na_segunda_pagina_e_parcial() {
  _reiniciar_dobro
  T_CORPOS=("{\"entries\":[$(_arq /r/d/a.txt a1)],\"has_more\":true,\"cursor\":\"c1\"}")
  T_FALHA_NA_PAGINA=2
  dbx_sync_listar_diretorio /r /r/d
  assert_diferente 0 "$?" 'falha na pagina 2'
}

teste_listar_diretorio_cursor_repetido_e_erro_remoto_parcial() {
  _reiniciar_dobro
  T_CORPOS=("{\"entries\":[],\"has_more\":true,\"cursor\":\"c1\"}" "{\"entries\":[],\"has_more\":true,\"cursor\":\"c1\"}")
  local estado
  dbx_sync_listar_diretorio /r /r/d
  estado=$?
  assert_igual "$(dbx_errors_codigo_saida erro_remoto)" "$estado" 'laco de paginas e erro_remoto'
}

teste_listar_diretorio_recusa_uso_incorreto() {
  dbx_sync_listar_diretorio /r
  assert_igual "$DBX_SYNC_ERRO_USO" "$?" 'faltam argumentos'
}

harness_executar "$@"
