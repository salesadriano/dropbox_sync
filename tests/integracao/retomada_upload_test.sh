#!/usr/bin/env bash
# Testes ponta a ponta da retomada de UPLOAD entre execucoes (fase 7a, F-03;
# RF-101 a RF-109; TC-RMU-01..16, TC-RME-02, 12, 14, TC-RMO-01..03, 05..11,
# TC-RMC-01, 04, 05, TC-RMS-01..06; DIV-171 a DIV-190).
#
# O DUPLO DE `curl` E UM SERVIDOR DE SESSAO COM ESTADO: cada `start` cria uma
# sessao em `sess/<id>` com o deslocamento confirmado e o SHA-256 de cada parte
# recebida, e o `finish` devolve o `content_hash` calculado sobre as partes que
# o duplo de fato recebeu. O resumo final so confere se as partes chegaram
# certas e na ordem; nenhum caso confere `content_hash` contra si mesmo.
#
# Roteiro por chamada em `roteiro`: `<endpoint> <ordinal> <acao>`, com o
# ordinal contado por endpoint desde o inicio do caso (todas as execucoes).
# Acoes: `SINAL:<NOME>` (manda o sinal ao `dbx` antes de processar), `KILL`
# (`kill -9` antes de processar), `ACEITA_E_KILL` (processa e entao `kill -9`:
# a parte chegou e a resposta se perdeu), `NOT_FOUND`, `CLOSED`, `TOO_LARGE`,
# `OFFSET:<n|abc>` (recusa por `incorrect_offset` com esse `correct_offset`),
# `LOOKUP_NOT_FOUND` e `HASH_ERRADO` (no `finish`), `CRESCE` (acrescenta um
# byte a origem e processa). Cada `append_v2` registra em `registros` o
# confirmado e a parte em voo do registro de retomada naquele instante.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e os roteiros chegam sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC_PADRAO="$DBX_HARNESS_RAIZ/bin/dbx"
readonly PARTE=4194304
readonly TAMANHO=$((157286400 + 3))
readonly SENTINELA_REFRESH='RT_SENTINELA_refresh_u6v7'
readonly SENTINELA_SEGREDO='AS_SENTINELA_segredo_u8v9'
readonly SENTINELA_CHAVE='AK_SENTINELA_chave_u0v1'
readonly SENTINELA_TOKEN='sl.SENTINELA_token_curto_u2v3'
readonly SENTINELA_SESSAO='SESSAOSENTINELA'

# _fixture_grande — 150 MiB + 3 bytes, esparso, com um marcador distinto no
# inicio de cada bloco de 4 MiB (partes trocadas mudam o `content_hash`).
# Gerado uma vez por execucao do arquivo; cada caso usa uma copia.
_fixture_grande() {
  local arquivo="$DBX_TESTES_TMP/retomada-up-grande.bin" i
  if [[ ! -e $arquivo ]]; then
    truncate -s "$TAMANHO" "$arquivo"
    for ((i = 0; i * PARTE < TAMANHO; i++)); do
      printf 'bloco-%03d' "$i" | dd of="$arquivo" bs=1 seek=$((i * PARTE)) conv=notrunc status=none
    done
  fi
  printf '%s' "$arquivo"
}

# _ambiente — credencial, origem grande, duplos de `curl` e `sleep`.
_ambiente() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/rup.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/tmp" "$base/trabalho" "$base/sess"
  chmod 700 "$base/config/dbx"
  printf '{"versao":1,"app_key":"%s","app_secret":"%s","refresh_token":"%s","raiz_remota":"/"}' \
    "$SENTINELA_CHAVE" "$SENTINELA_SEGREDO" "$SENTINELA_REFRESH" >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  cp --sparse=always "$(_fixture_grande)" "$base/trabalho/grande.iso"
  touch -d '1 hour ago' "$base/trabalho/grande.iso"
  : >"$base/roteiro"
  {
    printf '#!%s\n' "$BASH"
    printf 'base=%q\n' "$base"
    printf 'token=%q\n' "$SENTINELA_TOKEN"
    printf 'sentinela=%q\n' "$SENTINELA_SESSAO"
  } >"$base/bin/curl"
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
corpo=''
[[ -n $dados && -r $dados && $url != *content.dropboxapi.com* ]] && IFS= read -r -d '' corpo <"$dados"
ep=${url#https://*/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
printf '%s\n' "$ep" >>"$base/ordinais"
n=0
while IFS= read -r l; do [[ $l == "$ep" ]] && n=$((n + 1)); done <"$base/ordinais"
printf '%s %s %s\n' "$ep" "$arg" "$corpo" >>"$base/chamadas"
acao=''
while read -r e k a; do
  [[ $e == "$ep" && $k == "$n" ]] && acao=$a
done <"$base/roteiro"
pid=$(<"$base/pid")
case $acao in
  SINAL:*) kill -s "${acao#SINAL:}" "$pid"; sleep 5; exit 7 ;;
  KILL) : >"$base/morto"; kill -9 "$pid"; exit 7 ;;
  CRESCE) printf 'x' >>"$base/trabalho/grande.iso" ;;
