#!/usr/bin/env bats
# Testes de scripts/inventario-de-testes.sh: conferencia do inventario de testes contra os testes versionados.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../inventario-de-testes.sh"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  RAIZ="$BATS_TEST_TMPDIR/repo"
  INV="$RAIZ/docs/testes/inventario-de-testes.md"
  git init -q -b main "$RAIZ"
  mkdir -p "$RAIZ/tests" "$RAIZ/docs/testes"
  printf '#!/usr/bin/env bats\n@test "soma dois numeros" {\n  true\n}\n@test "subtrai dois numeros" {\n  true\n}\n' > "$RAIZ/tests/calc.bats"
  git -C "$RAIZ" add -A
  git -C "$RAIZ" commit -qm base
}

# Cabecalho de bloco completo para $1 (caminho do teste); o chamador acrescenta as linhas da tabela.
bloco() {
  printf '## `%s`\n\n- **Alvo:** `calc.sh`\n- **Modulo:** core\n- **Camada:** unitario\n- **Autoria:** Senior Developer (TDD da demanda `x`)\n- **Regras de origem:** AGENTS.md 51\n- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer\n- **Comando:** `bats %s`\n\n| Caso | O que verifica | Regra especifica |\n|---|---|---|\n' "$1" "$1"
}

inventario_completo() {
  {
    printf '# Inventario de testes - p\n\n## Como ler\n\ntexto\n\n## Resumo\n\n| Arquivo | Alvo |\n|---|---|\n| `tests/calc.bats` | x |\n\n'
    bloco tests/calc.bats
    printf '| soma dois numeros | soma 1 e 2 e retorna 3 | |\n| subtrai dois numeros | subtrai 3 de 5 e retorna 2 | |\n'
  } > "$INV"
}

# Reescreve o inventario com sed (argumentos do sed).
edita() {
  sed "$@" "$INV" > "$RAIZ/x.tmp"
  mv "$RAIZ/x.tmp" "$INV"
}

roda() {
  run sh -c "cd '$RAIZ' && sh '$SCRIPT' $*"
}

@test "inventario completo sai 0 e resume" {
  inventario_completo
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"arquivos: 1 | casos: 2 | divergencias: 0"* ]]
}

@test "teste sem linha gera FALTA" {
  inventario_completo
  printf '@test "multiplica" {\n  true\n}\n' >> "$RAIZ/tests/calc.bats"
  git -C "$RAIZ" add -A
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"FALTA tests/calc.bats :: multiplica"* ]]
  [[ "$output" == *"divergencias: 1"* ]]
}

@test "campo ausente gera CAMPO" {
  inventario_completo
  edita '/Regras de origem/d'
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"CAMPO tests/calc.bats :: Regras de origem"* ]]
}

@test "campo com placeholder gera CAMPO" {
  inventario_completo
  edita 's/^- \*\*Modulo:\*\* core/- **Modulo:** <modulo>/'
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"CAMPO tests/calc.bats :: Modulo"* ]]
}

@test "campo vazio gera CAMPO" {
  inventario_completo
  edita 's/^- \*\*Alvo:\*\* .*/- **Alvo:**/'
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"CAMPO tests/calc.bats :: Alvo"* ]]
}

@test "Nao aplicavel com motivo conta como preenchido" {
  inventario_completo
  edita 's/^- \*\*Comando:\*\* .*/- **Comando:** Nao aplicavel: roda pela suite/'
  roda
  [ "$status" -eq 0 ]
}

@test "Nao aplicavel com motivo placeholder gera CAMPO" {
  inventario_completo
  edita 's/^- \*\*Comando:\*\* .*/- **Comando:** Nao aplicavel: <motivo>/'
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"CAMPO tests/calc.bats :: Comando"* ]]
}

@test "autoria do QA exige Aceite do solicitante" {
  inventario_completo
  edita -e 's/^- \*\*Autoria:\*\* .*/- **Autoria:** QA Expert (suite independente)/' -e '/Aceite do solicitante/d'
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"CAMPO tests/calc.bats :: Aceite do solicitante"* ]]
}

@test "autoria do Senior Developer dispensa Aceite do solicitante" {
  inventario_completo
  edita '/Aceite do solicitante/d'
  roda
  [ "$status" -eq 0 ]
}

