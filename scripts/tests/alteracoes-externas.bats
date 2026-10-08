#!/usr/bin/env bats
# Testes de scripts/alteracoes-externas.sh (regra 48 do AGENTS.md).
# Cada teste monta um repositorio descartavel com remoto proprio em $BATS_TEST_TMPDIR.
# Rodar: bats --abort scripts/tests/alteracoes-externas.bats (ou npx --yes bats --abort ...);
# --abort para no primeiro teste falho (Regra 9 de protocolo-tdd).

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
  printf 'ignorado.log\n' > .gitignore
  git add app.txt .gitignore
  commit_agente "feat: base"
  git push --quiet -u origin main
}

detectar() { run sh "$SCRIPT" --detectar --principal main; }

commit_agente() {
  git commit --quiet -m "$1" -m "Prompt: docs/prompts/x.md
Registro: docs/reviews/x.md"
}

commit_humano() { git commit --quiet -m "$1"; }

# --- arquivos ----------------------------------------------------------------

@test "arvore limpa sem linha de base: nada a acusar" {
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "arquivo rastreado alterado sem registro e acusado com exit 3" {
  printf 'b\n' >> app.txt
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO app.txt" ]
}

@test "arquivo alterado e registrado pelo agent nao e acusado" {
  sh "$SCRIPT" --inicial --principal main
  printf 'b\n' >> app.txt
  sh "$SCRIPT" --registrar app.txt --principal main
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "arquivo registrado e alterado de novo por pessoa e acusado" {
  sh "$SCRIPT" --inicial --principal main
  printf 'b\n' >> app.txt
  sh "$SCRIPT" --registrar app.txt --principal main
  printf 'humano\n' >> app.txt
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO app.txt" ]
}

@test "alteracao do agent desfeita por pessoa e acusada" {
  sh "$SCRIPT" --inicial --principal main
  printf 'b\n' >> app.txt
  sh "$SCRIPT" --registrar app.txt --principal main
  git checkout --quiet -- app.txt
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO app.txt" ]
}

@test "arquivo novo nao rastreado e acusado; arquivo ignorado nao" {
  printf 'x\n' > novo.txt
  printf 'x\n' > ignorado.log
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO novo.txt" ]
}

@test "arquivo apagado e acusado" {
  rm app.txt
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO app.txt" ]
}

@test "caminho com espaco e acentuacao e acusado literalmente" {
  printf 'x\n' > "pasta de acao.txt"
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO pasta de acao.txt" ]
  printf 'x\n' > "ação.txt"
  sh "$SCRIPT" --inicial --principal main
  sh "$SCRIPT" --registrar "pasta de acao.txt" --principal main
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO ação.txt" ]
}

@test "registro aceita caminho relativo a subdiretorio" {
  mkdir -p src
  printf 'x\n' > src/mod.txt
  sh "$SCRIPT" --inicial --principal main
  (cd src && sh "$SCRIPT" --registrar mod.txt --principal main)
  detectar
  [ "$status" -eq 0 ]
}

@test "registrar nao absorve alteracao humana em arquivo nao informado" {
  sh "$SCRIPT" --inicial --principal main
  printf 'b\n' >> app.txt
  printf 'x\n' > humano.txt
  sh "$SCRIPT" --registrar app.txt --principal main
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO humano.txt" ]
}

@test "inicial nao absorve arquivo ja alterado" {
  printf 'b\n' >> app.txt
  sh "$SCRIPT" --inicial --principal main
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO app.txt" ]
}

@test "inicial recusa sobrescrever linha de base existente" {
  sh "$SCRIPT" --inicial --principal main
  run sh "$SCRIPT" --inicial --principal main
  [ "$status" -eq 1 ]
  [[ "$output" == *"linha de base ja existe"* ]]
}

@test "registrar sem linha de base exige --inicial" {
  run sh "$SCRIPT" --registrar app.txt --principal main
  [ "$status" -eq 1 ]
  [[ "$output" == *"--inicial"* ]]
}

@test "commit do agent com o registro do arquivo antes nao gera acusacao" {
  sh "$SCRIPT" --inicial --principal main
  printf 'b\n' >> app.txt
  sh "$SCRIPT" --registrar app.txt --principal main
  git add app.txt
  commit_agente "feat: agent"
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- commits -----------------------------------------------------------------

@test "commit sem trilha do protocolo na branch e acusado" {
  git checkout --quiet -b feature/x
  sh "$SCRIPT" --inicial --principal main
  printf 'b\n' >> app.txt
  git add app.txt
  commit_humano "ajuste manual"
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == "COMMIT "*" ajuste manual (Pessoa)" ]]
}

@test "registrar sem --commits nao absorve commit humano; com --commits absorve" {
  git checkout --quiet -b feature/x
  sh "$SCRIPT" --inicial --principal main
  printf 'b\n' >> app.txt
  git add app.txt
  commit_humano "ajuste manual"
  sh "$SCRIPT" --registrar --principal main
  detectar
  [ "$status" -eq 3 ]
  sh "$SCRIPT" --registrar --commits --principal main
  detectar
  [ "$status" -eq 0 ]
}

@test "commit do agent avanca a linha de base e commit humano posterior e acusado" {
  git checkout --quiet -b feature/x
  sh "$SCRIPT" --inicial --principal main
  printf 'b\n' >> app.txt
  git add app.txt
  commit_agente "feat: agent"
  sh "$SCRIPT" --registrar --principal main
  printf 'c\n' >> app.txt
  git add app.txt
  commit_humano "outro ajuste"
  detectar
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == *"outro ajuste"* ]]
}

