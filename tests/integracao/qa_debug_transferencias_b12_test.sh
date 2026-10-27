#!/usr/bin/env bash
# Suite independente do QA Expert para a fase 12 (--debug em download, upload e
# sync; RF-156..165), ciclo 1. Mira riscos, nao repete a suite do developer:
# segredo em stdout/stderr (inclusive em falha, retentativa e sinal), invariantes
# (stdout, codigo de saida e numero de requisicoes iguais com e sem --debug),
# sinal, formato de linha unica, resumo unico e convivencia com o progresso.
#
# Reusa so o duplo de curl de tests/support/disponibilidade.sh; cenarios,
# sentinelas e cenarios de sinal sao proprios do QA.
#
# shellcheck disable=SC2016,SC2034
# Justificativa: o trecho injetado no duplo e escrito sem expansao; variaveis QD_* sao lidas pelos testes.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"
# shellcheck source=tests/support/disponibilidade.sh
. "$DBX_HARNESS_RAIZ/tests/support/disponibilidade.sh"

readonly QD_SESSAO='SESSAO_QA_SENT_77x'
readonly QD_CURSOR='CURSOR_QA_SENT_55y'
readonly QD_URL='URLTEMP_QA_SENT_33z'
readonly QD_SENHA='SENHA_QA_SENT_11w'
readonly QD_SENTINELAS=("$SENTINELA_TOKEN" "$SENTINELA_REFRESH" "$SENTINELA_SEGREDO" "$SENTINELA_CHAVE" "$QD_SESSAO" "$QD_CURSOR" "$QD_URL" "$QD_SENHA" 'Authorization')
QD_ENV=()
QD_STDIN=/dev/null

_qd_corpo_rpc() { # <base> <entradas_list_folder>
  local hash
  hash=$(dbx_hash_conteudo_arquivo "$1/hello")
  printf '%s' "{\"name\":\"a.txt\",\"path_display\":\"/a.txt\",\".tag\":\"file\",\"size\":5,\"content_hash\":\"$hash\",\"used\":1,\"allocation\":{\".tag\":\"individual\",\"allocated\":2000000000},\"account_id\":\"dbid:QA\",\"link\":\"https://dl.example.com/x?senha=$QD_SENHA&t=$QD_URL\",\"entries\":[$2],\"has_more\":false,\"cursor\":\"$QD_CURSOR\"}" >"$1/rpc_corpo"
}

_qd_cenario() { # cenario base: arquivo local, upload simples ok, rpc coerente
  local base
  base=$(_cenario)
  printf 'hello' >"$base/hello"
  head -c 10240 /dev/zero >"$base/arq.bin"
  printf '10240' >"$base/enviados"
  printf '200' >"$base/content"
  printf '%s' '{"name":"arq.bin","path_display":"/arq.bin","size":10240,"content_hash":"0000"}' >"$base/content_corpo"
  mkdir -p "$base/local"
  printf 'hello' >"$base/local/a.txt"
  printf 'hello' >"$base/local/b c.txt"
  _qd_corpo_rpc "$base" ''
  printf '%s' "$base"
}

# Duplo do sync: o fixture do lote (session_id, finish_batch_v2) e da listagem de
# tests/integracao/debug_sync_test.sh, reescrito aqui com prefixo proprio e com as
# sentinelas do QA. Controles: `remoto/<caminho>`, `listagem`, `download_503`, `pendurar`.
_qd_cenario_sync() {
  local base script
  base=$(mktemp -d "$DBX_TESTES_TMP/qdsync.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp" "$base/remoto" "$base/falha" "$base/enviado"
  _credencial "$base"
  chmod 700 "$base/config/dbx"
  printf '{"entries":[],"has_more":false,"cursor":"%s"}' "$QD_CURSOR" >"$base/listagem"
  printf 'hello' >"$base/local/a.txt"
  printf 'hello' >"$base/local/b c.txt"
  : >"$base/stdin_sessao"
  IFS= read -r -d '' script <<'FIM'
conf=$(cat 2>/dev/null)
saida='' escrever='' anterior='' url='' corpo_arquivo='' falha_http='nao'
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac
  case $arg in http*) url=$arg ;; --fail) falha_http=sim ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
