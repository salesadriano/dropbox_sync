#!/usr/bin/env bash
# ref_test.sh — acesso a vetor pelo nome (lib/ref.sh), substituto do nameref na
# linha legada (bash 4.2). Requisitos: RF-199; System Design suporte-bash-42,
# eixo 5.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
# shellcheck source=lib/ref.sh
. "$DBX_HARNESS_RAIZ/lib/ref.sh"

# Chaves adversariais: nome de arquivo vindo do remoto. Literais entre aspas
# simples (RSK-28). Nenhuma pode ser executada nem reinterpretada.
_chaves_adversariais() {
  CHAVES=(
    '$(touch "$DBX_TESTES_TMP/executou")'
    '`touch "$DBX_TESTES_TMP/executou"`'
    'a]b'
    'a[0]'
    '*'
    '@'
    ' espaco inicial'
    "com'aspa"
    'com"aspa'
    'x$y'
    '\barra'
  )
}

teste_definir_e_obter_preserva_chave_e_valor_adversariais() {
  local -A mapa=()
  local chave valor
  _chaves_adversariais
  for chave in ${CHAVES[@]+"${CHAVES[@]}"}; do
    dbx_ref_definir mapa "$chave" "v:$chave"
  done
  for chave in ${CHAVES[@]+"${CHAVES[@]}"}; do
    dbx_ref_obter valor mapa "$chave"
    assert_igual "v:$chave" "$valor" "valor lido pela chave [$chave]"
  done
  assert_igual "${#CHAVES[@]}" "${#mapa[@]}" 'uma entrada por chave, nenhuma fundida'
  assert_arquivo_ausente "$DBX_TESTES_TMP/executou" 'chave nunca e executada'
}

teste_existe_e_remover_com_chave_adversarial() {
  local -A mapa=()
  local chave
  _chaves_adversariais
  for chave in ${CHAVES[@]+"${CHAVES[@]}"}; do
    dbx_ref_definir mapa "$chave" 1
  done
  for chave in ${CHAVES[@]+"${CHAVES[@]}"}; do
    dbx_ref_existe mapa "$chave" || assert_igual 'existe' 'ausente' "existe [$chave]"
    dbx_ref_remover mapa "$chave"
    if dbx_ref_existe mapa "$chave"; then
      assert_igual 'removida' 'presente' "remover [$chave]"
    fi
  done
  assert_igual 0 "${#mapa[@]}" 'todas removidas'
  assert_arquivo_ausente "$DBX_TESTES_TMP/executou" 'chave nunca e executada'
}

teste_obter_chave_ausente_devolve_vazio_sob_set_u() {
  local -A mapa=([a]=1)
  local valor=antigo
  dbx_ref_obter valor mapa 'nao-existe'
  assert_igual '' "$valor" 'ausente vira vazio, sem erro de variavel nao definida'
}

teste_nome_invalido_e_recusado_sem_efeito() {
  local -A mapa=()
  local nome status
  for nome in '' '1a' 'a b' 'a;touch x' 'a[0]' '$(id)' 'mapa]'; do
    status=0
    dbx_ref_definir "$nome" k v || status=$?
    assert_igual 2 "$status" "nome [$nome] recusado"
    status=0
    dbx_ref_obter "$nome" mapa k || status=$?
    assert_igual 2 "$status" "destino [$nome] recusado"
  done
  assert_igual 0 "${#mapa[@]}" 'nada gravado'
}

teste_anexar_tamanho_copiar_em_vetor_indexado() {
  local -a lista=() copia=()
  local n
  dbx_ref_tamanho n lista
  assert_igual 0 "$n" 'vazio tem tamanho 0'
  dbx_ref_copiar copia lista
  assert_igual 0 "${#copia[@]}" 'copia de vetor vazio sob set -u'
  dbx_ref_anexar lista 'a b' '$(id)' ''
  dbx_ref_anexar lista 'd'
  dbx_ref_tamanho n lista
  assert_igual 4 "$n" 'anexa cada argumento como um elemento'
  dbx_ref_copiar copia lista
  assert_igual 'a b|$(id)||d' "${copia[0]}|${copia[1]}|${copia[2]}|${copia[3]}" 'copia preserva elementos'
}

teste_chaves_lista_associativo_e_vazio() {
  local -A mapa=()
  local -a chaves=(sobra)
  dbx_ref_chaves chaves mapa
  assert_igual 0 "${#chaves[@]}" 'mapa vazio da lista vazia sob set -u'
  mapa['a]b']=1
  mapa['$(id)']=2
  dbx_ref_chaves chaves mapa
  assert_igual 2 "${#chaves[@]}" 'uma chave por entrada'
  local chave achou_id=nao achou_colchete=nao
  for chave in ${chaves[@]+"${chaves[@]}"}; do
    [[ $chave == '$(id)' ]] && achou_id=sim
    [[ $chave == 'a]b' ]] && achou_colchete=sim
  done
  assert_igual 'sim|sim' "$achou_id|$achou_colchete" 'chaves literais'
}

teste_grava_na_local_do_chamador_por_escopo_dinamico() {
  _chamador() {
    local -A _m=()
    local _v=''
    dbx_ref_definir _m k valor
    dbx_ref_obter _v _m k
    printf '%s' "$_v"
  }
  local saida
  saida=$(_chamador)
  assert_igual valor "$saida" 'destino e a local do chamador'
  assert_igual '' "${_v-}" 'nada vaza para o escopo global'
}

teste_limpar_mantem_o_tipo_associativo() {
  local -A mapa=([x]=1)
  dbx_ref_limpar mapa
  assert_igual 0 "${#mapa[@]}" 'esvaziado'
  dbx_ref_definir mapa 'chave texto' 1
  assert_igual 1 "${mapa['chave texto']}" 'continua associativo apos limpar'
}

harness_executar "$@"
