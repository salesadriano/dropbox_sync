#!/usr/bin/env bash
# Testes ponta a ponta da fase 5 do backlog: link temporario e link
# compartilhado (F-15, F-16; RF-84 a RF-92; TC-LTP, TC-CMP, TC-SNH, TC-LEX,
# TC-LST, TC-RVG, TC-SHE, TC-CPL-10, TC-DOC-04, TC-TST-08).
#
# O DUPLO DE `curl` RESPONDE POR REGRA, como o de `recuperacao_test`: linhas
# `endpoint<TAB>filtro_do_corpo<TAB>codigo<TAB>arquivo[<TAB>uma]` em `regras`;
# a primeira que casa responde, e chamada sem regra responde 400 e fica marcada
# `SEM_REGRA`. Cada chamada fica em `chamadas` (`endpoint corpo`), e e por ela
# que os casos provam que um endpoint NAO foi chamado.
#
# PARA A SENHA (RF-86(g)), o duplo registra ALEM do corpo, por invocacao: o
# `argv` (o dele e o dos dois processos acima dele, por /proc), o ambiente (o
# dele e o do processo do `dbx`) e a entrada de opcoes lida por `-K -`. O
# sentinela tem de aparecer SO no arquivo de corpo, durante a chamada, e nunca
# em `argv`, ambiente, opcoes, saida, erro, `--debug` ou arquivo restante em
# `TMPDIR` (privado de cada caso).
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e os roteiros chegam sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly SENTINELA_REFRESH='RT_SENTINELA_refresh_c5d6e7'
readonly SENTINELA_SEGREDO='AS_SENTINELA_segredo_f8g9h0'
readonly SENTINELA_CHAVE='AK_SENTINELA_chave_i1j2k3'
readonly SENTINELA_TOKEN='sl.SENTINELA_token_curto_l4m5n6'
readonly SENHA='SENHA_SENTINELA_p9o8i7'
readonly LINK_TEMP='https://dl.dropboxusercontent.com/apitl/1/LINKTEMP_SENTINELA_u7y6'
DORMIR=$(command -v sleep)
readonly DORMIR

