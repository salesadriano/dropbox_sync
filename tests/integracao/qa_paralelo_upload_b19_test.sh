#!/usr/bin/env bash
# Suite independente do QA, B19: upload de arquivo grande em partes simultaneas
# (F-100, etapa 2a; RF-177 a RF-183; DIV-358 a DIV-368; secoes 5.23 e 9 da
# especificacao). A suite do developer (paralelo_upload_test.sh) nao e base.
#
# Escrita como adversario, pelo executavel real `bin/dbx`. O duplo de `curl` e um
# servidor de sessao concorrente proprio: registra em `ev` cada chamada (`ini` e
# `fim`, em ordem de chegada, com deslocamento, close, tipo e limit-rate), guarda
# o corpo de CADA parte por deslocamento (`sess/<id>/d.<off>`, para `cmp`) e MONTA
# o arquivo no `finish`, calculando o content_hash pela montagem. A simultaneidade
# e a do `ev` (sobreposicao de ini/fim), nao do tempo de parede. O content_hash
# esperado e calculado AQUI, a partir do arquivo local, com o algoritmo publico da
# Dropbox (SHA-256 da concatenacao dos SHA-256 dos blocos de 4 MiB).
#
# Controles em $base/ctl (arquivos): recusa (codigo do start concurrent),
# falha.<off> (409 permanente), r429.<off> (um 429), atraso.<off> e atraso_todos
# (segundos de espera real), sinal (deslocamento) + sinal_apos (partes ja
# gravadas) -> TERM no dbx, seq_sinal (idem, so sessao sequencial), finish_recusa,
# expira (tag; so sessoes marcadas `velha`), expira_sempre (tag; todas).
#
# Origem dos dados: arquivos sinteticos gerados pela suite (urandom), sem segredo.
#
# shellcheck disable=SC2016,SC2034
# Justificativa: o duplo de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC_PADRAO="$DBX_HARNESS_RAIZ/bin/dbx"
readonly BLOCO=4194304
readonly PARTE=16777216
readonly LIMIAR=157286400
readonly T_LIMIAR_MAIS_1=$((LIMIAR + 1))
readonly T_MULTIPLO=$((10 * PARTE))
readonly T_FINAL_CURTA=$((10 * PARTE + 5))
readonly SESSAO='SESSAOQA19'

