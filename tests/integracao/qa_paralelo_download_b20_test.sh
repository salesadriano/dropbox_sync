#!/usr/bin/env bash
# Suite independente do QA, B20: download de arquivo grande em faixas
# simultaneas (F-100, etapa 2b; RF-180 a RF-184; DIV-369 a DIV-371, DIV-373 a
# DIV-376; RF-104(c)(d); RF-106(a)). A suite do developer
# (paralelo_download_test.sh) nao e base.
#
# Escrita como adversario, pelo executavel real `bin/dbx`. O duplo de `curl` e um
# servidor de `Range` proprio: serve `206` com `Content-Range` exato a partir de
# `remoto.bin`, e registra em `ev` (ordem de chegada, atomica por linha):
#   ini <a> <b|seq> <limit-rate> <vivos> <arquivos-f.*> <bytes-f.*>
#   pre <a> <tamanho-do-.part-agora>     (logo antes de responder a faixa)
#   fim <a> <codigo> <arquivos-f.*> <bytes-f.*>
# A simultaneidade e a sobreposicao de ini/fim; a area temporaria e medida pelos
# `f.*` vivos em $TMPDIR; a ORDEM de gravacao e provada pelo tamanho do `.part`
# no instante em que uma faixa atrasada responde.
#
# Controles (arquivos em $base/ctl): atraso_todos e atraso.<a> (s, espera real);
# falha.<a> (rede|403); r429.<a> (n respostas 429 com Retry-After); ignora (a
# partir do deslocamento: 200 ao Range; com max-filesize o cliente real recusa
# com 63 e nenhum corpo); crerrado.<a> (Content-Range deslocado e corpo
# adulterado); revoutra.<a> e rev_outra_todos (outra revisao + corpo adulterado);
# sinal.<a> (TERM no dbx); troca.<a> (troca o `.part` por outro arquivo).
#
# O content_hash esperado e calculado AQUI, do arquivo local, pelo algoritmo
# publico da Dropbox (SHA-256 da concatenacao dos SHA-256 dos blocos de 4 MiB).
# Origem dos dados: arquivos sinteticos gerados pela suite (urandom), sem segredo.
#
# shellcheck disable=SC2016,SC2034
# Justificativa: o duplo de `curl` e os fixtures sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC_PADRAO="$DBX_HARNESS_RAIZ/bin/dbx"
readonly BLOCO=4194304
readonly Q=16777216
readonly LIMIAR=157286400
readonly T_LIMIAR_MAIS_1=$((LIMIAR + 1))
readonly T_MULTIPLO=$((10 * Q))
readonly T_FINAL_CURTA=$((LIMIAR + 5))
readonly T_ABAIXO=$((100 * 1048576))
readonly T_VINTE=$((20 * 1048576))
readonly REV1='0123456789a'

_fixture() { # <tamanho> — 4 KiB aleatorios no inicio de cada bloco e nos ultimos 16 bytes
  local tam=$1 arquivo="$DBX_TESTES_TMP/qa20-$1.bin" i n
  if [[ ! -e $arquivo ]]; then
    truncate -s "$tam" "$arquivo"
    for ((i = 0; i * BLOCO < tam; i++)); do
      n=$((tam - i * BLOCO))
      ((n > 4096)) && n=4096
      head -c "$n" /dev/urandom | dd of="$arquivo" bs=4096 seek=$((i * BLOCO / 4096)) conv=notrunc status=none
    done
    n=16
    ((tam < 16)) && n=$tam
    head -c "$n" /dev/urandom | dd of="$arquivo" bs=1 seek=$((tam - n)) conv=notrunc status=none
  fi
  printf '%s' "$arquivo"
}

_hash_local() { # <arquivo> — content_hash esperado (algoritmo publico, independente do produto)
  local arq=$1 tam k h esc i
  if [[ -s $arq.qahash ]]; then
    cat "$arq.qahash"
    return 0
  fi
  tam=$(wc -c <"$arq")
  : >"$arq.cadeia"
  for ((k = 0; k * BLOCO < tam; k++)); do
    h=$(dd if="$arq" bs=$BLOCO skip="$k" count=1 2>/dev/null | sha256sum)
    h=${h%% *}
    esc=''
    for ((i = 0; i < 64; i += 2)); do esc+="\\x${h:i:2}"; done
    printf '%b' "$esc" >>"$arq.cadeia"
  done
  h=$(sha256sum <"$arq.cadeia")
  rm -f "$arq.cadeia"
  printf '%s' "${h%% *}" >"$arq.qahash"
  printf '%s' "${h%% *}"
}