@test "historico reescrito fora da linha de base e acusado" {
  git checkout --quiet -b feature/x
  printf 'b\n' >> app.txt
  git add app.txt
  commit_agente "feat: agent"
  sh "$SCRIPT" --inicial --principal main
  git reset --quiet --hard HEAD~1
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == "HISTORICO "* ]]
}

@test "commits que vieram da branch principal por integracao nao sao acusados na branch" {
  git checkout --quiet -b feature/x
  sh "$SCRIPT" --inicial --principal main
  git checkout --quiet main
  printf 'x\n' > outro.txt
  git add outro.txt
  commit_agente "feat: outra demanda"
  git push --quiet origin main
  git checkout --quiet feature/x
  git merge --quiet --no-edit -m "merge: integra main" -m "Prompt: docs/prompts/x.md" origin/main
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- branch principal --------------------------------------------------------

@test "commit sem trilha que chega a branch principal e acusado" {
  git checkout --quiet -b feature/x
  sh "$SCRIPT" --inicial --principal main
  git clone --quiet "$BATS_TEST_TMPDIR/remoto.git" "$BATS_TEST_TMPDIR/outro" 2>/dev/null
  (
    cd "$BATS_TEST_TMPDIR/outro"
    printf 'h\n' > hotfix.txt
    git add hotfix.txt
    git commit --quiet -m "hotfix direto"
    git push --quiet origin main
  )
  git fetch --quiet origin
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == "PRINCIPAL "*" hotfix direto (Pessoa)" ]]
}

@test "commit com trilha na branch principal nao e acusado" {
  sh "$SCRIPT" --inicial --principal main
  git clone --quiet "$BATS_TEST_TMPDIR/remoto.git" "$BATS_TEST_TMPDIR/outro" 2>/dev/null
  (
    cd "$BATS_TEST_TMPDIR/outro"
    printf 'h\n' > outro.txt
    git add outro.txt
    git commit --quiet -m "feat: outra instancia" -m "Prompt: docs/prompts/y.md"
    git push --quiet origin main
  )
  git fetch --quiet origin
  detectar
  [ "$status" -eq 0 ]
}

@test "marca da branch principal e compartilhada entre worktrees" {
  sh "$SCRIPT" --inicial --principal main
  git clone --quiet "$BATS_TEST_TMPDIR/remoto.git" "$BATS_TEST_TMPDIR/outro" 2>/dev/null
  (
    cd "$BATS_TEST_TMPDIR/outro"
    printf 'h\n' > hotfix.txt
    git add hotfix.txt
    git commit --quiet -m "hotfix direto"
    git push --quiet origin main
  )
  git fetch --quiet origin
  git worktree add --quiet --no-track -b feature/y "$BATS_TEST_TMPDIR/wt" origin/main
  cd "$BATS_TEST_TMPDIR/wt"
  sh "$SCRIPT" --inicial --principal main
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == *"PRINCIPAL "*"hotfix direto"* ]]
}

