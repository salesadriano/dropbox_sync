#!/usr/bin/env bash
# Etapa 2 de F-101 (RF-187 a RF-191, RF-193 a RF-196): o `sync` em ciclos cortados
# por diretorio, com `curl` duplo que responde a listagem POR DIRETORIO.
#
# O duplo guarda cada corpo de requisicao em `$base/corpos`; a listagem de cada
# pasta vem de `$base/ls/<caminho com nao-alfanumerico trocado por _>`, padrao
# vazia. Dado sintetico apenas.
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

_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/blocos.XXXXXX")
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
  *files/download*) corpo=$(cat "$base/conteudo_remoto") ;;
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

# _ls <base> <caminho> <entradas json...>
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

_arvore_local() { # <base>: raiz, a (2), b (1), c (2)
  local base=$1 d
  mkdir -p "$base/local/a" "$base/local/b" "$base/local/c"
  for d in a/a1 a/a2 b/b1 c/c1 c/c2; do printf 'x%s' "$d" >"$base/local/$d.txt"; done
}

_escritas() { _harness_contar 'files/upload\|files/delete_v2' "$1/chamadas"; }

teste_blc_enviar_forma_ciclos_por_diretorio_e_consulta_so_nao_recursivo() {
  local base
  base=$(_cenario)
  _arvore_local "$base"
  _rodar "$base" --json --progresso sync --enviar --origem "$base/local" --destino /r --bloco 2
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'ciclos=2' "$DBX_SAIDA" 'raiz e a (2) fecham o ciclo 1; b e c (3) o ciclo 2'
  assert_contem 'bloco=2' "$DBX_SAIDA" 'tamanho efetivo'
  assert_contem 'enviados=5' "$DBX_SAIDA" 'os cinco arquivos, nenhum omitido nem duplicado (RF-187(d))'
  assert_contem '[sync] ciclo 1' "$DBX_ERRO" 'progresso por ciclo'
  assert_contem '[sync] ciclo 2' "$DBX_ERRO" 'progresso por ciclo'
  assert_nao_contem '"recursive":true' "$(cat "$base/corpos")" 'RF-189(a): nenhum recursivo na varredura completa'
  assert_contem '"path":"/r/c"' "$(cat "$base/corpos")" 'o destino so e consultado nos diretorios do ciclo'
}

teste_blc_uma_arvore_que_cabe_em_um_ciclo_nao_muda_o_resultado() {
  local base
  base=$(_cenario)
  _arvore_local "$base"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'enviados=5' "$DBX_SAIDA" 'mesmo resultado'
  assert_nao_contem 'ciclos=' "$DBX_SAIDA" 'sem campo novo fora do --json com um ciclo'
}

teste_blc_receber_percorre_os_diretorios_remotos_nao_recursivamente() {
  local base
  _hash_remoto
  base=$(_cenario)
  _ls "$base" /r "$(_f /r/r1.txt)" "$(_d /r/a)" "$(_d /r/b)"
  _ls "$base" /r/a "$(_f /r/a/a1.txt)" "$(_f /r/a/a2.txt)"
  _ls "$base" /r/b "$(_f /r/b/b1.txt)"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local" --bloco 2 --sem-cursor
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'recebidos=4' "$DBX_SAIDA" 'todos os arquivos'
  assert_contem 'ciclos=2' "$DBX_SAIDA" 'ciclos'
  assert_arquivo_existe "$base/local/b/b1.txt" 'recebido no ciclo 2'
  assert_nao_contem '"recursive":true' "$(cat "$base/corpos")" 'RF-189(a)'
}

teste_blc_download_de_pasta_usa_ciclos() {
  local base
  _hash_remoto
  base=$(_cenario)
  printf '{".tag":"folder","id":"id:Draiz","path_display":"/r","path_lower":"/r"}' >"$base/meta"
  _ls "$base" /r "$(_f /r/r1.txt)" "$(_d /r/a)"
  _ls "$base" /r/a "$(_f /r/a/a1.txt)" "$(_f /r/a/a2.txt)"
  _rodar "$base" --json download /r "$base/saida" --bloco 2 --excluir "*.tmp"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_arquivo_existe "$base/saida/a/a2.txt" 'recebido pela descida por diretorio'
  assert_contem '"recursive":false' "$(cat "$base/corpos")" 'listagem por diretorio'
  assert_nao_contem '"recursive":true' "$(cat "$base/corpos")" 'RF-189(a)'
}

