#!/usr/bin/env bash
# Suite independente do QA, B17: portabilidade das expressoes regulares ao
# FreeBSD (RF-166, TC-FBSD-19 parte regex).
#
# POR QUE. No FreeBSD o `[[ =~ ]]` do bash usa o regcomp da libc, cujo limite de
# repeticao (RE_DUP_MAX) e 255: `{n}`, `{n,}` e `{n,m}` com n ou m acima disso
# sao regex INVALIDAS, e o teste falha sempre (nao erra: devolve "nao casou").
# Foi assim que o registro de retomada do upload (session_id) nunca era gravado
# e o cursor do `sync --receber` nunca era aceito. O `grep` e o `sed` da base do
# FreeBSD usam o mesmo regcomp/regexec e o mesmo limite; `awk` e `find -regex`
# tambem. O glibc aceita ate 32767, e por isso nenhuma suite em Linux enxerga o
# defeito: so uma auditoria do TEXTO das regex o pega. A suite do developer
# (tests/unit/regex_portavel_test.sh) nao e usada como base.
#
# O QUE ESTA SUITE FAZ
#   A. Auditoria de texto, mais ampla que a do developer: qualquer `{n}`,
#      `{n,}`, `{,m}`, `{n,m}` (ERE) e `\{n,m\}` (BRE) com numero > 255 em
#      lib/, commands/, bin/, install.sh, uninstall.sh, seja o consumidor
#      `[[ =~ ]]` (literal, em variavel ou constante), grep, sed, awk ou
#      `find -regex`. O auditor e validado contra um fixture com todas as
#      formas (positivos e negativos de fronteira), e o limite de bash 255
#      aceito. Limite dinamico (`{1,$N}`) e auditado a parte.
#   B. Comportamento pelo executavel real `bin/dbx`, com duplo de `curl`
#      proprio: upload por sessao interrompido grava o registro de retomada com
#      session_id realista e a execucao seguinte retoma; `sync --receber` grava
#      e reaproveita o cursor (300, 2000 e 8192 caracteres). Fronteiras:
#      session_id 256 aceito / 257 recusado; cursor 8192 / 8193; assinatura 256 /
#      257 (a assinatura do produto e constante; a fronteira e provada na
#      interface publica `dbx_state_cursor_contexto`).
#   C. Mutacao: em copia do codigo, cada regex volta a `{1,N}` com N > 255 e a
#      auditoria A tem de reprovar. A mutacao so e visivel pela auditoria, nao
#      pelo comportamento em Linux (glibc aceita).
#
# shellcheck disable=SC2016,SC2034
# Justificativa: os duplos de `curl` e os fixtures sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly QA_DBX="$DBX_HARNESS_RAIZ/bin/dbx"
readonly QA_PARTE=4194304
readonly QA_TAMANHO=$((157286400 + 3))
readonly QA_SESSAO='QA7SESSAOsentinela'
readonly QA_REV1='0123456789a'
readonly QA_REV2='0123456789b'

DBX_ESTADO=''
DBX_SAIDA=''
DBX_ERRO=''

# ---------------------------------------------------------------------------
# Comum
# ---------------------------------------------------------------------------

# _qa_hash_para <arquivo> <saida> — content_hash do arquivo, calculado pela
# biblioteca em subshell, gravado em <saida> (lido depois com `read`).
_qa_hash_para() {
  (
    . "$DBX_HARNESS_RAIZ/lib/hash.sh"
    dbx_hash_publicar_arquivo "$1" && printf '%s' "$DBX_HASH_RESULTADO" >"$2"
  )
}

_qa_ler() { # <arquivo> — primeira linha, sem `$(...)` sobre bytes externos
  local v=''
  [[ -r $1 ]] && IFS= read -r v <"$1"
  printf '%s' "$v"
}

_qa_credencial() { # <base>
  mkdir -p "$1/config/dbx"
  chmod 700 "$1/config/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$1/config/dbx/credencial.json"
  chmod 600 "$1/config/dbx/credencial.json"
}

