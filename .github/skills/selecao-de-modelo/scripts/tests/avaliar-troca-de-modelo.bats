#!/usr/bin/env bats
# Testes de avaliar-troca-de-modelo.sh: a troca so compensa quando a economia supera a transposicao.
# Tabela de teste com precos redondos para contas conferiveis a mao (USD por milhao de tokens):
#   forte: in 10, out 50, cache 1 | barato: in 1, out 5, cache 0.1

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../avaliar-troca-de-modelo.sh"
  D="$BATS_TEST_TMPDIR"
  printf 'maximo\tforte\tmodelo-f\t10\t50\t1\neconomico\tbarato\tmodelo-b\t1\t5\t0.1\n' > "$D/t.tsv"
}

# ficar = 10000*10 + 0 + 1000*50 = 150000 /1e6 = 0.15
# trocar = 1000*50 (pacote no forte) + (1000+10000)*1 + 1000*5 + 200*10 = 50000+11000+5000+2000 = 68000 -> 0.068
@test "documento de 1000 tokens com 10000 lidos e pacote de 1000: trocar compensa, contas conferidas" {
  run sh "$SCRIPT" --de maximo --para economico --saida 1000 --leitura 10000 --transposicao 1000 --tabela "$D/t.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ficar: 0.1500 USD"* ]]
  [[ "$output" == *"trocar: 0.0680 USD"* ]]
  [[ "$output" == *"economia: 0.0820 USD (54.7%)"* ]]
  [[ "$output" == *"veredito: TROCAR"* ]]
}

# ponto de equilibrio: ficar - fixo = 150000 - 17000 = 133000; porT = 50 + 1 = 51 -> 2607 tokens
@test "informa o ponto de equilibrio da transposicao" {
  run sh "$SCRIPT" --de maximo --para economico --saida 1000 --leitura 10000 --transposicao 1000 --tabela "$D/t.tsv"
  [[ "$output" == *"equilibrio: transposicao de ate 2607 tokens"* ]]
}

@test "transposicao acima do equilibrio: FICAR com exit 3" {
  run sh "$SCRIPT" --de maximo --para economico --saida 1000 --leitura 10000 --transposicao 3000 --tabela "$D/t.tsv"
  [ "$status" -eq 3 ]
  [[ "$output" == *"veredito: FICAR"* ]]
  [[ "$output" == *"economia: -"* ]]
}

# cache perdido vira entrada nova no barato: ficar = 50000*1 + 100*50 = 55000; trocar = 100*50 + (100+50000)*1 + 100*5 + 200*10 = 5000+50100+500+2000 = 57600
@test "cache grande no modelo atual pesa contra a troca" {
  run sh "$SCRIPT" --de forte --para barato --saida 100 --cache 50000 --transposicao 100 --tabela "$D/t.tsv"
  [ "$status" -eq 3 ]
  [[ "$output" == *"ficar: 0.0550 USD"* ]]
  [[ "$output" == *"trocar: 0.0576 USD"* ]]
}

# retrabalho de 50%: trocar ganha 0.5*ficar = 0.075 -> 0.068 + 0.075 = 0.143 < 0.15 ainda TROCAR; com 60%: 0.158 FICAR
@test "probabilidade de retrabalho entra no custo da troca" {
  run sh "$SCRIPT" --de maximo --para economico --saida 1000 --leitura 10000 --transposicao 1000 --retrabalho 50 --tabela "$D/t.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"trocar: 0.1430 USD"* ]]
  run sh "$SCRIPT" --de maximo --para economico --saida 1000 --leitura 10000 --transposicao 1000 --retrabalho 60 --tabela "$D/t.tsv"
  [ "$status" -eq 3 ]
}

@test "--pacote estima a transposicao por bytes/4, arredondando para cima" {
  head -c 4001 /dev/zero | tr '\0' 'a' > "$D/pacote.md"
  run sh "$SCRIPT" --de maximo --para economico --saida 1000 --leitura 10000 --pacote "$D/pacote.md" --tabela "$D/t.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"transposicao=1001 "* ]]
}

@test "retorno padrao e 10% da saida com minimo de 200" {
  run sh "$SCRIPT" --de maximo --para economico --saida 5000 --transposicao 10 --tabela "$D/t.tsv"
  [[ "$output" == *"retorno=500 "* ]]
  run sh "$SCRIPT" --de maximo --para economico --saida 100 --transposicao 10 --tabela "$D/t.tsv"
  [[ "$output" == *"retorno=200 "* ]]
}

@test "subir de faixa (barato para forte) tambem e calculado, e normalmente nao economiza" {
  run sh "$SCRIPT" --de economico --para maximo --saida 1000 --leitura 1000 --transposicao 100 --tabela "$D/t.tsv"
  [ "$status" -eq 3 ]
  [[ "$output" == *"equilibrio: nenhum"* ]]
}

@test "mesmo modelo nos dois lados: FICAR sem calculo" {
  run sh "$SCRIPT" --de forte --para maximo --saida 1000 --transposicao 10 --tabela "$D/t.tsv"
  [ "$status" -eq 3 ]
  [[ "$output" == *"veredito: FICAR (mesmo modelo"* ]]
}

@test "alias e faixa sao intercambiaveis na tabela" {
  run sh "$SCRIPT" --de forte --para barato --saida 1000 --leitura 10000 --transposicao 1000 --tabela "$D/t.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"de: forte (modelo-f)"* ]]
  [[ "$output" == *"para: barato (modelo-b)"* ]]
}

@test "uso invalido sai com 2: falta de argumento, valor nao inteiro, retrabalho fora de 0-100, modelo desconhecido, pacote e transposicao juntos" {
  run sh "$SCRIPT" --de forte --saida 10 --transposicao 1 --tabela "$D/t.tsv"
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --de forte --para barato --transposicao 1 --tabela "$D/t.tsv"
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --de forte --para barato --saida dez --transposicao 1 --tabela "$D/t.tsv"
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --de forte --para barato --saida 10 --transposicao 1 --retrabalho 101 --tabela "$D/t.tsv"
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --de forte --para gigante --saida 10 --transposicao 1 --tabela "$D/t.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"modelo desconhecido na tabela: gigante"* ]]
  run sh "$SCRIPT" --de forte --para barato --saida 10 --transposicao 1 --pacote "$D/t.tsv" --tabela "$D/t.tsv"
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --de forte --para barato --saida 10 --tabela "$D/t.tsv"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--transposicao"* ]]
}

@test "pacote inexistente e tabela inexistente saem com 1" {
  run sh "$SCRIPT" --de forte --para barato --saida 10 --pacote "$D/nao.md" --tabela "$D/t.tsv"
  [ "$status" -eq 1 ]
  run sh "$SCRIPT" --de forte --para barato --saida 10 --transposicao 1 --tabela "$D/nao.tsv"
  [ "$status" -eq 1 ]
}

@test "sem --tabela usa o exemplo de references com os aliases do cliente" {
  run sh "$SCRIPT" --de opus --para haiku --saida 2000 --leitura 5000 --transposicao 800
  [ "$status" -eq 0 ]
  [[ "$output" == *"de: opus (claude-opus-5-5)"* ]]
  [[ "$output" == *"veredito: TROCAR"* ]]
}
