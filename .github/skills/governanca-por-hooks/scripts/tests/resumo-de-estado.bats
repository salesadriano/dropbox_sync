#!/usr/bin/env bats
# Testes de resumo-de-estado.sh (hook SessionStart): imprime o estado e nunca falha a sessao.
# O script resolve a raiz pelo proprio caminho quando nao recebe --raiz, entao e copiado para uma
# arvore descartavel; os demais casos passam --raiz.

setup() {
  RAIZ="$BATS_TEST_TMPDIR/raiz"
  mkdir -p "$RAIZ/scripts" "$RAIZ/.github/agents/memoria/entradas"
  cp "$BATS_TEST_DIRNAME/../resumo-de-estado.sh" "$RAIZ/scripts/"
  SCRIPT="$RAIZ/scripts/resumo-de-estado.sh"
  ENTRADAS="$RAIZ/.github/agents/memoria/entradas"
}

repo_com_remoto() {
  git -C "$RAIZ" init -q
  git -C "$RAIZ" remote add origin git@example.com:dono/repo.git
}

entrada() {  # $1 = diretorio, $2 = nome (sem .md), $3 = tipo, $4 = status, $5 = titulo
  cat > "$1/$2.md" <<EOF
---
id: $2
tipo: $3
escopo: projeto
titulo: $5
data: 2026-09-25
dono: Tech Lead
agentes: todos
status: $4
---

Corpo.
EOF
}

path_restrito() {  # $@ = binarios a expor
  B="$BATS_TEST_TMPDIR/bin"; mkdir -p "$B"
  for b in "$@"; do ln -sf "$(command -v "$b")" "$B/$b"; done
}

# --- cabecalho, branch principal, remoto, branch atual ------------------------------------------

@test "imprime branch principal, remoto, branch atual, reservas, PRs e worktrees, com exit 0" {
  repo_com_remoto
  entrada "$ENTRADAS" 2026-09-25-1400-branch-principal decisao ativa 'A branch principal declarada do projeto e `develop`'
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"== resumo de estado"* ]]
  [[ "$output" == *"branch principal declarada: develop"* ]]
  [[ "$output" == *"remoto (origin): git@example.com:dono/repo.git"* ]]
  [[ "$output" == *"branch atual:"* ]]
  [[ "$output" == *"reservas ativas de escopo:"* ]]
  [[ "$output" == *"PRs abertas"* ]]
  [[ "$output" == *"worktrees:"* ]]
}

@test "raiz que nao e repositorio git e sem entradas: tudo indisponivel, exit 0" {
  rmdir "$ENTRADAS"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch principal declarada: indisponivel"* ]]
  [[ "$output" == *"remoto (origin): indisponivel"* ]]
  [[ "$output" == *"branch atual: indisponivel"* ]]
  [[ "$output" == *"reservas ativas de escopo: indisponivel"* ]]
  [[ "$output" == *"alteracoes nao realizadas pelos agents: indisponivel"* ]]
}

@test "repositorio sem remoto origin e sem commit: remoto indisponivel, branch 'HEAD (-)', exit 0" {
  git -C "$RAIZ" init -q
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"remoto (origin): indisponivel"* ]]
  [[ "$output" == *"branch atual: HEAD (-)"* ]]
  [[ "$output" == *"worktrees:"* ]]
}

@test "entrada branch-principal encerrada e ignorada; a ativa mais recente vence" {
  entrada "$ENTRADAS" 2026-09-25-1400-branch-principal decisao encerrada 'A branch principal declarada do projeto e `master`'
  entrada "$ENTRADAS" 2026-10-01-0900-branch-principal decisao ativa 'A branch principal declarada do projeto e `develop`'
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch principal declarada: develop"* ]]
  [[ "$output" != *"declarada: master"* ]]
}

@test "entrada ativa cujo titulo nao traz a branch entre crases: indisponivel com o nome do arquivo, exit 0" {
  entrada "$ENTRADAS" 2026-09-25-1400-branch-principal decisao ativa 'A branch principal e develop'
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch principal declarada: indisponivel (titulo sem crase em 2026-09-25-1400-branch-principal.md)"* ]]
}

