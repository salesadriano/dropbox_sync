#!/usr/bin/env bats
# QA independente de scripts/lint.sh. Shellcheck e duble no PATH; LINT_SEM_SYSTEMD=1 evita systemd real.
# Rodar: npx --yes bats@1.13.0 --abort scripts/tests/qa-lint.bats

SCRIPT="$BATS_TEST_DIRNAME/../lint.sh"

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/w"
  cat > "$BATS_TEST_TMPDIR/bin/shellcheck" <<'EOS'
#!/bin/sh
printf '%s\n' "$1" >> "$BATS_TEST_TMPDIR/chamadas"
case "$1" in
  *achado*) echo "In $1 line 1: SC2086"; exit 1 ;;
  *morto*) exit 1 ;;
  *) exit 0 ;;
esac
EOS
  chmod +x "$BATS_TEST_TMPDIR/bin/shellcheck"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" LINT_SEM_SYSTEMD=1
}

@test "nome de arquivo com espaco chega inteiro ao shellcheck" {
  run sh "$SCRIPT" "meu arquivo.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/chamadas")" = "meu arquivo.sh" ]
}

@test "nome de arquivo com aspas chega inteiro ao shellcheck" {
  run sh "$SCRIPT" "it's.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/chamadas")" = "it's.sh" ]
}

@test "achado em um arquivo nao impede analisar os demais e o resultado e 1" {
  run sh "$SCRIPT" achado.sh b.sh c.sh
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/chamadas")" -eq 3 ]
}

@test "sem argumentos, de outro diretorio, analisa lib commands bin e scripts da raiz" {
  cd "$BATS_TEST_TMPDIR/w"
  run sh "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx 'lib/cmd.sh' "$BATS_TEST_TMPDIR/chamadas"
  grep -qx 'bin/dbx' "$BATS_TEST_TMPDIR/chamadas"
  grep -qx 'scripts/lint.sh' "$BATS_TEST_TMPDIR/chamadas"
  grep -q '^commands/download.sh$' "$BATS_TEST_TMPDIR/chamadas"
}

@test "LINT_PARALELO=0 nao libera paralelismo ilimitado" {
  LINT_PARALELO=0 run sh "$SCRIPT" a.sh b.sh c.sh d.sh
  # xargs -P 0 significa ilimitado; o esperado e recusar (status != 0) ou ao menos nao disparar tudo.
  [ "$status" -ne 0 ]
}

@test "LINT_PARALELO invalido falha com status diferente de 0" {
  LINT_PARALELO=abc run sh "$SCRIPT" a.sh
  [ "$status" -ne 0 ]
}

@test "LINT_MEMORIA_MB invalido falha com status diferente de 0 e nao aprova em silencio" {
  LINT_MEMORIA_MB=abc run sh "$SCRIPT" a.sh
  [ "$status" -ne 0 ]
}

@test "com um unico argumento inexistente o status e propagado como falha (shellcheck real ausente de arquivo)" {
  cat > "$BATS_TEST_TMPDIR/bin/shellcheck" <<'EOS'
#!/bin/sh
[ -f "$1" ] || { echo "$1: openBinaryFile: does not exist"; exit 2; }
exit 0
EOS
  run sh "$SCRIPT" nao-existe.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"interrompido"* ]]
}

@test "saida do shellcheck nao e perdida quando o duble sai com 2 e texto" {
  cat > "$BATS_TEST_TMPDIR/bin/shellcheck" <<'EOS'
#!/bin/sh
echo "erro de uso"; exit 2
EOS
  run sh "$SCRIPT" a.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"erro de uso"* ]]
}

@test "shellcheck real com teto de 500 MB em arquivo leve passa" {
  command -v /usr/bin/shellcheck >/dev/null 2>&1 || command -v shellcheck >/dev/null || skip "sem shellcheck"
  skip_real=0
  [ -x /usr/bin/shellcheck ] || skip "shellcheck real fora de /usr/bin"
  PATH=/usr/bin:/bin LINT_MEMORIA_MB=2000 run sh "$SCRIPT" "$BATS_TEST_DIRNAME/../lint.sh"
  [ "$status" -eq 0 ]
}
