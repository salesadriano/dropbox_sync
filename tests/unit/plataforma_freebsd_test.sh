#!/usr/bin/env bash
# Testes de /dev/fd e /proc por capacidade (RF-171; TC-FBSD-20 e TC-FBSD-21).
#
# O FreeBSD so tem /dev/fd/0..2 sem `fdescfs` montado. O produto reabre
# descritores por /dev/fd/<n> (RNF-30), entao o preflight verifica a capacidade:
# abre um descritor proprio e testa o caminho. Para provar a recusa no Linux, a
# verificacao recebe o diretorio (padrao /dev/fd) e o teste aponta um vazio.
#
# shellcheck disable=SC2016
# Justificativa: os programas filhos sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"

readonly INSTRUCAO_MONTAGEM='mount -t fdescfs fdesc /dev/fd'
readonly INSTRUCAO_FSTAB='fdesc /dev/fd fdescfs rw 0 0'

# _descritores [diretorio] — "<status>|<detalhe>" da verificacao de /dev/fd.
_descritores() {
  env -i PATH="$PATH" "$BASH" -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    if [[ $# -ge 2 ]]; then dbx_preflight_descritores "$2"; else dbx_preflight_descritores; fi
    estado=$?
    printf "%s|%s" "$estado" "$DBX_PREFLIGHT_DETALHE"
  ' _ "$DBX_HARNESS_RAIZ" "$@" 2>&1
}

teste_com_dev_fd_utilizavel_o_preflight_de_descritores_passa() {
  assert_igual '0|' "$(_descritores)" 'TC-FBSD-20: /dev/fd/<n> acessivel passa'
}

teste_sem_dev_fd_utilizavel_recusa_com_3_e_a_instrucao_do_fdescfs() {
  local vazio saida
  vazio=$(mktemp -d "$DBX_TESTES_TMP/devfd.XXXXXX")
  saida=$(_descritores "$vazio")
  assert_igual 3 "${saida%%|*}" 'TC-FBSD-20: codigo de configuracao'
  assert_contem "$INSTRUCAO_MONTAGEM" "$saida" 'a recusa traz o comando de montagem do fdescfs'
  assert_contem "$INSTRUCAO_FSTAB" "$saida" 'a recusa traz a linha do /etc/fstab'
}

teste_diretorio_de_descritores_inexistente_tambem_recusa_com_3() {
  local saida
  saida=$(_descritores "$DBX_TESTES_TMP/nao-existe-devfd")
  assert_igual 3 "${saida%%|*}" 'sem o diretorio nao ha descritor utilizavel'
}

teste_a_verificacao_de_descritores_roda_no_nivel_ambiente_do_preflight() {
  local saida
  saida=$(env -i PATH="$PATH" HOME="$DBX_TESTES_TMP" "$BASH" -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_descritores() { DBX_PREFLIGHT_MOTIVO=descritores; return 3; }
    dbx_preflight_verificar ambiente
    printf "%s" "$?"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_igual 3 "$saida" 'dbx_preflight_verificar ambiente propaga a recusa de /dev/fd'
}

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
