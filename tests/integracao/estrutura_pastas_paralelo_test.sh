#!/usr/bin/env bash
# Tarefa 6 de F-103 (RF-215(a)(d)(e), TC-ARV-20 e TC-ARV-21): com `--paralelo`
# a criacao de pastas do ciclo termina antes de qualquer transferencia de
# arquivo (envio e recebimento); `--debug` registra cada operacao de pasta sem
# segredo; `--paralelo 1` e `--paralelo 8` produzem a mesma arvore final.
#
# Seam: o executavel `dbx` com o cliente HTTP real e duplos de `curl` que
# registram a ordem das chamadas (`$base/chamadas`). Dado sintetico apenas.
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

_cenario_env() {
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
# Criacao de pastas assincrona (async_job_id + check) quando $base/pastas_async existe.
if [[ $url == */files/create_folder_batch && -f $base/pastas_async ]]; then
  printf '%s' "$corpo" >"$base/pastas_complete"; corpo='{".tag":"async_job_id","async_job_id":"JOB-P"}'
fi
[[ $url == */create_folder_batch/check ]] && corpo=$(cat "$base/pastas_complete")
[[ -n $saida ]] && printf "%s" "$corpo" >"$saida"
[[ -n $escrever ]] && printf "%s" "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_cenario_rec() {
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
  *list_folder/continue*) corpo='{"entries":[],"has_more":false,"cursor":"CURSOR-DELTA-2"}' ;;
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
    { cd "$base/local" 2>/dev/null && find . -type d | sort; } >"$base/snap_$n.$$" ;;
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

_arquivo() { # <base> <relativo> — arquivo local com conteudo identificavel
  mkdir -p "$1/local/$(dirname -- "$2")"
  printf 'conteudo-%s' "${2//\//-}" >"$1/local/$2"
}
_corpos() { [[ -r $1/corpos ]] && cat "$1/corpos"; return 0; }
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
_pasta_json() { printf '{".tag":"folder","name":"%s","path_display":"/r/%s","path_lower":"/r/%s","id":"id:%s"}' "${1##*/}" "$1" "$1" "${1//\//}"; }
_arq_json() { printf '{".tag":"file","name":"%s","path_display":"/r/%s","path_lower":"/r/%s","content_hash":"h","size":3,"rev":"0a1b2c3d4e"}' "${1##*/}" "$1" "$1"; }
_lista() { # <base> <sufixo do arquivo, ex.: _r_o> <entradas...>
  local base=$1 suf=$2 itens
  shift 2
  itens=$(IFS=,; printf '%s' "$*")
  printf '{"entries":[%s],"has_more":false}' "$itens" >"$base/listagem$suf"
}

_env_arvore() { # <base> — 3 pastas, 2 arquivos pequenos em cada
  local p
  for p in p1 p2 p3; do
    _arquivo "$1" "$p/a.txt"
    _arquivo "$1" "$p/b.txt"
  done
  mkdir -p "$1/local/vazia"
}

_rec_arvore() { # <base> — remoto /r com a, b (arquivos) e c (vazia, com subpasta)
  _hash_remoto
  _ls "$1" /r "$(_d /r/a)" "$(_d /r/b)" "$(_d /r/c)"
  _ls "$1" /r/a "$(_f /r/a/a1.txt)" "$(_f /r/a/a2.txt)"
  _ls "$1" /r/b "$(_f /r/b/b1.txt)"
  _ls "$1" /r/c "$(_d /r/c/sub)"
}

