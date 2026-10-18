#!/usr/bin/env bats
# Suite independente do QA Expert para verificar-instrucoes-do-projeto.sh.
# Complementa verificar-instrucoes-do-projeto.bats: globs e diretorios citados, numeracao duplicada, frases
# quebradas entre blockquote e texto, remotos ssh:// e com ponto no nome, primeira frase vence.
# Validacao: docs/reviews/2026-10-15-0914-skills-dos-mods-validacao-qa.md

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../verificar-instrucoes-do-projeto.sh"
  RAIZ="$BATS_TEST_TMPDIR/raiz"
  mkdir -p "$RAIZ/scripts" "$RAIZ/docs" "$RAIZ/.github/workflows"
  git -C "$RAIZ" init -q
  git -C "$RAIZ" remote add origin git@github.com:dono/repo.git
  unset GITHUB_REPOSITORY
  : > "$RAIZ/scripts/verificar.sh"; : > "$RAIZ/docs/guia.md"; : > "$RAIZ/.github/workflows/ci.yml"
  protocolo 48
  entrada_branch main
}

protocolo() {  # $1 = N
  mkdir -p "$RAIZ/.github/agents"
  {
    printf '# Protocolo comum obrigatorio\n\n'
    i=1; while [ "$i" -le "$1" ]; do printf '%s. Regra %s.\n' "$i" "$i"; i=$((i + 1)); done
    printf '\n# Outra\n\n1. Nao e regra.\n'
  } > "$RAIZ/.github/agents/AGENTS.md"
}

entrada_branch() {  # $1 = branch
  mkdir -p "$RAIZ/.github/agents/memoria/entradas"
  printf -- '---\nid: 2026-09-19-1124-branch-principal\ntipo: decisao\ntitulo: Branch principal do projeto e `%s`\nstatus: ativa\n---\n' "$1" > "$RAIZ/.github/agents/memoria/entradas/2026-09-19-1124-branch-principal.md"
}

@test "QA: (a) caminhos citados com glob, chaves e < sao ignorados; diretorio citado com barra final existe" {
  cat > "$RAIZ/CLAUDE.md" <<'EOF'
Veja `scripts/verificar-*.sh`, `.github/workflows/{a,b}.yml`, `docs/<assunto>.md`, `scripts/x?.sh` e `.github/workflows/`.
EOF
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok a: 1 caminho(s) citado(s) existem"* ]]
}

@test "QA: (a) o mesmo caminho ausente citado tres vezes e um unico drift" {
  printf 'Veja `docs/nao.md`, de novo `docs/nao.md` e `docs/nao.md`.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^- (a) caminho citado nao existe: docs/nao.md')" -eq 1 ]
}

@test "QA: (a) caminho citado que e link simbolico quebrado e drift (nao existe no disco)" {
  ln -s /nao/existe "$RAIZ/docs/link.md"
  printf 'Veja `docs/link.md`.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- (a) caminho citado nao existe: docs/link.md"* ]]
}

@test "QA: (b) numero duplicado no protocolo (5. 5.) e drift de continuidade, nao de contagem" {
  sed -i 's/^6\. Regra 6\./5. Regra 6./' "$RAIZ/.github/agents/AGENTS.md"
  printf 'O protocolo tem **48 regras**.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- (b) regras do protocolo nao sao 1..N continuas: esperava 6, achei 5"* ]]
}

@test "QA: (b) protocolo que comeca em 0 ou em 2 e drift de continuidade" {
  sed -i 's/^1\. Regra 1\./2. Regra 1./' "$RAIZ/.github/agents/AGENTS.md"
  printf 'O protocolo tem **48 regras**.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"esperava 1, achei 2"* ]]
}

@test "QA: (b) a primeira frase 'N regras' vence; uma segunda com outro numero nao e conferida" {
  printf 'O protocolo tem **48 regras**. A secao X tem 12 regras.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok b: 48 regras"* ]]
  printf 'A secao X tem 12 regras. O protocolo tem **48 regras**.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- (b) instrucoes dizem 12 regras, protocolo tem 48"* ]]
}

@test "QA: (b) regras numeradas fora da secao do protocolo nao contam (secao seguinte com 1. 2. 3.)" {
  printf 'O protocolo tem **48 regras**.\n' > "$RAIZ/CLAUDE.md"
  printf '\n# Ciclo\n\n1. a\n2. b\n3. c\n' >> "$RAIZ/.github/agents/AGENTS.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok b: 48 regras"* ]]
}

