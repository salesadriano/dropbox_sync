#!/usr/bin/env bash
# Tarefa 3 de F-103 (RF-211(a)-(e), RF-213(a)-(c), RF-214(a), RF-210(g)): no
# sentido remoto -> local (`sync --receber` e `download` de pasta) as pastas do
# ciclo sao criadas, uma a uma e sem seguir ligacao, antes do primeiro `download`
# do ciclo. TC-ARV-10, 11 e 12, mais simulacao e recusa por origem vazia.
#
# Seam: o executavel `dbx` com o cliente HTTP real e um duplo de `curl` que
# lista por diretorio (`$base/ls`) e, a cada `files/download`, grava em
# `$base/snap_<n>` os diretorios que ja existiam em `$base/local`. Dado sintetico.
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
    { cd "$base/local" 2>/dev/null && find . -type d | sort; } >"$base/snap_$n" ;;
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


_pastas_locais() { (cd "$1/local" && find . -type d | sort); }

teste_tc_arv_10_pastas_de_cada_ciclo_existem_antes_do_primeiro_download_do_ciclo() {
  local base
  base=$(_cenario)
  _hash_remoto
  _ls "$base" /r "$(_d /r/a)" "$(_d /r/b)" "$(_d /r/c)"
  _ls "$base" /r/a "$(_f /r/a/a1.txt)"
  _ls "$base" /r/c "$(_f /r/c/c1.txt)" "$(_d /r/c/sub)"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local" --bloco 1 --sem-cursor
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'ciclos=3' "$DBX_SAIDA" 'tres ciclos'
  assert_contem './a' "$(cat "$base/snap_0")" 'ciclo 1: a existe antes do primeiro download'
  assert_nao_contem './b' "$(cat "$base/snap_0")" 'RF-211(a): b e do ciclo 2 e ainda nao existe'
  assert_contem './b' "$(cat "$base/snap_1")" 'ciclo 2: a pasta vazia b existe antes do download'
  assert_nao_contem './c/sub' "$(cat "$base/snap_1")" 'c/sub e do ciclo 3 e ainda nao existe'
  assert_contem './c/sub' "$(_pastas_locais "$base")" 'ao fim, a subpasta vazia do ciclo 3 existe'
}

# _mkdir_falha <base> <alvo> <mensagem> — duble de `mkdir` no PATH do dbx: so o
# `mkdir` do <alvo> falha com a mensagem do sistema; o resto vai ao real.
_mkdir_falha() {
  local base=$1
  {
    printf '#!/usr/bin/env bash\n'
    printf 'alvo=%q\nmsg=%q\nbase=%q\n' "$2" "$3" "$base"
    cat <<'FIM'
for a in "$@"; do
  if [[ $a == "$alvo" ]]; then printf 'mkdir\n' >>"$base/mkdir_falho"; printf 'mkdir: cannot create directory: %s\n' "$msg" >&2; exit 1; fi
done
exec /bin/mkdir "$@"
FIM
  } >"$base/bin/mkdir"
  chmod +x "$base/bin/mkdir"
}

teste_tc_arv_19_enospc_ou_erofs_no_mkdir_do_ciclo_2_zero_downloads_e_ciclo_1_permanece() {
  local base msg
  for msg in 'No space left on device' 'Read-only file system'; do
    base=$(_cenario)
    _hash_remoto
    _ls "$base" /r "$(_d /r/a)" "$(_d /r/b)"
    _ls "$base" /r/a "$(_f /r/a/a1.txt)"
    _ls "$base" /r/b "$(_f /r/b/b1.txt)"
    _mkdir_falha "$base" "$base/local/b" "$msg"
    _rodar "$base" sync --receber --origem /r --destino "$base/local" --bloco 1 --sem-cursor
    assert_igual 3 "$DBX_ESTADO" "RF-213(b): falha sistemica (configuracao) para: $msg"
    assert_contem 'sem espaco ou destino somente leitura para criar pastas' "$DBX_ERRO" "motivo para: $msg"
    assert_igual sim "$([[ -f $base/mkdir_falho ]] && printf sim)" 'o mkdir do ciclo 2 foi tentado e falhou'
    assert_igual 1 "$(_harness_contar 'files/download' "$base/chamadas")" 'RF-193(b): so o download do ciclo 1; zero do ciclo 2'
    assert_igual sim "$([[ -f $base/local/a/a1.txt ]] && printf sim)" 'efeitos do ciclo 1 permanecem'
    assert_igual '' "$([[ -e $base/local/b ]] && printf existe)" 'a pasta do ciclo 2 nao existe'
  done
}

