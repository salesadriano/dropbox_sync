#!/usr/bin/env bash
# Testes da poda por teto sem `find -printf` (RF-168; TC-FBSD-03 e 19 parte find).
#
# O find do FreeBSD nao conhece `-printf`. A poda por teto de `retomada-*` e de
# `cursor-*` escolhe o mais antigo pelo teste `-ot` do bash sobre o glob. Em GNU
# o defeito so aparece com o duble de tests/duplos/freebsd/bin/find no PATH, que
# rejeita `-printf` (antes da correcao a poda por teto nunca removia nada).
#
# shellcheck disable=SC2016,SC2034
# Justificativa: as amostras da auditoria sao codigo sem expansao, e os canais
# DBX_STATE_* sao lidos por lib/state, nao por este arquivo.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/tests/support/freebsd.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/path.sh"
. "$DBX_HARNESS_RAIZ/lib/output.sh"
. "$DBX_HARNESS_RAIZ/lib/progress.sh"
. "$DBX_HARNESS_RAIZ/lib/config.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"
. "$DBX_HARNESS_RAIZ/lib/auth.sh"
. "$DBX_HARNESS_RAIZ/lib/state.sh"

_area() {
  mktemp -d "$DBX_TESTES_TMP/poda.XXXXXX"
}

# _popular <diretorio> <prefixo> <quantidade> — cria <quantidade> registros
# `<prefixo>-<32 hex>` com mtime crescente: o de indice 0 e o MAIS ANTIGO.
_popular() {
  local diretorio=$1 prefixo=$2 total=$3 i nome agora
  # Recentes (de 1 a 2 dias): a poda por idade nao pode antecipar a por teto.
  printf -v agora '%(%s)T' -1
  for ((i = 0; i < total; i++)); do
    printf -v nome '%032x' "$i"
    : >"$diretorio/$prefixo-$nome"
    touch -d "@$((agora - 172800 + i))" "$diretorio/$prefixo-$nome"
  done
}

# _contar <diretorio> <prefixo> — quantidade de `<prefixo>-*`.
_contar() {
  local -a achados=("$1"/"$2"-*)
  printf '%s' "${#achados[@]}"
}

# ---------------------------------------------------------------------------
# O duble imita o BSD (sem ele, os demais casos nao provam nada)
# ---------------------------------------------------------------------------

teste_duplo_de_find_rejeita_printf_e_delega_o_resto() {
  local area saida estado
  area=$(_area)
  : >"$area/a"
  dbx_freebsd_ativar
  saida=$(find "$area" -maxdepth 1 -type f -printf '%T@ %p\0' 2>&1)
  estado=$?
  assert_igual 1 "$estado" 'no BSD `-printf` e primario desconhecido'
  assert_contem 'find: -printf: unknown primary or operator' "$saida"
  assert_igual "$area/a" "$(find "$area" -maxdepth 1 -type f -print)" 'o resto e delegado ao find real'
}

# ---------------------------------------------------------------------------
# TC-FBSD-03: teto de retomada-* com o find do BSD
# ---------------------------------------------------------------------------

teste_poda_por_teto_de_retomada_com_find_bsd_mantem_o_teto_e_o_atual() {
  local area excesso=5 total atual nome
  area=$(_area)
  total=$((DBX_STATE_RETOMADA_TETO + excesso))
  _popular "$area" retomada "$total"
  printf -v nome '%032x' 0
  atual="$area/retomada-$nome"
  DBX_STATE_RETOMADA_ARQUIVO=$atual
  dbx_freebsd_ativar
  _dbx_state_retomada_podar "$area"
  assert_igual "$DBX_STATE_RETOMADA_TETO" "$(_contar "$area" retomada)" \
    "RF-168(b): $total registros ficam no teto"
  assert_arquivo_existe "$atual" 'o registro do contexto atual, mesmo o mais antigo, nunca sai'
  printf -v nome '%032x' 1
  assert_arquivo_ausente "$area/retomada-$nome" 'saiu o mais antigo depois do atual'
  printf -v nome '%032x' "$excesso"
  assert_arquivo_ausente "$area/retomada-$nome" 'o quinto removido'
  printf -v nome '%032x' $((excesso + 1))
  assert_arquivo_existe "$area/retomada-$nome" 'o sexto mais antigo fica'
}

teste_poda_por_teto_de_cursor_com_find_bsd_mantem_o_teto_e_o_atual() {
  local area excesso=5 total atual nome
  area=$(_area)
  total=$((DBX_STATE_CURSOR_TETO + excesso))
  _popular "$area" cursor "$total"
  printf -v nome '%032x' 0
  atual="$area/cursor-$nome"
  DBX_STATE_CURSOR_ARQUIVO=$atual
  dbx_freebsd_ativar
  _dbx_state_cursor_podar "$area"
  assert_igual "$DBX_STATE_CURSOR_TETO" "$(_contar "$area" cursor)" \
    "RF-168(a): $total cursores ficam no teto"
  assert_arquivo_existe "$atual" 'o cursor do contexto atual nunca sai'
  printf -v nome '%032x' "$excesso"
  assert_arquivo_ausente "$area/cursor-$nome" 'o quinto mais antigo removido'
  printf -v nome '%032x' $((excesso + 1))
  assert_arquivo_existe "$area/cursor-$nome" 'o sexto mais antigo fica'
}

teste_poda_nao_toca_outros_prefixos_nem_abaixo_do_teto() {
  local area
  area=$(_area)
  _popular "$area" retomada 3
  _popular "$area" memoria 3
  DBX_STATE_RETOMADA_ARQUIVO="$area/retomada-nenhum"
  dbx_freebsd_ativar
  _dbx_state_retomada_podar "$area"
  assert_igual 3 "$(_contar "$area" retomada)" 'abaixo do teto nada sai'
  assert_igual 3 "$(_contar "$area" memoria)" 'memoria-* nunca entra na poda'
}

# ---------------------------------------------------------------------------
# TC-FBSD-19, parte find: auditoria estatica
# ---------------------------------------------------------------------------

# _printf_de_find_em <arquivo...> — `-printf` fora de comentario de linha inteira.
_printf_de_find_em() {
  grep -nE -- '(^|[[:space:]])-printf([[:space:]]|$)' "$@" |
    grep -vE '^[^:]*:?[0-9]+:[[:space:]]*#' || true
}

teste_nenhum_find_com_printf_em_codigo_de_runtime() {
  local area mutacao achados arquivo
  area=$(_area)
  printf '%s\n' 'find "$d" -type f -printf "%T@ %p\0"' >"$area/direto.sh"
  printf '%s\n' 'done < <(find "$d" -maxdepth 1 -name x -printf "%p")' >"$area/processo.sh"
  for mutacao in direto processo; do
    [[ -n $(_printf_de_find_em "$area/$mutacao.sh") ]] ||
      _harness_falhar "a auditoria nao acusou a forma '$mutacao'"
  done
  printf '%s\n' '  # find -printf so existe no GNU' 'x=$(find "$d" -print)' >"$area/limpo.sh"
  assert_igual '' "$(_printf_de_find_em "$area/limpo.sh")" 'comentario e find sem -printf nao sao acusados'
  achados=''
  for arquivo in "$DBX_HARNESS_RAIZ"/lib/*.sh "$DBX_HARNESS_RAIZ"/commands/*.sh; do
    achados+=$(_printf_de_find_em "$arquivo")
  done
  assert_igual '' "$achados" "-printf em codigo de runtime (so bin/dbx:35 e permitido): $achados"
}

harness_executar "$@"
