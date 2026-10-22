#!/usr/bin/env bash
# Testes ponta a ponta do cursor de listagem entre execucoes (fase 7b, F-14;
# RF-110 a RF-119; TC-CUA, TC-CUR, TC-CUV, TC-CUF, TC-CUD, TC-CUM, TC-CUS,
# TC-CUL, TC-CUO; parecer do DBA, C1 a C11).
#
# O ESTADO SO ACELERA. Os casos provam as duas metades da regra: o incremental
# produz o MESMO plano da varredura completa sobre o mesmo servidor (teste
# diferencial), e todo desvio — registro invalido, `reset`, erro transitorio,
# laco, contradicao, varredura vencida — volta a varredura completa na mesma
# execucao, com codigo 0. Nenhuma exclusao local nasce do registro sem
# `path/not_found` do servidor nesta execucao.
#
# O duplo de rede e por regras (endpoint, corpo, codigo, resposta), como nas
# suites do QA: cada pedido fica em `$B/chamadas` com o corpo enviado, que e o
# que permite afirmar "nenhum list_folder recursivo" ou "continue so com cursor".
#
# shellcheck disable=SC2016
# Justificativa: o roteiro do duplo de rede chega sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly CUR_DBX="$DBX_HARNESS_RAIZ/bin/dbx"
CUR_BASH=$(command -v bash)
readonly CUR_BASH
readonly CUR_TOKEN='sl.CURSENTINELAtoken9z'
readonly CUR_REFRESH='CURSENTINELArefresh8y'
readonly CUR_SEGREDO='CURSENTINELAsegredo7x'
# Prefixo de todo cursor do duplo: nenhum byte dele pode sair do processo.
readonly CUR_SENT='CURSORSENTINELA'
readonly CUR_REV='0123456789a'
CUR_H=''
CUR_H_OUTRO=''

_cur_hashes() {
  [[ -n $CUR_H ]] && return 0
  CUR_H=$(bash -c '. "$1/lib/errors.sh"; . "$1/lib/hash.sh"; printf "%s" "conteudo remoto" | dbx_hash_conteudo_fluxo' _ "$DBX_HARNESS_RAIZ")
  CUR_H_OUTRO=$(bash -c '. "$1/lib/errors.sh"; . "$1/lib/hash.sh"; printf "%s" "conteudo local" | dbx_hash_conteudo_fluxo' _ "$DBX_HARNESS_RAIZ")
}

# _cen — credencial, duplo de rede por regras, `sleep` nulo e raiz local `$B/l`.
_cen() {
  _cur_hashes
  B=$(mktemp -d "$DBX_TESTES_TMP/cursor.XXXXXX")
  mkdir -p "$B/cfg/dbx" "$B/bin" "$B/resp" "$B/tmp" "$B/estado" "$B/l"
  chmod 700 "$B/cfg/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"%s","refresh_token":"%s","raiz_remota":"/"}' \
    "$CUR_SEGREDO" "$CUR_REFRESH" >"$B/cfg/dbx/credencial.json"
  chmod 600 "$B/cfg/dbx/credencial.json"
  : >"$B/regras"
  : >"$B/chamadas"
  CUR_N=0
  {
    printf '#!%s\nQA=%q\nTOKEN=%q\n' "$CUR_BASH" "$B" "$CUR_TOKEN"
    cat <<'FIM'
export LC_ALL=C
cat >/dev/null
o=''; w=''; ant=''; url=''; dados=''; cab=''
for a in "$@"; do
  case $ant in -o) o=$a ;; -w) w=$a ;; --data-binary) dados=${a#@} ;; -D) cab=$a ;; esac
  case $a in http*) url=$a ;; esac
  ant=$a
done
pedido=''
[[ -n $dados && -r $dados ]] && IFS= read -r -d '' pedido <"$dados"
ep=${url#https://api.dropboxapi.com/2/}
ep=${ep#https://content.dropboxapi.com/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
printf '%s\t%s\n' "$ep" "$pedido" >>"$QA/chamadas"
cod=400 corpo='{"error_summary":"sem_regra/"}' achou=nao n=0
while IFS=$'\t' read -r rep rfi rco rar rvz; do
  n=$((n + 1))
  [[ -n $rep ]] || continue
  # shellcheck disable=SC2053
  [[ $ep == $rep && $pedido == $rfi ]] || continue
  if [[ $rvz == uma ]]; then
    mkdir "$QA/usada.$n" 2>/dev/null || continue
  fi
  achou=sim cod=$rco corpo=''
  [[ -r $QA/resp/$rar ]] && IFS= read -r -d '' corpo <"$QA/resp/$rar"
  break
done <"$QA/regras"
if [[ $achou == nao ]]; then
  case $ep in
    oauth2/token) cod=200 corpo="{\"access_token\":\"$TOKEN\",\"token_type\":\"bearer\",\"expires_in\":14400}" ;;
    users/get_current_account) cod=200 corpo='{"account_id":"dbid:CONTACURSOR"}' ;;
    files/get_metadata) cod=409 corpo='{"error_summary":"path/not_found/..","error":{".tag":"path","path":{".tag":"not_found"}}}' ;;
    files/download) cod=200 corpo='conteudo remoto' ;;
    auth/token/revoke) cod=200 corpo='null' ;;
  esac
fi
case $cod in
  REDE) exit 7 ;;
esac
if [[ -n $cab ]]; then
  {
    printf 'HTTP/1.1 %s X\r\n' "$cod"
    if [[ $ep == files/download && -r $QA/resultado ]]; then
      printf 'Dropbox-API-Result: %s\r\n' "$(<"$QA/resultado")"
    fi
    printf '\r\n'
  } >"$cab"
fi
[[ -n $o ]] && printf '%s' "$corpo" >"$o"
[[ -n $w ]] && printf '%s' "$cod"
exit 0
FIM
  } >"$B/bin/curl"
  printf '#!%s\nexit 0\n' "$CUR_BASH" >"$B/bin/sleep"
  chmod +x "$B/bin/curl" "$B/bin/sleep"
}

# _regra <endpoint> <filtro_do_corpo> <codigo> <corpo> [uma]
_regra() {
  CUR_N=$((CUR_N + 1))
  printf '%s' "$4" >"$B/resp/r$CUR_N"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "r$CUR_N" "${5:-}" >>"$B/regras"
}

_regras_zerar() {
  : >"$B/regras"
  rm -rf "$B"/usada.*
  : >"$B/chamadas"
}

# _rodar <argumentos...> — sem terminal, com teto de tempo.
_rodar() {
  (
    cd "$B" || exit 99
    env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
      TMPDIR="$B/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout -k 2 120 "$CUR_BASH" "$CUR_DBX" "$@" </dev/null >"$B/out" 2>"$B/err"
  )
  ESTADO=$?
  # NUL (modo --null) vira quebra de linha: nenhum byte depois do primeiro NUL
  # escapa das assercoes.
  SAIDA=$(tr '\0' '\n' <"$B/out")
  ERRO=$(tr '\0' '\n' <"$B/err")
  return 0
}

# _arq <relativo> [hash] [id] [rev] — entrada `file` sob /r, em CUR_E.
_arq() {
  local rel=$1 hash=${2:-$CUR_H} id=${3:-} rev=${4:-$CUR_REV} baixo
  [[ -n $id ]] || id="id:${rel//[^A-Za-z0-9]/_}"
  baixo=/r/$rel
  baixo=${baixo,,}
  printf -v CUR_E '{".tag":"file","name":"%s","id":"%s","path_lower":"%s","path_display":"/r/%s","rev":"%s","size":15,"server_modified":"2026-01-01T00:00:00Z","content_hash":"%s"}' \
    "${rel##*/}" "$id" "$baixo" "$rel" "$rev" "$hash"
}

_pasta() {
  local rel=$1 baixo=/r/$1
  baixo=${baixo,,}
  printf -v CUR_E '{".tag":"folder","name":"%s","id":"id:d_%s","path_lower":"%s","path_display":"/r/%s"}' \
    "${rel##*/}" "${rel//[^A-Za-z0-9]/_}" "$baixo" "$rel"
}

_apagado() {
  local rel=$1 baixo=/r/$1
  baixo=${baixo,,}
  printf -v CUR_E '{".tag":"deleted","name":"%s","path_lower":"%s","path_display":"/r/%s"}' \
    "${rel##*/}" "$baixo" "$rel"
}

# _pagina <cursor> <has_more> [entradas...] — corpo em CUR_P.
_pagina() {
  local cursor=$1 mais=$2 lista='' e
  shift 2
  for e in "$@"; do lista+=${lista:+,}$e; done
  printf -v CUR_P '{"entries":[%s],"cursor":"%s","has_more":%s}' "$lista" "$cursor" "$mais"
}

# _servidor <cursor> [entradas...] — o `list_folder` recursivo devolve a arvore,
# precedida, como a API real, da entrada da PROPRIA pasta listada (Context7,
# `list_folder`: listar /Homework/math traz /homework/math; QA-B7B-02).
_servidor() {
  local cursor=$1
  shift
  _pagina "$cursor" false '{".tag":"folder","name":"r","id":"id:raiz","path_lower":"/r","path_display":"/r"}' "$@"
  _regra files/list_folder '*"recursive":true*' 200 "$CUR_P"
}

# _delta <de> <para> [entradas...] — o `continue` a partir de <de>.
_delta() {
  local de=$1 para=$2
  shift 2
  _pagina "$para" false "$@"
  _regra files/list_folder/continue "*\"cursor\":\"$de\"*" 200 "$CUR_P"
}