teste_tc_arv_04_download_de_arquivo_unico_nao_cria_pasta_nem_registra_mkdir() {
  local base
  base=$(_cenario)
  _hash_remoto
  printf '%s' '{".tag":"file","name":"x.txt","rev":"015f00000000a1b2","size":15}' >"$base/meta"
  _rodar "$base" --debug download /r/x.txt "$base/local/x.txt"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'files/download' "$base/chamadas")" 'o arquivo foi baixado'
  assert_igual 0 "$(_harness_contar 'create_folder' "$base/chamadas")" 'RF-209(d): nenhuma criacao de pasta remota'
  assert_nao_contem 'operacao=mkdir' "$DBX_ERRO" 'RF-209(d): nenhum mkdir do ciclo de pastas'
}

teste_tc_arv_11_download_de_pasta_com_subpasta_vazia_cria_a_subpasta() {
  local base
  base=$(_cenario)
  _hash_remoto
  printf '%s' '{".tag":"folder","name":"r","id":"id:Dr","path_display":"/r","path_lower":"/r"}' >"$base/meta"
  _ls "$base" /r "$(_f /r/x.txt)" "$(_d /r/vazia)"
  _rodar "$base" download /r "$base/local" --excluir "zzz/"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual sim "$([[ -d $base/local/r/vazia ]] && printf sim)" 'RF-211: subpasta vazia criada'
  assert_igual sim "$([[ -f $base/local/r/x.txt ]] && printf sim)" 'o arquivo foi baixado'
}

teste_tc_arv_12_ligacao_simbolica_no_lugar_da_pasta_falha_sem_seguir_e_o_resto_segue() {
  local base
  base=$(_cenario)
  _hash_remoto
  mkdir -p "$base/local" "$base/alvo_link"
  ln -s "$base/alvo_link" "$base/local/a"
  _ls "$base" /r "$(_d /r/a)" "$(_d /r/b)"
  _ls "$base" /r/a "$(_f /r/a/a1.txt)" "$(_d /r/a/sub)"
  _ls "$base" /r/b "$(_f /r/b/b1.txt)"
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_diferente 0 "$DBX_ESTADO" 'falha de item no codigo de saida'
  assert_contem "arquivo no lugar da pasta: $base/local/a" "$DBX_ERRO" 'RF-214(a): motivo da pasta'
  assert_contem 'falha a/a1.txt: ' "$DBX_ERRO" 'arquivo sob a ligacao falha'
  assert_contem "pasta de destino nao criada: $base/local/a" "$DBX_ERRO" 'RF-213(a): motivo do arquivo'
  assert_igual '' "$(ls -A "$base/alvo_link")" 'RF-211(d): nada criado atraves da ligacao'
  assert_igual sim "$([[ -L $base/local/a ]] && printf sim)" 'a ligacao segue no lugar'
  assert_igual sim "$([[ -f $base/local/b/b1.txt ]] && printf sim)" 'o resto do ciclo segue'
}

teste_arquivo_regular_no_lugar_da_pasta_falha_e_nao_e_apagado() {
  local base
  base=$(_cenario)
  _hash_remoto
  mkdir -p "$base/local"
  printf 'meu' >"$base/local/a"
  _ls "$base" /r "$(_d /r/a)" "$(_d /r/b)"
  _ls "$base" /r/a "$(_f /r/a/a1.txt)"
  _ls "$base" /r/b "$(_f /r/b/b1.txt)"
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_diferente 0 "$DBX_ESTADO" 'falha de item no codigo de saida'
  assert_contem "arquivo no lugar da pasta: $base/local/a" "$DBX_ERRO" 'motivo da pasta'
  assert_contem "pasta de destino nao criada: $base/local/a" "$DBX_ERRO" 'motivo do arquivo'
  assert_igual meu "$(cat "$base/local/a")" 'RF-214(a): nada e apagado'
  assert_igual sim "$([[ -f $base/local/b/b1.txt ]] && printf sim)" 'o resto segue'
}

teste_simulacao_nao_cria_pasta_local() {
  local base
  base=$(_cenario)
  _hash_remoto
  _ls "$base" /r "$(_f /r/x.txt)" "$(_d /r/vazia)"
  _rodar "$base" --dry-run sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual '' "$(ls -A "$base/local")" 'RF-211(e): simulacao nao cria pasta'
}

