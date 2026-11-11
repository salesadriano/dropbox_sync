#!/usr/bin/env bats
# Regras 4 e 5 do guarda-de-comandos.sh: force em `git push` bloqueia (regra 47 do AGENTS.md; nao e autorizavel) e
# flag destrutiva em switch/worktree remove/branch pergunta (regra 48; o prompt e a autorizacao). Em qualquer posicao
# do segmento, que e o que o prefixo de permissions do cliente nao alcanca.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../guarda-de-comandos.sh"
  FORA="$BATS_TEST_TMPDIR/fora"; mkdir -p "$FORA"
}

json_do_hook() {  # $1 = comando
  python3 -I -c 'import json, sys; sys.stdout.write(json.dumps({"tool_input": {"command": sys.argv[1]}, "cwd": sys.argv[2]}))' "$1" "$FORA"
}

guarda() { json_do_hook "$1" | sh "$SCRIPT" 2>"$BATS_TEST_TMPDIR/err"; }

bloqueia() {  # $1 = comando
  run guarda "$1"
  [ "$status" -eq 2 ] || { echo "esperava bloqueio (2), veio $status: $1"; return 1; }
  grep -q 'regra 47' "$BATS_TEST_TMPDIR/err" || { echo "motivo sem regra 47"; cat "$BATS_TEST_TMPDIR/err"; return 1; }
}

pergunta() {  # $1 = comando
  run guarda "$1"
  [ "$status" -eq 0 ] || { echo "esperava exit 0, veio $status: $1"; return 1; }
  printf '%s' "$output" | python3 -I -c '
import json, sys
j = json.load(sys.stdin)["hookSpecificOutput"]
assert j["hookEventName"] == "PreToolUse" and j["permissionDecision"] == "ask" and "regra 48" in j["permissionDecisionReason"]' \
    || { echo "JSON de ask invalido para: $1 -> $output"; return 1; }
}

passa() {  # $1 = comando: sem bloqueio e sem decisao
  run guarda "$1"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "esperava passar em silencio: $1 -> $status $output"; return 1; }
}

# --- regra 4: force em push -------------------------------------------------------------------------

@test "force: --force em qualquer posicao do push bloqueia" {
  bloqueia 'git push --force origin x'
  bloqueia 'git push origin x --force'
  bloqueia 'git push origin --force x'
}

@test "force: -f em qualquer posicao bloqueia" {
  bloqueia 'git push -f origin x'
  bloqueia 'git push origin x -f'
}

@test "force: --force-with-lease (com e sem valor) e --force-if-includes bloqueiam" {
  bloqueia 'git push origin x --force-with-lease'
  bloqueia 'git push --force-with-lease=x:abc123 origin x'
  bloqueia 'git push origin x --force-if-includes'
}

@test "force: grupo de opcoes curtas com f bloqueia (-uf, -fu, -vfn)" {
  bloqueia 'git push -uf origin x'
  bloqueia 'git push origin x -fu'
  bloqueia 'git push -vfn origin x'
}

@test "force: refspec iniciado por + bloqueia, em qualquer posicao" {
  bloqueia 'git push origin +x'
  bloqueia 'git push origin +HEAD:feature/x'
  bloqueia 'git push +x origin'
}

@test "force: opcoes globais, sh -c, aspas, substituicao e encadeamento" {
  bloqueia 'git -C /tmp/r push origin x --force'
  bloqueia 'git -c core.x=1 push origin x -f'
  bloqueia "sh -c 'git push origin x --force'"
  bloqueia 'bash -c "git push origin x -f"'
  bloqueia 'echo $(git push origin +x)'
  bloqueia 'git fetch && git push origin x --force-with-lease'
  bloqueia 'git push origin x \
  --force'
}

@test "force: o + de refspec continua lendo a mira da integracao (regra 3 nao regride)" {
  run sh -c "printf '%s\n' 'git push origin +main' | awk -v sq=\"'\" -v integracao='main master' -f '$BATS_TEST_DIRNAME/../guarda-de-comandos.awk'"
  [ "$status" -eq 0 ]
  case "$output" in *push*mira*forca*|*push*forca*mira*) ;; *) echo "marcas: $output"; return 1 ;; esac
}

@test "force: push normal e comandos vizinhos nao sao bloqueados" {
  passa 'git push origin x'
  passa 'git push -u origin feature/force-f'
  passa 'git push --delete origin x'
  passa 'git push --follow-tags origin x'
  passa 'git push --dry-run origin x'
  passa 'git fetch --force'
  passa 'git fetch origin x -f'
  passa 'git commit -m "--force"'
  passa 'git log --oneline -f'
  passa 'git pull --force'
}

