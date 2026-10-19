#!/usr/bin/env bash
# completar — imprime o autocompletar do bash (RF-68(c), F-19). Alias em
# ingles: `completion`.
#
# Requisito `nenhum`: imprimir um arquivo do proprio pacote nao depende de
# rede, credencial nem utilitario externo, e o operador precisa conseguir ativar
# o autocompletar mesmo num ambiente que o preflight recusaria. A leitura e pelo
# proprio shell (`read -d ''`), e o conteudo sai IDENTICO ao versionado em
# `completions/dbx.bash`.

dbx_cmd_completar_requisitos() { printf 'nenhum'; }

dbx_cmd_completar_executar() {
  # shellcheck source=lib/cmd.sh
  . "$DBX_CLI_RAIZ/lib/cmd.sh"
  local alvo=''
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      *)
        [[ -z $alvo ]] || {
          dbx_cmd_falhar uso_invalido 'informe apenas o shell: dbx completar bash'
          return $?
        }
        alvo=$1
        ;;
    esac
    shift
  done
  [[ $alvo == 'bash' ]] || {
    dbx_cmd_falhar uso_invalido "shell nao suportado: '${alvo}' (use: dbx completar bash)"
    return $?
  }

  local arquivo="$DBX_CLI_RAIZ/completions/dbx.bash" conteudo=''
  [[ -f $arquivo && -r $arquivo ]] || {
    dbx_cmd_falhar configuracao "script de autocompletar ausente da instalacao: $arquivo"
    return $?
  }
  IFS= read -r -d '' conteudo <"$arquivo"
  printf '%s' "$conteudo"
  return 0
}
