#!/usr/bin/env bats
# QA independente: merge sem trilha na BRANCH (regra 48). Cenarios proprios de risco do QA.
# Rodar: npx --yes bats@1.13.0 --print-output-on-failure scripts/tests/qa-alteracoes-externas-merge-na-branch.bats

SCRIPT="$BATS_TEST_DIRNAME/../alteracoes-externas.sh"

setup() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=Pessoa GIT_AUTHOR_EMAIL=pessoa@example.invalid
  export GIT_COMMITTER_NAME=Pessoa GIT_COMMITTER_EMAIL=pessoa@example.invalid
  git init --quiet --bare --initial-branch=main "$BATS_TEST_TMPDIR/remoto.git"
  git clone --quiet "$BATS_TEST_TMPDIR/remoto.git" "$BATS_TEST_TMPDIR/repo" 2>/dev/null
  cd "$BATS_TEST_TMPDIR/repo"
  git checkout --quiet -b main
  printf 'a\n' > app.txt
  git add app.txt
  commit_agente "feat: base"
  git push --quiet -u origin main
  git checkout --quiet -b develop
}

detectar() { run sh "$SCRIPT" --detectar --principal main; }
commit_agente() { git commit --quiet -m "$1" -m "Prompt: docs/prompts/x.md"; }
ramo() {  # $1 nome, $2 arquivo, $3 conteudo: cria ramo a partir de develop com commit do agent
  git checkout --quiet -b "$1" develop
  printf '%s\n' "$3" > "$2"; git add "$2"; commit_agente "feat: $1"
  git checkout --quiet develop
}

@test "QA-M1: merge com conflito resolvido, sem trilha, na branch e acusado" {
  sh "$SCRIPT" --inicial --principal main
  git checkout --quiet -b b1; printf 'lado1\n' > app.txt; git add app.txt; commit_agente "feat: b1"
  git checkout --quiet develop; git checkout --quiet -b b2; printf 'lado2\n' > app.txt; git add app.txt; commit_agente "feat: b2"
  git checkout --quiet develop; git merge --quiet --no-ff -m "Merge b1" b1
  run git merge --no-ff -m "Merge b2 resolvido" b2
  printf 'resolucao humana\n' > app.txt; git add app.txt
  git commit --quiet -m "Merge b2 resolvido"
  detectar
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "COMMIT "*"Merge b2 resolvido (Pessoa)" ]]
}

@test "QA-M2: merge octopus limpo sem trilha na branch nao e acusado" {
  sh "$SCRIPT" --inicial --principal main
  ramo o1 o1.txt 1; ramo o2 o2.txt 2; ramo o3 o3.txt 3
  printf 'd\n' > d.txt; git add d.txt; commit_agente "feat: develop avanca"
  git merge --quiet --no-ff -m "Merge octopus" o1 o2 o3
  [ "$(git rev-list --parents -n 1 HEAD | wc -w)" -eq 5 ]
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "QA-M3: merge octopus com alteracao propria sem trilha na branch e acusado" {
  sh "$SCRIPT" --inicial --principal main
  ramo o1 o1.txt 1; ramo o2 o2.txt 2; ramo o3 o3.txt 3
  printf 'd\n' > d.txt; git add d.txt; commit_agente "feat: develop avanca"
  git merge --quiet --no-ff --no-commit o1 o2 o3
  [ "$(git rev-parse -q --verify MERGE_HEAD | wc -l)" -eq 1 ]
  printf 'maligno\n' > extra.txt; git add extra.txt
  git commit --quiet -m "Merge octopus maligno"
  detectar
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "COMMIT "*"Merge octopus maligno (Pessoa)" ]]
}

@test "QA-M4: merge limpo traz commit humano sem trilha: acusa o commit, nao o merge" {
  sh "$SCRIPT" --inicial --principal main
  git checkout --quiet -b h1; printf 'h\n' > h.txt; git add h.txt; git commit --quiet -m "ajuste humano"
  git checkout --quiet develop
  git merge --quiet --no-ff -m "Merge pull request #9 from x/h1" h1
  detectar
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "COMMIT "*"ajuste humano (Pessoa)" ]]
  [[ "$output" != *"Merge pull request"* ]]
}

@test "QA-M6: linha de base anterior ao merge: o merge limpo posterior nao e acusado, o com alteracao propria e" {
  sh "$SCRIPT" --inicial --principal main
  ramo c1 c1.txt 1
  git merge --quiet --no-ff -m "Merge pull request #1 from x/c1" c1
  ramo c2 c2.txt 2
  git merge --quiet --no-ff --no-commit c2
  printf 'maligno\n' >> app.txt; git add app.txt
  git commit --quiet -m "Merge c2 alterado"
  detectar
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "COMMIT "*"Merge c2 alterado (Pessoa)" ]]
}

@test "QA-M7: merge limpo com mesmo arquivo mudado pelos dois lados em hunks distintos nao e acusado" {
  printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n' > longo.txt; git add longo.txt; commit_agente "feat: longo"
  sh "$SCRIPT" --inicial --principal main
  git checkout --quiet -b l1; sed -i '1s/.*/um/' longo.txt; git add longo.txt; commit_agente "feat: l1"
  git checkout --quiet develop; git checkout --quiet -b l2; sed -i '9s/.*/nove/' longo.txt; git add longo.txt; commit_agente "feat: l2"
  git checkout --quiet develop
  git merge --quiet --no-ff -m "Merge l1" l1
  git merge --quiet --no-ff -m "Merge l2" l2
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "QA-M8: merge com Prompt no corpo e alteracao propria nao e acusado (trilha presente)" {
  sh "$SCRIPT" --inicial --principal main
  ramo p1 p1.txt 1
  git merge --quiet --no-ff --no-commit p1
  printf 'x\n' >> app.txt; git add app.txt
  git commit --quiet -m "Merge p1" -m "Prompt: docs/prompts/x.md"
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "QA-M9: git sem --remerge-diff (falha) em merge sem trilha: acusa por seguranca" {
  sh "$SCRIPT" --inicial --principal main
  ramo r1 r1.txt 1
  git merge --quiet --no-ff -m "Merge r1" r1
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  real=$(command -v git)
  cat > "$BATS_TEST_TMPDIR/fakebin/git" <<FAKE
#!/bin/sh
for a in "\$@"; do [ "\$a" = "--remerge-diff" ] && exit 129; done
exec "$real" "\$@"
FAKE
  chmod +x "$BATS_TEST_TMPDIR/fakebin/git"
  PATH="$BATS_TEST_TMPDIR/fakebin:$PATH" run sh "$SCRIPT" --detectar --principal main
  [ "$status" -eq 3 ]
  [[ "$output" == "COMMIT "*"Merge r1 (Pessoa)" ]]
}
