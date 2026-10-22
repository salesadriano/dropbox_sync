#!/usr/bin/env bats
# Suite independente do QA Expert para guarda-de-comandos.sh (hook PreToolUse).
# Complementa guarda-de-comandos.bats: JSON com unicode, aspas, quebras e tabs; padroes com `[`, `?`, `\`;
# padrao vazio; git push em docker compose exec; cwd inexistente; prova de nao execucao pelos DOIS leitores de JSON.
# Validacao: docs/reviews/2026-10-15-0914-skills-dos-mods-validacao-qa.md

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../guarda-de-comandos.sh"
  PADROES="$BATS_TEST_TMPDIR/padroes.txt"
  printf 'npm run verify\tnao roda no host\nvitest run\tsuite inteira\n' > "$PADROES"
  MARCA="$BATS_TEST_TMPDIR/marca"
}

json_literal() {  # $1 = texto JSON ja escapado para o campo command, $2 = cwd (opcional)
  if [ -n "${2:-}" ]; then printf '{"tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$2"
  else printf '{"tool_input":{"command":"%s"}}' "$1"; fi
}

# PATH restrito a um unico leitor de JSON (node ou python3), com o minimo que o guarda usa.
path_com() {  # $1 = leitor
  B="$BATS_TEST_TMPDIR/bin-$1"; mkdir -p "$B"
  for b in cat printf tr awk git sh grep sed "$1"; do ln -sf "$(command -v "$b")" "$B/$b"; done
  printf '%s' "$B"
}

repo_com_stub() {  # $1 = exit do stub de alteracoes-externas.sh
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts"
  git -C "$REPO" init -q
  printf '#!/usr/bin/env sh\n[ "$1" = --detectar ] || exit 2\necho "ARQUIVO docs/x.md"\nexit %s\n' "$1" > "$REPO/scripts/alteracoes-externas.sh"
}

@test "QA: comando com unicode (escape \\u e UTF-8 cru) e lido inteiro e o padrao ao lado bloqueia" {
  J="$BATS_TEST_TMPDIR/j.json"
  printf '%s' '{"tool_input":{"command":"echo ção && npx vitest run"}}' > "$J"
  run sh "$SCRIPT" --padroes "$PADROES" < "$J"
  [ "$status" -eq 2 ]
  printf '%s' $'{"tool_input":{"command":"echo acao-\xc3\xa7 \xe2\x9c\x94 \xf0\x9f\x98\x80; npm run verify"}}' > "$J"
  run sh "$SCRIPT" --padroes "$PADROES" < "$J"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nao roda no host"* ]]
  printf 'a\xc3\xa7\xc3\xa3o\tacento no padrao\n' > "$PADROES"
  printf '%s' $'{"tool_input":{"command":"npm run a\xc3\xa7\xc3\xa3o"}}' > "$J"
  run sh "$SCRIPT" --padroes "$PADROES" < "$J"
  [ "$status" -eq 2 ]
  [[ "$output" == *"acento no padrao"* ]]
}

@test "QA: comando com \\n, \\t e aspas escapadas no JSON: o padrao na ultima linha, depois de um tab, bloqueia" {
  run sh -c "printf '%s' '$(json_literal 'echo \"a\"\n\tcd x\n\tnpm run verify')' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
}

@test "QA: padrao com [ ] e ? no arquivo e literal: so o texto identico bloqueia" {
  printf 'rm -rf [abc]\tm1\ncp ?.txt\tm2\n' > "$PADROES"
  for c in 'rm -rf a' 'rm -rf b' 'cp x.txt' 'cp ab.txt'; do
    run sh -c "printf '%s' '$(json_literal "$c")' | sh '$SCRIPT' --padroes '$PADROES'"
    [ "$status" -eq 0 ]
  done
  run sh -c "printf '%s' '$(json_literal 'rm -rf [abc]')' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
  run sh -c "printf '%s' '$(json_literal 'cp ?.txt')' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
}

