#!/usr/bin/env bash
# Identidade forte do arquivo sob o GNU coreutils (RSK-43).
#
# `lib/hash` le a identidade com `stat -c '%Y|%y|%z|%d|%i|%s'`, e ate aqui so foi
# validada no uutils coreutils (o `stat` desta maquina). O GNU coreutils e o que
# a maioria dos Linux entrega, e esta maquina o tem como `/usr/bin/gnustat`.
# Estes casos colocam no PATH um `stat` de duplo que faz `exec` no `gnustat` e
# repetem as propriedades que o cache do upload exige: formato identico ao do
# `stat` de referencia, deteccao de `mtime` restaurado, de troca de inode e a
# regra de 2 s. Sem `gnustat`, cada caso e pulado com motivo explicito.
#
# shellcheck disable=SC2034
# Justificativa: canais publicos de lib/hash e lib/state lidos pelos casos.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/config.sh"
. "$DBX_HARNESS_RAIZ/lib/state.sh"

readonly GNUSTAT=/usr/bin/gnustat

# _com_stat_gnu — poe no PATH um `stat` que executa o GNU coreutils; publica
# REFERENCIA, o `stat` que o PATH resolvia ANTES (o de referencia da maquina), e
# AREA. Pula o caso se o GNU coreutils nao estiver instalado.
_com_stat_gnu() {
  [[ -x $GNUSTAT ]] || pular "GNU coreutils ausente: $GNUSTAT nao existe nesta maquina"
  REFERENCIA=$(command -v stat) || pular 'sem stat de referencia no PATH'
  AREA=$(mktemp -d "$DBX_TESTES_TMP/gnustat.XXXXXX")
  mkdir -p "$AREA/bin"
  printf '#!/bin/sh\necho x >>%s/chamadas\nexec %s "$@"\n' "$AREA" "$GNUSTAT" >"$AREA/bin/stat"
  chmod +x "$AREA/bin/stat"
  PATH="$AREA/bin:$PATH"
  [[ $(command -v stat) == "$AREA/bin/stat" ]] || _harness_falhar 'o duplo nao assumiu o stat'
}

_ler_identidade() { # <arquivo> — IDENTIDADE e TAMANHO da leitura de lib/hash
  dbx_hash_identidade "$1" || _harness_falhar "sem identidade para $1"
  IDENTIDADE=$DBX_HASH_IDENTIDADE
  TAMANHO=$DBX_HASH_TAMANHO_ARQUIVO
}

teste_gnu_formato_da_identidade_e_identico_ao_do_stat_de_referencia() {
  _com_stat_gnu
  printf 'abc' >"$AREA/f"
  touch -d '@1700000000.123456789' "$AREA/f"
  local formato=$DBX_HASH_FORMATO_IDENTIDADE esperado fuso
  _ler_identidade "$AREA/f"
  esperado=$("$REFERENCIA" -c "$formato" -- "$AREA/f")
  assert_igual "$esperado" "$IDENTIDADE" 'GNU e referencia: mesma identidade campo a campo'
  assert_contem '|2023-11-14 ' "$IDENTIDADE" '%y em data e hora legiveis'
  assert_contem '.123456789 ' "$IDENTIDADE" 'nanossegundos exatos, sem arredondamento'
  assert_igual 3 "$TAMANHO" 'tamanho publicado na mesma leitura'
  [[ -s $AREA/chamadas ]] || _harness_falhar 'lib/hash nao passou pelo duplo do GNU'
  assert_igual 6 "$(awk -F'|' '{print NF}' <<<"$IDENTIDADE")" 'seis campos separados por barra'
  for fuso in UTC America/Sao_Paulo Asia/Kolkata Pacific/Chatham; do
    TZ=$fuso _ler_identidade "$AREA/f"
    esperado=$(TZ=$fuso "$REFERENCIA" -c "$formato" -- "$AREA/f")
    assert_igual "$esperado" "$IDENTIDADE" "fuso $fuso: GNU e referencia coincidem"
  done
}

teste_gnu_identidade_e_aceita_pela_validacao_do_cache() {
  _com_stat_gnu
  local fuso
  printf 'abc' >"$AREA/f"
  touch -d '@1700000000.000000001' "$AREA/f"
  for fuso in UTC America/Sao_Paulo Asia/Kolkata Pacific/Chatham; do
    TZ=$fuso _ler_identidade "$AREA/f"
    _dbx_state_identidade_valida "$IDENTIDADE" ||
      _harness_falhar "fuso $fuso: a validacao do cache recusou: $IDENTIDADE"
  done
}

