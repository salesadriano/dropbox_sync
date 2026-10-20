#!/usr/bin/env bash
# Testes do limite de banda (RF-82; TC-BND-01..14).
#
# O limite e uma linha `limit-rate = <inteiro>` na configuracao que o cliente
# le pela entrada padrao (`curl -K -`). O duplo de `curl` guarda, por chamada,
# a URL, a linha de `limit-rate` (ou `-`) e o `argv` inteiro: e o que prova
# "so nas requisicoes de conteudo" e "o texto do operador nunca chega ao argv".
#
# shellcheck disable=SC2016
# Justificativa: o duplo precisa chegar sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly USO=2

_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/banda.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  printf '%s' '{".tag":"file","name":"a.txt","path_display":"/r/a.txt","size":15}' >"$base/metadado"
  printf '%s' 'conteudo remoto' >"$base/conteudo"
  {
    printf '#!%s\nbase=%q\n' "$BASH" "$base"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
saida='' escrever='' anterior='' url=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
limite=-
[[ $conf =~ (^|$'\n')(limit-rate = [^$'\n']*) ]] && limite=${BASH_REMATCH[2]}
printf '%s\t%s\n' "$url" "$limite" >>"$base/chamadas"
printf '%s\n' "$*" >>"$base/argv"
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *list_folder*) corpo=$(<"$base/listagem") ;;
  *get_metadata*) corpo=$(<"$base/metadado") ;;
  *files/download*) corpo=$(<"$base/conteudo") ;;
  *get_space_usage*) corpo='{"used":0,"allocation":{".tag":"individual","allocated":1000000000}}' ;;
  *upload_session/start*) corpo='{"session_id":"S-1"}' ;;
  *upload_session/append_v2*) corpo='{}' ;;
  *) corpo='{"name":"a.txt","path_display":"/r/a.txt","rev":"1","size":1}' ;;
esac
if [[ $url == *upload_session/append_v2 && -f $base/falhar_parte ]]; then
  rm -f "$base/falhar_parte"
  codigo=500
  corpo='{"error_summary":"internal/.."}'
fi
if [[ -n $saida ]]; then printf '%s' "$corpo" >"$saida" 2>/dev/null || exit 23; fi
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  printf '#!%s\nexit 0\n' "$BASH" >"$base/bin/sleep"
  chmod +x "$base/bin/curl" "$base/bin/sleep"
  printf 'abc' >"$base/local/a.txt"
  printf '%s' "$base"
}

# _rodar <base> <argumentos...> — DBX_T_AMBIENTE (vetor) entra no ambiente.
_rodar() {
  local base=$1
  shift
  DBX_SAIDA='' DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" ${DBX_T_AMBIENTE[@]+"${DBX_T_AMBIENTE[@]}"} \
    bash "$DBX_EXEC" "$@" <"${DBX_T_ENTRADA:-/dev/null}" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_limite_de() { # <base> <trecho_da_url> — limites das chamadas que casam, um por linha
  local linha
  [[ -r $1/chamadas ]] || return 0
  while IFS= read -r linha; do
    [[ ${linha%%$'\t'*} == *"$2" ]] && printf '%s\n' "${linha#*$'\t'}"
  done <"$1/chamadas"
  return 0
}

_zerar() { : >"$1/chamadas"; : >"$1/argv"; }

teste_bnd01_taxas_viram_limit_rate_inteiro_em_bytes() {
  local base par
  base=$(_cenario)
  for par in 2048=2048 10K=10240 1m=1048576 1G=1073741824; do
    _zerar "$base"
    _rodar "$base" upload --forcar --limite-banda "${par%%=*}" "$base/local/a.txt" /r/a.txt
    assert_igual 0 "$DBX_ESTADO" "${par%%=*}; $DBX_ERRO"
    assert_igual "limit-rate = ${par#*=}" "$(_limite_de "$base" /files/upload)" "${par%%=*}"
  done
}

teste_bnd02_valores_invalidos_saem_2_antes_da_rede() {
  local base valor
  base=$(_cenario)
  for valor in 0 -1 +1 1.5M 01 10KB 1KiB 1T '' ' ' ' 1' 1234567890; do
    _rodar "$base" upload --limite-banda "$valor" "$base/local/a.txt" /r/a.txt
    assert_igual "$USO" "$DBX_ESTADO" "valor [$valor]"
    assert_contem '--limite-banda' "$DBX_ERRO" "nomeia a opcao: [$valor]"
    assert_nao_contem 'nao reconhecida' "$DBX_ERRO" "recusa de valor: [$valor]"
  done
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --bwlimit 1.5M
  assert_igual "$USO" "$DBX_ESTADO" 'sync'
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada'
  assert_arquivo_ausente "$base/estado" 'nem trava nem memoria'
}

