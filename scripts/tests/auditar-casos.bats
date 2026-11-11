#!/usr/bin/env bats
# Testes de scripts/auditar-casos.sh: auditoria estatica de casos de teste inertes (issue #67, item 2).
# Cada caso monta um repositorio git descartavel com arquivos de teste sinteticos por adaptador.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../auditar-casos.sh"
  RAIZ="$BATS_TEST_TMPDIR/repo"
  git init -q -b main "$RAIZ"
  mkdir -p "$RAIZ/scripts"
  printf '*.bats\tbats\ntests/*_test.sh\tshell\n*.test.js\tjest\n' > "$RAIZ/scripts/auditar-casos.txt"
  git -C "$RAIZ" add -A
}

# Escreve o stdin em $RAIZ/$1 e o coloca no indice (a descoberta usa git ls-files). Nos arquivos sinteticos a
# declaracao de caso e escrita `%test`, porque o pre-processador do Bats reescreve linhas `@test` ate dentro de
# heredoc; aqui ela volta a ser `@test`.
arquivo() {
  mkdir -p "$(dirname "$RAIZ/$1")"
  sed 's/^\([[:space:]]*\)%test /\1@test /' > "$RAIZ/$1"
  git -C "$RAIZ" add -A
}

roda() {
  run sh -c "cd '$RAIZ' && sh '$SCRIPT' $*"
}

# ---------- bats ----------

@test "bats: skip incondicional na primeira instrucao e BLOQUEANTE SKIP" {
  arquivo tests/a.bats <<'EOF'
%test "nunca roda" {
  # comentario antes
  skip "depois"
  [ 1 -eq "$x" ]
}
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SKIP tests/a.bats :: nunca roda :: linha 3"* ]]
  [[ "$output" != *"SEM-ASSERCAO"* ]]
  [[ "$output" == *"arquivos: 1 | casos: 1 | bloqueantes: 1 | maiores: 0 | avisos: 0"* ]]
}

@test "bats: skip condicional nao e achado" {
  arquivo tests/a.bats <<'EOF'
%test "condicional na linha" {
  [ -z "$REDE" ] && skip "sem rede"
  run true
}
%test "condicional em bloco" {
  if [ -z "$REDE" ]; then
    skip "sem rede"
  fi
  run true
}
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"arquivos: 1 | casos: 2 | bloqueantes: 0 | maiores: 0 | avisos: 0"* ]]
}

@test "bats: return incondicional na primeira instrucao e BLOQUEANTE SKIP" {
  arquivo tests/a.bats <<'EOF'
%test "sai cedo" {
  return 0
  run true
}
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SKIP tests/a.bats :: sai cedo :: linha 2"* ]]
}

@test "bats: corpo so com true ou vazio e BLOQUEANTE SEM-ASSERCAO" {
  arquivo tests/a.bats <<'EOF'
%test "so true" {
  true
}

%test "vazio" {
}
%test "com assercao" {
  run echo x
  [ "$output" = x ]
}
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/a.bats :: so true :: linha 1"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/a.bats :: vazio :: linha 5"* ]]
  [[ "$output" != *":: com assercao ::"* ]]
  [[ "$output" == *"casos: 3 | bloqueantes: 2"* ]]
}

@test "bats: assercao transitiva por funcao do proprio arquivo libera; funcao sem assercao nao" {
  arquivo tests/a.bats <<'EOF'
confere() {
  [ -f "$1" ]
}
prepara() {
  touch "$1"
}
%test "usa helper com assercao" {
  confere x
}
%test "usa helper sem assercao" {
  prepara x
}
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" != *":: usa helper com assercao ::"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/a.bats :: usa helper sem assercao :: linha 10"* ]]
}

@test "bats: assercao transitiva por funcao de arquivo carregado com load" {
  arquivo tests/apoio.bash <<'EOF'
verifica_saida() {
  [[ "$output" == *ok* ]]
}
EOF
  arquivo tests/a.bats <<'EOF'
load apoio
%test "helper carregado" {
  verifica_saida
}
EOF
  roda
  [ "$status" -eq 0 ]
}

@test "bats: @test dentro de heredoc nao e caso" {
  arquivo tests/a.bats <<'EOF'
%test "gera arquivo de teste" {
  cat > x.bats <<'FIM'
%test "interno" {
  true
}
FIM
  [ -f x.bats ]
}
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"casos: 1 |"* ]]
}