# _contar <endpoint> [filtro] — pedidos registrados.
_contar() {
  local ep linha n=0 filtro=${2:-*}
  while IFS= read -r linha; do
    ep=${linha%%$'\t'*}
    # shellcheck disable=SC2053
    [[ $ep == "$1" && ${linha#*$'\t'} == $filtro ]] && n=$((n + 1))
  done <"$B/chamadas"
  CUR_CONTAGEM=$n
}

_marcar() { : >"$B/chamadas"; }

# _registro — o unico `cursor-*` em CUR_REG (vazio sem nenhum).
_registro() {
  local -a achados=()
  local f
  CUR_REG=''
  for f in "$B/estado/dbx"/cursor-*; do
    [[ -e $f || -L $f ]] && achados+=("$f")
  done
  [[ ${#achados[@]} -le 1 ]] || _harness_falhar "mais de um cursor-*: ${#achados[@]}"
  [[ ${#achados[@]} -eq 1 ]] && CUR_REG=${achados[0]}
  return 0
}

_impressao() { # <arquivo> — conteudo e modo, para comparar byte a byte
  if [[ -f $1 ]]; then
    printf '%s ' "$(stat -c %a -- "$1")"
    sha256sum <"$1"
  else
    printf 'ausente\n'
  fi
}

_campo() { # <nome> — valor do campo na saida (chave=valor fora de terminal), em CUR_V
  local linha
  CUR_V=''
  while IFS= read -r linha; do
    [[ $linha == "$1="* ]] && { CUR_V=${linha#"$1="}; return 0; }
  done <<<"$SAIDA"
  return 1
}

_plano() { # o plano (itens e contagens), ordenado, em CUR_PLANO
  CUR_PLANO=$(grep -E '^(transferir|apagar|apenas_no_destino|a_transferir|a_apagar|identicos|filtrados[a-z_]*|recusada|recusaria)=' <<<"$SAIDA" | LC_ALL=C sort)
}

_local() { # <relativo> [conteudo]
  mkdir -p -- "$B/l/$(dirname -- "$1")"
  printf '%s' "${2:-conteudo remoto}" >"$B/l/$1"
}

# _campos_do_registro <arquivo> — campos NUL do registro em CUR_CAMPOS.
_campos_do_registro() {
  CUR_CAMPOS=()
  mapfile -d '' -t CUR_CAMPOS <"$1"
}

# _reescrever <arquivo> <campos...> — grava os campos e um rodape VALIDO (o
# registro forjado passa no SHA-256: so a regra do campo pode reprova-lo).
_reescrever() {
  local arquivo=$1 resumo
  shift
  printf '%s\0' "$@" >"$arquivo"
  resumo=$(sha256sum <"$arquivo")
  printf 'fim\0%s\0' "${resumo%% *}" >>"$arquivo"
}

# _regravar_cabecalho <indice> <valor> — troca um campo do cabecalho do
# registro corrente, mantendo corpo e rodape validos.
_regravar_cabecalho() {
  _registro
  _campos_do_registro "$CUR_REG"
  local -a c=("${CUR_CAMPOS[@]}")
  unset 'c[${#c[@]}-1]' 'c[${#c[@]}-1]'
  c=("${c[@]}")
  c[$1]=$2
  _reescrever "$CUR_REG" "${c[@]}"
}

# Arvore base: tres arquivos na raiz e uma pasta com dois.
_arvore_base() {
  local -a ent=()
  _pasta p && ent+=("$CUR_E")
  _arq a.txt && ent+=("$CUR_E")
  _arq b.txt && ent+=("$CUR_E")
  _arq c.txt && ent+=("$CUR_E")
  _arq p/x.txt && ent+=("$CUR_E")
  _arq p/y.txt && ent+=("$CUR_E")
  CUR_BASE=("${ent[@]}")
}

# _primeira — primeira execucao real sobre a arvore base, cursor C1.
_primeira() {
  _cen
  _arvore_base
  _servidor "${CUR_SENT}C1" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "primeira execucao: $ERRO"
  _registro
  [[ -n $CUR_REG ]] || _harness_falhar 'a primeira execucao bem-sucedida deveria gravar cursor-*'
}

# ---------------------------------------------------------------------------
# RF-110, RF-111: alcance, registro, chave
# ---------------------------------------------------------------------------

teste_cua04_cur01_primeira_execucao_completa_grava_registro_0600() {
  _primeira
  _campo varredura; assert_igual completa "$CUR_V" 'primeira: varredura completa'
  _campo cursor_motivo; assert_igual sem-registro "$CUR_V" 'motivo sem-registro'
  _campo cursor_mudancas; assert_igual 0 "$CUR_V" 'mudancas 0 na completa'
  _campo cursor_confirmadas; assert_igual 0 "$CUR_V" 'confirmadas 0'
  assert_igual 600 "$(stat -c %a -- "$CUR_REG")" 'registro 0600'
  assert_igual 700 "$(stat -c %a -- "$B/estado/dbx")" 'diretorio 0700'
  _campos_do_registro "$CUR_REG"
  assert_igual dbx-cursor "${CUR_CAMPOS[0]}" 'magia'
  assert_igual 1 "${CUR_CAMPOS[1]}" 'versao do namespace'
  assert_igual dbid:CONTACURSOR "${CUR_CAMPOS[3]}" 'account_id no cabecalho (C2)'
  assert_igual "${CUR_SENT}C1" "${CUR_CAMPOS[7]}" 'cursor da ultima pagina'
  assert_igual 0 "${CUR_CAMPOS[9]}" 'incrementais zerados'
  # 5 arquivos + 1 pasta, sem filtro.
  assert_igual 6 "${CUR_CAMPOS[11]}" 'retrato com arquivos e pastas'
  assert_igual fim "${CUR_CAMPOS[${#CUR_CAMPOS[@]} - 2]}" 'rodape'
  local conteudo
  conteudo=$(tr '\0' '\n' <"$CUR_REG")
  assert_nao_contem "$CUR_TOKEN" "$conteudo" 'sem token (TC-CUR-09)'
  assert_nao_contem "$CUR_REFRESH" "$conteudo" 'sem refresh token'
  assert_nao_contem "$CUR_SEGREDO" "$conteudo" 'sem app secret'
  assert_nao_contem "$CUR_SENT" "$SAIDA$ERRO" 'cursor fora da saida'
  local -a temporarios=("$B/estado/dbx"/.cursor.*)
  [[ -e ${temporarios[0]} ]] && _harness_falhar 'temporario .cursor.* residual'
  return 0
}

teste_cuv02_cul11_delta_vazio_sem_listagem_recursiva_e_continue_so_com_cursor() {
  _primeira
  _regras_zerar
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2"
  _marcar
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "incremental: $ERRO"
  _campo varredura; assert_igual incremental "$CUR_V" 'delta vazio: incremental'
  _campo cursor_motivo && _harness_falhar 'cursor_motivo so na completa'
  _contar files/list_folder
  assert_igual 0 "$CUR_CONTAGEM" 'nenhum list_folder recursivo (TC-CUV-02)'
  _contar files/list_folder/continue "{\"cursor\":\"${CUR_SENT}C1\"}"
  assert_igual 1 "$CUR_CONTAGEM" 'o continue leva SO o cursor, sem limit (DIV-214, TC-CUL-11)'
  _contar files/download
  assert_igual 0 "$CUR_CONTAGEM" 'tudo identico: nada baixado'
  _campo identicos; assert_igual 5 "$CUR_V" 'mesmo plano: 5 identicos'
  _registro
  _campos_do_registro "$CUR_REG"
  assert_igual "${CUR_SENT}C2" "${CUR_CAMPOS[7]}" 'grava o cursor da ultima pagina do delta'
  assert_igual 1 "${CUR_CAMPOS[9]}" 'incrementais = 1'
}

teste_cul11_varredura_completa_de_duas_paginas_continue_sem_limit() {
  local -a ent=()
  _cen
  _arq a.txt && ent+=("$CUR_E")
  _pagina "${CUR_SENT}P1" true "${ent[@]}"
  _regra files/list_folder '*"recursive":true*' 200 "$CUR_P"
  ent=()
  _arq b.txt && ent+=("$CUR_E")
  _delta "${CUR_SENT}P1" "${CUR_SENT}C1" "${ent[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "duas paginas: $ERRO"
  _contar files/list_folder '{"limit":100,*'
  assert_igual 1 "$CUR_CONTAGEM" 'o list_folder inicial leva limit (RNF-23)'
  _contar files/list_folder/continue "{\"cursor\":\"${CUR_SENT}P1\"}"
  assert_igual 1 "$CUR_CONTAGEM" 'o continue da varredura leva so o cursor'
  _registro
  _campos_do_registro "$CUR_REG"
  assert_igual "${CUR_SENT}C1" "${CUR_CAMPOS[7]}" 'cursor da ultima pagina'
  assert_igual 2 "${CUR_CAMPOS[11]}" 'as duas paginas no retrato'
}

teste_cuv07_delta_de_varias_paginas() {
  _primeira
  _regras_zerar
  local -a ent=()
  _arq novo1.txt && ent+=("$CUR_E")
  _pagina "${CUR_SENT}D1" true "${ent[@]}"
  _regra files/list_folder/continue "*\"cursor\":\"${CUR_SENT}C1\"*" 200 "$CUR_P"
  ent=()
  _arq novo2.txt && ent+=("$CUR_E")
  _delta "${CUR_SENT}D1" "${CUR_SENT}C2" "${ent[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "delta paginado: $ERRO"
  _campo varredura; assert_igual incremental "$CUR_V" 'incremental'
  _campo cursor_mudancas; assert_igual 2 "$CUR_V" 'duas mudancas'
  assert_arquivo_existe "$B/l/novo1.txt" 'pagina 1 aplicada'
  assert_arquivo_existe "$B/l/novo2.txt" 'pagina 2 aplicada'
  _registro
  _campos_do_registro "$CUR_REG"
  assert_igual "${CUR_SENT}C2" "${CUR_CAMPOS[7]}" 'cursor da ULTIMA pagina'
}

# ---------------------------------------------------------------------------
# RF-112: equivalencia com a varredura completa (teste diferencial)
# ---------------------------------------------------------------------------

# _diferencial <nome> <espelhar> — com a arvore base sincronizada, o servidor
# passa a CUR_EST2 (varredura completa) e CUR_DLT (delta a partir de C1). O
# plano da simulacao com cursor e o da simulacao `--sem-cursor` sao iguais.
_diferencial() {
  local nome=$1 espelhar=${2:-sim} com_cursor sem_cursor
  local -a extra=()
  [[ $espelhar == 'sim' ]] && extra=(--espelhar)
  _regras_zerar
  _servidor "${CUR_SENT}C9" ${CUR_EST2[@]+"${CUR_EST2[@]}"}
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" ${CUR_DLT[@]+"${CUR_DLT[@]}"}
  _rodar --dry-run sync --receber --origem /r --destino "$B/l" ${extra[@]+"${extra[@]}"} ${CUR_FILTROS[@]+"${CUR_FILTROS[@]}"}
  assert_igual 0 "$ESTADO" "$nome com cursor: $ERRO"
  _campo varredura; assert_igual incremental "$CUR_V" "$nome: a execucao com cursor foi incremental"
  _plano
  com_cursor=$CUR_PLANO
  _rodar --dry-run sync --receber --origem /r --destino "$B/l" --sem-cursor ${extra[@]+"${extra[@]}"} ${CUR_FILTROS[@]+"${CUR_FILTROS[@]}"}
  assert_igual 0 "$ESTADO" "$nome sem cursor: $ERRO"
  _campo cursor_motivo; assert_igual desligado "$CUR_V" "$nome: --sem-cursor"
  _plano
  sem_cursor=$CUR_PLANO
  assert_igual "$sem_cursor" "$com_cursor" "$nome: plano do cursor = plano da varredura completa (RF-112(d))"
  CUR_PLANO_COMUM=$com_cursor
}

teste_cuv03_diferencial_dez_cenarios() {
  local -a e2=() d=()
  _primeira
  # 1. novo
  CUR_EST2=("${CUR_BASE[@]}"); _arq novo.txt "$CUR_H_OUTRO" && CUR_EST2+=("$CUR_E"); CUR_DLT=("$CUR_E")
  _diferencial novo
  assert_contem 'transferir=novo.txt' "$CUR_PLANO_COMUM" 'novo: transferir'
  # 2. modificado
  e2=() d=()
  _pasta p && e2+=("$CUR_E")
  _arq a.txt "$CUR_H_OUTRO" '' 'bbbbbbbbbbb' && e2+=("$CUR_E") && d+=("$CUR_E")
  _arq b.txt && e2+=("$CUR_E"); _arq c.txt && e2+=("$CUR_E")
  _arq p/x.txt && e2+=("$CUR_E"); _arq p/y.txt && e2+=("$CUR_E")
  CUR_EST2=("${e2[@]}") CUR_DLT=("${d[@]}")
  _diferencial modificado
  assert_contem 'transferir=a.txt' "$CUR_PLANO_COMUM" 'modificado: transferir'
  # 3. apagado (confirmado por not_found)
  e2=() d=()
  _pasta p && e2+=("$CUR_E"); _arq a.txt && e2+=("$CUR_E"); _arq c.txt && e2+=("$CUR_E")
  _arq p/x.txt && e2+=("$CUR_E"); _arq p/y.txt && e2+=("$CUR_E")
  _apagado b.txt && d+=("$CUR_E")
  CUR_EST2=("${e2[@]}") CUR_DLT=("${d[@]}")
  _diferencial apagado
  assert_contem 'apagar=b.txt' "$CUR_PLANO_COMUM" 'apagado: apagar com --espelhar'
  _diferencial apagado_sem_espelhar nao
  assert_contem 'apenas_no_destino=b.txt' "$CUR_PLANO_COMUM" 'apagado sem --espelhar: apenas_no_destino (DIV-218)'
  # 4. renomeado na raiz
  e2=() d=()
  _pasta p && e2+=("$CUR_E"); _arq a.txt && e2+=("$CUR_E"); _arq c.txt && e2+=("$CUR_E")
  _arq p/x.txt && e2+=("$CUR_E"); _arq p/y.txt && e2+=("$CUR_E")
  _arq b2.txt '' 'id:b_txt' && e2+=("$CUR_E")
  _apagado b.txt && d+=("$CUR_E"); _arq b2.txt '' 'id:b_txt' && d+=("$CUR_E")
  CUR_EST2=("${e2[@]}") CUR_DLT=("${d[@]}")
  _diferencial renomeado
  assert_contem 'transferir=b2.txt' "$CUR_PLANO_COMUM" 'renomeado: o novo e baixado'
  assert_contem 'apagar=b.txt' "$CUR_PLANO_COMUM" 'renomeado: o antigo sai com --espelhar'
  # 5. movido para subpasta (o `file` novo antes do `deleted` antigo)
  e2=() d=()
  _pasta p && e2+=("$CUR_E"); _arq a.txt && e2+=("$CUR_E"); _arq b.txt && e2+=("$CUR_E")
  _arq p/x.txt && e2+=("$CUR_E"); _arq p/y.txt && e2+=("$CUR_E"); _arq p/c.txt '' 'id:c_txt' && e2+=("$CUR_E")
  _arq p/c.txt '' 'id:c_txt' && d+=("$CUR_E"); _apagado c.txt && d+=("$CUR_E")
  CUR_EST2=("${e2[@]}") CUR_DLT=("${d[@]}")
  _diferencial movido
  # 6. pasta apagada com descendentes
  e2=() d=()
  _arq a.txt && e2+=("$CUR_E"); _arq b.txt && e2+=("$CUR_E"); _arq c.txt && e2+=("$CUR_E")
  _apagado p && d+=("$CUR_E")
  CUR_EST2=("${e2[@]}") CUR_DLT=("${d[@]}")
  _diferencial pasta_apagada
  assert_contem 'apagar=p/x.txt' "$CUR_PLANO_COMUM" 'pasta apagada: descendentes'
  # 7. apagado e recriado no mesmo caminho (vale a `file`)
  e2=() d=()
  _pasta p && e2+=("$CUR_E"); _arq b.txt && e2+=("$CUR_E"); _arq c.txt && e2+=("$CUR_E")
  _arq p/x.txt && e2+=("$CUR_E"); _arq p/y.txt && e2+=("$CUR_E")
  _arq a.txt "$CUR_H_OUTRO" 'id:a_novo' 'ccccccccccc' && e2+=("$CUR_E")
  _apagado a.txt && d+=("$CUR_E"); _arq a.txt "$CUR_H_OUTRO" 'id:a_novo' 'ccccccccccc' && d+=("$CUR_E")
  CUR_EST2=("${e2[@]}") CUR_DLT=("${d[@]}")
  _diferencial recriado
  assert_contem 'transferir=a.txt' "$CUR_PLANO_COMUM" 'recriado: transferir'
  assert_nao_contem 'apagar=a.txt' "$CUR_PLANO_COMUM" 'recriado: nunca apagado'
  # 8. mudanca so de caixa (o servico nao a relata no continue)
  e2=() d=()
  _pasta p && e2+=("$CUR_E"); _arq A.txt '' 'id:a_txt' && e2+=("$CUR_E"); _arq b.txt && e2+=("$CUR_E")
  _arq c.txt && e2+=("$CUR_E"); _arq p/x.txt && e2+=("$CUR_E"); _arq p/y.txt && e2+=("$CUR_E")
  CUR_EST2=("${e2[@]}") CUR_DLT=()
  _diferencial caixa
  assert_igual 0 "$(grep -c '^apagar=' <<<"$CUR_PLANO_COMUM")" 'caixa: nenhuma exclusao (RF-54)'
  # 9. muitos
  e2=() d=()
  _pasta p && e2+=("$CUR_E"); _arq a.txt "$CUR_H_OUTRO" '' 'ddddddddddd' && e2+=("$CUR_E") && d+=("$CUR_E")
  _arq p/x.txt && e2+=("$CUR_E")
  _arq n1.txt && e2+=("$CUR_E") && d+=("$CUR_E"); _arq n2.txt && e2+=("$CUR_E") && d+=("$CUR_E")
  _apagado b.txt && d+=("$CUR_E"); _apagado c.txt && d+=("$CUR_E"); _apagado p/y.txt && d+=("$CUR_E")
  CUR_EST2=("${e2[@]}") CUR_DLT=("${d[@]}")
  _diferencial muitos
  # 10. nenhum
  CUR_EST2=("${CUR_BASE[@]}") CUR_DLT=()
  _diferencial nenhum
  assert_contem 'identicos=5' "$CUR_PLANO_COMUM" 'nenhum: tudo identico'
}

teste_cuv04_05_lado_local_igual_a_varredura_completa() {
  _primeira
  # Local editado (remoto inalterado) e local apagado: o cursor nao sabe nada
  # do lado local, e o plano e o da completa.
  printf '%s' 'editado a mao' >"$B/l/a.txt"
  rm -f -- "$B/l/b.txt"
  CUR_EST2=("${CUR_BASE[@]}") CUR_DLT=()
  _diferencial local_mudou
  assert_contem 'transferir=a.txt' "$CUR_PLANO_COMUM" 'local editado e sobrescrito pela origem'
  assert_contem 'transferir=b.txt' "$CUR_PLANO_COMUM" 'local apagado e baixado de novo'
}

teste_cuv11_cul10_filtros_sobre_o_mapa_reconstruido() {
  local -a d=()
  _primeira
  _arq p/novo.log && d+=("$CUR_E"); CUR_EST2=("${CUR_BASE[@]}" "$CUR_E")
  _arq z.log && d+=("$CUR_E"); CUR_EST2+=("$CUR_E")
  CUR_DLT=("${d[@]}")
  CUR_FILTROS=(--excluir '*.log' --excluir p)
  _diferencial filtro_excluir
  assert_contem 'filtrados' "$CUR_PLANO_COMUM" 'contadores de filtrados presentes'
  CUR_FILTROS=(--incluir '*.log')
  _diferencial filtro_incluir
  CUR_FILTROS=(--tamanho-max 10)
  _diferencial filtro_tamanho nao
  CUR_FILTROS=()
}

teste_cuv12_pasta_excluida_pelo_filtro_nunca_apagada_com_cursor() {
  local -a d=()
  _primeira
  _apagado p && d+=("$CUR_E")
  _regras_zerar
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "${d[@]}"
  _rodar sync --receber --origem /r --destino "$B/l" --espelhar --excluir p
  assert_igual 0 "$ESTADO" "filtro com cursor: $ERRO"
  assert_arquivo_existe "$B/l/p/x.txt" 'pasta excluida pelo filtro intacta (RF-80)'
  _contar files/get_metadata
  assert_igual 0 "$CUR_CONTAGEM" 'item filtrado nem chega a candidato'
}

teste_cuv09_delta_incoerente_volta_a_varredura_completa_sem_10() {
  local caso
  for caso in sem_id sem_rev fora_da_raiz ponto_ponto id_repetido; do
    _primeira
    _regras_zerar
    case $caso in
      sem_id) CUR_E='{".tag":"file","name":"n.txt","path_lower":"/r/n.txt","path_display":"/r/n.txt","rev":"0123456789a","size":1,"content_hash":"'$CUR_H'"}' ;;
      sem_rev) CUR_E='{".tag":"file","name":"n.txt","id":"id:n","path_lower":"/r/n.txt","path_display":"/r/n.txt","size":1,"content_hash":"'$CUR_H'"}' ;;
      fora_da_raiz) CUR_E='{".tag":"file","name":"n.txt","id":"id:n","path_lower":"/outra/n.txt","path_display":"/outra/n.txt","rev":"0123456789a","size":1,"content_hash":"'$CUR_H'"}' ;;
      ponto_ponto) CUR_E='{".tag":"file","name":"n.txt","id":"id:n","path_lower":"/r/../n.txt","path_display":"/r/../n.txt","rev":"0123456789a","size":1,"content_hash":"'$CUR_H'"}' ;;
      id_repetido) _arq n.txt "$CUR_H" 'id:a_txt' ;;
    esac
    _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "$CUR_E"
    _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
    _rodar sync --receber --origem /r --destino "$B/l"
    assert_igual 0 "$ESTADO" "$caso: nunca 10 por estado: $ERRO"
    _campo varredura; assert_igual completa "$CUR_V" "$caso: varredura completa"
    _campo cursor_motivo; assert_igual descartado "$CUR_V" "$caso: descartado"
    assert_arquivo_ausente "$B/n.txt" "$caso: nada escrito fora da raiz (TC-CUV-13)"
    assert_arquivo_ausente "$B/l/n.txt" "$caso: entrada incoerente nao baixada"
  done
}

teste_cuv10_continue_malformado_volta_a_varredura_completa() {
  _primeira
  _regras_zerar
  _regra files/list_folder/continue '*' 200 '{"entries":[{".tag":"file"'
  _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "malformado: $ERRO"
  _campo cursor_motivo; assert_igual descartado "$CUR_V" 'malformado: descartado'
}

# ---------------------------------------------------------------------------
# RF-113: invalidacao e rede de seguranca
# ---------------------------------------------------------------------------

teste_cuf01_cuf12_reset_varredura_completa_zero_e_memoria_intacta() {
  _primeira
  local memorias=("$B/estado/dbx"/memoria-*)
  assert_arquivo_existe "${memorias[0]}" 'memoria-* gravada na primeira'
  _regras_zerar
  _regra files/list_folder/continue '*' 409 '{"error_summary":"reset/...","error":{".tag":"reset"}}'
  _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "reset nunca e 14 (RF-113(c)): $ERRO"
  _campo varredura; assert_igual completa "$CUR_V" 'reset: completa'
  _campo cursor_motivo; assert_igual reset "$CUR_V" 'motivo reset'
  assert_contem 'reset' "$ERRO" 'uma linha de aviso'
  assert_igual 1 "$(grep -c 'reset' <<<"$ERRO")" 'uma linha so'
  _campo memoria && _harness_falhar "reset nao descarta memoria-*: $CUR_V"
  assert_arquivo_existe "${memorias[0]}" 'memoria-* intacta (RF-43, C9)'
  _registro
  _campos_do_registro "$CUR_REG"
  assert_igual "${CUR_SENT}C3" "${CUR_CAMPOS[7]}" 'regravado pela varredura completa'
}

teste_cuf02_outro_409_e_4xx_voltam_a_varredura_completa() {
  local codigo
  for codigo in 409 400; do
    _primeira
    _regras_zerar
    _regra files/list_folder/continue '*' "$codigo" '{"error_summary":"path/not_found/.."}'
    _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
    _rodar sync --receber --origem /r --destino "$B/l"
    assert_igual 0 "$ESTADO" "$codigo: completa, nao falha: $ERRO"
    _campo cursor_motivo; assert_igual descartado "$CUR_V" "$codigo: descartado"
  done
}

teste_cuf03_04_transitorio_no_continue_e_completa_que_tambem_falha() {
  _primeira
  _regras_zerar
  _regra files/list_folder/continue '*' 503 '{"error_summary":"internal_error/"}'
  _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "5xx esgotado no continue: completa: $ERRO"
  _campo cursor_motivo; assert_igual transitorio "$CUR_V" 'motivo transitorio'
  # A completa tambem falha: erro de hoje, sem laco, e nenhum descarte toca
  # a memoria-* (RF-43, C9): ela fica byte a byte igual.
  local -a memorias=("$B/estado/dbx"/memoria-*)
  local memoria_antes
  memoria_antes=$(_impressao "${memorias[0]}")
  _regras_zerar
  _regra files/list_folder/continue '*' 503 '{"error_summary":"internal_error/"}'
  _regra files/list_folder '*' 503 '{"error_summary":"internal_error/"}'
  _marcar
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_diferente 0 "$ESTADO" 'a completa tambem falhou: a execucao falha pela rede'
  assert_diferente 14 "$ESTADO" 'nao e 14'
  _contar files/list_folder
  assert_igual 2 "$CUR_CONTAGEM" 'uma varredura completa (2 tentativas), sem laco'
  assert_igual "$memoria_antes" "$(_impressao "${memorias[0]}")" 'o descarte do cursor nao toca a memoria-*'
}

teste_cuf05_401_no_continue_mantem_a_classe_5() {
  _primeira
  _regras_zerar
  _regra files/list_folder/continue '*' 401 '{"error_summary":"invalid_access_token/"}'
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual "$(dbx_errors_codigo_saida autenticacao)" "$ESTADO" "401: classe 5: $ERRO"
}

teste_cuf06_cursor_repetido_e_laco_abandonam_o_incremental() {
  _primeira
  _regras_zerar
  _pagina "${CUR_SENT}C1" true
  _regra files/list_folder/continue '*' 200 "$CUR_P"
  _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "cursor repetido: $ERRO"
  _campo cursor_motivo; assert_igual descartado "$CUR_V" 'laco: descartado'
  _contar files/list_folder/continue
  assert_igual 1 "$CUR_CONTAGEM" 'uma pagina so, sem laco'
}

teste_cuf07_08_varredura_periodica_obrigatoria() {
  local agora
  printf -v agora '%(%s)T' -1
  # 7 dias e 1 minuto: completa.
  _primeira
  _regravar_cabecalho 8 "$((agora - 604800 - 60))"
  _regras_zerar
  _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  _campo cursor_motivo; assert_igual periodica "$CUR_V" '7 dias e 1 minuto: periodica'
  _contar files/list_folder/continue
  assert_igual 0 "$CUR_CONTAGEM" 'periodica: nenhum continue'
  _registro
  _campos_do_registro "$CUR_REG"
  assert_igual 0 "${CUR_CAMPOS[9]}" 'regravado com incrementais zerados'
  # 6 dias e 23 h: incremental.
  _primeira
  _regravar_cabecalho 8 "$((agora - 604800 + 3600))"
  _regras_zerar
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2"
  _rodar sync --receber --origem /r --destino "$B/l"
  _campo varredura; assert_igual incremental "$CUR_V" '6 dias e 23 h: incremental'
  # Relogio voltou: idade negativa acima de 5 min.
  _primeira
  _regravar_cabecalho 8 "$((agora + 600))"
  _regras_zerar
  _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  _campo cursor_motivo; assert_igual periodica "$CUR_V" 'idade negativa: periodica'
  # 100 incrementais: completa; 99: incremental e vira 100.
  _primeira
  _regravar_cabecalho 9 100
  _regras_zerar
  _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  _campo cursor_motivo; assert_igual periodica "$CUR_V" '100 incrementais: periodica'
  _primeira
  _regravar_cabecalho 9 99
  _regras_zerar
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2"
  _rodar sync --receber --origem /r --destino "$B/l"
  _campo varredura; assert_igual incremental "$CUR_V" '99: incremental'
  _registro
  _campos_do_registro "$CUR_REG"
  assert_igual 100 "${CUR_CAMPOS[9]}" '99 vira 100'
}

teste_cuf09_cuo01_02_05_forcada_e_desligado() {
  local antes opcao
  for opcao in --varredura-completa --full-scan; do
    _primeira
    _regras_zerar
    _servidor "${CUR_SENT}C5" "${CUR_BASE[@]}"
    _rodar sync --receber --origem /r --destino "$B/l" "$opcao"
    assert_igual 0 "$ESTADO" "$opcao: $ERRO"
    _campo cursor_motivo; assert_igual forcada "$CUR_V" "$opcao: forcada"
    _contar files/list_folder/continue
    assert_igual 0 "$CUR_CONTAGEM" "$opcao: nao le o registro"
    _registro
    _campos_do_registro "$CUR_REG"
    assert_igual "${CUR_SENT}C5" "${CUR_CAMPOS[7]}" "$opcao: regrava"
  done
  for opcao in --sem-cursor --no-cursor; do
    _primeira
    antes=$(_impressao "$CUR_REG")
    _regras_zerar
    _servidor "${CUR_SENT}C5" "${CUR_BASE[@]}"
    _rodar sync --receber --origem /r --destino "$B/l" "$opcao"
    assert_igual 0 "$ESTADO" "$opcao: $ERRO"
    _campo cursor_motivo; assert_igual desligado "$CUR_V" "$opcao: desligado"
    assert_igual "$antes" "$(_impressao "$CUR_REG")" "$opcao: registro byte a byte igual"
    _contar files/list_folder/continue
    assert_igual 0 "$CUR_CONTAGEM" "$opcao: nao le"
  done
  # --sem-cursor sem registro nao cria nenhum.
  _cen
  _arvore_base
  _servidor "${CUR_SENT}C1" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l" --sem-cursor
  _registro
  assert_igual '' "$CUR_REG" '--sem-cursor nao cria cursor-*'
}

teste_cuo03_04_opcoes_invalidas_saem_2_antes_do_estado() {
  local uso
  uso=$(dbx_errors_codigo_saida uso_invalido)
  _cen
  _rodar sync --receber --origem /r --destino "$B/l" --sem-cursor --varredura-completa
  assert_igual "$uso" "$ESTADO" 'as duas juntas: 2'
  _rodar sync --enviar --origem "$B/l" --destino /r --sem-cursor
  assert_igual "$uso" "$ESTADO" '--sem-cursor com --enviar: 2'
  assert_contem 'so valem com --receber' "$ERRO" 'mensagem'
  _rodar sync --enviar --origem "$B/l" --destino /r --full-scan
  assert_igual "$uso" "$ESTADO" '--full-scan com --enviar: 2'
  _rodar download /r "$B/l2" --sem-cursor
  assert_igual "$uso" "$ESTADO" 'download nao aceita (DIV-205)'
  _rodar list /r --varredura-completa
  assert_igual "$uso" "$ESTADO" 'list nao aceita'
  [[ -e $B/estado/dbx ]] && _harness_falhar 'nenhum estado lido nem criado antes da recusa'
  _contar files/list_folder
  assert_igual 0 "$CUR_CONTAGEM" 'nenhuma chamada'
}

# ---------------------------------------------------------------------------
# RF-114, RF-115, RF-116: exclusao so com confirmacao no servidor
# ---------------------------------------------------------------------------

teste_cud01_02_deleted_confirmado_apaga_so_com_espelhar() {
  local -a d=()
  _primeira
  _apagado b.txt && d+=("$CUR_E")
  _regras_zerar
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "${d[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "sem espelhar: $ERRO"
  assert_arquivo_existe "$B/l/b.txt" 'sem --espelhar: nada apagado'
  assert_contem 'apenas_no_destino=b.txt' "$SAIDA" 'apenas_no_destino'
  _contar files/get_metadata '*"path":"/r/b.txt"*'
  assert_igual 1 "$CUR_CONTAGEM" 'confirmado tambem sem --espelhar (DIV-218)'
  _primeira
  _regras_zerar
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "${d[@]}"
  _rodar sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "com espelhar: $ERRO"
  assert_arquivo_ausente "$B/l/b.txt" 'confirmado por not_found: apagado'
  _campo cursor_confirmadas; assert_igual 1 "$CUR_V" 'uma confirmada'
  assert_contem 'apagar=b.txt' "$SAIDA" 'anunciado no plano antes (RF-47)'
}

teste_cud03_04_contradicao_nunca_apaga_e_volta_a_completa() {
  local caso id_resposta
  for caso in existe recriado; do
    _primeira
    _regras_zerar
    _apagado b.txt
    _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "$CUR_E"
    id_resposta='id:b_txt'
    [[ $caso == 'recriado' ]] && id_resposta='id:outro'
    _regra files/get_metadata '*"path":"/r/b.txt"*' 200 \
      "{\".tag\":\"file\",\"id\":\"$id_resposta\",\"path_display\":\"/r/b.txt\",\"rev\":\"0123456789a\"}"
    _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
    _rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 0 "$ESTADO" "$caso: $ERRO"
    assert_arquivo_existe "$B/l/b.txt" "$caso: contradicao nunca apaga"
    _campo varredura; assert_igual completa "$CUR_V" "$caso: completa"
    _campo cursor_motivo; assert_igual contradicao "$CUR_V" "$caso: contradicao"
    assert_nao_contem 'apagar=b.txt' "$SAIDA" "$caso: o plano emitido e o da completa"
    _contar files/list_folder
    assert_igual 1 "$CUR_CONTAGEM" "$caso: varredura completa na mesma execucao"
  done
}

teste_cud05_cus02_retrato_que_omite_arquivo_nao_apaga() {
  # O retrato da primeira nao tinha `extra.txt`; o servidor o tem e o delta
  # nao o relata (servico omitiu, ou retrato velho). Local tem `extra.txt`.
  _primeira
  _local extra.txt
  _regras_zerar
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2"
  _arq extra.txt
  _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}" "$CUR_E"
  _regra files/get_metadata '*"path":"/r/extra.txt"*' 200 '{".tag":"file","id":"id:extra_txt"}'
  _rodar sync --receber --origem /r --destino "$B/l" --espelhar --permitir-origem-vazia --confirmar
  assert_igual 0 "$ESTADO" "retrato omisso: $ERRO"
  assert_arquivo_existe "$B/l/extra.txt" 'ausencia no retrato nunca apaga sem confirmacao (DIV-m)'
  _campo cursor_motivo; assert_igual contradicao "$CUR_V" 'contradicao'
  assert_contem 'identicos=6' "$SAIDA" 'a completa ve o arquivo'
}

teste_cud06_falha_na_confirmacao_falha_sem_plano_e_sem_escrita() {
  local antes
  _primeira
  antes=$(_impressao "$CUR_REG")
  _regras_zerar
  _apagado b.txt
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "$CUR_E"
  _regra files/get_metadata '*' 503 '{"error_summary":"internal_error/"}'
  _rodar sync --receber --origem /r --destino "$B/l" --espelhar
  assert_diferente 0 "$ESTADO" 'falha da enumeracao'
  assert_diferente 14 "$ESTADO" 'nao e 14'
  assert_nao_contem 'a_transferir' "$SAIDA" 'nenhum plano emitido'
  assert_arquivo_existe "$B/l/b.txt" 'nada apagado'
  assert_igual "$antes" "$(_impressao "$CUR_REG")" 'registro intacto (TC-CUD-06)'
}

teste_cud08_pasta_apagada_uma_confirmacao_cobre_os_descendentes() {
  _primeira
  _regras_zerar
  _apagado p
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "$CUR_E"
  _rodar sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "pasta apagada: $ERRO"
  _contar files/get_metadata
  assert_igual 1 "$CUR_CONTAGEM" 'uma confirmacao por raiz'
  _contar files/get_metadata '*"path":"/r/p"*'
  assert_igual 1 "$CUR_CONTAGEM" 'a raiz apagada e a confirmada'
  assert_arquivo_ausente "$B/l/p/x.txt" 'descendente apagado'
  assert_arquivo_ausente "$B/l/p/y.txt" 'descendente apagado'
}

teste_cud09_cuf10_cinquenta_confirmacoes_e_cinquenta_e_uma() {
  local total i
  local -a ent=() d=()
  for total in 50 51; do
    _cen
    ent=() d=()
    for ((i = 1; i <= total; i++)); do
      _arq "f$i.txt" && ent+=("$CUR_E")
      _apagado "f$i.txt" && d+=("$CUR_E")
    done
    _arq fica.txt && ent+=("$CUR_E")
    _servidor "${CUR_SENT}C1" "${ent[@]}"
    _rodar sync --receber --origem /r --destino "$B/l"
    assert_igual 0 "$ESTADO" "$total, primeira: $ERRO"
    _regras_zerar
    _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "${d[@]}"
    _arq fica.txt
    _servidor "${CUR_SENT}C3" "$CUR_E"
    _marcar
    _rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 0 "$ESTADO" "$total: $ERRO"
    _contar files/get_metadata
    if [[ $total -eq 50 ]]; then
      assert_igual 50 "$CUR_CONTAGEM" '50: confirmacoes sequenciais'
      _campo varredura; assert_igual incremental "$CUR_V" '50: incremental'
    else
      assert_igual 0 "$CUR_CONTAGEM" '51: nenhuma confirmacao emitida (TC-CUF-10)'
      _campo varredura; assert_igual completa "$CUR_V" '51: completa'
    fi
    assert_arquivo_ausente "$B/l/f1.txt" "$total: a exclusao real acontece"
  done
}

teste_cud07_deleted_desconhecido_e_ignorado() {
  _primeira
  _regras_zerar
  _apagado nunca_existiu.txt
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "$CUR_E"
  _rodar sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "desconhecido: $ERRO"
  _campo varredura; assert_igual incremental "$CUR_V" 'ignorada, segue incremental'
  _contar files/get_metadata
  assert_igual 0 "$CUR_CONTAGEM" 'nada a confirmar'
}

teste_cud10_cus10_guardas_valem_com_cursor() {
  _primeira
  # Memoria descartada (RF-41(f)): zero exclusoes, mesmo codigo de sem cursor.
  local -a memorias=("$B/estado/dbx"/memoria-*)
  printf 'lixo' >"${memorias[0]}"
  _regras_zerar
  _apagado b.txt
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "$CUR_E"
  _rodar sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$ESTADO" 'memoria descartada: 14 como hoje'
  assert_arquivo_existe "$B/l/b.txt" 'exclusao desabilitada'
  _registro
  [[ -n $CUR_REG ]] || _harness_falhar 'memoria descartada nao toca cursor-* (C9)'
}

teste_cuf12_cursor_sem_memoria_ainda_exige_o_reconhecimento() {
  _primeira
  rm -f -- "$B/estado/dbx"/memoria-*
  _regras_zerar
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2"
  _rodar sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$ESTADO" 'cursor-* nao vale como par visto (RF-48)'
  assert_contem 'primeira execucao' "$ERRO" 'a recusa de RF-48'
}

teste_cuf11_cus05_mapa_vazio_com_retrato_nao_vazio_vai_a_completa() {
  local -a d=()
  local rel
  _primeira
  for rel in a.txt b.txt c.txt p; do _apagado "$rel" && d+=("$CUR_E"); done
  _regras_zerar
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "${d[@]}"
  _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "mapa vazio: $ERRO"
  _campo varredura; assert_igual completa "$CUR_V" 'completa antes de RF-41(b)'
  assert_arquivo_existe "$B/l/a.txt" 'nada apagado'
  _contar files/get_metadata
  assert_igual 0 "$CUR_CONTAGEM" 'sem confirmacao: foi direto a completa'
}

teste_cud13_cul01_simulacao_confirma_e_nao_grava_nem_apaga() {
  local antes diretorio_antes
  _primeira
  antes=$(_impressao "$CUR_REG")
  _regras_zerar
  _apagado b.txt
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "$CUR_E"
  diretorio_antes=$(find "$B/estado/dbx" -maxdepth 1 -name 'cursor-*' -o -maxdepth 1 -name 'memoria-*' | sort)
  _rodar --dry-run sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "simulacao: $ERRO"
  _contar files/get_metadata
  assert_igual 1 "$CUR_CONTAGEM" 'a simulacao confirma (RF-114(d))'
  assert_contem 'apagar=b.txt' "$SAIDA" 'plano igual ao real'
  assert_igual "$antes" "$(_impressao "$CUR_REG")" 'simulacao nao grava'
  assert_arquivo_existe "$B/l/b.txt" 'simulacao nao apaga'
  # Registro invalido em simulacao: nao e apagado.
  printf 'lixo' >"$CUR_REG"
  antes=$(_impressao "$CUR_REG")
  _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
  _rodar --dry-run sync --receber --origem /r --destino "$B/l"
  _campo cursor_motivo; assert_igual descartado "$CUR_V" 'descartado'
  assert_igual "$antes" "$(_impressao "$CUR_REG")" 'simulacao nunca apaga o registro (RF-117(a))'
  assert_igual "$diretorio_antes" "$(find "$B/estado/dbx" -maxdepth 1 -name 'cursor-*' -o -maxdepth 1 -name 'memoria-*' | sort)" 'nenhum registro criado'
}

teste_cul02_simulacao_sem_registro_nao_cria() {
  _cen
  _arvore_base
  _servidor "${CUR_SENT}C1" "${CUR_BASE[@]}"
  _rodar --dry-run sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "simulacao: $ERRO"
  _registro
  assert_igual '' "$CUR_REG" 'simulacao sem registro nao cria cursor-*'
}

teste_cus03_retrato_com_hash_falso_o_download_confere() {
  # O retrato e a fonte do plano, nunca da integridade: o recebimento confere o
  # resumo publicado pelo servico (RF-55) e, divergindo, o destino fica intacto
  # e o item falha como no sync sem cursor (RF-59).
  _primeira
  rm -f -- "$B/l/a.txt"
  _regras_zerar
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2"
  printf '{"content_hash":"%s"}' "$CUR_H_OUTRO" >"$B/resultado"
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$ESTADO" 'item com resumo divergente falha'
  assert_contem 'integridade' "$ERRO" 'a classe e integridade'
  assert_arquivo_ausente "$B/l/a.txt" 'destino intacto (nada gravado)'
}

teste_download_not_found_de_item_incremental_apaga_o_registro() {
  _primeira
  _regras_zerar
  _arq sumiu.txt
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "$CUR_E"
  _regra files/download '*' 409 '{"error_summary":"path/not_found/.."}'
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$ESTADO" 'item falho: 14'
  _registro
  assert_igual '' "$CUR_REG" 'not_found de item incremental apaga o registro (C6)'
}

teste_cur10_cuv06_falha_nao_avanca_o_registro() {
  local antes
  _primeira
  antes=$(_impressao "$CUR_REG")
  _regras_zerar
  _arq novo.txt
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "$CUR_E"
  _regra files/download '*' 500 '{"error_summary":"internal_error/"}'
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_diferente 0 "$ESTADO" 'item falho'
  assert_igual "$antes" "$(_impressao "$CUR_REG")" 'execucao com falha nao avanca o cursor'
  # A seguinte retoma o item.
  _regras_zerar
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "$CUR_E"
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "a seguinte conclui: $ERRO"
  assert_arquivo_existe "$B/l/novo.txt" 'o item e retomado (TC-CUV-06)'
}

teste_cua02_03_enviar_verificar_e_download_de_pasta_nao_tocam_o_registro() {
  local antes
  _primeira
  antes=$(_impressao "$CUR_REG")
  _regras_zerar
  _servidor "${CUR_SENT}C7" "${CUR_BASE[@]}"
  _marcar
  _rodar sync --enviar --origem "$B/l" --destino /r
  assert_igual "$antes" "$(_impressao "$CUR_REG")" '--enviar nao altera cursor-*'
  _campo varredura && _harness_falhar '--enviar sem os campos novos (TC-CUO-07)'
  _rodar verificar --receber --origem /r --destino "$B/l"
  assert_igual "$antes" "$(_impressao "$CUR_REG")" 'verificar nao altera cursor-*'
  _campo varredura && _harness_falhar 'verificar sem os campos novos'
  _contar files/list_folder/continue
  assert_igual 0 "$CUR_CONTAGEM" 'nenhum continue fora do sync --receber'
  # download de pasta: o sync interno nao usa o cursor (DIV-205).
  _cen
  _arvore_base
  _servidor "${CUR_SENT}C1" "${CUR_BASE[@]}"
  _regra files/get_metadata '*"path":"/r"*' 200 '{".tag":"folder","id":"id:r","path_display":"/r"}'
  # Com filtro, o tipo vem do get_metadata e a pasta vai ao sync interno.
  _rodar download --excluir nada.zzz /r "$B/l2"
  assert_igual 0 "$ESTADO" "download de pasta: $ERRO"
  assert_arquivo_existe "$B/l2/p/x.txt" 'o sync interno recebeu a pasta'
  _registro
  assert_igual '' "$CUR_REG" 'download de pasta nao cria cursor-*'
  _campo varredura && _harness_falhar 'download de pasta sem os campos do cursor'
  return 0
}

# ---------------------------------------------------------------------------
# RF-111: registro invalido e descartado sem falhar
# ---------------------------------------------------------------------------

teste_cur05_06_registro_invalido_e_descartado_com_aviso_e_codigo_0() {
  local caso
  local -a c=()
  for caso in vazio truncado sha_errado contagem campo_8k cursor_regex versao2 magia assinatura \
    conta_divergente local_divergente remoto_divergente ponto_ponto duplicado controle; do
    _primeira
    _campos_do_registro "$CUR_REG"
    c=("${CUR_CAMPOS[@]}")
    unset 'c[${#c[@]}-1]' 'c[${#c[@]}-1]'
    c=("${c[@]}")
    case $caso in
      vazio) : >"$CUR_REG" ;;
      truncado) head -c 300 -- "$CUR_REG" >"$B/t" && cat "$B/t" >"$CUR_REG" ;;
      sha_errado)
        CUR_CAMPOS[${#CUR_CAMPOS[@]} - 1]=0000000000000000000000000000000000000000000000000000000000000000
        printf '%s\0' "${CUR_CAMPOS[@]}" >"$CUR_REG"
        ;;
      contagem) c[11]=7 && _reescrever "$CUR_REG" "${c[@]}" ;;
      campo_8k) printf -v c[7] '%8193s' '' && c[7]=${c[7]// /A} && _reescrever "$CUR_REG" "${c[@]}" ;;
      cursor_regex) c[7]='com espaco' && _reescrever "$CUR_REG" "${c[@]}" ;;
      versao2) c[1]=2 && _reescrever "$CUR_REG" "${c[@]}" ;;
      magia) c[0]=dbx-retomada && _reescrever "$CUR_REG" "${c[@]}" ;;
      assinatura) c[4]='list_folder;recursive=0' && _reescrever "$CUR_REG" "${c[@]}" ;;
      conta_divergente) c[3]=dbid:OUTRA && _reescrever "$CUR_REG" "${c[@]}" ;;
      local_divergente) c[6]=/outro/lugar && _reescrever "$CUR_REG" "${c[@]}" ;;
      remoto_divergente) c[5]=/R && _reescrever "$CUR_REG" "${c[@]}" ;;
      ponto_ponto) c[13]='/r/../fora.txt' && c[12]=${c[12]%$'\t'*}$'\t/r/../fora.txt' && _reescrever "$CUR_REG" "${c[@]}" ;;
      duplicado) c[15]=${c[13]} && _reescrever "$CUR_REG" "${c[@]}" ;;
      controle) c[12]=${c[12]%$'\t'*}$'\t/r/a\x01.txt' && c[13]=$'/r/a\x01.txt' && _reescrever "$CUR_REG" "${c[@]}" ;;
    esac
    _regras_zerar
    _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
    _rodar sync --receber --origem /r --destino "$B/l"
    assert_igual 0 "$ESTADO" "$caso: codigo de execucao sem estado: $ERRO"
    _campo varredura; assert_igual completa "$CUR_V" "$caso: completa"
    _campo cursor_motivo; assert_igual descartado "$CUR_V" "$caso: descartado"
    assert_igual 1 "$(grep -c 'registro de listagem' <<<"$ERRO")" "$caso: uma linha de aviso"
    assert_nao_contem "$CUR_SENT" "$ERRO" "$caso: o aviso nao cita o cursor"
    assert_arquivo_ausente "$B/fora.txt" "$caso: nada fora da raiz"
    _contar files/list_folder/continue
    assert_igual 0 "$CUR_CONTAGEM" "$caso: o registro invalido nao foi usado"
    _registro
    _campos_do_registro "$CUR_REG"
    assert_igual "${CUR_SENT}C3" "${CUR_CAMPOS[7]}" "$caso: substituido pelo da completa"
  done
}

