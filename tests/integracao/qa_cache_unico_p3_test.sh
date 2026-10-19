#!/usr/bin/env bash
# Suite independente do QA Expert — fase 3 (cache unico, skip do upload, segredo).
#
# Porte G: validacao independente sobre os itens afetados, com EXAUSTAO nos tres
# pontos de maior risco — a exclusao do espelhamento (RF-41 inteiro, inclusive
# RF-41(e)), a dispensa do envio no `upload` (RF-60) e a identidade forte do
# arquivo (RF-38(e), RF-61). Os cenarios sao do QA, com massa e duplos proprios;
# nenhum reaproveita caso do Senior Developer.
#
# Precedencia e origem dos dados: cada caso monta o proprio cenario (credencial
# sintetica, duplo de `curl`, arvore local) e encadeia as execucoes que precisa
# dentro dele — a primeira execucao de um caso e o "seeder" das seguintes. A
# limpeza e a da area do executor, ao fim do roteiro.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e escrito literalmente, sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly QA_HASH_FALSO='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'

# _qa_cenario — credencial, duplo de rede e arvore local. Publica BASE.
#
# O duplo registra cada URL em `chamadas`; e por ele, e nao pelo relatorio, que
# os casos afirmam "zero exclusoes" e "nenhuma chamada de rede". Arquivos de
# controle em BASE mudam a resposta:
#   conta_falha           `get_current_account` responde 400
#   listagem              corpo do `list_folder`
#   metadado_codigo/corpo resposta do `get_metadata`
#   alterar_na_consulta   caminho a reescrever DURANTE o `get_metadata`
#   resposta_envio        corpo do `files/upload`
_qa_cenario() {
  BASE=$(mktemp -d "$DBX_TESTES_TMP/qa_p3.XXXXXX")
  mkdir -p "$BASE/config/dbx" "$BASE/bin" "$BASE/local"
  _qa_credencial '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}'
  {
    printf '#!/usr/bin/env bash\nbase=%q\n' "$BASE"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
printf '%s\n' "$conf" >>"$base/opcoes"
saida='' escrever='' anterior='' url=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*)
    if [[ -f $base/conta_falha ]]; then codigo=400; corpo='{"error_summary":"other/"}'
    else corpo='{"account_id":"dbid:QA"}'; fi ;;
  *list_folder*)
    if [[ -f $base/listagem ]]; then corpo=$(cat "$base/listagem")
    else corpo='{"entries":[],"has_more":false}'; fi
    if [[ -f $base/listagem_codigo ]]; then
      codigo=$(cat "$base/listagem_codigo"); corpo='{"error_summary":"internal_error/.."}'
    fi ;;
  *files/get_metadata*)
    if [[ -f $base/alterar_na_consulta ]]; then
      alvo=$(cat "$base/alterar_na_consulta"); antes=$(stat -c %z "$alvo")
      tr a-z A-Z <"$alvo" >"$alvo.qa"; cat "$alvo.qa" >"$alvo"; rm -f "$alvo.qa"
      touch -d @1700000000.250000000 "$alvo"
      while [[ $(stat -c %z "$alvo") == "$antes" ]]; do chmod u+w "$alvo"; done
    fi
    if [[ -f $base/metadado_corpo ]]; then
      codigo=$(cat "$base/metadado_codigo"); corpo=$(cat "$base/metadado_corpo")
    else codigo=409; corpo='{"error_summary":"path/not_found/.."}'; fi ;;
  *files/download*) corpo='conteudo remoto' ;;
  *upload_session/start*) corpo='{"session_id":"S-1"}' ;;
  *upload_session/append_v2*) corpo='{}' ;;
  *files/upload)
    if [[ -f $base/resposta_envio ]]; then corpo=$(cat "$base/resposta_envio")
    else corpo='{"name":"a.txt","rev":"0a1"}'; fi ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$BASE/bin/curl"
  chmod +x "$BASE/bin/curl"
  # RNF-02: sentinelas — qualquer invocacao fica registrada e falha.
  local proibido
  for proibido in sqlite3 python3 python; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s $*" >>%q\nexit 1\n' \
      "$proibido" "$BASE/proibido" >"$BASE/bin/$proibido"
    chmod +x "$BASE/bin/$proibido"
  done
  : >"$BASE/chamadas"
}

_qa_credencial() { # <json>
  printf '%s' "$1" >"$BASE/config/dbx/credencial.json"
  chmod 700 "$BASE/config/dbx"
  chmod 600 "$BASE/config/dbx/credencial.json"
}

# _qa_rodar <argumentos...> — `bin/dbx` com ambiente minimo; retentativas curtas
# para que 5xx e 429 esgotem sem espera longa.
_qa_rodar() {
  SAIDA='' ERRO=''
  env -i PATH="$BASE/bin:$PATH" HOME="$BASE" XDG_CONFIG_HOME="$BASE/config" \
    XDG_STATE_HOME="$BASE/estado" TMPDIR="$DBX_TESTES_TMP" \
    DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
    DBX_HTTP_RETRY_AFTER_TETO_S=1 \
    bash "$DBX_EXEC" "$@" </dev/null >"$BASE/out" 2>"$BASE/err"
  ESTADO=$?
  IFS= read -r -d '' SAIDA <"$BASE/out"
  IFS= read -r -d '' ERRO <"$BASE/err"
  return 0
}

_qa_contar() { _harness_contar "$1" "$BASE/chamadas"; } # <padrao>
_qa_exclusoes() { _qa_contar 'files/delete_v2'; }
_qa_escritas() { _qa_contar 'files/upload\|files/delete_v2\|upload_session\|create_folder'; }
_qa_envios() { _qa_contar 'files/upload$'; }
_qa_consultas() { _qa_contar 'files/get_metadata'; }

_qa_antigo() { # <arquivo> <conteudo>
  printf '%s' "$2" >"$1"
  touch -d '@1700000000.250000000' "$1"
}

_qa_hash() { dbx_hash_conteudo_arquivo "$1"; }

_qa_listagem() { # <entrada...> — corpo do list_folder com as entradas dadas
  local IFS=,
  printf '{"entries":[%s],"has_more":false}' "$*" >"$BASE/listagem"
}

_qa_entrada() { # <caminho> <hash> <tamanho>
  printf '{".tag":"file","path_display":"%s","path_lower":"%s","content_hash":"%s","size":%s,"rev":"0a1"}' \
    "$1" "$1" "$2" "$3"
}

_qa_metadado() { # <codigo> <corpo>
  printf '%s' "$1" >"$BASE/metadado_codigo"
  printf '%s' "$2" >"$BASE/metadado_corpo"
}

_qa_remoto_arquivo() { # <content_hash>
  _qa_metadado 200 "{\".tag\":\"file\",\"name\":\"a.txt\",\"rev\":\"0a1\",\"content_hash\":\"$1\"}"
}

_qa_registros_upload() {
  local -a lista=()
  shopt -s nullglob
  lista=("$BASE/estado/dbx"/upload-*)
  shopt -u nullglob
  printf '%s' "${#lista[@]}"
}