teste_blc_espelhar_apaga_so_em_diretorio_lido_inteiro_e_o_so_do_destino_depois_do_pai() {
  local base
  _hash_remoto
  base=$(_cenario)
  _arvore_local "$base"
  _ls "$base" /r "$(_d /r/a)" "$(_d /r/zz)"
  _ls "$base" /r/a "$(_f /r/a/velho.txt)"
  _ls "$base" /r/zz "$(_f /r/zz/z1.txt)"
  _rodar "$base" --json sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --bloco 2
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'apagados=2' "$DBX_SAIDA" 'a/velho.txt e o conteudo do diretorio so do destino'
  assert_contem 'files/delete_v2' "$(cat "$base/chamadas")" 'exclusoes emitidas'
}

teste_blc_travessia_parcial_desliga_a_exclusao_na_execucao_inteira() {
  local base
  [[ $(id -u) -ne 0 ]] || return 0
  base=$(_cenario)
  _arvore_local "$base"
  chmod 000 "$base/local/c"
  _ls "$base" /r/a "$(_f /r/a/velho.txt)"
  _rodar "$base" --json sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --bloco 2
  chmod 755 "$base/local/c"
  assert_diferente 0 "$DBX_ESTADO" 'parcial: codigo diferente de zero (RF-41(a))'
  assert_contem 'exclusao_desabilitada=' "$DBX_SAIDA" 'exclusao desligada'
  assert_igual 0 "$(_harness_contar 'files/delete_v2' "$base/chamadas")" 'nenhuma exclusao em ciclo algum'
}

teste_blc_origem_vazia_com_algo_a_apagar_e_recusa_14_sem_escrita() {
  local base
  _hash_remoto
  base=$(_cenario)
  mkdir -p "$base/local/vazio"
  _ls "$base" /r "$(_d /r/outro)"
  _ls "$base" /r/outro "$(_f /r/outro/x.txt)"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --bloco 2
  assert_igual 14 "$DBX_ESTADO" "origem vazia e algo a apagar (no diretorio so do destino tambem): $DBX_ERRO"
  assert_igual 0 "$(_escritas "$base")" 'nenhuma escrita'
}

teste_blc_colisao_de_caixa_no_diretorio_do_ciclo_recusa_antes_de_escrever() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/a"
  printf 1 >"$base/local/a/x.txt"
  printf 2 >"$base/local/a/X.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --bloco 2
  assert_diferente 0 "$DBX_ESTADO" 'colisao e recusa'
  assert_contem 'colisao de caixa' "$DBX_ERRO" 'motivo'
  assert_igual 0 "$(_escritas "$base")" 'nada escrito'
}

teste_blc_dry_run_percorre_os_ciclos_sem_escrever() {
  local base
  base=$(_cenario)
  _arvore_local "$base"
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --bloco 2
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'transferir=c/c2.txt' "$DBX_SAIDA" 'plano do ultimo ciclo'
  assert_contem 'transferir=a/a1.txt' "$DBX_SAIDA" 'plano do primeiro ciclo'
  assert_igual 0 "$(_escritas "$base")" 'nenhuma escrita'
}

teste_blc_falha_de_arquivo_segue_e_falha_de_enumeracao_para() {
  local base
  base=$(_cenario)
  _arvore_local "$base"
  printf '500' >"$base/upload_erro"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --bloco 2
  assert_diferente 0 "$DBX_ESTADO" 'falha de arquivo reflete no codigo'
  assert_contem 'ciclos=2' "$DBX_SAIDA" 'os dois ciclos foram tentados apesar da falha de arquivo'
  rm -f "$base/upload_erro" "$base/chamadas" "$base/corpos"
  mkdir -p "$base/lserro"
  printf '500' >"$base/lserro/_r_c"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --bloco 2
  assert_diferente 0 "$DBX_ESTADO" 'falha de enumeracao do ciclo 2'
  assert_contem 'ciclos_concluidos=1' "$DBX_SAIDA" 'ciclo 1 ficou'
  assert_contem 'ciclo_falho=2' "$DBX_SAIDA" 'ciclo que falhou'
  assert_contem 'ciclos_nao_tentados=0' "$DBX_SAIDA" 'nada alem do ciclo falho'
}