@test "bats: assercao literal contra literal e MAIOR LITERAL; literal contra variavel nao" {
  arquivo tests/a.bats <<'EOF'
%test "literais" {
  [ 1 -eq 1 ]
  [ "a" = "a" ]
  [[ 1 == 1 ]]
  assert_equal "x" "x"
}
%test "variavel" {
  run true
  [ "$status" -eq 0 ]
  [[ "$output" == "a" ]]
  assert_equal "$x" "x"
}
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"MAIOR LITERAL tests/a.bats :: literais :: linha 2"* ]]
  [[ "$output" == *"MAIOR LITERAL tests/a.bats :: literais :: linha 3"* ]]
  [[ "$output" == *"MAIOR LITERAL tests/a.bats :: literais :: linha 4"* ]]
  [[ "$output" == *"MAIOR LITERAL tests/a.bats :: literais :: linha 5"* ]]
  [[ "$output" != *":: variavel ::"* ]]
  [[ "$output" == *"bloqueantes: 0 | maiores: 4 | avisos: 0"* ]]
}

@test "bats: ausencia de caminho que o teste nao cria e AVISO e nao muda o exit" {
  arquivo tests/a.bats <<'EOF'
%test "nunca criado" {
  run true
  [ ! -e "$RAIZ/fantasma.lock" ]
}
%test "criado pelo teste" {
  touch "$RAIZ/real.lock"
  rm "$RAIZ/real.lock"
  [ ! -f "$RAIZ/real.lock" ]
}
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"AVISO AUSENCIA tests/a.bats :: nunca criado :: linha 3"* ]]
  [[ "$output" != *":: criado pelo teste ::"* ]]
  [[ "$output" == *"avisos: 1"* ]]
}

@test "bats: ausencia de caminho citado por arquivo do produto nao e aviso; citado so por outro teste e" {
  # shellcheck disable=SC2016  # o script sintetico e literal; $1 e $marca expandem quando ele roda
  printf '#!/bin/sh\ntouch "$1/saida.lock"\nmarca=registro-local\ntouch "$1/$marca.trava"\n' > "$RAIZ/scripts/produto.sh"
  arquivo tests/outro.bats <<'EOF'
%test "cita o nome" {
  [ -n "so-teste.lock" ]
}
EOF
  arquivo tests/a.bats <<'EOF'
%test "o produto cria" {
  run sh produto.sh "$D"
  [ ! -e "$D/saida.lock" ]
}
%test "so outro teste cita" {
  run true
  [ ! -e "$D/so-teste.lock" ]
}
%test "o produto compoe o nome" {
  run sh produto.sh "$D"
  [ ! -e "$D/registro-local.trava" ]
}
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" != *":: o produto cria ::"* ]]
  [[ "$output" != *":: o produto compoe o nome ::"* ]]
  [[ "$output" == *"AVISO AUSENCIA tests/a.bats :: so outro teste cita :: linha 7"* ]]
  [[ "$output" == *"avisos: 1"* ]]
}

@test "bats: aspa escapada em string ANSI-C nao desalinha a leitura dos casos seguintes" {
  arquivo tests/a.bats <<'EOF'
%test "ansi-c" {
  for c in $'cat <<\'FIM\'\nx\nFIM' 'b'; do
    run echo "$c"
  done
}
%test "depois" {
  true
}
EOF
  roda --listar
  [ "${#lines[@]}" -eq 2 ]
  roda
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/a.bats :: depois :: linha 6"* ]]
}

@test "bats: aspas dentro de substituicao de comando entre aspas duplas nao desalinham os casos seguintes" {
  arquivo tests/a.bats <<'EOF'
%test "subst com aspa simples" {
  run printf '%s\n' "$(printf '%s %s' 'lote \"A" ok' 'rota C:\')"
  [ "$status" -eq 0 ]
}
%test "subst com aspas duplas" {
  x="$(printf '%s' "$y" | tr 'a' "b")" n="$((1 + 2))"
  [ -n "$x$n" ]
}
%test "subst em varias linhas" {
  v="$(
    printf '%s' 'a\'
  )"
}
%test "depois" {
  true
}
%test "literal no fim" {
  [ 1 -eq 1 ]
}
EOF
  roda --listar
  [ "${#lines[@]}" -eq 5 ]
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/a.bats :: subst em varias linhas :: linha 9"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/a.bats :: depois :: linha 14"* ]]
  [[ "$output" == *"MAIOR LITERAL tests/a.bats :: literal no fim :: linha 18"* ]]
  [[ "$output" == *"arquivos: 1 | casos: 5 | bloqueantes: 2 | maiores: 1 | avisos: 0"* ]]
}

