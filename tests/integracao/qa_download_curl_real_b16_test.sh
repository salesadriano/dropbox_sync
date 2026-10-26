#!/usr/bin/env bash
# Suite independente do QA, demanda chmod-portavel-bsd (download por descritor).
#
# DEFEITO: no destino `fd:<n>` o curl rodava com `--stderr <arquivo>`, que
# REABRE o stderr do processo; `-o /dev/stderr` virava o arquivo de erros e o
# conteudo nunca chegava ao `.part` (download de 335 MiB parado em 0%). A suite
# existente usa curl duble e nao via.
#
# AQUI: curl REAL (caminho absoluto resolvido antes de qualquer duble no PATH)
# contra servidor HTTP local REAL (python3, porta efemera, Range/206 e 409),
# pelo caminho de lib `dbx_http_conteudo_receber` com destino `fd:<n>` e `-`.
# O host da API e fixo no produto (cmd.sh), por isso a descida a lib.
#
# ORACULOS: `cmp` contra o arquivo de origem gerado pelo proprio teste (python3).
# MUTACAO: o caso `teste_mutacao_*` volta `--stderr` numa copia da lib e exige
# que o download completo REPROVE (se o produto fosse assim, o teste pegaria).
#
# shellcheck disable=SC2016,SC2031,SC2034
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"

CURL_REAL=$(command -v curl || true)
PY=$(command -v python3 || true)
readonly QA_TAMANHO=6291457   # 6 MiB + 1: acima de qualquer limiar de retomada

# _qa_preparar — pula sem curl/python3; cria origem, servidor, driver.
_qa_preparar() {
  [[ -n $CURL_REAL ]] || pular 'curl ausente'
  [[ -n $PY ]] || pular 'python3 ausente'
  QA_DIR=$DBX_TESTES_TMP/b16.$$.$RANDOM
  mkdir -p "$QA_DIR/bin"
  ln -sf "$CURL_REAL" "$QA_DIR/bin/curl"
  ORIGEM=$QA_DIR/origem
  "$PY" -I -c '
import sys
b = bytearray(i * 131 % 251 for i in range(int(sys.argv[2])))
b[10:14] = b"\x00\xff\n\r"
open(sys.argv[1], "wb").write(bytes(b))' "$ORIGEM" "$QA_TAMANHO"
  cat >"$QA_DIR/servidor.py" <<'PYEOF'
import http.server, re, sys
dados = open(sys.argv[1], "rb").read()
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def _resp(self, cod, corpo, extra=()):
        self.send_response(cod)
        for k, v in extra: self.send_header(k, v)
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)
    def do_GET(self):
        if self.path.startswith("/erro"):
            self._resp(409, b'{"error_summary":"path/conflict/file/..","error":{".tag":"path"}}',
                       [("Content-Type", "application/json")])
            return
        r = self.headers.get("Range")
        m = re.match(r"bytes=(\d+)-$", r or "")
        if m:
            i = int(m.group(1))
            self._resp(206, dados[i:], [("Content-Range", "bytes %d-%d/%d" % (i, len(dados) - 1, len(dados)))])
        else:
            self._resp(200, dados)
    do_POST = do_GET
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(sys.argv[2], "w").write(str(s.server_address[1]))
s.serve_forever()
PYEOF
  "$PY" -I "$QA_DIR/servidor.py" "$ORIGEM" "$QA_DIR/porta" >/dev/null 2>&1 &
  QA_SRV=$!
  trap 'kill "$QA_SRV" 2>/dev/null' EXIT
  local n=0
  until [[ -s $QA_DIR/porta ]]; do
    n=$((n + 1))
    [[ $n -le 100 ]] || _harness_falhar 'servidor local nao subiu'
    sleep 0.1
  done
  QA_URL=http://127.0.0.1:$(<"$QA_DIR/porta")
  cat >"$QA_DIR/driver.sh" <<'DREOF'
#!/usr/bin/env bash
# driver.sh <libdir> <url> <fd|saida> <part> [inicio]
set -u
libdir=$1 url=$2 modo=$3 part=$4 inicio=${5:-}
export no_proxy='*' NO_PROXY='*'
. "$libdir/errors.sh"; . "$libdir/json.sh"; . "$libdir/http.sh"
if [[ $modo == fd ]]; then
  exec {fd}>>"$part"
  dbx_http_conteudo_receber GET "$url" tok '{}' "fd:$fd" ${inicio:+"$inicio"}
else
  dbx_http_conteudo_receber GET "$url" tok '{}' - ${inicio:+"$inicio"}
fi
estado=$?
printf 'estado=%s classe=%s codigo=%s\n' "$estado" "${DBX_HTTP_CLASSE:-}" "${DBX_HTTP_CODIGO:-}" >&3
DREOF
}

