#!/usr/bin/env bats
# Testes de suite-completa.sh: roda o comando oficial e registra o resultado para o HEAD; --conferir so aceita
# registro verde, limpo e do commit atual. Cada caso monta um repositorio real em $BATS_TEST_TMPDIR.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../suite-completa.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts"
  git -C "$REPO" init -q
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "inicio"
  cp "$SCRIPT" "$REPO/scripts/suite-completa.sh"
}

sc() { (cd "$REPO" && sh scripts/suite-completa.sh "$@"); }
registro() { cat "$REPO/.git/agentes-suite-completa"; }

@test "comando verde em arvore limpa: exit 0, registro 'limpo 0' para o HEAD e --conferir em 0" {
  run sc -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"suite completa: verde, registrada para"* ]]
  sha=$(git -C "$REPO" rev-parse HEAD)
  run registro
  [[ "${lines[0]}" == "$sha limpo 0 "*"Z "* ]]
  run sc --conferir
  [ "$status" -eq 0 ]
  [[ "$output" == *"suite completa verde para"* ]]
}

@test "comando vermelho: propaga o exit, registra e --conferir sai com 3 citando o exit" {
  run sc -- sh -c 'exit 7'
  [ "$status" -eq 7 ]
  [[ "$output" == *"vermelha (exit 7)"* ]]
  run sc --conferir
  [ "$status" -eq 3 ]
  [[ "$output" == *"ficou vermelha (exit 7"* ]]
}

@test "alteracao em arquivo rastreado marca o registro como sujo e --conferir recusa" {
  echo a > "$REPO/a.txt"; git -C "$REPO" add a.txt; git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m a
  echo b > "$REPO/a.txt"
  run sc -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"registrada como suja"* ]]
  run registro
  [[ "${lines[0]}" == *" sujo 0 "* ]]
  run sc --conferir
  [ "$status" -eq 3 ]
  [[ "$output" == *"alteracao nao commitada"* ]]
}

@test "arquivo novo nao rastreado nao conta como sujo, so avisa" {
  echo x > "$REPO/novo.txt"
  run sc -- true
  [ "$status" -eq 0 ]
  [[ "$output" == *"aviso: ha arquivo nao rastreado"* ]]
  run sc --conferir
  [ "$status" -eq 0 ]
}

@test "sem registro, --conferir sai com 3 e ensina o comando" {
  run sc --conferir
  [ "$status" -eq 3 ]
  [[ "$output" == *"sem registro da suite completa para o commit atual"* ]]
  [[ "$output" == *"sh scripts/suite-completa.sh -- <comando oficial>"* ]]
}

@test "commit novo invalida o registro anterior; vale a ultima linha do HEAD" {
  run sc -- true
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "mais"
  run sc --conferir
  [ "$status" -eq 3 ]
  run sc -- false
  run sc -- true
  run sc --conferir
  [ "$status" -eq 0 ]
  [ "$(registro | wc -l)" -eq 3 ]
}

@test "--mostrar lista os registros, ou diz que nao ha" {
  run sc --mostrar
  [ "$status" -eq 0 ]
  [[ "$output" == "sem registro de suite completa neste worktree" ]]
  sc -- true >/dev/null
  run sc --mostrar
  [ "${#lines[@]}" -eq 1 ]
}

@test "sem comando apos -- e sem scripts/suite-completa.cmd: exit 2; com o .cmd, roda o que esta nele" {
  run sc
  [ "$status" -eq 2 ]
  [[ "$output" == *"informe o comando oficial"* ]]
  printf 'echo rodou-oficial && exit 0\n' > "$REPO/scripts/suite-completa.cmd"
  run sc
  [ "$status" -eq 0 ]
  [[ "$output" == *"rodou-oficial"* ]]
}

@test "o comando roda a partir da raiz do repositorio e recebe os argumentos como estao, sem eval" {
  mkdir -p "$REPO/sub"
  run sh -c 'cd "$1/sub" && sh ../scripts/suite-completa.sh -- sh -c "pwd; printf %s \"\$1\"" x "a \$(echo NAO) b"' _ "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$REPO"* ]]
  [[ "$output" == *'a $(echo NAO) b'* ]]
  [[ "$output" != *"a NAO b"* ]]
}

@test "argumento desconhecido e --conferir com argumento saem com 2; fora de repositorio sai com 1" {
  run sc --xpto
  [ "$status" -eq 2 ]
  run sc --conferir extra
  [ "$status" -eq 2 ]
  mkdir -p "$BATS_TEST_TMPDIR/fora"
  run sh -c 'cd "$1" && sh "$2" --conferir' _ "$BATS_TEST_TMPDIR/fora" "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "repositorio sem commit sai com 1" {
  V="$BATS_TEST_TMPDIR/vazio"; mkdir -p "$V"; git -C "$V" init -q
  run sh -c 'cd "$1" && sh "$2" -- true' _ "$V" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sem commit"* ]]
}

@test "em worktree secundario o registro fica no git-dir do proprio worktree" {
  git -C "$REPO" worktree add -q -b outra "$BATS_TEST_TMPDIR/wt" >/dev/null 2>&1
  mkdir -p "$BATS_TEST_TMPDIR/wt/scripts"; cp "$SCRIPT" "$BATS_TEST_TMPDIR/wt/scripts/"
  run sh -c 'cd "$1" && sh scripts/suite-completa.sh -- true' _ "$BATS_TEST_TMPDIR/wt"
  [ "$status" -eq 0 ]
  [ -f "$REPO/.git/worktrees/wt/agentes-suite-completa" ]
  [ ! -f "$REPO/.git/agentes-suite-completa" ]
}
