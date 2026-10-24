#!/usr/bin/env bash
# Testes do paralelismo controlado do `sync` (F-09; RF-133 a RF-135, RF-139;
# TC-PAR-01..): selecao e validacao, equivalencia entre N=1 e N>1, falha por item,
# ordem da saida, simulacao, listagem sempre sequencial, sinais, banda dividida,
# resumo de `--debug` e auditoria estatica de estado.
#
# O duplo de `curl` guarda, por transferencia, uma marca em `$base/vivos` enquanto
# ela dura e anota o pico de marcas simultaneas em `$base/pico`: e o que prova que
# o paralelismo e efetivo (N>1) ou ausente (N=1), sem depender de tempo.
#
# shellcheck disable=SC2016
# Justificativa: o duplo precisa chegar sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly USO=2

# _cenario — credencial, duplo de rede e diretorios. Controles do duplo, por
# arquivo em $base: `remoto/<caminho>` (conteudo do download), `atraso/<nome>`
# (segundos), `falha/<nome>` (409 no download), `r429/<nome>` (um 429 antes).
_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/paralelo.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp" "$base/remoto" \
    "$base/atraso" "$base/falha" "$base/r429" "$base/vivos" "$base/enviado"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  {
    printf '#!%s\nbase=%q\n' "$BASH" "$base"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
saida='' escrever='' anterior='' url='' corpo_arquivo='' falha_http='nao'
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac
  case $arg in http*) url=$arg ;; --fail) falha_http=sim ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
codigo=200
caminho=''
re='path\\":\\"([^\\"]*)\\"'
[[ $conf =~ $re ]] && caminho=${BASH_REMATCH[1]}
nome=${caminho##*/}
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *get_space_usage*) corpo='{"used":0,"allocation":{".tag":"individual","allocated":1000000000}}' ;;
  *list_folder*)
    corpo=$(<"$base/listagem")
    [[ -n $(ls "$base/vivos") ]] && printf 'x\n' >>"$base/listagem_concorrente"
    ;;
  *files/download)
    corpo=$(<"$base/remoto$caminho")
    marca="$base/vivos/$$"
    : >"$marca"
    n=$(find "$base/vivos" -type f | wc -l)
    printf '%s\n' "$n" >>"$base/picos"
    [[ -f $base/atraso/$nome ]] && sleep "$(<"$base/atraso/$nome")"
    rm -f "$marca"
    if [[ -f $base/r429/$nome ]]; then
      rm -f "$base/r429/$nome"
      codigo=429; corpo='{"error_summary":"too_many_requests/.."}'
    elif [[ -f $base/falha/$nome ]]; then
      codigo=409; corpo='{"error_summary":"path/not_found/.."}'
    fi
    ;;
  *upload_session/start*) corpo='{"session_id":"S-1"}' ;;
  *upload_session/append_v2*) corpo='{}' ;;
  *files/upload)
    marca="$base/vivos/$$"
    : >"$marca"
    printf '%s\n' "$(find "$base/vivos" -type f | wc -l)" >>"$base/picos"
    destino=$caminho
    [[ -f $base/atraso/$nome ]] && sleep "$(<"$base/atraso/$nome")"
    rm -f "$marca"
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
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

# _remoto <base> <n> — n arquivos remotos em /r, em duas pastas, com conteudo proprio.
_remoto() {
  local base=$1 n=$2 i caminho lista=''
  for ((i = 1; i <= n; i++)); do
    caminho="/r/d$((i % 2))/a$i.txt"
    mkdir -p "$base/remoto${caminho%/*}"
    printf 'conteudo %s' "$i" >"$base/remoto$caminho"
    lista+="${lista:+,}{\".tag\":\"file\",\"path_display\":\"$caminho\",\"size\":10}"
  done
  printf '{"entries":[%s],"has_more":false}' "$lista" >"$base/listagem"
}

_local() { # <base> <n> — n arquivos locais
  local base=$1 n=$2 i
  for ((i = 1; i <= n; i++)); do
    mkdir -p "$base/local/d$((i % 2))"
    printf 'conteudo %s' "$i" >"$base/local/d$((i % 2))/a$i.txt"
    touch -d '2020-01-01 00:00:00' "$base/local/d$((i % 2))/a$i.txt"
  done
}

