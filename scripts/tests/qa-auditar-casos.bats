#!/usr/bin/env bats
# Suite independente do QA para scripts/auditar-casos.sh (issue #67, item 2; referencia
# .github/skills/protocolo-tdd/references/auditoria-de-casos-inertes.md). Cobre o que a suite do autor nao prende:
# skip condicional em `if` multilinha e em `case`, `if` so em comentario, assercao transitiva por `function nome {`
# e por `source`, limite de dois niveis, literal com espacos, `<<-` com marcador entre aspas, `it.todo`,
# `describe.skip` aninhado, `.each` com titulo na linha, `--so` com arquivo inexistente, repetido ou fora do indice
# e a garantia de somente leitura.
# Nota (regra 12): este arquivo NAO e versionado antes do aceite do solicitante. Cada teste monta um repositorio
# descartavel em $BATS_TEST_TMPDIR.

setup() {
  export SCRIPT="$BATS_TEST_DIRNAME/../auditar-casos.sh"
  RAIZ="$BATS_TEST_TMPDIR/proj"
  git init -q -b main "$RAIZ"
  mkdir -p "$RAIZ/scripts"
  printf '*.bats\tbats\n*.spec.js\tjest\n' > "$RAIZ/scripts/auditar-casos.txt"
  git -C "$RAIZ" add -A
}

# Grava o stdin em $RAIZ/$1 e versiona. `%test` vira `@test` (o pre-processador do Bats reescreve `@test` ate em
# heredoc).
grava() {
  mkdir -p "$(dirname "$RAIZ/$1")"
  sed 's/^\([[:space:]]*\)%test /\1@test /' > "$RAIZ/$1"
  git -C "$RAIZ" add -A
}

audita() { run sh -c 'cd "$1" && shift && sh "$SCRIPT" "$@"' _ "$RAIZ" "$@"; }

@test "skip condicional em if multilinha e em case nao e achado; if so no comentario nao torna o skip condicional" {
  grava spec/s.bats <<'EOF'
%test "if em varias linhas" {
  if [ -z "${BANCO_URL:-}" ] ||
     [ "$CI" = nao ]
  then
    skip "sem banco"
  fi
  run consulta
  [ "$status" -eq 0 ]
}
%test "case" {
  case "$(uname)" in
    Darwin) skip "so linux" ;;
  esac
  [ -n "$PATH" ]
}
%test "comentario com if" {
  skip # if precisar, reativar
  [ -n "$PATH" ]
}
EOF
  audita
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SKIP spec/s.bats :: comentario com if :: linha 17"* ]]
  [[ "$output" != *":: if em varias linhas ::"* ]]
  [[ "$output" != *":: case ::"* ]]
  [[ "$output" == *"arquivos: 1 | casos: 3 | bloqueantes: 1 | maiores: 0 | avisos: 0"* ]]
}

