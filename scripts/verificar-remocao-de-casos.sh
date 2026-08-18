#!/usr/bin/env bash
# verificar-remocao-de-casos.sh — guarda contra remocao silenciosa de casos de teste.
#
# FERRAMENTA DE DESENVOLVIMENTO. Nao integra a suite nem o produto.
#   - Nao e executada por `tests/run.sh` e nao vive sob `tests/`.
#   - `git` NAO e pre-requisito de execucao do produto e por isso nao consta de
#     `DBX_PREFLIGHT_UTILITARIOS`. Colocar esta verificacao dentro da suite
#     obrigaria `git` a passar pela auditoria de comandos externos, declarando
#     como dependencia de execucao o que e dependencia de desenvolvimento, e
#     faria a suite falhar num tarball sem `.git` por ausencia de ferramenta —
#     falha indistinguivel de regressao.
#
# PROPRIEDADE VERIFICADA
#   A contagem de casos por arquivo nao pode diminuir em relacao a base da
#   branch. Quando diminuir de proposito, a reducao tem de estar declarada, e
#   nao acontecer por omissao.
#
# REFERENCIA: a base de merge com a branch de integracao, nao `HEAD`.
#   Contra `HEAD` a guarda so enxergaria remocao ainda nao commitada: uma
#   remocao commitada no meio da branch desapareceria da comparacao ja no
#   commit seguinte. A branch e a unidade em que a revisao acontece.
#
# DECLARACAO DE REMOCAO INTENCIONAL
#   Trailer numa mensagem de commit da propria branch:
#
#       Remocao-de-casos: tests/unit/exemplo_test.sh 3
#
#   A declaracao vive no historico — artefato que registra a mudanca e que o
#   revisor le no PR — em vez de num arquivo de excecoes mantido a mao.
#
# LIMITACAO CONHECIDA, REGISTRADA EM VEZ DE DISFARCADA
#   Contagem detecta REMOCAO, nao ESVAZIAMENTO. Trocar o corpo de um caso por
#   `:` mantem a contagem e mantem a suite verde. Esta guarda reduz o ponto
#   cego; nao o fecha. Nao conheco proxy derivavel para esvaziamento que nao
#   volte a ser numero mantido a mao.
#
# Uso:  bash scripts/verificar-remocao-de-casos.sh [branch-de-integracao]
# Saida: 0 nenhuma reducao nao declarada
#        1 reducao nao declarada encontrada
#        2 nao foi possivel verificar (sem `git`, sem repositorio, sem base)

set -u

readonly PADRAO_DE_CASO='^teste_[A-Za-z0-9_]*\(\)'
readonly PADRAO_DE_ARQUIVO='_test\.sh$'

_erro() {
  printf 'nao foi possivel verificar: %s\n' "$1" >&2
  exit 2
}

_contar_casos_em_texto() { grep -cE "$PADRAO_DE_CASO" || true; }

integracao=${1:-develop}

command -v git >/dev/null 2>&1 || _erro 'git ausente no PATH'
git rev-parse --git-dir >/dev/null 2>&1 || _erro 'diretorio atual nao e um repositorio git'
raiz=$(git rev-parse --show-toplevel) || _erro 'raiz do repositorio indeterminada'
cd -- "$raiz" || _erro "nao foi possivel entrar em $raiz"

git rev-parse --verify --quiet "$integracao" >/dev/null ||
  _erro "branch de integracao '$integracao' nao existe"
base=$(git merge-base "$integracao" HEAD) ||
  _erro "sem base de merge entre '$integracao' e HEAD"

# Declaracoes de remocao intencional, colhidas dos commits da branch.
declare -A declarado=()
while read -r _ arquivo quantidade _; do
  [[ -n ${arquivo:-} && ${quantidade:-} =~ ^[0-9]+$ ]] || continue
  declarado[$arquivo]=$((${declarado[$arquivo]:-0} + quantidade))
done < <(git log --format=%B "$base..HEAD" | grep -E '^Remocao-de-casos:[[:space:]]')

reducoes=0
total_base=0
total_atual=0

while IFS= read -r arquivo; do
  [[ -n $arquivo ]] || continue
  na_base=$(git show "$base:$arquivo" 2>/dev/null | _contar_casos_em_texto)
  na_base=${na_base:-0}
  if [[ -f $arquivo ]]; then
    agora=$(_contar_casos_em_texto <"$arquivo")
  else
    agora=0
  fi
  total_base=$((total_base + na_base))
  total_atual=$((total_atual + agora))

  perda=$((na_base - agora))
  ((perda > 0)) || continue

  coberto=${declarado[$arquivo]:-0}
  if ((coberto >= perda)); then
    printf 'declarado  %-42s %s -> %s (reducao de %s declarada)\n' \
      "$arquivo" "$na_base" "$agora" "$perda"
    continue
  fi
  printf 'REDUCAO    %-42s %s -> %s (%s caso(s) a menos, %s declarado(s))\n' \
    "$arquivo" "$na_base" "$agora" "$perda" "$coberto" >&2
  reducoes=$((reducoes + 1))
#
# O universo de arquivos vem da BASE, nunca da arvore de trabalho. Passar um
# glob do shell como pathspec (`-- tests/*/*_test.sh`) faria o shell expandi-lo
# contra a arvore atual ANTES de `git` ver: um arquivo apagado sumiria da
# propria lista que deveria acusa-lo. Foi o defeito que a prova de
# discriminacao encontrou nesta guarda. A filtragem e feita sobre a saida de
# `git`, ja restrita a base.
done < <(git ls-tree -r --name-only "$base" -- tests | grep -E "$PADRAO_DE_ARQUIVO")

printf 'base %s .. arvore de trabalho: %s -> %s caso(s)\n' \
  "${base:0:8}" "$total_base" "$total_atual"

if ((reducoes > 0)); then
  printf '\n%s arquivo(s) com reducao NAO declarada.\n' "$reducoes" >&2
  printf 'Se a remocao for intencional, declare no commit:\n' >&2
  printf '    Remocao-de-casos: <arquivo> <quantidade>\n' >&2
  exit 1
fi

printf 'nenhuma reducao nao declarada.\n'
