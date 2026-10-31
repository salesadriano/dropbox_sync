#!/usr/bin/env bash
# Suite independente do QA, fase 7b do backlog: cursor de listagem entre
# execucoes no `sync --receber` (F-14; RF-110..RF-119; DIV-204..DIV-234;
# condicoes C1..C11 do DBA).
#
# Escrita como ADVERSARIO, pelo executavel real `bin/dbx`, com duplo de `curl`
# proprio (independente do de `cursor_test`). Os focos sao os P0:
#
#   - o registro (cursor + retrato) NUNCA causa sozinho uma exclusao local:
#     retrato velho, forjado (rodape recalculado), adulterado (sem recalcular),
#     delta que omite mudanca, `deleted` de item que ainda existe, pasta apagada
#     e recriada, renomeacao, arquivo no lugar de pasta, caixa, mais de 50
#     confirmacoes, simulacao, com e sem `--espelhar`;
#   - equivalencia de conjunto entre o plano incremental e o da varredura
#     completa, com e sem filtros, com edicao local e arquivo local extra, e em
#     cadeia de execucoes reais;
#   - invalidacao: `reset`, outros 409, 4xx, 5xx, 429, rede, cursor repetido,
#     periodica (7 dias, 100 incrementais, relogio), cabecalho de outra
#     conta/raiz/listagem/versao, corpo e rodape adulterados, campo acima do
#     teto, caminho fora da raiz, `path_lower` repetido, entradas nao regulares;
#   - disciplina de gravacao: so execucao real com codigo 0; sinal no
#     `continue` e nas confirmacoes (TC-CUL-04/05); separacao `memoria-*` x
#     `cursor-*` (RF-43, RF-48); `--enviar`, `verificar` e download de pasta;
#   - sigilo do cursor (C10) em stdout, stderr, `--json`, `--null`, `--debug`,
#     `diagnostico`, argv e ambiente do cliente HTTP;
#   - `continue` sem `limit` (DIV-214, DIV-233).
#
# DUPLO DE REDE por regras (`ep<TAB>filtro_do_corpo<TAB>codigo<TAB>resposta<TAB>[uma]`).
# O codigo pode ser `REDE` (falha de transporte) ou `SINAL:<NOME>` (o duplo
# manda o sinal ao `dbx` e devolve falha de transporte). No download, o
# "corpo" que as regras filtram e o `Dropbox-API-Arg`; sem regra, o duplo
# devolve `conteudo remoto`. Cada chamada registra endpoint e corpo em
# `chamadas`, o argv em `argv` e o ambiente em `ambiente`.
#
# Achados (casos que REPROVAM de proposito, marcados com o ID): ver o parecer do
# QA da fase 7b.
#
# shellcheck disable=SC2016
# Justificativa: o roteiro do duplo de rede chega sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly Q_DBX="$DBX_HARNESS_RAIZ/bin/dbx"
Q_BASH=$(command -v bash)
readonly Q_BASH
Q_SLEEP=$(command -v sleep)
readonly Q_SLEEP
readonly Q_TOKEN='sl.QACURSORtoken5k'
readonly Q_REFRESH='QACURSORrefresh4j'
readonly Q_SEGREDO='QACURSORsegredo3h'
# Todo cursor do duplo comeca por este prefixo: nenhum byte dele pode sair.
readonly Q_SENT='QAB7BCURSORSENT'
readonly Q_REV='0123456789a'
Q_H1=''
Q_H2=''

_q_hash_de() { # <texto> — content_hash em Q_HASH
  Q_HASH=$(bash -c '. "$1/lib/errors.sh"; . "$1/lib/hash.sh"; printf "%s" "$2" | dbx_hash_conteudo_fluxo' _ "$DBX_HARNESS_RAIZ" "$1")
}

_q_hashes() {
  [[ -n $Q_H1 ]] && return 0
  _q_hash_de 'conteudo remoto'
  Q_H1=$Q_HASH
  _q_hash_de 'conteudo versao 2'
  Q_H2=$Q_HASH
}

# _q_cen [raiz_remota_da_credencial] — area, credencial, duplo de rede.
_q_cen() {
  _q_hashes
  B=$(mktemp -d "$DBX_TESTES_TMP/qa-cursor.XXXXXX")
  mkdir -p "$B/cfg/dbx" "$B/bin" "$B/resp" "$B/tmp" "$B/estado" "$B/l"
  chmod 700 "$B/cfg/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"%s","refresh_token":"%s","raiz_remota":"/"}' \
    "$Q_SEGREDO" "$Q_REFRESH" >"$B/cfg/dbx/credencial.json"
  chmod 600 "$B/cfg/dbx/credencial.json"
  : >"$B/regras"
  : >"$B/chamadas"
  : >"$B/argv"
  : >"$B/ambiente"
  Q_N=0
  {
    printf '#!%s\nQA=%q\nTOKEN=%q\nDORME=%q\n' "$Q_BASH" "$B" "$Q_TOKEN" "$Q_SLEEP"
    cat <<'FIM'
export LC_ALL=C
config=''
IFS= read -r -d '' config || :
printf '%s\0' "$@" >>"$QA/argv"
printf '\n' >>"$QA/argv"
env >>"$QA/ambiente"
o=''; w=''; ant=''; url=''; dados=''; cab=''
for a in "$@"; do
  case $ant in -o) o=$a ;; -w) w=$a ;; --data-binary) dados=${a#@} ;; -D) cab=$a ;; esac
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
    users/get_current_account) cod=200 corpo='{"account_id":"dbid:QACONTAB7B"}' ;;
    files/get_metadata) cod=409 corpo='{"error_summary":"path/not_found/..","error":{".tag":"path","path":{".tag":"not_found"}}}' ;;
    files/download) cod=200 corpo='conteudo remoto' ;;
    auth/token/revoke) cod=200 corpo='null' ;;
  esac
fi
case $cod in
  REDE) exit 7 ;;
  SINAL:*)
    kill -s "${cod#SINAL:}" "$(<"$QA/pid")"
    "$DORME" 1
    exit 7
    ;;
esac
if [[ -n $cab ]]; then
  printf 'HTTP/1.1 %s X\r\n\r\n' "$cod" >"$cab"
fi
[[ -n $o ]] && printf '%s' "$corpo" >"$o"
[[ -n $w ]] && printf '%s' "$cod"
exit 0
FIM
  } >"$B/bin/curl"
  printf '#!%s\nexit 0\n' "$Q_BASH" >"$B/bin/sleep"
  chmod +x "$B/bin/curl" "$B/bin/sleep"
}

# _q_regra <endpoint> <filtro_do_corpo> <codigo> <corpo> [uma]
_q_regra() {
  Q_N=$((Q_N + 1))
  printf '%s' "$4" >"$B/resp/r$Q_N"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "r$Q_N" "${5:-}" >>"$B/regras"
}

_q_zerar() {
  : >"$B/regras"
  rm -rf "$B"/usada.*
  : >"$B/chamadas"
}

# _q_rodar <argumentos...> — sem terminal, grupo proprio, teto de tempo, pid
# em `$B/pid` para o duplo poder sinalizar o `dbx`.
_q_rodar() {
  (
    cd "$B" || exit 99
    env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
      TMPDIR="$B/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout -k 2 120 setsid -w "$Q_BASH" -c 'umask "$1"; shift; printf "%s" "$$" >"$1/pid"; shift; exec "$@"' _ \
      "${Q_UMASK:-022}" "$B" "$Q_BASH" "$Q_DBX" "$@" </dev/null >"$B/out" 2>"$B/err"
  ) 2>/dev/null
  ESTADO=$?
  [[ $ESTADO -eq 124 || $ESTADO -eq 137 ]] && _harness_falhar "o comando pendurou ($ESTADO): $*"
  SAIDA=$(tr '\0' '\n' <"$B/out")
  ERRO=$(tr '\0' '\n' <"$B/err")
  return 0
}

# Entradas da listagem sob /r. _q_arq <rel> [hash] [id] [rev]
_q_arq() {
  local rel=$1 hash=${2:-$Q_H1} id=${3:-} rev=${4:-$Q_REV} baixo
  [[ -n $id ]] || id="id:${rel//[^A-Za-z0-9]/_}"
  baixo=/r/$rel
  baixo=${baixo,,}
  printf -v Q_E '{".tag":"file","name":"%s","id":"%s","path_lower":"%s","path_display":"/r/%s","rev":"%s","size":15,"server_modified":"2026-01-01T00:00:00Z","content_hash":"%s"}' \
    "${rel##*/}" "$id" "$baixo" "$rel" "$rev" "$hash"
}

_q_pasta() { # <rel> [id]
  local rel=$1 baixo=/r/$1 id=${2:-}
  [[ -n $id ]] || id="id:d_${rel//[^A-Za-z0-9]/_}"
  baixo=${baixo,,}
  printf -v Q_E '{".tag":"folder","name":"%s","id":"%s","path_lower":"%s","path_display":"/r/%s"}' \
    "${rel##*/}" "$id" "$baixo" "$rel"
}

_q_apagado() { # <rel>
  local rel=$1 baixo=/r/$1
  baixo=${baixo,,}
  printf -v Q_E '{".tag":"deleted","name":"%s","path_lower":"%s","path_display":"/r/%s"}' \
    "${rel##*/}" "$baixo" "$rel"
}

_q_pagina() { # <cursor> <has_more> [entradas...] — em Q_P
  local cursor=$1 mais=$2 lista='' e
  shift 2
  for e in "$@"; do lista+=${lista:+,}$e; done
  printf -v Q_P '{"entries":[%s],"cursor":"%s","has_more":%s}' "$lista" "$cursor" "$mais"
}

_q_servidor() { # <cursor> [entradas...] — listagem recursiva
  local cursor=$1
  shift
  _q_pagina "$cursor" false "$@"
  _q_regra files/list_folder '*"recursive":true*' 200 "$Q_P"
  _q_filhos "$cursor" "$@"
  _q_regra files/list_folder '*"recursive":false*' 200 "$Q_P"
  _q_regra files/list_folder/get_latest_cursor '*' 200 "{\"cursor\":\"$cursor\"}"
}

