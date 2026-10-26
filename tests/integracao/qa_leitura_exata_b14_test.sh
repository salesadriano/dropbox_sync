#!/usr/bin/env bash
# Suite independente do QA, demanda chmod-portavel-bsd (RF-173, TC-FBSD-25..27).
#
# DEFEITO: o `head -c N` do FreeBSD le alem de N do descritor; leituras em partes
# do MESMO descritor perdiam bytes (upload de 412689845 bytes leu 411060301;
# content_hash local errado acima de 4 MiB). Com o duble `head` do FreeBSD a
# frente do PATH (consome N+4096 e imprime N) o produto precisa se comportar como
# no Linux, pelo executavel real (bin/dbx) sempre que possivel.
#
# ORACULOS INDEPENDENTES: o content_hash de referencia vem de python3 (hashlib),
# nunca do produto; os bytes recebidos pelo servidor duble sao gravados e
# comparados com `cmp` ao arquivo de origem; o servidor duble calcula o resumo
# final a partir do que recebeu.
#
# MUTACAO: DBX_QA_MUTAR=1 troca, numa copia do produto, o `dd` de `dbx_ler_exato`
# por `head -c` e roda TODOS os casos contra ela (esperado: reprovar sob o duble).
# O caso `teste_mutacao_...` prova o mesmo dentro da suite, sem variavel.
#
# shellcheck disable=SC2016,SC2031,SC2034
# Justificativa: os dubles sao escritos sem expansao; subshells dos cenarios.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/tests/support/freebsd.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly QA_PARTE=4194304
readonly QA_MiB=1048576

# _qa_produto — executavel sob teste; com DBX_QA_MUTAR=1, a copia com `head -c`.
_qa_produto() {
  if [[ ${DBX_QA_MUTAR:-} == 1 ]]; then
    _qa_mutante
  else
    printf '%s' "$DBX_HARNESS_RAIZ/bin/dbx"
  fi
}

# _qa_mutante — copia do produto com `dbx_ler_exato` lendo por `head -c`.
_qa_mutante() {
  local copia
  copia=$(mktemp -d "$DBX_TESTES_TMP/mutante.XXXXXX")
  cp -R "$DBX_HARNESS_RAIZ/bin" "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands" "$copia/"
  cp "$copia/lib/atributos.sh" "$copia/lib/atributos.sh.orig"
  sed -e 's|dd bs="\$_falta" count=1 conv=notrunc <&"\$_fd"|head -c "$_falta" <\&"$_fd"|' \
    "$copia/lib/atributos.sh.orig" >"$copia/lib/atributos.sh"
  cmp -s "$copia/lib/atributos.sh" "$copia/lib/atributos.sh.orig" && _harness_falhar 'a mutacao nao alterou dbx_ler_exato'
  rm -f "$copia/lib/atributos.sh.orig"
  printf '%s' "$copia/bin/dbx"
}

# _qa_ref_hash <arquivo> — content_hash da Dropbox calculado fora do produto.
_qa_ref_hash() {
  python3 -I -c '
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as f:
    while True:
        b = f.read(4194304)
        if not b:
            break
        h.update(hashlib.sha256(b).digest())
print(h.hexdigest())' "$1"
}

# _qa_aleatorio <arquivo> <bytes> — conteudo sem padrao (bytes trocados mudam o resumo).
_qa_aleatorio() {
  dd if=/dev/urandom of="$1" bs=65536 count=$(($2 / 65536)) status=none
  dd if=/dev/urandom bs=1 count=$(($2 % 65536)) status=none >>"$1"
}

# ---------------------------------------------------------------------------
# content_hash local (TC-FBSD-25): `dbx verificar` compara o resumo LOCAL com o
# content_hash do remoto; a listagem remota traz o de referencia.
# ---------------------------------------------------------------------------

_qa_cenario_verificar() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/qa-b14v.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '#!/usr/bin/env bash\nbase=%q\n' "$base" >"$base/bin/curl"
  cat >>"$base/bin/curl" <<'FIM'
