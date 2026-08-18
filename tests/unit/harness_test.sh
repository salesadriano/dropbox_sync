#!/usr/bin/env bash
# harness_test.sh — casos sobre o proprio arcabouco de teste.
#
# Motivo de existir: o arcabouco imprime valores para diagnosticar, e desde que
# o diario de reprovacoes passou a gravar esses valores EM DISCO, imprimir
# virou superficie de vazamento. A assercao que prova que um segredo nao vaza e
# ela propria um vetor quando falha, porque imprime a agulha procurada.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"

# Segredos de teste sao escritos como literais entre aspas simples: substituicao
# de comando dentro do dado adversarial ja produziu, mais de uma vez, um dado
# diferente do pretendido (RSK-28).
readonly SEGREDO='RT9pQrStUvWxYz_segredo_de_teste'

# _rodar_assercao <arquivo_de_saida> <comando...>
# A assercao encerra o caso ao falhar; o subshell contem esse encerramento.
_rodar_assercao() {
  local arquivo=$1
  shift
  ("$@") >"$arquivo" 2>&1
}

_ler() {
  DBX_LIDO=''
  [[ -r $1 ]] && IFS= read -r -d '' DBX_LIDO <"$1"
  return 0
}

teste_assercao_de_segredo_aprova_quando_ausente() {
  local arquivo=$DBX_TESTES_TMP/ok.$$
  _rodar_assercao "$arquivo" assert_segredo_ausente "$SEGREDO" 'corpo sem credencial alguma'
  assert_igual 0 $? 'segredo ausente deve aprovar'
  _ler "$arquivo"
  assert_igual '' "$DBX_LIDO" 'aprovacao nao deve imprimir nada'
}

teste_assercao_de_segredo_reprova_quando_presente() {
  local arquivo=$DBX_TESTES_TMP/falha.$$
  _rodar_assercao "$arquivo" assert_segredo_ausente "$SEGREDO" "corpo=$SEGREDO&x=1"
  assert_igual 1 $? 'segredo presente deve reprovar'
}

teste_falha_de_segredo_nunca_imprime_o_segredo() {
  local arquivo=$DBX_TESTES_TMP/vaza.$$
  _rodar_assercao "$arquivo" assert_segredo_ausente "$SEGREDO" "Authorization: $SEGREDO"
  assert_igual 1 $? 'a falha precisa ter acontecido; senao o caso passa por vacuidade'
  _ler "$arquivo"
  assert_nao_contem "$SEGREDO" "${DBX_LIDO//$SEGREDO/<<<VAZOU>>>}" \
    'a mensagem da falha nao pode conter a agulha'
  [[ $DBX_LIDO == *"$SEGREDO"* ]] &&
    _harness_falhar 'segredo presente na mensagem de falha' \
      'posicao do vazamento existe; conteudo omitido de proposito'
  return 0
}

teste_falha_de_segredo_informa_posicao_e_comprimento() {
  local arquivo=$DBX_TESTES_TMP/pos.$$
  _rodar_assercao "$arquivo" assert_segredo_ausente "$SEGREDO" "abcde$SEGREDO"
  _ler "$arquivo"
  assert_contem 'posicao: 5' "$DBX_LIDO" 'deve localizar a primeira ocorrencia'
  assert_contem "comprimento: ${#SEGREDO}" "$DBX_LIDO" 'deve informar o tamanho'
}

teste_falha_de_segredo_preserva_o_restante_do_diagnostico() {
  local arquivo=$DBX_TESTES_TMP/legivel.$$
  _rodar_assercao "$arquivo" assert_segredo_ausente "$SEGREDO" \
    "grant_type=refresh&valor=$SEGREDO&client_id=publico" 'corpo da renovacao'
  _ler "$arquivo"
  assert_contem 'corpo da renovacao' "$DBX_LIDO" 'descricao deve sobreviver'
  assert_contem 'grant_type=refresh' "$DBX_LIDO" 'contexto nao sensivel deve sobreviver'
  assert_contem 'client_id=publico' "$DBX_LIDO" 'trecho apos o segredo deve sobreviver'
}

