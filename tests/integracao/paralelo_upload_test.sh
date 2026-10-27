#!/usr/bin/env bash
# Testes ponta a ponta do UPLOAD de arquivo grande em partes simultaneas
# (F-100, etapa 2a; RF-177 a RF-179, RF-181 (upload), RF-182, RF-183, RF-184,
# RF-175(c); DIV-358 a DIV-368, DIV-373 a DIV-376; TC-PUD).
#
# O DUPLO DE `curl` E UM SERVIDOR DE SESSAO CONCORRENTE: cada `append_v2` guarda o
# corpo recebido por deslocamento (reenvio da mesma parte sobrescreve, como
# no contrato real), marca `vivos/<pid>` enquanto dura (pico de simultaneas em
# `picos`) e o `finish` MONTA o arquivo pelos deslocamentos, confere o total e
# calcula o `content_hash` pela montagem. Nenhum caso confere resumo contra si.
# Controles em `$base/ctl`: `recusa` (start concurrent recusado), `falha`
# (deslocamento cujo append falha 409), `r429` (deslocamento com um 429),
# `segura` (cada append demora), `sinal_em` (TERM ao `dbx` na parte desse
# deslocamento, depois de as anteriores chegarem) e `seq_sinal_em` (TERM no
# append sequencial desse deslocamento).
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` chega sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC_PADRAO="$DBX_HARNESS_RAIZ/bin/dbx"
readonly BLOCO=4194304
readonly PARTE=16777216
readonly TAMANHO=$((157286400 + 3))
readonly PARTES=10
readonly SENTINELA_TOKEN='sl.SENTINELA_token_curto_p1q2'
readonly SENTINELA_SESSAO='SESSAOPAR'

_fixture_grande() {
  local arquivo="$DBX_TESTES_TMP/paralelo-up-grande.bin" i
  if [[ ! -e $arquivo ]]; then
    truncate -s "$TAMANHO" "$arquivo"
    for ((i = 0; i * BLOCO < TAMANHO; i++)); do
      printf 'bloco-%03d' "$i" | dd of="$arquivo" bs=1 seek=$((i * BLOCO)) conv=notrunc status=none
    done
  fi
  printf '%s' "$arquivo"
}

_ambiente() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/pup.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/tmp" "$base/trabalho" "$base/sess" "$base/vivos" "$base/ctl"
  chmod 700 "$base/config/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  cp --sparse=always "$(_fixture_grande)" "$base/trabalho/grande.iso"
  touch -d '1 hour ago' "$base/trabalho/grande.iso"
  head -c 1048576 /dev/urandom >"$base/trabalho/pequeno.bin"
  : >"$base/chamadas"
  {
    printf '#!%s\n' "$BASH"
    printf 'base=%q\ntoken=%q\nsentinela=%q\n' "$base" "$SENTINELA_TOKEN" "$SENTINELA_SESSAO"
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
ep=${url#https://*/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
sid=''; off=''; fechar=''; conc=nao
[[ $arg =~ \"session_id\":\"([^\"]*)\" ]] && sid=${BASH_REMATCH[1]}
[[ $arg =~ \"offset\":([0-9]+) ]] && off=${BASH_REMATCH[1]}
[[ $arg =~ \"close\":(true|false) ]] && fechar=${BASH_REMATCH[1]}
[[ $arg == *concurrent* ]] && conc=sim
printf '%s %s %s %s\n' "$ep" "${off:--}" "${fechar:--}" "$conc" >>"$base/chamadas"
pid=$(<"$base/pid")
vivo="$base/vivos/$$"
trap 'rm -f "$vivo"' EXIT
codigo=200 resposta='{}' extra=''
erro() { codigo=409; resposta="{\"error_summary\":\"$1\",\"error\":{\".tag\":\"${1%%/*}\"}}"; }
case $ep in
  oauth2/token) resposta="{\"access_token\":\"$token\",\"token_type\":\"bearer\",\"expires_in\":14400}" ;;
  files/get_metadata) erro 'path/not_found/' ;;
  users/get_space_usage) resposta='{"used":0,"allocation":{".tag":"individual","allocated":1000000000000}}' ;;
  files/list_folder) erro 'path/not_found/' ;;
  files/upload) resposta='{".tag":"file","name":"x","path_display":"/X","id":"id:2","rev":"0123456789b","size":1,"server_modified":"2026-01-01T00:00:00Z","client_modified":"2026-01-01T00:00:00Z"}' ;;
  files/upload_session/start)
    if [[ $conc == sim && -e $base/ctl/recusa ]]; then
      codigo=400; resposta='{"error_summary":"invalid_arguments/","error":{".tag":"invalid_arguments"}}'
    else
      sid="$sentinela-$$"
      mkdir -p "$base/sess/$sid"
      printf '%s' "$conc" >"$base/sess/$sid/conc"
      printf 0 >"$base/sess/$sid/offset"
      resposta="{\"session_id\":\"$sid\"}"
    fi
    ;;
  files/upload_session/append_v2)
    if [[ ! -d $base/sess/$sid ]]; then erro 'not_found/'
    else
      : >"$vivo"
      n=$(ls "$base/vivos" | wc -l)
      printf '%s\n' "$n" >>"$base/picos"
      [[ -e $base/ctl/segura ]] && command -p sleep 0.4
      conc_s=$(<"$base/sess/$sid/conc")
      if [[ -e $base/ctl/sinal_em && $off == "$(<"$base/ctl/sinal_em")" ]]; then
        k=0
        until [[ $(ls "$base/sess/$sid" | grep -c '^d\.') -ge $((off / 16777216)) || $k -ge 100 ]]; do
          command -p sleep 0.1; k=$((k + 1))
        done
        command -p sleep 1
        kill -s TERM "$pid"; command -p sleep 5; exit 7
      fi
      if [[ -e $base/ctl/seq_sinal_em && $conc_s == nao && $off == "$(<"$base/ctl/seq_sinal_em")" ]]; then
        kill -s TERM "$pid"; command -p sleep 5; exit 7
      fi
      if [[ -e $base/ctl/falha && $off == "$(<"$base/ctl/falha")" ]]; then
        erro 'other/'
      elif [[ -e $base/ctl/r429 && $off == "$(<"$base/ctl/r429")" ]] && mv "$base/ctl/r429" "$base/ctl/r429.usado" 2>/dev/null; then
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
    ;;
  files/upload_session/finish)
    total=$(wc -c <"$base/trabalho/grande.iso")
    if [[ ! -d $base/sess/$sid ]]; then erro 'lookup_failed/not_found/'
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

_up() { _rodar "$1" upload "${@:2}" grande.iso /Grande.iso; } # <base> [opcoes...]
_conta() { grep -c -F -- "$2" "$1/chamadas" || true; }         # <base> <trecho>
_pico() { sort -n "$1/picos" 2>/dev/null | tail -n 1; }
_registro_campo() { # <base> <indice> — campo do (unico) registro de retomada
  local r f c=()
  for r in "$1"/estado/dbx/retomada-*; do
    [[ -f $r ]] || continue
    while IFS= read -r -d '' f; do c+=("$f"); done <"$r"
    printf '%s' "${c[$2]:-}"
    return 0
  done
}
_registros() {
  local r n=0
  for r in "$1"/estado/dbx/retomada-*; do [[ -e $r ]] && n=$((n + 1)); done
  printf '%s' "$n"
}
_residuo() {
  local e lista=''
  for e in "$1"/tmp/* "$1"/tmp/.[!.]*; do [[ -e $e ]] && lista+=" ${e##*/}"; done
  printf '%s' "$lista"
}
# _offsets_append <base> — deslocamentos recebidos em append_v2, ordenados.
_offsets_append() {
  local ep o f c
  while read -r ep o f c; do [[ $ep == files/upload_session/append_v2 ]] && printf '%s\n' "$o"; done <"$1/chamadas" | sort -n | tr '\n' ' '
}
_todos_offsets() {
  local i s=''
  for ((i = 0; i < PARTES; i++)); do s+="$((i * PARTE)) "; done
  printf '%s' "$s"
}

teste_tc_pud_partes_simultaneas_montam_o_mesmo_arquivo_e_o_content_hash() {
  local base
  base=$(_ambiente)
  _up "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_contem 'sessao_em_partes' "$DBX_SAIDA"
  assert_contem 'conferida' "$DBX_SAIDA"
  assert_igual "$(_todos_offsets)" "$(_offsets_append "$base")" 'cada parte enviada uma vez'
  assert_igual 1 "$(_conta "$base" 'files/upload_session/start - false sim')" 'start concurrent'
  assert_igual 1 "$(_conta "$base" "files/upload_session/finish $TAMANHO - nao")" 'finish com offset = total'
  assert_igual 1 "$(_conta "$base" "append_v2 $((9 * PARTE)) true")" 'close so na ultima parte'
  assert_igual 1 "$(_conta "$base" ' true ')" 'um unico close'
  cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar 'bytes no servidor diferem do arquivo local'
  local pico
  pico=$(_pico "$base")
  [[ $pico -ge 2 && $pico -le 4 ]] || _harness_falhar "pico de partes simultaneas fora de 2..4: $pico"
  assert_igual 0 "$(_registros "$base")" 'registro removido no sucesso'
  assert_igual '' "$(_residuo "$base")" 'sem residuo no TMPDIR'
}

teste_tc_pud_n1_e_o_caminho_sequencial_de_sempre() {
  local base
  base=$(_ambiente)
  _up "$base"
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_igual 0 "$(_conta "$base" ' sim')" 'nenhuma sessao concorrente'
  assert_igual 1 "$(_pico "$base")" 'uma parte por vez'
  cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar 'bytes diferem'
}

teste_tc_pud_abaixo_do_limiar_o_n_nao_tem_efeito() {
  local base
  base=$(_ambiente)
  _rodar "$base" upload --paralelo 4 pequeno.bin /Pequeno.bin
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_contem 'requisicao_unica' "$DBX_SAIDA"
  assert_igual 0 "$(_conta "$base" 'upload_session')" 'sem sessao'
}

teste_tc_pud_falha_definitiva_de_parte_nao_faz_finish_e_preserva_o_registro_v2() {
  local base
  base=$(_ambiente)
  printf '%s' "$((3 * PARTE))" >"$base/ctl/falha"
  _up "$base" --paralelo 4
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'deveria falhar'
  assert_igual 0 "$(_conta "$base" 'upload_session/finish')" 'nenhum finish'
  assert_igual 1 "$(_registros "$base")" 'registro preservado'
  assert_igual 2 "$(_registro_campo "$base" 1)" 'registro v2'
  assert_igual concurrent "$(_registro_campo "$base" 7)" 'tipo da sessao'
  assert_nao_contem "$SENTINELA_SESSAO" "$DBX_ERRO"
  assert_igual '' "$(_residuo "$base")" 'sem residuo no TMPDIR'
}

teste_tc_pud_retomada_v2_reenvia_so_as_nao_confirmadas() {
  local base confirmadas esperado intervalo i a b
  base=$(_ambiente)
  printf '%s' "$((3 * PARTE))" >"$base/ctl/sinal_em"
  _up "$base" --paralelo 2
  assert_igual 1 "$(_registros "$base")" 'registro apos a interrupcao'
  assert_igual 2 "$(_registro_campo "$base" 1)" 'registro v2'
  intervalo=$(_registro_campo "$base" 12)
  confirmadas=' '
  for item in ${intervalo//,/ }; do
    a=${item%-*} b=${item#*-}
    for ((i = a; i <= b; i++)); do confirmadas+="$i "; done
  done
  esperado=''
  for ((i = 0; i < PARTES; i++)); do [[ $confirmadas == *" $i "* ]] || esperado+="$((i * PARTE)) "; done
  [[ $confirmadas == *' 0 '* && $confirmadas != *' 3 '* ]] || _harness_falhar "confirmadas inesperadas: $confirmadas"
  rm -f "$base/ctl/sinal_em"
  : >"$base/chamadas"
  _up "$base" --paralelo 2
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_igual "$esperado" "$(_offsets_append "$base")" 'so as nao confirmadas (a em voo reenviada)'
  assert_igual 0 "$(_conta "$base" 'upload_session/start')" 'sem novo start'
  cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar 'bytes diferem apos a retomada'
  assert_contem 'conferida' "$DBX_SAIDA"
  assert_igual 0 "$(_registros "$base")"
}

teste_tc_pud_registro_v1_com_n_maior_que_1_retoma_em_sequencia() {
  local base
  base=$(_ambiente)
  printf '%s' "$((3 * BLOCO))" >"$base/ctl/seq_sinal_em"
  _up "$base"
  assert_igual 1 "$(_registros "$base")" 'registro v1'
  assert_igual 1 "$(_registro_campo "$base" 1)" 'versao 1'
  rm -f "$base/ctl/seq_sinal_em"
  : >"$base/chamadas"
  _up "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_igual 0 "$(_conta "$base" 'upload_session/start')" 'sessao v1 retomada'
  assert_igual 0 "$(_conta "$base" ' sim')" 'nada concorrente'
  assert_igual 1 "$(_pico "$base")" 'sequencial'
  assert_nao_contem "append_v2 0 " "$(<"$base/chamadas")"
  cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar 'bytes diferem'
}

teste_tc_pud_servico_que_recusa_concurrent_cai_para_sequencial_com_aviso() {
  local base
  base=$(_ambiente)
  : >"$base/ctl/recusa"
  _up "$base" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_contem 'sessao concorrente' "$DBX_ERRO"
  assert_nao_contem "$SENTINELA_SESSAO" "$DBX_ERRO"
  assert_igual 1 "$(_pico "$base")" 'sequencial'
  assert_igual 2 "$(_conta "$base" 'upload_session/start')" 'concurrent recusado e start sequencial'
  cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar 'bytes diferem'
}

teste_tc_pud_429_em_uma_parte_nao_perde_nem_duplica_e_entra_no_resumo() {
  local base
  base=$(_ambiente)
  printf '%s' "$((2 * PARTE))" >"$base/ctl/r429"
  _rodar "$base" --debug upload --paralelo 4 grande.iso /Grande.iso
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_contem 'limites_429=1' "$DBX_ERRO"
  cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar 'bytes diferem'
}

teste_tc_pud_debug_traz_paralelo_no_resumo_e_uma_linha_por_parte() {
  local base
  base=$(_ambiente)
  _rodar "$base" --debug upload --paralelo 3 grande.iso /Grande.iso
  assert_igual 0 "$DBX_ESTADO" "erro: $DBX_ERRO"
  assert_contem 'paralelo=3' "$DBX_ERRO"
  assert_contem 'comando=upload' "$DBX_ERRO"
  assert_contem "debug: upload parte=9 deslocamento=$((9 * PARTE)) close=true" "$DBX_ERRO"
  assert_nao_contem "$SENTINELA_SESSAO" "$DBX_ERRO"
  base=$(_ambiente)
  _rodar "$base" --debug upload pequeno.bin /Pequeno.bin
  assert_nao_contem 'paralelo=' "$DBX_ERRO"
}

# QA-B19-01 / RF-181(a): intervalos fora de ordem, sobrepostos, adjacentes nao
# fundidos ou alem do total invalidam o registro; o envio recomeca do zero.
teste_tc_pud_registro_v2_com_intervalos_nao_canonicos_e_descartado_com_aviso() {
  local base arquivo campos f ruim i
  for ruim in '5-6,1-2' '1-4,3-5' '1-2,3-4' '4-3' '0-10'; do
    base=$(_ambiente)
    printf '%s' "$((3 * PARTE))" >"$base/ctl/sinal_em"
    _up "$base" --paralelo 2
    for arquivo in "$base"/estado/dbx/retomada-*; do :; done
    campos=()
    while IFS= read -r -d '' f; do campos+=("$f"); done <"$arquivo"
    campos[12]=$ruim
    printf '%s\0' "${campos[@]}" >"$arquivo"
    rm -f "$base/ctl/sinal_em"
    : >"$base/chamadas"
    _up "$base" --paralelo 2
    assert_igual 0 "$DBX_ESTADO" "[$ruim] erro: $DBX_ERRO"
    assert_contem 'estado de retomada descartado' "$DBX_ERRO"
    assert_igual "$(_todos_offsets)" "$(_offsets_append "$base")" "[$ruim] todas as partes enviadas"
    cmp -s "$base/montado" "$base/trabalho/grande.iso" || _harness_falhar "[$ruim] bytes diferem"
  done
}

harness_executar "$@"