_qa_unico_registro_upload() { # publica REGISTRO com o caminho do unico upload-*
  local -a lista=()
  shopt -s nullglob
  lista=("$BASE/estado/dbx"/upload-*)
  shopt -u nullglob
  [[ ${#lista[@]} -eq 1 ]] || _harness_falhar "esperado um upload-*, obtidos ${#lista[@]}"
  REGISTRO=${lista[0]}
}

# _qa_esperar_tique <arquivo> — ate o relogio de carimbos do nucleo avancar
# alem do `ctime` atual do arquivo. Espera por CONDICAO, sem tempo fixo.
_qa_esperar_tique() {
  local referencia sonda=$1.qa_sonda
  referencia=$(stat -c '%z' -- "$1")
  : >"$sonda"
  while [[ $(stat -c '%z' -- "$sonda") == "$referencia" ]]; do chmod 600 "$sonda"; done
  rm -f -- "$sonda"
}

# _qa_reescrever_mesmo_tamanho <arquivo> — conteudo novo, mesmo tamanho, `mtime`
# restaurado ao valor antigo: so o `ctime` (e o conteudo) denunciam a mudanca.
_qa_reescrever_mesmo_tamanho() {
  _qa_esperar_tique "$1"
  tr '[:lower:]' '[:upper:]' <"$1" >"$1.qa"
  cat "$1.qa" >"$1"
  rm -f -- "$1.qa"
  touch -d '@1700000000.250000000' "$1"
}

_qa_sem_root() {
  [[ $(id -u) -ne 0 ]] || pular 'permissao de diretorio nao se aplica a root'
}

# ===========================================================================
# 1. EXCLUSAO DO ESPELHAMENTO — RF-41 inteiro (exaustao)
# ===========================================================================

teste_qa_exclusao_origem_vazia_sem_conta_nos_dois_sentidos_com_e_sem_confirmar() {
  # RF-41(e), TC-DEL-07, RF-48: matriz sentido x --confirmar, conta falhando.
  _qa_cenario
  : >"$BASE/conta_falha"
  _qa_listagem "$(_qa_entrada /r/um.txt ff 1)" "$(_qa_entrada /r/dois.txt ee 1)"
  local confirmar
  for confirmar in '' --confirmar; do
    : >"$BASE/chamadas"
    # shellcheck disable=SC2086  # o sinalizador opcional some quando vazio
    _qa_rodar --json sync --enviar --origem "$BASE/local" --destino /r --espelhar $confirmar
    assert_igual 0 "$(_qa_escritas)" "enviar [${confirmar:-sem}]: nenhuma escrita remota"
    assert_diferente 0 "$ESTADO" "enviar [${confirmar:-sem}]: saida diferente de 0"
  done
  assert_contem 'conta nao identificada' "$SAIDA" 'com --confirmar, o motivo sai na saida estruturada'

  _qa_listagem
  _qa_antigo "$BASE/local/meu1.txt" 'local um'
  _qa_antigo "$BASE/local/meu2.txt" 'local dois'
  for confirmar in '' --confirmar; do
    # shellcheck disable=SC2086
    _qa_rodar --json sync --receber --origem /r --destino "$BASE/local" --espelhar $confirmar
    assert_arquivo_existe "$BASE/local/meu1.txt" "receber [${confirmar:-sem}]: local intacto"
    assert_arquivo_existe "$BASE/local/meu2.txt" "receber [${confirmar:-sem}]: local intacto"
    assert_diferente 0 "$ESTADO" "receber [${confirmar:-sem}]: saida diferente de 0"
  done
  assert_igual 0 "$(_qa_escritas)" 'receber: nenhuma escrita remota'
}

teste_qa_exclusao_origem_vazia_com_conta_e_memoria_recusa_sem_escrita_nos_dois_sentidos() {
  # RF-41(b): origem vazia com linha de base povoada, com e sem --confirmar.
  _qa_cenario
  _qa_antigo "$BASE/local/a.txt" 'aaaa'
  _qa_antigo "$BASE/local/b.txt" 'bbbb'
  _qa_listagem "$(_qa_entrada /r/a.txt "$(_qa_hash "$BASE/local/a.txt")" 4)" \
    "$(_qa_entrada /r/b.txt "$(_qa_hash "$BASE/local/b.txt")" 4)"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$ESTADO" "semeadura: primeira execucao conclui; diagnostico: $ERRO"
  rm -f -- "$BASE/local/a.txt" "$BASE/local/b.txt"
  # Ciclo 3 do QA: a recusa tambem nao escreve na memoria (conteudo e mtime).
  local confirmar estado_antes
  estado_antes=$(cd "$BASE/estado/dbx" && stat -c '%n %Y %s' -- * && cat -- *)
  for confirmar in '' --confirmar; do
    : >"$BASE/chamadas"
    # shellcheck disable=SC2086
    _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --espelhar $confirmar
    assert_igual 0 "$(_qa_escritas)" "enviar [${confirmar:-sem}]: recusa sem escrita"
    assert_diferente 0 "$ESTADO" "enviar [${confirmar:-sem}]: recusa integral"
    assert_igual "$estado_antes" "$(cd "$BASE/estado/dbx" && stat -c '%n %Y %s' -- * && cat -- *)" \
      "enviar [${confirmar:-sem}]: memoria intacta apos a recusa"
  done

  # Sentido receber: a origem (remota) esvazia e o destino local fica intacto.
  _qa_cenario
  _qa_antigo "$BASE/local/c.txt" 'cccc'
  _qa_listagem "$(_qa_entrada /r/c.txt "$(_qa_hash "$BASE/local/c.txt")" 4)"
  _qa_rodar sync --receber --origem /r --destino "$BASE/local" --espelhar --confirmar
  assert_igual 0 "$ESTADO" "semeadura receber; diagnostico: $ERRO"
  _qa_listagem
  for confirmar in '' --confirmar; do
    # shellcheck disable=SC2086
    _qa_rodar sync --receber --origem /r --destino "$BASE/local" --espelhar $confirmar
    assert_arquivo_existe "$BASE/local/c.txt" "receber [${confirmar:-sem}]: destino local intacto"
    assert_diferente 0 "$ESTADO" "receber [${confirmar:-sem}]: recusa integral"
  done
}

teste_qa_exclusao_origem_ausente_ou_que_nao_e_diretorio_recusa_sem_escrita() {
  # RF-41(b): raiz inexistente, arquivo regular, ligacao pendente; com e sem conta.
  _qa_cenario
  _qa_listagem "$(_qa_entrada /r/x.txt ff 1)"
  printf 'nao sou diretorio' >"$BASE/arquivo_regular"
  ln -s "$BASE/nao_existe" "$BASE/ligacao_pendente"
  local origem conta
  for conta in ok falha; do
    [[ $conta == falha ]] && : >"$BASE/conta_falha"
    for origem in "$BASE/inexistente" "$BASE/arquivo_regular" "$BASE/ligacao_pendente"; do
      : >"$BASE/chamadas"
      _qa_rodar sync --enviar --origem "$origem" --destino /r --espelhar --confirmar
      assert_igual 0 "$(_qa_escritas)" "conta $conta, origem ${origem##*/}: nenhuma escrita"
      assert_diferente 0 "$ESTADO" "conta $conta, origem ${origem##*/}: recusada"
    done
  done
}

teste_qa_exclusao_ponto_de_montagem_ausente_nao_apaga() {
  # RF-41(a)/(b): o ponto de montagem "desce" (fica vazio) ou some entre execucoes.
  _qa_cenario
  mkdir -p "$BASE/montagem"
  _qa_antigo "$BASE/montagem/dado.txt" 'dado'
  _qa_listagem "$(_qa_entrada /r/dado.txt "$(_qa_hash "$BASE/montagem/dado.txt")" 4)"
  _qa_rodar sync --enviar --origem "$BASE/montagem" --destino /r --espelhar --confirmar
  assert_igual 0 "$ESTADO" "semeadura; diagnostico: $ERRO"
  rm -f -- "$BASE/montagem/dado.txt" # desmontado: o diretorio fica vazio
  : >"$BASE/chamadas"
  _qa_rodar sync --enviar --origem "$BASE/montagem" --destino /r --espelhar
  assert_igual 0 "$(_qa_exclusoes)" 'montagem vazia com conta: zero exclusoes'
  assert_diferente 0 "$ESTADO" 'montagem vazia com conta: recusa'
  : >"$BASE/conta_falha"
  _qa_rodar sync --enviar --origem "$BASE/montagem" --destino /r --espelhar --confirmar
  assert_igual 0 "$(_qa_exclusoes)" 'montagem vazia sem conta, com --confirmar: zero exclusoes'
  assert_diferente 0 "$ESTADO" 'montagem vazia sem conta: saida diferente de 0'
  rmdir "$BASE/montagem"
  _qa_rodar sync --enviar --origem "$BASE/montagem" --destino /r --espelhar --confirmar
  assert_igual 0 "$(_qa_exclusoes)" 'ponto de montagem ausente: zero exclusoes'
  assert_diferente 0 "$ESTADO" 'ponto de montagem ausente: recusa'
}

teste_qa_exclusao_travessia_parcial_e_conta_nao_identificada_acumulam_nos_dois_sentidos() {
  # RF-41(a) + RF-41(e): os dois motivos juntos, zero exclusoes, saida != 0.
  _qa_sem_root
  _qa_cenario
  : >"$BASE/conta_falha"
  _qa_antigo "$BASE/local/ok.txt" 'ok'
  mkdir -p "$BASE/local/fechado"
  _qa_antigo "$BASE/local/fechado/x.txt" 'x'
  chmod 000 "$BASE/local/fechado"
  _qa_listagem "$(_qa_entrada /r/orfao.txt ff 1)"
  _qa_rodar --json sync --enviar --origem "$BASE/local" --destino /r --espelhar --confirmar
  chmod 700 "$BASE/local/fechado"
  assert_igual 0 "$(_qa_exclusoes)" 'enviar: zero exclusoes'
  assert_igual 1 "$(_qa_envios)" "enviar: o legivel ainda e enviado; diagnostico: $ERRO"
  assert_contem 'travessia parcial' "$SAIDA" 'enviar: motivo da travessia'
  assert_contem 'conta nao identificada' "$SAIDA" 'enviar: motivo da conta'
  assert_diferente 0 "$ESTADO" 'enviar: saida diferente de 0'

  _qa_listagem "$(_qa_entrada /r/remoto.txt ff 15)"
  chmod 000 "$BASE/local/fechado"
  _qa_rodar --json sync --receber --origem /r --destino "$BASE/local" --espelhar --confirmar
  chmod 700 "$BASE/local/fechado"
  assert_arquivo_existe "$BASE/local/ok.txt" 'receber: so-local intacto'
  assert_arquivo_existe "$BASE/local/fechado/x.txt" 'receber: ramo ilegivel intacto'
  assert_contem 'conta nao identificada' "$SAIDA" 'receber: motivo da conta'
  assert_diferente 0 "$ESTADO" 'receber: saida diferente de 0'
}

teste_qa_exclusao_memoria_descartada_com_origem_vazia_nao_apaga() {
  # RF-41(b) x RF-42 x v2 da memoria: a memoria do par EXISTE (o par conta como
  # visto e a rotina dispensa --confirmar), mas e descartada na carga — formato
  # da versao anterior (toda instalacao existente na primeira execucao apos a
  # atualizacao), truncada ou corrompida. Sem linha de base a guarda de origem
  # vazia nao atua: e a mesma razao que levou ao RF-41(e). Zero exclusoes.
  # Ciclo 2 do QA: tambem com --confirmar (RF-41(f): ele nao reabilita).
  local variante memoria confirmar
  for variante in versao_anterior truncada; do
    for confirmar in '' --confirmar; do
      _qa_semear_descartada "$variante"
      # shellcheck disable=SC2086  # o sinalizador opcional some quando vazio
      _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --espelhar $confirmar
      assert_igual 0 "$(_qa_exclusoes)" \
        "$variante [${confirmar:-sem}]: memoria descartada e origem vazia: zero exclusoes"
      assert_diferente 0 "$ESTADO" "$variante [${confirmar:-sem}]: saida diferente de 0"
    done
  done
}

# _qa_semear_descartada <variante> — par sincronizado com a.txt, memoria trocada
# pela variante descartavel e origem esvaziada (a montagem nao subiu).
_qa_semear_descartada() {
  local memoria
  _qa_cenario
  _qa_antigo "$BASE/local/a.txt" 'aaaa'
  _qa_listagem "$(_qa_entrada /r/a.txt "$(_qa_hash "$BASE/local/a.txt")" 4)"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$ESTADO" "$1: semeadura; diagnostico: $ERRO"
  memoria=$(find "$BASE/estado/dbx" -name 'memoria-*' -print -quit)
  [[ -n $memoria ]] || _harness_falhar "$1: semeadura sem memoria-*"
  case $1 in
    versao_anterior)
      printf '1\0dbid:QA\0%s\0/r\0%s\t4\t1700000000\ta.txt\0' "$BASE/local" \
        "$(_qa_hash "$BASE/local/a.txt")" >"$memoria" ;;
    truncada) printf '2\0dbid:QA\0' >"$memoria" ;;
  esac
  rm -f -- "$BASE/local/a.txt"
  : >"$BASE/chamadas"
}

teste_qa_exclusao_memoria_descartada_com_origem_vazia_segunda_execucao_nao_apaga() {
  # Ciclo 2 do QA: a primeira execucao (origem vazia, travessia completa)
  # regrava a v2 SEM caminhos; a segunda, com a origem ainda vazia, nao pode
  # apagar o destino — senao a correcao so adia a exclusao em massa uma rodada.
  _qa_semear_descartada versao_anterior
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --espelhar
  assert_igual 0 "$(_qa_exclusoes)" 'primeira execucao: zero exclusoes'
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --espelhar
  assert_igual 0 "$(_qa_exclusoes)" 'segunda execucao com a origem ainda vazia: zero exclusoes'
  assert_diferente 0 "$ESTADO" 'segunda execucao: saida diferente de 0'
}

# _qa_semear_memoria — par enviar sincronizado (a.txt), publica MEMORIA.
_qa_semear_memoria() {
  _qa_antigo "$BASE/local/a.txt" 'aaaa'
  _qa_listagem "$(_qa_entrada /r/a.txt "$(_qa_hash "$BASE/local/a.txt")" 4)" \
    "$(_qa_entrada /r/orfao.txt ff 1)"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r
  assert_igual 0 "$ESTADO" "semeadura sem espelho; diagnostico: $ERRO"
  MEMORIA=$(find "$BASE/estado/dbx" -name 'memoria-*' -print -quit)
  [[ -n $MEMORIA ]] || _harness_falhar 'semeadura sem memoria-*'
}

teste_qa_exclusao_memoria_descartada_duas_execucoes_a_segunda_propaga() {
  # RF-41(f), TC-DEL-08, ciclo 2 do QA: variantes de descarte; a primeira
  # execucao nao apaga e regrava v2, a segunda (sem mudanca) apaga e sai 0.
  local variante
  for variante in versao_anterior outra_conta so_nul; do
    _qa_cenario
    _qa_semear_memoria
    case $variante in
      versao_anterior) printf '1\0dbid:QA\0x\0/r\0' >"$MEMORIA" ;;
      outra_conta) printf '2\0dbid:OUTRA\0%s\0/r\0' "$(cd -P "$BASE/local" && pwd -P)" >"$MEMORIA" ;;
      so_nul) printf '\0\0\0\0\0\0' >"$MEMORIA" ;;
    esac
    : >"$BASE/chamadas"
    _qa_rodar --json sync --enviar --origem "$BASE/local" --destino /r --espelhar
    assert_igual 0 "$(_qa_exclusoes)" "$variante: primeira execucao nao apaga"
    assert_contem 'memoria descartada' "$SAIDA" "$variante: motivo na saida estruturada"
    assert_diferente 0 "$ESTADO" "$variante: primeira execucao sai diferente de 0"
    assert_igual '2' "$(head -c 1 "$MEMORIA")" "$variante: memoria regravada em v2"
    _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --espelhar
    assert_igual 1 "$(_qa_exclusoes)" "$variante: a segunda propaga a exclusao"
    assert_igual 0 "$ESTADO" "$variante: a segunda sai com 0; diagnostico: $ERRO"
  done
}