# _rodar <base> <argumentos...> — DBX_T_AMBIENTE (vetor) entra no ambiente.
_rodar() {
  local base=$1
  shift
  DBX_SAIDA='' DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" ${DBX_T_AMBIENTE[@]+"${DBX_T_AMBIENTE[@]}"} \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_conta_prefixo() { # <prefixo> <arquivo> — linhas que comecam pelo prefixo
  local n=0 linha
  [[ -r $2 ]] || { printf 0; return 0; }
  while IFS= read -r linha || [[ -n $linha ]]; do
    [[ $linha == "$1"* ]] && n=$((n + 1))
  done <"$2"
  printf '%s' "$n"
}

_norm() { # <base> <texto> — troca o diretorio do cenario por BASE
  printf "%s" "${2//$1/BASE}"
}

_pico() { # <base> — maior numero de transferencias simultaneas vistas
  local maior=0 n
  [[ -r $1/picos ]] || { printf 0; return 0; }
  while IFS= read -r n; do ((n > maior)) && maior=$n; done <"$1/picos"
  printf '%s' "$maior"
}

_arvore() { # <diretorio> — caminhos e conteudo, ordenados
  (cd "$1" && find . -type f -exec sh -c 'for f; do printf "%s=" "$f"; cat "$f"; printf "\n"; done' _ {} + | sort)
}

_estado_de() { # <base> — nomes e conteudo da memoria (sem trava), ordenados
  [[ -d $1/estado ]] || return 0
  (cd "$1/estado" && find . -type f ! -name 'trava-*' -exec sh -c 'for f; do printf "%s=" "$f"; tr "\\0" "\\n" <"$f" | sort; printf "\\n"; done' _ {} + | sort)
}

# ---------------------------------------------------------------------------
# RF-133: selecao, validacao e precedencia
# ---------------------------------------------------------------------------

teste_par01_valores_invalidos_saem_2_antes_da_rede_e_do_estado() {
  local base valor
  base=$(_cenario)
  for valor in 0 9 -1 +2 01 abc '' ' ' ' 2' '2 ' 1.5 10 $'2\n'; do
    _rodar "$base" sync --receber --origem /r --destino "$base/local" --paralelo "$valor"
    assert_igual "$USO" "$DBX_ESTADO" "valor [$valor]"
    assert_contem '--paralelo' "$DBX_ERRO" "nomeia a opcao: [$valor]"
  done
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --parallel
  assert_igual "$USO" "$DBX_ESTADO" 'sem valor'
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada de rede'
  assert_arquivo_ausente "$base/estado" 'nem trava nem memoria'
}

teste_par02_variavel_invalida_nomeia_a_variavel_e_a_opcao_vence() {
  local base valor
  base=$(_cenario)
  for valor in 0 9 -1 abc '' 01 ' 2'; do
    DBX_T_AMBIENTE=("DBX_PARALELO=$valor")
    _rodar "$base" sync --receber --origem /r --destino "$base/local"
    assert_igual "$USO" "$DBX_ESTADO" "variavel [$valor]"
    assert_contem 'DBX_PARALELO' "$DBX_ERRO" "nomeia a variavel: [$valor]"
  done
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada de rede'
  DBX_T_AMBIENTE=(DBX_PARALELO=99)
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --paralelo 2
  assert_igual 0 "$DBX_ESTADO" "a opcao vence a variavel invalida; $DBX_ERRO"
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --paralelo 9 --paralelo 3
  assert_igual 0 "$DBX_ESTADO" "opcao repetida: a ultima vence; $DBX_ERRO"
  DBX_T_AMBIENTE=(DBX_PARALELO=4)
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "variavel valida; $DBX_ERRO"
  DBX_T_AMBIENTE=()
  for valor in 1 8; do
    _rodar "$base" sync --receber --origem /r --destino "$base/local" --paralelo "$valor"
    assert_igual 0 "$DBX_ESTADO" "limite [$valor]; $DBX_ERRO"
  done
}

