#!/usr/bin/env bats
# Suite independente do QA Expert para conferir-copias.sh.
# Complementa conferir-copias.bats: ERE com =, /, # e |; zero a esquerda; grupo escapado; mesmo arquivo duas vezes;
# valor nao numerico; ancora ^; limites declarados ([(] e caminho com =).
# Validacao: docs/reviews/2026-10-15-0914-skills-dos-mods-validacao-qa.md

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../conferir-copias.sh"
  D="$BATS_TEST_TMPDIR"
  printf 'export const ROTAS = 168;\n' > "$D/a.ts"
  printf 'TOTAL=168 OK\n' > "$D/b.txt"
}

@test "QA: ERE com = e / dentro do padrao, caminho com / e separacao no PRIMEIRO =" {
  printf 'x=y/z=168\n' > "$D/c.txt"
  run sh "$SCRIPT" "$D/c.txt=x=y/z=([0-9]+)" "$D/b.txt=TOTAL=([0-9]+)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"168 igual em 2 copia(s)"* ]]
}

@test "QA: ERE com # e | fora do grupo, e com o delimitador \\001 ausente do texto" {
  printf 'a#168#b\n' > "$D/c.txt"
  run sh "$SCRIPT" "$D/c.txt=a#([0-9]+)#b|nada" "$D/b.txt=TOTAL=([0-9]+)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"168 igual em 2 copia(s)"* ]]
}

@test "QA: zero a esquerda e divergencia textual (0168 != 168): exit 1 com os dois valores listados" {
  printf 'TOTAL=0168 OK\n' > "$D/b.txt"
  run sh "$SCRIPT" "$D/a.ts=ROTAS = ([0-9]+);" "$D/b.txt=TOTAL=([0-9]+)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- $D/a.ts: 168"* ]]
  [[ "$output" == *"- $D/b.txt: 0168"* ]]
}

@test "QA: parenteses escapados \\( \\) nao contam como grupo e o valor entre eles e capturado" {
  printf 'valor (168) aqui\n' > "$D/c.txt"
  run sh "$SCRIPT" "$D/c.txt=valor \\(([0-9]+)\\)" "$D/b.txt=TOTAL=([0-9]+)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"168 igual em 2 copia(s)"* ]]
}

@test "QA: LIMITE declarado: ( dentro de colchetes conta como grupo e a ERE e recusada com 2" {
  run sh "$SCRIPT" "$D/a.ts=ROTAS[(] = ([0-9]+)" "$D/b.txt=TOTAL=([0-9]+)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"exatamente um grupo"* ]]
}

@test "QA: LIMITE declarado: caminho de arquivo com = e cortado no primeiro = e recusado como arquivo inexistente" {
  printf 'TOTAL=168\n' > "$D/a=b.txt"
  run sh "$SCRIPT" "$D/a=b.txt=TOTAL=([0-9]+)" "$D/b.txt=TOTAL=([0-9]+)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"arquivo nao encontrado: $D/a"* ]]
}

@test "QA: o mesmo arquivo passado duas vezes com EREs diferentes conta como duas copias" {
  printf 'ROTAS = 168; // TOTAL=168\n' > "$D/a.ts"
  run sh "$SCRIPT" "$D/a.ts=ROTAS = ([0-9]+);" "$D/a.ts=TOTAL=([0-9]+)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"168 igual em 2 copia(s)"* ]]
}

@test "QA: valor nao numerico (palavra) tambem e conferido" {
  printf 'branch: main\n' > "$D/c.txt"
  printf 'principal e `main`\n' > "$D/d.md"
  run sh "$SCRIPT" --rotulo branch "$D/c.txt=branch: ([a-z]+)" "$D/d.md=principal e \`([a-z]+)\`"
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch: main igual em 2 copia(s)"* ]]
}

@test "QA: ERE ancorada com ^ so le o inicio da linha; o mesmo padrao no meio da linha nao conta" {
  printf 'ROTAS = 168;\n// ROTAS = 170;\n' > "$D/a.ts"
  run sh "$SCRIPT" "$D/a.ts=^ROTAS = ([0-9]+);" "$D/b.txt=TOTAL=([0-9]+)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"168 igual em 2 copia(s)"* ]]
}

@test "QA: tres copias com duas divergentes listam as tres linhas e saem 1" {
  printf 'N=169\n' > "$D/c.txt"
  run sh "$SCRIPT" "$D/a.ts=ROTAS = ([0-9]+);" "$D/b.txt=TOTAL=([0-9]+)" "$D/c.txt=N=([0-9]+)"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^- ')" -eq 3 ]
  [[ "$output" == *"copias: copias divergem"* ]]
}

@test "QA: --rotulo depois de uma copia e recusado como opcao desconhecida (limite declarado no cabecalho)" {
  run sh "$SCRIPT" "$D/a.ts=ROTAS = ([0-9]+);" --rotulo x "$D/b.txt=TOTAL=([0-9]+)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"opcao desconhecida: --rotulo"* ]]
}

@test "QA: SEGURANCA: ERE e rotulo com \cifrao-parenteses e crase nao sao expandidos nem executados" {
  MARCA="$D/marca"
  run sh "$SCRIPT" --rotulo "\$(touch $MARCA.r)" "$D/a.ts=ROTAS = ([0-9]+);\$(touch $MARCA.e)" "$D/b.txt=TOTAL=([0-9]+)"
  [ ! -e "$MARCA.r" ] && [ ! -e "$MARCA.e" ]
  [ "$status" -eq 2 ]
  [[ "$output" == *'achei 2: ROTAS = ([0-9]+);$(touch'* ]]
  run sh "$SCRIPT" --rotulo "\$(touch $MARCA.r2)" "$D/a.ts=ROTAS = ([0-9]+);" "$D/b.txt=TOTAL=([0-9]+)"
  [ ! -e "$MARCA.r2" ]
  [ "$status" -eq 0 ]
  [[ "$output" == *'$(touch'*': 168 igual em 2 copia(s)'* ]]
}

@test "QA: valor com espaco interno dentro do grupo e preservado inteiro" {
  printf 'estado: em aberto\n' > "$D/c.txt"
  printf 'situacao=em aberto;\n' > "$D/d.txt"
  run sh "$SCRIPT" "$D/c.txt=estado: ([a-z ]+)" "$D/d.txt=situacao=([a-z ]+);"
  [ "$status" -eq 0 ]
  [[ "$output" == *"copias: em aberto igual em 2 copia(s)"* ]]
}

@test "QA: roda em dash e em bash com a mesma saida" {
  a=$(dash "$SCRIPT" "$D/a.ts=ROTAS = ([0-9]+);" "$D/b.txt=TOTAL=([0-9]+)")
  b=$(bash "$SCRIPT" "$D/a.ts=ROTAS = ([0-9]+);" "$D/b.txt=TOTAL=([0-9]+)")
  [ "$a" = "$b" ]
}
