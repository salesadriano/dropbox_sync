#!/usr/bin/env bats
# Testes de guarda-de-comandos.sh (hook PreToolUse do Bash): o que bloqueia, o que deixa passar.
# O JSON do hook e montado por `node` (ou `python3`) para que aspas, barras e quebras de linha cheguem
# ao guarda como o Claude Code as entrega. O guarda do `git push` procura `scripts/alteracoes-externas.sh`
# na raiz do repositorio do comando, entao esses casos usam um repositorio descartavel com um stub.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../guarda-de-comandos.sh"
  PADROES="$BATS_TEST_TMPDIR/padroes.txt"
  printf '# comentario\n\nnpm run verify\tnao roda no host; rode em conteiner\nvitest run\tsuite inteira local; so os itens afetados\ncypress run\tsuite E2E inteira local; passe --spec\n' > "$PADROES"
}

json_do_hook() {  # $1 = comando, $2 = cwd ("" omite o campo)
  if command -v node >/dev/null 2>&1; then
    node -e 'const [c, cwd] = process.argv.slice(1); const o = {session_id: "t", hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: c}}; if (cwd !== "") o.cwd = cwd; process.stdout.write(JSON.stringify(o))' "$1" "${2:-}"
  else
    python3 -I -c 'import json, sys; c, cwd = sys.argv[1], sys.argv[2]; o = {"tool_input": {"command": c}}; cwd and o.update(cwd=cwd); sys.stdout.write(json.dumps(o))' "$1" "${2:-}"
  fi
}

guarda() {  # $1 = comando, $2 = cwd (opcional); com o arquivo de padroes
  json_do_hook "$1" "${2:-}" | sh "$SCRIPT" --padroes "$PADROES"
}

guarda_sem_padroes() {  # $1 = comando, $2 = cwd (opcional)
  json_do_hook "$1" "${2:-}" | sh "$SCRIPT"
}

repo_com_stub() {  # $1 = exit do stub de alteracoes-externas.sh, $2 = texto que o stub imprime
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts/sub"
  git -C "$REPO" init -q
  printf '#!/usr/bin/env sh\n[ "$1" = --detectar ] || exit 2\necho "%s"\nexit %s\n' "$2" "$1" > "$REPO/scripts/alteracoes-externas.sh"
}

# --- forma do JSON e entrada vazia ----------------------------------------------------------------

@test "stdin vazio, JSON sem tool_input.command e JSON invalido deixam passar com exit 0" {
  run sh "$SCRIPT" --padroes "$PADROES" </dev/null
  [ "$status" -eq 0 ]
  run sh -c "printf '{\"tool_input\":{\"description\":\"x\"}}' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 0 ]
  run sh -c "printf '{nao e json' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 0 ]
  run sh -c "printf 'nao e json' | sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 0 ]
}

@test "comando com aspas duplas escapadas no JSON e lido inteiro e bloqueado" {
  run guarda 'echo "say \"ola\"" && npx vitest run'
  [ "$status" -eq 2 ]
  [[ "$output" == *"suite inteira local"* ]]
}

@test "comando multilinha e lido inteiro (o padrao na segunda linha e bloqueado)" {
  run guarda $'cd backend\nnpx vitest run'
  [ "$status" -eq 2 ]
}

@test "comando em subshell e bloqueado" {
  run guarda '(cd backend && npx vitest run)'
  [ "$status" -eq 2 ]
}

@test "cwd ausente no JSON nao derruba o guarda (bloqueia pelo comando, sem cwd)" {
  run guarda 'npx vitest run' ""
  [ "$status" -eq 2 ]
}

@test "o motivo do bloqueio vai para stderr com o prefixo BLOQUEADO, e stdout fica vazio" {
  saida=$(json_do_hook 'npx cypress run' | sh "$SCRIPT" --padroes "$PADROES" 2>/dev/null) || true
  [ -z "$saida" ]
  erro=$(json_do_hook 'npx cypress run' | sh "$SCRIPT" --padroes "$PADROES" 2>&1 >/dev/null) || true
  [[ "$erro" == "BLOQUEADO por guarda-de-comandos.sh: "* ]]
  [[ "$erro" == *"passe --spec"* ]]
}

# --- regra 2: arquivo de padroes -------------------------------------------------------------------

@test "comando que contem um padrao do arquivo e bloqueado com exit 2 e o motivo da linha" {
  run guarda "cd backend && npm run verify"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOQUEADO"* ]]
  [[ "$output" == *"npm run verify"* ]]
  [[ "$output" == *"nao roda no host"* ]]
}

