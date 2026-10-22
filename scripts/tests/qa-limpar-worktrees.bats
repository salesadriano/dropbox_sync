#!/usr/bin/env bats
# Suite independente do QA Expert para scripts/limpar-worktrees.sh.
# Complementa scripts/tests/limpar-worktrees.bats: --raiz num worktree que nao e o principal, squash sem gh,
# gh que falha, docker que falha no --executar, dry-run sem efeito em .git/, worktree com nome com espaco.
# Validacao: docs/reviews/2026-10-15-0914-skills-dos-mods-validacao-qa.md

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../limpar-worktrees.sh"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  REMOTO="$BATS_TEST_TMPDIR/remoto.git"
  RAIZ="$BATS_TEST_TMPDIR/repo"
  PASTA="$BATS_TEST_TMPDIR/repo.worktrees"
  ENTRADAS="$RAIZ/.github/agents/memoria/entradas"
  git init -q --bare "$REMOTO"
  git init -q -b main "$RAIZ"
  git -C "$RAIZ" remote add origin "$REMOTO"
  mkdir -p "$ENTRADAS"
  printf -- '---\nid: 2026-09-19-1124-branch-principal\ntipo: decisao\ntitulo: Branch principal do projeto e `main`\nstatus: ativa\n---\n' > "$ENTRADAS/2026-09-19-1124-branch-principal.md"
  echo base > "$RAIZ/a.txt"; git -C "$RAIZ" add -A; git -C "$RAIZ" commit -qm base
  git -C "$RAIZ" push -q -u origin main
  mkdir -p "$PASTA"
}

worktree_mesclado() {  # $1 = branch, $2 = diretorio
  git -C "$RAIZ" branch "$1" main
  git -C "$RAIZ" worktree add -q "$PASTA/$2" "$1"
  echo x > "$PASTA/$2/$2.txt"; git -C "$PASTA/$2" add -A; git -C "$PASTA/$2" commit -qm "$2"
  git -C "$RAIZ" merge -q --no-ff "$1" -m "merge $1"
  git -C "$RAIZ" push -q origin main
}

worktree_nao_mesclado() {
  git -C "$RAIZ" branch "$1" main
  git -C "$RAIZ" worktree add -q "$PASTA/$2" "$1"
  echo y > "$PASTA/$2/y.txt"; git -C "$PASTA/$2" add -A; git -C "$PASTA/$2" commit -qm y
}

# Squash real: o conteudo da branch entra em main num commit novo; a branch NAO e ancestral de main.
worktree_squash() {
  worktree_nao_mesclado "$1" "$2"
  git -C "$RAIZ" merge -q --squash "$1"
  git -C "$RAIZ" commit -qm "squash $1"
  git -C "$RAIZ" push -q origin main
}

# Assinatura de .git/: nome e conteudo de todo arquivo regular, FORA do que o fetch de <remoto>/<principal>
# escreve por desenho (FETCH_HEAD e refs/remotes/). Esses dois sao conferidos a parte no caso do dry-run.
assinatura_git() {
  (cd "$RAIZ/.git" && find . -type f ! -name FETCH_HEAD ! -path './refs/remotes/*' | LC_ALL=C sort | while IFS= read -r f; do printf '%s ' "$f"; sha256sum < "$f"; done | sha256sum)
}

@test "QA: squash mesclado em main, sem gh (--sem-gh): fica PENDENTE e nao e tocado nem no --executar" {
  worktree_squash feature/squash feature-squash
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDENTE (branch feature/squash nao mesclada em origin/main): feature-squash"* ]]
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDENTE (branch feature/squash nao mesclada em origin/main): feature-squash"* ]]
  [[ "$output" == *"resumo: 0 removido(s), 1 pendente(s), 0 falha(s)."* ]]
  [ -d "$PASTA/feature-squash" ]
  git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/squash
}

