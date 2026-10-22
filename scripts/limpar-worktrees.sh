#!/usr/bin/env sh
# Limpeza dos worktrees de demanda no fechamento (regra 46: um worktree por demanda em `<raiz>.worktrees/`).
#
# Uso: sh scripts/limpar-worktrees.sh [--dry-run | --executar] [--raiz <checkout principal>]
#                                     [--principal <branch>] [--entradas <dir>] [--remoto <nome>]
#                                     [--sem-gh] [--sem-docker]
#
# Percorre `<raiz>.worktrees/` (diretorio irmao do checkout principal). A branch principal vem de
# `--principal` ou da entrada `branch-principal` ativa da memoria, lida em `--entradas <dir>` ou, por
# padrao, em `<raiz>/.github/agents/memoria/entradas` e, se nao existir, em
# `<raiz>/.claude/ai_team/memoria/entradas`. Sem nenhuma das duas, sai com 2.
#
# Um worktree so e REMOVIDO quando TODAS valem: e um worktree registrado no git; tem branch (HEAD nao
# destacado) que nao e a principal declarada; nao esta travado (`git worktree lock`); `git status
# --porcelain` esta vazio fora de `node_modules/`; e a branch esta mesclada em `<remoto>/<principal>`
# ou a sua PR consta como MERGED no `gh` (merge por squash) com o MESMO commit que o HEAD local.
# Tudo o mais e listado como PENDENTE e nunca tocado. `--dry-run` (padrao) so lista e nao muda nada
# alem do `FETCH_HEAD` do fetch de `<remoto>/<principal>`; `--executar` remove o worktree e apaga a
# branch local (`git branch -D`, porque a mescla ja foi provada). `node_modules` criados por conteiner
# pertencem a root e sao apagados ANTES do
# `git worktree remove`, por `rm -rf` ou, se o `rm` falhar por permissao, por
# `docker run --rm -v <wt>:/wt alpine rm -rf`.
# Saida: 0; 1 quando `--executar` nao conseguiu remover algo que deveria; 2 em argumento invalido.

set -eu

modo=dry-run; raiz=""; principal=""; entradas=""; remoto=origin; usar_gh=1; usar_docker=1
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) modo=dry-run; shift ;;
    --executar) modo=executar; shift ;;
    --raiz) [ $# -ge 2 ] || { echo "--raiz exige um valor" >&2; exit 2; }; raiz="$2"; shift 2 ;;
    --principal) [ $# -ge 2 ] || { echo "--principal exige um valor" >&2; exit 2; }; principal="$2"; shift 2 ;;
    --entradas) [ $# -ge 2 ] || { echo "--entradas exige um valor" >&2; exit 2; }; entradas="$2"; shift 2 ;;
    --remoto) [ $# -ge 2 ] || { echo "--remoto exige um valor" >&2; exit 2; }; remoto="$2"; shift 2 ;;
    --sem-gh) usar_gh=0; shift ;;
    --sem-docker) usar_docker=0; shift ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$raiz" ]; then
  raiz=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
  [ -n "$raiz" ] || { echo "nao estou num repositorio git; use --raiz" >&2; exit 2; }
fi
raiz=$(CDPATH='' cd -- "$raiz" && pwd) || exit 2

if [ -z "$principal" ]; then
  if [ -z "$entradas" ]; then
    entradas="$raiz/.github/agents/memoria/entradas"
    [ -d "$entradas" ] || entradas="$raiz/.claude/ai_team/memoria/entradas"
  fi
  entrada=$(grep -l '^status: ativa' "$entradas"/????-??-??-????-branch-principal.md 2>/dev/null | tail -n 1 || true)
  # shellcheck disable=SC2016 # crases literais do titulo da entrada, nao expansao
  [ -z "$entrada" ] || principal=$(sed -n 's/^titulo:[^`]*`\([^`]*\)`.*/\1/p' "$entrada" | head -n 1)
  [ -n "$principal" ] || { echo "branch principal nao declarada (entrada branch-principal ativa em $entradas); use --principal ou --entradas" >&2; exit 2; }
fi

pasta="$(dirname "$raiz")/$(basename "$raiz").worktrees"
echo "== limpar-worktrees ($modo): $pasta, mesclado em $remoto/$principal =="
[ -d "$pasta" ] || { echo "nenhum worktree: $pasta nao existe"; exit 0; }

git -C "$raiz" fetch --quiet "$remoto" "$principal" 2>/dev/null || echo "AVISO: fetch de $remoto/$principal falhou; usando o ultimo estado conhecido"
git -C "$raiz" rev-parse --verify --quiet "refs/remotes/$remoto/$principal" >/dev/null || { echo "$remoto/$principal nao existe localmente" >&2; exit 2; }
[ "$modo" != executar ] || git -C "$raiz" worktree prune 2>/dev/null || true
lista=$(git -C "$raiz" worktree list --porcelain)
registrados=$(printf '%s\n' "$lista" | sed -n 's/^worktree //p')

