#!/usr/bin/env bash
# Testes ponta a ponta da trava de concorrencia e da area temporaria unica
# (RF-69, RF-70, RF-71, RNF-35; TC-TRV, TC-ESR, TC-DIA-11..14, TC-TMP-02, 05, 06).
#
# Tudo por `bin/dbx`, com o `curl` substituido por um duplo que registra cada
# URL e se havia trava no diretorio de estado NAQUELE instante (coluna T/N): e
# o que prova "nenhuma chamada antes da aquisicao" olhando o que saiu, e nao o
# que o comando diz ter feito.
#
# A concorrencia e real: o duplo segura a primeira listagem ate o caso soltar,
# e a segunda execucao roda enquanto a primeira detem a trava.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e os roteiros chegam sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly CONFLITO=7
readonly USO=2
readonly NAO_CONCLUIDA=14
readonly SENTINELAS='SEGREDO-SENTINELA RT-SENTINELA TOKEN-SENTINELA CONTA-SENTINELA'
DORMIR=$(command -v sleep)
readonly DORMIR

# _cenario — credencial, duplo de rede e arvore local; imprime a base.
_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/trava-e2e.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"SEGREDO-SENTINELA","refresh_token":"RT-SENTINELA","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  printf '%s' 'conteudo remoto' >"$base/conteudo_remoto"
  {
    printf '#!%s\nbase=%q\ndormir=%q\n' "$BASH" "$base" "$DORMIR"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
saida='' escrever='' anterior='' url=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
trava=N
for t in "$base"/estado/dbx/trava-*; do [[ -e $t ]] && trava=T; done
printf '%s %s\n' "$url" "$trava" >>"$base/chamadas"
# A PRIMEIRA chamada que casa fica presa ate `soltar` (mkdir e atomico).
if [[ -f $base/bloquear && $url == *"$(<"$base/bloquear")"* ]] && mkdir "$base/bloqueado" 2>/dev/null; then
  while [[ ! -e $base/soltar ]]; do "$dormir" 0.05; done
fi
if [[ -f $base/sinal && $url == *"$(<"$base/sinal_url")"* ]]; then
  kill -s "$(<"$base/sinal")" 0
  "$dormir" 5
fi
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.TOKEN-SENTINELA","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA-SENTINELA"}' ;;
  *list_folder*) corpo=$(<"$base/listagem") ;;
  *files/download*) corpo=$(<"$base/conteudo_remoto") ;;
  *get_space_usage*) corpo='{"used":1,"allocation":{".tag":"individual","allocated":100000000}}' ;;
  *) corpo='{"name":"x","rev":"1","size":1}' ;;
esac
# Download de PASTA: o conteudo responde `not_file` (DIV-49, TC-TRV-40).
if [[ $url == *files/download* && -f $base/pasta ]]; then
  codigo=409
  corpo='{"error_summary":"path/not_file/.."}'
fi
if [[ $url == *list_folder* && -f $base/listagem_codigo ]]; then
  codigo=$(<"$base/listagem_codigo")
  corpo='{"error_summary":"other/.."}'
fi
if [[ -n $saida ]]; then printf '%s' "$corpo" >"$saida" 2>/dev/null || exit 23; fi
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

# _sleep_registrado <base> — `sleep` substituto que registra e nao dorme
# (RF-70(c): a espera e observavel por duplo). Com `$base/sleep_real`, dorme.
_sleep_registrado() {
  {
    printf '#!%s\nbase=%q\ndormir=%q\n' "$BASH" "$1" "$DORMIR"
    cat <<'FIM'
printf 'sleep %s\n' "$*" >>"$base/sleeps"
: >"$base/esperando"
[[ -f $base/sleep_real ]] && "$dormir" "$@"
exit 0
FIM
  } >"$1/bin/sleep"
  chmod +x "$1/bin/sleep"
}

# _env <base> — ambiente da execucao, em vetor.
_env() {
  AMBIENTE=(env -i PATH="$1/bin:$PATH" HOME="$1" XDG_CONFIG_HOME="$1/config"
    XDG_STATE_HOME="$1/estado" TMPDIR="$1/tmp")
}