teste_bnd03_piso_e_o_dobro_da_velocidade_minima_efetiva() {
  local base
  base=$(_cenario)
  _rodar "$base" upload --forcar --limite-banda 2047 "$base/local/a.txt" /r/a.txt
  assert_igual "$USO" "$DBX_ESTADO" '2047 abaixo do piso'
  assert_contem 'DBX_HTTP_VELOCIDADE_MINIMA_BPS' "$DBX_ERRO" 'nomeia a variavel'
  DBX_T_AMBIENTE=(DBX_HTTP_VELOCIDADE_MINIMA_BPS=4096)
  _rodar "$base" upload --forcar --limite-banda 8191 "$base/local/a.txt" /r/a.txt
  assert_igual "$USO" "$DBX_ESTADO" 'com a variavel em 4096, 8191 recusado'
  _rodar "$base" upload --forcar --limite-banda 8K "$base/local/a.txt" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "8K = 8192 aceito; $DBX_ERRO"
  DBX_T_AMBIENTE=()
  assert_arquivo_existe "$base/chamadas" 'so o valido chegou a rede'
}

teste_bnd04_aspa_e_quebra_de_linha_recusadas_e_valor_nunca_no_argv() {
  local base
  base=$(_cenario)
  _rodar "$base" upload --limite-banda '10K"' "$base/local/a.txt" /r/a.txt
  assert_igual "$USO" "$DBX_ESTADO" 'aspa'
  _rodar "$base" upload --limite-banda $'10K\nheader = "X: y"' "$base/local/a.txt" /r/a.txt
  assert_igual "$USO" "$DBX_ESTADO" 'quebra de linha'
  assert_nao_contem $'\n' "${DBX_ERRO%$'\n'}" 'mensagem numa linha'
  _rodar "$base" upload --forcar --limite-banda 12345 "$base/local/a.txt" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "valido; $DBX_ERRO"
  assert_nao_contem '12345' "$(<"$base/argv")" 'o valor nunca vai ao argv'
  assert_nao_contem 'limit-rate' "$(<"$base/argv")" 'nem a opcao'
}

teste_bnd05_so_requisicoes_de_conteudo_levam_o_limite() {
  local base
  base=$(_cenario)
  # upload: token, get_metadata e get_space_usage sem; files/upload com.
  _rodar "$base" upload --limite-banda 4K "$base/local/a.txt" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload; $DBX_ERRO"
  assert_igual 'limit-rate = 4096' "$(_limite_de "$base" /files/upload)" 'upload'
  assert_igual - "$(_limite_de "$base" /oauth2/token)" 'token'
  assert_igual - "$(_limite_de "$base" /get_metadata)" 'get_metadata'
  assert_igual - "$(_limite_de "$base" /get_space_usage)" 'get_space_usage'
  # sessao pela entrada padrao: start, append_v2 e finish.
  _zerar "$base"
  head -c 5000000 /dev/zero >"$base/fluxo"
  DBX_T_ENTRADA="$base/fluxo" _rodar "$base" upload --limite-banda 4K - /r/f.bin
  assert_igual 0 "$DBX_ESTADO" "fluxo; $DBX_ERRO"
  assert_contem 'limit-rate = 4096' "$(_limite_de "$base" /upload_session/start)" 'start'
  assert_contem 'limit-rate = 4096' "$(_limite_de "$base" /upload_session/append_v2)" 'append_v2'
  assert_contem 'limit-rate = 4096' "$(_limite_de "$base" /upload_session/finish)" 'finish'
  # download: files/download com.
  _zerar "$base"
  _rodar "$base" download --limite-banda 4K /r/a.txt "$base/recebido.txt"
  assert_igual 0 "$DBX_ESTADO" "download; $DBX_ERRO"
  assert_igual 'limit-rate = 4096' "$(_limite_de "$base" /files/download)" 'download'
  # sync: list_folder e delete_v2 sem; files/upload com.
  _zerar "$base"
  printf '%s' '{"entries":[{".tag":"file","name":"z","path_display":"/r/z","content_hash":"00","size":1}],"has_more":false}' \
    >"$base/listagem"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --limite-banda 4K
  assert_igual 0 "$DBX_ESTADO" "sync; $DBX_ERRO"
  assert_igual - "$(_limite_de "$base" /files/list_folder)" 'list_folder'
  assert_igual - "$(_limite_de "$base" /files/delete_v2)" 'delete_v2'
  assert_igual 'limit-rate = 4096' "$(_limite_de "$base" /files/upload)" 'envio do sync'
}

