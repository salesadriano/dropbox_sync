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
  # RF-162: a linha `http` do proprio processo alimenta os contadores do resumo.
  if [[ $linha == 'debug: http'* ]]; then
    local _t=1 _e=0 _r=0
    for argumento in "$@"; do
      case $argumento in
        tentativa=[0-9]*) _t=${argumento#*=} ;;
        enviados=[0-9]*) _e=${argumento#*=} ;;
        recebidos=[0-9]*) _r=${argumento#*=} ;;
      esac
    done
    dbx_debug_somar_http "$_t" "$_e" "$_r"
  fi
  if [[ -n ${DBX_DEBUG_DESTINO:-} ]]; then
    # RF-158: auxiliar do sync paralelo grava em arquivo proprio (canal 0700 do
    # item); o principal as descarrega no stderr, na ordem do plano.
    printf '%s\n' "$linha" >>"$DBX_DEBUG_DESTINO" 2>/dev/null || true
    return 0
  fi
  _dbx_debug_escrever "$linha"
  return 0
}

# Descritor com o stderr do operador, aberto por `dbx_debug_canal_abrir`: chamada
# de apoio feita com `2>/dev/null` (ex.: identificacao da conta no sync) nao pode
# esconder a sua linha (RF-157(h)). Vazio = stderr corrente.
_DBX_DEBUG_FD=''

# dbx_debug_canal_abrir — duplica o stderr do operador num descritor proprio.
dbx_debug_canal_abrir() {
  [[ ${DBX_CLI_DEBUG:-nao} == 'sim' && -z $_DBX_DEBUG_FD ]] || return 0
  exec {_DBX_DEBUG_FD}>&2 || _DBX_DEBUG_FD=''
  return 0
}

# _dbx_debug_escrever <linha> — `>&N` antes de `2>/dev/null`: a linha vai ao
# canal e so a queixa do proprio printf (canal fechado ou cheio) e descartada.
_dbx_debug_escrever() {
  if [[ -n $_DBX_DEBUG_FD ]]; then
    printf '%s\n' "$1" 1>&"$_DBX_DEBUG_FD" 2>/dev/null || true
  else
    printf '%s\n' "$1" >&2 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Resumo (RF-162) e linhas dos auxiliares (RF-158)
# ---------------------------------------------------------------------------

# Destino alternativo das linhas (arquivo); vazio = stderr.
DBX_DEBUG_DESTINO=''
# Contadores do processo principal, somados dos auxiliares por descarga.
DBX_DEBUG_CHAMADAS=0
DBX_DEBUG_EXTRAS=0
DBX_DEBUG_ENVIADOS=0
DBX_DEBUG_RECEBIDOS=0
DBX_DEBUG_COMANDO=''
DBX_DEBUG_INICIO_US=0

# dbx_debug_somar_http <tentativa> <enviados> <recebidos>
dbx_debug_somar_http() {
  if ((10#${1:-1} == 1)); then
    DBX_DEBUG_CHAMADAS=$((DBX_DEBUG_CHAMADAS + 1))
  else
    DBX_DEBUG_EXTRAS=$((DBX_DEBUG_EXTRAS + 1))
  fi
  DBX_DEBUG_ENVIADOS=$((DBX_DEBUG_ENVIADOS + 10#${2:-0}))
  DBX_DEBUG_RECEBIDOS=$((DBX_DEBUG_RECEBIDOS + 10#${3:-0}))
  return 0
}

# dbx_debug_descarregar <arquivo> — escreve no stderr as linhas gravadas por um
# auxiliar, soma as `http` aos contadores e remove o arquivo. Sem --debug ou
# sem arquivo, nada.
dbx_debug_descarregar() {
  [[ ${DBX_CLI_DEBUG:-nao} == 'sim' && -s ${1-} ]] || return 0
  local linha tentativa enviados recebidos
  while IFS= read -r linha || [[ -n $linha ]]; do
    _dbx_debug_escrever "$linha"
    if [[ $linha == 'debug: http '* ]]; then
      tentativa=1 enviados=0 recebidos=0
      [[ $linha =~ ' tentativa='([0-9]+) ]] && tentativa=${BASH_REMATCH[1]}
      [[ $linha =~ ' enviados='([0-9]+) ]] && enviados=${BASH_REMATCH[1]}
      [[ $linha =~ ' recebidos='([0-9]+) ]] && recebidos=${BASH_REMATCH[1]}
      dbx_debug_somar_http "$tentativa" "$enviados" "$recebidos"
    fi
  done <"$1"
  rm -f -- "$1" 2>/dev/null || :
  return 0
}

# dbx_debug_resumo_armar <comando> — registra a linha `resumo` para o termino do
# processo (sucesso, falha ou sinal, DIV-341), via acao de lib/tmp.
dbx_debug_resumo_armar() {
  [[ ${DBX_CLI_DEBUG:-nao} == 'sim' ]] || return 0
  declare -F dbx_tmp_acao_registrar >/dev/null || return 0
  DBX_DEBUG_COMANDO=$1
  local t=${EPOCHREALTIME:-}
  if [[ -n $t ]]; then
    t=${t//[.,]/}
    DBX_DEBUG_INICIO_US=$((10#$t))
  else
    DBX_DEBUG_INICIO_US=$((SECONDS * 1000000))
  fi
  # Gancho "antes das acoes": o resumo sai antes das mensagens de interrupcao.
  dbx_tmp_gancho_antes _dbx_debug_resumo_emitir
}

# Canal para o comando publicar dados do resumo sem que a lib o conheca.
DBX_DEBUG_LIMITES_429=0
_DBX_DEBUG_CAMPOS=()

# dbx_debug_resumo_campo <chave> <valor> — campo extra no fim do resumo.
dbx_debug_resumo_campo() {
  _DBX_DEBUG_CAMPOS+=("${1-}=${2-}")
  return 0
}

# dbx_debug_somar_429 <n> — limites 429 contados fora de lib/http (auxiliares).
dbx_debug_somar_429() {
  DBX_DEBUG_LIMITES_429=$((DBX_DEBUG_LIMITES_429 + 10#${1:-0}))
  return 0
}

_dbx_debug_resumo_emitir() {
  [[ -n $DBX_DEBUG_COMANDO ]] || return 0
  local t=${EPOCHREALTIME:-} fim_us ms codigo=${DBX_TMP_SAIDA_CODIGO:-0}
  if [[ -n $t ]]; then
    t=${t//[.,]/}
    fim_us=$((10#$t))
  else
    fim_us=$((SECONDS * 1000000))
  fi
  ms=$(((fim_us - DBX_DEBUG_INICIO_US) / 1000))
  ((ms >= 0)) || ms=0
  local -a extra=()
  extra=(${_DBX_DEBUG_CAMPOS[@]+"${_DBX_DEBUG_CAMPOS[@]}"})
  local comando=$DBX_DEBUG_COMANDO
  DBX_DEBUG_COMANDO=''
  dbx_debug_linha resumo "comando=$comando" "chamadas=$DBX_DEBUG_CHAMADAS" \
    "tentativas_extras=$DBX_DEBUG_EXTRAS" \
    "limites_429=$((${DBX_HTTP_LIMITES_429:-0} + DBX_DEBUG_LIMITES_429))" \
    "enviados=$DBX_DEBUG_ENVIADOS" "recebidos=$DBX_DEBUG_RECEBIDOS" \
    "duracao_ms=$ms" "saida=$codigo" ${extra[@]+"${extra[@]}"}
  return 0
}