@test "linha de base e propria de cada worktree" {
  sh "$SCRIPT" --inicial --principal main
  git worktree add --quiet --no-track -b feature/y "$BATS_TEST_TMPDIR/wt" origin/main
  printf 'b\n' >> "$BATS_TEST_TMPDIR/wt/app.txt"
  (cd "$BATS_TEST_TMPDIR/wt" && sh "$SCRIPT" --inicial --principal main && sh "$SCRIPT" --registrar app.txt --principal main)
  printf 'humano\n' >> app.txt
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO app.txt" ]
  cd "$BATS_TEST_TMPDIR/wt"
  detectar
  [ "$status" -eq 0 ]
}

# --- configuracao ------------------------------------------------------------

@test "branch principal lida da entrada branch-principal ativa da memoria" {
  mkdir -p .github/agents/memoria/entradas
  printf -- '---\nstatus: ativa\ntitulo: Branch principal do projeto e `main`\n---\n' \
    > .github/agents/memoria/entradas/2026-01-01-0000-branch-principal.md
  git add .github
  commit_agente "chore: memoria"
  git push --quiet origin main
  sh "$SCRIPT" --inicial
  git clone --quiet "$BATS_TEST_TMPDIR/remoto.git" "$BATS_TEST_TMPDIR/outro" 2>/dev/null
  (
    cd "$BATS_TEST_TMPDIR/outro"
    printf 'h\n' > hotfix.txt
    git add hotfix.txt
    git commit --quiet -m "hotfix direto"
    git push --quiet origin main
  )
  git fetch --quiet origin
  run sh "$SCRIPT" --detectar
  [ "$status" -eq 3 ]
  [[ "$output" == *"hotfix direto"* ]]
}

@test "sem branch principal conhecida o script falha em vez de supor" {
  run sh "$SCRIPT" --detectar
  [ "$status" -eq 1 ]
  [[ "$output" == *"branch principal"* ]]
}

@test "argumento desconhecido falha com exit 2" {
  run sh "$SCRIPT" --apagar
  [ "$status" -eq 2 ]
}

@test "fora de repositorio git falha com exit 1" {
  cd "$BATS_TEST_TMPDIR"
  mkdir vazio && cd vazio
  run sh "$SCRIPT" --detectar --principal main
  [ "$status" -eq 1 ]
}

@test "detectar nunca altera a arvore de trabalho nem o indice" {
  printf 'b\n' >> app.txt
  printf 'x\n' > novo.txt
  antes=$(git status --porcelain; git diff; git diff --cached)
  detectar
  depois=$(git status --porcelain; git diff; git diff --cached)
  [ "$antes" = "$depois" ]
}

@test "caminho com barra invertida registrado nao gera falso positivo" {
  printf 'x\n' > 'a\tb.txt'
  sh "$SCRIPT" --inicial --principal main
  sh "$SCRIPT" --registrar 'a\tb.txt' --principal main
  detectar
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "symlink criado por pessoa e acusado, inclusive para diretorio" {
  mkdir alvo
  ln -s alvo link-dir
  ln -s app.txt link-arq
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == *"ARQUIVO link-arq"* ]]
  [[ "$output" == *"ARQUIVO link-dir"* ]]
}

@test "symlink registrado e comitado pelo agent sai da linha de base" {
  sh "$SCRIPT" --inicial --principal main
  ln -s app.txt link-arq
  sh "$SCRIPT" --registrar link-arq --principal main
  git add link-arq
  commit_agente "feat: link"
  sh "$SCRIPT" --registrar --principal main
  detectar
  [ "$status" -eq 0 ]
  [ "$(sed 1d "$(git rev-parse --absolute-git-dir)/agentes-linha-de-base")" = "" ]
}

# --- achados do QA (ciclo 1) -------------------------------------------------

@test "QA-B1: nomes que o git poe entre aspas sao acusados" {
  printf 'x\n' > 'a"b.txt'
  printf 'y\n' > 'c\d.txt'
  printf 'z\n' > "$(printf 'n\tl.txt')"
  detectar
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "QA-B1: nome com quebra de linha e acusado" {
  printf 'x\n' > "$(printf 'um\ndois.txt')"
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == "ARQUIVO um?dois.txt" ]]
}

