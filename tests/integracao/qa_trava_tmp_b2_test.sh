#!/usr/bin/env bash
# Suite independente do QA, fase 2 do backlog: trava de concorrencia (F-12;
# RF-69, RF-70, RF-71, DIV-38..49) e area temporaria unica (restante de F-31;
# RNF-35, RNF-36).
#
# Escrita como ADVERSARIO, pelo executavel real, com duplos proprios de `curl`,
# `ln` e `sleep` (independentes dos da suite do developer). A concorrencia e
# real: processos `bin/dbx` simultaneos, o duplo de `curl` segura a chamada
# escolhida ate o caso soltar, e o duplo de `ln` mata o proprio `dbx` com
# SIGKILL em cada fase da retomada de orfa. Os sinais vao a sessao propria de
# cada execucao (`setsid`), e `TMPDIR` e privado do caso.
#
# shellcheck disable=SC2016
# Justificativa: os duplos sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly QA_DBX="$DBX_HARNESS_RAIZ/bin/dbx"
QA_CONFLITO=$(dbx_errors_codigo_saida conflito)
QA_USO=$(dbx_errors_codigo_saida uso_invalido)
QA_NAO_CONCLUIDA=$(dbx_errors_codigo_saida nao_concluida)
readonly QA_CONFLITO QA_USO QA_NAO_CONCLUIDA
QA_DORMIR=$(command -v sleep)
QA_LN=$(command -v ln)
readonly QA_DORMIR QA_LN
# Sentinelas de segredo: app secret, refresh token, access token e conta.
readonly QA_SENTINELAS='QA-SEGREDO-B2 QA-RT-B2 QA-TOKEN-B2 QA-CONTA-B2'

B=''
QA_ESTADO=''
QA_SAIDA=''
QA_ERRO=''

# _qa_cenario — credencial com sentinelas, duplo de rede e arvore local em $B.
#
# Duplo de `curl`: anota cada URL em `diario` com T/N (trava presente ou nao
# NAQUELE instante); se `$B/prender` existe e a URL o contem, a chamada fica
# presa (anotando `preso.<pid>`) ate existir `$B/soltar` ou, so para ela,
# `$B/soltar_<ultimo segmento da URL>` (por exemplo `soltar_revoke`).
_qa_cenario() {
  B=$(mktemp -d "$DBX_TESTES_TMP/qa-b2.XXXXXX")
  # Caso que reprova com execucao presa no duplo nao pode prender a suite.
  # shellcheck disable=SC2064  # o caminho e fixado agora, de proposito
  trap ": >'$B/soltar'" EXIT
  mkdir -p "$B/cfg/dbx" "$B/bin" "$B/local" "$B/tmp"
  printf '%s' '{"versao":1,"app_key":"k","app_secret":"QA-SEGREDO-B2","refresh_token":"QA-RT-B2","raiz_remota":"/"}' \
    >"$B/cfg/dbx/credencial.json"
  chmod 700 "$B/cfg/dbx"
  chmod 600 "$B/cfg/dbx/credencial.json"
  printf '%s' '{"entries":[],"cursor":"c","has_more":false}' >"$B/listagem"
  {
    printf '#!%s\nQA=%q\nDORMIR=%q\n' "$BASH" "$B" "$QA_DORMIR"
    cat <<'FIM'
cat >/dev/null 2>&1
o=''; w=''; ant=''; url=''
for a in "$@"; do
  case $ant in -o) o=$a ;; -w) w=$a ;; esac
  case $a in http*) url=$a ;; esac
  ant=$a
done
t=N
for x in "${XDG_STATE_HOME:-$QA/estado}"/dbx/trava-*; do [[ -e $x ]] && t=T; done
printf '%s %s\n' "$url" "$t" >>"$QA/diario"
if [[ -f $QA/prender && $url == *"$(<"$QA/prender")"* ]]; then
  : >"$QA/preso.$$"
  while [[ ! -e $QA/soltar && ! -e $QA/soltar_${url##*/} ]]; do "$DORMIR" 0.05; done
fi
if [[ -f $QA/matar && $url == *"$(<"$QA/matar")"* ]]; then
  kill -s KILL 0
fi
c=200
case $url in
  *oauth2/token*) r='{"access_token":"sl.QA-TOKEN-B2","expires_in":14400}' ;;
  *get_current_account*) r='{"account_id":"dbid:QA-CONTA-B2"}' ;;
  *list_folder*) r=$(<"$QA/listagem") ;;
  *get_space_usage*) r='{"used":1,"allocation":{".tag":"individual","allocated":99999999}}' ;;
  *files/download*)
    if [[ -f $QA/eh_pasta ]]; then c=409; r='{"error_summary":"path/not_file/"}'; else r='x'; fi ;;
  *) r='{"name":"x","path_display":"/x",".tag":"file","rev":"1","size":1}' ;;
esac
[[ -n $w ]] && printf '%s' "$c"
# `--fail` (canal de fluxo): erro HTTP sai 22 sem corpo, como o cliente real.
if [[ " $* " == *' --fail '* && $c -ge 400 ]]; then exit 22; fi
if [[ -n $o ]]; then printf '%s' "$r" >"$o" 2>/dev/null || exit 23; fi
exit 0
FIM
  } >"$B/bin/curl"
  chmod +x "$B/bin/curl"
}

# _qa_sleep_contado — duplo de `sleep` que anota e nao dorme.
_qa_sleep_contado() {
  printf '#!%s\nprintf "sleep %%s\\n" "$*" >>%q\nexit 0\n' "$BASH" "$B/sleeps" >"$B/bin/sleep"
  chmod +x "$B/bin/sleep"
}

# _qa_ln_assassino <modo> — duplo de `ln` que mata o `dbx` (o pai) com SIGKILL:
#   r       logo depois de publicar a `.r`
#   antes   na publicacao da trava nova da retomada, ANTES do elo (orfa ja apagada)
#   depois  logo depois de publicar a trava nova da retomada (a `.r` ainda la)
_qa_ln_assassino() {
  {
    printf '#!%s\nLN=%q\nMODO=%q\n' "$BASH" "$QA_LN" "$1"
    cat <<'FIM'
destino=${*: -1}
case $MODO:$destino in
  r:*.r) "$LN" "$@"; s=$?; kill -s KILL "$PPID"; exit "$s" ;;
  antes:*/trava-*) if [[ $destino != *.r && -e $destino.r ]]; then kill -s KILL "$PPID"; exit 1; fi ;;
  depois:*/trava-*) if [[ $destino != *.r && -e $destino.r ]]; then "$LN" "$@"; kill -s KILL "$PPID"; fi ;;
esac
exec "$LN" "$@"
FIM
  } >"$B/bin/ln"
  chmod +x "$B/bin/ln"
}

# _qa_env — ambiente limpo da execucao, em QA_AMBIENTE.
_qa_env() {
  QA_AMBIENTE=(env -i PATH="$B/bin:$PATH" HOME="$B" LANG=C.UTF-8 LC_ALL="${QA_LOCALIDADE:-C.UTF-8}"
    XDG_CONFIG_HOME="$B/cfg"
    XDG_STATE_HOME="${QA_XDG_STATE:-$B/estado}" TMPDIR="$B/tmp")
}

# _qa_dbx <args...> — roda em sessao propria; publica QA_ESTADO/SAIDA/ERRO.
_qa_dbx() {
  _qa_env
  setsid -w "${QA_AMBIENTE[@]}" bash "$QA_DBX" "$@" </dev/null >"$B/out" 2>"$B/err"
  QA_ESTADO=$?
  QA_SAIDA=$(cat "$B/out")
  QA_ERRO=$(cat "$B/err")
}

