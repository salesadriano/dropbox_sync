#!/usr/bin/env sh
# Sugere o porte da demanda (regra 40 do AGENTS.md) a partir do diff real, nao de juizo: P quando o diff
# de codigo cabe no limite e nenhum caminho tocado casa com um gatilho de M ou G; senao M ou G, com motivo.
# O porte sugerido e um piso que o Tech Lead pode subir com justificativa no log de prompt; descer exige
# justificativa (regra 40). O script so le; nunca altera a arvore.
#
# Uso (a partir de qualquer diretorio do worktree):
#   sh scripts/porte.sh                              # compara a arvore de trabalho com a base
#   sh scripts/porte.sh --base origin/develop        # base explicita (padrao: origin/<branch-principal declarada>,
#                                                    # senao origin/main ou origin/master, o que existir)
#   sh scripts/porte.sh --limite 50                  # linhas de codigo (adicoes + remocoes) que P admite; padrao 50
#   sh scripts/porte.sh --caminhos scripts/porte-caminhos.txt   # gatilhos do projeto (padrao: esse arquivo, se existir)
#   sh scripts/porte.sh --critico                    # defeito de alta criticidade declarado: minimo M
#
# Arquivo de gatilhos: linhas `porte<TAB>padrao<TAB>motivo`, porte M ou G, padrao no formato de `case` do sh
# (`*` casa qualquer trecho, inclusive `/`). Os gatilhos embutidos abaixo valem sempre; o arquivo acrescenta.
# Linhas de documentacao (`docs/`, `*.md`, entradas de memoria) nao contam como codigo, mas um `.md` que case
# com gatilho G (ex.: `*/AGENTS.md`) ainda sobe o porte. Entradas de memoria, logs de prompt e registros de
# entrega nunca casam gatilho: sao a trilha da demanda, nao o seu escopo.
#
# Saida, uma linha por fato:
#   base: <ref> @ <sha>
#   arquivos: <n> | linhas de codigo: <n> (limite <n>)
#   gatilho: <porte> <padrao> (<motivo>): <arquivo>      (uma por caminho que casou)
#   motivo: ...
#   porte: P | M | G
# Exit: 0 (porte impresso), 2 uso invalido ou base inexistente. Nao usa `set -e`: cada fonte que falha vira motivo.

base=""; limite=50; caminhos=""; critico=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || { echo "--base exige um valor" >&2; exit 2; }; base="$2"; shift 2 ;;
    --limite) [ $# -ge 2 ] || { echo "--limite exige um valor" >&2; exit 2; }; limite="$2"; shift 2 ;;
    --caminhos) [ $# -ge 2 ] || { echo "--caminhos exige um valor" >&2; exit 2; }; caminhos="$2"; shift 2 ;;
    --critico) critico=1; shift ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done
case "$limite" in ''|*[!0-9]*) echo "--limite exige um inteiro" >&2; exit 2 ;; esac

topo=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "fora de um repositorio git" >&2; exit 2; }
cd "$topo" || exit 2
[ -n "$caminhos" ] || { [ -f scripts/porte-caminhos.txt ] && caminhos=scripts/porte-caminhos.txt; }

if [ -z "$base" ]; then
  for e in .github/agents/memoria/entradas .claude/ai_team/memoria/entradas; do
    [ -d "$e" ] || continue
    entrada=$(grep -l '^status: ativa' "$e"/????-??-??-????-branch-principal.md 2>/dev/null | tail -1)
    [ -n "$entrada" ] || continue
    # shellcheck disable=SC2016
    principal=$(sed -n 's/^titulo: .*`\([^`]*\)`.*/\1/p' "$entrada" | head -1)
    if [ -n "$principal" ]; then
      if git rev-parse --verify -q "origin/$principal^{commit}" >/dev/null 2>&1; then base="origin/$principal"; else base="$principal"; fi
    fi
    break
  done
  if [ -z "$base" ]; then
    for c in origin/main origin/master main master; do
      git rev-parse --verify -q "$c" >/dev/null 2>&1 && { base="$c"; break; }
    done
  fi
fi
if [ -z "$base" ] || ! git rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1; then echo "base inexistente: ${base:-nenhuma encontrada}; informe --base" >&2; exit 2; fi
mb=$(git merge-base "$base" HEAD 2>/dev/null) || mb=$(git rev-parse "$base")
echo "base: $base @ $(git rev-parse --short "$mb")"

