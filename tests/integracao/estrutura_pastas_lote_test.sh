#!/usr/bin/env bash
# Testes do adaptador de criacao de pastas em lote (F-103; RF-210, RF-213;
# TC-ARV-06 a TC-ARV-09; DIV-398): `dbx_lote_criar_pastas` em lib/lote.sh.
#
# A seam e a funcao publica com o cliente HTTP REAL (lib/auth + lib/http) e um
# duplo de `curl` que faz o papel do servico: responde `create_folder_batch` e
# `create_folder_batch/check` a partir do corpo recebido, e registra em
# `$DUPLO/chamadas` cada chamada (`lancar <caminhos>` ou `check`) e em
# `$DUPLO/corpos` cada corpo de lancamento. Controles (arquivos em `$DUPLO`):
#
#   pasta_existe      caminhos (um por linha) respondidos com path/conflict/folder
#   arquivo_no_lugar  caminhos respondidos com path/conflict/file
#   sem_espaco        caminhos respondidos com path/insufficient_space
#   assincrono        lancamento devolve async_job_id; o `check` devolve
#                     `in_progress` <conteudo> vezes e depois `complete`
#   tag_lancamento    lancamento devolve so {".tag":"<conteudo>"}
#   check_corpo       corpo fixo de todo `check`
#   falha_lancar      fila (uma por linha) de respostas do lancamento: um codigo
#   falha_check       HTTP, `rede` (curl sai 7) ou `sempre:<codigo|rede>` (repete);
#                     fila vazia = resposta normal. `corpo_erro` e o corpo delas.
#   (token)           a renovacao (oauth2/token) responde 200 e conta em `n_token`
#
# O recuo do `check` nao espera: `_dbx_lote_dormir` (ponto unico de espera da
# biblioteca) e substituido e so registra os segundos em `$DUPLO/dormiu`.
#
# shellcheck disable=SC2016,SC2034
# Justificativa: o duplo precisa chegar sem expansao; os canais de entrada das
# bibliotecas (DBX_LOTE_PASTAS, DBX_AUTH_*, DBX_CLI_SIMULACAO) sao lidos por elas.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"
. "$DBX_HARNESS_RAIZ/lib/auth.sh"
. "$DBX_HARNESS_RAIZ/lib/lote.sh"

DUPLO=''

_dbx_lote_dormir() { printf '%s\n' "$1" >>"$DUPLO/dormiu"; }
_dbx_http_dormir() { :; }