teste_blc_download_de_arquivo_ignora_a_variavel_invalida_e_o_de_pasta_recusa_2_sem_escrita() {
  # RF-186(e): `DBX_BLOCO` so e lida onde ha pasta. O teste da etapa 2 exigia 2
  # tambem em arquivo unico (briefing errado); aqui segue o requisito.
  local base
  base=$(_cenario)
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" TMPDIR="$DBX_TESTES_TMP" \
    DBX_BLOCO=abc bash "$DBX_EXEC" download /r/arquivo.txt "$base/saida.txt" >"$base/out" 2>"$base/err" </dev/null
  assert_igual 0 "$?" 'arquivo unico: variavel invalida nao quebra'
  assert_arquivo_existe "$base/saida.txt" 'arquivo baixado'
  rm -f "$base/chamadas"
  printf '{".tag":"folder","id":"id:Draiz","path_display":"/r","path_lower":"/r"}' >"$base/meta"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    DBX_BLOCO=abc bash "$DBX_EXEC" download /r "$base/pasta" --excluir "*.tmp" >"$base/out" 2>"$base/err" </dev/null
  assert_igual 2 "$?" 'pasta: uso invalido assim que o alvo se revela pasta'
  assert_contem 'DBX_BLOCO' "$(cat "$base/err")" 'nomeia a variavel'
  assert_arquivo_ausente "$base/pasta" 'nada escrito'
  assert_arquivo_ausente "$base/estado" 'nenhum estado'
  assert_nao_contem 'list_folder' "$(cat "$base/chamadas")" 'nenhuma listagem'
}

_cursor_gravado() { compgen -G "$1/estado/dbx/cursor-*" >/dev/null; }
_arvore_remota() { # <base>
  local base=$1
  _hash_remoto
  _ls "$base" /r "$(_f /r/r1.txt)" "$(_d /r/a)" "$(_d /r/b)"
  _ls "$base" /r/a "$(_f /r/a/a1.txt)" "$(_f /r/a/a2.txt)"
  _ls "$base" /r/b "$(_f /r/b/b1.txt)"
}
_receber() { # <base> [opcoes]: --dry-run e --debug sao globais; as demais, do sync
  local base=$1 a
  local -a globais=() locais=()
  shift
  for a in "$@"; do
    case $a in --dry-run | --debug) globais+=("$a") ;; *) locais+=("$a") ;; esac
  done
  _rodar "$base" --json ${globais[@]+"${globais[@]}"} sync --receber --origem /r --destino "$base/local" --bloco 2 ${locais[@]+"${locais[@]}"}
}

teste_blc_primeira_execucao_em_ciclos_grava_cursor_e_retrato_e_a_segunda_usa_o_delta() {
  local base
  base=$(_cenario)
  _arvore_remota "$base"
  _receber "$base"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'ciclos=2' "$DBX_SAIDA" 'primeira execucao sem cursor: em ciclos (RF-192)'
  assert_contem 'recebidos=4' "$DBX_SAIDA" 'todos os arquivos'
  _cursor_gravado "$base" || fail 'cursor e retrato deviam ter sido gravados'
  assert_igual 1 "$(_harness_contar '"recursive":true' "$base/corpos")" 'so a chamada do cursor e recursiva (RF-189(a))'
  local urls
  urls=$(cat "$base/chamadas")
  assert_contem 'get_latest_cursor' "$urls" 'cursor pedido'
  [[ $(grep -n 'get_latest_cursor' "$base/chamadas" | head -1 | cut -d: -f1) -lt $(grep -n 'list_folder$' "$base/chamadas" | head -1 | cut -d: -f1) ]] ||
    fail 'o cursor deve ser pedido antes da primeira listagem de diretorio'
  rm -f "$base/chamadas" "$base/corpos"
  _receber "$base"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'list_folder/continue' "$(cat "$base/chamadas")" 'segunda execucao: delta'
  assert_nao_contem 'get_latest_cursor' "$(cat "$base/chamadas")" 'sem novo cursor'
  assert_nao_contem '"recursive":false' "$(cat "$base/corpos" 2>/dev/null)" 'sem listagem por diretorio'
}