teste_qa_exclusao_memoria_ausente_nao_conta_como_descartada() {
  # RF-48 inalterado: sem memoria, pede reconhecimento; com --confirmar e a
  # primeira execucao normal (apaga o orfao e sai 0), sem "memoria descartada".
  _qa_cenario
  _qa_antigo "$BASE/local/a.txt" 'aaaa'
  _qa_listagem "$(_qa_entrada /r/a.txt "$(_qa_hash "$BASE/local/a.txt")" 4)" \
    "$(_qa_entrada /r/orfao.txt ff 1)"
  _qa_rodar --json sync --enviar --origem "$BASE/local" --destino /r --espelhar
  assert_diferente 0 "$ESTADO" 'sem memoria e sem --confirmar: reconhecimento'
  assert_igual 0 "$(_qa_escritas)" 'nenhuma escrita'
  assert_nao_contem 'descartada' "$SAIDA$ERRO" 'memoria ausente nao e descartada'
  _qa_rodar --json sync --enviar --origem "$BASE/local" --destino /r --espelhar --confirmar
  assert_igual 1 "$(_qa_exclusoes)" 'primeira execucao confirmada apaga o orfao'
  assert_igual 0 "$ESTADO" "e sai com 0; diagnostico: $ERRO"
  assert_nao_contem 'descartada' "$SAIDA$ERRO" 'sem motivo de descarte'
}

