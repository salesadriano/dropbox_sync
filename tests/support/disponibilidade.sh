#!/usr/bin/env bash
# Apoio compartilhado dos testes de disponibilidade (fase 11): cenario com duplo
# de curl que GRAVA o que viu (`chamadas`, `pedidos`), execucao sem terminal
# (`_rodar`) e com pseudo-terminal (`_rodar_tty`). Chamadas a /2/ do Dropbox sao
# o papel `rpc` (arquivos `rpc` = codigo e `rpc_corpo` = corpo).
#
# shellcheck disable=SC2016,SC2034
# Justificativa: o substituto de `curl` e escrito sem expansao; DBX_ESTADO e DBX_SAIDA sao lidos pelos testes que carregam este apoio.
# shellcheck source=tests/support/harness.sh
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly ESCOPOS='account_info.read files.metadata.read files.content.read files.content.write'
readonly SENTINELA_REFRESH='RT_SENTINELA_refresh_9f8e7d'
readonly SENTINELA_SEGREDO='AS_SENTINELA_segredo_1a2b3c'
readonly SENTINELA_CHAVE='AK_SENTINELA_chave_4d5e6f'
readonly SENTINELA_TOKEN='sl.SENTINELA_token_curto_7g8h9i'
readonly SENTINELA_STDIN='STDIN_SENTINELA_nao_ler_0z9y'
DBX_T_EXTRAS=()
BASH_ABSOLUTO=$(command -v bash)
readonly BASH_ABSOLUTO

_credencial() { # <base> [campos_omitidos]
  printf '{"versao":1,"app_key":"%s","app_secret":"%s","refresh_token":"%s","raiz_remota":"/"}' \
    "$SENTINELA_CHAVE" "$SENTINELA_SEGREDO" "$SENTINELA_REFRESH" >"$1/config/dbx/credencial.json"
  chmod 600 "$1/config/dbx/credencial.json"
}

# _cenario — credencial valida e rede saudavel. Os arquivos `sonda`, `api`,
# `content` (codigo HTTP, ou `falha` = sem resposta) e `token` ajustam o duplo.
_cenario() {
  local base alvo origem
  base=$(mktemp -d "$DBX_TESTES_TMP/testar.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/tmp"
  chmod 700 "$base/config/dbx"
  _credencial "$base"
  printf '{"access_token":"%s","expires_in":14400,"scope":"%s"}' "$SENTINELA_TOKEN" "$ESCOPOS" >"$base/token"
  for alvo in curl mktemp mv rm chmod mkdir stat head dd wc readlink dirname find cat sleep tail df ln rmdir sha256sum; do
    origem=$(command -v "$alvo" 2>/dev/null) || continue
    ln -s "$origem" "$base/bin/$alvo"
  done
  rm -f "$base/bin/curl"
  printf '#!%s\nbase=%s\n' "$BASH_ABSOLUTO" "$base" >"$base/bin/curl"
  cat >>"$base/bin/curl" <<'FIM'
read -r -d '' conf
saida=""; escrever=""; anterior=""; url=""; cabs=""; retry=""; falhar=""; com_corpo=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; -D) cabs=$arg ;; esac
  case $arg in http*) url=$arg ;; --fail) falhar=sim ;; --data-binary) com_corpo=sim ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
