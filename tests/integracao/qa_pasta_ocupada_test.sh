#!/usr/bin/env bash
# Suite independente do QA: DIV-394 (producao, 2.3.2). Na Dropbox existe um
# ARQUIVO com o nome de uma subpasta local; a listagem dela devolve HTTP 409
# `path/not_folder`. Em subdiretorio do ciclo isso e pasta remota vazia (com
# aviso) e o arquivo homonimo e orfao do espelhamento (RF-47); na raiz do
# destino continua falha da enumeracao, nomeando o caminho.
#
# Duplo de `curl` proprio por regras de endpoint (padrao das demais qa_*), pelo
# executavel real. `DBX_QA_EXEC` aponta outro `bin/dbx` (prova do vermelho
# contra a base).
#
# shellcheck disable=SC2016
# Justificativa: o roteiro do duplo de rede chega sem expansao.
#
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

Q_DBX=${DBX_QA_EXEC:-$DBX_HARNESS_RAIZ/bin/dbx}
readonly Q_DBX
Q_BASH=$(command -v bash)
readonly Q_BASH
readonly Q_NAO_PASTA='{"error_summary":"path/not_folder/..","error":{".tag":"path","path":{".tag":"not_folder"}}}'

# _p_cen — area, credencial e duplo de rede com regras por endpoint.
_p_cen() {
  B=$(mktemp -d "$DBX_TESTES_TMP/qa-ocupada.XXXXXX")
  mkdir -p "$B/cfg/dbx" "$B/bin" "$B/resp" "$B/tmp" "$B/estado" "$B/l"
  chmod 700 "$B/cfg/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"QAOCUPsegredo","refresh_token":"QAOCUPrefresh","raiz_remota":"/"}' \
    >"$B/cfg/dbx/credencial.json"
  chmod 600 "$B/cfg/dbx/credencial.json"
  : >"$B/regras"
  : >"$B/chamadas"
  P_N=0
  {
    printf '#!%s\nQA=%q\nLOTE=%q\n' "$Q_BASH" "$B" "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
    cat <<'FIM'
export LC_ALL=C
config=''
IFS= read -r -d '' config || :
o=''; w=''; ant=''; url=''; dados=''
for a in "$@"; do
  case $ant in -o) o=$a ;; -w) w=$a ;; --data-binary) dados=${a#@} ;; esac
  case $a in http*) url=$a ;; esac
  ant=$a
done
pedido=''
[[ -n $dados && -r $dados ]] && IFS= read -r -d '' pedido <"$dados"
if [[ -z $dados && $config == *Dropbox-API-Arg:* ]]; then
  pedido=${config#*Dropbox-API-Arg: }
  pedido=${pedido%%$'\n'*}
fi
ep=${url#https://api.dropboxapi.com/2/}
ep=${ep#https://content.dropboxapi.com/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
printf '%s\t%s\n' "$ep" "$pedido" >>"$QA/chamadas"
cod=400 corpo='{"error_summary":"sem_regra/"}' achou=nao
while IFS=$'\t' read -r rep rfi rco rar; do
  [[ -n $rep ]] || continue
  # shellcheck disable=SC2053
  [[ $ep == $rep && $pedido == $rfi ]] || continue
  achou=sim cod=$rco corpo=''
  [[ -r $QA/resp/$rar ]] && IFS= read -r -d '' corpo <"$QA/resp/$rar"
  break
done <"$QA/regras"
if [[ $achou == nao ]]; then
  case $ep in
    oauth2/token) cod=200 corpo='{"access_token":"sl.QAOCUPtoken","token_type":"bearer","expires_in":14400}' ;;
    users/get_current_account) cod=200 corpo='{"account_id":"dbid:QAOCUP"}' ;;
    files/get_metadata) cod=409 corpo='{"error_summary":"path/not_found/..","error":{".tag":"path","path":{".tag":"not_found"}}}' ;;
    files/upload) cod=200 corpo='{"name":"x","rev":"0123456789a"}' ;;
    auth/token/revoke) cod=200 corpo='null' ;;
  esac