teste_qa_exclusao_memoria_ilegivel_com_confirmar_nao_apaga() {
  # Memoria que EXISTE mas nao pode ser lida (0000, do proprio usuario):
  # nao ha linha de base; uma rotina com --confirmar e origem vazia nao apaga.
  # Ciclo 3 do QA: tambem com a origem POVOADA (so RF-41(f) protege o orfao;
  # a guarda de origem vazia nao atua), o que mata o mutante M32.
  _qa_sem_root
  _qa_cenario
  _qa_semear_memoria
  chmod 000 "$MEMORIA"
  : >"$BASE/chamadas"
  _qa_rodar --json sync --enviar --origem "$BASE/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$(_qa_exclusoes)" 'memoria ilegivel e origem povoada: o orfao fica'
  assert_contem 'memoria descartada' "$SAIDA" 'ilegivel conta como descartada'
  assert_diferente 0 "$ESTADO" 'origem povoada: saida diferente de 0'
  chmod 000 "$MEMORIA" 2>/dev/null
  rm -f -- "$BASE/local/a.txt"
  : >"$BASE/chamadas"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --espelhar --confirmar
  chmod 600 "$MEMORIA" 2>/dev/null
  assert_igual 0 "$(_qa_exclusoes)" 'memoria ilegivel e origem vazia: zero exclusoes'
  assert_diferente 0 "$ESTADO" 'saida diferente de 0'
}

teste_qa_exclusao_memoria_descartada_com_travessia_parcial_nao_regrava_base_vazia() {
  # RF-41(f): so a travessia COMPLETA regrava. Parcial + descartada nao pode
  # deixar uma v2 sem caminhos, que desarmaria a guarda de RF-41(b) na seguinte.
  # Ciclo 3 do QA: a origem tem tambem um arquivo legivel, para que a guarda de
  # origem vazia nao recuse a execucao parcial e a regravacao seja de fato
  # posta a prova (mata o mutante M31).
  _qa_sem_root
  _qa_cenario
  mkdir -p "$BASE/local/fechado"
  _qa_antigo "$BASE/local/fechado/x.txt" 'xxxx'
  _qa_antigo "$BASE/local/ok.txt" 'okok'
  _qa_listagem "$(_qa_entrada /r/fechado/x.txt "$(_qa_hash "$BASE/local/fechado/x.txt")" 4)" \
    "$(_qa_entrada /r/ok.txt "$(_qa_hash "$BASE/local/ok.txt")" 4)"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r
  MEMORIA=$(find "$BASE/estado/dbx" -name 'memoria-*' -print -quit)
  [[ -n $MEMORIA ]] || _harness_falhar 'semeadura sem memoria-*'
  printf '1\0dbid:QA\0x\0/r\0' >"$MEMORIA"
  chmod 000 "$BASE/local/fechado"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --espelhar
  chmod 700 "$BASE/local/fechado"
  assert_igual 0 "$(_qa_exclusoes)" 'parcial e descartada: zero exclusoes'
  assert_igual '1' "$(head -c 1 "$MEMORIA")" 'travessia parcial nao regrava a memoria descartada'
  rm -rf -- "$BASE/local/fechado" "$BASE/local/ok.txt" # a origem fica vazia (montagem caiu)
  : >"$BASE/chamadas"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --espelhar
  assert_igual 0 "$(_qa_exclusoes)" 'execucao seguinte com origem vazia: zero exclusoes'
  assert_diferente 0 "$ESTADO" 'e saida diferente de 0'
}

# ---------------------------------------------------------------------------
# Ciclo 3 do QA — guarda de origem vazia SEM memoria (RF-41(b) reescrito,
# RF-53(e), TC-DEL-09..12). Decisao registrada no parecer: "vazia" e "nenhum
# arquivo" — diretorios vazios, temporarios de recebimento (`.dbx-part.`) e
# ligacoes simbolicas (nao percorridas) nao contam como arquivo.
# ---------------------------------------------------------------------------

_qa_sem_escrita_local() { # <rotulo> — o diretorio de estado nem foi criado
  [[ ! -e $BASE/estado/dbx ]] || _harness_falhar "$1: escrita no diretorio de estado antes da recusa"
}

teste_qa_guarda_origem_vazia_sem_memoria_recusa_variantes_de_vazio_no_enviar() {
  local variante
  for variante in nada so_diretorios so_temporarios so_ligacao; do
    _qa_cenario
    _qa_listagem "$(_qa_entrada /r/valioso.txt ff 1)"
    case $variante in
      so_diretorios) mkdir -p "$BASE/local/a/b" "$BASE/local/c" ;;
      so_temporarios) printf 'parcial' >"$BASE/local/.x.txt.dbx-part.Ab12Cd" ;;
      so_ligacao)
        printf 'fora' >"$BASE/fora.txt"
        ln -s "$BASE/fora.txt" "$BASE/local/atalho.txt" ;;
    esac
    _qa_rodar --json sync --enviar --origem "$BASE/local" --destino /r --espelhar --confirmar
    assert_igual 0 "$(_qa_escritas)" "$variante: nenhuma escrita remota"
    assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$ESTADO" "$variante: nao_concluida (14); $ERRO"
    assert_contem 'recusada=origem vazia' "$SAIDA" "$variante: recusa no plano"
    assert_contem 'permitir-origem-vazia' "$ERRO" "$variante: a mensagem nomeia a opcao"
    _qa_sem_escrita_local "$variante"
  done
}

