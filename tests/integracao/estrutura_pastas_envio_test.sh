#!/usr/bin/env bash
# Tarefa 2 de F-103 (RF-209, RF-210(a)(e), RF-213(a)(b), RF-214(a)): no sentido
# local -> remoto (`sync --enviar` e `upload` de pasta) a arvore remota inteira e
# criada por `create_folder_batch` antes do primeiro envio. TC-ARV-01, 02, 03,
# 05 e 16, mais simulacao, `upload` de pasta e falha sistemica.
#
# Seam: o executavel `dbx` com o cliente HTTP real e um duplo de `curl` que
# registra cada URL em `$base/chamadas` (ordem) e responde as rotas em lote por
# tests/support/lote_duplo.sh (corpos de `create_folder_batch` em
# `$base/lote/chamadas`). Dado sintetico apenas.
#
# shellcheck disable=SC2016
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"

_cenario() {
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
  DBX_SAIDA='' DBX_ERRO=''
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_arquivo() { # <base> <relativo> — arquivo local com conteudo identificavel
  mkdir -p "$1/local/$(dirname -- "$2")"
  printf 'conteudo-%s' "${2//\//-}" >"$1/local/$2"
}

_pastas() { [[ -r $1/lote/chamadas ]] && grep '^create_folder_batch' "$1/lote/chamadas"; return 0; }
_corpos() { [[ -r $1/corpos ]] && cat "$1/corpos"; return 0; }

# _ordem <base> — "<ultima criacao de pasta> <primeiro envio>" pelas linhas de chamadas.
_ordem() {
  local n=0 ult=0 prim=0 l
  while IFS= read -r l; do
    n=$((n + 1))
    case $l in
      *create_folder_batch*) ult=$n ;;
      *files/upload | *upload_session/start) ((prim > 0)) || prim=$n ;;
    esac
  done <"$1/chamadas"
  ORDEM_ULT_PASTA=$ult ORDEM_PRIM_ENVIO=$prim
}

teste_tc_arv_01_pasta_vazia_e_pasta_com_arquivo_sao_criadas_e_o_arquivo_enviado() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/a/b"
  _arquivo "$base" c/x.txt
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem '"/r/a"' "$(_pastas "$base")" 'a criada (sem arquivo)'
  assert_contem '"/r/a/b"' "$(_pastas "$base")" 'a/b criada (vazia)'
  assert_contem '"/r/c"' "$(_pastas "$base")" 'c criada'
  assert_nao_contem '"/r"' "$(_pastas "$base")" 'RF-209(e): a raiz do destino segue como hoje'
  assert_contem 'conteudo-c-x.txt' "$(_corpos "$base")" 'x.txt enviado'
}

teste_tc_arv_02_pasta_podada_por_excluir_nao_e_criada() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/cache/sub" "$base/local/d"
  _arquivo "$base" cache/sub/c.txt
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --excluir 'cache/'
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem '"/r/d"' "$(_pastas "$base")" 'pasta no escopo criada'
  assert_nao_contem '/r/cache' "$(_pastas "$base")" 'RF-209(b): podada nao e criada, nem as subpastas'
}

teste_tc_arv_03_pasta_com_arquivos_todos_filtrados_por_tamanho_e_criada_vazia() {
  local base
  base=$(_cenario)
  _arquivo "$base" g/pequeno.txt
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --tamanho-min 100000
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem '"/r/g"' "$(_pastas "$base")" 'RF-209(c): filtro de tamanho nao poda a pasta'
  assert_nao_contem 'conteudo-g-pequeno.txt' "$(_corpos "$base")" 'o arquivo filtrado nao e enviado'
}

teste_tc_arv_05_com_tres_ciclos_toda_criacao_precede_o_primeiro_envio() {
  local base
  base=$(_cenario)
  _arquivo "$base" p1/a.txt
  _arquivo "$base" p2/b.txt
  _arquivo "$base" p3/c.txt
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --bloco 1
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'ciclos=3' "$DBX_SAIDA" 'tres ciclos'
  assert_igual 1 "$(_pastas "$base" | wc -l | tr -d ' ')" 'um lote unico antes do ciclo 1'
  _ordem "$base"
  assert_igual sim "$( ((ORDEM_ULT_PASTA > 0 && ORDEM_PRIM_ENVIO > ORDEM_ULT_PASTA)) && printf sim)" \
    "RF-210(a): pasta na linha $ORDEM_ULT_PASTA, primeiro envio na $ORDEM_PRIM_ENVIO"
}