esac
codigo=200 resposta='{}'
erro() { codigo=409; resposta="{\"error_summary\":\"$1\",\"error\":{\".tag\":\"${1%%/*}\"}}"; }
sid=''; off=''
[[ $arg =~ \"session_id\":\"([^\"]*)\" ]] && sid=${BASH_REMATCH[1]}
[[ $arg =~ \"offset\":([0-9]+) ]] && off=${BASH_REMATCH[1]}
registro() {
  local r c=() f
  for r in "$base"/estado/dbx/retomada-*; do
    [[ -f $r ]] || continue
    c=()
    while IFS= read -r -d '' f; do c+=("$f"); done <"$r"
    printf '%s %s %s %s\n' "$off" "${c[7]:-x}" "${c[8]:-x}" "${c[9]:0:8}" >>"$base/registros"
  done
}
recebe() { # anexa o corpo a sessao
  local tam h
  tam=$(wc -c <"$dados")
  if [[ $tam -gt 0 ]]; then
    h=$(sha256sum <"$dados"); h=${h%% *}
    printf '%s\n' "$h" >>"$base/sess/$sid/blocos"
  fi
  printf '%s %s %s\n' "$sid" "$off" "$tam" >>"$base/anexos"
  printf '%s' "$((off + tam))" >"$base/sess/$sid/offset"
}
case $ep in
  oauth2/token) resposta="{\"access_token\":\"$token\",\"token_type\":\"bearer\",\"expires_in\":14400}" ;;
  files/get_metadata)
    if [[ -r $base/publicado ]]; then
      resposta="{\".tag\":\"file\",\"name\":\"grande.iso\",\"path_display\":\"/Grande.iso\",\"rev\":\"0123456789a\",\"size\":1,\"content_hash\":\"$(<"$base/publicado")\"}"
    else
      erro 'path/not_found/'
    fi
    ;;
  users/get_space_usage) resposta='{"used":0,"allocation":{".tag":"individual","allocated":1000000000000}}' ;;
  files/upload) resposta='{".tag":"file","name":"x","path_display":"/X","id":"id:2","rev":"0123456789b","size":1,"server_modified":"2026-01-01T00:00:00Z","client_modified":"2026-01-01T00:00:00Z"}' ;;
  files/list_folder) erro 'path/not_found/' ;;
  files/create_folder_v2) resposta='{"metadata":{".tag":"folder","name":"Pasta","path_display":"/Pasta","id":"id:3"}}' ;;
  files/upload_session/start)
    sid="$sentinela-$n"
    mkdir -p "$base/sess/$sid"
    printf 0 >"$base/sess/$sid/offset"
    : >"$base/sess/$sid/blocos"
    resposta="{\"session_id\":\"$sid\"}"
    ;;
  files/upload_session/append_v2)
    registro
    if [[ ! -d $base/sess/$sid ]]; then erro 'not_found/'
    elif [[ -e $base/sess/$sid/fechada ]]; then erro 'closed/'
    else
      case $acao in
        NOT_FOUND) erro 'not_found/' ;;
        CLOSED) erro 'closed/' ;;
        TOO_LARGE) erro 'too_large/' ;;
        OFFSET:*) codigo=409; resposta="{\"error_summary\":\"incorrect_offset/\",\"error\":{\".tag\":\"incorrect_offset\",\"correct_offset\":\"${acao#OFFSET:}\"}}"
          [[ ${acao#OFFSET:} =~ ^[0-9]+$ ]] && resposta="{\"error_summary\":\"incorrect_offset/\",\"error\":{\".tag\":\"incorrect_offset\",\"correct_offset\":${acao#OFFSET:}}}" ;;
        *)
          srv=$(<"$base/sess/$sid/offset")
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
    if [[ ! -d $base/sess/$sid ]]; then erro 'lookup_failed/not_found/'
    elif [[ -e $base/sess/$sid/fechada ]]; then erro 'lookup_failed/closed/'
    elif [[ $acao == LOOKUP_NOT_FOUND ]]; then erro 'lookup_failed/not_found/'
    elif [[ $acao == TOO_LARGE ]]; then erro 'lookup_failed/too_large/'
    else
      srv=$(<"$base/sess/$sid/offset")
      if [[ $off != "$srv" ]]; then
        codigo=409; resposta="{\"error_summary\":\"lookup_failed/incorrect_offset/\",\"error\":{\".tag\":\"lookup_failed\",\"lookup_failed\":{\".tag\":\"incorrect_offset\",\"correct_offset\":$srv}}}"
      else
        recebe
        : >"$base/sess/$sid/fechada"
        : >"$base/cadeia"
        while IFS= read -r h; do
          esc=''
          for ((i = 0; i < 64; i += 2)); do esc+="\\x${h:i:2}"; done
          printf '%b' "$esc" >>"$base/cadeia"
        done <"$base/sess/$sid/blocos"
        ch=$(sha256sum <"$base/cadeia"); ch=${ch%% *}
        [[ $acao == HASH_ERRADO ]] && printf -v ch '%064d' 0
        printf '%s' "$ch" >"$base/publicado"
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

# _rodar <base> <argumentos...> — sem terminal, com teto de tempo, num grupo de
# processos proprio (o duplo manda sinais ao `dbx` pelo pid). `DBX_T_EXEC`
# troca o produto (copia mutante); `DBX_T_PATH` antepoe duplos extras.
_rodar() {
  local base=$1
  shift
  (
    cd "$base/trabalho" || exit 99
    env -i PATH="${DBX_T_PATH:+$DBX_T_PATH:}$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" ${DBX_T_UMASK:+DBX_T_UMASK="$DBX_T_UMASK"} \
      DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout -k 2 "${DBX_T_TETO:-120}" setsid -w bash -c 'printf "%s" "$$" >"$1/pid"; shift; exec bash "$@"' _ \
      "$base" "${DBX_T_EXEC:-$DBX_EXEC_PADRAO}" "$@" </dev/null >"$base/out" 2>"$base/err"
  ) 2>/dev/null
  DBX_ESTADO=$?
  # `kill -9` mandado pelo duplo (marca `morto`) nao e pendura.
  if [[ $DBX_ESTADO -eq 137 && -e $base/morto ]]; then
    rm -f "$base/morto"
  elif [[ $DBX_ESTADO -eq 124 || $DBX_ESTADO -eq 137 ]]; then
    _harness_falhar "o comando pendurou ($DBX_ESTADO): $*"
  fi
  DBX_SAIDA='' DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_up() { _rodar "$1" upload "${@:2}" grande.iso /Grande.iso; } # <base> [opcoes...]
_conta() { _harness_contar "$2" "$1/chamadas"; }              # <base> <padrao>
_roteiro() { printf '%s %s %s\n' "$2" "$3" "$4" >>"$1/roteiro"; } # <base> <ep> <ordinal> <acao>
_registros() { # <base> — registros de retomada presentes
  local r n=0
  for r in "$1"/estado/dbx/retomada-*; do [[ -e $r ]] && n=$((n + 1)); done
  printf '%s' "$n"
}
_travas() {
  local r n=0
  for r in "$1"/estado/dbx/trava-*; do [[ -e $r ]] && n=$((n + 1)); done
  printf '%s' "$n"
}
_residuo() { # entradas que sobraram no TMPDIR privado
  local e lista=''
  for e in "$1"/tmp/* "$1"/tmp/.[!.]*; do [[ -e $e ]] && lista+=" ${e##*/}"; done
  printf '%s' "$lista"
}
# _sessoes_em_anexos <base> — sessoes distintas que receberam parte.
_offsets_de() { # <base> <sessao> — deslocamentos recebidos pela sessao, em ordem
  local s o t lista=''
  while read -r s o t; do [[ $s == "$2" ]] && lista+="$o "; done <"$1/anexos"
  printf '%s' "$lista"
}
_copia_mutante() {
  local copia
  copia=$(mktemp -d "$DBX_TESTES_TMP/mutante.XXXXXX")
  cp -R "$DBX_HARNESS_RAIZ/bin" "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands" "$copia/"
  while [[ $# -ge 2 ]]; do
    cp "$copia/$1" "$copia/$1.orig"
    sed -e "$2" "$copia/$1.orig" >"$copia/$1"
    cmp -s "$copia/$1" "$copia/$1.orig" && _harness_falhar "a mutacao nao alterou $1: $2"
    rm -f "$copia/$1.orig"
    shift 2
  done
  printf '%s' "$copia/bin/dbx"
}

# _interrompida_na_parte <base> <k> — primeira execucao parada por TERM no
# k-esimo `append_v2` (antes de o servidor processa-lo): k-1 partes confirmadas.
_interrompida_na_parte() {
  _roteiro "$1" files/upload_session/append_v2 "$2" SINAL:TERM
  _up "$1"
  assert_igual 14 "$DBX_ESTADO" "sinal: operacao nao concluida ($DBX_ERRO)"
  assert_igual 1 "$(_registros "$1")" 'o registro fica para a proxima execucao'
}

# _stat_forjado <base> — duplo de `stat` que devolve, para a origem, a
# identidade lida AGORA (antes de o teste altera-la).
_stat_forjado() {
  local base=$1 real
  real=$(command -v stat)
  mkdir -p "$base/forja"
  stat -c "%s"$'\t''%Y|%y|%z|%d|%i|%s' -- "$base/trabalho/grande.iso" >"$base/forja/identidade"
  {
    printf '#!%s\n' "$BASH"
    printf 'real=%q\nalvo=%q\nforja=%q\n' "$real" "$base/trabalho/grande.iso" "$base/forja/identidade"
    printf '%s\n' 'ultimo=${!#}'
    printf '%s\n' 'if [[ ${ultimo##*/} == "${alvo##*/}" && $* == *"%Y|%y|%z|%d|%i|%s"* ]]; then cat "$forja"; exit 0; fi'
    printf '%s\n' 'exec "$real" "$@"'
  } >"$base/forja/stat"
  chmod +x "$base/forja/stat"
}

_altera_byte() { # <arquivo> <posicao>
  printf 'Z' | dd of="$1" bs=1 seek="$2" conv=notrunc status=none
}

# ---------------------------------------------------------------------------
# RF-103: retomada, ordem da gravacao e conferencia final (TC-RMU-01, 02, 06, 15, 16)
# ---------------------------------------------------------------------------

teste_rmu01_rmu02_interrompido_na_parte_4_retoma_do_confirmado_sem_reenviar() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  assert_igual 1 "$(_conta "$base" '^files/upload_session/start ')" 'um start'
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "retomado: $DBX_ERRO"
  assert_igual 1 "$(_conta "$base" '^files/upload_session/start ')" 'a segunda execucao nao chama start'
  local sessao="$SENTINELA_SESSAO-1"
  local esperados='' i
  for ((i = 0; i < 37; i++)); do esperados+="$((i * PARTE)) "; done
  esperados+="$((37 * PARTE)) "
  assert_igual "$esperados" "$(_offsets_de "$base" "$sessao")" 'cada parte uma vez, na ordem: nada antes do confirmado reenviado'
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'content_hash do arquivo inteiro confere'
  assert_contem 'retomada=sim' "$DBX_SAIDA" 'campo retomada'
  assert_contem "retomado_de=$((3 * PARTE))" "$DBX_SAIDA" 'retomado do confirmado'
  assert_igual 0 "$(_registros "$base")" 'registro removido depois do finish'
  assert_igual 0 "$(_travas "$base")" 'trava liberada'
  # TC-RMU-02: a cada append, o registro ja descrevia exatamente aquela parte,
  # e o confirmado so tinha valor confirmado pelo servidor.
  local off conf voo ok=0
  while read -r off conf voo _; do
    [[ $conf == "$off" && $voo == "$PARTE" ]] || _harness_falhar 'registro fora de ordem no append' "$off $conf $voo"
    ok=$((ok + 1))
  done <"$base/registros"
  assert_igual 37 "$ok" 'um registro conferido por append processado (3 na primeira, 34 na segunda)'
  # TC-RMU-16: nenhum content_hash por chamada.
  assert_igual 0 "$(_conta "$base" '^files/upload_session/[af].*content_hash')" 'sem content_hash no append_v2 nem no finish'
}

teste_rmu15_na_retomada_o_arquivo_e_lido_uma_vez() {
  local base real
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  real=$(command -v head)
  mkdir -p "$base/conta"
  {
    printf '#!%s\n' "$BASH"
    printf 'real=%q\nlog=%q\n' "$real" "$base/conta/lidos"
    printf '%s\n' '[[ $(readlink /proc/$$/fd/0) == */grande.iso ]] || exec "$real" "$@"'
    printf '%s\n' 't=$(mktemp)' '"$real" "$@" >"$t"; e=$?' 'wc -c <"$t" >>"$log"' 'cat "$t"; rm -f "$t"; exit $e'
  } >"$base/conta/head"
  chmod +x "$base/conta/head"
  DBX_T_PATH="$base/conta" _up "$base"
  assert_igual 0 "$DBX_ESTADO" "retomado: $DBX_ERRO"
  local total=0 v
  while read -r v; do total=$((total + v)); done <"$base/conta/lidos"
  assert_igual "$TAMANHO" "$total" 'prefixo relido para o acumulador e o resto: o arquivo uma vez'
}

# ---------------------------------------------------------------------------
# RF-103(c): o arquivo local nao mudou (TC-RMU-04, 05; C1)
# ---------------------------------------------------------------------------

teste_rmu04_ctime_diferente_com_mtime_restaurado_recomeca_do_zero() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  touch -r "$base/trabalho/grande.iso" "$base/ref"
  _altera_byte "$base/trabalho/grande.iso" 100
  touch -r "$base/ref" "$base/trabalho/grande.iso"
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "do zero: $DBX_ERRO"
  assert_contem 'arquivo local mudou desde a interrupcao' "$DBX_ERRO" 'aviso'
  assert_igual 2 "$(_conta "$base" '^files/upload_session/start ')" 'sessao nova'
  assert_igual "0 $PARTE $((2 * PARTE)) " "$(_offsets_de "$base" "$SENTINELA_SESSAO-1")" 'nada mais na sessao antiga'
  assert_contem 'retomada=recomecada' "$DBX_SAIDA" 'recomecada'
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'o arquivo novo confere'
}

_prefixo_alterado_com_stat_forjado() { # <base> — byte do prefixo trocado, stat igual
  _stat_forjado "$1"
  _altera_byte "$1/trabalho/grande.iso" $((PARTE + 7))
}

teste_rmu05_prefixo_alterado_com_stat_forjado_reprova_antes_do_primeiro_append() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  _prefixo_alterado_com_stat_forjado "$base"
  DBX_T_PATH="$base/forja" _up "$base"
  assert_igual 0 "$DBX_ESTADO" "do zero: $DBX_ERRO"
  assert_contem 'arquivo local mudou desde a interrupcao' "$DBX_ERRO" 'o prefixo_hash reprova'
  assert_igual "0 $PARTE $((2 * PARTE)) " "$(_offsets_de "$base" "$SENTINELA_SESSAO-1")" 'nenhum byte do sufixo na sessao antiga'
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'conteudo novo, sessao nova, confere'
}

teste_rmu05_mutante_que_retoma_so_pela_identidade_reprova() {
  local base mutante
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  _prefixo_alterado_com_stat_forjado "$base"
  mutante=$(_copia_mutante lib/transfer.sh 's/|| \$_DBX_TRANSFER_RET_PREFIXO != "\$prefixo" ]]/]]/')
  DBX_T_EXEC=$mutante DBX_T_PATH="$base/forja" _up "$base"
  [[ $(_offsets_de "$base" "$SENTINELA_SESSAO-1") != "0 $PARTE $((2 * PARTE)) " ]] ||
    _harness_falhar 'o mutante deveria anexar o sufixo na sessao antiga'
  assert_diferente 0 "$DBX_ESTADO" 'sem a barreira do prefixo, o resumo final acusa'
}

# ---------------------------------------------------------------------------
# RF-103(b): reconciliacao com o servidor (TC-RMU-06..08; DIV-172)
# ---------------------------------------------------------------------------

# _resposta_perdida <base> — a 4a parte chega ao servidor e a resposta se perde
# (`kill -9` depois de processar): servidor em 16 MiB, registro em 12 MiB com a
# parte em voo de 4 MiB.
_resposta_perdida() {
  _roteiro "$1" files/upload_session/append_v2 4 ACEITA_E_KILL
  _up "$1"
  assert_igual 1 "$(_registros "$1")" 'registro deixado pelo kill -9'
}

teste_rmu07_servidor_no_confirmado_mais_a_parte_em_voo_com_sha_igual_segue() {
  local base
  base=$(_ambiente)
  _resposta_perdida "$base"
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "retomado: $DBX_ERRO"
  assert_igual 1 "$(_conta "$base" '^files/upload_session/start ')" 'sem start'
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'confere'
  assert_contem 'retomada=sim' "$DBX_SAIDA" 'retomada'
  assert_contem 'trava orfa' "$DBX_ERRO" 'a trava do kill -9 e retomada com aviso'
}

_voo_alterado() { # <base> — byte da parte em voo trocado, stat igual
  _stat_forjado "$1"
  _altera_byte "$1/trabalho/grande.iso" $((3 * PARTE + 9))
}

teste_rmu07_parte_em_voo_relida_diferente_recomeca_do_zero() {
  local base
  base=$(_ambiente)
  _resposta_perdida "$base"
  _voo_alterado "$base"
  DBX_T_PATH="$base/forja" _up "$base"
  assert_igual 0 "$DBX_ESTADO" "do zero: $DBX_ERRO"
  assert_contem 'deslocamento que nao confere' "$DBX_ERRO" 'aviso do descarte'
  assert_igual 2 "$(_conta "$base" '^files/upload_session/start ')" 'sessao nova'
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'a sessao nova confere'
  assert_contem 'retomada=recomecada' "$DBX_SAIDA" 'recomecada'
}

teste_rmu07_mutante_que_aceita_o_avanco_sem_conferir_a_parte_reprova() {
  local base mutante
  base=$(_ambiente)
  _resposta_perdida "$base"
  _voo_alterado "$base"
  mutante=$(_copia_mutante lib/transfer.sh 's/)) \&\& \[\[ \$sha == "\$_DBX_TRANSFER_RET_VOO_H" \]\]; then/)); then/')
  DBX_T_EXEC=$mutante DBX_T_PATH="$base/forja" _up "$base"
  assert_igual 11 "$DBX_ESTADO" 'sem conferir a parte em voo, o finish publica conteudo misturado e o resumo acusa'
}

teste_rmu06_rmu08_correct_offset_fora_do_aceito_descarta_e_recomeca_do_zero() {
  local base valor
  # Igual ao confirmado: aceito (a mesma parte de novo). Os demais: descarte.
  for valor in $((3 * PARTE)) $((2 * PARTE)) $((5 * PARTE)) abc $((TAMANHO + PARTE)); do
    base=$(_ambiente)
    _interrompida_na_parte "$base" 4
    _roteiro "$base" files/upload_session/append_v2 5 "OFFSET:$valor"
    _up "$base"
    assert_igual 0 "$DBX_ESTADO" "correct_offset $valor: $DBX_ERRO"
    if [[ $valor == $((3 * PARTE)) ]]; then
      assert_igual 1 "$(_conta "$base" '^files/upload_session/start ')" "$valor: o confirmado e aceito"
      assert_contem 'retomada=sim' "$DBX_SAIDA" "$valor: retomada"
    else
      assert_igual 2 "$(_conta "$base" '^files/upload_session/start ')" "$valor: recomeco do zero"
      assert_contem 'retomada=recomecada' "$DBX_SAIDA" "$valor: recomecada"
      assert_igual 0 "$(_conta "$base" "^files/upload_session/finish .*$SENTINELA_SESSAO-1\"")" "$valor: nunca finish da sessao antiga"
    fi
    assert_contem 'integridade=conferida' "$DBX_SAIDA" "$valor: confere"
  done
}

