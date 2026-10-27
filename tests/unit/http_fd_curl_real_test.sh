#!/usr/bin/env bash
# Testes do destino `fd:<n>` de lib/http.sh com o `curl` REAL (URL file://).
#
# Por que existe: a suite de http usa um duble de `curl` e nao viu o defeito em
# que `--stderr <arquivo>` reabria o stderr do processo e o conteudo baixado ia
# para o arquivo de erros, deixando o `.part` com 0 bytes (FreeBSD e Linux).
# Aqui o cliente e o do sistema, resolvido ANTES de qualquer duble no PATH; sem
# rede (URL file://). Com file:// o cliente nao informa codigo HTTP (000) e a lib
# classifica como rede: nos casos de sucesso asserem-se os BYTES, nao o status.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"

CURL_REAL=$(command -v curl || true)

# _origem — cria a origem (com bytes nao textuais) e publica o caminho em ORIGEM.
_origem() {
  ORIGEM=$DBX_TESTES_TMP/origem.$$
  printf 'linha um\nlinha dois\n\000\377fim sem quebra' >"$ORIGEM"
}

# _receber <destino> [inicio] — chama o caminho de download com o curl real.
_receber() {
  local dir=$DBX_TESTES_TMP/bin.$$
  mkdir -p "$dir"
  ln -sf "$CURL_REAL" "$dir/curl"
  PATH=$dir:$PATH dbx_http_conteudo_receber POST "file://$ORIGEM" tok '{}' "$@"
  ESTADO_RECEBER=$?
}

teste_fd_part_vazio_recebe_os_bytes_da_origem() {
  [[ -n $CURL_REAL ]] || pular 'curl ausente'
  _origem
  local part=$DBX_TESTES_TMP/part.$$ fd
  : >"$part"
  exec {fd}>>"$part"
  _receber "fd:$fd"
  exec {fd}>&-
  cmp -s "$ORIGEM" "$part"
  assert_igual 0 "$?" 'bytes do .part iguais aos da origem'
}

teste_fd_part_com_prefixo_preserva_e_anexa_o_resto() {
  [[ -n $CURL_REAL ]] || pular 'curl ausente'
  _origem
  local part=$DBX_TESTES_TMP/part.$$ fd
  head -c 10 "$ORIGEM" >"$part"
  exec {fd}>>"$part"
  _receber "fd:$fd" 10
  exec {fd}>&-
  cmp -s "$ORIGEM" "$part"
  assert_igual 0 "$?" 'prefixo preservado e resto anexado'
}

teste_fd_url_inexistente_falha_sem_mensagem_no_part() {
  [[ -n $CURL_REAL ]] || pular 'curl ausente'
  local part=$DBX_TESTES_TMP/part.$$ fd
  : >"$part"
  exec {fd}>>"$part"
  ORIGEM=$DBX_TESTES_TMP/nao_existe.$$
  _receber "fd:$fd"
  exec {fd}>&-
  assert_diferente 0 "$ESTADO_RECEBER" 'falha classificada'
  [[ ! -s $part ]]
  assert_igual 0 "$?" 'nenhum byte (nem mensagem do cliente) no .part'
}

teste_saida_padrao_recebe_os_bytes_da_origem() {
  [[ -n $CURL_REAL ]] || pular 'curl ausente'
  _origem
  local saida=$DBX_TESTES_TMP/saida.$$
  _receber - >"$saida"
  cmp -s "$ORIGEM" "$saida"
  assert_igual 0 "$?" 'bytes da saida padrao iguais aos da origem'
}

harness_executar "$@"
