#!/usr/bin/env bash
# Testes da trava de concorrencia em lib/state.sh (RF-69, parecer do DBA de
# 2026-10-19; TC-TRV-12..15, 17, 21..30, 32..34, e a parte de biblioteca de
# TC-TRV-01, 09..11, 18).
#
# A CONCORRENCIA E REAL: cada disputante e um processo `bash` proprio, liberado
# por uma barreira de arquivo, e nao uma simulacao em laco. A trava protege
# contra outro PROCESSO, e so outro processo prova a exclusao.
#
# O filtro `state` do mapa de modulos casa este arquivo (substring), entao todo
# diff em lib/state.sh o seleciona.
#
# shellcheck disable=SC2016,SC2097,SC2098
# Justificativa: os roteiros dos processos filhos chegam sem expansao, e as
# atribuicoes de ambiente repassam ao filho valores do proprio caso.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly CONFLITO=7
IDENT='ident-SENTINELA-NAO-VAZA'

# _area — area do caso; publica AREA e ESTADO (diretorio de estado de lib/state).
_area() {
  AREA=$(mktemp -d "$DBX_TESTES_TMP/trava.XXXXXX")
  mkdir -p "$AREA/xdg" "$AREA/tmp"
  ESTADO="$AREA/xdg/dbx"
}

# _filho <roteiro> [args] — roda o roteiro num bash proprio com lib/state
# carregada. Publica FILHO_ESTADO e FILHO_SAIDA (stdout e stderr).
_filho() {
  local roteiro=$1
  shift
  FILHO_SAIDA=$(_filho_cru "$roteiro" "$@" 2>&1)
  FILHO_ESTADO=$?
}

_filho_cru() {
  local roteiro=$1
  shift
  XDG_STATE_HOME="$AREA/xdg" TMPDIR="$AREA/tmp" AREA="$AREA" ESTADO="$ESTADO" \
    RAIZ="$DBX_HARNESS_RAIZ" IDENT="$IDENT" bash -c '
    . "$RAIZ/lib/errors.sh"; . "$RAIZ/lib/json.sh"; . "$RAIZ/lib/config.sh"; . "$RAIZ/lib/state.sh"
'"$roteiro" _ "$@" </dev/null
}

# _host — host_id corrente e componentes, pela definicao unica de lib/state.
_host() {
  _filho_cru 'dbx_state_host_id; printf "%s\n%s\n%s\n%s\n" "$DBX_STATE_HOST_ID" "$DBX_STATE_HOST_NOME" "$DBX_STATE_HOST_BOOT" "$DBX_STATE_HOST_NS"'
}

# _caminho <identidade> <local> <remoto> — caminho da trava do par.
_caminho() {
  _filho_cru 'dbx_state_trava_caminho "$1" "$2" "$3" && printf "%s" "$DBX_STATE_RESULTADO"' "$@"
}

# _linha <pid> <host_id> <inicio> <comando> — conteudo valido de trava.
_linha() { printf 'dbx-trava\t1\t%s\t%s\t%s\t%s\tfim\n' "$1" "$2" "$3" "$4"; }