# _rodar <base> <argumentos...> — em sessao propria (o duplo sinaliza o grupo).
_rodar() {
  local base=$1
  shift
  _env "$base"
  DBX_SAIDA='' DBX_ERRO=''
  setsid -w "${AMBIENTE[@]}" bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _segundo_plano <base> <rotulo> <argumentos...> — execucao que vai deter a trava.
_segundo_plano() {
  local base=$1 rotulo=$2
  shift 2
  _env "$base"
  ( setsid -w "${AMBIENTE[@]}" bash "$DBX_EXEC" "$@" </dev/null >"$base/out.$rotulo" 2>"$base/err.$rotulo"
    printf '%s' "$?" >"$base/estado.$rotulo" ) &
}

_esperar_arquivo() { # <arquivo>
  local espera=0
  while [[ ! -e $1 && $espera -lt 400 ]]; do "$DORMIR" 0.05; espera=$((espera + 1)); done
  [[ -e $1 ]] || _harness_falhar "nao apareceu: $1"
}

_esperar_estado() { # <base> <rotulo> — espera a execucao de segundo plano terminar
  _esperar_arquivo "$1/estado.$2"
  cat "$1/estado.$2"
}

# _retrato <dir> — arvore com modo, tamanho e resumo; `ausente` se nao existe.
_retrato() {
  [[ -e $1 ]] || { printf 'ausente'; return 0; }
  find "$1" -printf '%P %y %m %s\n' | LC_ALL=C sort
  find "$1" -type f -exec sha256sum {} + | sed "s|$1||" | LC_ALL=C sort
}

_travas() { find "$1/estado" -name 'trava-*' -o -name '.trava.*' 2>/dev/null; }
_residuo() { find "$1/tmp" -mindepth 1 -maxdepth 1 -name 'dbx-*' 2>/dev/null; }

_sem_sentinela() { # <texto> <contexto>
  local s
  for s in $SENTINELAS; do
    assert_nao_contem "$s" "$1" "$2: sentinela $s nao pode aparecer"
  done
}

# _trava_do_par <base> <raiz_local> <raiz_remota> — caminho da trava do par,
# pela mesma definicao do comando (identidade da credencial, local canonico).
_trava_do_par() {
  XDG_CONFIG_HOME="$1/config" XDG_STATE_HOME="$1/estado" TMPDIR="$1/tmp" bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/json.sh"; . "$1/lib/path.sh"; . "$1/lib/config.sh"; . "$1/lib/state.sh"
    dbx_config_carregar >/dev/null 2>&1; dbx_config_identidade
    dbx_path_local_canonico "$2"
    dbx_state_trava_caminho "$DBX_CONFIG_IDENTIDADE" "$DBX_PATH_RESULTADO" "$3"
    printf "%s" "$DBX_STATE_RESULTADO"' _ "$DBX_HARNESS_RAIZ" "$2" "$3"
}

_host_id() {
  bash -c '. "$1/lib/errors.sh"; . "$1/lib/state.sh"; dbx_state_host_id; printf "%s" "$DBX_STATE_HOST_ID"' _ "$DBX_HARNESS_RAIZ"
}

_linha() { printf 'dbx-trava\t1\t%s\t%s\t%s\t%s\tfim\n' "$1" "$2" "$3" "$4"; }

_plantar() { # <arquivo> <conteudo_com_quebra>
  # Caminho vazio (chave quebrada) escreveria no diretorio corrente.
  [[ $1 == "$DBX_TESTES_TMP"/* ]] || _harness_falhar 'trava fora da area do caso' "[$1]"
  mkdir -p "${1%/*}"
  chmod 700 "${1%/*}"
  printf '%s' "$2" >"$1"
  chmod 600 "$1"
}

_pid_morto() {
  local pid
  "$DORMIR" 0 &
  pid=$!
  wait "$pid"
  printf '%s' "$pid"
}

# _viva <base> — trava viva do par (local, /r) por um processo `sleep` real;
# publica VIVO e TRAVA.
_viva() {
  "$DORMIR" 60 &
  VIVO=$!
  TRAVA=$(_trava_do_par "$1" "$1/local" /r)
  _plantar "$TRAVA" "$(_linha "$VIVO" "$(_host_id)" 1700000000 sync)"$'\n'
}

_resumo_de() { # <arquivo>
  bash -c ". '$DBX_HARNESS_RAIZ/lib/errors.sh'; . '$DBX_HARNESS_RAIZ/lib/hash.sh'; dbx_hash_conteudo_arquivo '$1'"
}

# ---------------------------------------------------------------------------
# RF-69(a)(b)(d)(e): exclusao real, chave sem ordem, ordem, recusa
# ---------------------------------------------------------------------------

teste_trv01_mesmo_par_se_exclui_em_qualquer_sentido_e_pares_diferentes_rodam_juntos() {
  local base estado
  base=$(_cenario)
  mkdir -p "$base/local2"
  printf 'list_folder' >"$base/bloquear"
  _segundo_plano "$base" a sync --enviar --origem "$base/local" --destino /r
  _esperar_arquivo "$base/bloqueado"
  [[ -n $(_travas "$base") ]] || _harness_falhar 'a primeira execucao nao detem a trava'

  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  assert_igual "$CONFLITO" "$DBX_ESTADO" "o sentido oposto do mesmo par se exclui (DIV-38): $DBX_ERRO"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /R
  assert_igual "$CONFLITO" "$DBX_ESTADO" 'verificar do mesmo par, remoto em outra caixa: excluido'
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r
  assert_igual "$CONFLITO" "$DBX_ESTADO" 'a simulacao tambem trava (RF-69(e))'
  _rodar "$base" sync --enviar --origem "$base/local2" --destino /r
  assert_igual 0 "$DBX_ESTADO" "par diferente roda junto: $DBX_ERRO"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /outro
  assert_igual 0 "$DBX_ESTADO" "outro remoto, par diferente: $DBX_ERRO"

  : >"$base/soltar"
  estado=$(_esperar_estado "$base" a)
  assert_igual 0 "$estado" "a primeira conclui: $(cat "$base/err.a")"
  assert_igual '' "$(_travas "$base")" 'nenhuma trava sobra'
}

teste_trv02_trv06_ocupada_recusa_na_hora_sem_sleep_sem_api_e_sem_segredo() {
  local base antes
  base=$(_cenario)
  _sleep_registrado "$base"
  _viva "$base"
  antes=$(_retrato "$base/estado")
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  kill "$VIVO" 2>/dev/null
  assert_igual "$CONFLITO" "$DBX_ESTADO" "conflito: $DBX_ERRO"
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada a API'
  assert_arquivo_ausente "$base/sleeps" 'nenhum sleep'
  assert_igual "$antes" "$(_retrato "$base/estado")" 'nada escrito no estado'
  assert_contem "pid $VIVO" "$DBX_ERRO" 'pid'
  assert_contem "${HOSTNAME:-}" "$DBX_ERRO" 'host'
  assert_contem '2023-11-14T22:13:20Z' "$DBX_ERRO" 'inicio em UTC'
  assert_contem 'o sync' "$DBX_ERRO" 'comando'
  assert_contem '--esperar' "$DBX_ERRO" 'a opcao de espera'
  _sem_sentinela "$DBX_SAIDA$DBX_ERRO" 'trava ocupada'
  assert_igual '' "$(_residuo "$base")" 'sem area temporaria'
}

teste_trv03_toda_chamada_sai_com_a_trava_e_recusas_de_uso_nao_adquirem() {
  local base linha
  base=$(_cenario)
  printf 'a' >"$base/local/a.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  while IFS= read -r linha; do
    [[ $linha == *' T' ]] || _harness_falhar 'chamada a API antes da aquisicao ou depois da liberacao' "$linha"
  done <"$base/chamadas"
  assert_igual '' "$(_travas "$base")" 'liberada ao fim'

  base=$(_cenario)
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --esperar abc
  assert_igual "$USO" "$DBX_ESTADO" 'argumento invalido'
  _rodar "$base" sync --enviar --origem "$base/local" --destino $'/r\001x'
  assert_igual "$(dbx_errors_codigo_saida caminho_recusado)" "$DBX_ESTADO" 'caminho recusado'
  _rodar "$base" verificar --enviar --origem "$base/local" --destino $'/r\001x'
  assert_igual "$(dbx_errors_codigo_saida caminho_recusado)" "$DBX_ESTADO" 'caminho recusado no verificar'
  assert_igual 'ausente' "$(_retrato "$base/estado")" 'nenhuma recusa de uso cria o estado'
  assert_arquivo_ausente "$base/chamadas" 'nem chama a API'
}

teste_trv04_liberada_em_termino_normal_falha_e_recusa_por_guarda() {
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/a.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "normal: $DBX_ERRO"
  assert_igual '' "$(_travas "$base")" 'normal: liberada'
  printf '400' >"$base/listagem_codigo"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'falha remota'
  assert_igual '' "$(_travas "$base")" 'falha: liberada'
  rm -f "$base/listagem_codigo"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /nova --espelhar
  assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" 'recusa por guarda (RF-48)'
  assert_igual '' "$(_travas "$base")" 'recusa: liberada'
  # Liberada, e nao ausente desde sempre: nas tres execucoes a trava existia a
  # cada chamada a API.
  assert_igual 0 "$(_harness_contar ' N$' "$base/chamadas")" 'a trava existia durante as tres execucoes'
  [[ $(_harness_contar ' T$' "$base/chamadas") -gt 0 ]] || _harness_falhar 'nenhuma chamada registrada'
  assert_igual '' "$(_residuo "$base")" 'sem residuo em TMPDIR'
}

teste_trv05_tmp02_tmp05_sinal_em_cada_fase_sem_residuo_e_sem_trava() {
  # RF-69(c), RNF-35(c)(f): renovacao do token (OBS-02), identificacao da
  # conta, listagem remota, consulta de espaco (depois do plano e antes da
  # primeira acao), envio e recebimento.
  local sinal fase base sentido resumo
  for sinal in INT TERM HUP; do
    for fase in oauth2/token get_current_account list_folder get_space_usage files/upload files/download; do
      base=$(_cenario)
      sentido=(--enviar --origem "$base/local" --destino /r)
      printf 'a' >"$base/local/a.txt"
      if [[ $fase == files/download ]]; then
        rm -f "$base/local/a.txt"
        printf 'conteudo remoto' >"$base/remoto.txt"
        resumo=$(_resumo_de "$base/remoto.txt")
        printf '{"entries":[{".tag":"file","path_display":"/r/b.txt","content_hash":"%s","size":15}],"has_more":false}' \
          "$resumo" >"$base/listagem"
        sentido=(--receber --origem /r --destino "$base/local")
      fi
      printf '%s' "$sinal" >"$base/sinal"
      printf '%s' "$fase" >"$base/sinal_url"
      _rodar "$base" sync "${sentido[@]}"
      assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" "$sinal em $fase: nao concluida ($DBX_ERRO)"
      assert_igual 1 "$(_harness_contar "$fase" "$base/chamadas")" "$sinal em $fase: o sinal chegou na fase"
      assert_igual '' "$(_residuo "$base")" "$sinal em $fase: nenhuma entrada dbx-* em TMPDIR"
      assert_igual '' "$(_travas "$base")" "$sinal em $fase: a trava foi liberada"
      assert_igual '' "$(find "$base/local" -name '*.dbx-part.*')" "$sinal em $fase: sem temporario de recebimento"
    done
  done
}

teste_trv08_comandos_avulsos_nao_travam() {
  local base comando linha
  base=$(_cenario)
  printf 'a' >"$base/local/a.txt"
  touch -d '@1700000000' "$base/local/a.txt"
  for comando in "upload $base/local/a.txt /r/a.txt" 'list /r' 'info /r/a.txt' 'space' \
    "download /r/a.txt $base/baixado" 'delete --confirmar /r/a.txt' 'diagnostico'; do
    # shellcheck disable=SC2086  # o comando e montado por palavras de proposito
    _rodar "$base" $comando
  done
  while IFS= read -r linha; do
    [[ $linha == *' N' ]] || _harness_falhar 'comando avulso com trava presente' "$linha"
  done <"$base/chamadas"
  assert_igual '' "$(_travas "$base")" 'nenhuma trava criada'
}

teste_trv09_orfa_do_mesmo_host_e_retomada_com_aviso_e_codigo_normal() {
  local base trava morto
  base=$(_cenario)
  morto=$(_pid_morto)
  trava=$(_trava_do_par "$base" "$base/local" /r)
  _plantar "$trava" "$(_linha "$morto" "$(_host_id)" 1700000000 verificar)"$'\n'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "codigo normal: $DBX_ERRO"
  assert_contem "trava orfa de pid $morto removida" "$DBX_ERRO" 'com aviso (DIV-53)'
  assert_contem "pid $morto" "$DBX_ERRO" 'nomeando o pid da orfa'
  assert_igual '' "$(_travas "$base")" 'e liberada ao fim'
}

teste_trv18_verificar_e_simulacao_deixam_o_estado_byte_a_byte() {
  # DIV-39, RF-69(e): ausente, existente com memoria e upload, depois de sinal e
  # depois de trava ocupada.
  local base cenario antes sinal
  for cenario in ausente existente; do
    for comando in verificar sync; do
      base=$(_cenario)
      printf 'a' >"$base/local/a.txt"
      if [[ $cenario == existente ]]; then
        mkdir -p "$base/estado/dbx"
        chmod 700 "$base/estado/dbx"
        printf 'memoria' >"$base/estado/dbx/memoria-x"
        printf 'upload' >"$base/estado/dbx/upload-y"
        chmod 600 "$base/estado/dbx/memoria-x"
      fi
      antes=$(_retrato "$base/estado")
      local -a args=("$comando" --enviar --origem "$base/local" --destino /r)
      [[ $comando == sync ]] && args=(--dry-run "${args[@]}")
      _rodar "$base" "${args[@]}"
      assert_igual "$antes" "$(_retrato "$base/estado")" "$cenario/$comando: termino normal"
      for sinal in INT TERM HUP; do
        printf '%s' "$sinal" >"$base/sinal"
        printf 'list_folder' >"$base/sinal_url"
        _rodar "$base" "${args[@]}"
        assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" "$cenario/$comando/$sinal"
        assert_igual "$antes" "$(_retrato "$base/estado")" "$cenario/$comando: depois de $sinal"
      done
      rm -f "$base/sinal"
    done
  done
  base=$(_cenario)
  _viva "$base"
  antes=$(_retrato "$base/estado")
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_igual "$CONFLITO" "$DBX_ESTADO" 'ocupada'
  assert_igual "$antes" "$(_retrato "$base/estado")" 'depois de trava ocupada'
  kill "$VIVO" 2>/dev/null
}

teste_trv31_ordem_trava_leitura_gravacao_liberacao() {
  # RF-69(n): dobro de ordem por rastreio das chamadas de funcao.
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/a.txt"
  touch -d '@1700000000' "$base/local/a.txt"
  # O gancho DEBUG nao roda dentro do tratador de EXIT, onde a liberacao
  # acontece: cada evento anota se a trava existia naquele instante (T/N), e a
  # liberacao depois do `mv` se prova por "T no mv" e "nenhuma trava no fim".
  _env "$base"
  "${AMBIENTE[@]}" LOG="$base/ordem" EST="$base/estado/dbx" bash -c '
    set -o functrace
    trap '"'"'case $BASH_COMMAND in
      "dbx_state_trava_adquirir "*) e=adquirir ;;
      "dbx_state_carregar "*) e=ler-memoria ;;
      "mv -f -- \"\$temporario\" \"\$arquivo\""*) e=mv ;;
      *) e="" ;;
    esac
    if [[ -n $e ]]; then
      t=N; for x in "$EST"/trava-*; do [[ -e $x ]] && t=T; done
      printf "%s-%s\n" "$e" "$t" >>"$LOG"
    fi'"'"' DEBUG
    . "$1" sync --enviar --origem "$2" --destino /r' _ "$DBX_EXEC" "$base/local" >/dev/null 2>&1
  # O gancho pode disparar mais de uma vez pelo mesmo comando: so a ordem conta.
  assert_igual $'adquirir-N\nler-memoria-T\nmv-T' "$(uniq "$base/ordem")" \
    'trava antes da leitura da memoria, e ainda detida no mv'
  assert_igual 1 "$(find "$base/estado/dbx" -name 'memoria-*' | wc -l)" 'a memoria foi gravada'
  assert_igual '' "$(_travas "$base")" 'e a trava saiu depois do mv, no termino'
}

# ---------------------------------------------------------------------------
# RF-69(h2): unlink (TC-TRV-19, TC-TRV-20, parte de TC-TRV-34)
# ---------------------------------------------------------------------------

teste_trv19_unlink_com_trava_viva_recusa_7_e_nao_apaga_nada() {
  local base antes credencial
  base=$(_cenario)
  _viva "$base"
  _plantar "$base/estado/dbx/trava-0123456789abcdef0123456789abcdef" \
    "$(_linha "$(_pid_morto)" "$(_host_id)" 1700000000 sync)"$'\n'
  printf 'm' >"$base/estado/dbx/memoria-x"
  antes=$(_retrato "$base/estado")
  credencial=$(cat "$base/config/dbx/credencial.json")
  _rodar "$base" unlink --confirmar
  kill "$VIVO" 2>/dev/null
  assert_igual "$CONFLITO" "$DBX_ESTADO" "recusa: $DBX_ERRO"
  assert_contem "pid $VIVO" "$DBX_ERRO" 'nomeia a execucao viva'
  assert_igual "$antes" "$(_retrato "$base/estado")" 'nada apagado no estado'
  assert_igual "$credencial" "$(cat "$base/config/dbx/credencial.json")" 'credencial intacta'
  assert_arquivo_ausente "$base/chamadas" 'nem revogada'
  _sem_sentinela "$DBX_SAIDA$DBX_ERRO" 'unlink recusado'
}

teste_trv20_unlink_mantem_travas_nao_vivas_com_um_aviso_por_trava() {
  local base host morto
  base=$(_cenario)
  host=$(_host_id)
  morto=$(_pid_morto)
  _plantar "$base/estado/dbx/trava-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$(_linha "$morto" "$host" 1700000000 sync)"$'\n'
  _plantar "$base/estado/dbx/trava-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" $'lixo\033]0;X\007'
  _plantar "$base/estado/dbx/trava-cccccccccccccccccccccccccccccccc" "$(_linha "$morto" outra:b:1 1700000000 sync)"$'\n'
  _plantar "$base/estado/dbx/trava-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.r" "$(_linha "$morto" "$host" 1700000001 sync)"$'\n'
  printf 'm' >"$base/estado/dbx/memoria-x"
  printf 'u' >"$base/estado/dbx/upload-y"
  printf 't' >"$base/estado/dbx/.memoria.1.AAAAAAAA"
  printf 'l' >"$base/estado/dbx/dbx.db"
  local travas_antes
  travas_antes=$(cd "$base/estado/dbx" && sha256sum trava-* | LC_ALL=C sort)
  _rodar "$base" unlink --confirmar
  assert_igual 0 "$DBX_ESTADO" "segue RF-51(f): $DBX_ERRO"
  assert_arquivo_ausente "$base/config/dbx/credencial.json" 'credencial removida'
  assert_arquivo_ausente "$base/estado/dbx/memoria-x" 'memoria removida'
  assert_arquivo_ausente "$base/estado/dbx/upload-y" 'cache removido'
  assert_arquivo_ausente "$base/estado/dbx/.memoria.1.AAAAAAAA" 'temporario removido'
  assert_arquivo_ausente "$base/estado/dbx/dbx.db" 'legado removido'
  assert_igual "$travas_antes" "$(cd "$base/estado/dbx" && sha256sum trava-* | LC_ALL=C sort)" \
    'as quatro travas nao vivas ficam, com os mesmos bytes'
  assert_igual 4 "$(grep -c 'trava mantida' <<<"$DBX_ERRO")" 'uma linha de aviso por trava'
  [[ $DBX_ERRO == *$'\033'* || $DBX_ERRO == *$'\007'* ]] && _harness_falhar 'byte cru da trava no stderr'
  return 0
}

# ---------------------------------------------------------------------------
# RF-70: --esperar / --wait (TC-ESR-01..08)
# ---------------------------------------------------------------------------

teste_esr01_valores_validos_e_invalidos() {
  local base valor
  base=$(_cenario)
  for valor in 0 1 3600; do
    _rodar "$base" sync --enviar --origem "$base/local" --destino /r --esperar "$valor"
    assert_igual 0 "$DBX_ESTADO" "$valor valido: $DBX_ERRO"
  done
  base=$(_cenario)
  for valor in '' -1 1.5 3601 abc +1 ' 1' 99999; do
    _rodar "$base" sync --enviar --origem "$base/local" --destino /r --esperar "$valor"
    assert_igual "$USO" "$DBX_ESTADO" "[$valor] invalido"
    assert_contem '--esperar' "$DBX_ERRO" "[$valor]: a mensagem nomeia a opcao"
    _rodar "$base" verificar --enviar --origem "$base/local" --destino /r --wait "$valor"
    assert_igual "$USO" "$DBX_ESTADO" "[$valor] invalido no verificar"
    assert_contem '--wait' "$DBX_ERRO" "[$valor]: nomeia o alias usado"
  done
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --esperar
  assert_igual "$USO" "$DBX_ESTADO" 'sem valor'
  assert_arquivo_ausente "$base/chamadas" 'antes de rede'
  assert_igual 'ausente' "$(_retrato "$base/estado")" 'antes de trava e escrita'
}

teste_esr02_esr04_zero_recusa_na_hora_e_espera_esgotada_diz_o_tempo() {
  local base
  base=$(_cenario)
  _sleep_registrado "$base"
  _viva "$base"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --esperar 0
  assert_igual "$CONFLITO" "$DBX_ESTADO" '0: recusa'
  assert_arquivo_ausente "$base/sleeps" '0: sem sondagem'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --esperar 3
  kill "$VIVO" 2>/dev/null
  assert_igual "$CONFLITO" "$DBX_ESTADO" 'esgotada: recusa'
  assert_igual $'sleep 1\nsleep 1\nsleep 1' "$(cat "$base/sleeps")" 'tres sondagens de 1 s'
  assert_contem 'esperou 3 s' "$DBX_ERRO" 'a mensagem diz quanto esperou'
  assert_arquivo_ausente "$base/chamadas" 'a espera nao chama a API'
}

teste_esr03_espera_e_adquire_quando_a_trava_e_liberada() {
  local base estado
  base=$(_cenario)
  printf 'list_folder' >"$base/bloquear"
  _segundo_plano "$base" a sync --enviar --origem "$base/local" --destino /r
  _esperar_arquivo "$base/bloqueado"
  _segundo_plano "$base" b verificar --enviar --origem "$base/local" --destino /r --esperar 20
  "$DORMIR" 1.5
  [[ -e $base/estado.b ]] && _harness_falhar 'a segunda nao esperou'
  : >"$base/soltar"
  assert_igual 0 "$(_esperar_estado "$base" a)" 'a primeira conclui'
  estado=$(_esperar_estado "$base" b)
  assert_igual 0 "$estado" "a segunda adquire depois da liberacao: $(cat "$base/err.b")"
  assert_igual '' "$(_travas "$base")" 'nada sobra'
}

teste_esr05_alias_e_repeticao_ultimo_vence() {
  local base
  base=$(_cenario)
  _sleep_registrado "$base"
  _viva "$base"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --esperar 0 --wait 2
  assert_igual $'sleep 1\nsleep 1' "$(cat "$base/sleeps")" 'o ultimo valor vence'
  rm -f "$base/sleeps"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r --wait abc --esperar 1
  kill "$VIVO" 2>/dev/null
  assert_igual "$CONFLITO" "$DBX_ESTADO" 'valor invalido sobrescrito: vale o ultimo'
  assert_igual 'sleep 1' "$(cat "$base/sleeps")" 'uma sondagem'
}

teste_esr06_orfa_retomada_na_primeira_sondagem_e_outro_host_nunca() {
  local base trava
  base=$(_cenario)
  _sleep_registrado "$base"
  trava=$(_trava_do_par "$base" "$base/local" /r)
  _plantar "$trava" "$(_linha "$(_pid_morto)" "$(_host_id)" 1700000000 sync)"$'\n'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --esperar 5
  assert_igual 0 "$DBX_ESTADO" "orfa retomada: $DBX_ERRO"
  assert_arquivo_ausente "$base/sleeps" 'sem esperar'
  _plantar "$trava" "$(_linha "$(_pid_morto)" outra-maquina:b:1 1700000000 sync)"$'\n'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --esperar 2
  assert_igual "$CONFLITO" "$DBX_ESTADO" 'outro host: recusa'
  assert_igual $'sleep 1\nsleep 1' "$(cat "$base/sleeps")" 'a espera corre ate o fim'
  assert_contem 'outro host' "$DBX_ERRO" 'e diz por que'
  assert_arquivo_existe "$trava" 'a de outro host fica'
}

teste_esr07_sinal_durante_a_espera_sai_com_14_sem_residuo() {
  local base sinal antes
  for sinal in INT TERM HUP; do
    base=$(_cenario)
    _sleep_registrado "$base"
    : >"$base/sleep_real"
    _viva "$base"
    antes=$(_retrato "$base/estado")
    ( _esperar_arquivo "$base/esperando"; kill "-$sinal" -- "-$(cat "$base/pid")" ) &
    _env "$base"
    setsid -w "${AMBIENTE[@]}" bash -c 'printf "%s" "$$" >"$1/pid"; exec bash "$2" sync --enviar --origem "$1/local" --destino /r --esperar 30' \
      _ "$base" "$DBX_EXEC" </dev/null >"$base/out" 2>"$base/err"
    DBX_ESTADO=$?
    wait
    kill "$VIVO" 2>/dev/null
    assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" "$sinal na espera: 14"
    assert_igual '' "$(_residuo "$base")" "$sinal na espera: sem residuo"
    assert_igual "$antes" "$(_retrato "$base/estado")" "$sinal na espera: a trava alheia fica e nada mais"
  done
}

teste_esr08_demais_comandos_recusam_esperar_e_a_ajuda_traz_a_opcao() {
  local base comando
  base=$(_cenario)
  printf 'a' >"$base/a.txt"
  for comando in "upload $base/a.txt /r/a.txt" 'download /r/a.txt' 'list /r' 'info /r' 'delete --confirmar /r/a'; do
    # shellcheck disable=SC2086  # o comando e montado por palavras de proposito
    _rodar "$base" $comando --esperar 5
    assert_igual "$USO" "$DBX_ESTADO" "$comando --esperar: uso invalido"
  done
  for comando in sync verificar; do
    _rodar "$base" help "$comando"
    assert_contem '--esperar, --wait <s>' "$DBX_SAIDA" "ajuda do $comando"
  done
}

# ---------------------------------------------------------------------------
# RF-71: checagem `trava` do diagnostico (TC-DIA-11..14), NFS (TC-TRV-35)
# ---------------------------------------------------------------------------

teste_dia11_sem_travas_ok_e_estado_ausente_nao_e_criado() {
  local base
  base=$(_cenario)
  _rodar "$base" diagnostico
  assert_contem 'trava=ok: sem travas' "$DBX_SAIDA" 'sem travas'
  assert_igual 'ausente' "$(_retrato "$base/estado")" 'nada criado'
}

teste_dia12_dia13_dia14_cada_estado_uma_linha_com_remedio_sem_alterar_nada() {
  local base host morto vivo antes
  base=$(_cenario)
  host=$(_host_id)
  morto=$(_pid_morto)
  "$DORMIR" 60 &
  vivo=$!
  _plantar "$base/estado/dbx/trava-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$(_linha "$vivo" "$host" 1700000000 sync)"$'\n'
  _plantar "$base/estado/dbx/trava-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" "$(_linha "$morto" "$host" 1700000000 verificar)"$'\n'
  _plantar "$base/estado/dbx/trava-cccccccccccccccccccccccccccccccc" "$(_linha "$morto" outra-maquina:b:1 1700000000 sync)"$'\n'
  _plantar "$base/estado/dbx/trava-dddddddddddddddddddddddddddddddd" $'lixo\033]0;X\007'
  _plantar "$base/estado/dbx/trava-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.r" "$(_linha "$morto" "$host" 1700000001 sync)"$'\n'
  antes=$(_retrato "$base/estado")
  _rodar "$base" diagnostico
  kill "$vivo" 2>/dev/null
  assert_contem "trava=ok: viva: o sync pid $vivo" "$DBX_SAIDA" 'viva'
  assert_contem "trava=aviso: orfa: o verificar pid $morto" "$DBX_SAIDA" 'orfa'
  assert_contem 'sera retomada na proxima execucao' "$DBX_SAIDA" 'remedio da orfa'
  assert_contem 'trava=aviso: outro-host: o sync' "$DBX_SAIDA" 'outro host'
  assert_contem 'confirme que a execucao em outra-maquina' "$DBX_SAIDA" 'remedio de outro host'
  assert_contem 'trava=aviso: ilegivel:' "$DBX_SAIDA" 'ilegivel'
  assert_contem 'retomada interrompida' "$DBX_SAIDA" '.r orfa'
  assert_igual 5 "$(grep -c '^trava=' <<<"$DBX_SAIDA")" 'uma linha por trava'
  assert_nao_contem 'trava=falha' "$DBX_SAIDA" 'trava nunca e falha'
  assert_igual "$antes" "$(_retrato "$base/estado")" 'nada alterado, a orfa continua la'
  [[ $DBX_SAIDA$DBX_ERRO == *$'\033'* ]] && _harness_falhar 'byte cru da trava ilegivel na saida'
  _sem_sentinela "$DBX_SAIDA$DBX_ERRO" 'diagnostico'
  _rodar "$base" --json diagnostico
  assert_contem 'contrato=' "$DBX_SAIDA" 'saida estruturada'
  assert_igual 5 "$(grep -c '^trava=' <<<"$DBX_SAIDA")" 'estruturada com os mesmos campos trava'
  _sem_sentinela "$DBX_SAIDA$DBX_ERRO" 'diagnostico --json'
}

teste_trv35_estado_em_nfs_avisa_e_nao_bloqueia() {
  local base real
  base=$(_cenario)
  real=$(command -v stat)
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  printf '#!%s\n[[ " $* " == *" -f "* ]] && { printf "nfs\\n"; exit 0; }\nexec %q "$@"\n' "$BASH" "$real" >"$base/bin/stat"
  chmod +x "$base/bin/stat"
  _rodar "$base" diagnostico
  assert_contem 'NFS' "$DBX_SAIDA" 'avisa'
  assert_contem 'melhor esforco' "$DBX_SAIDA" 'e diz o limite'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" 'nenhum comando bloqueia'
  printf '#!%s\n[[ " $* " == *" -f "* ]] && exit 1\nexec %q "$@"\n' "$BASH" "$real" >"$base/bin/stat"
  _rodar "$base" diagnostico
  assert_nao_contem 'NFS' "$DBX_SAIDA" 'sem stat -f, sem aviso'
}

# ---------------------------------------------------------------------------
# OBS-04 (RNF-35(g), TC-TMP-06) e auditoria de escrita (TC-TRV-36)
# ---------------------------------------------------------------------------

teste_tmp06_saida_em_socket_que_fecha_cedo_e_consumidor_encerrou() {
  command -v python3 >/dev/null 2>&1 || pular 'python3 ausente: sem como montar o socket do caso'
  local base estado
  base=$(_cenario)
  _env "$base"
  estado=$(ERRO="$base/err" python3 -I -c '
import os, socket, subprocess, sys
a, b = socket.socketpair()
b.close()
p = subprocess.run(sys.argv[1:], stdout=a.fileno(), stdin=subprocess.DEVNULL,
                   stderr=open(os.environ["ERRO"], "wb"))
print(p.returncode)
' "${AMBIENTE[@]}" bash "$DBX_EXEC" download /r/a.txt)
  DBX_ERRO=$(cat "$base/err" 2>/dev/null)
  assert_igual "$(dbx_errors_codigo_saida consumidor_encerrou)" "$estado" "classe 15: $DBX_ERRO"
  assert_contem 'consumidor' "$DBX_ERRO" 'a mensagem nomeia a causa'
  assert_nao_contem 'configuracao' "$DBX_ERRO" 'sem diagnostico de configuracao'
  assert_igual 1 "$(_harness_contar 'files/download' "$base/chamadas")" 'sem repeticao'
  assert_igual '' "$(_residuo "$base")" 'sem residuo'
}

teste_trv36_a_trava_e_escrita_so_de_lib_state() {
  local achados='' arquivo
  for arquivo in "$DBX_HARNESS_RAIZ"/lib/*.sh "$DBX_HARNESS_RAIZ"/commands/*.sh "$DBX_HARNESS_RAIZ"/bin/dbx; do
    [[ ${arquivo##*/} == state.sh ]] && continue
    # O nome da trava aparece entre aspas no codigo que a cria
    # (`: >"$d/trava-x"`, `mktemp "$d/.trava.XXXX"`): texto cru (QA-B2-11).
    achados+=$(grep -nE '\.trava\.|trava-' "$arquivo" |
      grep -vE '^[0-9]+:[[:space:]]*#' |
      grep -E '>|mktemp|dbx_tmp_arquivo' | sed "s|^|$arquivo:|" || true)
    # Para o ln, literais entre aspas (mensagem, lista de utilitarios) nao sao codigo.
    achados+=$(sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g' "$arquivo" |
      grep -nE '(^|[[:space:];&|(])ln[[:space:]]' |
      grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$arquivo:|" || true)
  done
  assert_igual '' "$achados" 'criacao de trava fora de lib/state'
  local -a usos=()
  mapfile -t usos < <(grep -nE '(^|[[:space:];&|(])ln[[:space:]]' "$DBX_HARNESS_RAIZ/lib/state.sh" |
    grep -vE '^[0-9]+:[[:space:]]*#')
  assert_igual 1 "${#usos[@]}" "um unico ln, o da receita de RF-69(j): ${usos[*]}"
}

# ---------------------------------------------------------------------------
# Ciclo 2 do QA: TC-TRV-37..40, DIV-50, DIV-51, QA-B2-02
# ---------------------------------------------------------------------------

teste_c2_trv37_a_chave_e_da_credencial_e_nao_revela_o_token() {
  # DIV-47: a mesma credencial exclui; outra credencial (outro refresh token)
  # sobre o mesmo par e o mesmo estado e outra chave.
  local base outra a b
  base=$(_cenario)
  outra="$base/config2"
  mkdir -p "$outra/dbx"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"SEGREDO-SENTINELA","refresh_token":"RT-OUTRO","raiz_remota":"/"}' \
    >"$outra/dbx/credencial.json"
  chmod 700 "$outra/dbx"
  chmod 600 "$outra/dbx/credencial.json"
  a=$(_trava_do_par "$base" "$base/local" /r)
  b=$(XDG_CONFIG_HOME="$outra" bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/json.sh"; . "$1/lib/path.sh"; . "$1/lib/config.sh"; . "$1/lib/state.sh"
    dbx_config_carregar >/dev/null 2>&1; dbx_config_identidade
    dbx_path_local_canonico "$2"
    XDG_STATE_HOME="$3" dbx_state_trava_caminho "$DBX_CONFIG_IDENTIDADE" "$DBX_PATH_RESULTADO" /r
    printf "%s" "$DBX_STATE_RESULTADO"' _ "$DBX_HARNESS_RAIZ" "$base/local" "$base/estado")
  [[ $a == "$base/estado/dbx/trava-"* && $b == "$base/estado/dbx/trava-"* ]] ||
    _harness_falhar 'caminhos de trava inesperados' "$a $b"
  assert_diferente "$a" "$b" 'outra credencial, outra chave'
  assert_nao_contem 'RT-' "$a$b" 'o token nao aparece no nome'
  _viva "$base"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  kill "$VIVO" 2>/dev/null
  assert_igual "$CONFLITO" "$DBX_ESTADO" 'a mesma credencial se exclui'
}

teste_c2_trv38_estado_alheio_segue_sem_trava_com_aviso() {
  [[ $EUID -ne 0 ]] || pular 'como root todo diretorio pertence ao usuario'
  local base
  base=$(_cenario)
  mkdir -p "$base/estado"
  ln -s /usr "$base/estado/dbx"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "segue: $DBX_ERRO"
  assert_contem 'sem trava de concorrencia nesta execucao' "$DBX_ERRO" 'com aviso'
}

teste_c2_trv39_estado_sem_escrita_segue_e_com_trava_viva_recusa_7() {
  [[ $EUID -ne 0 ]] || pular 'como root todo diretorio e gravavel'
  local base
  base=$(_cenario)
  mkdir -p "$base/estado/dbx"
  chmod 500 "$base/estado/dbx"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  chmod 700 "$base/estado/dbx"
  assert_igual 0 "$DBX_ESTADO" "sem trava, segue: $DBX_ERRO"
  assert_contem 'sem escrita' "$DBX_ERRO" 'o aviso diz por que'
  _viva "$base"
  chmod 500 "$base/estado/dbx"
  rm -f "$base/chamadas"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  chmod 700 "$base/estado/dbx"
  kill "$VIVO" 2>/dev/null
  assert_igual "$CONFLITO" "$DBX_ESTADO" "trava viva legivel em diretorio sem escrita: 7 ($DBX_ERRO)"
  assert_contem "pid $VIVO" "$DBX_ERRO" 'nomeia quem a tem'
  assert_arquivo_ausente "$base/chamadas" 'antes de qualquer chamada'
}

teste_c2_trv40_download_de_pasta_trava_o_par() {
  local base
  base=$(_cenario)
  : >"$base/pasta"
  # A pasta remota `/r` desce para `<destino>/r`: o par e (local/r, /r).
  "$DORMIR" 60 &
  VIVO=$!
  _plantar "$(_trava_do_par "$base" "$base/local/r" /r)" \
    "$(_linha "$VIVO" "$(_host_id)" 1700000000 sync)"$'\n'
  _rodar "$base" download /r "$base/local"
  kill "$VIVO" 2>/dev/null
  assert_igual "$CONFLITO" "$DBX_ESTADO" "o sync interno do download de pasta trava: $DBX_ERRO"
  assert_contem "pid $VIVO" "$DBX_ERRO" 'com a mensagem da trava'
}

teste_c2_div50_repeticoes_esgotadas_recusam_7_e_nao_seguem_sem_trava() {
  # `ln` que diz que criou e nao cria: o nome nunca aparece, as 50 repeticoes
  # se esgotam; o comando recusa com 7 e nenhuma chamada sai.
  local base
  base=$(_cenario)
  printf '#!%s\nexit 0\n' "$BASH" >"$base/bin/ln"
  chmod +x "$base/bin/ln"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual "$CONFLITO" "$DBX_ESTADO" "repeticoes esgotadas: 7 ($DBX_ERRO)"
  assert_nao_contem 'sem trava de concorrencia' "$DBX_ERRO" 'nunca segue sem trava'
  assert_arquivo_ausente "$base/chamadas" 'nada chega a API'
}

teste_c2_div51_download_para_socket_vivo_sai_0_com_o_conteudo() {
  command -v python3 >/dev/null 2>&1 || pular 'python3 ausente: sem como montar o socket do caso'
  local base saida
  base=$(_cenario)
  _env "$base"
  saida=$(ERRO="$base/err" python3 -I -c '
import os, socket, subprocess, sys
a, b = socket.socketpair()
p = subprocess.Popen(sys.argv[1:], stdout=a.fileno(), stdin=subprocess.DEVNULL,
                     stderr=open(os.environ["ERRO"], "wb"))
a.close()
dados = b""
while True:
    c = b.recv(4096)
    if not c:
        break
    dados += c
p.wait()
print(p.returncode, dados.decode())
' "${AMBIENTE[@]}" bash "$DBX_EXEC" download /r/a.txt)
  assert_igual '0 conteudo remoto' "$saida" "socket vivo: sai 0 e recebe tudo ($(cat "$base/err"))"
  assert_igual 1 "$(_harness_contar 'files/download' "$base/chamadas")" 'uma transferencia'
  assert_igual '' "$(_residuo "$base")" 'sem residuo'
}

teste_c2_qa_b2_02_unlink_reconfere_as_travas_antes_de_apagar() {
  # Uma execucao comeca DURANTE a revogacao (chamada de rede): o unlink confere
  # de novo antes de apagar, recusa com 7 e nao apaga nada local.
  local base estado credencial trava
  base=$(_cenario)
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  printf 'memoria' >"$base/estado/dbx/memoria-x"
  credencial=$(cat "$base/config/dbx/credencial.json")
  printf 'token/revoke' >"$base/bloquear"
  _segundo_plano "$base" u unlink --confirmar
  _esperar_arquivo "$base/bloqueado"
  "$DORMIR" 60 &
  VIVO=$!
  trava=$(_trava_do_par "$base" "$base/local" /r)
  _plantar "$trava" "$(_linha "$VIVO" "$(_host_id)" 1700000000 sync)"$'\n'
  : >"$base/soltar"
  estado=$(_esperar_estado "$base" u)
  kill "$VIVO" 2>/dev/null
  assert_igual "$CONFLITO" "$estado" "recusa depois da revogacao: $(cat "$base/err.u")"
  assert_arquivo_existe "$base/estado/dbx/memoria-x" 'a memoria fica'
  assert_igual "$credencial" "$(cat "$base/config/dbx/credencial.json")" 'a credencial fica'
  assert_nao_contem 'trava mantida' "$(cat "$base/err.u")" 'trava viva nunca descrita como mantida'
  assert_contem "pid $VIVO" "$(cat "$base/err.u")" 'nomeia a execucao viva'
}

teste_c3_qa_b2_09_orfa_conhecida_retomada_no_meio_do_unlink_para_com_7() {
  # A orfa que o unlink ja conhece e retomada (mesmo nome, agora viva) entre
  # duas remocoes: a conferencia por conteudo e estado para tudo com 7.
  local base trava real nova
  base=$(_cenario)
  trava=$(_trava_do_par "$base" "$base/local" /r)
  _plantar "$trava" "$(_linha "$(_pid_morto)" "$(_host_id)" 1700000000 sync)"$'\n'
  printf 'a' >"$base/estado/dbx/memoria-a"
  printf 'b' >"$base/estado/dbx/memoria-b"
  "$DORMIR" 60 &
  VIVO=$!
  nova=$(_linha "$VIVO" "$(_host_id)" 1700000900 sync)
  real=$(command -v rm)
  {
    printf '#!%s\nreal=%q\ntrava=%q\nnova=%q\nmarca=%q\n' "$BASH" "$real" "$trava" "$nova" "$base/trocada"
    # A nova trava e escrita fora do estado e renomeada: nenhum nome novo
    # `trava-*` aparece, so o conteudo muda.
    printf '%s\n' 'if [[ " $* " == *"/memoria-"* && ! -e $marca ]]; then' \
      '  printf "%s\n" "$nova" >"$marca.x"; mv -f -- "$marca.x" "$trava"; : >"$marca"' \
      'fi' 'exec "$real" "$@"'
  } >"$base/bin/rm"
  chmod +x "$base/bin/rm"
  _rodar "$base" unlink --confirmar
  kill "$VIVO" 2>/dev/null
  assert_arquivo_existe "$base/trocada" 'a troca aconteceu no meio da remocao'
  assert_igual "$CONFLITO" "$DBX_ESTADO" "a orfa virou viva no meio: 7 ($DBX_ERRO)"
  assert_igual 1 "$(find "$base/estado/dbx" -name 'memoria-*' | wc -l)" 'parou depois da primeira memoria'
  assert_nao_contem 'trava mantida' "$DBX_ERRO" 'a trava viva nunca e descrita como mantida'
}

harness_executar "$@"
