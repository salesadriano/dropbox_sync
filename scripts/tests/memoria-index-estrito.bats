#!/usr/bin/env bats
# Testes de scripts/memoria-index.sh --check --estrito: `todos` fora de decisao de pacote e erro; lista longa de papeis avisa.

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/raiz/scripts" "$BATS_TEST_TMPDIR/raiz/.github/agents/memoria/entradas"
  cp "$BATS_TEST_DIRNAME/../memoria-index.sh" "$BATS_TEST_TMPDIR/raiz/scripts/"
  SCRIPT="$BATS_TEST_TMPDIR/raiz/scripts/memoria-index.sh"
  DIR="$BATS_TEST_TMPDIR/raiz/.github/agents/memoria/entradas"
}

entrada() {  # $1 nome, $2 tipo, $3 escopo, $4 agentes
  printf -- '---\nid: %s\ntipo: %s\nescopo: %s\ntitulo: T\ndata: 2026-10-01\ndono: Tech Lead\nagentes: %s\nstatus: ativa\n---\n\nCorpo.\n' "$1" "$2" "$3" "$4" > "$DIR/$1.md"
}

@test "com --estrito, todos fora de decisao de pacote e ERRO (exit 1); decisao de pacote e branch-principal passam" {
  entrada 2026-10-01-1000-aceite aceite projeto todos
  run sh "$SCRIPT" --check --estrito
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERRO 2026-10-01-1000-aceite: 'agentes: todos'"* ]]
  rm "$DIR/2026-10-01-1000-aceite.md"
  entrada 2026-10-01-1000-regra decisao pacote todos
  entrada 2026-10-01-1001-branch-principal decisao projeto todos
  run sh "$SCRIPT" --check --estrito
  [ "$status" -eq 0 ]
  [[ "$output" == *"entradas validas: 2"* ]]
}
