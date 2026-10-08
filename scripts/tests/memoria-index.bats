#!/usr/bin/env bats
# Testes da validacao de origem em scripts/memoria-index.sh --check.
# O script resolve a raiz pelo proprio caminho, entao e copiado para uma arvore descartavel.

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/raiz/scripts" "$BATS_TEST_TMPDIR/raiz/.github/agents/memoria/entradas"
  cp "$BATS_TEST_DIRNAME/../memoria-index.sh" "$BATS_TEST_TMPDIR/raiz/scripts/"
  SCRIPT="$BATS_TEST_TMPDIR/raiz/scripts/memoria-index.sh"
}

entrada() {  # $1 = origem
  cat > "$BATS_TEST_TMPDIR/raiz/.github/agents/memoria/entradas/2026-09-25-0755-exemplo.md" <<EOF
---
id: 2026-09-25-0755-exemplo
tipo: aceite
escopo: projeto
titulo: Exemplo
data: 2026-09-25
dono: Tech Lead
agentes: todos
status: ativa
origem: $1
---

Corpo.
EOF
}

@test "origem intervencao-humana e aceita" {
  entrada intervencao-humana
  run sh "$SCRIPT" --check
  [ "$status" -eq 0 ]
}

@test "origem desconhecida e recusada" {
  entrada manual
  run sh "$SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"origem invalida 'manual'"* ]]
}