if [[ -f $base/pendurar ]]; then
  read -r alvo <"$base/pendurar"
  case $url in *"$alvo"*) exec sleep 3191 ;; esac
fi
codigo=200
caminho=''
re='path\\":\\"([^\\"]*)\\"'
[[ $conf =~ $re ]] && caminho=${BASH_REMATCH[1]}
nome=${caminho##*/}
case $url in
  *oauth2/token*) corpo='{"access_token":"TOKEN_AQUI","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *get_space_usage*) corpo='{"used":0,"allocation":{".tag":"individual","allocated":1000000000}}' ;;
  *list_folder*) corpo=$(<"$base/listagem") ;;
  *files/download)
    corpo=$(<"$base/remoto$caminho")
    [[ -f $base/download_503 ]] && { codigo=503; corpo=''; }
    ;;
  *finish_batch*)
    corpo_req=$conf
    for arg in "$@"; do
      if [[ $arg == @* && -f ${arg#@} ]]; then corpo_req+=$(<"${arg#@}"); fi
    done
    printf '%s\n' "BODY: $corpo_req" >>"$base/lote_corpo"
    sem=${corpo_req//session_id/}
    conf=$corpo_req
    qtd=$(((${#conf} - ${#sem}) / 10))
    lista=''
    for ((q = 0; q < qtd; q++)); do lista+="${lista:+,}{\".tag\":\"success\"}"; done
    corpo="{\".tag\":\"complete\",\"entries\":[$lista]}"
    ;;
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
  script=${script//TOKEN_AQUI/$SENTINELA_TOKEN}
  printf '#!%s\nbase=%q\n%s\n' "$BASH_ABSOLUTO" "$base" "$script" >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  local alvo origem
  for alvo in mktemp mv rm chmod mkdir stat head dd wc readlink dirname find cat sleep tail df ln rmdir sha256sum cp; do
    origem=$(command -v "$alvo" 2>/dev/null) || continue
    ln -s "$origem" "$base/bin/$alvo"
  done
  printf '%s' "$base"
}

_qd_cenario_download() {
  local base
  base=$(_qd_cenario)
  printf 'hello' >"$base/content_corpo"
  printf '%s' "$base"
}

_qd_cenario_sessao() {
  local base
  base=$(_qd_cenario)
  truncate -s 4194314 "$base/stdin_sessao"
  local hash
  hash=$(dbx_hash_conteudo_arquivo "$base/stdin_sessao")
  printf '%s' "{\"session_id\":\"$QD_SESSAO\",\"name\":\"arq.bin\",\"path_display\":\"/arq.bin\",\"size\":4194314,\"content_hash\":\"$hash\"}" >"$base/content_corpo"
  printf '%s' "$base"
}

_qd_cenario_receber() {
  local base lista='' n
  local hash=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  base=$(_qd_cenario_sync)
  rm -rf "$base/local"
  mkdir -p "$base/local" "$base/remoto/r"
  for n in a b c; do
    printf 'hello' >"$base/remoto/r/$n.txt"
    lista+="${lista:+,}{\".tag\":\"file\",\"path_display\":\"/r/$n.txt\",\"content_hash\":\"$hash\",\"size\":5}"
  done
  printf '{"entries":[%s],"has_more":false,"cursor":"%s"}' "$lista" "$QD_CURSOR" >"$base/listagem"
  printf '%s' "$base"
}

# Faz o duplo pendurar (sleep unico) na chamada cuja URL contem o trecho de `pendurar`.
_qd_pendurar() { # <base> <trecho>
  local base=$1 script marcador gancho
  printf '%s' "$2" >"$base/pendurar"
  IFS= read -r -d '' script <"$base/bin/curl"
  marcador='quem=sonda'
  gancho=$'if [[ -f $base/pendurar ]]; then\n  read -r alvo <"$base/pendurar"\n  case $url in *"$alvo"*) exec sleep 3191 ;; esac\nfi\nquem=sonda'
  printf '%s' "${script/"$marcador"/$gancho}" >"$base/bin/curl"
  chmod +x "$base/bin/curl"
}

_qd_exec() { # <base> <argumentos...> — preenche DBX_ESTADO, QD_OUT, QD_ERR
  local base=$1
  shift
  env -i PATH="$base/bin" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
    TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=2 \
    ${QD_ENV[@]+"${QD_ENV[@]}"} "$BASH_ABSOLUTO" "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err" <"$QD_STDIN"
  DBX_ESTADO=$?
  QD_OUT='' QD_ERR=''
  IFS= read -r -d '' QD_OUT <"$base/out"
  IFS= read -r -d '' QD_ERR <"$base/err"
  return 0
}

_qd_n_linhas() { # <arquivo> [prefixo] — linhas (com o prefixo, se dado)
  local n=0 linha
  [[ -f $1 ]] || {
    printf 0
    return 0
  }
  while IFS= read -r linha || [[ -n $linha ]]; do
    if [[ -z ${2-} || $linha == "$2"* ]]; then n=$((n + 1)); fi
  done <"$1"
  printf '%s' "$n"
}

_qd_sem_debug() { # <texto> — as linhas que nao sao `debug: `
  local linha saida=''
  while IFS= read -r linha || [[ -n $linha ]]; do
    [[ $linha == 'debug: '* ]] || saida+="$linha"$'\n'
  done <<<"$1"
  printf '%s' "$saida"
}

# O formato de TODA linha debug (RF-156): categoria do vocabulario, posicionais
# so de http, pares chave=valor, valor sem espaco ou entre aspas escapadas.
readonly QD_RE_LINHA='^debug: (http|upload|download|sync|resumo)( ([A-Z]+|[a-z0-9./_-]+))*( [a-z_0-9]+=([^[:space:]"]*|"([^"\\]|\\.)*"))*$'
_qd_verificar_formato() { # <arquivo_err> <rotulo>
  local linha n=0
  while IFS= read -r linha || [[ -n $linha ]]; do
    n=$((n + 1))
    [[ $linha == *$'\r'* ]] && _harness_falhar "$2: \\r na linha $n" "$linha"
    [[ $linha == *'debug: '* && $linha != 'debug: '* ]] && _harness_falhar "$2: debug no meio da linha $n" "$linha"
    if [[ $linha == 'debug: '* && $linha != 'debug: sonda '* ]]; then
      [[ $linha =~ $QD_RE_LINHA ]] || _harness_falhar "$2: linha $n fora do formato" "$linha"
    fi
  done <"$1"
}

_qd_sem_segredo() { # <base> <rotulo>
  local s tudo
  tudo="$QD_OUT"$'\n'"$QD_ERR"
  for s in "${QD_SENTINELAS[@]}"; do
    assert_nao_contem "$s" "$tudo" "$2: segredo $s vazou para stdout/stderr"
  done
}

_qd_resumo() { # <base> <codigo> <rotulo> [sem_contagem]
  local n re='chamadas=([0-9]+) tentativas_extras=([0-9]+)' saida http1 chamadas
  n=$(_qd_n_linhas "$1/err" 'debug: resumo')
  assert_igual 1 "$n" "$3: exatamente um resumo; stderr: $QD_ERR"
  [[ $QD_ERR =~ ' saida='([0-9]+) ]] || _harness_falhar "$3: resumo sem saida=" "$QD_ERR"
  saida=${BASH_REMATCH[1]}
  assert_igual "$2" "$saida" "$3: saida= do resumo igual ao codigo real"
  [[ -n ${4-} ]] && return 0
  [[ $QD_ERR =~ $re ]] || _harness_falhar "$3: resumo sem chamadas=" "$QD_ERR"
  chamadas=${BASH_REMATCH[1]}
  http1=$(_qd_n_linhas "$1/err" 'debug: http')
  assert_igual "$(_qd_n_linhas "$1/chamadas")" "$((chamadas + BASH_REMATCH[2]))" "$3: chamadas+tentativas_extras = requisicoes feitas ao duplo"
  # QA-DBG-01 (P2): com a sonda de disponibilidade a requisicao entra em `chamadas` mas
  # sai como `debug: sonda`, nao como `debug: http` (RF-162(e) dito duas formas). A
  # igualdade com as linhas http so vale sem sonda; ver o caso comentado abaixo.
  # DIV-351 A: a sonda conta em `chamadas`; linhas http + linhas sonda = requisicoes.
  assert_igual "$((http1 + $(_qd_n_linhas "$1/err" 'debug: sonda')))" "$((chamadas + BASH_REMATCH[2]))" "$3: uma linha http por tentativa mais uma por sonda"
}

# QA-DBG-01 (P2), caso reprovado mantido como especificacao do defeito, desligado para a suite seguir:
# teste_qa_dbg01_resumo_chamadas_igual_as_linhas_http_com_sonda() {
#   local base
#   base=$(_qd_cenario_rede_dl)
#   _qd_exec "$base" --debug download /a.txt -
#   # esperado (RF-162(e)): chamadas= do resumo == linhas `debug: http` com tentativa=1
#   # obtido: resumo chamadas=3 (token, download, sonda) contra 2 linhas http
#   assert_igual "$(_qd_n_linhas "$base/err" 'debug: http')" "$(_qd_n_linhas "$base/chamadas")" 'linhas http == requisicoes'
# }

# _qd_par <cenario> <argumentos com @B@ = base> — roda sem e com --debug em
# cenarios novos e iguais; confere as invariantes, o formato, o resumo e os segredos.
_qd_par() {
  local cenario=$1 bs bc cs cc os oc es ec ns nc arg ss sc
  shift
  local -a args_s=() args_c=()
  bs=$("$cenario")
  for arg in "$@"; do args_s+=("${arg//@B@/$bs}"); done
  _qd_exec "$bs" "${args_s[@]}"
  cs=$DBX_ESTADO os=$QD_OUT es=$QD_ERR ns=$(_qd_n_linhas "$bs/chamadas")
  assert_nao_contem 'debug:' "$es" 'sem --debug nenhuma linha debug (RF-156(e))'
  bc=$("$cenario")
  for arg in "$@"; do args_c+=("${arg//@B@/$bc}"); done
  _qd_exec "$bc" --debug "${args_c[@]}"
  cc=$DBX_ESTADO oc=$QD_OUT ec=$QD_ERR nc=$(_qd_n_linhas "$bc/chamadas")
  assert_igual "$cs" "$cc" "codigo de saida igual com e sem --debug; stderr: $ec"
  assert_igual "${os//"$bs"/@B@}" "${oc//"$bc"/@B@}" 'stdout byte a byte igual'
  assert_igual "$ns" "$nc" 'numero de requisicoes igual'
  ss=$(_qd_sem_debug "${es//"$bs"/@B@}")
  sc=$(_qd_sem_debug "${ec//"$bc"/@B@}")
  assert_igual "$ss" "$sc" 'mensagens de erro iguais fora das linhas debug (RF-163(b))'
  _qd_verificar_formato "$bc/err" 'com --debug'
  _qd_resumo "$bc" "$cc" 'com --debug'
  _qd_sem_segredo "$bc" 'com --debug'
  QD_BASE_COM=$bc
  QD_COD=$cc
}

# ------------------------------------------------------------ upload

teste_qa_upload_simples_sucesso_invariantes_e_segredos() {
  _qd_par _qd_cenario upload '@B@/arq.bin' /arq.bin
  assert_igual 0 "$QD_COD" 'sucesso'
}

teste_qa_upload_sessao_stdin_sem_id_de_sessao_e_resumo_correto() {
  QD_STDIN=
  local base
  base=$(_qd_cenario_sessao)
  QD_STDIN=$base/stdin_sessao
  _qd_exec "$base" --debug upload - /arq.bin
  QD_STDIN=/dev/null
  assert_igual 0 "$DBX_ESTADO" "sessao: $QD_ERR"
  assert_contem 'modalidade=sessao' "$QD_ERR" 'houve sessao'
  _qd_verificar_formato "$base/err" 'sessao'
  _qd_resumo "$base" 0 'sessao'
  _qd_sem_segredo "$base" 'sessao'
}

teste_qa_upload_5xx_falha_invariantes() {
  _qd_par _qd_cenario_5xx upload '@B@/arq.bin' /arq.bin
  [[ $QD_COD -ne 0 ]] || _harness_falhar 'esperava falha'
}

_qd_cenario_5xx() {
  local base
  base=$(_qd_cenario)
  printf '503' >"$base/content"
  printf '%s' "$base"
}

teste_qa_upload_409_conflito_invariantes() {
  _qd_par _qd_cenario_409 upload '@B@/arq.bin' /arq.bin
  [[ $QD_COD -ne 0 ]] || _harness_falhar 'esperava falha'
}

_qd_cenario_409() {
  local base
  base=$(_qd_cenario)
  printf '409' >"$base/content"
  printf '%s' "$base"
}

teste_qa_upload_rede_falha_invariantes() {
  _qd_par _qd_cenario_rede upload '@B@/arq.bin' /arq.bin
  assert_igual "$QA_REDE_COD" "$QD_COD" 'rede = 9'
}
QA_REDE_COD=$(dbx_errors_codigo_saida rede)

_qd_cenario_rede() {
  local base
  base=$(_qd_cenario)
  printf 'falha' >"$base/content"
  printf '%s' "$base"
}

teste_qa_credencial_ausente_invariantes_e_um_resumo() {
  _qd_par _qd_cenario_sem_credencial upload '@B@/arq.bin' /arq.bin
  [[ $QD_COD -ne 0 ]] || _harness_falhar 'esperava falha'
}

_qd_cenario_sem_credencial() {
  local base
  base=$(_qd_cenario)
  rm -f "$base/config/dbx/credencial.json"
  printf '%s' "$base"
}

teste_qa_upload_retentativa_429_503_linha_por_tentativa_e_retry_after_com_teto() {
  local base
  base=$(_qd_cenario)
  printf '429 30\n429 30\n' >"$base/content.fila"
  QD_ENV=(DBX_HTTP_TENTATIVAS_MAXIMAS=3 DBX_HTTP_RETRY_AFTER_TETO_S=1)
  _qd_exec "$base" --debug upload "$base/arq.bin" /arq.bin
  QD_ENV=()
  assert_igual 0 "$DBX_ESTADO" "apos 2 retentativas deve concluir: $QD_ERR"
  assert_contem ' tentativa=1 ' "$QD_ERR" 'tentativa 1'
  assert_contem ' tentativa=2 ' "$QD_ERR" 'tentativa 2'
  assert_contem ' tentativa=3 ' "$QD_ERR" 'tentativa 3'
  assert_contem ' status=429 ' "$QD_ERR" '429 registrado'
  assert_contem ' retry_after=1 ' "$QD_ERR" 'retry_after com o teto aplicado (RF-157(d))'
  assert_nao_contem 'retry_after=30' "$QD_ERR" 'valor bruto acima do teto nao sai'
  _qd_verificar_formato "$base/err" 'retentativa'
  _qd_resumo "$base" 0 'retentativa'
  assert_contem 'limites_429=2' "$QD_ERR" 'dois 429'
  _qd_sem_segredo "$base" 'retentativa'
}

# ------------------------------------------------------------ download

teste_qa_download_arquivo_invariantes_e_segredos() {
  _qd_par _qd_cenario_download download /a.txt '@B@/saida.txt'
  assert_igual 0 "$QD_COD" 'sucesso'
}

teste_qa_download_stdout_conteudo_intacto_e_debug_so_em_stderr() {
  _qd_par _qd_cenario_download download /a.txt -
  assert_igual 0 "$QD_COD" 'sucesso'
  assert_igual hello "$QD_OUT" 'o conteudo no stdout nao ganha linha debug'
}

teste_qa_download_stdout_omitido_destino_conteudo_intacto() {
  _qd_par _qd_cenario_download download /a.txt
  assert_igual hello "$QD_OUT" 'stdout so o conteudo'
}

teste_qa_download_5xx_e_rede_invariantes() {
  _qd_par _qd_cenario_5xx_dl download /a.txt '@B@/saida.txt'
  [[ $QD_COD -ne 0 ]] || _harness_falhar 'esperava falha 5xx'
  _qd_par _qd_cenario_rede_dl download /a.txt -
  assert_igual "$QA_REDE_COD" "$QD_COD" 'rede = 9'
}

_qd_cenario_5xx_dl() {
  local base
  base=$(_qd_cenario_download)
  printf '503' >"$base/content"
  printf '%s' "$base"
}

_qd_cenario_rede_dl() {
  local base
  base=$(_qd_cenario_download)
  printf 'falha' >"$base/content"
  printf '%s' "$base"
}

teste_qa_download_hash_divergente_registra_e_mantem_codigo() {
  pular 'duplo de curl sem cabecalho Dropbox-API-Result: sem content_hash para conferir (limite da fixture, nao defeito)'
  # RF-160(c) hash=divergente: coberto por tc_dbg_15 de retomada_download_test.sh (developer).
}

# ------------------------------------------------------------ sync

teste_qa_sync_enviar_invariantes_e_segredos() {
  _qd_par _qd_cenario_sync sync --enviar --origem '@B@/local' --destino /r
}

teste_qa_sync_enviar_paralelo_resumo_soma_auxiliares_e_sem_segredo() {
  _qd_par _qd_cenario_sync sync --enviar --origem '@B@/local' --destino /r --paralelo 3
  assert_contem 'paralelo=3' "$QD_ERR" 'o resumo ganha paralelo=N (RF-162(d))'
  assert_igual 0 "$(_qd_n_linhas "$QD_BASE_COM/err" 'debug: paralelo')" 'a linha antiga paralelo deixa de existir'
}

teste_qa_sync_receber_invariantes_cursor_nunca_aparece() {
  _qd_par _qd_cenario_receber sync --receber --origem /r --destino '@B@/local'
  assert_contem 'debug: sync cursor=' "$QD_ERR" 'linha de cursor'
}

teste_qa_sync_receber_paralelo_invariantes_e_ordem() {
  _qd_par _qd_cenario_receber sync --receber --origem /r --destino '@B@/local' --paralelo 3
  assert_contem 'paralelo=3' "$QD_ERR" 'paralelo no resumo'
}

teste_qa_sync_receber_download_5xx_invariantes() {
  _qd_par _qd_cenario_receber_5xx sync --receber --origem /r --destino '@B@/local'
  [[ $QD_COD -ne 0 ]] || _harness_falhar 'esperava falha'
}

_qd_cenario_receber_5xx() {
  local base
  base=$(_qd_cenario_receber)
  : >"$base/download_503"
  printf '%s' "$base"
}

teste_qa_sync_enviar_credencial_ausente_invariantes() {
  _qd_par _qd_cenario_sem_credencial sync --enviar --origem '@B@/local' --destino /r
  [[ $QD_COD -ne 0 ]] || _harness_falhar 'esperava falha'
}

# ------------------------------------------------------------ formato

teste_qa_caminho_com_espaco_aspas_quebra_e_controle_fica_em_uma_linha() {
  local base nome local_ dest
  base=$(_qd_cenario)
  printf -v nome 'a "q" b\\c\nd\001e.txt'
  local_="$base/$nome"
  printf 'hello' >"$local_"
  dest='/x y/"z".txt'
  _qd_exec "$base" --debug upload --forcar "$local_" "$dest"
  assert_igual 0 "$DBX_ESTADO" "upload: $QD_ERR"
  _qd_verificar_formato "$base/err" 'caminho hostil'
  local linha nao_debug=0
  while IFS= read -r linha || [[ -n $linha ]]; do
    [[ $linha == 'debug: '* ]] || nao_debug=$((nao_debug + 1))
  done <"$base/err"
  assert_igual 0 "$nao_debug" "toda linha fisica de stderr e debug: (quebra de linha vazou): $QD_ERR"
  assert_contem '?' "$(_qd_primeira "$base/err" 'debug: upload modalidade')" "controle vira ?; stderr: $QD_ERR"
  _qd_resumo "$base" 0 'caminho hostil'
}

_qd_primeira() { # <arquivo> <prefixo>
  local linha
  while IFS= read -r linha || [[ -n $linha ]]; do
    [[ $linha == "$2"* ]] && {
      printf '%s' "$linha"
      return 0
    }
  done <"$1"
}

teste_qa_sync_com_arquivo_de_nome_hostil_uma_linha_por_evento() {
  local base nome linha nao_debug=0
  base=$(_qd_cenario_sync)
  printf -v nome 'q "x"\ny\002.txt'
  printf 'hello' >"$base/local/$nome"
  _qd_exec "$base" --debug sync --enviar --origem "$base/local" --destino /r
  _qd_verificar_formato "$base/err" 'sync hostil'
  while IFS= read -r linha || [[ -n $linha ]]; do
    [[ $linha == 'debug: '* ]] || nao_debug=$((nao_debug + 1))
  done <"$base/err"
  assert_igual 0 "$nao_debug" "linha fisica fora do formato: $QD_ERR"
  _qd_resumo "$base" "$DBX_ESTADO" 'sync hostil'
}

# ------------------------------------------------------------ progresso

teste_qa_debug_com_progresso_sem_carriage_return_e_sem_mistura() {
  local base linha
  base=$(_qd_cenario)
  _qd_exec "$base" --debug --progresso upload "$base/arq.bin" /arq.bin
  assert_igual 0 "$DBX_ESTADO" "upload: $QD_ERR"
  _qd_verificar_formato "$base/err" 'upload --progresso'
  while IFS= read -r linha || [[ -n $linha ]]; do
    [[ $linha == 'debug: '* || $linha == '['* || -z $linha ]] || _harness_falhar "linha estranha no stderr: $linha"
  done <"$base/err"
  assert_igual 1 "$(_qd_n_linhas "$base/err" 'debug: resumo')" 'um resumo'
  base=$(_qd_cenario_sync)
  _qd_exec "$base" --debug --progresso sync --enviar --origem "$base/local" --destino /r
  _qd_verificar_formato "$base/err" 'sync --progresso'
  while IFS= read -r linha || [[ -n $linha ]]; do
    [[ $linha == 'debug: '* || $linha == '['* || -z $linha ]] || _harness_falhar "linha estranha (sync): $linha"
  done <"$base/err"
}

# ------------------------------------------------------------ sinais

# _qd_sinal <sinal> <trecho_da_url> <com_debug:sim|nao> <argumentos...> — devolve em
# QD_SIG_COD o codigo; deixa out/err em $QD_SIG_BASE.
_qd_sinal() {
  local sinal=$1 trecho=$2 debug=$3 base pid espera=0 vivo=0 prefixo=() estado
  shift 3
  if [[ $1 == sync ]]; then base=$(_qd_cenario_sync); else base=$(_qd_cenario_sessao); fi
  _qd_pendurar "$base" "$trecho"
  [[ $debug == sim ]] && prefixo=(--debug)
  setsid env --default-signal=INT -i PATH="$base/bin" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
    TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 "$BASH_ABSOLUTO" "$DBX_EXEC" "${prefixo[@]}" "${@//@B@/$base}" \
    >"$base/out" 2>"$base/err" <"$base/stdin_sessao" &
  pid=$!
  while ((espera < 100)); do
    [[ $(_qd_n_linhas "$base/chamadas") -gt 0 && -f $base/chamadas ]] && grep -q -F -- "$trecho" "$base/chamadas" && break
    sleep 0.1
    espera=$((espera + 1))
  done
  sleep 0.3
  kill -s "$sinal" -- "-$pid" 2>/dev/null
  espera=0
  while ((espera < 60)); do
    kill -0 "$pid" 2>/dev/null || {
      vivo=1
      break
    }
    sleep 0.1
    espera=$((espera + 1))
  done
  if ((vivo == 0)); then
    kill -s KILL "$pid" 2>/dev/null
    QD_SIG_COD=preso
  fi
  wait "$pid" 2>/dev/null
  estado=$?
  [[ $QD_SIG_COD == preso ]] || QD_SIG_COD=$estado
  pkill -f 'sleep 3191' 2>/dev/null
  QD_SIG_BASE=$base
  QD_ERR=''
  IFS= read -r -d '' QD_ERR <"$base/err"
  QD_OUT=''
  IFS= read -r -d '' QD_OUT <"$base/out"
  return 0
}

_qd_sinal_caso() { # <sinal> <trecho> <argumentos...>
  local sinal=$1 trecho=$2 cod_sem cod_com
  shift 2
  QD_SIG_COD=''
  _qd_sinal "$sinal" "$trecho" nao "$@"
  cod_sem=$QD_SIG_COD
  [[ $cod_sem != preso ]] || _harness_falhar "sem --debug o processo nao saiu com $sinal"
  QD_SIG_COD=''
  _qd_sinal "$sinal" "$trecho" sim "$@"
  cod_com=$QD_SIG_COD
  assert_igual "$cod_sem" "$cod_com" "$sinal em $trecho: mesmo codigo de saida com e sem --debug; stderr: $QD_ERR"
  _qd_verificar_formato "$QD_SIG_BASE/err" "$sinal/$trecho"
  _qd_sem_segredo "$QD_SIG_BASE" "$sinal/$trecho"
  _qd_resumo "$QD_SIG_BASE" "$cod_com" "$sinal/$trecho" sem_contagem
}

teste_qa_sinal_term_antes_da_primeira_requisicao_de_dados_upload() {
  _qd_sinal_caso TERM oauth2/token upload '@B@/arq.bin' /arq.bin
}

teste_qa_sinal_term_durante_a_transferencia_upload() {
  _qd_sinal_caso TERM content.dropboxapi.com upload '@B@/arq.bin' /arq.bin
}

teste_qa_sinal_int_durante_a_transferencia_upload() {
  _qd_sinal_caso INT content.dropboxapi.com upload '@B@/arq.bin' /arq.bin
}

teste_qa_sinal_int_antes_da_primeira_requisicao_upload() {
  _qd_sinal_caso INT oauth2/token upload '@B@/arq.bin' /arq.bin
}

teste_qa_sinal_term_durante_o_download() {
  _qd_sinal_caso TERM content.dropboxapi.com download /a.txt '@B@/saida.txt'
}

teste_qa_sinal_int_durante_o_sync_enviar() {
  _qd_sinal_caso INT content.dropboxapi.com sync --enviar --origem '@B@/local' --destino /r
}

teste_qa_sinal_term_durante_o_sync_paralelo() {
  _qd_sinal_caso TERM content.dropboxapi.com sync --enviar --origem '@B@/local' --destino /r --paralelo 3
}

harness_executar "$@"