teste_rmu08_confirmado_mais_4_mib_sem_parte_em_voo_gravada_recomeca() {
  local base r
  base=$(_ambiente)
  _resposta_perdida "$base"
  # O registro passa a dizer "sem parte em voo" (tamanho 0): o avanco de 4 MiB
  # do servidor nao tem o que conferir e nao e aceito.
  local -a c=()
  local f
  for r in "$base"/estado/dbx/retomada-*; do
    c=()
    while IFS= read -r -d '' f; do c+=("$f"); done <"$r"
    c[8]=0
    c[9]=-
    printf '%s\0' "${c[@]}" >"$r"
  done
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "do zero: $DBX_ERRO"
  assert_igual 2 "$(_conta "$base" '^files/upload_session/start ')" 'recomeco do zero'
}

# ---------------------------------------------------------------------------
# RF-103(f): sessao expirada ou fechada (TC-RMU-09..11; DIV-171)
# ---------------------------------------------------------------------------

teste_rmu09_not_found_no_primeiro_append_recomeca_uma_vez_sem_codigo_4() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  _roteiro "$base" files/upload_session/append_v2 5 NOT_FOUND
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "recomecado: $DBX_ERRO"
  assert_contem 'sessao de envio expirada no servidor; recomecando' "$DBX_ERRO" 'aviso'
  assert_igual 2 "$(_conta "$base" '^files/upload_session/start ')" 'uma sessao nova'
  assert_contem 'retomada=recomecada' "$DBX_SAIDA" 'recomecada'
  assert_igual 0 "$(_registros "$base")" 'registro removido no fim'
}