@test "force: so o segmento do push conta; -f em outro comando do mesmo comando nao" {
  passa 'git push origin x && rm -f arquivo'
  passa 'rm -f a; git push origin x'
}

# --- regra 5: reversao pergunta ---------------------------------------------------------------------

@test "reversao: switch com --discard-changes, -f, --force ou grupo com f pergunta" {
  pergunta 'git switch --discard-changes x'
  pergunta 'git switch x --discard-changes'
  pergunta 'git switch -f x'
  pergunta 'git switch x --force'
  pergunta 'git switch -fc novo'
}

@test "reversao: worktree remove com --force ou -f pergunta, em qualquer posicao" {
  pergunta 'git worktree remove --force ../w'
  pergunta 'git worktree remove ../w --force'
  pergunta 'git worktree remove -f ../w'
  pergunta 'git worktree remove -ff ../w'
}

@test "reversao: branch -D, ou -d/--delete junto de -f/--force, pergunta" {
  pergunta 'git branch -D x'
  pergunta 'git branch x -D'
  pergunta 'git branch -d x -f'
  pergunta 'git branch --delete --force x'
  pergunta 'git branch -fd x'
  pergunta 'git branch -df x'
}

@test "reversao: formas rotineiras nao perguntam" {
  passa 'git switch x'
  passa 'git switch -c novo'
  passa 'git worktree remove ../w'
  passa 'git worktree add -b x ../w'
  passa 'git worktree list'
  passa 'git branch -d x'
  passa 'git branch --delete x'
  passa 'git branch -a'
  passa 'git branch --list "*force*"'
}

@test "precedencia: force em push bloqueia mesmo com reversao no mesmo comando; padrao do arquivo bloqueia antes do ask" {
  bloqueia 'git branch -D x && git push origin x -f'
  printf 'rm -rf\tnao apague\n' > "$BATS_TEST_TMPDIR/p.txt"
  run sh -c "python3 -I -c 'import json,sys; print(json.dumps({\"tool_input\": {\"command\": \"git branch -D x; rm -rf y\"}, \"cwd\": sys.argv[1]}))' '$FORA' | sh '$SCRIPT' --padroes '$BATS_TEST_TMPDIR/p.txt'"
  [ "$status" -eq 2 ]
}

@test "reversao com isencao de conteiner e arquivo de padroes: o ask ainda sai" {
  printf 'rm -rf\tnao apague\n' > "$BATS_TEST_TMPDIR/p.txt"
  run sh -c "python3 -I -c 'import json,sys; print(json.dumps({\"tool_input\": {\"command\": \"git branch -D x\"}, \"cwd\": sys.argv[1]}))' '$FORA' | sh '$SCRIPT' --padroes '$BATS_TEST_TMPDIR/p.txt'"
  [ "$status" -eq 0 ]
  case "$output" in *'"permissionDecision":"ask"'*|*'"permissionDecision": "ask"'*) ;; *) echo "$output"; return 1 ;; esac
}

@test "despachante do plugin repassa o stdout do ask" {
  D="$BATS_TEST_DIRNAME/../../../../../claude-plugin/hooks/executar.sh"
  [ -f "$D" ] || skip "claude-plugin nao presente"
  CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/plugin" CLAUDE_PROJECT_DIR="$FORA"
  mkdir -p "$CLAUDE_PLUGIN_ROOT/skills/governanca-por-hooks/scripts"
  cp "$BATS_TEST_DIRNAME/../guarda-de-comandos.sh" "$BATS_TEST_DIRNAME/../guarda-de-comandos.awk" "$CLAUDE_PLUGIN_ROOT/skills/governanca-por-hooks/scripts/"
  export CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR
  run sh -c "python3 -I -c 'import json,sys; print(json.dumps({\"tool_input\": {\"command\": \"git switch -f x\"}, \"cwd\": sys.argv[1]}))' '$FORA' | sh '$D' guarda-de-comandos"
  [ "$status" -eq 0 ]
  case "$output" in *permissionDecision*ask*) ;; *) echo "$output"; return 1 ;; esac
}

# --- ciclo 3: abreviacao de opcao longa (o git aceita prefixo unico), --mirror e reposicionamento de branch -----------

@test "ciclo3 push: --mirror e abreviacoes bloqueiam" {
  bloqueia 'git push --mirror origin'
  bloqueia 'git push origin --mirror'
  bloqueia 'git push --mir origin'
  bloqueia 'git push --mi origin'
  bloqueia 'git push --m origin'
}

@test "ciclo3 push: prefixos de --force, --force-with-lease e --force-if-includes bloqueiam" {
  bloqueia 'git push --f origin x'
  bloqueia 'git push origin x --fo'
  bloqueia 'git push --for origin x'
  bloqueia 'git push --forc origin x'
  bloqueia 'git push --force-w origin x'
  bloqueia 'git push --force-with-lease=x origin x'
  bloqueia 'git push --force-if origin x'
}

