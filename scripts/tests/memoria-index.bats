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

@test "--desde sem valor sai com 2" {
  entrada_em 2026-09-01-0900-antiga decisao projeto ativa todos
  run sh "$SCRIPT" --desde
  [ "$status" -eq 2 ]
  [[ "$output" == *"--desde exige uma data"* ]]
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

@test "--check reprova a entrada com id, tipo, escopo, status e campos obrigatorios invalidos e nomeia cada erro" {
  cat > "$BATS_TEST_TMPDIR/raiz/.github/agents/memoria/entradas/entrada-fora-do-padrao.md" <<'EOF2'
---
id: outro-id
tipo: rascunho
escopo: global
status: pendente
---

Corpo.
EOF2
  run sh "$SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERRO entrada-fora-do-padrao: id 'outro-id' difere do nome do arquivo"* ]]
  [[ "$output" == *"ERRO entrada-fora-do-padrao: tipo invalido 'rascunho'"* ]]
  [[ "$output" == *"ERRO entrada-fora-do-padrao: escopo invalido 'global'"* ]]
  [[ "$output" == *"ERRO entrada-fora-do-padrao: status invalido 'pendente'"* ]]
  [[ "$output" == *"ERRO entrada-fora-do-padrao: data ausente"* ]]
  [[ "$output" == *"ERRO entrada-fora-do-padrao: dono ausente"* ]]
  [[ "$output" == *"ERRO entrada-fora-do-padrao: titulo ausente"* ]]
  [[ "$output" == *"ERRO entrada-fora-do-padrao: agentes ausente"* ]]
  [[ "$output" == *"ERRO entrada-fora-do-padrao: nome fora do padrao YYYY-MM-DD-HHMM-slug"* ]]
  [[ "$output" != *"entradas validas"* ]]
}

@test "--escopo e --tipo isolados filtram o indice e --agente tech-lead ve toda a memoria" {
  entrada_em 2026-09-01-0900-dec-proj decisao projeto ativa dba
  entrada_em 2026-09-02-0900-ace-proj aceite projeto ativa dba
  entrada_em 2026-09-03-0900-dec-pac decisao pacote ativa qa-expert
  run sh "$SCRIPT" --escopo pacote
  [ "$status" -eq 0 ]
  [[ "$output" == *"escopo=pacote tipo=todos"* ]]
  [[ "$output" == *"2026-09-03-0900-dec-pac"* ]]
  [[ "$output" != *"2026-09-01-0900-dec-proj"* ]]
  [[ "$output" != *"2026-09-02-0900-ace-proj"* ]]
  run sh "$SCRIPT" --tipo aceite
  [ "$status" -eq 0 ]
  [[ "$output" == *"escopo=todos tipo=aceite"* ]]
  [[ "$output" == *"2026-09-02-0900-ace-proj"* ]]
  [[ "$output" != *"2026-09-01-0900-dec-proj"* ]]
  [[ "$output" != *"2026-09-03-0900-dec-pac"* ]]
  run sh "$SCRIPT" --agente tech-lead
  [ "$status" -eq 0 ]
  [[ "$output" == *"agente=tech-lead (tudo)"* ]]
  [[ "$output" == *"2026-09-01-0900-dec-proj"* ]]
  [[ "$output" == *"2026-09-02-0900-ace-proj"* ]]
  [[ "$output" == *"2026-09-03-0900-dec-pac"* ]]
}