teste_rmu09_segundo_not_found_na_sessao_nova_tem_a_classe_de_hoje() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  _roteiro "$base" files/upload_session/append_v2 5 NOT_FOUND
  _roteiro "$base" files/upload_session/append_v2 6 NOT_FOUND
  _up "$base"
  assert_igual 4 "$DBX_ESTADO" 'o recomeco e unico: a segunda recusa e a de hoje'
  assert_igual 2 "$(_conta "$base" '^files/upload_session/start ')" 'nao recomeca de novo'
}

teste_rmu10_closed_no_append_e_lookup_failed_no_finish_recomecam() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  _roteiro "$base" files/upload_session/append_v2 5 CLOSED
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "closed: $DBX_ERRO"
  assert_igual 2 "$(_conta "$base" '^files/upload_session/start ')" 'closed: recomeca'
  base=$(_ambiente)
  _interrompida_na_parte "$base" 37
  _roteiro "$base" files/upload_session/finish 1 LOOKUP_NOT_FOUND
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "lookup_failed: $DBX_ERRO"
  assert_contem 'sessao de envio expirada' "$DBX_ERRO" 'aviso'
  assert_igual 2 "$(_conta "$base" '^files/upload_session/start ')" 'lookup_failed: recomeca'
  assert_igual 2 "$(_conta "$base" '^files/upload_session/finish ')" 'dois finish, o segundo na sessao nova'
}