teste_qa_guarda_origem_vazia_no_receber_e_raiz_remota_inexistente() {
  local listagem
  for listagem in vazia so_pastas; do
    _qa_cenario
    _qa_antigo "$BASE/local/meu.txt" 'meu'
    case $listagem in
      vazia) _qa_listagem ;;
      so_pastas) _qa_listagem '{".tag":"folder","path_display":"/r/p","path_lower":"/r/p"}' ;;
    esac
    _qa_rodar --json sync --receber --origem /r --destino "$BASE/local" --espelhar --confirmar
    assert_arquivo_existe "$BASE/local/meu.txt" "$listagem: destino local intacto"
    assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$ESTADO" "$listagem: recusa 14; $ERRO"
    assert_contem 'origem esta vazia' "$ERRO" "$listagem: a mensagem nomeia a origem vazia"
    assert_contem 'permitir-origem-vazia' "$ERRO" "$listagem: e a opcao"
    assert_igual 0 "$(_qa_escritas)" "$listagem: nenhuma escrita remota"
    _qa_sem_escrita_local "$listagem"
  done
  # Raiz remota inexistente: a enumeracao falha (nao e "vazia") e nada e apagado.
  _qa_cenario
  _qa_antigo "$BASE/local/meu.txt" 'meu'
  printf '409' >"$BASE/listagem_codigo"
  printf '{"error_summary":"path/not_found/.."}' >"$BASE/listagem"
  _qa_rodar sync --receber --origem /r --destino "$BASE/local" --espelhar --confirmar --permitir-origem-vazia
  assert_arquivo_existe "$BASE/local/meu.txt" 'raiz remota inexistente: destino local intacto'
  assert_diferente 0 "$ESTADO" 'raiz remota inexistente: saida diferente de 0'
}

teste_qa_guarda_permitir_origem_vazia_combinacoes() {
  # RF-53(e): sem --espelhar, sem efeito; em --dry-run lista as exclusoes; com
  # --confirmar na primeira execucao, apaga; RF-41(e) continua valendo.
  _qa_cenario
  _qa_listagem "$(_qa_entrada /r/um.txt ff 1)" "$(_qa_entrada /r/dois.txt ee 1)"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --permitir-origem-vazia
  assert_igual 0 "$ESTADO" "sem --espelhar: sem efeito, conclui; diagnostico: $ERRO"
  assert_igual 0 "$(_qa_escritas)" 'sem --espelhar: nada apagado'

  _qa_rodar --json --dry-run sync --enviar --origem "$BASE/local" --destino /r --espelhar
  assert_igual 0 "$ESTADO" "dry-run sem a opcao sai 0; diagnostico: $ERRO"
  assert_contem 'recusaria=origem vazia' "$SAIDA" 'dry-run anuncia a recusa'
  assert_nao_contem $'\napagar=' "$SAIDA" 'dry-run sem a opcao nao lista exclusao'

  _qa_rodar --json --dry-run sync --enviar --origem "$BASE/local" --destino /r --espelhar --permitir-origem-vazia
  assert_igual 0 "$ESTADO" "dry-run com a opcao sai 0; diagnostico: $ERRO"
  assert_contem $'\napagar=um.txt' "$SAIDA" 'dry-run com a opcao lista as exclusoes'
  assert_nao_contem 'recusaria' "$SAIDA" 'e nao anuncia recusa'
  assert_igual 0 "$(_qa_escritas)" 'dry-run: nenhuma escrita'

  : >"$BASE/conta_falha"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --espelhar --confirmar --permitir-origem-vazia
  assert_igual 0 "$(_qa_exclusoes)" 'com a opcao mas sem conta: RF-41(e) continua desabilitando'
  assert_diferente 0 "$ESTADO" 'sem conta: saida diferente de 0'
  rm -f -- "$BASE/conta_falha"

  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r --espelhar --confirmar --permitir-origem-vazia
  assert_igual 2 "$(_qa_exclusoes)" "com --confirmar e a opcao: as exclusoes ocorrem; diagnostico: $ERRO"
  assert_igual 0 "$ESTADO" 'e sai com 0'
}

teste_qa_guarda_origem_vazia_sem_nada_a_apagar_nao_recusa() {
  _qa_cenario
  _qa_rodar --json sync --enviar --origem "$BASE/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$ESTADO" "origem e destino vazios: sem recusa; diagnostico: $ERRO"
  assert_nao_contem 'recusada' "$SAIDA" 'nada a recusar'
}

# ===========================================================================
# 2. DISPENSA DO ENVIO — RF-60 (exaustao)
# ===========================================================================

teste_qa_skip_falha_5xx_429_e_corpo_enganoso_no_metadado_envia() {
  # RF-60(d): falha com tentativas esgotadas nunca dispensa — nem quando o corpo
  # do erro traz o `content_hash` igual ao local.
  _qa_cenario
  local origem="$BASE/local/a.txt" hash codigo esperado=0
  _qa_antigo "$origem" 'conteudo'
  hash=$(_qa_hash "$origem")
  for codigo in 500 503 429; do
    _qa_metadado "$codigo" "{\".tag\":\"file\",\"name\":\"a.txt\",\"content_hash\":\"$hash\"}"
    _qa_rodar upload "$origem" /r/a.txt
    esperado=$((esperado + 1))
    assert_igual 0 "$ESTADO" "$codigo: o comando segue; diagnostico: $ERRO"
    assert_igual "$esperado" "$(_qa_envios)" "$codigo: a falha da consulta leva ao envio"
    assert_nao_contem 'dispensado' "$SAIDA" "$codigo: nada dispensado"
  done
  assert_igual 6 "$(_qa_consultas)" 'tentativas esgotadas: duas consultas por execucao'
}

teste_qa_skip_remoto_pasta_ou_hash_malformado_nao_dispensa() {
  # RF-60(e) e resposta ilegivel: pasta COM content_hash igual, hash em caixa
  # alta, hash curto, `.tag` ausente.
  _qa_cenario
  local origem="$BASE/local/a.txt" hash corpo esperado=0
  _qa_antigo "$origem" 'conteudo'
  hash=$(_qa_hash "$origem")
  local -a corpos=(
    "{\".tag\":\"folder\",\"name\":\"a.txt\",\"content_hash\":\"$hash\"}"
    "{\".tag\":\"file\",\"name\":\"a.txt\",\"content_hash\":\"${hash:0:63}\"}"
    "{\"name\":\"a.txt\",\"content_hash\":\"$hash\"}"
    "{\".tag\":\"deleted\",\"name\":\"a.txt\",\"content_hash\":\"$hash\"}"
  )
  for corpo in "${corpos[@]}"; do
    _qa_metadado 200 "$corpo"
    _qa_rodar upload "$origem" /r/a.txt
    esperado=$((esperado + 1))
    assert_igual "$esperado" "$(_qa_envios)" "envia para: $corpo"
  done
}

