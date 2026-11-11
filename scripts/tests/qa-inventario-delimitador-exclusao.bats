#!/usr/bin/env bats
# Suite independente do QA para scripts/inventario-de-testes.sh nas issues #64 (nome pelo delimitador que abre
# primeiro, `\\` literal), #65 (`!<glob>`), #66 (aviso NAO-DESCOBERTO) e #67 item 4 (coluna Condicao de execucao).
# Cobre o que a suite do autor nao prende: nome igual ao que o proprio Bats imprime, crase que abre antes de aspas,
# `\\` seguido do delimitador, exclusao que tira tudo, exclusao com espaco e comentada, aviso unico por linha com dois
# padroes, condicao sem lado esquerdo, `\|` escapado, coluna pelo cabecalho acentuado e duas tabelas no mesmo bloco.
# Nota (regra 12): este arquivo NAO e versionado antes do aceite do solicitante. Cada teste monta um repositorio
# descartavel em $BATS_TEST_TMPDIR.

setup() {
  export GIT_AUTHOR_NAME=q GIT_AUTHOR_EMAIL=q@q GIT_COMMITTER_NAME=q GIT_COMMITTER_EMAIL=q@q
  export SCRIPT="$BATS_TEST_DIRNAME/../inventario-de-testes.sh"
  RAIZ="$BATS_TEST_TMPDIR/proj"
  INV="$RAIZ/docs/testes/inventario-de-testes.md"
  git init -q -b main "$RAIZ"
  mkdir -p "$RAIZ/spec" "$RAIZ/docs/testes"
}

versiona() { git -C "$RAIZ" add -A; }

# Bloco completo para o arquivo $1 (sem tabela).
bloco() {
  printf '## `%s`\n\n- **Alvo:** `pedido.sh`\n- **Modulo:** pedidos\n- **Camada:** unitario\n- **Autoria:** Senior Developer (TDD da demanda `q`)\n- **Regras de origem:** AGENTS.md 51\n- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer\n- **Comando:** `bats --abort %s`\n\n' "$1" "$1"
}

roda() { run sh -c 'cd "$1" && shift && sh "$SCRIPT" "$@"' _ "$RAIZ" "$@"; }

# ---------- #64: nome pelo delimitador que abre primeiro ----------

@test "nome descoberto e igual ao que o Bats imprime para aspas duplas, simples e barras" {
  # `%test` volta a ser `@test`: o pre-processador do Bats reescreve linhas `@test` ate dentro de heredoc.
  sed 's/^%test /@test /' > "$RAIZ/spec/nomes.bats" <<'EOF'
%test "pedido \"urgente\" com \\ no fim \\" {
  true
}
%test 'cupom DEZ com \\ duplo' {
  true
}
%test "frete 'gratis' acima de 100" {
  true
}
EOF
  versiona
  roda --listar
  [ "$status" -eq 0 ]
  descobertos="$(printf '%s\n' "$output" | cut -f 2 | sort)"
  bats_bin="${BATS_ROOT:-}/bin/bats"
  [ -x "$bats_bin" ]
  impressos="$("$bats_bin" --tap "$RAIZ/spec/nomes.bats" | sed -n 's/^ok [0-9]* //p' | sort)"
  [ "$(printf '%s\n' "$descobertos" | wc -l)" -eq 3 ]
  [ "$descobertos" = "$impressos" ]
}

@test "crase que abre antes de aspas manda no nome; aspas que abrem antes de crase tambem" {
  printf 'it(`total "bruto" e %s`, () => {});\n' "'liquido'" > "$RAIZ/spec/a.test.js"
  printf 'it("desconto `fixo` aplicado", () => {});\n' >> "$RAIZ/spec/a.test.js"
  versiona
  printf '*.test.js\t^[[:space:]]*it\\(\n' > "$RAIZ/pad.txt"
  roda --listar --padroes pad.txt
  [ "$status" -eq 0 ]
  esperado="$(printf '%s\t%s\n%s\t%s' spec/a.test.js 'desconto `fixo` aplicado' spec/a.test.js "total \"bruto\" e 'liquido'")"
  [ "$output" = "$esperado" ]
}

@test "barra dupla seguida do delimitador fecha a string; barra tripla antes da aspa a escapa" {
  printf '%s\n' "it('rota C:\\\\', () => {}); // 'resto'" "it(\"lote \\\\\\\"A\\\" ok\", () => {});" > "$RAIZ/spec/b.test.js"
  versiona
  printf '*.test.js\t^[[:space:]]*it\\(\n' > "$RAIZ/pad.txt"
  roda --listar --padroes pad.txt
  [ "$status" -eq 0 ]
  esperado="$(printf '%s\t%s\n%s\t%s' spec/b.test.js 'lote \"A" ok' spec/b.test.js 'rota C:\')"
  [ "$output" = "$esperado" ]
}

# ---------- #65: exclusoes ----------

