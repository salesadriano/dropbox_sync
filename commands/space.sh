#!/usr/bin/env bash
# space — uso e cota de espaco da conta (RF-26).
#
# Gemeo de `info`: os dois consultam um endpoint sem corpo util, interpretam um
# documento e emitem campos. A paridade que importa entre eles esta declarada em
# `_dbx_cmd_consultar`, usada pelos dois, para que a proxima correcao num nao
# precise ser lembrada no outro.

dbx_cmd_space_requisitos() { printf 'credencial'; }

dbx_cmd_space_executar() {
  local legivel='nao'
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --human | -H) legivel='sim' ;;
      *)
        dbx_cmd_falhar uso_invalido "argumento nao reconhecido: $1"
        return $?
        ;;
    esac
    shift
  done

  _dbx_cmd_consultar 'https://api.dropboxapi.com/2/users/get_space_usage' 'null' || return $?

  local usado='' alocado=''
  _dbx_cmd_campo used && usado=$DBX_CMD_LIDO
  # A cota vive sob `allocation`, cujo formato varia por tipo de conta: contas
  # de equipe expoem `allocated` em outro ramo. Ausencia nao e erro — o campo sai
  # vazio em vez de a operacao falhar por conta de um tipo nao previsto.
  _dbx_cmd_campo allocation allocated && alocado=$DBX_CMD_LIDO
  _dbx_cmd_encerrar_consulta

  dbx_cmd_iniciar_saida
  dbx_output_campo usado_bytes "$usado"
  dbx_output_campo alocado_bytes "$alocado"
  if [[ $legivel == 'sim' ]]; then
    dbx_output_campo usado_legivel "$(dbx_cmd_bytes_legiveis "$usado")"
    dbx_output_campo alocado_legivel "$(dbx_cmd_bytes_legiveis "$alocado")"
  fi
  dbx_output_render
  return 0
}
