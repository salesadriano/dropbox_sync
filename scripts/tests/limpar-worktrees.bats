#!/usr/bin/env bats
# Testes de scripts/limpar-worktrees.sh: so remove worktree limpo de branch mesclada; o resto e PENDENTE e intocado.
# Remoto bare local, worktrees reais; `gh` e `docker` so por stub no PATH, quando o caso exige.

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
  entrada_principal "$ENTRADAS" main
  echo base > "$RAIZ/a.txt"; git -C "$RAIZ" add -A; git -C "$RAIZ" commit -qm base
  git -C "$RAIZ" push -q -u origin main
  mkdir -p "$PASTA"
}

entrada_principal() {  # $1 = diretorio de entradas, $2 = branch
  printf -- '---\nid: 2026-09-19-1124-branch-principal\ntipo: decisao\ntitulo: Branch principal do projeto e `%s`\nstatus: ativa\n---\n' "$2" > "$1/2026-09-19-1124-branch-principal.md"
}

# branch mesclada em main (e enviada) com worktree limpo
worktree_mesclado() {
  git -C "$RAIZ" branch "$1" main
  git -C "$RAIZ" worktree add -q "$PASTA/$2" "$1"
  echo x > "$PASTA/$2/x.txt"; git -C "$PASTA/$2" add -A; git -C "$PASTA/$2" commit -qm x
  git -C "$RAIZ" merge -q --no-ff "$1" -m "merge $1"
  git -C "$RAIZ" push -q origin main
}

worktree_nao_mesclado() {
  git -C "$RAIZ" branch "$1" main
  git -C "$RAIZ" worktree add -q "$PASTA/$2" "$1"
  echo y > "$PASTA/$2/y.txt"; git -C "$PASTA/$2" add -A; git -C "$PASTA/$2" commit -qm y
}

@test "dry-run e o padrao: lista REMOVERIA e PENDENTE sem tocar em nada" {
  worktree_mesclado feature/ok feature-ok
  worktree_nao_mesclado feature/aberta feature-aberta
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOVERIA (branch feature/ok mesclada, worktree limpo): feature-ok"* ]]
  [[ "$output" == *"PENDENTE (branch feature/aberta nao mesclada em origin/main): feature-aberta"* ]]
  [[ "$output" == *"resumo: 1 a remover, 1 pendente(s). Nada foi tocado"* ]]
  [ -d "$PASTA/feature-ok" ]
  git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/ok
}

@test "--executar remove o worktree mesclado e limpo e apaga a branch local; o nao mesclado fica" {
  worktree_mesclado feature/ok feature-ok
  worktree_nao_mesclado feature/aberta feature-aberta
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOVIDO (branch feature/ok apagada): feature-ok"* ]]
  [[ "$output" == *"resumo: 1 removido(s), 1 pendente(s), 0 falha(s)."* ]]
  [ ! -e "$PASTA/feature-ok" ]
  run git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/ok
  [ "$status" -ne 0 ]
  [ -d "$PASTA/feature-aberta" ]
  git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/aberta
}

@test "worktree com alteracao nao commitada e PENDENTE mesmo com branch mesclada, e nao e tocado" {
  worktree_mesclado feature/ok feature-ok
  echo sujo >> "$PASTA/feature-ok/x.txt"
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDENTE (1 alteracao(oes) nao commitada(s); branch feature/ok): feature-ok"* ]]
  [ -d "$PASTA/feature-ok" ]
  git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/ok
}

@test "node_modules nao conta como alteracao" {
  worktree_mesclado feature/ok feature-ok
  mkdir -p "$PASTA/feature-ok/modulo/node_modules/pkg" "$PASTA/feature-ok/node_modules"
  echo lib > "$PASTA/feature-ok/modulo/node_modules/pkg/i.js"
  echo lib > "$PASTA/feature-ok/node_modules/j.js"
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOVERIA (branch feature/ok mesclada, worktree limpo): feature-ok"* ]]
}

