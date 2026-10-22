#!/usr/bin/env bats
# Suite independente do QA para scripts/alteracoes-externas.sh: merge sem trilha na branch principal
# (criterio --remerge-diff / --cc) e recusa de diretorio no --registrar (demanda
# detector-merge-limpo-diretorio, 2026-10-08-1159). Complementa alteracoes-externas.bats sem reusar
# os cenarios do Senior Developer: cada teste monta repositorio descartavel com remoto proprio.
# Rodar: npx --yes bats@1.13.0 --abort scripts/tests/alteracoes-externas-merge-qa.bats
# (--abort para no primeiro teste falho, Regra 9 de protocolo-tdd).

SCRIPT="$BATS_TEST_DIRNAME/../alteracoes-externas.sh"

setup() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=Humano GIT_AUTHOR_EMAIL=humano@example.invalid
  export GIT_COMMITTER_NAME=Humano GIT_COMMITTER_EMAIL=humano@example.invalid
  git init --quiet --bare --initial-branch=main "$BATS_TEST_TMPDIR/remoto.git"
  git clone --quiet "$BATS_TEST_TMPDIR/remoto.git" "$BATS_TEST_TMPDIR/repo" 2>/dev/null
  cd "$BATS_TEST_TMPDIR/repo"
  git checkout --quiet -b main
  printf 'linha-%s\n' 1 2 3 4 5 6 7 8 > dados.txt
  git add dados.txt
  com_trilha "feat: base qa"
  git push --quiet -u origin main
  sh "$SCRIPT" --inicial --principal main
  git clone --quiet "$BATS_TEST_TMPDIR/remoto.git" "$BATS_TEST_TMPDIR/pessoa" 2>/dev/null
}

detectar() { run sh "$SCRIPT" --detectar --principal main; }

com_trilha() {
  git commit --quiet -m "$1" -m "Prompt: docs/prompts/qa.md
Registro: docs/reviews/qa.md"
}

# Executa $1 no clone da pessoa (comandos de shell), publica main e atualiza o worktree do agent.
na_principal() {
  # Sem || nem &&: o set -e do bats vale dentro do subshell e qualquer passo falho reprova o teste.
  ( cd "$BATS_TEST_TMPDIR/pessoa"; eval "$1"; git push --quiet origin main )
  git fetch --quiet origin
}

troca() { sed "s/^$1\$/$2/" "$3" > "$3.tmp" && mv "$3.tmp" "$3"; }

base_atual() { cat "$(git rev-parse --absolute-git-dir)/agentes-linha-de-base"; }
marca_atual() { cat "$(git rev-parse --git-common-dir)/agentes-principal" 2>/dev/null || true; }

# --- merge na principal sem trilha: limpo nao conta ---------------------------

@test "QA-D1: merge limpo com rename de um lado e edicao do outro nao e acusado" {
  na_principal '
    git checkout --quiet -b ramo
    git mv dados.txt movido.txt; com_trilha "refactor: renomeia"
    git checkout --quiet main
    troca linha-2 editada dados.txt; git add dados.txt; com_trilha "feat: edita"
    git merge --quiet --no-ff -m "Merge rename" ramo
    test "$(cat movido.txt | sed -n 2p)" = editada'
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "QA-D2: merge limpo com troca de modo de um lado e edicao do outro nao e acusado" {
  na_principal '
    git checkout --quiet -b ramo
    chmod +x dados.txt; git add dados.txt; com_trilha "chore: executavel"
    git checkout --quiet main
    troca linha-7 editada dados.txt; git add dados.txt; com_trilha "feat: edita"
    git merge --quiet --no-ff -m "Merge modo" ramo
    test "$(git ls-tree HEAD dados.txt | cut -c1-6)" = 100755'
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "QA-D3: merge que troca so o modo de arquivo, sem trilha, e acusado" {
  na_principal '
    git checkout --quiet -b ramo
    printf "x\n" > outro.txt; git add outro.txt; com_trilha "feat: outro"
    git checkout --quiet main
    git merge --quiet --no-ff --no-commit ramo
    chmod +x dados.txt; git add dados.txt; git commit --quiet -m "Merge com chmod"'
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == "PRINCIPAL "*"Merge com chmod (Humano)" ]]
}