teste_tc_arv_16_arquivo_no_lugar_da_pasta_falha_os_arquivos_sob_ela_e_envia_o_resto() {
  local base
  base=$(_cenario)
  _arquivo "$base" a/a1.txt
  _arquivo "$base" a/sub/s.txt
  _arquivo "$base" b/b1.txt
  : >"$base/lote/pasta_arquivo/a"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'falha de item no codigo de saida'
  assert_contem 'arquivo no lugar da pasta: /r/a' "$DBX_ERRO" 'RF-214(a): motivo da pasta'
  assert_contem 'falha a/a1.txt: ' "$DBX_ERRO" 'arquivo direto sob a pasta falha'
  assert_contem 'falha a/sub/s.txt: ' "$DBX_ERRO" 'arquivo em qualquer profundidade falha'
  assert_contem 'pasta de destino nao criada: /r/a' "$DBX_ERRO" 'RF-213(a): motivo do arquivo'
  assert_nao_contem 'conteudo-a-a1.txt' "$(_corpos "$base")" 'nao tentado'
  assert_nao_contem 'conteudo-a-sub-s.txt' "$(_corpos "$base")" 'nao tentado'
  assert_contem 'conteudo-b-b1.txt' "$(_corpos "$base")" 'o resto segue'
  assert_nao_contem 'delete' "$(cat "$base/chamadas")" 'nada e apagado'
}

teste_simulacao_nao_chama_criacao_de_pastas() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/a/b"
  _arquivo "$base" c/x.txt
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_nao_contem 'create_folder_batch' "$(cat "$base/chamadas")" 'RF-210(e): nenhuma chamada em simulacao'
}

teste_upload_de_pasta_cria_a_arvore_antes_do_primeiro_envio() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/vazia"
  _arquivo "$base" c/x.txt
  _rodar "$base" upload "$base/local" /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem '/vazia"' "$(_pastas "$base")" 'pasta vazia criada pelo upload de pasta'
  _ordem "$base"
  assert_igual sim "$( ((ORDEM_ULT_PASTA > 0 && ORDEM_PRIM_ENVIO > ORDEM_ULT_PASTA)) && printf sim)" \
    "RF-210(a): pasta na linha $ORDEM_ULT_PASTA, primeiro envio na $ORDEM_PRIM_ENVIO"
}

teste_falha_sistemica_na_criacao_para_antes_de_qualquer_envio() {
  local base
  base=$(_cenario)
  _arquivo "$base" r.txt
  _arquivo "$base" a/a1.txt
  : >"$base/lote/pasta_sem_espaco/a"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'RF-213(b): parada'
  assert_contem 'sem espaco na conta Dropbox para criar pastas' "$DBX_ERRO" 'classe e motivo do lote'
  assert_nao_contem 'upload' "$(cat "$base/chamadas")" 'nenhuma transferencia'
  assert_nao_contem 'delete' "$(cat "$base/chamadas")" 'nenhuma exclusao'
}

teste_tc_arv_05b_origem_so_com_pastas_vazias_e_recusada_sem_criar_pasta() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/a/b" "$base/local/c"
  printf '%s' '{"entries":[{".tag":"file","name":"velho.txt","path_display":"/r/velho.txt","path_lower":"/r/velho.txt","content_hash":"h","size":3,"rev":"0a1"}],"has_more":false}' >"$base/listagem"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 14 "$DBX_ESTADO" 'RF-210(g): origem vazia recusada com nao_concluida (14)'
  assert_contem 'recusada=origem vazia' "$DBX_SAIDA" 'RF-41(b): recusa por origem vazia'
  assert_igual '' "$(_pastas "$base")" 'RF-210(g): nenhuma create_folder_batch antes da recusa'
}

