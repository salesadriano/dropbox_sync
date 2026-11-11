#!/usr/bin/env bats
# Suite independente do QA para scripts/porte.sh, scripts/memoria-extrato.sh e memoria-index.sh --check --estrito.
# Cobre o que as suites do autor nao prendem: binario, caminho com espaco, gatilho malformado, --caminhos ausente,
# arquivo ignorado pelo .gitignore, base por sha, termos vazios/maiusculos, README, --max-bytes 0, sufixo "(+N mais".

setup() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  PORTE="$BATS_TEST_DIRNAME/../porte.sh"
  RAIZ="$BATS_TEST_TMPDIR/repo"
  git init -q -b main "$RAIZ"
  mkdir -p "$RAIZ/src"
  echo base > "$RAIZ/src/a.js"
  git -C "$RAIZ" add -A; git -C "$RAIZ" commit -qm base
  BASE_SHA=$(git -C "$RAIZ" rev-parse HEAD)
  git -C "$RAIZ" checkout -q -b feature/x

  EX="$BATS_TEST_TMPDIR/raiz"
  mkdir -p "$EX/scripts" "$EX/.github/agents/memoria/entradas"
  cp "$BATS_TEST_DIRNAME/../memoria-extrato.sh" "$BATS_TEST_DIRNAME/../memoria-index.sh" "$EX/scripts/"
  DIR="$EX/.github/agents/memoria/entradas"
}

entrada() {  # $1 nome, $2 agentes, $3 titulo, $4 corpo
  printf -- '---\nid: %s\ntipo: decisao\nescopo: projeto\ntitulo: %s\ndata: 2026-10-01\ndono: Tech Lead\nagentes: %s\nstatus: ativa\n---\n\n%s\n' "$1" "$3" "$2" "$4" > "$DIR/$1.md"
}
porte() { run sh -c "cd '$RAIZ' && sh '$PORTE' --base main $*"; }

@test "porte: arquivo binario no diff conta como arquivo, zero linhas de codigo, e nao quebra" {
  head -c 4096 /dev/urandom > "$RAIZ/src/blob.bin"
  git -C "$RAIZ" add src/blob.bin
  porte
  [ "$status" -eq 0 ]
  [[ "$output" == *"arquivos: 1 | linhas de codigo: 0 (limite 50)"* ]]
  [[ "$output" == *"porte: P"* ]]
}

@test "porte: caminho com espaco e gatilho de padrao com espaco casam e contam linhas" {
  mkdir -p "$RAIZ/src/pasta com espaco"
  seq 1 3 > "$RAIZ/src/pasta com espaco/x y.js"
  printf 'M\t*pasta com espaco*\tpasta sensivel\n' > "$BATS_TEST_TMPDIR/g.txt"
  porte --caminhos "$BATS_TEST_TMPDIR/g.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"linhas de codigo: 3"* ]]
  [[ "$output" == *"gatilho: M *pasta com espaco* (pasta sensivel): src/pasta com espaco/x y.js"* ]]
  [[ "$output" == *"porte: M"* ]]
}

@test "porte: gatilho sem TAB e ignorado; --caminhos inexistente avisa em stderr; ambos seguem em P (exit 0)" {
  echo mudou >> "$RAIZ/src/a.js"
  printf 'M *.js dependencia sem tab\nG src/a.js sem tab\n' > "$BATS_TEST_TMPDIR/g.txt"
  porte --caminhos "$BATS_TEST_TMPDIR/g.txt"
  [ "$status" -eq 0 ]
  [[ "$output" != *"gatilho:"* ]]
  [[ "$output" == *"porte: P"* ]]
  run sh -c "cd '$RAIZ' && sh '$PORTE' --base main --caminhos nao-existe.txt 2>'$BATS_TEST_TMPDIR/err'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"porte: P"* ]]
  grep -q 'aviso: arquivo de gatilhos nao encontrado: nao-existe.txt' "$BATS_TEST_TMPDIR/err"
}

