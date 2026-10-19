#!/usr/bin/env bash
# Testes diretos de lib/sync.sh — comparacao do `verificar` (RF-65(c)(d)).
#
# `dbx_sync_comparar` reaproveita a tabela de `dbx_sync_planejar` e so traduz o
# plano para os quatro estados do relatorio. A traducao e o que estes casos
# provam: o estado de cada arquivo, o motivo `tipo`, a chave sem caixa e a
# ordem estavel da listagem.
#
# shellcheck disable=SC2034
# Justificativa: os vetores e mapas sao passados por nome a lib/sync; a analise
# estatica nao segue nameref entre arquivos.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"
. "$DBX_HARNESS_RAIZ/lib/sync.sh"

readonly H1=1111111111111111111111111111111111111111111111111111111111111111
readonly H2=2222222222222222222222222222222222222222222222222222222222222222

# _relatorio — linhas `estado|motivo|caminho`, na ordem publicada.
_relatorio() {
  local indice
  for indice in "${!DBX_SYNC_COMPARADOS_CAMINHOS[@]}"; do
    printf '%s|%s|%s\n' "${DBX_SYNC_COMPARADOS_ESTADOS[indice]}" \
      "${DBX_SYNC_COMPARADOS_MOTIVOS[indice]}" "${DBX_SYNC_COMPARADOS_CAMINHOS[indice]}"
  done
}

teste_comparar_publica_os_quatro_estados_na_ordem_da_chave() {
  local -a ordem_o=(z.txt b.txt a.txt) ordem_d=(b.txt a.txt c.txt)
  local -A mapa_o=([z.txt]=$H1 [b.txt]=$H1 [a.txt]=$H1) mapa_d=([b.txt]=$H2 [a.txt]=$H1 [c.txt]=$H1)
  dbx_sync_comparar ordem_o mapa_o ordem_d mapa_d
  assert_igual 0 $? 'a comparacao conclui'
  assert_igual $'igual||a.txt\ndiferente|conteudo|b.txt\nso_destino||c.txt\nso_origem||z.txt' \
    "$(_relatorio)" 'cada arquivo uma vez, com um dos quatro estados, na ordem da chave'
}

teste_comparar_casa_os_lados_sem_caixa_e_mantem_a_grafia_da_origem() {
  local -a ordem_o=(Docs/Foto.JPG) ordem_d=(docs/foto.jpg)
  local -A mapa_o=([Docs/Foto.JPG]=$H1) mapa_d=([docs/foto.jpg]=$H1)
  dbx_sync_comparar ordem_o mapa_o ordem_d mapa_d
  assert_igual 'igual||Docs/Foto.JPG' "$(_relatorio)" 'RF-54: so a caixa difere, e o mesmo arquivo'
}

teste_comparar_resumo_malformado_nunca_e_igual() {
  local -a ordem_o=(a.txt) ordem_d=(a.txt)
  local -A mapa_o=([a.txt]=$H1) mapa_d=([a.txt]=nao-e-resumo)
  dbx_sync_comparar ordem_o mapa_o ordem_d mapa_d
  assert_igual 'diferente|conteudo|a.txt' "$(_relatorio)" 'RF-33: resumo ilegivel nao prova igualdade'
}

teste_comparar_arquivo_contra_pasta_e_diferente_por_tipo() {
  # `docs` e arquivo na origem e pasta (prefixo de arquivos) no destino; `img`,
  # o contrario. Pastas sao implicitas: vem dos caminhos de arquivo.
  local -a ordem_o=(docs img/a.png) ordem_d=(docs/x.txt img)
  local -A mapa_o=([docs]=$H1 [img/a.png]=$H1) mapa_d=([docs/x.txt]=$H1 [img]=$H1)
  dbx_sync_comparar ordem_o mapa_o ordem_d mapa_d
  assert_igual $'diferente|tipo|docs\nso_destino||docs/x.txt\ndiferente|tipo|img\nso_origem||img/a.png' \
    "$(_relatorio)" 'arquivo num lado e pasta no outro e diferente, com motivo tipo'
}

teste_comparar_lados_vazios_nao_publica_nada() {
  local -a ordem_o=() ordem_d=()
  local -A mapa_o=() mapa_d=()
  dbx_sync_comparar ordem_o mapa_o ordem_d mapa_d
  assert_igual 0 $? 'arvores vazias comparam'
  assert_igual 0 "${#DBX_SYNC_COMPARADOS_CAMINHOS[@]}" 'nada a listar'
}

teste_comparar_exige_quatro_argumentos() {
  assert_status "$DBX_SYNC_ERRO_USO" dbx_sync_comparar um dois
}

harness_executar "$@"