# _plantar <arquivo> <conteudo> [cru] — trava 0600 escrita a mao, no diretorio
# 0700. O conteudo vem de `$( )`, que corta a quebra final: ela e devolvida,
# salvo com `cru`.
_plantar() {
  # Caminho vazio (aquisicao quebrada) escreveria no diretorio corrente.
  [[ $1 == "$AREA"/* ]] || _harness_falhar 'trava fora da area do caso' "[$1]"
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  if [[ ${3:-} == 'cru' ]]; then
    printf '%s' "$2" >"$1"
  else
    printf '%s\n' "$2" >"$1"
  fi
  chmod 600 "$1"
}

# _pid_morto — pid que existiu e ja terminou.
_pid_morto() {
  local pid
  sleep 0 &
  pid=$!
  wait "$pid"
  printf '%s' "$pid"
}

readonly ADQUIRIR='dbx_state_trava_adquirir "$IDENT" /dados /Remoto sync 0; e=$?
printf "estado=%s\n" "$e"
printf "motivo=%s\n" "$DBX_STATE_MOTIVO"
printf "aviso=%s\n" "$DBX_STATE_AVISO"'

# ---------------------------------------------------------------------------
# Chave, local e formato (RF-69(a)(h)(k); TC-TRV-01, TC-TRV-15)
# ---------------------------------------------------------------------------

teste_chave_e_sem_ordem_sem_caixa_no_remoto_e_por_par() {
  _area
  local a b c d e
  a=$(_caminho "$IDENT" /dados /Remoto)
  b=$(_caminho "$IDENT" /dados /remoto)
  c=$(_caminho "$IDENT" /dados /outro)
  d=$(_caminho '' /dados /Remoto)
  e=$(_caminho sem-conta /dados /Remoto)
  [[ $a =~ /trava-[0-9a-f]{32}$ ]] || _harness_falhar 'nome trava-<resumo>' "$a"
  assert_igual "$ESTADO" "${a%/*}" 'no diretorio de estado'
  assert_igual "$a" "$b" 'o remoto entra sem caixa'
  assert_diferente "$a" "$c" 'pares diferentes, travas diferentes'
  assert_igual "$d" "$e" 'sem identidade, o marcador sem-conta'
  assert_nao_contem 'SENTINELA' "$a" 'nenhum dado externo cru no nome'
}

teste_aquisicao_cria_0600_em_0700_com_linha_unica_e_liberacao_remove() {
  _area
  _filho "$ADQUIRIR"'
    a=$DBX_STATE_TRAVA
    stat -c "%a" "$a" >"$AREA/modo_arquivo"
    stat -c "%a" "${a%/*}" >"$AREA/modo_dir"
    cp "$a" "$AREA/copia"
    printf "%s" "$$" >"$AREA/pid"
    dbx_state_trava_liberar
    [[ -e $a ]] && printf "sobrou\n"
    exit 0'
  assert_contem 'estado=0' "$FILHO_SAIDA" 'adquirida'
  assert_nao_contem 'sobrou' "$FILHO_SAIDA" 'a liberacao remove'
  assert_igual 600 "$(cat "$AREA/modo_arquivo")" 'arquivo 0600'
  assert_igual 700 "$(cat "$AREA/modo_dir")" 'diretorio 0700'
  local -a campos=()
  IFS=$'\t' read -r -a campos <"$AREA/copia"
  assert_igual 7 "${#campos[@]}" 'sete campos'
  assert_igual 'dbx-trava 1' "${campos[0]} ${campos[1]}" 'marca e versao'
  assert_igual "$(cat "$AREA/pid")" "${campos[2]}" 'pid do dono'
  assert_igual "$(_host | head -1)" "${campos[3]}" 'host_id'
  assert_igual 'sync fim' "${campos[5]} ${campos[6]}" 'comando e campo-fim'
  assert_igual 1 "$(wc -l <"$AREA/copia")" 'uma linha'
  assert_igual '' "$(find "$ESTADO" -name '.trava.*' 2>/dev/null)" 'o temporario nao sobra'
}

teste_termino_do_processo_libera_a_trava() {
  _area
  _filho "$ADQUIRIR"'
    printf "%s" "$DBX_STATE_TRAVA" >"$AREA/trava"
    exit 3'
  assert_contem 'estado=0' "$FILHO_SAIDA" 'adquirida'
  [[ $(cat "$AREA/trava") == "$ESTADO"/trava-* ]] || _harness_falhar 'a trava nao foi detida'
  assert_igual 3 "$FILHO_ESTADO" 'o codigo do processo e preservado'
  assert_arquivo_ausente "$(cat "$AREA/trava")" 'liberada no termino'
}

teste_host_id_tem_nome_boot_e_namespace_no_alfabeto() {
  _area
  local -a h=()
  mapfile -t h < <(_host)
  [[ ${h[0]} =~ ^[A-Za-z0-9._:-]{1,255}$ ]] || _harness_falhar 'alfabeto do host_id' "${h[0]}"
  assert_igual "${h[1]}:${h[2]}:${h[3]}" "${h[0]}" 'nome:boot:namespace'
  if [[ -r /proc/sys/kernel/random/boot_id ]]; then
    assert_igual "$(cat /proc/sys/kernel/random/boot_id)" "${h[2]}" 'boot_id do kernel'
  fi
  if [[ -e /proc/self/ns/pid ]]; then
    assert_igual "$(stat -L -c %i /proc/self/ns/pid)" "${h[3]}" 'inode do namespace de pid'
  fi
}

# ---------------------------------------------------------------------------
# Ocupada, viva, outro host, ilegivel (RF-69(d)(f)(k)(l); TC-TRV-10, 11, 17,
# 21, 22, 24..27)
# ---------------------------------------------------------------------------

teste_trava_viva_recusa_com_7_e_mensagem_sem_segredo() {
  _area
  local trava host vivo
  trava=$(_caminho "$IDENT" /dados /Remoto)
  host=$(_host | head -1)
  sleep 30 &
  vivo=$!
  _plantar "$trava" "$(_linha "$vivo" "$host" 1700000000 verificar)"
  cp "$trava" "$AREA/antes"
  _filho "$ADQUIRIR"
  kill "$vivo" 2>/dev/null
  assert_contem "estado=$CONFLITO" "$FILHO_SAIDA" 'conflito'
  assert_contem "pid $vivo" "$FILHO_SAIDA" 'nomeia o pid'
  assert_contem "$(_host | sed -n 2p)" "$FILHO_SAIDA" 'nomeia o host'
  assert_contem '2023-11-14T22:13:20Z' "$FILHO_SAIDA" 'inicio em UTC, ISO 8601'
  assert_contem 'verificar' "$FILHO_SAIDA" 'nomeia o comando'
  assert_contem '--esperar' "$FILHO_SAIDA" 'aponta a espera'
  assert_nao_contem 'SENTINELA' "$FILHO_SAIDA" 'nenhum segredo nem identidade'
  cmp -s "$AREA/antes" "$trava" || _harness_falhar 'a trava viva foi alterada'
}

teste_orfa_do_mesmo_host_e_retomada_com_aviso() {
  _area
  local trava host morto
  trava=$(_caminho "$IDENT" /dados /Remoto)
  host=$(_host | head -1)
  morto=$(_pid_morto)
  _plantar "$trava" "$(_linha "$morto" "$host" 1700000000 sync)"
  _filho "$ADQUIRIR"'
    IFS=$'"'"'\t'"'"' read -r -a c <"$DBX_STATE_TRAVA"; printf "dono=%s\n" "${c[2]}"; printf "eu=%s\n" "$$"'
  assert_contem 'estado=0' "$FILHO_SAIDA" 'retomada'
  assert_contem "pid $morto" "$FILHO_SAIDA" 'o aviso nomeia o pid da orfa'
  assert_contem '2023-11-14T22:13:20Z' "$FILHO_SAIDA" 'e o inicio'
  local dono eu
  dono=$(grep '^dono=' <<<"$FILHO_SAIDA")
  eu=$(grep '^eu=' <<<"$FILHO_SAIDA")
  assert_igual "${eu#eu=}" "${dono#dono=}" 'a trava passou a ser do retomador'
}

teste_boot_diferente_no_mesmo_host_e_orfa_mesmo_com_pid_vivo() {
  # TC-TRV-25: reinicio prova orfandade; o pid vivo e de outro boot.
  _area
  local -a h=()
  mapfile -t h < <(_host)
  local trava
  trava=$(_caminho "$IDENT" /dados /Remoto)
  _plantar "$trava" "$(_linha "$$" "${h[1]}:outro-boot-0000:${h[3]}" 1700000000 sync)"
  _filho "$ADQUIRIR"
  assert_contem 'estado=0' "$FILHO_SAIDA" 'retomada'
  assert_contem 'aviso=' "$FILHO_SAIDA" 'com aviso'
  assert_nao_contem 'aviso=$' "$FILHO_SAIDA" 'aviso nao vazio'
}

teste_namespace_ou_nome_diferente_e_outro_host_nunca_retomado() {
  # TC-TRV-11 e TC-TRV-26; TC-TRV-27: `mtime` antigo ou futuro nao muda nada.
  _area
  local -a h=()
  mapfile -t h < <(_host)
  local trava morto hostid
  trava=$(_caminho "$IDENT" /dados /Remoto)
  morto=$(_pid_morto)
  for hostid in "${h[1]}:${h[2]}:999999" "outra-maquina:${h[2]}:${h[3]}"; do
    _plantar "$trava" "$(_linha "$morto" "$hostid" 1700000000 sync)"
    touch -d '@1000000000' "$trava"
    cp "$trava" "$AREA/antes"
    _filho "$ADQUIRIR"
    assert_contem "estado=$CONFLITO" "$FILHO_SAIDA" "$hostid: recusa"
    assert_contem 'outro host' "$FILHO_SAIDA" "$hostid: diz que e de outro host"
    assert_contem "$trava" "$FILHO_SAIDA" "$hostid: diz como liberar a mao"
    cmp -s "$AREA/antes" "$trava" || _harness_falhar "$hostid: a trava de outro host foi tocada"
    touch -d '@4000000000' "$trava"
    _filho "$ADQUIRIR"
    assert_contem "estado=$CONFLITO" "$FILHO_SAIDA" "$hostid: mtime futuro nao decide"
  done
}

teste_matriz_hostil_e_ilegivel_nunca_apagada_nem_retomada_nem_ecoada() {
  # TC-TRV-24 e TC-TRV-17.
  _area
  local trava host morto conteudo indice=0 massa pid
  trava=$(_caminho "$IDENT" /dados /Remoto)
  host=$(_host | head -1)
  morto=$(_pid_morto)
  # Massa montada por `printf -v` e plantada crua (RSK-28): cada byte e o do caso.
  local -a hostis=('' $'\n')
  printf -v massa 'dbx-trava\t1\t%s\t%s\n' "$morto" "$host"
  hostis+=("$massa")
  printf -v massa 'dbx-trava\t1\t%s\t%s\t1700000000\tsync\n' "$morto" "$host"
  hostis+=("$massa")
  for pid in 0 1 -1 99999999 007; do
    printf -v massa 'dbx-trava\t1\t%s\t%s\t1700000000\tsync\tfim\n' "$pid" "$host"
    hostis+=("$massa")
  done
  printf -v massa 'dbx-trava\t1\t%s\th\033]0;X\007\t1700000000\tsync\tfim\n' "$morto"
  hostis+=("$massa")
  printf -v massa 'dbx-trava\t2\t%s\t%s\t1700000000\tsync\tfim\n' "$morto" "$host"
  hostis+=("$massa")
  printf -v massa 'dbx-trava\t1\t%s\t%s\t1700000000\tsync\textra\tfim\n' "$morto" "$host"
  hostis+=("$massa")
  printf -v massa 'dbx-trava\t1\t%s\t%s\t1700000000\tfim\n' "$morto" "$host"
  hostis+=("$massa")
  printf -v massa 'dbx-trava\t1\t%s\t%s\t1700000000\tupload\tfim\n' "$morto" "$host"
  hostis+=("$massa")
  printf -v massa 'dbx-trava\t1\t%s\t%s\t1700000000\tsync\tfim\n%600s' "$morto" "$host" ''
  hostis+=("$massa")
  printf -v massa 'dbx-trava\t1\t%s\t%s\t1700000000\tsync\tfim\nsegunda\n' "$morto" "$host"
  hostis+=("$massa")
  for conteudo in "${hostis[@]}"; do
    indice=$((indice + 1))
    _plantar "$trava" "$conteudo" cru
    cp "$trava" "$AREA/antes"
    _filho "$ADQUIRIR"
    assert_contem "estado=$CONFLITO" "$FILHO_SAIDA" "caso $indice: recusa"
    assert_contem 'ilegivel' "$FILHO_SAIDA" "caso $indice: trava ilegivel"
    assert_contem "$trava" "$FILHO_SAIDA" "caso $indice: remedio manual com o caminho"
    [[ $FILHO_SAIDA == *$'\033'* || $FILHO_SAIDA == *$'\007'* ]] &&
      _harness_falhar "caso $indice: byte cru da trava chegou a saida"
    cmp -s "$AREA/antes" "$trava" || _harness_falhar "caso $indice: a trava ilegivel foi alterada"
  done
  # Vazia de verdade e sem a quebra final (escrita interrompida).
  for conteudo in '' "$(_linha "$morto" "$host" 1700000000 sync)"; do
    _plantar "$trava" "$conteudo" cru
    _filho "$ADQUIRIR"
    assert_contem 'ilegivel' "$FILHO_SAIDA" "cru [${#conteudo}]: trava ilegivel"
    assert_arquivo_existe "$trava" "cru [${#conteudo}]: nao apagada"
  done
  # Validas de 2 e de 7 digitos sao legiveis (orfas: retomadas).
  for morto in 12 9999999; do
    kill -0 "$morto" 2>/dev/null && continue
    _plantar "$trava" "$(_linha "$morto" "$host" 1700000000 sync)"
    _filho "$ADQUIRIR"
    assert_contem 'estado=0' "$FILHO_SAIDA" "pid $morto valido e morto: retomada"
  done
}

teste_trava_com_dono_alheio_ligacao_ou_diretorio_e_ilegivel_e_intacta() {
  # TC-TRV-21 e TC-TRV-22.
  _area
  local trava
  trava=$(_caminho "$IDENT" /dados /Remoto)
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  mkdir "$trava"
  _filho "$ADQUIRIR"
  assert_contem "estado=$CONFLITO" "$FILHO_SAIDA" 'diretorio no nome: recusa'
  assert_igual '' "$(find "$trava" -mindepth 1)" 'o ln nao deixa elo dentro do diretorio'
  rmdir "$trava"
  printf 'alvo' >"$AREA/alvo"
  ln -s "$AREA/alvo" "$trava"
  _filho "$ADQUIRIR"
  assert_contem "estado=$CONFLITO" "$FILHO_SAIDA" 'ligacao simbolica: recusa'
  assert_igual "$AREA/alvo" "$(readlink "$trava")" 'o elo fica'
  assert_igual 'alvo' "$(cat "$AREA/alvo")" 'e o alvo tambem'
  rm -f "$trava"
  if [[ $EUID -ne 0 && -e /etc/hostname && ! -O /etc/hostname ]]; then
    ln -s /etc/hostname "$trava"
    _filho 'dbx_state_trava_ler "$1"; printf "ler=%s\n" "$?"' "$trava"
    assert_contem 'ler=1' "$FILHO_SAIDA" 'arquivo de outro dono e ilegivel'
  fi
}

# ---------------------------------------------------------------------------
# Criacao exclusiva e retomada serializada (RF-69(g)(j)(m); TC-TRV-12, 13, 14,
# 23, 28..30)
# ---------------------------------------------------------------------------

# _disputa <n> <roteiro_antes> — n processos reais, liberados juntos por uma
# barreira; cada um grava o proprio resultado. Publica GANHOU e PERDEU.
_disputa() {
  local n=$1 antes=${2:-} i
  rm -f "$AREA"/resultado.* "$AREA"/aviso.* "$AREA/barreira"
  for ((i = 1; i <= n; i++)); do
    _filho_cru "$antes"'
      while [[ ! -e $AREA/barreira ]]; do sleep 0.01; done
      dbx_state_trava_adquirir "$IDENT" /dados /Remoto sync 0
      printf "%s" "$?" >"$AREA/resultado.$1"
      printf "%s" "$DBX_STATE_AVISO" >"$AREA/aviso.$1"
      # Quem venceu segura a trava ate todos terem tentado.
      [[ $(cat "$AREA/resultado.$1") == 0 ]] && sleep 2
      exit 0' "$i" >/dev/null 2>&1 &
  done
  sleep 0.3
  : >"$AREA/barreira"
  wait
  GANHOU=$(grep -lx 0 "$AREA"/resultado.* 2>/dev/null | wc -l)
  PERDEU=$(grep -lx "$CONFLITO" "$AREA"/resultado.* 2>/dev/null | wc -l)
}

teste_vinte_processos_disputam_e_exatamente_um_vence() {
  # TC-TRV-12 (RF-69(g)).
  _area
  _disputa 20
  assert_igual 1 "$GANHOU" 'exatamente um adquire'
  assert_igual 19 "$PERDEU" 'os demais recusam com conflito'
  assert_igual '' "$(find "$ESTADO" -name 'trava-*' -o -name '.trava.*' 2>/dev/null)" 'nada sobra ao fim'
}

teste_dois_e_vinte_retomadores_da_mesma_orfa_exatamente_um_vence() {
  # TC-TRV-13 e TC-TRV-28 (RF-69(m)).
  _area
  local n trava host morto
  trava=$(_caminho "$IDENT" /dados /Remoto)
  host=$(_host | head -1)
  for n in 2 20; do
    morto=$(_pid_morto)
    _plantar "$trava" "$(_linha "$morto" "$host" 1700000000 sync)"
    _disputa "$n"
    assert_igual 1 "$GANHOU" "$n retomadores: exatamente um adquire"
    assert_igual $((n - 1)) "$PERDEU" "$n retomadores: os demais recusam"
    assert_igual '' "$(find "$ESTADO" -name 'trava-*' 2>/dev/null)" "$n retomadores: nem trava nem .r sobram"
    # DIV-53: exatamente um aviso por orfa removida, venca quem vencer.
    local aviso avisos=0
    for aviso in "$AREA"/aviso.*; do
      [[ $(<"$aviso") == *removida* ]] && avisos=$((avisos + 1))
    done
    assert_igual 1 "$avisos" "$n retomadores: um aviso so"
  done
}

teste_div53_quem_apaga_a_orfa_avisa_mesmo_perdendo_o_ln() {
  # Uma aquisicao comum entra entre o `rm` da orfa e o `ln` do retomador (dobro
  # de `ln` que, no passo da retomada, publica antes uma trava viva alheia). O
  # retomador perde, sai com conflito, e ainda assim e ele quem avisa a remocao;
  # o aviso nao diz que ele ficou com a trava.
  _area
  local trava host morto vivo real
  trava=$(_caminho "$IDENT" /dados /Remoto)
  host=$(_host | head -1)
  morto=$(_pid_morto)
  sleep 30 &
  vivo=$!
  real=$(command -v ln)
  mkdir -p "$AREA/bin"
  {
    printf '#!%s\nreal=%q\nalheia=%q\n' "$BASH" "$real" "$(_linha "$vivo" "$host" 1700000500 sync)"
    printf '%s\n' 'destino=${*: -1}' \
      'if [[ $destino != *.r && -e $destino.r && ! -e $destino ]]; then printf "%s\n" "$alheia" >"$destino"; fi' \
      'exec "$real" "$@"'
  } >"$AREA/bin/ln"
  chmod +x "$AREA/bin/ln"
  _plantar "$trava" "$(_linha "$morto" "$host" 1700000000 sync)"
  _filho 'PATH="$AREA/bin:$PATH"
'"$ADQUIRIR"
  kill "$vivo" 2>/dev/null
  assert_contem "estado=$CONFLITO" "$FILHO_SAIDA" 'o retomador perdeu o ln para a aquisicao comum'
  assert_contem "pid $vivo" "$FILHO_SAIDA" 'e recusa nomeando a vencedora'
  assert_contem "trava orfa de pid $morto" "$FILHO_SAIDA" 'mas e ele quem avisa a remocao da orfa'
  assert_contem 'removida' "$FILHO_SAIDA" 'o aviso diz que removeu'
  assert_nao_contem 'retomada' "$FILHO_SAIDA" 'e nao afirma que ficou com a trava'
}

teste_leitor_concorrente_nunca_ve_trava_vazia_ou_parcial() {
  # TC-TRV-14: enquanto 10 processos adquirem e liberam em sequencia, um leitor
  # le o nome sem parar; toda leitura e ausente ou legivel.
  _area
  local trava
  trava=$(_caminho "$IDENT" /dados /Remoto)
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  _filho_cru '
    fim=$((SECONDS + 4)); ruins=0; vistas=0
    while ((SECONDS < fim)); do
      dbx_state_trava_ler "$1"; e=$?
      [[ $e -eq 1 ]] && ruins=$((ruins + 1))
      [[ $e -eq 0 ]] && vistas=$((vistas + 1))
    done
    printf "%s %s" "$ruins" "$vistas" >"$AREA/leitor"' "$trava" &
  local i ruins vistas
  for ((i = 0; i < 15; i++)); do
    _filho_cru 'dbx_state_trava_adquirir "$IDENT" /dados /Remoto sync 5 >/dev/null 2>&1; sleep 0.05' &
  done
  wait
  read -r ruins vistas <"$AREA/leitor"
  assert_igual 0 "$ruins" "nenhuma leitura de trava vazia ou parcial ($vistas legiveis)"
  [[ $vistas -gt 0 ]] || _harness_falhar 'o leitor nunca viu a trava: o caso nao mediu nada'
}

teste_ponto_r_orfa_nao_e_retomada_e_recusa() {
  # TC-TRV-29.
  _area
  local trava host morto
  trava=$(_caminho "$IDENT" /dados /Remoto)
  host=$(_host | head -1)
  morto=$(_pid_morto)
  _plantar "$trava" "$(_linha "$morto" "$host" 1700000000 sync)"
  _plantar "$trava.r" "$(_linha "$morto" "$host" 1700000001 sync)"
  cp "$trava.r" "$AREA/antes"
  _filho "$ADQUIRIR"
  assert_contem "estado=$CONFLITO" "$FILHO_SAIDA" 'recusa'
  assert_contem "$trava.r" "$FILHO_SAIDA" 'nomeia a .r e o remedio'
  cmp -s "$AREA/antes" "$trava.r" || _harness_falhar 'a .r orfa foi tocada'
  assert_arquivo_existe "$trava" 'a orfa continua la'
}

teste_identidade_que_muda_antes_da_releitura_solta_a_r_e_nao_apaga_a_nova() {
  # TC-TRV-30: entre a primeira leitura e a obtencao da .r, outro processo
  # retoma a orfa e passa a ter a trava viva. O retomador relê, ve outra
  # identidade, solta a .r e recusa a trava viva sem apaga-la.
  _area
  local trava host morto vivo
  trava=$(_caminho "$IDENT" /dados /Remoto)
  host=$(_host | head -1)
  morto=$(_pid_morto)
  sleep 30 &
  vivo=$!
  _plantar "$trava" "$(_linha "$morto" "$host" 1700000000 sync)"
  _filho '
    vivo=$1 host=$2 trava=$3
    eval "$(declare -f _dbx_state_trava_ler | sed "1s/.*/_ler_original ()/")"
    leituras=0
    _dbx_state_trava_ler() {
      leituras=$((leituras + 1))
      if [[ $leituras -eq 2 ]]; then
        printf "dbx-trava\t1\t%s\t%s\t1700000500\tsync\tfim\n" "$vivo" "$host" >"$trava.novo"
        mv -f "$trava.novo" "$trava"
      fi
      _ler_original "$@"
    }
    dbx_state_trava_adquirir "$IDENT" /dados /Remoto sync 0; printf "estado=%s\n" "$?"
    printf "motivo=%s\n" "$DBX_STATE_MOTIVO"' "$vivo" "$host" "$trava"
  kill "$vivo" 2>/dev/null
  assert_contem "estado=$CONFLITO" "$FILHO_SAIDA" 'a trava nova e viva: recusa'
  assert_contem "pid $vivo" "$FILHO_SAIDA" 'e a nova que e nomeada'
  assert_arquivo_existe "$trava" 'a trava nova nao foi apagada'
  assert_contem 1700000500 "$(cat "$trava")" 'e continua sendo a nova'
  assert_arquivo_ausente "$trava.r" 'a .r foi solta'
}

teste_sucesso_e_o_inode_e_nao_o_codigo_do_ln() {
  # TC-TRV-23 (RF-69(j), NFS): dobro de `ln` que cria e diz que falhou adquire;
  # dobro que diz que criou e nao criou nao adquire.
  _area
  local real
  real=$(command -v ln)
  mkdir -p "$AREA/bin1" "$AREA/bin2"
  printf '#!/usr/bin/env bash\n%q "$@"\nexit 1\n' "$real" >"$AREA/bin1/ln"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$AREA/bin2/ln"
  chmod +x "$AREA/bin1/ln" "$AREA/bin2/ln"
  _filho 'PATH="$AREA/bin1:$PATH"
'"$ADQUIRIR"
  assert_contem 'estado=0' "$FILHO_SAIDA" 'EEXIST com o elo criado: adquirida pelo -ef'
  _filho 'PATH="$AREA/bin2:$PATH"
'"$ADQUIRIR"
  # DIV-50: repeticoes esgotadas recusam com conflito, nunca seguem sem trava.
  assert_contem "estado=$CONFLITO" "$FILHO_SAIDA" 'zero sem elo: nao adquirida, conflito'
  assert_igual '' "$(find "$ESTADO" -name 'trava-*' -o -name '.trava.*' 2>/dev/null)" 'nada sobra'
}

# ---------------------------------------------------------------------------
# Liberacao, diretorio criado, kill -9 (RF-69(c)(e)(n); TC-TRV-18, TC-TRV-32)
# ---------------------------------------------------------------------------

teste_liberacao_nunca_apaga_trava_de_outro_dono() {
  _area
  _filho "$ADQUIRIR"'
    [[ -n $DBX_STATE_TRAVA ]] || exit 9
    printf "dbx-trava\t1\t4242\t%s\t1\tsync\tfim\n" "$DBX_STATE_HOST_ID" >"$DBX_STATE_TRAVA.x"
    mv -f "$DBX_STATE_TRAVA.x" "$DBX_STATE_TRAVA"
    printf "%s" "$DBX_STATE_TRAVA" >"$AREA/trava"
    dbx_state_trava_liberar
    exit 0'
  assert_arquivo_existe "$(cat "$AREA/trava")" 'a trava que ja nao e nossa fica'
}

teste_diretorio_criado_pela_trava_sai_vazio_e_o_preexistente_fica() {
  # RF-69(e), TC-TRV-18 na biblioteca: rmdir so do que a aquisicao criou.
  _area
  _filho "$ADQUIRIR"'exit 0'
  assert_contem 'estado=0' "$FILHO_SAIDA" 'adquirida'
  [[ -e $ESTADO ]] && _harness_falhar 'o diretorio criado pela trava sobrou'
  [[ -d $AREA/xdg ]] || _harness_falhar 'o pai do XDG nao e removido'
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  _filho "$ADQUIRIR"'exit 0'
  [[ -d $ESTADO ]] || _harness_falhar 'o diretorio preexistente foi removido'
  rmdir "$ESTADO"
  _filho "$ADQUIRIR"'printf x >"$ESTADO/memoria-outro"; exit 0'
  assert_arquivo_existe "$ESTADO/memoria-outro" 'diretorio nao vazio: o rmdir falha calado e correto'
}

teste_kill_9_entre_a_gravacao_e_a_liberacao_deixa_memoria_integra_e_trava_retomavel() {
  # TC-TRV-32 (RF-69(n)).
  _area
  _filho "$ADQUIRIR"'
    dbx_state_carregar conta /dados /Remoto
    dbx_state_registrar a.txt aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa x x
    dbx_state_gravar conta /dados /Remoto sim
    kill -9 $$'
  local -a memorias=("$ESTADO"/memoria-*)
  assert_igual 1 "${#memorias[@]}" 'a memoria foi gravada'
  _filho 'dbx_state_carregar conta /dados /Remoto; printf "descartada=%s visto=%s\n" "$DBX_STATE_DESCARTADA" "$DBX_STATE_VISTO"'
  assert_contem 'descartada=nao visto=sim' "$FILHO_SAIDA" 'a memoria esta integra'
  assert_igual 1 "$(find "$ESTADO" -name 'trava-*' | wc -l)" 'a trava ficou orfa'
  _filho "$ADQUIRIR"
  assert_contem 'estado=0' "$FILHO_SAIDA" 'e e retomada na execucao seguinte'
  assert_nao_contem 'aviso=$' "$FILHO_SAIDA" 'com aviso'
}

# ---------------------------------------------------------------------------
# Temporarios, poda e listagem (RF-69(o), RF-71; TC-TRV-33, TC-TRV-34)
# ---------------------------------------------------------------------------

teste_temporario_de_trava_antigo_e_varrido_e_o_novo_fica() {
  # TC-TRV-33.
  _area
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  local nome
  for nome in .trava.1.h.AAAAAAAA .memoria.1.AAAAAAAA .upload.1.AAAAAAAA; do
    printf x >"$ESTADO/$nome"
    touch -d '2 days ago' "$ESTADO/$nome"
  done
  printf x >"$ESTADO/.trava.2.h.BBBBBBBB"
  _filho 'dbx_state_carregar conta /d /r; dbx_state_gravar conta /d /r sim'
  assert_arquivo_ausente "$ESTADO/.trava.1.h.AAAAAAAA" '.trava.* antigo sai'
  assert_arquivo_ausente "$ESTADO/.memoria.1.AAAAAAAA" '.memoria.* antigo sai'
  assert_arquivo_ausente "$ESTADO/.upload.1.AAAAAAAA" '.upload.* antigo sai'
  assert_arquivo_existe "$ESTADO/.trava.2.h.BBBBBBBB" 'o recente fica'
}

teste_poda_e_limpeza_nunca_tocam_trava() {
  # TC-TRV-34 (parte de poda; o `unlink` esta no teste ponta a ponta).
  _area
  local trava host morto vivo i
  trava=$(_caminho "$IDENT" /dados /Remoto)
  host=$(_host | head -1)
  morto=$(_pid_morto)
  sleep 30 &
  vivo=$!
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  for ((i = 0; i <= 10000; i++)); do : >"$ESTADO/upload-velho$i"; done
  find "$ESTADO" -name 'upload-*' -exec touch -d '200 days ago' {} +
  _plantar "$trava" "$(_linha "$vivo" "$host" 1700000000 sync)"
  _plantar "$ESTADO/trava-0123456789abcdef0123456789abcdef" "$(_linha "$morto" "$host" 1700000000 sync)"
  touch -d '200 days ago' "$trava" "$ESTADO/trava-0123456789abcdef0123456789abcdef"
  printf 'abc' >"$AREA/arquivo"
  touch -d '1 hour ago' "$AREA/arquivo"
  _filho '
    dbx_hash_identidade "$AREA/arquivo"; i=$DBX_HASH_IDENTIDADE
    dbx_state_upload_gravar "$AREA/arquivo" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$i" "$i"
    printf "gravou=%s\n" "$?"'
  kill "$vivo" 2>/dev/null
  assert_contem 'gravou=0' "$FILHO_SAIDA" 'a gravacao rodou a poda'
  [[ $(find "$ESTADO" -name 'upload-velho*' | wc -l) -lt 10001 ]] || _harness_falhar 'a poda nao rodou'
  assert_arquivo_existe "$trava" 'a trava viva fica'
  assert_arquivo_existe "$ESTADO/trava-0123456789abcdef0123456789abcdef" 'a orfa fica'
}

teste_listagem_classifica_e_nao_cria_o_diretorio() {
  # RF-71 na biblioteca: viva, orfa, outro-host, ilegivel, .r orfa.
  _area
  _filho 'dbx_state_travas_listar; printf "n=%s\n" "${#DBX_STATE_TRAVAS_ARQUIVO[@]}"'
  assert_contem 'n=0' "$FILHO_SAIDA" 'sem diretorio, nenhuma'
  [[ -e $ESTADO ]] && _harness_falhar 'a listagem criou o diretorio'
  local host morto vivo
  host=$(_host | head -1)
  morto=$(_pid_morto)
  sleep 30 &
  vivo=$!
  _plantar "$ESTADO/trava-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$(_linha "$vivo" "$host" 1700000000 sync)"
  _plantar "$ESTADO/trava-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" "$(_linha "$morto" "$host" 1700000000 verificar)"
  _plantar "$ESTADO/trava-cccccccccccccccccccccccccccccccc" "$(_linha "$morto" outra:b:1 1700000000 sync)"
  _plantar "$ESTADO/trava-dddddddddddddddddddddddddddddddd" 'lixo'
  _plantar "$ESTADO/trava-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.r" "$(_linha "$morto" "$host" 1700000001 sync)"
  _filho 'dbx_state_travas_listar
    for i in "${!DBX_STATE_TRAVAS_ARQUIVO[@]}"; do
      printf "%s %s %s\n" "${DBX_STATE_TRAVAS_ARQUIVO[i]##*/}" "${DBX_STATE_TRAVAS_ESTADO[i]}" "${DBX_STATE_TRAVAS_PID[i]}"
    done'
  kill "$vivo" 2>/dev/null
  assert_contem "trava-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa viva $vivo" "$FILHO_SAIDA" 'viva'
  assert_contem "trava-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb orfa $morto" "$FILHO_SAIDA" 'orfa'
  assert_contem 'trava-cccccccccccccccccccccccccccccccc outro-host' "$FILHO_SAIDA" 'outro host'
  assert_contem 'trava-dddddddddddddddddddddddddddddddd ilegivel' "$FILHO_SAIDA" 'ilegivel'
  assert_contem 'trava-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.r orfa' "$FILHO_SAIDA" '.r orfa'
}

# ---------------------------------------------------------------------------
# Ciclo 2 do QA: QA-B2-01, QA-B2-03, DIV-50 (TC-TRV-38, TC-TRV-39)
# ---------------------------------------------------------------------------

teste_c2_qualquer_byte_depois_da_quebra_final_e_ilegivel() {
  # QA-B2-01: um unico nulo (ou outro byte) depois do `\n` final.
  _area
  local trava host morto sufixo
  trava=$(_caminho "$IDENT" /dados /Remoto)
  host=$(_host | head -1)
  morto=$(_pid_morto)
  for sufixo in '\000' '\000\000' 'x' '\000x'; do
    mkdir -p "$ESTADO"
    chmod 700 "$ESTADO"
    printf "dbx-trava\t1\t%s\t%s\t1700000000\tsync\tfim\n$sufixo" "$morto" "$host" >"$trava"
    chmod 600 "$trava"
    cp "$trava" "$AREA/antes"
    _filho "$ADQUIRIR"
    assert_contem "estado=$CONFLITO" "$FILHO_SAIDA" "[$sufixo] recusada"
    assert_contem 'ilegivel' "$FILHO_SAIDA" "[$sufixo] ilegivel, nao retomada"
    cmp -s "$AREA/antes" "$trava" || _harness_falhar "[$sufixo] a trava foi tocada"
  done
}

teste_c2_mesma_grafia_mesma_chave_em_c_e_em_c_utf8() {
  # QA-B2-03: a dobra de caixa da chave e so ASCII, independente da localidade.
  _area
  local remoto em_c em_utf8
  for remoto in /ACAO /AÇÃO /Documentos/RELATÓRIO /ação; do
    em_c=$(LC_ALL=C _caminho "$IDENT" /dados "$remoto")
    em_utf8=$(LC_ALL=C.UTF-8 _caminho "$IDENT" /dados "$remoto")
    assert_igual "$em_c" "$em_utf8" "[$remoto] mesma chave em C e em C.UTF-8"
  done
  assert_igual "$(LC_ALL=C.UTF-8 _caminho "$IDENT" /dados /Remoto)" \
    "$(LC_ALL=C _caminho "$IDENT" /dados /remoto)" 'ASCII continua sem caixa'
}

_somente_leitura() { # <dir> — pula como root, que escreve em qualquer lugar
  [[ $EUID -ne 0 ]] || pular 'como root todo diretorio e gravavel'
  chmod 500 "$1"
}

teste_c2_estado_sem_escrita_sem_trava_segue_e_com_viva_recusa() {
  # DIV-50, TC-TRV-39: diretorio sem escrita e sem trava: permissao (o comando
  # segue sem trava, com aviso); com trava viva e legivel: conflito.
  _area
  local trava host vivo
  mkdir -p "$ESTADO"
  _somente_leitura "$ESTADO"
  _filho "$ADQUIRIR"
  chmod 700 "$ESTADO"
  assert_contem "estado=$(dbx_errors_codigo_saida permissao)" "$FILHO_SAIDA" 'sem escrita e sem trava: permissao'
  trava=$(_caminho "$IDENT" /dados /Remoto)
  host=$(_host | head -1)
  sleep 30 &
  vivo=$!
  _plantar "$trava" "$(_linha "$vivo" "$host" 1700000000 sync)"
  _somente_leitura "$ESTADO"
  _filho "$ADQUIRIR"
  chmod 700 "$ESTADO"
  kill "$vivo" 2>/dev/null
  assert_contem "estado=$CONFLITO" "$FILHO_SAIDA" 'trava viva em diretorio sem escrita: conflito'
  assert_contem "pid $vivo" "$FILHO_SAIDA" 'nomeando quem a tem'
}

teste_c2_pai_sem_escrita_e_estado_alheio_sao_permissao() {
  # DIV-50, TC-TRV-38: nao da para criar o diretorio, ou ele e de outro dono.
  _area
  _somente_leitura "$AREA/xdg"
  _filho "$ADQUIRIR"
  chmod 700 "$AREA/xdg"
  assert_contem "estado=$(dbx_errors_codigo_saida permissao)" "$FILHO_SAIDA" 'pai sem escrita: permissao'
}

teste_c2_erro_de_uso_da_aquisicao_e_uso() {
  _area
  _filho 'dbx_state_trava_adquirir "$IDENT" /d /r sync abc; printf "estado=%s\n" "$?"'
  assert_contem "estado=$(dbx_errors_codigo_saida uso_invalido)" "$FILHO_SAIDA" 'espera invalida: uso'
}

harness_executar "$@"
