#!/usr/bin/env bash
# Validacao independente do QA da demanda `ignorar-cdpath` (defeito em producao,
# 2026-11-02): CDPATH exportado fazia `cd` relativo imprimir o destino no stdout e
# entrar em pasta homonima de OUTRA arvore.
#
# Estrategia: cada comando que desce por `cd` relativo roda com o ambiente limpo
# (linha de base) e com CDPATH hostil (`.`, outra arvore com pastas homonimas e as
# duas juntas). O desfecho (codigo de saida, chamadas de rede, arvore local e a
# arvore isca) tem de ser IDENTICO ao da linha de base, e a arvore isca nunca muda.
# O caso mais perigoso e `sync --receber --espelhar`, que apaga no LOCAL.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` precisa chegar sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="${DBX_QA_EXEC:-$DBX_HARNESS_RAIZ/bin/dbx}"

_hash_de() { # <conteudo>
  local f
  f=$(mktemp "$DBX_TESTES_TMP/h.XXXXXX")
  printf '%s' "$1" >"$f"
  bash -c ". '$DBX_HARNESS_RAIZ/lib/errors.sh'; . '$DBX_HARNESS_RAIZ/lib/hash.sh'; dbx_hash_conteudo_arquivo '$f'"
  rm -f "$f"
}

# _cenario — credencial, duplo de rede, arvore local e arvore isca homonima.
_cenario() {
  local base ha hb
  base=$(mktemp -d "$DBX_TESTES_TMP/qacd.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/tmp" \
    "$base/local/sub/deep" "$base/isca/sub/deep" "$base/isca/local/sub" "$base/dest/sub/deep"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf 'A' >"$base/local/sub/a.txt"
  printf 'B' >"$base/local/sub/deep/b.txt"
  printf 'X' >"$base/local/sub/extra.txt"
  printf 'iscaso' >"$base/isca/sub/iscaso.txt"
  printf 'iscaso2' >"$base/isca/sub/deep/iscaso2.txt"
  printf 'iscaso3' >"$base/isca/local/sub/iscaso3.txt"
    ha=$(_hash_de A)
  hb=$(_hash_de B)
  printf 'A' >"$base/local/a.txt"
  cp -a "$base/local/." "$base/dest/"
  ha=$(_hash_de A)
  hb=$ha
  printf '{"entries":[{".tag":"file","path_display":"/r/a.txt","content_hash":"%s","size":1},{".tag":"file","path_display":"/r/remoto.txt","content_hash":"%s","size":1}],"has_more":false}' \
    "$ha" "$hb" >"$base/listagem"
  printf '%s' '{".tag":"folder","name":"r","path_display":"/r"}' >"$base/metadado"
  {
    printf '#!%s\nbase=%q\nDBX_HARNESS_RAIZ=%q\n' "$BASH" "$base" "$DBX_HARNESS_RAIZ"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
saida='' escrever='' anterior='' url='' corpo_req=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) corpo_req=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
argumento=''
if [[ $conf =~ Dropbox-API-Arg:\ ([^$'\n']*) ]]; then argumento=${BASH_REMATCH[1]}
elif [[ $corpo_req == @* && -r ${corpo_req#@} ]]; then argumento=$(<"${corpo_req#@}"); fi
printf '%s\t%s\n' "$url" "$argumento" >>"$base/chamadas"
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *get_latest_cursor*) corpo='{"cursor":"C1"}' ;;
  *list_folder*) corpo=$(<"$base/listagem") ;;
  *get_metadata*) corpo=$(<"$base/metadado") ;;
  *files/download*) corpo='conteudo remoto' ;;
  *get_space_usage*) corpo='{"used":0,"allocation":{".tag":"individual","allocated":1000000000}}' ;;
  *upload_session/start*) corpo='{"session_id":"S-1"}' ;;
  *upload_session/append_v2*) corpo='{}' ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
LOTE_ECOA_V2=sim
. "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
lote_responder "$url" "${corpo_req#@}" || :
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