# _q_filhos <cursor> [entradas...] — a coleta em fluxo (RF-189) lista UM diretorio
# por vez, sem recursao: o duplo responde, por diretorio, so os filhos diretos
# (a API real nao devolve netos num list_folder nao recursivo). Regras por
# diretorio vem antes da generica de `_q_servidor` (a primeira que casa vence).
_q_filhos() {
  local cursor=$1 e caminho pai dir
  local -A filhos=() existe=() vezes=()
  shift
  for e in "$@"; do
    [[ $e =~ \"path_lower\":\"([^\"]*)\" ]] || continue
    vezes[d${BASH_REMATCH[1]}]=$((${vezes[d${BASH_REMATCH[1]}]:-0} + 1))
  done
  for e in "$@"; do
    [[ $e =~ \"path_lower\":\"([^\"]*)\" ]] || continue
    caminho=${BASH_REMATCH[1]}
    pai=d${caminho%/*}
    filhos[$pai]+=${filhos[$pai]:+,}$e
    existe[$pai]=1
    # Servidor hostil (QA-H02): a entrada REPETIDA com o mesmo caminho tambem volta
    # na listagem do proprio diretorio; a entrada normal nunca volta nela.
    if ((vezes[d$caminho] > 1)); then
      filhos[d$caminho]+=${filhos[d$caminho]:+,}$e
      existe[d$caminho]=1
    fi
    [[ $e == *'".tag":"folder"'* ]] && existe[d$caminho]=1
  done
  for dir in "${!existe[@]}"; do
    printf -v Q_P '{"entries":[%s],"cursor":"%s","has_more":false}' "${filhos[$dir]:-}" "$cursor"
    _q_regra files/list_folder "*\"path\":\"${dir#d}\",\"recursive\":false*" 200 "$Q_P"
  done
  _q_pagina "$cursor" false "$@"
}

_q_delta() { # <de> <para> [entradas...]
  local de=$1 para=$2
  shift 2
  _q_pagina "$para" false "$@"
  _q_regra files/list_folder/continue "*\"cursor\":\"$de\"*" 200 "$Q_P"
}

# _q_meta <rel> [id] — get_metadata do caminho devolve metadado (o item EXISTE).
_q_meta() {
  local rel=$1 id=${2:-}
  _q_arq "$rel" "$Q_H1" "$id"
  _q_regra files/get_metadata "*\"path\":\"/r/$rel\"*" 200 "$Q_E"
}

_q_contar() { # <endpoint> [filtro] — em Q_CONT
  local ep linha n=0 filtro=${2:-*}
  while IFS= read -r linha; do
    ep=${linha%%$'\t'*}
    # shellcheck disable=SC2053
    [[ $ep == "$1" && ${linha#*$'\t'} == $filtro ]] && n=$((n + 1))
  done <"$B/chamadas"
  Q_CONT=$n
}

_q_registro() { # o unico cursor-* em Q_REG
  local -a achados=()
  local f
  Q_REG=''
  for f in "$B/estado/dbx"/cursor-*; do
    [[ -e $f || -L $f ]] && achados+=("$f")
  done
  [[ ${#achados[@]} -le 1 ]] || _harness_falhar "mais de um cursor-*: ${#achados[@]}"
  [[ ${#achados[@]} -eq 1 ]] && Q_REG=${achados[0]}
  return 0
}

_q_campos() { # <arquivo> — campos NUL em Q_CAMPOS
  Q_CAMPOS=()
  mapfile -d '' -t Q_CAMPOS <"$1"
}

# _q_reescrever <arquivo> <campos...> — campos e rodape VALIDO recalculado (o
# forjador tem acesso ao 0600: so as regras de campo e a confirmacao barram).
_q_reescrever() {
  local arquivo=$1 resumo
  shift
  printf '%s\0' "$@" >"$arquivo"
  resumo=$(sha256sum <"$arquivo")
  printf 'fim\0%s\0' "${resumo%% *}" >>"$arquivo"
}

# _q_sem_rodape — campos do registro corrente sem o rodape, em Q_C.
_q_sem_rodape() {
  _q_registro
  _q_campos "$Q_REG"
  Q_C=("${Q_CAMPOS[@]}")
  unset 'Q_C[${#Q_C[@]}-1]' 'Q_C[${#Q_C[@]}-1]'
  Q_C=("${Q_C[@]}")
}

_q_impressao() { # <arquivo> — modo e conteudo
  if [[ -f $1 ]]; then
    printf '%s ' "$(stat -c %a -- "$1")"
    sha256sum <"$1"
  else
    printf 'ausente\n'
  fi
}

# _q_foto <dir> — impressao de toda entrada do diretorio (nome, tipo, modo,
# conteudo), salvo a trava, em Q_FOTO.
_q_foto() {
  local f linha
  Q_FOTO=''
  for f in "$1"/* "$1"/.[!.]*; do
    [[ -e $f || -L $f ]] || continue
    [[ ${f##*/} == trava-* ]] && continue
    linha=$(_q_impressao "$f")
    Q_FOTO+="${f##*/} $linha"$'\n'
  done
}

_q_valor() { # <campo> — valor na saida (chave=valor), em Q_V
  local linha
  Q_V=''
  while IFS= read -r linha; do
    [[ $linha == "$1="* ]] && { Q_V=${linha#"$1="}; return 0; }
  done <<<"$SAIDA"
  return 1
}

_q_plano() { # plano ordenado (conjunto), em Q_PLANO
  Q_PLANO=$(grep -E '^(transferir|apagar|apenas_no_destino|a_transferir|a_apagar|identicos|filtrados[a-z_]*|recusada|recusaria)=' <<<"$SAIDA" | LC_ALL=C sort)
}

_q_local() { # <rel> [conteudo]
  mkdir -p -- "$B/l/$(dirname -- "$1")"
  printf '%s' "${2:-conteudo remoto}" >"$B/l/$1"
}

# Arvore base: pasta p (x, y), pasta q/r (z), a, b, c.
_q_base() {
  local -a ent=()
  _q_pasta p && ent+=("$Q_E")
  _q_arq a.txt && ent+=("$Q_E")
  _q_arq b.txt && ent+=("$Q_E")
  _q_arq c.txt && ent+=("$Q_E")
  _q_arq p/x.txt && ent+=("$Q_E")
  _q_arq p/y.txt && ent+=("$Q_E")
  _q_pasta q && ent+=("$Q_E")
  _q_pasta q/r && ent+=("$Q_E")
  _q_arq q/r/z.txt && ent+=("$Q_E")
  Q_BASE=("${ent[@]}")
}

# _q_primeira — primeira execucao real (com --espelhar --confirmar,
# para o par ficar "visto"), cursor C1.
_q_primeira() {
  _q_cen
  _q_base
  _q_servidor "${Q_SENT}C1" "${Q_BASE[@]}"
  _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar --confirmar
  assert_igual 0 "$ESTADO" "primeira execucao: $ERRO"
  _q_registro
  [[ -n $Q_REG ]] || _harness_falhar 'a primeira execucao bem-sucedida deveria gravar cursor-*'
  Q_LOCAL_ANTES=$(cd "$B/l" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum)
}

_q_locais() { # impressao dos arquivos locais em Q_LOCAIS
  Q_LOCAIS=$(cd "$B/l" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum)
}

# _q_equiv <nome> [args...] — simulacao com cursor (deve ser incremental, a
# menos que Q_ESPERA_MODO diga outra coisa) e simulacao `--sem-cursor`, sobre o
# MESMO servidor: planos iguais como conjunto (RF-112(d), DIV-234).
_q_equiv() {
  local nome=$1 com sem modo=${Q_ESPERA_MODO:-incremental}
  shift
  _q_rodar --dry-run sync --receber --origem /r --destino "$B/l" "$@"
  assert_igual 0 "$ESTADO" "$nome com cursor: $ERRO"
  _q_valor varredura
  assert_igual "$modo" "$Q_V" "$nome: modo da execucao com cursor"
  _q_plano
  com=$Q_PLANO
  _q_rodar --dry-run sync --receber --origem /r --destino "$B/l" --sem-cursor "$@"
  assert_igual 0 "$ESTADO" "$nome sem cursor: $ERRO"
  _q_plano
  sem=$Q_PLANO
  assert_igual "$sem" "$com" "$nome: plano incremental = plano da varredura completa"
  Q_PLANO_COMUM=$com
}


# _q_forjar_sem <path_lower...> — retrato do registro corrente SEM as chaves
# dadas, contagem ajustada e rodape recalculado (forjador com acesso ao 0600).
_q_forjar_sem() {
  local -A fora=()
  local k i
  for k in "$@"; do fora[$k]=1; done
  _q_sem_rodape
  local -a novo=("${Q_C[@]:0:12}")
  for ((i = 12; i + 1 < ${#Q_C[@]}; i += 2)); do
    [[ -n ${fora[${Q_C[i + 1]}]+x} ]] && continue
    novo+=("${Q_C[i]}" "${Q_C[i + 1]}")
  done
  novo[11]=$(((${#novo[@]} - 12) / 2))
  _q_reescrever "$Q_REG" "${novo[@]}"
}

# _q_cabecalho <indice> <valor> — troca um campo e recalcula o rodape.
_q_cabecalho() {
  _q_sem_rodape
  Q_C[$1]=$2
  _q_reescrever "$Q_REG" "${Q_C[@]}"
}

# _q_byte <deslocamento> <byte> — troca um byte do registro SEM recalcular.
_q_byte() {
  printf '%s' "$2" | dd of="$Q_REG" bs=1 seek="$1" conv=notrunc status=none
}

_q_tamanho_cabecalho() { # bytes do cabecalho do registro corrente, em Q_TC
  local i
  _q_campos "$Q_REG"
  Q_TC=0
  for ((i = 0; i < 12; i++)); do Q_TC=$((Q_TC + ${#Q_CAMPOS[i]} + 1)); done
}

# ===========================================================================
# A. O registro nunca apaga sozinho (RF-114, RF-116; P1, P2)
# ===========================================================================

teste_qa_a01_retrato_forjado_com_rodape_valido_nunca_apaga() {
  local f
  _q_primeira
  _q_forjar_sem /r/b.txt /r/c.txt /r/p/x.txt /r/p/y.txt /r/q/r/z.txt
  _q_zerar
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
  _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
  for f in b.txt c.txt p/x.txt p/y.txt q/r/z.txt; do _q_meta "$f"; done
  _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar --permitir-origem-vazia
  assert_igual 0 "$ESTADO" "retrato forjado: $ERRO"
  _q_locais
  assert_igual "$Q_LOCAL_ANTES" "$Q_LOCAIS" 'nenhum arquivo local apagado pelo retrato forjado'
  _q_valor varredura; assert_igual completa "$Q_V" 'contradicao: completa na mesma execucao'
  _q_valor cursor_motivo; assert_igual contradicao "$Q_V" 'motivo contradicao'
  _q_valor apagados; assert_igual 0 "$Q_V" 'apagados=0'
  _q_contar files/list_folder '*"recursive":true*'
  assert_igual 1 "$Q_CONT" 'a varredura completa rodou uma vez'
}

teste_qa_a02_retrato_forjado_sem_arquivo_algum_nao_vira_origem_vazia() {
  local f
  _q_primeira
  _q_forjar_sem /r/a.txt /r/b.txt /r/c.txt /r/p/x.txt /r/p/y.txt /r/q/r/z.txt
  _q_zerar
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
  _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
  for f in a.txt b.txt c.txt p/x.txt p/y.txt q/r/z.txt; do _q_meta "$f"; done
  _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "retrato sem arquivos nao pode gerar recusa nem exclusao: $ERRO"
  _q_locais
  assert_igual "$Q_LOCAL_ANTES" "$Q_LOCAIS" 'nada apagado'
  _q_valor varredura; assert_igual completa "$Q_V" 'completa'
}

teste_qa_a03_deleted_de_item_que_ainda_existe_nunca_apaga() {
  local caso id
  for caso in mesmo_id outro_id; do
    _q_primeira
    _q_zerar
    _q_apagado b.txt
    _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "$Q_E"
    _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
    id=id:b_txt
    [[ $caso == outro_id ]] && id=id:b_recriado
    _q_meta b.txt "$id"
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 0 "$ESTADO" "$caso: $ERRO"
    assert_arquivo_existe "$B/l/b.txt" "$caso: b.txt existe no servidor e fica"
    _q_valor cursor_motivo; assert_igual contradicao "$Q_V" "$caso: contradicao"
    _q_valor apagados; assert_igual 0 "$Q_V" "$caso: nada apagado"
    assert_nao_contem "$Q_SENT" "$SAIDA$ERRO" "$caso: o aviso de contradicao nao cita o cursor"
  done
}

teste_qa_a04_resposta_duvidosa_na_confirmacao_nunca_apaga() {
  local caso cod corpo
  for caso in outro_409 tag_deleted_200 400 404 restricted; do
    _q_primeira
    _q_zerar
    _q_apagado b.txt
    _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "$Q_E"
    _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
    case $caso in
      outro_409) cod=409 corpo='{"error_summary":"path/malformed_path/..","error":{".tag":"path"}}' ;;
      tag_deleted_200) cod=200 corpo='{".tag":"deleted","name":"b.txt","path_lower":"/r/b.txt","path_display":"/r/b.txt"}' ;;
      400) cod=400 corpo='bad' ;;
      404) cod=404 corpo='{}' ;;
      restricted) cod=409 corpo='{"error_summary":"path/restricted_content/","error":{".tag":"path"}}' ;;
    esac
    _q_regra files/get_metadata '*' "$cod" "$corpo"
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_arquivo_existe "$B/l/b.txt" "$caso: resposta que nao e not_found nunca apaga"
    case $ESTADO in
      0)
        _q_valor varredura; assert_igual completa "$Q_V" "$caso: completa"
        ;;
      *) : ;;
    esac
  done
}

teste_qa_a05_pasta_apagada_e_arquivo_readicionado_no_mesmo_delta() {
  local -a d=() est=()
  _q_primeira
  _q_zerar
  _q_apagado p && d+=("$Q_E")
  _q_arq p/novo.txt '' 'id:p_novo' 'abcabcabcab' && d+=("$Q_E")
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "${d[@]}"
  _q_pasta p 'id:p_nova' && est+=("$Q_E")
  _q_arq a.txt && est+=("$Q_E"); _q_arq b.txt && est+=("$Q_E"); _q_arq c.txt && est+=("$Q_E")
  _q_arq p/novo.txt '' 'id:p_novo' 'abcabcabcab' && est+=("$Q_E")
  _q_pasta q && est+=("$Q_E"); _q_pasta q/r && est+=("$Q_E"); _q_arq q/r/z.txt && est+=("$Q_E")
  _q_servidor "${Q_SENT}C9" "${est[@]}"
  # A pasta p existe de novo: confirmar p pelo caminho devolve metadado.
  _q_pasta p 'id:p_nova'
  _q_regra files/get_metadata '*"path":"/r/p"*' 200 "$Q_E"
  Q_ESPERA_MODO=completa _q_equiv pasta_readicionada --espelhar
  _q_contar files/get_metadata '*"path":"/r/p/x.txt"*'
  _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "real: $ERRO"
  _q_valor varredura; assert_igual completa "$Q_V" 'a raiz apagada que voltou a existir nao confirma: completa'
  assert_arquivo_existe "$B/l/p/novo.txt" 'o novo e baixado'
  assert_arquivo_ausente "$B/l/p/x.txt" 'x sai pela varredura completa, que e a autoridade'
}

teste_qa_a06_arquivo_no_lugar_de_pasta_e_pasta_no_lugar_de_arquivo() {
  local -a d=() est=()
  _q_primeira
  _q_zerar
  # p vira arquivo (sem `deleted` dos filhos); a.txt vira pasta com um filho.
  _q_arq p '' 'id:p_arquivo' 'eeeeeeeeeee' && d+=("$Q_E")
  _q_pasta a.txt 'id:a_pasta' && d+=("$Q_E")
  _q_arq a.txt/dentro.txt '' 'id:dentro' && d+=("$Q_E")
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "${d[@]}"
  _q_arq p '' 'id:p_arquivo' 'eeeeeeeeeee' && est+=("$Q_E")
  _q_pasta a.txt 'id:a_pasta' && est+=("$Q_E"); _q_arq a.txt/dentro.txt '' 'id:dentro' && est+=("$Q_E")
  _q_arq b.txt && est+=("$Q_E"); _q_arq c.txt && est+=("$Q_E")
  _q_pasta q && est+=("$Q_E"); _q_pasta q/r && est+=("$Q_E"); _q_arq q/r/z.txt && est+=("$Q_E")
  _q_servidor "${Q_SENT}C9" "${est[@]}"
  _q_equiv tipo_trocado --espelhar
  assert_contem 'apagar=p/x.txt' "$Q_PLANO_COMUM" 'filho da pasta que virou arquivo sai'
  assert_contem 'transferir=p' "$Q_PLANO_COMUM" 'o arquivo p e transferido'
  _q_equiv tipo_trocado_sem_espelhar
}

teste_qa_a07_renomeacao_so_de_caixa_relatada_nunca_apaga() {
  local -a d=()
  _q_primeira
  _q_zerar
  # O servico relata (se relatar) apagado da grafia antiga e `file` da nova,
  # com a mesma chave sem caixa: a exclusao e anulada.
  _q_apagado b.txt && d+=("$Q_E")
  _q_arq B.TXT '' 'id:b_txt' && d+=("$Q_E")
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "${d[@]}"
  local -a est=("${Q_BASE[@]}")
  _q_servidor "${Q_SENT}C9" "${est[@]}"
  _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "caixa: $ERRO"
  assert_arquivo_existe "$B/l/b.txt" 'a grafia local fica (RF-54)'
  _q_valor apagados; assert_igual 0 "$Q_V" 'nada apagado'
  _q_contar files/get_metadata
  assert_igual 0 "$Q_CONT" 'nenhuma candidata a confirmar'
}

teste_qa_a08_simulacao_com_confirmacoes_nunca_apaga_nem_toca_o_estado() {
  local -a d=()
  local i antes
  _q_primeira
  _q_foto "$B/estado/dbx"
  antes=$Q_FOTO
  _q_zerar
  _q_apagado b.txt && d+=("$Q_E")
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "${d[@]}"
  _q_rodar --dry-run sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "simulacao: $ERRO"
  _q_valor cursor_confirmadas; assert_igual 1 "$Q_V" 'simulacao confirma (leitura)'
  assert_contem 'apagar=b.txt' "$SAIDA" 'o plano anuncia a exclusao confirmada'
  assert_arquivo_existe "$B/l/b.txt" 'simulacao nao apaga'
  _q_foto "$B/estado/dbx"
  assert_igual "$antes" "$Q_FOTO" 'simulacao: estado byte a byte igual'
  # 51 candidatas: completa, sem nenhuma confirmacao, nada apagado, estado igual.
  _q_zerar
  d=()
  for ((i = 1; i <= 51; i++)); do _q_local "extra$i.txt"; done
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
  _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
  _q_rodar --dry-run sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "51 na simulacao: $ERRO"
  _q_valor varredura; assert_igual completa "$Q_V" '51 candidatas: completa'
  _q_contar files/get_metadata
  assert_igual 0 "$Q_CONT" '51: nenhuma confirmacao'
  assert_arquivo_existe "$B/l/extra51.txt" 'simulacao nao apaga'
  _q_foto "$B/estado/dbx"
  assert_igual "$antes" "$Q_FOTO" '51 na simulacao: estado igual (registro nao apagado)'
}

teste_qa_a09_sem_espelhar_confirmada_vira_apenas_no_destino_e_fica() {
  _q_primeira
  _q_zerar
  _q_apagado b.txt
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "$Q_E"
  _q_rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "sem espelhar: $ERRO"
  assert_contem 'apenas_no_destino=b.txt' "$SAIDA" 'apenas_no_destino'
  assert_arquivo_existe "$B/l/b.txt" 'sem --espelhar nada sai'
  _q_valor varredura; assert_igual incremental "$Q_V" 'incremental'
}

teste_qa_a10_registro_adulterado_sem_recalcular_rodape_e_descartado() {
  local caso tc
  for caso in corpo cabecalho rodape trunca acrescenta vazio; do
    _q_primeira
    _q_tamanho_cabecalho
    tc=$Q_TC
    case $caso in
      # Troca uma letra de caminho do retrato (b -> k): se fosse aceito, b.txt
      # viraria candidata.
      corpo)
        local i off=$tc
        for ((i = 12; i < ${#Q_CAMPOS[@]}; i++)); do
          [[ ${Q_CAMPOS[i]} == /r/b.txt ]] && break
          off=$((off + ${#Q_CAMPOS[i]} + 1))
        done
        _q_byte "$((off + 3))" k
        ;;
      cabecalho) _q_byte 40 Z ;;
      rodape)
        local t
        t=$(stat -c %s -- "$Q_REG")
        _q_byte "$((t - 3))" 0
        _q_byte "$((t - 2))" 0
        ;;
      trunca) truncate -s -1 "$Q_REG" ;;
      acrescenta) printf 'x\0' >>"$Q_REG" ;;
      vazio) : >"$Q_REG" ;;
    esac
    _q_zerar
    _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
    _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 0 "$ESTADO" "$caso: $ERRO"
    _q_valor varredura; assert_igual completa "$Q_V" "$caso: descartado, completa"
    _q_valor cursor_motivo; assert_igual descartado "$Q_V" "$caso: motivo descartado"
    _q_contar files/list_folder/continue
    assert_igual 0 "$Q_CONT" "$caso: o cursor adulterado nao e usado"
    _q_contar files/get_metadata
    assert_igual 0 "$Q_CONT" "$caso: nenhuma confirmacao"
    _q_locais
    assert_igual "$Q_LOCAL_ANTES" "$Q_LOCAIS" "$caso: nada apagado"
    assert_nao_contem "$Q_SENT" "$SAIDA$ERRO" "$caso: aviso sem o cursor"
  done
}

# ===========================================================================
# B. Equivalencia incremental x completa (RF-112(d))
# ===========================================================================

# Cadeia de execucoes REAIS com --espelhar: a cada passo o servidor muda, o
# plano incremental e igual ao da completa, e no fim a arvore local e a do
# servidor.
teste_qa_b01_cadeia_de_execucoes_reais_converge_para_o_servidor() {
  local passo esperado
  local -a est=() d=()
  _q_primeira
  for passo in 1 2 3 4 5; do
    _q_zerar
    est=() d=()
    case $passo in
      1) # novo, modificado, apagado
        _q_arq novo.txt && d+=("$Q_E")
        _q_arq a.txt "$Q_H2" '' 22222222222 && d+=("$Q_E")
        _q_apagado c.txt && d+=("$Q_E")
        _q_pasta p && est+=("$Q_E"); _q_arq a.txt "$Q_H2" '' 22222222222 && est+=("$Q_E")
        _q_arq b.txt && est+=("$Q_E"); _q_arq novo.txt && est+=("$Q_E")
        _q_arq p/x.txt && est+=("$Q_E"); _q_arq p/y.txt && est+=("$Q_E")
        _q_pasta q && est+=("$Q_E"); _q_pasta q/r && est+=("$Q_E"); _q_arq q/r/z.txt && est+=("$Q_E")
        ;;
      2) # pasta q apagada inteira, movimento b -> p/b.txt
        _q_apagado q && d+=("$Q_E")
        _q_arq p/b.txt '' 'id:b_txt' && d+=("$Q_E")
        _q_apagado b.txt && d+=("$Q_E")
        _q_pasta p && est+=("$Q_E"); _q_arq a.txt "$Q_H2" '' 22222222222 && est+=("$Q_E")
        _q_arq novo.txt && est+=("$Q_E"); _q_arq p/b.txt '' 'id:b_txt' && est+=("$Q_E")
        _q_arq p/x.txt && est+=("$Q_E"); _q_arq p/y.txt && est+=("$Q_E")
        ;;
      3) # delta vazio; o operador apaga um arquivo local e cria um extra
        rm -f -- "$B/l/p/x.txt"
        _q_local extra.txt 'conteudo local'
        _q_pasta p && est+=("$Q_E"); _q_arq a.txt "$Q_H2" '' 22222222222 && est+=("$Q_E")
        _q_arq novo.txt && est+=("$Q_E"); _q_arq p/b.txt '' 'id:b_txt' && est+=("$Q_E")
        _q_arq p/x.txt && est+=("$Q_E"); _q_arq p/y.txt && est+=("$Q_E")
        ;;
      4) # pasta nova com subpasta e arquivo; edicao local de a.txt
        printf '%s' 'editado a mao' >"$B/l/a.txt"
        _q_pasta n && d+=("$Q_E"); _q_pasta n/m && d+=("$Q_E"); _q_arq n/m/f.txt && d+=("$Q_E")
        _q_pasta p && est+=("$Q_E"); _q_arq a.txt "$Q_H2" '' 22222222222 && est+=("$Q_E")
        _q_arq novo.txt && est+=("$Q_E"); _q_arq p/b.txt '' 'id:b_txt' && est+=("$Q_E")
        _q_arq p/x.txt && est+=("$Q_E"); _q_arq p/y.txt && est+=("$Q_E")
        _q_pasta n && est+=("$Q_E"); _q_pasta n/m && est+=("$Q_E"); _q_arq n/m/f.txt && est+=("$Q_E")
        ;;
      5) # p renomeada para P2 (deleted p, folder P2, files)
        _q_apagado p && d+=("$Q_E")
        _q_pasta P2 'id:d_p' && d+=("$Q_E")
        _q_arq P2/b.txt '' 'id:b_txt' && d+=("$Q_E"); _q_arq P2/x.txt '' 'id:p_x_txt' && d+=("$Q_E")
        _q_arq P2/y.txt '' 'id:p_y_txt' && d+=("$Q_E")
        _q_pasta P2 'id:d_p' && est+=("$Q_E"); _q_arq a.txt "$Q_H2" '' 22222222222 && est+=("$Q_E")
        _q_arq novo.txt && est+=("$Q_E"); _q_arq P2/b.txt '' 'id:b_txt' && est+=("$Q_E")
        _q_arq P2/x.txt '' 'id:p_x_txt' && est+=("$Q_E"); _q_arq P2/y.txt '' 'id:p_y_txt' && est+=("$Q_E")
        _q_pasta n && est+=("$Q_E"); _q_pasta n/m && est+=("$Q_E"); _q_arq n/m/f.txt && est+=("$Q_E")
        ;;
    esac
    _q_delta "${Q_SENT}C$passo" "${Q_SENT}C$((passo + 1))" ${d[@]+"${d[@]}"}
    _q_servidor "${Q_SENT}F$passo" "${est[@]}"
    _q_regra files/download '*/r/a.txt[!/]*' 200 'conteudo versao 2'
    # O delta parte do cursor gravado no passo anterior (C1 na primeira).
    if [[ $passo -gt 1 ]]; then
      _q_sem_rodape
      assert_igual "${Q_SENT}C$passo" "${Q_C[7]}" "passo $passo: o registro avancou para o cursor do passo anterior"
    fi
    _q_equiv "passo$passo" --espelhar
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 0 "$ESTADO" "passo $passo real: $ERRO"
    _q_valor varredura; assert_igual incremental "$Q_V" "passo $passo: incremental"
  done
  _q_locais
  esperado=$(cd "$B/l" && find . -type f | LC_ALL=C sort | tr '\n' ' ')
  assert_igual './P2/b.txt ./P2/x.txt ./P2/y.txt ./a.txt ./n/m/f.txt ./novo.txt ' "$esperado" \
    'a arvore local converge para a do servidor'
  assert_igual 'conteudo versao 2' "$(<"$B/l/a.txt")" 'a.txt na versao do servidor'
}

teste_qa_b02_filtros_trocados_entre_execucoes_mesmo_plano() {
  local -a d=() est=()
  _q_primeira
  _q_zerar
  _q_arq p/n.log && d+=("$Q_E"); _q_arq q/r/w.log && d+=("$Q_E")
  _q_apagado p/y.txt && d+=("$Q_E")
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "${d[@]}"
  _q_pasta p && est+=("$Q_E"); _q_arq a.txt && est+=("$Q_E"); _q_arq b.txt && est+=("$Q_E")
  _q_arq c.txt && est+=("$Q_E"); _q_arq p/x.txt && est+=("$Q_E"); _q_arq p/n.log && est+=("$Q_E")
  _q_pasta q && est+=("$Q_E"); _q_pasta q/r && est+=("$Q_E"); _q_arq q/r/z.txt && est+=("$Q_E")
  _q_arq q/r/w.log && est+=("$Q_E")
  _q_servidor "${Q_SENT}C9" "${est[@]}"
  _q_local local.log 'conteudo local'
  _q_equiv excluir_q --espelhar --excluir q
  _q_equiv excluir_log --espelhar --excluir '*.log'
  _q_equiv incluir_log --espelhar --incluir '*.log'
  _q_equiv incluir_p --espelhar --incluir 'p/*'
  _q_equiv tamanho --tamanho-min 16
  _q_equiv tamanho_max --tamanho-max 100
}

teste_qa_b03_filtro_de_data_sem_data_no_retrato_vai_a_completa_com_mesmo_plano() {
  local -a d=()
  _q_primeira
  _q_zerar
  _q_arq novo.txt && d+=("$Q_E")
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "${d[@]}"
  _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}" "$Q_E"
  Q_ESPERA_MODO=completa _q_equiv data_desde --modificado-desde 2025-01-01
  Q_ESPERA_MODO=completa _q_equiv data_ate --modificado-ate 2025-01-01
}

teste_qa_b04_filtro_de_data_nas_duas_execucoes_incremental_com_mesmo_plano() {
  local -a d=() est=()
  _q_cen
  _q_base
  _q_servidor "${Q_SENT}C1" "${Q_BASE[@]}"
  _q_rodar sync --receber --origem /r --destino "$B/l" --modificado-desde 2025-06-01
  assert_igual 0 "$ESTADO" "primeira com data: $ERRO"
  _q_zerar
  # Um arquivo antigo e um novo no delta.
  printf -v Q_E '{".tag":"file","name":"velho.txt","id":"id:velho","path_lower":"/r/velho.txt","path_display":"/r/velho.txt","rev":"%s","size":15,"server_modified":"2020-01-01T00:00:00Z","content_hash":"%s"}' "$Q_REV" "$Q_H1"
  d+=("$Q_E")
  est=("${Q_BASE[@]}" "$Q_E")
  _q_arq novo.txt && d+=("$Q_E") && est+=("$Q_E")
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "${d[@]}"
  _q_servidor "${Q_SENT}C9" "${est[@]}"
  _q_equiv data_nas_duas --modificado-desde 2025-06-01
  assert_nao_contem 'transferir=velho.txt' "$Q_PLANO_COMUM" 'o antigo e filtrado nos dois modos'
}

teste_qa_b05_edicao_local_extra_local_e_remoto_alterado() {
  local -a d=() est=()
  _q_primeira
  _q_zerar
  printf '%s' 'editado a mao' >"$B/l/a.txt"
  rm -f -- "$B/l/b.txt"
  _q_local extra.txt 'conteudo local'
  _q_local p/extra2.txt 'conteudo local'
  _q_arq c.txt "$Q_H2" '' 33333333333 && d+=("$Q_E")
  _q_apagado p/y.txt && d+=("$Q_E")
  _q_arq n.txt && d+=("$Q_E")
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "${d[@]}"
  _q_pasta p && est+=("$Q_E"); _q_arq a.txt && est+=("$Q_E"); _q_arq b.txt && est+=("$Q_E")
  _q_arq c.txt "$Q_H2" '' 33333333333 && est+=("$Q_E"); _q_arq p/x.txt && est+=("$Q_E")
  _q_arq n.txt && est+=("$Q_E")
  _q_pasta q && est+=("$Q_E"); _q_pasta q/r && est+=("$Q_E"); _q_arq q/r/z.txt && est+=("$Q_E")
  _q_servidor "${Q_SENT}C9" "${est[@]}"
  _q_equiv local_e_remoto --espelhar
  assert_contem 'transferir=a.txt' "$Q_PLANO_COMUM" 'edicao local sobrescrita pela origem'
  assert_contem 'transferir=b.txt' "$Q_PLANO_COMUM" 'apagado local volta'
  assert_contem 'apagar=extra.txt' "$Q_PLANO_COMUM" 'extra local sai com --espelhar'
  assert_contem 'apagar=p/extra2.txt' "$Q_PLANO_COMUM" 'extra local em subpasta sai com --espelhar'
  _q_equiv local_e_remoto_sem_espelhar
}

# ===========================================================================
# C. Invalidacao e rede de seguranca (RF-111(h), RF-113)
# ===========================================================================

teste_qa_c01_erros_do_continue_voltam_a_completa_na_mesma_execucao() {
  local caso cod corpo motivo
  for caso in reset outro_409 400 404 500 503 429 rede; do
    _q_primeira
    _q_zerar
    corpo='{}'
    motivo=descartado
    case $caso in
      reset) cod=409 corpo='{"error_summary":"reset/..","error":{".tag":"reset"}}' motivo=reset ;;
      outro_409) cod=409 corpo='{"error_summary":"path/not_found/..","error":{".tag":"path"}}' ;;
      400) cod=400 corpo='bad' ;;
      404) cod=404 ;;
      500) cod=500 motivo=transitorio ;;
      503) cod=503 motivo=transitorio ;;
      429) cod=429 corpo='{"error_summary":"too_many_requests/"}' motivo=transitorio ;;
      rede) cod=REDE motivo=transitorio ;;
    esac
    _q_regra files/list_folder/continue "*${Q_SENT}C1*" "$cod" "$corpo"
    _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 0 "$ESTADO" "$caso: nunca falha por causa do estado: $ERRO"
    _q_valor varredura; assert_igual completa "$Q_V" "$caso: completa"
    _q_valor cursor_motivo; assert_igual "$motivo" "$Q_V" "$caso: motivo"
    _q_registro
    _q_sem_rodape
    assert_igual "${Q_SENT}C9" "${Q_C[7]}" "$caso: a completa regrava o registro"
    assert_igual 0 "${Q_C[9]}" "$caso: incrementais zerados"
    local -a memorias=("$B/estado/dbx"/memoria-*)
    [[ -f ${memorias[0]} ]] || _harness_falhar "$caso: o recuo apagou memoria-* (RF-113(e))"
    assert_nao_contem "$Q_SENT" "$SAIDA$ERRO" "$caso: aviso sem o cursor"
  done
}

