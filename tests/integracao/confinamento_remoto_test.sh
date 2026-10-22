#!/usr/bin/env bash
# Confinamento remoto em todo comando (F-36, RNF-20(b1..b6), TC-SEC-18..27) e
# caminho remoto com caractere de controle (F-37, RNF-10(b), TC-SEC-28..29).
#
# Pelo executavel real. A prova de "antes de qualquer chamada a API" e o LOG do
# duplo de `curl`: na recusa ele nao existe — nem a renovacao do token sai.
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
RECUSADO=$(dbx_errors_codigo_saida caminho_recusado)
CONFIGURACAO=$(dbx_errors_codigo_saida configuracao)
readonly RECUSADO CONFIGURACAO

# Todas as formas de comando que recebem caminho remoto. O `upload` de
# diretorio e o `download` de pasta derivam o destino e o repassam ao `sync`.
readonly FORMAS='upload upload_fluxo upload_diretorio download list delete info sync_enviar sync_receber verificar_enviar verificar_receber'

# _cenario <raiz_remota_gravada> — credencial com a raiz dada, duplo de rede que
# registra cada URL em `chamadas` e o que foi enviado (opcoes e corpo) em
# `enviado`, arvore local com um arquivo.
_cenario() {
  local raiz=$1 base
  base=$(mktemp -d "$DBX_TESTES_TMP/confinamento.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"%s"}' "$raiz" \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf 'conteudo' >"$base/local/a.txt"
  cat >"$base/bin/curl" <<FIM
#!/usr/bin/env bash
base=$base
FIM
  cat >>"$base/bin/curl" <<'FIM'
cat >>"$base/enviado" 2>/dev/null
saida=""; escrever=""; anterior=""; url=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; @*) cat -- "${arg#@}" >>"$base/enviado" 2>/dev/null ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *list_folder*) corpo='{"entries":[],"cursor":"c","has_more":false}' ;;
  *upload_session/start*) corpo='{"session_id":"s1"}' ;;
  *get_space_usage*) corpo='{"used":1,"allocation":{".tag":"individual","allocated":1000000}}' ;;
  *files/get_metadata*) codigo=409; corpo='{"error_summary":"path/not_found/"}' ;;
  *files/download*)
    if [[ -f $base/pasta ]]; then codigo=409; corpo='{"error_summary":"path/not_file/"}'
    else corpo='conteudo'; fi ;;
  *) corpo='{"name":"a.txt","path_display":"/x",".tag":"file","size":1}' ;;
esac
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_rodar() { # <base> <argumentos...>
  local base=$1
  shift
  rm -f "$base/chamadas" "$base/enviado"
  DBX_SAIDA=''
  DBX_ERRO=''
  env -i ${DBX_TESTE_LC:+LC_ALL="$DBX_TESTE_LC"} PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _rodar_forma <base> <forma> <remoto> — executa a forma com o caminho remoto.
_rodar_forma() {
  local base=$1 forma=$2 remoto=$3
  case $forma in
    upload) _rodar "$base" upload "$base/local/a.txt" "$remoto" ;;
    upload_fluxo) _rodar "$base" upload - "$remoto" ;;
    upload_diretorio) _rodar "$base" upload "$base/local" "$remoto/" ;;
    download) _rodar "$base" download "$remoto" "$base/baixado" ;;
    list) _rodar "$base" list "$remoto" ;;
    delete) _rodar "$base" delete --yes "$remoto" ;;
    info) _rodar "$base" info "$remoto" ;;
    sync_enviar) _rodar "$base" sync --enviar --origem "$base/local" --destino "$remoto" ;;
    sync_receber) _rodar "$base" sync --receber --origem "$remoto" --destino "$base/recebido" ;;
    verificar_enviar) _rodar "$base" verificar --enviar --origem "$base/local" --destino "$remoto" ;;
    verificar_receber) _rodar "$base" verificar --receber --origem "$remoto" --destino "$base/local" ;;
    *) _harness_falhar "forma desconhecida: $forma" ;;
  esac
}