teste_cur07_fifo_e_ligacao_no_lugar_do_registro_nao_sao_lidos() {
  local caso
  for caso in fifo ligacao diretorio; do
    _primeira
    rm -f -- "$CUR_REG"
    case $caso in
      fifo) mkfifo "$CUR_REG" ;;
      ligacao) printf 'alvo' >"$B/alvo" && ln -s "$B/alvo" "$CUR_REG" ;;
      diretorio) mkdir "$CUR_REG" ;;
    esac
    _regras_zerar
    _servidor "${CUR_SENT}C3" "${CUR_BASE[@]}"
    _rodar sync --receber --origem /r --destino "$B/l"
    assert_igual 0 "$ESTADO" "$caso: nao pendura, segue: $ERRO"
    _campo varredura; assert_igual completa "$CUR_V" "$caso: completa"
    case $caso in
      fifo) [[ -p $CUR_REG ]] || _harness_falhar 'a FIFO foi substituida' ;;
      ligacao)
        [[ -L $CUR_REG ]] || _harness_falhar 'a ligacao foi substituida'
        assert_igual alvo "$(cat "$B/alvo")" 'o alvo da ligacao intacto'
        ;;
      diretorio) [[ -d $CUR_REG ]] || _harness_falhar 'o diretorio foi substituido' ;;
    esac
  done
}

