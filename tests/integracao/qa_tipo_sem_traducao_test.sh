#!/usr/bin/env bash
# Suite independente do QA: o tipo de arquivo lido por `stat` nao depende da
# localidade (DIV-395; RF-167; trava de RF-69/RF-70 e cursor de RF-110).
# Pelo executavel real `bin/dbx`, com um `stat` duble que TRADUZ `%F` fora da
# localidade C ("regular file" -> "arquivo comum", como o coreutils em pt_BR) e
# um duble de `curl`. `DBX_QA_EXEC` aponta outro `bin/dbx` (a base, para provar
# o vermelho). Consumidores cobertos: trava (orfa, viva, diagnostico, ilegivel
# genuina) e o registro do cursor de listagem (`_dbx_state_cursor_abrir`).
#
# shellcheck disable=SC2016
# Justificativa: os roteiros dos dubles chegam sem expansao.
#
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

Q_DBX=${DBX_QA_EXEC:-$DBX_HARNESS_RAIZ/bin/dbx}
readonly Q_DBX
Q_DORMIR=$(command -v sleep)
Q_STAT=$(command -v stat)
readonly Q_DORMIR Q_STAT

# _q_cen — credencial, curl duble, stat duble e arvore local; base em `B`.
_q_cen() {
  B=$(mktemp -d "$DBX_TESTES_TMP/qa-tiposem.XXXXXX")
  mkdir -p "$B/config/dbx" "$B/bin" "$B/local" "$B/tmp" "$B/estado/dbx"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$B/config/dbx/credencial.json"
  chmod 700 "$B/config/dbx"
  chmod 600 "$B/config/dbx/credencial.json"
  : >"$B/chamadas"
  {
    printf '#!%s\nbase=%q\n' "$BASH" "$B"
    cat <<'FIM'
cat >/dev/null
saida='' escrever='' anterior='' url=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.T","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *list_folder/get_latest_cursor*) corpo='{"cursor":"C1"}' ;;
  *list_folder*) corpo='{"entries":[{".tag":"folder","name":"r","id":"id:raiz","path_lower":"/r","path_display":"/r"}],"cursor":"C1","has_more":false}' ;;
  *) corpo='{"name":"x","rev":"1","size":1}' ;;
