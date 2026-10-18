#!/usr/bin/env bats
# Suite independente do QA para selecao-de-modelo: cenarios de risco que a suite dos autores nao cobre.
# Nao versionar antes do aceite do solicitante (regra 12); o sha256 vai no registro de entrega.

setup() {
  F="$BATS_TEST_DIRNAME/../faixa-do-modelo.sh"
  A="$BATS_TEST_DIRNAME/../avaliar-troca-de-modelo.sh"
  D="$BATS_TEST_TMPDIR"
  printf 'economico\tb\tmb\t1\t5\t0.1\npadrao\tm\tmm\t2\t10\t0.2\nmaximo\tf\tmf\t10\t50\t1\n' > "$D/t.tsv"
}

@test "QA-1: toda classe listada por --classes e aceita por --classe e devolve a mesma faixa" {
  run sh "$F" --classes
  [ "$status" -eq 0 ]
  while read -r classe faixa; do
    run sh "$F" --classe "$classe" --tabela "$D/t.tsv"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "faixa: $faixa" ]
  done <<< "$output"
}

@test "QA-2: --toca tolera espaco apos a virgula e item repetido, e so sobe uma vez" {
  run sh "$F" --classe teste --toca "contrato, auth" --tabela "$D/t.tsv"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "faixa: maximo" ]
  [ "${lines[1]}" = "motivo: classe teste e padrao; toca auth sobe para maximo" ]
  run sh "$F" --classe teste --toca schema,schema --tabela "$D/t.tsv"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "motivo: classe teste e padrao; toca schema sobe para maximo" ]
}

@test "QA-3: tabela com linha de comentario no meio e com so tres colunas ainda resolve o modelo" {
  printf 'economico\tb\tmb\n# meio\npadrao\tm\tmm\n' > "$D/curta.tsv"
  run sh "$F" --classe commit --tabela "$D/curta.tsv"
  [ "$status" -eq 0 ]
  [ "${lines[2]}" = "modelo: b (mb)" ]
}

@test "QA-4: avaliar com tabela de tres colunas falha com 2, nao divide por campo vazio" {
  printf 'economico\tb\tmb\nmaximo\tf\tmf\n' > "$D/curta.tsv"
  run sh "$A" --de maximo --para economico --saida 10 --transposicao 1 --tabela "$D/curta.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"modelo desconhecido na tabela"* ]]
}

@test "QA-5: transposicao zero e saida zero nao quebram a conta" {
  # saida 0 e leitura 100: ficar 0.0010; trocar paga o retorno minimo de 200 tokens no forte (0.0020): FICAR
  run sh "$A" --de maximo --para economico --saida 0 --leitura 100 --transposicao 0 --tabela "$D/t.tsv"
  [ "$status" -eq 3 ]
  [[ "$output" == *"ficar: 0.0010 USD"* ]]
  [[ "$output" == *"trocar: 0.0021 USD"* ]]
  run sh "$A" --de maximo --para economico --saida 0 --leitura 0 --transposicao 0 --tabela "$D/t.tsv"
  [ "$status" -eq 3 ]
  [[ "$output" == *"economia: -0.0020 USD (0.0%)"* ]]
}

@test "QA-6: retrabalho 100 iguala trocar a ficar mais o custo da troca: sempre FICAR" {
  run sh "$A" --de maximo --para economico --saida 1000 --leitura 10000 --transposicao 1 --retrabalho 100 --tabela "$D/t.tsv"
  [ "$status" -eq 3 ]
}

@test "QA-7: pacote vazio conta zero tokens de transposicao" {
  : > "$D/vazio.md"
  run sh "$A" --de maximo --para economico --saida 100 --pacote "$D/vazio.md" --tabela "$D/t.tsv"
  [[ "$output" == *"transposicao=0 "* ]]
}

@test "QA-8: numero negativo e rejeitado como nao inteiro" {
  run sh "$A" --de maximo --para economico --saida -5 --transposicao 1 --tabela "$D/t.tsv"
  [ "$status" -eq 2 ]
  run sh "$A" --de maximo --para economico --saida 5 --transposicao 1 --cache -1 --tabela "$D/t.tsv"
  [ "$status" -eq 2 ]
}

@test "QA-9: ponto de equilibrio e consistente com o veredito nas duas bordas" {
  run sh "$A" --de maximo --para economico --saida 1000 --leitura 10000 --transposicao 1000 --tabela "$D/t.tsv"
  eq=$(printf '%s\n' "$output" | sed -n 's/^equilibrio: transposicao de ate \([0-9]*\) tokens$/\1/p')
  [ -n "$eq" ]
  run sh "$A" --de maximo --para economico --saida 1000 --leitura 10000 --transposicao "$eq" --tabela "$D/t.tsv"
  [ "$status" -eq 0 ]
  run sh "$A" --de maximo --para economico --saida 1000 --leitura 10000 --transposicao $((eq + 1)) --tabela "$D/t.tsv"
  [ "$status" -eq 3 ]
}

@test "QA-10: scripts rodam em bash como sh (dialeto do shebang nao e dash-only)" {
  run bash "$F" --classe redacao --tabela "$D/t.tsv"
  [ "$status" -eq 0 ]
  run bash "$A" --de maximo --para economico --saida 1000 --leitura 10000 --transposicao 1000 --tabela "$D/t.tsv"
  [ "$status" -eq 0 ]
}
