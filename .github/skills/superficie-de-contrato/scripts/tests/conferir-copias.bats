#!/usr/bin/env bats
# Testes de conferir-copias.sh: N copias de um numero, em arquivos diferentes, dizem o mesmo valor.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../conferir-copias.sh"
  D="$BATS_TEST_TMPDIR"
  printf 'export const ROTAS = 168;\n' > "$D/matriz.ts"
  printf 'Superficie: **168 rotas** hoje.\n' > "$D/INSTRUCOES.md"
  printf "expect(x).toBe('TOTAL=168 OK');\n" > "$D/pino.spec.ts"
}

@test "copias iguais em tres arquivos: exit 0 e o valor no resumo" {
  run sh "$SCRIPT" "$D/matriz.ts=ROTAS = ([0-9]+);" "$D/INSTRUCOES.md=\*\*([0-9]+) rotas\*\*" "$D/pino.spec.ts=TOTAL=([0-9]+)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"copias: 168 igual em 3 copia(s)"* ]]
}

@test "copia divergente: lista arquivo e valor, e exit 1" {
  printf "expect(x).toBe('TOTAL=167 OK');\n" > "$D/pino.spec.ts"
  run sh "$SCRIPT" "$D/matriz.ts=ROTAS = ([0-9]+);" "$D/pino.spec.ts=TOTAL=([0-9]+)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- $D/matriz.ts: 168"* ]]
  [[ "$output" == *"- $D/pino.spec.ts: 167"* ]]
  [[ "$output" == *"copias: copias divergem"* ]]
}

@test "padrao ausente em um arquivo e erro, nao silencio" {
  run sh "$SCRIPT" "$D/matriz.ts=ROTAS = ([0-9]+);" "$D/INSTRUCOES.md=NAO_EXISTE=([0-9]+)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nao achei NAO_EXISTE=([0-9]+) em $D/INSTRUCOES.md"* ]]
}

@test "duas ocorrencias com valores diferentes no mesmo arquivo e erro" {
  printf 'export const ROTAS = 168;\n// ROTAS = 170;\n' > "$D/matriz.ts"
  run sh "$SCRIPT" "$D/matriz.ts=ROTAS = ([0-9]+);" "$D/pino.spec.ts=TOTAL=([0-9]+)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ROTAS = ([0-9]+); aparece 2 vez(es) com valores diferentes em $D/matriz.ts: 168, 170"* ]]
}

@test "ocorrencias repetidas com o mesmo valor no mesmo arquivo contam uma vez" {
  printf 'export const ROTAS = 168;\n// ROTAS = 168;\n' > "$D/matriz.ts"
  run sh "$SCRIPT" "$D/matriz.ts=ROTAS = ([0-9]+);" "$D/pino.spec.ts=TOTAL=([0-9]+)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"168 igual em 2 copia(s)"* ]]
}

@test "--rotulo nomeia o resumo" {
  run sh "$SCRIPT" --rotulo superficie "$D/matriz.ts=ROTAS = ([0-9]+);" "$D/pino.spec.ts=TOTAL=([0-9]+)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"superficie: 168 igual em 2 copia(s)"* ]]
}

@test "um argumento so sai 2" {
  run sh "$SCRIPT" "$D/matriz.ts=ROTAS = ([0-9]+);"
  [ "$status" -eq 2 ]
  [[ "$output" == *"pelo menos duas copias"* ]]
}

@test "argumento sem '=' sai 2" {
  run sh "$SCRIPT" "$D/matriz.ts" "$D/pino.spec.ts=TOTAL=([0-9]+)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"esperava <arquivo>=<ERE>"* ]]
}

@test "ERE sem grupo ou com mais de um grupo sai 2" {
  run sh "$SCRIPT" "$D/matriz.ts=ROTAS = [0-9]+;" "$D/pino.spec.ts=TOTAL=([0-9]+)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"exatamente um grupo"* ]]
  run sh "$SCRIPT" "$D/matriz.ts=(ROTAS) = ([0-9]+);" "$D/pino.spec.ts=TOTAL=([0-9]+)"
  [ "$status" -eq 2 ]
}

@test "arquivo inexistente sai 2" {
  run sh "$SCRIPT" "$D/nao-existe.ts=ROTAS = ([0-9]+);" "$D/pino.spec.ts=TOTAL=([0-9]+)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"arquivo nao encontrado: $D/nao-existe.ts"* ]]
}

@test "--rotulo sem valor e opcao desconhecida saem 2" {
  run sh "$SCRIPT" --rotulo
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --x "$D/matriz.ts=ROTAS = ([0-9]+);" "$D/pino.spec.ts=TOTAL=([0-9]+)"
  [ "$status" -eq 2 ]
}

@test "ERE com '=' no padrao e com '\\*\\*' escapado funciona; o primeiro '=' separa arquivo de ERE" {
  run sh "$SCRIPT" "$D/INSTRUCOES.md=\*\*([0-9]+) rotas\*\*" "$D/pino.spec.ts=TOTAL=([0-9]+) OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"168 igual em 2 copia(s)"* ]]
}

@test "ERE com '/' e com '|' dentro do grupo funciona" {
  printf 'caminho a/b/168/c\n' > "$D/x.txt"
  printf 'valor 168\n' > "$D/y.txt"
  run sh "$SCRIPT" "$D/x.txt=a/b/([0-9]+)/c" "$D/y.txt=valor ([0-9]+|nada)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"168 igual em 2 copia(s)"* ]]
}

@test "roda sob dash" {
  command -v dash >/dev/null 2>&1 || skip "dash nao instalado"
  run dash "$SCRIPT" "$D/matriz.ts=ROTAS = ([0-9]+);" "$D/pino.spec.ts=TOTAL=([0-9]+)"
  [ "$status" -eq 0 ]
}
