#!/usr/bin/env bats
# Suite independente do QA para scripts/inventario-de-testes.sh (regra 51 do AGENTS.md).
# Cobre o que a suite do autor nao prende: crase e acentos no nome do caso, caracteres de regex no nome, dois blocos
# para o mesmo arquivo, tabela com espacos extras ou sem a coluna Regra especifica, caminho com espaco, teste removido,
# arquivo renomeado, @test com aspas simples, glob em subdiretorio, bloco de exemplo do template sem troca, `<`/`>`
# soltos em texto, CRLF, secoes depois do ultimo bloco, execucao a partir de subdiretorio, somente leitura e exit code.
# Nota (regra 12): este arquivo NAO e versionado antes do aceite do solicitante. Cada teste monta um repositorio
# descartavel em $BATS_TEST_TMPDIR.

setup() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  export SCRIPT="$BATS_TEST_DIRNAME/../inventario-de-testes.sh"
  RAIZ="$BATS_TEST_TMPDIR/repo"
  INV="$RAIZ/docs/testes/inventario-de-testes.md"
  git init -q -b main "$RAIZ"
  mkdir -p "$RAIZ/tests" "$RAIZ/docs/testes"
}

commita() { git -C "$RAIZ" add -A; git -C "$RAIZ" commit -qm c; }

# Bloco completo para o arquivo $1 (sem tabela de casos).
cab() {
  printf '## `%s`\n\n- **Alvo:** `x.sh`\n- **Modulo:** core\n- **Camada:** integracao\n- **Autoria:** Senior Developer (TDD da demanda `x`)\n- **Regras de origem:** AGENTS.md 51\n- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer\n- **Comando:** `bats %s`\n\n' "$1" "$1"
}
tab_cab() { printf '| Caso | O que verifica | Regra especifica |\n|---|---|---|\n'; }

# roda [args...]: executa o script a partir de $DIR (padrao: a raiz do repositorio).
roda() { run sh -c 'cd "${DIR:-$1}" && shift && sh "$SCRIPT" "$@"' _ "$RAIZ" "$@"; }

@test "nome do caso com crase casa com a linha que traz as crases" {
  printf '@test "usa `git status` no caso" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '%s\n' '| usa `git status` no caso | roda git status e le a saida | |'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"arquivos: 1 | casos: 1 | divergencias: 0"* ]]
}

@test "nome do caso com acentos e cedilha casa" {
  printf '@test "não calcula conversão é ação" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '| não calcula conversão é ação | recusa a conversão e sai 1 | |\n'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
}

@test "nome com caracteres de regex e de substituicao casa literalmente" {
  printf '@test "50%% (a.b)* [x] & y+z" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '| 50%% (a.b)* [x] & y+z | trata o nome como texto literal | |\n'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"casos: 1 | divergencias: 0"* ]]
}

@test "dois blocos para o mesmo arquivo com o mesmo caso geram DUPLICADO" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '| a | primeira linha | |\n\n'; cab tests/a.bats; tab_cab; printf '| a | segunda linha | |\n'; } > "$INV"
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"DUPLICADO tests/a.bats :: a"* ]]
}

@test "tabela com espacos extras nas celulas casa" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '|    a    |     comportamento descrito   |   |\n'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
}

@test "tabela sem a coluna Regra especifica casa" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; printf '| Caso | O que verifica |\n|---|---|\n| a | comportamento descrito |\n'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
}

@test "caminho de teste com espaco e descoberto, conferido e listado" {
  mkdir -p "$RAIZ/tests/pasta com espaco"
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/pasta com espaco/meu teste.bats"; commita
  { cab "tests/pasta com espaco/meu teste.bats"; tab_cab; printf '| a | comportamento descrito | |\n'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
  roda --listar
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests/pasta com espaco/meu teste.bats"* ]]
}

@test "teste removido do arquivo gera SOBRA e exit 1" {
  printf '@test "a" {\n  true\n}\n@test "b" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '| a | descrito | |\n| b | descrito | |\n'; } > "$INV"
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"SOBRA tests/a.bats :: b"* ]]
  [[ "$output" == *"divergencias: 1"* ]]
}

@test "arquivo de teste renomeado gera FALTA no novo e ARQUIVO no antigo" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '| a | descrito | |\n'; } > "$INV"
  git -C "$RAIZ" mv tests/a.bats tests/novo.bats; commita
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"FALTA tests/novo.bats :: a"* ]]
  [[ "$output" == *"ARQUIVO tests/a.bats"* ]]
}

@test "@test com aspas simples forma o nome do caso" {
  printf "@test 'caso entre aspas simples' {\n  true\n}\n" > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '| caso entre aspas simples | descrito | |\n'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
}