travado() {
  printf '%s\n' "$lista" | awk -v w="worktree $1" '$0==w{p=1;next} /^worktree /{p=0} p && /^locked/{f=1} END{exit !f}'
}

# Mesclada: contida em <remoto>/<principal>; ou (squash) PR MERGED pelo gh cujo head e o HEAD local da branch.
mesclada() {
  git -C "$raiz" merge-base --is-ancestor "$1" "refs/remotes/$remoto/$principal" 2>/dev/null && return 0
  [ "$usar_gh" -eq 1 ] && command -v gh >/dev/null 2>&1 || return 1
  repo=$(git -C "$raiz" remote get-url "$remoto" 2>/dev/null | sed -n 's#.*[:/]\([^/]*\)/\([^/]*\)$#\1/\2#p' | sed 's/\.git$//')
  [ -n "$repo" ] || return 1
  head_da_pr=$(cd "$raiz" && gh pr list --repo "$repo" --state merged --base "$principal" --head "$1" --limit 1 --json headRefOid --jq '.[0].headRefOid // empty' 2>/dev/null) || return 1
  [ -n "$head_da_pr" ] && [ "$head_da_pr" = "$(git -C "$raiz" rev-parse "$1" 2>/dev/null)" ]
}

# `rm -rf` do caminho; se falhar por permissao (arquivos de root criados por conteiner), docker alpine.
apagar() {
  rm -rf "$1" 2>/dev/null && [ ! -e "$1" ] && return 0
  [ "$usar_docker" -eq 1 ] && command -v docker >/dev/null 2>&1 || return 1
  echo "  arquivos de root em $1: apagando via docker (alpine rm -rf)"
  docker run --rm -v "$(dirname "$1")":/wt alpine rm -rf "/wt/$(basename "$1")" >/dev/null 2>&1 && [ ! -e "$1" ]
}

apagar_node_modules() {
  for nm in "$1"/node_modules "$1"/*/node_modules; do
    [ -d "$nm" ] || continue
    apagar "$nm" || return 1
  done
  return 0
}

removeria=0; removidos=0; pendentes=0; falhas=0
for wt in "$pasta"/*/; do
  wt=${wt%/}
  [ -e "$wt" ] || continue
  nome=$(basename "$wt")
  if ! printf '%s\n' "$registrados" | grep -qxF "$wt"; then
    echo "PENDENTE (nao e worktree registrado): $nome"; pendentes=$((pendentes + 1)); continue
  fi
  branch=$(git -C "$wt" symbolic-ref --short -q HEAD 2>/dev/null || true)
  if [ -z "$branch" ]; then
    echo "PENDENTE (HEAD destacado em $(git -C "$wt" rev-parse --short HEAD 2>/dev/null)): $nome"; pendentes=$((pendentes + 1)); continue
  fi
  if [ "$branch" = "$principal" ]; then
    echo "PENDENTE (branch principal $principal): $nome"; pendentes=$((pendentes + 1)); continue
  fi
  if travado "$wt"; then
    echo "PENDENTE (worktree travado por git worktree lock; branch $branch): $nome"; pendentes=$((pendentes + 1)); continue
  fi
  sujo=$(git -C "$wt" status --porcelain -uall 2>/dev/null | grep -c -v 'node_modules/' || true)
  if [ "$sujo" -gt 0 ]; then
    echo "PENDENTE ($sujo alteracao(oes) nao commitada(s); branch $branch): $nome"; pendentes=$((pendentes + 1)); continue
  fi
  if ! mesclada "$branch"; then
    echo "PENDENTE (branch $branch nao mesclada em $remoto/$principal): $nome"; pendentes=$((pendentes + 1)); continue
  fi
  if [ "$modo" = dry-run ]; then
    echo "REMOVERIA (branch $branch mesclada, worktree limpo): $nome"; removeria=$((removeria + 1)); continue
  fi
  # node_modules sai ANTES do remove: um remove que falha no meio apaga o registro e deixa o diretorio orfao.
  if ! apagar_node_modules "$wt"; then
    echo "FALHOU (node_modules nao removivel; confira permissoes ou docker): $nome"; falhas=$((falhas + 1)); continue
  fi
  if ! git -C "$raiz" worktree remove "$wt" >/dev/null 2>&1; then
    # O registro pode ja ter sido apagado pelo remove parcial: completa no disco e poda o registro.
    apagar "$wt" || { echo "FALHOU (git worktree remove e rm; confira permissoes): $nome"; falhas=$((falhas + 1)); continue; }
    git -C "$raiz" worktree prune 2>/dev/null || true
  fi
  git -C "$raiz" branch -D "$branch" >/dev/null 2>&1 || echo "  AVISO: branch local $branch nao apagada"
  echo "REMOVIDO (branch $branch apagada): $nome"; removidos=$((removidos + 1))
done

if [ "$modo" = dry-run ]; then
  echo "resumo: $removeria a remover, $pendentes pendente(s). Nada foi tocado; use --executar para agir."
else
  echo "resumo: $removidos removido(s), $pendentes pendente(s), $falhas falha(s)."
fi
[ "$falhas" -eq 0 ]