teste_par03_fora_do_sync_a_opcao_e_recusada_e_a_variavel_ignorada() {
  local base
  base=$(_cenario)
  _rodar "$base" list --paralelo 2 /
  assert_igual "$USO" "$DBX_ESTADO" 'list recusa a opcao'
  _rodar "$base" info --paralelo 2 /x
  assert_igual "$USO" "$DBX_ESTADO" 'info recusa a opcao'
  DBX_T_AMBIENTE=(DBX_PARALELO=99)
  printf 'abc' >"$base/arq"
  _rodar "$base" upload --forcar "$base/arq" /r/arq
  assert_igual 0 "$DBX_ESTADO" "upload ignora a variavel; $DBX_ERRO"
  _rodar "$base" upload --forcar "$base/local" /r/pasta
  assert_igual 0 "$DBX_ESTADO" "upload de pasta ignora a variavel; $DBX_ERRO"
  _rodar "$base" download /r "$base/local"
  assert_diferente "$USO" "$DBX_ESTADO" "download de pasta ignora a variavel invalida; $DBX_ERRO"
  DBX_T_AMBIENTE=()
}

# ---------------------------------------------------------------------------
# RF-134: equivalencia entre N=1 e N>1
# ---------------------------------------------------------------------------

# _fotografia <base> <arvore> — o que uma execucao deixou: stdout, stderr, codigo,
# arquivos finais e memoria. A mesma raiz serve a N=1 e a N>1 (a memoria e a trava
# sao por raiz); entre as duas, o ambiente e zerado.
_fotografia() {
  local base=$1 arvore=$2
  printf '== estado %s\n== stdout\n%s\n== stderr\n%s\n== arvore\n%s\n== memoria\n%s\n' \
    "$DBX_ESTADO" "$DBX_SAIDA" "$DBX_ERRO" "$(_arvore "$arvore")" "$(_estado_de "$base" )"
}

_zerar() { # <base> — volta ao inicio: sem destino local, sem memoria, sem rastros
  rm -rf "$1/estado" "$1/enviado" "$1/picos" "$1/chamadas" "$1/local2"
  [[ $2 == 'receber' ]] && rm -rf "$1/local"
  mkdir -p "$1/enviado"
}

teste_par04_receber_com_n4_e_igual_a_n1_e_e_efetivo() {
  local base foto_um foto_n pico_um n
  base=$(_cenario)
  _remoto "$base" 7
  printf '0.3' >"$base/atraso/a1.txt"
  printf '0.3' >"$base/atraso/a2.txt"
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "N=1; $DBX_ERRO"
  foto_um=$(_fotografia "$base" "$base/local")
  pico_um=$(_pico "$base")
  for n in 2 4 8; do
    _zerar "$base" receber
    _rodar "$base" sync --receber --origem /r --destino "$base/local" --paralelo "$n"
    assert_igual 0 "$DBX_ESTADO" "N=$n; $DBX_ERRO"
    foto_n=$(_fotografia "$base" "$base/local")
    assert_igual "$foto_um" "$foto_n" "N=$n: saida, arquivos, cache e codigo iguais aos de N=1"
    [[ $(_pico "$base") -gt 1 ]] || _harness_falhar "N=$n sem simultaneidade: pico $(_pico "$base")"
    [[ $(_pico "$base") -le $n ]] || _harness_falhar "pico acima de $n: $(_pico "$base")"
  done
  assert_igual 1 "$pico_um" 'N=1 nunca tem duas transferencias juntas'
}

teste_par05_enviar_com_n4_e_igual_a_n1_e_e_efetivo() {
  local base foto_um foto_n n
  base=$(_cenario)
  _local "$base" 7
  # F-09 mede o envio UNITARIO em paralelo: acima do limiar do lote (1 MiB,
  # RF-137, DIV-256) os arquivos seguem o caminho unitario. O lote tem o lou07.
  find "$base/local" -type f -exec sh -c 'for f; do head -c 1048577 /dev/zero >>"$f"; touch -d "2020-01-01 00:00:00" "$f"; done' _ {} +
  printf '0.3' >"$base/atraso/a1.txt"
  printf '0.3' >"$base/atraso/a2.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "N=1; $DBX_ERRO"
  foto_um="$(_fotografia "$base" "$base/local")
$(_arvore "$base/enviado")"
  assert_igual 7 "$(find "$base/enviado" -type f | wc -l)" 'sete arquivos no destino'
  assert_igual 1 "$(_pico "$base")" 'N=1 sequencial'
  assert_contem 'a1.txt' "$(_estado_de "$base" )" 'a memoria tem entradas'
  for n in 2 4 8; do
    _zerar "$base" enviar
    _rodar "$base" sync --enviar --origem "$base/local" --destino /r --paralelo "$n"
    assert_igual 0 "$DBX_ESTADO" "N=$n; $DBX_ERRO"
    foto_n="$(_fotografia "$base" "$base/local")
$(_arvore "$base/enviado")"
    assert_igual "$foto_um" "$foto_n" "N=$n igual a N=1"
    [[ $(_pico "$base") -gt 1 ]] || _harness_falhar "N=$n sem simultaneidade: pico $(_pico "$base")"
  done
}

