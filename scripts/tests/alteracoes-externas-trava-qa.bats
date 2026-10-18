#!/usr/bin/env bats
# Suite independente do QA para a trava da linha de base do detector. Nao versionar antes do aceite (regra 12).

SCRIPT="$BATS_TEST_DIRNAME/../alteracoes-externas.sh"

setup() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=P GIT_AUTHOR_EMAIL=p@x GIT_COMMITTER_NAME=P GIT_COMMITTER_EMAIL=p@x
  git init --quiet --bare --initial-branch=main "$BATS_TEST_TMPDIR/remoto.git"
  git clone --quiet "$BATS_TEST_TMPDIR/remoto.git" "$BATS_TEST_TMPDIR/repo" 2>/dev/null
  cd "$BATS_TEST_TMPDIR/repo"; git checkout --quiet -b main
  printf 'a\n' > app.txt; git add app.txt; git commit --quiet -m "feat: base" -m "Prompt: x"; git push --quiet -u origin main
  sh "$SCRIPT" --inicial --principal main
  T=".git/agentes-linha-de-base.trava"
}

@test "QA-1: pid nao numerico na trava e tratado como desconhecido: espera e sai com 1 sem quebrar" {
  echo 'lixo; rm -rf /' > "$T"
  ALTERACOES_EXTERNAS_ESPERA=1 run sh "$SCRIPT" --registrar --principal main app.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"em uso"* ]]
  [[ "$output" != *"pid lixo"* ]]
  [ -e "$T" ]
}

@test "QA-2: espera zero: ocupado sai com 1 na primeira volta; livre segue" {
  echo $$ > "$T"
  ALTERACOES_EXTERNAS_ESPERA=0 run sh "$SCRIPT" --registrar --principal main app.txt
  [ "$status" -eq 1 ]
  rm -f "$T"
  ALTERACOES_EXTERNAS_ESPERA=0 run sh "$SCRIPT" --registrar --principal main app.txt
  [ "$status" -eq 0 ]
}

@test "QA-3: --detectar nao toma trava e le a linha de base enquanto ela esta ocupada" {
  echo $$ > "$T"
  run sh "$SCRIPT" --detectar --principal main
  [ "$status" -eq 0 ]
  rm -f "$T"
}

@test "QA-4: trava da linha de base e por worktree; a da marca compartilhada fica no git-dir comum" {
  git worktree add --quiet -b outra "$BATS_TEST_TMPDIR/wt" >/dev/null 2>&1
  (cd "$BATS_TEST_TMPDIR/wt" && sh "$SCRIPT" --inicial --principal main)
  echo $$ > "$T"
  printf 'b\n' > "$BATS_TEST_TMPDIR/wt/app.txt"
  ALTERACOES_EXTERNAS_ESPERA=1 run sh -c 'cd "$1" && sh "$2" --registrar --principal main app.txt' _ "$BATS_TEST_TMPDIR/wt" "$SCRIPT"
  [ "$status" -eq 0 ]
  rm -f "$T"
  echo $$ > .git/agentes-principal.trava
  git -C "$BATS_TEST_TMPDIR/wt" commit --quiet -am "x" -m "Prompt: y"
  ALTERACOES_EXTERNAS_ESPERA=1 run sh -c 'cd "$1" && sh "$2" --registrar --principal main' _ "$BATS_TEST_TMPDIR/wt" "$SCRIPT"
  [ "$status" -eq 1 ]
  rm -f .git/agentes-principal.trava
}

@test "QA-5: registrar interrompido por TERM enquanto espera nao deixa trava propria nem mexe na alheia" {
  echo $$ > "$T"
  sh "$SCRIPT" --registrar --principal main app.txt 2>/dev/null & p=$!
  sleep 0.5; kill -TERM "$p" 2>/dev/null; wait "$p" || true
  [ "$(cat "$T")" = "$$" ]
  rm -f "$T"
  run sh "$SCRIPT" --registrar --principal main app.txt
  [ "$status" -eq 0 ]
}

@test "QA-6: duas rodadas de registrar paralelos com commit no meio mantem HEAD e entradas coerentes" {
  for i in 1 2 3 4 5; do printf '%s\n' "$i" > "f$i.txt"; done
  for i in 1 2 3 4 5; do sh "$SCRIPT" --registrar --principal main "f$i.txt" & done; wait
  git add f1.txt f2.txt; git commit --quiet -m "parte" -m "Prompt: z"
  for i in 3 4 5; do printf 'x%s\n' "$i" > "f$i.txt"; sh "$SCRIPT" --registrar --principal main "f$i.txt" & done
  sh "$SCRIPT" --registrar --principal main & wait
  run sh "$SCRIPT" --detectar --principal main
  [ "$status" -eq 0 ]
  [ "$(grep -c '' .git/agentes-linha-de-base)" -eq 4 ]
  [ ! -e "$T" ]
}