# _qa_rodar <base> <argumentos...> — sem terminal, com teto, em grupo proprio.
# `QA_EXEC` troca o executavel (copia mutante, usada so na auditoria do QA).
_qa_rodar() {
  local base=$1
  shift
  (
    cd "$base/trabalho" || exit 99
    env -i PATH="${QA_PATH:+$QA_PATH:}$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
      DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout -k 2 "${QA_TETO:-120}" setsid -w bash -c 'umask "$1"; shift; printf "%s" "$$" >"$1/pid"; shift; exec bash "$@"' _ \
      "${QA_UMASK:-022}" "$base" "${QA_EXEC:-$QA_DBX}" "$@" </dev/null >"$base/out" 2>"$base/err"
  ) 2>/dev/null
  DBX_ESTADO=$?
  if [[ $DBX_ESTADO -eq 137 && -e $base/morto ]]; then
    rm -f "$base/morto"
  elif [[ $DBX_ESTADO -eq 124 || $DBX_ESTADO -eq 137 ]]; then
    _harness_falhar "o comando pendurou ($DBX_ESTADO): $*"
  fi
  # Com `--null` a saida tem NUL: cada campo entra, separado por quebra de
  # linha, para as assercoes verem a saida INTEIRA.
  local campo
  DBX_SAIDA='' DBX_ERRO=''
  while IFS= read -r -d '' campo || [[ -n $campo ]]; do DBX_SAIDA+=$campo$'\n'; done <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_qa_registros() { # <base> — quantos `retomada-*`
  local r n=0
  for r in "$1"/estado/dbx/retomada-*; do [[ -e $r || -L $r ]] && n=$((n + 1)); done
  printf '%s' "$n"
}

_qa_registro() { # <base> — caminho do (unico) `retomada-*`
  local r
  for r in "$1"/estado/dbx/retomada-*; do [[ -e $r ]] && printf '%s' "$r"; done
}

# _qa_campos_ler <registro> — campos em QA_C.
QA_C=()
_qa_campos_ler() {
  local f
  QA_C=()
  while IFS= read -r -d '' f; do QA_C+=("$f"); done <"$1"
}
_qa_campos_gravar() { printf '%s\0' "${QA_C[@]}" >"$1"; }

_qa_impressao() { # <arquivo> — conteudo e metadados que nao podem mudar
  local h
  h=$(sha256sum <"$1")
  stat -c '%i %s %a %Y' -- "$1"
  printf '%s\n' "${h%% *}"
}

# ---------------------------------------------------------------------------
# Upload: ambiente e duplo
# ---------------------------------------------------------------------------

_qa_fixture_up() {
  local arquivo="$DBX_TESTES_TMP/qa7-up.bin" i
  if [[ ! -e $arquivo ]]; then
    truncate -s "$QA_TAMANHO" "$arquivo"
    for ((i = 0; i * QA_PARTE < QA_TAMANHO; i++)); do
      printf 'qa-up-%03d' "$i" | dd of="$arquivo" bs=1 seek=$((i * QA_PARTE)) conv=notrunc status=none
    done
  fi
  printf '%s' "$arquivo"
}

# Higiene do tmp da suite (fase 9, 2026-10-22): cada ambiente guarda copias de ~150 MiB e o
# runner so limpa DBX_TESTES_TMP no fim da suite; sem isto este arquivo deixava ~3,2 GB no tmpfs
# e a retomada de download seguinte o lotava. Os ambientes do caso ANTERIOR saem quando outro
# caso cria o primeiro dele; um caso com dois ambientes mantem os dois. As fixtures ficam.
_qa_limpar_ambientes_de_outro_caso() {
  local caso='' f marca="$DBX_TESTES_TMP/qa7.caso" anterior=''
  for f in "${FUNCNAME[@]}"; do
    [[ $f == teste_* ]] && { caso=$f; break; }
  done
  [[ -n $caso ]] || return 0
  [[ -r $marca ]] && IFS= read -r anterior <"$marca"
  [[ $anterior == "$caso" ]] && return 0
  rm -rf -- "$DBX_TESTES_TMP"/qa7u.* "$DBX_TESTES_TMP"/qa7d.*
  printf '%s\n' "$caso" >"$marca"
}

_qa_up_ambiente() {
  local base
  _qa_limpar_ambientes_de_outro_caso
  base=$(mktemp -d "$DBX_TESTES_TMP/qa7u.XXXXXX")
  mkdir -p "$base/bin" "$base/tmp" "$base/trabalho" "$base/sess"
  _qa_credencial "$base"
  cp --sparse=always "$(_qa_fixture_up)" "$base/trabalho/grande.iso"
  touch -d '1 hour ago' "$base/trabalho/grande.iso"
  : >"$base/roteiro"
  {
    printf '#!%s\n' "$BASH"
    printf 'base=%q\nsentinela=%q\n' "$base" "$QA_SESSAO"
  } >"$base/bin/curl"
  cat >>"$base/bin/curl" <<'FIM'
export LC_ALL=C
conf=$(cat)
printf '%s\n' "$*" >>"$base/argv"
env >>"$base/ambiente"
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
while read -r e k a; do [[ $e == "$ep" && $k == "$n" ]] && acao=$a; done <"$base/roteiro"
pid=$(<"$base/pid")
case $acao in
  SINAL:*) kill -s "${acao#SINAL:}" "$pid"; sleep 5; exit 7 ;;
esac
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
    printf '%s\n' "$h" >>"$base/sess/${sid:0:100}/blocos"
  fi
  printf '%s %s %s\n' "$sid" "$off" "$tam" >>"$base/anexos"
  printf '%s' "$((off + tam))" >"$base/sess/${sid:0:100}/offset"
}
case $ep in
  oauth2/token) resposta='{"access_token":"sl.QA7token","token_type":"bearer","expires_in":14400}' ;;
  files/get_metadata)
    if [[ -r $base/publicado ]]; then
      resposta="{\".tag\":\"file\",\"name\":\"grande.iso\",\"path_display\":\"/Grande.iso\",\"id\":\"id:1\",\"rev\":\"0123456789a\",\"size\":$(<"$base/publicado_tamanho"),\"content_hash\":\"$(<"$base/publicado")\"}"
    else
      erro 'path/not_found/'
    fi
    ;;
  users/get_space_usage) resposta='{"used":0,"allocation":{".tag":"individual","allocated":1000000000000}}' ;;
  files/upload_session/start)
    sid="$sentinela-$n"; [[ -r $base/sid_fixo ]] && sid=$(<"$base/sid_fixo")
    mkdir -p "$base/sess/${sid:0:100}"
    printf 0 >"$base/sess/${sid:0:100}/offset"
    : >"$base/sess/${sid:0:100}/blocos"
    resposta="{\"session_id\":\"$sid\"}"
    ;;
  files/upload_session/append_v2)
    if [[ ! -d $base/sess/${sid:0:100} ]]; then erro 'not_found/'
    elif [[ -e $base/sess/${sid:0:100}/fechada ]]; then erro 'closed/'
    else
      case $acao in
        NOT_FOUND) erro 'not_found/' ;;
        OFFSET:*) codigo=409; resposta="{\"error_summary\":\"incorrect_offset/\",\"error\":{\".tag\":\"incorrect_offset\",\"correct_offset\":${acao#OFFSET:}}}" ;;
        *)
          srv=$(<"$base/sess/${sid:0:100}/offset")
          if [[ $off != "$srv" ]]; then
            codigo=409; resposta="{\"error_summary\":\"incorrect_offset/\",\"error\":{\".tag\":\"incorrect_offset\",\"correct_offset\":$srv}}"
          else
            recebe
          fi
          ;;
      esac
    fi
    ;;
  files/upload_session/finish)
    if [[ ! -d $base/sess/${sid:0:100} ]]; then erro 'lookup_failed/not_found/'
    elif [[ -e $base/sess/${sid:0:100}/fechada ]]; then erro 'lookup_failed/closed/'
    else
      srv=$(<"$base/sess/${sid:0:100}/offset")
      if [[ $off != "$srv" ]]; then
        codigo=409; resposta="{\"error_summary\":\"lookup_failed/incorrect_offset/\",\"error\":{\".tag\":\"lookup_failed\",\"lookup_failed\":{\".tag\":\"incorrect_offset\",\"correct_offset\":$srv}}}"
      else
        recebe
        : >"$base/sess/${sid:0:100}/fechada"
        : >"$base/cadeia"
        while IFS= read -r h; do
          esc=''
          for ((i = 0; i < 64; i += 2)); do esc+="\\x${h:i:2}"; done
          printf '%b' "$esc" >>"$base/cadeia"
        done <"$base/sess/${sid:0:100}/blocos"
        ch=$(sha256sum <"$base/cadeia"); ch=${ch%% *}
        printf '%s' "$ch" >"$base/publicado"
        printf '%s' "$(<"$base/sess/${sid:0:100}/offset")" >"$base/publicado_tamanho"
        printf '%s\n' "$sid" >>"$base/finalizadas"
        resposta="{\".tag\":\"file\",\"name\":\"grande.iso\",\"path_display\":\"/Grande.iso\",\"id\":\"id:1\",\"rev\":\"0123456789a\",\"size\":1,\"content_hash\":\"$ch\",\"server_modified\":\"2026-01-01T00:00:00Z\",\"client_modified\":\"2026-01-01T00:00:00Z\"}"
      fi
    fi
    ;;
  *) erro 'sem_regra/' ;;