# _qa_rodar <libdir> <caminho> <modo> <part> [inicio] — stdout do download em
# $QA_SAIDA e resumo em $QA_RESUMO.
_qa_rodar() {
  local libdir=$1 caminho=$2 modo=$3 part=$4 inicio=${5:-}
  QA_SAIDA=$QA_DIR/saida.$RANDOM
  PATH=$QA_DIR/bin:$PATH bash "$QA_DIR/driver.sh" "$libdir" "$QA_URL$caminho" "$modo" "$part" "$inicio" \
    >"$QA_SAIDA" 2>"$QA_DIR/stderr" 3>"$QA_DIR/resumo"
  QA_RESUMO=$(<"$QA_DIR/resumo")
}

teste_fd_download_completo_acima_do_limiar_tem_bytes_identicos() {
  _qa_preparar
  local part=$QA_DIR/p.part
  : >"$part"
  _qa_rodar "$DBX_HARNESS_RAIZ/lib" /arq fd "$part"
  assert_contem 'estado=0' "$QA_RESUMO" 'download concluido'
  cmp -s "$ORIGEM" "$part"
  assert_igual 0 "$?" 'bytes do .part identicos aos da origem'
}

teste_fd_retomada_com_range_206_anexa_e_confere() {
  _qa_preparar
  local part=$QA_DIR/p.part
  head -c 2097152 "$ORIGEM" >"$part"
  _qa_rodar "$DBX_HARNESS_RAIZ/lib" /arq fd "$part" 2097152
  assert_contem 'estado=0' "$QA_RESUMO" 'retomada concluida'
  cmp -s "$ORIGEM" "$part"
  assert_igual 0 "$?" 'prefixo preservado e resto anexado, final identico'
}

teste_saida_padrao_em_arquivo_tem_bytes_identicos() {
  _qa_preparar
  _qa_rodar "$DBX_HARNESS_RAIZ/lib" /arq saida /dev/null
  assert_contem 'estado=0' "$QA_RESUMO" 'download concluido'
  cmp -s "$ORIGEM" "$QA_SAIDA"
  assert_igual 0 "$?" 'saida padrao em arquivo identica a origem'
}

teste_saida_padrao_em_cano_tem_bytes_identicos() {
  _qa_preparar
  local copia=$QA_DIR/cano.out
  PATH=$QA_DIR/bin:$PATH bash "$QA_DIR/driver.sh" "$DBX_HARNESS_RAIZ/lib" "$QA_URL/arq" saida /dev/null \
    2>/dev/null 3>"$QA_DIR/resumo" | cat >"$copia"
  cmp -s "$ORIGEM" "$copia"
  assert_igual 0 "$?" 'saida padrao em cano identica a origem'
}

teste_fd_resposta_409_nao_grava_corpo_nem_mensagem_no_part() {
  _qa_preparar
  local part=$QA_DIR/p.part
  : >"$part"
  _qa_rodar "$DBX_HARNESS_RAIZ/lib" /erro fd "$part"
  assert_nao_contem 'estado=0' "$QA_RESUMO" 'falha classificada'
  assert_contem 'codigo=409' "$QA_RESUMO" 'status 409 reconhecido'
  [[ ! -s $part ]]
  assert_igual 0 "$?" 'nenhum byte (corpo de erro ou mensagem do cliente) no .part'
  [[ ! -s $QA_SAIDA ]]
  assert_igual 0 "$?" 'nada vazou para a saida padrao'
  printf '# resumo: %s\n' "$QA_RESUMO" >&2
}

teste_saida_padrao_resposta_409_nao_emite_corpo_de_erro() {
  _qa_preparar
  _qa_rodar "$DBX_HARNESS_RAIZ/lib" /erro saida /dev/null
  assert_nao_contem 'estado=0' "$QA_RESUMO" 'falha classificada'
  [[ ! -s $QA_SAIDA ]]
  assert_igual 0 "$?" 'saida padrao sem byte de corpo de erro'
}

teste_mutacao_stderr_arquivo_reprova_o_download_completo() {
  _qa_preparar
  local copia=$QA_DIR/mutante
  mkdir -p "$copia"
  cp -R "$DBX_HARNESS_RAIZ/lib/." "$copia/"
  cp "$copia/http.sh" "$copia/http.sh.orig"
  sed -e 's|--no-show-error --fail|--stderr "$area/erro_cliente" --fail|' "$copia/http.sh.orig" >"$copia/http.sh"
  cmp -s "$copia/http.sh" "$copia/http.sh.orig" && _harness_falhar 'a mutacao nao alterou o produto'
  rm -f "$copia/http.sh.orig"
  local part=$QA_DIR/p.part
  : >"$part"
  _qa_rodar "$copia" /arq fd "$part"
  # o oraculo do caso (1), aplicado ao mutante, DEVE reprovar
  if cmp -s "$ORIGEM" "$part"; then
    _harness_falhar 'mutante sobreviveu: o oraculo do download completo nao detecta --stderr'
  fi
  printf '# mutante morto: .part=%s bytes de %s\n' "$(wc -c <"$part")" "$QA_TAMANHO" >&2
}

harness_executar "$@"
