#!/usr/bin/env bash
# Tarefa 6a de F-103 (RF-217, RF-218, RF-214(e), RF-219(a)), sentido local ->
# remoto: simulacao e plano de pastas, contadores `pastas_*` no resumo e no
# `--json`, relatorio da exclusao antecipada. TC-ARV-30, 31 e 32. Duble de `curl`
# copiado de estrutura_pastas_envio_test.sh. Dado sintetico apenas.
#
# Seam: o executavel `dbx` com o cliente HTTP real e um duplo de `curl` que
# registra cada URL em `$base/chamadas` (ordem) e responde as rotas em lote por
# tests/support/lote_duplo.sh (corpos de `create_folder_batch` em
# `$base/lote/chamadas`). Dado sintetico apenas.
#
# shellcheck disable=SC2016
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"

_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/pastas_envio.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/lote/pasta_arquivo" "$base/lote/pasta_sem_espaco"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%s\nDBX_HARNESS_RAIZ=%q\n' "$base" "$DBX_HARNESS_RAIZ"
    cat <<'FIM'
cat >/dev/null 2>&1
saida=""; escrever=""; anterior=""; url=""; corpo_arquivo=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
[[ -f $corpo_arquivo ]] && { cat "$corpo_arquivo"; printf '\n'; } >>"$base/corpos"
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_space_usage*) corpo='{"used":0,"allocation":{".tag":"individual","allocated":1000000}}'
    [[ -r $base/espaco_curto ]] && corpo='{"used":0,"allocation":{".tag":"individual","allocated":1}}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *list_folder/get_latest_cursor*) corpo='{"cursor":"CURSOR-RAIZ-1"}' ;;
  *list_folder/continue*) corpo='{"entries":[],"has_more":false,"cursor":"CURSOR-DELTA-2"}' ;;
  *list_folder*)
    corpo='{"entries":[],"has_more":false}'; [[ -r $base/listagem ]] && corpo=$(cat "$base/listagem")
    # RF-216: listagem por pasta (`listagem<caminho com _>`) e, por chamada, a variante `.N`
    lp=$(grep -o '"path":"[^"]*"' "$corpo_arquivo" | head -1); lp=${lp#\"path\":\"}; lp=${lp%\"}
    arq="$base/listagem${lp//\//_}"
    if [[ -r $arq ]]; then
      nlp=$(( $(cat "$arq.n" 2>/dev/null || printf 0) + 1 )); printf '%s' "$nlp" >"$arq.n"
      corpo=$(cat "$arq"); [[ -r $arq.$nlp ]] && corpo=$(cat "$arq.$nlp")
    fi ;;
  *files/delete_v2*)
    nome=$(grep -o '"path":"[^"]*"' "$corpo_arquivo" | head -1); nome=${nome%\"}; nome=${nome##*/}
    if [[ -r $base/delete_v2_409 ]]; then codigo=409; corpo='{"error_summary":"path_lookup/not_found/.."}'
    else rm -f "$base/lote/pasta_arquivo/$nome"; corpo='{"metadata":{".tag":"file","name":"x"}}'; fi ;;
  *files/get_metadata*) codigo=409; corpo='{"error_summary":"path/not_found/.."}' ;;
  *upload_session/start*) corpo='{"session_id":"S-1"}' ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
. "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
lote_responder "$url" "$corpo_arquivo" || :
[[ -n $saida ]] && printf "%s" "$corpo" >"$saida"
[[ -n $escrever ]] && printf "%s" "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_rodar() { # <base> <argumentos...>
  local base=$1
  shift
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err" </dev/null
  DBX_ESTADO=$?
  DBX_SAIDA='' DBX_ERRO=''
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_arquivo() { # <base> <relativo> — arquivo local com conteudo identificavel
  mkdir -p "$1/local/$(dirname -- "$2")"
  printf 'conteudo-%s' "${2//\//-}" >"$1/local/$2"
}

_pastas() { [[ -r $1/lote/chamadas ]] && grep '^create_folder_batch' "$1/lote/chamadas"; return 0; }
_corpos() { [[ -r $1/corpos ]] && cat "$1/corpos"; return 0; }
_listagem_arquivo() { # <base> <nome> — o destino /r tem um ARQUIVO <nome> com rev conhecido
  printf '{"entries":[{".tag":"file","name":"%s","path_display":"/r/%s","path_lower":"/r/%s","content_hash":"h","size":3,"rev":"0a1b2c3d4e"}],"has_more":false}' \
    "$2" "$2" "$2" >"$1/listagem"
}
_sequencia() { # <base> — as chamadas relevantes, na ordem, pelo ultimo segmento da URL
  grep -E 'create_folder_batch|list_folder|delete_v2|delete_batch|upload' "$1/chamadas" | sed 's#.*/##' | tr '\n' ' '
}
_pasta_json() { printf '{".tag":"folder","name":"%s","path_display":"/r/%s","path_lower":"/r/%s","id":"id:%s"}' "${1##*/}" "$1" "$1" "${1//\//}"; }
_arq_json() { printf '{".tag":"file","name":"%s","path_display":"/r/%s","path_lower":"/r/%s","content_hash":"h","size":3,"rev":"0a1b2c3d4e"}' "${1##*/}" "$1" "$1"; }
_lista() { # <base> <sufixo do arquivo, ex.: _r_o> <entradas...>
  local base=$1 suf=$2 itens
  shift 2
  itens=$(IFS=,; printf '%s' "$*")
  printf '{"entries":[%s],"has_more":false}' "$itens" >"$base/listagem$suf"
}
_deletes_v2() { _harness_contar 'files/delete_v2' "$1/chamadas"; }
_orfa_remota() { # <base> — origem local com k.txt; /r tem a pasta o
  _arquivo "$1" k.txt
  _lista "$1" _r "$(_arq_json k.txt)" "$(_pasta_json o)"
}