# _ambiente [raiz_remota] — credencial, duplo de `curl`, `date` proibido e regras.
_ambiente() {
  local raiz=${1:-/} base
  base=$(mktemp -d "$DBX_TESTES_TMP/compartilhamento.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/respostas" "$base/tmp"
  chmod 700 "$base/config/dbx"
  printf '{"versao":1,"app_key":"%s","app_secret":"%s","refresh_token":"%s","raiz_remota":"%s"}' \
    "$SENTINELA_CHAVE" "$SENTINELA_SEGREDO" "$SENTINELA_REFRESH" "$raiz" \
    >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  : >"$base/regras"
  {
    printf '#!%s\n' "$BASH"
    printf 'base=%q\n' "$base"
    printf 'token=%q\n' "$SENTINELA_TOKEN"
  } >"$base/bin/curl"
  cat >>"$base/bin/curl" <<'FIM'
opcoes=$(cat)
{ printf '%s\n' "$opcoes"; printf -- '--\n'; } >>"$base/opcoes.log"
{
  printf 'curl'; printf ' %q' "$@"; printf '\n'
  for p in "$PPID" "$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')"; do
    [[ -r /proc/$p/cmdline ]] && { tr '\0' ' ' </proc/$p/cmdline; printf '\n'; }
  done
} >>"$base/argv.log"
{
  for v in $(compgen -e); do printf '%s=%s\n' "$v" "${!v}"; done
  pai=$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')
  [[ -r /proc/$pai/environ ]] && tr '\0' '\n' </proc/$pai/environ
  printf -- '--\n'
} >>"$base/env.log"
saida=''; escrever=''; anterior=''; url=''; dados=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) dados=${arg#@} ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
pedido=''
[[ -n $dados && -r $dados ]] && IFS= read -r -d '' pedido <"$dados"
[[ -n $dados ]] && printf '%s\n' "$dados" >>"$base/arquivos_de_corpo.log"
# QA-B5-05: modo do arquivo de corpo no instante da chamada.
[[ -n $dados && -e $dados ]] && printf '%s\n' "$(stat -c %a "$dados")" >>"$base/modos.log"
endpoint=${url#https://api.dropboxapi.com/2/}
codigo=400 corpo='{"error_summary":"sem_regra/"}'
if [[ $url == *oauth2/token* ]]; then
  printf 'oauth2/token\n' >>"$base/chamadas"
  codigo=200
  corpo="{\"access_token\":\"$token\",\"token_type\":\"bearer\",\"expires_in\":14400}"
else
  printf '%s %s\n' "$endpoint" "$pedido" >>"$base/chamadas"
  achou=nao n=0
  while IFS=$'\t' read -r ep filtro cod arq vez; do
    n=$((n + 1))
    [[ -n $ep ]] || continue
    # shellcheck disable=SC2053
    [[ $endpoint == $ep && $pedido == $filtro ]] || continue
    if [[ $vez == uma ]]; then
      [[ -e $base/usada.$n ]] && continue
      : >"$base/usada.$n"
    fi
    achou=sim codigo=$cod corpo=''
    [[ -n $arq && -r $base/respostas/$arq ]] && IFS= read -r -d '' corpo <"$base/respostas/$arq"
    # `@N@` vira o numero da chamada: cursor sempre novo (QA-B5-14).
    if [[ $corpo == *@N@* ]]; then
      total=0
      while IFS= read -r _l; do total=$((total + 1)); done <"$base/chamadas"
      corpo=${corpo//@N@/$total}
    fi
    break
  done <"$base/regras"
  [[ $achou == sim ]] || printf 'SEM_REGRA %s\n' "$endpoint" >>"$base/chamadas"
fi
case $codigo in
  TERM) kill -TERM 0; sleep 5; exit 1 ;;
  REDE) printf 'curl: (7) Failed to connect\n' >&2; exit 7 ;;
esac
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  # RF-84(f), RF-85(e): nenhuma data vem do utilitario `date`.
  printf '#!%s\nprintf "date %%s\\n" "$*" >>%q\nexit 1\n' "$BASH" "$base/proibido" >"$base/bin/date"
  chmod +x "$base/bin/curl" "$base/bin/date"
  printf '%s' "$base"
}

_seq=0
_regra() { # <base> <endpoint> <filtro> <codigo> <corpo> [uma]
  local base=$1 ep=$2 filtro=$3 codigo=$4 corpo=$5 vez=${6:-}
  _seq=$((_seq + 1))
  printf '%s' "$corpo" >"$base/respostas/r$_seq"
  printf '%s\t%s\t%s\t%s\t%s\n' "$ep" "$filtro" "$codigo" "r$_seq" "$vez" >>"$base/regras"
}

# _rodar <base> <argumentos...> — sem terminal; entrada em DBX_T_ENTRADA (arquivo).
_rodar() {
  local base=$1
  shift
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
    ${DBX_T_ENV:+"$DBX_T_ENV"} \
    timeout -k 2 "${DBX_T_TETO:-60}" setsid -w bash "$DBX_EXEC" "$@" <"${DBX_T_ENTRADA:-/dev/null}" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  # Teto de tempo: comando que pendura reprova (124) em vez de prender a suite.
  [[ $DBX_ESTADO -ne 124 && $DBX_ESTADO -ne 137 ]] || _harness_falhar "o comando pendurou ($DBX_ESTADO): $*"
  DBX_SAIDA='' DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _entrada <base> <texto> — arquivo de entrada padrao com o texto exato.
_entrada() {
  printf '%s' "$2" >"$1/entrada"
  DBX_T_ENTRADA="$1/entrada"
}

_esperar_texto() { # <arquivo> <texto>
  local espera=0 conteudo=''
  while [[ $espera -lt 200 ]]; do
    [[ -r $1 ]] && IFS= read -r -d '' conteudo <"$1"
    [[ $conteudo == *"$2"* ]] && return 0
    "$DORMIR" 0.05
    espera=$((espera + 1))
  done
  _harness_falhar "nao apareceu [$2]" "$conteudo"
}

# _rodar_tty <base> <primeira> <segunda|-|TERM> <argumentos...> — entrada num
# pseudo-terminal (script(1)). A resposta so e escrita depois da pergunta: antes
# dela o terminal ainda ecoaria o que chega. `-` nao responde a confirmacao;
# `TERM` manda o sinal ao `dbx` em vez da primeira resposta.
_rodar_tty() {
  local base=$1 primeira=$2 segunda=$3 linha arg fd pid conteudo=''
  shift 3
  command -v script >/dev/null 2>&1 || pular 'script(1) ausente: sem terminal para o caso'
  printf -v linha 'bash -c %q _ %q' 'printf "%s" "$$" >"$1/pid"; shift; exec bash "$@"' "$base"
  printf -v arg ' %q' "$DBX_EXEC"
  linha+=$arg
  for arg in "$@"; do printf -v arg ' %q' "$arg" && linha+=$arg; done
  linha+='; printf "\nESTADO=%s\n" "$?"; stty -a'
  rm -f "$base/fifo" "$base/pid"
  mkfifo "$base/fifo"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    script -qec "$linha" /dev/null <"$base/fifo" >"$base/out" 2>&1 &
  pid=$!
  exec {fd}>"$base/fifo"
  _esperar_texto "$base/out" 'senha do link:'
  if [[ $primeira == 'TERM' ]]; then
    kill -TERM "$(<"$base/pid")"
  else
    printf '%s\n' "$primeira" >&"$fd"
    if [[ $segunda != '-' ]]; then
      _esperar_texto "$base/out" 'confirme a senha:'
      printf '%s\n' "$segunda" >&"$fd"
    fi
  fi
  wait "$pid"
  exec {fd}>&-
  IFS= read -r -d '' conteudo <"$base/out"
  DBX_SAIDA=$conteudo
  DBX_ESTADO=''
  [[ $conteudo =~ ESTADO=([0-9]+) ]] && DBX_ESTADO=${BASH_REMATCH[1]}
  return 0
}

_chamadas() { _harness_contar "$2" "$1/chamadas"; } # <base> <trecho>
_nenhuma_chamada() { assert_arquivo_ausente "$1/chamadas" "$2"; }
_saida_nula() { tr '\0' '|' <"$1/out"; }

# _residuo <base> — entradas que sobraram no TMPDIR privado.
_residuo() {
  local entrada lista=''
  for entrada in "$1"/tmp/* "$1"/tmp/.[!.]*; do
    [[ -e $entrada ]] && lista+=" ${entrada##*/}"
  done
  printf '%s' "$lista"
}

# _sem_senha_em_canais <base> — RF-86(g): fora do corpo, o sentinela nao existe.
_sem_senha_em_canais() {
  local base=$1 arquivo conteudo
  for arquivo in argv.log env.log opcoes.log out err; do
    [[ -f $base/$arquivo ]] || continue
    IFS= read -r -d '' conteudo <"$base/$arquivo"
    assert_segredo_ausente "$SENHA" "$conteudo" "a senha nao aparece em $arquivo"
  done
  conteudo=$(grep -rl -- "$SENHA" "$base/tmp" 2>/dev/null || true)
  assert_igual '' "$conteudo" 'nenhum arquivo restante em TMPDIR traz a senha'
  assert_igual '' "$(_residuo "$base")" 'TMPDIR sem residuo'
}

# Massa ----------------------------------------------------------------------

# _link <url> <path_lower|-> <visibilidade> <true|false> [expires] [tag]
_link() {
  local caminho='' expira=''
  [[ $2 != '-' ]] && caminho=",\"path_lower\":\"$2\""
  [[ -n ${5:-} ]] && expira=",\"expires\":\"$5\""
  printf '{".tag":"%s","url":"%s","name":"a.txt"%s,"link_permissions":{"resolved_visibility":{".tag":"%s"},"require_password":%s,"can_revoke":true}%s}' \
    "${6:-file}" "$1" "$caminho" "$3" "$4" "$expira"
}
readonly URL_A='https://www.dropbox.com/scl/fi/aaa/a.txt?rlkey=k1'
readonly URL_B='https://www.dropbox.com/scl/fi/bbb/a.txt?rlkey=k2'
readonly URL_P='https://www.dropbox.com/scl/fo/ppp/docs?rlkey=k3'
F_A='*"path":"/docs/a.txt"*'
JA_EXISTE='{"error_summary":"shared_link_already_exists/..","error":{".tag":"shared_link_already_exists"}}'

_existente() { # <base> <links_json> — create recusa e a listagem devolve os links
  _regra "$1" sharing/create_shared_link_with_settings "$F_A" 409 "$JA_EXISTE"
  _regra "$1" sharing/list_shared_links "$F_A" 200 "{\"links\":[$2],\"has_more\":false}"
}

META_TEMP='{"name":"a.txt","path_lower":"/docs/a.txt","path_display":"/docs/a.txt","rev":"0000000c3","size":3,"content_hash":"hc3","server_modified":"2026-10-05T10:00:00Z"}'
_temp_ok() { # <base> [metadata]
  _regra "$1" files/get_temporary_link "$F_A" 200 "{\"metadata\":${2:-$META_TEMP},\"link\":\"$LINK_TEMP\"}"
}

# ===========================================================================
# TC-LTP — dbx link-temporario (RF-84)
# ===========================================================================

teste_ltp01_arquivo_valido_gera_link_com_validade_e_metadados() {
  local base
  base=$(_ambiente)
  _temp_ok "$base"
  _rodar "$base" link-temporario /docs/./a.txt
  assert_igual 0 "$DBX_ESTADO" "link temporario sai 0: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" 'files/get_temporary_link {"path":"/docs/a.txt"}')" 'uma chamada, caminho normalizado'
  assert_igual 2 "$(_harness_contar '' "$base/chamadas")" 'so a renovacao e a chamada'
  assert_contem 'operacao=link_temporario' "$DBX_SAIDA" 'operacao'
  assert_contem "link=$LINK_TEMP" "$DBX_SAIDA" 'link no resultado'
  assert_contem 'validade_segundos=14400' "$DBX_SAIDA" 'validade'
  [[ $DBX_SAIDA =~ expira_em_estimado=([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z) ]] ||
    _harness_falhar 'expira_em_estimado em UTC' "$DBX_SAIDA"
  assert_contem 'rev=0000000c3' "$DBX_SAIDA" 'metadados de info'
  assert_contem 'content_hash=hc3' "$DBX_SAIDA" 'content_hash'
}

teste_ltp02_uso_invalido_sem_rede() {
  local base
  base=$(_ambiente)
  _rodar "$base" link-temporario
  assert_igual 2 "$DBX_ESTADO" 'sem argumento'
  _rodar "$base" link-temporario /a /b
  assert_igual 2 "$DBX_ESTADO" 'dois argumentos'
  _rodar "$base" link-temporario docs/a.txt
  assert_igual 2 "$DBX_ESTADO" 'relativo'
  _rodar "$base" link-temporario --publico /a
  assert_igual 2 "$DBX_ESTADO" 'opcao desconhecida'
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_ltp03_fora_da_raiz_e_controle_sao_recusados_sem_chamada() {
  local base caminho
  base=$(_ambiente /docs)
  for caminho in /outra/a.txt /docs/../fora.txt $'/docs/a\n.txt' $'/docs/a\r.txt'; do
    _rodar "$base" link-temporario "$caminho"
    assert_igual 13 "$DBX_ESTADO" "recusado: [$caminho]"
  done
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_ltp04_pasta_tipo_sem_link_e_inexistente() {
  local base
  base=$(_ambiente)
  _regra "$base" files/get_temporary_link '*"/pasta"*' 409 '{"error_summary":"path/not_file/.."}'
  _regra "$base" files/get_temporary_link '*"/doc.gdoc"*' 409 '{"error_summary":"unsupported_file/.."}'
  _regra "$base" files/get_temporary_link '*"/nada"*' 409 '{"error_summary":"path/not_found/.."}'
  _rodar "$base" link-temporario /pasta
  assert_igual 2 "$DBX_ESTADO" 'pasta e uso invalido'
  assert_contem 'link temporario existe so para arquivo; para pasta use dbx compartilhar' "$DBX_ERRO" 'mensagem'
  _rodar "$base" link-temporario /doc.gdoc
  assert_igual 2 "$DBX_ESTADO" 'unsupported_file'
  assert_contem 'este tipo de arquivo nao tem link temporario' "$DBX_ERRO" 'mensagem'
  _rodar "$base" link-temporario /nada
  assert_igual 4 "$DBX_ESTADO" 'inexistente'
  _rodar "$base" link-temporario /
  assert_igual 2 "$DBX_ESTADO" 'a raiz da conta e pasta'
}

teste_ltp05_permissao_e_escopo() {
  local base
  base=$(_ambiente)
  _regra "$base" files/get_temporary_link '*"/a"*' 409 '{"error_summary":"not_allowed/.."}'
  _regra "$base" files/get_temporary_link '*"/b"*' 409 '{"error_summary":"email_not_verified/.."}'
  _regra "$base" files/get_temporary_link '*"/c"*' 401 '{"error_summary":"missing_scope/..","error":{".tag":"missing_scope","required_scope":"files.content.read"}}'
  _rodar "$base" link-temporario /a
  assert_igual 6 "$DBX_ESTADO" 'not_allowed'
  _rodar "$base" link-temporario /b
  assert_igual 6 "$DBX_ESTADO" 'email_not_verified'
  _rodar "$base" link-temporario /c
  assert_igual 5 "$DBX_ESTADO" 'missing_scope'
}

teste_ltp06_resposta_sem_path_lower_repetida_ou_fora_da_raiz_nao_imprime_o_link() {
  local base meta
  base=$(_ambiente /docs)
  for meta in '{"name":"a.txt","path_display":"/docs/a.txt"}' \
    '{"name":"a.txt","path_lower":"/docs/a.txt","path_lower":"/docs/a.txt"}' \
    '{"name":"a.txt","path_lower":"/fora/a.txt"}'; do
    : >"$base/regras"
    _temp_ok "$base" "$meta"
    _rodar "$base" link-temporario /docs/a.txt
    assert_igual 10 "$DBX_ESTADO" "resposta recusada: $meta"
    assert_nao_contem 'LINKTEMP_SENTINELA' "$DBX_SAIDA" 'link fora da saida'
    assert_nao_contem 'LINKTEMP_SENTINELA' "$DBX_ERRO" 'link fora do erro'
  done
}

teste_ltp07_dry_run_so_consulta_metadado() {
  local base
  base=$(_ambiente)
  _regra "$base" files/get_metadata "$F_A" 200 '{".tag":"file","name":"a.txt","path_display":"/docs/a.txt","rev":"0000000c3"}'
  _regra "$base" files/get_metadata '*"/pasta"*' 200 '{".tag":"folder","name":"pasta","path_display":"/pasta"}'
  _rodar "$base" --dry-run link-temporario /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "simulacao sai 0: $DBX_ERRO"
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'simulado'
  assert_igual 0 "$(_chamadas "$base" 'files/get_temporary_link')" 'zero get_temporary_link'
  assert_igual 1 "$(_chamadas "$base" 'files/get_metadata')" 'so get_metadata'
  _rodar "$base" --dry-run link-temporario /pasta
  assert_igual 2 "$DBX_ESTADO" 'pasta recusada tambem na simulacao'
}

teste_ltp08_link_so_no_resultado_nunca_em_stderr_nem_debug() {
  local base
  base=$(_ambiente)
  _temp_ok "$base"
  _rodar "$base" --debug link-temporario /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'sucesso'
  assert_contem 'LINKTEMP_SENTINELA' "$DBX_SAIDA" 'link na saida padrao'
  assert_nao_contem 'LINKTEMP_SENTINELA' "$DBX_ERRO" 'nunca em stderr'
}

teste_ltp09_json_null_mesmos_campos_e_nenhum_date() {
  local base
  base=$(_ambiente)
  _temp_ok "$base"
  _rodar "$base" --json link-temporario /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'json'
  assert_contem 'contrato=' "$DBX_SAIDA" 'saida estruturada com a versao do contrato'
  assert_contem 'validade_segundos=14400' "$DBX_SAIDA" 'campo na saida estruturada'
  assert_contem 'expira_em_estimado=' "$DBX_SAIDA" 'estimativa na saida estruturada'
  _rodar "$base" --null link-temporario /docs/a.txt
  assert_contem 'validade_segundos=14400|' "$(_saida_nula "$base")" 'registro com nulo'
  assert_arquivo_ausente "$base/proibido" 'nenhum utilitario date'
}

teste_ltp10_alias_sem_estado_e_sem_trava() {
  local base
  base=$(_ambiente)
  _temp_ok "$base"
  _rodar "$base" temp-link /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "o alias temp-link e o mesmo comando: $DBX_ERRO"
  assert_arquivo_ausente "$base/estado" 'nada em lib/state, nenhuma trava'
  assert_igual '' "$(_residuo "$base")" 'TMPDIR limpo'
}

# ===========================================================================
# TC-CMP — dbx compartilhar (RF-85)
# ===========================================================================

teste_cmp01_sem_visibilidade_e_uso_invalido_antes_de_tudo() {
  local base
  base=$(_ambiente)
  _rodar "$base" compartilhar /docs/a.txt
  assert_igual 2 "$DBX_ESTADO" 'sem visibilidade'
  assert_contem 'informe a visibilidade: --publico, --equipe ou --senha; nada e publicado por omissao' "$DBX_ERRO" 'mensagem'
  _rodar "$base" compartilhar /docs/a.txt --expira 7d
  assert_igual 2 "$DBX_ESTADO" 'expiracao nao e visibilidade'
  _rodar "$base" share /docs/a.txt
  assert_igual 2 "$DBX_ESTADO" 'pelo alias tambem'
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_cmp02_publico_cria_com_audience_public_sem_campo_depreciado() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt public false)"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "publico sai 0: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" '"settings":{"audience":"public","require_password":false}')" 'audience public'
  assert_igual 0 "$(_chamadas "$base" 'requested_visibility')" 'sem o campo depreciado'
  assert_contem 'situacao=criado' "$DBX_SAIDA" 'criado'
  assert_contem "url=$URL_A" "$DBX_SAIDA" 'url'
  assert_contem 'visibilidade=public' "$DBX_SAIDA" 'visibilidade resolvida'
  assert_contem 'senha=nao' "$DBX_SAIDA" 'sem senha'
  assert_contem 'tipo=arquivo' "$DBX_SAIDA" 'tipo'
}

teste_cmp03_equipe_usa_audience_team() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt team_only false)"
  _rodar "$base" compartilhar --equipe /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "equipe: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" '"audience":"team","require_password":false')" 'audience team'
  assert_contem 'visibilidade=team_only' "$DBX_SAIDA" 'resolvida'
  assert_nao_contem 'visibilidade_pedida' "$DBX_SAIDA" 'igual a pedida'
}

