#!/usr/bin/env bash
# TC-DIA-17, TC-DIA-18 (RF-91): os escopos opcionais `sharing.write` e
# `sharing.read` aparecem na PROPRIA linha `escopos` do `dbx diagnostico`, sem
# checagem nova e sem mudar o resultado da linha nem o codigo de saida.
#
# Arquivo proprio para nao reescrever o `diagnostico_test` aprovado; o cenario
# e o mesmo (credencial com sentinelas, duplo de `curl` com o `scope` da
# renovacao lido de arquivo).
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly ESCOPOS='account_info.read files.metadata.read files.content.read files.content.write'

BASH_ABSOLUTO=$(command -v bash)
readonly BASH_ABSOLUTO

_cenario() { # <escopos_extras>
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/diag_comp.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/tmp"
  chmod 700 "$base/config/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '{"access_token":"sl.t","expires_in":14400,"scope":"%s%s"}' "$ESCOPOS" "${1:+ $1}" >"$base/token"
  cat >"$base/bin/curl" <<FIM
#!$BASH_ABSOLUTO
base=$base
FIM
  cat >>"$base/bin/curl" <<'FIM'
read -r -d '' _conf
saida=""; escrever=""; anterior=""; url=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
case $url in
  *oauth2/token*) corpo=$(<"$base/token") ;;
  *check/user*) corpo='{"result":"dbx"}' ;;
  *get_space_usage*) corpo='{"used":100,"allocation":{".tag":"individual","allocated":1000}}' ;;
  *) corpo='{}' ;;
esac
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '200'
exit 0
FIM
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_rodar() {
  local base=$1
  shift
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 \
    "$BASH_ABSOLUTO" "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  DBX_SAIDA=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  return 0
}

_linhas_de() { # <id> — as linhas da checagem
  local linha saida=''
  while IFS= read -r linha; do
    [[ $linha == "$1="* ]] && saida+="$linha"$'\n'
  done <<<"$DBX_SAIDA"
  printf '%s' "${saida%$'\n'}"
}

_contagem_de_linhas() { local n=0 linha; while IFS= read -r linha; do n=$((n + 1)); done <<<"$DBX_SAIDA"; printf '%s' "$n"; }

teste_dia17_opcionais_de_compartilhamento_concedidos_na_mesma_linha() {
  local base linhas_sem estado_sem
  base=$(_cenario)
  _rodar "$base" diagnostico
  linhas_sem=$(_contagem_de_linhas)
  estado_sem=$DBX_ESTADO
  base=$(_cenario 'sharing.write sharing.read')
  _rodar "$base" diagnostico
  assert_contem 'escopos=ok' "$(_linhas_de escopos)" 'continua ok'
  assert_contem 'opcionais sharing.write e sharing.read concedidos (dbx compartilhar habilitado)' \
    "$(_linhas_de escopos)" 'na propria linha'
  assert_igual "$linhas_sem" "$(_contagem_de_linhas)" 'mesmo numero de linhas'
  assert_igual "$estado_sem" "$DBX_ESTADO" 'mesmo codigo'
}

teste_dia18_opcional_ausente_cita_modos_afetados_e_remedio_sem_mudar_resultado() {
  local base estado_completo
  base=$(_cenario 'sharing.write sharing.read')
  _rodar "$base" diagnostico
  estado_completo=$DBX_ESTADO
  base=$(_cenario 'sharing.write')
  _rodar "$base" diagnostico
  assert_contem 'escopos=ok' "$(_linhas_de escopos)" 'ausente nao reprova'
  assert_contem 'opcional sharing.read ausente: dbx compartilhar --listar, reuso de link existente e --revogar indisponivel' \
    "$(_linhas_de escopos)" 'modos afetados sem sharing.read'
  assert_contem 'dbx unlink' "$(_linhas_de escopos)" 'remedio'
  assert_igual "$estado_completo" "$DBX_ESTADO" 'codigo inalterado'
  base=$(_cenario 'sharing.read')
  _rodar "$base" diagnostico
  assert_contem 'opcional sharing.write ausente: dbx compartilhar criar, modificar e --revogar indisponivel' \
    "$(_linhas_de escopos)" 'modos afetados sem sharing.write'
  assert_nao_contem 'escopos=aviso' "$DBX_SAIDA" 'nao vira aviso'
  assert_nao_contem 'escopos=falha' "$DBX_SAIDA" 'nem falha'
}

harness_executar "$@"
