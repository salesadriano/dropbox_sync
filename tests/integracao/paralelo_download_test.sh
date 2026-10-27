#!/usr/bin/env bash
# Testes ponta a ponta do DOWNLOAD de arquivo grande em faixas simultaneas
# (F-100, etapa 2b; RF-180, RF-181 (download), RF-182, RF-183, RF-184;
# DIV-369 a DIV-371, DIV-373 a DIV-376; TC-PUD-30..33).
#
# O DUPLO DE `curl` SERVE `Range` FECHADO (`range = "a-b"` na configuracao, como
# o cliente real) com `206` e `Content-Range`, a partir de `remoto.bin`; registra
# cada pedido em `chamadas` (`endpoint argumento faixa limit-rate`), marca
# `vivos/<pid>` enquanto atende (pico em `picos`) e segura cada faixa 0,3 s.
# Controles em `$base/ctl`: `ignora` (responde `200` ao Range: o cliente real,
# com `max-filesize`, recusa com status 63), `falha` (inicio da faixa que
# recebe 403) e `sinal_em` (inicio da faixa que manda TERM ao `dbx`).
#
# shellcheck disable=SC2016,SC2031
# Justificativa: o duplo de `curl` chega sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC_PADRAO="$DBX_HARNESS_RAIZ/bin/dbx"
readonly BLOCO=4194304
readonly Q=16777216
readonly LIMIAR_MAIS_UM=$((157286400 + 1))
readonly LIMIAR_MAIS_5=$((157286400 + 5))
readonly MULTIPLO=$((10 * Q))
readonly REV1='0123456789a'

_fixture() { # <tamanho>
  local tam=$1 arquivo="$DBX_TESTES_TMP/pdown-$1.bin" i
  if [[ ! -e $arquivo.hash ]]; then
    truncate -s "$tam" "$arquivo"
    for ((i = 0; i * BLOCO < tam; i++)); do
      printf 'remoto-%03d' "$i" | dd of="$arquivo" bs=1 seek=$((i * BLOCO)) conv=notrunc status=none
    done
    (
      . "$DBX_HARNESS_RAIZ/lib/hash.sh"
      dbx_hash_publicar_arquivo "$arquivo" && printf '%s' "$DBX_HASH_RESULTADO" >"$arquivo.hash"
    )
  fi
  printf '%s' "$arquivo"
}

_ambiente() { # <tamanho>
  local base remoto
  base=$(mktemp -d "$DBX_TESTES_TMP/pdw.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/tmp" "$base/trabalho" "$base/vivos" "$base/ctl"
  chmod 700 "$base/config/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  remoto=$(_fixture "$1")
  ln -sf "$remoto" "$base/remoto.bin"
  cp "$remoto.hash" "$base/hash"
  printf '%s' "$REV1" >"$base/rev"
  : >"$base/chamadas"
  : >"$base/picos"
  {
    printf '#!%s\n' "$BASH"
    printf 'base=%q\n' "$base"
  } >"$base/bin/curl"
  cat >>"$base/bin/curl" <<'FIM'
export LC_ALL=C
conf=$(cat)
saida=''; escrever=''; anterior=''; url=''; cabecalhos=''
for a in "$@"; do
  case $anterior in -o) saida=$a ;; -w) escrever=$a ;; -D) cabecalhos=$a ;; esac
  case $a in http*) url=$a ;; esac
  anterior=$a