teste_cmp04_combinacoes_invalidas_sao_uso_invalido_sem_rede() {
  local base
  base=$(_ambiente)
  _rodar "$base" compartilhar --publico --equipe /a
  assert_igual 2 "$DBX_ESTADO" '--publico --equipe'
  _rodar "$base" compartilhar --equipe --senha-stdin /a
  assert_igual 2 "$DBX_ESTADO" '--equipe --senha-stdin'
  _rodar "$base" compartilhar --equipe --senha /a
  assert_igual 2 "$DBX_ESTADO" '--equipe --senha'
  _rodar "$base" compartilhar --senha --senha-stdin /a
  assert_igual 2 "$DBX_ESTADO" '--senha --senha-stdin'
  _rodar "$base" compartilhar --listar --publico
  assert_igual 2 "$DBX_ESTADO" '--listar com visibilidade'
  _rodar "$base" compartilhar --listar --expira 7d
  assert_igual 2 "$DBX_ESTADO" '--listar com --expira'
  _rodar "$base" compartilhar --revogar "$URL_A" --publico
  assert_igual 2 "$DBX_ESTADO" '--revogar com visibilidade'
  _rodar "$base" compartilhar --listar --revogar "$URL_A"
  assert_igual 2 "$DBX_ESTADO" '--listar com --revogar'
  _rodar "$base" compartilhar --revogar "$URL_A" /a
  assert_igual 2 "$DBX_ESTADO" '--revogar com posicional'
  _rodar "$base" compartilhar --publico /a /b
  assert_igual 2 "$DBX_ESTADO" 'dois caminhos'
  _rodar "$base" compartilhar --publico
  assert_igual 2 "$DBX_ESTADO" 'sem caminho'
  _rodar "$base" compartilhar --publico --expira
  assert_igual 2 "$DBX_ESTADO" '--expira sem valor'
  _rodar "$base" compartilhar --revogar
  assert_igual 2 "$DBX_ESTADO" '--revogar sem url'
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_cmp04_publico_com_senha_equivale_a_senha() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt password true)"
  _entrada "$base" "$SENHA"$'\n'
  _rodar "$base" compartilhar --publico --senha-stdin /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "--publico --senha-stdin: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" '"audience":"public","require_password":true,"link_password"')" 'como --senha'
}

teste_cmp05_expira_validas_viram_expires_normalizado_no_corpo() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt public false 2099-12-31T23:59:59Z)"
  _rodar "$base" compartilhar --publico --expira 2099-12-31 /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "data: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" '"expires":"2099-12-31T23:59:59Z"')" 'fim do dia UTC'
  assert_contem 'expira=2099-12-31T23:59:59Z' "$DBX_SAIDA" 'expira na saida'
  _rodar "$base" compartilhar --publico --expires 7d /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'duracao pelo alias'
  assert_igual 1 "$(_chamadas "$base" '"expires":"20[0-8][0-9]-[0-9-]*T[0-9:]*Z"}')" 'duracao vira carimbo'
  assert_arquivo_ausente "$base/proibido" 'nenhum utilitario date'
}

teste_cmp06_07_expira_invalida_ou_no_passado_sem_rede() {
  local base valor
  base=$(_ambiente)
  for valor in 2099-02-30 '2099-12-31T10:00:00+03:00' 0d 07d 3651d 8761h 1w '' 2000-01-01; do
    _rodar "$base" compartilhar --publico --expira "$valor" /docs/a.txt
    assert_igual 2 "$DBX_ESTADO" "--expira [$valor]"
  done
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_cmp08_fora_da_raiz_antes_da_senha_e_sem_rede() {
  local base
  base=$(_ambiente /docs)
  _rodar "$base" compartilhar --publico /fora/a.txt
  assert_igual 13 "$DBX_ESTADO" 'fora da raiz'
  _rodar "$base" compartilhar --publico $'/docs/a\n.txt'
  assert_igual 13 "$DBX_ESTADO" 'quebra de linha'
  # Sem terminal, --senha recusaria com 2: sair 13 prova que a senha nao foi pedida.
  _rodar "$base" compartilhar --senha /fora/a.txt
  assert_igual 13 "$DBX_ESTADO" 'confinamento antes da senha'
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_cmp09_raiz_da_conta_e_recusada_e_a_raiz_remota_e_alvo_valido() {
  local base
  base=$(_ambiente)
  _rodar "$base" compartilhar --publico /
  assert_igual 2 "$DBX_ESTADO" 'conta inteira'
  assert_contem 'compartilhar a conta inteira nao e permitido' "$DBX_ERRO" 'mensagem'
  _nenhuma_chamada "$base" 'zero chamadas'
  base=$(_ambiente /docs)
  _regra "$base" sharing/create_shared_link_with_settings '*"path":"/docs"*' 200 "$(_link "$URL_P" /docs public false '' folder)"
  _rodar "$base" compartilhar --publico /docs
  assert_igual 0 "$DBX_ESTADO" "a raiz remota e alvo valido: $DBX_ERRO"
  assert_contem 'tipo=pasta' "$DBX_SAIDA" 'pasta aceita'
}

teste_cmp11_visibilidade_resolvida_diferente_avisa_e_sai_zero() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt team_only false)"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'sai 0'
  assert_contem 'visibilidade=team_only' "$DBX_SAIDA" 'a resolvida'
  assert_contem 'visibilidade_pedida=public' "$DBX_SAIDA" 'a pedida'
  assert_contem 'o servico aplicou team_only no lugar de public' "$DBX_ERRO" 'aviso'
}

teste_cmp12_dry_run_so_lista_e_nao_le_a_senha() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/list_shared_links "$F_A" 200 '{"links":[],"has_more":false}'
  # Entrada vazia: se fosse lida, a senha vazia seria recusada com 2.
  _entrada "$base" ''
  _rodar "$base" --dry-run compartilhar --senha-stdin /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "simulacao: $DBX_ERRO"
  assert_contem 'situacao=criaria' "$DBX_SAIDA" 'criaria'
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'simulado'
  assert_contem 'senha=sim' "$DBX_SAIDA" 'o plano mostra senha sim'
  assert_igual 1 "$(_chamadas "$base" 'sharing/list_shared_links .*"direct_only":true')" 'so a listagem do alvo'
  assert_igual 0 "$(_chamadas "$base" 'create_shared_link\|modify_shared_link')" 'zero escrita'
  # Sem terminal, --senha tambem nao e pedida na simulacao.
  _rodar "$base" --dry-run compartilhar --senha /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'sem pergunta na simulacao'
}

teste_cmp13_json_e_null_com_os_campos() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt public false)"
  _rodar "$base" --json compartilhar --publico /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'json'
  local campo
  for campo in situacao url visibilidade senha expira; do
    assert_contem "$campo=" "$DBX_SAIDA" "campo $campo na saida estruturada"
  done
  _rodar "$base" --null compartilhar --publico /docs/a.txt
  assert_contem 'situacao=criado|' "$(_saida_nula "$base")" 'registro com nulo'
}

teste_cmp14_she02_conta_sem_permissao_de_configuracao_sai_6_com_remedio() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 409 '{"error_summary":"settings_error/not_authorized/.."}'
  _rodar "$base" compartilhar --equipe /docs/a.txt
  assert_igual 6 "$DBX_ESTADO" 'permissao'
  # DIV-122: "Basic <palavra>" e esquema de autenticacao para a redacao; a frase usa virgula.
  assert_contem 'no plano Basic, so link publico, sem senha e sem expiracao' "$DBX_ERRO" 'mensagem do plano'
  assert_contem 'use --publico sem --expira' "$DBX_ERRO" 'remedio'
}

