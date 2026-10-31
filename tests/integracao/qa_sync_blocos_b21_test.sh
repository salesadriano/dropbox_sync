#!/usr/bin/env bash
# Suite independente do QA: sync, upload e download de pasta em blocos de
# arquivos cortados por diretorio (F-101; RF-186..RF-197; TC-BLC-01..28;
# DIV-377..DIV-384). Escrita como ADVERSARIO a partir da secao 5.24 dos
# requisitos, pelo executavel real `bin/dbx` e com duplo de `curl` proprio
# (padrao das demais qa_*). Prioridade: a EXCLUSAO (RF-190, RF-191, RF-41(a)).
#
# Foco: diretorio nao observado nunca perde arquivo; so-no-destino so some com o
# pai observado nos dois lados; parcialidade em qualquer ciclo desliga a
# exclusao; origem vazia = 14 sem escrita; cursor so ao fim integral; cada
# diretorio remoto listado uma vez; corte por diretorio (ciclos no --json).
#
# shellcheck disable=SC2016
# Justificativa: o roteiro do duplo de rede chega sem expansao.
#
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
    env -i ${Q_ENV_EXTRA:+"$Q_ENV_EXTRA"} PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
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
  _q_regra files/list_folder '*"recursive":false*' 200 "$Q_P"
  _q_regra files/list_folder/get_latest_cursor '*' 200 "{\"cursor\":\"$cursor\"}"
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


# ---------------------------------------------------------------------------
# Auxiliares proprios desta suite (F-101, secao 5.24 dos requisitos).
# ---------------------------------------------------------------------------

# _b_loc <rel> — arquivo local cujo conteudo tem o content_hash do duplo (iguais).
_b_loc() {
  mkdir -p "$B/l/$(dirname -- "$1")"
  printf 'conteudo remoto' >"$B/l/$1"
}

# _b_dir <rel_do_dir|''> <nomes...> — listagem NAO recursiva do diretorio remoto;
# `dir:<nome>` e subpasta.
_b_dir() {
  local rel=$1 p n
  local -a lista=()
  shift
  p=/r${rel:+/$rel}
  for n in "$@"; do
    if [[ $n == dir:* ]]; then _q_pasta "${rel:+$rel/}${n#dir:}"; else _q_arq "${rel:+$rel/}$n"; fi
    lista+=("$Q_E")
  done
  _q_pagina "CUR$Q_N" false ${lista[@]+"${lista[@]}"}
  _q_regra files/list_folder "*\"path\":\"$p\"*" 200 "$Q_P"
}

# _b_falha <rel> [codigo] — a listagem do diretorio falha (teto de tentativas esgotado).
_b_falha() {
  _q_regra files/list_folder "*\"path\":\"/r${1:+/$1}\"*" "${2:-500}" '{"error_summary":"internal/"}'
}

_b_cursor() { _q_regra files/list_folder/get_latest_cursor '*' 200 '{"cursor":"CUR-FIM"}'; }

# _b_arvore3 [dir_que_falha] — remoto: d1,d2,d3 com a.txt/b.txt; local: o mesmo
# mais x.txt em cada diretorio e top.txt na raiz (candidatos a exclusao).
_b_arvore3() {
  _q_cen
  [[ -n ${1:-} ]] && _b_falha "$1"
  _b_dir '' dir:d1 dir:d2 dir:d3
  _b_dir d1 a.txt b.txt
  _b_dir d2 a.txt b.txt
  _b_dir d3 a.txt b.txt
  _b_cursor
  local d
  for d in d1 d2 d3; do
    _b_loc "$d/a.txt"; _b_loc "$d/b.txt"; _b_loc "$d/x.txt"
  done
  _b_loc top.txt
}

# --dry-run e opcao global: antes do comando.
_b_receber() { # <args extras...>
  local -a pre=() resto=()
  local a
  for a in "$@"; do
    if [[ $a == --dry-run || $a == --json ]]; then pre+=("$a"); else resto+=("$a"); fi
  done
  _q_rodar ${pre[@]+"${pre[@]}"} sync --receber --origem /r --destino "$B/l" ${resto[@]+"${resto[@]}"}
}