@test "QA-D4: merge maligno que so acrescenta arquivo novo e acusado" {
  na_principal '
    git checkout --quiet -b ramo
    troca linha-1 ramo dados.txt; git add dados.txt; com_trilha "feat: ramo"
    git checkout --quiet main
    git merge --quiet --no-ff --no-commit ramo
    printf "segredo\n" > "novo arquivo.txt"; git add "novo arquivo.txt"
    git commit --quiet -m "Merge com arquivo novo"'
  detectar
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "PRINCIPAL "*"Merge com arquivo novo (Humano)" ]]
}

@test "QA-D5: merge maligno que apaga arquivo e acusado" {
  na_principal '
    printf "y\n" > apagar.txt; git add apagar.txt; com_trilha "feat: apagar"
    git checkout --quiet -b ramo
    troca linha-1 ramo dados.txt; git add dados.txt; com_trilha "feat: ramo"
    git checkout --quiet main
    git merge --quiet --no-ff --no-commit ramo
    git rm --quiet apagar.txt; git commit --quiet -m "Merge que apaga"'
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == "PRINCIPAL "*"Merge que apaga (Humano)" ]]
}

@test "QA-D6: merge com pai orfao (raiz propria), limpo, nao e acusado; maligno e" {
  na_principal '
    git checkout --quiet --orphan orfao
    git rm --quiet -rf .
    printf "o\n" > orfao.txt; git add orfao.txt; com_trilha "feat: raiz orfa"
    git checkout --quiet main
    git merge --quiet --no-ff --allow-unrelated-histories -m "Merge orfao limpo" orfao'
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  na_principal '
    git checkout --quiet --orphan orfao2
    git rm --quiet -rf .
    printf "p\n" > orfao2.txt; git add orfao2.txt; com_trilha "feat: raiz orfa 2"
    git checkout --quiet main
    git merge --quiet --no-ff --no-commit --allow-unrelated-histories orfao2
    printf "extra\n" >> orfao2.txt; git add orfao2.txt; git commit --quiet -m "Merge orfao maligno"'
  detectar
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "PRINCIPAL "*"Merge orfao maligno (Humano)" ]]
}

@test "QA-D7: mesma alteracao identica nos dois lados mesclada sem conflito nao e acusada" {
  na_principal '
    git checkout --quiet -b ramo
    troca linha-4 igual dados.txt; git add dados.txt; com_trilha "feat: ramo"
    git checkout --quiet main
    troca linha-4 igual dados.txt; git add dados.txt; com_trilha "feat: principal"
    git merge --quiet --no-ff -m "Merge identico" ramo'
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "QA-D8: conflito resolvido com a versao do ramo (theirs) e acusado" {
  na_principal '
    git checkout --quiet -b ramo
    troca linha-3 ramo dados.txt; git add dados.txt; com_trilha "feat: ramo"
    git checkout --quiet main
    troca linha-3 principal dados.txt; git add dados.txt; com_trilha "feat: principal"
    ! git merge --quiet ramo >/dev/null 2>&1
    git checkout --quiet --theirs dados.txt; git add dados.txt; git commit --quiet -m "Merge theirs"'
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == "PRINCIPAL "*"Merge theirs (Humano)" ]]
}

@test "QA-D9: conflito modificar/apagar resolvido apagando e acusado" {
  na_principal '
    git checkout --quiet -b ramo
    git rm --quiet dados.txt; com_trilha "feat: apaga"
    git checkout --quiet main
    troca linha-3 principal dados.txt; git add dados.txt; com_trilha "feat: principal"
    ! git merge --quiet ramo >/dev/null 2>&1
    git rm --quiet dados.txt; git commit --quiet -m "Merge apaga"'
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == "PRINCIPAL "*"Merge apaga (Humano)" ]]
}

@test "QA-D10: sequencia de merges acusa so o maligno, com uma linha" {
  na_principal '
    for r in a b; do
      git checkout --quiet -b "r$r" main; printf "%s\n" "$r" > "$r.txt"; git add "$r.txt"; com_trilha "feat: $r"
    done
    git checkout --quiet main
    git merge --quiet --no-ff -m "Merge limpo a" ra
    git merge --quiet --no-ff --no-commit rb
    printf "z\n" >> a.txt; git add a.txt; git commit --quiet -m "Merge maligno b"'
  detectar
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "PRINCIPAL "*"Merge maligno b (Humano)" ]]
}

@test "QA-D11: merge maligno em arquivo com espaco no nome e acusado" {
  na_principal '
    printf "1\n2\n3\n" > "com espaco.txt"; git add "com espaco.txt"; com_trilha "feat: espaco"
    git checkout --quiet -b ramo
    troca linha-1 ramo dados.txt; git add dados.txt; com_trilha "feat: ramo"
    git checkout --quiet main
    git merge --quiet --no-ff --no-commit ramo
    printf "4\n" >> "com espaco.txt"; git add "com espaco.txt"; git commit --quiet -m "Merge espaco"'
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == "PRINCIPAL "*"Merge espaco (Humano)" ]]
}