teste_cmp15_aliases_em_ingles() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt team_only false)"
  _rodar "$base" share --team --expires 2099-01-01 /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "aliases: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" '"audience":"team".*"expires":"2099-01-01T23:59:59Z"')" 'mesmo corpo'
  _rodar "$base" share --public /docs/a.txt
  assert_igual 2 "$(_chamadas "$base" 'create_shared_link')" '--public'
}

teste_cmp16_nada_em_lib_state_nem_trava() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt public false)"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'sucesso'
  assert_arquivo_ausente "$base/estado" 'nenhum estado'
}

# ===========================================================================
# TC-SNH — senha (RF-86)
# ===========================================================================

teste_snh01_terminal_pergunta_duas_vezes_sem_eco_e_envia_no_corpo() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt password true)"
  _rodar_tty "$base" "$SENHA" "$SENHA" compartilhar --senha /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "terminal: $DBX_SAIDA"
  assert_contem 'senha do link:' "$DBX_SAIDA" 'primeira pergunta'
  assert_contem 'confirme a senha:' "$DBX_SAIDA" 'confirmacao'
  assert_segredo_ausente "$SENHA" "$DBX_SAIDA" 'sem eco no terminal'
  assert_igual 1 "$(_chamadas "$base" "\"require_password\":true,\"link_password\":\"$SENHA\"")" 'senha no corpo'
  _sem_senha_em_canais "$base"
}

teste_snh02_confirmacao_divergente_sai_14_sem_chamada() {
  local base
  base=$(_ambiente)
  _rodar_tty "$base" "$SENHA" "${SENHA}x" compartilhar --senha /docs/a.txt
  assert_igual 14 "$DBX_ESTADO" "divergente: $DBX_SAIDA"
  _nenhuma_chamada "$base" 'nada criado nem modificado'
}

teste_snh03_senha_sem_terminal_e_uso_invalido() {
  local base
  base=$(_ambiente)
  _rodar "$base" compartilhar --senha /docs/a.txt
  assert_igual 2 "$DBX_ESTADO" 'sem terminal'
  assert_contem 'sem terminal use --senha-stdin' "$DBX_ERRO" 'remedio'
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_snh04_senha_stdin_le_so_a_primeira_linha() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt password true)"
  _entrada "$base" "$SENHA"$'\nsegunda linha\n'
  _rodar "$base" compartilhar --senha-stdin /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "stdin: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" "\"link_password\":\"$SENHA\"}")" 'so a primeira linha'
  assert_contem 'senha=sim' "$DBX_SAIDA" 'senha sim, nunca o valor'
  _entrada "$base" "$SENHA"
  _rodar "$base" compartilhar --password-stdin /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'fim da entrada sem quebra de linha e pelo alias'
  _sem_senha_em_canais "$base"
}

teste_snh05_06_senha_invalida_e_recusada_sem_rede_e_sem_citar() {
  local base valor longa
  base=$(_ambiente)
  printf -v longa '%*s' 1025 ''
  for valor in '' $'\n' "$SENHA"$'\r\n' "$SENHA"$'\001' "${longa// /a}" "$SENHA"$'\xc3\n'; do
    _entrada "$base" "$valor"
    _rodar "$base" compartilhar --senha-stdin /docs/a.txt
    assert_igual 2 "$DBX_ESTADO" "senha recusada (${#valor} bytes)"
    assert_segredo_ausente "$SENHA" "$DBX_ERRO" 'mensagem sem a senha'
  done
  _nenhuma_chamada "$base" 'zero chamadas'
  _rodar_tty "$base" '' - compartilhar --senha /docs/a.txt
  assert_igual 2 "$DBX_ESTADO" "vazia no terminal: $DBX_SAIDA"
  _nenhuma_chamada "$base" 'zero chamadas no terminal'
}

teste_snh07_senha_na_linha_de_comando_e_recusada_sem_citar() {
  local base forma
  base=$(_ambiente)
  for forma in "--senha=$SENHA" "--senha-stdin=$SENHA" "--password=$SENHA" "--password-stdin=$SENHA"; do
    _rodar "$base" compartilhar --publico "$forma" /docs/a.txt
    assert_igual 2 "$DBX_ESTADO" 'forma com valor'
    assert_contem 'a senha nunca e aceita na linha de comando; use --senha ou --senha-stdin' "$DBX_ERRO" 'mensagem'
    assert_segredo_ausente "$SENHA" "$DBX_ERRO" 'sem o valor'
  done
  _rodar "$base" compartilhar /docs/a.txt --senha "$SENHA"
  assert_igual 2 "$DBX_ESTADO" 'posicional excedente'
  assert_segredo_ausente "$SENHA" "$DBX_ERRO" 'a recusa nao cita o excedente'
  _rodar "$base" compartilhar --publico "--pass=$SENHA" /docs/a.txt
  assert_igual 2 "$DBX_ESTADO" 'opcao desconhecida com valor'
  assert_segredo_ausente "$SENHA" "$DBX_ERRO" 'a recusa nao cita o valor da opcao'
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_snh08_variavel_de_ambiente_e_ignorada() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt public false)"
  DBX_T_ENV="DBX_SENHA=$SENHA" _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'publica sem senha'
  DBX_T_ENV="DBX_PASSWORD=$SENHA" _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 0 "$(_chamadas "$base" "$SENHA")" 'o sentinela do ambiente nao chega ao corpo'
  assert_igual 0 "$(_chamadas "$base" 'link_password')" 'nenhuma senha enviada'
}

teste_snh09_10_sentinela_so_no_corpo_em_sucesso_e_em_erro() {
  local base resposta
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt password true)"
  _entrada "$base" "$SENHA"$'\n'
  _rodar "$base" --debug compartilhar --senha-stdin /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "sucesso: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" "$SENHA")" 'presente no corpo da chamada'
  _sem_senha_em_canais "$base"
  _rodar "$base" --json compartilhar --senha-stdin /docs/a.txt
  _sem_senha_em_canais "$base"
  _rodar "$base" --null compartilhar --senha-stdin /docs/a.txt
  _sem_senha_em_canais "$base"
  for resposta in '409|{"error_summary":"settings_error/not_authorized/.."}' \
    '409|{"error_summary":"settings_error/invalid_settings/.."}' '500|erro interno' \
    '409|{"error_summary":"access_denied/.."}' '400|corpo nao json'; do
    : >"$base/regras"
    _regra "$base" sharing/create_shared_link_with_settings "$F_A" "${resposta%%|*}" "${resposta#*|}"
    _rodar "$base" --debug compartilhar --senha-stdin /docs/a.txt
    assert_diferente 0 "$DBX_ESTADO" "erro ${resposta%%|*}"
    _sem_senha_em_canais "$base"
  done
}

teste_snh11_corpo_de_erro_que_ecoa_a_senha_e_mascarado() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 400 "link_password=$SENHA invalido"
  _entrada "$base" "$SENHA"$'\n'
  _rodar "$base" compartilhar --senha-stdin /docs/a.txt
  assert_igual 2 "$DBX_ESTADO" 'recusa do servico'
  assert_igual 1 "$(_chamadas "$base" 'create_shared_link')" 'o servico recebeu o pedido e ecoou a senha'
  # QA-B5-08/09 (ciclo 3): com a senha no pedido, nenhum texto do servico e
  # citado; so a mensagem propria, o codigo HTTP e a tag reconhecida.
  assert_contem 'codigo HTTP 400' "$DBX_ERRO" 'diagnostico proprio com o codigo'
  assert_nao_contem 'invalido' "$DBX_ERRO" 'nenhum trecho do corpo do servico'
  assert_segredo_ausente "$SENHA" "$DBX_ERRO" 'mascarado pela redacao'
}

teste_snh12_term_durante_a_chamada_nao_deixa_arquivo() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" TERM ''
  _entrada "$base" "$SENHA"$'\n'
  _rodar "$base" compartilhar --senha-stdin /docs/a.txt
  assert_igual 14 "$DBX_ESTADO" 'sinal: nao concluida'
  _sem_senha_em_canais "$base"
}

teste_snh13_sinal_durante_a_leitura_restaura_o_eco_e_sai_14() {
  local base
  base=$(_ambiente)
  _rodar_tty "$base" TERM - compartilhar --senha /docs/a.txt
  assert_igual 14 "$DBX_ESTADO" "sinal na leitura: $DBX_SAIDA"
  [[ $DBX_SAIDA =~ (^|[[:space:]])-echo([[:space:]]|$) ]] &&
    _harness_falhar 'o eco do terminal ficou desligado' "$DBX_SAIDA"
  [[ $DBX_SAIDA =~ (^|[[:space:]])echo([[:space:]]|$) ]] ||
    _harness_falhar 'stty mostra o eco ligado' "$DBX_SAIDA"
  _nenhuma_chamada "$base" 'zero chamadas'
  assert_igual '' "$(_residuo "$base")" 'sem residuo'
}

teste_snh14_senha_com_caracteres_especiais_chega_identica() {
  local base senha="${SENHA} a\"b\\c ação" corpo
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt password true)"
  _entrada "$base" "$senha"$'\n'
  _rodar "$base" compartilhar --senha-stdin /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "especiais: $DBX_ERRO"
  corpo=$(grep '^sharing/create' "$base/chamadas")
  corpo=${corpo#* }
  bash -c '. "$1/lib/errors.sh"; . "$1/lib/json.sh"; dbx_json_contexto t; dbx_json_analisar "$2" &&
    dbx_json_valor settings link_password >/dev/null && [[ $DBX_JSON_RESULTADO == "$3" ]]' _ \
    "$DBX_HARNESS_RAIZ" "$corpo" "$senha" || _harness_falhar 'JSON invalido ou valor diferente da senha'
}

# ===========================================================================
# TC-LEX — link existente (RF-87)
# ===========================================================================

teste_lex01_estado_igual_reusa_sem_escrita() {
  local base
  base=$(_ambiente)
  _existente "$base" "$(_link "$URL_A" /docs/a.txt public false)"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "reuso: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" 'sharing/list_shared_links {"path":"/docs/a.txt","direct_only":true}')" 'listagem do alvo'
  assert_igual 0 "$(_chamadas "$base" 'modify_shared_link')" 'zero modify'
  assert_contem 'situacao=existente' "$DBX_SAIDA" 'existente'
  assert_contem "url=$URL_A" "$DBX_SAIDA" 'o link existente'
}