fi
base=$QA
LOTE_ECOA_V2=sim
. "$LOTE"
if lote_responder "$url" "$dados"; then cod=$codigo; fi
[[ -n $o ]] && printf "%s" "$corpo" >"$o"
[[ -n $w ]] && printf '%s' "$cod"
exit 0
FIM
  } >"$B/bin/curl"
  printf '#!%s\nexit 0\n' "$Q_BASH" >"$B/bin/sleep"
  chmod +x "$B/bin/curl" "$B/bin/sleep"
}

_p_regra() { # <endpoint> <filtro_do_corpo> <codigo> <corpo>
  P_N=$((P_N + 1))
  printf '%s' "$4" >"$B/resp/r$P_N"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "r$P_N" >>"$B/regras"
}

# _p_dir <rel_do_dir|''> <nomes...> — listagem nao recursiva; `dir:<n>` e pasta.
_p_dir() {
  local rel=$1 n e lista=''
  shift
  for n in "$@"; do
    if [[ $n == dir:* ]]; then
      printf -v e '{".tag":"folder","name":"%s","id":"id:d%s","path_lower":"/r/%s","path_display":"/r/%s"}' "${n#dir:}" "$P_N" "${rel:+$rel/}${n#dir:}" "${rel:+$rel/}${n#dir:}"
    else
      printf -v e '{".tag":"file","name":"%s","id":"id:f%s","path_lower":"/r/%s","path_display":"/r/%s","rev":"0123456789a","size":3,"server_modified":"2026-01-01T00:00:00Z","content_hash":"%064d"}' "$n" "$P_N" "${rel:+$rel/}$n" "${rel:+$rel/}$n" 0
    fi
    lista+=${lista:+,}$e
  done
  _p_regra files/list_folder "*\"path\":\"/r${rel:+/$rel}\"*" 200 "{\"entries\":[$lista],\"cursor\":\"C$P_N\",\"has_more\":false}"
}

_p_nao_pasta() { _p_regra files/list_folder "*\"path\":\"/r$1\"*" 409 "$Q_NAO_PASTA"; }

_p_local() { # <rel> — arquivo local
  mkdir -p "$B/l/$(dirname -- "$1")"
  printf 'conteudo %s' "$1" >"$B/l/$1"
}

_p_rodar() { # <args...>
  (
    cd "$B" || exit 99
    env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
      TMPDIR="$B/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout -k 2 120 "$Q_BASH" "$Q_DBX" "$@" </dev/null >"$B/out" 2>"$B/err"
  ) 2>/dev/null
  ESTADO=$?
  [[ $ESTADO -eq 124 || $ESTADO -eq 137 ]] && _harness_falhar "o comando pendurou ($ESTADO): $*"
  SAIDA=$(<"$B/out")
  ERRO=$(<"$B/err")
  return 0
}