@test "--executar com node_modules nao rastreado: apaga por rm e remove o worktree" {
  worktree_mesclado feature/ok feature-ok
  mkdir -p "$PASTA/feature-ok/modulo/node_modules/pkg"
  echo lib > "$PASTA/feature-ok/modulo/node_modules/pkg/i.js"
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --sem-docker --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOVIDO (branch feature/ok apagada): feature-ok"* ]]
  [ ! -e "$PASTA/feature-ok" ]
}

@test "node_modules IGNORADO e apagado antes do remove: sem registro orfao" {
  git -C "$RAIZ" branch feature/ok main
  git -C "$RAIZ" worktree add -q "$PASTA/feature-ok" feature/ok
  printf 'node_modules/\n' > "$PASTA/feature-ok/.gitignore"
  git -C "$PASTA/feature-ok" add -A; git -C "$PASTA/feature-ok" commit -qm ignore
  git -C "$RAIZ" merge -q --no-ff feature/ok -m "merge feature/ok"; git -C "$RAIZ" push -q origin main
  mkdir -p "$PASTA/feature-ok/modulo/node_modules/pkg"; echo lib > "$PASTA/feature-ok/modulo/node_modules/pkg/i.js"
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --sem-docker --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOVIDO (branch feature/ok apagada): feature-ok"* ]]
  [ ! -e "$PASTA/feature-ok" ]
  [ ! -e "$RAIZ/.git/worktrees/feature-ok" ]
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh
  [[ "$output" != *"feature-ok"* ]]
}