teste_lex02_metadados_no_erro_nao_dispensam_a_listagem() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 409 \
    "{\"error_summary\":\"shared_link_already_exists/..\",\"error\":{\".tag\":\"shared_link_already_exists\",\"shared_link_already_exists\":{\".tag\":\"metadata\",\"url\":\"$URL_B\"}}}"
  _regra "$base" sharing/list_shared_links "$F_A" 200 "{\"links\":[$(_link "$URL_A" /docs/a.txt public false)],\"has_more\":false}"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'reuso'
  assert_igual 1 "$(_chamadas "$base" 'list_shared_links')" 'listou mesmo com metadados'
  assert_contem "url=$URL_A" "$DBX_SAIDA" 'a fonte e a listagem'
}

teste_lex03_link_de_ancestral_nao_e_candidato() {
  local base
  base=$(_ambiente)
  _existente "$base" "$(_link "$URL_P" /docs public false '' folder),$(_link "$URL_A" /Docs/A.txt public false)"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "um candidato: $DBX_ERRO"
  assert_contem "url=$URL_A" "$DBX_SAIDA" 'so o do alvo (caixa ASCII dobrada)'
}

teste_lex04_nenhum_candidato_sai_10() {
  local base
  base=$(_ambiente)
  _existente "$base" "$(_link "$URL_P" /docs public false '' folder)"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'nenhum candidato'
  assert_contem 'o servico diz que o link existe mas nao o lista' "$DBX_ERRO" 'mensagem'
}

teste_lex05_dois_candidatos_sai_7_com_as_urls() {
  local base
  base=$(_ambiente)
  _existente "$base" "$(_link "$URL_A" /docs/a.txt public false),$(_link "$URL_B" /docs/a.txt team_only false)"
  _rodar "$base" compartilhar --equipe /docs/a.txt
  assert_igual 7 "$DBX_ESTADO" 'conflito'
  assert_contem "$URL_A" "$DBX_ERRO" 'primeira url'
  assert_contem "$URL_B" "$DBX_ERRO" 'segunda url'
  assert_contem 'dbx compartilhar --revogar' "$DBX_ERRO" 'remedio'
  assert_igual 0 "$(_chamadas "$base" 'modify_shared_link')" 'nada modificado'
}

teste_lex06_visibilidade_diferente_modifica_e_mostra_o_depois_da_resposta() {
  local base
  base=$(_ambiente)
  _existente "$base" "$(_link "$URL_A" /docs/a.txt public false)"
  # O servico devolve outra coisa que o pedido: o depois vem da resposta.
  _regra "$base" sharing/modify_shared_link_settings '*' 200 "$(_link "$URL_A" /docs/a.txt shared_folder_only false)"
  _rodar "$base" compartilhar --equipe /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "modifica: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" "sharing/modify_shared_link_settings {\"url\":\"https://www.dropbox.com/scl/fi/aaa/a.txt?rlkey=k1\",\"settings\":{\"audience\":\"team\",\"require_password\":false}}")" \
    'so os campos pedidos'
  assert_contem 'situacao=modificado' "$DBX_SAIDA" 'modificado'
  assert_contem 'antes_visibilidade=public' "$DBX_SAIDA" 'antes'
  assert_contem 'depois_visibilidade=shared_folder_only' "$DBX_SAIDA" 'depois lido da resposta'
  assert_contem $'antes=' "$DBX_SAIDA" 'linha antes'
  assert_contem $'depois=' "$DBX_SAIDA" 'linha depois'
}

teste_lex07_expiracao_so_comparada_quando_dada() {
  local base
  base=$(_ambiente)
  _existente "$base" "$(_link "$URL_A" /docs/a.txt public false 2099-01-01T00:00:00Z)"
  _regra "$base" sharing/modify_shared_link_settings '*' 200 "$(_link "$URL_A" /docs/a.txt public false 2099-06-01T23:59:59Z)"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_contem 'situacao=existente' "$DBX_SAIDA" 'sem --expira a vigente nao conta'
  assert_igual 0 "$(_chamadas "$base" 'modify_shared_link')" 'nem e mudada'
  _rodar "$base" compartilhar --publico --expira 2099-06-01 /docs/a.txt
  assert_contem 'situacao=modificado' "$DBX_SAIDA" '--expira diferente modifica'
  assert_igual 1 "$(_chamadas "$base" 'modify_shared_link.*"expires":"2099-06-01T23:59:59Z"')" 'com a nova expiracao'
  _rodar "$base" compartilhar --publico --expira 2099-01-01T00:00:00Z /docs/a.txt
  assert_contem 'situacao=existente' "$DBX_SAIDA" 'igual ao segundo reusa'
}

teste_lex08_senha_sobre_link_existente_sempre_redefine() {
  local base
  base=$(_ambiente)
  _existente "$base" "$(_link "$URL_A" /docs/a.txt password true)"
  _regra "$base" sharing/modify_shared_link_settings '*' 200 "$(_link "$URL_A" /docs/a.txt password true)"
  _entrada "$base" "$SENHA"$'\n'
  _rodar "$base" compartilhar --senha-stdin /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "redefine: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" "modify_shared_link.*\"link_password\":\"$SENHA\"")" 'modify com a senha'
  assert_contem 'senha_redefinida=sim' "$DBX_SAIDA" 'redefinida'
  _sem_senha_em_canais "$base"
}

teste_lex09_10_publico_sobre_link_com_senha_remove_e_avisa_exposicao() {
  local base
  base=$(_ambiente)
  _existente "$base" "$(_link "$URL_A" /docs/a.txt password true)"
  _regra "$base" sharing/modify_shared_link_settings '*' 200 "$(_link "$URL_A" /docs/a.txt public false)"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "sai 0: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" 'modify_shared_link.*"require_password":false')" 'remove a senha'
  assert_contem 'antes_senha=sim' "$DBX_SAIDA" 'antes com senha'
  assert_contem 'depois_senha=nao' "$DBX_SAIDA" 'depois sem'
  assert_contem 'a senha do link foi removida' "$DBX_ERRO" 'aviso'
  assert_contem "o link $URL_A ficou mais exposto" "$DBX_ERRO" 'exposicao ampliada'
}

teste_lex11_dry_run_mostra_antes_e_depois_previsto_sem_modify() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/list_shared_links "$F_A" 200 "{\"links\":[$(_link "$URL_A" /docs/a.txt public false)],\"has_more\":false}"
  _rodar "$base" --dry-run compartilhar --equipe /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "simulacao: $DBX_ERRO"
  assert_contem 'situacao=modificaria' "$DBX_SAIDA" 'modificaria'
  assert_contem 'antes_visibilidade=public' "$DBX_SAIDA" 'antes'
  assert_contem 'depois_visibilidade=team_only' "$DBX_SAIDA" 'depois previsto'
  assert_igual 0 "$(_chamadas "$base" 'modify_shared_link\|create_shared_link')" 'nenhuma escrita'
  _rodar "$base" --dry-run compartilhar --publico /docs/a.txt
  assert_contem 'situacao=reusaria' "$DBX_SAIDA" 'reusaria'
}

teste_lex12_link_revogado_entre_listagem_e_modify_sai_4() {
  local base
  base=$(_ambiente)
  _existente "$base" "$(_link "$URL_A" /docs/a.txt public false)"
  _regra "$base" sharing/modify_shared_link_settings '*' 409 '{"error_summary":"shared_link_not_found/.."}'
  _rodar "$base" compartilhar --equipe /docs/a.txt
  assert_igual 4 "$DBX_ESTADO" 'nao encontrado'
  assert_contem 'o link mudou durante a operacao; repita' "$DBX_ERRO" 'mensagem'
  assert_igual 1 "$(_chamadas "$base" 'create_shared_link')" 'nenhum create adicional'
}

teste_lex_missing_scope_sharing_read_na_listagem_sai_5() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 409 "$JA_EXISTE"
  _regra "$base" sharing/list_shared_links '*' 401 '{"error_summary":"missing_scope/..","error":{".tag":"missing_scope","required_scope":"sharing.read"}}'
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 5 "$DBX_ESTADO" 'escopo'
  assert_contem 'sharing.read' "$DBX_ERRO" 'nomeia o escopo'
  assert_contem 'dbx unlink' "$DBX_ERRO" 'remedio'
}

# ===========================================================================
# TC-LST — --listar (RF-88)
# ===========================================================================

teste_lst01_segue_o_cursor_sem_path_ate_o_fim() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/list_shared_links '{}' 200 "{\"links\":[$(_link "$URL_A" /docs/a.txt public false)],\"has_more\":true,\"cursor\":\"C1\"}"
  _regra "$base" sharing/list_shared_links '*"C1"*' 200 "{\"links\":[$(_link "$URL_B" /docs/b.txt team_only false)],\"has_more\":true,\"cursor\":\"C2\"}"
  _regra "$base" sharing/list_shared_links '*"C2"*' 200 "{\"links\":[$(_link "$URL_P" /docs/c public true '' folder)],\"has_more\":false}"
  _rodar "$base" compartilhar --listar
  assert_igual 0 "$DBX_ESTADO" "listar: $DBX_ERRO"
  assert_igual 3 "$(_chamadas "$base" 'list_shared_links')" 'tres paginas'
  assert_igual 0 "$(_chamadas "$base" 'list_shared_links .*"path"')" 'sem path no corpo'
  assert_igual 1 "$(_chamadas "$base" 'sharing/list_shared_links {"cursor":"C2"}')" 'so o cursor'
  assert_contem 'total=3' "$DBX_SAIDA" 'total'
  assert_contem 'omitidos=0' "$DBX_SAIDA" 'omitidos'
  assert_contem 'senha=sim' "$DBX_SAIDA" 'senha por link'
}