@test "ciclo3 push: --follow-tags e opcao curta/longa sem force nao bloqueiam" {
  passa 'git push --follow-tags origin x'
  passa 'git push --fol origin x'
  passa 'git push --set-upstream origin x'
  passa 'git push --tags origin x'
  passa 'git push --atomic origin x'
}

@test "ciclo3 switch: abreviacoes de --discard-changes, --force e --force-create perguntam" {
  pergunta 'git switch --disc main'
  pergunta 'git switch --d main'
  pergunta 'git switch main --discard'
  pergunta 'git switch --f main'
  pergunta 'git switch --forc main'
  pergunta 'git switch --force-c nova'
  pergunta 'git switch --force-create nova'
  pergunta 'git switch --force-create=nova'
}

@test "ciclo3 switch: -C e grupo com C perguntam; -c e demais formas nao" {
  pergunta 'git switch -C main'
  pergunta 'git switch main -C x'
  pergunta 'git switch -tC x'
  passa 'git switch -c nova'
  passa 'git switch --create nova'
  passa 'git switch --detach HEAD~1'
  passa 'git switch -'
}

@test "ciclo3 worktree remove: abreviacoes de --force perguntam; remove sem force e outros subcomandos nao" {
  pergunta 'git worktree remove --f ../x'
  pergunta 'git worktree remove ../x --fo'
  pergunta 'git worktree remove --forc ../x'
  passa 'git worktree remove path'
  passa 'git worktree prune -f'
  passa 'git worktree prune --expire=now'
  passa 'git worktree add --force ../x'
}

@test "ciclo3 branch: -f/--force (com ou sem nome, sem -d) e abreviacoes perguntam" {
  pergunta 'git branch -f main HEAD~3'
  pergunta 'git branch --force main HEAD~3'
  pergunta 'git branch --f main HEAD~3'
  pergunta 'git branch main HEAD~3 -f'
  pergunta 'git branch -f'
  pergunta 'git branch -fu origin/x x'
  pergunta 'git branch -Df x'
  pergunta 'git branch -M velho novo'
  pergunta 'git branch -C velho novo'
}

@test "ciclo3 branch: criar, apagar sem force, copiar e listar nao perguntam" {
  passa 'git branch nova'
  passa 'git branch nova origin/main'
  passa 'git branch -d x'
  passa 'git branch --delete x'
  passa 'git branch -c velho novo'
  passa 'git branch -m velho novo'
  passa 'git branch --list "*f*"'
  passa 'git branch -vv'
}

@test "ciclo3: git fetch --force e abreviacao em outro subcomando nao perguntam" {
  passa 'git fetch --force'
  passa 'git fetch --f'
  passa 'git pull --f'
}

@test "ciclo3: abreviacao dentro de sh -c, opcao global e encadeamento" {
  pergunta "sh -c 'git worktree remove --f ../x'"
  pergunta 'git -C /tmp/r switch --disc main'
  pergunta 'git fetch && git branch -f main HEAD~3'
  bloqueia "sh -c 'git push --mirror origin'"
}

@test "conteiner: force em push dentro de docker run e docker exec bloqueia mesmo com arquivo de padroes (a regra 4 antecede a isencao); branch -D dentro de docker run segue perguntando" {
  printf 'rm -rf\tnao apague\n' > "$BATS_TEST_TMPDIR/p.txt"
  for c in 'docker run --rm img git push --force origin x' 'docker exec app git push -f origin x'; do
    run sh -c "python3 -I -c 'import json,sys; print(json.dumps({\"tool_input\": {\"command\": sys.argv[2]}, \"cwd\": sys.argv[1]}))' '$FORA' '$c' | sh '$SCRIPT' --padroes '$BATS_TEST_TMPDIR/p.txt' 2>&1"
    [ "$status" -eq 2 ] || { echo "nao bloqueou: $c ($status)"; false; }
    [[ "$output" == *"regra 47"* ]]
  done
  run sh -c "python3 -I -c 'import json,sys; print(json.dumps({\"tool_input\": {\"command\": \"docker run --rm img git branch -D x\"}, \"cwd\": sys.argv[1]}))' '$FORA' | sh '$SCRIPT' --padroes '$BATS_TEST_TMPDIR/p.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision"'*'"ask"'* ]]
}

@test "force: --force como valor de outra opcao do push (-o --force) bloqueia por desenho, porque o guarda nao distingue (lado seguro)" {
  bloqueia 'git push -o --force origin x'
  bloqueia 'git push origin x -o --force'
}