teste_qa_skip_cache_envenenado_nao_leva_a_dispensa_indevida() {
  # RF-60(f): registro com hash falso e a MESMA identidade; registro de outra
  # chave copiado para esta. Nenhum dispensa quando o remoto difere do real.
  _qa_cenario
  local origem="$BASE/local/a.txt" outra="$BASE/local/b.txt" real conteudo
  _qa_antigo "$origem" 'conteudo real'
  real=$(_qa_hash "$origem")
  _qa_remoto_arquivo "$real"
  _qa_rodar upload "$origem" /r/a.txt
  assert_contem 'dispensado' "$SAIDA" 'semeadura: hash igual dispensa e grava o cache'
  _qa_unico_registro_upload
  # Envenena: troca o resumo guardado pelo falso, mantendo a identidade.
  IFS= read -r -d '' conteudo < <(tr '\0' '\n' <"$REGISTRO")
  local identidade=${conteudo##*$'\t'}
  identidade=${identidade%$'\n'}
  printf '2\0upload\0%s\0%s\t%s\0' "$(cd -P "$BASE/local" && pwd -P)/a.txt" "$QA_HASH_FALSO" \
    "$identidade" >"$REGISTRO"
  # Remoto = conteudo real: o cache falso nao pode decidir nem "igual" nem "dispensa".
  _qa_rodar --progresso upload "$origem" /r/a.txt
  assert_contem 'resumo local em cache' "$ERRO" 'o registro envenenado foi de fato lido'
  assert_igual 1 "$(_qa_envios)" 'hash falso diferente do remoto: envia (nunca dispensa indevida)'
  # Registro de b.txt copiado para o nome do de a.txt: chave divergente, descartado.
  _qa_antigo "$outra" 'conteudo real'
  _qa_rodar upload "$outra" /r/b.txt
  local -a lista=()
  shopt -s nullglob
  lista=("$BASE/estado/dbx"/upload-*)
  shopt -u nullglob
  local registro_b
  for registro_b in "${lista[@]}"; do [[ $registro_b != "$REGISTRO" ]] && break; done
  cp -- "$registro_b" "$REGISTRO"
  _qa_metadado 200 "{\".tag\":\"file\",\"name\":\"a.txt\",\"content_hash\":\"$QA_HASH_FALSO\"}"
  _qa_rodar --progresso upload "$origem" /r/a.txt
  assert_contem 'calculando resumo local' "$ERRO" 'registro de outra chave nao e aceito'
  assert_igual 2 "$(_qa_envios)" 'e o envio ocorre'
}

teste_qa_skip_forcar_rev_e_entrada_padrao_ignoram_cache_valido() {
  # RF-60(g), (h), (i) COM cache valido e remoto igual: nenhuma consulta.
  _qa_cenario
  local origem="$BASE/local/a.txt"
  _qa_antigo "$origem" 'conteudo'
  _qa_remoto_arquivo "$(_qa_hash "$origem")"
  _qa_rodar upload "$origem" /r/a.txt
  assert_igual 1 "$(_qa_registros_upload)" 'semeadura: cache valido'
  : >"$BASE/chamadas"
  _qa_rodar upload --forcar "$origem" /r/a.txt
  assert_igual 0 "$(_qa_consultas)" '--forcar: sem consulta'
  assert_igual 1 "$(_qa_envios)" '--forcar: envia'
  _qa_rodar upload --rev 0a1 "$origem" /r/a.txt
  assert_igual 0 "$(_qa_consultas)" '--rev: sem consulta'
  assert_igual 2 "$(_qa_envios)" '--rev: envia'
  assert_contem 'update' "$(cat "$BASE/opcoes")" '--rev: em modo update'
  : >"$BASE/chamadas"
  SAIDA=''
  env -i PATH="$BASE/bin:$PATH" HOME="$BASE" XDG_CONFIG_HOME="$BASE/config" \
    XDG_STATE_HOME="$BASE/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash "$DBX_EXEC" upload - /r/a.txt <"$origem" >"$BASE/out" 2>"$BASE/err"
  assert_igual 0 "$(_qa_consultas)" 'entrada padrao: sem consulta'
  assert_igual 1 "$(_qa_registros_upload)" 'entrada padrao: nenhum registro novo'
}

# ===========================================================================
# 3. IDENTIDADE FORTE — RF-38(e), RF-61(b) a (d) (exaustao)
# ===========================================================================

# _qa_semear_upload <conteudo> — origem antiga, remoto igual, cache gravado.
_qa_semear_upload() {
  ORIGEM="$BASE/local/a.txt"
  _qa_antigo "$ORIGEM" "$1"
  HASH_ANTIGO=$(_qa_hash "$ORIGEM")
  _qa_remoto_arquivo "$HASH_ANTIGO"
  _qa_rodar upload "$ORIGEM" /r/a.txt
  assert_contem 'dispensado' "$SAIDA" "semeadura: dispensa; diagnostico: $ERRO"
  assert_igual 1 "$(_qa_registros_upload)" 'semeadura: cache gravado'
}

teste_qa_identidade_mtime_restaurado_por_touch_envia() {
  # RF-61(b): mesmo tamanho, mesmo `mtime` (touch -d), remoto = conteudo antigo.
  _qa_cenario
  _qa_semear_upload 'abcdef'
  _qa_reescrever_mesmo_tamanho "$ORIGEM"
  _qa_rodar upload "$ORIGEM" /r/a.txt
  assert_igual 1 "$(_qa_envios)" 'conteudo mudou sob identidade de mtime e tamanho: envia'
}

teste_qa_identidade_troca_de_inode_por_mv_envia() {
  _qa_cenario
  _qa_semear_upload 'abcdef'
  printf 'ABCDEF' >"$BASE/local/novo"
  touch -d '@1700000000.250000000' "$BASE/local/novo"
  mv -f -- "$BASE/local/novo" "$ORIGEM"
  _qa_rodar upload "$ORIGEM" /r/a.txt
  assert_igual 1 "$(_qa_envios)" 'inode trocado com mesmo tamanho e mtime: envia'
}

teste_qa_identidade_hardlink_alterado_pelo_outro_nome_envia_e_tem_registro_proprio() {
  # RF-61(b) e RF-62(a): ligacao fisica e outra chave; escrita por ela muda o inode comum.
  _qa_cenario
  _qa_semear_upload 'abcdef'
  ln -- "$ORIGEM" "$BASE/local/fisica.txt"
  _qa_reescrever_mesmo_tamanho "$BASE/local/fisica.txt"
  _qa_rodar upload "$ORIGEM" /r/a.txt
  assert_igual 1 "$(_qa_envios)" 'alterado pela ligacao fisica: envia'
  _qa_remoto_arquivo "$(_qa_hash "$ORIGEM")"
  _qa_rodar upload "$BASE/local/fisica.txt" /r/a.txt
  assert_igual 2 "$(_qa_registros_upload)" 'ligacao fisica gera registro proprio'
}

teste_qa_identidade_arquivo_alterado_entre_o_stat_e_o_resumo_nao_grava() {
  # RF-61(c): a origem muda depois da primeira leitura de `stat` e antes do
  # calculo (durante o `get_metadata`). Decide pelo conteudo novo e nao grava.
  _qa_cenario
  local origem="$BASE/local/a.txt"
  _qa_antigo "$origem" 'abcdef'
  _qa_remoto_arquivo "$(_qa_hash "$origem")"
  printf '%s' "$origem" >"$BASE/alterar_na_consulta"
  printf 'ABCDEF' >"$BASE/conteudo_novo"
  printf '{"name":"a.txt","rev":"0a2","content_hash":"%s"}' \
    "$(_qa_hash "$BASE/conteudo_novo")" >"$BASE/resposta_envio"
  _qa_esperar_tique "$origem"
  _qa_rodar upload "$origem" /r/a.txt
  assert_igual 'ABCDEF' "$(cat "$origem")" 'o duplo alterou a origem durante a consulta'
  assert_igual 1 "$(_qa_envios)" 'conteudo novo difere do remoto: envia'
  assert_igual 0 "$(_qa_registros_upload)" 'stat antes e depois divergentes: nada gravado'
}

teste_qa_identidade_janela_de_dois_segundos_no_upload() {
  # RF-61(d): `mtime` no futuro e no instante atual nao gravam; 5 s atras grava.
  _qa_cenario
  local origem="$BASE/local/a.txt" agora
  printf 'conteudo' >"$origem"
  printf -v agora '%(%s)T' -1
  _qa_remoto_arquivo "$(_qa_hash "$origem")"
  touch -d "@$((agora + 3600))" "$origem"
  _qa_rodar upload "$origem" /r/a.txt
  assert_igual 0 "$(_qa_registros_upload)" 'mtime no futuro: nao grava'
  touch -d "@$agora" "$origem"
  _qa_rodar upload "$origem" /r/a.txt
  assert_igual 0 "$(_qa_registros_upload)" 'mtime agora: nao grava'
  touch -d "@$((agora - 5))" "$origem"
  _qa_rodar upload "$origem" /r/a.txt
  assert_igual 1 "$(_qa_registros_upload)" 'mtime ha 5 s: grava'
}

teste_qa_identidade_sync_envia_arquivo_com_mtime_restaurado() {
  # RF-38(e): o `sync` nao reaproveita resumo de identidade que mudou.
  _qa_cenario
  _qa_antigo "$BASE/local/a.txt" 'abcdef'
  _qa_listagem "$(_qa_entrada /r/a.txt "$(_qa_hash "$BASE/local/a.txt")" 6)"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r
  assert_igual 0 "$(_qa_envios)" "semeadura: identico; diagnostico: $ERRO"
  _qa_reescrever_mesmo_tamanho "$BASE/local/a.txt"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r
  assert_igual 1 "$(_qa_envios)" 'reescrita com mtime restaurado: o sync envia'
}

# ===========================================================================
# 4. ESTADO E DIRETORIO (RNF-25), PODA (RF-61(i)), LEGADO (RNF-33), DEPENDENCIAS
# ===========================================================================

teste_qa_estado_0755_corrigido_por_upload_e_sync_com_legado_intacto() {
  # RNF-25(b1), RNF-33(b), RNF-02(c).
  _qa_cenario
  mkdir -p "$BASE/estado/dbx"
  chmod 755 "$BASE/estado/dbx"
  local legado antes depois
  for legado in dbx.db dbx.db-wal dbx.db-shm; do
    printf 'legado %s /home/u/segredo.txt' "$legado" >"$BASE/estado/dbx/$legado"
    touch -d '@1600000000' "$BASE/estado/dbx/$legado"
  done
  antes=$(cd "$BASE/estado/dbx" && stat -c '%n %s %Y %i' dbx.db* && cat dbx.db*)
  _qa_antigo "$BASE/local/a.txt" 'aaaa'
  _qa_remoto_arquivo "$(_qa_hash "$BASE/local/a.txt")"
  _qa_rodar upload "$BASE/local/a.txt" /r/a.txt
  assert_igual 700 "$(stat -c '%a' "$BASE/estado/dbx")" 'upload corrige 0755 para 0700'
  chmod 755 "$BASE/estado/dbx"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r
  assert_igual 0 "$ESTADO" "sync conclui; diagnostico: $ERRO"
  assert_igual 700 "$(stat -c '%a' "$BASE/estado/dbx")" 'sync corrige 0755 para 0700'
  depois=$(cd "$BASE/estado/dbx" && stat -c '%n %s %Y %i' dbx.db* && cat dbx.db*)
  assert_igual "$antes" "$depois" 'dbx.db* intactos'
  assert_arquivo_ausente "$BASE/proibido" 'nenhuma invocacao de sqlite3/python'
  local estranho
  estranho=$(cd "$BASE/estado/dbx" && find . -mindepth 1 ! -name 'memoria-*' ! -name 'upload-*' ! -name 'dbx.db*')
  assert_igual '' "$estranho" 'RNF-26: so memoria-*, upload-* e o legado'
}

teste_qa_estado_diretorio_alheio_gravavel_nao_recebe_nada() {
  # RNF-25(b1): `dbx` aponta para diretorio de outro dono e GRAVAVEL (/tmp, 1777).
  _qa_sem_root
  [[ -d /tmp && ! -O /tmp && -w /tmp ]] || pular '/tmp nao e diretorio alheio gravavel aqui'
  _qa_cenario
  mkdir -p "$BASE/estado"
  ln -s /tmp "$BASE/estado/dbx"
  local modo_antes
  modo_antes=$(stat -c '%a' /tmp)
  _qa_antigo "$BASE/local/qa-p3-alheio-$$.txt" 'aaaa'
  _qa_remoto_arquivo "$(_qa_hash "$BASE/local/qa-p3-alheio-$$.txt")"
  _qa_rodar upload "$BASE/local/qa-p3-alheio-$$.txt" /r/a.txt
  assert_igual 0 "$ESTADO" "o upload conclui; diagnostico: $ERRO"
  assert_igual "$modo_antes" "$(stat -c '%a' /tmp)" 'modo do diretorio alheio intacto'
  local -a criados=()
  mapfile -t criados < <(find /tmp -maxdepth 1 -user "$(id -u)" \( -name 'upload-*' -o -name '.upload.*' \) -newer "$BASE/local" 2>/dev/null)
  assert_igual 0 "${#criados[@]}" "nada gravado no diretorio alheio: ${criados[*]:-}"
}

# _qa_povoar <total> — registros upload-* sinteticos; 5 com 91 dias, 1 com 89.
_qa_povoar() {
  local i nome
  mkdir -p "$BASE/estado/dbx"
  chmod 700 "$BASE/estado/dbx"
  for ((i = 0; i < $1; i++)); do
    printf -v nome '%s/upload-f%031x' "$BASE/estado/dbx" "$i"
    : >"$nome"
  done
  for i in 0 1 2 3 4; do
    printf -v nome '%s/upload-f%031x' "$BASE/estado/dbx" "$i"
    touch -d '91 days ago' "$nome"
  done
  printf -v nome '%s/upload-f%031x' "$BASE/estado/dbx" 5
  touch -d '89 days ago' "$nome"
}

teste_qa_poda_acerto_de_registro_velho_sobrevive_e_so_os_velhos_saem() {
  # RF-61(i): 10.001 sinteticos + o registro real (91 dias): acima do teto.
  _qa_cenario
  _qa_semear_upload 'abcdef'
  _qa_unico_registro_upload
  local real=$REGISTRO
  _qa_povoar 10001
  touch -d '91 days ago' "$real"
  _qa_rodar --progresso upload "$ORIGEM" /r/a.txt
  assert_contem 'resumo local em cache' "$ERRO" 'acerto de cache'
  assert_arquivo_existe "$real" 'o registro acertado e regravado'
  local idade
  printf -v idade '%(%s)T' -1
  idade=$((idade - $(stat -c '%Y' "$real")))
  [[ $idade -lt 120 ]] || _harness_falhar 'o acerto renova o carimbo' "idade: $idade s"
  assert_igual 9997 "$(_qa_registros_upload)" '10.002 - 6 velhos + 1 regravado'
  assert_arquivo_existe "$BASE/estado/dbx/upload-f0000000000000000000000000000005" '89 dias fica'
  assert_arquivo_ausente "$BASE/estado/dbx/upload-f0000000000000000000000000000000" '91 dias sai'
}

teste_qa_poda_no_teto_exato_nao_remove_nem_os_velhos() {
  _qa_cenario
  _qa_semear_upload 'abcdef'
  _qa_povoar 9999
  _qa_rodar upload "$ORIGEM" /r/a.txt
  assert_igual 10000 "$(_qa_registros_upload)" '10.000 registros: nada removido'
  assert_arquivo_existe "$BASE/estado/dbx/upload-f0000000000000000000000000000000" 'velho fica no teto'
}

teste_qa_legado_install_readme_e_codigo_sem_sqlite_nem_python() {
  # RNF-33(a), (c), (d) e RNF-02(a): auditoria estatica independente.
  local achados
  achados=$(grep -n -i 'sqlite\|python' "$DBX_HARNESS_RAIZ/install.sh" || true)
  assert_igual '' "$achados" 'install.sh nao detecta nem recomenda sqlite3/python3'
  achados=$(grep -rn -i 'sqlite\|python\|dbx_db_\|dbx\.db' "$DBX_HARNESS_RAIZ/bin" \
    "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands" | grep -v ':[0-9]*:[[:space:]]*#' || true)
  assert_igual '' "$achados" 'bin/, lib/ e commands/ sem sqlite, python, dbx_db_ ou dbx.db'
  # O README so pode citar SQLite no paragrafo do legado (RNF-33(c)).
  achados=$(grep -n -i 'sqlite' "$DBX_HARNESS_RAIZ/README.md" | grep -v -i 'legado' || true)
  assert_igual '' "$achados" 'README nao anuncia mais o cache SQLite fora do paragrafo do legado'
}

# ===========================================================================
# 5. SEGREDO OBRIGATORIO — RF-63
# ===========================================================================

teste_qa_segredo_ausente_recusa_antes_da_rede_com_o_codigo_de_rf03() {
  # RF-63(a): "mesma classe e codigo de saida de RF-03" — configuracao, 3.
  local credencial comando
  local configuracao
  configuracao=$(dbx_errors_codigo_saida configuracao)
  for credencial in \
    '{"versao":1,"app_key":"ak","refresh_token":"rt","raiz_remota":"/"}' \
    '{"versao":1,"app_key":"ak","app_secret":"","refresh_token":"rt","raiz_remota":"/"}'; do
    _qa_cenario
    _qa_credencial "$credencial"
    _qa_antigo "$BASE/local/a.txt" 'aaaa'
    for comando in upload sync; do
      : >"$BASE/chamadas"
      if [[ $comando == upload ]]; then
        _qa_rodar upload "$BASE/local/a.txt" /r/a.txt
      else
        _qa_rodar sync --enviar --origem "$BASE/local" --destino /r
      fi
      assert_igual 0 "$(_qa_contar .)" "$comando: nenhuma chamada de rede"
      assert_igual "$configuracao" "$ESTADO" \
        "$comando: codigo de saida de RF-03 (configuracao); diagnostico: $ERRO"
      # Campo ausente nem chega a ser carregado (RF-03); campo vazio e carregado
      # e e o caso de RF-63(a): a mensagem nomeia a falta do segredo.
      [[ $credencial == *'"app_secret"'* ]] &&
        assert_contem 'segredo' "$ERRO" "$comando: o motivo nomeia o segredo"
    done
  done
}

teste_qa_segredo_preparo_nao_vaza_e_nao_incide_onde_nao_ha_rede() {
  # `dbx_auth_preparar` (ciclo 3): nenhum valor de credencial no diagnostico;
  # simulacao de upload nao escreve (desde a fase 1 do backlog, so renova, le
  # o content_hash remoto e consulta o espaco); o preparo nao duplica a
  # renovacao.
  _qa_cenario
  _qa_credencial '{"versao":1,"app_key":"ak_qa_p3","app_secret":"","refresh_token":"RT_QA_P3_SENTINELA","raiz_remota":"/"}'
  _qa_antigo "$BASE/local/a.txt" 'aaaa'
  local comando
  for comando in upload sync; do
    if [[ $comando == upload ]]; then
      _qa_rodar upload "$BASE/local/a.txt" /r/a.txt
    else
      _qa_rodar sync --enviar --origem "$BASE/local" --destino /r
    fi
    assert_nao_contem 'RT_QA_P3_SENTINELA' "$SAIDA$ERRO" "$comando: refresh token fora da saida"
    assert_nao_contem 'ak_qa_p3' "$SAIDA$ERRO" "$comando: app key fora da saida"
  done
  _qa_credencial '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}'
  : >"$BASE/chamadas"
  _qa_rodar --dry-run upload "$BASE/local/a.txt" /r/a.txt
  assert_igual 0 "$ESTADO" "simulacao conclui; diagnostico: $ERRO"
  # RF-15/RF-44 (v1.10) e RF-67(f): simulacao proibe ESCRITA; leituras sao
  # permitidas. Decisao do Tech Lead (O-3, fase 1): a simulacao do upload le o
  # `content_hash` remoto antes da checagem de espaco, na ordem da execucao
  # real. Revisao do QA: o conjunto de leituras fica FECHADO, cada uma com
  # contagem exata (o preparo nao duplica a renovacao), e nada mais.
  assert_igual 0 "$(_qa_escritas)" 'simulacao de upload: nenhuma chamada de escrita'
  assert_igual 1 "$(_qa_contar 'oauth2/token')" 'simulacao de upload: uma unica renovacao'
  assert_igual 1 "$(_qa_contar 'files/get_metadata')" 'simulacao de upload: uma leitura do content_hash remoto'
  assert_igual 1 "$(_qa_contar 'get_space_usage')" 'simulacao de upload: uma consulta de espaco (RF-67(f))'
  assert_igual 3 "$(_qa_contar .)" 'simulacao de upload: nenhuma chamada alem das tres leituras'
  _qa_remoto_arquivo "$(_qa_hash "$BASE/local/a.txt")"
  # A simulacao agora renova o token para consultar o espaco: a contagem do
  # upload real comeca do zero.
  : >"$BASE/chamadas"
  _qa_rodar upload "$BASE/local/a.txt" /r/a.txt
  assert_igual 1 "$(_qa_contar 'oauth2/token')" 'upload real: uma unica renovacao'
}

# ===========================================================================
# 6. P3.4 — codigo de saida e politica sem regressao (lib/http, lib/errors)
# ===========================================================================

teste_qa_p34_falha_de_rede_nao_vira_sucesso_no_upload_nem_no_sync() {
  # Uma falha que esgota as tentativas sai com o codigo da classe, nunca 0.
  _qa_cenario
  _qa_antigo "$BASE/local/a.txt" 'aaaa'
  printf '500' >"$BASE/listagem_codigo"
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida erro_remoto)" "$ESTADO" \
    "sync: enumeracao remota com 5xx esgotado sai com erro_remoto; diagnostico: $ERRO"
  assert_igual 0 "$(_qa_envios)" 'sync: nada enviado sem a listagem remota'
  # Segredo vazio na credencial: a renovacao e recusada antes da rede (RF-63);
  # o comando nao pode terminar com sucesso.
  rm -f -- "$BASE/listagem_codigo"
  _qa_credencial '{"versao":1,"app_key":"ak","app_secret":"","refresh_token":"rt","raiz_remota":"/"}'
  _qa_rodar sync --enviar --origem "$BASE/local" --destino /r
  assert_diferente 0 "$ESTADO" "sync com segredo vazio nao sai com sucesso; diagnostico: $ERRO"
}

harness_executar "$@"