@test "sem entrada branch-principal ativa: indisponivel com a orientacao da regra 46, exit 0" {
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch principal declarada: indisponivel (nenhuma entrada branch-principal ativa"* ]]
}

# --- diretorio de entradas: --entradas e fallback para .claude/ai_team ----------------------------

@test "--entradas explicito e usado no lugar do diretorio padrao" {
  OUTRO="$BATS_TEST_TMPDIR/outro"; mkdir -p "$OUTRO"
  entrada "$ENTRADAS" 2026-09-25-1400-branch-principal decisao ativa 'A branch principal declarada do projeto e `main`'
  entrada "$OUTRO" 2026-09-25-1400-branch-principal decisao ativa 'A branch principal declarada do projeto e `trunk`'
  run sh "$SCRIPT" --raiz "$RAIZ" --entradas "$OUTRO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch principal declarada: trunk"* ]]
}

@test "sem .github/agents/memoria/entradas, usa .claude/ai_team/memoria/entradas" {
  rmdir "$ENTRADAS"
  ALT="$RAIZ/.claude/ai_team/memoria/entradas"; mkdir -p "$ALT"
  entrada "$ALT" 2026-09-25-1400-branch-principal decisao ativa 'A branch principal declarada do projeto e `develop`'
  entrada "$ALT" 2026-10-01-0900-reserva-x reserva ativa 'Reserva - x'
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch principal declarada: develop"* ]]
  [[ "$output" == *"reservas ativas de escopo: 1"* ]]
}

@test "--entradas apontando para diretorio inexistente: fontes da memoria indisponiveis, exit 0" {
  run sh "$SCRIPT" --raiz "$RAIZ" --entradas "$BATS_TEST_TMPDIR/nao-existe"
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch principal declarada: indisponivel"* ]]
  [[ "$output" == *"reservas ativas de escopo: indisponivel"* ]]
}

# --- reservas ativas de escopo ------------------------------------------------------------------

@test "reservas ativas sao contadas e listadas por titulo; encerradas e outros tipos ficam de fora" {
  entrada "$ENTRADAS" 2026-10-01-0900-reserva-a reserva ativa 'Reserva - correcao do detector'
  entrada "$ENTRADAS" 2026-10-02-0900-reserva-b reserva ativa 'Reserva - skills dos mods'
  entrada "$ENTRADAS" 2026-10-03-0900-reserva-c reserva encerrada 'Reserva - antiga'
  entrada "$ENTRADAS" 2026-10-04-0900-decisao-d decisao ativa 'Decisao qualquer'
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reservas ativas de escopo: 2"* ]]
  [[ "$output" == *"  2026-10-01-0900-reserva-a: Reserva - correcao do detector"* ]]
  [[ "$output" == *"  2026-10-02-0900-reserva-b: Reserva - skills dos mods"* ]]
  [[ "$output" != *"Reserva - antiga"* ]]
  [[ "$output" != *"Decisao qualquer"* ]]
}

@test "sem reserva ativa imprime 'nenhuma'" {
  entrada "$ENTRADAS" 2026-10-03-0900-reserva-c reserva encerrada 'Reserva - antiga'
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reservas ativas de escopo: nenhuma"* ]]
}

# --- PRs abertas via gh --------------------------------------------------------------------------

@test "sem gh no PATH a linha de PRs diz 'gh ausente' e o exit continua 0" {
  path_restrito cat printf tr awk git grep sed tail head basename dirname wc sort sh
  run env -i PATH="$B" HOME="$HOME" sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRs abertas: indisponivel (gh ausente"* ]]
}

@test "gh presente mas sem acesso: 'gh sem acesso', exit 0" {
  path_restrito cat printf tr awk git grep sed tail head basename dirname wc sort sh
  printf '#!/bin/sh\necho "gh: not logged in" >&2\nexit 4\n' > "$B/gh"; chmod +x "$B/gh"
  run env -i PATH="$B" HOME="$HOME" sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRs abertas: indisponivel (gh sem acesso"* ]]
}

@test "gh que responde vazio imprime 'nenhuma'; gh que responde lista imprime a lista" {
  path_restrito cat printf tr awk git grep sed tail head basename dirname wc sort sh
  printf '#!/bin/sh\nexit 0\n' > "$B/gh"; chmod +x "$B/gh"
  run env -i PATH="$B" HOME="$HOME" sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRs abertas:"* ]]
  [[ "$output" == *"  nenhuma"* ]]
  printf '#!/bin/sh\necho "  #7 [main <- feature/x] Titulo"\n' > "$B/gh"
  run env -i PATH="$B" HOME="$HOME" sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"  #7 [main <- feature/x] Titulo"* ]]
}

