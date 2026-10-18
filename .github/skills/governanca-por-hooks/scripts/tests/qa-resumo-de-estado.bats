#!/usr/bin/env bats
# Suite independente do QA Expert para resumo-de-estado.sh (hook SessionStart).
# Complementa resumo-de-estado.bats: entrada branch-principal substituida mais recente que a ativa; titulos,
# reservas e saida do gh com $(...) e crase impressos literalmente; detector com exit 3 e saida vazia.
# Validacao: docs/reviews/2026-10-15-0914-skills-dos-mods-validacao-qa.md

setup() {
  RAIZ="$BATS_TEST_TMPDIR/raiz"
  mkdir -p "$RAIZ/scripts" "$RAIZ/.github/agents/memoria/entradas"
  cp "$BATS_TEST_DIRNAME/../resumo-de-estado.sh" "$RAIZ/scripts/"
  SCRIPT="$RAIZ/scripts/resumo-de-estado.sh"
  ENTRADAS="$RAIZ/.github/agents/memoria/entradas"
  MARCA="$BATS_TEST_TMPDIR/marca"
}

entrada() {  # $1 = nome (sem .md), $2 = tipo, $3 = status, $4 = titulo
  printf -- '---\nid: %s\ntipo: %s\nescopo: projeto\ntitulo: %s\nstatus: %s\n---\n\nCorpo.\n' "$1" "$2" "$4" "$3" > "$ENTRADAS/$1.md"
}

path_restrito() {
  B="$BATS_TEST_TMPDIR/bin"; mkdir -p "$B"
  for b in cat printf tr awk git grep sed tail head basename dirname wc sort sh; do ln -sf "$(command -v "$b")" "$B/$b"; done
}

@test "QA: branch-principal substituida (mais recente) e ignorada e a ativa mais antiga declara a branch" {
  entrada 2026-09-19-1124-branch-principal decisao ativa 'Branch principal do projeto e `main`'
  entrada 2026-10-10-0900-branch-principal decisao substituida 'Branch principal do projeto e `develop`'
  entrada 2026-10-11-0900-branch-principal decisao encerrada 'Branch principal do projeto e `trunk`'
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch principal declarada: main"* ]]
  [[ "$output" != *"declarada: develop"* ]]
  [[ "$output" != *"declarada: trunk"* ]]
}

@test "QA: duas entradas branch-principal ativas: vence a de nome mais recente, nao a de data: mais recente" {
  entrada 2026-09-19-1124-branch-principal decisao ativa 'Branch principal do projeto e `main`'
  entrada 2026-10-10-0900-branch-principal decisao ativa 'Branch principal do projeto e `develop`'
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch principal declarada: develop"* ]]
}

@test "QA: SEGURANCA: titulo da entrada branch-principal com \cifrao-parenteses e crase e impresso literal, sem executar" {
  entrada 2026-09-19-1124-branch-principal decisao ativa "Branch principal e \`\$(touch $MARCA.titulo)\` mesmo"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [ ! -e "$MARCA.titulo" ]
  [[ "$output" == *'branch principal declarada: $(touch'* ]]
}

@test "QA: SEGURANCA: titulo de reserva com \cifrao-parenteses, crase e ; e impresso literal, sem executar" {
  entrada 2026-10-01-0900-reserva-x reserva ativa "Reserva - \$(touch $MARCA.reserva); \`touch $MARCA.r2\`"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [ ! -e "$MARCA.reserva" ] && [ ! -e "$MARCA.r2" ]
  [[ "$output" == *"reservas ativas de escopo: 1"* ]]
  [[ "$output" == *'2026-10-01-0900-reserva-x: Reserva - $(touch'* ]]
}

@test "QA: SEGURANCA: saida do gh com \cifrao-parenteses e crase e impressa literal, sem executar" {
  path_restrito
  printf '#!/bin/sh\necho "  #9 [main <- feature/x] Titulo \\$(touch %s.gh) \\`touch %s.gh2\\`"\n' "$MARCA" "$MARCA" > "$B/gh"; chmod +x "$B/gh"
  run env -i PATH="$B" HOME="$HOME" sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [ ! -e "$MARCA.gh" ] && [ ! -e "$MARCA.gh2" ]
  [[ "$output" == *'Titulo $(touch'* ]]
}

@test "QA: SEGURANCA: saida do detector com \cifrao-parenteses e impressa literal e identada, sem executar" {
  printf '#!/usr/bin/env sh\n[ "$1" = --detectar ] || exit 2\necho "ARQUIVO \\$(touch %s.det)"\nexit 3\n' "$MARCA" > "$RAIZ/scripts/alteracoes-externas.sh"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [ ! -e "$MARCA.det" ]
  [[ "$output" == *'  ARQUIVO $(touch'* ]]
}

@test "QA: detector com exit 3 e saida vazia: DIVERGENCIA sem linha identada e exit 0" {
  printf '#!/usr/bin/env sh\nexit 3\n' > "$RAIZ/scripts/alteracoes-externas.sh"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DIVERGENCIA (exit 3)"* ]]
}

@test "QA: reserva com 'status: ativa' so no corpo (nao no frontmatter) ainda conta como ativa (limite: grep sem ancora de secao)" {
  printf -- '---\nid: 2026-10-01-0900-reserva-y\ntipo: reserva\ntitulo: Reserva - y\nstatus: encerrada\n---\n\nAntes era\nstatus: ativa\n' > "$ENTRADAS/2026-10-01-0900-reserva-y.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reservas ativas de escopo: 1"* ]]
}

@test "QA: --raiz com caminho relativo e aceito e o verificador roda a partir dele" {
  cd "$BATS_TEST_TMPDIR"
  run sh "$SCRIPT" --raiz raiz --verificador 'pwd'
  [ "$status" -eq 0 ]
  [[ "$output" == *"verificador: ok ($(cd "$RAIZ" && pwd -P))"* ]]
}

@test "QA: o resumo imprime as sete linhas na mesma ordem, com ou sem fontes disponiveis" {
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  ordem=$(printf '%s\n' "$output" | grep -oE '^(branch principal declarada|remoto \(origin\)|branch atual|reservas ativas de escopo|PRs abertas|worktrees|alteracoes nao realizadas pelos agents|verificador):' | tr '\n' ' ')
  [ "$ordem" = "branch principal declarada: remoto (origin): branch atual: reservas ativas de escopo: PRs abertas: worktrees: alteracoes nao realizadas pelos agents: verificador: " ]
}

@test "QA: roda em dash e em bash com a mesma saida" {
  entrada 2026-09-19-1124-branch-principal decisao ativa 'Branch principal do projeto e `main`'
  a=$(dash "$SCRIPT" --raiz "$RAIZ")
  b=$(bash "$SCRIPT" --raiz "$RAIZ")
  [ "$a" = "$b" ]
  [[ "$a" == *"branch principal declarada: main"* ]]
}
