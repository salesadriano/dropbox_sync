#!/usr/bin/env bats
# Autorizacao de sessao do git flow: guarda-de-comandos.sh (PreToolUse) pergunta uma vez e grava o pendente;
# autorizacao-de-sessao.sh (PostToolUse/PostToolUseFailure) promove o pendente a marcador de sessao quando o
# comando executou; com o marcador, o guarda devolve `allow` para o git flow elegivel. Force, `gh pr merge` e a
# regra 48 (alteracao humana acusada pelo detector) nunca sao afrouxados. Repositorio temporario por teste.

setup() {
  GUARDA="$BATS_TEST_DIRNAME/../guarda-de-comandos.sh"
  AUTORIZA="$BATS_TEST_DIRNAME/../autorizacao-de-sessao.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts"
  git -C "$REPO" init -q
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m inicio
  # detector falso: o exit sai do arquivo scripts/.detector (0 limpo, 3 alteracao humana)
  printf '%s\n' 'exit "$(cat "$(dirname "$0")/.detector")"' > "$REPO/scripts/alteracoes-externas.sh"
  echo 0 > "$REPO/scripts/.detector"
  DIR="$REPO/.git/agentes-autorizacao-sessao"
}

json() {  # $1 = comando ou vazio; $2 = sid; $3 = tid; $4 = permission_mode (opcional); cwd = $CWD ou $REPO
  python3 -I -c '
import json, sys
c, s, t, m, cwd = sys.argv[1:6]
d = {"cwd": cwd}
if c: d["tool_input"] = {"command": c}
if s: d["session_id"] = s
if t: d["tool_use_id"] = t
if m: d["permission_mode"] = m
sys.stdout.write(json.dumps(d))' "$1" "${2-}" "${3-}" "${4-}" "${CWD:-$REPO}"
}

pre() { json "$1" "${2-}" "${3-}" "${4-}" | sh "$GUARDA" 2>"$BATS_TEST_TMPDIR/err"; }
post() { json "" "${1-}" "${2-}" | sh "$AUTORIZA" 2>"$BATS_TEST_TMPDIR/err"; }

decisao() {  # imprime a decisao do hook (ask/allow) ou nada
  printf '%s' "$1" | python3 -I -c '
import json, sys
s = sys.stdin.read()
if s.strip(): sys.stdout.write(json.loads(s)["hookSpecificOutput"]["permissionDecision"])'
}

pergunta() {  # pre <cmd> <sid> <tid> [modo]: ask
  run pre "$@"; [ "$status" -eq 0 ] && [ "$(decisao "$output")" = ask ] || { echo "esperava ask: $1 -> $status $output"; return 1; }
}
libera() {
  run pre "$@"; [ "$status" -eq 0 ] && [ "$(decisao "$output")" = allow ] || { echo "esperava allow: $1 -> $status $output"; return 1; }
}
sem_opiniao() {
  run pre "$@"; [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "esperava silencio: $1 -> $status $output"; return 1; }
}
nao_libera() {  # nunca allow (ask ou silencio)
  run pre "$@"; [ "$status" -eq 0 ] && [ "$(decisao "$output")" != allow ] || { echo "nao devia liberar: $1 -> $status $output"; return 1; }
}
autoriza() {  # primeira autorizacao da sessao S1: pergunta com pendente e o comando executa
  pergunta 'git tag v0' S1 T0 && post S1 T0
}
sem_pendente() { [ -z "$(ls "$DIR" 2>/dev/null | grep '^pendente-')" ]; }

# --- primeira autorizacao -----------------------------------------------------------------------------

@test "rotina sem gatilho e sem marcador: sem opiniao e sem pendente" {
  sem_opiniao 'git status' S1 T1
  sem_opiniao 'git fetch origin' S1 T2
  sem_opiniao 'git commit -m "msg"' S1 T3
  sem_pendente
}

@test "gatilho sem marcador: ask e grava o pendente da sessao e da chamada" {
  pergunta 'git tag v1' S1 T1
  [ -f "$DIR/pendente-S1.T1" ]
}

@test "gatilho: tag, cherry-pick, revert, -C e gh novos perguntam com pendente" {
  for c in 'git tag v1' 'git cherry-pick abc' 'git revert abc' 'git -C . status' 'gh pr checks 1' 'gh pr comment 1 -b x' \
           'gh run list' 'gh run view 1' 'gh run watch 1' 'gh issue view 1' 'gh issue list' 'gh issue comment 1 -b x'; do
    rm -rf "$DIR"
    pergunta "$c" S1 T1
    [ -f "$DIR/pendente-S1.T1" ] || { echo "sem pendente: $c"; return 1; }
  done
}