# --- alteracoes nao realizadas pelos agents (regra 48) ---------------------------------------------

detector() {  # $1 = exit do stub, $2 = texto impresso
  printf '#!/usr/bin/env sh\n[ "$1" = --detectar ] || exit 2\necho "%s"\nexit %s\n' "$2" "$1" > "$RAIZ/scripts/alteracoes-externas.sh"
}

@test "sem scripts/alteracoes-externas.sh na raiz: indisponivel, exit 0" {
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alteracoes nao realizadas pelos agents: indisponivel (scripts/alteracoes-externas.sh nao encontrado)"* ]]
}

@test "detector com exit 0 imprime 'nenhuma'" {
  detector 0 ''
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alteracoes nao realizadas pelos agents: nenhuma"* ]]
}

@test "detector com exit 3 imprime DIVERGENCIA com a saida identada e o resumo ainda sai com 0" {
  detector 3 'ARQUIVO src/x.ts'
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alteracoes nao realizadas pelos agents: DIVERGENCIA (exit 3): pergunte ao solicitante antes de tocar"* ]]
  [[ "$output" == *"  ARQUIVO src/x.ts"* ]]
}

@test "detector com exit diferente de 0 e 3 (erro interno) vira indisponivel com o codigo, exit 0" {
  detector 1 'erro interno'
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alteracoes nao realizadas pelos agents: indisponivel (detector saiu com 1)"* ]]
  [[ "$output" == *"  erro interno"* ]]
}

# --- verificador em modo aviso --------------------------------------------------------------------

@test "sem --verificador a linha diz 'nao configurado'" {
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verificador: nao configurado"* ]]
}

@test "--verificador que sai com 0 imprime ok com a primeira linha da saida" {
  run sh "$SCRIPT" --raiz "$RAIZ" --verificador 'printf "tudo certo\nsegunda linha\n"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"verificador: ok (tudo certo)"* ]]
  [[ "$output" != *"segunda linha"* ]]
}

@test "--verificador que falha imprime AVISO com a saida identada e o resumo ainda sai com 0" {
  run sh "$SCRIPT" --raiz "$RAIZ" --verificador 'echo "drift em X"; echo "drift em Y" >&2; exit 1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"verificador: AVISO (exit 1)"* ]]
  [[ "$output" == *"  drift em X"* ]]
  [[ "$output" == *"  drift em Y"* ]]
}

@test "--verificador roda a partir da raiz" {
  run sh "$SCRIPT" --raiz "$RAIZ" --verificador 'pwd'
  [ "$status" -eq 0 ]
  [[ "$output" == *"verificador: ok ($(cd "$RAIZ" && pwd -P))"* ]]
}

# --- argumentos e raiz padrao ---------------------------------------------------------------------

@test "sem --raiz, a raiz e o repositorio que contem o script (uso pelo hook)" {
  repo_com_remoto
  run sh "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"remoto (origin): git@example.com:dono/repo.git"* ]]
}

@test "sem --raiz e fora de repositorio git, a raiz e o pai do diretorio do script" {
  entrada "$ENTRADAS" 2026-09-25-1400-branch-principal decisao ativa 'A branch principal declarada do projeto e `develop`'
  run sh "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch principal declarada: develop"* ]]
}

@test "argumento desconhecido sai com 2" {
  run sh "$SCRIPT" --x
  [ "$status" -eq 2 ]
  [[ "$output" == *"argumento desconhecido: --x"* ]]
}

@test "--raiz, --entradas e --verificador sem valor saem com 2 em vez de entrar em laco" {
  run timeout 5 sh "$SCRIPT" --raiz
  [ "$status" -eq 2 ]
  [[ "$output" == *"--raiz exige um valor"* ]]
  [[ "$output" != *"== resumo de estado"* ]]
  run timeout 5 sh "$SCRIPT" --entradas
  [ "$status" -eq 2 ]
  run timeout 5 sh "$SCRIPT" --verificador
  [ "$status" -eq 2 ]
}

@test "o resumo nao traz nada do projeto de origem (matriz de rotas, CLAUDE.md, nomes de clientes)" {
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" != *"superficie de rotas"* ]]
  [[ "$output" != *"CLAUDE.md"* ]]
  run ! grep -q -e 'matriz-de-autorizacao' -e 'verificar-claude-md' -e 'web-campo' -e 'web-comando' "$SCRIPT"
}