@test "QA: padrao com barra invertida e literal (a\\b casa so com a\\b)" {
  printf 'a\\b\tm\n' > "$PADROES"
  run sh -c "printf '%s' '$(json_literal 'echo ab')' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 0 ]
  run sh -c "printf '%s' '$(json_literal 'echo a\\b')' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
}

@test "QA: linha so com TAB e motivo (padrao vazio) nao bloqueia todo comando" {
  printf '\tmotivo sem padrao\nnpm run verify\tm\n' > "$PADROES"
  run sh -c "printf '%s' '$(json_literal 'ls')' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 0 ]
  run sh -c "printf '%s' '$(json_literal 'npm run verify')' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
}

@test "QA: padrao com espacos nas pontas e preservado literalmente ('ls ' nao casa 'ls')" {
  printf 'ls \tm\n' > "$PADROES"
  run sh -c "printf '%s' '$(json_literal 'ls')' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 0 ]
  run sh -c "printf '%s' '$(json_literal 'ls -la')' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
}

@test "QA: git push dentro de docker compose exec e de docker-compose run continua verificado pela regra 1" {
  repo_com_stub 3
  run sh -c "printf '%s' '$(json_literal 'docker compose exec app git push origin HEAD' "$REPO")' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"regra 48"* ]]
  run sh -c "printf '%s' '$(json_literal 'docker-compose run --rm app sh -c \"git push\"' "$REPO")' | sh '$SCRIPT'"
  [ "$status" -eq 2 ]
}

@test "QA: 'git push' citado em string de outro comando tambem dispara a regra 1 (limite por substring, declarado)" {
  repo_com_stub 3
  run sh -c "printf '%s' '$(json_literal 'grep -n \"git push\" README.md' "$REPO")' | sh '$SCRIPT'"
  [ "$status" -eq 2 ]
}

@test "QA: 'git pushy' e 'gitpush' nao sao 'git push'; 'git -c x push' e" {
  repo_com_stub 3
  run sh -c "printf '%s' '$(json_literal 'echo gitpush' "$REPO")' | sh '$SCRIPT'"
  [ "$status" -eq 0 ]
  run sh -c "printf '%s' '$(json_literal 'git -c core.x=1 push' "$REPO")' | sh '$SCRIPT'"
  [ "$status" -eq 2 ]
}

@test "QA: cwd que nao existe no disco, cwd relativo e cwd nao-string: o guarda nao quebra e decide so pelo padrao" {
  cd "$BATS_TEST_TMPDIR"   # fora de qualquer repositorio: o cwd vazio cai no pwd, que nao pode ser um repo com detector
  run sh -c "printf '%s' '$(json_literal 'git push' /nao/existe/mesmo)' | sh '$SCRIPT'"
  [ "$status" -eq 0 ]
  run sh -c "printf '%s' '$(json_literal 'npx vitest run' /nao/existe/mesmo)' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
  run sh -c "printf '%s' '{\"tool_input\":{\"command\":\"git push\"},\"cwd\":[1,2]}' | sh '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "QA: command que nao e string (numero, lista, objeto) libera com 0" {
  for v in 123 '[\"npm run verify\"]' '{\"x\":\"npm run verify\"}' null; do
    run sh -c "printf '%s' '{\"tool_input\":{\"command\":$v}}' | sh '$SCRIPT' --padroes '$PADROES'"
    [ "$status" -eq 0 ]
  done
}

