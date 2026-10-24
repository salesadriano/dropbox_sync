#!/usr/bin/env bash
# Testes do --debug do `sync` (RF-159(a)(d), RF-161, RF-158(b), RF-164; TC-DBG-17
# a TC-DBG-20 e o sentinela de cursor de TC-DBG-25): linha de decisao por item,
# linha do cursor, ordem das linhas dos auxiliares e etapas do envio em lote.
#
# O duplo de `curl` e o de paralelo_test.sh (copiado, sem rede). Controles, por
# arquivo em $base: `remoto/<caminho>` (conteudo do download), `falha/<nome>`
# (409 no envio), `listagem` (resposta do list_folder).
#
# shellcheck disable=SC2016
# Justificativa: o duplo precisa chegar sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly SENTINELA_CURSOR='CURSOR_SENTINELA_99'

_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/debugsync.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp" "$base/remoto" \
    "$base/falha" "$base/enviado"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '{"entries":[],"has_more":false,"cursor":"%s"}' "$SENTINELA_CURSOR" >"$base/listagem"
  {
    printf '#!%s\nbase=%q\n' "$BASH" "$base"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
saida='' escrever='' anterior='' url='' corpo_arquivo='' falha_http='nao'
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac
  case $arg in http*) url=$arg ;; --fail) falha_http=sim ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
codigo=200
caminho=''
re='path\\":\\"([^\\"]*)\\"'
[[ $conf =~ $re ]] && caminho=${BASH_REMATCH[1]}
nome=${caminho##*/}
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *get_space_usage*) corpo='{"used":0,"allocation":{".tag":"individual","allocated":1000000000}}' ;;
  *list_folder*) corpo=$(<"$base/listagem") ;;
  *files/download) corpo=$(<"$base/remoto$caminho") ;;
  *upload_session/start*) corpo='{"session_id":"S-1"}' ;;
  *upload_session/append_v2*) corpo='{}' ;;
  *files/upload)
    destino=$caminho
    mkdir -p "$base/enviado${destino%/*}"
    [[ -n $corpo_arquivo ]] && cp "$corpo_arquivo" "$base/enviado$destino" 2>/dev/null
    if [[ -f $base/falha/$nome ]]; then
      codigo=409; corpo='{"error_summary":"path/conflict/file/.."}'
    else
      corpo='{"name":"x","rev":"1"}'
    fi
    ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
if [[ $falha_http == sim && $codigo -ge 400 && -n $saida ]]; then
  [[ -n $escrever ]] && printf '%s' "$codigo"
  exit 22
fi
if [[ -n $saida ]]; then printf '%s' "$corpo" >"$saida" 2>/dev/null || exit 23; fi
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

