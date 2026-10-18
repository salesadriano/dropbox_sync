#!/usr/bin/env bats
# Testes de verificar-instrucoes-do-projeto.sh: drift entre o arquivo de instrucoes e o repositorio.
# Cada caso monta um repositorio git real em $BATS_TEST_TMPDIR; nada toca o repositorio do pacote.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../verificar-instrucoes-do-projeto.sh"
  RAIZ="$BATS_TEST_TMPDIR/raiz"
  mkdir -p "$RAIZ"
  git -C "$RAIZ" init -q
  git -C "$RAIZ" remote add origin git@github.com:dono/repo.git
  unset GITHUB_REPOSITORY
}

# Protocolo com N regras contiguas em `# Protocolo comum obrigatorio`, no layout pedido ($1 = dir, $2 = N).
protocolo() {
  mkdir -p "$RAIZ/$1"
  {
    printf '# Proposito\n\nTexto.\n\n# Protocolo comum obrigatorio\n\nIntro.\n\n'
    i=1; while [ "$i" -le "$2" ]; do printf '%s. Regra %s.\n' "$i" "$i"; i=$((i + 1)); done
    printf '\n# Outra secao\n\n1. Item que nao e regra.\n'
  } > "$RAIZ/$1/AGENTS.md"
}

# Entrada branch-principal ($1 = dir de entradas, $2 = branch, $3 = status, $4 = data-hora do nome).
entrada_branch() {
  mkdir -p "$RAIZ/$1"
  cat > "$RAIZ/$1/${4:-2026-09-19-1124}-branch-principal.md" <<EOF
---
id: ${4:-2026-09-19-1124}-branch-principal
tipo: decisao
titulo: Branch principal do projeto e \`$2\`
status: ${3:-ativa}
---

Corpo.
EOF
}

# Arquivo de instrucoes completo e coerente com o repositorio montado por `repo_completo`.
instrucoes() {  # $1 = caminho relativo
  mkdir -p "$RAIZ/$(dirname "$1")"
  cat > "$RAIZ/$1" <<'EOF'
# Instrucoes

Rode `scripts/verificar.sh` e leia `docs/guia.md`; o protocolo tem **48 regras**.
A branch principal declarada e `main`. O repositorio canonico e `dono/repo`.
Comando com argumento: `scripts/verificar.sh --raiz .` nao e caminho. Glob: `docs/*.md`.
EOF
}

repo_completo() {
  mkdir -p "$RAIZ/scripts" "$RAIZ/docs"
  : > "$RAIZ/scripts/verificar.sh"
  : > "$RAIZ/docs/guia.md"
  protocolo .github/agents 48
  entrada_branch .github/agents/memoria/entradas main
}

@test "repositorio coerente: quatro conferencias ok e exit 0" {
  repo_completo; instrucoes CLAUDE.md
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok a: 2 caminho(s) citado(s) existem"* ]]
  [[ "$output" == *"ok b: 48 regras"* ]]
  [[ "$output" == *"ok c: branch principal main"* ]]
  [[ "$output" == *"ok d: repositorio canonico dono/repo"* ]]
  [[ "$output" == *"sem drift: $RAIZ/CLAUDE.md"* ]]
}

@test "(a) caminho citado que nao existe e drift" {
  repo_completo; instrucoes CLAUDE.md
  rm "$RAIZ/docs/guia.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- (a) caminho citado nao existe: docs/guia.md"* ]]
  [[ "$output" != *"scripts/verificar.sh"*"nao existe"* ]]
}

@test "(a) citacao com argumento ou glob nao e tratada como caminho" {
  repo_completo; instrucoes CLAUDE.md
  rm "$RAIZ/scripts/verificar.sh" "$RAIZ/docs/guia.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^- (a)')" -eq 2 ]
}

@test "(a) sem caminho citado entre crases e pulada" {
  repo_completo
  printf 'Sem caminhos. **48 regras**. branch principal e `main`. repositorio canonico e `dono/repo`.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pulada a: nenhum caminho citado"* ]]
}

@test "(b) contagem de regras diferente do protocolo e drift" {
  repo_completo; instrucoes CLAUDE.md
  protocolo .github/agents 47
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- (b) instrucoes dizem 48 regras, protocolo tem 47"* ]]
}

@test "(b) regras do protocolo com buraco sao drift, nao contagem" {
  repo_completo; instrucoes CLAUDE.md
  sed -i 's/^30\. Regra 30\./31. Regra 30./' "$RAIZ/.github/agents/AGENTS.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- (b) regras do protocolo nao sao 1..N continuas: esperava 30, achei 31"* ]]
}

@test "(b) frase 'N regras' sem negrito tambem e lida" {
  repo_completo
  printf 'O protocolo tem 48 regras. branch principal e `main`. repositorio canonico e `dono/repo`.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok b: 48 regras"* ]]
}

@test "(b) sem a frase ou sem o protocolo e pulada" {
  repo_completo
  printf 'branch principal e `main`. repositorio canonico e `dono/repo`.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pulada b: frase 'N regras' nao encontrada"* ]]
  instrucoes CLAUDE.md
  rm "$RAIZ/.github/agents/AGENTS.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pulada b: protocolo nao encontrado"* ]]
}

@test "(c) branch declarada diferente da entrada ativa e drift" {
  repo_completo; instrucoes CLAUDE.md
  entrada_branch .github/agents/memoria/entradas develop ativa 2026-09-25-1400
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- (c) instrucoes dizem branch principal \`main\`, entrada 2026-09-25-1400-branch-principal declara \`develop\`"* ]]
}

@test "(c) entrada substituida (status != ativa) nao conta; a ativa mais recente vence" {
  repo_completo; instrucoes CLAUDE.md
  entrada_branch .github/agents/memoria/entradas develop substituida 2026-09-25-1400
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok c: branch principal main"* ]]
}

@test "(c) aceita 'branch principal e' sem 'declarada' e com acento" {
  repo_completo
  printf 'A branch principal \303\251 `main`. repositorio canonico e `dono/repo`.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok c: branch principal main"* ]]
}

@test "(c) sem frase ou sem entrada ativa e pulada" {
  repo_completo
  printf 'repositorio canonico e `dono/repo`.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pulada c: frase 'branch principal' nao encontrada"* ]]
  instrucoes CLAUDE.md
  rm -r "$RAIZ/.github/agents/memoria"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pulada c: entrada branch-principal ativa nao encontrada"* ]]
}

@test "(d) canonico declarado diferente do remoto origin e drift" {
  repo_completo; instrucoes CLAUDE.md
  git -C "$RAIZ" remote set-url origin git@github.com:outro/repo.git
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- (d) instrucoes dizem repositorio canonico \`dono/repo\`, remoto origin e \`outro/repo\`"* ]]
}

@test "(d) remoto https com e sem .git reduz a dono/repo" {
  repo_completo; instrucoes CLAUDE.md
  git -C "$RAIZ" remote set-url origin https://github.com/dono/repo.git
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok d: repositorio canonico dono/repo"* ]]
  git -C "$RAIZ" remote set-url origin https://github.com/dono/repo
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok d: repositorio canonico dono/repo"* ]]
}

@test "(d) frase com acentos tambem e lida" {
  repo_completo
  printf 'O reposit\303\263rio can\303\264nico \303\251 `dono/repo`. branch principal e `main`.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok d: repositorio canonico dono/repo"* ]]
}

@test "(d) sem .git usa GITHUB_REPOSITORY; sem os dois e pulada" {
  repo_completo; instrucoes CLAUDE.md
  rm -rf "$RAIZ/.git"
  GITHUB_REPOSITORY=dono/repo run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok d: repositorio canonico dono/repo"* ]]
  GITHUB_REPOSITORY=outro/repo run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- (d) instrucoes dizem repositorio canonico \`dono/repo\`, remoto origin e \`outro/repo\`"* ]]
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pulada d: sem .git e sem GITHUB_REPOSITORY"* ]]
}

@test "frases quebradas em duas linhas, inclusive dentro de blockquote, sao lidas (b, c e d)" {
  repo_completo
  cat > "$RAIZ/CLAUDE.md" <<'EOF'
> Este arquivo tem **48
> regras**. A branch principal
> declarada e `main`, e o repositorio
> canonico e `dono/repo`.
EOF
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok b: 48 regras"* ]]
  [[ "$output" == *"ok c: branch principal main"* ]]
  [[ "$output" == *"ok d: repositorio canonico dono/repo"* ]]
}

@test "(d) sem a frase do canonico e pulada" {
  repo_completo
  printf 'branch principal e `main`.\n' > "$RAIZ/CLAUDE.md"
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pulada d: frase 'repositorio canonico' nao encontrada"* ]]
}

@test "deteccao do arquivo de instrucoes: CLAUDE.md, copilot-instructions.md e AGENTS.md da raiz, nessa ordem" {
  repo_completo
  instrucoes .github/copilot-instructions.md
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sem drift: $RAIZ/.github/copilot-instructions.md"* ]]
  rm "$RAIZ/.github/copilot-instructions.md"
  instrucoes AGENTS.md
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sem drift: $RAIZ/AGENTS.md"* ]]
  instrucoes CLAUDE.md
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sem drift: $RAIZ/CLAUDE.md"* ]]
}

@test "--instrucoes explicito vence a deteccao" {
  repo_completo; instrucoes CLAUDE.md; instrucoes docs/outro.md
  printf 'branch principal e `errada`.\n' >> "$RAIZ/docs/outro.md"
  run sh "$SCRIPT" --raiz "$RAIZ" --instrucoes docs/outro.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"sem drift: $RAIZ/docs/outro.md"* ]]
}

@test "sem arquivo de instrucoes detectavel sai 2 pedindo --instrucoes" {
  repo_completo
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--instrucoes"* ]]
  run sh "$SCRIPT" --raiz "$RAIZ" --instrucoes nao-existe.md
  [ "$status" -eq 2 ]
}

@test "layout .claude/ai_team e detectado para protocolo e entradas" {
  mkdir -p "$RAIZ/scripts" "$RAIZ/docs"; : > "$RAIZ/scripts/verificar.sh"; : > "$RAIZ/docs/guia.md"
  protocolo .claude/ai_team 48
  entrada_branch .claude/ai_team/memoria/entradas main
  instrucoes CLAUDE.md
  run sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok b: 48 regras"* ]]
  [[ "$output" == *"ok c: branch principal main"* ]]
}

@test "--protocolo e --entradas explicitos vencem os layouts conhecidos" {
  repo_completo; instrucoes CLAUDE.md
  protocolo outro 48
  entrada_branch outro/entradas main
  protocolo .github/agents 3
  entrada_branch .github/agents/memoria/entradas develop
  run sh "$SCRIPT" --raiz "$RAIZ" --protocolo outro/AGENTS.md --entradas outro/entradas
  [ "$status" -eq 0 ]
}

@test "raiz padrao e o topo do git do diretorio corrente" {
  repo_completo; instrucoes CLAUDE.md
  cd "$RAIZ/docs"
  run sh "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sem drift: $RAIZ/CLAUDE.md"* ]]
}

@test "argumento invalido ou sem valor sai 2" {
  run sh "$SCRIPT" --x
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --raiz
  [ "$status" -eq 2 ]
}

@test "roda sob dash" {
  command -v dash >/dev/null 2>&1 || skip "dash nao instalado"
  repo_completo; instrucoes CLAUDE.md
  run dash "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
}
