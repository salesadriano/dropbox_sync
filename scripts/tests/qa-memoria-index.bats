#!/usr/bin/env bats
# Suite independente do QA Expert para scripts/memoria-index.sh (--desde, --todas, AVISO de `agentes: todos`).
# Complementa scripts/tests/memoria-index.bats: borda exata da data, combinacao de filtros, isencao por sufixo.
# Validacao: docs/reviews/2026-10-15-0914-skills-dos-mods-validacao-qa.md

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/raiz/scripts" "$BATS_TEST_TMPDIR/raiz/.github/agents/memoria/entradas"
  cp "$BATS_TEST_DIRNAME/../memoria-index.sh" "$BATS_TEST_TMPDIR/raiz/scripts/"
  SCRIPT="$BATS_TEST_TMPDIR/raiz/scripts/memoria-index.sh"
  ENTRADAS="$BATS_TEST_TMPDIR/raiz/.github/agents/memoria/entradas"
}

entrada() {  # $1 = nome (sem .md), $2 = tipo, $3 = escopo, $4 = status, $5 = agentes, $6 = data do campo (opcional)
  cat > "$ENTRADAS/$1.md" <<EOF
---
id: $1
tipo: $2
escopo: $3
titulo: Entrada $1
data: ${6:-2026-09-25}
dono: Tech Lead
agentes: $5
status: $4
---

Corpo de $1.
EOF
}

@test "QA: --desde e inclusivo no limite exato: a entrada do mesmo dia entra, a da vespera nao" {
  entrada 2026-09-14-2359-vespera decisao pacote ativa todos
  entrada 2026-09-15-0000-no-dia decisao pacote ativa todos
  entrada 2026-09-15-2359-fim-do-dia decisao pacote ativa todos
  entrada 2026-09-16-0001-depois decisao pacote ativa todos
  run sh "$SCRIPT" --desde 2026-09-15
  [ "$status" -eq 0 ]
  [[ "$output" != *"2026-09-14-2359-vespera"* ]]
  [[ "$output" == *"2026-09-15-0000-no-dia"* ]]
  [[ "$output" == *"2026-09-15-2359-fim-do-dia"* ]]
  [[ "$output" == *"2026-09-16-0001-depois"* ]]
}

@test "QA: --desde filtra pelo nome do arquivo e nao pelo campo data: do frontmatter" {
  entrada 2026-08-01-0900-nome-antigo decisao pacote ativa todos 2026-10-10
  entrada 2026-10-10-0900-nome-novo decisao pacote ativa todos 2026-08-01
  run sh "$SCRIPT" --desde 2026-10-01
  [ "$status" -eq 0 ]
  [[ "$output" != *"2026-08-01-0900-nome-antigo"* ]]
  [[ "$output" == *"2026-10-10-0900-nome-novo"* ]]
}

@test "QA: --desde combinado com --agente mantem so a intersecao (papel certo E data certa)" {
  entrada 2026-08-01-0900-qa-antiga decisao projeto ativa qa-expert
  entrada 2026-10-01-0900-qa-nova decisao projeto ativa "tech-lead, qa-expert"
  entrada 2026-10-02-0900-dba-nova decisao projeto ativa dba
  entrada 2026-10-03-0900-todos-nova decisao pacote ativa todos
  run sh "$SCRIPT" --agente qa-expert --desde 2026-09-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"agente=qa-expert desde=2026-09-01"* ]]
  [[ "$output" != *"2026-08-01-0900-qa-antiga"* ]]
  [[ "$output" == *"2026-10-01-0900-qa-nova"* ]]
  [[ "$output" != *"2026-10-02-0900-dba-nova"* ]]
  [[ "$output" == *"2026-10-03-0900-todos-nova"* ]]
}

@test "QA: --desde combinado com --tipo e --todas: reserva encerrada recente entra, decisao recente nao" {
  entrada 2026-10-01-0900-reserva-encerrada reserva pacote encerrada tech-lead
  entrada 2026-10-02-0900-decisao-ativa decisao pacote ativa todos
  entrada 2026-08-01-0900-reserva-antiga reserva pacote encerrada tech-lead
  run sh "$SCRIPT" --todas --tipo reserva --desde 2026-09-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-10-01-0900-reserva-encerrada"* ]]
  [[ "$output" != *"2026-10-02-0900-decisao-ativa"* ]]
  [[ "$output" != *"2026-08-01-0900-reserva-antiga"* ]]
}

@test "QA: --desde com --corpo imprime o corpo so das entradas dentro da janela" {
  entrada 2026-08-01-0900-fora decisao pacote ativa todos
  entrada 2026-10-01-0900-dentro decisao pacote ativa todos
  run sh "$SCRIPT" --desde 2026-09-01 --corpo
  [ "$status" -eq 0 ]
  [[ "$output" == *"Corpo de 2026-10-01-0900-dentro"* ]]
  [[ "$output" != *"Corpo de 2026-08-01-0900-fora"* ]]
}

