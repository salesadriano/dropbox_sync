#!/usr/bin/env bash
# Suite independente do QA: quem espera pela trava de raiz nao confunde o
# diretorio de estado que o detentor removeu ao soltar com "sem escrita"
# (DIV-396; RF-132, DIV-250). Detentor e espera sao processos `bash` reais; a
# intercalacao e deterministica, sem carga nem espera longa: um `mktemp` duble
# no PATH da espera, chamado dentro do diretorio de estado a cada sondagem da
# trava, solta o detentor real (ou apaga o diretorio) no ponto exato da corrida,
# entre a conferencia do diretorio e a gravacao do temporario da trava.
#
# shellcheck disable=SC2016
# Justificativa: os roteiros dos processos filhos chegam sem expansao.
#
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

Q_MKTEMP=$(command -v mktemp)
readonly Q_MKTEMP

# _q_cen — area do caso (XDG, TMPDIR, raiz local) e o mktemp duble; ESTADO ainda nao existe.
_q_cen() {
  A=$(mktemp -d "$DBX_TESTES_TMP/qa-raizsumida.XXXXXX")
  mkdir -p "$A/xdg" "$A/tmp" "$A/bin" "$A/raiz"
  ESTADO="$A/xdg/dbx"
  : >"$A/mk.log"
  {
    printf '#!%s\nreal=%q\nlog=%q\n' "$BASH" "$Q_MKTEMP" "$A/mk.log"
    cat <<'FIM'
case "$*" in */.trava.*) ;; *) exec "$real" "$@" ;; esac
[[ -n ${QA_MODO:-} ]] || exec "$real" "$@"
printf 'x\n' >>"$log"
mapfile -t linhas <"$log"
case $QA_MODO in
  liberar)
    if [[ ${#linhas[@]} -eq 2 ]]; then
      : >"$QA_AREA/solta"
      for ((i = 0; i < 300; i++)); do
        if [[ $QA_ATE == dir ]]; then
          [[ -e $QA_ESTADO ]] || break
        else
          compgen -G "$QA_ESTADO/trava-*" >/dev/null || break
        fi
        command sleep 0.05
      done
    fi
    ;;
  sumir) rm -rf -- "$QA_ESTADO" ;;
esac
exec "$real" "$@"
FIM
  } >"$A/bin/mktemp"
  chmod +x "$A/bin/mktemp"
}

# _q_segurar — detentor real da trava de raiz ate existir "$A/solta".
_q_segurar() {
  export A
  XDG_STATE_HOME="$A/xdg" TMPDIR="$A/tmp" RAIZ="$DBX_HARNESS_RAIZ" bash -c '
    . "$RAIZ/lib/errors.sh"; . "$RAIZ/lib/json.sh"; . "$RAIZ/lib/config.sh"; . "$RAIZ/lib/state.sh"
    dbx_state_trava_raiz_adquirir "$A/raiz" 0 || exit 9
    : >"$A/segurando"
    while [[ ! -e $A/solta ]]; do command sleep 0.05; done
  ' </dev/null >/dev/null 2>&1 &
  Q_DETENTOR=$!
  local i
  for ((i = 0; i < 200; i++)); do
    [[ -e $A/segurando ]] && return 0
    command sleep 0.05
  done
  _harness_falhar 'o detentor nao adquiriu a trava de raiz'
}

_q_soltar() {
  : >"$A/solta"
  wait "$Q_DETENTOR" 2>/dev/null
  Q_DETENTOR_ESTADO=$?
}

# _q_espera <modo> <ate> <roteiro> — roda a espera; o roteiro escreve em "$A/resultado".
_q_espera() {
  local modo=$1 ate=$2 roteiro=$3
  export A ESTADO
  PATH="$A/bin:$PATH" QA_MODO=$modo QA_ATE=$ate QA_AREA=$A QA_ESTADO=$ESTADO \
    XDG_STATE_HOME="$A/xdg" TMPDIR="$A/tmp" RAIZ="$DBX_HARNESS_RAIZ" \
    timeout 90 bash -c '
    . "$RAIZ/lib/errors.sh"; . "$RAIZ/lib/json.sh"; . "$RAIZ/lib/config.sh"; . "$RAIZ/lib/state.sh"
'"$roteiro" </dev/null >"$A/out" 2>&1
  Q_ESTADO=$?
}

_q_chamadas() { _harness_contar x "$A/mk.log"; }

teste_qa_espera_conclui_quando_o_detentor_apaga_o_diretorio_na_janela_da_sondagem() {
  _q_cen
  _q_segurar
  _q_espera liberar dir '
    dbx_state_trava_raiz_adquirir "$A/raiz" 10
    estado=$?
    [[ -f ${DBX_STATE_TRAVA_RAIZ:-} ]] && arquivo=sim || arquivo=nao
    printf "%s %s" "$estado" "$arquivo" >"$A/resultado"
  '
  _q_soltar
  assert_igual 0 "$Q_ESTADO" "a espera terminou: $(<"$A/out")"
  assert_igual 0 "$Q_DETENTOR_ESTADO" 'o detentor terminou limpo'
  assert_igual '0 sim' "$(<"$A/resultado")" 'adquirida, com o arquivo da trava presente'
  assert_igual 3 "$(_q_chamadas)" 'sondou ocupada, sondou na janela da corrida e repetiu uma vez'
}

