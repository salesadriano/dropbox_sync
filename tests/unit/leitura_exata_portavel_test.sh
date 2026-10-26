#!/usr/bin/env bash
# Leitura em partes sem perda sobre o MESMO descritor (FreeBSD, medido no
# upload de 412689845 bytes em fusefs: 411060301 bytes lidos, arquivo intacto).
#
# O `head -c N` do FreeBSD le por stdio com leitura antecipada e deixa o
# deslocamento do descritor alem de N; a parte seguinte comeca tarde e bytes se
# perdem. O duble tests/duplos/freebsd/bin/head reproduz isso (consome N+4096).
# O GNU `head -c` nunca le alem de N, por isso a suite no Linux nao via o
# defeito. A correcao e `dbx_ler_exato` (lib/atributos.sh), sobre `dd`.
#
# shellcheck disable=SC2094
# Justificativa: a massa e entrada padrao E nome; o componente so a le.
#
# shellcheck disable=SC2016
# Justificativa: o duble de curl e escrito sem expansao.
#
# shellcheck disable=SC2034
# Justificativa: canais de lib/ ajustados pelos casos.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/tests/support/freebsd.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"
. "$DBX_HARNESS_RAIZ/lib/auth.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"
. "$DBX_HARNESS_RAIZ/lib/transfer.sh"

DBX_AUTH_TOKEN='sl.tokenDeTeste'
DBX_AUTH_EXPIRA_EM=$((SECONDS + 3600))
DBX_HTTP_ESPERA_BASE_MS=1

readonly CONFIRMACAO='{"path":"/r/a.bin","mode":"add","autorename":false,"mute":false}'
readonly BLOCO=4194304

preparar_caso() {
  TMPDIR=$(mktemp -d "$DBX_TESTES_TMP/tmpdir.XXXXXX") || return 1
  export TMPDIR
}

# _massa <bytes> — conteudo aleatorio (cada byte importa: perda deve aparecer).
_massa() {
  local caminho
  caminho=$(mktemp "$DBX_TESTES_TMP/massa.XXXXXX")
  dbx_freebsd_real head -c "$1" /dev/urandom >"$caminho"
  printf '%s' "$caminho"
}

# _trecho <arquivo> <deslocamento> <bytes> — referencia independente do produto.
_trecho() {
  dbx_freebsd_real tail -c "+$(($2 + 1))" "$1" | dbx_freebsd_real head -c "$3"
}

# _curl_que_guarda_partes — curl que guarda cada corpo enviado (append e o do
# finish, que leva o resto) em <dir>/parte.N.
_curl_que_guarda_partes() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/sess.XXXXXX")
  {
    printf '#!/usr/bin/env bash\n'
    printf 'dir=%s\n' "$dir"
    cat <<'FIM'
cat >/dev/null
url=''; saida=''; escrever=''; corpoarq=''; ant=''
for a in "$@"; do
  case $ant in -o) saida=$a ;; -w) escrever=$a ;; esac
  case $a in http*) url=$a ;; @*) corpoarq=${a#@} ;; esac
  ant=$a
done
corpo='{}'
case $url in
  *upload_session/start*) corpo='{"session_id":"S-1"}' ;;
  *upload_session/append_v2*)
    n=0
    [[ -r $dir/n ]] && read -r n <"$dir/n"
    n=$((n + 1))
    printf '%s' "$n" >"$dir/n"
    [[ -n $corpoarq ]] && cat "$corpoarq" >"$dir/parte.$n"
    ;;
  *upload_session/finish*)
    n=0
    [[ -r $dir/n ]] && read -r n <"$dir/n"
    [[ -n $corpoarq ]] && cat "$corpoarq" >"$dir/parte.$((n + 1))"
    corpo='{"name":"a.bin","path_display":"/r/a.bin","rev":"016","size":1}'
    ;;
esac
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '200'
exit 0
FIM
  } >"$dir/curl"
  chmod +x "$dir/curl"
  printf '%s' "$dir"
}

teste_duplo_de_head_le_alem_de_n_do_descritor() {
  local massa dir fd
  massa=$(_massa 20000)
  dir=$(mktemp -d "$DBX_TESTES_TMP/duplo.XXXXXX")
  dbx_freebsd_ativar
  exec {fd}<"$massa"
  head -c 1000 <&"$fd" >"$dir/a"
  head -c 1000 <&"$fd" >"$dir/b"
  exec {fd}<&-
  assert_igual 1000 "$(wc -c <"$dir/a")" 'o duble imprime so N'
  _trecho "$massa" 1000 1000 >"$dir/esperada"
  assert_status 1 dbx_freebsd_real cmp -s "$dir/b" "$dir/esperada"
}