@test "glob com subdiretorio descobre so o que casa" {
  mkdir -p "$RAIZ/src/mod/specs" "$RAIZ/src/outro"
  printf 'it("caso x", () => {})\n' > "$RAIZ/src/mod/specs/a.spec.js"
  printf 'it("fora", () => {})\n' > "$RAIZ/src/outro/b.js"
  commita
  printf 'src/*/specs/*.spec.js\t^[[:space:]]*it\\(\n' > "$RAIZ/pad.txt"
  roda --padroes pad.txt --listar
  [ "$status" -eq 0 ]
  [[ "$output" == *"src/mod/specs/a.spec.js"*"caso x"* ]]
  [[ "$output" != *"fora"* ]]
}

@test "padrao que nao casa nada deixa as linhas como SOBRA e nao como sucesso" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '| a | descrito | |\n'; } > "$INV"
  printf 'nada/*.xyz\t^@test \n' > "$RAIZ/pad.txt"
  roda --padroes pad.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"SOBRA tests/a.bats :: a"* ]]
}

@test "faltantes colado no inventario nao passa ate ser preenchido" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  roda --faltantes
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$INV"
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"CAMPO tests/a.bats :: Alvo"* ]]
  [[ "$output" == *"VAZIO tests/a.bats :: a"* ]]
}

@test "sinais de menor e maior soltos em O que verifica nao sao placeholder" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '| a | com x < 3 e y > 2 devolve 0 | |\n'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
}

@test "placeholder entre crases em O que verifica e aceito" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '%s\n' '| a | emite `<html>` quando vazio | |'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
}

@test "Nao aplicavel acentuado com motivo e aceito e sem motivo gera CAMPO" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats | sed 's/Nao aplicavel: teste do Senior Developer/Não aplicável: teste do Senior Developer/'; tab_cab; printf '| a | descrito | |\n'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
  { cab tests/a.bats | sed 's/AGENTS.md 51/Não aplicável:/'; tab_cab; printf '| a | descrito | |\n'; } > "$INV"
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"CAMPO tests/a.bats :: Regras de origem"* ]]
}

@test "autoria QA aceita Aceite pendente no lote da demanda" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats | sed 's/Senior Developer (TDD da demanda `x`)/QA Expert (suite independente da demanda `x`)/; s/Nao aplicavel: teste do Senior Developer/pendente no lote da demanda/'; tab_cab; printf '| a | descrito | |\n'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
}

@test "secao com tabela depois do ultimo bloco nao conta como casos" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '| a | descrito | |\n\n## Glossario\n\n| Termo | Significado |\n|---|---|\n| lixo | nao e caso |\n'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"divergencias: 0"* ]]
}

@test "inventario com fim de linha CRLF e conferido como o LF" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '| a | descrito | |\n'; } | sed 's/$/\r/' > "$INV"
  roda
  [ "$status" -eq 0 ]
}

@test "executado de um subdiretorio do repositorio confere a raiz" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; printf '| a | descrito | |\n'; } > "$INV"
  DIR="$RAIZ/tests" roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"arquivos: 1 | casos: 1 | divergencias: 0"* ]]
  DIR="$RAIZ/tests" roda --inventario docs/testes/inventario-de-testes.md
  [ "$status" -eq 0 ]
}

@test "fora de repositorio git sai 2" {
  mkdir -p "$BATS_TEST_TMPDIR/solto"
  DIR="$BATS_TEST_TMPDIR/solto" roda
  [ "$status" -eq 2 ]
}

@test "o exit code nao e mascarado: 1 por divergencia, 2 por uso, 0 so sem divergencia" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  roda
  [ "$status" -eq 2 ]
  { cab tests/a.bats; tab_cab; } > "$INV"
  roda
  [ "$status" -eq 1 ]
  roda --padroes inexistente.txt
  [ "$status" -eq 2 ]
  roda --inventario
  [ "$status" -eq 2 ]
  { cab tests/a.bats; tab_cab; printf '| a | descrito | |\n'; } > "$INV"
  roda
  [ "$status" -eq 0 ]
}

@test "o script so le: nao altera a arvore versionada" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  { cab tests/a.bats; tab_cab; } > "$INV"
  commita
  roda
  roda --faltantes
  roda --listar
  [ -z "$(git -C "$RAIZ" status --porcelain)" ]
}

@test "listar e faltantes nao exigem inventario e saem 0" {
  printf '@test "a" {\n  true\n}\n' > "$RAIZ/tests/a.bats"; commita
  rm -rf "$RAIZ/docs"
  roda --listar
  [ "$status" -eq 0 ]
  roda --faltantes
  [ "$status" -eq 0 ]
  [[ "$output" == *'## `tests/a.bats`'* ]]
}

@test "o resumo conta arquivos e casos descobertos mesmo com inventario vazio" {
  printf '@test "a" {\n  true\n}\n@test "b" {\n  true\n}\n' > "$RAIZ/tests/a.bats"
  printf '@test "c" {\n  true\n}\n' > "$RAIZ/tests/b.bats"; commita
  : > "$INV"
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"arquivos: 2 | casos: 3 | divergencias: 3"* ]]
}