@test "assercao transitiva por function nome { e por source do mesmo diretorio; dois niveis e SEM-ASSERCAO" {
  mkdir -p "$RAIZ/spec"
  printf 'confere_total() {\n  [ "$total" -gt 0 ]\n}\n' > "$RAIZ/spec/apoio.sh"
  grava spec/t.bats <<'EOF'
function verifica_saida {
  [[ "$output" == *pago* ]]
}
encadeia() {
  verifica_saida
}
%test "helper com function sem parenteses" { verifica_saida; }
%test "helper de arquivo carregado por source" {
  source "$BATS_TEST_DIRNAME/apoio.sh"
  confere_total
}
%test "helper que so chama helper" {
  encadeia
}
EOF
  audita
  [ "$status" -eq 1 ]
  [[ "$output" != *":: helper com function sem parenteses ::"* ]]
  [[ "$output" != *":: helper de arquivo carregado por source ::"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO spec/t.bats :: helper que so chama helper :: linha 12"* ]]
  [[ "$output" == *"casos: 3 | bloqueantes: 1 |"* ]]
}

@test "literal com espacos dos dois lados e MAIOR LITERAL em [ ], [[ ]] e test; variavel contra literal com espaco nao" {
  grava spec/l.bats <<'EOF'
%test "literais com espaco" {
  [ "pedido pago" = "pedido pago" ]
  [[ 'nota fiscal' == "nota fiscal" ]]
  test "a b" != "c d"
}
%test "variavel" {
  run status_pedido
  [ "$output" = "pedido pago" ]
}
EOF
  audita
  [ "$status" -eq 1 ]
  [[ "$output" == *"MAIOR LITERAL spec/l.bats :: literais com espaco :: linha 2"* ]]
  [[ "$output" == *"MAIOR LITERAL spec/l.bats :: literais com espaco :: linha 3"* ]]
  [[ "$output" == *"MAIOR LITERAL spec/l.bats :: literais com espaco :: linha 4"* ]]
  [[ "$output" != *":: variavel ::"* ]]
  [[ "$output" == *"bloqueantes: 0 | maiores: 3 | avisos: 0"* ]]
}

@test "heredoc <<- com marcador entre aspas e tabs: o corpo nao conta e o caso seguinte e lido" {
  printf '%%test "gera config" {\n\tcat > c.ini <<-"FIM"\n\t\t[ 1 -eq 1 ]\n\t\tskip\n\tFIM\n\t[ -s c.ini ]\n}\n%%test "seguinte" {\n  true\n}\n' | grava spec/h.bats
  audita
  [ "$status" -eq 1 ]
  [[ "$output" != *":: gera config ::"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO spec/h.bats :: seguinte :: linha 8"* ]]
  [[ "$output" == *"casos: 2 | bloqueantes: 1 | maiores: 0"* ]]
}

@test "jest: it.todo nao e caso; describe.skip aninhado e SKIP no grupo; .each com titulo na linha e caso" {
  grava src/p.spec.js <<'EOF'
describe("pedidos", () => {
  it.todo("cancelamento parcial");
  describe.skip("estorno", () => {
    it("devolve o valor", () => { expect(estorna(10)).toBe(10); });
  });
  it.each([[1, 2], [2, 4]])("dobra %i", (a, b) => {
    expect(dobra(a)).toBe(b);
  });
  test.each([3])("sem assercao %i", (n) => {
    dobra(n);
  });
});
EOF
  audita
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SKIP src/p.spec.js :: estorno :: linha 3"* ]]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO src/p.spec.js :: sem assercao %i :: linha 9"* ]]
  [[ "$output" != *"cancelamento parcial"* ]]
  [[ "$output" != *":: dobra %i ::"* ]]
  [[ "$output" == *"casos: 3 | bloqueantes: 2 | maiores: 0"* ]]
  audita --listar
  [[ "$output" != *"cancelamento parcial"* ]]
  [[ "$output" == *"$(printf 'src/p.spec.js\tdobra %%i')"* ]]
}

@test "--so: arquivo inexistente junto de um valido sai 2 sem resumo; repetido e com ./ conta uma vez; fora do indice vale" {
  grava spec/ok.bats <<'EOF'
%test "valido" {
  run true
  [ "$status" -eq 0 ]
}
EOF
  audita --so spec/ok.bats --so spec/nao-existe.bats
  [ "$status" -eq 2 ]
  [[ "$output" == *"spec/nao-existe.bats"* ]]
  [[ "$output" != *"arquivos:"* ]]
  audita --so ./spec/ok.bats --so spec/ok.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"arquivos: 1 | casos: 1 | bloqueantes: 0"* ]]
  printf '@test "novo sem assercao" {\n  true\n}\n' > "$RAIZ/spec/novo.bats"
  audita --so spec/novo.bats
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO spec/novo.bats :: novo sem assercao :: linha 1"* ]]
  audita
  [[ "$output" != *"spec/novo.bats"* ]]
}

@test "somente leitura: auditar com achados nao altera arvore nem indice" {
  grava spec/r.bats <<'EOF'
%test "inerte" {
  true
}
EOF
  git -C "$RAIZ" add -A
  antes="$(git -C "$RAIZ" status --porcelain=v1 --untracked-files=all; git -C "$RAIZ" ls-files -s)"
  audita
  [ "$status" -eq 1 ]
  audita --listar
  [ "$status" -eq 0 ]
  depois="$(git -C "$RAIZ" status --porcelain=v1 --untracked-files=all; git -C "$RAIZ" ls-files -s)"
  [ "$antes" = "$depois" ]
}