teste_lst02_03_sem_argumento_usa_a_raiz_e_omite_fora_e_sem_path_lower() {
  local base fora='https://www.dropbox.com/scl/fi/FORA_SENTINELA/x' sem='https://www.dropbox.com/s/SEM_SENTINELA/y'
  base=$(_ambiente /docs)
  _regra "$base" sharing/list_shared_links '{}' 200 \
    "{\"links\":[$(_link "$URL_A" /docs/a.txt public false),$(_link "$fora" /fora/x public false),$(_link "$sem" - public false)],\"has_more\":false}"
  _rodar "$base" share --list
  assert_igual 0 "$DBX_ESTADO" "listar: $DBX_ERRO"
  assert_contem "url=$URL_A" "$DBX_SAIDA" 'o de dentro'
  assert_nao_contem 'FORA_SENTINELA' "$DBX_SAIDA$DBX_ERRO" 'fora da raiz nao aparece'
  assert_nao_contem 'SEM_SENTINELA' "$DBX_SAIDA$DBX_ERRO" 'sem path_lower nao aparece'
  assert_contem 'total=1' "$DBX_SAIDA" 'total'
  assert_contem 'omitidos=2' "$DBX_SAIDA" 'omitidos'
}

teste_lst04_05_pasta_por_componente_e_caixa() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/list_shared_links '{}' 200 \
    "{\"links\":[$(_link "$URL_A" /a/x.txt public false),$(_link "$URL_B" /ab/y.txt public false),$(_link "$URL_P" /ação/z public false)],\"has_more\":false}"
  _rodar "$base" compartilhar --listar /A
  assert_contem "url=$URL_A" "$DBX_SAIDA" '/a com caixa ASCII'
  assert_nao_contem "$URL_B" "$DBX_SAIDA" '/ab nao esta em /a'
  assert_contem 'total=1' "$DBX_SAIDA" 'um'
  _rodar "$base" compartilhar --listar /AÇÃO
  assert_nao_contem "$URL_P" "$DBX_SAIDA" 'caixa fora do ASCII: omitido'
  assert_contem 'total=0' "$DBX_SAIDA" 'nenhum'
}

teste_lst06_cursor_repetido_sai_10_e_reset_14() {
  local base
  base=$(_ambiente)
  # Paginas com item: o cursor repetido e o que nao avanca (a pagina vazia com
  # has_more e o caso de QA-B5-03, na suite do QA).
  _regra "$base" sharing/list_shared_links '{}' 200 "{\"links\":[$(_link "$URL_A" /a.txt public false)],\"has_more\":true,\"cursor\":\"C1\"}"
  _regra "$base" sharing/list_shared_links '*"C1"*' 200 "{\"links\":[$(_link "$URL_B" /b.txt public false)],\"has_more\":true,\"cursor\":\"C1\"}"
  _rodar "$base" compartilhar --listar
  assert_igual 10 "$DBX_ESTADO" 'paginacao nao avanca'
  assert_contem 'paginacao nao avanca' "$DBX_ERRO" 'mensagem'
  assert_igual 2 "$(_chamadas "$base" 'list_shared_links')" 'sem laco'
  : >"$base/regras"
  _regra "$base" sharing/list_shared_links '*' 409 '{"error_summary":"reset/.."}'
  _rodar "$base" compartilhar --listar
  assert_igual 14 "$DBX_ESTADO" 'reset'
  assert_contem 'repita a listagem' "$DBX_ERRO" 'mensagem'
}

teste_lst07_08_vazia_e_recusas_de_argumento() {
  local base
  base=$(_ambiente /docs)
  _regra "$base" sharing/list_shared_links '{}' 200 '{"links":[],"has_more":false}'
  _rodar "$base" compartilhar --listar
  assert_igual 0 "$DBX_ESTADO" 'vazia'
  assert_contem 'total=0' "$DBX_SAIDA" 'total 0'
  rm -f "$base/chamadas"
  _rodar "$base" compartilhar --listar /fora
  assert_igual 13 "$DBX_ESTADO" 'fora'
  _rodar "$base" compartilhar --listar $'/docs/a\nb'
  assert_igual 13 "$DBX_ESTADO" 'quebra de linha'
  _nenhuma_chamada "$base" 'zero chamadas'
}

# DIV-123: caminho relativo e uso invalido (2) em todo modo que recebe caminho,
# antes do ponto unico (que o recusaria com 13) e de qualquer rede. O
# `--revogar` recebe URL, nao caminho: o relativo cai na validacao da URL (2).
teste_div123_caminho_relativo_e_uso_invalido_em_todo_modo() {
  local base
  base=$(_ambiente /docs)
  _rodar "$base" compartilhar --listar docs
  assert_igual 2 "$DBX_ESTADO" '--listar relativo'
  assert_contem 'absoluto' "$DBX_ERRO" 'a mensagem pede caminho absoluto'
  _rodar "$base" share --list ./docs
  assert_igual 2 "$DBX_ESTADO" '--list relativo pelo alias'
  _rodar "$base" compartilhar --publico docs/a.txt
  assert_igual 2 "$DBX_ESTADO" 'criar relativo'
  _rodar "$base" link-temporario docs/a.txt
  assert_igual 2 "$DBX_ESTADO" 'link temporario relativo'
  _rodar "$base" compartilhar --revogar s/abc/a.txt
  assert_igual 2 "$DBX_ESTADO" '--revogar com url relativa'
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_lst09_json_null_e_ordem_pela_chave_sem_caixa() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/list_shared_links '{}' 200 \
    "{\"links\":[$(_link "$URL_B" /b.txt public false),$(_link "$URL_A" /A.txt public false)],\"has_more\":false}"
  _rodar "$base" compartilhar --listar
  [[ $DBX_SAIDA == *"$URL_A"*"$URL_B"* ]] || _harness_falhar 'ordem pela chave sem caixa' "$DBX_SAIDA"
  _rodar "$base" --json compartilhar --listar
  assert_contem 'path_lower=/A.txt' "$DBX_SAIDA" 'json'
  _rodar "$base" --null compartilhar --listar
  assert_contem 'total=2|' "$(_saida_nula "$base")" 'null'
}

teste_lst10_missing_scope_sharing_read_e_nenhuma_escrita() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/list_shared_links '*' 401 '{"error_summary":"missing_scope/..","error":{".tag":"missing_scope","required_scope":"sharing.read"}}'
  _rodar "$base" compartilhar --listar
  assert_igual 5 "$DBX_ESTADO" 'escopo'
  assert_contem 'sharing.read' "$DBX_ERRO" 'nomeia'
  assert_igual 0 "$(_chamadas "$base" 'create_\|modify_\|revoke_')" 'nenhuma escrita'
}

# ===========================================================================
# TC-RVG — --revogar (RF-89) — P0 de confinamento
# ===========================================================================

_meta_link() { # <base> <corpo> — resposta do get_shared_link_metadata
  _regra "$1" sharing/get_shared_link_metadata '*' 200 "$2"
  _regra "$1" sharing/revoke_shared_link '*' 200 'null'
}

teste_rvg01_link_dentro_da_raiz_e_revogado() {
  local base
  base=$(_ambiente /docs)
  _meta_link "$base" "$(_link "$URL_A" /docs/a.txt public false)"
  _rodar "$base" compartilhar --revogar "$URL_A"
  assert_igual 0 "$DBX_ESTADO" "revoga: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" 'sharing/get_shared_link_metadata {"url":"https://www.dropbox.com/scl/fi/aaa/a.txt?rlkey=k1"}')" 'metadados pela url'
  assert_igual 1 "$(_chamadas "$base" 'sharing/revoke_shared_link {"url":"https://www.dropbox.com/scl/fi/aaa/a.txt?rlkey=k1"}')" 'revoke'
  [[ $(grep -n 'get_shared_link_metadata' "$base/chamadas" | head -1) < $(grep -n 'revoke_shared_link' "$base/chamadas" | head -1) ]] ||
    _harness_falhar 'a guarda vem antes da revogacao'
  assert_contem 'resultado=revogado' "$DBX_SAIDA" 'revogado'
  assert_contem 'caminho=/docs/a.txt' "$DBX_SAIDA" 'caminho'
}

teste_rvg02_fora_da_raiz_sai_13_sem_revoke() {
  local base
  base=$(_ambiente /docs)
  _meta_link "$base" "$(_link "$URL_A" /fora/a.txt public false)"
  _rodar "$base" share --revoke "$URL_A"
  assert_igual 13 "$DBX_ESTADO" 'fora'
  assert_igual 0 "$(_chamadas "$base" 'revoke_shared_link')" 'zero revoke'
}

teste_rvg03_sem_path_lower_sai_13_mesmo_com_raiz_da_conta() {
  local base
  base=$(_ambiente /)
  _meta_link "$base" "$(_link "$URL_A" - public false)"
  _rodar "$base" compartilhar --revogar "$URL_A"
  assert_igual 13 "$DBX_ESTADO" 'ausente com raiz /'
  assert_igual 0 "$(_chamadas "$base" 'revoke_shared_link')" 'zero revoke'
}

teste_rvg04_guarda_sem_estado_ignora_estado_local_adulterado() {
  local base
  base=$(_ambiente /docs)
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  printf '%s\n' "$URL_A /docs/a.txt autorizado" >"$base/estado/dbx/compartilhamento"
  printf '%s\n' "$URL_A" >"$base/estado/dbx/upload-autorizado"
  _meta_link "$base" "$(_link "$URL_A" /fora/a.txt public false)"
  _rodar "$base" compartilhar --revogar "$URL_A"
  assert_igual 13 "$DBX_ESTADO" 'a decisao segue so a resposta'
  assert_igual 0 "$(_chamadas "$base" 'revoke_shared_link')" 'zero revoke'
}

teste_rvg05_path_lower_vazio_repetido_ou_malformado_sai_10() {
  local base corpo
  base=$(_ambiente)
  for corpo in "{\".tag\":\"file\",\"url\":\"$URL_A\",\"path_lower\":\"\"}" \
    "{\".tag\":\"file\",\"url\":\"$URL_A\",\"path_lower\":\"/a\",\"path_lower\":\"/a\"}" \
    "{\".tag\":\"file\",\".tag\":\"file\",\"url\":\"$URL_A\",\"path_lower\":\"/a\"}" \
    '{"path_lower":"/a"' 'nao json'; do
    : >"$base/regras"
    _meta_link "$base" "$corpo"
    _rodar "$base" compartilhar --revogar "$URL_A"
    assert_igual 10 "$DBX_ESTADO" "resposta recusada: $corpo"
  done
  assert_igual 0 "$(_chamadas "$base" 'revoke_shared_link')" 'zero revoke'
}