@test "bats: interpretador com assercao inline (python3 -c assert, jq -e) e assercao" {
  arquivo tests/a.bats <<'EOF'
%test "python" {
  python3 -c 'import sys; assert len(sys.argv) == 2' x
}
%test "jq" {
  printf '{}' | jq -e '.a == null'
}
%test "python sem assert" {
  python3 -c 'print(1)'
}
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" != *":: python ::"* ]]
  [[ "$output" != *":: jq ::"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/a.bats :: python sem assert :: linha 7"* ]]
}

# ---------- harness shell ----------

@test "shell: pular incondicional, literal, assercao propria e ausencia" {
  arquivo tests/perfis_test.sh <<'EOF'
teste_pulado() {
  pular "depois"
  assert_igual "$a" 1
}
teste_pular_condicional() {
  [ -n "$ROOT" ] || pular "sem root"
  afirmar_saida ok
}
teste_literal() {
  assert_igual 0 0
}
teste_ausencia() {
  esperar_codigo 0
  assert_arquivo_ausente "$base/argv.nao"
}
teste_sem_nada() {
  echo oi
}
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SKIP tests/perfis_test.sh :: teste_pulado :: linha 2"* ]]
  [[ "$output" == *"MAIOR LITERAL tests/perfis_test.sh :: teste_literal :: linha 10"* ]]
  [[ "$output" == *"AVISO AUSENCIA tests/perfis_test.sh :: teste_ausencia :: linha 14"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/perfis_test.sh :: teste_sem_nada :: linha 16"* ]]
  [[ "$output" != *"teste_pular_condicional"* ]]
  [[ "$output" == *"casos: 5 | bloqueantes: 2 | maiores: 1 | avisos: 1"* ]]
}

# ---------- jest / vitest ----------

@test "jest: formas de skip incondicional sao BLOQUEANTE SKIP; skipIf nao" {
  arquivo src/a.test.js <<'EOF'
it.skip("a", () => { expect(f()).toBe(2); });
test.skip("b", () => { expect(f()).toBe(2); });
xit("c", () => { expect(f()).toBe(2); });
xtest("d", () => { expect(f()).toBe(2); });
describe.skip("e", () => {
  it("e1", () => { expect(f()).toBe(2); });
});
xdescribe("f", () => {
  it("f1", () => { expect(f()).toBe(2); });
});
it.skipIf(process.env.CI)("g", () => { expect(f()).toBe(2); });
it("h", () => {
  return;
  expect(f()).toBe(2);
});
EOF
  roda
  [ "$status" -eq 1 ]
  for c in "a :: linha 1" "b :: linha 2" "c :: linha 3" "d :: linha 4" "e :: linha 5" "f :: linha 8" "h :: linha 13"; do
    [[ "$output" == *"BLOQUEANTE SKIP src/a.test.js :: $c"* ]]
  done
  [[ "$output" != *":: g ::"* ]]
  [[ "$output" == *"bloqueantes: 7 |"* ]]
}

@test "jest: caso sem expect e SEM-ASSERCAO; expect em string do titulo nao conta" {
  arquivo src/a.test.js <<'EOF'
describe("grupo", () => {
  it("chama expect(x) no titulo", () => {
    f();
  });
  test("multilinha", async () => {
    const r = await g();
    await expect(h()).rejects.toThrow("x");
  });
});
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO src/a.test.js :: chama expect(x) no titulo :: linha 2"* ]]
  [[ "$output" != *":: multilinha ::"* ]]
  [[ "$output" == *"casos: 2 |"* ]]
}

@test "jest: expect literal contra literal e MAIOR LITERAL; com variavel nao" {
  arquivo src/a.test.js <<'EOF'
it("literal", () => {
  expect(1).toBe(1);
  expect("x").toEqual("x");
  expect(true).toBe(true);
});
it("variavel", () => {
  expect(soma(1, 1)).toBe(2);
  expect(x).toEqual("x");
});
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"MAIOR LITERAL src/a.test.js :: literal :: linha 2"* ]]
  [[ "$output" == *"MAIOR LITERAL src/a.test.js :: literal :: linha 3"* ]]
  [[ "$output" == *"MAIOR LITERAL src/a.test.js :: literal :: linha 4"* ]]
  [[ "$output" != *":: variavel ::"* ]]
}

@test "jest: existsSync falso sobre caminho que o teste nao cria e AVISO" {
  arquivo src/a.test.js <<'EOF'
it("fantasma", () => {
  run();
  expect(fs.existsSync(path.join(dir, "fantasma.txt"))).toBe(false);
});
it("criado", () => {
  fs.writeFileSync(path.join(dir, "real.txt"), "x");
  limpa();
  expect(fs.existsSync(path.join(dir, "real.txt"))).toBe(false);
});
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"AVISO AUSENCIA src/a.test.js :: fantasma :: linha 3"* ]]
  [[ "$output" != *":: criado ::"* ]]
}

