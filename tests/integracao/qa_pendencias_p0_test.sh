#!/usr/bin/env bash
# Suite independente do QA Expert — fase 0 (O-5 e RSK-43).
#
# Porte M: validacao independente sobre `dbx_cmd_ler_corpo_silencioso` (lib/cmd)
# e seu uso em `_dbx_cmd_upload_hash_remoto` (commands/upload), e sobre a prova
# de que `identidade_gnustat_test` passa de fato pelo `gnustat`. Massa e duplo de
# `curl` proprios; nenhum caso reaproveita o do Senior Developer.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e literal.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
# Token sintetico reconhecivel: nao pode aparecer em saida nenhuma (RNF-03).
readonly QA_TOKEN='sl.QA_P0_segredo_de_corpo_9z8y7x'
readonly QA_HASH_BOM='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

# _qa_cenario <codigo_metadado> <corpo_metadado> — publica BASE e ORIGEM.
_qa_cenario() {
  BASE=$(mktemp -d "$DBX_TESTES_TMP/qa_p0.XXXXXX")
  mkdir -p "$BASE/config/dbx" "$BASE/bin"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$BASE/config/dbx/credencial.json"
  chmod 700 "$BASE/config/dbx"
  chmod 600 "$BASE/config/dbx/credencial.json"
  printf '%s' "$1" >"$BASE/meta_codigo"
  printf '%s' "$2" >"$BASE/meta_corpo"
  {
    printf '#!/usr/bin/env bash\nbase=%q\n' "$BASE"
    cat <<'FIM'
cat >/dev/null 2>&1
saida='' escrever='' anterior='' url=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:QAP0"}' ;;
  *files/get_metadata*) codigo=$(cat "$base/meta_codigo"); corpo=$(cat "$base/meta_corpo") ;;
  *files/upload) corpo='{"name":"a.txt","rev":"0a1"}' ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
[[ -n $escrever ]] && printf '%s' "$codigo"
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
exit 0
FIM
  } >"$BASE/bin/curl"
  chmod +x "$BASE/bin/curl"
  ORIGEM="$BASE/local.txt"
  printf 'conteudo qa' >"$ORIGEM"
  touch -d '@1700000000' "$ORIGEM"
}

_qa_rodar() {
  DBX_SAIDA='' DBX_ERRO=''
  env -i PATH="$BASE/bin:$PATH" HOME="$BASE" XDG_CONFIG_HOME="$BASE/config" \
    XDG_STATE_HOME="$BASE/estado" TMPDIR="$DBX_TESTES_TMP" \
    DBX_HTTP_TENTATIVAS_MAXIMAS=1 DBX_HTTP_ESPERA_BASE_MS=1 \
    bash "$DBX_EXEC" --progresso "$@" </dev/null >"$BASE/out" 2>"$BASE/err"
  DBX_ESTADO=$?
  [[ -r $BASE/out ]] && IFS= read -r -d '' DBX_SAIDA <"$BASE/out"
  [[ -r $BASE/err ]] && IFS= read -r -d '' DBX_ERRO <"$BASE/err"
  return 0
}

_qa_envios() { _harness_contar 'files/upload$' "$BASE/chamadas"; }

# _qa_caso_de_falha <codigo> <corpo> <classe> <motivo> — envio segue, classe e
# motivo no progresso (stderr), saida padrao sem diagnostico.
_qa_caso_de_falha() {
  _qa_cenario "$1" "$2"
  _qa_rodar upload "$ORIGEM" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "o envio segue e sai 0; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_qa_envios)" 'exatamente um files/upload'
  assert_contem "classe=$3" "$DBX_ERRO" 'classe propagada'
  assert_contem "$4" "$DBX_ERRO" 'motivo propagado'
  assert_contem 'operacao=upload' "$DBX_SAIDA" 'stdout com a operacao'
  assert_nao_contem 'classe=' "$DBX_SAIDA" 'stdout sem diagnostico'
  assert_nao_contem 'motivo=' "$DBX_SAIDA" 'stdout sem motivo'
}

teste_corpo_vazio_propaga_classe_e_motivo_e_envia() {
  _qa_caso_de_falha 200 '' erro_remoto 'resposta nao interpretavel'
}

teste_json_truncado_propaga_classe_e_motivo_e_envia() {
  _qa_caso_de_falha 200 '{".tag":"file","content_ha' erro_remoto 'resposta nao interpretavel'
}

teste_campo_ausente_propaga_classe_e_motivo_e_envia() {
  _qa_caso_de_falha 200 '{".tag":"file","name":"a.txt"}' erro_remoto 'ausente ou malformado'
}

teste_hash_malformado_propaga_classe_e_motivo_e_envia() {
  _qa_caso_de_falha 200 '{".tag":"file","content_hash":"XYZ-curto"}' erro_remoto 'ausente ou malformado'
}

teste_destino_pasta_propaga_classe_e_motivo_e_envia() {
  _qa_caso_de_falha 200 "{\".tag\":\"folder\",\"content_hash\":\"$QA_HASH_BOM\"}" \
    erro_remoto 'nao e um arquivo comparavel'
}

teste_erro_5xx_propaga_classe_e_motivo_e_envia() {
  _qa_cenario 503 '{"error_summary":"internal_server_error/.."}'
  _qa_rodar upload "$ORIGEM" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "5xx na consulta nao aborta; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_qa_envios)" 'o envio segue'
  assert_contem 'classe=' "$DBX_ERRO" 'classe nomeada'
  assert_contem 'motivo=consulta recusada' "$DBX_ERRO" 'motivo nomeado'
  assert_nao_contem 'classe=desconhecido' "$DBX_ERRO" 'classe real, nao o reserva'
}