teste_qa_c02_401_e_403_no_continue_mantem_a_classe_5_e_nao_avancam() {
  local cod antes
  for cod in 401 403; do
    _q_primeira
    antes=$(_q_impressao "$Q_REG")
    _q_zerar
    _q_regra files/list_folder/continue '*' "$cod" '{"error_summary":"invalid_access_token/"}'
    _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 5 "$ESTADO" "$cod: classe 5: $ERRO"
    assert_igual "$antes" "$(_q_impressao "$Q_REG")" "$cod: registro intacto"
    _q_locais
    assert_igual "$Q_LOCAL_ANTES" "$Q_LOCAIS" "$cod: nada mudou no local"
  done
}

teste_qa_c03_cursor_repetido_e_has_more_sem_cursor_abandonam_o_incremental() {
  local caso
  for caso in repetido sem_cursor cursor_invalido; do
    _q_primeira
    _q_zerar
    case $caso in
      repetido) _q_pagina "${Q_SENT}C1" true ;;
      sem_cursor) Q_P='{"entries":[],"cursor":"","has_more":true}' ;;
      cursor_invalido) Q_P='{"entries":[],"cursor":"tem espaco e acento","has_more":false}' ;;
    esac
    _q_regra files/list_folder/continue "*${Q_SENT}C1*" 200 "$Q_P"
    _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
    _q_rodar sync --receber --origem /r --destino "$B/l"
    assert_igual 0 "$ESTADO" "$caso: $ERRO"
    _q_valor varredura; assert_igual completa "$Q_V" "$caso: completa"
    _q_contar files/list_folder/continue
    [[ $Q_CONT -le 2 ]] || _harness_falhar "$caso: laco de continue ($Q_CONT chamadas)"
  done
}