@test "QA: (c) frase quebrada entre uma linha de blockquote e uma linha comum, com blockquote aninhado" {
  cat > "$RAIZ/CLAUDE.md" <<'EOF'
> > A branch principal
declarada e `main`; o
> repositorio canonico
> > e `dono/repo`.
EOF
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok c: branch principal main"* ]]
  [[ "$output" == *"ok d: repositorio canonico dono/repo"* ]]
}

@test "QA: (c) crase vazia na frase (branch principal e \`\`) nao casa e a conferencia e pulada" {
  printf 'A branch principal declarada e ``.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pulada c:"* ]]
}

@test "QA: (c) duas entradas branch-principal ativas: a de nome mais recente decide" {
  printf 'A branch principal declarada e `develop`.\n' > "$RAIZ/CLAUDE.md"
  printf -- '---\nid: 2026-10-10-0900-branch-principal\ntipo: decisao\ntitulo: Branch principal do projeto e `develop`\nstatus: ativa\n---\n' > "$RAIZ/.github/agents/memoria/entradas/2026-10-10-0900-branch-principal.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok c: branch principal develop"* ]]
}

@test "QA: (d) remotos ssh://, https com barra final, git@ sem .git e nome com ponto reduzem a dono/repo" {
  printf 'O repositorio canonico e `dono/repo`.\n' > "$RAIZ/CLAUDE.md"
  for url in ssh://git@github.com/dono/repo.git https://github.com/dono/repo/ git@github.com:dono/repo https://user@github.com/dono/repo.git; do
    git -C "$RAIZ" remote set-url origin "$url"
    run sh "$SCRIPT" --raiz "$RAIZ"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok d: repositorio canonico dono/repo"* ]]
  done
  printf 'O repositorio canonico e `dono/my.repo`.\n' > "$RAIZ/CLAUDE.md"
  git -C "$RAIZ" remote set-url origin https://github.com/dono/my.repo.git
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok d: repositorio canonico dono/my.repo"* ]]
}

@test "QA: (d) LIMITE declarado: dono/repo com erro de digitacao identico nos dois lados passa" {
  printf 'O repositorio canonico e `dono/rpeo`.\n' > "$RAIZ/CLAUDE.md"
  git -C "$RAIZ" remote set-url origin git@github.com:dono/rpeo.git
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
}

@test "QA: (d) remoto com dono em caixa diferente do declarado e drift (comparacao literal)" {
  printf 'O repositorio canonico e `Dono/repo`.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- (d) instrucoes dizem repositorio canonico \`Dono/repo\`, remoto origin e \`dono/repo\`"* ]]
}

@test "QA: todas as quatro conferencias em drift ao mesmo tempo: quatro linhas, exit 1" {
  printf 'Veja `docs/nao.md`. **47 regras**. branch principal e `develop`. repositorio canonico e `outro/repo`.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^- (')" -eq 4 ]
}

@test "QA: arquivo de instrucoes vazio: as quatro conferencias sao puladas e o exit e 0" {
  : > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^pulada ')" -eq 4 ]
}

@test "QA: SEGURANCA: caminho citado com \cifrao-parenteses nao e expandido (espaco e < o excluem; sem espaco, e conferido literalmente)" {
  MARCA="$BATS_TEST_TMPDIR/marca"
  printf 'Veja `docs/$(touch %s).md`.\n' "$MARCA" > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ ! -e "$MARCA" ]
  printf 'Veja `docs/$(touch%s).md`.\n' "$MARCA" > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [ ! -e "$MARCA" ]
  [[ "$output" == *'caminho citado nao existe: docs/$(touch'* ]]
}

@test "QA: --raiz relativo e --instrucoes absoluto fora da raiz funcionam juntos" {
  mkdir -p "$BATS_TEST_TMPDIR/fora"
  printf 'branch principal e `main`.\n' > "$BATS_TEST_TMPDIR/fora/inst.md"
  cd "$BATS_TEST_TMPDIR"
  run sh "$SCRIPT" --raiz raiz --instrucoes "$BATS_TEST_TMPDIR/fora/inst.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok c: branch principal main"* ]]
}