esac
[[ $acao == ACEITA_E_KILL ]] && { : >"$base/morto"; kill -9 "$pid"; exit 7; }
[[ -n $cabecalhos ]] && printf 'HTTP/1.1 %s X\r\n\r\n' "$codigo" >"$cabecalhos"
if [[ $falhar == sim && $codigo -ge 400 ]]; then
  [[ -n $escrever ]] && printf '%s' "$codigo"
  exit 22
fi
[[ -n $saida ]] && printf '%s' "$resposta" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  printf '#!%s\nexit 0\n' "$BASH" >"$base/bin/sleep"
  chmod +x "$base/bin/curl" "$base/bin/sleep"
  printf '%s' "$base"
}

_qa_up() { _qa_rodar "$1" upload "${@:2}" grande.iso /Grande.iso; }
_qa_roteiro() { printf '%s %s %s\n' "$2" "$3" "$4" >>"$1/roteiro"; }
_qa_conta() { _harness_contar "$2" "$1/chamadas"; }
_qa_offsets_de() { # <base> <sessao>
  local s o t lista=''
  [[ -r $1/anexos ]] || return 0
  while read -r s o t; do [[ $s == "$2" ]] && lista+="$o "; done <"$1/anexos"
  printf '%s' "$lista"
}

# _qa_up_parada <base> <k> — TERM no k-esimo `append_v2`: k-1 partes confirmadas.
_qa_up_parada() {
  _qa_roteiro "$1" files/upload_session/append_v2 "$2" SINAL:TERM
  _qa_up "$1"
  assert_igual 14 "$DBX_ESTADO" "sinal: 14 ($DBX_ERRO)"
  assert_igual 1 "$(_qa_registros "$1")" 'registro fica'
}

# _qa_up_perdida <base> <k> — a k-esima parte chega e a resposta se perde.
_qa_up_perdida() {
  _qa_roteiro "$1" files/upload_session/append_v2 "$2" ACEITA_E_KILL
  _qa_up "$1"
  assert_igual 1 "$(_qa_registros "$1")" 'registro deixado pelo kill -9'
}

# _qa_up_publicado_e_o_local <base> — o que o servidor publicou e o conteudo
# local CORRENTE, byte a byte (pelo content_hash), e a saida declara conferida.
_qa_up_publicado_e_o_local() {
  _qa_hash_para "$1/trabalho/grande.iso" "$1/hash_local"
  assert_igual "$(_qa_ler "$1/hash_local")" "$(_qa_ler "$1/publicado")" 'o publicado e o arquivo local corrente'
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'conferida'
}

readonly Q_DBX="$DBX_HARNESS_RAIZ/bin/dbx"
Q_BASH=$(command -v bash)
readonly Q_BASH
Q_SLEEP=$(command -v sleep)
readonly Q_SLEEP
readonly Q_TOKEN='sl.QACURSORtoken5k'
readonly Q_REFRESH='QACURSORrefresh4j'
readonly Q_SEGREDO='QACURSORsegredo3h'
# Todo cursor do duplo comeca por este prefixo: nenhum byte dele pode sair.
readonly Q_SENT='QAB7BCURSORSENT'
readonly Q_REV='0123456789a'
Q_H1=''
Q_H2=''

_q_hash_de() { # <texto> — content_hash em Q_HASH
  Q_HASH=$(bash -c '. "$1/lib/errors.sh"; . "$1/lib/hash.sh"; printf "%s" "$2" | dbx_hash_conteudo_fluxo' _ "$DBX_HARNESS_RAIZ" "$1")
}

_q_hashes() {
  [[ -n $Q_H1 ]] && return 0
  _q_hash_de 'conteudo remoto'
  Q_H1=$Q_HASH
  _q_hash_de 'conteudo versao 2'
  Q_H2=$Q_HASH
}