# _recusado_sem_rede <base> <rotulo> [codigo]
_recusado_sem_rede() {
  local base=$1 rotulo=$2 codigo=${3:-$RECUSADO}
  assert_igual "$codigo" "$DBX_ESTADO" "$rotulo: codigo; erro: $DBX_ERRO; estado: $DBX_ESTADO"
  assert_arquivo_ausente "$base/chamadas" "$rotulo: nenhuma chamada, nem a renovacao do token"
  assert_igual '' "$DBX_SAIDA" "$rotulo: a recusa nao sai pela saida padrao (RF-28)"
  # Uma unica linha de erro: a recusa nao e emitida duas vezes. (O aviso de
  # localidade do `verificar`, quando houver, e outra linha e nao conta.)
  assert_igual 1 "$(_harness_contar '^erro[=:]' "$base/err")" "$rotulo: um unico diagnostico de erro; erro: $DBX_ERRO; estado: $DBX_ESTADO"
}

# _aceito <base> <rotulo> <trecho_enviado> — passou do confinamento e o caminho
# chegou a API.
_aceito() {
  local base=$1 rotulo=$2 trecho=$3
  assert_diferente "$RECUSADO" "$DBX_ESTADO" "$rotulo: nao recusado; erro: $DBX_ERRO; estado: $DBX_ESTADO"
  assert_diferente "$CONFIGURACAO" "$DBX_ESTADO" "$rotulo: nao e configuracao; erro: $DBX_ERRO; estado: $DBX_ESTADO"
  assert_arquivo_existe "$base/chamadas" "$rotulo: chegou a rede"
  assert_contem "$trecho" "$(cat "$base/enviado" 2>/dev/null)" "$rotulo: o caminho foi enviado; chamadas: $(cat "$base/chamadas" 2>/dev/null); erro: $DBX_ERRO; estado: $DBX_ESTADO"
}

# ---------------------------------------------------------------------------
# TC-SEC-18..24 — fora da raiz, em todo comando, antes da API (b1, b2, b3, b5)
# ---------------------------------------------------------------------------

teste_sec18_24_fora_da_raiz_e_recusado_em_todo_comando_sem_chamada() {
  local base forma remoto
  base=$(_cenario /raiz)
  for forma in $FORMAS; do
    for remoto in /fora /raizX /raiz2/a /raiz/../fora /raiz/.. /RAIZX/a; do
      _rodar_forma "$base" "$forma" "$remoto"
      _recusado_sem_rede "$base" "$forma [$remoto]"
      assert_contem '/raiz' "$DBX_ERRO" "$forma [$remoto]: o diagnostico nomeia a raiz"
    done
  done
}

teste_sec18_raiz_da_conta_fora_da_raiz_configurada_e_recusada() {
  # `/` e o pai da raiz: fora dela. Inclui `upload` de diretorio para `/`, cujo
  # destino derivado seria `/<nome>`.
  local base forma
  base=$(_cenario /raiz)
  for forma in $FORMAS; do
    [[ $forma == upload_diretorio ]] && continue
    _rodar_forma "$base" "$forma" /
    _recusado_sem_rede "$base" "$forma [/]"
  done
  _rodar "$base" upload "$base/local" /
  _recusado_sem_rede "$base" 'upload de diretorio para /'
}

# ---------------------------------------------------------------------------
# TC-SEC-25..26 — dentro da raiz: por componente, sem caixa, `..` normalizado
# ---------------------------------------------------------------------------

teste_sec25_26_dentro_da_raiz_e_aceito_em_todo_comando() {
  local base forma remoto
  base=$(_cenario /Raiz)
  for forma in $FORMAS; do
    for remoto in /Raiz/a /raiz/a /RAIZ/x/../a; do
      _rodar_forma "$base" "$forma" "$remoto"
      _aceito "$base" "$forma [$remoto]" "/a"
    done
  done
}

teste_sec25_derivado_do_upload_de_diretorio_fica_dentro_da_raiz() {
  local base
  base=$(_cenario /raiz)
  _rodar "$base" upload "$base/local" /raiz/
  _aceito "$base" 'upload de diretorio para /raiz/' '/raiz/local/a.txt'
}

teste_sec25_derivado_do_download_de_pasta_fica_dentro_da_raiz() {
  local base
  base=$(_cenario /raiz)
  : >"$base/pasta"
  _rodar "$base" download /raiz/pasta "$base/baixado"
  assert_igual 0 "$DBX_ESTADO" "pasta recebida pelo sync; erro: $DBX_ERRO; estado: $DBX_ESTADO"
  assert_contem 'list_folder' "$(cat "$base/chamadas")" 'o sync derivado listou'
  assert_contem '/raiz/pasta' "$(cat "$base/enviado")" 'com o caminho derivado'
}