esac
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '200'
exit 0
FIM
  } >"$B/bin/curl"
  {
    printf '#!%s\nreal=%q\n' "$BASH" "$Q_STAT"
    cat <<'FIM'
loc=${LC_ALL:-${LC_MESSAGES:-${LANG:-C}}}
case $loc in C | C.* | POSIX) exec "$real" "$@" ;; esac
saida=$("$real" "$@") || exit $?
saida=${saida//regular empty file/arquivo comum vazio}
saida=${saida//regular file/arquivo comum}
saida=${saida//directory/diretorio}
printf '%s\n' "$saida"
FIM
  } >"$B/bin/stat"
  chmod +x "$B/bin/curl" "$B/bin/stat"
}

# _q_rodar <localidade> <exportar_lc_all:0|1> <argumentos...> — saida em Q_*.
_q_rodar() {
  local loc=$1 lcall=$2 ambiente
  shift 2
  ambiente=(env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/config"
    XDG_STATE_HOME="$B/estado" TMPDIR="$B/tmp" LANG="$loc")
  [[ $lcall == 1 ]] && ambiente+=(LC_ALL="$loc")
  : >"$B/chamadas"
  setsid -w "${ambiente[@]}" timeout 60 bash "$Q_DBX" "$@" </dev/null >"$B/out" 2>"$B/err"
  Q_ESTADO=$?
  Q_SAIDA=$(<"$B/out")
  Q_ERRO=$(<"$B/err")
}

_q_trava() { # caminho da trava do par (local, /r), pela definicao do produto
  XDG_CONFIG_HOME="$B/config" XDG_STATE_HOME="$B/estado" TMPDIR="$B/tmp" bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/json.sh"; . "$1/lib/path.sh"; . "$1/lib/config.sh"; . "$1/lib/state.sh"
    dbx_config_carregar >/dev/null 2>&1; dbx_config_identidade
    dbx_path_local_canonico "$2"
    dbx_state_trava_caminho "$DBX_CONFIG_IDENTIDADE" "$DBX_PATH_RESULTADO" /r
    printf "%s" "$DBX_STATE_RESULTADO"' _ "$DBX_HARNESS_RAIZ" "$B/local"
}

_q_host() {
  bash -c '. "$1/lib/errors.sh"; . "$1/lib/state.sh"; dbx_state_host_id; printf "%s" "$DBX_STATE_HOST_ID"' _ "$DBX_HARNESS_RAIZ"
}

# _q_plantar <conteudo> — grava a trava do par; publica Q_TRAVA.
_q_plantar() {
  Q_TRAVA=$(_q_trava)
  [[ $Q_TRAVA == "$DBX_TESTES_TMP"/* ]] || _harness_falhar 'trava fora da area do caso' "[$Q_TRAVA]"
  mkdir -p "${Q_TRAVA%/*}"
  chmod 700 "${Q_TRAVA%/*}"
  printf '%s\n' "$1" >"$Q_TRAVA"
  chmod 600 "$Q_TRAVA"
}

_q_linha() { printf 'dbx-trava\t1\t%s\t%s\t1700000000\tsync\tfim\n' "$1" "$(_q_host)"; }

_q_pid_morto() {
  local pid
  "$Q_DORMIR" 0 &
  pid=$!
  wait "$pid"
  printf '%s' "$pid"
}

# Precondicao de todo caso: o duble traduz de fato nesta localidade.
_q_duble_traduz() {
  local tipo
  tipo=$(env -i PATH="$B/bin:$PATH" LANG="$1" stat -c %F -- "$B/local")
  assert_igual diretorio "$tipo" 'o duble de stat traduz fora de C'
}

teste_qa_trava_orfa_e_retomada_em_pt_br_com_stat_traduzido() {
  local morto
  _q_cen
  _q_duble_traduz pt_BR.UTF-8
  morto=$(_q_pid_morto)
  _q_plantar "$(_q_linha "$morto")"
  _q_rodar pt_BR.UTF-8 0 sync --enviar --origem "$B/local" --destino /r
  assert_igual 0 "$Q_ESTADO" "orfa retomada: $Q_ERRO"
  assert_contem "trava orfa de pid $morto removida" "$Q_ERRO" 'aviso da orfa'
  assert_nao_contem 'ilegivel' "$Q_ERRO$Q_SAIDA" 'orfa nao e ilegivel'
}

teste_qa_trava_viva_e_dita_ocupada_e_nao_ilegivel_em_pt_br() {
  local vivo
  _q_cen
  _q_duble_traduz pt_BR.UTF-8
  "$Q_DORMIR" 60 &
  vivo=$!
  _q_plantar "$(_q_linha "$vivo")"
  _q_rodar pt_BR.UTF-8 0 sync --enviar --origem "$B/local" --destino /r
  kill "$vivo" 2>/dev/null
  assert_igual 7 "$Q_ESTADO" "conflito: $Q_ERRO"
  assert_contem 'trava ocupada' "$Q_ERRO" 'ocupada'
  assert_contem "pid $vivo" "$Q_ERRO" 'nomeia o pid vivo'
  assert_nao_contem 'ilegivel' "$Q_ERRO" 'nao e ilegivel'
  assert_nao_contem 'rm ' "$Q_ERRO" 'sem pedir remocao manual'
  [[ -f $Q_TRAVA ]] || _harness_falhar 'a trava viva foi apagada'
  assert_igual 0 "$(_harness_contar . "$B/chamadas")" 'nenhuma chamada a API com a trava ocupada'
}

teste_qa_lc_all_exportado_em_pt_br_nao_muda_o_veredito_da_trava() {
  local vivo morto
  _q_cen
  _q_duble_traduz pt_BR.UTF-8
  "$Q_DORMIR" 60 &
  vivo=$!
  _q_plantar "$(_q_linha "$vivo")"
  _q_rodar pt_BR.UTF-8 1 sync --enviar --origem "$B/local" --destino /r
  kill "$vivo" 2>/dev/null
  assert_igual 7 "$Q_ESTADO" "viva com LC_ALL exportado: $Q_ERRO"
  assert_contem 'trava ocupada' "$Q_ERRO" 'ocupada'
  assert_nao_contem 'ilegivel' "$Q_ERRO" 'nao e ilegivel'
  morto=$(_q_pid_morto)
  _q_plantar "$(_q_linha "$morto")"
  _q_rodar pt_BR.UTF-8 1 sync --enviar --origem "$B/local" --destino /r
  assert_igual 0 "$Q_ESTADO" "orfa com LC_ALL exportado: $Q_ERRO"
  assert_contem "trava orfa de pid $morto removida" "$Q_ERRO" 'orfa retomada'
}

teste_qa_diagnostico_reporta_trava_viva_como_ok_em_pt_br() {
  local vivo
  _q_cen
  _q_duble_traduz pt_BR.UTF-8
  "$Q_DORMIR" 60 &
  vivo=$!
  _q_plantar "$(_q_linha "$vivo")"
  _q_rodar pt_BR.UTF-8 0 diagnostico
  kill "$vivo" 2>/dev/null
  assert_contem "trava=ok: viva: o sync pid $vivo" "$Q_SAIDA" 'viva'
  assert_nao_contem 'trava=aviso: ilegivel' "$Q_SAIDA" 'nao e ilegivel'
}

teste_qa_cursor_gravado_continua_incremental_em_pt_br() {
  _q_cen
  _q_duble_traduz pt_BR.UTF-8
  _q_rodar pt_BR.UTF-8 0 sync --receber --origem /r --destino "$B/local"
  assert_igual 0 "$Q_ESTADO" "primeira execucao: $Q_ERRO"
  [[ -n $(find "$B/estado/dbx" -name 'cursor-*' 2>/dev/null) ]] || _harness_falhar 'sem registro de cursor apos a primeira execucao'
  _q_rodar pt_BR.UTF-8 0 sync --receber --origem /r --destino "$B/local"
  assert_igual 0 "$Q_ESTADO" "segunda execucao: $Q_ERRO"
  assert_contem 'list_folder/continue' "$(<"$B/chamadas")" 'o cursor e lido e continuado'
  assert_nao_contem 'descartado' "$Q_SAIDA$Q_ERRO" 'registro do cursor nao e descartado'
}

teste_qa_trava_realmente_ilegivel_continua_ilegivel_em_pt_br() {
  _q_cen
  _q_duble_traduz pt_BR.UTF-8
  _q_plantar 'lixo sem formato'
  _q_rodar pt_BR.UTF-8 0 sync --enviar --origem "$B/local" --destino /r
  assert_igual 7 "$Q_ESTADO" "conflito: $Q_ERRO"
  assert_contem 'trava ilegivel' "$Q_ERRO" 'a correcao nao legitima lixo'
  [[ -f $Q_TRAVA ]] || _harness_falhar 'trava ilegivel foi apagada'
}

harness_executar "$@"