# _pos <texto> <trecho> — posicao do trecho no texto (para ordem nas linhas da saida).
_pos() { local pre=${1%%"$2"*}; [[ $1 == *"$2"* ]] && printf '%s' "${#pre}" || printf '%s' 999999; }

teste_tc_arv_31_resumo_traz_os_quatro_contadores_e_pasta_nao_e_arquivo() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/a/b"
  _arquivo "$base" c/x.txt
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'pastas_criadas=3' "$DBX_SAIDA" 'RF-218(a): a, a/b e c'
  assert_contem 'pastas_apagadas=0' "$DBX_SAIDA" 'RF-218(a)'
  assert_contem 'pastas_mantidas=0' "$DBX_SAIDA" 'RF-218(a)'
  assert_contem 'pastas_falhas=0' "$DBX_SAIDA" 'RF-218(a)'
  assert_contem 'enviados=1' "$DBX_SAIDA" 'RF-218(c): pasta nao conta como arquivo transferido'
}

teste_tc_arv_31_json_traz_os_quatro_contadores() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/a"
  _arquivo "$base" x.txt
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'pastas_criadas=1' "$DBX_SAIDA" 'RF-218(a)'
  assert_contem 'pastas_apagadas=0' "$DBX_SAIDA" 'RF-218(a)'
  assert_contem 'pastas_mantidas=0' "$DBX_SAIDA" 'RF-218(a)'
  assert_contem 'pastas_falhas=0' "$DBX_SAIDA" 'RF-218(a)'
  assert_contem 'enviados=1' "$DBX_SAIDA" 'RF-218(c): campos antigos intactos'
}

teste_tc_arv_32_arvore_sem_pasta_nova_traz_os_antigos_iguais_e_os_novos_zerados() {
  local base
  base=$(_cenario)
  _arquivo "$base" x.txt
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'enviados=1' "$DBX_SAIDA" 'RF-219(a)'
  assert_contem 'apagados=0' "$DBX_SAIDA" 'RF-219(a)'
  assert_contem 'falhas=0' "$DBX_SAIDA" 'RF-219(a)'
  assert_contem 'pastas_criadas=0' "$DBX_SAIDA" 'RF-219(a): novos com 0'
  assert_contem 'pastas_falhas=0' "$DBX_SAIDA" 'RF-219(a): novos com 0'
}

teste_tc_arv_31_falha_de_pasta_sai_com_caminho_e_motivo_antes_dos_contadores() {
  local base
  base=$(_cenario)
  _arquivo "$base" a/x.txt
  : >"$base/lote/pasta_arquivo/a"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_contem 'pastas_falhas=1' "$DBX_SAIDA" 'RF-218(a): a pasta que falhou'
  assert_contem 'falha=a' "$DBX_SAIDA" 'RF-218(b): caminho da pasta'
  assert_contem 'arquivo no lugar da pasta' "$DBX_SAIDA" 'RF-218(b): motivo'
  assert_igual sim "$([[ $(_pos "$DBX_SAIDA" 'falha=a') -lt $(_pos "$DBX_SAIDA" 'pastas_falhas=') ]] && printf sim)" 'RF-218(b): antes dos contadores'
}

teste_tc_arv_30_simulacao_anuncia_as_pastas_antes_dos_arquivos_sem_nenhuma_escrita() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/a/b"
  _arquivo "$base" c/x.txt
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'criaria=pasta a' "$DBX_SAIDA" 'RF-217(a)'
  assert_contem 'criaria=pasta a/b' "$DBX_SAIDA" 'RF-217(a)'
  assert_contem 'criaria=pasta c' "$DBX_SAIDA" 'RF-217(a)'
  assert_igual sim "$([[ $(_pos "$DBX_SAIDA" 'criaria=pasta c') -lt $(_pos "$DBX_SAIDA" $'\ntransferir=') ]] && printf sim)" 'RF-217(a): antes dos arquivos'
  assert_igual '' "$(_pastas "$base")" 'RF-217(b): zero create_folder'
  assert_igual 0 "$(_deletes_v2 "$base")" 'RF-217(b): zero delete_v2'
  assert_contem 'pastas_criadas=3' "$DBX_SAIDA" 'RF-218(a): conta o anunciado'
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'RF-218(a): marca de simulacao de hoje'
}

