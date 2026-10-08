#!/usr/bin/env bash
# list — listagem de pasta remota com paginacao completa (RF-16, RNF-23).
#
# Gemeo de `info` na leitura de metadado: os dois usam `_dbx_cmd_metadado_em`.
# Se o campo emitido mudar, muda para os dois.

dbx_cmd_list_requisitos() { printf 'credencial'; }

readonly DBX_LIST_LIMITE_PADRAO=100

dbx_cmd_list_executar() {
  local caminho='' recursivo='false' limite=$DBX_LIST_LIMITE_PADRAO
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --recursive | -R) recursivo='true' ;;
      --limit)
        shift
        limite=${1-}
        [[ $limite =~ ^[0-9]+$ && $limite -ge 1 && $limite -le 100 ]] || {
          dbx_cmd_falhar uso_invalido "limite invalido: ${limite:-vazio} (1..100)"
          return $?
        }
        ;;
      -*)
        dbx_cmd_falhar uso_invalido "opcao nao reconhecida: $1"
        return $?
        ;;
      *)
        [[ -z $caminho ]] || {
          dbx_cmd_falhar uso_invalido 'informe apenas um caminho'
          return $?
        }
        caminho=$1
        ;;
    esac
    shift
  done

  [[ -n $caminho ]] || caminho='/'
  local remoto
  _dbx_cmd_caminho_remoto "$caminho" || {
    dbx_cmd_falhar caminho_recusado "caminho remoto recusado: $caminho"
    return $?
  }
  remoto=$DBX_CMD_LIDO

  dbx_json_escapar_cadeia "$remoto"
  local corpo="{\"path\":\"$DBX_JSON_ESCAPADO\",\"recursive\":$recursivo}"
  local url='https://api.dropboxapi.com/2/files/list_folder'
  local estado total=0

  while :; do
    dbx_auth_colecao POST "$url" "$corpo" "$limite"
    estado=$?
    [[ $estado -eq 0 ]] || {
      dbx_cmd_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
        "listagem recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
      return $?
    }

    # `dbx_http_colecao` analisa so para decidir sobre o limite e DESCARTA o
    # documento antes de retornar; a leitura dos campos exige analisar de novo.
    _dbx_cmd_analisar_corpo || return $?
    local quantidade indice
    quantidade=$(dbx_json_tamanho_arranjo entries) || quantidade=0
    for ((indice = 0; indice < quantidade; indice++)); do
      dbx_cmd_iniciar_saida
      _dbx_cmd_metadado_em entries "$indice"
      dbx_output_render
      total=$((total + 1))
    done

    local mais='' cursor=''
    _dbx_cmd_campo has_more && mais=$DBX_CMD_LIDO
    _dbx_cmd_campo cursor && cursor=$DBX_CMD_LIDO
    [[ $mais == 'true' && -n $cursor ]] || break
    _dbx_cmd_encerrar_consulta

    # Cursor tratado como possivelmente invalido: `reset` e caminho previsto, e
    # nao excecao. Nao ha fonte que garanta sobrevivencia de cursor, e o desenho
    # nao depende de uma.
    dbx_json_escapar_cadeia "$cursor"
    corpo="{\"cursor\":\"$DBX_JSON_ESCAPADO\"}"
    url='https://api.dropboxapi.com/2/files/list_folder/continue'
  done

  _dbx_cmd_encerrar_consulta
  dbx_cmd_iniciar_saida
  dbx_output_campo total "$total"
  dbx_output_render
  return 0
}