_ambiente() { # <tamanho>
  local base remoto velho
  for velho in "$DBX_TESTES_TMP"/qa20.*; do [[ -d $velho ]] && rm -rf -- "$velho"; done
  base=$(mktemp -d "$DBX_TESTES_TMP/qa20.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/tmp" "$base/trabalho" "$base/vivos" "$base/ctl"
  chmod 700 "$base/config/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  remoto=$(_fixture "$1")
  ln -sf "$remoto" "$base/remoto.bin"
  _hash_local "$remoto" >"$base/hash"
  printf '%s' "$REV1" >"$base/rev"
  printf '0.3' >"$base/ctl/atraso_todos"
  : >"$base/ev"
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
arg='' faixa_req='' limite='-' maximo='' continuar=''
while IFS= read -r linha; do
  case $linha in
    'header = "Dropbox-API-Arg: '*) arg=${linha#'header = "Dropbox-API-Arg: '}; arg=${arg%\"}; arg=${arg//\\\"/\"} ;;
    'range = "'*) faixa_req=${linha#range = \"}; faixa_req=${faixa_req%\"} ;;
    'limit-rate = '*) limite=${linha#limit-rate = } ;;
    'max-filesize = '*) maximo=${linha#max-filesize = } ;;
    'continue-at = '*) continuar=${linha#continue-at = } ;;
  esac
done <<<"$conf"
ep=${url#https://*/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
ctl() { [[ -r $base/ctl/$1 ]] && cat "$base/ctl/$1"; }
rev=$(<"$base/rev"); hash=$(<"$base/hash"); tam=$(wc -c <"$base/remoto.bin")
codigo=200 resposta='{}' faixa='' resultado='' extra='' nf=0 by=0 rev_res=$rev
medir() {
  local s
  nf=0 by=0
  while read -r s; do nf=$((nf + 1)); by=$((by + s)); done < <(find "$base/tmp" -type f -name 'f.*' -printf '%s\n' 2>/dev/null)
}
cabecalho() {
  [[ -n $cabecalhos ]] || return 0
  {
    printf 'HTTP/1.1 %s X\r\n' "$codigo"
    [[ -n $faixa ]] && printf 'Content-Range: %s\r\n' "$faixa"
    [[ -n $extra ]] && printf '%s\r\n' "$extra"
    [[ -n $resultado ]] && printf 'Dropbox-API-Result: %s\r\n' "$resultado"
    printf '\r\n'
  } >"$cabecalhos"
}
resultado_json() { resultado="{\"name\":\"grande.iso\",\"rev\":\"$1\",\"size\":$tam,\"content_hash\":\"$hash\"}"; }
case $ep in
  oauth2/token) resposta='{"access_token":"sl.tokenD","token_type":"bearer","expires_in":14400}' ;;
  files/get_metadata)
    resposta="{\".tag\":\"file\",\"name\":\"grande.iso\",\"path_display\":\"/Grande.iso\",\"id\":\"id:1\",\"rev\":\"$rev\",\"size\":$tam,\"content_hash\":\"$hash\"}"
    ;;
  files/download)
    [[ -e $base/ctl/rev_outra_todos ]] && rev_res='ffffffffffb'
    if [[ -n $faixa_req ]]; then
      a=${faixa_req%-*}; b=${faixa_req#*-}
      vivo="$base/vivos/$$"; : >"$vivo"; trap 'rm -f "$vivo"' EXIT
      : >"$saida"
      medir
      printf 'ini %s %s %s %s %s %s\n' "$a" "$b" "$limite" "$(ls "$base/vivos" | wc -l)" "$nf" "$by" >>"$base/ev"
      fim() { medir; printf 'fim %s %s %s %s\n' "$a" "$1" "$nf" "$by" >>"$base/ev"; }
      ign=$(ctl ignora)
      if [[ -n $ign ]] && ((a >= ign)); then
        if [[ -n $maximo ]]; then
          codigo=200; cabecalho; fim 200
          [[ -n $escrever ]] && printf '%s' 200
          exit 63
        fi
        codigo=200; resultado_json "$rev_res"; cabecalho; cat "$base/remoto.bin" >"$saida"; fim 200
        [[ -n $escrever ]] && printf '%s' 200
        exit 0
      fi
      modo=$(ctl "falha.$a")
      case $modo in
        rede) fim 0; [[ -n $escrever ]] && printf '%s' 0; exit 18 ;;
        403)
          codigo=403; resposta='{"error_summary":"no_permission/"}'; cabecalho; printf '%s' "$resposta" >"$saida"
          fim 403; [[ -n $escrever ]] && printf '%s' 403; exit 22 ;;
      esac
      r=$(ctl "r429.$a")
      if [[ -n $r ]] && ((r > 0)); then
        printf '%s' $((r - 1)) >"$base/ctl/r429.$a"
        codigo=429; extra='Retry-After: 1'; resposta='{"error_summary":"too_many_requests/"}'; cabecalho
        printf '%s' "$resposta" >"$saida"
        fim 429; [[ -n $escrever ]] && printf '%s' 429; exit 22
      fi
      d=$(ctl "atraso.$a"); [[ -n $d ]] || d=$(ctl atraso_todos)
      sn=$(ctl "sinal.$a")
      if [[ -n $sn ]]; then kill -s TERM "$(<"$base/pid")"; /bin/sleep 5; exit 18; fi
      [[ -n $d ]] && /bin/sleep "$d"
      if [[ -e $base/ctl/troca.$a ]]; then
        p=$(ls "$base"/trabalho/.grande.iso.dbx-part.* 2>/dev/null | head -1)
        cp -p "$p" "$base/troca.tmp" && mv -f "$base/troca.tmp" "$p"
        stat -c %s "$p" >"$base/obs.troca"
      fi
      ps=0; p=$(ls "$base"/trabalho/.grande.iso.dbx-part.* 2>/dev/null | head -1)
      [[ -n $p ]] && ps=$(stat -c %s "$p")
      printf 'pre %s %s\n' "$a" "$ps" >>"$base/ev"
      codigo=206; faixa="bytes $a-$b/$tam"; resultado_json "$rev_res"
      corromper=nao
      if [[ -e $base/ctl/crerrado.$a ]]; then faixa="bytes $((a + 1))-$((b + 1))/$tam"; corromper=sim; fi
      if [[ -e $base/ctl/revoutra.$a ]]; then resultado_json ffffffffffb; corromper=sim; fi
      [[ -e $base/ctl/rev_outra_todos ]] && corromper=sim
      cabecalho
      if [[ $corromper == sim ]]; then
        dd if="$base/remoto.bin" bs=1M iflag=skip_bytes,count_bytes skip="$a" count=$((b - a + 1)) status=none | tr '\000' '\377' >"$saida"
      else
        dd if="$base/remoto.bin" bs=1M iflag=skip_bytes,count_bytes skip="$a" count=$((b - a + 1)) status=none >"$saida"
      fi
      fim 206
      [[ -n $escrever ]] && printf '%s' 206
      exit 0
    fi
    # sem faixa fechada: caminho sequencial (inteiro, ou retomado por continue-at)
    medir
    printf 'ini seq %s %s 0 %s %s\n' "${continuar:-0}" "$limite" "$nf" "$by" >>"$base/ev"
    resultado_json "$rev_res"
    if [[ -n $continuar && $continuar -gt 0 ]]; then
      codigo=206; faixa="bytes $continuar-$((tam - 1))/$tam"; cabecalho
      tail -c +$((continuar + 1)) "$base/remoto.bin" >>"$saida"
    else
      cabecalho
      if [[ -e $base/ctl/rev_outra_todos ]]; then tr '\000' '\377' <"$base/remoto.bin" >"$saida"; else cat "$base/remoto.bin" >"$saida"; fi
    fi
    printf 'fim seq %s 0 0\n' "$codigo" >>"$base/ev"
    [[ -n $escrever ]] && printf '%s' "$codigo"
    exit 0
    ;;
  *) codigo=409; resposta='{"error_summary":"sem_regra/"}' ;;