@test "QA-B2: mudanca so de modo executavel e acusada" {
  chmod +x app.txt
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO app.txt" ]
}

@test "QA-B3: versao preparada por pessoa diferente da arvore e acusada" {
  sh "$SCRIPT" --inicial --principal main
  echo agent > app.txt
  sh "$SCRIPT" --registrar app.txt --principal main
  echo humano > app.txt
  git add app.txt
  echo agent > app.txt
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO app.txt" ]
}

@test "QA-B4: arquivo novo preparado e apagado da arvore e acusado" {
  sh "$SCRIPT" --inicial --principal main
  echo h > h.txt
  git add h.txt
  rm h.txt
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO h.txt" ]
}

@test "QA-B5: commit humano local no checkout principal sem linha de base e acusado" {
  echo h > x.txt
  git add x.txt
  commit_humano "humano"
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == "COMMIT "*" humano (Pessoa)" ]]
}

@test "QA-B6: merge com alteracao propria sem trilha na principal e acusado; merge limpo nao" {
  sh "$SCRIPT" --inicial --principal main
  git clone --quiet "$BATS_TEST_TMPDIR/remoto.git" "$BATS_TEST_TMPDIR/outro" 2>/dev/null
  (
    cd "$BATS_TEST_TMPDIR/outro"
    git checkout --quiet -b feat
    echo f > f.txt; git add f.txt; commit_agente "feat: f"
    git checkout --quiet main
    git merge --quiet --no-ff -m "Merge limpo" feat
    git checkout --quiet -b feat2
    echo g > g.txt; git add g.txt; commit_agente "feat: g"
    git checkout --quiet main
    git merge --quiet --no-ff --no-commit feat2
    echo maligno >> app.txt; git add app.txt
    git commit --quiet -m "Merge feat2"
    git push --quiet origin main
  )
  git fetch --quiet origin
  detectar
  [ "$status" -eq 3 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "PRINCIPAL "*"Merge feat2 (Pessoa)" ]]
}

@test "QA-B7: marca da principal ausente ou vazia nao absorve commit humano" {
  sh "$SCRIPT" --inicial --principal main
  : > "$(git rev-parse --git-common-dir)/agentes-principal"
  git clone --quiet "$BATS_TEST_TMPDIR/remoto.git" "$BATS_TEST_TMPDIR/outro" 2>/dev/null
  (
    cd "$BATS_TEST_TMPDIR/outro"
    echo h > hotfix.txt; git add hotfix.txt; git commit --quiet -m "hotfix direto"
    git push --quiet origin main
  )
  git fetch --quiet origin
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == "PRINCIPAL "*"hotfix direto"* ]]
  [[ "$output" != *"HISTORICO"* ]]
  sh "$SCRIPT" --registrar --principal main
  detectar
  [ "$status" -eq 3 ]
}

@test "QA-B8: submodulo registrado continua sob deteccao" {
  git init --quiet --initial-branch=main "$BATS_TEST_TMPDIR/sub"
  (cd "$BATS_TEST_TMPDIR/sub" && echo s > s.txt && git add s.txt && git commit --quiet -m s && echo t >> s.txt && git commit --quiet -am t)
  git -c protocol.file.allow=always submodule --quiet add "$BATS_TEST_TMPDIR/sub" mod
  commit_agente "feat: submodulo"
  git push --quiet origin main
  sh "$SCRIPT" --inicial --principal main
  git -C mod checkout --quiet HEAD~1
  sh "$SCRIPT" --registrar mod --principal main
  detectar
  [ "$status" -eq 0 ]
  git -C mod checkout --quiet main
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO mod" ]
  git -C mod checkout --quiet HEAD~1
  echo hh >> mod/s.txt
  detectar
  [ "$status" -eq 3 ]
  [ "$output" = "ARQUIVO mod" ]
}

@test "QA-B9: branch principal inexistente no remoto falha com exit 1" {
  run sh "$SCRIPT" --detectar --principal naoexiste
  [ "$status" -eq 1 ]
  [[ "$output" == *"naoexiste"* ]]
  run sh "$SCRIPT" --detectar --principal main --remoto nada
  [ "$status" -eq 1 ]
}