teste_qa_c04_varredura_periodica_por_idade_contagem_e_relogio() {
  local caso agora valor esperado
  printf -v agora '%(%s)T' -1
  for caso in oito_dias sete_dias_menos_1h cem noventa_e_nove futuro_10min futuro_4min; do
    _q_primeira
    esperado=periodica
    case $caso in
      oito_dias) _q_cabecalho 8 "$((agora - 8 * 86400))" ;;
      sete_dias_menos_1h) _q_cabecalho 8 "$((agora - 7 * 86400 + 3600))"; esperado='' ;;
      cem) _q_cabecalho 9 100 ;;
      noventa_e_nove) _q_cabecalho 9 99; esperado='' ;;
      futuro_10min) _q_cabecalho 8 "$((agora + 600))" ;;
      futuro_4min) _q_cabecalho 8 "$((agora + 240))"; esperado='' ;;
    esac
    _q_zerar
    _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
    _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
    _q_rodar sync --receber --origem /r --destino "$B/l"
    assert_igual 0 "$ESTADO" "$caso: $ERRO"
    if [[ -n $esperado ]]; then
      _q_valor cursor_motivo; assert_igual periodica "$Q_V" "$caso: periodica"
      _q_sem_rodape
      assert_igual 0 "${Q_C[9]}" "$caso: contadores zerados"
      valor=${Q_C[8]}
      [[ $valor -ge $agora && $valor -le $((agora + 120)) ]] || _harness_falhar "$caso: carimbo da completa nao renovado: $valor"
    else
      _q_valor varredura; assert_igual incremental "$Q_V" "$caso: ainda incremental"
    fi
  done
}