teste_par06_falha_por_item_sob_n_maior_continua_por_item_e_na_ordem_do_plano() {
  local base foto_um foto_n codigo_um
  base=$(_cenario)
  _remoto "$base" 6
  : >"$base/falha/a2.txt"
  : >"$base/falha/a5.txt"
  # Os primeiros demoram mais: a conclusao sai fora da ordem do plano.
  printf '0.4' >"$base/atraso/a1.txt"
  printf '0.3' >"$base/atraso/a2.txt"
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_diferente 0 "$DBX_ESTADO" 'N=1 falha'
  codigo_um=$DBX_ESTADO
  foto_um=$(_fotografia "$base" "$base/local")
  _zerar "$base" receber
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --paralelo 6
  foto_n=$(_fotografia "$base" "$base/local")
  assert_igual "$codigo_um" "$DBX_ESTADO" 'mesmo codigo de saida'
  assert_igual "$foto_um" "$foto_n" 'mesmas linhas de falha, na mesma ordem, mesmos arquivos e cache'
  assert_igual 2 "$(grep -c '^falha ' <<<"$DBX_ERRO")" 'cada item falho aparece uma vez'
  assert_contem 'falhas=2' "$DBX_SAIDA" 'contagem do resumo'
  assert_contem 'recebidos=4' "$DBX_SAIDA" 'os demais seguem'
  assert_igual 4 "$(find "$base/local" -type f | wc -l)" 'quatro arquivos recebidos'
  _zerar "$base" receber
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local" --paralelo 6
  assert_contem 'falha_caminho' "$DBX_SAIDA" 'json traz as falhas'
}

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

teste_par07_dry_run_nunca_dispara_paralelismo_nem_transferencia() {
  local base
  base=$(_cenario)
  _remoto "$base" 5
  _rodar "$base" --dry-run sync --receber --origem /r --destino "$base/local" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'simulacao'
  assert_igual 0 "$(_harness_contar 'files/download' "$base/chamadas")" 'nenhum download'
  assert_arquivo_ausente "$base/picos" 'nenhuma transferencia'
  assert_igual 0 "$(find "$base/tmp" -mindepth 1 | wc -l)" 'nenhuma area temporaria'
}

teste_par08_listagem_nunca_concorre_com_transferencia() {
  local base
  base=$(_cenario)
  _remoto "$base" 6
  printf '0.2' >"$base/atraso/a1.txt"
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_arquivo_ausente "$base/listagem_concorrente" 'nenhuma listagem com transferencia em andamento'
  [[ $(_harness_contar 'list_folder' "$base/chamadas") -ge 1 ]] || _harness_falhar 'sem listagem'
}