@test "rm que falha no node_modules cai no docker (stub) e so remove se o diretorio sumiu" {
  worktree_mesclado feature/ok feature-ok
  mkdir -p "$PASTA/feature-ok/node_modules/pkg"; echo lib > "$PASTA/feature-ok/node_modules/pkg/i.js"
  chmod 555 "$PASTA/feature-ok/node_modules"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/docker" <<'EOF2'
#!/bin/sh
# stub: `docker run --rm -v <pai>:/wt alpine rm -rf /wt/<nome>` apaga no host o mesmo caminho
pai=""; alvo=""
while [ $# -gt 0 ]; do
  case "$1" in -v) pai=${2%%:*}; shift 2 ;; /wt/*) alvo=${1#/wt/}; shift ;; *) shift ;; esac
done
chmod -R u+w "$pai/$alvo" 2>/dev/null; rm -rf "$pai/$alvo"
EOF2
  chmod +x "$BATS_TEST_TMPDIR/bin/docker"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"apagando via docker"* ]]
  [[ "$output" == *"REMOVIDO (branch feature/ok apagada): feature-ok"* ]]
  [ ! -e "$PASTA/feature-ok" ]
}

@test "rm que falha e sem docker: FALHOU, worktree intocado e exit 1" {
  worktree_mesclado feature/ok feature-ok
  mkdir -p "$PASTA/feature-ok/node_modules/pkg"; echo lib > "$PASTA/feature-ok/node_modules/pkg/i.js"
  chmod 555 "$PASTA/feature-ok/node_modules"
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --sem-docker --executar
  chmod -R u+w "$PASTA/feature-ok/node_modules"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FALHOU (node_modules nao removivel; confira permissoes ou docker): feature-ok"* ]]
  [[ "$output" == *"resumo: 0 removido(s), 0 pendente(s), 1 falha(s)."* ]]
  [ -d "$PASTA/feature-ok" ]
  git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/ok
}

@test "HEAD destacado e diretorio que nao e worktree sao PENDENTE" {
  git -C "$RAIZ" worktree add -q --detach "$PASTA/solto" main
  mkdir -p "$PASTA/so-logs"; echo log > "$PASTA/so-logs/a.log"
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDENTE (HEAD destacado em"*"): solto"* ]]
  [[ "$output" == *"PENDENTE (nao e worktree registrado): so-logs"* ]]
  [[ "$output" != *"REMOVIDO"* ]]
  [ -d "$PASTA/solto" ]
  [ -d "$PASTA/so-logs" ]
}

@test "worktree na branch principal e PENDENTE e nao e tocado" {
  git -C "$RAIZ" checkout -q --detach   # a mesma branch nao pode estar em dois worktrees
  git -C "$RAIZ" worktree add -q "$PASTA/outro-main" main
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDENTE (branch principal main): outro-main"* ]]
  [ -d "$PASTA/outro-main" ]
}

@test "worktree travado (git worktree lock) e PENDENTE e nao e tocado, mesmo mesclado e limpo" {
  worktree_mesclado feature/ok feature-ok
  git -C "$RAIZ" worktree lock "$PASTA/feature-ok"
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDENTE (worktree travado por git worktree lock; branch feature/ok): feature-ok"* ]]
  [ -d "$PASTA/feature-ok" ]
  git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/ok
}

@test "a branch principal vem da entrada branch-principal; --principal a substitui" {
  worktree_nao_mesclado feature/aberta feature-aberta
  git -C "$RAIZ" branch outra feature/aberta
  git -C "$RAIZ" push -q origin outra
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --principal outra
  [ "$status" -eq 0 ]
  [[ "$output" == *"mesclado em origin/outra =="* ]]
  [[ "$output" == *"REMOVERIA (branch feature/aberta mesclada, worktree limpo): feature-aberta"* ]]
}

@test "--entradas aponta o diretorio de entradas explicitamente" {
  rm -r "$ENTRADAS"
  mkdir -p "$BATS_TEST_TMPDIR/entradas-fora"
  entrada_principal "$BATS_TEST_TMPDIR/entradas-fora" main
  worktree_mesclado feature/ok feature-ok
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh --entradas "$BATS_TEST_TMPDIR/entradas-fora"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mesclado em origin/main =="* ]]
  [[ "$output" == *"REMOVERIA (branch feature/ok mesclada, worktree limpo): feature-ok"* ]]
}

@test "sem .github/agents, cai no layout .claude/ai_team/memoria/entradas" {
  rm -r "$RAIZ/.github"
  mkdir -p "$RAIZ/.claude/ai_team/memoria/entradas"
  entrada_principal "$RAIZ/.claude/ai_team/memoria/entradas" main
  worktree_mesclado feature/ok feature-ok
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"mesclado em origin/main =="* ]]
  [[ "$output" == *"REMOVERIA (branch feature/ok mesclada, worktree limpo): feature-ok"* ]]
}

@test "sem entrada branch-principal e sem --principal, sai com 2" {
  rm "$ENTRADAS/2026-09-19-1124-branch-principal.md"
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh
  [ "$status" -eq 2 ]
  [[ "$output" == *"branch principal nao declarada"* ]]
}

@test "sem pasta de worktrees, informa e sai com 0" {
  rmdir "$PASTA"
  run sh "$SCRIPT" --raiz "$RAIZ" --sem-gh
  [ "$status" -eq 0 ]
  [[ "$output" == *"nenhum worktree: $PASTA nao existe"* ]]
}

@test "argumento desconhecido e opcao sem valor saem com 2" {
  run sh "$SCRIPT" --foo
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --raiz
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --raiz "$RAIZ" --principal
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --raiz "$RAIZ" --entradas
  [ "$status" -eq 2 ]
}

@test "squash com PR MERGED no mesmo sha: --executar remove o worktree e apaga a branch; commit local posterior fica PENDENTE e intacto" {
  worktree_nao_mesclado feature/squash feature-squash
  worktree_nao_mesclado feature/depois feature-depois
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  for b in squash depois; do
    sha=$(git -C "$RAIZ" rev-parse "feature/$b")
    printf '%s\n' "$sha" > "$BATS_TEST_TMPDIR/sha-$b"
  done
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<EOF2
#!/bin/sh
case "\$*" in
  *--head\ feature/squash*) cat "$BATS_TEST_TMPDIR/sha-squash" ;;
  *--head\ feature/depois*) cat "$BATS_TEST_TMPDIR/sha-depois" ;;
esac
EOF2
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  echo z > "$PASTA/feature-depois/z.txt"; git -C "$PASTA/feature-depois" add -A; git -C "$PASTA/feature-depois" commit -qm z
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run sh "$SCRIPT" --raiz "$RAIZ" --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOVIDO (branch feature/squash apagada): feature-squash"* ]]
  [[ "$output" == *"PENDENTE (branch feature/depois nao mesclada em origin/main): feature-depois"* ]]
  [[ "$output" == *"resumo: 1 removido(s), 1 pendente(s), 0 falha(s)."* ]]
  [ ! -e "$PASTA/feature-squash" ]
  [ -z "$(git -C "$RAIZ" branch --list feature/squash)" ]
  [ -d "$PASTA/feature-depois" ]
  git -C "$RAIZ" show-ref --verify --quiet refs/heads/feature/depois
}

# como worktree_mesclado, com um arquivo proprio por branch (varias branches mescladas na mesma main sem conflito)
worktree_mesclado_em() {  # $1 = branch, $2 = diretorio
  git -C "$RAIZ" branch "$1" main
  git -C "$RAIZ" worktree add -q "$PASTA/$2" "$1"
  echo x > "$PASTA/$2/$2.txt"; git -C "$PASTA/$2" add -A; git -C "$PASTA/$2" commit -qm "$2"
  git -C "$RAIZ" merge -q --no-ff "$1" -m "merge $1"
  git -C "$RAIZ" push -q origin main
}

@test "com gh disponivel e sem --sem-gh, branch ancestral nao consulta o gh; no mesmo --executar, so o mesclado limpo sai e o resumo agrega o resto" {
  worktree_mesclado_em feature/ok feature-ok
  worktree_mesclado_em feature/suja feature-suja
  worktree_mesclado_em feature/presa feature-presa
  worktree_nao_mesclado feature/aberta feature-aberta
  echo lixo > "$PASTA/feature-suja/lixo.txt"
  git -C "$RAIZ" worktree lock "$PASTA/feature-presa"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<EOF2
#!/bin/sh
echo "\$*" >> "$BATS_TEST_TMPDIR/gh.log"
EOF2
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run sh "$SCRIPT" --raiz "$RAIZ" --executar
  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOVIDO (branch feature/ok apagada): feature-ok"* ]]
  [[ "$output" == *"PENDENTE (1 alteracao(oes) nao commitada(s); branch feature/suja): feature-suja"* ]]
  [[ "$output" == *"PENDENTE (worktree travado por git worktree lock; branch feature/presa): feature-presa"* ]]
  [[ "$output" == *"PENDENTE (branch feature/aberta nao mesclada em origin/main): feature-aberta"* ]]
  [[ "$output" == *"resumo: 1 removido(s), 3 pendente(s), 0 falha(s)."* ]]
  [ ! -e "$PASTA/feature-ok" ]
  [ -d "$PASTA/feature-suja" ] && [ -d "$PASTA/feature-presa" ] && [ -d "$PASTA/feature-aberta" ]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/gh.log")" -eq 1 ]
  grep -q -- '--head feature/aberta' "$BATS_TEST_TMPDIR/gh.log"
}

# ---------- pendentes (auditoria 2026-11-08, secao 7) ----------

@test "pendente: git worktree remove que falha cai na recuperacao e conclui REMOVIDO; recuperacao que tambem falha e FALHOU" {
  skip "pendente: provar os dois desfechos do caminho apagar + worktree prune"
}

@test "pendente: git branch -D que falha avisa branch local nao apagada e o worktree ainda conta como REMOVIDO com exit 0" {
  skip "pendente: provar o AVISO e o exit 0 quando a branch ja foi apagada"
}
