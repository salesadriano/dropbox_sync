#!/usr/bin/env bash
# Tarefa 6b de F-103 (RF-212, TC-ARV-13, 14 e 15): recebimento sem ciclos, isto e,
# so o delta com cursor valido. A entrada `folder` do delta e a pasta do retrato
# ausente localmente criam a pasta local antes das transferencias; `deleted` de
# pasta nao exclui pasta; nenhum `list_folder` por diretorio e feito. Duble de
# `curl` copiado de estrutura_pastas_recebimento_test.sh, com o delta lido de
# `$base/delta`. Dado sintetico apenas.
#
# Seam: o executavel `dbx` com o cliente HTTP real e o duble de `curl`.
#
#
#
# shellcheck disable=SC2016
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
HASH_REMOTO=''

_hash_remoto() {
  [[ -n $HASH_REMOTO ]] ||
    HASH_REMOTO=$(bash -c '. "$1/lib/errors.sh"; . "$1/lib/hash.sh"; printf "%s" "conteudo remoto" | dbx_hash_conteudo_fluxo' _ "$DBX_HARNESS_RAIZ")
}

_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/pastas_receb.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/ls"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' 'conteudo remoto' >"$base/conteudo_remoto"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%s\nDBX_HARNESS_RAIZ=%q\n' "$base" "$DBX_HARNESS_RAIZ"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
saida=""; escrever=""; anterior=""; url=""; cabecalhos=""; corpo_arquivo=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; -D) cabecalhos=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
[[ -f $corpo_arquivo ]] && { cat "$corpo_arquivo"; printf '\n'; } >>"$base/corpos"
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *list_folder/get_latest_cursor*) corpo='{"cursor":"CURSOR-RAIZ-1"}' ;;
  *list_folder/continue*) corpo='{"entries":[],"has_more":false,"cursor":"CURSOR-DELTA-2"}'
    [[ -r $base/delta ]] && corpo=$(cat "$base/delta") ;;
  *list_folder*)
    caminho=$(grep -o '"path":"[^"]*"' "$corpo_arquivo" | head -1)
    caminho=${caminho#\"path\":\"}; caminho=${caminho%\"}
    chave=${caminho//[^A-Za-z0-9]/_}
    if [[ -f "$base/lsapos/$chave" ]]; then
      restantes=$(cat "$base/lsapos/$chave")
      if ((restantes > 0)); then printf '%s' "$((restantes - 1))" >"$base/lsapos/$chave"; corpo=$(cat "$base/ls/$chave"); else codigo=500; corpo='{"error_summary":"x"}'; fi
    elif [[ -f "$base/lserro/$chave" ]]; then codigo=$(cat "$base/lserro/$chave"); corpo='{"error_summary":"x"}'
    elif [[ -f "$base/ls/$chave" ]]; then corpo=$(cat "$base/ls/$chave")
    else corpo='{"entries":[],"has_more":false}'; fi ;;
  *files/get_metadata*) if [[ -f "$base/meta" ]]; then corpo=$(cat "$base/meta"); else corpo='{".tag":"file","name":"x","rev":"015f00000000a1b2","size":15}'; fi ;;
  *files/download*)
    corpo=$(cat "$base/conteudo_remoto")
    n=$(find "$base" -maxdepth 1 -name 'snap_*' | wc -l)
    { cd "$base/local" 2>/dev/null && find . -type d | sort; } >"$base/snap_$n" ;;
  *upload_session/start*) corpo='{"session_id":"S-1"}' ;;
  *upload_session/append_v2*) corpo='{}' ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
LOTE_ECOA_V2=sim
. "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
lote_responder "$url" "$corpo_arquivo" || :
if [[ $url == *files/upload* && -f "$base/upload_erro" ]]; then codigo=$(cat "$base/upload_erro"); corpo='{"error_summary":"x"}'; fi
if [[ $url == *files/download* && -f "$base/download_erro" ]]; then codigo=$(cat "$base/download_erro"); corpo='{"error_summary":"x"}'; fi
if [[ $url == *files/download* && -n $cabecalhos && -f "$base/resultado_cabecalho" ]]; then
  printf "Dropbox-API-Result: %s\r\n" "$(cat "$base/resultado_cabecalho")" >"$cabecalhos"
fi
if [[ $url == *files/get_metadata* && -f "$base/meta_ausente" ]]; then
  codigo=409; corpo='{"error_summary":"path/not_found/"}'
fi
# meta_pasta: o caminho que, DEPOIS da confirmacao de exclusao (primeira consulta,
# que segue meta_ausente), o servidor responde como pasta (a consulta da fase de pastas).
if [[ $url == *files/get_metadata* && -f "$base/meta_pasta" ]] && grep -qF "\"path\":\"$(cat "$base/meta_pasta")\"" "$corpo_arquivo"; then
  if [[ -f "$base/meta_pasta_vista" ]]; then codigo=200; corpo='{".tag":"folder","name":"x","id":"id:DX"}'; else : >"$base/meta_pasta_vista"; fi