# _q_cen [raiz_remota_da_credencial] — area, credencial, duplo de rede.
_q_cen() {
  _q_hashes
  B=$(mktemp -d "$DBX_TESTES_TMP/qa-cursor.XXXXXX")
  mkdir -p "$B/cfg/dbx" "$B/bin" "$B/resp" "$B/tmp" "$B/estado" "$B/l"
  chmod 700 "$B/cfg/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"%s","refresh_token":"%s","raiz_remota":"/"}' \
    "$Q_SEGREDO" "$Q_REFRESH" >"$B/cfg/dbx/credencial.json"
  chmod 600 "$B/cfg/dbx/credencial.json"
  : >"$B/regras"
  : >"$B/chamadas"
  : >"$B/argv"
  : >"$B/ambiente"
  Q_N=0
  {
    printf '#!%s\nQA=%q\nTOKEN=%q\nDORME=%q\n' "$Q_BASH" "$B" "$Q_TOKEN" "$Q_SLEEP"
    cat <<'FIM'
export LC_ALL=C
config=''
IFS= read -r -d '' config || :
printf '%s\0' "$@" >>"$QA/argv"
printf '\n' >>"$QA/argv"
env >>"$QA/ambiente"
o=''; w=''; ant=''; url=''; dados=''; cab=''
for a in "$@"; do
  case $ant in -o) o=$a ;; -w) w=$a ;; --data-binary) dados=${a#@} ;; -D) cab=$a ;; esac
  case $a in http*) url=$a ;; esac
  ant=$a
done
pedido=''
[[ -n $dados && -r $dados ]] && IFS= read -r -d '' pedido <"$dados"
if [[ -z $dados && $config == *Dropbox-API-Arg:* ]]; then
  pedido=${config#*Dropbox-API-Arg: }
  pedido=${pedido%%$'\n'*}
fi
ep=${url#https://api.dropboxapi.com/2/}
ep=${ep#https://content.dropboxapi.com/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
printf '%s\t%s\n' "$ep" "$pedido" >>"$QA/chamadas"
cod=400 corpo='{"error_summary":"sem_regra/"}' achou=nao n=0
while IFS=$'\t' read -r rep rfi rco rar rvz; do
  n=$((n + 1))
  [[ -n $rep ]] || continue
  # shellcheck disable=SC2053
  [[ $ep == $rep && $pedido == $rfi ]] || continue
  if [[ $rvz == uma ]]; then
    mkdir "$QA/usada.$n" 2>/dev/null || continue
  fi
  achou=sim cod=$rco corpo=''
  [[ -r $QA/resp/$rar ]] && IFS= read -r -d '' corpo <"$QA/resp/$rar"
  break
done <"$QA/regras"
if [[ $achou == nao ]]; then
  case $ep in
    oauth2/token) cod=200 corpo="{\"access_token\":\"$TOKEN\",\"token_type\":\"bearer\",\"expires_in\":14400}" ;;
    users/get_current_account) cod=200 corpo='{"account_id":"dbid:QACONTAB7B"}' ;;
    files/get_metadata) cod=409 corpo='{"error_summary":"path/not_found/..","error":{".tag":"path","path":{".tag":"not_found"}}}' ;;
    files/download) cod=200 corpo='conteudo remoto' ;;
    auth/token/revoke) cod=200 corpo='null' ;;
  esac
fi
case $cod in
  REDE) exit 7 ;;
  SINAL:*)
    kill -s "${cod#SINAL:}" "$(<"$QA/pid")"
    "$DORME" 1
    exit 7
    ;;
esac
if [[ -n $cab ]]; then
  printf 'HTTP/1.1 %s X\r\n\r\n' "$cod" >"$cab"
fi
[[ -n $o ]] && printf '%s' "$corpo" >"$o"
[[ -n $w ]] && printf '%s' "$cod"
exit 0
FIM
  } >"$B/bin/curl"
  printf '#!%s\nexit 0\n' "$Q_BASH" >"$B/bin/sleep"
  chmod +x "$B/bin/curl" "$B/bin/sleep"
}

# _q_regra <endpoint> <filtro_do_corpo> <codigo> <corpo> [uma]
_q_regra() {
  Q_N=$((Q_N + 1))
  printf '%s' "$4" >"$B/resp/r$Q_N"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "r$Q_N" "${5:-}" >>"$B/regras"
}

_q_zerar() {
  : >"$B/regras"
  rm -rf "$B"/usada.*
  : >"$B/chamadas"
}

# _q_rodar <argumentos...> — sem terminal, grupo proprio, teto de tempo, pid
# em `$B/pid` para o duplo poder sinalizar o `dbx`.
_q_rodar() {
  (
    cd "$B" || exit 99
    env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
      TMPDIR="$B/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout -k 2 120 setsid -w "$Q_BASH" -c 'umask "$1"; shift; printf "%s" "$$" >"$1/pid"; shift; exec "$@"' _ \
      "${Q_UMASK:-022}" "$B" "$Q_BASH" "$Q_DBX" "$@" </dev/null >"$B/out" 2>"$B/err"
  ) 2>/dev/null
  ESTADO=$?
  [[ $ESTADO -eq 124 || $ESTADO -eq 137 ]] && _harness_falhar "o comando pendurou ($ESTADO): $*"
  SAIDA=$(tr '\0' '\n' <"$B/out")
  ERRO=$(tr '\0' '\n' <"$B/err")
  return 0
}

# Entradas da listagem sob /r. _q_arq <rel> [hash] [id] [rev]
_q_arq() {
  local rel=$1 hash=${2:-$Q_H1} id=${3:-} rev=${4:-$Q_REV} baixo
  [[ -n $id ]] || id="id:${rel//[^A-Za-z0-9]/_}"
  baixo=/r/$rel
  baixo=${baixo,,}
  printf -v Q_E '{".tag":"file","name":"%s","id":"%s","path_lower":"%s","path_display":"/r/%s","rev":"%s","size":15,"server_modified":"2026-01-01T00:00:00Z","content_hash":"%s"}' \
    "${rel##*/}" "$id" "$baixo" "$rel" "$rev" "$hash"
}

_q_pasta() { # <rel> [id]
  local rel=$1 baixo=/r/$1 id=${2:-}
  [[ -n $id ]] || id="id:d_${rel//[^A-Za-z0-9]/_}"
  baixo=${baixo,,}
  printf -v Q_E '{".tag":"folder","name":"%s","id":"%s","path_lower":"%s","path_display":"/r/%s"}' \
    "${rel##*/}" "$id" "$baixo" "$rel"
}

