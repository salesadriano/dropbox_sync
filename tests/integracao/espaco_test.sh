#!/usr/bin/env bash
# Testes ponta a ponta da checagem previa de espaco (RF-67, TC-ESP-01..10).
#
# O que importa provar, alem da conta, e a ORDEM: a recusa vem antes de
# qualquer escrita (nenhum envio, nenhuma sessao, nenhuma exclusao do
# `--espelhar`, nenhuma memoria gravada), e uma unica consulta por execucao.
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly OUTRO=0000000000000000000000000000000000000000000000000000000000000000

# _cenario <usado> <alocado> — credencial, duplo de rede e arvore local.
_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/espaco.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '{"used":%s,"allocation":{".tag":"individual","allocated":%s}}' "${1:-0}" "${2:-1000000}" \
    >"$base/espaco"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  cat >"$base/bin/curl" <<FIM
#!/usr/bin/env bash
base=$base
FIM
  cat >>"$base/bin/curl" <<'FIM'
cat >/dev/null 2>&1
saida=""; escrever=""; anterior=""; url=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_space_usage*) corpo=$(cat "$base/espaco") ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *get_metadata*) codigo=409; corpo='{"error_summary":"path/not_found/"}' ;;
  *list_folder*) corpo=$(cat "$base/listagem") ;;
  *upload_session/start*) corpo='{"session_id":"S-1"}' ;;
  *) corpo='{"name":"x","rev":"1","size":1}' ;;
esac
if [[ $url == *get_metadata* && -f $base/metadata ]]; then
  codigo=200; corpo=$(cat "$base/metadata")
fi
if [[ $url == *get_space_usage* && -f $base/espaco_codigo ]]; then
  codigo=$(cat "$base/espaco_codigo")
fi
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
  rm -f "$base/chamadas"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 \
    bash "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  DBX_SAIDA=''
  DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_rodar_com_fluxo() { # <base> <arquivo_de_entrada> <argumentos...>
  local base=$1 entrada=$2
  shift 2
  rm -f "$base/chamadas"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 \
    bash "$DBX_EXEC" "$@" <"$entrada" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  return 0
}

_consultas() { _harness_contar 'get_space_usage' "$1/chamadas"; }
_envios() { _harness_contar 'files/upload\|upload_session' "$1/chamadas"; }
_exclusoes() { _harness_contar 'files/delete' "$1/chamadas"; }

_bytes() { # <arquivo> <quantidade>
  head -c "$2" /dev/zero | tr '\0' 'a' >"$1"
}

_resumo_de() { # <arquivo>
  bash -c ". '$DBX_HARNESS_RAIZ/lib/errors.sh'; . '$DBX_HARNESS_RAIZ/lib/hash.sh'; dbx_hash_conteudo_arquivo '$1'"
}

_entrada() { # <caminho> <hash> <tamanho>
  printf '{".tag":"file","path_display":"%s","content_hash":"%s","size":%s,"rev":"r1"}' "$1" "$2" "$3"
}

_listagem() { # <entradas...>
  local IFS=,
  printf '{"entries":[%s],"has_more":false}' "$*"
}

# ---------------------------------------------------------------------------
# TC-ESP-01 — upload
# ---------------------------------------------------------------------------

teste_esp01_upload_maior_que_a_folga_e_recusado_sem_nenhuma_escrita() {
  local base
  base=$(_cenario 300 1000)
  _bytes "$base/local/a.bin" 701
  _rodar "$base" upload "$base/local/a.bin" /r/a.bin
  assert_igual "$(dbx_errors_codigo_saida espaco)" "$DBX_ESTADO" 'nao cabe: 12'
  assert_igual 0 "$(_envios "$base")" 'nenhum envio, nenhuma sessao'
  assert_contem 'necessario 701 bytes' "$DBX_ERRO" 'total necessario'
  assert_contem 'livre 700 bytes' "$DBX_ERRO" 'folga'
  assert_contem 'faltam 1 bytes' "$DBX_ERRO" 'diferenca'
  assert_contem '--forcar' "$DBX_ERRO" 'a saida e nomeada'
  _bytes "$base/local/b.bin" 700
  _rodar "$base" upload "$base/local/b.bin" /r/b.bin
  assert_igual 0 "$DBX_ESTADO" "igual a folga cabe; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_envios "$base")" 'o envio sai'
  assert_igual 1 "$(_consultas "$base")" 'uma consulta'
}

# ---------------------------------------------------------------------------
# TC-ESP-02, TC-ESP-03, TC-ESP-04 — sync --enviar
# ---------------------------------------------------------------------------

teste_esp02_sync_que_nao_cabe_recusa_antes_da_primeira_acao() {
  local base
  base=$(_cenario 0 100)
  _bytes "$base/local/a.bin" 80
  _bytes "$base/local/b.bin" 80
  _listagem "$(_entrada /r/sobra.bin "$OUTRO" 5)" >"$base/listagem"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual "$(dbx_errors_codigo_saida espaco)" "$DBX_ESTADO" 'nao cabe: 12'
  assert_igual 0 "$(_envios "$base")" 'nenhum envio'
  assert_igual 0 "$(_exclusoes "$base")" 'nem a exclusao do --espelhar'
  assert_arquivo_ausente "$base/estado/dbx" 'nenhuma memoria gravada'
  assert_contem 'necessario 160 bytes' "$DBX_ERRO" 'o total do plano'
}