teste_origem_remota_so_com_pastas_vazias_e_recusada_sem_criar_pasta_local() {
  local base
  base=$(_cenario)
  _hash_remoto
  printf 'velho' >"$base/local/velho.txt"
  _ls "$base" /r "$(_d /r/x)" "$(_d /r/y)"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_diferente 0 "$DBX_ESTADO" 'RF-210(g): origem vazia recusada'
  assert_igual sim "$([[ ! -e $base/local/x && ! -e $base/local/y ]] && printf sim)" 'RF-210(g): nenhuma pasta criada antes da recusa'
  assert_igual velho "$(cat "$base/local/velho.txt")" 'nada apagado'
}

teste_pasta_vazia_ocupada_conta_ela_mesma_como_falha_de_item() {
  local base
  base=$(_cenario)
  _hash_remoto
  printf 'meu' >"$base/local/a"
  _ls "$base" /r "$(_d /r/a)" "$(_d /r/b)"
  _ls "$base" /r/b "$(_f /r/b/b1.txt)"
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_diferente 0 "$DBX_ESTADO" 'RF-213(a): a pasta vazia que falha e falha de item'
  assert_contem 'falha a: ' "$DBX_ERRO" 'a pasta e citada na saida de falhas'
  assert_igual meu "$(cat "$base/local/a")" 'nada apagado'
  assert_igual sim "$([[ -f $base/local/b/b1.txt ]] && printf sim)" 'o resto segue'
}

teste_download_de_pasta_sem_filtro_cria_subpasta_vazia() {
  local base
  base=$(_cenario)
  _hash_remoto
  _ls "$base" /r/p "$(_f /r/p/x.txt)" "$(_d /r/p/vazia)"
  : >"$base/download_erro_pasta"
  _rodar "$base" download /r/p "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual sim "$([[ -d $base/local/p/vazia ]] && printf sim)" 'subpasta vazia criada pelo fallback sem filtro'
  assert_igual sim "$([[ -f $base/local/p/x.txt ]] && printf sim)" 'o arquivo foi baixado'
}

# RF-214 (DIV-401), recebimento: arquivo ou ligacao local no lugar da pasta remota.
_remoto_a_b() { # <base> — /r tem as pastas a (com a1.txt) e b (com b1.txt)
  _hash_remoto
  _ls "$1" /r "$(_d /r/a)" "$(_d /r/b)"
  _ls "$1" /r/a "$(_f /r/a/a1.txt)"
  _ls "$1" /r/b "$(_f /r/b/b1.txt)"
}

teste_tc_arv_17c_espelhar_remove_o_arquivo_regular_e_preenche_a_pasta_na_mesma_execucao() {
  local base
  base=$(_cenario)
  _remoto_a_b "$base"
  printf 'meu' >"$base/local/a"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual sim "$([[ -d $base/local/a && ! -L $base/local/a ]] && printf sim)" 'a virou pasta'
  assert_igual sim "$([[ -f $base/local/a/a1.txt ]] && printf sim)" 'preenchida na mesma execucao'
  assert_contem 'apagados=1' "$DBX_SAIDA" 'RF-214(e): conta uma vez'
  assert_contem 'arquivo no lugar da pasta' "$DBX_ERRO" 'RF-214(e): motivo no relatorio'
}

teste_tc_arv_17c_ligacao_local_com_espelhar_segue_a_leitura_parcial_e_nada_e_removido() {
  # A ligacao simbolica no destino local torna a travessia local parcial
  # (lib/walk: "ligacao simbolica nao percorrida"), e a leitura parcial desliga
  # tambem a exclusao antecipada (RF-214(c)(4)): a ligacao fica, o alvo fica.
  local base
  base=$(_cenario)
  _remoto_a_b "$base"
  mkdir -p "$base/alvo_link"
  printf 'alvo' >"$base/alvo_link/intocado.txt"
  ln -s "$base/alvo_link" "$base/local/a"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_diferente 0 "$DBX_ESTADO" 'RF-214(d): falha de item'
  assert_contem 'arquivo no lugar da pasta' "$DBX_ERRO" 'motivo'
  assert_igual sim "$([[ -L $base/local/a ]] && printf sim)" 'a ligacao segue no lugar'
  assert_igual alvo "$(cat "$base/alvo_link/intocado.txt")" 'o alvo da ligacao nao foi tocado'
  assert_igual intocado.txt "$(ls -A "$base/alvo_link")" 'nada foi criado atraves da ligacao'
}