@test "git remote sem subcomando, -v, show e get-url sao gatilho; add e inelegivel e nunca ganha pendente" {
  for c in 'git remote' 'git remote -v' 'git remote show origin' 'git remote get-url origin'; do
    rm -rf "$DIR"
    pergunta "$c" S1 T1
    [ -f "$DIR/pendente-S1.T1" ] || { echo "sem pendente: $c"; return 1; }
  done
  rm -rf "$DIR"
  sem_opiniao 'git remote add o u' S1 T5
  [ ! -e "$DIR/pendente-S1.T5" ]
}

@test "modos auto, bypassPermissions e dontAsk: ask sem pendente (nao houve autorizacao humana)" {
  for m in auto bypassPermissions dontAsk; do
    pergunta 'git tag v1' S1 T1 "$m"
    sem_pendente
  done
  pergunta 'git tag v1' S1 T1 default
  [ -f "$DIR/pendente-S1.T1" ]
}

@test "Post com o pendente: grava o marcador de sessao e apaga o pendente" {
  pergunta 'git tag v1' S1 T1
  run post S1 T1
  [ "$status" -eq 0 ]
  [ -f "$DIR/sessao-S1" ]
  [ ! -e "$DIR/pendente-S1.T1" ]
}

@test "PostToolUseFailure usa o mesmo caminho: comando executou apos o ask" {
  pergunta 'git tag v1' S1 T1
  run sh -c "python3 -I -c 'import json,sys; print(json.dumps({\"hook_event_name\":\"PostToolUseFailure\",\"session_id\":\"S1\",\"tool_use_id\":\"T1\",\"cwd\":sys.argv[1],\"error\":\"x\"}))' '$REPO' | sh '$AUTORIZA'"
  [ "$status" -eq 0 ]
  [ -f "$DIR/sessao-S1" ]
}

@test "Post sem pendente daquele par (ou de outra chamada) nao grava marcador" {
  run post S1 T9; [ "$status" -eq 0 ]
  [ ! -e "$DIR/sessao-S1" ]
  pergunta 'git tag v1' S1 T1
  run post S1 T2; [ "$status" -eq 0 ]
  [ ! -e "$DIR/sessao-S1" ]
}

@test "recusa nao gera Post: o pendente fica inerte e a proxima chamada pergunta de novo" {
  pergunta 'git tag v1' S1 T1
  pergunta 'git tag v2' S1 T2
  pergunta 'git revert abc' S1 T3
  [ ! -e "$DIR/sessao-S1" ]
}

# --- depois da autorizacao ----------------------------------------------------------------------------

@test "com marcador: rotina, gatilhos e gh novos viram allow" {
  autoriza
  for c in 'git status' 'git tag v2' 'git cherry-pick abc' 'git revert abc' 'git -C . log' 'git commit -m "msg simples"' \
           'git remote -v' 'git push origin feature/x' 'gh pr create --title t' 'gh pr view 1' 'gh pr checks 1' 'gh run list' \
           'gh issue comment 1 -b x' 'git add . && git commit -m x' "cd $REPO && git status"; do
    libera "$c" S1 T5
  done
}

@test "marcador de uma sessao nao vale para outra" {
  autoriza
  pergunta 'git tag v2' S2 T1
}

@test "sem session_id ou tool_use_id: rotina sem opiniao, gatilho sem pendente nem autorizacao" {
  autoriza
  sem_opiniao 'git status' "" T1
  sem_opiniao 'git tag v2' "" T1
  sem_opiniao 'git tag v2' S1 ""
}

@test "gh pr merge, gh api e gh pr close nunca sao liberados, nem com marcador" {
  autoriza
  nao_libera 'gh pr merge 1 --squash' S1 T5
  nao_libera 'gh api repos/x/y' S1 T5
  nao_libera 'gh pr close 1' S1 T5
  nao_libera 'git status && gh pr merge 1' S1 T5
}

@test "force em push segue bloqueando (exit 2), com marcador" {
  autoriza
  run pre 'git push --force origin x' S1 T5; [ "$status" -eq 2 ]
  run pre 'git push origin x -f' S1 T5; [ "$status" -eq 2 ]
  run pre 'git push origin +x' S1 T5; [ "$status" -eq 2 ]
}