esac
cabecalho
[[ -n $saida ]] && printf '%s' "$resposta" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  printf '#!%s\nexit 0\n' "$BASH" >"$base/bin/sleep"
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
      timeout -k 2 "${DBX_T_TETO:-150}" setsid -w bash -c 'printf "%s" "$$" >"$1/pid"; shift; exec bash "$@"' _ \
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
_iguais() { cmp -s "$1/trabalho/grande.iso" "$1/remoto.bin"; }
_conta_ev() { _harness_contar "$2" "$1/ev"; }
_registros() {
  local r n=0
  for r in "$1"/estado/dbx/retomada-*; do [[ -e $r ]] && n=$((n + 1)); done
  printf '%s' "$n"
}
_part() {
  local p
  for p in "$1"/trabalho/.grande.iso.dbx-part.*; do [[ -e $p ]] && printf '%s' "$p"; done
}
_max_campo() { awk -v t="$2" -v c="$3" '$1 == t && $c + 0 > m { m = $c + 0 } END { print m + 0 }' "$1/ev"; }
_linha() { grep -n -E -- "$2" "$1/ev" | head -1 | cut -d: -f1; }
_pre() { awk -v a="$2" '$1 == "pre" && $2 == a { print $3; exit }' "$1/ev"; }
# _prefixo_ok <base> <tamanho_max> — o .part e prefixo EXATO do remoto, multiplo de Q, <= tamanho_max
_prefixo_ok() {
  local p t
  p=$(_part "$1")
  [[ -n $p ]] || { printf 'sem .part'; return 1; }
  t=$(stat -c %s "$p")
  ((t % Q == 0 && t <= $2)) || { printf '.part de %s nao e prefixo de faixas (max %s)' "$t" "$2"; return 1; }
  cmp -s -n "$t" "$p" "$1/remoto.bin" || { printf '.part nao e prefixo do remoto'; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# 1. Bytes identicos, content_hash e faixa final; fora de ordem gravada em ordem
# ---------------------------------------------------------------------------

_bytes_e_hash() { # <tamanho> <faixas>
  local base m=$2 ultima
  base=$(_ambiente "$1")
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "download de $1: $DBX_ERRO"
  _iguais "$base" || _harness_falhar "download de $1: bytes diferentes do remoto"
  assert_contem 'integridade=conferida' "$DBX_SAIDA"
  assert_contem "content_hash=$(<"$base/hash")" "$DBX_SAIDA"
  assert_igual "$m" "$(_conta_ev "$base" '^ini [0-9]')" "faixas de $1"
  ultima=$(((m - 1) * Q))
  assert_igual 1 "$(_conta_ev "$base" "^ini $ultima $(($1 - 1)) ")" "faixa final de $1 e [$ultima, $(($1 - 1))]"
  assert_igual 0 "$(_conta_ev "$base" '^ini seq')" 'nenhum pedido sem faixa'
  assert_igual '' "$(_part "$base")" 'sem .part'
  assert_igual 0 "$(_registros "$base")" 'registro removido'
}

teste_limiar_mais_um_byte_bytes_e_hash() { _bytes_e_hash "$T_LIMIAR_MAIS_1" 10; }
teste_multiplo_exato_de_16_mib_bytes_e_hash() { _bytes_e_hash "$T_MULTIPLO" 10; }
teste_faixa_final_curta_bytes_e_hash() { _bytes_e_hash "$T_FINAL_CURTA" 10; }

# _ordem_ok <base> — 0 quando o cenario "faixa 0 chega por ultimo" termina certo e
# o .part nunca recebeu nada antes dela. Compartilhada com a mutacao.
_ordem_ok() {
  local base=$1 l0 l1
  [[ $DBX_ESTADO -eq 0 ]] || { printf 'exit %s' "$DBX_ESTADO"; return 1; }
  _iguais "$base" || { printf 'bytes diferentes'; return 1; }
  [[ $(_pre "$base" 0) == '0' ]] || { printf '.part nao estava vazio quando a faixa 0 chegou: %s' "$(_pre "$base" 0)"; return 1; }
  l0=$(_linha "$base" '^fim 0 206') l1=$(_linha "$base" "^fim $Q 206")
  ((l1 < l0)) || { printf 'o cenario nao produziu chegada fora de ordem'; return 1; }
  return 0
}

teste_faixa_zero_atrasada_chega_por_ultimo_e_nada_e_gravado_antes() {
  local base msg
  base=$(_ambiente "$T_FINAL_CURTA")
  printf '1.5' >"$base/ctl/atraso.0"
  _down "$base" --paralelo 4
  msg=$(_ordem_ok "$base") || _harness_falhar "ordem: $msg"
  # Janela: nenhuma faixa alem das 4 primeiras e despachada enquanto a 0 nao termina.
  assert_igual 0 "$(awk -v lim="$((4 * Q))" 'BEGIN{f=0} $1=="fim" && $2==0 {f=1} $1=="ini" && !f && $2+0 >= lim {n++} END{print n+0}' "$base/ev")" \
    'janela de N=4: nenhuma faixa >= 4Q antes do fim da faixa 0'
}

teste_faixa_do_meio_atrasada_part_so_tem_o_prefixo_contiguo() {
  local base
  base=$(_ambiente "$T_FINAL_CURTA")
  printf '1.5' >"$base/ctl/atraso.$((2 * Q))"
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'bytes diferentes'
  assert_igual "$((2 * Q))" "$(_pre "$base" "$((2 * Q))")" '.part = faixas 0 e 1 quando a 2 chega; 3 e 4 prontas ficam fora'
  assert_igual 1 "$(_linha "$base" "^fim $((3 * Q)) 206" | awk -v l="$(_linha "$base" "^fim $((2 * Q)) 206")" '{print ($1 < l)}')" \
    'a faixa 3 terminou antes da 2 (fora de ordem de fato)'
}

# ---------------------------------------------------------------------------
# 2. Pico e area temporaria
# ---------------------------------------------------------------------------

_pico_e_area() { # <N>
  local base pico arq bytes
  base=$(_ambiente "$T_FINAL_CURTA")
  _down "$base" --paralelo "$1"
  assert_igual 0 "$DBX_ESTADO" "N=$1: $DBX_ERRO"
  _iguais "$base" || _harness_falhar "N=$1: bytes diferentes"
  pico=$(_max_campo "$base" ini 5)
  ((pico > 1 && pico <= $1)) || _harness_falhar "N=$1: pico de simultaneas fora de (1,$1]: $pico"
  arq=$(awk '$1 ~ /^(ini|fim)$/ && $1 != "x" { n = ($1 == "ini") ? $6 : $4; if (n + 0 > m) m = n + 0 } END { print m + 0 }' "$base/ev")
  bytes=$(awk '$1 ~ /^(ini|fim)$/ { n = ($1 == "ini") ? $7 : $5; if (n + 0 > m) m = n + 0 } END { print m + 0 }' "$base/ev")
  ((arq >= 1)) || _harness_falhar "N=$1: a medicao nao viu nenhum f.* (area temporaria fora de \$TMPDIR?)"
  ((arq <= $1)) || _harness_falhar "N=$1: $arq arquivos temporarios vivos (> N)"
  ((bytes <= $1 * Q)) || _harness_falhar "N=$1: $bytes bytes temporarios (> N x 16 MiB)"
  assert_igual '' "$(find "$base/tmp" -mindepth 1 -print -quit)" 'area temporaria removida ao fim'
}

teste_pico_e_area_temporaria_com_n_2() { _pico_e_area 2; }
teste_pico_e_area_temporaria_com_n_4() { _pico_e_area 4; }

teste_area_temporaria_limitada_a_n_mesmo_com_a_faixa_zero_presa() {
  local base arq bytes
  base=$(_ambiente "$T_FINAL_CURTA")
  printf '1.5' >"$base/ctl/atraso.0"
  _down "$base" --paralelo 3
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  arq=$(awk '{ n = ($1 == "ini") ? $6 : $4; if ($1 ~ /^(ini|fim)$/ && n + 0 > m) m = n + 0 } END { print m + 0 }' "$base/ev")
  bytes=$(awk '{ n = ($1 == "ini") ? $7 : $5; if ($1 ~ /^(ini|fim)$/ && n + 0 > m) m = n + 0 } END { print m + 0 }' "$base/ev")
  ((arq <= 3 && bytes <= 3 * Q)) || _harness_falhar "faixa 0 presa: $arq arquivos / $bytes bytes temporarios (limite 3 faixas)"
}

# ---------------------------------------------------------------------------
# 3. N=1, abaixo do limiar, saida padrao: caminho antigo
# ---------------------------------------------------------------------------

teste_n1_abaixo_do_limiar_e_saida_padrao_nao_usam_faixa_fechada() {
  local base
  base=$(_ambiente "$T_FINAL_CURTA")
  _down "$base"
  assert_igual 0 "$DBX_ESTADO" "N=1: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'N=1: bytes diferentes'
  assert_igual 0 "$(_conta_ev "$base" '^ini [0-9]')" 'N=1: nenhuma faixa fechada'
  assert_igual 1 "$(_conta_ev "$base" '^ini seq')" 'N=1: um pedido sequencial'
  base=$(_ambiente "$T_ABAIXO")
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "abaixo do limiar: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'abaixo do limiar: bytes diferentes'
  assert_igual 0 "$(_conta_ev "$base" '^ini [0-9]')" 'abaixo do limiar (100 MiB): nenhuma faixa fechada'
  base=$(_ambiente "$T_VINTE")
  _rodar "$base" download /Grande.iso
  assert_igual 0 "$DBX_ESTADO" "saida padrao: $DBX_ERRO"
  cmp -s "$base/out" "$base/remoto.bin" || _harness_falhar 'saida padrao: bytes diferentes'
  assert_igual 0 "$(_conta_ev "$base" '^ini [0-9]')" 'saida padrao: nenhuma faixa fechada'
  _rodar "$base" download --paralelo 4 /Grande.iso -
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'saida padrao com --paralelo explicito deveria ser recusada'
  assert_contem 'saida padrao' "$DBX_ERRO"
}

# ---------------------------------------------------------------------------
# 4. Queda de rede: so o prefixo contiguo; reexecucao continua dali
# ---------------------------------------------------------------------------

teste_queda_de_rede_preserva_prefixo_e_registro_e_reexecucao_continua() {
  local base msg partes
  base=$(_ambiente "$T_FINAL_CURTA")
  printf 'alvo anterior' >"$base/trabalho/grande.iso"
  printf 'rede' >"$base/ctl/falha.$((3 * Q))"
  _down "$base" --paralelo 4
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'a queda deveria falhar o comando'
  assert_igual 'alvo anterior' "$(cat "$base/trabalho/grande.iso")" 'sem mv: alvo intacto'
  msg=$(_prefixo_ok "$base" "$((3 * Q))") || _harness_falhar "$msg"
  assert_igual "$((3 * Q))" "$(stat -c %s "$(_part "$base")")" '.part = faixas 0..2 (as contiguas em voo foram gravadas)'
  assert_igual 1 "$(_registros "$base")" 'registro preservado (rede)'
  rm -f "$base/ctl/falha.$((3 * Q))"
  : >"$base/ev"
  _rodar "$base" --debug download --paralelo 4 /Grande.iso grande.iso
  assert_igual 0 "$DBX_ESTADO" "reexecucao: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'reexecucao: bytes diferentes'
  assert_contem "content_hash=$(<"$base/hash")" "$DBX_SAIDA"
  assert_igual 0 "$(awk -v lim="$((3 * Q))" '$1 == "ini" && $2 != "seq" && $2 + 0 < lim { n++ } END { print n + 0 }' "$base/ev")" 'nao rebaixa o prefixo'
  assert_igual 1 "$(_conta_ev "$base" "^ini $((3 * Q)) ")" 'continua exatamente do prefixo'
  partes=$((($(wc -c <"$base/remoto.bin") - 3 * Q + Q - 1) / Q))
  assert_contem "paralelo=4 partes=$partes" "$DBX_ERRO" 'debug da retomada conta as faixas restantes'
  assert_igual '' "$(_part "$base")" 'sem .part ao fim'
  assert_igual 0 "$(_registros "$base")" 'registro removido ao fim'
}

# ---------------------------------------------------------------------------
# 5. 403: regra do sequencial
# ---------------------------------------------------------------------------

teste_403_numa_faixa_descarta_part_e_registro_sem_mv() {
  local base
  base=$(_ambiente "$T_FINAL_CURTA")
  printf 'alvo anterior' >"$base/trabalho/grande.iso"
  printf '403' >"$base/ctl/falha.$((3 * Q))"
  _down "$base" --paralelo 4
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar "403 deveria falhar: $DBX_SAIDA"
  assert_igual 'alvo anterior' "$(cat "$base/trabalho/grande.iso")" 'sem mv: alvo intacto'
  assert_igual '' "$(_part "$base")" '403 e definitivo: .part descartado, como no sequencial'
  assert_igual 0 "$(_registros "$base")" 'registro descartado'
  assert_igual 0 "$(_conta_ev "$base" "^ini $((4 * Q)) ")" 'nada novo despachado depois da falha definitiva (faixa 4 fora da janela)'
}

# ---------------------------------------------------------------------------
# 6. 429: pausa compartilhada
# ---------------------------------------------------------------------------

teste_429_numa_faixa_conclui_certo_e_a_faixa_repete_so_a_sua() {
  local base
  base=$(_ambiente "$T_FINAL_CURTA")
  printf '1' >"$base/ctl/r429.$Q"
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'bytes diferentes'
  assert_contem "content_hash=$(<"$base/hash")" "$DBX_SAIDA"
  assert_igual 1 "$(_conta_ev "$base" "^fim $Q 429")" 'o cenario precisa ter produzido o 429'
  assert_igual 2 "$(_conta_ev "$base" "^ini $Q ")" 'a faixa que recebeu o 429 repete (RF-182(a)); as demais nao'
  assert_igual 0 "$(awk '$1 == "ini" && $2 != "seq" && $2 != '"$Q"' { c[$2]++ } END { for (k in c) if (c[k] > 1) n++; print n + 0 }' "$base/ev")" 'nenhuma outra faixa repetida'
}

# Nome com prefixo z_: roda por ultimo, para que a reprovacao (achado do produto) nao esconda os demais casos.
teste_z_429_sem_faixa_nova_durante_a_pausa_compartilhada() {
  local base viol
  base=$(_ambiente "$T_FINAL_CURTA")
  printf '1' >"$base/ctl/r429.$Q"
  printf '1.5' >"$base/ctl/atraso.$Q"
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'bytes diferentes'
  assert_igual 1 "$(_conta_ev "$base" "^fim $Q 429")" 'o cenario precisa ter produzido o 429'
  viol=$(awk '
    $1 == "ini" { if (pausa && !($2 in vistos)) print "ini " $2 " durante a pausa"; vistos[$2] = 1 }
    $1 == "fim" { if ($3 == 429) { pausa = 1; alvo = $2 } else if (pausa && $2 == alvo) pausa = 0 }' "$base/ev")
  assert_igual '' "$viol" 'nenhuma faixa nova entre o 429 e o fim da faixa que o recebeu'
  assert_contem 'integridade=conferida' "$DBX_SAIDA"
}

# ---------------------------------------------------------------------------
# 7. 200 ignorando Range
# ---------------------------------------------------------------------------

teste_200_ignorando_range_avisa_e_recomeca_sequencial_unico_sem_laco() {
  local base
  base=$(_ambiente "$T_FINAL_CURTA")
  printf '0' >"$base/ctl/ignora"
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  assert_contem 'faixa ignorada' "$DBX_ERRO"
  _iguais "$base" || _harness_falhar 'o recomeco sequencial deveria entregar o remoto'
  assert_igual 1 "$(_conta_ev "$base" '^ini seq')" 'exatamente um recomeco sequencial'
  ((($(_conta_ev "$base" '^ini [0-9]')) <= 8)) || _harness_falhar 'laco de faixas: pedidos demais'
  assert_igual 1 "$(_conta_ev "$base" '^fim seq')" 'um so fim sequencial'
}

teste_200_ignorando_range_so_a_partir_da_faixa_3_recomeca_sequencial_unico() {
  local base
  base=$(_ambiente "$T_FINAL_CURTA")
  printf '%s' "$((3 * Q))" >"$base/ctl/ignora"
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  assert_contem 'faixa ignorada' "$DBX_ERRO"
  _iguais "$base" || _harness_falhar 'bytes diferentes'
  assert_igual 1 "$(_conta_ev "$base" '^ini seq')" 'exatamente um recomeco sequencial'
  assert_igual 0 "$(awk '$1 == "ini" && $2 != "seq" { c[$2]++ } END { for (k in c) if (c[k] > 1) n++; print n + 0 }' "$base/ev")" \
    'nenhuma faixa fechada reemitida (RF-180: faixa fechada nunca reemitida sem Range)'
  assert_igual '' "$(_part "$base")" 'sem .part'
}

# ---------------------------------------------------------------------------
# 8. Content-Range errado / revisao divergente: nunca gravada
# ---------------------------------------------------------------------------

_faixa_adulterada() { # <controle> <rotulo> <persistente: sim|nao>
  local base msg
  base=$(_ambiente "$T_FINAL_CURTA")
  printf 'alvo anterior' >"$base/trabalho/grande.iso"
  : >"$base/ctl/$1.$((2 * Q))"
  [[ $3 == sim ]] && : >"$base/ctl/rev_outra_todos"
  _down "$base" --paralelo 4
  if [[ $DBX_ESTADO -eq 0 ]]; then
    # So admitido quando a divergencia era da faixa: o produto a trata como faixa
    # ignorada (RF-104(d)) e recomeca sequencial; bytes adulterados nunca chegam ao alvo.
    [[ $3 == nao ]] || _harness_falhar "$2: divergencia persistente nao pode concluir com sucesso"
    assert_contem 'faixa ignorada' "$DBX_ERRO" "$2: sucesso so por recomeco sequencial avisado"
    _iguais "$base" || _harness_falhar "$2: sucesso com bytes adulterados publicados"
    return 0
  fi
  assert_igual 'alvo anterior' "$(cat "$base/trabalho/grande.iso")" "$2: sem mv"
  if [[ -n $(_part "$base") ]]; then
    msg=$(_prefixo_ok "$base" "$((2 * Q))") || _harness_falhar "$2: $msg"
  fi
}

teste_content_range_errado_numa_faixa_nao_e_gravado() { _faixa_adulterada crerrado 'Content-Range errado' nao; }
teste_revisao_divergente_numa_faixa_nao_e_gravada() { _faixa_adulterada revoutra 'revisao divergente na faixa' nao; }
teste_revisao_divergente_persistente_falha_sem_gravar_a_faixa() { _faixa_adulterada revoutra 'revisao divergente persistente' sim; }

teste_content_range_errado_so_na_faixa_2_nenhum_byte_adulterado_chega_ao_alvo() {
  local base
  base=$(_ambiente "$T_FINAL_CURTA")
  : >"$base/ctl/crerrado.$((2 * Q))"
  _down "$base" --paralelo 4
  if [[ $DBX_ESTADO -eq 0 ]]; then
    _iguais "$base" || _harness_falhar 'sucesso com bytes adulterados publicados'
  else
    [[ ! -e $base/trabalho/grande.iso ]] || _harness_falhar 'falha com alvo publicado'
  fi
}

# ---------------------------------------------------------------------------
# 9. SIGTERM
# ---------------------------------------------------------------------------

teste_sigterm_sem_orfaos_part_prefixo_contiguo_e_retomada_completa() {
  local base msg t
  base=$(_ambiente "$T_FINAL_CURTA")
  printf 'alvo anterior' >"$base/trabalho/grande.iso"
  printf '1' >"$base/ctl/sinal.$((5 * Q))"
  _down "$base" --paralelo 4
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'o sinal deveria interromper o comando'
  /bin/sleep 0.5
  if pgrep -f "$base/bin/curl" >/dev/null 2>&1; then _harness_falhar 'ficaram auxiliares orfaos'; fi
  assert_igual '' "$(find "$base/tmp" -name 'f.*' -print -quit)" 'sem faixas temporarias apos o sinal'
  assert_igual 'alvo anterior' "$(cat "$base/trabalho/grande.iso")" 'sem mv apos o sinal'
  msg=$(_prefixo_ok "$base" "$((5 * Q))") || _harness_falhar "$msg"
  assert_igual 1 "$(_registros "$base")" 'registro preservado'
  t=$(stat -c %s "$(_part "$base")")
  rm -f "$base/ctl/sinal.$((5 * Q))"
  : >"$base/ev"
  _down "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "retomada: $DBX_ERRO"
  _iguais "$base" || _harness_falhar 'retomada: bytes diferentes'
  assert_contem "content_hash=$(<"$base/hash")" "$DBX_SAIDA"
  assert_igual 0 "$(awk -v lim="$t" '$1 == "ini" && $2 != "seq" && $2 + 0 < lim { n++ } END { print n + 0 }' "$base/ev")" 'retomada nao rebaixa o prefixo'
  assert_igual 1 "$(_conta_ev "$base" "^ini $t ")" 'retomada continua de T'
}

# ---------------------------------------------------------------------------
# 10. Barreira do .part
# ---------------------------------------------------------------------------

teste_troca_do_part_durante_o_download_e_recusada_sem_tocar_no_outro_arquivo() {
  local base obs
  base=$(_ambiente "$T_FINAL_CURTA")
  printf 'alvo anterior' >"$base/trabalho/grande.iso"
  : >"$base/ctl/troca.$((2 * Q))"
  printf '1.2' >"$base/ctl/atraso.$((2 * Q))"
  _down "$base" --paralelo 4
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'a troca do .part deveria ser recusada'
  assert_igual 'alvo anterior' "$(cat "$base/trabalho/grande.iso")" 'sem mv: alvo intacto'
  obs=$(<"$base/obs.troca")
  assert_igual "$((2 * Q))" "$obs" 'precondicao: faixas 0 e 1 ja gravadas quando o .part foi trocado'
  [[ -n $(_part "$base") ]] || _harness_falhar 'o arquivo que tomou o lugar do .part deve ficar (barreira nao apaga arquivo alheio)'
  assert_igual "$obs" "$(stat -c %s "$(_part "$base")")" 'nenhum byte foi gravado no arquivo trocado'
}

# ---------------------------------------------------------------------------
# 11. Banda e debug
# ---------------------------------------------------------------------------

_bytes_de() { # <limit-rate do curl> -> bytes
  local v=$1
  case $v in
    *[kK]) printf '%s' $((${v%[kK]} * 1024)) ;;
    *[mM]) printf '%s' $((${v%[mM]} * 1048576)) ;;
    *) printf '%s' "$v" ;;
  esac
}