teste_qa_quem_recriou_o_diretorio_o_remove_ao_soltar_e_nao_deixa_lixo() {
  _q_cen
  _q_segurar
  _q_espera liberar dir '
    dbx_state_trava_raiz_adquirir "$A/raiz" 10
    estado=$?
    printf "%s" "$estado" >"$A/resultado"
    dbx_state_trava_raiz_liberar
    [[ -e $ESTADO ]] && printf sim >"$A/depois" || printf nao >"$A/depois"
  '
  _q_soltar
  assert_igual 0 "$(<"$A/resultado")" "adquiriu apos a recriacao: $(<"$A/out")"
  assert_igual nao "$(<"$A/depois")" 'o diretorio que a espera recriou sai ao soltar'
  assert_arquivo_ausente "$ESTADO" 'sem lixo no estado'
}

teste_qa_diretorio_que_a_espera_nao_criou_permanece_ao_soltar() {
  _q_cen
  mkdir -m 700 "$ESTADO"
  printf 'meu\n' >"$ESTADO/outro.txt"
  _q_segurar
  _q_espera liberar trava '
    dbx_state_trava_raiz_adquirir "$A/raiz" 10
    printf "%s" "$?" >"$A/resultado"
    dbx_state_trava_raiz_liberar
  '
  _q_soltar
  assert_igual 0 "$(<"$A/resultado")" "adquiriu: $(<"$A/out")"
  assert_arquivo_existe "$ESTADO/outro.txt" 'arquivo alheio intacto'
  assert_igual 1 "$(find "$ESTADO" -mindepth 1 | wc -l | tr -d ' ')" 'so o arquivo alheio resta no estado'
}

teste_qa_diretorio_existente_sem_escrita_continua_permissao() {
  _q_cen
  mkdir -m 500 "$ESTADO"
  [[ ! -w $ESTADO ]] || _harness_falhar 'ambiente com escrita apesar de modo 500 (executando como root?)'
  _q_espera nenhum x '
    dbx_state_trava_raiz_adquirir "$A/raiz" 0
    printf "%s" "$?" >"$A/resultado"
    printf "%s" "${DBX_STATE_MOTIVO:-}" >"$A/motivo"
  '
  chmod 700 "$ESTADO"
  assert_igual 6 "$(<"$A/resultado")" "permissao: $(<"$A/out")"
  assert_contem "diretorio de estado sem escrita: $ESTADO" "$(<"$A/motivo")" 'mensagem da guarda'
  assert_arquivo_existe "$ESTADO" 'o diretorio existente nao e apagado'
}

teste_qa_diretorio_de_outro_dono_continua_permissao_e_intacto() {
  _q_cen
  mkdir -m 700 "$ESTADO"
  # Sem root nao ha como criar diretorio alheio: o dono e decidido por este unico predicado.
  _q_espera nenhum x '
    _dbx_state_diretorio_confiavel() { return 1; }
    dbx_state_trava_raiz_adquirir "$A/raiz" 0
    printf "%s" "$?" >"$A/resultado"
    printf "%s" "${DBX_STATE_MOTIVO:-}" >"$A/motivo"
  '
  assert_igual 6 "$(<"$A/resultado")" "permissao: $(<"$A/out")"
  assert_contem 'pertence a outro usuario' "$(<"$A/motivo")" 'mensagem do dono'
  assert_nao_contem 'sem escrita' "$(<"$A/motivo")" 'nao e confundido com falta de escrita'
  assert_arquivo_existe "$ESTADO" 'o diretorio alheio nao e apagado'
}

teste_qa_diretorio_que_some_a_cada_sondagem_para_no_limite_de_repeticoes() {
  _q_cen
  _q_espera sumir x '
    dbx_state_trava_raiz_adquirir "$A/raiz" 0
    printf "%s" "$?" >"$A/resultado"
    printf "%s" "${DBX_STATE_MOTIVO:-}" >"$A/motivo"
  '
  [[ $Q_ESTADO -ne 124 ]] || _harness_falhar 'laco sem fim: timeout'
  assert_igual 6 "$(<"$A/resultado")" "cai em permissao ao esgotar: $(<"$A/out")"
  assert_contem 'sem escrita' "$(<"$A/motivo")" 'a mensagem de permissao'
  assert_igual 51 "$(_q_chamadas)" 'uma sondagem mais 50 repeticoes, nem uma a mais'
  assert_arquivo_ausente "$ESTADO" 'o diretorio recriado e desfeito ao desistir'
}

harness_executar "$@"
