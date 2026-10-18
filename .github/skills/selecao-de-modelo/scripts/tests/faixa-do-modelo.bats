#!/usr/bin/env bats
# Testes de faixa-do-modelo.sh: a faixa vem da classe da tarefa e so sobe com porte, --toca e --critico.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../faixa-do-modelo.sh"
  D="$BATS_TEST_TMPDIR"
  printf '# comentario\neconomico\tbarato\tmodelo-b\t0.10\t0.50\t0.01\npadrao\tmedio\tmodelo-m\t2\t10\t0.2\nmaximo\tforte\tmodelo-f\t4\t20\t0.2\n' > "$D/tabela.tsv"
}

@test "classe de renderizacao e economico e aponta o modelo da tabela" {
  run sh "$SCRIPT" --classe redacao --tabela "$D/tabela.tsv"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "faixa: economico" ]
  [ "${lines[1]}" = "motivo: classe redacao e economico" ]
  [ "${lines[2]}" = "modelo: barato (modelo-b)" ]
}

@test "commit e log de prompt sao economico" {
  run sh "$SCRIPT" --classe commit --tabela "$D/tabela.tsv"
  [ "${lines[0]}" = "faixa: economico" ]
  run sh "$SCRIPT" --classe log-de-prompt --tabela "$D/tabela.tsv"
  [ "${lines[0]}" = "faixa: economico" ]
}

@test "implementacao e padrao em M" {
  run sh "$SCRIPT" --classe implementacao --porte M --tabela "$D/tabela.tsv"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "faixa: padrao" ]
  [ "${lines[2]}" = "modelo: medio (modelo-m)" ]
}

@test "modelo de dados e maximo mesmo em porte P" {
  run sh "$SCRIPT" --classe modelo-de-dados --porte P --tabela "$D/tabela.tsv"
  [ "${lines[0]}" = "faixa: maximo" ]
  [ "${lines[2]}" = "modelo: forte (modelo-f)" ]
}

@test "porte G sobe padrao para maximo e nao mexe em economico" {
  run sh "$SCRIPT" --classe teste --porte G --tabela "$D/tabela.tsv"
  [ "${lines[0]}" = "faixa: maximo" ]
  [[ "${lines[1]}" == *"porte G sobe padrao para maximo"* ]]
  run sh "$SCRIPT" --classe redacao --porte G --tabela "$D/tabela.tsv"
  [ "${lines[0]}" = "faixa: economico" ]
}

@test "--toca schema sobe redacao direto para maximo" {
  run sh "$SCRIPT" --classe redacao --toca schema --tabela "$D/tabela.tsv"
  [ "${lines[0]}" = "faixa: maximo" ]
  [[ "${lines[1]}" == *"toca schema sobe para maximo"* ]]
}

@test "--toca contrato sobe economico para padrao e nao desce maximo" {
  run sh "$SCRIPT" --classe resumo --toca contrato --tabela "$D/tabela.tsv"
  [ "${lines[0]}" = "faixa: padrao" ]
  run sh "$SCRIPT" --classe arquitetura --toca contrato --tabela "$D/tabela.tsv"
  [ "${lines[0]}" = "faixa: maximo" ]
  [ "${lines[1]}" = "motivo: classe arquitetura e maximo" ]
}

@test "--toca com lista: vale o item mais alto" {
  run sh "$SCRIPT" --classe analise --toca pipeline,dependencia,auth --tabela "$D/tabela.tsv"
  [ "${lines[0]}" = "faixa: maximo" ]
  [[ "${lines[1]}" == *"toca auth sobe para maximo"* ]]
}

@test "--critico sobe qualquer classe para maximo" {
  run sh "$SCRIPT" --classe formatacao --critico --tabela "$D/tabela.tsv"
  [ "${lines[0]}" = "faixa: maximo" ]
  [[ "${lines[1]}" == *"critico sobe para maximo"* ]]
}

@test "classe desconhecida sai com 2 e aponta --classes" {
  run sh "$SCRIPT" --classe magia --tabela "$D/tabela.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"classe desconhecida: magia"* ]]
  [[ "$output" == *"--classes"* ]]
}

@test "item desconhecido em --toca, porte invalido e argumento desconhecido saem com 2" {
  run sh "$SCRIPT" --classe teste --toca banco --tabela "$D/tabela.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"item desconhecido em --toca: banco"* ]]
  run sh "$SCRIPT" --classe teste --porte X --tabela "$D/tabela.tsv"
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --classe teste --fantasia
  [ "$status" -eq 2 ]
  run sh "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "--classes lista toda classe com a faixa minima" {
  run sh "$SCRIPT" --classes
  [ "$status" -eq 0 ]
  [[ "$output" == *"redacao economico"* ]]
  [[ "$output" == *"implementacao padrao"* ]]
  [[ "$output" == *"modelo-de-dados maximo"* ]]
}

@test "sem tabela ao lado do script, usa o exemplo de references" {
  run sh "$SCRIPT" --classe commit
  [ "$status" -eq 0 ]
  [[ "${lines[2]}" == "modelo: haiku ("* ]]
}

@test "tabela inexistente e tabela sem a faixa saem com 1" {
  run sh "$SCRIPT" --classe commit --tabela "$D/nao-existe.tsv"
  [ "$status" -eq 1 ]
  printf 'padrao\tmedio\tmodelo-m\t2\t10\t0.2\n' > "$D/so-padrao.tsv"
  run sh "$SCRIPT" --classe commit --tabela "$D/so-padrao.tsv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sem linha para a faixa economico"* ]]
}