teste_pasta_vazia_ocupada_conta_ela_mesma_como_falha_de_item() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/a"
  _arquivo "$base" b/b1.txt
  : >"$base/lote/pasta_arquivo/a"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'RF-213(a): a pasta vazia que falha e falha de item'
  assert_contem 'falha a: ' "$DBX_ERRO" 'a pasta e citada na saida de falhas'
  assert_contem 'arquivo no lugar da pasta: /r/a' "$DBX_ERRO" 'motivo da pasta'
  assert_contem 'conteudo-b-b1.txt' "$(_corpos "$base")" 'o resto segue'
}

# RF-214 (DIV-401): arquivo remoto no lugar de pasta da origem.
_listagem_arquivo() { # <base> <nome> — o destino /r tem um ARQUIVO <nome> com rev conhecido
  printf '{"entries":[{".tag":"file","name":"%s","path_display":"/r/%s","path_lower":"/r/%s","content_hash":"h","size":3,"rev":"0a1b2c3d4e"}],"has_more":false}' \
    "$2" "$2" "$2" >"$1/listagem"
}

_sequencia() { # <base> — as chamadas relevantes, na ordem, pelo ultimo segmento da URL
  grep -E 'create_folder_batch|list_folder|delete_v2|delete_batch|upload' "$1/chamadas" | sed 's#.*/##' | tr '\n' ' '
}

teste_tc_arv_17_espelhar_apaga_o_arquivo_antes_de_criar_a_pasta_e_envia_na_mesma_execucao() {
  local base
  base=$(_cenario)
  _arquivo "$base" a/x.txt
  _arquivo "$base" b.txt
  : >"$base/lote/pasta_arquivo/a"
  _listagem_arquivo "$base" a
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'create_folder_batch list_folder delete_v2 create_folder_batch' "$(_sequencia "$base")" 'RF-214(b): cria, lista o pai, apaga, cria de novo'
  assert_contem '"path":"/r/a","parent_rev":"0a1b2c3d4e"' "$(_corpos "$base")" 'RF-214(c)(6): delete_v2 com o rev observado'
  assert_nao_contem 'delete_batch' "$(_sequencia "$base")" 'nunca delete_batch neste caso'
  assert_contem 'conteudo-a-x.txt' "$(_corpos "$base")" 'o arquivo sob a pasta e enviado na mesma execucao'
  assert_contem 'apagados' "$DBX_SAIDA" 'relatorio'
  assert_contem 'apagados=1' "$DBX_SAIDA" 'RF-214(e): conta uma vez (sem dupla contagem)'
  assert_contem 'arquivo no lugar da pasta' "$DBX_ERRO" 'RF-214(e): motivo no relatorio'
}

teste_tc_arv_17_sem_espelhar_nao_chama_delete_v2_e_a_pasta_falha() {
  local base
  base=$(_cenario)
  _arquivo "$base" a/x.txt
  : >"$base/lote/pasta_arquivo/a"
  _listagem_arquivo "$base" a
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'RF-214(a): falha de item'
  assert_contem 'arquivo no lugar da pasta: /r/a' "$DBX_ERRO" 'motivo'
  assert_nao_contem 'delete_v2' "$(_sequencia "$base")" 'RF-214(a): nada e apagado'
}

teste_tc_arv_17b_destino_filtrado_e_protegido_e_a_pasta_falha() {
  local base
  base=$(_cenario)
  _arquivo "$base" a/x.txt
  _arquivo "$base" b.txt
  : >"$base/lote/pasta_arquivo/a"
  _listagem_arquivo "$base" a
  _rodar "$base" sync --enviar --espelhar --confirmar --incluir 'a/' --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'RF-214(c)(3): falha de item'
  assert_contem 'arquivo no lugar da pasta: /r/a' "$DBX_ERRO" 'motivo'
  assert_nao_contem 'delete_v2' "$(_sequencia "$base")" 'filtro protege o destino'
  assert_nao_contem 'delete_batch' "$(_sequencia "$base")" 'nem o delete comum'
}

teste_tc_arv_17b_rev_divergente_no_delete_v2_nao_apaga_e_a_pasta_falha() {
  local base
  base=$(_cenario)
  _arquivo "$base" a/x.txt
  _arquivo "$base" b.txt
  : >"$base/lote/pasta_arquivo/a"
  : >"$base/delete_v2_409"
  _listagem_arquivo "$base" a
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'RF-214(d): falha de item'
  assert_contem 'arquivo no lugar da pasta: /r/a' "$DBX_ERRO" 'motivo'
  assert_contem 'pasta de destino nao criada: /r/a' "$DBX_ERRO" 'descendente falha'
  assert_nao_contem 'conteudo-a-x.txt' "$(_corpos "$base")" 'nada enviado sob a pasta'
  assert_nao_contem 'delete_batch' "$(_sequencia "$base")" 'o arquivo nao e apagado depois por outro caminho'
  assert_contem 'conteudo-b.txt' "$(_corpos "$base")" 'o resto segue'
}