teste_rmu11_too_large_e_definitivo_com_codigo_10() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  _roteiro "$base" files/upload_session/append_v2 5 TOO_LARGE
  _up "$base"
  assert_igual 10 "$DBX_ESTADO" 'too_large: resposta incoerente'
  assert_igual 0 "$(_registros "$base")" 'registro removido'
}

# ---------------------------------------------------------------------------
# RF-103(d)(e)(g) (TC-RMU-12..14)
# ---------------------------------------------------------------------------

teste_rmu12_finish_leva_o_modo_desta_execucao() {
  local base
  base=$(_ambiente)
  _roteiro "$base" files/upload_session/append_v2 4 SINAL:TERM
  _up "$base" --modo add
  _up "$base" --modo overwrite
  assert_igual 0 "$DBX_ESTADO" "retomado: $DBX_ERRO"
  assert_contem 'retomada=sim' "$DBX_SAIDA" 'retomou'
  assert_igual 1 "$(_conta "$base" '^files/upload_session/finish .*"mode":"overwrite"')" 'finish com overwrite'
}

teste_rmu13_hash_do_finish_divergente_sai_11_sem_reenvio_nem_exclusao() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  _roteiro "$base" files/upload_session/finish 1 HASH_ERRADO
  _up "$base"
  assert_igual 11 "$DBX_ESTADO" 'integridade'
  assert_contem 'nao considere o item integro' "$DBX_ERRO" 'mensagem de hoje'
  assert_igual 0 "$(_registros "$base")" 'registro removido'
  assert_igual 1 "$(_conta "$base" '^files/upload_session/start ')" 'nenhum start novo'
  assert_igual 0 "$(_conta "$base" 'delete')" 'nenhuma exclusao'
}

teste_rmu14_arquivo_que_cresce_durante_o_envio_retomado_aborta_e_remove_o_registro() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  _roteiro "$base" files/upload_session/append_v2 7 CRESCE
  _up "$base"
  assert_igual 14 "$DBX_ESTADO" 'nao concluida'
  assert_contem 'mudou de tamanho' "$DBX_ERRO" 'motivo'
  assert_igual 0 "$(_conta "$base" '^files/upload_session/finish ')" 'nenhum finish'
  assert_igual 0 "$(_registros "$base")" 'registro removido'
}

teste_rmu03_falha_ao_gravar_o_registro_segue_sem_retomada() {
  local base real
  base=$(_ambiente)
  real=$(command -v mktemp)
  mkdir -p "$base/mk"
  {
    printf '#!%s\n' "$BASH"
    printf 'real=%q\n' "$real"
    printf '%s\n' 'for a in "$@"; do [[ $a == */.retomada.* ]] && exit 1; done' 'exec "$real" "$@"'
  } >"$base/mk/mktemp"
  chmod +x "$base/mk/mktemp"
  DBX_T_PATH="$base/mk" _up "$base"
  assert_igual 0 "$DBX_ESTADO" "conclui: $DBX_ERRO"
  assert_contem 'sem retomada nesta execucao: o registro de retomada nao pode ser gravado' "$DBX_ERRO" 'aviso'
  assert_igual 1 "$(grep -c 'registro de retomada nao pode ser gravado' <<<"$DBX_ERRO")" 'um aviso so'
  assert_igual 0 "$(_registros "$base")" 'nenhum registro'
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'envio de hoje'
}

# ---------------------------------------------------------------------------
# RF-102: alcance e ordem (TC-RMO-01..03; C5)
# ---------------------------------------------------------------------------

teste_rmo01_rmo02_fora_do_alcance_nao_cria_nem_le_registro() {
  local base
  base=$(_ambiente)
  truncate -s 157286400 "$base/trabalho/exato.bin"
  _rodar "$base" upload exato.bin /Exato.bin
  assert_igual 0 "$DBX_ESTADO" "150 MiB exatos: $DBX_ERRO"
  assert_nao_contem 'retomada' "$DBX_SAIDA" 'saida de hoje'
  printf 'abc' >"$base/trabalho/pequeno.txt"
  _rodar "$base" upload - /Fluxo.bin
  assert_igual 0 "$DBX_ESTADO" "entrada padrao: $DBX_ERRO"
  assert_igual 0 "$(_registros "$base")" 'nenhum retomada-*'
  mkdir -p "$base/trabalho/pasta"
  cp --sparse=always "$base/trabalho/grande.iso" "$base/trabalho/pasta/grande.iso"
  _roteiro "$base" files/upload_session/append_v2 4 SINAL:TERM
  _rodar "$base" upload pasta /Pasta
  assert_igual 2 "$(_conta "$base" '^files/upload_session/start ')" 'a entrada padrao e o upload de pasta abriram sessao'
  assert_igual 0 "$(_registros "$base")" 'upload de pasta (sync --enviar) nao cria registro'
}