preparar_caso() {
  DUPLO=$(mktemp -d "$DBX_TESTES_TMP/pastas.XXXXXX") || return 1
  mkdir -p "$DUPLO/corpos"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'dir=%q\n' "$DUPLO"
    cat <<'FIM'
cat >/dev/null
url='' saida='' escrever='' corpoarq='' ant=''
for a in "$@"; do
  case $ant in -o) saida=$a ;; -w) escrever=$a ;; esac
  case $a in http*) url=$a ;; @*) corpoarq=${a#@} ;; esac
  ant=$a
done
corpo_req=''
[[ -n $corpoarq && -r $corpoarq ]] && corpo_req=$(<"$corpoarq")
_em() { [[ -r $dir/$1 ]] && grep -Fxq -- "$2" "$dir/$1"; }
_entradas() { # corpo do pedido -> entries por posicao
  local lista=${1#*\"paths\":[} item out=''
  lista=${lista%%]*}
  lista=${lista//\"/}
  IFS=',' read -r -a itens <<<"$lista"
  for item in "${itens[@]}"; do
    if _em pasta_existe "$item"; then
      e='{".tag":"failure","failure":{".tag":"path","path":{".tag":"conflict","conflict":{".tag":"folder"}}}}'
    elif _em arquivo_no_lugar "$item"; then
      e='{".tag":"failure","failure":{".tag":"path","path":{".tag":"conflict","conflict":{".tag":"file"}}}}'
    elif _em sem_espaco "$item"; then
      e='{".tag":"failure","failure":{".tag":"path","path":{".tag":"insufficient_space"}}}'
    else
      e="{\".tag\":\"success\",\"metadata\":{\"name\":\"x\",\"path_lower\":\"$item\",\"id\":\"id:1\"}}"
    fi
    out+="${out:+,}$e"
  done
  printf '{".tag":"complete","entries":[%s]}' "$out"
}
codigo=200
case $url in
  *create_folder_batch/check*)
    printf 'check\n' >>"$dir/chamadas"
    vez=0
    [[ -r $dir/n_check ]] && read -r vez <"$dir/n_check"
    vez=$((vez + 1))
    printf '%s' "$vez" >"$dir/n_check"
    limite=0
    [[ -r $dir/assincrono ]] && read -r limite <"$dir/assincrono"
    if [[ -r $dir/check_corpo ]]; then
      corpo=$(<"$dir/check_corpo")
    elif ((vez <= limite)); then
      corpo='{".tag":"in_progress"}'
    else
      corpo=$(_entradas "$(<"$dir/pendente")")
      : >"$dir/n_check"
    fi
    ;;
  *create_folder_batch*)
    n=$(ls "$dir/corpos" | wc -l)
    printf '%s' "$corpo_req" >"$dir/corpos/$((n + 1))"
    lista=${corpo_req#*\"paths\":[}
    lista=${lista%%]*}
    lista=${lista//\"/}
    printf 'lancar %s\n' "${lista//,/ }" >>"$dir/chamadas"
    if [[ -r $dir/tag_lancamento ]]; then
      corpo="{\".tag\":\"$(<"$dir/tag_lancamento")\"}"
    elif [[ -r $dir/assincrono ]]; then
      printf '%s' "$corpo_req" >"$dir/pendente"
      corpo='{".tag":"async_job_id","async_job_id":"dbjid:JOB"}'
    else
      corpo=$(_entradas "$corpo_req")
    fi
    ;;
  *oauth2/token*)
    printf 'x\n' >>"$dir/n_token"
    corpo='{"access_token":"sl.renovado-sintetico","expires_in":3600}'
    ;;
  *) corpo='{}' ;;
esac
_falha() { # fila -> proxima resposta de falha (vazio = normal)
  local f=$dir/$1 prox
  [[ -s $f ]] || return 0
  prox=$(head -n 1 "$f")
  [[ $prox == sempre:* ]] && { printf '%s' "${prox#sempre:}"; return 0; }
  tail -n +2 "$f" >"$f.n"; mv "$f.n" "$f"
  printf '%s' "$prox"
}
fila=''
case $url in
  *create_folder_batch/check*) fila=falha_check ;;
  *create_folder_batch*) fila=falha_lancar ;;
esac
if [[ -n $fila ]]; then
  f=$(_falha "$fila")
  if [[ $f == rede ]]; then exit 7
  elif [[ -n $f ]]; then
    codigo=$f
    corpo='{"error_summary":"erro_de_teste","error":{".tag":"x"}}'
    [[ -r $dir/corpo_erro ]] && corpo=$(<"$dir/corpo_erro")
  fi
fi
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$DUPLO/curl"
  chmod +x "$DUPLO/curl"
  PATH="$DUPLO:$PATH"
  DBX_AUTH_TOKEN='sl.teste-sintetico'
  DBX_AUTH_EXPIRA_EM=$((SECONDS + 3600))
  DBX_CLI_SIMULACAO='nao'
  DBX_CONFIG_REFRESH_TOKEN='rt-sintetico' DBX_CONFIG_APP_KEY='key-sintetica'
  DBX_CONFIG_APP_SECRET='segredo-sintetico'
}

_chamadas() { [[ -r $DUPLO/chamadas ]] && cat "$DUPLO/chamadas"; return 0; }