teste_qa_c05_cabecalho_de_outra_conta_raiz_listagem_versao_e_descartado() {
  local caso indice valor
  for caso in conta account assinatura remoto local versao magia; do
    _q_primeira
    case $caso in
      conta) indice=2 valor=cred-00000000000000000000000000000000 ;;
      account) indice=3 valor=dbid:OUTRACONTA ;;
      assinatura) indice=4 valor='list_folder;recursive=0' ;;
      remoto) indice=5 valor=/R ;;
      local) indice=6 valor=/tmp/outra ;;
      versao) indice=1 valor=2 ;;
      magia) indice=0 valor=dbx-cursos ;;
    esac
    _q_cabecalho "$indice" "$valor"
    _q_zerar
    _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
    _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 0 "$ESTADO" "$caso: $ERRO"
    _q_valor cursor_motivo; assert_igual descartado "$Q_V" "$caso: descartado"
    _q_contar files/list_folder/continue
    assert_igual 0 "$Q_CONT" "$caso: o cursor alheio nunca e enviado"
    _q_sem_rodape
    assert_igual "${Q_SENT}C9" "${Q_C[7]}" "$caso: registro refeito pela completa"
  done
}

# Forjados COM rodape recalculado: so as regras de campo barram.
teste_qa_c06_retrato_forjado_com_campo_invalido_e_descartado() {
  local caso grande i
  printf -v grande '%8180s' ''
  grande=/r/${grande// /g}
  for caso in contagem_maior contagem_menor campo_8193 ponto_ponto barra_dupla quebra_de_linha \
    controle fora_da_raiz relativo duplicado id_invalido rev_invalido hash_invalido cursor_invalido \
    entradas_acima pasta_com_rev tag_x; do
    _q_primeira
    _q_sem_rodape
    case $caso in
      contagem_maior) Q_C[11]=$((Q_C[11] + 1)) ;;
      contagem_menor) Q_C[11]=$((Q_C[11] - 1)) ;;
      campo_8193) Q_C+=("f	id:g	$Q_REV	$Q_H1	15	-	$grande" "${grande,,}"); Q_C[11]=$((Q_C[11] + 1)) ;;
      ponto_ponto) Q_C+=("f	id:g	$Q_REV	$Q_H1	15	-	/r/../g.txt" "/r/../g.txt"); Q_C[11]=$((Q_C[11] + 1)) ;;
      barra_dupla) Q_C+=("f	id:g	$Q_REV	$Q_H1	15	-	/r//g.txt" "/r//g.txt"); Q_C[11]=$((Q_C[11] + 1)) ;;
      quebra_de_linha) Q_C+=("f	id:g	$Q_REV	$Q_H1	15	-	/r/g"$'\n'"h.txt" "/r/g"$'\n'"h.txt"); Q_C[11]=$((Q_C[11] + 1)) ;;
      controle) Q_C+=("f	id:g	$Q_REV	$Q_H1	15	-	/r/g"$'\x01'".txt" "/r/g"$'\x01'".txt"); Q_C[11]=$((Q_C[11] + 1)) ;;
      fora_da_raiz) Q_C+=("f	id:g	$Q_REV	$Q_H1	15	-	/outra/g.txt" "/outra/g.txt"); Q_C[11]=$((Q_C[11] + 1)) ;;
      relativo) Q_C+=("f	id:g	$Q_REV	$Q_H1	15	-	r/g.txt" "r/g.txt"); Q_C[11]=$((Q_C[11] + 1)) ;;
      duplicado) Q_C+=("f	id:g	$Q_REV	$Q_H1	15	-	/r/A.txt" "/r/a.txt"); Q_C[11]=$((Q_C[11] + 1)) ;;
      id_invalido) Q_C+=("f	xx	$Q_REV	$Q_H1	15	-	/r/g.txt" "/r/g.txt"); Q_C[11]=$((Q_C[11] + 1)) ;;
      rev_invalido) Q_C+=("f	id:g	XYZ	$Q_H1	15	-	/r/g.txt" "/r/g.txt"); Q_C[11]=$((Q_C[11] + 1)) ;;
      hash_invalido) Q_C+=("f	id:g	$Q_REV	abc	15	-	/r/g.txt" "/r/g.txt"); Q_C[11]=$((Q_C[11] + 1)) ;;
      cursor_invalido) Q_C[7]='cursor com espaco' ;;
      entradas_acima) Q_C[11]=1000001 ;;
      pasta_com_rev) Q_C+=("d	id:g	$Q_REV	-	0	-	/r/g" "/r/g"); Q_C[11]=$((Q_C[11] + 1)) ;;
      tag_x) Q_C+=("x	id:g	$Q_REV	$Q_H1	15	-	/r/g.txt" "/r/g.txt"); Q_C[11]=$((Q_C[11] + 1)) ;;
    esac
    _q_reescrever "$Q_REG" "${Q_C[@]}"
    _q_zerar
    _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
    _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 0 "$ESTADO" "$caso: $ERRO"
    _q_valor cursor_motivo; assert_igual descartado "$Q_V" "$caso: descartado"
    _q_contar files/list_folder/continue
    assert_igual 0 "$Q_CONT" "$caso: nao usado"
    _q_locais
    assert_igual "$Q_LOCAL_ANTES" "$Q_LOCAIS" "$caso: nada apagado"
    for i in "$B/l/g.txt" "$B/g.txt" "$B/l/../g.txt"; do
      assert_arquivo_ausente "$i" "$caso: nada escrito pelo caminho do retrato"
    done
  done
}

teste_qa_c07_ligacao_simbolica_para_registro_valido_nao_e_seguida() {
  local alvo antes
  _q_primeira
  alvo="$B/registro_real"
  mv -- "$Q_REG" "$alvo"
  ln -s -- "$alvo" "$Q_REG"
  antes=$(_q_impressao "$alvo")
  _q_zerar
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
  _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
  _q_rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "ligacao: $ERRO"
  _q_valor varredura; assert_igual completa "$Q_V" 'ligacao nao e seguida'
  _q_contar files/list_folder/continue
  assert_igual 0 "$Q_CONT" 'cursor do alvo nunca usado'
  [[ -L $Q_REG ]] || _harness_falhar 'a ligacao foi substituida'
  assert_igual "$antes" "$(_q_impressao "$alvo")" 'o alvo fica intacto'
}

_q_linha_cursor_sem_falha() { # a checagem `cursor` nunca e `falha` (RF-117(e))
  local linha
  while IFS= read -r linha; do
    [[ $linha == *cursor* && $linha == *falha* ]] && _harness_falhar "checagem cursor com falha: $linha"
  done <<<"$SAIDA"
  return 0
}

teste_qa_c08_fifo_no_registro_nao_pendura_diagnostico_nem_unlink() {
  _q_primeira
  rm -f -- "$Q_REG"
  mkfifo "$Q_REG"
  _q_rodar diagnostico
  assert_contem 'ilegivel' "$SAIDA$ERRO" 'FIFO listada como ilegivel'
  _q_linha_cursor_sem_falha
  [[ -p $Q_REG ]] || _harness_falhar 'diagnostico tocou a FIFO'
  _q_rodar unlink --confirmar
  [[ -e $Q_REG ]] && _harness_falhar "unlink deixou o cursor-* (FIFO): $ERRO"
  return 0
}

# Delta com `path_lower` fora do confinamento (RF-112(e)(h)): a entrada e
# incoerente e o incremental deve ser abandonado.
teste_qa_z03_delta_com_path_lower_fora_da_raiz_e_incoerente() {
  local caso e
  for caso in ponto_ponto fora_da_raiz; do
    _q_primeira
    _q_zerar
    case $caso in
      ponto_ponto) printf -v e '{".tag":"file","name":"ok.txt","id":"id:ok","path_lower":"/r/../ok.txt","path_display":"/r/ok.txt","rev":"%s","size":15,"server_modified":"2026-01-01T00:00:00Z","content_hash":"%s"}' "$Q_REV" "$Q_H1" ;;
      fora_da_raiz) printf -v e '{".tag":"file","name":"ok.txt","id":"id:ok","path_lower":"/outra/ok.txt","path_display":"/r/ok.txt","rev":"%s","size":15,"server_modified":"2026-01-01T00:00:00Z","content_hash":"%s"}' "$Q_REV" "$Q_H1" ;;
    esac
    _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "$e"
    _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
    _q_rodar sync --receber --origem /r --destino "$B/l"
    assert_igual 0 "$ESTADO" "$caso: $ERRO"
    _q_valor varredura
    assert_igual completa "$Q_V" "QA-B7B-03: $caso: path_lower fora do confinamento deveria abandonar o incremental (RF-112(e), RF-115(h))"
  done
}

# ===========================================================================
# D. Disciplina de gravacao (RF-111(g), RF-43, RF-48, RF-110(b))
# ===========================================================================

teste_qa_d01_falha_parcial_nao_avanca_o_registro() {
  local antes
  _q_primeira
  antes=$(_q_impressao "$Q_REG")
  _q_zerar
  _q_arq novo.txt '' '' 44444444444
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "$Q_E"
  _q_regra files/download '*' 500 '{}'
  _q_rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 14 "$ESTADO" "item falho: 14: $ERRO"
  assert_igual "$antes" "$(_q_impressao "$Q_REG")" 'execucao com falha nao avanca o registro'
}

teste_qa_d02_memoria_descartada_nao_toca_o_cursor_e_vice_versa() {
  local antes m
  _q_primeira
  for m in "$B/estado/dbx"/memoria-*; do printf 'lixo' >"$m"; done
  _q_zerar
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
  _q_rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "memoria lixo: $ERRO"
  _q_valor varredura; assert_igual incremental "$Q_V" 'memoria descartada nao descarta o cursor'
  _q_registro
  [[ -n $Q_REG ]] || _harness_falhar 'cursor-* sumiu com o descarte da memoria'
  # Com --espelhar e memoria descartada: o cursor e lido, mas nao avanca.
  for m in "$B/estado/dbx"/memoria-*; do printf 'lixo' >"$m"; done
  antes=$(_q_impressao "$Q_REG")
  _q_zerar
  _q_delta "${Q_SENT}C2" "${Q_SENT}C3"
  _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual "$antes" "$(_q_impressao "$Q_REG")" 'memoria descartada com --espelhar: registro nao avanca'
}

teste_qa_d03_cursor_sem_memoria_nao_vale_como_par_visto() {
  _q_primeira
  rm -f -- "$B/estado/dbx"/memoria-*
  _q_zerar
  _q_apagado b.txt
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "$Q_E"
  _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
  assert_igual 14 "$ESTADO" "RF-48 exige --confirmar mesmo com cursor-*: $ERRO"
  assert_arquivo_existe "$B/l/b.txt" 'nada apagado'
}