_q_apagado() { # <rel>
  local rel=$1 baixo=/r/$1
  baixo=${baixo,,}
  printf -v Q_E '{".tag":"deleted","name":"%s","path_lower":"%s","path_display":"/r/%s"}' \
    "${rel##*/}" "$baixo" "$rel"
}

_q_pagina() { # <cursor> <has_more> [entradas...] — em Q_P
  local cursor=$1 mais=$2 lista='' e
  shift 2
  for e in "$@"; do lista+=${lista:+,}$e; done
  printf -v Q_P '{"entries":[%s],"cursor":"%s","has_more":%s}' "$lista" "$cursor" "$mais"
}

_q_servidor() { # <cursor> [entradas...] — listagem recursiva
  local cursor=$1
  shift
  _q_pagina "$cursor" false "$@"
  _q_regra files/list_folder '*"recursive":true*' 200 "$Q_P"
}

_q_delta() { # <de> <para> [entradas...]
  local de=$1 para=$2
  shift 2
  _q_pagina "$para" false "$@"
  _q_regra files/list_folder/continue "*\"cursor\":\"$de\"*" 200 "$Q_P"
}

# _q_meta <rel> [id] — get_metadata do caminho devolve metadado (o item EXISTE).
_q_meta() {
  local rel=$1 id=${2:-}
  _q_arq "$rel" "$Q_H1" "$id"
  _q_regra files/get_metadata "*\"path\":\"/r/$rel\"*" 200 "$Q_E"
}