cat >/dev/null 2>&1
saida=''; escrever=''; anterior=''; url=''
for a in "$@"; do
  case $anterior in -o) saida=$a ;; -w) escrever=$a ;; esac
  case $a in http*) url=$a ;; esac
  anterior=$a
done
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *list_folder*) corpo=$(cat "$base/listagem") ;;
  *) corpo='{}' ;;
esac
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '200'
exit 0
FIM
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

# _qa_rodar_verificar <base> <exec> — `verificar --json` sobre local x /r.
_qa_rodar_verificar() {
  local base=$1 exec=$2
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    DBX_FREEBSD_REGISTRO="${DBX_FREEBSD_REGISTRO:-}" \
    DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
    bash "$exec" verificar --enviar --origem "$base/local" --destino /r \
    </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  DBX_SAIDA=''
  DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _qa_verificar_tamanhos <bytes...> — cria um arquivo por tamanho, lista o remoto
# com o resumo de referencia e exige que o produto, sob o duble do FreeBSD, o ache
# igual.
_qa_verificar_tamanhos() {
  local base tamanho i=0 ref entradas='' sep=''
  base=$(_qa_cenario_verificar)
  for tamanho in "$@"; do
    _qa_aleatorio "$base/local/f$i.bin" "$tamanho"
    ref=$(_qa_ref_hash "$base/local/f$i.bin")
    entradas+="$sep{\".tag\":\"file\",\"path_display\":\"/r/f$i.bin\",\"content_hash\":\"$ref\",\"size\":$tamanho,\"rev\":\"0123456789a\"}"
    sep=','
    i=$((i + 1))
  done
  printf '{"entries":[%s],"has_more":false}' "$entradas" >"$base/listagem"
  dbx_freebsd_ativar
  _qa_rodar_verificar "$base" "$(_qa_produto)"
  assert_igual 0 "$DBX_ESTADO" "verificar acha todos os $# arquivos iguais ao resumo de referencia: $DBX_ERRO"
  assert_contem "iguais=$#" "$DBX_SAIDA" "RF-173(a): $* bytes, resumo local igual ao de referencia"
  assert_contem 'diferentes=0' "$DBX_SAIDA" 'nenhum arquivo diverge do resumo de referencia'
  assert_igual '' "$(dbx_freebsd_erros)" 'os dubles nao registraram erro de uso'
}

teste_content_hash_varios_blocos_e_resto_igual_ao_de_referencia() {
  _qa_verificar_tamanhos $((2 * QA_PARTE + 777)) $((QA_PARTE + 1)) $((QA_PARTE - 1))
}

teste_content_hash_tamanho_exato_multiplo_de_4_mib() {
  _qa_verificar_tamanhos "$QA_PARTE" $((2 * QA_PARTE)) $((3 * QA_PARTE))
}

teste_content_hash_arquivo_de_zero_bytes_e_arquivo_pequeno() {
  _qa_verificar_tamanhos 0 1 4095 4096 4097
}

teste_content_hash_arquivo_grande_de_muitos_blocos_com_resto() {
  _qa_verificar_tamanhos $((40 * QA_MiB + 12345))
}

# ---------------------------------------------------------------------------
# Leitura curta: descritor que entrega menos que o pedido por read() (cano).
# ---------------------------------------------------------------------------

# _qa_produtor <total> <fatia> — emite `total` bytes em fatias de `fatia`, com
# pausa entre elas, para que cada read() do consumidor volte curto.
_qa_produtor() {
  local total=$1 fatia=$2 emitido=0 n
  while [[ $emitido -lt $total ]]; do
    n=$fatia
    [[ $((total - emitido)) -lt $n ]] && n=$((total - emitido))
    head -c "$n" /dev/zero | tr '\0' 'x'
    emitido=$((emitido + n))
    sleep 0.01
  done
}

teste_leitura_curta_de_cano_nao_e_tomada_como_fim_e_nao_perde_bytes() {
  local destino="$DBX_TESTES_TMP/curta.out" total=300000 contagem
  . "$DBX_HARNESS_RAIZ/lib/atributos.sh"
  dbx_freebsd_ativar
  exec 6< <(_qa_produtor "$total" 1000)
  # pedido maior que o que um read() entrega: o laco volta ao descritor.
  dbx_ler_exato 100000 6 "$destino" || _harness_falhar 'dbx_ler_exato falhou na parte 1'
  contagem=$(wc -c <"$destino")
  assert_igual 100000 "${contagem//[^0-9]/}" 'parte 1: exatamente o pedido, apesar das leituras curtas'
  # a parte seguinte comeca exatamente em 100000: nada foi consumido a mais.
  dbx_ler_exato 100000 6 "$destino" || _harness_falhar 'dbx_ler_exato falhou na parte 2'
  contagem=$(wc -c <"$destino")
  assert_igual 100000 "${contagem//[^0-9]/}" 'parte 2: exatamente o pedido'
  # o que sobra (100000) vem como leitura curta final, sem erro, e depois so EOF.
  dbx_ler_exato 150000 6 "$destino" || _harness_falhar 'dbx_ler_exato falhou na parte 3'
  contagem=$(wc -c <"$destino")
  assert_igual 100000 "${contagem//[^0-9]/}" 'parte 3: pedido de 150000 devolve os 100000 que restavam (fim da entrada)'
  dbx_ler_exato 10 6 "$destino" || _harness_falhar 'dbx_ler_exato falhou no EOF'
  contagem=$(wc -c <"$destino")
  assert_igual 0 "${contagem//[^0-9]/}" 'depois do fim: zero bytes, status 0'
  exec 6<&-
}

teste_content_hash_de_fluxo_lento_igual_ao_de_referencia_sob_o_duble() {
  local arquivo="$DBX_TESTES_TMP/lento.bin" ref obtido
  . "$DBX_HARNESS_RAIZ/lib/hash.sh"
  _qa_aleatorio "$arquivo" $((2 * QA_PARTE + 4321))
  ref=$(_qa_ref_hash "$arquivo")
  dbx_freebsd_ativar
  # cano: cada read() entrega no maximo o que o `cat` escreveu por vez (64 KiB).
  obtido=$(cat "$arquivo" | dbx_hash_conteudo_fluxo)
  assert_igual "$ref" "$obtido" 'resumo de um fluxo por cano (leituras curtas) igual ao de referencia'
}

# ---------------------------------------------------------------------------
# Upload por sessao (TC-FBSD-26) e retomada (TC-FBSD-27): servidor duble que
# GRAVA os bytes de cada parte (`sess/<id>/bytes`) para o `cmp` final.
# ---------------------------------------------------------------------------

# _qa_origem <arquivo> <bytes> — esparsa, com marcas distintas no INICIO, no MEIO
# e no FIM de cada bloco de 4 MiB: bytes perdidos ou deslocados mudam o `cmp`.
_qa_origem() {
  local arquivo=$1 tamanho=$2 i pos
  [[ -e $arquivo ]] && return 0
  truncate -s "$tamanho" "$arquivo"
  for ((i = 0; i * QA_PARTE < tamanho; i++)); do
    for pos in 0 $((QA_PARTE / 2)) $((QA_PARTE - 16)); do
      [[ $((i * QA_PARTE + pos + 12)) -le $tamanho ]] || continue
      printf 'm%03d-%07d' "$i" "$pos" | dd of="$arquivo" bs=1 seek=$((i * QA_PARTE + pos)) conv=notrunc status=none
    done
  done
}

_qa_ambiente_sessao() { # <bytes> — base com credencial, origem e servidor duble
  local tamanho=$1 base
  base=$(mktemp -d "$DBX_TESTES_TMP/qa-b14u.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/tmp" "$base/trabalho" "$base/sess"
  chmod 700 "$base/config/dbx"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  _qa_origem "$DBX_TESTES_TMP/qa-b14-origem-$tamanho.bin" "$tamanho"
  cp --sparse=always "$DBX_TESTES_TMP/qa-b14-origem-$tamanho.bin" "$base/trabalho/grande.iso"
  touch -d '1 hour ago' "$base/trabalho/grande.iso"
  : >"$base/roteiro"
  printf '#!%s\nbase=%q\n' "$BASH" "$base" >"$base/bin/curl"
  cat >>"$base/bin/curl" <<'FIM'
export LC_ALL=C
conf=$(cat)
saida=''; escrever=''; anterior=''; url=''; dados=''; cabecalhos=''; falhar=nao
for a in "$@"; do
  case $anterior in -o) saida=$a ;; -w) escrever=$a ;; --data-binary) dados=${a#@} ;; -D) cabecalhos=$a ;; esac
  case $a in http*) url=$a ;; --fail) falhar=sim ;; esac
  anterior=$a