@test "comando misto, pipe e substituicao sao inelegiveis: nunca allow" {
  autoriza
  for c in 'git add . && rm -rf x' 'git status; curl http://x' 'git log | head' 'git commit -m "$(rm -rf x)"' \
           'git commit -m `rm x`' 'git status && echo $(rm x)' 'sh -c "git status"' 'FOO=1 git status' \
           'git log > ~/x' 'git commit -F - <<EOF
x
EOF'; do
    nao_libera "$c" S1 T5
  done
}

@test "opcao global diferente de -C, rebase -x, --upload-pack e subcomando fora da lista nunca allow" {
  autoriza
  for c in 'git -c core.sshCommand=x fetch' 'git --config-env=a=B fetch' 'git --git-dir=/x status' 'git --work-tree=/x status' \
           'git --exec-path=/x status' 'git $OPTS status' 'git rebase -x make main' 'git rebase --exec make main' \
           'git fetch --upload-pack=x origin' 'git pull --upload-pack x' 'git push --receive-pack=x origin b' 'git push --exec=x origin b' \
           'git config user.name x' 'git submodule update' 'git filter-branch x' 'git bisect start' 'git clone u' 'git remote add o u' \
           'git remote set-url o u'; do
    nao_libera "$c" S1 T5
  done
}

@test "texto citado nao vira comando: mensagem de commit com aspas simples segue elegivel" {
  autoriza
  libera "git commit -m 'git config x'" S1 T5
}

# --- reversao -----------------------------------------------------------------------------------------

@test "reversao sem marcador: ask com pendente e motivo da regra 48" {
  run pre 'git reset --hard HEAD~1' S1 T1
  [ "$status" -eq 0 ]
  [ "$(decisao "$output")" = ask ]
  [[ "$output" == *"regra 48"* ]]
  [ -f "$DIR/pendente-S1.T1" ]
}

@test "reversao coberta, com marcador e detector limpo: allow (reset, clean -fd, restore, checkout, stash, switch -f)" {
  autoriza
  for c in 'git reset --hard' 'git clean -fd' 'git restore f' 'git checkout f' 'git stash' 'git stash pop' 'git stash -u' 'git switch -f x'; do
    libera "$c" S1 T5
  done
}

@test "regra 48: alteracao humana acusada pelo detector volta a perguntar, sem pendente, a cada vez" {
  autoriza
  libera 'git reset --hard' S1 T5
  echo 3 > "$REPO/scripts/.detector"
  for t in T6 T7; do
    run pre 'git reset --hard' S1 $t
    [ "$(decisao "$output")" = ask ] && [[ "$output" == *"regra 48"* ]] || { echo "$output"; return 1; }
  done
  sem_pendente
  echo 0 > "$REPO/scripts/.detector"
  libera 'git reset --hard' S1 T8
}

@test "detector ausente: reversao pergunta sem pendente, mesmo com marcador" {
  autoriza
  rm "$REPO/scripts/alteracoes-externas.sh"
  pergunta 'git restore f' S1 T5
  sem_pendente
}

@test "reversao que o detector nao enxerga pergunta sempre, sem pendente: -C, cd, clean -x/-X, stash -a, branch -D/-M/-C/-f, worktree remove --force" {
  autoriza
  for c in 'git -C . reset --hard' "cd $REPO && git reset --hard" 'git clean -fdx' 'git stash -a' 'git stash --all' 'git stash --al' 'git stash -ua' \
           'git branch -D x' 'git branch -M x' 'git branch -C x' 'git branch -f x' 'git branch --force x' 'git branch -fd x' 'git clean -fdX' 'git clean -xfd' \
           'git worktree remove --force ../w' 'git worktree remove -f ../w'; do
    run pre "$c" S1 T5
    [ "$(decisao "$output")" = ask ] || { echo "esperava ask: $c -> $output"; return 1; }
  done
  sem_pendente
}