_q_contar() { # <endpoint> [filtro] — em Q_CONT
  local ep linha n=0 filtro=${2:-*}
  while IFS= read -r linha; do
    ep=${linha%%$'\t'*}
    # shellcheck disable=SC2053
    [[ $ep == "$1" && ${linha#*$'\t'} == $filtro ]] && n=$((n + 1))
  done <"$B/chamadas"
  Q_CONT=$n
}

_q_registro() { # o unico cursor-* em Q_REG
  local -a achados=()
  local f
  Q_REG=''
  for f in "$B/estado/dbx"/cursor-*; do
    [[ -e $f || -L $f ]] && achados+=("$f")
  done
  [[ ${#achados[@]} -le 1 ]] || _harness_falhar "mais de um cursor-*: ${#achados[@]}"
  [[ ${#achados[@]} -eq 1 ]] && Q_REG=${achados[0]}
  return 0
}

_q_campos() { # <arquivo> — campos NUL em Q_CAMPOS
  Q_CAMPOS=()
  mapfile -d '' -t Q_CAMPOS <"$1"
}

# _q_reescrever <arquivo> <campos...> — campos e rodape VALIDO recalculado (o
# forjador tem acesso ao 0600: so as regras de campo e a confirmacao barram).
_q_reescrever() {
  local arquivo=$1 resumo
  shift
  printf '%s\0' "$@" >"$arquivo"
  resumo=$(sha256sum <"$arquivo")
  printf 'fim\0%s\0' "${resumo%% *}" >>"$arquivo"
}

# _q_sem_rodape — campos do registro corrente sem o rodape, em Q_C.
_q_sem_rodape() {
  _q_registro
  _q_campos "$Q_REG"
  Q_C=("${Q_CAMPOS[@]}")
  unset 'Q_C[${#Q_C[@]}-1]' 'Q_C[${#Q_C[@]}-1]'
  Q_C=("${Q_C[@]}")
}

_q_impressao() { # <arquivo> — modo e conteudo
  if [[ -f $1 ]]; then
    printf '%s ' "$(stat -c %a -- "$1")"
    sha256sum <"$1"
  else
    printf 'ausente\n'
  fi
}

# _q_foto <dir> — impressao de toda entrada do diretorio (nome, tipo, modo,
# conteudo), salvo a trava, em Q_FOTO.
_q_foto() {
  local f linha
  Q_FOTO=''
  for f in "$1"/* "$1"/.[!.]*; do
    [[ -e $f || -L $f ]] || continue
    [[ ${f##*/} == trava-* ]] && continue
    linha=$(_q_impressao "$f")
    Q_FOTO+="${f##*/} $linha"$'\n'
  done
}

_q_valor() { # <campo> — valor na saida (chave=valor), em Q_V
  local linha
  Q_V=''
  while IFS= read -r linha; do
    [[ $linha == "$1="* ]] && { Q_V=${linha#"$1="}; return 0; }
  done <<<"$SAIDA"
  return 1
}

_q_plano() { # plano ordenado (conjunto), em Q_PLANO
  Q_PLANO=$(grep -E '^(transferir|apagar|apenas_no_destino|a_transferir|a_apagar|identicos|filtrados[a-z_]*|recusada|recusaria)=' <<<"$SAIDA" | LC_ALL=C sort)
}

_q_local() { # <rel> [conteudo]
  mkdir -p -- "$B/l/$(dirname -- "$1")"
  printf '%s' "${2:-conteudo remoto}" >"$B/l/$1"
}

# Arvore base: pasta p (x, y), pasta q/r (z), a, b, c.
_q_base() {
  local -a ent=()
  _q_pasta p && ent+=("$Q_E")
  _q_arq a.txt && ent+=("$Q_E")
  _q_arq b.txt && ent+=("$Q_E")
  _q_arq c.txt && ent+=("$Q_E")
  _q_arq p/x.txt && ent+=("$Q_E")
  _q_arq p/y.txt && ent+=("$Q_E")
  _q_pasta q && ent+=("$Q_E")
  _q_pasta q/r && ent+=("$Q_E")
  _q_arq q/r/z.txt && ent+=("$Q_E")
  Q_BASE=("${ent[@]}")
}

# _q_primeira — primeira execucao real (com --espelhar --confirmar,
# para o par ficar "visto"), cursor C1.
_q_primeira() {
  _q_cen
  _q_base
  _q_servidor "${Q_SENT}C1" "${Q_BASE[@]}"
  _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar --confirmar
  assert_igual 0 "$ESTADO" "primeira execucao: $ERRO"
  _q_registro
  [[ -n $Q_REG ]] || _harness_falhar 'a primeira execucao bem-sucedida deveria gravar cursor-*'
  Q_LOCAL_ANTES=$(cd "$B/l" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum)
}



# ===========================================================================
# A. Auditoria de texto das repeticoes de regex (RE_DUP_MAX = 255)
# ===========================================================================

readonly QR_LIMITE=255

# _qr_acima <digitos> — 0 se o numero passa de 255 (sem aritmetica sobre bytes
# de entrada: tira zeros a esquerda e compara por comprimento e valor).
_qr_acima() {
  local n=$1
  [[ -n $n ]] || return 1
  while [[ $n == 0?* ]]; do n=${n#0}; done
  [[ ${#n} -gt 3 ]] && return 0
  [[ $((10#$n)) -gt $QR_LIMITE ]]
}

# _qr_auditar <raiz> — imprime `arquivo:linha:texto` de toda linha com repeticao
# acima de 255, em qualquer consumidor. Cobre ERE `{n,m}` e BRE `\{n,m\}`.
_qr_auditar() {
  local raiz=$1 alvo linha resto achou
  local -a alvos=()
  for alvo in lib commands bin install.sh uninstall.sh; do
    [[ -e $raiz/$alvo ]] && alvos+=("$alvo")
  done
  while IFS= read -r linha; do
    resto=${linha#*:*:}
    achou=nao
    while [[ $resto =~ \{([0-9]*)(,?)([0-9]*)\\?\} ]]; do
      if _qr_acima "${BASH_REMATCH[1]}" || _qr_acima "${BASH_REMATCH[3]}"; then
        achou=sim
        break
      fi
      resto=${resto#*"${BASH_REMATCH[0]}"}
    done
    [[ $achou == sim ]] && printf '%s\n' "$linha"
  done < <(cd "$raiz" && grep -rnE -- '\{[0-9]*,?[0-9]*\\?\}' "${alvos[@]}" 2>/dev/null)
  return 0
}

# _qr_dinamicos <raiz> — repeticao com limite vindo de variavel (`{1,$N}`),
# que nenhum auditor de texto consegue medir.
_qr_dinamicos() {
  local raiz=$1 alvo
  local -a alvos=()
  for alvo in lib commands bin install.sh uninstall.sh; do
    [[ -e $raiz/$alvo ]] && alvos+=("$alvo")
  done
  (cd "$raiz" && grep -rnE -- '\{[0-9]*,\$[{A-Za-z_(][^}]*\}' "${alvos[@]}" 2>/dev/null) || true
}

_qr_numeros() { # linhas `arq:n:txt` -> "n n n"
  local l r='' n
  while IFS= read -r l; do
    [[ -n $l ]] || continue
    n=${l#*:}
    r+="${n%%:*} "
  done <<<"$1"
  printf '%s' "$r"
}

teste_qa_a01_o_auditor_pega_toda_forma_de_repeticao_acima_de_255() {
  local d achados
  d=$(mktemp -d "$DBX_TESTES_TMP/qr-fix.XXXXXX")
  mkdir -p "$d/lib"
  {
    printf '%s\n' '[[ $x =~ ^[a-z]{1,256}$ ]]'
    printf '%s\n' "RE='^[0-9]{300}\$'"
    printf '%s\n' "grep -E '^.{1,1000}\$' f"
    printf '%s\n' "grep '.\\{1,300\\}' f"
    printf '%s\n' "sed -E 's/a{500}/b/'"
    printf '%s\n' "sed 's/a\\{257,\\}/b/'"
    printf '%s\n' "awk '/x{1,4096}/'"
    printf '%s\n' "find . -regex '.*[a-z]{1,999}'"
    printf '%s\n' "[[ \$v =~ \$RE ]] && grep -E 'a{,300}' f"
    printf '%s\n' "x='[0-9]{00256}'"
    printf '%s\n' "y='[0-9]{1,255}' z='a{255}' w='b{256,}'"
    # negativos
    printf '%s\n' "[[ \$x =~ ^[a-z]{1,255}\$ ]]"
    printf '%s\n' "r=\${x:-300} s=\${#x} t={1..300} u=a{b,c} v='a{1,2}'"
    printf '%s\n' "echo '{}' \$((3 + 300))"
  } >"$d/lib/f.sh"
  achados=$(_qr_auditar "$d")
  # positivos nas linhas 1..9 e 10; a 11 tem b{256,} (positivo); 12..14 negativas
  assert_igual '1 2 3 4 5 6 7 8 9 10 11 ' "$(_qr_numeros "$achados")" "linhas sinalizadas: $achados"
}

teste_qa_a02_o_auditor_cobre_todas_as_raizes_do_produto() {
  local d r
  d=$(mktemp -d "$DBX_TESTES_TMP/qr-raiz.XXXXXX")
  mkdir -p "$d/lib" "$d/commands" "$d/bin"
  printf '%s\n' 'a=~[a-z]{1,256}' >"$d/lib/a.sh"
  printf '%s\n' 'a=~[a-z]{1,257}' >"$d/commands/b.sh"
  printf '%s\n' 'a=~[a-z]{1,258}' >"$d/bin/dbx"
  printf '%s\n' 'grep -E "x{1,259}"' >"$d/install.sh"
  printf '%s\n' 'sed -E "s/x{260}//"' >"$d/uninstall.sh"
  r=$(_qr_auditar "$d")
  assert_contem 'lib/a.sh:1' "$r" 'lib'
  assert_contem 'commands/b.sh:1' "$r" 'commands'
  assert_contem 'bin/dbx:1' "$r" 'bin'
  assert_contem 'install.sh:1' "$r" 'install.sh'
  assert_contem 'uninstall.sh:1' "$r" 'uninstall.sh'
}

teste_qa_a03_nenhuma_repeticao_do_produto_passa_de_255_em_qualquer_consumidor() {
  local achados
  achados=$(_qr_auditar "$DBX_HARNESS_RAIZ")
  assert_igual '' "$achados" "repeticao acima de RE_DUP_MAX 255 (quebra no regcomp do FreeBSD): $achados"
}

teste_qa_a04_nenhum_limite_de_repeticao_vem_de_variavel() {
  local achados
  achados=$(_qr_dinamicos "$DBX_HARNESS_RAIZ")
  assert_igual '' "$achados" "limite de repeticao dinamico nao e auditavel; confirmar <= 255 a mao: $achados"
}

# ===========================================================================
# B1. Upload por sessao: registro de retomada com session_id realista
# ===========================================================================

readonly QR_PREFIXO_SID='pid_upload_session:'

_qr_rep() { # <n> — n caracteres base64url, deterministicos
  local n=$1 base='AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_' s=''
  while ((${#s} < n)); do s+=$base; done
  printf '%s' "${s:0:n}"
}

# _qr_up_sid <sid> — upload interrompido no 2o append. Imprime a base.
_qr_up_preparar() {
  local base
  base=$(_qa_up_ambiente)
  printf '%s' "$1" >"$base/sid_fixo"
  printf '%s' "$base"
}

teste_qa_b01_upload_interrompido_grava_o_registro_e_a_execucao_seguinte_retoma() {
  local base sid
  sid="${QR_PREFIXO_SID}$(_qr_rep 60)"
  base=$(_qr_up_preparar "$sid")
  _qa_up_parada "$base" 2
  _qa_campos_ler "$(_qa_registro "$base")"
  assert_igual "$sid" "${QA_C[6]}" 'o registro guarda o session_id realista'
  assert_igual 1 "$(_qa_conta "$base" '^files/upload_session/start ')" 'uma sessao aberta ate aqui'
  _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "a execucao seguinte conclui: $DBX_ERRO"
  assert_igual 1 "$(_qa_conta "$base" '^files/upload_session/start ')" 'retomou: nenhuma sessao nova'
  assert_contem "$sid" "$(<"$base/finalizadas")" 'a sessao do registro foi a concluida'
  local offs
  offs=$(_qa_offsets_de "$base" "$sid")
  [[ $offs == '0 4194304 '* ]] || _harness_falhar "a parte 0 nao pode ser reenviada: $offs"
  _qa_up_publicado_e_o_local "$base"
  assert_igual 0 "$(_qa_registros "$base")" 'registro some ao concluir'
}

teste_qa_b02_session_id_de_256_caracteres_e_aceito_e_retomado() {
  local base sid
  sid="${QR_PREFIXO_SID}$(_qr_rep $((256 - ${#QR_PREFIXO_SID})))"
  assert_igual 256 "${#sid}" 'fixture com 256'
  base=$(_qr_up_preparar "$sid")
  _qa_up_parada "$base" 2
  _qa_campos_ler "$(_qa_registro "$base")"
  assert_igual "$sid" "${QA_C[6]}" 'registro com session_id de 256'
  _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "retoma: $DBX_ERRO"
  assert_igual 1 "$(_qa_conta "$base" '^files/upload_session/start ')" 'sem sessao nova'
}

teste_qa_b03_session_id_de_257_caracteres_nao_vira_registro() {
  local base sid
  sid="${QR_PREFIXO_SID}$(_qr_rep $((257 - ${#QR_PREFIXO_SID})))"
  assert_igual 257 "${#sid}" 'fixture com 257'
  base=$(_qr_up_preparar "$sid")
  _qa_roteiro "$base" files/upload_session/append_v2 2 SINAL:TERM
  _qa_up "$base"
  assert_igual 14 "$DBX_ESTADO" "sinal: 14 ($DBX_ERRO)"
  assert_igual 0 "$(_qa_registros "$base")" 'session_id fora do limite nao e gravado'
}

# ===========================================================================
# B2. sync --receber: cursor de comprimento realista e fronteiras
# ===========================================================================

# _qr_cursor <comprimento> — cursor com prefixo sentinela, alfabeto do protocolo.
_qr_cursor() {
  local n=$1 s
  s="${Q_SENT}$(_qr_rep $((n - ${#Q_SENT})))"
  printf '%s' "${s:0:n}"
}

# _qr_primeira <cursor> — primeira execucao real com esse cursor.
_qr_primeira() {
  _q_cen
  _q_base
  _q_servidor "$1" "${Q_BASE[@]}"
  _q_rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "primeira execucao: $ERRO"
}

_qr_cursor_gravado_e_reaproveitado() { # <comprimento>
  local c novo
  c=$(_qr_cursor "$1")
  assert_igual "$1" "${#c}" 'fixture com o comprimento pedido'
  _qr_primeira "$c"
  _q_registro
  [[ -n $Q_REG ]] || _harness_falhar "cursor de $1 caracteres deveria ser gravado em cursor-*"
  novo="${Q_SENT}N$1"
  _q_zerar
  _q_delta "$c" "$novo"
  _q_rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "segunda execucao: $ERRO"
  _q_valor varredura
  assert_igual incremental "$Q_V" 'a segunda execucao e incremental, com o cursor gravado'
  _q_contar files/list_folder/continue
  assert_igual 1 "$Q_CONT" 'o continue foi chamado com o cursor gravado'
  _q_contar files/list_folder '*"recursive":true*'
  assert_igual 0 "$Q_CONT" 'nenhuma varredura completa'
}

teste_qa_c01_cursor_de_300_caracteres_e_gravado_e_reaproveitado() { _qr_cursor_gravado_e_reaproveitado 300; }
teste_qa_c02_cursor_de_2000_caracteres_e_gravado_e_reaproveitado() { _qr_cursor_gravado_e_reaproveitado 2000; }
teste_qa_c03_cursor_de_8192_caracteres_e_aceito() { _qr_cursor_gravado_e_reaproveitado 8192; }

teste_qa_c04_cursor_de_8193_caracteres_nao_e_gravado_e_a_execucao_segue() {
  _qr_primeira "$(_qr_cursor 8193)"
  _q_registro
  assert_igual '' "$Q_REG" 'cursor acima do teto nao vira registro'
  assert_contem 'a.txt' "$(cd "$B/l" && printf '%s ' *)" 'a execucao baixou os arquivos mesmo assim'
}

teste_qa_c05_cursor_com_caractere_fora_do_alfabeto_nao_e_gravado() {
  _qr_primeira "${Q_SENT}ab cd"
  _q_registro
  assert_igual '' "$Q_REG" 'espaco no cursor: sem registro'
}

teste_qa_c06_assinatura_aceita_256_e_recusa_257_e_vazia() {
  local d r
  d=$(mktemp -d "$DBX_TESTES_TMP/qr-ctx.XXXXXX")
  mkdir -p "$d/l"
  _ctx() { # <assinatura>
    env -i PATH="$PATH" HOME="$d" XDG_STATE_HOME="$d/estado" bash -c \
      '. "$1/lib/errors.sh"; . "$1/lib/config.sh"; . "$1/lib/state.sh"; dbx_state_cursor_contexto cred-0123456789abcdef0123456789abcdef dbid:C "$2" /r "$3"' \
      _ "$DBX_HARNESS_RAIZ" "$d/l" "$1" >/dev/null 2>&1
  }
  _ctx "$(_qr_rep 256)"
  r=$?
  assert_igual 0 "$r" 'assinatura de 256 aceita'
  _ctx "$(_qr_rep 257)"
  r=$?
  assert_diferente 0 "$r" 'assinatura de 257 recusada'
  _ctx ''
  r=$?
  assert_diferente 0 "$r" 'assinatura vazia recusada'
  _ctx 'a b'
  r=$?
  assert_diferente 0 "$r" 'assinatura fora do alfabeto recusada'
}

# ===========================================================================
# C. Mutacao: a regex volta a {1,N>255} e a auditoria tem de reprovar
# ===========================================================================

# _qr_copia — copia do codigo auditado, em QR_COPIA.
_qr_copia() {
  QR_COPIA=$(mktemp -d "$DBX_TESTES_TMP/qr-mut.XXXXXX")
  cp -R "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands" "$DBX_HARNESS_RAIZ/bin" \
    "$DBX_HARNESS_RAIZ/install.sh" "$DBX_HARNESS_RAIZ/uninstall.sh" "$QR_COPIA/"
}

teste_qa_m00_a_copia_sem_mutacao_passa_na_auditoria() {
  _qr_copia
  assert_igual '' "$(_qr_auditar "$QR_COPIA")" 'controle da mutacao'
}

teste_qa_m01_cursor_volta_a_1_8192_e_a_auditoria_reprova() {
  local r
  _qr_copia
  sed -i "s|^readonly DBX_STATE_CURSOR_RE_CURSOR=.*|readonly DBX_STATE_CURSOR_RE_CURSOR='^[A-Za-z0-9_=+/.-]{1,8192}\$'|" "$QR_COPIA/lib/state.sh"
  r=$(_qr_auditar "$QR_COPIA")
  assert_contem 'lib/state.sh' "$r" 'mutante {1,8192} detectado'
  assert_contem '{1,8192}' "$r" 'linha do mutante'
}

teste_qa_m02_assinatura_volta_a_1_256_e_a_auditoria_reprova() {
  local r
  _qr_copia
  sed -i "s|^readonly DBX_STATE_CURSOR_RE_ASSINATURA=.*|readonly DBX_STATE_CURSOR_RE_ASSINATURA='^[A-Za-z0-9_;=.-]{1,256}\$'|" "$QR_COPIA/lib/state.sh"
  r=$(_qr_auditar "$QR_COPIA")
  assert_contem '{1,256}' "$r" 'mutante {1,256} detectado'
}

teste_qa_m03_session_id_volta_a_1_256_e_a_auditoria_reprova() {
  local r
  _qr_copia
  sed -i 's|\[\[ \${c\[6\]} =~ \^\[A-Za-z0-9:_-\]+\$ && \${#c\[6\]} -le 256 &&|[[ ${c[6]} =~ ^[A-Za-z0-9:_-]{1,256}$ \&\&|' "$QR_COPIA/lib/state.sh"
  r=$(_qr_auditar "$QR_COPIA")
  assert_contem 'lib/state.sh' "$r" 'mutante do session_id detectado'
  assert_contem '{1,256}' "$r" 'linha do session_id'
}

teste_qa_m04_o_mutante_so_aparece_na_auditoria_e_nao_no_comportamento_em_linux() {
  # Documenta o limite do comportamento: o regcomp do glibc aceita {1,8192}.
  # Por isso a protecao de regressao e a auditoria (A), nao os casos B.
  local ok=nao
  [[ ${QR_CURSOR_8192:-$(_qr_rep 8192)} =~ ^[A-Za-z0-9_=+/.-]{1,8192}$ ]] && ok=sim
  assert_igual sim "$ok" 'glibc aceita a regex longa: so a auditoria enxerga o defeito do FreeBSD'
}

teste_qa_m05_mutante_em_grep_e_sed_tambem_reprova() {
  local r
  _qr_copia
  printf '%s\n' "grep -E '^[a-z]{1,300}\$' arquivo" "sed -E 's/x{1,400}//' arquivo" >>"$QR_COPIA/lib/state.sh"
  r=$(_qr_auditar "$QR_COPIA")
  assert_contem "grep -E '^[a-z]{1,300}" "$r" 'grep'
  assert_contem 'sed -E' "$r" 'sed'
}

harness_executar "$@"
