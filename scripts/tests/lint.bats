#!/usr/bin/env bats
# scripts/lint.sh: um shellcheck por arquivo, sob teto de memoria. O shellcheck e um duble no PATH,
# cujo comportamento vem do nome do arquivo analisado; o teto real nao e exercitado aqui.
# Rodar: npx --yes bats@1.13.0 --abort scripts/tests/lint.bats

SCRIPT="$BATS_TEST_DIRNAME/../lint.sh"

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/shellcheck" <<'EOF'
#!/bin/sh
echo "$1" >> "$BATS_TEST_TMPDIR/chamadas"
case "$1" in
  *achado*) echo "In $1 line 1: SC2086"; exit 1 ;;
  *morto*) exit 1 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/shellcheck"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" LINT_SEM_SYSTEMD=1
}

@test "um processo por arquivo; arquivos limpos saem com 0" {
  run sh "$SCRIPT" a.sh b.sh c.sh
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/chamadas")" -eq 3 ]
}

@test "achado sai com 1, mostra o texto e nao culpa o teto" {
  run sh "$SCRIPT" a.sh achado.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"SC2086"* ]]
  [[ "$output" != *"interrompido"* ]]
}

@test "saida 1 sem texto e acusada como interrompida pelo teto" {
  run sh "$SCRIPT" morto.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"lint: morto.sh interrompido"* ]]
}

@test "sem shellcheck no PATH sai com 2" {
  PATH=/usr/bin:/bin run sh "$SCRIPT" a.sh
  [ "$status" -eq 2 ]
}