done
arg=''
while IFS= read -r linha; do
  case $linha in 'header = "Dropbox-API-Arg: '*)
    arg=${linha#'header = "Dropbox-API-Arg: '}; arg=${arg%\"}; arg=${arg//\\\"/\"}; arg=${arg//\\\\/\\} ;;
  esac
done <<<"$conf"
ep=${url#https://*/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
printf '%s\n' "$ep" >>"$base/ordinais"
n=0
while IFS= read -r l; do [[ $l == "$ep" ]] && n=$((n + 1)); done <"$base/ordinais"
printf '%s %s\n' "$ep" "$arg" >>"$base/chamadas"
acao=''
while read -r e k a; do
  [[ $e == "$ep" && $k == "$n" ]] && acao=$a
done <"$base/roteiro"
[[ $acao == SINAL:* ]] && { kill -s "${acao#SINAL:}" "$(<"$base/pid")"; sleep 5; exit 7; }
codigo=200 resposta='{}'
erro() { codigo=409; resposta="{\"error_summary\":\"$1\",\"error\":{\".tag\":\"${1%%/*}\"}}"; }
sid=''; off=''
[[ $arg =~ \"session_id\":\"([^\"]*)\" ]] && sid=${BASH_REMATCH[1]}
[[ $arg =~ \"offset\":([0-9]+) ]] && off=${BASH_REMATCH[1]}
recebe() {
  local tam h
  tam=$(wc -c <"$dados")
  if [[ $tam -gt 0 ]]; then
    h=$(sha256sum <"$dados"); h=${h%% *}
    printf '%s\n' "$h" >>"$base/sess/$sid/blocos"
    cat "$dados" >>"$base/sess/$sid/bytes"
  fi
  printf '%s %s %s\n' "$sid" "$off" "$tam" >>"$base/anexos"
  printf '%s' "$((off + tam))" >"$base/sess/$sid/offset"
}
case $ep in
  oauth2/token) resposta='{"access_token":"sl.t","token_type":"bearer","expires_in":14400}' ;;
  files/get_metadata)
    if [[ -r $base/publicado ]]; then
      resposta="{\".tag\":\"file\",\"name\":\"grande.iso\",\"path_display\":\"/Grande.iso\",\"rev\":\"0123456789a\",\"size\":1,\"content_hash\":\"$(<"$base/publicado")\"}"
    else
      erro 'path/not_found/'
    fi
    ;;
  users/get_space_usage) resposta='{"used":0,"allocation":{".tag":"individual","allocated":1000000000000}}' ;;
  files/upload_session/start)
    sid="SESSAO-$n"
    mkdir -p "$base/sess/$sid"
    printf 0 >"$base/sess/$sid/offset"
    : >"$base/sess/$sid/blocos"
    : >"$base/sess/$sid/bytes"
    resposta="{\"session_id\":\"$sid\"}"
    ;;
  files/upload_session/append_v2)
    if [[ ! -d $base/sess/$sid ]]; then erro 'not_found/'
    else
      srv=$(<"$base/sess/$sid/offset")
      if [[ $off != "$srv" ]]; then
        codigo=409; resposta="{\"error_summary\":\"incorrect_offset/\",\"error\":{\".tag\":\"incorrect_offset\",\"correct_offset\":$srv}}"
      else
        recebe
      fi
    fi
    ;;
  files/upload_session/finish)
    if [[ ! -d $base/sess/$sid ]]; then erro 'lookup_failed/not_found/'
    else
      srv=$(<"$base/sess/$sid/offset")
      if [[ $off != "$srv" ]]; then
        codigo=409; resposta="{\"error_summary\":\"lookup_failed/incorrect_offset/\",\"error\":{\".tag\":\"lookup_failed\",\"lookup_failed\":{\".tag\":\"incorrect_offset\",\"correct_offset\":$srv}}}"
      else
        recebe
        : >"$base/sess/$sid/fechada"
        printf '%s' "$sid" >"$base/sessao_final"
        : >"$base/cadeia"
        while IFS= read -r h; do
          esc=''
          for ((i = 0; i < 64; i += 2)); do esc+="\\x${h:i:2}"; done
          printf '%b' "$esc" >>"$base/cadeia"
        done <"$base/sess/$sid/blocos"
        ch=$(sha256sum <"$base/cadeia"); ch=${ch%% *}
        printf '%s' "$ch" >"$base/publicado"
        resposta="{\".tag\":\"file\",\"name\":\"grande.iso\",\"path_display\":\"/Grande.iso\",\"id\":\"id:1\",\"rev\":\"0123456789a\",\"size\":$srv,\"content_hash\":\"$ch\",\"server_modified\":\"2026-01-01T00:00:00Z\",\"client_modified\":\"2026-01-01T00:00:00Z\"}"
      fi
    fi
    ;;
  *) erro 'sem_regra/' ;;