teste_tc_arv_17b_item_listado_como_pasta_nao_apaga() {
  local base
  base=$(_cenario)
  _arquivo "$base" a/x.txt
  _arquivo "$base" b.txt
  : >"$base/lote/pasta_arquivo/a"
  printf '%s' '{"entries":[{".tag":"folder","name":"a","path_display":"/r/a","path_lower":"/r/a","id":"id:a"}],"has_more":false}' >"$base/listagem"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'RF-214(c)(6): alvo sem tag file'
  assert_nao_contem 'delete_v2' "$(_sequencia "$base")" 'pasta nunca e apagada'
}

teste_tc_arv_17b_origem_vazia_e_leitura_parcial_nao_apagam_antes_de_criar() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/a"
  : >"$base/lote/pasta_arquivo/a"
  _listagem_arquivo "$base" a
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 14 "$DBX_ESTADO" 'RF-214(c)(4): origem vazia recusada'
  assert_nao_contem 'delete_v2' "$(_sequencia "$base")" 'nada apagado'
}

teste_div_400_item_de_exclusao_sob_pasta_que_falhou_nao_e_apagado() {
  local base
  base=$(_cenario)
  _arquivo "$base" a/x.txt
  _arquivo "$base" b.txt
  : >"$base/lote/pasta_arquivo/a"
  printf '%s' '{"entries":[{".tag":"file","name":"velho.txt","path_display":"/r/a/velho.txt","path_lower":"/r/a/velho.txt","content_hash":"h","size":3,"rev":"0a1b2c3d4e"}],"has_more":false}' >"$base/listagem"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'a pasta falhou'
  assert_nao_contem 'delete_batch' "$(_sequencia "$base")" 'DIV-400: nada sob a pasta que falhou e apagado'
  assert_nao_contem 'delete_v2' "$(_sequencia "$base")" 'DIV-400: nem por delete_v2'
}

# RF-216 (Tarefa 5), envio: exclusao de pasta orfa REMOTA, so com --espelhar,
# depois das exclusoes de arquivo do ciclo, com releitura nao recursiva imediatamente
# antes e `delete_v2` de UMA pasta por chamada. Destino /r; origem local com k.txt.
_pasta_json() { printf '{".tag":"folder","name":"%s","path_display":"/r/%s","path_lower":"/r/%s","id":"id:%s"}' "${1##*/}" "$1" "$1" "${1//\//}"; }
_arq_json() { printf '{".tag":"file","name":"%s","path_display":"/r/%s","path_lower":"/r/%s","content_hash":"h","size":3,"rev":"0a1b2c3d4e"}' "${1##*/}" "$1" "$1"; }
_lista() { # <base> <sufixo do arquivo, ex.: _r_o> <entradas...>
  local base=$1 suf=$2 itens
  shift 2
  itens=$(IFS=,; printf '%s' "$*")
  printf '{"entries":[%s],"has_more":false}' "$itens" >"$base/listagem$suf"
}
_deletes_v2() { _harness_contar 'files/delete_v2' "$1/chamadas"; }
_orfa_remota() { # <base> — origem local com k.txt; /r tem a pasta o
  _arquivo "$1" k.txt
  _lista "$1" _r "$(_arq_json k.txt)" "$(_pasta_json o)"
}

teste_tc_arv_04_upload_de_arquivo_unico_nao_chama_criacao_de_pasta() {
  local base
  base=$(_cenario)
  _arquivo "$base" x.txt
  _rodar "$base" upload "$base/local/x.txt" /r/x.txt
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'files/upload' "$base/chamadas")" 'o arquivo foi enviado'
  assert_igual 0 "$(_harness_contar 'create_folder' "$base/chamadas")" 'RF-209(d): nenhuma criacao de pasta'
}