@test "!glob que exclui tudo: nenhum caso descoberto e o bloco e linha do inventario viram ARQUIVO e SOBRA com exit 1" {
  printf '@test "aprova pedido" {\n  true\n}\n' > "$RAIZ/spec/p.bats"; versiona
  { bloco spec/p.bats; printf '| Caso | O que verifica | Regra especifica |\n|---|---|---|\n| aprova pedido | aprova o pedido valido | |\n'; } > "$INV"
  printf '*.bats\t^@test \n!*\n' > "$RAIZ/pad.txt"
  roda --check --padroes pad.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"SOBRA spec/p.bats :: aprova pedido"* ]]
  [[ "$output" == *"ARQUIVO spec/p.bats"* ]]
  [[ "$output" == *"| casos: 0 | divergencias: 2"* ]]
  roda --listar --padroes pad.txt
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "!glob com espaco no caminho e espacos finais exclui; a mesma linha comentada nao exclui" {
  mkdir -p "$RAIZ/spec/dados de apoio"
  printf '@test "massa de apoio" {\n  true\n}\n' > "$RAIZ/spec/dados de apoio/m.bats"
  printf '@test "caso real" {\n  true\n}\n' > "$RAIZ/spec/r.bats"
  versiona
  printf '*.bats\t^@test \n!spec/dados de apoio/*   \n' > "$RAIZ/pad.txt"
  roda --listar --padroes pad.txt
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'spec/r.bats\tcaso real')" ]
  printf '*.bats\t^@test \n#!spec/dados de apoio/*\n' > "$RAIZ/pad.txt"
  roda --listar --padroes pad.txt
  [[ "$output" == *"massa de apoio"* ]]
  [[ "$output" == *"caso real"* ]]
}

# ---------- #66: NAO-DESCOBERTO ----------

@test "arquivo casado por dois padroes gera um aviso por linha, fora da contagem de divergencias e do --faltantes" {
  printf 'test(nomeCalculado, () => {});\n\tit.each ([3, 4])("parcela %%s", () => {});\n' > "$RAIZ/spec/c.test.js"
  versiona
  : > "$INV"
  printf '*.test.js\t^[[:space:]]*test\\(\nspec/*\t^[[:space:]]*test\\(\n' > "$RAIZ/pad.txt"
  roda --check --padroes pad.txt
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'NAO-DESCOBERTO spec/c.test.js :: linha 1$')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'NAO-DESCOBERTO spec/c.test.js :: linha 2$')" -eq 1 ]
  [[ "${lines[${#lines[@]}-1]}" == *"| casos: 0 | divergencias: 0 | nao descobertos: 2" ]]
  roda --faltantes --padroes pad.txt
  [ "$status" -eq 0 ]
  [[ "$output" != *"NAO-DESCOBERTO"* ]]
}

# ---------- #67 item 4: Condicao de execucao ----------

@test "condicao sem lado esquerdo ou sem espacos na seta gera CONDICAO; nao preencher e incondicional" {
  printf '@test "a" {\n  true\n}\n@test "b" {\n  true\n}\n@test "c" {\n  true\n}\n@test "d" {\n  true\n}\n' > "$RAIZ/spec/k.bats"; versiona
  { bloco spec/k.bats
    printf '| Caso | O que verifica | Regra especifica | Condicao de execucao |\n|---|---|---|---|\n'
    printf '| a | caso a | | -> job noturno |\n| b | caso b | | docker->job e2e |\n| c | caso c | | |\n| d | caso d | | docker disponivel -> job integracao |\n'
  } > "$INV"
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONDICAO spec/k.bats :: a"* ]]
  [[ "$output" == *"CONDICAO spec/k.bats :: b"* ]]
  [[ "$output" != *"CONDICAO spec/k.bats :: c"* ]]
  [[ "$output" != *"CONDICAO spec/k.bats :: d"* ]]
  [[ "$output" == *"divergencias: 2"* ]]
}

@test "tabela de 4 colunas com pipe escapado no caso e na condicao casa e nao gera CONDICAO" {
  printf '@test "aceita a | b" {\n  true\n}\n' > "$RAIZ/spec/e.bats"; versiona
  { bloco spec/e.bats
    printf '| Caso | O que verifica | Regra especifica | Condicao de execucao |\n|---|---|---|---|\n'
    printf '%s\n' '| aceita a \| b | separa por \| e soma | | rede \| dns externos -> job e2e-rede |'
  } > "$INV"
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"casos: 1 | divergencias: 0"* ]]
}

@test "coluna achada pelo cabecalho acentuado em outra posicao; segunda tabela do bloco sem a coluna e incondicional" {
  printf '@test "x1" {\n  true\n}\n@test "x2" {\n  true\n}\n' > "$RAIZ/spec/f.bats"; versiona
  { bloco spec/f.bats
    printf '| Caso | Condição de execução | O que verifica | Regra especifica |\n|---|---|---|---|\n'
    printf '| x1 | sem seta | verifica x1 | |\n\n'
    printf '| Caso | O que verifica | Regra especifica |\n|---|---|---|\n'
    printf '| x2 | verifica x2 | | sem seta |\n'
  } > "$INV"
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONDICAO spec/f.bats :: x1"* ]]
  [[ "$output" != *"CONDICAO spec/f.bats :: x2"* ]]
  [[ "$output" == *"divergencias: 1"* ]]
}