teste_cur13_sem_trava_sem_cursor_e_codigo_normal() {
  _cen
  _arvore_base
  _servidor "${CUR_SENT}C1" "${CUR_BASE[@]}"
  mkdir -p "$B/estado/dbx"
  chmod 500 "$B/estado/dbx"
  _rodar sync --receber --origem /r --destino "$B/l"
  chmod 700 "$B/estado/dbx"
  assert_igual 0 "$ESTADO" "estado sem escrita: nao 6: $ERRO"
  _registro
  assert_igual '' "$CUR_REG" 'nenhum cursor-*'
}

teste_cur08_cuo08_cursor_nunca_sai_do_processo() {
  local modo
  _primeira
  for modo in '' --json --null --debug --progresso; do
    _regras_zerar
    _regra files/list_folder/continue '*' 409 '{"error_summary":"reset/..."}'
    _servidor "${CUR_SENT}C4" "${CUR_BASE[@]}"
    _rodar ${modo:+"$modo"} sync --receber --origem /r --destino "$B/l"
    assert_nao_contem "$CUR_SENT" "$SAIDA$ERRO" "cursor ausente da saida (${modo:-texto})"
    assert_nao_contem $'\x01' "$ERRO" 'sem byte de controle nos avisos'
  done
  _rodar diagnostico
  assert_nao_contem "$CUR_SENT" "$SAIDA$ERRO" 'cursor ausente do diagnostico'
  _rodar --json diagnostico
  assert_nao_contem "$CUR_SENT" "$SAIDA$ERRO" 'cursor ausente do diagnostico --json'
}