teste_rmo03_dispensa_por_content_hash_igual_remove_o_registro_sem_sessao() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  # O remoto ja tem o mesmo conteudo (por exemplo, publicado num finish cuja
  # resposta se perdeu): a dispensa de RF-60 vem antes da retomada.
  . "$DBX_HARNESS_RAIZ/lib/hash.sh"
  dbx_hash_publicar_arquivo "$base/trabalho/grande.iso"
  printf '%s' "$DBX_HASH_RESULTADO" >"$base/publicado"
  local antes
  antes=$(_conta "$base" '^files/upload_session/')
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "dispensado: $DBX_ERRO"
  assert_contem 'status=dispensado' "$DBX_SAIDA" 'dispensado'
  assert_igual "$antes" "$(_conta "$base" '^files/upload_session/')" 'nenhuma chamada upload_session'
  assert_igual 0 "$(_registros "$base")" 'o registro some'
}

teste_rmo03_rev_decide_antes_e_o_finish_leva_o_rev_desta_execucao() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  _up "$base" --rev 0123456789abc
  assert_igual 0 "$DBX_ESTADO" "retomado: $DBX_ERRO"
  assert_igual 1 "$(_conta "$base" '^files/upload_session/finish .*"update":"0123456789abc"')" 'finish com o rev desta execucao'
}

# ---------------------------------------------------------------------------
# RF-108: opcao, saida e avisos (TC-RMO-05..09, 11; TC-RME-02, 12, 14)
# ---------------------------------------------------------------------------

teste_rmo05_rmo06_sem_retomada_e_no_resume_nao_leem_nem_tocam_o_registro() {
  local base opcao copia
  for opcao in --sem-retomada --no-resume; do
    base=$(_ambiente)
    _interrompida_na_parte "$base" 4
    copia=$(cat "$base"/estado/dbx/retomada-* | od -An -tx1 | tr -d ' \n')
    _up "$base" "$opcao"
    assert_igual 0 "$DBX_ESTADO" "$opcao: $DBX_ERRO"
    assert_igual 2 "$(_conta "$base" '^files/upload_session/start ')" "$opcao: do zero, como antes"
    assert_igual "$copia" "$(cat "$base"/estado/dbx/retomada-* | od -An -tx1 | tr -d ' \n')" "$opcao: registro intacto"
    assert_nao_contem 'retomada' "$DBX_SAIDA" "$opcao: saida de antes da fase"
    assert_igual 0 "$(_travas "$base")" "$opcao: nenhuma trava"
  done
}

teste_rmo07_opcao_em_outro_comando_e_uso_invalido() {
  local base cmd
  base=$(_ambiente)
  mkdir -p "$base/trabalho/d"
  for cmd in 'sync --enviar --origem d --destino /D --sem-retomada' 'list / --sem-retomada' \
    'reter /Bk --padrao x --manter 1 --no-resume'; do
    # shellcheck disable=SC2086  # o comando e dividido de proposito
    _rodar "$base" $cmd
    assert_igual 2 "$DBX_ESTADO" "$cmd"
  done
}

teste_rmo08_campos_em_texto_json_e_null_e_resto_da_saida_igual() {
  local base
  base=$(_ambiente)
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "estruturada: $DBX_ERRO"
  assert_contem $'retomada=nao\nretomado_de=0' "$DBX_SAIDA" 'estruturada (fora de terminal) sem retomada'
  local sem
  sem=${DBX_SAIDA//$'retomada=nao\nretomado_de=0\n'/}
  rm -f "$base/publicado"
  _up "$base" --sem-retomada
  assert_igual "$sem" "$DBX_SAIDA" 'o resto da saida e o de antes'
  rm -f "$base/publicado"
  _rodar "$base" --json upload grande.iso /Grande.iso
  assert_contem $'retomada=nao\nretomado_de=0' "$DBX_SAIDA" 'json'
  rm -f "$base/publicado"
  _rodar "$base" --null upload grande.iso /Grande.iso
  local nul
  nul=$(tr '\0' '\n' <"$base/out")
  assert_contem $'retomada=nao\nretomado_de=0' "$nul" 'null'
  # Texto: so num terminal de verdade (`script`).
  command -v script >/dev/null 2>&1 || pular 'sem o utilitario script para um terminal'
  rm -f "$base/publicado"
  printf 'cd %q && exec env -i PATH=%q HOME=%q XDG_CONFIG_HOME=%q XDG_STATE_HOME=%q TMPDIR=%q bash %q upload grande.iso /Grande.iso 2>/dev/null\n' \
    "$base/trabalho" "$base/bin:$PATH" "$base" "$base/config" "$base/estado" "$base/tmp" "$DBX_EXEC_PADRAO" >"$base/texto.sh"
  printf '%s' "$$" >"$base/pid"
  timeout -k 2 120 script -qec "bash $base/texto.sh" /dev/null </dev/null >"$base/out_texto" 2>&1
  local texto
  texto=$(tr -d '\r' <"$base/out_texto")
  assert_contem $'retomada: nao\nretomado_de: 0' "$texto" 'texto'
}

teste_rme02_rmo09_sentinelas_e_session_id_fora_da_saida_e_do_registro() {
  local base r
  base=$(_ambiente)
  _roteiro "$base" files/upload_session/append_v2 4 SINAL:TERM
  _rodar "$base" --debug upload grande.iso /Grande.iso
  for r in "$base"/estado/dbx/retomada-*; do
    local bruto
    bruto=$(tr '\0' '\n' <"$r")
    assert_segredo_ausente "$SENTINELA_TOKEN" "$bruto" 'token fora do registro'
    assert_segredo_ausente "$SENTINELA_REFRESH" "$bruto" 'refresh token fora do registro'
    assert_segredo_ausente "$SENTINELA_SEGREDO" "$bruto" 'segredo fora do registro'
    assert_segredo_ausente "$SENTINELA_CHAVE" "$bruto" 'APP_KEY fora do registro'
    assert_contem "$SENTINELA_SESSAO" "$bruto" 'o session_id fica so no registro'
    assert_igual 600 "$(stat -c %a "$r")" 'registro 0600'
  done
  assert_segredo_ausente "$SENTINELA_SESSAO" "$DBX_SAIDA$DBX_ERRO" 'session_id fora da saida com --debug (interrompido)'
  _rodar "$base" diagnostico
  assert_segredo_ausente "$SENTINELA_SESSAO" "$DBX_SAIDA$DBX_ERRO" 'session_id fora do diagnostico'
  assert_contem 'retomada' "$DBX_SAIDA" 'diagnostico lista o registro'
  _rodar "$base" --debug upload grande.iso /Grande.iso
  assert_igual 0 "$DBX_ESTADO" "retomado com --debug: $DBX_ERRO"
  assert_segredo_ausente "$SENTINELA_SESSAO" "$DBX_SAIDA$DBX_ERRO" 'session_id fora da saida com --debug (retomado)'
  local modo bruto
  for modo in --json --null; do
    rm -f "$base/publicado"
    _rodar "$base" "$modo" upload grande.iso /Grande.iso
    bruto=$(tr '\0' '\n' <"$base/out"; cat "$base/err")
    assert_segredo_ausente "$SENTINELA_SESSAO" "$bruto" "session_id fora da saida ($modo)"
  done
}

teste_rme12_diretorio_de_estado_sem_escrita_segue_sem_retomada() {
  local base
  base=$(_ambiente)
  mkdir -p "$base/estado/dbx"
  chmod 500 "$base/estado/dbx"
  _up "$base"
  chmod 700 "$base/estado/dbx"
  assert_igual 0 "$DBX_ESTADO" "codigo normal: $DBX_ERRO"
  assert_contem 'sem retomada nesta execucao' "$DBX_ERRO" 'aviso'
  assert_igual 0 "$(_registros "$base")" 'nada escrito'
}

teste_rme14_registro_apagado_a_mao_so_muda_o_custo() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  rm -f "$base"/estado/dbx/retomada-*
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "do zero: $DBX_ERRO"
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'mesmo resultado'
  assert_igual 2 "$(_conta "$base" '^files/upload_session/start ')" 'so recomecou'
}

