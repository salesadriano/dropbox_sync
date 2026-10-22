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

# Mods 2 e 3 do projeto de origem: --desde, --todas e AVISO de `agentes: todos`.

entrada_em() {  # $1 = nome do arquivo (sem .md), $2 = tipo, $3 = escopo, $4 = status, $5 = agentes
  cat > "$BATS_TEST_TMPDIR/raiz/.github/agents/memoria/entradas/$1.md" <<EOF2
---
id: $1
tipo: $2
escopo: $3
titulo: Entrada $1
data: 2026-09-25
dono: Tech Lead
agentes: $5
status: $4
---

Corpo.
EOF2
}

@test "--desde filtra pela data do nome do arquivo e aparece na linha Filtros" {
  entrada_em 2026-09-01-0900-antiga decisao projeto ativa todos
  entrada_em 2026-10-01-0900-recente decisao projeto ativa todos
  run sh "$SCRIPT" --desde 2026-09-15
  [ "$status" -eq 0 ]
  [[ "$output" == *"desde=2026-09-15"* ]]
  [[ "$output" == *"2026-10-01-0900-recente"* ]]
  [[ "$output" != *"2026-09-01-0900-antiga"* ]]
}

@test "sem --desde a linha Filtros mostra desde=inicio e nada e filtrado por data" {
  entrada_em 2026-09-01-0900-antiga decisao projeto ativa todos
  run sh "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"desde=inicio"* ]]
  [[ "$output" == *"2026-09-01-0900-antiga"* ]]
}

@test "--desde sem valor sai com 2" {
  entrada_em 2026-09-01-0900-antiga decisao projeto ativa todos
  run sh "$SCRIPT" --desde
  [ "$status" -eq 2 ]
  [[ "$output" == *"--desde exige uma data"* ]]
}

@test "--desde com mes e dia fora do calendario sai com 2" {
  entrada_em 2026-09-01-0900-antiga decisao projeto ativa todos
  run sh "$SCRIPT" --desde 2026-13-45
  [ "$status" -eq 2 ]
  [[ "$output" == *"data invalida em --desde: 2026-13-45"* ]]
}

@test "--desde com forma invalida (2026-1-1) sai com 2" {
  entrada_em 2026-09-01-0900-antiga decisao projeto ativa todos
  run sh "$SCRIPT" --desde 2026-1-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"data invalida em --desde: 2026-1-1"* ]]
}

@test "--todas e atalho de --status todas: inclui entrada encerrada" {
  entrada_em 2026-09-01-0900-fechada decisao projeto encerrada todos
  run sh "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"2026-09-01-0900-fechada"* ]]
  run sh "$SCRIPT" --todas
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=todas"* ]]
  [[ "$output" == *"2026-09-01-0900-fechada"* ]]
}

@test "--check emite AVISO para agentes: todos em tipo reserva e continua com exit 0" {
  entrada_em 2026-09-01-0900-reserva reserva pacote ativa todos
  run sh "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"AVISO 2026-09-01-0900-reserva: 'agentes: todos' fora de tipo decisao + escopo pacote; nomeie os papeis (README das entradas)"* ]]
  [[ "$output" == *"entradas validas: 1"* ]]
}

@test "--check nao emite AVISO para tipo decisao + escopo pacote com agentes: todos" {
  entrada_em 2026-09-01-0900-regra decisao pacote ativa todos
  run sh "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" != *"AVISO"* ]]
}

@test "--check nao emite AVISO para a entrada branch-principal com agentes: todos (regra 46)" {
  entrada_em 2026-09-01-0900-branch-principal decisao projeto ativa todos
  run sh "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" != *"AVISO"* ]]
}

@test "--desde no limite exato: entrada com a mesma data entra, dia anterior sai (QA-SK-5)" {
  entrada_em 2026-09-14-2359-vespera decisao projeto ativa todos
  entrada_em 2026-09-15-0000-no-dia decisao projeto ativa todos
  run sh "$SCRIPT" --desde 2026-09-15
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-09-15-0000-no-dia"* ]]
  [[ "$output" != *"2026-09-14-2359-vespera"* ]]
}