# _b_apagou <caminho_remoto> — Q_CONT = chamadas de exclusao remota que o citam.
_b_apagou() {
  local a b
  _q_contar files/delete_batch "*$1*"; a=$Q_CONT
  _q_contar files/delete_v2 "*$1*"; b=$Q_CONT
  Q_CONT=$((a + b))
}

_b_sem_cursor() { _q_registro; assert_igual '' "$Q_REG" "${1:-nenhum cursor-* deveria existir}"; }

# --- TC-BLC-11, RF-190(a): tudo observado nos dois lados, apaga o extra -------
teste_qa_blc_exclusao_so_com_o_diretorio_lido_inteiro_nos_dois_lados() {
  _b_arvore3
  _b_receber --espelhar --confirmar --bloco 2
  assert_igual 0 "$ESTADO" "execucao integral: $ERRO"
  assert_arquivo_ausente "$B/l/d1/x.txt"
  assert_arquivo_ausente "$B/l/d2/x.txt"
  assert_arquivo_ausente "$B/l/d3/x.txt"
  assert_arquivo_ausente "$B/l/top.txt"
  assert_arquivo_existe "$B/l/d2/a.txt" "arquivo igual nao pode ser apagado"
  assert_arquivo_existe "$B/l/d3/b.txt" "arquivo igual nao pode ser apagado"
}

# --- RF-190(a)/(c), TC-BLC-11: pagina remota falha no ciclo 2 ------------------
teste_qa_blc_listagem_remota_falha_no_ciclo_2_nao_apaga_o_nao_observado() {
  _b_arvore3 d2
  _b_receber --espelhar --confirmar --bloco 2
  assert_diferente 0 "$ESTADO" "falha de enumeracao nao pode sair 0"
  assert_arquivo_existe "$B/l/d2/x.txt" "diretorio que falhou nunca perde arquivo"
  assert_arquivo_existe "$B/l/d3/x.txt" "ciclo posterior a falha nao apaga"
}

# --- RF-190(c): segunda pagina do diretorio falha ------------------------------
teste_qa_blc_segunda_pagina_que_falha_desliga_a_exclusao() {
  _q_cen
  _q_arq d2/a.txt; local a=$Q_E
  _q_pagina CURP1 true "$a"
  _q_regra files/list_folder '*"path":"/r/d2"*' 200 "$Q_P"
  _q_regra files/list_folder/continue '*"cursor":"CURP1"*' 500 '{"error_summary":"internal/"}'
  _b_dir '' dir:d2
  _b_cursor
  _b_loc d2/a.txt; _b_loc d2/x.txt; _b_loc d2/c.txt
  _b_receber --espelhar --confirmar --bloco 2
  assert_diferente 0 "$ESTADO" "pagina remota falhou: nao pode sair 0"
  assert_arquivo_existe "$B/l/d2/x.txt" "pagina parcial nunca autoriza exclusao"
  assert_arquivo_existe "$B/l/d2/c.txt" "pagina parcial nunca autoriza exclusao"
}

# --- TC-BLC-13, RF-190(c): diretorio local ilegivel no ciclo 2 -----------------
teste_qa_blc_leitura_local_parcial_no_ciclo_2_desliga_a_exclusao_dos_seguintes() {
  _b_arvore3
  mkdir -p "$B/l/d2/ilegivel"
  chmod 000 "$B/l/d2/ilegivel"
  _b_receber --espelhar --confirmar --bloco 2
  chmod 700 "$B/l/d2/ilegivel"
  assert_diferente 0 "$ESTADO" "travessia local parcial nao pode sair 0"
  assert_arquivo_existe "$B/l/d2/x.txt" "o diretorio parcial nao perde arquivo"
  assert_arquivo_existe "$B/l/d3/x.txt" "ciclo seguinte a parcialidade nao apaga"
}