teste_tc_arv_17c_sem_espelhar_nada_e_removido() {
  local base
  base=$(_cenario)
  _remoto_a_b "$base"
  mkdir -p "$base/alvo_link"
  ln -s "$base/alvo_link" "$base/local/a"
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_diferente 0 "$DBX_ESTADO" 'RF-214(a): falha de item'
  assert_igual sim "$([[ -L $base/local/a ]] && printf sim)" 'a ligacao segue no lugar'
}

teste_tc_arv_17c_destino_filtrado_nao_e_removido() {
  local base
  base=$(_cenario)
  _remoto_a_b "$base"
  printf 'meu' >"$base/local/a"
  _rodar "$base" sync --receber --espelhar --confirmar --incluir 'a/' --origem /r --destino "$base/local"
  assert_diferente 0 "$DBX_ESTADO" 'RF-214(c)(3): falha de item'
  assert_igual meu "$(cat "$base/local/a")" 'o filtro protege o destino'
}

teste_tc_arv_17c_diretorio_local_nunca_e_removido_por_este_caminho() {
  local base
  base=$(_cenario)
  _remoto_a_b "$base"
  mkdir -p "$base/local/a"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual sim "$([[ -f $base/local/a/a1.txt ]] && printf sim)" 'a pasta existente e preenchida'
  assert_nao_contem 'apagado: a (arquivo no lugar da pasta)' "$DBX_ERRO" 'nada foi removido por este caminho'
}

# RF-216 (Tarefa 5), recebimento: exclusao de pasta orfa LOCAL, so com --espelhar,
# por `rmdir` nao recursivo, filhos antes do pai. A origem remota /r tem so k.txt.
_remoto_k() { # <base>
  _hash_remoto
  _ls "$1" /r "$(_f /r/k.txt)"
}

teste_rf216_pasta_orfa_vazia_e_apagada_e_a_raiz_fica() {
  local base
  base=$(_cenario)
  _remoto_k "$base"
  mkdir -p "$base/local/o"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual nao "$([[ -e $base/local/o ]] && printf sim || printf nao)" 'RF-216(a)(d): rmdir da pasta orfa'
  assert_contem 'pasta apagada: o' "$DBX_ERRO" 'consta do relatorio'
  assert_igual sim "$([[ -d $base/local ]] && printf sim)" 'RF-216(j): a raiz do destino fica'
}

teste_rf216_sem_espelhar_a_pasta_orfa_fica() {
  local base
  base=$(_cenario)
  _remoto_k "$base"
  mkdir -p "$base/local/o"
  _rodar "$base" sync --receber --confirmar --origem /r --destino "$base/local"
  assert_igual sim "$([[ -d $base/local/o ]] && printf sim)" 'RF-216(a): sem --espelhar nada'
}

teste_rf216_pasta_orfa_com_arquivo_orfao_arquivo_sai_e_depois_a_pasta() {
  local base
  base=$(_cenario)
  _remoto_k "$base"
  mkdir -p "$base/local/o"
  printf 'x' >"$base/local/o/x.txt"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual nao "$([[ -e $base/local/o ]] && printf sim || printf nao)" 'RF-216(b): arquivo e pasta saem'
  assert_contem 'pasta apagada: o' "$DBX_ERRO" 'a pasta consta'
  assert_contem 'apagados=1' "$DBX_SAIDA" 'o arquivo saiu pela exclusao comum'
}

teste_rf216_pastas_aninhadas_filho_antes_do_pai() {
  local base
  base=$(_cenario)
  _remoto_k "$base"
  mkdir -p "$base/local/a/b"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual nao "$([[ -e $base/local/a ]] && printf sim || printf nao)" 'a e a/b saem'
  local pre_b=${DBX_ERRO%%pasta apagada: a/b*} pre_a=${DBX_ERRO%%pasta apagada: a$'\n'*}
  assert_igual sim "$([[ $DBX_ERRO == *'pasta apagada: a/b'* && ${#pre_b} -lt ${#pre_a} ]] && printf sim)" 'RF-216(c): a/b antes de a'
}

teste_rf216_pasta_orfa_com_item_filtrado_fica_mantida() {
  local base
  base=$(_cenario)
  _remoto_k "$base"
  mkdir -p "$base/local/o"
  printf 'log' >"$base/local/o/x.log"
  _rodar "$base" sync --receber --espelhar --confirmar --excluir '*.log' --origem /r --destino "$base/local"
  assert_igual log "$(cat "$base/local/o/x.log" 2>/dev/null)" 'RF-216(d)(f): ENOTEMPTY, nada removido'
  assert_contem 'pasta mantida: o' "$DBX_ERRO" 'mantida com motivo'
  assert_nao_contem 'pasta apagada: o' "$DBX_ERRO" 'nao consta como apagada'
}