teste_limite_de_banda_dividido_entre_as_faixas() {
  local base lim min max
  base=$(_ambiente "$T_FINAL_CURTA")
  _down "$base" --paralelo 4 --limite-banda 8M
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  min=999999999999 max=0
  while read -r lim; do
    [[ $lim != '-' ]] || _harness_falhar 'faixa sem limit-rate'
    lim=$(_bytes_de "$lim")
    ((lim < min)) && min=$lim
    ((lim > max)) && max=$lim
  done < <(awk '$1 == "ini" && $2 != "seq" { print $4 }' "$base/ev")
  ((max <= 2097152 && min >= 1887436)) || _harness_falhar "limite por faixa fora de [90%, 100%] de 8 MiB/4: $min..$max"
  base=$(_ambiente "$T_FINAL_CURTA")
  _down "$base" --paralelo 2 --limite-banda 8M
  assert_igual 0 "$DBX_ESTADO" "N=2: $DBX_ERRO"
  max=$(awk '$1 == "ini" && $2 != "seq" { print $4; exit }' "$base/ev")
  max=$(_bytes_de "$max")
  ((max <= 4194304 && max >= 3774873)) || _harness_falhar "N=2: limite por faixa fora de 8 MiB/2: $max"
}

teste_debug_registra_paralelo_partes_e_cada_parte() {
  local base
  base=$(_ambiente "$T_FINAL_CURTA")
  _rodar "$base" --debug download --paralelo 4 /Grande.iso grande.iso
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  assert_contem 'paralelo=4 partes=10' "$DBX_ERRO"
  assert_contem 'parte=0 deslocamento=0' "$DBX_ERRO"
  assert_contem "parte=9 deslocamento=$((9 * Q))" "$DBX_ERRO"
  _iguais "$base" || _harness_falhar 'bytes diferentes'
}