# --- TC-BLC-12, RF-190(b): diretorio so no destino --------------------------------
teste_qa_blc_diretorio_so_no_destino_so_e_apagado_com_o_pai_observado() {
  _b_arvore3
  _b_loc d1/fantasma/z.txt
  _b_receber --espelhar --confirmar --bloco 2
  assert_igual 0 "$ESTADO" "execucao integral: $ERRO"
  assert_arquivo_ausente "$B/l/d1/fantasma/z.txt"
  # pai (d3) nao observado: a listagem dele falha
  _b_arvore3 d3
  _b_loc d3/fantasma/z.txt
  _b_receber --espelhar --confirmar --bloco 2
  assert_diferente 0 "$ESTADO"
  assert_arquivo_existe "$B/l/d3/fantasma/z.txt" "pai nao observado: o filho so do destino fica"
}

# --- TC-BLC-15, RF-191, DIV-378: origem vazia ---------------------------------
teste_qa_blc_origem_vazia_recusa_14_sem_nenhuma_escrita_e_o_flag_libera() {
  _q_cen
  _b_dir ''
  _b_cursor
  _b_loc d1/a.txt; _b_loc top.txt
  _b_receber --espelhar --bloco 2
  assert_igual 14 "$ESTADO" "origem vazia sem confirmar: $ERRO"
  _b_receber --espelhar --confirmar --bloco 2
  assert_igual 14 "$ESTADO" "--confirmar nao dispensa a guarda: $ERRO"
  assert_arquivo_existe "$B/l/d1/a.txt"
  assert_arquivo_existe "$B/l/top.txt"
  _b_apagou /r
  assert_igual 0 "$Q_CONT" "nenhuma exclusao remota"
  _b_sem_cursor "recusa nao grava cursor"
  _b_receber --espelhar --bloco 2 --dry-run
  assert_igual 0 "$ESTADO" "dry-run nao recusa: $ERRO"
  assert_contem 'origem vazia' "$SAIDA$ERRO" "dry-run anuncia recusaria=origem vazia"
  assert_arquivo_existe "$B/l/top.txt"
  _b_receber --espelhar --confirmar --permitir-origem-vazia --bloco 2
  assert_igual 0 "$ESTADO" "com o flag: $ERRO"
  assert_arquivo_ausente "$B/l/top.txt"
}

# --- RF-191(a): vazia em varredura em ciclos, com a raiz so de pastas --------------
teste_qa_blc_origem_so_de_pastas_vazias_com_bloco_1_continua_origem_vazia_de_arquivos() {
  _q_cen
  _b_dir '' dir:d1 dir:d2
  _b_dir d1
  _b_dir d2
  _b_cursor
  _b_loc top.txt
  _b_receber --espelhar --confirmar --bloco 1
  assert_igual 14 "$ESTADO" "sem nenhum arquivo na origem e algo a apagar: $ERRO"
  assert_arquivo_existe "$B/l/top.txt"
}

# --- RF-190, direcao --enviar --------------------------------------------------------
_b_enviar_cenario() { # [dir_remoto_que_falha]
  _q_cen
  [[ -n ${1:-} ]] && _b_falha "$1"
  _b_dir '' dir:d1 dir:d2 dir:d3 dir:d9
  _b_dir d1 a.txt b.txt x.txt
  _b_dir d2 a.txt b.txt x.txt
  _b_dir d3 a.txt b.txt x.txt
  _b_dir d9 z.txt
  _b_cursor
  local d
  for d in d1 d2 d3; do _b_loc "$d/a.txt"; _b_loc "$d/b.txt"; done
}

teste_qa_blc_enviar_apaga_no_remoto_so_o_observado_nos_dois_lados() {
  _b_enviar_cenario
  _q_rodar sync --enviar --origem "$B/l" --destino /r --espelhar --confirmar --bloco 2
  _b_apagou /r/d1/x.txt; assert_igual 1 "$Q_CONT" "x.txt de d1 (observado) e apagado: $ERRO"
  _b_apagou /r/d2/x.txt; assert_igual 1 "$Q_CONT" "x.txt de d2 (observado) e apagado"
  _b_apagou /r/d3/x.txt; assert_igual 1 "$Q_CONT" "x.txt de d3 (observado) e apagado"
  _b_apagou /r/d9; assert_diferente 0 "$Q_CONT" "pasta so no destino, pai (raiz) observado: apagada"
  _b_apagou /r/d1/a.txt; assert_igual 0 "$Q_CONT" "arquivo igual nunca e apagado"
}

