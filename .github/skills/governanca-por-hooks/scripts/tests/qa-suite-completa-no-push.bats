#!/usr/bin/env bats
# Suite independente do QA para a regra 3 do guarda e suite-completa.sh: cenarios de risco fora da suite dos
# autores. Nao versionar antes do aceite do solicitante (regra 12); sha256 no registro de entrega.

setup() {
  GUARDA="$BATS_TEST_DIRNAME/../guarda-de-comandos.sh"
  SUITE="$BATS_TEST_DIRNAME/../suite-completa.sh"
  REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$REPO/scripts"
  git -C "$REPO" init -q -b main
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m inicio
  printf '#!/usr/bin/env sh\nexit 0\n' > "$REPO/scripts/alteracoes-externas.sh"
  cp "$SUITE" "$REPO/scripts/suite-completa.sh"
}
hook() { printf '{"tool_input":{"command":%s},"cwd":"%s"}' "$(printf '%s' "$1" | python3 -I -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" "$2" | sh "$GUARDA"; }
sc() { (cd "$REPO" && sh scripts/suite-completa.sh "$@"); }

@test "QA-1: registro gravado a mao com sha de outro commit nao libera; so o HEAD exato" {
  printf '%s limpo 0 2026-01-01T00:00:00Z 1\n' "$(printf 'a%.0s' $(seq 40))" > "$REPO/.git/agentes-suite-completa"
  run hook "git push" "$REPO"
  [ "$status" -eq 2 ]
}

@test "QA-2: registro com linha malformada (campos faltando) para o HEAD nao libera e nao quebra o guarda" {
  printf '%s\n' "$(git -C "$REPO" rev-parse HEAD)" > "$REPO/.git/agentes-suite-completa"
  run hook "git push" "$REPO"
  [ "$status" -eq 2 ]
  run sc --conferir
  [ "$status" -eq 3 ]
}

@test "QA-3: registro verde seguido de vermelho para o mesmo HEAD: vale o ultimo (bloqueia)" {
  sc -- true >/dev/null
  sc -- false >/dev/null 2>&1 || true
  run hook "git push" "$REPO"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ficou vermelha"* ]]
}

@test "QA-4: comando com 'git push' citado numa string e tambem verificado pela regra 3 (limite por substring, declarado)" {
  run hook "echo 'git push' > nota.txt" "$REPO"
  [ "$status" -eq 2 ]
}

@test "QA-5: 'gh pr create' precedido de outro comando na mesma linha e verificado" {
  run hook "cd x && gh pr create --fill" "$REPO"
  [ "$status" -eq 2 ]
}

@test "QA-6: gh que falha (exit 1, sem saida) e tratado como zero PRs: branch de trabalho passa" {
  git -C "$REPO" checkout -q -b feature/x; git -C "$REPO" remote add origin git@example.invalid:x/y.git
  mkdir -p "$BATS_TEST_TMPDIR/bin"; printf '#!/usr/bin/env sh\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/gh"; chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run hook "git push" "$REPO"
  [ "$status" -eq 0 ]
}

@test "QA-7: gh que devolve lixo (nao numero) nao bloqueia nem quebra" {
  git -C "$REPO" checkout -q -b feature/x; git -C "$REPO" remote add origin git@example.invalid:x/y.git
  mkdir -p "$BATS_TEST_TMPDIR/bin"; printf '#!/usr/bin/env sh\necho "erro: nao autenticado"\n' > "$BATS_TEST_TMPDIR/bin/gh"; chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run hook "git push" "$REPO"
  [ "$status" -eq 0 ]
}

@test "QA-8: entrada branch-principal substituida (status nao ativa) e ignorada; vale main/master" {
  mkdir -p "$REPO/.github/agents/memoria/entradas"
  printf -- '---\ntitulo: Branch principal declarada e `trunk`\nstatus: substituida\n---\n' > "$REPO/.github/agents/memoria/entradas/2026-01-01-0000-branch-principal.md"
  run hook "git push" "$REPO"
  [ "$status" -eq 2 ]
}

@test "QA-9: SEGURANCA: comando oficial com metacaracteres nao e expandido pelo suite-completa.sh" {
  run sc -- sh -c 'printf "%s" "$1"' x '$(touch /tmp/NAO-$$) `id`'
  [ "$status" -eq 0 ]
  [[ "$output" == *'$(touch'* ]]
  [ ! -f "/tmp/NAO-$$" ]
}

@test "QA-10: --conferir le o registro do worktree certo quando o cwd e um subdiretorio" {
  mkdir -p "$REPO/sub/dir"
  sc -- true >/dev/null
  run sh -c 'cd "$1/sub/dir" && sh ../../scripts/suite-completa.sh --conferir' _ "$REPO"
  [ "$status" -eq 0 ]
  run hook "git push" "$REPO/sub/dir"
  [ "$status" -eq 0 ]
}

@test "QA-11: suite-completa.sh e guarda rodam em bash como sh" {
  run sh -c 'cd "$1" && bash scripts/suite-completa.sh -- true' _ "$REPO"
  [ "$status" -eq 0 ]
  run sh -c 'printf "{\"tool_input\":{\"command\":\"git push\"},\"cwd\":\"$1\"}" "$1" | bash "$2"' _ "$REPO" "$GUARDA"
  [ "$status" -eq 0 ]
}