teste_cuo06_campos_em_texto_json_e_null() {
  _primeira
  _regras_zerar
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2"
  _rodar --json sync --receber --origem /r --destino "$B/l"
  assert_contem 'varredura' "$SAIDA" 'campo varredura em --json'
  assert_contem 'cursor_mudancas' "$SAIDA" 'cursor_mudancas em --json'
  assert_contem 'cursor_confirmadas' "$SAIDA" 'cursor_confirmadas em --json'
  _regras_zerar
  _delta "${CUR_SENT}C2" "${CUR_SENT}C3"
  _rodar --null sync --receber --origem /r --destino "$B/l"
  assert_contem 'varredura' "$SAIDA" 'campo varredura em --null'
}

# ---------------------------------------------------------------------------
# RF-117: unlink, diagnostico, poda
# ---------------------------------------------------------------------------

teste_cul06_unlink_remove_cursor() {
  _primeira
  _rodar unlink --confirmar
  _registro
  assert_igual '' "$CUR_REG" 'unlink nao deixa cursor-* (RF-51(f))'
}

teste_cul08_diagnostico_le_so_o_cabecalho() {
  local agora
  printf -v agora '%(%s)T' -1
  _primeira
  _rodar diagnostico
  assert_contem 'cursor' "$SAIDA" 'checagem cursor'
  assert_contem 'valido' "$SAIDA" 'registro valido'
  assert_contem '/r' "$SAIDA" 'raiz remota citada'
  # Registro vencido: a idade conta.
  _regravar_cabecalho 8 "$((agora - 9 * 86400))"
  _rodar diagnostico
  assert_contem 'vencido' "$SAIDA" 'registro vencido'
  # Registro grande (corpo acima de 16 KiB): o cabecalho basta (C4).
  local -a c=() corpo=()
  local i
  _campos_do_registro "$CUR_REG"
  c=("${CUR_CAMPOS[@]:0:12}")
  c[11]=400
  c[8]=$agora
  for ((i = 0; i < 400; i++)); do
    printf -v 'corpo[2*i]' 'd\tid:d%s\t-\t-\t0\t-\t/r/pasta_com_nome_longo_%s' "$i" "$i"
    printf -v 'corpo[2*i+1]' '/r/pasta_com_nome_longo_%s' "$i"
  done
  _reescrever "$CUR_REG" "${c[@]}" "${corpo[@]}"
  [[ $(stat -c %s -- "$CUR_REG") -gt 16384 ]] || _harness_falhar 'o registro grande deveria passar de 16 KiB'
  _rodar diagnostico
  assert_contem 'valido' "$SAIDA" 'registro grande lido so pelo cabecalho'
  # Ilegivel.
  printf 'lixo' >"$CUR_REG"
  _rodar diagnostico
  assert_contem 'ilegivel' "$SAIDA" 'registro ilegivel'
  assert_arquivo_existe "$CUR_REG" 'diagnostico nao remove nada'
  # Sem registros: nenhuma linha cursor.
  rm -f -- "$CUR_REG"
  _rodar diagnostico
  assert_igual 0 "$(grep -c '^cursor=' <<<"$SAIDA")" 'sem registros, nenhuma linha cursor'
}

