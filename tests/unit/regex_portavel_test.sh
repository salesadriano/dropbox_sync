#!/usr/bin/env bash
# Portabilidade das expressoes regulares (RF-166, TC-FBSD-19 parte regex).
#
# O `[[ =~ ]]` do bash usa o regcomp da libc. No FreeBSD RE_DUP_MAX e 255: `{n,m}`
# com n ou m acima disso e regex invalida, o teste falha e o registro de retomada
# nunca era gravado. No glibc o limite e 32767, e por isso a suite nao via.
# O limite de comprimento fica em `${#valor} -le N` no ponto de uso.
#
# shellcheck disable=SC2034
# Justificativa: canais de lib/state ajustados pelos casos.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/state.sh"

_rep() {
  local n=$1 c=${2:-a} s
  printf -v s '%*s' "$n" ''
  printf '%s' "${s// /$c}"
}

teste_nenhuma_repeticao_de_regex_passa_de_255() {
  local achados
  achados=$(cd "$DBX_HARNESS_RAIZ" && grep -rnE '\{[0-9]*,?[0-9]*\}' lib commands bin/dbx install.sh uninstall.sh |
    awk '{ l=$0; while (match(l, /\{[0-9]+(,[0-9]*)?\}|\{,[0-9]+\}/)) {
             t=substr(l, RSTART+1, RLENGTH-2); n=split(t, p, ",")
             for (i=1; i<=n; i++) if (p[i]+0 > 255) { print $0; break }
             l=substr(l, RSTART+RLENGTH) } }')
  assert_igual '' "$achados" "repeticao acima de RE_DUP_MAX 255 do FreeBSD: $achados"
}

teste_session_id_do_registro_de_retomada_aceita_256_e_recusa_257_e_vazio() {
  local cred='cred-0123456789abcdef0123456789abcdef' h
  h=$(_rep 64 a)
  _formato() {
    _dbx_state_retomada_formato "$DBX_STATE_RETOMADA_MAGIA" 1 upload "$cred" perfil /a "$1" 0 0 - 10 '1|2|3|4|5|6' 7 "$h" x
  }
  _formato "$(_rep 256)"
  assert_igual 0 "$?" 'session_id com 256 caracteres e aceito'
  _formato "$(_rep 257)"
  assert_igual 1 "$?" 'session_id com 257 caracteres e recusado'
  _formato ''
  assert_igual 1 "$?" 'session_id vazio e recusado'
}

teste_cursor_e_assinatura_do_cabecalho_respeitam_8192_e_256() {
  local cred='cred-0123456789abcdef0123456789abcdef'
  _cab() {
    _dbx_state_cursor_cabecalho_formato "$DBX_STATE_CURSOR_MAGIA" "$DBX_STATE_CURSOR_VERSAO" "$cred" dbid:C "$1" /r /l "$2" 1 1 1 1
  }
  _cab "$(_rep 256)" "$(_rep 8192)"
  assert_igual 0 "$?" 'assinatura 256 e cursor 8192 sao aceitos'
  _cab "$(_rep 257)" "$(_rep 8192)"
  assert_igual 1 "$?" 'assinatura 257 e recusada'
  _cab "$(_rep 256)" "$(_rep 8193)"
  assert_igual 1 "$?" 'cursor 8193 e recusado'
  _cab "$(_rep 256)" ''
  assert_igual 1 "$?" 'cursor vazio e recusado'
  _cab '' "$(_rep 8192)"
  assert_igual 1 "$?" 'assinatura vazia e recusada'
}

harness_executar "$@"