teste_rvg06_07_url_invalida_ou_temporaria_sem_rede() {
  local base url
  base=$(_ambiente)
  for url in 'http://www.dropbox.com/s/abc' 'https://evil.com/s/abc' 'https://www.dropbox.com.evil/s/a' \
    'https://user@www.dropbox.com/s/a' 'https://www.dropbox.com:443/s/a' 'https://www.dropbox.com/s/a b' \
    $'https://www.dropbox.com/s/a\nb'; do
    _rodar "$base" compartilhar --revogar "$url"
    assert_igual 2 "$DBX_ESTADO" "url recusada: [$url]"
  done
  _rodar "$base" compartilhar --revogar "$LINK_TEMP"
  assert_igual 2 "$DBX_ESTADO" 'link temporario'
  assert_contem 'link temporario nao pode ser revogado; ele expira em 4 horas' "$DBX_ERRO" 'mensagem'
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_rvg08_dry_run_executa_a_guarda_sem_revogar() {
  local base
  base=$(_ambiente /docs)
  _meta_link "$base" "$(_link "$URL_A" /docs/a.txt public false)"
  _rodar "$base" --dry-run compartilhar --revogar "$URL_A"
  assert_igual 0 "$DBX_ESTADO" 'simulacao'
  assert_contem 'resultado=revogaria' "$DBX_SAIDA" 'revogaria'
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'simulado'
  assert_igual 1 "$(_chamadas "$base" 'get_shared_link_metadata')" 'guarda executada'
  assert_igual 0 "$(_chamadas "$base" 'revoke_shared_link')" 'zero revoke'
  : >"$base/regras"
  _meta_link "$base" "$(_link "$URL_A" /fora/a.txt public false)"
  _rodar "$base" --dry-run compartilhar --revogar "$URL_A"
  assert_igual 13 "$DBX_ESTADO" 'a guarda vale na simulacao'
}

teste_rvg09_10_link_inexistente_e_de_outro_membro() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/get_shared_link_metadata '*' 200 "$(_link "$URL_A" /a.txt public false)"
  _regra "$base" sharing/revoke_shared_link '*' 409 '{"error_summary":"shared_link_not_found/.."}' uma
  _regra "$base" sharing/revoke_shared_link '*' 409 '{"error_summary":"shared_link_access_denied/.."}'
  _rodar "$base" compartilhar --revogar "$URL_A"
  assert_igual 4 "$DBX_ESTADO" 'nao encontrado'
  assert_contem 'o link nao existe (pode ja ter sido revogado pela tentativa anterior)' "$DBX_ERRO" 'mensagem'
  _rodar "$base" compartilhar --revogar "$URL_A"
  assert_igual 6 "$DBX_ESTADO" 'acesso negado'
  : >"$base/regras"
  _regra "$base" sharing/get_shared_link_metadata '*' 409 '{"error_summary":"shared_link_not_found/.."}'
  _rodar "$base" compartilhar --revogar "$URL_A"
  assert_igual 4 "$DBX_ESTADO" 'inexistente ja na guarda'
}

teste_rvg12_raiz_x_nao_esta_em_raiz() {
  local base
  base=$(_ambiente /raiz)
  _meta_link "$base" "$(_link "$URL_A" /raizx/a.txt public false)"
  _rodar "$base" compartilhar --revogar "$URL_A"
  assert_igual 13 "$DBX_ESTADO" '/raizX fora de /raiz'
  : >"$base/regras"
  _meta_link "$base" "$(_link "$URL_A" /RAIZ/a.txt public false)"
  _rodar "$base" compartilhar --revogar "$URL_A"
  assert_igual 0 "$DBX_ESTADO" 'caixa ASCII dentro'
}

# ===========================================================================
# TC-SHE — erros e retentativa (RF-90)
# ===========================================================================

teste_she03_04_invalid_settings_e_missing_scope_de_escrita() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings '*"/x"*' 409 '{"error_summary":"settings_error/invalid_settings/.."}'
  _regra "$base" sharing/create_shared_link_with_settings '*"/y"*' 401 '{"error_summary":"missing_scope/..","error":{".tag":"missing_scope","required_scope":"sharing.write"}}'
  _rodar "$base" compartilhar --publico /x
  assert_igual 2 "$DBX_ESTADO" 'invalid_settings'
  assert_contem 'configuracao de link recusada pelo servico' "$DBX_ERRO" 'mensagem'
  _rodar "$base" compartilhar --publico /y
  assert_igual 5 "$DBX_ESTADO" 'escopo'
  assert_contem 'sharing.write' "$DBX_ERRO" 'nomeia o escopo'
  assert_contem 'App Console' "$DBX_ERRO" 'remedio'
}

teste_she05_resposta_perdida_e_retentativa_com_link_existente_segue_o_reuso() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 429 '{"error_summary":"too_many_requests/.."}' uma
  _existente "$base" "$(_link "$URL_A" /docs/a.txt public false)"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "um link so: $DBX_ERRO"
  assert_igual 2 "$(_chamadas "$base" 'create_shared_link')" 'retentativa'
  assert_contem 'situacao=existente' "$DBX_SAIDA" 'reuso'
}

# ===========================================================================
# Ciclo 2 do QA (QA-B5-04..07; os 01..03 estao na suite do QA)
# ===========================================================================

teste_qab5_04_recusa_de_url_nao_cita_credencial_embutida() {
  local base url
  base=$(_ambiente)
  for url in 'https://usuario_x:SEGREDO_URL_9@www.dropbox.com/s/a/x' \
    'https://usuario_x:SEGREDO_URL_9@evil.com/s/a/x' 'http://usuario_x:SEGREDO_URL_9@www.dropbox.com/s/a'; do
    _rodar "$base" compartilhar --revogar "$url"
    assert_igual 2 "$DBX_ESTADO" "recusada: $url"
    assert_nao_contem 'SEGREDO_URL_9' "$DBX_ERRO" 'a senha embutida nao e citada'
    assert_nao_contem 'usuario_x' "$DBX_ERRO" 'nem o usuario embutido'
  done
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_qab5_05_arquivo_de_corpo_com_a_senha_nasce_0600() {
  local base modo
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt password true)"
  _entrada "$base" "$SENHA"$'\n'
  _rodar "$base" compartilhar --senha-stdin /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "sucesso: $DBX_ERRO"
  assert_arquivo_existe "$base/modos.log" 'o duble registrou o modo'
  while IFS= read -r modo; do
    assert_igual 600 "$modo" 'arquivo de corpo nasce 0600'
  done <"$base/modos.log"
}

teste_qab5_06_link_temporario_com_controle_sai_10_sem_imprimir() {
  local base
  base=$(_ambiente)
  _regra "$base" files/get_temporary_link "$F_A" 200 \
    "{\"metadata\":$META_TEMP,\"link\":\"https://dl.dropboxusercontent.com/LINKTEMP_SENTINELA\\nerro=falso\"}"
  _rodar "$base" link-temporario /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'link com quebra de linha e resposta malformada'
  assert_nao_contem 'LINKTEMP_SENTINELA' "$DBX_SAIDA$DBX_ERRO" 'o link nao e impresso'
}

teste_qab5_07_resposta_sem_url_sai_10() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 '{}'
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'create 200 sem url'
  : >"$base/regras"
  _existente "$base" "$(_link "$URL_A" /docs/a.txt public false)"
  _regra "$base" sharing/modify_shared_link_settings '*' 200 '{".tag":"file"}'
  _rodar "$base" compartilhar --equipe /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'modify 200 sem url'
}

# ===========================================================================
# Ciclo 3 do QA (QA-B5-13..16; 08, 09, 11 e 12 estao na suite do QA)
# ===========================================================================

teste_qab5_13_link_reusado_sem_url_sai_10() {
  local base
  base=$(_ambiente)
  _existente "$base" '{".tag":"file","path_lower":"/docs/a.txt","link_permissions":{"resolved_visibility":{".tag":"public"},"require_password":false}}'
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'reuso sem url'
  assert_igual 0 "$(_chamadas "$base" 'modify_shared_link')" 'nada modificado'
}

teste_qab5_14_listar_tem_teto_de_1000_paginas() {
  local base
  base=$(_ambiente /docs)
  # Paginas nunca vazias (um link omitido cada) e cursor sempre novo.
  _regra "$base" sharing/list_shared_links '*' 200 \
    "{\"links\":[$(_link "$URL_A" /fora/x public false)],\"has_more\":true,\"cursor\":\"c@N@\"}"
  DBX_T_TETO=300 _rodar "$base" compartilhar --listar
  assert_igual 10 "$DBX_ESTADO" 'teto de paginas'
  assert_contem 'listagem nao terminou em 1000 paginas' "$DBX_ERRO" 'mensagem'
  assert_igual 1000 "$(_chamadas "$base" 'list_shared_links')" 'exatamente o teto de paginas'
}

teste_qab5_15_link_temporario_com_espaco_sai_10() {
  local base
  base=$(_ambiente)
  _regra "$base" files/get_temporary_link "$F_A" 200 \
    "{\"metadata\":$META_TEMP,\"link\":\"https://dl.dropboxusercontent.com/LINKTEMP_SENTINELA a\"}"
  _rodar "$base" link-temporario /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'link com espaco'
  assert_nao_contem 'LINKTEMP_SENTINELA' "$DBX_SAIDA$DBX_ERRO" 'nao impresso'
}

teste_qab5_16_password_sem_require_password_e_incoerente() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt password false)"
  _entrada "$base" "$SENHA"$'\n'
  _rodar "$base" compartilhar --senha-stdin /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'criacao incoerente'
  assert_contem 'dbx compartilhar --listar' "$DBX_ERRO" 'aviso para conferir'
  : >"$base/regras"
  _existente "$base" "$(_link "$URL_A" /docs/a.txt public false)"
  _regra "$base" sharing/modify_shared_link_settings '*' 200 "$(_link "$URL_A" /docs/a.txt password false)"
  _rodar "$base" compartilhar --senha-stdin /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'modify incoerente'
  assert_contem 'dbx compartilhar --listar' "$DBX_ERRO" 'aviso para conferir'
}