# _ordem <base> — "<ultima criacao de pasta> <primeiro envio>" pelas chamadas.
_ordem() {
  local n=0 ult=0 prim=0 l
  while IFS= read -r l; do
    n=$((n + 1))
    case $l in
      *create_folder_batch*) ult=$n ;;
      *files/upload | *upload_session/*) ((prim > 0)) || prim=$n ;;
    esac
  done <"$1/chamadas"
  ORDEM_ULT_PASTA=$ult ORDEM_PRIM_ENVIO=$prim
}

teste_tc_arv_20_envio_com_paralelo_nenhum_envio_sai_antes_do_fim_da_criacao_das_pastas() {
  local base
  base=$(_cenario_env)
  _env_arvore "$base"
  : >"$base/pastas_async"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  _ordem "$base"
  assert_diferente 0 "$ORDEM_ULT_PASTA" 'houve criacao de pastas'
  assert_diferente 0 "$ORDEM_PRIM_ENVIO" 'houve envio de arquivos'

  [[ $ORDEM_ULT_PASTA -lt $ORDEM_PRIM_ENVIO ]]
  assert_igual 0 $? "RF-215(a): criacao ($ORDEM_ULT_PASTA) antes do primeiro envio ($ORDEM_PRIM_ENVIO)"
}

teste_tc_arv_20_recebimento_com_paralelo_todas_as_pastas_existem_antes_de_qualquer_download() {
  local base snap n=0 conteudo
  base=$(_cenario_rec)
  _rec_arvore "$base"
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --paralelo 4 --sem-cursor
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  for snap in "$base"/snap_*; do
    [[ -e $snap ]] || continue
    n=$((n + 1))
    conteudo=$(cat "$snap")
    assert_contem './a' "$conteudo" "RF-215(a): a existe antes do download ($snap)"
    assert_contem './b' "$conteudo" "RF-215(a): b existe antes do download ($snap)"
    assert_contem './c/sub' "$conteudo" "RF-215(a): c/sub existe antes do download ($snap)"
  done
  assert_igual 3 "$n" 'tres downloads observados'
}

teste_tc_arv_21_debug_registra_criacao_de_pasta_no_envio_sem_segredo() {
  local base
  base=$(_cenario_env)
  _env_arvore "$base"
  : >"$base/pastas_async"
  _rodar "$base" --debug sync --enviar --origem "$base/local" --destino /r --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'create_folder_batch ' "$DBX_ERRO" 'RF-215(d): create_folder_batch'
  assert_contem 'create_folder_batch/check' "$DBX_ERRO" 'RF-215(d): check do lote de pastas'
  assert_nao_contem 'sl.t' "$DBX_ERRO" 'sem token'
  assert_nao_contem 'Authorization' "$DBX_ERRO" 'sem cabecalho Authorization'
  assert_nao_contem 'Bearer' "$DBX_ERRO" 'sem Bearer'
  assert_nao_contem 'S-1' "$DBX_ERRO" 'sem session_id'
}

teste_tc_arv_21_debug_registra_delete_v2_de_pasta_orfa_sem_segredo() {
  local base
  base=$(_cenario_env)
  _arquivo "$base" k.txt
  _lista "$base" _r "$(_arq_json k.txt)" "$(_pasta_json o)"
  _lista "$base" _r_o
  _rodar "$base" --debug sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'files/delete_v2' "$DBX_ERRO" 'RF-215(d): delete_v2 de pasta'
  assert_nao_contem 'sl.t' "$DBX_ERRO" 'sem token'
  assert_nao_contem 'Bearer' "$DBX_ERRO" 'sem Bearer'
}

teste_tc_arv_21_debug_registra_mkdir_e_rmdir_locais_sem_segredo() {
  local base
  base=$(_cenario_rec)
  _hash_remoto
  _ls "$base" /r "$(_f /r/k.txt)" "$(_d /r/novo)"
  mkdir -p "$base/local/orfa"
  _rodar "$base" --debug sync --receber --espelhar --confirmar --origem /r --destino "$base/local" --sem-cursor
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'debug: pasta operacao=mkdir' "$DBX_ERRO" 'RF-215(d): mkdir'
  assert_contem 'novo' "$(grep 'operacao=mkdir' <<<"$DBX_ERRO")" 'mkdir da pasta nova'
  assert_contem 'debug: pasta operacao=rmdir' "$DBX_ERRO" 'RF-215(d): rmdir'
  assert_contem 'orfa' "$(grep 'operacao=rmdir' <<<"$DBX_ERRO")" 'rmdir da pasta orfa'
  assert_nao_contem 'sl.t' "$DBX_ERRO" 'sem token'
  assert_nao_contem 'Bearer' "$DBX_ERRO" 'sem Bearer'
}

teste_rf215e_envio_paralelo_1_e_8_produzem_a_mesma_arvore() {
  local base1 base8
  base1=$(_cenario_env)
  base8=$(_cenario_env)
  _env_arvore "$base1"
  _env_arvore "$base8"
  _rodar "$base1" sync --enviar --origem "$base1/local" --destino /r --paralelo 1
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  _rodar "$base8" sync --enviar --origem "$base8/local" --destino /r --paralelo 8
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_diferente '' "$(grep -o '"path":"[^"]*"' "$base1/lote/chamadas" | sort -u)" 'ha pastas criadas'
  assert_igual "$(grep -o '"path":"[^"]*"' "$base1/lote/chamadas" | sort -u)" \
    "$(grep -o '"path":"[^"]*"' "$base8/lote/chamadas" | sort -u)" 'mesmas pastas criadas'
  assert_igual "$(grep -o 'conteudo-p[0-9]-[ab]\.txt' "$base1/corpos" | sort -u)" \
    "$(grep -o 'conteudo-p[0-9]-[ab]\.txt' "$base8/corpos" | sort -u)" 'mesmos arquivos enviados'
}

teste_rf215e_recebimento_paralelo_1_e_8_produzem_a_mesma_arvore() {
  local base1 base8
  base1=$(_cenario_rec)
  base8=$(_cenario_rec)
  _rec_arvore "$base1"
  _rec_arvore "$base8"
  _rodar "$base1" sync --receber --origem /r --destino "$base1/local" --paralelo 1 --sem-cursor
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  _rodar "$base8" sync --receber --origem /r --destino "$base8/local" --paralelo 8 --sem-cursor
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem './c/sub' "$(cd "$base1/local" && find . | sort)" 'arvore do paralelo 1 completa'
  assert_igual "$(cd "$base1/local" && find . | sort)" "$(cd "$base8/local" && find . | sort)" 'mesma arvore final'
}

harness_executar "$@"