teste_sec26_list_sem_argumento_lista_a_raiz_configurada() {
  local base
  base=$(_cenario /raiz)
  _rodar "$base" list
  assert_igual 0 "$DBX_ESTADO" "list sem argumento; erro: $DBX_ERRO; estado: $DBX_ESTADO"
  assert_contem '"/raiz"' "$(cat "$base/enviado")" 'lista a raiz configurada'
}

# ---------------------------------------------------------------------------
# TC-SEC-27 — raiz `/` (ou vazia): nada muda (b6)
# ---------------------------------------------------------------------------

teste_sec27_raiz_da_conta_nao_recusa_caminho_valido() {
  local base forma raiz
  for raiz in / ''; do
    base=$(_cenario "$raiz")
    for forma in $FORMAS; do
      _rodar_forma "$base" "$forma" /qualquer/a
      _aceito "$base" "raiz [$raiz] $forma" '/qualquer/a'
    done
    _rodar "$base" list /../fora
    _recusado_sem_rede "$base" "raiz [$raiz]: .. acima da conta segue recusado"
    _rodar "$base" info relativo/a
    _recusado_sem_rede "$base" "raiz [$raiz]: relativo segue recusado"
  done
}

teste_sec27_raiz_malformada_na_credencial_falha_fechado() {
  local base forma raiz
  for raiz in raiz /..; do
    base=$(_cenario "$raiz")
    for forma in list info sync_enviar; do
      _rodar_forma "$base" "$forma" /raiz/a
      _recusado_sem_rede "$base" "raiz [$raiz] $forma" "$CONFIGURACAO"
    done
    _rodar "$base" list
    _recusado_sem_rede "$base" "raiz [$raiz] list sem argumento" "$CONFIGURACAO"
  done
}

# ---------------------------------------------------------------------------
# TC-SEC-28..29 — caminho remoto com caractere de controle (F-37)
# ---------------------------------------------------------------------------

teste_sec28_quebra_de_linha_e_recusada_em_todo_comando_sem_chamada() {
  local base forma raiz
  for raiz in /raiz /; do
    base=$(_cenario "$raiz")
    for forma in $FORMAS; do
      _rodar_forma "$base" "$forma" $'/raiz/a\nFORJADA'
      _recusado_sem_rede "$base" "raiz [$raiz] $forma"
      assert_nao_contem $'\nFORJADA' "$DBX_ERRO" "$forma: o byte cru nao sai no diagnostico"
      assert_contem 'controle' "$DBX_ERRO" "$forma: o motivo e nomeado"
    done
  done
}

teste_sec29_demais_bytes_de_controle_sao_recusados() {
  local base forma byte visivel
  base=$(_cenario /raiz)
  for byte in $'\r' $'\t' $'\001' $'\037' $'\177'; do
    printf -v visivel '%q' "$byte"
    for forma in list upload sync_receber; do
      _rodar_forma "$base" "$forma" "/raiz/a${byte}b"
      _recusado_sem_rede "$base" "$forma [$visivel]"
      assert_nao_contem "a${byte}b" "$DBX_ERRO" "$forma: o byte cru nao sai no diagnostico"
    done
  done
}

# ---------------------------------------------------------------------------
# Ciclo 2 (QA-B1B-01, QA-B1B-02)
# ---------------------------------------------------------------------------

teste_sec26_caixa_fora_do_ascii_nao_escapa_em_nenhuma_localidade() {
  # U+0130 vira `i` na glibc sob UTF-8, mas e outra pasta na Dropbox.
  local base loc forma remoto
  base=$(_cenario /Raiz)
  for loc in C C.UTF-8 en_US.UTF-8 tr_TR.UTF-8; do
    [[ $loc == C ]] || locale -a 2>/dev/null | grep -qix -- "${loc/UTF-8/utf8}" || continue
    for forma in delete upload sync_enviar list; do
      for remoto in $'/RAİZ/fora' $'/Raız/fora'; do
        DBX_TESTE_LC=$loc _rodar_forma "$base" "$forma" "$remoto"
        _recusado_sem_rede "$base" "[$loc] $forma"
      done
    done
    DBX_TESTE_LC=$loc _rodar "$base" info /RAIZ/a
    _aceito "$base" "[$loc] caixa ASCII" '/RAIZ/a'
  done
}

teste_sec31_raiz_com_controle_e_list_sem_argumento_sai_3() {
  local base raiz
  for raiz in '/Raiz\n' '/Ra\u001biz'; do
    base=$(_cenario "$raiz")
    _rodar "$base" list
    _recusado_sem_rede "$base" "raiz [$raiz] list sem argumento" "$CONFIGURACAO"
  done
}

harness_executar "$@"