# _qa_fundo <rotulo> <args...> — execucao em segundo plano; o codigo vai para
# `estado.<rotulo>` e o pid da sessao para `pid.<rotulo>`.
_qa_fundo() {
  local rotulo=$1
  shift
  _qa_env
  (
    setsid -w "${QA_AMBIENTE[@]}" bash "$QA_DBX" "$@" </dev/null >"$B/out.$rotulo" 2>"$B/err.$rotulo" &
    printf '%s' "$!" >"$B/pid.$rotulo"
    wait "$!"
    printf '%s' "$?" >"$B/estado.$rotulo.tmp"
    mv "$B/estado.$rotulo.tmp" "$B/estado.$rotulo"
  ) &
}

_qa_esperar() { # <arquivo> [decimos_de_segundo]
  local n=0 limite=${2:-300}
  while [[ ! -e $1 && $n -lt $limite ]]; do "$QA_DORMIR" 0.1; n=$((n + 1)); done
  [[ -e $1 ]] || _harness_falhar "nao apareceu a tempo: $1"
}

_qa_presos() { find "$B" -maxdepth 1 -name 'preso.*' | wc -l | tr -d ' '; }
_qa_travas() { find "$B/estado" \( -name 'trava-*' -o -name '.trava.*' \) 2>/dev/null | LC_ALL=C sort; }
_qa_residuo() { find "$B/tmp" -mindepth 1 -maxdepth 1 -name 'dbx-*' 2>/dev/null; }

# _qa_retrato <dir> — arvore com tipo, modo, tamanho e resumo; `ausente`.
_qa_retrato() {
  [[ -e $1 || -L $1 ]] || { printf 'ausente'; return 0; }
  find "$1" -printf '%P|%y|%m|%s|%l\n' | LC_ALL=C sort
  (cd -- "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum)
}

# _qa_trava_do_par <raiz_local> <raiz_remota> — caminho da trava pela mesma
# definicao do comando (identidade local da credencial, DIV-47).
_qa_trava_do_par() {
  XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="${QA_XDG_STATE:-$B/estado}" TMPDIR="$B/tmp" LANG=C.UTF-8 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/json.sh"; . "$1/lib/path.sh"; . "$1/lib/config.sh"; . "$1/lib/state.sh"
    dbx_config_carregar >/dev/null 2>&1; dbx_config_identidade
    dbx_path_local_canonico "$2"
    dbx_state_trava_caminho "$DBX_CONFIG_IDENTIDADE" "$DBX_PATH_RESULTADO" "$3"
    printf "%s" "$DBX_STATE_RESULTADO"' _ "$DBX_HARNESS_RAIZ" "$1" "$2"
}

# _qa_host_campo <nome|boot|ns|id> — identidade do host como o produto a calcula.
_qa_host_campo() {
  bash -c '. "$1/lib/errors.sh"; . "$1/lib/state.sh"; dbx_state_host_id
    case $2 in nome) printf "%s" "$DBX_STATE_HOST_NOME" ;; boot) printf "%s" "$DBX_STATE_HOST_BOOT" ;;
      ns) printf "%s" "$DBX_STATE_HOST_NS" ;; *) printf "%s" "$DBX_STATE_HOST_ID" ;; esac' _ "$DBX_HARNESS_RAIZ" "$1"
}

_qa_linha() { printf 'dbx-trava\t1\t%s\t%s\t%s\t%s\tfim\n' "$1" "$2" "$3" "$4"; }