done
arg='' faixa_req='' limite='' maximo=''
while IFS= read -r linha; do
  case $linha in
    'header = "Dropbox-API-Arg: '*) arg=${linha#'header = "Dropbox-API-Arg: '}; arg=${arg%\"}; arg=${arg//\\\"/\"} ;;
    'range = "'*) faixa_req=${linha#range = \"}; faixa_req=${faixa_req%\"} ;;
    'limit-rate = '*) limite=${linha#limit-rate = } ;;
    'max-filesize = '*) maximo=${linha#max-filesize = } ;;
  esac
done <<<"$conf"
ep=${url#https://*/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
printf '%s %s %s %s\n' "$ep" "$arg" "$faixa_req" "$limite" >>"$base/chamadas"
rev=$(<"$base/rev"); hash=$(<"$base/hash"); tam=$(wc -c <"$base/remoto.bin")
codigo=200 resposta='{}' faixa='' resultado=''
cabecalho() {
  [[ -n $cabecalhos ]] || return 0
  {
    printf 'HTTP/1.1 %s X\r\n' "$codigo"
    [[ -n $faixa ]] && printf 'Content-Range: %s\r\n' "$faixa"
    [[ -n $resultado ]] && printf 'Dropbox-API-Result: %s\r\n' "$resultado"
    [[ -n ${extra:-} ]] && printf '%s\r\n' "$extra"
    printf '\r\n'
  } >"$cabecalhos"
}
case $ep in
  oauth2/token) resposta='{"access_token":"sl.tokenD","token_type":"bearer","expires_in":14400}' ;;
  files/get_metadata)
    resposta="{\".tag\":\"file\",\"name\":\"grande.iso\",\"path_display\":\"/Grande.iso\",\"id\":\"id:1\",\"rev\":\"$rev\",\"size\":$tam,\"content_hash\":\"$hash\"}"
    ;;
  files/download)
    resultado="{\"name\":\"grande.iso\",\"rev\":\"$rev\",\"size\":$tam,\"content_hash\":\"$hash\"}"
    if [[ -n $faixa_req ]]; then
      a=${faixa_req%-*}; b=${faixa_req#*-}
      if [[ -e $base/ctl/ignora ]]; then
        codigo=200; cabecalho; [[ -n $escrever ]] && printf '%s' 200; exit 63
      fi
      if [[ -r $base/ctl/falha && $a == "$(<"$base/ctl/falha")" ]]; then
        if [[ -e $base/ctl/falha_rede ]]; then
          [[ -n $escrever ]] && printf '%s' 0; exit 18
        fi
        codigo=403; resposta='{"error_summary":"no_permission/"}'; cabecalho
        [[ -n $escrever ]] && printf '%s' 403; exit 22
      fi
      if [[ -r $base/ctl/sinal_em && $a == "$(<"$base/ctl/sinal_em")" ]]; then
        kill -s TERM "$(<"$base/pid")"; /bin/sleep 5; exit 18
      fi
      printf 'ini %s\n' "$a" >>"$base/ev"
      if [[ -r $base/ctl/r429 && $a == "$(<"$base/ctl/r429")" ]] && mv "$base/ctl/r429" "$base/ctl/r429.usado" 2>/dev/null; then
        printf '429 %s\n' "$a" >>"$base/ev"
        codigo=429; resposta='{"error_summary":"too_many_requests/"}'; extra='Retry-After: 1'; cabecalho
        [[ -n $escrever ]] && printf '%s' 429; exit 22
      fi
      : >"$base/vivos/$$"
      ls "$base/vivos" | wc -l >>"$base/picos"
      /bin/sleep 0.3
      codigo=206; faixa="bytes $a-$b/$tam"; cabecalho
      tail -c +$((a + 1)) "$base/remoto.bin" | head -c $((b - a + 1)) >"$saida"
      rm -f "$base/vivos/$$"
      [[ -n $escrever ]] && printf '%s' 206
      exit 0
    fi
    cabecalho
    cat "$base/remoto.bin" >"$saida"
    [[ -n $escrever ]] && printf '%s' 200
    exit 0
    ;;
  *) codigo=409; resposta='{"error_summary":"sem_regra/"}' ;;
esac
cabecalho
[[ -n $saida ]] && printf '%s' "$resposta" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  {
    printf '#!%s\n' "$BASH"
    printf '[[ -e %q/ctl/sleep_real && $1 != 0.* ]] && exec /bin/sleep "$1"\nexit 0\n' "$base"
  } >"$base/bin/sleep"
  chmod +x "$base/bin/curl" "$base/bin/sleep"
  printf '%s' "$base"
}