# _fixture <tamanho> — arquivo sintetico: 4 KiB aleatorios no inicio de cada bloco
# de 4 MiB e nos ultimos 16 bytes, o resto esparso.
_fixture() {
  local tam=$1 arquivo="$DBX_TESTES_TMP/qa19-$1.bin" i n
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

# _hash_local <arquivo> — content_hash esperado (algoritmo publico, independente).
_hash_local() {
  local arq=$1 tam k h esc i
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
  printf '%s' "${h%% *}"
}

_ambiente() { # <tamanho>
  local base tam=${1:-$T_LIMIAR_MAIS_1} velho
  # Cada caso usa so o ambiente mais recente: os anteriores (centenas de MiB de
  # partes e montagens) saem, para a suite nao esgotar o disco da area temporaria.
  for velho in "$DBX_TESTES_TMP"/qa19.*; do [[ -d $velho ]] && rm -rf -- "$velho"; done
  base=$(mktemp -d "$DBX_TESTES_TMP/qa19.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/tmp" "$base/trabalho" "$base/sess" "$base/vivos" "$base/ctl"
  chmod 700 "$base/config/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  cp --sparse=always "$(_fixture "$tam")" "$base/trabalho/grande.iso"
  touch -d '1 hour ago' "$base/trabalho/grande.iso"
  head -c 1048576 /dev/urandom >"$base/trabalho/pequeno.bin"
  : >"$base/ev"
  {
    printf '#!%s\n' "$BASH"
    printf 'base=%q\ntoken=sl.token_qa19\nsentinela=%q\n' "$base" "$SESSAO"
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
arg='' limite='-'
while IFS= read -r linha; do
  case $linha in
    'header = "Dropbox-API-Arg: '*) arg=${linha#'header = "Dropbox-API-Arg: '}; arg=${arg%\"}; arg=${arg//\\\"/\"}; arg=${arg//\\\\/\\} ;;
    'limit-rate = '*) limite=${linha#'limit-rate = '} ;;
  esac
done <<<"$conf"
ep=${url#https://*/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
sid=''; off=''; fechar=''; conc=nao
[[ $arg =~ \"session_id\":\"([^\"]*)\" ]] && sid=${BASH_REMATCH[1]}
[[ $arg =~ \"offset\":([0-9]+) ]] && off=${BASH_REMATCH[1]}
[[ $arg =~ \"close\":(true|false) ]] && fechar=${BASH_REMATCH[1]}
[[ $arg == *concurrent* ]] && conc=sim
pid=$(<"$base/pid")
vivo="$base/vivos/$$"
trap 'rm -f "$vivo"' EXIT
codigo=200 resposta='{}' extra=''
erro() { codigo=409; resposta="{\"error_summary\":\"$1\",\"error\":{\".tag\":\"${1%%/*}\"}}"; }
registrar() { [[ $ep == files/upload_session/* ]] && printf '%s\n' "$*" >>"$base/ev"; }
ctl() { [[ -e $base/ctl/$1 ]]; }
case $ep in
  oauth2/token) resposta="{\"access_token\":\"$token\",\"token_type\":\"bearer\",\"expires_in\":14400}" ;;
  files/get_metadata|files/list_folder) erro 'path/not_found/' ;;
  users/get_space_usage) resposta='{"used":0,"allocation":{".tag":"individual","allocated":1000000000000}}' ;;
  files/upload) printf 'upload_unico\n' >>"$base/ev"; resposta='{".tag":"file","name":"x","path_display":"/X","id":"id:2","rev":"0123456789b","size":1,"server_modified":"2026-01-01T00:00:00Z","client_modified":"2026-01-01T00:00:00Z"}' ;;
  files/upload_session/start)
    registrar "ini start - - $conc $limite"
    if [[ $conc == sim ]] && ctl recusa; then
      codigo=$(<"$base/ctl/recusa"); resposta='{"error_summary":"invalid_arguments/","error":{".tag":"invalid_arguments"}}'
    else
      sid="$sentinela-$$"
      mkdir -p "$base/sess/$sid"
      printf '%s' "$conc" >"$base/sess/$sid/conc"
      printf 0 >"$base/sess/$sid/offset"
      resposta="{\"session_id\":\"$sid\"}"
    fi
    registrar "fim start - $codigo"
    ;;
  files/upload_session/append_v2)
    conc_s=nao
    [[ -r $base/sess/$sid/conc ]] && conc_s=$(<"$base/sess/$sid/conc")
    registrar "ini append $off $fechar $conc_s $limite"
    : >"$vivo"
    printf '%s\n' "$(ls "$base/vivos" | wc -l)" >>"$base/picos"
    if [[ ! -d $base/sess/$sid ]]; then erro 'not_found/'
    else
      [[ -e $base/ctl/atraso_todos ]] && command -p sleep "$(<"$base/ctl/atraso_todos")"
      [[ -e $base/ctl/atraso.$off ]] && command -p sleep "$(<"$base/ctl/atraso.$off")"
      if ctl sinal && [[ $off == "$(<"$base/ctl/sinal")" ]]; then
        k=0
        until [[ $(ls "$base"/sess/*/d.* 2>/dev/null | wc -l) -ge $(<"$base/ctl/sinal_apos") || $k -ge 150 ]]; do
          command -p sleep 0.1; k=$((k + 1))
        done
        command -p sleep 0.5
        kill -s TERM "$pid"; command -p sleep 5; exit 7
      fi
      if ctl seq_sinal && [[ $conc_s == nao && $off == "$(<"$base/ctl/seq_sinal")" ]]; then
        kill -s TERM "$pid"; command -p sleep 5; exit 7
      fi
      if ctl expira_sempre || { ctl expira && [[ -e $base/sess/$sid/velha ]]; }; then
        [[ -e $base/ctl/expira_sempre ]] && t=$(<"$base/ctl/expira_sempre") || t=$(<"$base/ctl/expira")
        erro "$t/"
      elif ctl "falha.$off"; then
        erro 'other/'
      elif ctl "r429.$off" && mv "$base/ctl/r429.$off" "$base/ctl/r429.$off.usado" 2>/dev/null; then
        codigo=429; resposta='{"error_summary":"too_many_requests/"}'; extra='Retry-After: 1'
      elif [[ $conc_s == nao && $off != "$(<"$base/sess/$sid/offset")" ]]; then
        codigo=409; resposta="{\"error_summary\":\"incorrect_offset/\",\"error\":{\".tag\":\"incorrect_offset\",\"correct_offset\":$(<"$base/sess/$sid/offset")}}"
      else
        printf -v nome 'd.%012d' "$off"
        cp "$dados" "$base/sess/$sid/$nome"
        printf '%s' "$((off + $(wc -c <"$dados")))" >"$base/sess/$sid/offset"
        [[ $fechar == true ]] && : >"$base/sess/$sid/fechou"
      fi
    fi
    registrar "fim append $off $codigo"
    ;;
  files/upload_session/finish)
    total=$(wc -c <"$base/trabalho/grande.iso")
    conc_s=nao
    [[ -r $base/sess/$sid/conc ]] && conc_s=$(<"$base/sess/$sid/conc")
    registrar "ini finish $off - $conc_s $limite"
    if [[ ! -d $base/sess/$sid ]]; then erro 'lookup_failed/not_found/'
    elif ctl finish_recusa; then erro 'lookup_failed/not_found/'
    else
      tam_f=$(wc -c <"$dados")
      if [[ $tam_f -gt 0 ]]; then printf -v nome 'd.%012d' "$off"; cp "$dados" "$base/sess/$sid/$nome"; fi
      cat "$base/sess/$sid"/d.* >"$base/montado" 2>/dev/null
      if [[ $((off + tam_f)) != "$total" || $(wc -c <"$base/montado") != "$total" ]]; then
        codigo=409; resposta='{"error_summary":"lookup_failed/incorrect_offset/","error":{".tag":"lookup_failed","lookup_failed":{".tag":"incorrect_offset","correct_offset":0}}}'
      else
        : >"$base/cadeia"
        for ((o = 0; o < total; o += 4194304)); do
          h=$(dd if="$base/montado" bs=4194304 skip=$((o / 4194304)) count=1 2>/dev/null | sha256sum); h=${h%% *}
          esc=''
          for ((i = 0; i < 64; i += 2)); do esc+="\\x${h:i:2}"; done
          printf '%b' "$esc" >>"$base/cadeia"
        done
        ch=$(sha256sum <"$base/cadeia"); ch=${ch%% *}
        printf '%s' "$ch" >"$base/publicado"
        resposta="{\".tag\":\"file\",\"name\":\"grande.iso\",\"path_display\":\"/Grande.iso\",\"id\":\"id:1\",\"rev\":\"0123456789a\",\"size\":$total,\"content_hash\":\"$ch\",\"server_modified\":\"2026-01-01T00:00:00Z\",\"client_modified\":\"2026-01-01T00:00:00Z\"}"
      fi
    fi
    registrar "fim finish $off $codigo"
    ;;
  *) erro 'sem_regra/' ;;
esac
[[ -n $cabecalhos ]] && printf 'HTTP/1.1 %s X\r\n%s\r\n\r\n' "$codigo" "$extra" >"$cabecalhos"
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

_rodar() {
  local base=$1
  shift
  (
    cd "$base/trabalho" || exit 99
    env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
      DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout -k 2 "${DBX_T_TETO:-240}" setsid -w bash -c 'printf "%s" "$$" >"$1/pid"; shift; exec bash "$@"' _ \
      "$base" "$DBX_EXEC_PADRAO" "$@" </dev/null >"$base/out" 2>"$base/err"
  ) 2>/dev/null
  DBX_ESTADO=$?
  DBX_SAIDA='' DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_up() { _rodar "$1" "${@:2}" upload grande.iso /Grande.iso; } # <base> [opcoes globais] — upload vem depois
_upp() { _rodar "$1" upload "${@:2}" grande.iso /Grande.iso; } # <base> [opcoes do upload...]

_conta() { grep -c -E -- "$2" "$1/ev" || true; } # <base> <regex em ev>
# _ini_offsets <base> — deslocamentos dos appends iniciados, ordenados.
_ini_offsets() {
  local e ep o r
  while read -r e ep o r; do [[ $e == ini && $ep == append ]] && printf '%s\n' "$o"; done <"$1/ev" | sort -n | tr '\n' ' '
}
# _pico_ev <base> — maior numero de appends sobrepostos (ini sem fim) em ev.
_pico_ev() {
  local e ep r n=0 max=0
  while read -r e ep r; do
    [[ $ep == append ]] || continue
    if [[ $e == ini ]]; then n=$((n + 1)); ((n > max)) && max=$n; else n=$((n - 1)); fi
  done <"$1/ev"
  printf '%s' "$max"
}
_esperados() { # <tamanho> — deslocamentos de todas as partes
  local i s='' partes=$((($1 + PARTE - 1) / PARTE))
  for ((i = 0; i < partes; i++)); do s+="$((i * PARTE)) "; done
  printf '%s' "$s"
}
_registro_arquivo() { local r; for r in "$1"/estado/dbx/retomada-*; do [[ -f $r ]] && { printf '%s' "$r"; return 0; }; done; return 1; }
_registro_campo() { # <base> <indice>
  local r f c=()
  r=$(_registro_arquivo "$1") || return 0
  while IFS= read -r -d '' f; do c+=("$f"); done <"$r"
  printf '%s' "${c[$2]:-}"
}
_registros() { local r n=0; for r in "$1"/estado/dbx/retomada-*; do [[ -e $r ]] && n=$((n + 1)); done; printf '%s' "$n"; }
_residuo() {
  local e lista=''
  for e in "$1"/tmp/* "$1"/tmp/.[!.]*; do [[ -e $e ]] && lista+=" ${e##*/}"; done
  printf '%s' "$lista"
}
# _orfaos <base> — processos ainda vivos com diretorio de trabalho na base.
_orfaos() {
  local p l=''
  for p in /proc/[0-9]*; do
    [[ $(readlink "$p/cwd" 2>/dev/null) == "$1/trabalho" ]] && l+=" ${p#/proc/}"
  done
  printf '%s' "$l"
}
_matar_orfaos() { local p; for p in $(_orfaos "$1"); do kill -KILL "$p" 2>/dev/null; done; return 0; }
_sessao_dir() { local d; for d in "$1"/sess/*; do [[ -d $d ]] && { printf '%s' "$d"; return 0; }; done; return 1; }
_confirmadas() { # <intervalos a-b,c-d> -> " 0 1 2 "
  local item a b i s=' '
  for item in ${1//,/ }; do
    [[ $item == '-' ]] && continue
    a=${item%-*} b=${item#*-}
    for ((i = a; i <= b; i++)); do s+="$i "; done
  done
  printf '%s' "$s"
}
_complemento() { # <tamanho> <confirmadas " 0 1 "> -> deslocamentos faltantes
  local i s='' partes=$((($1 + PARTE - 1) / PARTE))
  for ((i = 0; i < partes; i++)); do [[ $2 == *" $i "* ]] || s+="$((i * PARTE)) "; done
  printf '%s' "$s"
}
_sem_erro_de_shell() { # <texto>
  local t
  for t in ': line [0-9]' 'unbound variable' 'syntax error' 'command not found' 'bad substitution' 'value too great' 'integer expression'; do
    [[ $1 =~ $t ]] && _harness_falhar "erro de shell vazou na saida: $t" "$1"
  done
  return 0
}
_publicou_certo() { # <base> <tamanho> — bytes, hash e ausencia de lacunas
  local base=$1 tam=$2 esperado
  assert_igual 0 "$DBX_ESTADO" "upload deveria concluir; erro: $DBX_ERRO"
  cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar 'bytes publicados diferem do arquivo local (cmp)'
  esperado=$(_hash_local "$base/trabalho/grande.iso")
  assert_igual "$esperado" "$(<"$base/publicado")" 'content_hash publicado difere do calculado do arquivo local'
  assert_contem 'conferida' "$DBX_SAIDA" 'integridade conferida'
  assert_igual 0 "$(_registros "$base")" 'registro removido apos a publicacao'
  assert_igual '' "$(_residuo "$base")" 'sem residuo no TMPDIR'
  assert_igual '' "$(_orfaos "$base")" 'sem processo vivo'
}
_partes_gravadas() { # <base> <tamanho> — cada parte guardada tem o tamanho certo e o conteudo do trecho
  local base=$1 tam=$2 d i n off esperado
  d=$(_sessao_dir "$base") || _harness_falhar 'sem sessao no servidor'
  n=$(((tam + PARTE - 1) / PARTE))
  for ((i = 0; i < n; i++)); do
    printf -v off '%s/d.%012d' "$d" $((i * PARTE))
    esperado=$((tam - i * PARTE))
    ((esperado > PARTE)) && esperado=$PARTE
    [[ -f $off ]] || _harness_falhar "parte $i ausente no servidor"
    assert_igual "$esperado" "$(wc -c <"$off")" "tamanho da parte $i"
    dd if="$base/trabalho/grande.iso" bs=$PARTE skip="$i" count=1 2>/dev/null | cmp -s - "$off" ||
      _harness_falhar "conteudo da parte $i diverge do trecho do arquivo local"
  done
}

# ---------------------------------------------------------------- item 1
_caso_bytes() { # <tamanho> <rotulo>
  local base tam=$1
  base=$(_ambiente "$tam")
  DBX_T_TETO=300 _upp "$base" --paralelo 4
  _publicou_certo "$base" "$tam"
  assert_igual "$(_esperados "$tam")" "$(_ini_offsets "$base")" 'cada parte enviada exatamente uma vez'
  _partes_gravadas "$base" "$tam"
  assert_igual 1 "$(_conta "$base" '^ini start - - sim')" 'start concurrent'
  assert_igual 1 "$(_conta "$base" "^ini finish $tam - sim")" 'finish com offset = total, em sessao concorrente'
  assert_igual 1 "$(_conta "$base" '^ini append [0-9]+ true')" 'um unico close'
  assert_igual 1 "$(_conta "$base" "^ini append $((((tam + PARTE - 1) / PARTE - 1) * PARTE)) true")" 'o close e da ultima parte'
}
teste_b19_bytes_e_hash_limiar_mais_1() { _caso_bytes "$T_LIMIAR_MAIS_1"; }
teste_b19_bytes_e_hash_multiplo_exato_de_16_mib() { _caso_bytes "$T_MULTIPLO"; }
teste_b19_bytes_e_hash_parte_final_de_5_bytes() { _caso_bytes "$T_FINAL_CURTA"; }

# ---------------------------------------------------------------- item 2
teste_b19_no_maximo_n_em_voo_e_mais_de_um() {
  local base n pico
  for n in 2 3; do
    base=$(_ambiente "$T_LIMIAR_MAIS_1")
    echo 0.4 >"$base/ctl/atraso_todos"
    _upp "$base" --paralelo "$n"
    assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
    pico=$(_pico_ev "$base")
    ((pico <= n)) || _harness_falhar "N=$n e pico em ev=$pico (acima de N)"
    ((pico > 1)) || _harness_falhar "N=$n e pico=$pico (sem simultaneidade)"
    assert_igual "$n" "$(sort -n "$base/picos" | tail -n 1)" "pico observado pelo duplo para N=$n com partes lentas"
    cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar 'bytes diferem'
  done
}

# ---------------------------------------------------------------- item 3
teste_b19_n1_e_abaixo_do_limiar_nao_tem_chamada_concorrente() {
  local base
  base=$(_ambiente "$T_LIMIAR_MAIS_1")
  echo 0.2 >"$base/ctl/atraso_todos"
  _upp "$base" --paralelo 1
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_igual 0 "$(_conta "$base" ' sim')" 'nenhuma chamada concorrente com N=1'
  assert_igual 1 "$(_pico_ev "$base")" 'uma chamada por vez'
  cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar 'bytes diferem'
  # abaixo do limiar e exatamente no limiar: requisicao unica, N sem efeito
  base=$(_ambiente "$LIMIAR")
  _upp "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_contem 'requisicao_unica' "$DBX_SAIDA"
  assert_igual 0 "$(_conta "$base" 'start|append')" 'nenhuma sessao no limiar exato'
  base=$(_ambiente "$T_LIMIAR_MAIS_1")
  _rodar "$base" upload --paralelo 4 pequeno.bin /Pequeno.bin
  assert_contem 'requisicao_unica' "$DBX_SAIDA"
  assert_igual 0 "$(_conta "$base" 'start|append')" 'nenhuma sessao abaixo do limiar'
}

# ---------------------------------------------------------------- item 4
teste_b19_falha_definitiva_sem_finish_registro_v2_e_reexecucao_so_do_que_falta() {
  local base conf tam=$T_LIMIAR_MAIS_1 esperado classe
  base=$(_ambiente "$tam")
  : >"$base/ctl/falha.$((3 * PARTE))"
  _upp "$base" --paralelo 4
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'deveria falhar'
  classe=$DBX_ESTADO
  assert_igual 0 "$(_conta "$base" 'finish')" 'nenhum finish'
  [[ ! -e $base/publicado ]] || _harness_falhar 'publicou apesar da falha'
  assert_igual 1 "$(_registros "$base")" 'registro preservado'
  assert_igual 2 "$(_registro_campo "$base" 1)" 'registro v2'
  assert_igual concurrent "$(_registro_campo "$base" 7)" 'tipo da sessao'
  conf=$(_confirmadas "$(_registro_campo "$base" 12)")
  [[ $conf != *' 3 '* ]] || _harness_falhar "parte 3 (que falhou) consta como confirmada: $conf"
  assert_nao_contem "$SESSAO" "$DBX_ERRO" 'session_id nao vaza'
  assert_igual '' "$(_residuo "$base")" 'sem residuo no TMPDIR'
  assert_igual '' "$(_orfaos "$base")" 'sem processo vivo'
  printf '# codigo da classe na falha de parte: %s\n' "$classe" >&2
  esperado=$(_complemento "$tam" "$conf")
  rm -f "$base/ctl/falha.$((3 * PARTE))"
  : >"$base/ev"
  _upp "$base" --paralelo 4
  assert_igual "$esperado" "$(_ini_offsets "$base")" 'reexecucao envia so o que faltava'
  assert_igual 0 "$(_conta "$base" '^ini start')" 'sem novo start'
  _publicou_certo "$base" "$tam"
}

# ---------------------------------------------------------------- item 5
teste_b19_sigterm_sem_orfaos_sem_publicacao_registro_coerente_e_retomada() {
  local base conf tam=$T_LIMIAR_MAIS_1 esperado i d off
  base=$(_ambiente "$tam")
  printf '%s' "$((3 * PARTE))" >"$base/ctl/sinal"
  echo 3 >"$base/ctl/sinal_apos"
  _upp "$base" --paralelo 2
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'interrompido por SIGTERM deveria sair com erro'
  assert_igual '' "$(_orfaos "$base")" 'nenhum auxiliar vivo depois do termino'
  _matar_orfaos "$base"
  assert_igual 0 "$(_conta "$base" 'finish')" 'nenhum finish'
  [[ ! -e $base/publicado ]] || _harness_falhar 'publicou apos SIGTERM'
  assert_igual '' "$(_residuo "$base")" 'sem residuo no TMPDIR'
  assert_igual 1 "$(_registros "$base")" 'registro v2 preservado'
  assert_igual 2 "$(_registro_campo "$base" 1)" 'versao 2'
  conf=$(_confirmadas "$(_registro_campo "$base" 12)")
  [[ $conf == *' 0 '* ]] || _harness_falhar "nenhuma parte confirmada: $conf"
  [[ $conf != *' 3 '* ]] || _harness_falhar "parte em voo no TERM consta como confirmada: $conf"
  d=$(_sessao_dir "$base")
  for i in $conf; do
    printf -v off '%s/d.%012d' "$d" $((i * PARTE))
    [[ -f $off ]] || _harness_falhar "parte $i consta no registro mas nunca chegou ao servidor"
  done
  esperado=$(_complemento "$tam" "$conf")
  rm -f "$base/ctl/sinal" "$base/ctl/sinal_apos"
  : >"$base/ev"
  _upp "$base" --paralelo 2
  assert_igual "$esperado" "$(_ini_offsets "$base")" 'retomada reenvia o que faltava, inclusive a que estava em voo'
  assert_igual 0 "$(_conta "$base" '^ini start')" 'sem novo start na retomada'
  _publicou_certo "$base" "$tam"
}

# ---------------------------------------------------------------- item 6
teste_b19_finish_recusado_em_modo_concorrente_falha_sem_vazar_e_reexecucao_so_finaliza() {
  local base tam=$T_LIMIAR_MAIS_1
  base=$(_ambiente "$tam")
  : >"$base/ctl/finish_recusa"
  _upp "$base" --paralelo 4
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'finish recusado deveria falhar'
  assert_igual 1 "$(_conta "$base" '^ini finish')" 'uma tentativa de finish'
  assert_igual 1 "$(_conta "$base" '^ini start')" 'nao recomeca em modo concorrente'
  [[ ! -e $base/publicado ]] || _harness_falhar 'publicou'
  assert_nao_contem "$SESSAO" "$DBX_ERRO" 'session_id nao vaza'
  _sem_erro_de_shell "$DBX_ERRO"
  assert_igual '' "$(_orfaos "$base")" 'sem processo vivo'
  printf '# registros apos finish recusado: %s\n' "$(_registros "$base")" >&2
  rm -f "$base/ctl/finish_recusa"
  : >"$base/ev"
  _upp "$base" --paralelo 4
  if [[ $(_registros "$base") == 0 && $DBX_ESTADO -eq 0 ]]; then
    printf '# reexecucao: appends=%s starts=%s\n' "$(_conta "$base" '^ini append')" "$(_conta "$base" '^ini start')" >&2
    cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar 'bytes diferem'
  fi
  assert_igual 0 "$DBX_ESTADO" "reexecucao deveria publicar; erro: $DBX_ERRO"
  cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar 'bytes diferem apos reexecucao'
}

_interrompida() { # <base> — deixa registro v2 e sessao no servidor, marcada velha
  local d
  printf '%s' "$((3 * PARTE))" >"$1/ctl/sinal"
  echo 3 >"$1/ctl/sinal_apos"
  _upp "$1" --paralelo 2
  _matar_orfaos "$1"
  assert_igual 1 "$(_registros "$1")" 'registro apos a interrupcao'
  # Nota: residuo de TMPDIR logo apos o TERM e medido no caso do SIGTERM; aqui so a
  # reexecucao interessa.
  rm -rf -- "$1"/tmp/dbx-http.* 2>/dev/null
  for d in "$1"/sess/*; do : >"$d/velha"; done
  rm -f "$1/ctl/sinal" "$1/ctl/sinal_apos"
  : >"$1/ev"
}
teste_b19_sessao_expirada_not_found_recomeca_do_zero_uma_vez() {
  local base tam=$T_LIMIAR_MAIS_1
  base=$(_ambiente "$tam")
  _interrompida "$base"
  printf not_found >"$base/ctl/expira"
  _upp "$base" --paralelo 2
  assert_contem 'expirada' "$DBX_ERRO" 'aviso de sessao expirada'
  assert_igual 1 "$(_conta "$base" '^ini start - - sim')" 'um novo start concorrente'
  _publicou_certo "$base" "$tam"
}
teste_b19_sessao_fechada_closed_recomeca_do_zero() {
  local base tam=$T_LIMIAR_MAIS_1
  base=$(_ambiente "$tam")
  _interrompida "$base"
  printf closed >"$base/ctl/expira"
  _upp "$base" --paralelo 2
  assert_contem 'expirada' "$DBX_ERRO" 'aviso de sessao expirada'
  assert_igual 1 "$(_conta "$base" '^ini start - - sim')" 'um novo start concorrente'
  _publicou_certo "$base" "$tam"
}
teste_b19_sessao_expirada_de_novo_nao_entra_em_laco() {
  local base tam=$T_LIMIAR_MAIS_1
  base=$(_ambiente "$tam")
  _interrompida "$base"
  printf not_found >"$base/ctl/expira_sempre"
  _upp "$base" --paralelo 2
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'sessao que expira sempre deveria acabar em erro'
  assert_igual 1 "$(_conta "$base" '^ini start')" 'recomeca UMA vez (um start novo), sem laco'
  [[ ! -e $base/publicado ]] || _harness_falhar 'publicou'
  assert_igual '' "$(_orfaos "$base")" 'sem processo vivo'
}

# ---------------------------------------------------------------- item 7
teste_b19_limite_de_banda_dividido_entre_as_partes() {
  local base e ep o r a b lim
  base=$(_ambiente "$T_LIMIAR_MAIS_1")
  _upp "$base" --paralelo 4 --limite-banda 4194304
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  while read -r e ep o a b lim; do
    [[ $e == ini && $ep == append ]] || continue
    assert_igual 1048576 "$lim" "taxa do auxiliar da parte $o = total/N"
  done <"$base/ev"
  assert_igual 10 "$(_conta "$base" '^ini append')" 'dez appends'
  # abaixo do piso (2 x velocidade minima): o auxiliar nunca fica abaixo dele
  base=$(_ambiente "$T_LIMIAR_MAIS_1")
  _upp "$base" --paralelo 4 --limite-banda 6000
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  while read -r e ep o a b lim; do
    [[ $e == ini && $ep == append ]] || continue
    assert_igual 2048 "$lim" "taxa minima do auxiliar da parte $o"
  done <"$base/ev"
  # N=1: o teto inteiro
  base=$(_ambiente "$T_LIMIAR_MAIS_1")
  _upp "$base" --limite-banda 4194304
  while read -r e ep o a b lim; do
    [[ $e == ini && $ep == append ]] || continue
    assert_igual 4194304 "$lim" 'N=1 leva o teto inteiro'
  done <"$base/ev"
}

# ---------------------------------------------------------------- item 8 e 9
_molde() { # <base> — registro v2 real, barato: a parte 0 falha e o envio para
  : >"$1/ctl/falha.0"
  _upp "$1" --paralelo 2
  [[ $(_registros "$1") == 1 && $(_registro_campo "$1" 1) == 2 ]] || _harness_falhar 'molde de registro v2 nao gravado'
  rm -f "$1/ctl/falha.0"
  : >"$1/ev"
}
_forjar() { # <base> <indice> <valor> — reescreve um campo do registro (NUL)
  local r f c=() i
  r=$(_registro_arquivo "$1")
  while IFS= read -r -d '' f; do c+=("$f"); done <"$r"
  c[$2]=$3
  : >"$r"
  for f in "${c[@]}"; do printf '%s\0' "$f" >>"$r"; done
}
_caso_hostil() { # <indice> <valor>
  local base tam=$T_LIMIAR_MAIS_1
  base=$(_ambiente "$tam")
  _molde "$base"
  _forjar "$base" "$1" "$2"
  _upp "$base" --paralelo 4
  _sem_erro_de_shell "$DBX_ERRO"
  assert_igual 0 "$DBX_ESTADO" "registro hostil nao pode derrubar o envio; erro: $DBX_ERRO"
  case $DBX_ERRO in *descartado* | *recomeca*) ;; *) _harness_falhar 'sem aviso de descarte' "$DBX_ERRO" ;; esac
  assert_igual 1 "$(_conta "$base" '^ini start - - sim')" 'recomeco com sessao nova'
  _publicou_certo "$base" "$tam"
}
teste_b19_registro_hostil_intervalo_nao_numerico() { _caso_hostil 12 'x-y'; }
teste_b19_registro_hostil_intervalo_invertido() { _caso_hostil 12 '3-1'; }
teste_b19_registro_hostil_intervalo_alem_das_partes() { _caso_hostil 12 '0-99'; }
teste_b19_registro_hostil_intervalos_fora_de_ordem() { _caso_hostil 12 '5-6,1-2'; }
teste_b19_registro_hostil_intervalos_adjacentes_nao_fundidos() { _caso_hostil 12 '1-2,3-4'; }
teste_b19_registro_hostil_intervalo_repetido() { _caso_hostil 12 '2-2,2-2'; }
teste_b19_registro_hostil_intervalos_sobrepostos() { _caso_hostil 12 '1-4,3-5'; }
teste_b19_registro_hostil_mais_de_256_intervalos() {
  local s='' i
  for ((i = 0; i < 300; i++)); do s+="${s:+,}$((2 * i))-$((2 * i))"; done
  _caso_hostil 12 "$s"
}
teste_b19_registro_hostil_tamanho_de_parte_invalido() { _caso_hostil 8 '16777217'; }
teste_b19_registro_hostil_total_nao_numerico() { _caso_hostil 9 'abc'; }
teste_b19_registro_hostil_sessao_com_espaco() { _caso_hostil 6 'a b'; }
teste_b19_registro_hostil_tipo_diferente_de_concurrent() { _caso_hostil 7 'sequential'; }
teste_b19_registro_hostil_identidade_invalida() { _caso_hostil 10 'lixo'; }
teste_b19_registro_hostil_total_diferente_do_arquivo() { _caso_hostil 9 '999999999'; }
teste_b19_registro_hostil_truncado() {
  local base tam=$T_LIMIAR_MAIS_1 r
  base=$(_ambiente "$tam")
  _molde "$base"
  r=$(_registro_arquivo "$base")
  head -c 120 "$r" >"$r.t" && mv "$r.t" "$r"
  _upp "$base" --paralelo 4
  _sem_erro_de_shell "$DBX_ERRO"
  _publicou_certo "$base" "$tam"
}

teste_b19_registro_v2_com_n1_e_descartado_com_aviso_e_recomeca() {
  local base tam=$T_LIMIAR_MAIS_1
  base=$(_ambiente "$tam")
  _molde "$base"
  _upp "$base"
  _sem_erro_de_shell "$DBX_ERRO"
  case $DBX_ERRO in *descartado* | *recomeca*) ;; *) _harness_falhar 'sem aviso ao descartar o v2 com N=1' "$DBX_ERRO" ;; esac
  assert_igual 0 "$(_conta "$base" ' sim')" 'recomeco sequencial, nada concorrente'
  assert_igual 1 "$(_pico_ev "$base")" 'sequencial'
  _publicou_certo "$base" "$tam"
}
teste_b19_registro_v1_com_n_maior_que_1_retoma_em_sequencia() {
  local base tam=$T_LIMIAR_MAIS_1
  base=$(_ambiente "$tam")
  printf '%s' "$((3 * BLOCO))" >"$base/ctl/seq_sinal"
  _upp "$base"
  assert_igual 1 "$(_registro_campo "$base" 1)" 'registro v1'
  _matar_orfaos "$base"
  rm -f "$base/ctl/seq_sinal"
  : >"$base/ev"
  echo 0.1 >"$base/ctl/atraso_todos"
  _upp "$base" --paralelo 4
  assert_igual 0 "$(_conta "$base" '^ini start')" 'sessao v1 retomada, sem start'
  assert_igual 0 "$(_conta "$base" ' sim')" 'nada concorrente'
  assert_igual 1 "$(_pico_ev "$base")" 'sequencial'
  _publicou_certo "$base" "$tam"
}

# ---------------------------------------------------------------- item 10
_caso_recusa() { # <codigo http do start concurrent>
  local base tam=$T_LIMIAR_MAIS_1
  base=$(_ambiente "$tam")
  printf '%s' "$1" >"$base/ctl/recusa"
  _upp "$base" --paralelo 4
  assert_contem 'sessao concorrente' "$DBX_ERRO" 'aviso da recusa'
  assert_igual 1 "$(_conta "$base" '^ini start - - sim')" 'um start concurrent (recusado)'
  assert_igual 1 "$(_conta "$base" '^ini start - - nao')" 'um start sequencial'
  assert_igual 1 "$(_pico_ev "$base")" 'envio sequencial'
  assert_nao_contem "$SESSAO" "$DBX_ERRO"
  _publicou_certo "$base" "$tam"
}
teste_b19_recusa_400_do_concurrent_cai_para_sequencial() { _caso_recusa 400; }
teste_b19_recusa_403_do_concurrent_cai_para_sequencial() { _caso_recusa 403; }
teste_b19_recusa_409_do_concurrent_cai_para_sequencial() { _caso_recusa 409; }
teste_b19_erro_5xx_no_start_nao_cai_para_sequencial() {
  local base
  base=$(_ambiente "$T_LIMIAR_MAIS_1")
  printf 500 >"$base/ctl/recusa"
  _upp "$base" --paralelo 4
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar '5xx no start deveria falhar'
  assert_igual 0 "$(_conta "$base" '^ini start - - nao')" 'sem start sequencial'
  assert_igual 0 "$(_conta "$base" '^ini append')" 'nenhuma parte'
}

# ---------------------------------------------------------------- item 11
teste_b19_429_nao_despacha_parte_nova_durante_a_pausa() {
  local base ordem e ep o r aberto=() i seen=' ' pausa='nao' fim429 viol='' abertos_n
  base=$(_ambiente "$T_LIMIAR_MAIS_1")
  echo 1.5 >"$base/ctl/atraso.0"
  echo 1.5 >"$base/ctl/atraso.$((2 * PARTE))"
  : >"$base/ctl/r429.$PARTE"
  _upp "$base" --paralelo 3
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  [[ -e $base/ctl/r429.$PARTE.usado ]] || _harness_falhar 'o 429 nao ocorreu'
  # analise de ev: apos o fim 200 da parte P (que viu 429), as abertas nesse
  # instante nao admitem inicio de parte nova ate terminarem.
  local -A aberta=() visto=()
  local c429=nao
  while read -r e ep o r; do
    [[ $ep == append ]] || continue
    if [[ $e == ini ]]; then
      if [[ $pausa == sim && -z ${visto[$o]:-} ]]; then viol+=" $o"; fi
      visto[$o]=1 aberta[$o]=1
    else
      unset "aberta[$o]"
      if [[ $o == "$PARTE" && $r == 429 ]]; then c429=sim; fi
      if [[ $o == "$PARTE" && $r == 200 && $c429 == sim ]]; then pausa=sim; fi
      if [[ $pausa == sim ]]; then
        abertos_n=${#aberta[@]}
        ((abertos_n == 0)) && pausa=nao
      fi
    fi
  done <"$base/ev"
  assert_igual '' "$viol" 'parte nova iniciada durante a pausa do 429'
  assert_igual "$(_esperados "$T_LIMIAR_MAIS_1")" "$(_ini_offsets "$base" | tr ' ' '\n' | sort -un | tr '\n' ' ')" 'todas as partes enviadas ao fim'
  cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar 'bytes diferem'
}

# ---------------------------------------------------------------- item 12
teste_b19_nenhuma_repeticao_de_regex_acima_de_255_nos_arquivos_novos() {
  local arq n achados='' ref
  for arq in lib/transfer_paralelo.sh lib/transfer.sh lib/state.sh lib/hash.sh commands/upload.sh; do
    while IFS= read -r ref; do
      for n in $(grep -oE '[0-9]+' <<<"${ref#*:}"); do
        ((10#$n > 255)) && achados+=" $arq:$ref"
      done
    done < <(grep -noE '\{[0-9]*,?[0-9]*\}|\\\{[0-9]*,?[0-9]*\\\}' "$DBX_HARNESS_RAIZ/$arq" | grep -vE '^[0-9]+:\{\}$' | grep -E '[0-9]')
  done
  assert_igual '' "$achados" 'repeticao acima de 255 (RE_DUP_MAX do FreeBSD)'
  # o auditor enxerga o positivo: fixture com {1,256}
  printf '%s\n' '[[ $x =~ ^a{1,256}$ ]]' >"$DBX_TESTES_TMP/qa19-regex.txt"
  [[ $(grep -oE '\{[0-9]*,?[0-9]*\}' "$DBX_TESTES_TMP/qa19-regex.txt" | grep -oE '[0-9]+' | sort -n | tail -n 1) -gt 255 ]] ||
    _harness_falhar 'auditor nao enxerga {1,256}'
}

harness_executar "$@"