esac
[[ -n $cabecalhos ]] && printf 'HTTP/1.1 %s X\r\n\r\n' "$codigo" >"$cabecalhos"
if [[ $falhar == sim && $codigo -ge 400 ]]; then
  [[ -n $escrever ]] && printf '%s' "$codigo"
  exit 22
fi
[[ -n $saida ]] && printf '%s' "$resposta" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

# _qa_subir <base> — `dbx upload grande.iso /Grande.iso`, em grupo de processos
# proprio (o duble sinaliza o dbx pelo pid) e sem terminal.
_qa_subir() {
  local base=$1
  (
    cd "$base/trabalho" || exit 99
    env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
      DBX_FREEBSD_REGISTRO="${DBX_FREEBSD_REGISTRO:-}" \
      DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout -k 2 300 setsid -w bash -c 'printf "%s" "$$" >"$1/pid"; shift; exec bash "$@"' _ \
      "$base" "$(_qa_produto)" upload grande.iso /Grande.iso </dev/null >"$base/out" 2>"$base/err"
  ) 2>/dev/null
  DBX_ESTADO=$?
  DBX_SAIDA=''
  DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _qa_soma_anexos <base> — soma dos bytes recebidos pelas partes, por sessao final.
_qa_soma_anexos() {
  local s o t soma=0
  while read -r s o t; do soma=$((soma + t)); done <"$1/anexos"
  printf '%s' "$soma"
}

# _qa_confere_servidor <base> <bytes> — o servidor tem EXATAMENTE a origem.
_qa_confere_servidor() {
  local base=$1 tamanho=$2 sid
  sid=$(<"$base/sessao_final")
  assert_igual "$tamanho" "$(dbx_freebsd_real stat -c %s "$base/sess/$sid/bytes")" 'o servidor recebeu o tamanho exato do arquivo'
  cmp -s "$base/sess/$sid/bytes" "$base/trabalho/grande.iso" ||
    _harness_falhar 'bytes no servidor duble diferem da origem (cmp)'
  assert_igual "$(_qa_ref_hash "$base/trabalho/grande.iso")" "$(<"$base/publicado")" \
    'content_hash do que o servidor recebeu igual ao de referencia da origem'
}

teste_upload_por_sessao_acima_do_limiar_envia_o_tamanho_e_bytes_identicos() {
  local base tamanho=$((150 * QA_MiB + 3))
  base=$(_qa_ambiente_sessao "$tamanho")
  dbx_freebsd_ativar
  _qa_subir "$base"
  assert_igual 0 "$DBX_ESTADO" "RF-173: upload por sessao conclui sob o duble do head: $DBX_ERRO"
  assert_igual "$tamanho" "$(_qa_soma_anexos "$base")" 'TC-FBSD-26: a soma das partes e o tamanho do arquivo'
  _qa_confere_servidor "$base" "$tamanho"
  assert_igual '' "$(dbx_freebsd_erros)" 'os dubles nao registraram erro de uso'
}

teste_upload_por_sessao_de_tamanho_exato_multiplo_de_4_mib() {
  local base tamanho=$((160 * QA_MiB))
  base=$(_qa_ambiente_sessao "$tamanho")
  dbx_freebsd_ativar
  _qa_subir "$base"
  assert_igual 0 "$DBX_ESTADO" "upload multiplo exato conclui: $DBX_ERRO"
  assert_igual "$tamanho" "$(_qa_soma_anexos "$base")" 'a soma das partes e o tamanho'
  _qa_confere_servidor "$base" "$tamanho"
}

teste_retomada_de_upload_interrompido_deixa_o_arquivo_final_identico() {
  local base tamanho=$((150 * QA_MiB + 3)) sid
  base=$(_qa_ambiente_sessao "$tamanho")
  dbx_freebsd_ativar
  printf '%s\n' 'files/upload_session/append_v2 6 SINAL:TERM' >>"$base/roteiro"
  _qa_subir "$base"
  assert_igual 14 "$DBX_ESTADO" "TC-FBSD-27: a 1a execucao e interrompida por TERM: $DBX_ERRO"
  sid=SESSAO-1
  assert_igual $((5 * QA_PARTE)) "$(<"$base/sess/$sid/offset")" 'o servidor confirmou 5 partes antes da queda'
  _qa_subir "$base"
  assert_igual 0 "$DBX_ESTADO" "a retomada conclui (prefixo relido sem perda): $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'upload_session/start' "$base/chamadas")" 'a retomada reaproveitou a sessao (um unico start)'
  assert_igual "$(<"$base/sessao_final")" "$sid" 'a sessao finalizada e a interrompida'
  _qa_confere_servidor "$base" "$tamanho"
  assert_igual '' "$(dbx_freebsd_erros)" 'os dubles nao registraram erro de uso'
}

# ---------------------------------------------------------------------------
# Mutacao: `head -c` no lugar de `dbx_ler_exato` TEM de ser pego sob o duble, e
# so sob ele (controle: sem o duble o GNU `head -c` nao perde nada).
# ---------------------------------------------------------------------------

teste_mutacao_head_c_no_lugar_de_dbx_ler_exato_e_reprovada_sob_o_duble() {
  local base mutante tamanho=$((2 * QA_PARTE + 777)) ref
  mutante=$(_qa_mutante)
  base=$(_qa_cenario_verificar)
  _qa_aleatorio "$base/local/m.bin" "$tamanho"
  ref=$(_qa_ref_hash "$base/local/m.bin")
  printf '{"entries":[{".tag":"file","path_display":"/r/m.bin","content_hash":"%s","size":%s,"rev":"0123456789a"}],"has_more":false}' \
    "$ref" "$tamanho" >"$base/listagem"
  # controle: sem o duble, o mutante e inofensivo (o defeito e do head do FreeBSD).
  _qa_rodar_verificar "$base" "$mutante"
  assert_igual 0 "$DBX_ESTADO" "controle: mutante sem o duble do head confere igual: $DBX_ERRO"
  # com o duble: o mutante reproduz o defeito de campo.
  dbx_freebsd_ativar
  _qa_rodar_verificar "$base" "$mutante"
  assert_diferente 0 "$DBX_ESTADO" 'o mutante sob o duble do head do FreeBSD diverge do resumo de referencia'
  # e o produto real, sob o mesmo duble, confere.
  _qa_rodar_verificar "$base" "$DBX_HARNESS_RAIZ/bin/dbx"
  assert_igual 0 "$DBX_ESTADO" "o produto real sob o duble confere igual: $DBX_ERRO"
}

harness_executar "$@"