# Gatilhos embutidos (porte, padrao case, motivo). Agnosticos a stack; o projeto acrescenta os seus.
embutidos='M	*/migrations/*	schema ou migration
M	*/migration/*	schema ou migration
M	*migrate*	schema ou migration
M	*schema.prisma	schema
M	*/auth/*	autenticacao ou autorizacao
M	*guard*	autenticacao ou autorizacao
M	*/policies/*	autorizacao
M	*/.github/workflows/*	pipeline
M	.github/workflows/*	pipeline
M	*/package.json	dependencia
M	package.json	dependencia
M	*lock.yaml	dependencia
M	*lock.json	dependencia
M	*.lock	dependencia
M	*/pyproject.toml	dependencia
M	pyproject.toml	dependencia
M	*requirements*.txt	dependencia
M	*/go.mod	dependencia
M	go.mod	dependencia
M	*/Cargo.toml	dependencia
M	Cargo.toml	dependencia
M	*/composer.json	dependencia
M	composer.json	dependencia
M	*.csproj	dependencia
M	*/.env*	segredo ou configuracao sensivel
M	.env*	segredo ou configuracao sensivel
M	*openapi*	contrato publico
M	*swagger*	contrato publico
G	*/AGENTS.md	regra transversal do pacote
G	*/agents/*.agent.md	regra transversal do pacote
G	.claude/agents/*.md	persona
G	*/skills/*/SKILL.md	skill
G	*system-design*	System Design
G	*SYSTEM-DESIGN*	System Design
G	*design-system*	Design System'

gatilhos="$embutidos"
if [ -n "$caminhos" ]; then
  if [ -f "$caminhos" ]; then
    extra=$(grep -v '^[[:space:]]*#' "$caminhos" | grep -v '^[[:space:]]*$')
    [ -z "$extra" ] || gatilhos="$gatilhos
$extra"
  else
    echo "aviso: arquivo de gatilhos nao encontrado: $caminhos" >&2
  fi
fi

TAB=$(printf '\t')
arquivos=0; linhas=0; porte="P"
sobe() {  # $1 = porte alvo
  case "$1" in
    G) porte="G" ;;
    M) [ "$porte" = "G" ] || porte="M" ;;
  esac
}
# numstat da arvore de trabalho contra a base: inclui o que ainda nao foi commitado. Arquivo binario vem com `-`.
git diff --numstat "$mb" -- 2>/dev/null | while IFS="$TAB" read -r add del arq; do
  printf '%s\t%s\t%s\n' "$add" "$del" "$arq"
done > "${TMPDIR:-/tmp}/porte.$$"
# Arquivo novo ainda nao rastreado tambem e escopo da demanda (os agents criam arquivos): conta as linhas como adicao.
git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r novo; do
  [ -f "$novo" ] || continue
  n=$(grep -c '' "$novo" 2>/dev/null || echo 0)
  printf '%s\t0\t%s\n' "$n" "$novo"
done >> "${TMPDIR:-/tmp}/porte.$$"
trap 'rm -f "${TMPDIR:-/tmp}/porte.$$"' EXIT
while IFS="$TAB" read -r add del arq; do
  [ -n "$arq" ] || continue
  arquivos=$((arquivos + 1))
  doc=0
  case "$arq" in docs/*|*.md|*/memoria/entradas/*|*/memoria/historico/*) doc=1 ;; esac
  if [ "$doc" -eq 0 ]; then
    case "$add" in ''|-|*[!0-9]*) add=0 ;; esac
    case "$del" in ''|-|*[!0-9]*) del=0 ;; esac
    linhas=$((linhas + add + del))
  fi
  case "$arq" in */memoria/entradas/*|*/memoria/historico/*|docs/prompts/*|docs/reviews/*) continue ;; esac
  printf '%s\n' "$gatilhos" | while IFS="$TAB" read -r gp gpad gmot; do
    [ -n "$gpad" ] || continue
    case "$gp" in M|G) ;; *) continue ;; esac
    # shellcheck disable=SC2254  # o padrao vem do arquivo de gatilhos e e usado como padrao de case
    case "$arq" in $gpad) echo "gatilho: $gp $gpad ($gmot): $arq" ;; esac
  done
done < "${TMPDIR:-/tmp}/porte.$$" > "${TMPDIR:-/tmp}/porte.$$.hits"
# A contagem precisa sobreviver ao subshell do while: recalcula fora dele.
arquivos=$(grep -c . "${TMPDIR:-/tmp}/porte.$$" || true)
linhas=$(awk -F '\t' '$3 !~ /^docs\// && $3 !~ /\.md$/ && $3 !~ /\/memoria\/(entradas|historico)\// { a=($1 ~ /^[0-9]+$/)?$1:0; d=($2 ~ /^[0-9]+$/)?$2:0; s+=a+d } END { print s+0 }' "${TMPDIR:-/tmp}/porte.$$")
echo "arquivos: $arquivos | linhas de codigo: $linhas (limite $limite)"
if [ -s "${TMPDIR:-/tmp}/porte.$$.hits" ]; then
  cat "${TMPDIR:-/tmp}/porte.$$.hits"
  grep -q '^gatilho: G ' "${TMPDIR:-/tmp}/porte.$$.hits" && sobe G
  grep -q '^gatilho: M ' "${TMPDIR:-/tmp}/porte.$$.hits" && sobe M
fi
rm -f "${TMPDIR:-/tmp}/porte.$$.hits"
if [ "$linhas" -gt "$limite" ]; then
  echo "motivo: $linhas linhas de codigo excedem o limite de P ($limite)"; sobe M
fi
if [ "$critico" -eq 1 ]; then
  echo "motivo: defeito de alta criticidade declarado (--critico)"; sobe M
fi
[ "$porte" != "P" ] || echo "motivo: ate $limite linhas de codigo e nenhum gatilho de M ou G tocado; confira os criterios nao mensuraveis de fluxo-p.md (contrato, fronteira, dado sensivel)"
echo "porte: $porte"
exit 0