teste_cul09_poda_101_registros_e_mais_de_8_dias() {
  local i nome
  _cen
  mkdir -p "$B/estado/dbx"
  chmod 700 "$B/estado/dbx"
  for ((i = 0; i < 100; i++)); do
    printf -v nome '%s/cursor-%032x' "$B/estado/dbx" "$i"
    printf 'x' >"$nome"
    touch -d "@$((1700000000 + i))" "$nome"
  done
  printf 'x' >"$B/estado/dbx/memoria-velha"
  printf 'x' >"$B/estado/dbx/upload-velho"
  printf 'x' >"$B/estado/dbx/retomada-velha"
  touch -d '@1600000000' "$B/estado/dbx/memoria-velha" "$B/estado/dbx/upload-velho" "$B/estado/dbx/retomada-velha"
  _arvore_base
  _servidor "${CUR_SENT}C1" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "poda: $ERRO"
  local -a restantes=("$B/estado/dbx"/cursor-*)
  # Todos os 100 antigos tem mais de 8 dias: saem; fica o corrente.
  assert_igual 1 "${#restantes[@]}" 'so o registro corrente fica (mais de 8 dias)'
  assert_arquivo_existe "$B/estado/dbx/memoria-velha" 'memoria-* nunca podada'
  assert_arquivo_existe "$B/estado/dbx/upload-velho" 'upload-* nunca podado'
  assert_arquivo_existe "$B/estado/dbx/retomada-velha" 'retomada-* nunca podada'
  # Teto de 100: 101 recentes, sai o mais antigo.
  _cen
  mkdir -p "$B/estado/dbx"
  chmod 700 "$B/estado/dbx"
  local agora
  printf -v agora '%(%s)T' -1
  for ((i = 0; i < 100; i++)); do
    printf -v nome '%s/cursor-%032x' "$B/estado/dbx" "$i"
    printf 'x' >"$nome"
    touch -d "@$((agora - 3600 - i))" "$nome"
  done
  _arvore_base
  _servidor "${CUR_SENT}C1" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  restantes=("$B/estado/dbx"/cursor-*)
  assert_igual 100 "${#restantes[@]}" 'teto de 100 com o recem-gravado'
  printf -v nome '%s/cursor-%032x' "$B/estado/dbx" 99
  assert_arquivo_ausente "$nome" 'saiu o mais antigo'
  local f presente=0
  for f in "${restantes[@]}"; do
    [[ $(head -c 10 -- "$f") == dbx-cursor ]] && presente=1
  done
  assert_igual 1 "$presente" 'o registro corrente nunca sai'
}