@test "porte: arquivo novo ignorado pelo .gitignore nao conta; o nao ignorado conta; base por sha funciona" {
  printf 'ignorado.log\n' > "$RAIZ/.gitignore"
  seq 1 100 > "$RAIZ/ignorado.log"
  seq 1 7 > "$RAIZ/src/novo.js"
  run sh -c "cd '$RAIZ' && sh '$PORTE' --base '$BASE_SHA'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"base: $BASE_SHA @ ${BASE_SHA:0:7}"* ]]
  [[ "$output" == *"arquivos: 2 | linhas de codigo: 8 (limite 50)"* ]]
  [[ "$output" != *"ignorado.log"* ]]
  [[ "$output" == *"porte: P"* ]]
}

@test "extrato: termos vazios ordenam por data, termo em maiusculas e acento pontua e README.md e ignorado" {
  entrada 2026-10-01-1000-velha qa-expert "Velha" "nada"
  entrada 2026-10-05-1000-nova qa-expert "Nova" "nada"
  entrada 2026-10-03-1000-acento qa-expert "Alocação de turno" "corpo"
  printf -- '---\nid: README\ntipo: decisao\nescopo: projeto\ntitulo: R\nagentes: todos\nstatus: ativa\n---\n\nreadme\n' > "$DIR/README.md"
  run sh -c "sh '$EX/scripts/memoria-extrato.sh' --papel qa-expert --termos '' | grep '^## '"
  [ "$status" -eq 0 ]
  [ "$output" = "## 2026-10-05-1000-nova
## 2026-10-03-1000-acento
## 2026-10-01-1000-velha" ]
  run sh -c "sh '$EX/scripts/memoria-extrato.sh' --papel qa-expert --termos 'ALOCACAO TURNO' | grep '^## ' | head -1"
  [ "$output" = "## 2026-10-03-1000-acento" ]
  run sh "$EX/scripts/memoria-extrato.sh" --papel qa-expert
  [[ "$output" == *"extrato: 3 de 3 entradas"* ]]
  [[ "$output" != *"readme"* ]]
}

@test "extrato: entrada sem frontmatter nao entra e nao derruba o extrato" {
  entrada 2026-10-01-1000-ok qa-expert "Ok" "corpo"
  printf 'so texto sem frontmatter\n' > "$DIR/2026-10-02-1000-solta.md"
  run sh "$EX/scripts/memoria-extrato.sh" --papel qa-expert
  [ "$status" -eq 0 ]
  [[ "$output" == *"## 2026-10-01-1000-ok"* ]]
  [[ "$output" != *"solta"* ]]
  [[ "$output" == *"extrato: 1 de 1 entradas"* ]]
}

@test "extrato: --max-bytes 0 omite tudo e mais de 12 omitidas viram sufixo (+N mais" {
  for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15; do
    entrada "2026-10-$i-1000-e$i" qa-expert "T$i" "corpo"
  done
  run sh "$EX/scripts/memoria-extrato.sh" --papel qa-expert --max-bytes 0
  [ "$status" -eq 0 ]
  [[ "$output" != *"## 2026"* ]]
  [[ "$output" == *"extrato: 0 de 15 entradas pertinentes, 0 bytes | omitidas: "* ]]
  [[ "$output" == *"(+3 mais; peca ao Tech Lead por assunto)"* ]]
}

@test "estrito: agentes com espacos \"a, b, c, d, e\" contam 5 papeis e avisam sem falhar; 4 nao avisam" {
  entrada 2026-10-01-1000-longa "tech-lead, senior-developer, qa-expert, dba, ux-expert" "T" "c"
  run sh -c "cd '$EX' && sh scripts/memoria-index.sh --check --estrito"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AVISO 2026-10-01-1000-longa: 5 papeis em agentes"* ]]
  entrada 2026-10-01-1000-longa "tech-lead, senior-developer, qa-expert, dba" "T" "c"
  run sh -c "cd '$EX' && sh scripts/memoria-index.sh --check --estrito"
  [ "$status" -eq 0 ]
  [[ "$output" != *"papeis em agentes"* ]]
}

@test "extrato: termo com maiuscula acentuada (ALOCAÇÃO) casa titulo acentuado em minuscula" {
  entrada 2026-10-01-1000-a qa-expert "Alocação" "x"
  entrada 2026-10-02-1000-b qa-expert "Outra" "x"
  run sh -c "sh '$EX/scripts/memoria-extrato.sh' --papel qa-expert --termos 'ALOCAÇÃO' | grep '^## ' | head -1"
  [ "$output" = "## 2026-10-01-1000-a" ]
}