@test "coluna O que verifica vazia ou placeholder gera VAZIO" {
  inventario_completo
  edita -e 's/^| soma dois numeros | .*/| soma dois numeros |  | |/' -e 's/^| subtrai dois numeros | .*/| subtrai dois numeros | <condicao, acao e resultado> | |/'
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"VAZIO tests/calc.bats :: soma dois numeros"* ]]
  [[ "$output" == *"VAZIO tests/calc.bats :: subtrai dois numeros"* ]]
}

@test "linha repetida gera DUPLICADO" {
  inventario_completo
  printf '| soma dois numeros | de novo | |\n' >> "$INV"
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"DUPLICADO tests/calc.bats :: soma dois numeros"* ]]
}

@test "arquivo nao versionado e ignorado" {
  inventario_completo
  printf '@test "solto" {\n  true\n}\n' > "$RAIZ/tests/solto.bats"
  roda
  [ "$status" -eq 0 ]
  [[ "$output" != *"solto"* ]]
}

@test "opcao invalida sai 2" {
  inventario_completo
  roda --nada
  [ "$status" -eq 2 ]
}

@test "--inventario aponta para outro arquivo" {
  inventario_completo
  mv "$INV" "$RAIZ/outro.md"
  roda --inventario outro.md
  [ "$status" -eq 0 ]
}

@test "padroes customizados descobrem outros frameworks e nome por aspas simples ou def" {
  printf "describe('x', () => {\n  it('faz algo', () => {});\n  test(\"faz outra\", () => {});\n});\n" > "$RAIZ/a.test.js"
  printf 'def test_unico():\n    pass\n' > "$RAIZ/test_a.py"
  git -C "$RAIZ" add -A
  printf '# comentario\n*.test.js\t^[[:space:]]*(it|test)\\(\n\ntest_*.py\t^def test_\n' > "$RAIZ/padroes.txt"
  roda --listar --padroes padroes.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.test.js"*"faz algo"* ]]
  [[ "$output" == *"a.test.js"*"faz outra"* ]]
  [[ "$output" == *"test_a.py"*"test_unico"* ]]
  [[ "$output" != *"calc.bats"* ]]
}

@test "--listar imprime arquivo TAB caso ordenado" {
  roda --listar
  [ "$status" -eq 0 ]
  esperado="$(printf 'tests/calc.bats\tsoma dois numeros\ntests/calc.bats\tsubtrai dois numeros')"
  [ "$output" = "$esperado" ]
}

@test "--faltantes imprime esqueleto de bloco para arquivo sem bloco e exit 0" {
  roda --faltantes
  [ "$status" -eq 0 ]
  [[ "$output" == *'## `tests/calc.bats`'* ]]
  [[ "$output" == *"- **Alvo:** <"* ]]
  [[ "$output" == *"| Caso | O que verifica | Regra especifica |"* ]]
  [[ "$output" == *"| soma dois numeros | <"* ]]
  [[ "$output" == *"| subtrai dois numeros | <"* ]]
}

@test "--faltantes lista so as linhas que faltam quando o bloco existe" {
  inventario_completo
  printf '@test "multiplica" {\n  true\n}\n' >> "$RAIZ/tests/calc.bats"
  git -C "$RAIZ" add -A
  roda --faltantes
  [ "$status" -eq 0 ]
  [[ "$output" == *"| multiplica | <"* ]]
  [[ "$output" != *"soma dois numeros"* ]]
  [[ "$output" != *"- **Alvo:**"* ]]
}

# Issue #64: nome do caso pelo delimitador que abre primeiro na linha.
@test "titulo entre aspas simples com aspas duplas internas forma o nome inteiro" {
  printf "it('mostra \"15\" no total', () => {});\n" > "$RAIZ/a.test.js"
  git -C "$RAIZ" add -A
  printf '*.test.js\t^[[:space:]]*(it|test)\\(\n' > "$RAIZ/padroes.txt"
  roda --listar --padroes padroes.txt
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'a.test.js\tmostra "15" no total')" ]
}

# Issue #65: linha !<glob> no arquivo de padroes exclui caminhos da descoberta.
@test "!glob que exclui tudo: o resumo traz arquivos 0 e casos 0" {
  printf '# Inventario de testes - p\n\n## Resumo\n\nNenhum teste.\n' > "$INV"
  printf '*.bats\t^@test \n!*\n' > "$RAIZ/padroes.txt"
  roda --check --padroes padroes.txt
  [ "$status" -eq 0 ]
  [ "$output" = "arquivos: 0 | casos: 0 | divergencias: 0" ]
}