teste_tc_arv_28_subarvore_so_no_destino_com_pagina_que_falha_nada_dentro_e_apagado() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  printf '%s' "{\"entries\":[$(_pasta_json o/p)],\"has_more\":true,\"cursor\":\"CUR-O\"}" >"$base/listagem_r_o"
  _lista "$base" _r_o_p
  mv "$base/bin/curl" "$base/bin/curl_base"
  {
    printf '#!/usr/bin/env bash\nbase=%q\n' "$base"
    cat <<'FIM'
saida=""; escrever=""; anterior=""; url=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
if [[ $url == *list_folder/continue ]]; then
  printf '%s\n' "$url" >>"$base/chamadas"
  [[ -n $saida ]] && printf '{"error_summary":"x"}' >"$saida"
  [[ -n $escrever ]] && printf 500
  exit 0
fi
exec "$base/bin/curl_base" "$@"
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'a leitura da subarvore falhou'
  assert_diferente 0 "$(_harness_contar 'list_folder/continue' "$base/chamadas")" 'a pagina que falha foi pedida (esgotando as tentativas)'
  assert_igual 0 "$(_deletes_v2 "$base")" 'RF-216(h): nenhuma pasta da subarvore apagada'
  assert_nao_contem 'delete_batch' "$(_sequencia "$base")" 'nenhum arquivo apagado em lote'
}

teste_tc_arv_28_releitura_da_orfa_com_pagina_que_falha_nao_apaga() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o
  printf '%s' '{"entries":[],"has_more":true,"cursor":"CUR-REL"}' >"$base/listagem_r_o.2"
  mv "$base/bin/curl" "$base/bin/curl_base"
  {
    printf '#!/usr/bin/env bash\nbase=%q\n' "$base"
    cat <<'FIM'
saida=""; escrever=""; anterior=""; url=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
if [[ $url == *list_folder/continue ]]; then
  printf '%s\n' "$url" >>"$base/chamadas"
  [[ -n $saida ]] && printf '{"error_summary":"x"}' >"$saida"
  [[ -n $escrever ]] && printf 500
  exit 0
fi
exec "$base/bin/curl_base" "$@"
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_diferente 0 "$(_harness_contar 'list_folder/continue' "$base/chamadas")" 'a pagina da releitura falhou (esgotando as tentativas)'
  assert_igual 0 "$(_deletes_v2 "$base")" 'RF-216(h): releitura incompleta nao apaga a pasta'
  assert_contem 'pastas_apagadas=0' "$DBX_SAIDA" 'nenhuma pasta apagada'
  assert_contem 'pasta mantida: o (releitura falhou)' "$DBX_ERRO" 'a pasta consta como mantida, com o motivo'
}

teste_rf216_pasta_remota_orfa_vazia_vai_para_delete_v2_apos_releitura() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_deletes_v2 "$base")" 'RF-216(e): um delete_v2'
  assert_contem '{"path":"/r/o"}' "$(_corpos "$base")" 'delete_v2 da propria pasta, sem parent_rev'
  assert_nao_contem '{"path":"/r"}' "$(_corpos "$base")" 'RF-216(j): a raiz nunca'
  assert_contem 'pasta apagada: o' "$DBX_ERRO" 'consta do relatorio'
  assert_igual 3 "$(_harness_contar 'list_folder$' "$base/chamadas")" 'raiz, leitura do ramo e releitura da pasta imediatamente antes (nao recursivas)'
}

teste_rf216_sem_espelhar_nenhuma_pasta_remota_e_apagada() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o
  _rodar "$base" sync --enviar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$(_deletes_v2 "$base")" 'RF-216(a): sem --espelhar nada'
}

teste_rf216_pasta_orfa_com_arquivo_orfao_arquivo_em_lote_depois_pasta_por_delete_v2() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o "$(_arq_json o/x.txt)"
  _lista "$base" _r_o.2
  printf '{"entries":[],"has_more":false}' >"$base/listagem_r_o.2"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  local seq
  seq=$(_sequencia "$base")
  assert_contem 'delete_batch' "$seq" 'o arquivo sai pela exclusao comum'
  assert_igual sim "$([[ ${seq%%delete_v2*} == *delete_batch* ]] && printf sim)" 'RF-215(c): pasta depois da exclusao de arquivo'
  assert_igual 1 "$(_deletes_v2 "$base")" 'um delete_v2 (a pasta)'
}