teste_bnd06_cada_parte_e_cada_retentativa_levam_o_limite() {
  local base
  base=$(_cenario)
  head -c 9000000 /dev/zero >"$base/fluxo"
  DBX_T_ENTRADA="$base/fluxo" _rodar "$base" upload --limite-banda 4K - /r/f.bin
  assert_igual 0 "$DBX_ESTADO" "fluxo; $DBX_ERRO"
  assert_igual $'limit-rate = 4096\nlimit-rate = 4096' "$(_limite_de "$base" /upload_session/append_v2)" \
    'cada parte'
  _zerar "$base"
  # A parte e idempotente (RF-09): a primeira tentativa falha com 500 e a
  # repeticao sai com o mesmo limite.
  : >"$base/falhar_parte"
  DBX_T_ENTRADA="$base/fluxo" _rodar "$base" upload --limite-banda 4K - /r/f.bin
  assert_igual 0 "$DBX_ESTADO" "retentativa conclui; $DBX_ERRO"
  assert_igual $'limit-rate = 4096\nlimit-rate = 4096\nlimit-rate = 4096' \
    "$(_limite_de "$base" /upload_session/append_v2)" 'a retentativa tambem'
}

teste_bnd07_variavel_sem_a_opcao_e_a_opcao_vence() {
  local base
  base=$(_cenario)
  DBX_T_AMBIENTE=(DBX_LIMITE_BANDA=8K)
  _rodar "$base" upload --forcar "$base/local/a.txt" /r/a.txt
  assert_igual 'limit-rate = 8192' "$(_limite_de "$base" /files/upload)" 'variavel sem a opcao'
  _zerar "$base"
  _rodar "$base" upload --forcar --bwlimit 16K "$base/local/a.txt" /r/a.txt
  assert_igual 'limit-rate = 16384' "$(_limite_de "$base" /files/upload)" 'a opcao vence'
  _zerar "$base"
  DBX_T_AMBIENTE=(DBX_LIMITE_BANDA=lixo)
  _rodar "$base" upload --forcar --limite-banda 16K "$base/local/a.txt" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "variavel invalida com opcao valida segue (DIV-89); $DBX_ERRO"
  assert_igual 'limit-rate = 16384' "$(_limite_de "$base" /files/upload)" 'com a opcao'
  DBX_T_AMBIENTE=()
}

teste_bnd08_variavel_invalida_recusa_so_onde_vale() {
  local base valor comando
  base=$(_cenario)
  for valor in '' 0 abc; do
    DBX_T_AMBIENTE=("DBX_LIMITE_BANDA=$valor")
    _rodar "$base" upload --forcar "$base/local/a.txt" /r/a.txt
    assert_igual "$USO" "$DBX_ESTADO" "upload com [$valor]"
    assert_contem 'variavel de ambiente DBX_LIMITE_BANDA invalida' "$DBX_ERRO" 'mensagem'
    assert_contem 'unset DBX_LIMITE_BANDA' "$DBX_ERRO" 'remedio'
    _rodar "$base" download /r/a.txt "$base/x.txt"
    assert_igual "$USO" "$DBX_ESTADO" "download com [$valor]"
    _rodar "$base" sync --enviar --origem "$base/local" --destino /r
    assert_igual "$USO" "$DBX_ESTADO" "sync com [$valor]"
  done
  assert_arquivo_ausente "$base/chamadas" 'nada chegou a rede'
  DBX_T_AMBIENTE=(DBX_LIMITE_BANDA=abc)
  for comando in 'list /r' 'info /r/a.txt' 'space'; do
    # shellcheck disable=SC2086  # comando e argumentos, separados de proposito
    _rodar "$base" $comando
    assert_igual 0 "$DBX_ESTADO" "$comando ignora a variavel; $DBX_ERRO"
  done
  mkdir -p "$base/vazio"
  _rodar "$base" verificar --enviar --origem "$base/vazio" --destino /r
  assert_igual 0 "$DBX_ESTADO" "verificar ignora a variavel; $DBX_ERRO"
  DBX_T_AMBIENTE=()
}

teste_bnd09_alias_identico_e_repetida_o_ultimo_vence() {
  local base pt
  base=$(_cenario)
  _rodar "$base" upload --forcar --limite-banda 4K "$base/local/a.txt" /r/a.txt
  pt=$DBX_SAIDA
  _zerar "$base"
  _rodar "$base" upload --forcar --bwlimit 4K "$base/local/a.txt" /r/a.txt
  assert_igual "$pt" "$DBX_SAIDA" 'mesma saida'
  assert_igual 'limit-rate = 4096' "$(_limite_de "$base" /files/upload)" 'mesmo limite'
  _zerar "$base"
  _rodar "$base" upload --forcar --limite-banda 4K --bwlimit 8K "$base/local/a.txt" /r/a.txt
  assert_igual 'limit-rate = 8192' "$(_limite_de "$base" /files/upload)" 'o ultimo vence'
}