# ===========================================================================
# Ciclo 4 do QA (QA-B5-17..19)
# ===========================================================================

teste_qab5_17_tag_igual_a_senha_nao_e_citada() {
  local base
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 409 '{"error_summary":"banned_member/.."}'
  _entrada "$base" $'banned_member\n'
  _rodar "$base" compartilhar --senha-stdin /docs/a.txt
  assert_igual 6 "$DBX_ESTADO" 'classe da tag'
  assert_nao_contem 'banned_member' "$DBX_ERRO" 'a tag igual a senha nao e citada'
  assert_contem 'codigo HTTP 409' "$DBX_ERRO" 'o codigo continua'
}

teste_qab5_18_url_ou_link_fora_do_ascii_imprimivel_sai_10() {
  local base nbsp=$'\u00a0' ls=$'\u2028'
  base=$(_ambiente)
  _regra "$base" files/get_temporary_link "$F_A" 200 \
    "{\"metadata\":$META_TEMP,\"link\":\"https://dl.dropboxusercontent.com/LINKTEMP_SENTINELA${nbsp}x\"}"
  _rodar "$base" link-temporario /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'link temporario com U+00A0'
  assert_nao_contem 'LINKTEMP_SENTINELA' "$DBX_SAIDA$DBX_ERRO" 'nao impresso'
  : >"$base/regras"
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "https://www.dropbox.com/s/a${ls}b" /docs/a.txt public false)"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'criar com U+2028 na url'
  : >"$base/regras"
  _existente "$base" "$(_link "https://www.dropbox.com/s/a${nbsp}b" /docs/a.txt public false)"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'reuso com U+00A0 na url'
  : >"$base/regras"
  _existente "$base" "$(_link "$URL_A" /docs/a.txt public false)"
  _regra "$base" sharing/modify_shared_link_settings '*' 200 "$(_link "https://www.dropbox.com/s/a${nbsp}b" /docs/a.txt team_only false)"
  _rodar "$base" compartilhar --equipe /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'modify com U+00A0 na url'
}

teste_qab5_19_coerencia_entre_visibilidade_e_senha() {
  local base linha modo vis req
  while IFS=$'\t' read -r modo vis req; do
    base=$(_ambiente)
    _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt "$vis" "$req")"
    _entrada "$base" "$SENHA"$'\n'
    _rodar "$base" compartilhar "$modo" /docs/a.txt
    assert_igual 10 "$DBX_ESTADO" "criacao incoerente: $vis/$req"
    assert_contem 'dbx compartilhar --listar' "$DBX_ERRO" 'aviso para conferir'
  done <<'FIM'
--publico	public	true
--equipe	team_only	true
--senha-stdin	team_and_password	false
FIM
  # Reuso (DIV-129): link existente incoerente nunca volta como esta; difere do
  # pedido, vai ao modify (como em qa_x01) e a resposta do modify e conferida.
  base=$(_ambiente)
  _existente "$base" "$(_link "$URL_A" /docs/a.txt public true)"
  _regra "$base" sharing/modify_shared_link_settings '*' 200 "$(_link "$URL_A" /docs/a.txt public true)"
  _rodar "$base" compartilhar --publico /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'reuso de link incoerente que continua incoerente'
  assert_igual 0 "$(_chamadas "$base" 'situacao=existente')" 'nunca devolvido como esta'
  assert_nao_contem 'situacao=existente' "$DBX_SAIDA" 'sem reuso sem escrita'
  base=$(_ambiente)
  _existente "$base" "$(_link "$URL_A" /docs/a.txt public false)"
  _regra "$base" sharing/modify_shared_link_settings '*' 200 "$(_link "$URL_A" /docs/a.txt team_only true)"
  _rodar "$base" compartilhar --equipe /docs/a.txt
  assert_igual 10 "$DBX_ESTADO" 'modify incoerente'
  base=$(_ambiente)
  _regra "$base" sharing/create_shared_link_with_settings "$F_A" 200 "$(_link "$URL_A" /docs/a.txt team_and_password true)"
  _entrada "$base" "$SENHA"$'\n'
  _rodar "$base" compartilhar --senha-stdin /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'team_and_password com senha e coerente'
}

# ===========================================================================
# TC-CPL-10, TC-DOC-04, TC-TST-08 (RF-92)
# ===========================================================================

_ajuda() { env -i PATH="$PATH" HOME="$DBX_TESTES_TMP" bash "$DBX_EXEC" help "$@" 2>&1; }

_opcoes_da_ajuda() { # <comando> — a mesma leitura de completar_test
  local linha secao=nao
  while IFS= read -r linha; do
    [[ $linha == Opcoes* ]] && secao=sim && continue
    [[ -z $linha ]] && secao=nao
    [[ $secao == sim && $linha == '  -'* ]] || continue
    linha=${linha#  }
    linha=${linha%%  *}
    grep -oE '(^|[ ,])-{1,2}[A-Za-z][A-Za-z-]*' <<<"$linha" | tr -d ' ,'
  done < <(_ajuda "$@") | LC_ALL=C sort -u
}

_completar() {
  env -i PATH="$PATH" HOME="$DBX_TESTES_TMP" bash -c '
    . "$1"; shift
    COMP_WORDS=(dbx "$@"); COMP_CWORD=$#; COMPREPLY=()
    _dbx_completar dbx "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}"
    for item in ${COMPREPLY[@]+"${COMPREPLY[@]}"}; do printf "%s\n" "$item"; done
  ' _ "$DBX_HARNESS_RAIZ/completions/dbx.bash" "$@" 2>&1 | LC_ALL=C sort -u
}

teste_cpl10_opcoes_da_ajuda_e_do_autocompletar_coincidem() {
  local comando
  for comando in link-temporario compartilhar; do
    assert_igual "$(_opcoes_da_ajuda "$comando")" "$(_completar "$comando" -)" "opcoes de $comando"
  done
  assert_igual "$(_opcoes_da_ajuda compartilhar)" "$(_completar share -)" 'pelo alias share'
  assert_contem '--senha-stdin' "$(_opcoes_da_ajuda compartilhar)" 'a ajuda traz --senha-stdin'
  assert_contem '--password-stdin' "$(_completar share --p)" 'ingles completado'
  assert_contem 'temp-link' "$(_completar t)" 'alias temp-link'
  assert_contem 'share' "$(_completar s)" 'alias share'
  assert_contem 'link-temporario' "$(_completar l)" 'comando'
  assert_igual '' "$(_completar compartilhar --expira '')" 'valor de --expira nao e completado'
  assert_igual "$(_ajuda link-temporario)" "$(_ajuda temp-link)" 'a ajuda do alias e a mesma'
}

teste_doc04_ajuda_e_readme_trazem_as_frases() {
  local texto frase readme
  texto="$(_ajuda compartilhar)$(_ajuda link-temporario)"
  IFS= read -r -d '' readme <"$DBX_HARNESS_RAIZ/README.md" || :
  for frase in 'nada e publicado por omissao: informe --publico, --equipe ou --senha' \
    'a senha nunca e aceita na linha de comando nem em variavel de ambiente: use --senha (terminal, sem eco) ou --senha-stdin (uma linha da entrada)' \
    'senha vazia e recusada' \
    'o link temporario vale 4 horas, nao pode ser revogado e da acesso a quem o tiver' \
    'senha, equipe e expiracao dependem do plano da conta'; do
    assert_contem "$frase" "$texto" "ajuda: $frase"
  done
  assert_contem 'AAAA-MM-DD' "$(_ajuda compartilhar)" 'formatos de --expira'
  assert_contem '<N>d' "$(_ajuda compartilhar)" 'duracao'
  assert_contem 'link-temporario' "$(_ajuda)" 'lista de comandos'
  for frase in 'Compartilhamento' 'sharing.write' 'sharing.read' 'dbx compartilhar --revogar' \
    'dbx link-temporario' 'dbx unlink'; do
    assert_contem "$frase" "$readme" "README: $frase"
  done
}

teste_tst08_mapa_de_modulos_tem_as_entradas_da_fase() {
  local mapa
  IFS= read -r -d '' mapa <"$DBX_HARNESS_RAIZ/docs/testes/mapa-modulos.md" || :
  assert_contem 'lib/compartilhamento.sh' "$mapa" 'lib/compartilhamento'
  assert_contem 'commands/link_temporario.sh' "$mapa" 'link_temporario'
  assert_contem 'commands/compartilhar.sh' "$mapa" 'compartilhar'
  assert_contem 'compartilhamento_test.sh' "$mapa" 'os testes da fase'
}

# A auditoria de ponto unico de `composicao_test` le o corpo de
# `dbx_cmd_[a-z]+_executar` e nao reconhece o sublinhado do nome do arquivo
# (DIV-121). Aqui a mesma ordem e conferida para os dois comandos novos.
teste_ponto_unico_vem_antes_de_qualquer_rede_nos_comandos_novos() {
  local nome corpo primeiro rede
  for nome in link_temporario compartilhar; do
    corpo=$(awk "/^dbx_cmd_${nome}_executar\\(\\) \\{/{d=1} d{print} d && /^\\}/{exit}" \
      "$DBX_HARNESS_RAIZ/commands/$nome.sh" | grep -vE '^[[:space:]]*#')
    primeiro=$(grep -nE '_dbx_cmd_caminho_remoto ".*" \|\| return \$\?$' <<<"$corpo" | head -n 1)
    rede=$(grep -nE 'dbx_auth_|_dbx_cmd_consultar|_dbx_cmd_escrita_remota|_dbx_cmd_[a-z_]+_(criar|listar|revogar|gerar)' <<<"$corpo" | head -n 1)
    [[ -n $primeiro ]] || _harness_falhar "$nome: executar sem o ponto unico"
    [[ -z $rede || ${rede%%:*} -gt ${primeiro%%:*} ]] || _harness_falhar "$nome: rede antes do ponto unico: $rede"
    grep -q 'dbx_path_remoto_' "$DBX_HARNESS_RAIZ/commands/$nome.sh" &&
      _harness_falhar "$nome: lib/path remoto sem o ponto unico"
  done
  return 0
}

harness_executar "$@"