teste_cur11_temporario_orfao_varrido_apos_um_dia() {
  _cen
  mkdir -p "$B/estado/dbx"
  chmod 700 "$B/estado/dbx"
  printf 'x' >"$B/estado/dbx/.cursor.111.AAAAAAAA"
  printf 'x' >"$B/estado/dbx/.cursor.222.BBBBBBBB"
  touch -d '@1600000000' "$B/estado/dbx/.cursor.111.AAAAAAAA"
  _arvore_base
  _servidor "${CUR_SENT}C1" "${CUR_BASE[@]}"
  _rodar sync --receber --origem /r --destino "$B/l"
  assert_arquivo_ausente "$B/estado/dbx/.cursor.111.AAAAAAAA" '.cursor.* com mais de 1 dia sai'
  assert_arquivo_existe "$B/estado/dbx/.cursor.222.BBBBBBBB" '.cursor.* recente fica'
}

teste_cuv14_cus04_auditoria_exclusao_so_apos_confirmacao() {
  # Auditoria estatica (TC-CUD-14, TC-CUS-04): em commands/sync.sh, o laco da
  # enumeracao chama a confirmacao ANTES de o plano ser emitido, e a remocao
  # local so existe no laco de exclusao, depois do plano.
  local texto confirma plano
  texto=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/commands/sync.sh")
  confirma=$(grep -n 'dbx_sync_confirmar_exclusoes' <<<"$texto" | head -n 1)
  plano=$(grep -n 'dbx_output_campo a_apagar' <<<"$texto" | head -n 1)
  # RF-136: a exclusao remota (sentido enviar) e o lote; a local segue item a item.
  # As duas ficam DEPOIS do plano.
  local apaga_remoto apaga_local
  apaga_remoto=$(grep -n '^ *_dbx_cmd_sync_apagar_remoto_em_lote "\$remoto"' <<<"$texto" | head -n 1)
  apaga_local=$(grep -n 'if _dbx_cmd_sync_apagar_local "\$raiz_local"' <<<"$texto" | head -n 1)
  [[ -n $confirma && -n $plano && -n $apaga_remoto && -n $apaga_local ]] || _harness_falhar 'pontos da auditoria nao encontrados'
  [[ ${confirma%%:*} -lt ${plano%%:*} && ${plano%%:*} -lt ${apaga_remoto%%:*} && ${plano%%:*} -lt ${apaga_local%%:*} ]] ||
    _harness_falhar 'a confirmacao tem de vir antes do plano, e o plano antes da exclusao'
  # A data remota (RF-39) continua com um unico ponto de leitura em lib/sync.
  local codigo_sync
  codigo_sync=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/sync.sh")
  assert_igual 1 "$(grep -c 'DBX_FILTRO_CAMPO_DATA_REMOTA' <<<"$codigo_sync")" \
    'um unico ponto de leitura da data remota'
}