teste_par09_auditoria_estatica_o_auxiliar_nao_alcanca_escrita_de_estado() {
  local arquivo corpo funcao
  arquivo="$DBX_HARNESS_RAIZ/commands/sync.sh"
  for funcao in _dbx_cmd_sync_aux_item _dbx_cmd_sync_aux_iniciar _dbx_cmd_sync_enviar _dbx_cmd_sync_receber; do
    corpo=$(awk -v f="$funcao" '$0 ~ "^"f"\\(\\) \\{" {d=1} d {print} d && /^}/ {exit}' "$arquivo")
    [[ -n $corpo ]] || _harness_falhar "funcao $funcao nao encontrada"
    assert_nao_contem 'dbx_state_' "$corpo" "$funcao nao toca lib/state"
    assert_nao_contem 'dbx_cmd_ciclo' "$corpo" "$funcao nao toca trava nem area do ciclo"
    assert_nao_contem 'dbx_output_render' "$corpo" "$funcao nao imprime"
  done
  # O sync nunca liga a retomada (RF-102): o auxiliar nao alcanca o registro dela.
  assert_nao_contem 'dbx_cmd_retomada_preparar' "$(<"$arquivo")" 'sync nao prepara retomada'
  # O unico ponto que cria auxiliar e o da transferencia do plano.
  assert_igual 1 "$(_harness_contar '_dbx_cmd_sync_aux_item "\$pasta' "$arquivo")" 'um unico ponto de lancamento'
  # A listagem nao e chamada pelo ramo paralelo.
  corpo=$(awk '/^_dbx_cmd_sync_transferir_paralelo\(\) \{/ {d=1} d {print} d && /^}/ {exit}' "$arquivo")
  assert_nao_contem 'dbx_sync_listar' "$corpo" 'o ramo paralelo nao lista'
  assert_nao_contem 'dbx_state_gravar' "$corpo" 'cache so no fim, no principal'
}

# ---------------------------------------------------------------------------
# RF-134(c): sinais
# ---------------------------------------------------------------------------

teste_par10_sigterm_nao_deixa_auxiliar_vivo_nem_parcial() {
  local base pid i vivos
  base=$(_cenario)
  _remoto "$base" 4
  for i in 1 2 3 4; do printf '30' >"$base/atraso/a$i.txt"; done
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$DBX_EXEC" sync --receber --origem /r --destino "$base/local" --paralelo 4 \
    </dev/null >"$base/out" 2>"$base/err" &
  pid=$!
  for ((i = 0; i < 100; i++)); do
    [[ $(find "$base/vivos" -type f 2>/dev/null | wc -l) -ge 4 ]] && break
    sleep 0.1
  done
  [[ $(find "$base/vivos" -type f | wc -l) -ge 4 ]] || _harness_falhar 'as quatro transferencias nao chegaram a correr'
  kill -TERM "$pid"
  wait "$pid"
  DBX_ESTADO=$?
  assert_igual 14 "$DBX_ESTADO" 'mesmo codigo de saida de um sinal (nao_concluida)'
  vivos=$(pgrep -f -- "$base" | wc -l)
  assert_igual 0 "$vivos" 'nenhum processo remanescente'
  [[ -z $(find "$base/local" "$base/tmp" -name '*dbx-part*' -o -name '.*XXXX*' 2>/dev/null) ]] ||
    _harness_falhar 'sobrou parcial'
  assert_igual 0 "$(find "$base/local" -type f | wc -l)" 'nenhum arquivo parcial no destino'
  assert_igual 0 "$(find "$base/tmp" -mindepth 1 | wc -l)" 'nenhuma area temporaria'
}

# ---------------------------------------------------------------------------
# DIV-261, DIV-258, RF-139
# ---------------------------------------------------------------------------

_limites_de_download() { # <base> — as linhas limit-rate das requisicoes de conteudo
  grep -h 'limit-rate' "$1/opcoes" 2>/dev/null | sort -u
}

teste_par11_limite_de_banda_e_o_teto_total_dividido_por_n() {
  local base
  base=$(_cenario)
  _remoto "$base" 4
  # O duplo de teste desta fase nao guarda a configuracao: usa-se um segundo.
  sed -i 's|^printf .%s\\n. "\$url" >>"\$base/chamadas"$|&\n[[ $conf =~ (limit-rate = [^$'"'"'\\n'"'"']*) ]] \&\& printf "%s\\n" "${BASH_REMATCH[1]}" >>"$base/opcoes"|' "$base/bin/curl"
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --paralelo 4 --limite-banda 80K
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_igual 'limit-rate = 20480' "$(_limites_de_download "$base")" '81920 / 4 por transferencia'
  rm -f "$base/opcoes"
  rm -rf "$base/local"
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --limite-banda 80K
  assert_igual 'limit-rate = 81920' "$(_limites_de_download "$base")" 'N=1: a taxa inteira'
  rm -f "$base/opcoes"
  rm -rf "$base/local"
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --paralelo 8 --limite-banda 8K
  assert_igual 'limit-rate = 2048' "$(_limites_de_download "$base")" 'nunca abaixo do piso'
}