teste_token_em_corpo_de_erro_nunca_aparece() {
  _qa_cenario 200 "{\"access_token\":\"$QA_TOKEN\",\"x\":"
  _qa_rodar upload "$ORIGEM" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" 'envio segue'
  assert_segredo_ausente "$QA_TOKEN" "$DBX_ERRO" 'token fora do progresso (truncado)'
  assert_segredo_ausente "$QA_TOKEN" "$DBX_SAIDA" 'token fora da saida (truncado)'
  _qa_cenario 503 "{\"error_summary\":\"falhou access_token=$QA_TOKEN fim\"}"
  _qa_rodar upload "$ORIGEM" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" 'envio segue (5xx)'
  assert_segredo_ausente "$QA_TOKEN" "$DBX_ERRO" 'token fora do progresso (5xx)'
  assert_segredo_ausente "$QA_TOKEN" "$DBX_SAIDA" 'token fora da saida (5xx)'
}

teste_hash_bom_remoto_igual_dispensa_sem_classe_nem_motivo() {
  # Controle: o caminho de sucesso nao emite diagnostico de falha.
  local hash=''
  _qa_cenario 200 '{}'
  dbx_hash_publicar_arquivo "$ORIGEM" && hash=$DBX_HASH_RESULTADO
  [[ -n $hash ]] || pular 'sem content_hash local calculavel'
  printf '%s' "{\".tag\":\"file\",\"content_hash\":\"$hash\"}" >"$BASE/meta_corpo"
  _qa_rodar upload "$ORIGEM" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "sucesso; diagnostico: $DBX_ERRO"
  assert_igual 0 "$(_qa_envios)" 'hash igual dispensa o envio'
  assert_nao_contem 'classe=' "$DBX_ERRO" 'sem classe no caminho de sucesso'
}

teste_leitura_nao_vaza_contexto_nem_canais() {
  # Em processo isolado: o auxiliar descarta documento, corpo e resultado, e
  # nao emite nada, em sucesso e em falha.
  local saida
  saida=$(bash -c '
    R=$1
    . "$R/lib/errors.sh"; . "$R/lib/progress.sh"; . "$R/lib/json.sh"; . "$R/lib/hash.sh"
    . "$R/lib/http.sh"; . "$R/lib/auth.sh"; . "$R/lib/cmd.sh"
    DBX_HTTP_CORPO="{\".tag\":\"file\",\"content_hash\":\"abc\"}"
    dbx_cmd_ler_corpo_silencioso .tag content_hash nada; s1=$?
    printf "S1=%s|%s|%s|%s|%s|%s\n" "$s1" "${DBX_CMD_CAMPOS[0]}" "${DBX_CMD_CAMPOS[1]}" "[${DBX_CMD_CAMPOS[2]}]" "[$DBX_HTTP_CORPO]" "[$DBX_JSON_RESULTADO]"
    DBX_HTTP_CORPO="{\"a\":"
    dbx_cmd_ler_corpo_silencioso a; s2=$?
    printf "S2=%s|%s|[%s]\n" "$s2" "$DBX_CMD_FALHA_CLASSE" "$DBX_HTTP_CORPO"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_contem 'S1=0|file|abc|[]|[]|[]' "$saida" 'sucesso: campos na ordem, ausente vazio, canais limpos'
  assert_contem 'S2=1|erro_remoto|[]' "$saida" 'falha: status 1, classe, corpo descartado'
  assert_igual 2 "$(grep -c . <<<"$saida")" 'nada alem das duas linhas do proprio teste foi emitido'
}

teste_gnustat_do_senior_passa_pelo_duplo_registrado() {
  # Prova independente: um mutante do duplo (que adultera a saida do GNU) TEM de
  # reprovar o caso do Senior; logo o caso depende do `gnustat`, nao do `stat`
  # da maquina.
  [[ -x /usr/bin/gnustat ]] || pular 'GNU coreutils ausente: /usr/bin/gnustat'
  local copia
  copia=$(mktemp -d "$DBX_TESTES_TMP/qa_gnu.XXXXXX")
  mkdir -p "$copia/tests/unit" "$copia/tests/support"
  cp -R "$DBX_HARNESS_RAIZ/lib" "$copia/lib"
  cp "$DBX_HARNESS_RAIZ/tests/support/harness.sh" "$copia/tests/support/"
  cp "$DBX_HARNESS_RAIZ/tests/run.sh" "$copia/tests/"
  sed 's#exec %s "\$@"#exec %s "$@" | tr "|" ";"#' \
    "$DBX_HARNESS_RAIZ/tests/unit/identidade_gnustat_test.sh" >"$copia/tests/unit/identidade_gnustat_test.sh"
  cmp -s "$copia/tests/unit/identidade_gnustat_test.sh" "$DBX_HARNESS_RAIZ/tests/unit/identidade_gnustat_test.sh" &&
    _harness_falhar 'o mutante nao alterou o arquivo'
  local tap
  tap=$(cd "$copia" && bash tests/run.sh identidade_gnustat </dev/null 2>&1)
  assert_diferente 0 $? 'o mutante do duplo reprova o caso'
  assert_contem 'not ok' "$tap" 'TAP com reprovacao'
}

harness_executar "$@"