@test "o mesmo padrao dentro de docker run, docker compose, docker-compose e docker exec passa" {
  run guarda "docker run --rm -v x:/repo -w /repo/backend node:24-alpine sh -c 'npm run verify'"
  [ "$status" -eq 0 ]
  run guarda 'docker compose -f docker-compose.e2e.yml run --rm web npx vitest run'
  [ "$status" -eq 0 ]
  run guarda 'docker-compose run --rm web npx cypress run'
  [ "$status" -eq 0 ]
  run guarda 'docker exec backend npm run verify'
  [ "$status" -eq 0 ]
}

@test "'docker ps' no mesmo comando NAO conta como conteiner: o padrao ao lado continua bloqueado" {
  run guarda 'docker ps; npx vitest run'
  [ "$status" -eq 2 ]
}

@test "comandos sem padrao passam" {
  run guarda "git status --short"
  [ "$status" -eq 0 ]
  run guarda "ls -la && cat README.md"
  [ "$status" -eq 0 ]
  run guarda "npm run typecheck"
  [ "$status" -eq 0 ]
}

@test "linhas vazias e comentarios do arquivo de padroes sao ignorados (um '#' no comando nao bloqueia)" {
  run guarda "echo '# comentario'"
  [ "$status" -eq 0 ]
  run guarda "echo ''"
  [ "$status" -eq 0 ]
}

@test "linha de padrao sem motivo (sem TAB) bloqueia com motivo generico" {
  printf 'rm -rf /\n' > "$PADROES"
  run guarda "rm -rf build"
  [ "$status" -eq 0 ]
  run guarda "rm -rf / "
  [ "$status" -eq 2 ]
  [[ "$output" == *"bloqueado pelo arquivo de padroes"* ]]
}

@test "o padrao e literal: metacaracteres de glob no arquivo nao viram curinga" {
  printf 'npm run *\tmotivo\n' > "$PADROES"
  run guarda "npm run typecheck"
  [ "$status" -eq 0 ]
  run guarda "npm run * && ls"
  [ "$status" -eq 2 ]
}

@test "limite declarado: o casamento e por substring, sem ler argumentos (arquivo de teste nao libera; citacao em grep bloqueia)" {
  run guarda 'npx vitest run src/x.spec.ts'
  [ "$status" -eq 2 ]
  run guarda 'grep -n "npm run verify" README.md'
  [ "$status" -eq 2 ]
  run guarda 'echo "docker run" && npm run verify'
  [ "$status" -eq 0 ]
}

@test "sem --padroes so a regra 1 vale: os padroes do exemplo passam" {
  run guarda_sem_padroes "cd backend && npm run verify"
  [ "$status" -eq 0 ]
  run guarda_sem_padroes "npx vitest run"
  [ "$status" -eq 0 ]
}

@test "--padroes apontando para arquivo ausente nao falha: so a regra 1 vale" {
  PADROES="$BATS_TEST_TMPDIR/nao-existe.txt"
  run guarda 'npx vitest run'
  [ "$status" -eq 0 ]
}

@test "arquivo de padroes vazio nao bloqueia nada" {
  : > "$PADROES"
  run guarda "npm run verify"
  [ "$status" -eq 0 ]
}

# --- regra 1: git push com alteracao nao realizada pelos agents -------------------------------------

@test "git push e bloqueado quando alteracoes-externas --detectar sai com 3, e a saida vai no motivo" {
  repo_com_stub 3 'ARQUIVO src/x.ts'
  run guarda "git push -u origin feature/x" "$REPO"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOQUEADO por guarda-de-comandos.sh"* ]]
  [[ "$output" == *"regra 48"* ]]
  [[ "$output" == *"ARQUIVO src/x.ts"* ]]
}

@test "git push passa quando --detectar sai com 0" {
  repo_com_stub 0 'nada'
  run guarda "git push -u origin feature/x" "$REPO"
  [ "$status" -eq 0 ]
}

@test "a regra 1 vale sem --padroes" {
  repo_com_stub 3 'ARQUIVO docs/x.md'
  run guarda_sem_padroes "git push" "$REPO"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ARQUIVO docs/x.md"* ]]
}

@test "git com opcoes antes do push (git -C dir push) tambem e verificado" {
  repo_com_stub 3 'ARQUIVO docs/x.md'
  run guarda "git -C $REPO push origin HEAD" "$REPO"
  [ "$status" -eq 2 ]
}

@test "git push --dry-run tambem e bloqueado com --detectar em 3 (o guarda nao distingue)" {
  repo_com_stub 3 'ARQUIVO docs/x.md'
  run guarda 'git push --dry-run origin HEAD' "$REPO"
  [ "$status" -eq 2 ]
}

@test "git push com cwd num subdiretorio do repositorio acha o script na raiz" {
  repo_com_stub 3 'ARQUIVO docs/y.md'
  run guarda 'git push' "$REPO/scripts/sub"
  [ "$status" -eq 2 ]
}