teste_par12_debug_informa_n_e_quantos_429_sem_reduzir_n() {
  local base
  base=$(_cenario)
  _remoto "$base" 4
  printf '#!%s\nexit 0\n' "$BASH" >"$base/bin/sleep"
  chmod +x "$base/bin/sleep"
  : >"$base/r429/a1.txt"
  : >"$base/r429/a2.txt"
  _rodar "$base" --debug sync --receber --origem /r --destino "$base/local" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  # DIV-338: o resumo unico de RF-162 substitui a linha `paralelo` de RF-135(d).
  assert_contem 'debug: resumo comando=sync ' "$DBX_ERRO" 'resumo unico'
  assert_contem ' limites_429=2 ' "$DBX_ERRO" 'contagem de 429 dos auxiliares'
  assert_contem ' paralelo=4' "$DBX_ERRO" 'N no resumo'
  assert_nao_contem 'transferencias simultaneas' "$DBX_ERRO" 'sem a linha paralelo antiga'
  assert_igual 4 "$(find "$base/local" -type f | wc -l)" 'todos recebidos apos o Retry-After'
}

teste_par13_sem_a_opcao_e_sem_a_variavel_nada_muda_e_nao_ha_auxiliar() {
  local base
  base=$(_cenario)
  _remoto "$base" 4
  _rodar "$base" --debug sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_nao_contem 'transferencias simultaneas' "$DBX_ERRO" 'sem resumo de paralelismo'
  assert_contem 'debug: resumo comando=sync ' "$DBX_ERRO" 'resumo com N=1'
  assert_nao_contem 'paralelo=' "$DBX_ERRO" 'N=1 omite paralelo= (RF-162(d))'
  assert_igual 1 "$(_pico "$base")" 'sequencial'
  assert_arquivo_ausente "$base/tmp/paralelo" 'sem area de auxiliares'
}

teste_par14_ajuda_autocompletar_readme_e_diagnostico() {
  local base
  base=$(_cenario)
  _rodar "$base" help sync
  assert_contem '--paralelo' "$DBX_SAIDA" 'help sync lista a opcao'
  assert_contem '--parallel' "$DBX_SAIDA" 'e o alias'
  assert_contem 'DBX_PARALELO' "$DBX_SAIDA" 'e a variavel'
  assert_contem '429' "$DBX_SAIDA" 'e a relacao com 429'
  assert_contem 'teto TOTAL' "$DBX_SAIDA" 'e a banda total (DIV-261)'
  _rodar "$base" completar bash
  assert_contem '--paralelo' "$DBX_SAIDA" 'autocompletar'
  assert_contem 'DBX_PARALELO' "$(<"$DBX_HARNESS_RAIZ/README.md")" 'README'
  assert_contem '--paralelo' "$(<"$DBX_HARNESS_RAIZ/README.md")" 'README'
  DBX_T_AMBIENTE=(DBX_PARALELO=3)
  _rodar "$base" diagnostico
  assert_contem 'paralelo=ok: 3 (origem: ambiente' "$DBX_SAIDA" 'diagnostico informa o efetivo'
  DBX_T_AMBIENTE=(DBX_PARALELO=0)
  _rodar "$base" diagnostico
  assert_contem 'paralelo=aviso' "$DBX_SAIDA" 'variavel invalida e aviso'
  DBX_T_AMBIENTE=()
}

# ---------------------------------------------------------------------------
# F-51: linhas dos auxiliares e resumo (RF-158, RF-162; TC-DBG-20, 21, 30, 31, 32)
# ---------------------------------------------------------------------------