# _criar <caminho>... — roda a funcao publica e guarda o status em ESTADO.
_criar() {
  DBX_LOTE_PASTAS=("$@")
  dbx_lote_criar_pastas
  ESTADO=$?
}

# ---------------------------------------------------------------------------

teste_tc_arv_06_nivel_seguinte_so_depois_do_check_complete_do_anterior() {
  printf '1\n' >"$DUPLO/assincrono"
  _criar /a/b/c /a/b /a /x
  assert_igual 0 "$ESTADO" 'tudo criado: sucesso'
  assert_igual $'lancar /a /x\ncheck\ncheck\nlancar /a/b\ncheck\ncheck\nlancar /a/b/c\ncheck\ncheck' \
    "$(_chamadas)" 'por nivel, cada um concluido pelo check antes do proximo'
  assert_igual 'criada criada criada criada' "${DBX_LOTE_PASTAS_RESULTADO[*]}" \
    'resultado por posicao da entrada'
  assert_igual $'1\n1\n1' "$(cat "$DUPLO/dormiu")" 'recuo do check reaproveitado (DIV-262)'
}

teste_tc_arv_07_pasta_existente_conta_como_sucesso_e_nao_como_criada() {
  printf '/a\n' >"$DUPLO/pasta_existe"
  _criar /a /a/b
  assert_igual 0 "$ESTADO" 'pasta existente nao e falha'
  assert_igual 'existia' "${DBX_LOTE_PASTAS_RESULTADO[0]}" 'conflict/folder = existia'
  assert_igual 'criada' "${DBX_LOTE_PASTAS_RESULTADO[1]}" 'filha de pasta existente e submetida'
  assert_igual $'lancar /a\nlancar /a/b' "$(_chamadas)" 'sem check quando o lancamento ja e complete'
}