@test "QA: squash com gh ausente no PATH, gh que falha (exit 1) e gh que responde sha diferente: PENDENTE nos tres" {
  worktree_squash feature/squash feature-squash
  B="$BATS_TEST_TMPDIR/bin"; mkdir -p "$B"
  for b in sh git sed awk grep cat printf basename dirname rm tail head cut tr wc sort; do ln -sf "$(command -v "$b")" "$B/$b"; done
  run env PATH="$B" sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDENTE (branch feature/squash nao mesclada"* ]]
  printf '#!/bin/sh\necho "gh: auth required" >&2\nexit 1\n' > "$B/gh"; chmod +x "$B/gh"
  run env PATH="$B" sh "$SCRIPT" --raiz "$RAIZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDENTE (branch feature/squash nao mesclada"* ]]
  printf '#!/bin/sh\necho 0000000000000000000000000000000000000000\n' > "$B/gh"
  run env PATH="$B" sh "$SCRIPT" --raiz "$RAIZ" --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDENTE (branch feature/squash nao mesclada"* ]]
  [ -d "$PASTA/feature-squash" ]
}

@test "QA: gh que devolve o sha com cifrao-parenteses ou crase nao e expandido: PENDENTE e nenhuma marca criada" {
  worktree_squash feature/squash feature-squash
  B="$BATS_TEST_TMPDIR/bin"; mkdir -p "$B"
  MARCA="$BATS_TEST_TMPDIR/marca"
  printf '#!/bin/sh\necho "\\$(touch %s)"\n' "$MARCA" > "$B/gh"; chmod +x "$B/gh"
  PATH="$B:$PATH" run sh "$SCRIPT" --raiz "$RAIZ" --executar
  [ "$status" -eq 0 ]
  [ ! -e "$MARCA" ]
  [[ "$output" == *"PENDENTE (branch feature/squash nao mesclada"* ]]
  [ -d "$PASTA/feature-squash" ]
}

@test "QA: --executar com docker que falha (exit 1 sem apagar): FALHOU, exit 1, worktree e branch intactos, registro inteiro" {
  worktree_mesclado feature/ok feature-ok
  mkdir -p "$PASTA/feature-ok/node_modules/pkg"; echo lib > "$PASTA/feature-ok/node_modules/pkg/i.js"
  chmod 555 "$PASTA/feature-ok/node_modules"
  B="$BATS_TEST_TMPDIR/bin"; mkdir -p "$B"
  printf '#!/bin/sh\necho "docker: daemon not running" >&2\nexit 1\n' > "$B/docker"; chmod +x "$B/docker"
  PATH="$B:$PATH" run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --executar
  chmod -R u+w "$PASTA/feature-ok/node_modules"
  [ "$status" -eq 1 ]
  [[ "$output" == *"apagando via docker"* ]]
  [[ "$output" == *"FALHOU (node_modules nao removivel; confira permissoes ou docker): feature-ok"* ]]
  [[ "$output" == *"resumo: 0 removido(s), 0 pendente(s), 1 falha(s)."* ]]
  [ -d "$PASTA/feature-ok" ]
  [ -d "$RAIZ/.git/worktrees/feature-ok" ]
  git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/ok
}

