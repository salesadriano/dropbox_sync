#!/usr/bin/env sh
# Resumo de estado do repositorio para o hook SessionStart do Claude Code (skill governanca-por-hooks).
# Agnostico a projeto e a stack: imprime, uma fonte por linha, o que o protocolo manda conferir no
# inicio de toda demanda (branch principal declarada, remoto, branch atual, reservas ativas, PRs abertas,
# worktrees, alteracoes nao realizadas pelos agents) e, se pedido, um verificador do projeto em modo aviso.
#
# Uso: sh resumo-de-estado.sh [--raiz <dir>] [--entradas <dir>] [--verificador "<comando>"]
#   --raiz         raiz do repositorio (padrao: topo do repositorio git que contem este script, ou o pai
#                  do diretorio do script quando nao ha git)
#   --entradas     diretorio das entradas de memoria (padrao: <raiz>/.github/agents/memoria/entradas e,
#                  se nao existir, <raiz>/.claude/ai_team/memoria/entradas)
#   --verificador  comando do projeto executado a partir da raiz, por `sh -c`; falha vira AVISO, nunca erro.
#                  Vem da configuracao do proprio projeto (settings do hook), nunca de entrada externa.
#
# Exit sempre 0: o hook nunca impede a sessao de abrir. So uso invalido sai com 2. Nao usa `set -e`
# de proposito: cada fonte que falha vira uma linha "indisponivel (...)" e as seguintes continuam.
# O resumo so le e informa; nenhuma decisao e tomada aqui (a divergencia do detector vai ao solicitante).

raiz=""; entradas=""; verificador=""
while [ $# -gt 0 ]; do
  case "$1" in
    --raiz) [ $# -ge 2 ] || { echo "--raiz exige um valor" >&2; exit 2; }; raiz="$2"; shift 2 ;;
    --entradas) [ $# -ge 2 ] || { echo "--entradas exige um valor" >&2; exit 2; }; entradas="$2"; shift 2 ;;
    --verificador) [ $# -ge 2 ] || { echo "--verificador exige um valor" >&2; exit 2; }; verificador="$2"; shift 2 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$raiz" ]; then
  aqui=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || aqui="."
  raiz=$(git -C "$aqui" rev-parse --show-toplevel 2>/dev/null) || raiz=$(CDPATH='' cd -- "$aqui/.." 2>/dev/null && pwd) || raiz="."
fi
if [ -z "$entradas" ]; then
  entradas="$raiz/.github/agents/memoria/entradas"
  [ -d "$entradas" ] || entradas="$raiz/.claude/ai_team/memoria/entradas"
fi

echo "== resumo de estado (resumo-de-estado.sh) =="

if [ -d "$entradas" ]; then
  entrada=$(grep -l '^status: ativa' "$entradas"/????-??-??-????-branch-principal.md 2>/dev/null | tail -1)
  if [ -n "$entrada" ]; then
    # shellcheck disable=SC2016  # as crases sao literais: o titulo da entrada traz a branch entre crases
    principal=$(sed -n 's/^titulo: .*`\([^`]*\)`.*/\1/p' "$entrada" | head -1)
    echo "branch principal declarada: ${principal:-indisponivel (titulo sem crase em $(basename "$entrada"))}"
  else
    echo "branch principal declarada: indisponivel (nenhuma entrada branch-principal ativa; pedir a declaracao ao solicitante, regra 46)"
  fi
else
  echo "branch principal declarada: indisponivel (diretorio de entradas nao encontrado: $entradas)"
fi

remoto=$(git -C "$raiz" remote get-url origin 2>/dev/null)
echo "remoto (origin): ${remoto:-indisponivel}"
atual=$(git -C "$raiz" rev-parse --abbrev-ref HEAD 2>/dev/null)
echo "branch atual: ${atual:-indisponivel} ($(git -C "$raiz" rev-parse --short HEAD 2>/dev/null || echo '-'))"

if [ -d "$entradas" ]; then
  n=0; lista=""
  for r in "$entradas"/*.md; do
    [ -f "$r" ] || continue
    if grep -q '^tipo: reserva' "$r" 2>/dev/null && grep -q '^status: ativa' "$r" 2>/dev/null; then
      n=$((n + 1)); lista="$lista  $(basename "$r" .md): $(sed -n 's/^titulo: //p' "$r" | head -1)
"
    fi
  done
  if [ "$n" -gt 0 ]; then
    echo "reservas ativas de escopo: $n"
    printf '%s' "$lista"
  else
    echo "reservas ativas de escopo: nenhuma"
  fi
else
  echo "reservas ativas de escopo: indisponivel (diretorio de entradas nao encontrado)"
fi

if command -v gh >/dev/null 2>&1; then
  if prs=$(cd "$raiz" && gh pr list --state open --limit 30 --json number,title,headRefName,baseRefName,isDraft \
        --template '{{range .}}  #{{.number}} [{{.baseRefName}} <- {{.headRefName}}]{{if .isDraft}} (draft){{end}} {{.title}}{{"\n"}}{{end}}' 2>/dev/null); then
    echo "PRs abertas:"; if [ -n "$prs" ]; then printf '%s\n' "$prs"; else echo "  nenhuma"; fi
  else
    echo "PRs abertas: indisponivel (gh sem acesso; pedir a lista ao solicitante)"
  fi
else
  echo "PRs abertas: indisponivel (gh ausente; pedir a lista ao solicitante)"
fi

echo "worktrees:"
git -C "$raiz" worktree list 2>/dev/null | sed 's/^/  /' || echo "  indisponivel"

if [ -f "$raiz/scripts/alteracoes-externas.sh" ]; then
  saida=$(cd "$raiz" && sh scripts/alteracoes-externas.sh --detectar 2>&1); codigo=$?
  case "$codigo" in
    0) echo "alteracoes nao realizadas pelos agents: nenhuma" ;;
    3) echo "alteracoes nao realizadas pelos agents: DIVERGENCIA (exit 3): pergunte ao solicitante antes de tocar"
       printf '%s\n' "$saida" | sed 's/^/  /' ;;
    *) echo "alteracoes nao realizadas pelos agents: indisponivel (detector saiu com $codigo)"
       printf '%s\n' "$saida" | sed 's/^/  /' ;;
  esac
else
  echo "alteracoes nao realizadas pelos agents: indisponivel (scripts/alteracoes-externas.sh nao encontrado)"
fi

if [ -n "$verificador" ]; then
  saida=$(cd "$raiz" && sh -c -- "$verificador" 2>&1); codigo=$?
  if [ "$codigo" -eq 0 ]; then
    echo "verificador: ok ($(printf '%s\n' "$saida" | head -1))"
  else
    echo "verificador: AVISO (exit $codigo)"
    printf '%s\n' "$saida" | sed 's/^/  /'
  fi
else
  echo "verificador: nao configurado"
fi
exit 0