teste_bnd10_verificar_e_demais_comandos_recusam_a_opcao() {
  local base comando
  base=$(_cenario)
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r --limite-banda 4K
  assert_igual "$USO" "$DBX_ESTADO" 'verificar'
  assert_contem 'nao transfere conteudo' "$DBX_ERRO" 'a recusa do verificar diz por que'
  for comando in list info delete restaurar revisoes lixeira; do
    _rodar "$base" "$comando" --bwlimit 4K /r/a.txt
    assert_igual "$USO" "$DBX_ESTADO" "$comando"
  done
  _rodar "$base" space --limite-banda 4K
  assert_igual "$USO" "$DBX_ESTADO" 'space'
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada'
}

teste_bnd11_bnd12_com_e_sem_limite_mesmos_bytes_e_fluxo_aplica() {
  local base
  base=$(_cenario)
  _rodar "$base" download /r/a.txt "$base/sem.txt"
  assert_igual 0 "$DBX_ESTADO" 'sem limite'
  _rodar "$base" download --limite-banda 1M /r/a.txt "$base/com.txt"
  assert_igual 0 "$DBX_ESTADO" 'com limite'
  assert_igual "$(<"$base/sem.txt")" "$(<"$base/com.txt")" 'mesmos bytes'
  _zerar "$base"
  _rodar "$base" download --limite-banda 1M /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "fluxo; $DBX_ERRO"
  assert_contem 'conteudo remoto' "$DBX_SAIDA" 'o conteudo vai a saida padrao'
  assert_igual 'limit-rate = 1048576' "$(_limite_de "$base" /files/download)" 'fluxo aplica o limite'
}

teste_bnd13_limite_banda_na_saida() {
  local base
  base=$(_cenario)
  _rodar "$base" upload --forcar --limite-banda 4K "$base/local/a.txt" /r/a.txt
  assert_contem 'limite_banda=4096' "$DBX_SAIDA" 'upload'
  _rodar "$base" upload --forcar "$base/local/a.txt" /r/a.txt
  assert_contem $'limite_banda=\n' "$DBX_SAIDA" 'vazio sem limite'
  _rodar "$base" --json --null download --limite-banda 4K /r/a.txt "$base/y.txt"
  assert_contem '|limite_banda=4096|' "$(tr '\0' '|' <"$base/out")" 'download --null'
  _rodar "$base" --json --dry-run sync --enviar --origem "$base/local" --destino /r --limite-banda 4K
  assert_contem 'limite_banda=4096' "$DBX_SAIDA" 'plano do sync'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --limite-banda 4K
  assert_igual 2 "$(grep -c '^limite_banda=4096$' <<<"$DBX_SAIDA")" 'plano e resumo do sync'
}

teste_bnd14_sync_nos_dois_sentidos_e_download_de_pasta_aplicam() {
  local base
  base=$(_cenario)
  printf '%s' '{"entries":[{".tag":"file","name":"b.txt","path_display":"/r/b.txt","content_hash":"00","size":1}],"has_more":false}' \
    >"$base/listagem"
  _rodar "$base" sync --receber --origem /r --destino "$base/dst" --bwlimit 4K
  assert_igual 0 "$DBX_ESTADO" "receber; $DBX_ERRO"
  assert_igual 'limit-rate = 4096' "$(_limite_de "$base" /files/download)" 'sync --receber'
  _zerar "$base"
  printf '%s' '{".tag":"folder","name":"r","path_display":"/r"}' >"$base/metadado"
  _rodar "$base" download --limite-banda 4K /r "$base/pasta" --incluir '*'
  assert_igual 0 "$DBX_ESTADO" "download de pasta; $DBX_ERRO"
  assert_igual 'limit-rate = 4096' "$(_limite_de "$base" /files/download)" 'download de pasta'
  _zerar "$base"
  DBX_T_AMBIENTE=(DBX_LIMITE_BANDA=4K)
  _rodar "$base" download /r "$base/pasta2" --incluir '*'
  DBX_T_AMBIENTE=()
  assert_igual 'limit-rate = 4096' "$(_limite_de "$base" /files/download)" 'variavel chega ao sync interno'
}

harness_executar "$@"