@test "QA: --executar com docker que diz que apagou mas nao apagou: FALHOU e nada e removido" {
  worktree_mesclado feature/ok feature-ok
  mkdir -p "$PASTA/feature-ok/node_modules/pkg"; echo lib > "$PASTA/feature-ok/node_modules/pkg/i.js"
  chmod 555 "$PASTA/feature-ok/node_modules"
  B="$BATS_TEST_TMPDIR/bin"; mkdir -p "$B"
  printf '#!/bin/sh\nexit 0\n' > "$B/docker"; chmod +x "$B/docker"
  PATH="$B:$PATH" run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --executar
  chmod -R u+w "$PASTA/feature-ok/node_modules"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FALHOU (node_modules nao removivel"* ]]
  [ -d "$PASTA/feature-ok" ]
  git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/ok
}

@test "QA: --executar nunca remove worktree sujo: arquivo novo nao rastreado e alteracao staged contam como sujo" {
  worktree_mesclado feature/novo feature-novo
  echo solto > "$PASTA/feature-novo/solto.txt"
  worktree_mesclado feature/staged feature-staged
  echo mudou >> "$PASTA/feature-staged/x.txt"; git -C "$PASTA/feature-staged" add -A
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDENTE (1 alteracao(oes) nao commitada(s); branch feature/novo): feature-novo"* ]]
  [[ "$output" == *"PENDENTE (1 alteracao(oes) nao commitada(s); branch feature/staged): feature-staged"* ]]
  [[ "$output" != *"REMOVIDO"* ]]
  [ -d "$PASTA/feature-novo" ] && [ -d "$PASTA/feature-staged" ]
  git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/novo
  git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/staged
}

@test "QA: dry-run nao altera .git/ (refs locais, HEAD, worktrees/, config, objetos) e so o fetch escreve FETCH_HEAD" {
  worktree_mesclado feature/ok feature-ok
  worktree_nao_mesclado feature/aberta feature-aberta
  git -C "$RAIZ" worktree add -q --detach "$PASTA/solto" main
  rm -rf "$PASTA/feature-aberta"   # registro sem diretorio: o dry-run nao pode podar
  rm -f "$RAIZ/.git/FETCH_HEAD"
  antes=$(assinatura_git)
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh
  [ "$status" -eq 0 ]
  depois=$(assinatura_git)
  [ "$antes" = "$depois" ]
  [ -d "$RAIZ/.git/worktrees/feature-aberta" ]
  # ACHADO QA-SK (documental): a referencia diz "nao toca em nada, nem em .git/", mas o fetch do dry-run escreve FETCH_HEAD.
  [ -f "$RAIZ/.git/FETCH_HEAD" ]
}

@test "QA: --raiz apontando para um worktree de demanda (nao o principal) nao acha a pasta de worktrees e nao toca em nada" {
  worktree_mesclado feature/ok feature-ok
  worktree_nao_mesclado feature/aberta feature-aberta
  run sh "$SCRIPT" --raiz "$PASTA/feature-aberta" --sem-gh --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"nenhum worktree: $PASTA/feature-aberta.worktrees nao existe"* ]]
  [ -d "$PASTA/feature-ok" ]
  git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/ok
}

@test "QA: rodando de dentro de um worktree, sem --raiz, o principal e o primeiro da lista: a propria demanda e removida quando mesclada" {
  worktree_mesclado feature/ok feature-ok
  worktree_mesclado feature/eu feature-eu
  cd "$PASTA/feature-eu"
  run sh "$SCRIPT" --sem-gh --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOVIDO (branch feature/ok apagada): feature-ok"* ]]
  [[ "$output" == *"REMOVIDO (branch feature/eu apagada): feature-eu"* ]]
  [ ! -e "$PASTA/feature-ok" ]
}

@test "QA: --remoto inexistente sai com 2 sem tocar em nada" {
  worktree_mesclado feature/ok feature-ok
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --remoto upstream --executar
  [ "$status" -eq 2 ]
  [[ "$output" == *"upstream/main nao existe localmente"* ]]
  [ -d "$PASTA/feature-ok" ]
}

@test "QA: worktree cujo diretorio tem espaco no nome e tratado inteiro (REMOVERIA e REMOVIDO)" {
  worktree_mesclado feature/espaco "feature com espaco"
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOVERIA (branch feature/espaco mesclada, worktree limpo): feature com espaco"* ]]
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOVIDO (branch feature/espaco apagada): feature com espaco"* ]]
  [ ! -e "$PASTA/feature com espaco" ]
}

@test "QA: entrada branch-principal substituida e ignorada mesmo sendo a mais recente; a ativa antiga declara a branch" {
  printf -- '---\nid: 2026-10-01-0900-branch-principal\ntipo: decisao\ntitulo: Branch principal do projeto e `develop`\nstatus: substituida\n---\n' > "$ENTRADAS/2026-10-01-0900-branch-principal.md"
  worktree_mesclado feature/ok feature-ok
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"mesclado em origin/main =="* ]]
}

@test "QA: fetch que falha (remoto apagado) vira AVISO e o ultimo estado conhecido decide; exit 0" {
  worktree_mesclado feature/ok feature-ok
  rm -rf "$REMOTO"
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"AVISO: fetch de origin/main falhou"* ]]
  [[ "$output" == *"REMOVERIA (branch feature/ok mesclada, worktree limpo): feature-ok"* ]]
}