teste_qa_blc_enviar_listagem_do_ciclo_falha_nao_apaga_do_nao_observado() {
  _b_enviar_cenario d2
  _q_rodar sync --enviar --origem "$B/l" --destino /r --espelhar --confirmar --bloco 2
  assert_diferente 0 "$ESTADO" "falha de enumeracao remota nao sai 0"
  _b_apagou /r/d2/x.txt; assert_igual 0 "$Q_CONT" "diretorio que falhou: nenhuma exclusao"
  _b_apagou /r/d3/x.txt; assert_igual 0 "$Q_CONT" "ciclo seguinte a falha: nenhuma exclusao"
  # RF-190(d)/RF-193(b): exclusao valida de ciclo ANTERIOR a parcialidade pode ja ter
  # ocorrido; depois da primeira falha de listagem, nenhuma.
  local falha_n apaga_n
  falha_n=$(grep -n $'^files/list_folder\t.*"path":"/r/d2"' "$B/chamadas" | head -1 | cut -d: -f1)
  apaga_n=$(grep -n $'^files/delete_\(batch\|v2\)\t' "$B/chamadas" | tail -1 | cut -d: -f1)
  [[ -n $falha_n ]] || _harness_falhar "a listagem de d2 deveria ter sido tentada"
  [[ -z $apaga_n ]] || [[ $apaga_n -lt $falha_n ]] || _harness_falhar "exclusao emitida depois da falha do ciclo 2" "falha na linha $falha_n, exclusao na $apaga_n"
}