teste_qa_d04_enviar_verificar_e_download_de_pasta_nao_tocam_cursor() {
  local antes
  _q_primeira
  antes=$(_q_impressao "$Q_REG")
  _q_zerar
  _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
  _q_regra files/get_metadata '*"path":"/r"*' 200 '{".tag":"folder","name":"r","id":"id:raiz","path_lower":"/r","path_display":"/r"}'
  _q_rodar sync --enviar --origem "$B/l" --destino /r
  assert_igual 0 "$ESTADO" "enviar: $ERRO"
  assert_nao_contem 'varredura=' "$SAIDA" 'enviar sem campos de cursor'
  _q_rodar verificar --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "verificar: $ERRO"
  assert_nao_contem 'varredura=' "$SAIDA" 'verificar sem campos de cursor'
  mkdir -p "$B/d2"
  _q_rodar download /r "$B/d2"
  assert_igual 0 "$ESTADO" "download de pasta: $ERRO"
  assert_nao_contem 'varredura=' "$SAIDA" 'download sem campos de cursor'
  _q_contar files/list_folder/continue
  assert_igual 0 "$Q_CONT" 'nenhum desses usou o cursor gravado'
  assert_igual "$antes" "$(_q_impressao "$Q_REG")" 'registro byte a byte igual'
  _q_registro
  _q_rodar download /r "$B/d2" --sem-cursor
  assert_igual 2 "$ESTADO" "download de pasta recusa --sem-cursor: $ERRO"
}

# ===========================================================================
# E. Sinais no `continue` e nas confirmacoes (TC-CUL-04/05)
# ===========================================================================

teste_qa_e01_sinal_durante_o_continue() {
  local sinal antes
  for sinal in TERM INT HUP; do
    _q_primeira
    antes=$(_q_impressao "$Q_REG")
    _q_zerar
    _q_regra files/list_folder/continue "*${Q_SENT}C1*" "SINAL:$sinal" '{}'
    _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 14 "$ESTADO" "$sinal no continue: 14 ($ERRO)"
    assert_igual "$antes" "$(_q_impressao "$Q_REG")" "$sinal: registro intacto"
    _q_locais
    assert_igual "$Q_LOCAL_ANTES" "$Q_LOCAIS" "$sinal: nada mudou no local"
    _q_contar files/list_folder '*"recursive":true*'
    assert_igual 0 "$Q_CONT" "$sinal: o sinal nao vira recuo para a completa"
    local -a sobra=("$B/estado/dbx"/.cursor.*)
    if [[ -e ${sobra[0]} ]]; then _harness_falhar "$sinal: temporario residual"; fi
  done
}

teste_qa_e02_sinal_durante_as_confirmacoes() {
  local sinal antes
  local -a d=()
  for sinal in TERM INT HUP; do
    _q_primeira
    antes=$(_q_impressao "$Q_REG")
    _q_zerar
    d=()
    _q_apagado a.txt && d+=("$Q_E")
    _q_apagado b.txt && d+=("$Q_E")
    _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "${d[@]}"
    _q_regra files/get_metadata '*"path":"/r/b.txt"*' "SINAL:$sinal" '{}'
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 14 "$ESTADO" "$sinal na confirmacao: 14 ($ERRO)"
    assert_arquivo_existe "$B/l/a.txt" "$sinal: a ja confirmada nao e apagada antes do plano"
    assert_arquivo_existe "$B/l/b.txt" "$sinal: b nao apagada"
    assert_igual "$antes" "$(_q_impressao "$Q_REG")" "$sinal: registro intacto"
  done
}

teste_qa_e03_falha_de_transporte_na_confirmacao_falha_sem_plano() {
  local cod antes
  for cod in 500 429 REDE; do
    _q_primeira
    antes=$(_q_impressao "$Q_REG")
    _q_zerar
    _q_apagado b.txt
    _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "$Q_E"
    _q_regra files/get_metadata '*' "$cod" '{}'
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    [[ $ESTADO -ne 0 && $ESTADO -ne 14 ]] || _harness_falhar "$cod: deveria falhar com a classe de rede, obtido $ESTADO"
    assert_arquivo_existe "$B/l/b.txt" "$cod: nada apagado"
    assert_nao_contem 'apagar=' "$SAIDA" "$cod: nenhum plano"
    assert_igual "$antes" "$(_q_impressao "$Q_REG")" "$cod: registro nao avanca"
  done
}

# ===========================================================================
# F. Opcoes, saida e sigilo (RF-118, C10)
# ===========================================================================

teste_qa_f01_opcoes_invalidas_saem_2_sem_tocar_estado() {
  local antes
  _q_primeira
  _q_foto "$B/estado/dbx"
  antes=$Q_FOTO
  _q_zerar
  _q_rodar sync --receber --origem /r --destino "$B/l" --no-cursor --full-scan
  assert_igual 2 "$ESTADO" 'juntas'
  _q_rodar sync --enviar --origem "$B/l" --destino /r --sem-cursor
  assert_igual 2 "$ESTADO" '--sem-cursor com --enviar'
  _q_rodar sync --enviar --origem "$B/l" --destino /r --full-scan
  assert_igual 2 "$ESTADO" '--full-scan com --enviar'
  _q_rodar verificar --receber --origem /r --destino "$B/l" --sem-cursor
  assert_igual 2 "$ESTADO" 'verificar recusa a opcao'
  _q_contar files/list_folder
  assert_igual 0 "$Q_CONT" 'nenhuma listagem antes da recusa'
  _q_foto "$B/estado/dbx"
  assert_igual "$antes" "$Q_FOTO" 'estado intacto'
}

teste_qa_f02_sem_cursor_nao_le_nao_grava_nao_apaga() {
  local antes
  _q_primeira
  _q_cabecalho 9 100
  _q_foto "$B/estado/dbx"
  antes=$Q_FOTO
  _q_zerar
  _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
  _q_rodar sync --receber --origem /r --destino "$B/l" --no-cursor
  assert_igual 0 "$ESTADO" "$ERRO"
  _q_valor cursor_motivo; assert_igual desligado "$Q_V" 'desligado'
  _q_foto "$B/estado/dbx"
  local filtrado_antes filtrado_depois
  filtrado_antes=$(grep '^cursor-' <<<"$antes")
  filtrado_depois=$(grep '^cursor-' <<<"$Q_FOTO")
  assert_igual "$filtrado_antes" "$filtrado_depois" '--no-cursor: cursor-* byte a byte igual'
}

teste_qa_f03_cursor_nunca_sai_por_saida_argv_ambiente_ou_residuo() {
  local -a d=()
  _q_primeira
  _q_zerar
  _q_apagado b.txt && d+=("$Q_E")
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "${d[@]}"
  : >"$B/argv"
  : >"$B/ambiente"
  _q_rodar --debug --json sync --receber --origem /r --destino "$B/l" --progresso
  assert_igual 0 "$ESTADO" "debug json: $ERRO"
  assert_nao_contem "$Q_SENT" "$SAIDA$ERRO" '--debug --json --progresso'
  _q_zerar
  _q_regra files/list_folder/continue "*${Q_SENT}C2*" 409 '{"error_summary":"reset/","error":{".tag":"reset"}}'
  _q_servidor "${Q_SENT}C3" "${Q_BASE[@]}"
  _q_rodar --null --debug sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "null reset: $ERRO"
  assert_nao_contem "$Q_SENT" "$SAIDA$ERRO" '--null com reset'
  _q_zerar
  _q_apagado a.txt
  _q_delta "${Q_SENT}C3" "${Q_SENT}C4" "$Q_E"
  _q_meta a.txt
  _q_rodar --debug sync --receber --origem /r --destino "$B/l" --espelhar
  assert_nao_contem "$Q_SENT" "$SAIDA$ERRO" 'contradicao com --debug'
  _q_rodar --debug diagnostico
  assert_nao_contem "$Q_SENT" "$SAIDA$ERRO" 'diagnostico'
  _q_rodar --json diagnostico
  assert_nao_contem "$Q_SENT" "$SAIDA$ERRO" 'diagnostico --json'
  local argv ambiente
  argv=$(tr '\0' '\n' <"$B/argv")
  ambiente=$(<"$B/ambiente")
  assert_nao_contem "$Q_SENT" "$argv" 'argv do cliente HTTP'
  assert_nao_contem "$Q_SENT" "$ambiente" 'ambiente do cliente HTTP'
  local residuo
  residuo=$(grep -rl "$Q_SENT" "$B/tmp" 2>/dev/null)
  assert_igual '' "$residuo" 'nenhum residuo com o cursor na area temporaria'
}

teste_qa_f04_umask_000_registro_0600_e_diretorio_0700() {
  _q_cen
  _q_base
  _q_servidor "${Q_SENT}C1" "${Q_BASE[@]}"
  Q_UMASK=000 _q_rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "$ERRO"
  _q_registro
  assert_igual 600 "$(stat -c %a -- "$Q_REG")" 'registro 0600 com umask 000'
  assert_igual 700 "$(stat -c %a -- "$B/estado/dbx")" 'diretorio 0700 com umask 000'
}

teste_qa_f05_campos_em_json_e_null() {
  _q_primeira
  _q_zerar
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
  _q_rodar --json sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "$ERRO"
  assert_contem 'varredura=incremental' "$SAIDA" 'json: varredura'
  assert_contem 'cursor_mudancas=0' "$SAIDA" 'json: cursor_mudancas'
  assert_contem 'cursor_confirmadas=0' "$SAIDA" 'json: cursor_confirmadas'
  assert_nao_contem 'cursor_motivo' "$SAIDA" 'json: sem motivo no incremental'
  _q_zerar
  _q_servidor "${Q_SENT}C9" "${Q_BASE[@]}"
  _q_rodar --null sync --receber --origem /r --destino "$B/l" --full-scan
  assert_igual 0 "$ESTADO" "$ERRO"
  assert_contem 'cursor_motivo=forcada' "$SAIDA" 'null: forcada'
}

teste_qa_f06_poda_de_registros_de_outros_pares_nunca_alcanca_outros_namespaces() {
  local f
  _q_primeira
  for f in cursor-00000000000000000000000000000001 memoria-00000000000000000000000000000001 \
    retomada-00000000000000000000000000000001 upload-00000000000000000000000000000001; do
    printf 'x' >"$B/estado/dbx/$f"
    touch -d '10 days ago' "$B/estado/dbx/$f"
  done
  _q_zerar
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
  _q_rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "$ERRO"
  assert_arquivo_ausente "$B/estado/dbx/cursor-00000000000000000000000000000001" 'cursor-* de 10 dias podado'
  assert_arquivo_existe "$B/estado/dbx/memoria-00000000000000000000000000000001" 'memoria-* nunca podada pela poda do cursor'
  assert_arquivo_existe "$B/estado/dbx/retomada-00000000000000000000000000000001" 'retomada-* intacta'
  assert_arquivo_existe "$B/estado/dbx/upload-00000000000000000000000000000001" 'upload-* intacta'
  _q_registro
}

teste_qa_f07_unlink_remove_cursor_e_diagnostico_lista() {
  _q_primeira
  _q_rodar diagnostico
  assert_contem 'cursor' "$SAIDA$ERRO" 'diagnostico tem a linha cursor'
  assert_contem 'valido' "$SAIDA$ERRO" 'registro valido'
  _q_rodar unlink --confirmar
  _q_registro
  assert_igual '' "$Q_REG" 'unlink remove cursor-*'
}

# ===========================================================================
# G. `continue` sem `limit` (DIV-214, DIV-233)
# ===========================================================================