printf '%s\n' "ARGV: $* CONF: ${conf//$'\n'/ ; }" >>"$base/pedidos"
printf '%s %s\n' "$url" "${HTTPS_PROXY-}" >>"$base/proxies"
# Travas vivas (trava-*) no momento de cada chamada: "<destino> <quantas>".
printf '%s %s\n' "$url" "$(find "$base/estado" -name 'trava-*' 2>/dev/null | wc -l)" >>"$base/travas"
quem=sonda
case $url in
  *oauth2/token*) quem=token ;;
  *api.dropboxapi.com/2/*) quem=rpc ;;
  *api.dropboxapi.com*) quem=api ;;
  *content.dropboxapi.com*) quem=content ;;
esac
codigo=204
[[ $quem == rpc ]] && codigo=200
[[ -f $base/$quem ]] && codigo=$(cat "$base/$quem")
# `<papel>.fila`: uma resposta por linha, "<codigo> [retry-after]"; consome a primeira.
if [[ -s $base/$quem.fila ]]; then
  mapfile -t fila <"$base/$quem.fila"
  read -r codigo retry <<<"${fila[0]}"
  if ((${#fila[@]} > 1)); then printf '%s\n' "${fila[@]:1}" >"$base/$quem.fila"; else : >"$base/$quem.fila"; fi
fi
[[ $quem == token && -f $base/troca_falha && $conf == *authorization_code* ]] && exit 6
[[ $quem == sonda && -f $base/sonda_lenta ]] && exec sleep 3137
[[ $codigo == falha:* ]] && exit "${codigo#falha:}" # falha:<codigo de saida do curl>
[[ $codigo == falha ]] && exit 6
corpo=''
if [[ $quem == token ]]; then
  corpo=$(cat "$base/token"); codigo=200
  [[ -f $base/token_codigo ]] && { codigo=$(cat "$base/token_codigo"); corpo=$(cat "$base/token_corpo"); }
fi
[[ $quem == rpc && -f $base/rpc_corpo ]] && corpo=$(cat "$base/rpc_corpo")
# `recusar_refresh` guarda o refresh token que o duplo recusa com invalid_grant.
if [[ $quem == token && -f $base/recusar_refresh && $conf == *"$(cat "$base/recusar_refresh")"* ]]; then
  codigo=400; corpo='{"error":"invalid_grant"}'
fi
[[ $quem == content && -f $base/content_corpo ]] && corpo=$(cat "$base/content_corpo")
# `--fail` como no curl real (canal de fluxo de lib/http): resposta >= 400 nao escreve
# corpo no `-o`, ainda imprime o `-w` e sai com 22.
recusado=""
[[ -n $falhar && $codigo =~ ^[0-9]+$ ]] && ((codigo >= 400)) && { recusado=sim; corpo=''; }
[[ -n $saida && -z $recusado ]] && printf '%s' "$corpo" >"$saida"
if [[ -n $cabs ]]; then
  { [[ -n $retry ]] && printf 'Retry-After: %s\r\n' "$retry"; } >"$cabs"
fi
if [[ $escrever == *time_total* ]]; then
  # Medidas do `-w` ampliado (--debug): tempo fixo 0.250 s; bytes enviados lidos de
  # `enviados`, so na chamada com corpo (`--data-binary`), como o size_upload do curl.
  enviados=0
  [[ -n $com_corpo && -f $base/enviados ]] && enviados=$(cat "$base/enviados")
  printf '%s 0.250 %s %s' "$codigo" "$enviados" "${#corpo}"
elif [[ -n $escrever ]]; then
  printf '%s' "$codigo"
fi
[[ -n $recusado ]] && exit 22
exit 0
FIM
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_rodar() { # <base> <argumentos...> — sem terminal, stdin vazio
  local base=$1
  shift
  env -i PATH="$base/bin" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
    TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 ${DBX_T_AMBIENTE:+"$DBX_T_AMBIENTE"} \
    "$BASH_ABSOLUTO" "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err" </dev/null
  DBX_ESTADO=$?
  DBX_SAIDA='' DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_linha() { # <id> — linhas da checagem
  local linha saida=''
  while IFS= read -r linha; do
    [[ $linha == "$1="* ]] && saida+="$linha"$'\n'
  done <<<"$DBX_SAIDA"
  printf '%s' "${saida%$'\n'}"
}

_todo_o_rastro() { # <base> — tudo o que o duplo viu e o comando disse
  local x=''
  IFS= read -r -d '' x <"$1/pedidos" 2>/dev/null
  printf '%s\n%s\n%s' "$DBX_SAIDA" "$DBX_ERRO" "$x"
}

# _rodar_tty <base> <resposta|-> <argumentos...> — pseudo-terminal; a resposta so
# e escrita depois da pergunta `[s/N]`. `-` = fecha a entrada sem responder.
_rodar_tty() {
  local base=$1 resposta=$2 linha arg fd pid conteudo='' espera=0
  shift 2
  command -v script >/dev/null 2>&1 || pular 'script(1) ausente: sem terminal para o caso'
  printf -v linha '%q %q' "$BASH_ABSOLUTO" "$DBX_EXEC"
  for arg in "$@"; do printf -v arg ' %q' "$arg" && linha+=$arg; done
  # DBX_T_REDIR_ERR=sim manda o stderr do comando a um arquivo; DBX_T_REDIR_OUT=sim, o stdout.
  [[ ${DBX_T_REDIR_ERR:-nao} == 'sim' ]] && linha+=" 2>$base/stderr_arquivo"
  [[ ${DBX_T_REDIR_OUT:-nao} == 'sim' ]] && linha+=" >$base/stdout_arquivo"
  linha+='; printf "\nESTADO=%s\n" "$?"'
  rm -f "$base/fifo"
  mkfifo "$base/fifo"
  printf -v arg '%q' "$linha; true"
  linha="bash -c $arg"
  command -v timeout >/dev/null 2>&1 || pular 'timeout ausente'
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
    TMPDIR="$base/tmp" TERM="${DBX_T_TERM:-xterm}" DBX_HTTP_TENTATIVAS_MAXIMAS=1 ${DBX_T_AMBIENTE:+"$DBX_T_AMBIENTE"} \
    timeout -s KILL 20 script -qec "$linha" /dev/null <"$base/fifo" >"$base/out" 2>&1 &
  pid=$!
  exec {fd}>"$base/fifo"
  # Portao fechado: o processo termina sem ler, e a escrita na fifo nao pode matar a suite.
  trap '' PIPE
  while [[ $espera -lt 200 ]]; do
    [[ -r $base/out ]] && IFS= read -r -d '' conteudo <"$base/out"
    [[ $conteudo == *'[s/N]'* ]] && break
    sleep 0.05
    espera=$((espera + 1))
  done
  # Fim de entrada: Ctrl-D no pty (o script(1) 2.41 nao converte o EOF da fifo).
  if [[ $resposta == '-' ]]; then { printf '\004' >&"$fd"; } 2>/dev/null; else { printf '%s\n' "$resposta" >&"$fd"; } 2>/dev/null; fi
  # Dialogo seguinte (DBX_T_EXTRAS: "prompt|resposta"...), cada resposta so depois
  # do seu prompt; DBX_T_EOF=sim encerra a entrada com Ctrl-D.
  local par esperado
  for par in "${DBX_T_EXTRAS[@]}"; do
    esperado=${par%%|*}
    espera=0
    while [[ $espera -lt 200 ]]; do
      [[ -r $base/out ]] && IFS= read -r -d '' conteudo <"$base/out"
      [[ $conteudo == *"$esperado"* ]] && break
      sleep 0.05
      espera=$((espera + 1))
    done
    printf '%s\n' "${par#*|}" >&"$fd"
  done
  if [[ ${DBX_T_CTRLC:-nao} == 'sim' ]]; then
    sleep 0.3
    printf '\003' >&"$fd"
  fi
  if [[ ${DBX_T_EOF:-nao} == 'sim' ]]; then
    sleep 0.3
    printf '\004' >&"$fd"
  fi
  wait "$pid"
  trap - PIPE
  exec {fd}>&-
  IFS= read -r -d '' conteudo <"$base/out"
  DBX_SAIDA=$conteudo DBX_ERRO=$conteudo DBX_ESTADO=''
  [[ $conteudo =~ ESTADO=([0-9]+) ]] && DBX_ESTADO=${BASH_REMATCH[1]}
  return 0
}

_contar() { printf '%s\n' "$1" | grep -F -c -- "$2"; } # <texto> <trecho>: linhas com o trecho

_retrato() { find "$1" -printf '%P %m %s\n' | sort; find "$1" -type f -exec cksum {} + | sort; }