teste_rf216_subpasta_com_filtrado_mantem_a_cadeia_e_apaga_a_irma_vazia() {
  local base
  base=$(_cenario)
  _remoto_k "$base"
  mkdir -p "$base/local/o/p" "$base/local/q"
  printf 'log' >"$base/local/o/p/x.log"
  _rodar "$base" sync --receber --espelhar --confirmar --excluir '*.log' --origem /r --destino "$base/local"
  assert_igual sim "$([[ -f $base/local/o/p/x.log ]] && printf sim)" 'o filtrado fica'
  assert_igual nao "$([[ -e $base/local/q ]] && printf sim || printf nao)" 'a irma vazia sai'
  assert_contem 'pasta mantida: o/p' "$DBX_ERRO" 'p mantida'
  assert_contem 'pasta mantida: o ' "$DBX_ERRO" 'o mantida (ENOTEMPTY)'
}

teste_rf216_ligacao_simbolica_no_lugar_de_pasta_orfa_nada_e_apagado() {
  local base
  base=$(_cenario)
  _remoto_k "$base"
  mkdir -p "$base/alvo_link" "$base/local/vazia"
  printf 'alvo' >"$base/alvo_link/intocado.txt"
  ln -s "$base/alvo_link" "$base/local/o"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual sim "$([[ -L $base/local/o ]] && printf sim)" 'RF-216(d): a ligacao fica'
  assert_igual alvo "$(cat "$base/alvo_link/intocado.txt")" 'o alvo fica'
  assert_igual sim "$([[ -d $base/local/vazia ]] && printf sim)" 'RF-216(g): leitura parcial desliga a exclusao de pasta'
}

teste_rf216_origem_vazia_recusa_antes_de_apagar_pasta() {
  local base
  base=$(_cenario)
  _ls "$base" /r
  mkdir -p "$base/local/o"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 14 "$DBX_ESTADO" 'RF-216(g): recusa por origem vazia'
  assert_igual sim "$([[ -d $base/local/o ]] && printf sim)" 'nenhuma pasta apagada'
}

teste_rf216_simulacao_nao_apaga_pasta() {
  local base
  base=$(_cenario)
  _remoto_k "$base"
  mkdir -p "$base/local/o"
  _rodar "$base" --dry-run sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual sim "$([[ -d $base/local/o ]] && printf sim)" 'RF-217(b): zero rmdir em simulacao'
}

# Regressao de RF-216: pasta local que o remoto cobre so com a caixa diferente
# (Dropbox ignora a caixa) nao e orfa, nao e apagada e nao provoca recusa.
teste_rf216_pasta_local_com_caixa_diferente_do_remoto_nao_e_orfa() {
  local base
  base=$(_cenario)
  _hash_remoto
  _ls "$base" /r "$(_f /r/Docs/k.txt)"
  mkdir -p "$base/local/docs"
  printf 'antigo' >"$base/local/docs/k.txt"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual 'conteudo remoto' "$(cat "$base/local/docs/k.txt")" 'o arquivo da pasta de outra caixa e atualizado'
  assert_nao_contem 'pasta apagada' "$DBX_ERRO" 'a pasta com a caixa diferente nao e orfa'
}

teste_rf216_pasta_local_com_caixa_diferente_e_vazia_nao_e_apagada() {
  local base
  base=$(_cenario)
  _remoto_k "$base"
  _ls "$base" /r "$(_f /r/k.txt)" "$(_d /r/Docs)"
  _ls "$base" /r/Docs
  mkdir -p "$base/local/docs"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_igual sim "$([[ -d $base/local/docs ]] && printf sim)" 'a pasta existe nos dois lados: fica'
}

teste_rf216_a_decisao_nao_le_memoria_retrato_nem_cursor() {
  local fonte
  fonte=$(sed -n '/^_dbx_cmd_sync_pastas_orfas_/,/^}/p' "$DBX_HARNESS_RAIZ/commands/sync.sh")
  assert_diferente '' "$fonte" 'as funcoes de pasta orfa existem'
  assert_nao_contem 'dbx_state' "$fonte" 'RF-216(i): sem memoria'
  assert_nao_contem 'retrato' "$fonte" 'RF-216(i): sem retrato'
  assert_nao_contem 'cursor' "$fonte" 'RF-216(i): sem cursor'
}