# --- git sem --remerge-diff: falha segura --------------------------------------

# Stub de git no PATH que imita git anterior a 2.36: recusa --remerge-diff e repassa o resto.
stub_git_antigo() {
  real=$(command -v git)
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/git" <<EOF
#!/bin/sh
for a in "\$@"; do
  [ "\$a" != --remerge-diff ] || { echo "fatal: unrecognized argument: --remerge-diff" >&2; exit 128; }
done
exec "$real" "\$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/git"
}

@test "QA-D12: git sem --remerge-diff acusa merge limpo em vez de deixar passar" {
  na_principal '
    git checkout --quiet -b ramo
    troca linha-1 ramo dados.txt; git add dados.txt; com_trilha "feat: ramo"
    git checkout --quiet main
    troca linha-8 principal dados.txt; git add dados.txt; com_trilha "feat: principal"
    git merge --quiet --no-ff -m "Merge limpo" ramo'
  detectar
  [ "$status" -eq 0 ]
  stub_git_antigo
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run sh "$SCRIPT" --detectar --principal main
  [ "$status" -eq 3 ]
  [[ "$output" == "PRINCIPAL "*"Merge limpo (Humano)" ]]
  [[ "$output" != *"unrecognized"* ]]
}

@test "QA-D13: git sem --remerge-diff nao altera o caminho octopus (--cc)" {
  na_principal '
    for r in r1 r2; do
      git checkout --quiet -b "$r" main; printf "%s\n" "$r" > "$r.txt"; git add "$r.txt"; com_trilha "feat: $r"
    done
    git checkout --quiet main
    git merge --quiet --no-ff -m "Octopus limpo" r1 r2 >/dev/null'
  stub_git_antigo
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run sh "$SCRIPT" --detectar --principal main
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- diretorio no --registrar --------------------------------------------------

@test "QA-D14: registrar recusa '.' na raiz e no subdiretorio, sem tocar linha de base e marca" {
  mkdir -p sub; printf 'x\n' > sub/a.txt
  antes=$(base_atual); marca=$(marca_atual)
  run sh "$SCRIPT" --registrar . --principal main
  [ "$status" -eq 2 ]
  run sh -c 'cd sub && sh "$1" --registrar . --principal main' _ "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"diretorio"*"sub"* ]]
  run sh "$SCRIPT" --registrar sub/. --principal main
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --registrar ./sub// --principal main
  [ "$status" -eq 2 ]
  [ "$(base_atual)" = "$antes" ]
  [ "$(marca_atual)" = "$marca" ]
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO sub/a.txt" ]
}

@test "QA-D15: diretorio com espaco e recusado; arquivo dentro dele e aceito" {
  mkdir -p "meu dir"; printf 'x\n' > "meu dir/um arquivo.txt"
  run sh "$SCRIPT" --registrar "meu dir/" --principal main
  [ "$status" -eq 2 ]
  [[ "$output" == *"meu dir"* ]]
  sh "$SCRIPT" --registrar "meu dir/um arquivo.txt" --principal main
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "QA-D16: registrar com diretorio antes do arquivo valido recusa tudo; nada e absorvido" {
  mkdir -p pasta; printf 'x\n' > pasta/n.txt
  printf 'mudou\n' >> dados.txt
  antes=$(base_atual)
  run sh "$SCRIPT" --registrar pasta dados.txt --principal main
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --registrar dados.txt "$PWD/pasta" --principal main
  [ "$status" -eq 2 ]
  [ "$(base_atual)" = "$antes" ]
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == *"ARQUIVO dados.txt"* ]]
  [[ "$output" == *"ARQUIVO pasta/n.txt"* ]]
}

@test "QA-D17: diretorio vazio e recusado; caminho inexistente continua aceito como apagado" {
  mkdir vazio
  run sh "$SCRIPT" --registrar vazio --principal main
  [ "$status" -eq 2 ]
  git rm --quiet dados.txt
  sh "$SCRIPT" --registrar dados.txt --principal main
  detectar
  [ "$status" -eq 0 ]
}

@test "QA-D18: arquivo informado com barra final e registrado como o proprio arquivo" {
  printf 'mudou\n' >> dados.txt
  sh "$SCRIPT" --registrar dados.txt/ --principal main
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
