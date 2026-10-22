#!/usr/bin/env bash
# Trava por raiz local canonica em lib/state.sh (F-18, fase 8; RF-132, DIV-250;
# TC-PFT-01..03, 06..08). Cada disputante e um processo `bash` proprio: a
# exclusao so se prova entre processos.
#
# O filtro `state` casa este arquivo (substring): todo diff em lib/state.sh o
# seleciona.
#
# shellcheck disable=SC2016
# Justificativa: os roteiros dos processos filhos chegam sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly CONFLITO=7

_area() {
  AREA=$(mktemp -d "$DBX_TESTES_TMP/raiz.XXXXXX")
  mkdir -p "$AREA/xdg" "$AREA/tmp" "$AREA/dados"
  ESTADO="$AREA/xdg/dbx"
}

_filho() {
  local roteiro=$1 xdg=$AREA/xdg tmp=$AREA/tmp
  shift
  FILHO_SAIDA=$(XDG_STATE_HOME="$xdg" TMPDIR="$tmp" AREA="$AREA" ESTADO="$ESTADO" \
    RAIZ="$DBX_HARNESS_RAIZ" bash -c '
    . "$RAIZ/lib/errors.sh"; . "$RAIZ/lib/json.sh"; . "$RAIZ/lib/config.sh"; . "$RAIZ/lib/state.sh"
'"$roteiro" _ "$@" </dev/null 2>&1)
  FILHO_ESTADO=$?
}

# _segurar <raiz> — processo que detem a trava de raiz ate existir "$AREA/solta".
_segurar() {
  local xdg=$AREA/xdg tmp=$AREA/tmp
  XDG_STATE_HOME="$xdg" TMPDIR="$tmp" AREA="$AREA" RAIZ="$DBX_HARNESS_RAIZ" bash -c '
    . "$RAIZ/lib/errors.sh"; . "$RAIZ/lib/json.sh"; . "$RAIZ/lib/config.sh"; . "$RAIZ/lib/state.sh"
    dbx_state_trava_raiz_adquirir "$1" 0 || exit 9
    : >"$AREA/segurando"
    while [[ ! -e $AREA/solta ]]; do sleep 0.1; done
  ' _ "$1" </dev/null >/dev/null 2>&1 &
  SEGURANDO=$!
  local i
  for ((i = 0; i < 100; i++)); do
    [[ -e $AREA/segurando ]] && return 0
    sleep 0.1
  done
  _harness_falhar 'o processo nao adquiriu a trava de raiz'
}

_soltar() {
  : >"$AREA/solta"
  wait "$SEGURANDO" 2>/dev/null
}

teste_pft01_segunda_aquisicao_da_mesma_raiz_recusa_com_conflito() {
  _area
  _segurar "$AREA/dados"
  _filho 'dbx_state_trava_raiz_adquirir "$1" 0; printf "%s\n%s" "$?" "$DBX_STATE_MOTIVO"' "$AREA/dados"
  _soltar
  assert_contem "$CONFLITO" "${FILHO_SAIDA%%$'\n'*}" 'conflito (7)'
  assert_contem 'raiz local' "$FILHO_SAIDA" 'a mensagem nomeia a raiz'
  assert_contem 'pid' "$FILHO_SAIDA" 'e o detentor'
}

teste_pft02_grafias_diferentes_da_mesma_pasta_resolvem_a_mesma_trava() {
  _area
  ln -s "$AREA/dados" "$AREA/atalho"
  mkdir -p "$AREA/dados/sub"
  local a b c
  a=$(_filho 'dbx_state_trava_raiz_caminho "$1" && printf "%s" "$DBX_STATE_RESULTADO"' "$AREA/dados"; printf '%s' "$FILHO_SAIDA")
  _filho 'dbx_state_trava_raiz_caminho "$1" && printf "%s" "$DBX_STATE_RESULTADO"' "$AREA/dados"
  a=$FILHO_SAIDA
  _filho 'dbx_state_trava_raiz_caminho "$1" && printf "%s" "$DBX_STATE_RESULTADO"' "$AREA/atalho"
  b=$FILHO_SAIDA
  _filho 'dbx_state_trava_raiz_caminho "$1" && printf "%s" "$DBX_STATE_RESULTADO"' "$AREA/dados/sub/.."
  c=$FILHO_SAIDA
  [[ $a == "$ESTADO"/trava-* ]] || _harness_falhar "nome da trava: $a"
  assert_igual "$a" "$b" 'ligacao simbolica: mesma trava'
  assert_igual "$a" "$c" 'caminho com ..: mesma trava'
}

teste_pft_raizes_diferentes_tem_travas_diferentes_e_aninhadas_nao_sao_cobertas() {
  _area
  mkdir -p "$AREA/dados/sub"
  local a b
  _filho 'dbx_state_trava_raiz_caminho "$1" && printf "%s" "$DBX_STATE_RESULTADO"' "$AREA/dados"
  a=$FILHO_SAIDA
  _filho 'dbx_state_trava_raiz_caminho "$1" && printf "%s" "$DBX_STATE_RESULTADO"' "$AREA/dados/sub"
  b=$FILHO_SAIDA
  assert_diferente "$a" "$b" 'inodes distintos: nao cobertas (risco declarado)'
  _segurar "$AREA/dados"
  _filho 'dbx_state_trava_raiz_adquirir "$1" 0; printf "%s" "$?"' "$AREA/dados/sub"
  _soltar
  assert_igual 0 "$FILHO_SAIDA" 'a aninhada adquire'
}

teste_pft03_espera_cobre_a_trava_e_conclui_quando_a_primeira_termina() {
  _area
  _segurar "$AREA/dados"
  ( sleep 2; : >"$AREA/solta" ) &
  _filho 'dbx_state_trava_raiz_adquirir "$1" 6; printf "%s" "$?"' "$AREA/dados"
  wait "$SEGURANDO" 2>/dev/null
  assert_igual 0 "$FILHO_SAIDA" 'esperou e adquiriu'
}

teste_pft06_trava_orfa_de_processo_morto_e_retomada() {
  _area
  local host chave
  _filho 'dbx_state_host_id; printf "%s" "$DBX_STATE_HOST_ID"'
  host=$FILHO_SAIDA
  _filho 'dbx_state_trava_raiz_caminho "$1" && printf "%s" "$DBX_STATE_RESULTADO"' "$AREA/dados"
  chave=$FILHO_SAIDA
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  printf 'dbx-trava\t1\t999999\t%s\t1700000000\tsync\tfim\n' "$host" >"$chave"
  _filho 'dbx_state_trava_raiz_adquirir "$1" 0; printf "%s|%s" "$?" "$DBX_STATE_AVISO"' "$AREA/dados"
  assert_contem '0|trava orfa' "$FILHO_SAIDA" 'retomada com aviso'
}

teste_pft07_a_trava_nao_carrega_credencial_conta_nem_perfil() {
  _area
  _filho 'dbx_state_trava_raiz_adquirir "$1" 0 || exit 1; for f in "$ESTADO"/trava-*; do printf "%s\n" "${f##*/}"; cat "$f"; done' "$AREA/dados"
  [[ $FILHO_SAIDA == trava-* ]] || _harness_falhar "nome comeca por trava-: $FILHO_SAIDA"
  assert_nao_contem 'cred-' "$FILHO_SAIDA" 'sem identidade'
  assert_nao_contem 'dbid' "$FILHO_SAIDA" 'sem conta'
  assert_nao_contem 'perfil' "$FILHO_SAIDA" 'sem perfil'
  assert_contem 'dbx-trava' "$FILHO_SAIDA" 'mesmo formato de registro'
}

teste_pft08_par_depois_raiz_libera_na_ordem_inversa_e_falha_da_segunda_libera_a_primeira() {
  _area
  _segurar "$AREA/dados"
  _filho '
    dbx_state_trava_adquirir ident-x "$1" /rem sync 0 || exit 11
    dbx_state_trava_raiz_adquirir "$1" 0
    estado=$?
    [[ $estado -eq 7 ]] || exit 12
    # A falha da raiz nao pode deixar a do par presa por este processo.
    dbx_state_trava_liberar
    for f in "$ESTADO"/trava-*; do printf "%s\n" "${f##*/}"; done
  ' "$AREA/dados"
  assert_igual 0 "$FILHO_ESTADO" "roteiro: $FILHO_SAIDA"
  _soltar
}

teste_pft_liberacao_so_apaga_a_propria_e_limpa_o_diretorio_criado() {
  _area
  _filho '
    dbx_state_trava_raiz_adquirir "$1" 0 || exit 1
    dbx_state_trava_raiz_liberar
    [[ -z $(ls -A "$ESTADO" 2>/dev/null) ]] || exit 2
    [[ ! -e $ESTADO ]] || exit 3
  ' "$AREA/dados"
  assert_igual 0 "$FILHO_ESTADO" "liberacao: $FILHO_SAIDA"
}

teste_pft_raiz_inexistente_nao_tem_identidade() {
  _area
  _filho 'dbx_state_trava_raiz_adquirir "$1" 0; printf "%s" "$?"' "$AREA/nao-existe"
  assert_diferente 0 "$FILHO_SAIDA" 'sem inode nao ha trava'
}

harness_executar "$@"