@test "--detectar saindo com codigo diferente de 3 (ex.: 1) deixa o push passar" {
  repo_com_stub 1 'falha interna'
  run guarda 'git push -u origin feature/x' "$REPO"
  [ "$status" -eq 0 ]
}

@test "git push fora de um repositorio git, ou em repositorio sem o detector, passa" {
  mkdir -p "$BATS_TEST_TMPDIR/fora"
  run guarda 'git push' "$BATS_TEST_TMPDIR/fora"
  [ "$status" -eq 0 ]
  SEM="$BATS_TEST_TMPDIR/sem-detector"; mkdir -p "$SEM"; git -C "$SEM" init -q
  run guarda 'git push' "$SEM"
  [ "$status" -eq 0 ]
}

@test "git push dentro de docker tambem e verificado (a isencao de conteiner e so da regra 2)" {
  repo_com_stub 3 'ARQUIVO src/x.ts'
  run guarda "docker run --rm -v x:/repo alpine git push" "$REPO"
  [ "$status" -eq 2 ]
}

@test "o comando nunca e executado nem expandido pelo guarda" {
  MARCA="$BATS_TEST_TMPDIR/marca"
  run guarda "touch $MARCA; \$(touch $MARCA.sub); \`touch $MARCA.crase\`"
  [ "$status" -eq 0 ]
  [ ! -e "$MARCA" ] && [ ! -e "$MARCA.sub" ] && [ ! -e "$MARCA.crase" ]
  printf 'x\t$(touch %s)\n' "$MARCA.motivo" > "$PADROES"
  run guarda "echo x"
  [ "$status" -eq 2 ]
  [ ! -e "$MARCA.motivo" ]
  [[ "$output" == *'$(touch'* ]]
}

# --- interpretes de JSON e argumentos ----------------------------------------------------------------

@test "sem node nem python3 no PATH o guarda avisa em stderr e libera (exit 0)" {
  B="$BATS_TEST_TMPDIR/bin"; mkdir -p "$B"
  for b in cat printf tr awk git sh; do ln -s "$(command -v "$b")" "$B/$b"; done
  run sh -c "printf '%s' '{\"tool_input\":{\"command\":\"npx vitest run\"}}' | env -i PATH='$B' sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sem node nem python3"* ]]
}

@test "so com python3 no PATH o guarda le o JSON e bloqueia" {
  command -v python3 >/dev/null 2>&1 || skip "sem python3 neste ambiente"
  B="$BATS_TEST_TMPDIR/bin"; mkdir -p "$B"
  for b in cat printf tr awk git sh python3; do ln -s "$(command -v "$b")" "$B/$b"; done
  run sh -c "printf '%s' '{\"tool_input\":{\"command\":\"npx vitest run\"}}' | env -i PATH='$B' sh '$SCRIPT' --padroes '$PADROES'"
  [ "$status" -eq 2 ]
}

@test "--padroes sem valor sai com 2; argumento desconhecido sai com 2" {
  run sh -c "printf '{}' | timeout 5 sh '$SCRIPT' --padroes"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--padroes exige um valor"* ]]
  run sh -c "printf '{}' | sh '$SCRIPT' --x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"argumento desconhecido: --x"* ]]
}

@test "o guarda nao traz os padroes do projeto de origem embutidos" {
  run ! grep -q -e 'vitest' -e 'cypress' -e 'npm run verify' -e 'web-campo' -e 'web-comando' "$SCRIPT"
}

# --- regra 3: suite completa registrada antes do push para a PR de integracao --------------------------

repo_com_suite() {  # $1 = branch inicial; cria repo com commit, detector em 0 e o suite-completa.sh real
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/scripts"
  git -C "$REPO" init -q -b "$1"
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m inicio
  printf '#!/usr/bin/env sh\nexit 0\n' > "$REPO/scripts/alteracoes-externas.sh"
  cp "$BATS_TEST_DIRNAME/../suite-completa.sh" "$REPO/scripts/suite-completa.sh"
}