teste_esp03_soma_so_a_parte_transferir_e_consulta_uma_vez() {
  local base
  base=$(_cenario 0 60)
  _bytes "$base/local/igual.bin" 100
  _bytes "$base/local/novo.bin" 50
  _listagem "$(_entrada /r/igual.bin "$(_resumo_de "$base/local/igual.bin")" 100)" \
    "$(_entrada /r/sobra.bin "$OUTRO" 500)" >"$base/listagem"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "omitidos e exclusoes nao contam: 50 cabe em 60; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_consultas "$base")" 'uma unica consulta por execucao'
  rm -f "$base/local/novo.bin"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$(_consultas "$base")" 'nada a enviar: nenhuma consulta'
}

teste_esp04_sobrescrita_conta_o_arquivo_novo_inteiro() {
  local base
  base=$(_cenario 0 50)
  _bytes "$base/local/a.bin" 100
  _listagem "$(_entrada /r/a.bin "$OUTRO" 90)" >"$base/listagem"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida espaco)" "$DBX_ESTADO" \
    'so caberia pela diferenca (10): recusado'
  assert_contem 'necessario 100 bytes' "$DBX_ERRO" 'o total e o arquivo novo inteiro'
}

# ---------------------------------------------------------------------------
# TC-ESP-05 — --forcar e --force
# ---------------------------------------------------------------------------

teste_esp05_forcar_pula_a_checagem_no_upload_e_no_sync() {
  local base opcao
  base=$(_cenario 1000 1000)
  _bytes "$base/local/a.bin" 10
  for opcao in --forcar --force; do
    _rodar "$base" upload "$opcao" "$base/local/a.bin" /r/a.bin
    assert_igual 0 "$DBX_ESTADO" "upload $opcao envia; diagnostico: $DBX_ERRO"
    assert_igual 0 "$(_consultas "$base")" "upload $opcao: zero consultas"
    _rodar "$base" sync --enviar "$opcao" --origem "$base/local" --destino /r
    assert_igual 0 "$DBX_ESTADO" "sync $opcao envia; diagnostico: $DBX_ERRO"
    assert_igual 0 "$(_consultas "$base")" "sync $opcao: zero consultas"
    assert_igual 1 "$(_envios "$base")" "sync $opcao: o envio sai"
  done
}

teste_esp05_forcar_no_sync_nao_muda_a_decisao_por_conteudo() {
  local base
  base=$(_cenario 1000 1000)
  _bytes "$base/local/a.bin" 10
  _listagem "$(_entrada /r/a.bin "$(_resumo_de "$base/local/a.bin")" 10)" >"$base/listagem"
  _rodar "$base" sync --enviar --forcar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "identico continua omitido; diagnostico: $DBX_ERRO"
  assert_igual 0 "$(_envios "$base")" 'RF-39: --forcar nao reenvia o identico'
}

teste_esp05_forcar_com_receber_e_uso_invalido() {
  local base opcao
  base=$(_cenario)
  for opcao in --forcar --force; do
    _rodar "$base" sync --receber "$opcao" --origem /r --destino "$base/local"
    assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" "$opcao com --receber: 2"
  done
}

# ---------------------------------------------------------------------------
# TC-ESP-06 — simulacao
# ---------------------------------------------------------------------------

teste_esp06_simulacao_so_avisa_que_recusaria() {
  local base
  base=$(_cenario 0 10)
  _bytes "$base/local/a.bin" 20
  _rodar "$base" --dry-run upload "$base/local/a.bin" /r/a.bin
  assert_igual 0 "$DBX_ESTADO" "simulacao sai com 0; diagnostico: $DBX_ERRO"
  assert_contem 'recusaria=' "$DBX_SAIDA" 'o plano anuncia a recusa'
  assert_contem 'necessario 20 bytes, livre 10 bytes' "$DBX_SAIDA" 'com total e folga'
  assert_igual 0 "$(_envios "$base")" 'nenhum envio'
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "simulacao do sync sai com 0; diagnostico: $DBX_ERRO"
  assert_contem 'recusaria=' "$DBX_SAIDA" 'o plano do sync anuncia a recusa'
  assert_contem 'necessario 20 bytes, livre 10 bytes' "$DBX_SAIDA" 'com total e folga'
  assert_igual 0 "$(_envios "$base")" 'nenhum envio'
}

