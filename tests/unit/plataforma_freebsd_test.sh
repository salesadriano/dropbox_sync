#!/usr/bin/env bash
# Testes de /proc por capacidade (RF-171(b); TC-FBSD-21). O TC-FBSD-20 (/dev/fd)
# esta em tests/unit/descritor_portavel_test.sh.
#
# shellcheck disable=SC2016
# Justificativa: os programas filhos sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"

# Os casos de `dbx_preflight_descritores` (TC-FBSD-20, versao de preflight)
# foram removidos: o produto nao depende mais de /dev/fd/<n> e o preflight nao
# o exige. A prova agora e tests/unit/descritor_portavel_test.sh.

# ---------------------------------------------------------------------------
# TC-FBSD-21: host_id sem /proc (DIV-353, opcao A)
# ---------------------------------------------------------------------------

# Roda a definicao real de dbx_state_host_id com /proc apontando para um lugar
# que nao existe, que e o que o FreeBSD sem procfs oferece.
_host_id_sem_proc() {
  env -i PATH="$PATH" HOSTNAME=maquina "$BASH" -c '
    DBX_STATE_HOST_ID=""
    eval "$(sed -n "/^dbx_state_host_id() {/,/^}/p" "$1/lib/state.sh" | sed "s|/proc/|/sem-proc/|g")"
    dbx_state_host_id
    printf "%s|%s|%s|%s" "$DBX_STATE_HOST_ID" "$DBX_STATE_HOST_NOME" "$DBX_STATE_HOST_BOOT" "$DBX_STATE_HOST_NS"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1
}

teste_host_id_sem_proc_publica_boot_e_ns_como_x() {
  assert_igual 'maquina:x:x|maquina|x|x' "$(_host_id_sem_proc)" \
    'RF-171(b): sem /proc o boot e o ns degradam para x, e o host_id segue valido'
}

harness_executar "$@"