teste_ler_exato_nao_passa_de_n_e_continua_do_ponto_certo() {
  local massa dir fd
  massa=$(_massa 200000)
  dir=$(mktemp -d "$DBX_TESTES_TMP/exato.XXXXXX")
  dbx_freebsd_ativar
  exec {fd}<"$massa"
  dbx_ler_exato 70000 "$fd" "$dir/a"
  assert_igual 0 $? 'primeira parte'
  dbx_ler_exato 70000 "$fd" "$dir/b"
  assert_igual 0 $? 'segunda parte'
  dbx_ler_exato 70000 "$fd" "$dir/c"
  assert_igual 0 $? 'terceira parte'
  exec {fd}<&-
  assert_igual 70000 "$(wc -c <"$dir/a")" 'tamanho da primeira'
  assert_igual 60000 "$(wc -c <"$dir/c")" 'a terceira traz so o resto (fim da entrada)'
  _trecho "$massa" 70000 70000 >"$dir/esperada"
  assert_sucesso dbx_freebsd_real cmp -s "$dir/b" "$dir/esperada"
  cat "$dir/a" "$dir/b" "$dir/c" >"$dir/todos"
  assert_sucesso dbx_freebsd_real cmp -s "$dir/todos" "$massa"
}

teste_ler_exato_le_de_cano_com_leituras_curtas() {
  local massa dir i
  massa=$(_massa 300000)
  dir=$(mktemp -d "$DBX_TESTES_TMP/cano.XXXXXX")
  dbx_freebsd_ativar
  # o cano entrega em fatias de 1000 bytes: cada read() devolve pouco.
  dbx_ler_exato 250000 0 "$dir/a" < <(for ((i = 0; i < 300; i++)); do dbx_freebsd_real dd if="$massa" bs=1000 skip="$i" count=1 2>/dev/null; done)
  assert_igual 0 $? 'status'
  assert_igual 250000 "$(wc -c <"$dir/a")" 'bytes lidos'
  _trecho "$massa" 0 250000 >"$dir/esperada"
  assert_sucesso dbx_freebsd_real cmp -s "$dir/a" "$dir/esperada"
}

teste_ler_exato_recusa_uso_invalido() {
  dbx_ler_exato abc 0 /dev/null
  assert_igual 2 $? 'bytes nao numerico'
}

teste_content_hash_de_arquivo_maior_que_um_bloco_nao_depende_do_head() {
  local massa esperado obtido
  massa=$(_massa $((2 * BLOCO + 12345)))
  esperado=$(dbx_hash_conteudo_arquivo "$massa")
  assert_igual 0 $? 'referencia calculada sem o duble'
  dbx_freebsd_ativar
  obtido=$(dbx_hash_conteudo_arquivo "$massa")
  assert_igual 0 $? 'com o head do FreeBSD'
  assert_igual "$esperado" "$obtido" 'content_hash igual ao da referencia'
}

teste_upload_por_sessao_le_todos_os_bytes_em_partes_exatas() {
  local massa dir i
  massa=$(_massa $((2 * BLOCO + 12345)))
  dir=$(_curl_que_guarda_partes)
  dbx_freebsd_ativar
  PATH="$dir:$PATH" dbx_transfer_sessao "$CONFIRMACAO" "$massa" <"$massa"
  assert_igual 0 $? "a sessao conclui; motivo: ${DBX_TRANSFER_MOTIVO:-}"
  assert_igual $((2 * BLOCO + 12345)) "$DBX_TRANSFER_BYTES" 'total lido igual ao tamanho do arquivo'
  _trecho "$massa" "$BLOCO" "$BLOCO" >"$dir/esperada"
  assert_sucesso dbx_freebsd_real cmp -s "$dir/parte.2" "$dir/esperada"
  : >"$dir/todas"
  for i in 1 2 3; do cat "$dir/parte.$i" >>"$dir/todas"; done
  assert_sucesso dbx_freebsd_real cmp -s "$dir/todas" "$massa"
}

teste_reposicionamento_da_retomada_posiciona_no_deslocamento_exato() {
  local massa dir bloco restante
  massa=$(_massa $((2 * BLOCO + 12345)))
  dir=$(mktemp -d "$DBX_TESTES_TMP/repos.XXXXXX")
  dbx_freebsd_ativar
  _DBX_TRANSFER_ORIGEM=$massa
  _DBX_TRANSFER_FONTE=0
  bloco="$dir/bloco"
  restante=$((BLOCO + 1000))
  _dbx_transfer_reposicionar "$bloco" "$restante"
  assert_igual 0 $? "reposicionou; motivo: ${DBX_TRANSFER_MOTIVO:-}"
  # O descritor novo esta no byte `restante`: a proxima leitura tem de ser dali.
  dbx_freebsd_real dd bs=5000 count=1 <&"$_DBX_TRANSFER_FONTE" >"$dir/depois" 2>/dev/null
  _trecho "$massa" "$restante" 5000 >"$dir/esperada"
  assert_sucesso dbx_freebsd_real cmp -s "$dir/depois" "$dir/esperada"
}

harness_executar "$@"