teste_falha_de_segredo_mascara_todas_as_ocorrencias() {
  local arquivo=$DBX_TESTES_TMP/varias.$$
  _rodar_assercao "$arquivo" assert_segredo_ausente "$SEGREDO" \
    "a=$SEGREDO b=$SEGREDO c=$SEGREDO"
  _ler "$arquivo"
  assert_contem 'ocorrencias: 3' "$DBX_LIDO" 'deve contar as ocorrencias'
  [[ $DBX_LIDO == *"$SEGREDO"* ]] && _harness_falhar 'sobrou ocorrencia sem mascara'
  return 0
}

teste_segredo_com_metacaractere_de_glob_e_tratado_literalmente() {
  local arquivo=$DBX_TESTES_TMP/glob.$$
  local agulha='a*b[c]?d'
  _rodar_assercao "$arquivo" assert_segredo_ausente "$agulha" 'axxbcd nao e a agulha'
  assert_igual 0 $? 'glob nao pode casar como padrao'
  _rodar_assercao "$arquivo" assert_segredo_ausente "$agulha" "prefixo${agulha}sufixo"
  assert_igual 1 $? 'ocorrencia literal deve ser detectada'
}

teste_assercao_de_segredo_recusa_agulha_vazia() {
  local arquivo=$DBX_TESTES_TMP/vazia.$$
  _rodar_assercao "$arquivo" assert_segredo_ausente '' 'qualquer texto'
  assert_igual 1 $? 'agulha vazia deve ser recusada, nao aprovada por vacuidade'
  _ler "$arquivo"
  assert_contem 'vazio' "$DBX_LIDO" 'a recusa deve dizer o motivo'
}

teste_diario_nao_recebe_segredo_sem_forma_reconhecivel() {
  local saida=$DBX_TESTES_TMP/saida.$$ diario=$DBX_TESTES_TMP/diario.$$
  rm -f "$diario"
  _rodar_assercao "$saida" assert_segredo_ausente "$SEGREDO" "corpo=$SEGREDO"
  assert_igual 1 $? 'a falha precisa ter acontecido'
  DBX_HARNESS_DIARIO=$diario _harness_registrar_reprovacao 'teste_ficticio' 1 'host' "$saida"
  _ler "$diario"
  assert_contem 'teste_ficticio' "$DBX_LIDO" 'o diario deve ter sido escrito'
  [[ $DBX_LIDO == *"$SEGREDO"* ]] && _harness_falhar 'segredo chegou ao diario em disco'
  return 0
}

teste_diario_preserva_o_diagnostico_do_caso() {
  local saida=$DBX_TESTES_TMP/saida2.$$ diario=$DBX_TESTES_TMP/diario2.$$
  rm -f "$diario"
  _rodar_assercao "$saida" assert_segredo_ausente "$SEGREDO" \
    "grant_type=refresh&valor=$SEGREDO" 'corpo da renovacao'
  DBX_HARNESS_DIARIO=$diario _harness_registrar_reprovacao 'teste_ficticio' 1 'host' "$saida"
  _ler "$diario"
  assert_contem 'corpo da renovacao' "$DBX_LIDO" 'diario redigido nao pode virar diario vazio'
  assert_contem 'grant_type=refresh' "$DBX_LIDO" 'contexto nao sensivel deve chegar ao diario'
}

# ---------------------------------------------------------------------------
# As assercoes do arcabouco tambem precisam de prova de que REPROVAM.
#
# Achado por mutacao: trocar o corpo de `assert_nao_contem` por `return 0` deixa
# a suite inteira verde. Nenhum caso do projeto exige que ela falhe — assercao
# negativa so e usada para afirmar ausencia, entao neutraliza-la nunca quebra
# nada, apenas para de verificar. Vale para toda a familia negativa. Os casos
# abaixo cobrem os dois sentidos de cada assercao usada no projeto.
# ---------------------------------------------------------------------------

_status_da_assercao() {
  local arquivo=$DBX_TESTES_TMP/assercao.$$
  _rodar_assercao "$arquivo" "$@"
  return $?
}