_p_contar() { # <regex_do_endpoint> [trecho_do_corpo] — Q em P_CONT
  local linha n=0
  while IFS= read -r linha; do
    [[ ${linha%%$'\t'*} =~ ^($1)$ && ${linha#*$'\t'} == *${2:-}* ]] && n=$((n + 1))
  done <"$B/chamadas"
  P_CONT=$n
}

# Remoto: raiz com a.txt e o ARQUIVO `sub`; `sub` recusa a listagem. Local: a.txt e sub/b.txt.
_p_cenario() {
  _p_cen
  _p_dir '' a.txt sub
  _p_nao_pasta /sub
  _p_local a.txt
  _p_local sub/b.txt
}

teste_qa_ocupada_espelhar_nao_encerra_planeja_o_conteudo_e_apaga_o_arquivo_homonimo() {
  _p_cenario
  _p_rodar --json sync --enviar --origem "$B/l" --destino /r --espelhar --confirmar
  assert_igual 0 "$ESTADO" "not_folder em subpasta nao encerra o sync: $ERRO"
  assert_contem 'transferir=sub/b.txt' "$SAIDA" "o conteudo da pasta entra no plano"
  assert_contem 'apagar=sub' "$SAIDA" "o arquivo homonimo e orfao"
  _p_contar 'files/delete_v2' '"/r/sub"'
  assert_igual 1 "$P_CONT" "a exclusao do arquivo homonimo foi executada"
  _p_contar 'files/upload|files/upload_session/start' 'conteudo sub/b.txt'
  assert_diferente 0 "$P_CONT" "o envio do conteudo da pasta foi tentado"
}

teste_qa_ocupada_aviso_sai_em_stderr_sem_progresso_e_nomeia_o_caminho() {
  _p_cenario
  _p_rodar sync --enviar --origem "$B/l" --destino /r --espelhar --confirmar
  assert_igual 0 "$ESTADO" "diagnostico: $ERRO"
  assert_contem '/r/sub' "$ERRO" "o aviso nomeia o caminho remoto"
  assert_contem 'arquivo na Dropbox' "$ERRO" "o aviso diz que e um arquivo"
}

teste_qa_ocupada_sem_espelhar_o_arquivo_homonimo_fica_e_nada_e_apagado() {
  _p_cenario
  _p_rodar --json sync --enviar --origem "$B/l" --destino /r --confirmar
  assert_igual 0 "$ESTADO" "diagnostico: $ERRO"
  assert_contem 'apenas_no_destino' "$SAIDA" "o homonimo e so-no-destino"
  assert_nao_contem 'apagar=sub' "$SAIDA" "sem --espelhar nao ha exclusao planejada"
  _p_contar 'files/delete_batch|files/delete_batch/check|files/delete_v2'
  assert_igual 0 "$P_CONT" "nada apagado"
}

teste_qa_ocupada_raiz_do_destino_que_e_arquivo_continua_falha_nomeando_o_caminho() {
  _p_cen
  _p_nao_pasta ''
  _p_local a.txt
  _p_rodar sync --enviar --origem "$B/l" --destino /r --espelhar --confirmar
  assert_igual 2 "$ESTADO" "raiz que e arquivo: classe de uso invalido; $ERRO"
  assert_contem 'recusada em /r:' "$ERRO" "o motivo nomeia o caminho"
  _p_contar 'files/upload|files/delete_batch|files/delete_v2'
  assert_igual 0 "$P_CONT" "sem listagem remota nada e escrito"
}

teste_qa_ocupada_dry_run_nao_escreve_nada() {
  _p_cenario
  _p_rodar --dry-run --json sync --enviar --origem "$B/l" --destino /r --espelhar --confirmar
  assert_igual 0 "$ESTADO" "diagnostico: $ERRO"
  assert_contem 'apagar=sub' "$SAIDA" "o plano mostra a exclusao"
  _p_contar 'files/upload|files/upload_session/[a-z_]*|files/delete_batch|files/delete_batch/check|files/delete_v2'
  assert_igual 0 "$P_CONT" "dry-run nao escreve no remoto"
}

teste_qa_ocupada_em_ciclo_posterior_o_orfao_sai_no_ciclo_do_pai_e_o_conteudo_e_enviado() {
  _p_cen
  _p_dir '' a.txt sub dir:zz
  _p_dir zz
  _p_nao_pasta /sub
  _p_local a.txt
  _p_local sub/b.txt
  _p_local zz/c.txt
  _p_rodar --json sync --enviar --origem "$B/l" --destino /r --espelhar --confirmar --bloco 1
  assert_igual 0 "$ESTADO" "pasta ocupada em ciclo posterior nao encerra: $ERRO"
  _p_contar 'files/delete_v2' '"/r/sub"'
  assert_igual 1 "$P_CONT" "o orfao e apagado no ciclo do pai"
  _p_contar 'files/upload|files/upload_session/start' 'conteudo sub/b.txt'
  assert_diferente 0 "$P_CONT" "o conteudo da pasta ocupada e enviado"
  _p_contar 'files/upload|files/upload_session/start' 'conteudo zz/c.txt'
  assert_diferente 0 "$P_CONT" "o ciclo seguinte segue normalmente"
  assert_contem '/r/sub' "$ERRO" "aviso do caminho"
}

harness_executar "$@"