teste_rme_registro_invalido_descarta_com_um_aviso_e_conclui_igual() {
  local base r
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  for r in "$base"/estado/dbx/retomada-*; do printf 'lixo\0\0\0' >"$r"; done
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "descartado: $DBX_ERRO"
  assert_igual 1 "$(grep -c '^aviso[=:] *estado de retomada descartado' <<<"$DBX_ERRO")" 'uma linha de aviso'
  assert_contem 'retomada=recomecada' "$DBX_SAIDA" 'recomecada'
}

# _outra_conta <base> — o registro passa a dizer outra conta (mesmo nome).
_outra_conta() {
  local r f
  local -a c=()
  for r in "$1"/estado/dbx/retomada-*; do
    c=()
    while IFS= read -r -d '' f; do c+=("$f"); done <"$r"
    c[3]=cred-ffffffffffffffffffffffffffffffff
    printf '%s\0' "${c[@]}" >"$r"
  done
}

teste_rme_registro_de_outra_conta_e_descartado_e_o_mutante_que_o_aceita_reprova() {
  local base mutante
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  _outra_conta "$base"
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "descartado: $DBX_ERRO"
  assert_contem 'estado de retomada descartado: registro de outra conta' "$DBX_ERRO" 'aviso'
  assert_contem 'retomada=recomecada' "$DBX_SAIDA" 'do zero'
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  _outra_conta "$base"
  mutante=$(_copia_mutante lib/state.sh 's/\${c\[3\]} != "\$DBX_STATE_RETOMADA_CONTA" ||//')
  DBX_T_EXEC=$mutante _up "$base"
  assert_contem 'retomada=sim' "$DBX_SAIDA" 'o mutante usa o registro de outra conta'
}

# ---------------------------------------------------------------------------
# RF-105: trava por registro (TC-RMC-01, 04, 05)
# ---------------------------------------------------------------------------

teste_rmc01_dois_uploads_simultaneos_um_retoma_o_outro_vai_do_zero() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  local copia
  copia=$(mktemp -d "$DBX_TESTES_TMP/rmc.XXXXXX")
  # Dois processos reais, largando juntos; o segundo usa o mesmo estado.
  (
    cd "$base/trabalho" || exit 99
    for i in 1 2; do
      env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
        TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
        timeout -k 2 120 bash -c 'while [[ ! -e $1 ]]; do :; done; shift; printf "%s" "$$" >"$1/pid"; exec bash "$2" upload grande.iso /Grande.iso' _ \
        "$copia/largada" "$base" "$DBX_EXEC_PADRAO" </dev/null >"$copia/out$i" 2>"$copia/err$i" &
    done
    : >"$copia/largada"
    wait
  )
  local s1 s2
  s1=$(cat "$copia/out1" "$copia/err1")
  s2=$(cat "$copia/out2" "$copia/err2")
  assert_contem 'integridade=conferida' "$s1" 'o primeiro conclui'
  assert_contem 'integridade=conferida' "$s2" 'o segundo conclui'
  local sim=0 nao=0
  [[ $s1 == *'retomada=sim'* ]] && sim=$((sim + 1))
  [[ $s2 == *'retomada=sim'* ]] && sim=$((sim + 1))
  [[ $s1 == *'retomada=nao'* ]] && nao=$((nao + 1))
  [[ $s2 == *'retomada=nao'* ]] && nao=$((nao + 1))
  assert_igual '1 1' "$sim $nao" 'exatamente um retoma; o outro vai do zero sem retomada'
  assert_contem 'trava do registro ocupada' "$s1$s2" 'o aviso nomeia a trava'
  assert_contem ' pid ' "$s1$s2" 'com pid'
  assert_igual 0 "$(_registros "$base")" 'nenhum registro sobra'
  assert_igual 0 "$(_travas "$base")" 'nenhuma trava sobra'
}

teste_rmc01_mutante_sem_trava_de_registro_deixa_os_dois_lerem() {
  local base mutante
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  # Trava viva de outro processo deste host sobre o mesmo registro.
  local r trava host
  for r in "$base"/estado/dbx/retomada-*; do trava="${r%/*}/trava-${r##*/retomada-}"; done
  host=$(XDG_STATE_HOME="$base/estado" bash -c '. "$1/lib/errors.sh"; . "$1/lib/json.sh"; . "$1/lib/config.sh"; . "$1/lib/state.sh"; dbx_state_host_id; printf %s "$DBX_STATE_HOST_ID"' _ "$DBX_HARNESS_RAIZ")
  printf 'dbx-trava\t1\t%s\t%s\t%s\tretomada\tfim\n' "$$" "$host" 1700000000 >"$trava"
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "segue sem retomada: $DBX_ERRO"
  assert_contem 'retomada=nao' "$DBX_SAIDA" 'nao leu o registro alheio'
  assert_igual 1 "$(_registros "$base")" 'o registro do outro fica'
  assert_arquivo_existe "$trava" 'a trava viva fica'
  mutante=$(_copia_mutante lib/cmd.sh 's/^  dbx_state_retomada_travar$/  dbx_state_retomada_travar || :/')
  rm -f "$base/publicado"
  DBX_T_EXEC=$mutante _up "$base"
  assert_contem 'retomada=sim' "$DBX_SAIDA" 'sem respeitar a trava, o mutante le o registro do outro'
}