# _qa_plantar <arquivo> <conteudo> — grava exatamente os bytes dados, 0600.
_qa_plantar() {
  [[ $1 == "$DBX_TESTES_TMP"/* ]] || _harness_falhar 'trava fora da area do caso' "[$1]"
  mkdir -p "${1%/*}"
  chmod 700 "${1%/*}"
  printf '%s' "$2" >"$1"
  chmod 600 "$1"
}

_qa_pid_morto() {
  local pid
  "$QA_DORMIR" 0 &
  pid=$!
  wait "$pid"
  printf '%s' "$pid"
}

_qa_sem_sentinela() { # <texto> <contexto>
  local s
  for s in $QA_SENTINELAS; do
    assert_nao_contem "$s" "$1" "$2: sentinela $s"
  done
}

_qa_sem_esc() { # <texto> <contexto>
  [[ $1 != *$'\033'* ]] || _harness_falhar "$2: byte ESC cru na saida"
}

_qa_soltar_e_colher() { # <rotulo> — solta o duplo e devolve o codigo da execucao
  : >"$B/soltar"
  _qa_esperar "$B/estado.$1"
  cat "$B/estado.$1"
}

# ---------------------------------------------------------------------------
# RF-69(g)(m): corridas reais entre processos
# ---------------------------------------------------------------------------

teste_qa_b2_01_dez_execucoes_simultaneas_do_mesmo_par_um_so_entra() {
  # RF-69(g): exclusao real, pelo executavel; quem perde nao apaga a trava viva.
  local i n7=0 e
  _qa_cenario
  printf 'list_folder' >"$B/prender"
  for i in 0 1 2 3 4 5 6 7 8 9; do
    if ((i % 2)); then
      _qa_fundo "p$i" verificar --enviar --origem "$B/local" --destino /r
    else
      _qa_fundo "p$i" --dry-run sync --receber --origem /R --destino "$B/local/"
    fi
  done
  for i in 0 1 2 3 4 5 6 7 8 9; do
    _qa_esperar "$B/pid.p$i"
  done
  # 9 terminam com 7; 1 fica preso no duplo detendo a trava.
  local terminados=0 n=0
  while [[ $n -lt 300 ]]; do
    terminados=$(find "$B" -maxdepth 1 -name 'estado.p*' ! -name '*.tmp' | wc -l)
    [[ $terminados -ge 9 && $(_qa_presos) -ge 1 ]] && break
    "$QA_DORMIR" 0.1
    n=$((n + 1))
  done
  assert_igual 9 "$terminados" 'nove execucoes terminaram'
  assert_igual 1 "$(_qa_presos)" 'uma so execucao chegou a API'
  for e in "$B"/estado.p*; do
    [[ $e == *.tmp ]] && continue
    [[ $(cat "$e") == "$QA_CONFLITO" ]] && n7=$((n7 + 1))
  done
  assert_igual 9 "$n7" 'as nove perdedoras recusaram com conflito'
  local -a vencedora=("$B"/estado/dbx/trava-*)
  assert_igual 1 "${#vencedora[@]}" 'a trava da vencedora continua la depois das perdedoras'
  assert_arquivo_existe "${vencedora[0]}" 'e e um arquivo de verdade'
  : >"$B/soltar"
  for i in 0 1 2 3 4 5 6 7 8 9; do
    _qa_esperar "$B/estado.p$i"
  done
  assert_igual '' "$(_qa_travas)" 'nenhuma trava, temporario ou .r sobra'
  assert_igual '' "$(_qa_residuo)" 'nenhuma area dbx-* sobra'
  assert_igual 0 "$(_harness_contar ' N$' "$B/diario")" 'nenhuma chamada sem trava'
}

teste_qa_b2_02_dez_retomadores_simultaneos_da_mesma_orfa_um_so_entra() {
  # RF-69(m), TC-TRV-28, DIV-53: um vencedor so, a orfa sai uma vez so, e
  # quem a apagou avisa uma vez ("removida"), seja ou nao o vencedor.
  local i trava n7=0 e vencedor='' avisos=0 err
  _qa_cenario
  trava=$(_qa_trava_do_par "$B/local" /r)
  _qa_plantar "$trava" "$(_qa_linha "$(_qa_pid_morto)" "$(_qa_host_campo id)" 1700000000 sync)"$'\n'
  printf 'list_folder' >"$B/prender"
  for i in 0 1 2 3 4 5 6 7 8 9; do
    _qa_fundo "p$i" verificar --enviar --origem "$B/local" --destino /r
  done
  local n=0 terminados=0
  while [[ $n -lt 300 ]]; do
    terminados=$(find "$B" -maxdepth 1 -name 'estado.p*' ! -name '*.tmp' | wc -l)
    [[ $terminados -ge 9 && $(_qa_presos) -ge 1 ]] && break
    "$QA_DORMIR" 0.1
    n=$((n + 1))
  done
  assert_igual 1 "$(_qa_presos)" 'um so retomador chegou a API'
  for e in "$B"/estado.p*; do
    [[ $e == *.tmp ]] && continue
    [[ $(cat "$e") == "$QA_CONFLITO" ]] && n7=$((n7 + 1))
  done
  assert_igual 9 "$n7" 'os demais recusaram com conflito'
  assert_igual "$trava" "$(_qa_travas)" 'so a trava nova; nenhuma .r nem temporario'
  : >"$B/soltar"
  for i in 0 1 2 3 4 5 6 7 8 9; do
    _qa_esperar "$B/estado.p$i"
    [[ $(cat "$B/estado.p$i") == 0 ]] && vencedor=$i
  done
  [[ -n $vencedor ]] || _harness_falhar 'nenhum retomador concluiu'
  for i in 0 1 2 3 4 5 6 7 8 9; do
    IFS= read -r -d '' err <"$B/err.p$i" || :
    [[ $err == *'removida'* ]] && avisos=$((avisos + 1))
    # Um aviso por processo, no maximo.
    [[ ${err#*removida} != *removida* ]] || _harness_falhar "p$i avisou duas vezes"
  done
  assert_igual 1 "$avisos" 'exatamente um aviso de orfa removida entre os dez'
  assert_igual '' "$(_qa_travas)" 'liberada ao fim'
}

teste_qa_b2_03_sigkill_em_cada_fase_da_retomada_nunca_rouba_nem_some() {
  # RF-69(m), TC-TRV-29: morto com a `.r` publicada, entre apagar a orfa e
  # publicar a nova, e depois de publicar a nova. A `.r` que sobra nunca e
  # retomada sozinha, nada vivo e apagado e o diagnostico a mostra.
  local modo trava morto antes
  for modo in r antes depois; do
    _qa_cenario
    trava=$(_qa_trava_do_par "$B/local" /r)
    morto=$(_qa_pid_morto)
    _qa_plantar "$trava" "$(_qa_linha "$morto" "$(_qa_host_campo id)" 1700000000 sync)"$'\n'
    _qa_ln_assassino "$modo"
    _qa_dbx verificar --enviar --origem "$B/local" --destino /r
    assert_igual 137 "$QA_ESTADO" "$modo: o dbx morreu por SIGKILL na fase"
    rm -f "$B/bin/ln"
    assert_arquivo_existe "$trava.r" "$modo: a .r ficou para tras"
    antes=$(_qa_retrato "$B/estado")
    if [[ $modo == antes ]]; then
      assert_arquivo_ausente "$trava" 'antes: a orfa ja tinha sido apagada'
      # Sem trava, a proxima execucao adquire do zero; a .r continua la.
      _qa_dbx verificar --enviar --origem "$B/local" --destino /r
      assert_igual 0 "$QA_ESTADO" "antes: sem trava, adquire normalmente: $QA_ERRO"
      assert_arquivo_existe "$trava.r" 'antes: a .r nunca e apagada sozinha'
    else
      _qa_dbx verificar --enviar --origem "$B/local" --destino /r
      assert_igual "$QA_CONFLITO" "$QA_ESTADO" "$modo: a .r presa recusa com conflito"
      assert_contem "rm $trava.r" "$QA_ERRO" "$modo: o remedio manual nomeia a .r"
      assert_igual "$antes" "$(_qa_retrato "$B/estado")" "$modo: nada apagado nem criado"
      assert_arquivo_ausente "$B/diario" "$modo: nenhuma chamada a API"
    fi
    _qa_dbx diagnostico
    assert_contem 'retomada interrompida' "$QA_SAIDA" "$modo: o diagnostico mostra a .r"
    assert_arquivo_existe "$trava.r" "$modo: o diagnostico nao apaga a .r"
    # Remedio manual aplicado: a orfa (se houver) e retomada.
    rm -f "$trava.r"
    _qa_dbx verificar --enviar --origem "$B/local" --destino /r
    assert_igual 0 "$QA_ESTADO" "$modo: depois do remedio, segue: $QA_ERRO"
    # O temporario `.trava.*` do processo morto por SIGKILL fica para a poda de
    # RF-69(o); trava e `.r`, nao.
    assert_igual '' "$(_qa_travas | grep '/trava-' || :)" "$modo: nenhuma trava depois do remedio"
  done
}

teste_qa_b2_04_sigkill_com_a_trava_detida_vira_orfa_retomada() {
  # RF-69(f)(n): processo morto (SIGKILL no grupo) durante a listagem.
  local trava
  _qa_cenario
  trava=$(_qa_trava_do_par "$B/local" /r)
  printf 'list_folder' >"$B/matar"
  _qa_dbx sync --enviar --origem "$B/local" --destino /r
  assert_igual 137 "$QA_ESTADO" 'morto por SIGKILL'
  assert_arquivo_existe "$trava" 'a trava ficou orfa'
  rm -f "$B/matar"
  _qa_dbx diagnostico
  assert_contem 'orfa:' "$QA_SAIDA" 'o diagnostico a classifica orfa'
  _qa_dbx sync --enviar --origem "$B/local" --destino /r
  assert_igual 0 "$QA_ESTADO" "retomada e codigo normal: $QA_ERRO"
  assert_contem 'removida' "$QA_ERRO" 'com aviso de orfa removida (DIV-53)'
  assert_igual '' "$(_qa_travas)" 'liberada ao fim'
}

# ---------------------------------------------------------------------------
# RF-69(f)(l): vida da trava, pid reaproveitado e outro host
# ---------------------------------------------------------------------------

teste_qa_b2_05_pid_reaproveitado_ou_de_outro_usuario_conta_como_viva() {
  # RF-69(f)(l), RSK-47: falha para o lado seguro, nunca retoma nem apaga.
  local trava alheio='' p conteudo
  _qa_cenario
  trava=$(_qa_trava_do_par "$B/local" /r)
  "$QA_DORMIR" 30 &
  p=$!
  conteudo=$(_qa_linha "$p" "$(_qa_host_campo id)" 1700000000 sync)$'\n'
  _qa_plantar "$trava" "$conteudo"
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r
  kill "$p" 2>/dev/null
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" 'pid vivo de outro programa: ocupada'
  assert_contem 'trava ocupada' "$QA_ERRO" 'mensagem de ocupada'
  assert_igual "$conteudo" "$(cat "$trava")"$'\n' 'trava intacta'
  # Processo de outro usuario (kill -0 da EPERM): vivo.
  for p in /proc/[1-9][0-9]*; do
    p=${p#/proc/}
    [[ $p =~ ^[1-9][0-9]{1,6}$ && -O /proc/$p ]] && continue
    [[ -e /proc/$p ]] && { alheio=$p; break; }
  done
  [[ -n $alheio ]] || pular 'nenhum processo de outro usuario visivel'
  _qa_plantar "$trava" "$(_qa_linha "$alheio" "$(_qa_host_campo id)" 1700000000 sync)"$'\n'
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" "pid $alheio de outro usuario: ocupada ($QA_ERRO)"
  assert_arquivo_existe "$trava" 'nao apagada'
}

teste_qa_b2_06_outro_host_nunca_retomado_nem_esperando_e_reinicio_e_orfa() {
  # RF-69(f)(l), RF-70(d), TC-TRV-25/26.
  local trava morto nome boot ns conteudo vivo
  _qa_cenario
  _qa_sleep_contado
  trava=$(_qa_trava_do_par "$B/local" /r)
  morto=$(_qa_pid_morto)
  nome=$(_qa_host_campo nome) boot=$(_qa_host_campo boot) ns=$(_qa_host_campo ns)
  for conteudo in \
    "$(_qa_linha "$morto" "outra-maquina:$boot:$ns" 1700000000 sync)" \
    "$(_qa_linha "$morto" "$nome:$boot:1" 1700000000 sync)" \
    "$(_qa_linha "$morto" "$nome" 1700000000 sync)" \
    "$(_qa_linha "$morto" "$nome:$boot:$ns:extra" 1700000000 sync)"; do
    _qa_plantar "$trava" "$conteudo"$'\n'
    rm -f "$B/sleeps"
    _qa_dbx verificar --enviar --origem "$B/local" --destino /r --esperar 3
    assert_igual "$QA_CONFLITO" "$QA_ESTADO" "outro host nunca retomado: [$conteudo]"
    assert_contem 'outro host' "$QA_ERRO" 'a recusa diz outro host'
    assert_contem 'esperou 3 s' "$QA_ERRO" 'a espera correu ate o fim'
    assert_igual 3 "$(_harness_contar 'sleep 1' "$B/sleeps")" 'tres sondagens de 1 s'
    assert_contem "rm $trava" "$QA_ERRO" 'remedio com o caminho'
    assert_igual "$conteudo" "$(cat "$trava")" 'trava intacta'
    assert_arquivo_ausente "$B/diario" 'nenhuma chamada a API'
  done
  # Mesmo nome e namespace, boot diferente: reinicio prova orfandade, ainda que
  # o pid exista agora (reaproveitado depois do boot).
  "$QA_DORMIR" 30 &
  vivo=$!
  _qa_plantar "$trava" "$(_qa_linha "$vivo" "$nome:outro-boot-id:$ns" 1700000000 sync)"$'\n'
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r
  kill "$vivo" 2>/dev/null
  assert_igual 0 "$QA_ESTADO" "boot diferente: retomada ($QA_ERRO)"
  assert_contem 'houve reinicio' "$QA_ERRO" 'o aviso diz que houve reinicio'
  assert_igual '' "$(_qa_travas)" 'liberada'
}

# ---------------------------------------------------------------------------
# RF-69(k)(j): conteudo hostil, ligacao simbolica e diretorio
# ---------------------------------------------------------------------------

teste_qa_b2_07_trava_hostil_e_ilegivel_nunca_retomada_apagada_nem_ecoada() {
  # RF-69(k), TC-TRV-24: cada variante seria uma orfa (pid morto, mesmo host)
  # se fosse aceita; ilegivel, ela fica intacta e nenhum byte dela sai.
  local trava morto host linha variante i=0 esperado
  _qa_cenario
  trava=$(_qa_trava_do_par "$B/local" /r)
  morto=$(_qa_pid_morto)
  host=$(_qa_host_campo id)
  printf -v linha 'dbx-trava\t1\t%s\t%s\t1700000000\tsync\tfim' "$morto" "$host"
  local preenchimento
  printf -v preenchimento '%0600d' 0
  local -a variantes=(
    ''
    "$linha"
    "${linha%fim}"
    "${linha}"$'\r\n'
    "$linha"$'\n'"$linha"$'\n'
    "$linha"$'\n\033[31mQA-ESC'
    $'\357\273\277'"$linha"$'\n'
    "$(_qa_linha "$morto" "$host"$'\033[2J' 1700000000 sync)"$'\n'
    "$(_qa_linha "$morto" "$host" 1700000000 upload)"$'\n'
    "$(_qa_linha "$morto" "$host" 1700000000 'sync	x')"$'\n'
    "$(_qa_linha "$morto" "$host" -1 sync)"$'\n'
    "$(_qa_linha "$morto" "$host" 17000000000000000000 sync)"$'\n'
    "$(_qa_linha 0 "$host" 1700000000 sync)"$'\n'
    "$(_qa_linha 1 "$host" 1700000000 sync)"$'\n'
    "$(_qa_linha -1 "$host" 1700000000 sync)"$'\n'
    "$(_qa_linha 0"$morto" "$host" 1700000000 sync)"$'\n'
    "$(_qa_linha 12345678 "$host" 1700000000 sync)"$'\n'
    "${linha/dbx-trava$'\t'1/dbx-trava$'\t'2}"$'\n'
    "$linha"$'\t\n'
    "${linha//$'\t'/ }"$'\n'
    "$linha$preenchimento"$'\n'
    'NUL-AO-FIM'
    'NUL-NO-MEIO'
    'NUL-E-LIXO'
  )
  for variante in "${variantes[@]}"; do
    i=$((i + 1))
    # `printf %s` nao grava o nulo de uma variavel: a variante com nulo e escrita
    # por printf com escape.
    _qa_plantar "$trava" "$variante"
    case $variante in
      NUL-AO-FIM) printf '%s\n\000' "$linha" >"$trava" ;;
      NUL-NO-MEIO) printf 'dbx-trava\t1\000\t%s\n' "${linha#dbx-trava$'\t'1$'\t'}" >"$trava" ;;
      NUL-E-LIXO) printf '%s\n\000lixo\n' "$linha" >"$trava" ;;
    esac
    esperado=$(sha256sum <"$trava")
    rm -f "$B/diario"
    _qa_dbx verificar --enviar --origem "$B/local" --destino /r
    assert_arquivo_ausente "$B/diario" "variante $i: o verificar nao chegou a API"
    assert_igual "$QA_CONFLITO" "$QA_ESTADO" "variante $i: recusada ($QA_ERRO)"
    assert_contem 'trava ilegivel' "$QA_ERRO" "variante $i: mensagem de ilegivel"
    assert_igual "$esperado" "$(sha256sum <"$trava")" "variante $i: intacta"
    _qa_sem_esc "$QA_SAIDA$QA_ERRO" "variante $i"
    assert_nao_contem 'QA-ESC' "$QA_ERRO" "variante $i: nada do arquivo ecoado"
    _qa_dbx diagnostico
    assert_contem 'ilegivel:' "$QA_SAIDA" "variante $i: o diagnostico a mostra ilegivel"
    _qa_sem_esc "$QA_SAIDA$QA_ERRO" "variante $i: diagnostico"
    assert_igual "$esperado" "$(sha256sum <"$trava")" "variante $i: o diagnostico nao a altera"
  done
  # O `diagnostico` faz as proprias leituras (RF-66): token, conta e espaco.
}

teste_qa_b2_08_ligacao_simbolica_ou_diretorio_no_lugar_da_trava_ou_da_r() {
  # RF-69(j), TC-TRV-21/22: recusada, nada seguido, nada criado fora.
  local trava vitima antes
  _qa_cenario
  trava=$(_qa_trava_do_par "$B/local" /r)
  mkdir -p "${trava%/*}"
  chmod 700 "${trava%/*}"
  vitima="$B/vitima"
  printf 'conteudo da vitima' >"$vitima"
  # 1. trava -> arquivo do usuario fora do diretorio
  ln -s "$vitima" "$trava"
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" 'ligacao no lugar da trava: recusa'
  assert_igual 'conteudo da vitima' "$(cat "$vitima")" 'alvo intacto'
  [[ -L $trava ]] || _harness_falhar 'a ligacao foi apagada'
  rm -f "$trava"
  # 2. ligacao pendente: nada nasce no alvo
  ln -s "$B/nao-existe" "$trava"
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" 'ligacao pendente: recusa'
  assert_arquivo_ausente "$B/nao-existe" 'nada criado no alvo da ligacao'
  rm -f "$trava"
  # 3. diretorio no nome: nenhum elo dentro dele
  mkdir "$trava"
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" 'diretorio no lugar da trava: recusa'
  assert_igual '' "$(find "$trava" -mindepth 1)" 'nenhum elo deixado dentro do diretorio'
  rmdir "$trava"
  # 4. orfa com a .r sendo ligacao para a vitima, e depois diretorio
  _qa_plantar "$trava" "$(_qa_linha "$(_qa_pid_morto)" "$(_qa_host_campo id)" 1700000000 sync)"$'\n'
  ln -s "$vitima" "$trava.r"
  antes=$(_qa_retrato "$B/estado")
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" '.r ligacao: recusa'
  assert_igual 'conteudo da vitima' "$(cat "$vitima")" '.r ligacao: alvo intacto'
  assert_igual "$antes" "$(_qa_retrato "$B/estado")" '.r ligacao: orfa e ligacao intactas'
  rm -f "$trava.r"
  mkdir "$trava.r"
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" '.r diretorio: recusa'
  assert_igual '' "$(find "$trava.r" -mindepth 1)" '.r diretorio: vazio'
  assert_arquivo_ausente "$B/diario" 'nenhuma chamada a API'
}

# ---------------------------------------------------------------------------
# RF-69(e), DIV-48: diretorio de estado
# ---------------------------------------------------------------------------

teste_qa_b2_09_verificar_e_simulacao_deixam_o_estado_como_estava() {
  # RF-69(e), DIV-39: XDG ausente em varios niveis e diretorio existente com
  # modo frouxo (a trava nao corrige o modo; nada sobra).
  local comando antes
  for comando in verificar simulacao; do
    _qa_cenario
    printf 'a' >"$B/local/a.txt"
    local -a args=(verificar --enviar --origem "$B/local" --destino /r)
    [[ $comando == simulacao ]] && args=(--dry-run sync --enviar --origem "$B/local" --destino /r)
    QA_XDG_STATE="$B/x/y/z"
    _qa_dbx "${args[@]}"
    # O verificar acusa `a.txt` so na origem (11); a simulacao conclui (0).
    [[ $QA_ESTADO == 0 || $QA_ESTADO == 11 ]] || _harness_falhar "$comando com XDG ausente: $QA_ESTADO $QA_ERRO"
    assert_arquivo_ausente "$B/x" "$comando: nenhum nivel do XDG ausente sobra"
    assert_igual 0 "$(_harness_contar ' N$' "$B/diario")" "$comando: toda chamada com trava"
    unset QA_XDG_STATE
    mkdir -p "$B/estado/dbx"
    chmod 755 "$B/estado/dbx"
    printf 'm' >"$B/estado/dbx/memoria-qa"
    printf 'u' >"$B/estado/dbx/upload-qa"
    printf 't' >"$B/estado/dbx/.memoria.recente"
    antes=$(_qa_retrato "$B/estado")
    _qa_dbx "${args[@]}"
    [[ $QA_ESTADO == 0 || $QA_ESTADO == 11 ]] || _harness_falhar "$comando com estado existente: $QA_ESTADO $QA_ERRO"
    assert_igual "$antes" "$(_qa_retrato "$B/estado")" "$comando: arquivos, bytes e modos (inclusive 0755) iguais"
  done
}

teste_qa_b2_10_estado_sem_escrita_ou_alheio_segue_sem_trava_so_sem_trava_que_decida() {
  # DIV-48, DIV-50: sem escrita e sem trava (ou so com orfa, que ninguem
  # retoma ali), segue com UMA linha de aviso e nada muda; trava viva, de outro
  # host ou ilegivel ja presente ainda decide (7), sem escrita nenhuma.
  local antes trava morto vivo host conteudo n_avisos
  _qa_cenario
  trava=$(_qa_trava_do_par "$B/local" /r)
  morto=$(_qa_pid_morto)
  host=$(_qa_host_campo id)
  mkdir -p "$B/estado/dbx"
  chmod 500 "$B/estado/dbx"
  antes=$(_qa_retrato "$B/estado")
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r
  assert_igual "$antes" "$(_qa_retrato "$B/estado")" 'sem escrita: nada mudou'
  assert_igual 0 "$QA_ESTADO" "sem escrita: segue ($QA_ERRO)"
  n_avisos=0
  [[ $QA_ERRO == *'sem trava de concorrencia'* ]] && n_avisos=1
  [[ ${QA_ERRO#*sem trava de concorrencia} == *'sem trava de concorrencia'* ]] && n_avisos=2
  assert_igual 1 "$n_avisos" 'sem escrita: uma linha de aviso'
  assert_igual '' "$(_qa_residuo)" 'sem escrita: sem residuo'
  "$QA_DORMIR" 60 &
  vivo=$!
  for conteudo in \
    "$(_qa_linha "$vivo" "$host" 1700000000 sync)"$'\n' \
    "$(_qa_linha "$morto" "outra-maquina:x:1" 1700000000 sync)"$'\n' \
    'ilegivel' \
    "$(_qa_linha "$morto" "$host" 1700000000 sync)"$'\n'; do
    chmod 700 "$B/estado/dbx"
    _qa_plantar "$trava" "$conteudo"
    chmod 500 "$B/estado/dbx"
    antes=$(_qa_retrato "$B/estado")
    rm -f "$B/diario"
    _qa_dbx verificar --enviar --origem "$B/local" --destino /r
    assert_igual "$antes" "$(_qa_retrato "$B/estado")" "sem escrita [$conteudo]: nada mudou"
    if [[ $conteudo == *"$morto	$host"* ]]; then
      assert_igual 0 "$QA_ESTADO" "orfa em diretorio sem escrita: segue com aviso ($QA_ERRO)"
      assert_contem 'sem trava de concorrencia' "$QA_ERRO" 'orfa: avisa'
    else
      assert_igual "$QA_CONFLITO" "$QA_ESTADO" "trava que decide em diretorio sem escrita: 7 [$conteudo] ($QA_ERRO)"
      assert_arquivo_ausente "$B/diario" 'recusa sem chamada a API'
    fi
  done
  kill "$vivo" 2>/dev/null
  chmod 700 "$B/estado/dbx"
  # Pai do XDG sem escrita: o diretorio nem pode ser criado.
  rm -rf "$B/estado"
  mkdir -p "$B/ro"
  chmod 500 "$B/ro"
  QA_XDG_STATE="$B/ro/estado"
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r
  unset QA_XDG_STATE
  chmod 700 "$B/ro"
  assert_igual 0 "$QA_ESTADO" "pai sem escrita: segue ($QA_ERRO)"
  assert_contem 'sem trava de concorrencia' "$QA_ERRO" 'pai sem escrita: avisa'
  # Alheio: o diretorio de estado e uma ligacao para um diretorio de root.
  mkdir -p "$B/estado"
  [[ -d / && ! -O / ]] || pular 'raiz do sistema e do proprio usuario'
  ln -s / "$B/estado/dbx"
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r
  assert_igual 0 "$QA_ESTADO" "alheio: segue ($QA_ERRO)"
  assert_contem 'sem trava de concorrencia' "$QA_ERRO" 'alheio: avisa'
  assert_igual '' "$(find / -maxdepth 1 \( -name 'trava-*' -o -name '.trava.*' \) 2>/dev/null)" 'nada escrito no alheio'
}

# ---------------------------------------------------------------------------
# RF-69(a), DIV-38, DIV-47, DIV-49: chave
# ---------------------------------------------------------------------------

teste_qa_b2_11_chave_sem_ordem_canonica_e_sem_caixa() {
  # RF-69(a), DIV-38: mesmo par por grafias diferentes se exclui; par diferente
  # roda.
  local estado
  _qa_cenario
  mkdir -p "$B/real/sub"
  ln -s "$B/real" "$B/atalho"
  printf 'list_folder' >"$B/prender"
  _qa_fundo dono sync --enviar --origem "$B/real/sub" --destino /Pasta/Sub
  local n=0
  while [[ $(_qa_presos) -lt 1 && $n -lt 300 ]]; do "$QA_DORMIR" 0.1; n=$((n + 1)); done
  assert_igual 1 "$(_qa_presos)" 'a dona detem a trava'
  rm -f "$B/prender"
  _qa_dbx verificar --receber --origem /pasta/sub --destino "$B/atalho/sub/"
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" "sentido oposto, caixa e ligacao diferentes: $QA_ERRO"
  _qa_dbx --dry-run sync --receber --origem /PASTA/SUB/ --destino "$B/real/./sub"
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" "barra final e ponto: $QA_ERRO"
  _qa_dbx verificar --enviar --origem "$B/real/sub" --destino /pasta/sub2
  assert_igual 0 "$QA_ESTADO" "remoto diferente roda junto: $QA_ERRO"
  _qa_dbx verificar --enviar --origem "$B/real" --destino /pasta/sub
  assert_igual 0 "$QA_ESTADO" "local diferente roda junto: $QA_ERRO"
  estado=$(_qa_soltar_e_colher dono)
  assert_igual 0 "$estado" 'a dona conclui'
  assert_igual '' "$(_qa_travas)" 'nada sobra'
}

teste_qa_b2_21_mesma_grafia_remota_em_localidades_diferentes_se_exclui() {
  # RF-69(a)(g), RNF-20(b4) (QA-B1B-01: dobra de caixa independente da
  # localidade): o MESMO par, com a MESMA grafia, rodado do agendador (`C`) e do
  # terminal (`C.UTF-8`), tem uma trava so.
  local remoto estado
  _qa_cenario
  printf 'list_folder' >"$B/prender"
  for remoto in /ACAO /AÇÃO /Documentos/RELATÓRIO; do
    rm -f "$B"/preso.* "$B/soltar" "$B/estado.dono" "$B/prender"
    printf 'list_folder' >"$B/prender"
    QA_LOCALIDADE=C.UTF-8 _qa_fundo dono sync --enviar --origem "$B/local" --destino "$remoto"
    local n=0
    while [[ $(_qa_presos) -lt 1 && $n -lt 300 ]]; do "$QA_DORMIR" 0.1; n=$((n + 1)); done
    rm -f "$B/prender"
    QA_LOCALIDADE=C _qa_dbx verificar --enviar --origem "$B/local" --destino "$remoto"
    estado=$QA_ESTADO
    assert_igual 0 "$(_qa_soltar_e_colher dono)" "[$remoto] a dona conclui"
    assert_igual "$QA_CONFLITO" "$estado" "[$remoto] mesma grafia em C e em C.UTF-8: uma trava so ($QA_ERRO)"
  done
}

teste_qa_b2_12_receber_em_destino_ainda_inexistente_tem_a_mesma_chave() {
  # RF-69(a)(b): a raiz que o --receber ainda vai criar, por ligacao no pai,
  # tem a mesma chave da grafia fisica; e ela so e criada sob a trava.
  local estado
  _qa_cenario
  mkdir -p "$B/real"
  ln -s "$B/real" "$B/atalho"
  printf 'list_folder' >"$B/prender"
  _qa_fundo dono sync --receber --origem /r --destino "$B/atalho/novo"
  local n=0
  while [[ $(_qa_presos) -lt 1 && $n -lt 300 ]]; do "$QA_DORMIR" 0.1; n=$((n + 1)); done
  rm -f "$B/prender"
  assert_igual 1 "$(_qa_presos)" 'a dona detem a trava'
  _qa_dbx verificar --enviar --origem "$B/real/novo" --destino /R
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" "grafia fisica do mesmo destino: $QA_ERRO"
  estado=$(_qa_soltar_e_colher dono)
  assert_igual 0 "$estado" "a dona conclui: $(cat "$B/err.dono")"
}

teste_qa_b2_13_download_de_pasta_trava_o_par() {
  # DIV-49: o download de pasta e um sync --receber por dentro; `/r` baixado
  # em `alvo/` vai para `alvo/r`, que e o par.
  _qa_cenario
  mkdir -p "$B/alvo/r"
  printf 'list_folder' >"$B/prender"
  _qa_fundo dono verificar --receber --origem /r --destino "$B/alvo/r"
  local n=0
  while [[ $(_qa_presos) -lt 1 && $n -lt 300 ]]; do "$QA_DORMIR" 0.1; n=$((n + 1)); done
  rm -f "$B/prender"
  : >"$B/eh_pasta"
  _qa_dbx download /r "$B/alvo"
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" "download de pasta do mesmo par: $QA_ERRO"
  assert_contem 'trava ocupada' "$QA_ERRO" 'mensagem da trava'
  assert_igual 0 "$(_qa_soltar_e_colher dono)" 'a dona conclui'
}

# ---------------------------------------------------------------------------
# RF-70: --esperar
# ---------------------------------------------------------------------------

teste_qa_b2_14_esperar_limites_e_valores_nao_numericos() {
  # RF-70(b): uso invalido (2) antes de trava, rede e escrita.
  local v comando
  _qa_cenario
  for comando in sync verificar; do
    for v in '' ' 1' '1 ' '+1' '-1' '1.0' '1e2' '0x10' '3601' '9999' '10000' $'1\n' $'\0331' '١' 'abc'; do
      _qa_dbx "$comando" --enviar --origem "$B/local" --destino /r --esperar "$v"
      assert_igual "$QA_USO" "$QA_ESTADO" "$comando --esperar [$v]: uso invalido"
      assert_contem '--esperar' "$QA_ERRO" "$comando [$v]: a mensagem nomeia a opcao"
      _qa_sem_esc "$QA_ERRO" "$comando [$v]"
    done
    _qa_dbx "$comando" --enviar --origem "$B/local" --destino /r --wait
    assert_igual "$QA_USO" "$QA_ESTADO" "$comando --wait sem valor"
    _qa_dbx "$comando" --enviar --origem "$B/local" --destino /r --esperar 5 --wait x
    assert_igual "$QA_USO" "$QA_ESTADO" "$comando: o ultimo valor vence e e validado"
  done
  assert_arquivo_ausente "$B/diario" 'nenhuma chamada a API'
  assert_igual 'ausente' "$(_qa_retrato "$B/estado")" 'nenhuma trava nem estado criado'
  for v in 0 3600 0003 03600; do
    _qa_dbx verificar --enviar --origem "$B/local" --destino /r --wait "$v"
    case $v in
      03600) assert_igual "$QA_USO" "$QA_ESTADO" "[$v]: mais de 4 digitos" ;;
      *) assert_igual 0 "$QA_ESTADO" "[$v] valido: $QA_ERRO" ;;
    esac
  done
  _qa_dbx upload "$B/cfg/dbx/credencial.json" /x --esperar 1
  assert_igual "$QA_USO" "$QA_ESTADO" 'upload recusa --esperar'
}

teste_qa_b2_15_esperar_real_adquire_ao_liberar_e_esgota_no_prazo() {
  # RF-70(c): sondagem de 1 s com `sleep` real.
  local inicio fim
  _qa_cenario
  printf 'list_folder' >"$B/prender"
  _qa_fundo dono verificar --enviar --origem "$B/local" --destino /r
  local n=0
  while [[ $(_qa_presos) -lt 1 && $n -lt 300 ]]; do "$QA_DORMIR" 0.1; n=$((n + 1)); done
  rm -f "$B/prender"
  inicio=$SECONDS
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r --esperar 2
  fim=$SECONDS
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" 'esgotou'
  assert_contem 'esperou 2 s' "$QA_ERRO" 'diz o tempo'
  [[ $((fim - inicio)) -ge 2 && $((fim - inicio)) -le 5 ]] || _harness_falhar "esperou $((fim - inicio)) s para N=2"
  _qa_fundo espera verificar --enviar --origem "$B/local" --destino /r --esperar 20
  "$QA_DORMIR" 1.5
  assert_arquivo_ausente "$B/estado.espera" 'a segunda ainda espera'
  assert_igual 0 "$(_qa_soltar_e_colher dono)" 'a dona conclui'
  _qa_esperar "$B/estado.espera" 100
  assert_igual 0 "$(cat "$B/estado.espera")" "a que esperava adquiriu: $(cat "$B/err.espera")"
  assert_igual '' "$(_qa_travas)" 'nada sobra'
}

# ---------------------------------------------------------------------------
# RNF-35: sinais e lib/tmp
# ---------------------------------------------------------------------------

teste_qa_b2_16_sinal_na_espera_sai_14_sem_residuo_e_sem_tocar_a_trava_alheia() {
  # RF-70(e), RNF-35(c): o sinal chega DURANTE a espera, entregue pelo duplo de
  # `sleep` (que dorme de verdade e entao sinaliza o grupo ou so o `dbx`). Um
  # processo lancado com `&` herda INT ignorado, por isso o sinal sai do duplo.
  local sinal alvo trava conteudo
  _qa_cenario
  printf 'list_folder' >"$B/prender"
  _qa_fundo dono verificar --enviar --origem "$B/local" --destino /r
  local n=0
  while [[ $(_qa_presos) -lt 1 && $n -lt 300 ]]; do "$QA_DORMIR" 0.1; n=$((n + 1)); done
  rm -f "$B/prender"
  trava=$(_qa_trava_do_par "$B/local" /r)
  conteudo=$(cat "$trava")
  # A dona tem a propria area e a da requisicao presa no duplo.
  local da_dona
  da_dona=$(_qa_residuo | LC_ALL=C sort)
  for sinal in INT TERM HUP; do
    for alvo in grupo processo; do
      {
        printf '#!%s\nDORMIR=%q\n' "$BASH" "$QA_DORMIR"
        printf '"$DORMIR" "$@"\n'
        if [[ $alvo == grupo ]]; then
          printf 'kill -s %s 0\n' "$sinal"
        else
          printf 'kill -s %s "$PPID"\n' "$sinal"
        fi
      } >"$B/bin/sleep"
      chmod +x "$B/bin/sleep"
      _qa_dbx verificar --enviar --origem "$B/local" --destino /r --esperar 30
      assert_igual "$QA_NAO_CONCLUIDA" "$QA_ESTADO" "$sinal ao $alvo na espera: 14 ($QA_ERRO)"
      assert_igual "$conteudo" "$(cat "$trava")" "$sinal ao $alvo: a trava da dona intacta"
      assert_igual "$da_dona" "$(_qa_residuo | LC_ALL=C sort)" "$sinal ao $alvo: so as areas da dona em TMPDIR"
    done
  done
  rm -f "$B/bin/sleep"
  assert_igual 0 "$(_qa_soltar_e_colher dono)" 'a dona conclui'
  assert_igual '' "$(_qa_residuo)" 'nenhuma area sobra'
  assert_igual '' "$(_qa_travas)" 'nenhuma trava sobra'
}

teste_qa_b2_17_lib_tmp_subshell_codigo_e_sinal_durante_a_limpeza() {
  # RNF-35(b)(d)(h): subshell nao limpa do pai; codigo original preservado;
  # sinal durante a acao de limpeza nao a interrompe; LIFO acoes e depois areas.
  local d="$B" saida
  _qa_cenario
  d=$B
  saida=$(TMPDIR="$d/tmp" bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/tmp.sh"
    dbx_tmp_area pai; pai=$DBX_TMP_CAMINHO
    ( dbx_tmp_area filho; printf "%s" "$DBX_TMP_CAMINHO" >"$2/filho" )
    [[ -d $pai ]] && printf "pai-vivo "
    [[ -e $(cat "$2/filho") ]] || printf "filho-limpo "
    sub=$(dbx_tmp_area cap; printf "%s" "$DBX_TMP_CAMINHO")
    [[ -e $sub ]] || printf "captura-limpa "
    exit 5' _ "$DBX_HARNESS_RAIZ" "$d")
  local estado=$?
  assert_igual 'pai-vivo filho-limpo captura-limpa ' "$saida" 'cada processo limpa so o seu'
  assert_igual 5 "$estado" 'codigo original preservado'
  assert_igual '' "$(_qa_residuo)" 'nada sobra'

  # Sinal durante a acao: ela termina, as areas saem depois.
  QA_D=$d QA_DORMIR_X=$QA_DORMIR TMPDIR="$d/tmp" setsid bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/tmp.sh"
    qa_acao() { printf "a1 " >>"$QA_D/ordem"; [[ -d $(cat "$QA_D/area") ]] && printf "area-ainda " >>"$QA_D/ordem"
      : >"$QA_D/na_acao"; "$QA_DORMIR_X" 1; printf "fim " >>"$QA_D/ordem"; }
    qa_acao2() { printf "a2 " >>"$QA_D/ordem"; }
    dbx_tmp_area x; printf "%s" "$DBX_TMP_CAMINHO" >"$QA_D/area"
    dbx_tmp_acao_registrar qa_acao
    dbx_tmp_acao_registrar qa_acao2
    exit 3' _ "$DBX_HARNESS_RAIZ" &
  local pid=$!
  _qa_esperar "$d/na_acao" 50
  kill -s TERM "$pid"
  wait "$pid"
  estado=$?
  assert_igual 'a2 a1 area-ainda fim ' "$(cat "$d/ordem")" 'LIFO, area viva na acao, acao nao interrompida'
  assert_igual '' "$(_qa_residuo)" 'area removida depois da acao'
  assert_igual 3 "$estado" 'sinal na limpeza do EXIT nao muda o codigo ja decidido'
}

teste_qa_b2_18_obs03_sinal_logo_apos_o_mktemp_nao_deixa_area() {
  # RNF-35(e): dobro de `mktemp` que cria e se auto-sinaliza (processo principal).
  local sinal estado
  _qa_cenario
  for sinal in INT TERM HUP; do
    {
      printf '#!%s\nREAL=%q\n' "$BASH" "$(command -v mktemp)"
      printf '"$REAL" "$@"; s=$?; kill -s %s "$QA_PRINCIPAL"; exit "$s"\n' "$sinal"
    } >"$B/bin/mktemp"
    chmod +x "$B/bin/mktemp"
    PATH="$B/bin:$PATH" TMPDIR="$B/tmp" bash -c '
      export QA_PRINCIPAL=$$
      . "$1/lib/errors.sh"; . "$1/lib/tmp.sh"
      dbx_tmp_area obs; "$2" 2; exit 0' _ "$DBX_HARNESS_RAIZ" "$QA_DORMIR"
    estado=$?
    assert_igual "$QA_NAO_CONCLUIDA" "$estado" "$sinal: 14"
    assert_igual '' "$(_qa_residuo)" "$sinal: a area criada foi removida"
  done
}

# ---------------------------------------------------------------------------
# RF-69(h2)(p), RF-71, RNF-03: unlink, diagnostico e segredo
# ---------------------------------------------------------------------------

teste_qa_b2_19_unlink_nao_apaga_estado_de_sync_que_comecou_durante_ele() {
  # RF-69(h2)(p), DIV-44: a recusa vale para a execucao viva no momento de
  # apagar, e nao so no inicio do unlink (a revogacao e uma chamada de rede).
  # Deterministico: o sync continua preso no duplo, detendo a trava, ate DEPOIS
  # de o unlink terminar; so a revogacao e solta.
  local estado_u trava err_u
  _qa_cenario
  mkdir -p "$B/estado/dbx"
  chmod 700 "$B/estado/dbx"
  printf 'memoria do par' >"$B/estado/dbx/memoria-qa"
  printf 'token/revoke' >"$B/prender"
  _qa_fundo unlink unlink --confirmar
  local n=0
  while [[ $(_qa_presos) -lt 1 && $n -lt 300 ]]; do "$QA_DORMIR" 0.1; n=$((n + 1)); done
  assert_igual 1 "$(_qa_presos)" 'o unlink esta na revogacao'
  # Um sync do par comeca e fica detendo a trava.
  printf 'list_folder' >"$B/prender"
  rm -f "$B"/preso.*
  _qa_fundo sync sync --enviar --origem "$B/local" --destino /r
  n=0
  while [[ $(_qa_presos) -lt 1 && $n -lt 300 ]]; do "$QA_DORMIR" 0.1; n=$((n + 1)); done
  trava=$(_qa_trava_do_par "$B/local" /r)
  assert_arquivo_existe "$trava" 'o sync detem a trava'
  : >"$B/soltar_revoke"
  _qa_esperar "$B/estado.unlink"
  estado_u=$(cat "$B/estado.unlink")
  IFS= read -r -d '' err_u <"$B/err.unlink" || :
  assert_arquivo_existe "$trava" 'o sync ainda detinha a trava quando o unlink terminou'
  assert_arquivo_existe "$B/estado/dbx/memoria-qa" 'a memoria do sync em curso nao foi apagada'
  assert_nao_contem 'trava mantida (orfa' "$err_u" 'trava viva nunca e descrita como nao viva'
  assert_igual "$QA_CONFLITO" "$estado_u" "unlink com sync vivo ao apagar: conflito ($err_u)"
  assert_contem 'execucao em curso' "$err_u" 'a recusa nomeia a execucao em curso'
  _qa_sem_sentinela "$err_u" 'unlink recusado depois da revogacao'
  : >"$B/soltar"
  _qa_esperar "$B/estado.sync"
}

teste_qa_b2_23_unlink_para_quando_uma_orfa_e_retomada_durante_a_remocao() {
  # RF-69(h2)(p), QA-B2-02 (conferencia antes de cada remocao): um sync que ja
  # carregou a credencial retoma uma orfa CONHECIDA do unlink no meio da
  # remocao (mesmo nome, agora viva). Duplos: o `ln` do sync fica preso ate o
  # `rm` do unlink chegar a primeira memoria, e esse `rm` so volta quando o
  # sync detem a trava. A remocao tem de parar: a segunda memoria fica, e a
  # trava viva nunca e descrita como mantida (orfa, ilegivel ou de outro host).
  local trava err_u estado_u
  _qa_cenario
  trava=$(_qa_trava_do_par "$B/local" /r)
  _qa_plantar "$trava" "$(_qa_linha "$(_qa_pid_morto)" "$(_qa_host_campo id)" 1700000000 sync)"$'\n'
  printf 'a' >"$B/estado/dbx/memoria-a"
  printf 'b' >"$B/estado/dbx/memoria-b"
  {
    printf '#!%s\nLN=%q\nB=%q\nDORMIR=%q\n' "$BASH" "$QA_LN" "$B" "$QA_DORMIR"
    cat <<'FIM'
if [[ ! -e $B/ln_bloqueado ]]; then
  : >"$B/ln_bloqueado"
  while [[ ! -e $B/ln_liberado ]]; do "$DORMIR" 0.05; done
fi
exec "$LN" "$@"
FIM
  } >"$B/bin/ln"
  {
    printf '#!%s\nRM=%q\nB=%q\nDORMIR=%q\n' "$BASH" "$(command -v rm)" "$B" "$QA_DORMIR"
    cat <<'FIM'
if [[ " $* " == *'/memoria-a '* && ! -e $B/ln_liberado ]]; then
  : >"$B/ln_liberado"
  n=0
  while ! compgen -G "$B/preso.*" >/dev/null && [[ $n -lt 300 ]]; do "$DORMIR" 0.1; n=$((n + 1)); done
fi
exec "$RM" "$@"
FIM
  } >"$B/bin/rm"
  chmod +x "$B/bin/ln" "$B/bin/rm"
  printf 'list_folder' >"$B/prender"
  _qa_fundo sync sync --enviar --origem "$B/local" --destino /r
  _qa_esperar "$B/ln_bloqueado"
  _qa_dbx unlink --confirmar
  estado_u=$QA_ESTADO err_u=$QA_ERRO
  assert_arquivo_existe "$B/ln_liberado" 'o rm do unlink soltou o sync'
  assert_igual 1 "$(_qa_presos)" 'o sync retomou a orfa e detem a trava'
  assert_nao_contem 'trava mantida (orfa' "$err_u" 'trava retomada (viva) nunca e descrita como nao viva'
  assert_arquivo_existe "$B/estado/dbx/memoria-b" 'a remocao parou antes da segunda memoria'
  assert_igual "$QA_CONFLITO" "$estado_u" "unlink: conflito ($err_u)"
  : >"$B/soltar"
  _qa_esperar "$B/estado.sync"
  rm -f "$B/bin/ln" "$B/bin/rm"
  assert_contem 'removida' "$(cat "$B/err.sync")" 'o sync retomou a orfa (DIV-53)'
}

teste_qa_b2_22_div51_download_para_socket_vivo_sai_0_e_fechado_sai_15() {
  # RNF-35(g), DIV-51: socket vivo recebe tudo e sai 0; consumidor que fecha
  # sai 15 (consumidor_encerrou), sem 3 e sem reemissao.
  command -v python3 >/dev/null 2>&1 || pular 'python3 ausente: sem como montar o socket'
  local resultado
  _qa_cenario
  _qa_env
  resultado=$(python3 -I -c '
import socket, subprocess, sys
amb = sys.argv[2:]
env = dict(a.split("=", 1) for a in amb[2:] if "=" in a)
a, b = socket.socketpair()
p = subprocess.Popen(["bash", sys.argv[1], "download", "/x"], stdout=a, stderr=subprocess.DEVNULL, env=env)
a.close()
dados = b""
while True:
    c = b.recv(4096)
    if not c:
        break
    dados += c
p.wait()
print("%d %s" % (p.returncode, dados.decode()))
' "$QA_DBX" "${QA_AMBIENTE[@]}")
  assert_igual '0 x' "$resultado" 'socket vivo: codigo 0 e o conteudo inteiro'
  # Consumidor que fecha antes: o socket ja nasce fechado do outro lado.
  rm -f "$B/diario"
  resultado=$(python3 -I -c '
import socket, subprocess, sys
amb = sys.argv[2:]
env = dict(a.split("=", 1) for a in amb[2:] if "=" in a)
a, b = socket.socketpair()
b.close()
p = subprocess.Popen(["bash", sys.argv[1], "download", "/x"], stdout=a, stderr=subprocess.PIPE, env=env)
a.close()
_, err = p.communicate()
print("%d %s" % (p.returncode, "consumidor" in err.decode()))
' "$QA_DBX" "${QA_AMBIENTE[@]}")
  assert_igual '15 True' "$resultado" 'socket fechado: 15 com a causa nomeada'
  assert_igual 1 "$(_harness_contar 'files/download' "$B/diario")" 'socket fechado: sem reemissao do download'
  assert_igual '' "$(_qa_residuo)" 'sem residuo'
}

teste_qa_b2_20_mensagens_de_trava_sem_segredo_e_nome_hostil_sem_byte_cru() {
  # RF-69(d)(k), RF-71, RNF-03: sentinelas ausentes; arquivo `trava-` com nome
  # hostil plantado no diretorio de estado nao chega cru ao terminal.
  local trava saida
  _qa_cenario
  printf 'list_folder' >"$B/prender"
  _qa_fundo dono sync --enviar --origem "$B/local" --destino /r
  local n=0
  while [[ $(_qa_presos) -lt 1 && $n -lt 300 ]]; do "$QA_DORMIR" 0.1; n=$((n + 1)); done
  rm -f "$B/prender"
  _qa_dbx verificar --enviar --origem "$B/local" --destino /r
  _qa_sem_sentinela "$QA_SAIDA$QA_ERRO" 'ocupada'
  _qa_dbx unlink --confirmar
  assert_igual "$QA_CONFLITO" "$QA_ESTADO" 'unlink com viva: 7'
  _qa_sem_sentinela "$QA_SAIDA$QA_ERRO" 'unlink recusado'
  _qa_dbx diagnostico
  saida="$QA_SAIDA$QA_ERRO"
  _qa_dbx --json diagnostico
  saida+="$QA_SAIDA$QA_ERRO"
  _qa_sem_sentinela "$saida" 'diagnostico'
  assert_igual 0 "$(_qa_soltar_e_colher dono)" 'a dona conclui'
  trava=$(_qa_trava_do_par "$B/local" /r)
  _qa_plantar "${trava%/*}/trava-"$'\033]0;QA\007\033[31mhostil\nlinha' 'lixo'
  _qa_dbx diagnostico
  _qa_sem_esc "$QA_SAIDA$QA_ERRO" 'diagnostico com nome hostil'
  [[ "$QA_SAIDA$QA_ERRO" != *$'\007'* ]] || _harness_falhar 'BEL cru no diagnostico'
  _qa_dbx --json diagnostico
  _qa_sem_esc "$QA_SAIDA$QA_ERRO" 'diagnostico --json com nome hostil'
  _qa_dbx unlink --confirmar
  _qa_sem_esc "$QA_SAIDA$QA_ERRO" 'unlink com nome hostil'
}

harness_executar "$@"
