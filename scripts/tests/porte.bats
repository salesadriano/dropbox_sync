#!/usr/bin/env bats
# Testes de scripts/porte.sh: porte sugerido a partir do diff real contra a base, com gatilhos por caminho.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../porte.sh"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  RAIZ="$BATS_TEST_TMPDIR/repo"
  git init -q -b main "$RAIZ"
  mkdir -p "$RAIZ/src" "$RAIZ/.github/agents/memoria/entradas"
  printf -- '---\nid: 2026-09-19-1124-branch-principal\ntipo: decisao\ntitulo: Branch principal do projeto e `main`\nstatus: ativa\n---\n' > "$RAIZ/.github/agents/memoria/entradas/2026-09-19-1124-branch-principal.md"
  echo base > "$RAIZ/src/a.js"
  git -C "$RAIZ" add -A; git -C "$RAIZ" commit -qm base
  git -C "$RAIZ" checkout -q -b feature/x
}

@test "diff pequeno sem gatilho e P, com base da branch principal declarada" {
  echo mudou >> "$RAIZ/src/a.js"
  run sh -c "cd '$RAIZ' && sh '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"base: main @"* ]]
  [[ "$output" == *"linhas de codigo: 1 (limite 50)"* ]]
  [[ "$output" == *"porte: P"* ]]
}

@test "diff acima do limite sobe para M com motivo" {
  seq 1 60 >> "$RAIZ/src/a.js"
  run sh -c "cd '$RAIZ' && sh '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"motivo: 60 linhas de codigo excedem o limite de P (50)"* ]]
  [[ "$output" == *"porte: M"* ]]
}

@test "documentacao nao conta como codigo e --limite e respeitado" {
  seq 1 200 > "$RAIZ/docs-x.md"
  echo mudou >> "$RAIZ/src/a.js"
  run sh -c "cd '$RAIZ' && sh '$SCRIPT' --limite 1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"linhas de codigo: 1 (limite 1)"* ]]
  [[ "$output" == *"porte: P"* ]]
}

@test "gatilho embutido de migration sobe para M e de AGENTS.md para G" {
  mkdir -p "$RAIZ/db/migrations"; echo 'create' > "$RAIZ/db/migrations/001.sql"
  run sh -c "cd '$RAIZ' && sh '$SCRIPT'"
  [[ "$output" == *"gatilho: M */migrations/* (schema ou migration): db/migrations/001.sql"* ]]
  [[ "$output" == *"porte: M"* ]]
  echo regra > "$RAIZ/.github/agents/AGENTS.md"
  run sh -c "cd '$RAIZ' && sh '$SCRIPT'"
  [[ "$output" == *"gatilho: G */AGENTS.md (regra transversal do pacote): .github/agents/AGENTS.md"* ]]
  [[ "$output" == *"porte: G"* ]]
}

@test "entrada de memoria e log de prompt nunca casam gatilho" {
  echo 'x' > "$RAIZ/.github/agents/memoria/entradas/2026-10-19-1200-decisao.md"
  mkdir -p "$RAIZ/docs/prompts"; echo p > "$RAIZ/docs/prompts/2026-10-19_1200_x.md"
  run sh -c "cd '$RAIZ' && sh '$SCRIPT'"
  [[ "$output" != *"gatilho:"* ]]
  [[ "$output" == *"porte: P"* ]]
}

@test "arquivo de gatilhos do projeto acrescenta padrao e --critico forca M" {
  printf 'M\tsrc/perm*\tmatriz de autorizacao\n' > "$RAIZ/gatilhos.txt"
  echo x > "$RAIZ/src/permissoes.ts"
  run sh -c "cd '$RAIZ' && sh '$SCRIPT' --caminhos gatilhos.txt"
  [[ "$output" == *"gatilho: M src/perm* (matriz de autorizacao): src/permissoes.ts"* ]]
  [[ "$output" == *"porte: M"* ]]
  rm "$RAIZ/src/permissoes.ts"
  echo mudou >> "$RAIZ/src/a.js"
  run sh -c "cd '$RAIZ' && sh '$SCRIPT' --critico"
  [[ "$output" == *"motivo: defeito de alta criticidade declarado (--critico)"* ]]
  [[ "$output" == *"porte: M"* ]]
}

@test "base inexistente sai com 2 e limite invalido tambem" {
  run sh -c "cd '$RAIZ' && sh '$SCRIPT' --base nao-existe"
  [ "$status" -eq 2 ]
  run sh -c "cd '$RAIZ' && sh '$SCRIPT' --limite abc"
  [ "$status" -eq 2 ]
}

@test "sem branch principal declarada cai em origin/master; renomear nao conta linhas, apagar conta; --critico nao rebaixa gatilho G" {
  M="$BATS_TEST_TMPDIR/mestre"
  git init -q --bare "$BATS_TEST_TMPDIR/mestre.git"
  git init -q -b master "$M"
  git -C "$M" remote add origin "$BATS_TEST_TMPDIR/mestre.git"
  mkdir -p "$M/src"
  seq 1 100 > "$M/src/grande.js"; seq 1 3 > "$M/src/pequeno.js"
  git -C "$M" add -A; git -C "$M" commit -qm base
  git -C "$M" push -q -u origin master
  git -C "$M" mv src/grande.js src/renomeado.js
  git -C "$M" rm -q src/pequeno.js
  run sh -c "cd '$M' && sh '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"base: origin/master @"* ]]
  [[ "$output" == *"arquivos: 2 | linhas de codigo: 3 (limite 50)"* ]]
  [[ "$output" == *"porte: P"* ]]
  mkdir -p "$RAIZ/.github/agents"; echo regra > "$RAIZ/.github/agents/AGENTS.md"
  run sh -c "cd '$RAIZ' && sh '$SCRIPT' --critico"
  [ "$status" -eq 0 ]
  [[ "$output" == *"motivo: defeito de alta criticidade declarado (--critico)"* ]]
  [[ "$output" == *"porte: G"* ]]
}

# ---------- pendentes (auditoria 2026-11-08, secao 7) ----------

@test "pendente: diff vazio e porte P com zero arquivos e renomeado com destino em gatilho casa o gatilho" {
  skip "pendente: provar 'arquivos: 0 | linhas de codigo: 0' com exit 0 e o gatilho pelo destino do rename"
}