# _desfecho <base> <cdpath|''> <args com @B@...> — roda e imprime o desfecho normalizado.
_desfecho() {
  local base=$1 cdp=$2 arg
  shift 2
  local -a args=()
  for arg in "$@"; do args+=("${arg//@B@/$base}"); done
  (
    cd "$base" || exit 1
    env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" ${cdp:+CDPATH="${cdp//@B@/$base}"} ${cdp:+${QA_EXTRA:+"${QA_EXTRA//@B@/$base}"}} \
      bash "$DBX_EXEC" "${args[@]}" </dev/null >"$base/out" 2>"$base/err"
    printf 'estado=%s\n' "$?"
    printf -- '--chamadas\n'
    cut -f1 "$base/chamadas" 2>/dev/null | sort -u
    grep -oE '/r(/[A-Za-z0-9_.-]+)*' "$base/chamadas" 2>/dev/null | sort -u
    printf -- '--arvore\n'
    find local isca dest -printf '%p %y %s\n' | sort
    find local isca dest -type f -exec cksum {} + | sort
  ) | sed -E "s#$base#BASE#g; s#[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z#TS#g"
}

# QA_EXTRA='VAR=valor' (investigacao): outra variavel de ambiente so nas execucoes hostis.
# _matriz <rotulo> <deve conter nas chamadas ou arvore> <argumentos...>
_matriz() {
  local rotulo=$1 deve=$2 base ref got valor
  shift 2
  base=$(_cenario)
  ref=$(_desfecho "$base" '' "$@")
  assert_contem "${QA_ESTADO:-estado=0}" "$ref" "$rotulo: a linha de base conclui; diagnostico: $(<"$base/err")"
  [[ -z $deve ]] || assert_contem "$deve" "$ref" "$rotulo: a linha de base faz o esperado"
  assert_nao_contem 'iscaso' "$(sort "$base/chamadas")" "$rotulo: base nao toca a isca"
  for valor in . '@B@/isca' '@B@/isca:.' '@B@/isca:' ':@B@/isca'; do
    base=$(_cenario)
    got=$(_desfecho "$base" "$valor" "$@")
    assert_igual "$ref" "$got" "$rotulo: CDPATH=[$valor] tem o mesmo desfecho da linha de base"
    assert_nao_contem 'iscaso' "$(sort "$base/chamadas")" "$rotulo: CDPATH=[$valor] nunca le a isca"
    assert_nao_contem 'syntax' "$(<"$base/err")" "$rotulo: CDPATH=[$valor] sem erro de sintaxe"
    assert_igual $'iscaso\niscaso2\niscaso3' \
      "$(cat "$base/isca/sub/iscaso.txt"; printf '\n'; cat "$base/isca/sub/deep/iscaso2.txt"; printf '\n'; cat "$base/isca/local/sub/iscaso3.txt")" \
      "$rotulo: CDPATH=[$valor] a isca fica intacta"
  done
}

teste_upload_de_pasta() {
  _matriz upload 'sub/deep/b.txt' upload '@B@/local' /r
}
teste_upload_de_pasta_paralelo() {
  _matriz 'upload paralelo' 'sub/deep/b.txt' upload --paralelo 2 '@B@/local' /r
}
teste_download_de_pasta() {
  _matriz download '' download /r '@B@/dest'
}
teste_verificar() {
  QA_ESTADO='estado=' _matriz verificar '' verificar --enviar --origem '@B@/local' --destino /r
  QA_ESTADO='estado=' _matriz 'verificar receber' '' verificar --receber --origem /r --destino '@B@/dest'
}
teste_sync_enviar_espelhar() {
  _matriz 'sync enviar' 'sub/deep/b.txt' sync --enviar --origem '@B@/local' --destino /r --espelhar --confirmar
}
teste_sync_receber_espelhar_apaga_so_o_excedente_da_destino() {
  local base
  _matriz 'sync receber espelhar' 'dest/remoto.txt' sync --receber --origem /r --destino '@B@/dest' --espelhar --confirmar
  # prova absoluta (CDPATH hostil): extra.txt some, o que o remoto tem fica, a origem local nao e tocada
  base=$(_cenario)
  _desfecho "$base" '@B@/isca:.' sync --receber --origem /r --destino '@B@/dest' --espelhar --confirmar >/dev/null
  assert_arquivo_ausente "$base/dest/sub/extra.txt" 'o excedente local e apagado'
  assert_arquivo_ausente "$base/dest/sub/deep/b.txt" 'o excedente aninhado e apagado'
  assert_arquivo_existe "$base/dest/a.txt" 'o que o remoto tem nao e apagado'
  assert_arquivo_existe "$base/dest/remoto.txt" 'o que faltava e recebido'
  assert_arquivo_existe "$base/local/sub/extra.txt" 'a outra arvore local nao e tocada'
  assert_arquivo_existe "$base/isca/sub/iscaso.txt" 'a isca nao e tocada'
}
teste_sync_receber_espelhar_em_blocos_e_paralelo() {
  _matriz 'sync receber bloco' 'dest/remoto.txt' sync --receber --origem /r --destino '@B@/dest' --espelhar --confirmar --bloco 1
  _matriz 'sync receber paralelo' 'dest/remoto.txt' sync --receber --origem /r --destino '@B@/dest' --espelhar --confirmar --paralelo 2
}
teste_sync_enviar_em_blocos_e_paralelo() {
  _matriz 'sync enviar bloco' 'sub/deep/b.txt' sync --enviar --origem '@B@/local' --destino /r --espelhar --confirmar --bloco 1
  _matriz 'sync enviar paralelo' 'sub/deep/b.txt' sync --enviar --origem '@B@/local' --destino /r --espelhar --confirmar --paralelo 2
}

harness_executar "$@"