# ---------- opcoes e padroes ----------

@test "--listar imprime arquivo TAB caso de todos os adaptadores, ordenado" {
  arquivo tests/a.bats <<'EOF'
%test "bats um" {
  run true
}
EOF
  arquivo tests/x_test.sh <<'EOF'
teste_shell() {
  assert_igual "$a" 1
}
EOF
  arquivo src/a.test.js <<'EOF'
describe("g", () => {
  it("jest um", () => { expect(a).toBe(1); });
});
EOF
  roda --listar
  [ "$status" -eq 0 ]
  esperado="$(printf 'src/a.test.js\tjest um\ntests/a.bats\tbats um\ntests/x_test.sh\tteste_shell')"
  [ "$output" = "$esperado" ]
}

@test "--so audita apenas os arquivos indicados" {
  arquivo tests/a.bats <<'EOF'
%test "ruim" {
  true
}
EOF
  arquivo tests/b.bats <<'EOF'
%test "bom" {
  run true
}
EOF
  roda --so tests/b.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"arquivos: 1 | casos: 1 | bloqueantes: 0"* ]]
  roda --so tests/b.bats --so tests/a.bats
  [ "$status" -eq 1 ]
  [[ "$output" == *"arquivos: 2 | casos: 2 | bloqueantes: 1"* ]]
}

@test "linha !glob exclui caminhos da auditoria" {
  printf '*.bats\tbats\n!fixtures/*\n' > "$RAIZ/scripts/auditar-casos.txt"
  arquivo fixtures/ruim.bats <<'EOF'
%test "fixture inerte de proposito" {
  true
}
EOF
  arquivo tests/a.bats <<'EOF'
%test "bom" {
  run true
}
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"arquivos: 1 | casos: 1 |"* ]]
}

@test "sem arquivo de padroes usa o embutido (*.bats bats)" {
  rm "$RAIZ/scripts/auditar-casos.txt"
  arquivo src/a.test.js <<'EOF'
it("x", () => { f(); });
EOF
  arquivo tests/a.bats <<'EOF'
%test "bom" {
  run true
}
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"arquivos: 1 | casos: 1 |"* ]]
}

@test "roda da raiz a partir de subdiretorio" {
  arquivo tests/a.bats <<'EOF'
%test "ruim" {
  true
}
EOF
  run sh -c "cd '$RAIZ/tests' && sh '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/a.bats :: ruim :: linha 1"* ]]
}

@test "uso invalido sai 2" {
  roda --desconhecida
  [ "$status" -eq 2 ]
  roda --padroes
  [ "$status" -eq 2 ]
  roda --padroes nao-existe.txt
  [ "$status" -eq 2 ]
  roda --so
  [ "$status" -eq 2 ]
  roda --so README.md
  [ "$status" -eq 2 ]
  printf '*.bats\tpython\n' > "$RAIZ/scripts/auditar-casos.txt"
  roda
  [ "$status" -eq 2 ]
}

