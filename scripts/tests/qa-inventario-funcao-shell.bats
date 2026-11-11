#!/usr/bin/env bats
# Suite independente do QA: descoberta de caso declarado como funcao shell (issue #60) e @epoch no touch (issue #35).
# Seam: saida de --listar do script real em repositorio git descartavel. Nao versionar antes do aceite (regra 12).

setup() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  export SCRIPT="$BATS_TEST_DIRNAME/../inventario-de-testes.sh"
  RAIZ="$BATS_TEST_TMPDIR/repo"
  git init -q -b main "$RAIZ"
  mkdir -p "$RAIZ/tests"
}

# lista <glob> <ERE> : grava o padrao e roda --listar sobre os arquivos adicionados
lista() {
  git -C "$RAIZ" add -A
  printf '%s\t%s\n' "$1" "$2" > "$RAIZ/padroes.txt"
  run sh -c 'cd "$1" && sh "$SCRIPT" --listar --padroes padroes.txt' _ "$RAIZ"
}

PADRAO_ISSUE='^teste_[A-Za-z0-9_]+[ ]*\(\)'

@test "padrao da issue descobre teste_x() { e teste_y () { com nomes sem espaco" {
  printf 'teste_x() {\n  true\n}\nteste_y () {\n  true\n}\n' > "$RAIZ/tests/h_test.sh"
  lista 'tests/*_test.sh' "$PADRAO_ISSUE"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'tests/h_test.sh\tteste_x\ntests/h_test.sh\tteste_y')" ]
}

@test "varios espacos antes dos parenteses nao entram no nome" {
  printf 'teste_w   () {\n  true\n}\n' > "$RAIZ/tests/h_test.sh"
  lista 'tests/*_test.sh' "$PADRAO_ISSUE"
  [ "$output" = "$(printf 'tests/h_test.sh\tteste_w')" ]
}

@test "go func Test nao regride (nome antes dos parenteses via func, nao via funcao shell)" {
  printf 'func TestSoma(t *testing.T) {\n}\n' > "$RAIZ/tests/a_test.go"
  lista '*_test.go' '^func Test'
  [ "$output" = "$(printf 'tests/a_test.go\tTestSoma')" ]
}

# Adaptacao do projeto (inverte o caso do modelo "aspas na linha da funcao prevalecem"): o harness proprio tem casos
# de uma linha so com string no corpo, e o nome do caso e o da funcao (docs/reviews/2026-10-27-1500-registro-protocolo-atual.md).
@test "projeto: o nome da funcao shell no inicio da linha prevalece sobre as aspas do corpo (caso de uma linha so)" {
  printf 'teste_q() { echo "descricao q"; }\n' > "$RAIZ/tests/h_test.sh"
  lista 'tests/*_test.sh' "$PADRAO_ISSUE"
  [ "$output" = "$(printf 'tests/h_test.sh\tteste_q')" ]
}

@test "funcao helper que nao casa o padrao do projeto nao e listada" {
  printf 'helper_x() {\n  true\n}\nteste_ok() {\n  true\n}\n' > "$RAIZ/tests/h_test.sh"
  lista 'tests/*_test.sh' "$PADRAO_ISSUE"
  [ "$output" = "$(printf 'tests/h_test.sh\tteste_ok')" ]
}

@test "chamada teste_x() dentro de string em outra linha nao e caso" {
  printf 'echo "teste_fake() {"\nteste_real() {\n  true\n}\n' > "$RAIZ/tests/h_test.sh"
  lista 'tests/*_test.sh' "$PADRAO_ISSUE"
  [ "$output" = "$(printf 'tests/h_test.sh\tteste_real')" ]
}

@test "limite conhecido: funcao indentada casada por padrao proprio nao tem nome e e omitida" {
  printf '  teste_i() {\n  true\n}\n' > "$RAIZ/tests/h_test.sh"
  lista 'tests/*_test.sh' '^[[:space:]]+teste_[A-Za-z0-9_]+[ ]*\(\)'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "limite conhecido: forma 'function nome {' sem parenteses nao e reconhecida" {
  printf 'function teste_f {\n  true\n}\n' > "$RAIZ/tests/h_test.sh"
  lista 'tests/*_test.sh' '^function teste_'
  [ -z "$output" ]
}
