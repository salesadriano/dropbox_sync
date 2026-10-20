#!/usr/bin/env bash
# revisoes — lista as revisoes de um arquivo (RF-72, F-07). Alias: `revisions`.
#
# SO LEITURA: renovacao do token e UMA `list_revisions`, sem paginacao
# automatica (o `--limite` diz quantas) e sem tocar `lib/state`. Cada revisao
# sai pela mesma emissao de `info` e `list` (`_dbx_cmd_metadado_em`), e o
# registro final traz o que e do arquivo e nao de uma revisao: `apagado`,
# `apagado_em`, `mais` e `total`.
#
# No modo `--por-id` a API segue o arquivo atraves de movimentos; a revisao que
# esteve fora da `raiz_remota` nao e mostrada, e a saida diz quantas foram
# omitidas (RF-72(b)): o confinamento vale tambem para o que a API devolve.

dbx_cmd_revisoes_requisitos() { printf 'credencial'; }

readonly DBX_REVISOES_LIMITE_PADRAO=10

dbx_cmd_revisoes_executar() {
  local caminho='' limite=$DBX_REVISOES_LIMITE_PADRAO modo='path'
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --limite | --limit)
        shift
        limite=${1-}
        if [[ ! $limite =~ ^[0-9]{1,3}$ ]] || ((10#$limite < 1 || 10#$limite > 100)); then
          dbx_cmd_caminho_exibivel "$limite"
          dbx_cmd_falhar uso_invalido "limite invalido: [${DBX_CMD_EXIBIDO}] (inteiro de 1 a 100)"
          return $?
        fi
        limite=$((10#$limite))
        ;;
      --por-id | --by-id) modo='id' ;;
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

  [[ -n $caminho ]] || {
    dbx_cmd_falhar uso_invalido 'informe o caminho remoto do arquivo'
    return $?
  }

  local remoto
  _dbx_cmd_caminho_remoto "$caminho" || return $?
  remoto=$DBX_CMD_LIDO
  [[ -n $remoto ]] || {
    dbx_cmd_falhar uso_invalido 'revisoes existem so para arquivos; a raiz da conta e pasta'
    return $?
  }

  dbx_json_escapar_cadeia "$remoto"
  dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/files/list_revisions' \
    "{\"path\":\"$DBX_JSON_ESCAPADO\",\"mode\":\"$modo\",\"limit\":$limite}" sim || {
    local classe=${DBX_HTTP_CLASSE:-erro_remoto}
    case ${DBX_HTTP_RESUMO_DE_ERRO:-} in
      *not_file*)
        dbx_cmd_falhar uso_invalido \
          'revisoes existem so para arquivos; para pasta apagada use dbx restaurar <pasta>'
        return $?
        ;;
    esac
    dbx_cmd_falhar "$classe" \
      "consulta de revisoes recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return $?
  }
  _dbx_cmd_analisar_corpo || return $?

  local quantidade indice total=0 omitidas=0
  quantidade=$(dbx_json_tamanho_arranjo entries) || quantidade=0
  for ((indice = 0; indice < quantidade; indice++)); do
    if [[ $modo == 'id' ]]; then
      _dbx_cmd_campo entries "$indice" path_display || DBX_CMD_LIDO=''
      dbx_cmd_remoto_confinado "$DBX_CMD_LIDO" || {
        omitidas=$((omitidas + 1))
        continue
      }
    fi
    dbx_cmd_iniciar_saida
    _dbx_cmd_metadado_em entries "$indice"
    dbx_output_render
    total=$((total + 1))
  done

  local apagado='nao' apagado_em='' mais='nao'
  _dbx_cmd_campo is_deleted && [[ $DBX_CMD_LIDO == 'true' ]] && apagado='sim'
  _dbx_cmd_campo server_deleted && apagado_em=$DBX_CMD_LIDO
  _dbx_cmd_campo has_more && [[ $DBX_CMD_LIDO == 'true' ]] && mais='sim'
  _dbx_cmd_encerrar_consulta

  dbx_cmd_iniciar_saida
  dbx_cmd_campo_caminho caminho "$remoto"
  dbx_output_campo apagado "$apagado"
  [[ -n $apagado_em ]] && dbx_output_campo apagado_em "$apagado_em"
  dbx_output_campo mais "$mais"
  [[ $modo == 'id' ]] && dbx_output_campo omitidas "$omitidas"
  dbx_output_campo total "$total"
  dbx_output_render
  return 0
}