teste_tc_arv_30_simulacao_anuncia_a_pasta_orfa_sem_releitura_nem_escrita() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o
  _rodar "$base" --dry-run sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'apagaria=pasta o' "$DBX_SAIDA" 'RF-217(a)(c)'
  assert_igual 0 "$(_deletes_v2 "$base")" 'RF-217(b): zero delete_v2'
  assert_igual 2 "$(_harness_contar 'list_folder$' "$base/chamadas")" 'RF-217(b): sem releitura de confirmacao'
  assert_contem 'pastas_apagadas=1' "$DBX_SAIDA" 'RF-218(a)'
}

teste_rf214e_exclusao_antecipada_sai_no_relatorio_com_motivo() {
  local base
  base=$(_cenario)
  _arquivo "$base" a/x.txt
  : >"$base/lote/pasta_arquivo/a"
  _listagem_arquivo "$base" a
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'apagado=a (arquivo no lugar da pasta)' "$DBX_SAIDA" 'RF-214(e): linha do relatorio com o motivo'
  assert_contem 'apagados=1' "$DBX_SAIDA" 'RF-214(e): conta uma vez'
}

teste_rf214e_simulacao_anuncia_apagaria_e_criaria_pasta() {
  local base
  base=$(_cenario)
  _arquivo "$base" a/x.txt
  _listagem_arquivo "$base" a
  _rodar "$base" --dry-run sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'apagaria=a (arquivo no lugar da pasta)' "$DBX_SAIDA" 'RF-214(e)'
  assert_contem 'criaria=pasta a' "$DBX_SAIDA" 'RF-214(e)'
  assert_igual 0 "$(_deletes_v2 "$base")" 'RF-214(e): sem chamada'
  assert_igual '' "$(_pastas "$base")" 'RF-214(e): sem chamada'
}

# --- RF-217(c)(d): so o que ficaria vazio e anunciado; recusa por espaco cala o plano ---

teste_rf217c_simulacao_anuncia_a_orfa_que_fica_vazia_pelas_exclusoes_planejadas() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o "$(_arq_json o/x.txt)"
  _rodar "$base" --dry-run sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'apagar=o/x.txt' "$DBX_SAIDA" 'o arquivo orfao esta no plano'
  assert_contem 'apagaria=pasta o' "$DBX_SAIDA" 'RF-217(c): ficaria vazia'
}

teste_rf217c_simulacao_nao_anuncia_a_orfa_com_item_filtrado() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o "$(_arq_json o/x.log)"
  _rodar "$base" --dry-run sync --enviar --espelhar --confirmar --excluir '*.log' --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_nao_contem 'apagaria=pasta o' "$DBX_SAIDA" 'RF-217(c): o filtrado a mantem'
  assert_contem 'pastas_apagadas=0' "$DBX_SAIDA" 'RF-218(a): conta o anunciado'
}

teste_rf217c_simulacao_subpasta_com_filtrado_mantem_a_cadeia_e_anuncia_a_irma_vazia() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o "$(_pasta_json o/p)" "$(_pasta_json o/q)"
  _lista "$base" _r_o_p "$(_arq_json o/p/x.log)"
  _lista "$base" _r_o_q
  _rodar "$base" --dry-run sync --enviar --espelhar --confirmar --excluir '*.log' --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'apagaria=pasta o/q' "$DBX_SAIDA" 'a irma vazia sai'
  assert_nao_contem 'apagaria=pasta o/p' "$DBX_SAIDA" 'a subpasta com filtrado fica'
  assert_nao_contem 'apagaria=pasta o'$'\n' "$DBX_SAIDA" 'a cadeia ate a raiz da orfa fica'
}

teste_rf217d_recusa_por_espaco_nao_anuncia_nenhuma_pasta() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o
  mkdir -p "$base/local/n"
  _arquivo "$base" n/z.txt
  : >"$base/espaco_curto"
  _rodar "$base" --dry-run sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'recusaria=' "$DBX_SAIDA" 'a recusa por espaco aparece como hoje'
  assert_nao_contem 'criaria=' "$DBX_SAIDA" 'RF-217(d): nenhuma pasta a criar'
  assert_nao_contem 'apagaria=' "$DBX_SAIDA" 'RF-217(d): nenhuma pasta a apagar'
  assert_contem 'pastas_criadas=0' "$DBX_SAIDA" 'RF-218(a): contadores zerados'
  assert_contem 'pastas_apagadas=0' "$DBX_SAIDA" 'RF-218(a): contadores zerados'
}

harness_executar "$@"