teste_qa_g01_continue_sem_limit_no_verificar_e_no_enviar() {
  local cmd
  for cmd in verificar enviar; do
    _q_cen
    _q_arq a.txt
    _q_pagina "${Q_SENT}P1" true "$Q_E"
    _q_regra files/list_folder '*"recursive":true*' 200 "$Q_P"
    _q_regra files/list_folder '*"recursive":false*' 200 "$Q_P"
    _q_arq b.txt
    _q_delta "${Q_SENT}P1" "${Q_SENT}P2" "$Q_E"
    _q_local a.txt
    _q_local b.txt
    case $cmd in
      verificar) _q_rodar verificar --receber --origem /r --destino "$B/l" ;;
      enviar) _q_rodar sync --enviar --origem "$B/l" --destino /r ;;
    esac
    assert_igual 0 "$ESTADO" "$cmd: $ERRO"
    _q_contar files/list_folder/continue "{\"cursor\":\"${Q_SENT}P1\"}"
    assert_igual 1 "$Q_CONT" "$cmd: continue so com o cursor"
    _q_contar files/list_folder/continue '*limit*'
    assert_igual 0 "$Q_CONT" "$cmd: nenhum continue com limit"
    _q_registro
    assert_igual '' "$Q_REG" "$cmd: nenhum cursor-* criado"
  done
}

# ===========================================================================
# Z. Achados (reprovam de proposito ate a correcao)
# ===========================================================================

# QA-B7B-01: com a raiz remota `/` (a da credencial padrao), o `sync
# --receber` nunca grava o registro: `dbx_state_cursor_contexto` exige raiz
# remota nao vazia, e a raiz da API e "". O cursor nunca e usado e o motivo e
# sempre `sem-registro`.
teste_qa_z01_raiz_remota_barra_usa_o_cursor() {
  local e1
  _q_cen
  printf -v e1 '{".tag":"file","name":"a.txt","id":"id:a","path_lower":"/a.txt","path_display":"/a.txt","rev":"%s","size":15,"server_modified":"2026-01-01T00:00:00Z","content_hash":"%s"}' "$Q_REV" "$Q_H1"
  _q_pagina "${Q_SENT}C1" false "$e1"
  _q_regra files/list_folder '*"recursive":true*' 200 "$Q_P"
  _q_filhos "${Q_SENT}C1" "$e1"
  _q_regra files/list_folder '*"recursive":false*' 200 "$Q_P"
  _q_regra files/list_folder/get_latest_cursor '*' 200 "{\"cursor\":\"${Q_SENT}C1\"}"
  _q_rodar sync --receber --origem / --destino "$B/l"
  assert_igual 0 "$ESTADO" "raiz /: $ERRO"
  _q_registro
  [[ -n $Q_REG ]] || _harness_falhar 'QA-B7B-01: sync --receber da raiz / nunca grava cursor-* (RF-110(a)(c), RF-111(g))'
  _q_zerar
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
  _q_rodar sync --receber --origem / --destino "$B/l"
  _q_valor varredura
  assert_igual incremental "$Q_V" 'QA-B7B-01: segunda execucao da raiz / deveria ser incremental'
}

# QA-B7B-02: o `list_folder` recursivo de uma pasta devolve a PROPRIA pasta
# como entrada (exemplo da documentacao: listar /Homework/math traz a entrada
# /homework/math). `_dbx_sync_entrada` reprova essa entrada no confinamento e
# marca a tabela como nao persistivel: o registro nunca e gravado.
teste_qa_z02_listagem_com_a_propria_pasta_grava_o_registro() {
  local raiz
  _q_cen
  _q_base
  printf -v raiz '{".tag":"folder","name":"r","id":"id:raiz","path_lower":"/r","path_display":"/r"}'
  _q_servidor "${Q_SENT}C1" "$raiz" "${Q_BASE[@]}"
  _q_rodar sync --receber --origem /r --destino "$B/l"
  assert_igual 0 "$ESTADO" "propria pasta: $ERRO"
  _q_registro
  [[ -n $Q_REG ]] || _harness_falhar 'QA-B7B-02: listagem real (com a entrada da propria raiz) nunca grava cursor-*'
}

# ===========================================================================
# H. Ciclo 2: reataque das correcoes de QA-B7B-01, 02 e 03 (raiz `/`, a
# entrada da propria pasta reconhecida pela estrutura, `path_lower` confinado)
# ===========================================================================

# _q_ent <tag> <path_display> [hash] [id] — entrada com path_lower = display
# em minusculas (ASCII), em Q_E. Para `deleted`, so caminhos.
_q_ent() {
  local tag=$1 exibido=$2 hash=${3:-$Q_H1} id=${4:-} baixo
  baixo=${exibido,,}
  [[ -n $id ]] || id="id:${exibido//[^A-Za-z0-9]/_}"
  case $tag in
    file)
      printf -v Q_E '{".tag":"file","name":"%s","id":"%s","path_lower":"%s","path_display":"%s","rev":"%s","size":15,"server_modified":"2026-01-01T00:00:00Z","content_hash":"%s"}' \
        "${exibido##*/}" "$id" "$baixo" "$exibido" "$Q_REV" "$hash"
      ;;
    folder)
      printf -v Q_E '{".tag":"folder","name":"%s","id":"%s","path_lower":"%s","path_display":"%s"}' \
        "${exibido##*/}" "$id" "$baixo" "$exibido"
      ;;
    *)
      printf -v Q_E '{".tag":"deleted","name":"%s","path_lower":"%s","path_display":"%s"}' \
        "${exibido##*/}" "$baixo" "$exibido"
      ;;
  esac
}

# Arvore da raiz `/` (API ""): sem a entrada da propria raiz, como a API.
_q_base_raiz() {
  local -a ent=()
  _q_ent file /a.txt && ent+=("$Q_E")
  _q_ent file /b.txt && ent+=("$Q_E")
  _q_ent folder /d && ent+=("$Q_E")
  _q_ent file /d/x.txt && ent+=("$Q_E")
  Q_BASE_RAIZ=("${ent[@]}")
}

# _q_delta_cru <json_da_entrada> — delta C1 -> C2 com a entrada
# crua, servidor completo = arvore base com a raiz /r listada.
_q_delta_cru() {
  _q_zerar
  _q_pagina "${Q_SENT}C2" false "$1"
  _q_regra files/list_folder/continue "*\"cursor\":\"${Q_SENT}C1\"*" 200 "$Q_P"
  _q_ent folder /r 'id:raiz'
  _q_servidor "${Q_SENT}C9" "$Q_E" "${Q_BASE[@]}"
}

teste_qa_h01_raiz_barra_incremental_confirma_e_contradiz_por_servidor() {
  local -a d=()
  _q_cen
  _q_base_raiz
  _q_servidor "${Q_SENT}C1" "${Q_BASE_RAIZ[@]}"
  _q_rodar sync --receber --origem / --destino "$B/l" --espelhar --confirmar
  assert_igual 0 "$ESTADO" "raiz /, primeira: $ERRO"
  _q_registro
  [[ -n $Q_REG ]] || _harness_falhar 'raiz /: registro gravado'
  _q_campos "$Q_REG"
  assert_igual '' "${Q_CAMPOS[5]}" 'raiz / no cabecalho e a cadeia vazia da API'
  # a.txt apagado de fato (not_found); b.txt relatado apagado mas existe.
  _q_zerar
  _q_ent deleted /a.txt && d+=("$Q_E")
  _q_ent deleted /b.txt && d+=("$Q_E")
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2" "${d[@]}"
  _q_ent file /b.txt
  _q_regra files/get_metadata '*"path":"/b.txt"*' 200 "$Q_E"
  _q_servidor "${Q_SENT}C9" "${Q_BASE_RAIZ[@]:1}"
  _q_rodar sync --receber --origem / --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "raiz /, contradicao: $ERRO"
  _q_valor cursor_motivo; assert_igual contradicao "$Q_V" 'raiz /: b.txt existe, contradicao'
  assert_arquivo_existe "$B/l/b.txt" 'raiz /: b.txt nunca apagado'
  assert_arquivo_ausente "$B/l/a.txt" 'raiz /: a.txt sai pela varredura completa'
  _q_contar files/get_metadata '*"path":"//*'
  assert_igual 0 "$Q_CONT" 'raiz /: confirmacao nunca com barra dupla'
  # Agora incremental com confirmacao valida.
  _q_zerar
  _q_ent deleted /d/x.txt
  _q_delta "${Q_SENT}C9" "${Q_SENT}C10" "$Q_E"
  _q_rodar sync --receber --origem / --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "raiz /, confirmada: $ERRO"
  _q_valor varredura; assert_igual incremental "$Q_V" 'raiz /: incremental'
  _q_valor cursor_confirmadas; assert_igual 1 "$Q_V" 'raiz /: uma confirmada'
  _q_contar files/get_metadata '*"path":"/d/x.txt"*'
  assert_igual 1 "$Q_CONT" 'raiz /: confirmacao pelo caminho certo'
  assert_arquivo_ausente "$B/l/d/x.txt" 'raiz /: confirmada e apagada com --espelhar'
}

teste_qa_h02_entrada_da_raiz_na_completa_nao_vira_porta() {
  local caso e1 e2
  for caso in duas_vezes_outro_id exibido_estranho arquivo_com_o_caminho_da_raiz caixa_da_raiz; do
    _q_cen
    _q_base
    case $caso in
      duas_vezes_outro_id)
        _q_ent folder /r 'id:raiz1'; e1=$Q_E
        _q_ent folder /r 'id:raiz2'; e2=$Q_E
        ;;
      exibido_estranho)
        printf -v e1 '{".tag":"folder","name":"x","id":"id:raiz","path_lower":"/r","path_display":"/r/../fora"}'
        e2=$e1
        ;;
      arquivo_com_o_caminho_da_raiz)
        _q_ent folder /r 'id:raiz'; e1=$Q_E
        _q_ent file /r '' 'id:arquivo_raiz'; e2=$Q_E
        ;;
      caixa_da_raiz)
        printf -v e1 '{".tag":"folder","name":"R","id":"id:raiz","path_lower":"/R","path_display":"/R"}'
        e2=$e1
        ;;
    esac
    _q_servidor "${Q_SENT}C1" "$e1" "${Q_BASE[@]}" "$e2"
    _q_rodar sync --receber --origem /r --destino "$B/l"
    assert_igual 0 "$ESTADO" "$caso: $ERRO"
    assert_arquivo_ausente "$B/fora" "$caso: nada fora da raiz local"
    assert_arquivo_ausente "$B/l/r" "$caso: a raiz nunca vira item local"
    _q_registro
    case $caso in
      arquivo_com_o_caminho_da_raiz)
        assert_igual '' "$Q_REG" "$caso: arquivo no caminho da raiz torna o retrato nao gravavel"
        ;;
      *)
        [[ -n $Q_REG ]] || _harness_falhar "$caso: a pasta da raiz e so ignorada, o registro e gravado"
        _q_campos "$Q_REG"
        local i
        for ((i = 12; i < ${#Q_CAMPOS[@]} - 2; i += 2)); do
          [[ ${Q_CAMPOS[i + 1],,} == /r ]] && _harness_falhar "$caso: a raiz entrou no retrato"
        done
        ;;
    esac
  done
  return 0
}

teste_qa_h03_entrada_da_raiz_no_delta() {
  local caso e esperado
  for caso in pasta_outro_id pasta_duas_vezes pasta_caixa raiz_apagada arquivo_na_raiz; do
    _q_primeira
    esperado=incremental
    case $caso in
      pasta_outro_id) _q_ent folder /r 'id:raiz_nova'; e=$Q_E ;;
      pasta_duas_vezes) _q_ent folder /r 'id:raiz'; e="$Q_E,$Q_E" ;;
      pasta_caixa) printf -v e '{".tag":"folder","name":"R","id":"id:raiz","path_lower":"/R","path_display":"/R"}' ;;
      raiz_apagada) _q_ent deleted /r; e=$Q_E; esperado=completa ;;
      arquivo_na_raiz) _q_ent file /r '' 'id:arq'; e=$Q_E; esperado=completa ;;
    esac
    _q_delta_cru "$e"
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 0 "$ESTADO" "$caso: $ERRO"
    _q_valor varredura; assert_igual "$esperado" "$Q_V" "$caso: modo"
    _q_locais
    assert_igual "$Q_LOCAL_ANTES" "$Q_LOCAIS" "$caso: nada apagado nem trocado"
    _q_contar files/get_metadata
    assert_igual 0 "$Q_CONT" "$caso: nenhuma candidata"
  done
}