teste_cuo09_10_11_ajuda_readme_e_autocompletar() {
  local texto frase linha readme
  _cen
  _rodar help sync
  assert_igual 0 "$ESTADO" 'help sync'
  # As frases podem quebrar linha na ajuda: comparadas com espacos normalizados.
  texto=$(tr -s ' \n' '  ' <<<"$SAIDA")
  texto=${texto,,}
  for frase in --sem-cursor --no-cursor --varredura-completa --full-scan \
    'o cursor so acelera a listagem remota; sem registro, com registro invalido ou vencido, a varredura completa roda sozinha' \
    'uma exclusao local so e feita depois de o servidor confirmar que o arquivo foi apagado' \
    'use --varredura-completa para refazer o registro e --sem-cursor para nao usa-lo'; do
    assert_contem "$frase" "$texto" "ajuda do sync: $frase (TC-CUO-09)"
  done
  IFS= read -r -d '' readme <"$DBX_HARNESS_RAIZ/README.md" || :
  for frase in 'cursor-<resumo>' '--varredura-completa' '--full-scan' '--sem-cursor' '--no-cursor' \
    'rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/dbx"/cursor-*'; do
    assert_contem "$frase" "$readme" "README: $frase (TC-CUO-10)"
  done
  # TC-CUO-11: so o sync oferece as opcoes no autocompletar.
  while IFS= read -r linha; do
    [[ $linha == *'--sem-cursor'* || $linha == *'--full-scan'* ]] || continue
    [[ $linha == *'sync) lista='* ]] || _harness_falhar "opcao do cursor fora do sync: $linha"
  done <"$DBX_HARNESS_RAIZ/completions/dbx.bash"
  assert_contem '--varredura-completa --full-scan' "$(grep 'sync) lista=' "$DBX_HARNESS_RAIZ/completions/dbx.bash")" \
    'autocompletar do sync com as quatro'
}

teste_qa_b7b_01_raiz_barra_grava_e_usa_o_cursor() {
  # A raiz `/` da credencial e "" na API: a listagem nao traz entrada da raiz.
  local -a ent=()
  _cen
  printf -v CUR_E '{".tag":"folder","name":"p","id":"id:p","path_lower":"/p","path_display":"/p"}'
  ent+=("$CUR_E")
  printf -v CUR_E '{".tag":"file","name":"a.txt","id":"id:a","path_lower":"/a.txt","path_display":"/a.txt","rev":"%s","size":15,"server_modified":"2026-01-01T00:00:00Z","content_hash":"%s"}' "$CUR_REV" "$CUR_H"
  ent+=("$CUR_E")
  printf -v CUR_E '{".tag":"file","name":"x.txt","id":"id:x","path_lower":"/p/x.txt","path_display":"/p/x.txt","rev":"%s","size":15,"server_modified":"2026-01-01T00:00:00Z","content_hash":"%s"}' "$CUR_REV" "$CUR_H"
  ent+=("$CUR_E")
  _pagina "${CUR_SENT}C1" false "${ent[@]}"
  _regra files/list_folder '*"recursive":true*' 200 "$CUR_P"
  _rodar sync --receber --origem / --destino "$B/l"
  assert_igual 0 "$ESTADO" "raiz /: $ERRO"
  _registro
  [[ -n $CUR_REG ]] || _harness_falhar 'raiz /: o registro e gravado (QA-B7B-01)'
  _campos_do_registro "$CUR_REG"
  assert_igual '' "${CUR_CAMPOS[5]}" 'raiz remota da API vazia no cabecalho'
  _regras_zerar
  CUR_E='{".tag":"deleted","name":"x.txt","path_lower":"/p/x.txt","path_display":"/p/x.txt"}'
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "$CUR_E"
  _rodar sync --receber --origem / --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "raiz /, incremental: $ERRO"
  _campo varredura; assert_igual incremental "$CUR_V" 'raiz /: a segunda execucao e incremental'
  _contar files/get_metadata '*"path":"/p/x.txt"*'
  assert_igual 1 "$CUR_CONTAGEM" 'confirmacao pelo caminho absoluto'
  assert_arquivo_ausente "$B/l/p/x.txt" 'confirmada, apagada'
  _rodar diagnostico
  assert_contem 'valido' "$SAIDA" 'diagnostico le o registro da raiz /'
}

teste_qa_b7b_02_subpasta_com_a_propria_pasta_grava_e_usa_o_cursor() {
  # Raiz /r/Sub: a listagem traz /r/sub (outra caixa) antes do conteudo.
  local -a ent=()
  _cen
  printf -v CUR_E '{".tag":"folder","name":"sub","id":"id:sub","path_lower":"/r/sub","path_display":"/r/sub"}'
  ent+=("$CUR_E")
  _arq Sub/a.txt && ent+=("$CUR_E")
  _pagina "${CUR_SENT}C1" false "${ent[@]}"
  _regra files/list_folder '*"recursive":true*' 200 "$CUR_P"
  _rodar sync --receber --origem /r/Sub --destino "$B/l"
  assert_igual 0 "$ESTADO" "subpasta: $ERRO"
  _registro
  [[ -n $CUR_REG ]] || _harness_falhar 'a entrada da propria pasta nao bloqueia o registro (QA-B7B-02)'
  _campos_do_registro "$CUR_REG"
  assert_igual 1 "${CUR_CAMPOS[11]}" 'a propria pasta nao entra no retrato'
  _regras_zerar
  printf -v CUR_E '{".tag":"folder","name":"sub","id":"id:sub","path_lower":"/r/sub","path_display":"/r/sub"}'
  _delta "${CUR_SENT}C1" "${CUR_SENT}C2" "$CUR_E"
  _rodar sync --receber --origem /r/Sub --destino "$B/l"
  _campo varredura; assert_igual incremental "$CUR_V" 'a propria pasta no delta e ignorada, segue incremental'
}

teste_qa_b7b_o1_remedio_nao_promete_substituir_registro_nao_regular() {
  _primeira
  rm -f -- "$CUR_REG"
  mkfifo "$CUR_REG"
  _rodar diagnostico
  assert_contem 'ilegivel' "$SAIDA" 'FIFO no lugar do registro: ilegivel'
  assert_nao_contem 'substitui' "$(grep '^cursor=' <<<"$SAIDA")" 'o remedio nao promete substituir o que nunca e substituido (O1)'
}

harness_executar "$@"