teste_esp06_simulacao_segue_a_ordem_real_e_nao_anuncia_recusa_do_que_seria_dispensado() {
  # O-3 (QA; decisao do Tech Lead, RF-15/RF-44 emendados): a simulacao le o
  # `content_hash` remoto antes do espaco, na ordem da execucao real.
  local base
  base=$(_cenario 0 10)
  _bytes "$base/local/a.bin" 20
  printf '{".tag":"file","content_hash":"%s"}' "$(_resumo_de "$base/local/a.bin")" >"$base/metadata"
  _rodar "$base" upload "$base/local/a.bin" /r/a.bin
  assert_igual 0 "$DBX_ESTADO" "real: dispensado; diagnostico: $DBX_ERRO"
  assert_contem 'dispensado' "$DBX_SAIDA" 'a execucao real dispensa'
  _rodar "$base" --dry-run upload "$base/local/a.bin" /r/a.bin
  assert_igual 0 "$DBX_ESTADO" "simulacao sai com 0; diagnostico: $DBX_ERRO"
  assert_nao_contem 'recusaria' "$DBX_SAIDA" 'nada a recusar: o envio seria dispensado'
  assert_contem 'dispensado' "$DBX_SAIDA" 'a simulacao anuncia a dispensa'
  assert_igual 0 "$(_consultas "$base")" 'dispensado: sem consulta de espaco, como na execucao real'
  assert_igual 0 "$(_envios "$base")" 'nenhum envio'
  # Conteudo diferente: a mesma simulacao segue para o espaco e recusaria.
  printf '{".tag":"file","content_hash":"%s"}' "$OUTRO" >"$base/metadata"
  local antes
  antes=$(find "$base/estado" -type f -exec cksum {} + 2>/dev/null | sort)
  _rodar "$base" --dry-run upload "$base/local/a.bin" /r/a.bin
  assert_contem 'recusaria=' "$DBX_SAIDA" 'diferente: anuncia a recusa por espaco'
  assert_igual "$antes" "$(find "$base/estado" -type f -exec cksum {} + 2>/dev/null | sort)" \
    'a simulacao nao grava o cache do upload'
}

# ---------------------------------------------------------------------------
# TC-ESP-07, TC-ESP-08, TC-ESP-09 — falha da consulta, entrada padrao, equipe
# ---------------------------------------------------------------------------

teste_esp07_falha_da_consulta_avisa_uma_vez_e_o_envio_segue() {
  local base codigo
  base=$(_cenario 0 1)
  _bytes "$base/local/a.bin" 10
  for codigo in 500 401; do
    printf '%s' "$codigo" >"$base/espaco_codigo"
    _rodar "$base" upload "$base/local/a.bin" /r/a.bin
    assert_igual 0 "$DBX_ESTADO" "consulta $codigo nao bloqueia; diagnostico: $DBX_ERRO"
    assert_igual 1 "$(_harness_contar 'espaco livre' "$base/err")" "um aviso ($codigo)"
    assert_igual 1 "$(_envios "$base")" "o envio segue ($codigo)"
  done
  rm -f "$base/espaco_codigo"
  printf 'nao e json' >"$base/espaco"
  _rodar "$base" upload "$base/local/a.bin" /r/a.bin
  assert_igual 0 "$DBX_ESTADO" "resposta ilegivel nao bloqueia; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_envios "$base")" 'o envio segue'
}

teste_esp08_upload_da_entrada_padrao_nao_consulta() {
  local base
  base=$(_cenario 0 1)
  _bytes "$base/entrada" 10
  _rodar_com_fluxo "$base" "$base/entrada" upload - /r/a.bin
  assert_igual 0 "$DBX_ESTADO" 'o fluxo e enviado'
  assert_igual 0 "$(_consultas "$base")" 'tamanho desconhecido: sem consulta'
}

teste_esp09_conta_de_equipe_usa_a_menor_folga_e_sem_alocacao_nao_recusa() {
  local base
  base=$(_cenario)
  printf '%s' '{"used":0,"allocation":{".tag":"team","used":900,"allocated":1000,"user_within_team_space_allocated":0}}' \
    >"$base/espaco"
  _bytes "$base/local/a.bin" 150
  _rodar "$base" upload "$base/local/a.bin" /r/a.bin
  assert_igual "$(dbx_errors_codigo_saida espaco)" "$DBX_ESTADO" 'folga da equipe 100: recusa'
  printf '%s' '{"used":0}' >"$base/espaco"
  _rodar "$base" upload "$base/local/a.bin" /r/a.bin
  assert_igual 0 "$DBX_ESTADO" "sem alocacao: nao recusa; diagnostico: $DBX_ERRO"
  assert_contem 'aviso' "$DBX_ERRO" 'e avisa'
}

# ---------------------------------------------------------------------------
# TC-ESP-10 — saida estruturada
# ---------------------------------------------------------------------------

teste_esp10_campos_de_espaco_na_saida_estruturada() {
  local base
  base=$(_cenario 0 1000)
  _bytes "$base/local/a.bin" 10
  _rodar "$base" --json upload "$base/local/a.bin" /r/a.bin
  assert_contem $'espaco_necessario=10\nespaco_livre=1000\nespaco_verificado=sim' "$DBX_SAIDA" 'upload'
  _rodar "$base" --json upload --forcar "$base/local/a.bin" /r/a.bin
  assert_contem 'espaco_verificado=pulado' "$DBX_SAIDA" 'upload --forcar'
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_contem $'espaco_necessario=10\nespaco_livre=1000\nespaco_verificado=sim' "$DBX_SAIDA" 'sync'
}

harness_executar "$@"