teste_qa_h04_delta_com_caminho_fora_do_confinamento_vai_a_completa() {
  local caso e
  for caso in ponto_ponto fora_da_raiz irma_com_prefixo barra_final barra_dupla quebra_de_linha nul \
    relativo exibido_fora ponto controle; do
    _q_primeira
    case $caso in
      ponto_ponto) printf -v e '{".tag":"file","name":"x","id":"id:x","path_lower":"/r/../x.txt","path_display":"/r/x.txt","rev":"%s","size":15,"content_hash":"%s"}' "$Q_REV" "$Q_H1" ;;
      fora_da_raiz) printf -v e '{".tag":"file","name":"x","id":"id:x","path_lower":"/etc/x.txt","path_display":"/r/x.txt","rev":"%s","size":15,"content_hash":"%s"}' "$Q_REV" "$Q_H1" ;;
      irma_com_prefixo) printf -v e '{".tag":"file","name":"x","id":"id:x","path_lower":"/rx/x.txt","path_display":"/rx/x.txt","rev":"%s","size":15,"content_hash":"%s"}' "$Q_REV" "$Q_H1" ;;
      barra_final) printf -v e '{".tag":"folder","name":"x","id":"id:x","path_lower":"/r/","path_display":"/r/"}' ;;
      barra_dupla) printf -v e '{".tag":"file","name":"x","id":"id:x","path_lower":"/r//x.txt","path_display":"/r//x.txt","rev":"%s","size":15,"content_hash":"%s"}' "$Q_REV" "$Q_H1" ;;
      quebra_de_linha) printf -v e '{".tag":"file","name":"x","id":"id:x","path_lower":"/r/x\\n.txt","path_display":"/r/x.txt","rev":"%s","size":15,"content_hash":"%s"}' "$Q_REV" "$Q_H1" ;;
      nul) printf -v e '{".tag":"file","name":"x","id":"id:x","path_lower":"/r/x\\u0000.txt","path_display":"/r/x\\u0000.txt","rev":"%s","size":15,"content_hash":"%s"}' "$Q_REV" "$Q_H1" ;;
      relativo) printf -v e '{".tag":"file","name":"x","id":"id:x","path_lower":"r/x.txt","path_display":"r/x.txt","rev":"%s","size":15,"content_hash":"%s"}' "$Q_REV" "$Q_H1" ;;
      exibido_fora) printf -v e '{".tag":"file","name":"x","id":"id:x","path_lower":"/r/x.txt","path_display":"/outra/x.txt","rev":"%s","size":15,"content_hash":"%s"}' "$Q_REV" "$Q_H1" ;;
      ponto) printf -v e '{".tag":"file","name":"x","id":"id:x","path_lower":"/r/./x.txt","path_display":"/r/./x.txt","rev":"%s","size":15,"content_hash":"%s"}' "$Q_REV" "$Q_H1" ;;
      controle) printf -v e '{".tag":"file","name":"x","id":"id:x","path_lower":"/r/x\\u0001.txt","path_display":"/r/x.txt","rev":"%s","size":15,"content_hash":"%s"}' "$Q_REV" "$Q_H1" ;;
    esac
    _q_delta_cru "$e"
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 0 "$ESTADO" "$caso: nunca falha por causa do delta: $ERRO"
    _q_valor varredura; assert_igual completa "$Q_V" "$caso: entrada fora do confinamento abandona o incremental"
    _q_locais
    assert_igual "$Q_LOCAL_ANTES" "$Q_LOCAIS" "$caso: nada apagado nem escrito"
    assert_arquivo_ausente "$B/x.txt" "$caso: nada escrito fora"
    assert_arquivo_ausente "$B/l/x.txt" "$caso: o item incoerente nao e baixado"
    _q_sem_rodape
    local i
    for ((i = 12; i + 1 < ${#Q_C[@]}; i += 2)); do
      [[ ${Q_C[i + 1]} == /r/* && ${Q_C[i + 1]} != */../* && ${Q_C[i + 1]} != *//* ]] ||
        _harness_falhar "$caso: chave fora do confinamento no retrato regravado: ${Q_C[i + 1]}"
    done
  done
}

teste_qa_h05_deleted_com_grafia_diferente_nunca_apaga_o_que_o_mapa_tem() {
  local caso e
  for caso in caixa ponto_ponto fora; do
    _q_primeira
    case $caso in
      caixa) printf -v e '{".tag":"deleted","name":"A.TXT","path_lower":"/R/A.TXT","path_display":"/R/A.TXT"}' ;;
      ponto_ponto) printf -v e '{".tag":"deleted","name":"a.txt","path_lower":"/r/../r/a.txt","path_display":"/r/../r/a.txt"}' ;;
      fora) printf -v e '{".tag":"deleted","name":"a.txt","path_lower":"/outra/a.txt","path_display":"/outra/a.txt"}' ;;
    esac
    _q_delta_cru "$e"
    _q_meta a.txt
    _q_rodar sync --receber --origem /r --destino "$B/l" --espelhar
    assert_igual 0 "$ESTADO" "$caso: $ERRO"
    assert_arquivo_existe "$B/l/a.txt" "$caso: a.txt continua no mapa e nunca e apagado"
    _q_valor apagados; assert_igual 0 "$Q_V" "$caso: nada apagado"
  done
}

teste_qa_h06_raiz_na_linha_de_comando_com_caixa_e_barra_final() {
  local arg
  for arg in /r/ /R //r; do
    _q_primeira
    _q_zerar
    _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
    _q_ent folder /r 'id:raiz'
    _q_servidor "${Q_SENT}C9" "$Q_E" "${Q_BASE[@]}"
    _q_rodar sync --receber --origem "$arg" --destino "$B/l" --espelhar
    if [[ $ESTADO -eq 0 ]]; then
      _q_locais
      assert_igual "$Q_LOCAL_ANTES" "$Q_LOCAIS" "$arg: nada apagado"
      _q_valor apagados; assert_igual 0 "$Q_V" "$arg: apagados=0"
      _q_valor a_transferir; assert_igual 0 "$Q_V" "$arg: nada a transferir"
    else
      # Raiz recusada pela validacao da CLI: tambem seguro, sem tocar o local.
      _q_locais
      assert_igual "$Q_LOCAL_ANTES" "$Q_LOCAIS" "$arg recusado ($ESTADO): nada mudou"
    fi
    assert_nao_contem "$Q_SENT" "$SAIDA$ERRO" "$arg: aviso sem o cursor"
  done
}

teste_qa_h07_raiz_unicode_em_localidade_c_e_segura() {
  local -a ent=()
  _q_cen
  printf -v Q_E '{".tag":"folder","name":"Ünï","id":"id:raiz","path_lower":"/ünï","path_display":"/Ünï"}'
  ent+=("$Q_E")
  printf -v Q_E '{".tag":"file","name":"a.txt","id":"id:a","path_lower":"/ünï/a.txt","path_display":"/Ünï/a.txt","rev":"%s","size":15,"content_hash":"%s"}' "$Q_REV" "$Q_H1"
  ent+=("$Q_E")
  printf -v Q_E '{".tag":"file","name":"B.txt","id":"id:b","path_lower":"/ünï/b.txt","path_display":"/Ünï/B.txt","rev":"%s","size":15,"content_hash":"%s"}' "$Q_REV" "$Q_H1"
  ent+=("$Q_E")
  _q_servidor "${Q_SENT}C1" "${ent[@]}"
  _q_delta "${Q_SENT}C1" "${Q_SENT}C2"
  _q_rodar sync --receber --origem /Ünï --destino "$B/l" --espelhar --confirmar
  assert_igual 0 "$ESTADO" "unicode, primeira: $ERRO"
  assert_arquivo_existe "$B/l/a.txt" 'recebido'
  _q_rodar sync --receber --origem /Ünï --destino "$B/l" --espelhar
  assert_igual 0 "$ESTADO" "unicode, segunda: $ERRO"
  assert_arquivo_existe "$B/l/a.txt" 'nada apagado (DIV-235: so custo)'
  assert_arquivo_existe "$B/l/B.txt" 'nada apagado'
  _q_valor apagados; assert_igual 0 "$Q_V" 'apagados=0'
}

teste_qa_h08_registros_da_raiz_barra_e_da_subpasta_nao_se_cruzam() {
  local -a ent=()
  _q_cen
  _q_base_raiz
  _q_ent folder /r 'id:raiz' && ent+=("$Q_E")
  _q_arq a.txt && ent+=("$Q_E")
  # list_folder de "" e de "/r" respondem cursores diferentes.
  _q_pagina "${Q_SENT}RAIZ1" false "${Q_BASE_RAIZ[@]}"
  _q_regra files/list_folder '*"path":"","recursive":true*' 200 "$Q_P"
  _q_pagina "${Q_SENT}SUB1" false "${ent[@]}"
  _q_regra files/list_folder '*"path":"/r","recursive":true*' 200 "$Q_P"
  # RF-189: a coleta em fluxo lista um diretorio por vez (filhos diretos); o
  # cursor de cada par vem do get_latest_cursor da propria raiz.
  _q_filhos "${Q_SENT}RAIZ1" "${Q_BASE_RAIZ[@]}"
  _q_filhos "${Q_SENT}SUB1" "${ent[@]}"
  _q_regra files/list_folder/get_latest_cursor '*"path":"","recursive":true*' 200 "{\"cursor\":\"${Q_SENT}RAIZ1\"}"
  _q_regra files/list_folder/get_latest_cursor '*"path":"/r","recursive":true*' 200 "{\"cursor\":\"${Q_SENT}SUB1\"}"
  mkdir -p "$B/l2"
  _q_rodar sync --receber --origem / --destino "$B/l"
  assert_igual 0 "$ESTADO" "raiz: $ERRO"
  _q_rodar sync --receber --origem /r --destino "$B/l2"
  assert_igual 0 "$ESTADO" "sub: $ERRO"
  local -a regs=("$B/estado/dbx"/cursor-*)
  assert_igual 2 "${#regs[@]}" 'um registro por par'
  _q_delta "${Q_SENT}RAIZ1" "${Q_SENT}RAIZ2"
  _q_delta "${Q_SENT}SUB1" "${Q_SENT}SUB2"
  : >"$B/chamadas"
  _q_rodar sync --receber --origem /r --destino "$B/l2"
  assert_igual 0 "$ESTADO" "sub, incremental: $ERRO"
  _q_valor varredura; assert_igual incremental "$Q_V" 'sub incremental'
  _q_contar files/list_folder/continue "*${Q_SENT}RAIZ1*"
  assert_igual 0 "$Q_CONT" 'o par da subpasta nunca usa o cursor da raiz'
  : >"$B/chamadas"
  _q_rodar sync --receber --origem / --destino "$B/l"
  assert_igual 0 "$ESTADO" "raiz, incremental: $ERRO"
  _q_valor varredura; assert_igual incremental "$Q_V" 'raiz incremental'
  _q_contar files/list_folder/continue "*${Q_SENT}SUB*"
  assert_igual 0 "$Q_CONT" 'o par da raiz nunca usa o cursor da subpasta'
}

harness_executar "$@"