teste_assercao_nao_contem_reprova_quando_o_trecho_esta_presente() {
  _status_da_assercao assert_nao_contem 'agulha' 'texto com agulha dentro'
  assert_igual 1 $? 'assert_nao_contem tem de reprovar com o trecho presente'
  _status_da_assercao assert_nao_contem 'agulha' 'texto sem o trecho'
  assert_igual 0 $? 'assert_nao_contem tem de aprovar com o trecho ausente'
}

teste_assercao_contem_reprova_quando_o_trecho_falta() {
  _status_da_assercao assert_contem 'agulha' 'texto sem o trecho'
  assert_igual 1 $? 'assert_contem tem de reprovar com o trecho ausente'
  _status_da_assercao assert_contem 'agulha' 'texto com agulha dentro'
  assert_igual 0 $? 'assert_contem tem de aprovar com o trecho presente'
}

teste_assercao_diferente_reprova_quando_os_valores_sao_iguais() {
  _status_da_assercao assert_diferente 'x' 'x'
  assert_igual 1 $? 'assert_diferente tem de reprovar com valores iguais'
  _status_da_assercao assert_diferente 'x' 'y'
  assert_igual 0 $? 'assert_diferente tem de aprovar com valores distintos'
}

# `assert_igual` nao pode ser verificada com `assert_igual`: neutralizada, ela
# aprovaria tambem a propria verificacao. Medido — a suite inteira ficava verde.
# Aqui a comparacao e feita com o operador do shell, e a falha e sinalizada pela
# primitiva, nao por outra assercao.
teste_assercao_igual_reprova_quando_os_valores_diferem() {
  local obtido
  _status_da_assercao assert_igual 'x' 'y'
  obtido=$?
  [[ $obtido -eq 1 ]] ||
    _harness_falhar 'assert_igual nao reprovou com valores distintos' "status: $obtido"
  _status_da_assercao assert_igual 'x' 'x'
  obtido=$?
  [[ $obtido -eq 0 ]] ||
    _harness_falhar 'assert_igual nao aprovou com valores iguais' "status: $obtido"
  return 0
}

# A primitiva de falha e o nucleo em que tudo se apoia: se ela nao encerrar o
# caso, toda assercao vira decorativa. Verificada sem assercao alguma.
teste_primitiva_de_falha_encerra_o_caso_com_status_um() {
  local obtido
  _status_da_assercao _harness_falhar 'falha deliberada'
  obtido=$?
  [[ $obtido -eq 1 ]] || {
    printf '# FALHA: _harness_falhar nao encerrou o caso (status %s)\n' "$obtido" >&2
    exit 1
  }
  return 0
}

teste_assercao_de_arquivo_ausente_reprova_quando_o_arquivo_existe() {
  local presente=$DBX_TESTES_TMP/presente.$$
  : >"$presente"
  _status_da_assercao assert_arquivo_ausente "$presente"
  assert_igual 1 $? 'assert_arquivo_ausente tem de reprovar com o arquivo presente'
  rm -f "$presente"
  _status_da_assercao assert_arquivo_ausente "$presente"
  assert_igual 0 $? 'assert_arquivo_ausente tem de aprovar com o arquivo ausente'
}

teste_assercao_de_arquivo_existe_reprova_quando_o_arquivo_falta() {
  local ausente=$DBX_TESTES_TMP/ausente.$$
  rm -f "$ausente"
  _status_da_assercao assert_arquivo_existe "$ausente"
  assert_igual 1 $? 'assert_arquivo_existe tem de reprovar com o arquivo ausente'
  : >"$ausente"
  _status_da_assercao assert_arquivo_existe "$ausente"
  assert_igual 0 $? 'assert_arquivo_existe tem de aprovar com o arquivo presente'
  rm -f "$ausente"
}

teste_assercao_de_status_reprova_quando_o_codigo_difere() {
  _status_da_assercao assert_status 3 bash -c 'exit 4'
  assert_igual 1 $? 'assert_status tem de reprovar com codigo divergente'
  _status_da_assercao assert_status 4 bash -c 'exit 4'
  assert_igual 0 $? 'assert_status tem de aprovar com codigo igual'
}

harness_executar "$@"