teste_blc_retrato_dos_ciclos_e_o_da_varredura_recursiva_da_mesma_arvore() {
  # TC-BLC-18: esperado derivado da arvore (formato de lib/state), nao do codigo.
  local base arquivo esperado
  base=$(_cenario)
  _arvore_remota "$base"
  _receber "$base"
  arquivo=$(compgen -G "$base/estado/dbx/cursor-*" | head -1)
  esperado=$(for e in /r/a /r/a/a1.txt /r/a/a2.txt /r/b /r/b/b1.txt /r/r1.txt; do printf '%s\n' "$e"; done)
  local obtido
  obtido=$(tr '\0' '\n' <"$arquivo" | grep -a '^/r/' | sort)
  assert_igual "$esperado" "$obtido" 'mesmo conjunto de caminhos do retrato recursivo, sem repeticao nem omissao'
}

teste_blc_dry_run_nao_grava_cursor_nem_retrato() {
  local base
  base=$(_cenario)
  _arvore_remota "$base"
  _receber "$base" --dry-run
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'transferir=b/b1.txt' "$DBX_SAIDA" 'plano do ultimo ciclo (os dois ciclos rodaram)'
  _cursor_gravado "$base" && fail 'dry-run nao grava (RF-112)'
  assert_nao_contem 'get_latest_cursor' "$(cat "$base/chamadas")" 'nem pede o cursor'
}

teste_blc_falha_no_ciclo_k_nao_grava() {
  local base
  base=$(_cenario)
  _arvore_remota "$base"
  mkdir -p "$base/lsapos"
  printf '0' >"$base/lsapos/_r_b"  # /r/b e lido so no ciclo 2 (em fluxo) e essa leitura falha
  _receber "$base"
  assert_diferente 0 "$DBX_ESTADO" 'falha de enumeracao do ciclo 2'
  assert_contem 'ciclo_falho=2' "$DBX_SAIDA" 'ciclo que falhou'
  _cursor_gravado "$base" && fail 'falha de ciclo nao grava'
  return 0
}

teste_blc_leitura_parcial_nao_grava() {
  local base
  [[ $(id -u) -ne 0 ]] || return 0
  base=$(_cenario)
  _arvore_remota "$base"
  mkdir -p "$base/local/c"
  printf x >"$base/local/c/z.txt"
  chmod 000 "$base/local/c"
  _receber "$base"
  chmod 755 "$base/local/c"
  assert_diferente 0 "$DBX_ESTADO" 'travessia parcial: codigo diferente de zero'
  _cursor_gravado "$base" && fail 'parcial nao grava'
  return 0
}

teste_blc_varredura_completa_forcada_roda_em_ciclos_e_regrava() {
  local base
  base=$(_cenario)
  _arvore_remota "$base"
  _receber "$base"
  rm -f "$base/chamadas" "$base/corpos"
  _rodar "$base" --json sync --receber --varredura-completa --origem /r --destino "$base/local" --bloco 2
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'ciclos=2' "$DBX_SAIDA" 'forcada: ciclos'
  assert_contem 'get_latest_cursor' "$(cat "$base/chamadas")" 'novo cursor'
  _cursor_gravado "$base" || fail 'regravado'
}

# RF-189, RF-188(b): coleta remota em fluxo, cada diretorio listado uma unica vez.
teste_blc_receber_lista_cada_diretorio_remoto_exatamente_uma_vez() {
  local base d n
  base=$(_cenario)
  _arvore_remota "$base"
  _receber "$base" --sem-cursor
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'ciclos=2' "$DBX_SAIDA" 'dois ciclos'
  for d in /r /r/a /r/b; do
    n=$(_harness_contar "\"path\":\"$d\"" "$base/corpos")
    assert_igual 1 "$n" "list_folder de $d exatamente uma vez"
  done
}

# RF-187(c): diretorio com mais de N arquivos forma ciclo SOZINHO no receber em fluxo.
teste_blc_receber_diretorio_maior_que_n_forma_ciclo_sozinho() {
  local base d n
  base=$(_cenario)
  _hash_remoto
  _ls "$base" /r "$(_f /r/r1.txt)" "$(_d /r/a)"
  _ls "$base" /r/a "$(_f /r/a/a1.txt)" "$(_f /r/a/a2.txt)" "$(_f /r/a/a3.txt)"
  _receber "$base" --sem-cursor
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'ciclos=2' "$DBX_SAIDA" 'raiz num ciclo e a/ sozinho no outro'
  assert_contem 'recebidos=4' "$DBX_SAIDA" 'todos os arquivos'
  for d in /r /r/a; do
    n=$(_harness_contar "\"path\":\"$d\"" "$base/corpos")
    assert_igual 1 "$n" "list_folder de $d exatamente uma vez"
  done
}

