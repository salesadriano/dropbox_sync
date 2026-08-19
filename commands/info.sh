#!/usr/bin/env bash
# info — metadados de um item remoto (RF-17).
#
# Gemeo de `space` no formato da consulta, e gemeo de `list` na interpretacao de
# metadado: os campos `name`, `size`, `content_hash`, `rev` e `.tag` sao lidos
# pelos dois pelo MESMO auxiliar, `_dbx_cmd_metadado_em`. Duplicar a leitura
# faria a proxima correcao valer para um lado so — foi assim sete vezes.

dbx_cmd_info_requisitos() { printf 'credencial'; }

dbx_cmd_info_executar() {
  local caminho=''
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
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
    dbx_cmd_falhar uso_invalido 'informe o caminho remoto'
    return $?
  }

  local remoto
  _dbx_cmd_caminho_remoto "$caminho" || {
    dbx_cmd_falhar caminho_recusado "caminho remoto recusado: $caminho"
    return $?
  }
  remoto=$DBX_CMD_LIDO

  dbx_json_escapar_cadeia "$remoto"
  _dbx_cmd_consultar 'https://api.dropboxapi.com/2/files/get_metadata' \
    "{\"path\":\"$DBX_JSON_ESCAPADO\"}" || return $?

  dbx_cmd_iniciar_saida
  _dbx_cmd_metadado_em
  _dbx_cmd_encerrar_consulta
  dbx_output_render
  return 0
}