@test "assercao de biblioteca externa carregada por load, it.only e arquivo .bats com CRLF: leitura correta, sem achado indevido" {
  arquivo tests/lib.bats <<'EOF2'
load 'test_helper/bats-assert/load'
%test "helper externo sem definicao local" {
  assert_success
  assert_output ""
}
EOF2
  arquivo src/foco.test.js <<'EOF2'
it.only("foco", () => { expect(f()).toBe(2); });
EOF2
  arquivo tests/crlf.bats <<'EOF2'
%test "inerte com CRLF" {
  skip "depois"
  [ 1 -eq "$x" ]
}
%test "vazio com CRLF" {
  true
}
%test "sadio com CRLF" {
  [ "$status" -eq 0 ]
}
EOF2
  cr=$(printf '\r')
  sed "s/\$/$cr/" "$RAIZ/tests/crlf.bats" > "$RAIZ/tests/crlf.tmp" && mv "$RAIZ/tests/crlf.tmp" "$RAIZ/tests/crlf.bats"
  roda --so tests/lib.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"arquivos: 1 | casos: 1 | bloqueantes: 0 | maiores: 0 | avisos: 0"* ]]
  roda --so src/foco.test.js
  [ "$status" -eq 0 ]
  [[ "$output" == *"arquivos: 1 | casos: 1 | bloqueantes: 0 | maiores: 0 | avisos: 0"* ]]
  roda --so tests/crlf.bats
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SKIP tests/crlf.bats :: inerte com CRLF :: linha 2"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/crlf.bats :: vazio com CRLF :: linha 5"* ]]
  [[ "$output" != *":: sadio com CRLF"* ]]
  [[ "$output" == *"arquivos: 1 | casos: 3 | bloqueantes: 2 | maiores: 0 | avisos: 0"* ]]
}

# ---------- bats: esqueleto pendente ----------

@test "bats: skip com motivo pendente e corpo so de comentarios vira AVISO PENDENTE e nao reprova" {
  arquivo tests/p.bats <<'EOF2'
%test "falta provar X" {
  skip "pendente: provar que X rejeita entrada vazia"
  # a assercao entra quando o teste for escrito
}
EOF2
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"AVISO PENDENTE tests/p.bats :: falta provar X :: linha 2"* ]]
  [[ "$output" != *"BLOQUEANTE"* ]]
  [[ "$output" == *"arquivos: 1 | casos: 1 | bloqueantes: 0 | maiores: 0 | avisos: 1"* ]]
}

@test "bats: cada pendente aparece em linha propria e soma em avisos" {
  arquivo tests/p.bats <<'EOF2'
%test "um" {
  skip "pendente: a"
}
%test "dois" { skip "pendente: b"; }
EOF2
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"AVISO PENDENTE tests/p.bats :: um :: linha 2"* ]]
  [[ "$output" == *"AVISO PENDENTE tests/p.bats :: dois :: linha 4"* ]]
  [[ "$output" == *"avisos: 2"* ]]
}

@test "bats: skip com outro texto, motivo vazio ou sem dois pontos continua BLOQUEANTE SKIP" {
  arquivo tests/p.bats <<'EOF2'
%test "outro texto" {
  skip "depois eu faco"
}
%test "motivo vazio" {
  skip "pendente:"
}
%test "motivo so espacos" {
  skip "pendente:   "
}
%test "sem dois pontos" {
  skip "pendente provar X"
}
%test "skip sem texto" {
  skip
}
EOF2
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SKIP tests/p.bats :: outro texto :: linha 2"* ]]
  [[ "$output" == *"BLOQUEANTE SKIP tests/p.bats :: motivo vazio :: linha 5"* ]]
  [[ "$output" == *"BLOQUEANTE SKIP tests/p.bats :: motivo so espacos :: linha 8"* ]]
  [[ "$output" == *"BLOQUEANTE SKIP tests/p.bats :: sem dois pontos :: linha 11"* ]]
  [[ "$output" == *"BLOQUEANTE SKIP tests/p.bats :: skip sem texto :: linha 14"* ]]
  [[ "$output" != *"AVISO PENDENTE"* ]]
}

@test "bats: codigo depois do skip pendente deixa de ser pendente e e BLOQUEANTE SKIP" {
  arquivo tests/p.bats <<'EOF2'
%test "com codigo depois" {
  skip "pendente: provar Y"
  [ -n "$HOME" ]
}
%test "com comando depois" {
  skip "pendente: provar Z"
  true
}
EOF2
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SKIP tests/p.bats :: com codigo depois :: linha 2"* ]]
  [[ "$output" == *"BLOQUEANTE SKIP tests/p.bats :: com comando depois :: linha 6"* ]]
  [[ "$output" != *"AVISO PENDENTE"* ]]
}