# ---------------------------------------------------------------------------
# 12. Auditoria de texto
# ---------------------------------------------------------------------------

# _repeticoes_acima <texto> — imprime cada repeticao de regex com numero > 255.
_repeticoes_acima() {
  local r n
  while IFS= read -r r; do
    for n in $(grep -o -E '[0-9]+' <<<"$r"); do
      ((10#$n > 255)) && { printf '%s\n' "$r"; break; }
    done
  done < <(printf '%s\n' "$1" | grep -o -E '\{[0-9]+(,[0-9]*)?\\?\}|\{,[0-9]+\\?\}')
}

# _corpo_funcao <arquivo> <nome> — corpo de uma funcao de coluna zero.
_corpo_funcao() { awk -v n="$2" '$0 ~ "^" n "\\(\\) \\{" { d = 1 } d { print } d && /^}/ { exit }' "$1"; }

_codigo_novo() { # texto do codigo novo, sem comentarios de linha inteira
  local r=$DBX_HARNESS_RAIZ d
  {
    sed -e '/^[[:space:]]*#/d' "$r/lib/download_paralelo.sh"
    _corpo_funcao "$r/lib/http.sh" dbx_http_conteudo_receber_faixa | sed -e '/^[[:space:]]*#/d'
    _corpo_funcao "$r/lib/auth.sh" dbx_auth_conteudo_receber_faixa | sed -e '/^[[:space:]]*#/d'
    d=$(git -C "$r" diff -U0 HEAD -- lib/http.sh lib/auth.sh lib/cmd.sh 2>/dev/null | grep -E '^\+[^+]' | sed -e 's/^+//' -e '/^[[:space:]]*#/d')
    printf '%s\n' "$d"
  }
}

teste_o_auditor_de_repeticao_reconhece_as_formas_de_fronteira() {
  assert_igual '' "$(_repeticoes_acima 'x{1,255} y{255} z{0,9} w{,255}')" 'ate 255 e aceito'
  assert_contem '{1,256}' "$(_repeticoes_acima 'x{1,256}')"
  assert_contem '{256}' "$(_repeticoes_acima 'x{256}')"
  assert_contem '{,300}' "$(_repeticoes_acima 'x{,300}')"
  assert_contem '{1,999' "$(_repeticoes_acima 'grep x\{1,999\}')" 'forma BRE'
  assert_contem '{300,}' "$(_repeticoes_acima 'x{300,}')"
}

teste_auditoria_dos_arquivos_novos() {
  local texto achados
  texto=$(_codigo_novo)
  [[ -n $texto ]] || _harness_falhar 'auditoria vazia (arquivo novo nao encontrado)'
  achados=$(_repeticoes_acima "$texto")
  assert_igual '' "$achados" 'nenhuma repeticao de regex acima de 255 (RE_DUP_MAX do FreeBSD)'
  achados=$(grep -n '/dev/fd' <<<"$texto" || true)
  assert_igual '' "$achados" 'nenhum /dev/fd'
  achados=$(grep -n 'head -c' <<<"$texto" | grep -E '<&|>&|/dev/fd|\$\{?_?[A-Za-z_]*FD|\$fd' || true)
  assert_igual '' "$achados" 'nenhum head -c sobre descritor'
  achados=$(grep -n -E '\bdd\b.*(of=|conv=notrunc)' <<<"$texto" | grep -E 'fd|FD' || true)
  assert_igual '' "$achados" 'nenhum dd com saida por descritor'
}

# ---------------------------------------------------------------------------
# Mutacao: copia do produto com a ordem/prefixo quebrados; a suite tem de pegar
# ---------------------------------------------------------------------------

_copia_mutante() { # <rotulo> -> caminho do bin/dbx mutado em $DBX_TESTES_TMP
  local d="$DBX_TESTES_TMP/mut20.$1"
  rm -rf -- "$d"
  mkdir -p "$d"
  cp -r "$DBX_HARNESS_RAIZ/bin" "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands" "$d/"
  printf '%s' "$d"
}

teste_mutacao_a_gravar_a_faixa_assim_que_chega_e_pega_pela_ordem() {
  local d f base msg novo
  d=$(_copia_mutante a)
  f="$d/lib/download_paralelo.sh"
  novo=$(awk '
    /^    # Gravacao no `\.part`/ { pulando = 1; next }
    pulando && /^    vivos=0$/ {
      pulando = 0
      print "    while :; do"
      print "      w=-1"
      print "      for ((k = proximo - 1; k >= escrever; k--)); do [[ ${est[k]:-} == p ]] && { w=$k; break; }; done"
      print "      [[ $w -ge 0 ]] || break"
      print "      cat -- \"$_DBX_FAIXAS_PASTA/f.$w\" >&\"$fd\"; rm -f -- \"$_DBX_FAIXAS_PASTA/f.$w\"; est[w]=w"
      print "      while [[ ${est[escrever]:-} == w ]]; do escrever=$((escrever + 1)); done"
      print "    done"
    }
    !pulando { print }' "$f")
  [[ $novo != "$(cat "$f")" ]] || _harness_falhar 'mutacao a nao se aplicou'
  printf '%s\n' "$novo" >"$f"
  base=$(_ambiente "$T_FINAL_CURTA")
  printf '1.5' >"$base/ctl/atraso.0"
  DBX_T_EXEC="$d/bin/dbx" DBX_T_TETO=60 _down "$base" --paralelo 4
  if msg=$(_ordem_ok "$base"); then _harness_falhar 'o mutante (a) sobreviveu: a suite nao pega a gravacao fora de ordem'; fi
  printf '# mutante a reprovado por: %s\n' "$msg" >&2
}

teste_mutacao_b_contar_como_prefixo_faixa_nao_gravada_e_pega_pelos_bytes() {
  local d f base conteudo velho novo
  d=$(_copia_mutante b)
  f="$d/lib/download_paralelo.sh"
  conteudo=$(cat "$f")
  velho='! cat -- "$_DBX_FAIXAS_PASTA/f.$escrever" >&"$fd"; then'
  novo='! { [[ $escrever -eq 2 ]] || cat -- "$_DBX_FAIXAS_PASTA/f.$escrever" >&"$fd"; }; then'
  shopt -u patsub_replacement 2>/dev/null
  [[ $conteudo == *"$velho"* ]] || _harness_falhar 'mutacao b: trecho nao encontrado'
  printf '%s\n' "${conteudo/"$velho"/$novo}" >"$f"
  base=$(_ambiente "$T_FINAL_CURTA")
  DBX_T_EXEC="$d/bin/dbx" DBX_T_TETO=60 _down "$base" --paralelo 4
  # Mesmas assercoes de _bytes_e_hash: o produto percebe o content_hash errado e
  # recomeca sequencial (exit 0, bytes certos), mas o caminho sequencial inesperado
  # (`ini seq`, `retomada=recomecada`) e exatamente o que a suite real reprova.
  if [[ $DBX_ESTADO -eq 0 ]] && _iguais "$base" && [[ $(_conta_ev "$base" '^ini seq') -eq 0 ]] &&
    [[ $DBX_SAIDA != *'retomada=recomecada'* ]]; then
    _harness_falhar 'o mutante (b) sobreviveu: a suite nao pega a faixa contada e nao gravada'
  fi
  printf '# mutante b reprovado por: exit=%s seq=%s recomecada=%s\n' "$DBX_ESTADO" "$(_conta_ev "$base" '^ini seq')" \
    "$([[ $DBX_SAIDA == *'retomada=recomecada'* ]] && echo sim || echo nao)" >&2
}

harness_executar "$@"