@test "QA-M1: registrar normaliza ./ e ../ e aceita caminho absoluto dentro do repositorio" {
  mkdir -p sub
  sh "$SCRIPT" --inicial --principal main
  printf 'b\n' >> app.txt
  printf 'x\n' > sub/f.txt
  sh "$SCRIPT" --registrar ./app.txt sub/./f.txt --principal main
  detectar
  [ "$status" -eq 0 ]
  printf 'c\n' >> app.txt
  (cd sub && sh "$SCRIPT" --registrar ../app.txt --principal main)
  detectar
  [ "$status" -eq 0 ]
  printf 'd\n' >> app.txt
  sh "$SCRIPT" --registrar "$PWD/app.txt" --principal main
  detectar
  [ "$status" -eq 0 ]
}

@test "QA-M1: registrar recusa caminho fora do repositorio" {
  sh "$SCRIPT" --inicial --principal main
  run sh "$SCRIPT" --registrar ../fora.txt --principal main
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --registrar /etc/hosts --principal main
  [ "$status" -eq 2 ]
}

@test "QA-m1: renomeacao acusa origem e destino" {
  git mv app.txt b.txt
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == *"ARQUIVO app.txt"* ]]
  [[ "$output" == *"ARQUIVO b.txt"* ]]
}

@test "QA-m2: assume-unchanged e skip-worktree nao escondem a alteracao" {
  printf 'x\n' > outro.txt
  git add outro.txt
  commit_agente "feat: outro"
  git update-index --assume-unchanged app.txt
  git update-index --skip-worktree outro.txt
  printf 'b\n' >> app.txt
  printf 'b\n' >> outro.txt
  detectar
  [ "$status" -eq 3 ]
  [[ "$output" == *"ARQUIVO app.txt"* ]]
  [[ "$output" == *"ARQUIVO outro.txt"* ]]
}

# --- achados do QA (ciclo 2) -------------------------------------------------

@test "QA-N1: agent prepara uma versao e continua editando o mesmo arquivo" {
  git checkout --quiet -b feat
  sh "$SCRIPT" --inicial --principal main
  printf 'v1\n' >> app.txt
  git add app.txt
  printf 'v2\n' >> app.txt
  sh "$SCRIPT" --registrar app.txt --principal main
  detectar
  [ "$status" -eq 0 ]
  printf 'humano\n' > app.txt
  git add app.txt
  printf 'v2\n' >> app.txt
  detectar
  [ "$status" -eq 3 ]
}

@test "QA-N2: merge de integracao com conflito nao acusa o que veio da principal" {
  git checkout --quiet -b feat
  sh "$SCRIPT" --inicial --principal main
  printf 'feat\n' >> app.txt
  sh "$SCRIPT" --registrar app.txt --principal main
  git add app.txt; commit_agente "feat: lado feat"
  sh "$SCRIPT" --registrar --principal main
  git checkout --quiet main
  printf 'main\n' >> app.txt; printf 'o\n' > o.txt
  git add app.txt o.txt; commit_agente "feat: lado main"
  git push --quiet origin main
  git checkout --quiet feat
  run git merge -m "merge: integra main" -m "Prompt: x" origin/main
  [ "$status" -ne 0 ]
  detectar
  [ "$status" -eq 0 ]
  printf 'a\nfeat\nmain\n' > app.txt
  sh "$SCRIPT" --registrar app.txt --principal main
  git add app.txt
  detectar
  [ "$status" -eq 0 ]
  git commit --quiet --no-edit
  sh "$SCRIPT" --registrar --principal main
  detectar
  [ "$status" -eq 0 ]
}

@test "QA-N3: caminho absoluto por symlink para o repositorio e aceito" {
  ln -s "$BATS_TEST_TMPDIR/repo" "$BATS_TEST_TMPDIR/link"
  sh "$SCRIPT" --inicial --principal main
  printf 'b\n' >> app.txt
  (cd "$BATS_TEST_TMPDIR/link" && sh "$SCRIPT" --registrar "$BATS_TEST_TMPDIR/link/app.txt" --principal main)
  detectar
  [ "$status" -eq 0 ]
}
