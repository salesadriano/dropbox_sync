#!/usr/bin/env bash
# lib/debug.sh — ponto UNICO de emissao das linhas `debug:` (RF-156, F-51).
#
# Camada: adaptadores. Depende de lib/errors.sh (redacao). Nao conhece comando
# nem rede: lib/http e os comandos chamam `dbx_debug_linha`.
#
# Formato: `debug: <categoria> chave=valor chave=valor`, uma linha por evento,
# so em stderr, so com `DBX_CLI_DEBUG=sim`. Valor passa por `dbx_errors_redigir`,
# caractere de controle vira `?` e valor vazio ou com espaco, aspas ou barra
# invertida sai entre aspas duplas com `"` e `\` escapados (DIV-336).
#
# Argumento sem `=` entra como esta, apos o mesmo saneamento: serve ao metodo e
# ao endpoint da categoria `http`, que sao posicionais.

[[ -n ${DBX_DEBUG_CARREGADO:-} ]] && return 0
DBX_DEBUG_CARREGADO=1

_dbx_debug_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_debug_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_debug_diretorio=.
_dbx_debug_diretorio=$(cd -P -- "$_dbx_debug_diretorio" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_debug_diretorio/errors.sh"
unset _dbx_debug_diretorio

# _dbx_debug_valor <valor> — publica em _DBX_DEBUG_VALOR o valor saneado.
_dbx_debug_valor() {
  local valor=$1
  # Controle vira `?` ANTES da redacao: `dbx_errors_redigir` recusa inteiro o texto
  # com caractere de controle (fail-safe), e o nome do arquivo sumiria da linha.
  valor=${valor//[[:cntrl:]]/\?}
  dbx_errors_redigir "$valor" >/dev/null
  valor=$DBX_ERRORS_REDIGIDO
  if [[ -z $valor || $valor == *[[:space:]\"\\]* ]]; then
    valor=${valor//\\/\\\\}
    valor=${valor//\"/\\\"}
    valor=\"$valor\"
  fi
  _DBX_DEBUG_VALOR=$valor
}

# dbx_debug_linha <categoria> [chave=valor|posicional]... — escreve a linha em
# stderr quando `--debug` esta ativo; sempre devolve 0 (RF-163(d): falha de
# escrita nunca muda o resultado do comando).
dbx_debug_linha() {
  [[ ${DBX_CLI_DEBUG:-nao} == 'sim' ]] || return 0
  local linha="debug: ${1-}" argumento
  shift
  for argumento in "$@"; do
    if [[ $argumento == *=* ]]; then
      _dbx_debug_valor "${argumento#*=}"
      linha+=" ${argumento%%=*}=$_DBX_DEBUG_VALOR"
    else
      _dbx_debug_valor "$argumento"
      linha+=" $_DBX_DEBUG_VALOR"
    fi
  done
  # `>&2` antes de `2>/dev/null`: a linha vai ao stderr do chamador e so a queixa
  # do proprio printf (stderr fechado ou cheio) e descartada.
  printf '%s\n' "$linha" >&2 2>/dev/null || true
  return 0
}