# _rodar <base> <argumentos...> — sempre com --debug.
_rodar() {
  local base=$1
  shift
  DBX_SAIDA='' DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$DBX_EXEC" --debug "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _linha_de <arquivo> <trecho> — numero da primeira linha que contem o trecho
# (em LINHA; 0 se nao ha) e quantas contem (em QTD).
_linha_de() {
  local n=0 linha
  LINHA=0 QTD=0
  while IFS= read -r linha || [[ -n $linha ]]; do
    n=$((n + 1))
    if [[ $linha == *"$2"* ]]; then
      QTD=$((QTD + 1))
      ((LINHA == 0)) && LINHA=$n
    fi
  done <"$1"
}

_linhas_com() { # <arquivo> <trecho> — as linhas que contem o trecho
  local linha saida=''
  while IFS= read -r linha || [[ -n $linha ]]; do
    [[ $linha == *"$2"* ]] && saida+="$linha"$'\n'
  done <"$1"
  printf '%s' "$saida"
}

_entrada() { # <caminho> <content_hash> <tamanho>
  printf '{".tag":"file","path_display":"%s","content_hash":"%s","size":%s}' "$1" "$2" "$3"
}

readonly HASH_QUALQUER='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'

# _remoto_novos <base> — quatro arquivos remotos novos, de tamanhos 11 a 14.
_remoto_novos() {
  local base=$1 i lista='' conteudo='aaaaaaaaaa'
  mkdir -p "$base/remoto/r"
  for i in 1 2 3 4; do
    conteudo+='a'
    printf '%s' "$conteudo" >"$base/remoto/r/n$i.txt"
    lista+="${lista:+,}$(_entrada "/r/n$i.txt" "$HASH_QUALQUER" "${#conteudo}")"
  done
  printf '%s' "$lista"
}

_listar() { # <base> <entradas> — listagem com cursor sentinela
  printf '{"entries":[%s],"has_more":false,"cursor":"%s"}' "$2" "$SENTINELA_CURSOR" >"$1/listagem"
}

# ---------------------------------------------------------------------------
# RF-161: decisao por item (TC-DBG-17, TC-DBG-18) e sentinela de cursor
# ---------------------------------------------------------------------------

teste_dbg17_cada_item_tem_decisao_com_o_motivo_do_vocabulario() {
  local base lista hash
  base=$(_cenario)
  lista=$(_remoto_novos "$base")
  printf 'igual' >"$base/local/igual.txt"
  dbx_hash_verificar_dependencias >/dev/null 2>&1 || :
  dbx_hash_publicar_arquivo "$base/local/igual.txt" || _harness_falhar 'hash local do item igual'
  hash=$DBX_HASH_RESULTADO
  printf 'local' >"$base/local/mod.txt"
  printf 'sobra' >"$base/local/orfao.txt"
  printf 'remoto' >"$base/remoto/r/mod.txt"
  printf 'log' >"$base/remoto/r/x.log"
  lista+=",$(_entrada /r/igual.txt "$hash" 5),$(_entrada /r/mod.txt "$HASH_QUALQUER" 6),$(_entrada /r/x.log "$HASH_QUALQUER" 3)"
  _listar "$base" "$lista"
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --espelhar --confirmar --excluir '*.log'
  assert_igual 0 "$DBX_ESTADO" "sync termina bem; $DBX_ERRO"
  assert_contem 'debug: sync decisao=receber motivo=ausente-no-destino item=n1.txt' "$DBX_ERRO" 'novo'
  assert_contem 'debug: sync decisao=receber motivo=content-hash-diferente item=mod.txt' "$DBX_ERRO" 'diferente'
  assert_contem 'debug: sync decisao=pular motivo=content-hash-igual item=igual.txt' "$DBX_ERRO" 'igual, TC-DBG-18'
  assert_contem 'debug: sync decisao=pular motivo=filtrado item=x.log' "$DBX_ERRO" 'filtrado'
  assert_contem 'debug: sync decisao=apagar motivo=espelho-apaga-orfao item=orfao.txt' "$DBX_ERRO" 'orfao'
  _linha_de "$base/err" 'debug: sync decisao='
  assert_igual 8 "$QTD" 'uma linha por item: 4 novos, 1 diferente, 1 igual, 1 filtrado e 1 orfao'
}

teste_dbg17_sem_debug_nao_ha_linha_de_decisao() {
  local base
  base=$(_cenario)
  _listar "$base" "$(_remoto_novos "$base")"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$DBX_EXEC" sync --receber --origem /r --destino "$base/local" </dev/null >"$base/out" 2>"$base/err"
  _linha_de "$base/err" 'debug:'
  assert_igual 0 "$QTD" 'sem --debug nenhuma linha debug'
}

# ---------------------------------------------------------------------------
# RF-161(d): cursor (TC-DBG-19) e RF-164: nunca o valor (TC-DBG-25)
# ---------------------------------------------------------------------------

teste_dbg19_cursor_com_motivo_e_sem_o_valor() {
  local base
  base=$(_cenario)
  _listar "$base" "$(_remoto_novos "$base")"
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_contem 'debug: sync cursor=reconstruido motivo=sem-registro' "$DBX_ERRO" 'primeira execucao'
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --sem-cursor
  assert_contem 'debug: sync cursor=desligado motivo=desligado' "$DBX_ERRO" '--sem-cursor'
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --varredura-completa
  assert_contem 'debug: sync cursor=forcado motivo=forcada' "$DBX_ERRO" '--varredura-completa'
  _linha_de "$base/err" "$SENTINELA_CURSOR"
  assert_igual 0 "$QTD" 'TC-DBG-25: o cursor nao aparece em stderr'
  _linha_de "$base/out" "$SENTINELA_CURSOR"
  assert_igual 0 "$QTD" 'nem em stdout'
  assert_nao_contem "$SENTINELA_CURSOR" "$DBX_SAIDA$DBX_ERRO" 'nem no texto lido dos dois canais'
}

teste_dbg19_enviar_nao_tem_linha_de_cursor() {
  local base
  base=$(_cenario)
  printf 'um' >"$base/local/a.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  _linha_de "$base/err" 'debug: sync cursor='
  assert_igual 0 "$QTD" 'o cursor so existe no --receber'
}

# ---------------------------------------------------------------------------
# RF-158(b): ordem por item com --paralelo 4 (TC-DBG-20)
# ---------------------------------------------------------------------------

teste_dbg20_decisao_do_item_vem_antes_das_linhas_do_download_dele() {
  local base i decisao download
  base=$(_cenario)
  _listar "$base" "$(_remoto_novos "$base")"
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "sync termina bem; $DBX_ERRO"
  for i in 1 2 3 4; do
    _linha_de "$base/err" "decisao=receber motivo=ausente-no-destino item=n$i.txt"
    decisao=$LINHA
    assert_igual 1 "$QTD" "uma decisao para n$i"
    # O plano do download do item (linha do auxiliar) traz o destino com o nome dele.
    _linha_de "$base/err" "/local/n$i.txt bytes="
    download=$LINHA
    assert_igual 1 "$QTD" "uma linha de plano de download para n$i"
    ((decisao > 0 && download > decisao)) && decisao=ok
    assert_igual ok "$decisao" "n$i: a decisao precede as linhas do download do item"
  done
  _linha_de "$base/err" 'debug: http'
  assert_igual 1 "$((QTD > 0))" 'as linhas http dos auxiliares chegam ao operador'
}

# ---------------------------------------------------------------------------
# RF-159(a)(d): lote e resultado
# ---------------------------------------------------------------------------

teste_dbg159_lote_tem_modalidade_e_resultado_por_item() {
  local base i
  base=$(_cenario)
  for i in 1 2 3; do printf 'pequeno %s' "$i" >"$base/local/p$i.txt"; done
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  for i in 1 2 3; do
    assert_contem "debug: upload modalidade=lote arquivo=p$i.txt bytes=" "$DBX_ERRO" "p$i em lote"
    # O resultado leva o item: no lote as linhas de resultado saem juntas, depois do lote.
    assert_contem "arquivo=p$i.txt" "$(_linhas_com "$base/err" 'debug: upload resultado=')" "resultado de p$i nomeia o item"
  done
  _linha_de "$base/err" 'debug: upload resultado='
  assert_igual 3 "$QTD" 'um resultado por item do lote'
  _linha_de "$base/err" "$SENTINELA_CURSOR"
  assert_igual 0 "$QTD" 'sentinela ausente'
}

teste_dbg159_envio_unitario_tem_resultado_ok_e_falha_com_classe() {
  local base
  base=$(_cenario)
  printf 'um' >"$base/local/a.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "envio ok; $DBX_ERRO"
  assert_contem 'debug: upload resultado=ok' "$DBX_ERRO" 'ok'
  # RF-164(b), DIV-332: no sync o arquivo e nomeado relativo a raiz, nunca pelo caminho local completo.
  assert_contem 'debug: upload modalidade=simples arquivo=a.txt ' "$DBX_ERRO" 'item relativo a raiz'
  assert_nao_contem "arquivo=$base/local" "$DBX_ERRO" 'sem o caminho local completo'
  : >"$base/falha/a.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r2
  assert_contem 'debug: upload resultado=falha classe=' "$DBX_ERRO" 'falha com a classe'
}

teste_dbg17_so_no_destino_sem_espelhar_e_protegido_tambem_tem_linha() {
  local base
  base=$(_cenario)
  _listar "$base" "$(_remoto_novos "$base")"
  printf 'sobra' >"$base/local/orfao.txt"
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "sync termina bem; $DBX_ERRO"
  # RF-161(c): sem --espelhar o item so do destino fica, mas nao some da trilha (DIV-345).
  assert_contem 'debug: sync decisao=pular motivo=so-no-destino item=orfao.txt' "$DBX_ERRO" 'so no destino'
  assert_nao_contem 'decisao=apagar' "$DBX_ERRO" 'sem --espelhar nada e apagado'
}

harness_executar "$@"