@test "bats: skip pendente condicional nao e acusado nem contado como pendente" {
  arquivo tests/p.bats <<'EOF2'
%test "condicional" {
  [ -z "$X" ] && skip "pendente: so sem X"
  [ 1 -eq "$Y" ]
}
EOF2
  roda
  [ "$status" -eq 0 ]
  [[ "$output" != *"AVISO PENDENTE"* ]]
  [[ "$output" == *"avisos: 0"* ]]
}

@test "jest: skip com texto pendente continua BLOQUEANTE SKIP" {
  arquivo src/j.test.js <<'EOF2'
it.skip("pendente: provar W", () => {
  expect(1).toBe(1);
});
EOF2
  roda --so src/j.test.js
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SKIP src/j.test.js"* ]]
  [[ "$output" != *"AVISO PENDENTE"* ]]
}

# ---------- issue #78: falsos positivos do adaptador jest e do bats ----------

@test "jest: should, and, cy.contains, its e throw new Error contam como assercao direta" {
  arquivo a.test.js <<'EOF'
it('should', () => { cy.get('a').should('exist'); });
it('and', () => { cy.get('a').and('be.visible'); });
it('contains', () => { cy.contains('texto'); });
it('its', () => { cy.wrap(obj).its('campo'); });
it('throw', () => { if (!ok) { throw new Error('falhou'); } });
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"arquivos: 1 | casos: 5 | bloqueantes: 0 | maiores: 0 | avisos: 0"* ]]
}

@test "jest: cypress sem as formas, forma so em comentario ou string e helper sem assercao continuam SEM-ASSERCAO" {
  arquivo a.test.js <<'EOF'
it('sem forma', () => { cy.get('a').click(); });
it('comentario', () => {
  // cy.get('a').should('exist')
  /* .and('x') cy.contains('y') */
  cy.get('a').click();
});
it('string', () => { const s = ".should( .its( throw new Error"; cy.visit(s); });
const ajuda = () => { cy.get('a').click(); };
it('helper sem assercao', () => { ajuda(); });
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO a.test.js :: sem forma :: linha 1"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO a.test.js :: comentario :: linha 2"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO a.test.js :: string :: linha 7"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO a.test.js :: helper sem assercao :: linha 9"* ]]
  [[ "$output" == *"casos: 4 | bloqueantes: 4 |"* ]]
}

@test "jest: helper de um e de dois niveis, por function ou const, conta; de tres niveis nao" {
  arquivo a.test.js <<'EOF'
function nivel0() { cy.get('a').should('exist'); }
const nivel1 = () => { nivel0(); };
const nivel2 = async () => { nivel1(); };
const expr = () => expect(1).toBe(2);
it('um nivel', () => { nivel0(); });
it('dois niveis', () => { nivel1(); });
it('tres niveis', () => { nivel2(); });
it('expressao', () => { expr(); });
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO a.test.js :: tres niveis :: linha 7"* ]]
  [[ "$output" == *"casos: 4 | bloqueantes: 1 |"* ]]
}

@test "jest: literal de regex com aspas e branqueado e o expect seguinte continua visivel" {
  arquivo a.test.js <<'EOF'
it('regex com aspas', () => {
  const m = texto.match(/'([^']+)'/g);
  expect(m).toBeTruthy();
});
it('regex com aspas e sem assercao', () => {
  const m = texto.match(/'([^']+)'/g);
  usar(m);
});
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO a.test.js :: regex com aspas e sem assercao :: linha 5"* ]]
  [[ "$output" == *"casos: 2 | bloqueantes: 1 |"* ]]
}

@test "jest: divisao comum nao vira regex, nem esconde assercao nem inventa uma" {
  arquivo a.test.js <<'EOF'
it('divisao e assercao', () => {
  const r = total / quantidade; expect(r).toBe(2); const s = x / y / z;
});
it('divisao em cadeia sem assercao', () => {
  const r = a / b / c; const t = (a + b) / 2; usar(r, t);
});
it('divisao e depois should em comentario', () => {
  const r = a / b; // .should('x') / c
  usar(r);
});
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" != *":: divisao e assercao ::"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO a.test.js :: divisao em cadeia sem assercao :: linha 4"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO a.test.js :: divisao e depois should em comentario :: linha 7"* ]]
  [[ "$output" == *"casos: 3 | bloqueantes: 2 |"* ]]
}