_rodar() {
  local base=$1
  shift
  (
    cd "$base/trabalho" || exit 99
    env -i PATH="${DBX_T_PATH:+$DBX_T_PATH:}$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
      DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout -k 2 "${DBX_T_TETO:-120}" setsid -w bash -c 'printf "%s" "$$" >"$1/pid"; shift; exec bash "$@"' _ \
      "$base" "${DBX_T_EXEC:-$DBX_EXEC_PADRAO}" "$@" </dev/null >"$base/out" 2>"$base/err"
  ) 2>/dev/null
  DBX_ESTADO=$?
  [[ $DBX_ESTADO -ne 124 && $DBX_ESTADO -ne 137 ]] || _harness_falhar "o comando pendurou ($DBX_ESTADO): $*"
  DBX_SAIDA='' DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_down() { _rodar "$1" download "${@:2}" /Grande.iso grande.iso; }
_conta() { _harness_contar "$2" "$1/chamadas"; }
_pico() { sort -n "$1/picos" | tail -1; }
_iguais() { cmp -s "$1/trabalho/grande.iso" "$1/remoto.bin"; }
_registros() {
  local r n=0
  for r in "$1"/estado/dbx/retomada-*; do [[ -e $r ]] && n=$((n + 1)); done
  printf '%s' "$n"
}
_part() {
  local p
  for p in "$1"/trabalho/.grande.iso.dbx-part.*; do [[ -e $p ]] && printf '%s' "$p"; done
}

# ---------------------------------------------------------------------------
# RF-180: bytes, conferencia e simultaneidade
# ---------------------------------------------------------------------------

teste_limiar_mais_cinco_faixa_final_curta_bytes_identicos_e_pico() {
  local base pico
  base=$(_ambiente "$LIMIAR_MAIS_5")
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'o alvo deveria ser identico ao remoto'
  assert_contem 'integridade=conferida' "$DBX_SAIDA"
  assert_contem "content_hash=$(<"$base/hash")" "$DBX_SAIDA"
  assert_igual 10 "$(_conta "$base" '^files/download .* [0-9][0-9]*-[0-9][0-9]* ')" 'dez faixas'
  assert_igual 1 "$(_conta "$base" "^files/download .* $((9 * Q))-$((LIMIAR_MAIS_5 - 1)) ")" 'faixa final curta'
  pico=$(_pico "$base")
  ((pico > 1 && pico <= 4)) || _harness_falhar "pico de simultaneas fora de (1,4]: $pico"
  assert_igual '' "$(_part "$base")" 'sem .part'
  assert_igual 0 "$(_registros "$base")" 'registro removido'
}

teste_limiar_mais_um_byte() {
  local base
  base=$(_ambiente "$LIMIAR_MAIS_UM")
  _down "$base" --paralelo 3
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'o alvo deveria ser identico ao remoto'
  assert_contem 'integridade=conferida' "$DBX_SAIDA"
}

teste_multiplo_exato_de_16_mib() {
  local base
  base=$(_ambiente "$MULTIPLO")
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'o alvo deveria ser identico ao remoto'
  assert_igual 10 "$(_conta "$base" '^files/download .* [0-9][0-9]*-[0-9][0-9]* ')" 'dez faixas'
  assert_igual 1 "$(_conta "$base" "^files/download .* $((9 * Q))-$((MULTIPLO - 1)) ")" 'ultima faixa cheia'
}

teste_n1_e_abaixo_do_limiar_seguem_o_caminho_de_hoje() {
  local base
  base=$(_ambiente "$LIMIAR_MAIS_5")
  _down "$base"
  assert_igual 0 "$DBX_ESTADO" "N=1: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'N=1: alvo diferente'
  assert_igual 0 "$(_conta "$base" '^files/download .* [0-9][0-9]*-[0-9][0-9]* ')" 'N=1: nenhuma faixa fechada'
  base=$(_ambiente 1048576)
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "abaixo do limiar: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'abaixo do limiar: alvo diferente'
  assert_igual 0 "$(_conta "$base" '^files/download .* [0-9][0-9]*-[0-9][0-9]* ')" 'abaixo do limiar: nenhuma faixa'
}

# ---------------------------------------------------------------------------
# RF-182: falha, sinal, servidor que ignora Range
# ---------------------------------------------------------------------------

teste_queda_de_rede_numa_faixa_preserva_part_e_reexecucao_completa() {
  local base part tamanho
  base=$(_ambiente "$LIMIAR_MAIS_5")
  printf 'alvo anterior' >"$base/trabalho/grande.iso"
  : >"$base/ctl/falha_rede"
  printf '%s' "$((3 * Q))" >"$base/ctl/falha"
  _down "$base" --paralelo 4
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar "a falha de uma faixa deveria falhar o comando: $DBX_SAIDA $DBX_ERRO"
  assert_igual 'alvo anterior' "$(cat "$base/trabalho/grande.iso")" 'sem mv: alvo intacto'
  part=$(_part "$base")
  [[ -n $part ]] || _harness_falhar '.part deveria ficar'
  assert_igual 1 "$(_registros "$base")" 'registro preservado'
  tamanho=$(stat -c %s "$part")
  assert_igual "$((3 * Q))" "$tamanho" '.part e o prefixo contiguo'
  rm -f "$base/ctl/falha" "$base/ctl/falha_rede"
  : >"$base/chamadas"
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "reexecucao: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'reexecucao: alvo diferente'
  assert_igual 1 "$(_conta "$base" "^files/download .* $((3 * Q))-")" 'continua do prefixo contiguo'
  assert_igual 0 "$(_conta "$base" '^files/download .* 0-')" 'nao rebaixa o prefixo'
}

teste_403_numa_faixa_segue_a_regra_do_sequencial_descarta_part_e_registro() {
  local base
  base=$(_ambiente "$LIMIAR_MAIS_5")
  printf 'alvo anterior' >"$base/trabalho/grande.iso"
  printf '%s' "$((3 * Q))" >"$base/ctl/falha"
  _down "$base" --paralelo 4
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar "403 deveria falhar o comando: $DBX_SAIDA $DBX_ERRO"
  assert_igual 'alvo anterior' "$(cat "$base/trabalho/grande.iso")" 'sem mv: alvo intacto'
  assert_igual '' "$(_part "$base")" 'classe definitiva: .part descartado como no sequencial'
  assert_igual 0 "$(_registros "$base")" 'registro descartado'
}

teste_sigterm_sem_orfaos_e_retomada_pelo_prefixo_contiguo() {
  local base part tamanho
  base=$(_ambiente "$LIMIAR_MAIS_5")
  printf 'alvo anterior' >"$base/trabalho/grande.iso"
  printf '%s' "$((5 * Q))" >"$base/ctl/sinal_em"
  _down "$base" --paralelo 4
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'o sinal deveria interromper o comando'
  if pgrep -f "$base/bin/curl" >/dev/null 2>&1; then _harness_falhar 'ficaram auxiliares orfaos'; fi
  assert_igual 'alvo anterior' "$(cat "$base/trabalho/grande.iso")" 'sem mv: alvo intacto'
  part=$(_part "$base")
  [[ -n $part ]] || _harness_falhar '.part deveria ficar'
  assert_igual 1 "$(_registros "$base")" 'registro preservado'
  tamanho=$(stat -c %s "$part")
  ((tamanho % Q == 0 && tamanho <= 5 * Q)) || _harness_falhar ".part nao e prefixo contiguo de faixas: $tamanho"
  rm -f "$base/ctl/sinal_em"
  : >"$base/chamadas"
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "retomada: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'retomada: alvo diferente'
  assert_igual 0 "$(_conta "$base" '^files/download .* 0-')" 'nao rebaixa o prefixo'
  if ((tamanho > 0)); then
    assert_igual 1 "$(_conta "$base" "^files/download .* $tamanho-")" 'continua de T'
  fi
}

teste_servidor_que_ignora_range_recomeca_sequencial_com_aviso() {
  local base
  base=$(_ambiente "$LIMIAR_MAIS_5")
  : >"$base/ctl/ignora"
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  assert_contem 'faixa ignorada' "$DBX_ERRO"
  _iguais "$base" || _harness_falhar 'o recomeco sequencial deveria entregar o remoto'
}

# ---------------------------------------------------------------------------
# RF-183: banda e debug
# ---------------------------------------------------------------------------

teste_limite_de_banda_dividido_entre_as_faixas() {
  local base limite
  base=$(_ambiente "$LIMIAR_MAIS_5")
  _down "$base" --paralelo 4 --limite-banda 8M
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  limite=$(awk '$1 == "files/download" && $3 ~ /-/ { print $4; exit }' "$base/chamadas")
  [[ $limite =~ ^[0-9]+$ ]] || _harness_falhar "faixa sem limit-rate: '$limite'"
  ((limite >= 2000000 && limite <= 2097152)) || _harness_falhar "limite por faixa nao e total/N: $limite"
}

teste_debug_registra_paralelo_e_partes() {
  local base
  base=$(_ambiente "$LIMIAR_MAIS_5")
  _rodar "$base" --debug download --paralelo 4 /Grande.iso grande.iso
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  assert_contem 'debug: download paralelo=4 partes=10' "$DBX_ERRO"
  assert_contem 'debug: download parte=0 deslocamento=0' "$DBX_ERRO"
}

# Pausar ANTES de esperar (DIV-365 A, RF-182(a)): a marca do 429 vale durante o Retry-After.
teste_429_pausa_o_despacho_durante_o_retry_after() {
  local base viol
  base=$(_ambiente "$LIMIAR_MAIS_5")
  printf "%s" "$Q" >"$base/ctl/r429"
  : >"$base/ctl/sleep_real"
  _rodar "$base" download --paralelo 4 /Grande.iso grande.iso
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  assert_igual 1 "$(grep -c '^429 ' "$base/ev")" 'o cenario precisa ter produzido o 429'
  viol=$(awk -v q="$Q" -v lim="$((4 * Q))" '
    $1 == "429" { pausa = 1; next }
    $1 == "ini" { if (pausa && $2 == q) pausa = 0; else if (pausa && $2 >= lim) print "ini " $2 " durante a espera" }' "$base/ev")
  assert_igual '' "$viol" 'nenhuma faixa nova durante o Retry-After'
}

harness_executar "$@"