teste_par15_debug_linhas_dos_auxiliares_chegam_ao_operador_e_somam_no_resumo() {
  local base http total i
  base=$(_cenario)
  _remoto "$base" 4
  # Atraso de 1 s por download: as quatro precisam se sobrepor para o pico ser 4.
  for i in 1 2 3 4; do printf '1' >"$base/atraso/a$i.txt"; done
  _rodar "$base" --debug sync --receber --origem /r --destino "$base/local" --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_igual 4 "$(_pico "$base")" 'paralelismo efetivo'
  # TC-DBG-20: as quatro transferencias rodaram nos auxiliares e as linhas chegaram.
  http=$(_conta_prefixo 'debug: http GET content.dropboxapi.com/2/files/download tentativa=1 ' "$base/err")
  assert_igual 4 "$http" 'uma linha http por download dos auxiliares'
  # RF-162(e): chamadas = requisicoes feitas (principal e auxiliares) = linhas com tentativa=1.
  total=$(_conta_prefixo '' "$base/chamadas")
  assert_igual "$total" "$(_conta_prefixo 'debug: http ' "$base/err")" \
    "toda requisicao tem linha; chamadas: $(<"$base/chamadas") | stderr: $DBX_ERRO"
  assert_contem "debug: resumo comando=sync chamadas=$total tentativas_extras=0 " "$DBX_ERRO" 'resumo soma os auxiliares'
  assert_igual 1 "$(_conta_prefixo 'debug: resumo ' "$base/err")" 'um so resumo'
  # TC-DBG-21: o arquivo de linhas de cada auxiliar nao sobrevive.
  assert_igual 0 "$(find "$base/tmp" -name 'dbg.*' | wc -l)" 'sem arquivo de linhas ao fim'
}

teste_par16_sem_debug_nenhuma_linha_nem_arquivo_de_auxiliar() {
  local base
  base=$(_cenario)
  _remoto "$base" 4
  printf '2' >"$base/atraso/a1.txt"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$DBX_EXEC" sync --receber --origem /r --destino "$base/local" --paralelo 4 \
    </dev/null >"$base/out" 2>"$base/err" &
  local pid=$! i
  for ((i = 0; i < 100; i++)); do
    [[ -n $(find "$base/vivos" -type f 2>/dev/null) ]] && break
    sleep 0.05
  done
  # TC-DBG-30: com a transferencia em curso, nenhum arquivo de linhas foi criado.
  assert_igual 0 "$(find "$base/tmp" -name 'dbg.*' | wc -l)" 'sem arquivo de linhas durante a execucao'
  wait "$pid"
  assert_igual 0 "$?" 'sync concluido'
  assert_nao_contem 'debug:' "$(<"$base/err")" 'nenhuma linha debug sem --debug'
}

teste_par17_falha_de_item_tem_resumo_com_o_codigo_de_saida() {
  local base
  base=$(_cenario)
  _remoto "$base" 4
  : >"$base/falha/a2.txt"
  _rodar "$base" --debug sync --receber --origem /r --destino "$base/local" --paralelo 4
  [[ $DBX_ESTADO -ne 0 ]] || _harness_falhar 'a falha do item deveria mudar o codigo'
  # TC-DBG-32: o resumo sai tambem em falha, com o codigo real.
  assert_contem 'debug: resumo comando=sync ' "$DBX_ERRO" 'resumo em falha'
  assert_contem " saida=$DBX_ESTADO" "$DBX_ERRO" 'resumo traz o codigo de saida'
  assert_contem 'a2.txt' "$DBX_ERRO" 'a mensagem de falha do item continua'
}

teste_par18_sinal_tem_resumo_em_melhor_esforco_e_nao_deixa_arquivo_de_linhas() {
  local base pid i
  base=$(_cenario)
  _remoto "$base" 4
  for i in 1 2 3 4; do printf '30' >"$base/atraso/a$i.txt"; done
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$DBX_EXEC" --debug sync --receber --origem /r --destino "$base/local" --paralelo 4 \
    </dev/null >"$base/out" 2>"$base/err" &
  pid=$!
  for ((i = 0; i < 100; i++)); do
    [[ $(find "$base/vivos" -type f 2>/dev/null | wc -l) -ge 4 ]] && break
    sleep 0.1
  done
  kill -TERM "$pid"
  wait "$pid"
  assert_igual 14 "$?" 'codigo de sinal'
  # TC-DBG-32 / DIV-341: resumo em melhor esforco; TC-DBG-21: sem arquivo de linhas.
  assert_contem 'debug: resumo comando=sync ' "$(<"$base/err")" 'resumo no sinal'
  assert_contem ' saida=14' "$(<"$base/err")" 'resumo com o codigo do sinal'
  assert_igual 0 "$(find "$base/tmp" -name 'dbg.*' | wc -l)" 'sem arquivo de linhas apos o sinal'
}

harness_executar "$@"