@test "bats: return e exit diferentes de zero e awk com exit diferente de zero contam como assercao" {
  arquivo tests/a.bats <<'EOF'
%test "return 1" {
  comando_externo || return 1
}
%test "exit 2" {
  comando_externo || exit 2
}
%test "awk em uma linha" {
  awk 'BEGIN { exit (n != 1) }' arquivo
}
%test "awk com -v e programa em varias linhas" {
  awk -v n="1" '
    /x/ { c++ }
    END { exit (c != n) }
  ' arquivo
}
%test "awk exit com valor literal" {
  awk '{ exit 3 }' arquivo
}
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"casos: 5 | bloqueantes: 0 | maiores: 0 | avisos: 0"* ]]
}

@test "bats: exit 0, return 0, exitoso, awk sem exit ou com exit 0 e exit em programa de outro caso continuam SEM-ASSERCAO" {
  arquivo tests/a.bats <<'EOF'
%test "exit zero" {
  comando_externo
  exit 0
}
%test "return zero" {
  comando_externo
  return 0
}
%test "exitoso" {
  awk '{ exitoso = 1 }' arquivo
}
%test "awk sem exit" {
  awk '{ print $1 }' arquivo
}
%test "awk exit zero" {
  awk 'END { exit 0 }' arquivo
}
%test "awk com programa de varias linhas sem exit" {
  awk '
    { c++ }
    END { print c }
  ' arquivo
}
%test "exit so em string" {
  echo 'exit 1'
}
%test "awk com exit" {
  awk 'END { exit 1 }' arquivo
}
%test "awk de outro caso, sem exit" {
  awk '{ print }' arquivo
}
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"casos: 9 | bloqueantes: 8 |"* ]]
  [[ "$output" != *":: awk com exit ::"* ]]
  [[ "$output" == *":: awk de outro caso, sem exit ::"* ]]
  [[ "$output" == *":: exitoso ::"* ]]
}

@test "bats: exit so em comentario ou string do programa awk continua SEM-ASSERCAO e exit real continua contando" {
  arquivo tests/a.bats <<'EOF2'
%test "awk comentario" {
  awk '# exit 1
{ print }' arquivo
}
%test "awk comentario inline" {
  awk '{ print } # exit 2' arquivo
}
%test "awk string com exit" {
  awk '{ print "exit 1" }' arquivo
}
%test "awk string em variavel" {
  awk '{ print "a" ; x = "exit 1" }' arquivo
}
%test "awk exit real apos comentario" {
  awk '# nota
{ exit (n != 1) }' arquivo
}
%test "awk exit real com string antes" {
  awk '{ print "a" } END { exit 1 }' arquivo
}
EOF2
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"casos: 6 | bloqueantes: 4 |"* ]]
  [[ "$output" == *":: awk comentario ::"* ]]
  [[ "$output" == *":: awk comentario inline ::"* ]]
  [[ "$output" == *":: awk string com exit ::"* ]]
  [[ "$output" == *":: awk string em variavel ::"* ]]
  [[ "$output" != *":: awk exit real apos comentario ::"* ]]
  [[ "$output" != *":: awk exit real com string antes ::"* ]]
}

@test "jest: divisao depois de parentese, colchete, numero e string nao vira regex e a assercao seguinte fica visivel" {
  arquivo a.test.js <<'EOF2'
it('apos parentese', () => {
  const z = (a + b) / 2; expect(z).toBe(1); const w = (c) / 3;
});
it('apos colchete', () => {
  const z = a[0] / 2; expect(z).toBe(1); const w = b[1] / 3;
});
it('apos numero', () => {
  const z = 4 / 2; expect(z).toBe(2); const w = 6 / 3;
});
it('apos string', () => {
  const z = "a" / 2; expect(z).toBe(1); const w = "b" / 3;
});
EOF2
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"casos: 4 | bloqueantes: 0 |"* ]]
}

@test "jest: metodo de objeto com o nome do helper nao conta como chamada do helper" {
  arquivo a.test.js <<'EOF2'
function verificar() { expect(1).toBe(1); }
it('chama o helper', () => { verificar(); });
it('chama membro homonimo', () => { obj.verificar(); });
EOF2
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO a.test.js :: chama membro homonimo :: linha 3"* ]]
  [[ "$output" != *":: chama o helper ::"* ]]
  [[ "$output" == *"casos: 2 | bloqueantes: 1 |"* ]]
}