teste_rmc04_sync_e_upload_do_mesmo_par_nao_se_esperam() {
  local base
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  mkdir -p "$base/trabalho/d"
  printf 'x' >"$base/trabalho/d/a.txt"
  _rodar "$base" sync --enviar --origem d --destino /D
  assert_igual 0 "$DBX_ESTADO" "o sync nao le nem espera o registro: $DBX_ERRO"
  assert_igual 1 "$(_registros "$base")" 'o registro do upload fica'
}

teste_rmc05_verificar_e_dry_run_deixam_o_estado_byte_a_byte() {
  local base antes depois
  base=$(_ambiente)
  _interrompida_na_parte "$base" 4
  antes=$(cd "$base/estado" && find . -type f -exec sha256sum {} + | sort)
  _rodar "$base" --dry-run upload grande.iso /Grande.iso
  assert_igual 0 "$DBX_ESTADO" "simulacao: $DBX_ERRO"
  depois=$(cd "$base/estado" && find . -type f -exec sha256sum {} + | sort)
  assert_igual "$antes" "$depois" 'simulacao: estado intacto'
}

# ---------------------------------------------------------------------------
# RF-106: interrupcao (TC-RMS-01..06)
# ---------------------------------------------------------------------------

teste_rms01_a_03_int_term_hup_entre_partes_deixam_registro_e_soltam_a_trava() {
  local base sinal
  for sinal in INT TERM HUP; do
    base=$(_ambiente)
    _roteiro "$base" files/upload_session/append_v2 3 "SINAL:$sinal"
    _up "$base"
    assert_igual 14 "$DBX_ESTADO" "$sinal: 14"
    assert_igual 1 "$(_registros "$base")" "$sinal: o registro fica"
    assert_igual 0 "$(_travas "$base")" "$sinal: a trava de registro e liberada"
    assert_igual '' "$(_residuo "$base")" "$sinal: nenhuma area dbx-* no TMPDIR"
    _up "$base"
    assert_igual 0 "$DBX_ESTADO" "$sinal: retoma"
    assert_contem 'retomada=sim' "$DBX_SAIDA" "$sinal: retomado"
  done
}

teste_rms04_kill_9_e_a_seguinte_conclui_igual_retomando_a_trava_orfa() {
  local base
  base=$(_ambiente)
  _roteiro "$base" files/upload_session/append_v2 6 KILL
  _up "$base"
  assert_igual 1 "$(_travas "$base")" 'o kill -9 deixa a trava orfa'
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "conclui: $DBX_ERRO"
  assert_contem 'trava orfa' "$DBX_ERRO" 'a orfa e retomada com aviso'
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'mesmo resultado'
  assert_igual 0 "$(_travas "$base")" 'trava liberada'
}

teste_rms05_kill_9_depois_do_finish_publicado_a_seguinte_dispensa() {
  local base
  base=$(_ambiente)
  _roteiro "$base" files/upload_session/finish 1 ACEITA_E_KILL
  _up "$base"
  assert_igual 1 "$(_registros "$base")" 'registro do finish sem resposta'
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "dispensado: $DBX_ERRO"
  assert_contem 'status=dispensado' "$DBX_SAIDA" 'get_metadata com hash igual dispensa (C5)'
  assert_igual 1 "$(_conta "$base" '^files/upload_session/start ')" 'nada reenviado'
  assert_igual 0 "$(_registros "$base")" 'registro removido'
}

teste_rms06_falha_definitiva_e_sucesso_nao_deixam_registro() {
  local base
  base=$(_ambiente)
  _rodar "$base" upload inexistente.iso /X.iso
  assert_igual 4 "$DBX_ESTADO" 'origem inexistente'
  _rodar "$base" upload grande.iso $'/X\n.iso'
  assert_igual 13 "$DBX_ESTADO" 'caminho recusado'
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "sucesso: $DBX_ERRO"
  assert_igual 0 "$(_registros "$base")" 'nenhum retomada-*'
}

teste_rmo11_codigos_iguais_com_e_sem_registro_previo() {
  local base com sem
  for caso in 'TOO_LARGE 10' 'NOT_FOUND 4'; do
    base=$(_ambiente)
    _roteiro "$base" files/upload_session/append_v2 1 "${caso% *}"
    _roteiro "$base" files/upload_session/append_v2 2 "${caso% *}"
    _up "$base"
    sem=$DBX_ESTADO
    base=$(_ambiente)
    _interrompida_na_parte "$base" 2
    _roteiro "$base" files/upload_session/append_v2 3 "${caso% *}"
    _roteiro "$base" files/upload_session/append_v2 4 "${caso% *}"
    _up "$base"
    com=$DBX_ESTADO
    assert_igual "${caso#* }" "$sem" "${caso% *} sem registro"
    assert_igual "$sem" "$com" "${caso% *}: o registro nao muda o codigo"
  done
}

# TC-RMO-10: ajuda (fonte unica, portugues e ingles) e autocompletar.
teste_rmo10_ajuda_e_autocompletar_trazem_a_opcao_e_as_frases() {
  local cmd ajuda frase lista
  for cmd in upload download; do
    ajuda=$(bash "$DBX_EXEC_PADRAO" help "$cmd" 2>&1)
    assert_contem '--sem-retomada, --no-resume' "$ajuda" "$cmd: a opcao nos dois idiomas"
    for frase in \
      'uma transferencia grande interrompida continua de onde parou na proxima execucao com os mesmos argumentos' \
      'o upload so continua se o arquivo local nao mudou' \
      'o destino so muda depois de conferido o content_hash' \
      'use --sem-retomada para comecar do zero'; do
      assert_contem "$frase" "$ajuda" "$cmd: frase de RF-108(c)"
    done
    lista=$(env -i PATH="$PATH" HOME="$DBX_TESTES_TMP" bash -c '
      . "$1"; f=$(complete -p dbx); f=${f#*-F }; f=${f%% *}
      COMP_WORDS=(dbx "$2" --); COMP_CWORD=2; COMP_LINE="dbx $2 --"; COMP_POINT=${#COMP_LINE}; COMPREPLY=()
      "$f" dbx -- "$2"; printf "%s\n" "${COMPREPLY[@]}"' _ "$DBX_HARNESS_RAIZ/completions/dbx.bash" "$cmd")
    assert_contem '--sem-retomada' "$lista" "$cmd: completado"
    assert_contem '--no-resume' "$lista" "$cmd: alias completado"
  done
  assert_contem 'retomada-' "$(cat "$DBX_HARNESS_RAIZ/README.md")" 'o README explica onde vive o estado'
  assert_contem '.dbx-part.' "$(cat "$DBX_HARNESS_RAIZ/README.md")" 'o README explica o parcial junto do destino'
}

harness_executar "$@"