@test "F1: -C ou cd com escrita e inelegivel: sem allow e sem pendente, com ou sem marcador" {
  for c in 'git -C /outro commit -am x' 'git -C ../principal rebase main' 'git -C ../principal merge feature' 'git -C /outro add -A' \
           'git -C /outro pull' 'git -C /outro branch x' 'git -C /outro tag v1' 'git -C /outro revert HEAD' 'git -C /outro cherry-pick abc' \
           'git -C /outro switch x' 'git -C /outro push origin feature/x' "cd /outro && git commit -am x" "cd /outro && git add . && git commit -m x" \
           "cd /outro && git merge x" "cd /outro && git push origin feature/x"; do
    sem_opiniao "$c" S1 T1
  done
  sem_pendente
  autoriza
  for c in 'git -C /outro commit -am x' 'git -C /outro merge feature' 'git -C /outro rebase main' 'git -C /outro pull' 'git -C /outro add -A' \
           'git -C /outro tag v1' "cd /outro && git commit -am x" "cd /outro && git merge x" 'git -C /outro revert HEAD'; do
    nao_libera "$c" S1 T5
  done
}

@test "F1: -C e cd com leitura, fetch ou worktree sem remove continuam elegiveis" {
  autoriza
  for c in 'git -C /outro log' 'git -C /outro status' 'git -C /outro diff' 'git -C /outro show HEAD' 'git -C /outro rev-parse HEAD' 'git -C /outro merge-base a b' \
           'git -C /outro fetch origin' 'git -C /outro worktree add ../w' 'git -C /outro ls-files' "cd /outro && git status" "cd /outro && git fetch" \
           "cd /outro && git log" "cd /outro && git worktree list"; do
    libera "$c" S1 T5
  done
}

@test "F1: -C com leitura sem marcador segue a regra de antes (gatilho do -C pergunta com pendente; cd e rotina sem opiniao)" {
  pergunta 'git -C /outro fetch origin' S1 T1
  sem_opiniao 'cd /outro && git log' S1 T2
}

@test "F7: cd com gh de escrita (comment, edit, rerun, criacao de PR) e inelegivel; cd com gh de leitura segue elegivel" {
  autoriza
  for c in 'cd /outro && gh pr comment 1 -b x' 'cd /outro && gh pr edit 1 --title t' 'cd /outro && gh issue comment 1 -b x' \
           'cd /outro && gh run rerun 5' 'cd /outro && gh pr create --title t --body b' 'cd /outro && gh pr ready 1'; do
    nao_libera "$c" S1 T5
  done
  libera 'gh pr comment 1 -b x' S1 T6
  for c in 'cd /outro && gh pr view 1' 'cd /outro && gh pr list' 'cd /outro && gh pr diff 1' 'cd /outro && gh pr checks 1' \
           'cd /outro && gh run list' 'cd /outro && gh run view 5' 'cd /outro && gh run watch 5' 'cd /outro && gh issue view 1' 'cd /outro && gh issue list'; do
    libera "$c" S1 T7
  done
}

@test "F2: gh com -F, --body-file, -R, --repo (colados, separados, abreviados) e inelegivel; sem eles segue elegivel" {
  autoriza
  for c in 'gh pr comment 1 -F /etc/passwd' 'gh pr comment 1 -F/etc/passwd' 'gh pr comment 1 --body-file f' 'gh pr comment 1 --body-file=f' \
           'gh pr comment 1 --body-fi f' 'gh pr comment 1 --bod f' 'gh issue comment 1 -R evil/x -b x' 'gh issue comment 1 -Revil/x -b x' \
           'gh issue comment 1 --repo evil/x -b x' 'gh issue comment 1 --repo=evil/x -b x' 'gh pr view 1 --rep evil/x' 'gh pr edit 1 -R evil/x'; do
    nao_libera "$c" S1 T5
  done
  libera 'gh pr comment 1 -b x' S1 T6
  libera 'gh pr comment 1 --body texto' S1 T7
  libera 'gh pr view 1' S1 T8
}

@test "F3: git stash com -a, --all, abreviacao ou grupo com a pergunta sempre; stash comum e -u seguem cobertos" {
  autoriza
  for c in 'git stash -a' 'git stash --all' 'git stash --al' 'git stash push -a' 'git stash -ua' 'git stash push -m x --all'; do
    pergunta "$c" S1 T5
  done
  libera 'git stash' S1 T6
  libera 'git stash push -m msg' S1 T7
  libera 'git stash -u' S1 T8
}

