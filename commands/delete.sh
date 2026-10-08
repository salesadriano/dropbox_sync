#!/usr/bin/env bash
# delete — exclusao de item remoto (RF-21, RF-49, RF-15).
#
# Gemeo de `upload` na escrita remota: os dois passam por
# `_dbx_cmd_escrita_remota`, que concentra simulacao, `rev` e mapeamento de
# conflito. O `sync` sera o terceiro pelo mesmo caminho.

dbx_cmd_delete_requisitos() { printf 'credencial'; }

dbx_cmd_delete_executar() {
  local caminho='' confirmado='nao' rev=''
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --yes | -y) confirmado='sim' ;;
      --rev)
        shift
        rev=${1-}
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

  [[ -n $caminho ]] || {
    dbx_cmd_falhar uso_invalido 'informe o caminho remoto'
    return $?
  }

  # RF-21 com RNF-19: sem terminal associado nenhuma pergunta pode bloquear o
  # processo, entao a confirmacao e por sinalizador explicito. Recusar e o lado
  # correto do erro: exclusao nao confirmada nao acontece.
  [[ $confirmado == 'sim' ]] || {
    dbx_cmd_falhar uso_invalido 'exclusao exige confirmacao explicita: use --yes'
    return $?
  }

  local remoto
  _dbx_cmd_caminho_remoto "$caminho" || {
    dbx_cmd_falhar caminho_recusado "caminho remoto recusado: $caminho"
    return $?
  }
  remoto=$DBX_CMD_LIDO

  dbx_json_escapar_cadeia "$remoto"
  local corpo="{\"path\":\"$DBX_JSON_ESCAPADO\""
  if [[ -n $rev ]]; then
    # RF-49: o `rev` esperado viaja com a escrita. Alteracao remota entre a
    # leitura e a exclusao vira conflito, e nao remocao do que mudou.
    dbx_json_escapar_cadeia "$rev"
    corpo+=",\"parent_rev\":\"$DBX_JSON_ESCAPADO\""
  fi
  corpo+='}'

  _dbx_cmd_escrita_remota 'https://api.dropboxapi.com/2/files/delete_v2' "$corpo" || return $?

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao delete
  dbx_output_campo caminho "$remoto"
  if [[ $DBX_CMD_SIMULADO == 'sim' ]]; then
    dbx_output_campo simulado sim
  else
    _dbx_cmd_metadado_em metadata
    _dbx_cmd_encerrar_consulta
  fi
  dbx_output_render
  return 0
}