@test "QA: --desde com mes 00, dia 00 ou letras sai com 2 antes de gerar o indice" {
  entrada 2026-10-01-0900-x decisao pacote ativa todos
  run sh "$SCRIPT" --desde 2026-00-10
  [ "$status" -eq 2 ]
  [[ "$output" != *"| Id |"* ]]
  run sh "$SCRIPT" --desde 2026-10-00
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --desde abcd-ef-gh
  [ "$status" -eq 2 ]
  [[ "$output" == *"data invalida em --desde: abcd-ef-gh"* ]]
}

@test "QA: --desde seguido de outra opcao como valor (--desde --corpo) e recusado com 2, nao consumido" {
  entrada 2026-10-01-0900-x decisao pacote ativa todos
  run sh "$SCRIPT" --desde --corpo
  [ "$status" -eq 2 ]
  [[ "$output" == *"data invalida em --desde: --corpo"* ]]
}

@test "QA: --todas seguido de --status ativa: a ultima opcao vence (ordem de linha de comando)" {
  entrada 2026-10-01-0900-fechada decisao pacote encerrada todos
  run sh "$SCRIPT" --todas --status ativa
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=ativa"* ]]
  [[ "$output" != *"2026-10-01-0900-fechada"* ]]
  run sh "$SCRIPT" --status ativa --todas
  [[ "$output" == *"status=todas"* ]]
  [[ "$output" == *"2026-10-01-0900-fechada"* ]]
}

@test "QA: --check avisa para aceite de pacote e para decisao de projeto com todos; uma linha por entrada; exit 0" {
  entrada 2026-10-01-0900-aceite aceite pacote ativa todos
  entrada 2026-10-02-0900-decisao-projeto decisao projeto ativa todos
  entrada 2026-10-03-0900-backlog backlog projeto ativa todos
  entrada 2026-10-04-0900-regra decisao pacote ativa todos
  run sh "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^AVISO ')" -eq 3 ]
  [[ "$output" == *"AVISO 2026-10-01-0900-aceite:"* ]]
  [[ "$output" == *"AVISO 2026-10-02-0900-decisao-projeto:"* ]]
  [[ "$output" == *"AVISO 2026-10-03-0900-backlog:"* ]]
  [[ "$output" != *"AVISO 2026-10-04-0900-regra:"* ]]
  [[ "$output" == *"entradas validas: 4"* ]]
}

@test "QA: a isencao de branch-principal vale por sufixo do nome, em qualquer tipo e escopo" {
  entrada 2026-10-01-0900-branch-principal reserva projeto ativa todos
  run sh "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" != *"AVISO"* ]]
}

@test "QA: LIMITE: nome que apenas termina em -branch-principal (outra-branch-principal) tambem e isento" {
  entrada 2026-10-01-0900-outra-branch-principal aceite projeto ativa todos
  run sh "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" != *"AVISO"* ]]
}

@test "QA: LIMITE: 'agentes: todos, qa-expert' nao e 'todos' para o AVISO, embora entre no bootstrap de todo papel" {
  entrada 2026-10-01-0900-misto aceite projeto ativa "todos, qa-expert"
  run sh "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" != *"AVISO"* ]]
  run sh "$SCRIPT" --agente dba
  [[ "$output" == *"2026-10-01-0900-misto"* ]]
}

@test "QA: --check ignora --desde: a entrada antiga com todos continua avisada e continua contada" {
  entrada 2026-08-01-0900-antiga aceite projeto ativa todos
  run sh "$SCRIPT" --check --desde 2026-10-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"AVISO 2026-08-01-0900-antiga:"* ]]
  [[ "$output" == *"entradas validas: 1"* ]]
}

@test "QA: o AVISO nao esconde o ERRO: entrada com todos fora do caso E agente invalido reprova com 1" {
  entrada 2026-10-01-0900-ruim aceite projeto ativa "todos"
  entrada 2026-10-02-0900-invalida aceite projeto ativa "todos, ninguem"
  run sh "$SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERRO 2026-10-02-0900-invalida: agente invalido 'ninguem'"* ]]
}

@test "QA: --desde que nao corta nada mantem todas as entradas e so muda a linha Filtros" {
  entrada 2026-10-01-0900-a decisao pacote ativa todos
  entrada 2026-10-02-0900-b decisao pacote ativa todos
  run sh "$SCRIPT" --desde 2026-01-01
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^| \[2026-')" -eq 2 ]
  [[ "$output" == *"desde=2026-01-01"* ]]
}