teste_gnu_mtime_restaurado_nao_esconde_a_reescrita() {
  # Mesmo tamanho, `mtime` devolvido por `touch -d`: so o `ctime` denuncia.
  _com_stat_gnu
  local antes depois
  printf 'aaaa' >"$AREA/f"
  touch -d '@1700000000.500000000' "$AREA/f"
  _ler_identidade "$AREA/f"
  antes=$IDENTIDADE
  # Espera por condicao: o relogio grosso do nucleo pode dar o mesmo `ctime`.
  local sonda=$AREA/sonda ref
  ref=$(stat -c '%z' -- "$AREA/f")
  : >"$sonda"
  while [[ $(stat -c '%z' -- "$sonda") == "$ref" ]]; do chmod 600 "$sonda"; done
  printf 'bbbb' >"$AREA/f"
  touch -d '@1700000000.500000000' "$AREA/f"
  _ler_identidade "$AREA/f"
  depois=$IDENTIDADE
  assert_igual "${antes%%|*}" "${depois%%|*}" 'o mtime em segundos foi restaurado'
  assert_diferente "$antes" "$depois" 'GNU: a identidade muda mesmo com mtime e tamanho iguais'
}

teste_gnu_troca_de_inode_muda_a_identidade() {
  # Outro arquivo, mesmo tamanho e mesmo `mtime`, posto no lugar por `mv`.
  _com_stat_gnu
  local antes depois
  printf 'aaaa' >"$AREA/f"
  touch -d '@1700000000.250000000' "$AREA/f"
  _ler_identidade "$AREA/f"
  antes=$IDENTIDADE
  printf 'bbbb' >"$AREA/g"
  touch -d '@1700000000.250000000' "$AREA/g"
  mv -f -- "$AREA/g" "$AREA/f"
  _ler_identidade "$AREA/f"
  depois=$IDENTIDADE
  assert_igual "${antes%%|*}" "${depois%%|*}" 'mesmo mtime em segundos'
  assert_diferente "$antes" "$depois" 'GNU: troca de inode muda a identidade'
  assert_diferente "$(cut -d'|' -f5 <<<"$antes")" "$(cut -d'|' -f5 <<<"$depois")" 'o campo %i difere'
}

teste_gnu_identidade_inalterada_se_nada_muda() {
  _com_stat_gnu
  printf 'abc' >"$AREA/f"
  touch -d '@1700000000.750000000' "$AREA/f"
  _ler_identidade "$AREA/f"
  local primeira=$IDENTIDADE
  _ler_identidade "$AREA/f"
  assert_igual "$primeira" "$IDENTIDADE" 'duas leituras seguidas coincidem'
}

teste_gnu_regra_de_dois_segundos_do_registro() {
  _com_stat_gnu
  local agora identidade
  printf -v agora '%(%s)T' -1
  printf 'abc' >"$AREA/antigo"
  touch -d "@$((agora - 3))" "$AREA/antigo"
  _ler_identidade "$AREA/antigo"
  identidade=$IDENTIDADE
  dbx_state_registravel "$identidade" "$identidade"
  assert_igual 0 $? 'GNU: mtime com 3 s de idade e registravel'

  printf 'abc' >"$AREA/novo"
  _ler_identidade "$AREA/novo"
  identidade=$IDENTIDADE
  dbx_state_registravel "$identidade" "$identidade"
  assert_igual 1 $? 'GNU: mtime de agora (menos de 2 s) nao e registravel'

  printf 'abc' >"$AREA/exato"
  touch -d "@$((agora - 2))" "$AREA/exato"
  _ler_identidade "$AREA/exato"
  identidade=$IDENTIDADE
  dbx_state_registravel "$identidade" "$identidade"
  assert_igual 0 $? 'GNU: 2 s de idade ja e registravel (limite inclusivo)'

  _ler_identidade "$AREA/antigo"
  local antes=$IDENTIDADE
  printf 'abcd' >"$AREA/antigo"
  touch -d "@$((agora - 3))" "$AREA/antigo"
  _ler_identidade "$AREA/antigo"
  dbx_state_registravel "$antes" "$IDENTIDADE"
  assert_igual 1 $? 'GNU: leituras diferentes antes e depois nao registram'
}

teste_gnu_identidade_de_arquivo_vazio_nao_e_registravel() {
  _com_stat_gnu
  local identidade
  : >"$AREA/vazio"
  touch -d '@1700000000' "$AREA/vazio"
  _ler_identidade "$AREA/vazio"
  identidade=$IDENTIDADE
  assert_igual 0 "$TAMANHO" 'tamanho zero'
  dbx_state_registravel "$identidade" "$identidade"
  assert_igual 1 $? 'GNU: arquivo vazio fica fora (RF-61(e))'
}

harness_executar "$@"