teste_tc_arv_08_09_fatias_conservadoras_posicao_e_autorename_false() {
  local i caminhos=() corpo n_corpos=0 n_false=0 n_async=0
  for ((i = 1; i <= 251; i++)); do caminhos+=("/d$i"); done
  printf '/d3\n' >"$DUPLO/pasta_existe"
  printf '/d251\n' >"$DUPLO/arquivo_no_lugar"
  _criar "${caminhos[@]}"
  assert_igual 1 "$ESTADO" 'falha de item tem status proprio'
  assert_igual 250 "$DBX_LOTE_PASTAS_FATIA" 'fatia conservadora em constante unica'
  assert_igual 2 "$(_harness_contar '^lancar' "$DUPLO/chamadas")" '251 pastas = 250 + 1'
  assert_igual 'lancar /d251' "$(tail -n 1 "$DUPLO/chamadas")" 'a segunda fatia leva so a 251a'
  assert_igual 'criada' "${DBX_LOTE_PASTAS_RESULTADO[1]}" 'posicao 2'
  assert_igual 'existia' "${DBX_LOTE_PASTAS_RESULTADO[2]}" 'posicao 3 le a entrada 3'
  assert_igual 'criada' "${DBX_LOTE_PASTAS_RESULTADO[249]}" 'ultima da primeira fatia'
  assert_igual $'falha\tarquivo no lugar da pasta: /d251' "${DBX_LOTE_PASTAS_RESULTADO[250]}" \
    'posicao 1 da segunda fatia e a 251a'
  for corpo in "$DUPLO"/corpos/*; do
    n_corpos=$((n_corpos + 1))
    [[ $(<"$corpo") == *'"autorename":false'* ]] && n_false=$((n_false + 1))
    [[ $(<"$corpo") == *force_async* ]] && n_async=$((n_async + 1))
  done
  assert_igual 2 "$n_corpos" 'dois corpos de lancamento'
  assert_igual "$n_corpos" "$n_false" 'autorename false em todo corpo (TC-ARV-09)'
  assert_igual 0 "$n_async" 'force_async nunca enviado'
}

teste_arquivo_no_lugar_falha_a_pasta_e_nao_submete_descendentes() {
  printf '/a\n' >"$DUPLO/arquivo_no_lugar"
  _criar /a /a/b /a/b/c /z /z/y
  assert_igual 1 "$ESTADO" 'falha de item, nao sistemica'
  assert_igual $'lancar /a /z\nlancar /z/y' "$(_chamadas)" 'descendentes de /a nao sao submetidos'
  assert_igual $'falha\tarquivo no lugar da pasta: /a' "${DBX_LOTE_PASTAS_RESULTADO[0]}" 'motivo da pasta'
  assert_igual $'falha\tpasta de destino nao criada: /a' "${DBX_LOTE_PASTAS_RESULTADO[1]}" 'filha'
  assert_igual $'falha\tpasta de destino nao criada: /a' "${DBX_LOTE_PASTAS_RESULTADO[2]}" \
    'neta cita a pasta que falhou de fato'
  assert_igual 'criada criada' "${DBX_LOTE_PASTAS_RESULTADO[3]} ${DBX_LOTE_PASTAS_RESULTADO[4]}" \
    'o resto segue'
}

teste_tag_desconhecida_no_lancamento_e_falha_sistemica() {
  printf 'novidade\n' >"$DUPLO/tag_lancamento"
  _criar /a /a/b
  assert_igual 2 "$ESTADO" 'tag desconhecida = falha sistemica'
  assert_igual 'lancar /a' "$(_chamadas)" 'nada mais e submetido'
  assert_igual 'erro_remoto' "$DBX_LOTE_PASTAS_CLASSE" 'classe da parada'
  assert_igual 'falha' "${DBX_LOTE_PASTAS_RESULTADO[1]%%$'\t'*}" 'nenhuma pasta sai como sucesso'
}

teste_job_failed_no_check_e_falha_sistemica() {
  printf '0\n' >"$DUPLO/assincrono"
  printf '%s' '{".tag":"failed","failed":{".tag":"too_many_files"}}' >"$DUPLO/check_corpo"
  _criar /a /a/b
  assert_igual 2 "$ESTADO" 'job failed = falha sistemica'
  assert_igual $'lancar /a\ncheck' "$(_chamadas)" 'para antes do nivel 2'
  assert_contem 'too_many_files' "$DBX_LOTE_PASTAS_MOTIVO" 'motivo cita o erro do lote'
}

teste_sem_espaco_na_entrada_e_falha_sistemica() {
  printf '/a\n' >"$DUPLO/sem_espaco"
  _criar /a /b /a/c
  assert_igual 2 "$ESTADO" 'insufficient_space = falha sistemica'
  assert_igual 'lancar /a /b' "$(_chamadas)" 'nivel 2 nao e submetido'
  assert_igual 'espaco' "$DBX_LOTE_PASTAS_CLASSE" 'classe espaco'
  assert_igual 'criada' "${DBX_LOTE_PASTAS_RESULTADO[1]}" 'o que o servidor confirmou continua valendo'
}

teste_teto_do_check_e_falha_sistemica() {
  printf '%s' '{".tag":"in_progress"}' >"$DUPLO/check_corpo"
  printf '0\n' >"$DUPLO/assincrono"
  _criar /a
  local soma=0 s
  while IFS= read -r s; do soma=$((soma + s)); done <"$DUPLO/dormiu"
  assert_igual 2 "$ESTADO" 'teto estourado = falha sistemica'
  assert_igual 'nao_concluida' "$DBX_LOTE_PASTAS_CLASSE" 'classe nao_concluida'
  assert_igual 1 "$(_harness_contar '^lancar' "$DUPLO/chamadas")" 'o lancamento nao e repetido'
  assert_igual 1 "$((soma <= DBX_LOTE_ESPERA_TETO))" 'espera acumulada dentro do teto'
}

teste_simulacao_e_lista_vazia_nao_chamam_a_api() {
  DBX_CLI_SIMULACAO='sim'
  _criar /a
  assert_igual 0 "$ESTADO" 'simulacao nao falha'
  DBX_CLI_SIMULACAO='nao'
  _criar
  assert_igual 0 "$ESTADO" 'lista vazia nao falha'
  assert_igual '' "$(_chamadas)" 'nenhuma chamada (RF-210(e))'
}

teste_401_renova_o_token_uma_vez_e_repete_o_lancamento() {
  printf '401\n' >"$DUPLO/falha_lancar"
  _criar /a
  assert_igual 0 "$ESTADO" '401 seguido de 200 = sucesso'
  assert_igual 1 "$(_harness_contar 'x' "$DUPLO/n_token")" 'uma renovacao'
  assert_igual $'lancar /a\nlancar /a' "$(_chamadas)" 'o lancamento e repetido uma vez'
  assert_igual 'criada' "${DBX_LOTE_PASTAS_RESULTADO[0]}" 'pasta criada apos a renovacao'
}

teste_401_de_novo_apos_renovar_e_falha_de_autenticacao_sem_laco() {
  printf 'sempre:401\n' >"$DUPLO/falha_lancar"
  _criar /a /a/b
  assert_igual 2 "$ESTADO" '401 persistente = falha sistemica'
  assert_igual 'autenticacao' "$DBX_LOTE_PASTAS_CLASSE" 'classe de autenticacao'
  assert_igual 1 "$(_harness_contar 'x' "$DUPLO/n_token")" 'renova uma unica vez'
  assert_igual 2 "$(_harness_contar '^lancar' "$DUPLO/chamadas")" 'duas tentativas, sem laco'
  assert_igual 'falha' "${DBX_LOTE_PASTAS_RESULTADO[1]%%$'\t'*}" 'nenhuma pasta sai como sucesso'
}

# _esgota <fila> <valor> — falha repetida no lancamento (async=nao) ou no check.
_esgota() {
  if [[ $1 == falha_check ]]; then printf '0\n' >"$DUPLO/assincrono"; fi
  printf 'sempre:%s\n' "$2" >"$DUPLO/$1"
  printf '%s' 'sl.vazou-segredo-no-corpo' >"$DUPLO/corpo_erro"
  _criar /a
  assert_igual 2 "$ESTADO" "$1 $2: falha sistemica"
  local alvo='^lancar'
  [[ $1 == falha_check ]] && alvo='^check'
  assert_igual "$DBX_HTTP_TENTATIVAS_MAXIMAS_PADRAO" "$(_harness_contar "$alvo" "$DUPLO/chamadas")" \
    'ate esgotar as tentativas do cliente (RNF-21)'
  assert_contem "$3" "$DBX_LOTE_PASTAS_CLASSE" 'classe da parada'
  assert_igual 1 "$((${#DBX_LOTE_PASTAS_MOTIVO} > 0))" 'ha motivo'
  case $DBX_LOTE_PASTAS_MOTIVO in
    *vazou-segredo* | *sl.teste* | *segredo-sintetico*) assert_igual 'limpo' 'vazou' 'motivo sem corpo bruto nem segredo' ;;
    *) assert_igual 'limpo' 'limpo' 'motivo sem corpo bruto nem segredo' ;;
  esac
}

teste_rede_repetida_no_lancamento_esgota_as_tentativas() { _esgota falha_lancar rede rede; }
teste_429_repetido_no_lancamento_esgota_as_tentativas() { _esgota falha_lancar 429 limite_taxa; }
teste_5xx_repetido_no_lancamento_esgota_as_tentativas() { _esgota falha_lancar 503 erro_remoto; }
teste_rede_repetida_no_check_esgota_as_tentativas() { _esgota falha_check rede rede; }
teste_429_repetido_no_check_esgota_as_tentativas() { _esgota falha_check 429 limite_taxa; }
teste_5xx_repetido_no_check_esgota_as_tentativas() { _esgota falha_check 500 erro_remoto; }

harness_executar "$@"