@test "QA: SEGURANCA (leitor node): \cifrao-parenteses, crase, ; e | no comando nao sao executados nem expandidos; bloqueio por padrao 'touch'" {
  command -v node >/dev/null 2>&1 || skip "sem node"
  B=$(path_com node)
  printf 'touch\tm\n' > "$PADROES"
  run sh -c "printf '%s' '$(json_literal "\$(touch $MARCA.1); \`touch $MARCA.2\`; touch $MARCA.3 | touch $MARCA.4 && \$HOME")' | env -i PATH='$B' sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
  [[ "$output" != *"sem node nem python3"* ]]
  [ ! -e "$MARCA.1" ] && [ ! -e "$MARCA.2" ] && [ ! -e "$MARCA.3" ] && [ ! -e "$MARCA.4" ]
  run sh -c "printf '%s' '$(json_literal "\$(touch $MARCA.5); \`touch $MARCA.6\`")' | env -i PATH='$B' sh '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ ! -e "$MARCA.5" ] && [ ! -e "$MARCA.6" ]
}

@test "QA: SEGURANCA (leitor python3): o mesmo comando malicioso nao e executado nem expandido; bloqueio por padrao 'touch'" {
  command -v python3 >/dev/null 2>&1 || skip "sem python3"
  B=$(path_com python3)
  printf 'touch\tm\n' > "$PADROES"
  run sh -c "printf '%s' '$(json_literal "\$(touch $MARCA.1); \`touch $MARCA.2\`; touch $MARCA.3 | touch $MARCA.4 && \$HOME")' | env -i PATH='$B' sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
  [[ "$output" != *"sem node nem python3"* ]]
  [ ! -e "$MARCA.1" ] && [ ! -e "$MARCA.2" ] && [ ! -e "$MARCA.3" ] && [ ! -e "$MARCA.4" ]
  run sh -c "printf '%s' '$(json_literal "\$(touch $MARCA.5); \`touch $MARCA.6\`")' | env -i PATH='$B' sh '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ ! -e "$MARCA.5" ] && [ ! -e "$MARCA.6" ]
}

@test "QA: SEGURANCA: motivo e padrao com \cifrao-parenteses e crase no arquivo de padroes nao sao executados (node e python3)" {
  printf '$(touch %s.p)\tmotivo `touch %s.m`\n' "$MARCA" "$MARCA" > "$PADROES"
  for leitor in node python3; do
    command -v "$leitor" >/dev/null 2>&1 || continue
    B=$(path_com "$leitor")
    run sh -c "printf '%s' '$(json_literal "echo \$(touch $MARCA.p) x")' | env -i PATH='$B' sh '$SCRIPT' --padroes '$PADROES'"
    [ "$status" -eq 2 ]
    [[ "$output" == *'motivo `touch'* ]]
    [ ! -e "$MARCA.p" ] && [ ! -e "$MARCA.m" ]
  done
}

@test "QA: SEGURANCA: cwd com \cifrao-parenteses nao e expandido (git -C recebe o texto literal) e o push passa sem efeito colateral" {
  run sh -c "printf '%s' '$(json_literal 'git push' "\$(touch $MARCA.cwd)")' | sh '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ ! -e "$MARCA.cwd" ]
}

@test "QA: o JSON do hook inteiro (session_id, hook_event_name, tool_name, outros campos) nao atrapalha a leitura" {
  run sh -c "printf '%s' '{\"session_id\":\"s\",\"transcript_path\":\"/t\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npx vitest run\",\"description\":\"x\",\"timeout\":5},\"cwd\":\"/\"}' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
}

@test "QA: comando longo (200 KB) com o padrao no fim e lido inteiro" {
  J="$BATS_TEST_TMPDIR/j.json"
  { printf '{"tool_input":{"command":"'; head -c 200000 /dev/zero | tr '\0' 'a'; printf ' npm run verify"}}'; } > "$J"
  run sh "$SCRIPT" --padroes "$PADROES" < "$J"
  [ "$status" -eq 2 ]
}

@test "QA: o guarda roda em dash e em bash com o mesmo resultado" {
  run sh -c "printf '%s' '$(json_literal 'npx vitest run')' | dash '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
  run sh -c "printf '%s' '$(json_literal 'npx vitest run')' | bash '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
}