# RF-190(b), RF-190(a): ramo local so do destino no receber com --espelhar.
teste_blc_receber_espelhar_apaga_ramo_local_que_so_existe_no_destino() {
  local base
  base=$(_cenario)
  _arvore_remota "$base"
  mkdir -p "$base/local/so_aqui/fundo" "$base/local/b"
  printf x >"$base/local/so_aqui/fundo/velho.txt"
  printf x >"$base/local/b/velho_b.txt"
  _receber "$base" --espelhar --confirmar --sem-cursor
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'recebidos=4' "$DBX_SAIDA" 'a origem toda chega'
  assert_contem 'apagados=2' "$DBX_SAIDA" 'o ramo so do destino e o arquivo de b'
  [[ ! -e $base/local/so_aqui/fundo/velho.txt ]] || fail 'ramo so do destino apagado'
  [[ ! -e $base/local/b/velho_b.txt ]] || fail 'extra do diretorio lido inteiro apagado'
  assert_arquivo_existe "$base/local/b/b1.txt" 'origem preservada'
}

# RF-194: o resumo de --debug traz o tamanho do bloco e os ciclos.
teste_blc_debug_traz_a_linha_bloco_no_resumo() {
  local base
  base=$(_cenario)
  _arvore_remota "$base"
  _rodar "$base" --json --debug sync --receber --origem /r --destino "$base/local" --bloco 2 --sem-cursor
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'bloco=2' "$DBX_ERRO" 'linha bloco no resumo de --debug'
  assert_contem 'ciclos=2' "$DBX_ERRO" 'ciclos no resumo de --debug'
}

# RF-195: --paralelo com ciclos: barreira no fim do ciclo, mesmo resultado de N=1.
teste_blc_paralelo_2_fecha_o_ciclo_antes_do_proximo_e_da_o_mesmo_resultado() {
  local base antes
  base=$(_cenario)
  _arvore_remota "$base"
  _receber "$base" --sem-cursor --paralelo 2
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'recebidos=4' "$DBX_SAIDA" 'mesmo resultado de N=1'
  assert_contem 'ciclos=2' "$DBX_SAIDA" 'mesmos ciclos de N=1'
  antes=$(awk '/files\/list_folder$/ { l++ } l == 3 { exit } /files\/download/ { d++ } END { print d + 0 }' "$base/chamadas")
  assert_igual 3 "$antes" 'os tres downloads do ciclo 1 terminam antes da leitura de /r/b (barreira)'
  assert_arquivo_existe "$base/local/b/b1.txt" 'ciclo 2 recebido'
}

# RF-193, DIV-380 C: falha sistemica para a execucao; falha de um arquivo so segue.
teste_blc_falha_sistemica_de_transferencia_para_e_a_de_arquivo_segue() {
  local base n
  base=$(_cenario)
  _arvore_remota "$base"
  printf '403' >"$base/download_erro"
  _receber "$base" --sem-cursor --paralelo 1
  assert_diferente 0 "$DBX_ESTADO" 'permissao em transferencia para a execucao'
  assert_contem 'ciclo_falho=1' "$DBX_SAIDA" 'relatorio de ciclos'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'so o primeiro arquivo do ciclo 1 foi tentado (a/a1 e a/a2 nao)'
  assert_nao_contem 'falha_caminho=a/' "$DBX_SAIDA" 'nenhum outro arquivo do ciclo e tentado'
  assert_contem 'ciclos_nao_tentados=1' "$DBX_SAIDA" 'o diretorio pendente na fila fica sem tentar'
  assert_nao_contem '"path":"/r/b"' "$(cat "$base/corpos")" 'o ciclo 2 nem e lido'
  _cursor_gravado "$base" && fail 'falha sistemica nao grava'
  rm -f "$base/download_erro" "$base/chamadas" "$base/corpos"
  printf '500' >"$base/download_erro"
  _receber "$base" --sem-cursor
  assert_diferente 0 "$DBX_ESTADO" 'falha de arquivo reflete no codigo'
  assert_contem 'ciclos=2' "$DBX_SAIDA" 'a falha de um arquivo segue ate o fim'
  return 0
}

harness_executar "$@"