teste_rf216_pastas_remotas_aninhadas_filho_antes_do_pai() {
  local base
  base=$(_cenario)
  _arquivo "$base" k.txt
  _lista "$base" _r "$(_arq_json k.txt)" "$(_pasta_json a)"
  _lista "$base" _r_a "$(_pasta_json a/b)"
  _lista "$base" _r_a_b
  _lista "$base" _r_a.2
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual 2 "$(_deletes_v2 "$base")" 'duas pastas, um delete_v2 cada'
  local c
  c=$(_corpos "$base")
  local pre_b=${c%%'{"path":"/r/a/b"}'*} pre_a=${c%%'{"path":"/r/a"}'*}
  assert_igual sim "$([[ $c == *'{"path":"/r/a/b"}'* && ${#pre_b} -lt ${#pre_a} ]] && printf sim)" 'RF-216(c): a/b antes de a'
}

teste_rf216_releitura_com_entrada_nova_mantem_a_pasta_sem_delete_v2() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o
  _lista "$base" _r_o.2 "$(_arq_json o/novo.txt)"
  printf '{"entries":[{".tag":"file","name":"novo.txt","path_display":"/r/o/novo.txt","path_lower":"/r/o/novo.txt","content_hash":"h","size":3,"rev":"0a1b2c3d4e"}],"has_more":false}' >"$base/listagem_r_o.2"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$(_deletes_v2 "$base")" 'RF-216(e): zero delete_v2 da pasta'
  assert_contem 'pasta mantida: o' "$DBX_ERRO" 'mantida com motivo'
}

teste_rf216_pasta_remota_com_item_filtrado_nunca_e_apagada() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o "$(_arq_json o/x.log)"
  _rodar "$base" sync --enviar --espelhar --confirmar --excluir '*.log' --origem "$base/local" --destino /r
  assert_igual 0 "$(_deletes_v2 "$base")" 'RF-216(f): item filtrado protege a pasta'
  assert_nao_contem 'delete_batch' "$(_sequencia "$base")" 'e o arquivo filtrado tambem'
}

teste_rf216_pasta_remota_excluida_por_filtro_nunca_e_apagada() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o
  _rodar "$base" sync --enviar --espelhar --confirmar --excluir 'o/' --origem "$base/local" --destino /r
  assert_igual 0 "$(_deletes_v2 "$base")" 'RF-216(f): pasta excluida por RF-80'
}

teste_rf216_origem_vazia_recusa_antes_de_apagar_pasta_remota() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/d"
  _lista "$base" _r "$(_pasta_json o)"
  _lista "$base" _r_o
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 14 "$DBX_ESTADO" 'RF-216(g): recusa por origem vazia'
  assert_igual 0 "$(_deletes_v2 "$base")" 'nenhuma pasta apagada'
}

teste_rf216_leitura_parcial_desliga_a_exclusao_de_pasta() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o
  ln -s "$base/local" "$base/local/ligacao"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$(_deletes_v2 "$base")" 'RF-216(g): travessia parcial'
}

teste_rf216_simulacao_nao_escreve_nem_rele_a_pasta() {
  local base
  base=$(_cenario)
  _orfa_remota "$base"
  _lista "$base" _r_o
  _rodar "$base" --dry-run sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$(_deletes_v2 "$base")" 'RF-217(b): zero delete_v2'
  assert_igual 2 "$(_harness_contar 'list_folder$' "$base/chamadas")" 'sem releitura de confirmacao: so raiz e ramo'
}

teste_rf216_a_decisao_remota_nao_apaga_em_lote_nem_permanentemente() {
  local fonte
  fonte=$(sed -n '/^_dbx_cmd_sync_pastas_orfas_/,/^}/p' "$DBX_HARNESS_RAIZ/commands/sync.sh")
  assert_diferente '' "$fonte" 'as funcoes de pasta orfa existem'
  assert_nao_contem 'delete_batch' "$fonte" 'DIV-402: nunca delete_batch de pasta'
  assert_nao_contem 'permanently_delete' "$fonte" 'DIV-402: nunca permanently_delete'
}

harness_executar "$@"