@test "F4: dolar em qualquer posicao da palavra, chaves de expansao e --output tornam inelegivel; aspas simples e texto comum nao" {
  autoriza
  for c in 'git log --pretty=$FOO' 'git log --pretty=a$FOO' 'git log "--pretty=$FOO"' 'git log --pretty=${FOO}' 'git log --output=/etc/x' 'git log --out /etc/x' \
           'git diff --output=/etc/x' 'git show -o x' 'git log --{a,b}' 'git log --{pretty=oneline,stat}' 'gh pr comment 1 -b "x$FOO"'; do
    nao_libera "$c" S1 T5
  done
  libera 'git commit -m "texto sem cifrao"' S1 T6
  libera "git commit -m 'custa \$5 e {a}'" S1 T7
  libera 'git log --oneline --pretty=oneline' S1 T8
  libera 'git commit -m "chaves {a}"' S1 T9
}

@test "reversao em modo auto ou sem session_id/tool_use_id: ask sem pendente" {
  pergunta 'git reset --hard' S1 T1 auto
  pergunta 'git reset --hard' "" T1
  pergunta 'git reset --hard' S1 ""
  sem_pendente
}

@test "reversao em comando misto pergunta sem pendente (inelegivel)" {
  autoriza
  pergunta 'git reset --hard && rm -rf x' S1 T5
  sem_pendente
}

@test "reversao ja detectada sem autorizacao previa segue perguntando (switch -f, branch -D, worktree remove --force)" {
  for c in 'git switch -f x' 'git branch -D x' 'git worktree remove --force ../w'; do pergunta "$c" S1 T1; done
}

# --- sanitizacao e limpeza ----------------------------------------------------------------------------

@test "session_id e tool_use_id fora de [A-Za-z0-9_-] nao escrevem nada" {
  run pre 'git tag v1' '../x' T1; [ "$status" -eq 0 ]
  run pre 'git tag v1' S1 '../../y'; [ "$status" -eq 0 ]
  run post '../x' T1; [ "$status" -eq 0 ]
  run post S1 'a/b'; [ "$status" -eq 0 ]
  [ -z "$(ls "$DIR" 2>/dev/null)" ]
  [ ! -e "$REPO/.git/x" ] && [ ! -e "$REPO/x" ] && [ ! -e "$BATS_TEST_TMPDIR/x" ] && [ ! -e "$REPO/.git/y" ]
  pergunta 'git reset --hard' '../x' T1
}

@test "pendente forjado com id invalido nao promove: Post com ../x nao cria marcador fora do diretorio" {
  mkdir -p "$DIR"; : > "$DIR/pendente-..x.T1"
  run post '../x' T1; [ "$status" -eq 0 ]
  [ ! -e "$REPO/.git/sessao-..-x" ] && [ ! -e "$DIR/sessao-../x" ]
}

@test "Post limpa marcadores e pendentes com mais de 7 dias e mantem os recentes" {
  mkdir -p "$DIR"
  : > "$DIR/sessao-VELHA"; : > "$DIR/pendente-VELHA.T1"; : > "$DIR/sessao-NOVA"
  touch -d '10 days ago' "$DIR/sessao-VELHA" "$DIR/pendente-VELHA.T1"
  run post S9 T9; [ "$status" -eq 0 ]
  [ ! -e "$DIR/sessao-VELHA" ] && [ ! -e "$DIR/pendente-VELHA.T1" ] && [ -e "$DIR/sessao-NOVA" ]
}

@test "Post nunca bloqueia: sem repositorio, sem JSON valido, sem entrada" {
  FORA="$BATS_TEST_TMPDIR/fora"; mkdir -p "$FORA"
  run sh -c "printf '%s' '{\"session_id\":\"S1\",\"tool_use_id\":\"T1\",\"cwd\":\"$FORA\"}' | sh '$AUTORIZA'"
  [ "$status" -eq 0 ]
  run sh -c "printf 'nao e json' | sh '$AUTORIZA'"; [ "$status" -eq 0 ]
  run sh -c "printf '' | sh '$AUTORIZA'"; [ "$status" -eq 0 ]
}

@test "worktree compartilha o marcador pelo git-common-dir" {
  git -C "$REPO" worktree add -q "$BATS_TEST_TMPDIR/wt" -b outra
  CWD="$BATS_TEST_TMPDIR/wt" pergunta 'git tag v1' S1 T1
  CWD="$BATS_TEST_TMPDIR/wt" post S1 T1
  [ -f "$DIR/sessao-S1" ]
  libera 'git tag v2' S1 T2
}

# --- configuracao: os dois casos do modelo (exemplo de settings da skill e hooks.json do plugin) leem arquivos que
# so existem no repositorio do pacote ai_team e nao foram trazidos para o projeto; la continuam cobertos.