# --- TC-BLC-04/05/06/07: formacao dos ciclos (numero de ciclos no --json) --------------
_b_ciclos() { # <N> <layout...> — layout "d1=2 d2=2": remoto, ciclos no JSON
  local n=$1 par d q i
  local -a nomes=()
  shift
  _q_cen
  for par in "$@"; do nomes+=("dir:${par%%=*}"); done
  _b_dir '' "${nomes[@]}"
  for par in "$@"; do
    d=${par%%=*}; q=${par##*=}
    local -a fs=()
    for ((i = 1; i <= q; i++)); do fs+=("f$i.txt"); done
    _b_dir "$d" ${fs[@]+"${fs[@]}"}
    unset fs
  done
  _b_cursor
  _b_receber --json --bloco "$n"
}

teste_qa_blc_o_diretorio_que_cruza_n_entra_inteiro_e_fecha_o_ciclo() {
  _b_ciclos 5 d1=2 d2=2 d3=2 d4=2
  assert_igual 0 "$ESTADO" "$ERRO"
  assert_contem $'\nciclos=2\n' $'\n'"$SAIDA"$'\n' "[2,2,2,2] com N=5: {d1,d2,d3} e {d4}"
  _b_ciclos 3 d1=1 d2=1 d3=1
  assert_contem $'\nciclos=1\n' $'\n'"$SAIDA"$'\n' "[1,1,1] com N=3: um ciclo"
}

teste_qa_blc_diretorio_maior_que_n_forma_ciclo_sozinho_e_nao_e_partido() {
  _b_ciclos 5 d1=12 d2=1
  assert_igual 0 "$ESTADO" "$ERRO"
  assert_contem $'\nciclos=2\n' $'\n'"$SAIDA"$'\n' "d1(12)>N sozinho; d2 no seguinte"
  assert_arquivo_existe "$B/l/d1/f12.txt" "nenhum diretorio e partido"
  assert_arquivo_existe "$B/l/d2/f1.txt"
}

teste_qa_blc_subdiretorio_sem_arquivo_direto_e_unidade_propria_de_custo_zero() {
  _q_cen
  _b_dir '' dir:p
  _b_dir p dir:s a.txt b.txt c.txt
  _b_dir p/s x.txt
  _b_cursor
  _b_receber --json --bloco 4
  assert_igual 0 "$ESTADO" "$ERRO"
  assert_contem $'\nciclos=1\n' $'\n'"$SAIDA"$'\n' "p(3)+s(1)=4 atinge N so no fim: um ciclo"
  assert_arquivo_existe "$B/l/p/s/x.txt"
}

# --- TC-BLC-06/27: o corte nao muda o conjunto final ---------------------------------
teste_qa_blc_o_conjunto_final_independe_do_tamanho_do_bloco() {
  local n ref='' atual
  for n in 1 2 7 ''; do
    _q_cen
    _b_dir '' dir:d1 dir:d2 dir:d3
    _b_dir d1 a.txt b.txt
    _b_dir d2 dir:s c.txt
    _b_dir d2/s e.txt
    _b_dir d3
    _b_cursor
    if [[ -n $n ]]; then _b_receber --bloco "$n"; else _b_receber; fi
    assert_igual 0 "$ESTADO" "bloco '$n': $ERRO"
    atual=$(cd "$B/l" && find . -type f | LC_ALL=C sort | tr '\n' ' ')
    [[ -n $ref ]] || ref=$atual
    assert_igual "$ref" "$atual" "bloco '$n' muda o conjunto final"
  done
  assert_contem './d2/s/e.txt' "$ref"
}

# --- TC-BLC-08/09, RF-189: nao recursivo, cada diretorio uma vez --------------------------
teste_qa_blc_cada_diretorio_remoto_e_listado_uma_vez_e_nunca_recursivo() {
  _b_arvore3
  _b_receber --bloco 2
  assert_igual 0 "$ESTADO" "$ERRO"
  _q_contar files/list_folder '*"recursive":true*'
  assert_igual 0 "$Q_CONT" "nenhum list_folder recursivo na varredura completa"
  local p
  for p in /r /r/d1 /r/d2 /r/d3; do
    _q_contar files/list_folder "*\"path\":\"$p\"*"
    assert_igual 1 "$Q_CONT" "$p listado exatamente uma vez"
  done
}

teste_qa_blc_diretorio_remoto_inexistente_e_lista_vazia_e_o_ciclo_segue() {
  _q_cen
  _q_regra files/list_folder '*"path":"/r/d1"*' 409 '{"error_summary":"path/not_found/..","error":{".tag":"path","path":{".tag":"not_found"}}}'
  _b_dir '' dir:d1 dir:d2
  _b_dir d2 n.txt
  _b_cursor
  _b_receber --bloco 1
  assert_igual 0 "$ESTADO" "path/not_found nao e falha: $ERRO"
  assert_arquivo_existe "$B/l/d2/n.txt" "o ciclo seguinte roda"
}

# --- TC-BLC-26, RF-196: pasta excluida nao e percorrida nem listada -----------------------
teste_qa_blc_pasta_excluida_nao_e_listada_no_remoto() {
  _q_cen
  _b_dir '' dir:cache dir:d1
  _b_dir d1 a.txt
  _b_cursor
  _b_receber --bloco 2 --excluir 'cache/'
  assert_igual 0 "$ESTADO" "$ERRO"
  _q_contar files/list_folder '*"path":"/r/cache"*'
  assert_igual 0 "$Q_CONT" "pasta excluida nao e listada"
  assert_arquivo_existe "$B/l/d1/a.txt"
}

# --- TC-BLC-02, RF-186: validacao antes de rede e de estado -----------------------------
teste_qa_blc_valor_invalido_sai_2_antes_de_rede_e_de_estado() {
  _q_cen
  _b_dir '' dir:d1
  _b_dir d1 a.txt
  _b_cursor
  local v
  for v in 0 -1 1000001 abc +5 05 ' 5' '5 ' ''; do
    _b_receber --bloco "$v"
    assert_igual 2 "$ESTADO" "--bloco '$v' deve sair 2: $ERRO"
    assert_contem 'bloco' "$ERRO" "mensagem nomeia a opcao ('$v')"
  done
  for v in 0 abc +5 05 1000001; do
    Q_ENV_EXTRA="DBX_BLOCO=$v" _b_receber
    assert_igual 2 "$ESTADO" "DBX_BLOCO='$v' deve sair 2: $ERRO"
    assert_contem 'DBX_BLOCO' "$ERRO" "mensagem nomeia o ambiente ('$v')"
  done
  assert_igual 0 "$(wc -l <"$B/chamadas")" "nenhuma chamada de rede"
  _b_sem_cursor "nenhum estado gravado"
  Q_ENV_EXTRA="DBX_BLOCO=abc" _b_receber --bloco 3
  assert_igual 0 "$ESTADO" "a opcao vence e a variavel nao e lida: $ERRO"
  _b_receber --batch 3
  assert_igual 0 "$ESTADO" "--batch e alias: $ERRO"
}

# --- TC-BLC-16/17/18, RF-192, DIV-379: cursor so ao fim integral ------------------------------
teste_qa_blc_cursor_so_e_gravado_ao_fim_integral() {
  _b_arvore3
  _b_receber --bloco 2 --dry-run
  assert_igual 0 "$ESTADO" "$ERRO"
  _b_sem_cursor "dry-run nao grava"
  _b_arvore3 d2
  _b_receber --bloco 2
  assert_diferente 0 "$ESTADO"
  _b_sem_cursor "falha no ciclo 2 nao grava"
  _b_arvore3
  mkdir -p "$B/l/d2/ilegivel"
  chmod 000 "$B/l/d2/ilegivel"
  _b_receber --bloco 2
  chmod 700 "$B/l/d2/ilegivel"
  _b_sem_cursor "travessia local parcial nao grava"
  _b_arvore3
  _b_receber --bloco 2
  assert_igual 0 "$ESTADO" "$ERRO"
  _q_registro
  assert_diferente '' "$Q_REG" "fim integral grava o cursor"
}

teste_qa_blc_falha_no_ciclo_k_preserva_o_cursor_anterior_intacto() {
  _b_arvore3
  _b_receber --bloco 2
  assert_igual 0 "$ESTADO" "$ERRO"
  _q_registro
  local antes
  antes=$(_q_impressao "$Q_REG")
  _q_regra files/list_folder '*"path":"/r/d2"*' 500 '{"error_summary":"internal/"}'
  # a regra nova vem depois da OK: precisa ficar na frente
  { printf '%s\t%s\t%s\t%s\t\n' files/list_folder '*"path":"/r/d2"*' 500 "r$Q_N"; cat "$B/regras"; } >"$B/regras.novo"
  mv "$B/regras.novo" "$B/regras"
  _b_receber --bloco 2 --varredura-completa
  assert_diferente 0 "$ESTADO" "falha no ciclo 2"
  assert_igual "$antes" "$(_q_impressao "$Q_REG")" "cursor/retrato anteriores intactos"
}

teste_qa_blc_enviar_nao_le_nem_cria_cursor() {
  _b_enviar_cenario
  _q_rodar sync --enviar --origem "$B/l" --destino /r --bloco 2
  _b_sem_cursor "--enviar nunca cria cursor-*"
  _q_contar files/list_folder/get_latest_cursor
  assert_igual 0 "$Q_CONT" "--enviar nao pede cursor"
}

# --- TC-BLC-25, RF-196(a)/DIV-383: colisao de caixa antes de escrever --------------------------
teste_qa_blc_colisao_de_caixa_no_diretorio_recusa_antes_de_enviar() {
  _q_cen
  _b_dir '' dir:d1
  _b_dir d1
  _b_cursor
  _b_loc d1/a.txt
  printf 'outro' >"$B/l/d1/A.txt"
  _q_rodar sync --enviar --origem "$B/l" --destino /r --bloco 2
  assert_diferente 0 "$ESTADO" "colisao deve recusar"
  _q_contar files/upload '*'; local u=$Q_CONT
  _q_contar files/upload_session/start '*'; u=$((u + Q_CONT))
  _q_contar files/upload_session/finish_batch '*'; u=$((u + Q_CONT))
  assert_igual 0 "$u" "nenhum envio antes da recusa"
}

# --- TC-BLC-22, RF-194(c): dry-run nao escreve ------------------------------------------------
teste_qa_blc_dry_run_nao_escreve_nada_em_nenhum_lado() {
  _b_arvore3
  rm "$B/l/d2/a.txt"
  _b_receber --bloco 2 --espelhar --confirmar --dry-run
  assert_igual 0 "$ESTADO" "$ERRO"
  assert_arquivo_ausente "$B/l/d2/a.txt" "dry-run nao baixa"
  assert_arquivo_existe "$B/l/d1/x.txt" "dry-run nao apaga"
  _q_contar files/download '*'
  assert_igual 0 "$Q_CONT" "dry-run nao baixa"
}

# --- TC-BLC-21, RF-194(b): campos antigos intactos e agregados ---------------------------------
teste_qa_blc_json_agrega_ciclos_e_traz_o_bloco_efetivo() {
  _b_ciclos 2 d1=2 d2=2 d3=2
  assert_igual 0 "$ESTADO" "$ERRO"
  assert_contem $'\nciclos=3\n' $'\n'"$SAIDA"$'\n'
  assert_contem $'\nbloco=2\n' $'\n'"$SAIDA"$'\n' "tamanho efetivo"
  assert_contem $'\nbloco_origem=opcao\n' $'\n'"$SAIDA"$'\n' "origem do tamanho"
  assert_contem $'\nrecebidos=6\n' $'\n'"$SAIDA"$'\n' "contagem agregada dos 3 ciclos"
}


# --- RF-190(b)/RF-193: arquivo local ILEGIVEL num ciclo e parcialidade -------------------------
teste_qa_blc_arquivo_local_ilegivel_no_ciclo_desliga_a_exclusao_dali_em_diante() {
  _b_arvore3
  chmod 000 "$B/l/d2/a.txt"
  _b_receber --espelhar --confirmar --bloco 2
  chmod 600 "$B/l/d2/a.txt"
  assert_diferente 0 "$ESTADO" "execucao parcial nao sai 0: $ERRO"
  assert_arquivo_existe "$B/l/d2/x.txt" "ciclo da parcialidade nao apaga"
  assert_arquivo_existe "$B/l/d3/x.txt" "ciclo posterior a parcialidade nao apaga"
  assert_arquivo_existe "$B/l/d2/a.txt" "o arquivo ilegivel permanece"
}

# --- RF-191/RF-194: o filtro conta no escopo da origem vazia (14) -----------------------------
_b_filtro_fundo_regras() {
  _b_dir '' a.txt dir:s1 dir:s2
  _b_dir s1 b.txt
  _b_dir s2 dir:fundo
  _b_dir s2/fundo c.log
  _b_cursor
}

_b_filtro_fundo() {
  _q_cen
  _b_filtro_fundo_regras
  printf 'sobra' >"$B/l/sobra.log"
}

teste_qa_blc_filtro_sem_casamento_na_raiz_nao_recusa_por_origem_vazia() {
  _b_filtro_fundo
  _b_receber --espelhar --dry-run --json --incluir '*.log' --bloco 1
  local e1=$ESTADO s1=$SAIDA m1=$SAIDA$ERRO
  assert_igual 0 "$e1" "bloco 1: $ERRO"
  [[ $m1 != *'origem vazia'* ]] || _harness_falhar "bloco 1 recusaria por origem vazia" "$m1"
  _q_zerar
  _b_filtro_fundo_regras
  _b_receber --espelhar --dry-run --json --incluir '*.log' --bloco 1000000
  assert_igual 0 "$ESTADO" "bloco grande: $ERRO"
  [[ $SAIDA$ERRO != *'origem vazia'* ]] || _harness_falhar "bloco grande recusaria por origem vazia"
  assert_contem 'sobra.log' "$s1" "o plano com bloco 1 apaga sobra.log"
  assert_contem 'sobra.log' "$SAIDA" "o plano com bloco grande apaga sobra.log"
}

_q_impressao() { # <arquivo> — modo e conteudo
  if [[ -f $1 ]]; then
    printf '%s ' "$(stat -c %a -- "$1")"
    sha256sum <"$1"
  else
    printf 'ausente\n'
  fi
}

harness_executar "$@"