fi
if [[ $url == *files/get_metadata* && -f "$base/download_erro_pasta" ]]; then
  codigo=409; corpo='{"error_summary":"path/not_found/"}'
fi
if [[ $url == *files/download* && -f "$base/download_erro_pasta" ]]; then
  # o cliente tenta o arquivo duas vezes antes do fallback de pasta: 409 nas duas
  printf x >>"$base/dl_pasta"
  [[ $(wc -c <"$base/dl_pasta") -ge 3 ]] && rm -f "$base/download_erro_pasta"
  codigo=409; corpo='{"error_summary":"path/not_file/.."}'
fi
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
  DBX_SAIDA=''
  DBX_ERRO=''
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _ls <base> <caminho> <entradas json...>
_ls() {
  local base=$1 caminho=$2 chave itens
  shift 2
  chave=${caminho//[^A-Za-z0-9]/_}
  itens=$(IFS=,; printf '%s' "$*")
  printf '{"entries":[%s],"has_more":false}' "$itens" >"$base/ls/$chave"
}
_f() { printf '{".tag":"file","id":"id:A%s","path_display":"%s","path_lower":"%s","content_hash":"%s","size":15,"rev":"%s"}' \
  "${1//[^A-Za-z0-9]/}" "$1" "${1,,}" "$HASH_REMOTO" "015f00000000a1b2"; }
_d() { printf '{".tag":"folder","id":"id:D%s","path_display":"%s","path_lower":"%s"}' "${1//[^A-Za-z0-9]/}" "$1" "${1,,}"; }


_pastas_locais() { (cd "$1/local" && find . -type d | sort); }
_listagens() { _harness_contar 'list_folder$' "$1/chamadas"; }

# _primeira <base> — varredura completa que grava cursor e retrato.
_primeira() {
  _rodar "$1" sync --receber --origem /r --destino "$1/local"
  assert_igual 0 "$DBX_ESTADO" "primeira execucao; diagnostico: $DBX_ERRO"
}

teste_tc_arv_13_entrada_folder_do_delta_cria_a_pasta_local_sem_list_folder_por_diretorio() {
  local base antes
  base=$(_cenario)
  _hash_remoto
  _ls "$base" /r "$(_f /r/k.txt)"
  _primeira "$base"
  antes=$(_listagens "$base")
  printf '{"entries":[%s,%s,%s],"has_more":false,"cursor":"CURSOR-DELTA-2"}' \
    "$(_d /r/novo)" "$(_d /r/novo/sub)" "$(_f /r/novo/n.txt)" >"$base/delta"
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'varredura=incremental' "$DBX_SAIDA" 'e o delta, sem ciclos'
  assert_igual sim "$([[ -d $base/local/novo/sub ]] && printf sim)" 'RF-212(a): a pasta vazia do delta existe'
  assert_contem './novo' "$(cat "$base"/snap_* 2>/dev/null)" 'RF-212(a): a pasta existia antes do primeiro download'
  assert_igual "$antes" "$(_listagens "$base")" 'RF-212(d): nenhum list_folder por diretorio'
  assert_contem 'pastas_criadas=2' "$DBX_SAIDA" 'RF-218(a): so as pastas criadas'
}

_remoto_a_b() { # <base> — /r tem as pastas a (com a1.txt) e b (com b1.txt)
  _hash_remoto
  _ls "$1" /r "$(_d /r/a)" "$(_d /r/b)"
  _ls "$1" /r/a "$(_f /r/a/a1.txt)"
  _ls "$1" /r/b "$(_f /r/b/b1.txt)"
}

teste_tc_arv_14_pasta_do_retrato_ausente_localmente_e_recriada() {
  local base antes
  base=$(_cenario)
  _hash_remoto
  _ls "$base" /r "$(_d /r/a)" "$(_d /r/b)"
  _ls "$base" /r/b "$(_f /r/b/b1.txt)"
  _primeira "$base"
  rm -rf "$base/local/a"
  antes=$(_listagens "$base")
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'varredura=incremental' "$DBX_SAIDA" 'e o delta, sem ciclos'
  assert_igual sim "$([[ -d $base/local/a ]] && printf sim)" 'RF-212(b): recriada'
  assert_igual "$antes" "$(_listagens "$base")" 'RF-212(d): nenhum list_folder por diretorio'
}

teste_tc_arv_15_deleted_de_pasta_no_delta_nao_autoriza_exclusao_de_pasta() {
  local base
  base=$(_cenario)
  _hash_remoto
  # retrato forjado a dizer "vazia": /r/a sem arquivo; a pasta local tambem vazia,
  # de modo que um rmdir, se tentado, teria sucesso (RF-212(c)).
  _ls "$base" /r "$(_d /r/a)" "$(_f /r/k.txt)"
  _primeira "$base"
  assert_igual vazia "$([[ -d $base/local/a && -z $(ls -A "$base/local/a") ]] && printf vazia)" 'a pasta local a esta vazia'
  : >"$base/meta_ausente"
  printf '{"entries":[{".tag":"deleted","name":"a","path_display":"/r/a","path_lower":"/r/a"}],"has_more":false,"cursor":"CURSOR-DELTA-2"}' >"$base/delta"
  _rodar "$base" --debug sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual sim "$([[ -d $base/local/a ]] && printf sim)" 'RF-212(c): a pasta fica, so RF-216 a apaga'
  assert_nao_contem 'operacao=rmdir' "$DBX_ERRO" 'RF-212(c): nenhuma tentativa de remocao'
  assert_nao_contem 'pasta apagada' "$DBX_ERRO" 'RF-212(c): nada anunciado como apagado'
}

teste_rf_214_delta_com_espelhar_apaga_o_arquivo_que_ocupa_a_pasta_e_cria_a_pasta() {
  local base
  base=$(_cenario)
  _hash_remoto
  _ls "$base" /r "$(_f /r/k.txt)"
  _primeira "$base"
  printf 'local' >"$base/local/novo"
  : >"$base/meta_ausente"
  printf '/r/novo' >"$base/meta_pasta"
  printf '{"entries":[%s,%s],"has_more":false,"cursor":"CURSOR-DELTA-2"}' \
    "$(_d /r/novo)" "$(_f /r/novo/n.txt)" >"$base/delta"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'varredura=incremental' "$DBX_SAIDA" 'e o delta, sem ciclos'
  assert_igual sim "$([[ -d $base/local/novo && ! -L $base/local/novo ]] && printf sim)" 'RF-214: a pasta ocupa o lugar do arquivo'
  assert_igual 'conteudo remoto' "$(cat "$base/local/novo/n.txt" 2>/dev/null)" 'RF-214: o conteudo da pasta foi baixado'
  assert_contem 'apagado: novo (arquivo no lugar da pasta)' "$DBX_ERRO$DBX_SAIDA" 'RF-214: anunciado como nos ciclos'
}

teste_rf_214_delta_sem_espelhar_mantem_o_arquivo_e_falha_o_item() {
  local base
  base=$(_cenario)
  _hash_remoto
  _ls "$base" /r "$(_f /r/k.txt)"
  _primeira "$base"
  printf 'local' >"$base/local/novo"
  : >"$base/meta_ausente"
  printf '{"entries":[%s,%s],"has_more":false,"cursor":"CURSOR-DELTA-2"}' \
    "$(_d /r/novo)" "$(_f /r/novo/n.txt)" >"$base/delta"
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_igual sim "$([[ -f $base/local/novo ]] && printf sim)" 'RF-214: sem --espelhar o arquivo fica'
  assert_igual local "$(cat "$base/local/novo")" 'RF-214: conteudo intacto'
  assert_contem 'arquivo no lugar da pasta' "$DBX_ERRO" 'RF-214: falha de item com motivo'
  assert_nao_contem 'apagado:' "$DBX_ERRO$DBX_SAIDA" 'RF-214: nada apagado'
}

# RF-214(a), DIV-401: a tabela mistura o retrato (memoria) com o delta; so a pasta
# observada NESTA execucao autoriza apagar o arquivo local que ocupa o lugar dela.
_pasta_so_no_retrato() { # <base> — retrato com /r/a; o local troca a pasta por arquivo
  local base=$1
  _remoto_a_b "$base"
  _primeira "$base"
  rm -rf "$base/local/a"
  printf 'local' >"$base/local/a"
}

teste_rf_214_delta_pasta_so_do_retrato_nao_confirmada_nao_apaga_o_arquivo_local() {
  local base
  base=$(_cenario)
  _pasta_so_no_retrato "$base"
  : >"$base/meta_ausente"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_contem 'varredura=incremental' "$DBX_SAIDA" 'e o delta, sem ciclos'
  assert_igual sim "$([[ -f $base/local/a && ! -d $base/local/a ]] && printf sim)" 'RF-214(a): o arquivo local fica'
  assert_igual local "$(cat "$base/local/a" 2>/dev/null)" 'RF-214(a): conteudo intacto'
  assert_contem 'arquivo no lugar da pasta' "$DBX_ERRO" 'RF-214(a): falha de item com motivo'
  assert_contem 'pastas_falhas=1' "$DBX_SAIDA" 'RF-218(a): a pasta conta como falha'
  assert_nao_contem 'apagado: a (arquivo no lugar da pasta)' "$DBX_ERRO$DBX_SAIDA" 'RF-214(a): nada apagado'
}

teste_rf_214_delta_pasta_so_do_retrato_confirmada_por_get_metadata_apaga_o_arquivo_local() {
  local base
  base=$(_cenario)
  _pasta_so_no_retrato "$base"
  : >"$base/meta_ausente"
  printf '/r/a' >"$base/meta_pasta"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual sim "$([[ -d $base/local/a && ! -L $base/local/a ]] && printf sim)" 'RF-214(a): a pasta confirmada ocupa o lugar'
  assert_contem 'apagado: a (arquivo no lugar da pasta)' "$DBX_ERRO$DBX_SAIDA" 'RF-214(a): anunciado'
}

harness_executar "$@"