@test "linha !glob antes dos padroes vale para todos eles" {
  mkdir -p "$RAIZ/tests/fixtures"
  printf '@test "fixture" {\n  true\n}\n' > "$RAIZ/tests/fixtures/f.bats"
  printf "it('fixture js', () => {});\n" > "$RAIZ/tests/fixtures/f.test.js"
  printf "it('caso js', () => {});\n" > "$RAIZ/tests/a.test.js"
  git -C "$RAIZ" add -A
  printf '!tests/fixtures/*\n*.bats\t^@test \n*.test.js\t^[[:space:]]*it\\(\n' > "$RAIZ/padroes.txt"
  roda --listar --padroes padroes.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests/a.test.js"*"caso js"* ]]
  [[ "$output" == *"tests/calc.bats"* ]]
  [[ "$output" != *"fixture"* ]]
}

# Issue #66: aviso NAO-DESCOBERTO no --check.
@test "declaracoes it.each test.each e describe.each geram NAO-DESCOBERTO mesmo sem a ERE casar" {
  inventario_completo
  printf "describe.each([1])('grupo %%s', (n) => {\n  it.each([\n    [1],\n  ])('caso %%s', () => {});\n  test.each([2])('outro %%s', () => {});\n});\n" > "$RAIZ/a.test.js"
  git -C "$RAIZ" add -A
  printf '*.bats\t^@test \n*.test.js\t^[[:space:]]*(it|test)\\(\n' > "$RAIZ/padroes.txt"
  roda --check --padroes padroes.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"NAO-DESCOBERTO a.test.js :: linha 1"* ]]
  [[ "$output" == *"NAO-DESCOBERTO a.test.js :: linha 2"* ]]
  [[ "$output" == *"NAO-DESCOBERTO a.test.js :: linha 5"* ]]
  [[ "$output" == *"divergencias: 0 | nao descobertos: 3"* ]]
}

@test "it.each casado pela ERE do projeto com nome na linha tambem gera NAO-DESCOBERTO" {
  inventario_completo
  printf "it.each([1, 2])('soma %%s', (n) => {});\n" > "$RAIZ/a.test.js"
  git -C "$RAIZ" add -A
  printf '*.bats\t^@test \n*.test.js\t^[[:space:]]*it[.(]\n' > "$RAIZ/padroes.txt"
  roda --check --padroes padroes.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"FALTA a.test.js :: soma %s"* ]]
  [[ "$output" == *"NAO-DESCOBERTO a.test.js :: linha 1"* ]]
  [[ "$output" == *"divergencias: 1 | nao descobertos: 1"* ]]
}

@test "resumo sem nao descobertos nao ganha o sufixo" {
  inventario_completo
  roda --check
  [ "$status" -eq 0 ]
  [[ "$output" != *"nao descobertos"* ]]
}

# Issue #67 item 4: coluna Condicao de execucao (identificada pelo cabecalho da tabela).
cabecalho_com_condicao() {
  edita -e 's/^| Caso | O que verifica | Regra especifica |$/| Caso | O que verifica | Regra especifica | Condicao de execucao |/' -e 's/^|---|---|---|$/|---|---|---|---|/'
}

@test "condicao de execucao sem seta gera CONDICAO e a valida passa" {
  inventario_completo
  cabecalho_com_condicao
  edita -e 's/^| soma dois numeros | .*/| soma dois numeros | soma 1 e 2 | | rede externa -> job e2e-rede da pipeline |/' \
        -e 's/^| subtrai dois numeros | .*/| subtrai dois numeros | subtrai 3 de 5 | | rede externa |/'
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONDICAO tests/calc.bats :: subtrai dois numeros"* ]]
  [[ "$output" != *"CONDICAO tests/calc.bats :: soma dois numeros"* ]]
  [[ "$output" == *"divergencias: 1"* ]]
}

@test "condicao de execucao com o lado direito vazio gera CONDICAO" {
  inventario_completo
  cabecalho_com_condicao
  edita 's/^| soma dois numeros | .*/| soma dois numeros | soma 1 e 2 | | root ->   |/'
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONDICAO tests/calc.bats :: soma dois numeros"* ]]
}

@test "--faltantes imprime a coluna Condicao de execucao no cabecalho da tabela" {
  roda --faltantes
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Caso | O que verifica | Regra especifica | Condicao de execucao |"* ]]
  [[ "$output" == *"|---|---|---|---|"* ]]
}