teste_tc_arv_31_recebimento_conta_so_a_pasta_criada_e_pasta_nao_e_arquivo() {
  local base
  base=$(_cenario)
  _remoto_a_b "$base"
  mkdir -p "$base/local/a"
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'pastas_criadas=1' "$DBX_SAIDA" 'RF-218(c): a ja existia, so b foi criada'
  assert_contem 'pastas_apagadas=0' "$DBX_SAIDA" 'RF-218(a)'
  assert_contem 'pastas_mantidas=0' "$DBX_SAIDA" 'RF-218(a)'
  assert_contem 'pastas_falhas=0' "$DBX_SAIDA" 'RF-218(a)'
  assert_contem 'recebidos=2' "$DBX_SAIDA" 'RF-218(c): so os arquivos'
}

teste_tc_arv_30_simulacao_de_recebimento_anuncia_as_pastas_sem_criar_nada() {
  local base
  base=$(_cenario)
  _remoto_a_b "$base"
  _rodar "$base" --dry-run sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'criaria=pasta a' "$DBX_SAIDA" 'RF-217(a)'
  assert_contem 'criaria=pasta b' "$DBX_SAIDA" 'RF-217(a)'
  assert_igual nao "$([[ -e $base/local/a || -e $base/local/b ]] && printf sim || printf nao)" 'RF-217(b): zero mkdir'
  assert_contem 'pastas_criadas=2' "$DBX_SAIDA" 'RF-218(a)'
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'marca de simulacao'
}

teste_tc_arv_30_simulacao_de_recebimento_anuncia_a_pasta_orfa_sem_rmdir() {
  local base
  base=$(_cenario)
  _remoto_k "$base"
  mkdir -p "$base/local/o"
  _rodar "$base" --dry-run sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'apagaria=pasta o' "$DBX_SAIDA" 'RF-217(a)(c)'
  assert_igual sim "$([[ -d $base/local/o ]] && printf sim)" 'RF-217(b): zero rmdir'
  assert_contem 'pastas_apagadas=1' "$DBX_SAIDA" 'RF-218(a)'
}

teste_rf214e_recebimento_exclusao_antecipada_sai_no_relatorio_com_motivo() {
  local base
  base=$(_cenario)
  _remoto_a_b "$base"
  printf 'meu' >"$base/local/a"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_contem 'apagado=a (arquivo no lugar da pasta)' "$DBX_SAIDA" 'RF-214(e): linha do relatorio com o motivo'
}

teste_rf214e_recebimento_simulacao_anuncia_apagaria_e_criaria_pasta() {
  local base
  base=$(_cenario)
  _remoto_a_b "$base"
  printf 'meu' >"$base/local/a"
  _rodar "$base" --dry-run sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_contem 'apagaria=a (arquivo no lugar da pasta)' "$DBX_SAIDA" 'RF-214(e)'
  assert_contem 'criaria=pasta a' "$DBX_SAIDA" 'RF-214(e)'
  assert_igual sim "$([[ -f $base/local/a ]] && printf sim)" 'RF-217(b): o arquivo local fica'
}

teste_rf217c_recebimento_simulacao_anuncia_a_orfa_que_fica_vazia_pelo_arquivo_planejado() {
  local base
  base=$(_cenario)
  _remoto_k "$base"
  mkdir -p "$base/local/o"
  printf 'x' >"$base/local/o/x.txt"
  _rodar "$base" --dry-run sync --receber --espelhar --confirmar --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_contem 'apagar=o/x.txt' "$DBX_SAIDA" 'o arquivo orfao esta no plano'
  assert_contem 'apagaria=pasta o' "$DBX_SAIDA" 'RF-217(c): ficaria vazia'
  assert_igual x "$(cat "$base/local/o/x.txt" 2>/dev/null)" 'RF-217(b): nada removido'
}

teste_rf217c_recebimento_simulacao_nao_anuncia_a_orfa_com_item_filtrado() {
  local base
  base=$(_cenario)
  _remoto_k "$base"
  mkdir -p "$base/local/o"
  printf 'log' >"$base/local/o/x.log"
  _rodar "$base" --dry-run sync --receber --espelhar --confirmar --excluir '*.log' --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $DBX_ERRO"
  assert_nao_contem 'apagaria=pasta o' "$DBX_SAIDA" 'RF-217(c): o filtrado a mantem'
  assert_contem 'pastas_apagadas=0' "$DBX_SAIDA" 'RF-218(a): conta o anunciado'
}

harness_executar "$@"