gh_stub() {  # $1 = numero de PRs abertas que `gh pr list` devolve; grava as chamadas em $BATS_TEST_TMPDIR/gh.log
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env sh\necho "$@" >> "%s/gh.log"\necho %s\n' "$BATS_TEST_TMPDIR" "$1" > "$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

sem_gh() { mkdir -p "$BATS_TEST_TMPDIR/bin"; printf '#!/usr/bin/env sh\nexit 127\n' > "$BATS_TEST_TMPDIR/bin/gh"; chmod +x "$BATS_TEST_TMPDIR/bin/gh"; PATH="$BATS_TEST_TMPDIR/bin:$PATH"; }

@test "regra 3: push na branch main sem suite completa registrada e bloqueado, com o motivo do --conferir" {
  repo_com_suite main
  run guarda_sem_padroes "git push origin main" "$REPO"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Regra 8 de protocolo-tdd"* ]]
  [[ "$output" == *"sem registro da suite completa para o commit atual"* ]]
}

@test "regra 3: push na branch master tambem e verificado; com suite verde registrada para o HEAD, passa" {
  repo_com_suite master
  run guarda_sem_padroes "git push" "$REPO"
  [ "$status" -eq 2 ]
  (cd "$REPO" && sh scripts/suite-completa.sh -- true >/dev/null)
  run guarda_sem_padroes "git push" "$REPO"
  [ "$status" -eq 0 ]
}

@test "regra 3: registro de outro commit ou vermelho nao libera o push" {
  repo_com_suite main
  (cd "$REPO" && sh scripts/suite-completa.sh -- true >/dev/null)
  git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m novo
  run guarda_sem_padroes "git push" "$REPO"
  [ "$status" -eq 2 ]
  (cd "$REPO" && sh scripts/suite-completa.sh -- false >/dev/null 2>&1 || true)
  run guarda_sem_padroes "git push" "$REPO"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ficou vermelha"* ]]
}

@test "regra 3: push de branch de trabalho sem remoto nao consulta gh e passa (nao ha PR conhecida)" {
  repo_com_suite feature/x
  gh_stub 1
  run guarda_sem_padroes "git push -u origin feature/x" "$REPO"
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/gh.log" ]
}

@test "regra 3: branch de trabalho com remoto e PR aberta para main (gh) exige o registro; sem PR aberta, passa" {
  repo_com_suite feature/x
  git -C "$REPO" remote add origin git@example.invalid:x/y.git
  gh_stub 1
  run guarda_sem_padroes "git push" "$REPO"
  [ "$status" -eq 2 ]
  grep -q -- '--head feature/x --base main' "$BATS_TEST_TMPDIR/gh.log"
  rm -f "$BATS_TEST_TMPDIR/gh.log"; gh_stub 0
  run guarda_sem_padroes "git push" "$REPO"
  [ "$status" -eq 0 ]
  grep -q -- '--base master' "$BATS_TEST_TMPDIR/gh.log"
}

@test "regra 3: sem gh no PATH, branch de trabalho com remoto passa (so a branch de integracao e verificada)" {
  repo_com_suite feature/x
  git -C "$REPO" remote add origin git@example.invalid:x/y.git
  sem_gh
  run guarda_sem_padroes "git push" "$REPO"
  [ "$status" -eq 0 ]
}

@test "regra 3: gh pr create exige o registro em qualquer branch; com registro verde, passa" {
  repo_com_suite feature/x
  run guarda_sem_padroes "gh pr create --base main --title t --body b" "$REPO"
  [ "$status" -eq 2 ]
  (cd "$REPO" && sh scripts/suite-completa.sh -- true >/dev/null)
  run guarda_sem_padroes "gh pr create --base main --title t --body b" "$REPO"
  [ "$status" -eq 0 ]
}

@test "regra 3: a branch de integracao e a branch-principal declarada na memoria; main deixa de ser especial" {
  repo_com_suite trunk
  mkdir -p "$REPO/.github/agents/memoria/entradas"
  printf -- '---\nid: x\ntitulo: Branch principal declarada e `trunk`\nstatus: ativa\n---\n' > "$REPO/.github/agents/memoria/entradas/2026-01-01-0000-branch-principal.md"
  run guarda_sem_padroes "git push" "$REPO"
  [ "$status" -eq 2 ]
  git -C "$REPO" checkout -q -b main
  run guarda_sem_padroes "git push" "$REPO"
  [ "$status" -eq 0 ]
}

@test "regra 3: a regra 1 (detector) e avaliada antes e continua bloqueando sozinha" {
  repo_com_suite main
  printf '#!/usr/bin/env sh\necho ARQUIVO x\nexit 3\n' > "$REPO/scripts/alteracoes-externas.sh"
  run guarda_sem_padroes "git push" "$REPO"
  [ "$status" -eq 2 ]
  [[ "$output" == *"regra 48"* ]]
  [[ "$output" != *"Regra 8"* ]]
}

@test "regra 3: repositorio sem scripts/suite-completa.sh nao e afetado (regra opcional por adocao)" {
  repo_com_suite main
  rm "$REPO/scripts/suite-completa.sh"
  run guarda_sem_padroes "git push origin main" "$REPO"
  [ "$status" -eq 0 ]
}

@test "regra 3: HEAD destacado na branch de integracao nao quebra o guarda (sem branch, so gh decidiria)" {
  repo_com_suite main
  git -C "$REPO" checkout -q --detach
  run guarda_sem_padroes "git push origin HEAD:main" "$REPO"
  [ "$status" -eq 0 ]
}
