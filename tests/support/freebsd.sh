#!/usr/bin/env bash
# freebsd.sh — poe os dubles de utilitario BSD a frente do PATH (RF-166).
#
# Os dubles ficam em tests/duplos/freebsd/bin e imitam o comportamento do
# FreeBSD onde ele diverge do GNU (chmod, stat e demais). Uso em um teste, que ja roda em
# subshell proprio, entao o PATH alterado nao vaza para outros casos:
#
#   . "$DBX_HARNESS_RAIZ/tests/support/freebsd.sh"
#   dbx_freebsd_ativar
#
# Novos dubles (stat, find, sha256 etc.) so precisam ser colocados no diretorio.

DBX_FREEBSD_DUPLOS=${DBX_HARNESS_RAIZ:?harness nao carregado}/tests/duplos/freebsd/bin

# dbx_freebsd_erros — o que os dubles registraram como erro, mesmo quando o
# produto engoliu o stderr. Vazio significa que nenhuma invocacao falhou.
dbx_freebsd_erros() {
  [[ -n ${DBX_FREEBSD_REGISTRO:-} && -f $DBX_FREEBSD_REGISTRO ]] || return 0
  cat -- "$DBX_FREEBSD_REGISTRO"
}

# dbx_freebsd_real <comando> [args...] — roda o utilitario do sistema, sem os
# dubles, para o teste conferir o resultado com o GNU mesmo com o PATH do BSD
# ativo (o duble de stat rejeita `-c`, que o teste usa para ler o modo).
dbx_freebsd_real() {
  local PATH=${PATH//"$DBX_FREEBSD_DUPLOS:"/}
  hash -r
  "$@"
  local estado=$?
  hash -r
  return "$estado"
}

# dbx_freebsd_ativar — antepoe o diretorio de dubles ao PATH do processo e abre
# o registro de erros dos dubles (DBX_FREEBSD_REGISTRO).
dbx_freebsd_ativar() {
  DBX_FREEBSD_REGISTRO=$(mktemp "${DBX_TESTES_TMP:?}/freebsd-registro.XXXXXX") || return 1
  export DBX_FREEBSD_REGISTRO
  case ":$PATH:" in
    ":$DBX_FREEBSD_DUPLOS:"*) ;;
    *) PATH="$DBX_FREEBSD_DUPLOS:$PATH" ;;
  esac
  export PATH
}
