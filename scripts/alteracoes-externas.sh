#!/usr/bin/env sh
# Detecta alteracoes nao realizadas pelos agents: intervencao humana direta (regra 48 do AGENTS.md).
#
# Os agents mantem uma linha de base local, fora do versionamento, com o que eles mesmos alteraram.
# Tudo o que divergir dela e acusado: arquivo alterado, criado, apagado, renomeado ou com modo trocado,
# na arvore de trabalho ou no indice (versao preparada); submodulo com outro commit ou sujo; commit na
# branch sem a trilha do protocolo (linha `Prompt:` no corpo); commit ou merge com alteracao propria sem
# trilha que chega a branch principal; historico reescrito. O script so le e acusa: nunca altera a arvore
# de trabalho, o indice ou o historico; escreve apenas a linha de base e a marca, dentro de `.git/`.
#
# Uso (a partir de qualquer diretorio do worktree):
#   sh scripts/alteracoes-externas.sh --detectar              # acusa divergencias; exit 3 quando houver
#   sh scripts/alteracoes-externas.sh --inicial               # cria a linha de base do worktree (logo apos cria-lo)
#   sh scripts/alteracoes-externas.sh --registrar <arq>...    # agent registra os arquivos que ELE alterou
#   sh scripts/alteracoes-externas.sh --registrar             # avanca a linha de base apos commit do agent
#   sh scripts/alteracoes-externas.sh --registrar --commits   # incorpora commits acusados, so apos decisao explicita
#   --principal <branch>  branch principal (padrao: entrada branch-principal ativa da memoria)
#   --remoto <nome>       remoto da branch principal (padrao: origin); `<remoto>/<principal>` precisa existir
#
# Saida de --detectar, uma linha por divergencia:
#   ARQUIVO <caminho>                    (caracteres de controle no nome aparecem como ?)
#   COMMIT <sha> <assunto> (<autor>)
#   PRINCIPAL <sha> <assunto> (<autor>)
#   HISTORICO <descricao>
# Exit: 0 sem divergencia, 3 com divergencia, 1 erro, 2 uso invalido.
#
# Limites conhecidos: commit humano com linha `Prompt:` forjada passa como de agent; arquivo ignorado
# (.gitignore, .git/info/exclude, core.excludesFile) esta fora do escopo; rebase feito pelo proprio agent
# aparece como HISTORICO (o protocolo integra por merge, regra 47); o checkout principal nao tem linha de
# base, porque agents nao trabalham nele (regra 46): ali, qualquer diferenca e acusada. Durante um merge
# em andamento (MERGE_HEAD), o que o git preparou no indice e os caminhos em conflito sao atribuidos ao
# merge; o agent que integra registra a resolucao e conclui o merge antes de seguir.

set -eu

modo=""; commits=0; principal=""; remoto="origin"
lista=$(mktemp)
trap 'rm -f "$lista"' EXIT

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "fora de um repositorio git" >&2; exit 1; }
prefixo=$(git rev-parse --show-prefix)
topo=$(git rev-parse --show-toplevel)
SEP=$(printf '\001')
NL='
'

# Caminho relativo a raiz, sem segmentos . e ..; falha para caminho fora do repositorio.
normalizar() {
  case "$1" in
    *"$NL"*|"$topo") return 1 ;;
    /*) # resolve symlinks do diretorio, como o toplevel do git ja vem resolvido
        d=$(CDPATH='' cd -- "$(dirname -- "$1")" 2>/dev/null && pwd -P) || return 1
        case "$d/" in "$topo"/*) c="${d#"$topo"}/$(basename -- "$1")" ;; *) return 1 ;; esac ;;
    *) c="$prefixo$1" ;;
  esac
  printf '%s\n' "$c" | awk -F/ '{
    n = 0
    for (i = 1; i <= NF; i++) {
      if ($i == "" || $i == ".") continue
      if ($i == "..") { if (n == 0) exit 1; n--; continue }
      s[++n] = $i
    }
    if (n == 0) exit 1
    out = s[1]; for (i = 2; i <= n; i++) out = out "/" s[i]; print out
  }'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --detectar|--inicial|--registrar) modo="${1#--}"; shift ;;
    --commits) commits=1; shift ;;
    --principal) principal="${2:?--principal exige valor}"; shift 2 ;;
    --remoto) remoto="${2:?--remoto exige valor}"; shift 2 ;;
    --*) echo "argumento desconhecido: $1" >&2; exit 2 ;;
    *) [ "$modo" = "registrar" ] || { echo "arquivo so e aceito com --registrar: $1" >&2; exit 2; }
       n=$(normalizar "$1") || { echo "caminho fora do repositorio: $1" >&2; exit 2; }
       printf '%s\n' "$n" >> "$lista"; shift ;;
  esac
done
[ -n "$modo" ] || { echo "informe --detectar, --inicial ou --registrar" >&2; exit 2; }

gd=$(git rev-parse --absolute-git-dir)
gcd=$(CDPATH='' cd -- "$(git rev-parse --git-common-dir)" && pwd)
cd -- "$topo"
base="$gd/agentes-linha-de-base"          # por worktree
marca="$gcd/agentes-principal"            # compartilhada entre os worktrees do repositorio
trap 'rm -f "$lista" "$base.$$" "$marca.$$"' EXIT

if [ -z "$principal" ]; then
  entrada=$(grep -l '^status: ativa' .github/agents/memoria/entradas/????-??-??-????-branch-principal.md 2>/dev/null | tail -n 1 || true)
  # shellcheck disable=SC2016 # crases literais do titulo da entrada, nao expansao
  [ -z "$entrada" ] || principal=$(sed -n 's/^titulo:[^`]*`\([^`]*\)`.*/\1/p' "$entrada")
fi
[ -n "$principal" ] || { echo "branch principal desconhecida: registrar a entrada branch-principal (regra 46) ou passar --principal" >&2; exit 1; }
ref_principal="refs/remotes/$remoto/$principal"
git show-ref --verify --quiet "$ref_principal" || { echo "branch principal $remoto/$principal inexistente: rodar git fetch ou corrigir --principal/--remoto" >&2; exit 1; }
modo_arquivo=$(git config --bool core.fileMode || echo true)

cabeca_atual() { git rev-parse -q --verify HEAD 2>/dev/null || echo nenhum; }

# Estados no formato <modo>:<id>, comparaveis entre HEAD, indice e arvore de trabalho.
estado_head() {
  e=$(git ls-tree HEAD -- "$1" 2>/dev/null | awk -F'\t' 'NR == 1 { split($1, a, " "); print a[1] ":" a[3] }')
  echo "${e:-ausente}"
}

estado_indice() {
  e=$(git ls-files -s -- ":(literal)$1" | awk -F'\t' 'NR == 1 { split($1, a, " "); print a[1] ":" a[2] }')
  echo "${e:-ausente}"
}

estado_atual() {
  if [ -L "$1" ]; then
    printf '120000:%s\n' "$(printf '%s' "$(readlink "$1")" | git hash-object --stdin)"
  elif [ -d "$1" ]; then
    # Submodulo: commit do checkout mais um resumo do que estiver sujo nele.
    if [ "$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" = "$topo/$1" ]; then
      sujo=$({ git -C "$1" diff HEAD; git -C "$1" ls-files --others --exclude-standard; } | git hash-object --stdin)
      [ "$sujo" != "$(printf '' | git hash-object --stdin)" ] || sujo=""
      printf '160000:%s%s\n' "$(git -C "$1" rev-parse -q --verify HEAD || echo nenhum)" "${sujo:++$sujo}"
    else
      echo diretorio
    fi
  elif [ -f "$1" ]; then
    if [ "$modo_arquivo" = false ]; then
      m=$(estado_indice "$1"); m=${m%%:*}
      case "$m" in 100644|100755) ;; *) m=100644 ;; esac
    elif [ -x "$1" ]; then m=100755; else m=100644; fi
    printf '%s:%s\n' "$m" "$(git hash-object -- "$1")"
  else
    echo ausente
  fi
}

entradas() { if [ -f "$base" ]; then sed '1d' "$base"; fi; }

# Entrada da linha de base: "<estado da arvore>;<estado do indice> <caminho>".
esperado() { entradas | P="$1" awk 'substr($0, index($0, " ") + 1) == ENVIRON["P"] { print $1; exit }'; }

# Listas -z convertidas para uma linha por caminho; quebra de linha no nome vira SEP e e acusada.
z() { tr '\n\0' "$SEP$NL"; }

candidatos() {
  {
    entradas | cut -d' ' -f2-
    git diff --name-only --no-renames -z | z
    git diff --cached --name-only --no-renames -z | z
    git ls-files --others --exclude-standard -z | z
    git ls-files -v -z | z | sed -n 's/^[a-zS] //p'   # assume-unchanged e skip-worktree
  } | sed 's:/$::' | sort -u
}

sem_trilha() {  # commits sem a linha "Prompt:" no corpo
  git rev-list "$@" | while read -r c; do
    git show -s --format=%B "$c" | grep -q '^Prompt: ' || git show -s --format='%h %s (%an)' "$c"
  done
}

sem_trilha_principal() {  # idem, mas merge sem alteracao propria nao conta
  git rev-list "$@" | while read -r c; do
    git show -s --format=%B "$c" | grep -q '^Prompt: ' && continue
    if [ "$(git rev-list --parents -n 1 "$c" | wc -w)" -gt 2 ]; then
      [ -n "$(git diff-tree --cc -r --no-commit-id --name-only "$c")" ] || continue
    fi
    git show -s --format='%h %s (%an)' "$c"
  done
}

commits_da_branch() {
  agora=$(cabeca_atual)
  [ "$agora" != nenhum ] || return 0
  if [ ! -f "$base" ]; then
    sem_trilha "$agora" --not "$ref_principal" | sed 's/^/COMMIT /'
    return 0
  fi
  antes=$(sed -n '1s/^HEAD //p' "$base")
  [ "$antes" != "$agora" ] || return 0
  if [ "$antes" = nenhum ]; then
    sem_trilha "$agora" --not "$ref_principal"
  elif git merge-base --is-ancestor "$antes" "$agora" 2>/dev/null; then
    sem_trilha "$antes..$agora" --not "$ref_principal"
  else
    echo "HISTORICO HEAD fora da linha de base ($(git rev-parse --short "$antes" 2>/dev/null || echo "$antes") -> $(git rev-parse --short "$agora")): reset, rebase ou troca de branch"
    return 0
  fi | sed '/^HISTORICO /!s/^/COMMIT /'
}

inicio_principal() {  # marca gravada ou, sem ela, o ponto em que HEAD se separou da principal
  if [ -s "$marca" ]; then cat "$marca"; else git merge-base HEAD "$ref_principal" 2>/dev/null || true; fi
}

commits_da_principal() {
  antes=$(inicio_principal)
  agora=$(git rev-parse "$ref_principal")
  [ -n "$antes" ] && [ "$antes" != "$agora" ] || return 0
  if ! git merge-base --is-ancestor "$antes" "$agora" 2>/dev/null; then
    echo "HISTORICO branch principal $principal reescrita no remoto ($(git rev-parse --short "$antes" 2>/dev/null || echo "$antes") -> $(git rev-parse --short "$agora"))"
    return 0
  fi
  sem_trilha_principal "$antes..$agora" | sed 's/^/PRINCIPAL /'
}

arquivos() {
  em_merge=0; git rev-parse -q --verify MERGE_HEAD >/dev/null && em_merge=1
  candidatos | while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in *"$SEP"*) printf 'ARQUIVO %s\n' "$(printf '%s' "$p" | tr "$SEP" '?')"; continue ;; esac
    atual=$(estado_atual "$p")
    cabeca=$(estado_head "$p")
    e=$(esperado "$p"); [ -n "$e" ] || e="$cabeca;$cabeca"
    e_arvore=${e%%;*}; e_indice=${e#*;}
    indice=$(estado_indice "$p")
    if [ "$em_merge" -eq 1 ]; then
      [ -z "$(git ls-files -u -- ":(literal)$p")" ] || continue   # conflito em aberto: do merge
      [ "$atual" != "$indice" ] || [ "$e_arvore" = "$cabeca" ] || [ "$atual" = "$e_arvore" ] || { printf 'ARQUIVO %s\n' "$p"; continue; }
      [ "$atual" != "$indice" ] || continue                      # preparado pelo merge e igual a arvore
    fi
    # A arvore diverge do esperado, ou o indice guarda versao que nao e o HEAD, a arvore nem a registrada.
    if [ "$atual" != "$e_arvore" ] || { [ "$indice" != "$cabeca" ] && [ "$indice" != "$atual" ] && [ "$indice" != "$e_indice" ]; }; then
      printf 'ARQUIVO %s\n' "$p"
    fi
  done
}

grava() { cat > "$1.$$" && mv -f "$1.$$" "$1"; }   # escrita atomica: leitor concorrente nunca ve arquivo truncado

case "$modo" in
  detectar)
    saida=$(arquivos; commits_da_branch; commits_da_principal)
    [ -z "$saida" ] && exit 0
    printf '%s\n' "$saida"
    exit 3
    ;;
  inicial)
    [ ! -f "$base" ] || { echo "linha de base ja existe em $base; use --registrar" >&2; exit 1; }
    if [ ! -s "$marca" ]; then
      i=$(inicio_principal); [ -z "$i" ] || printf '%s\n' "$i" | grava "$marca"
    fi
    printf 'HEAD %s\n' "$(cabeca_atual)" | grava "$base"
    ;;
  registrar)
    [ -f "$base" ] || { echo "sem linha de base neste worktree: rodar --inicial primeiro" >&2; exit 1; }
    cabeca=$(sed -n '1s/^HEAD //p' "$base")
    if [ "$commits" -eq 1 ] || [ -z "$(commits_da_branch)" ]; then cabeca=$(cabeca_atual); fi
    {
      printf 'HEAD %s\n' "$cabeca"
      {
        entradas | while IFS= read -r l; do grep -qxF -- "${l#* }" "$lista" || printf '%s\n' "$l"; done
        sort -u "$lista" | while IFS= read -r p; do printf '%s;%s %s\n' "$(estado_atual "$p")" "$(estado_indice "$p")" "$p"; done
      } | while IFS= read -r l; do
        # Entrada igual ao HEAD ja esta comitada: sai da linha de base.
        e=${l%% *}; [ "${e%%;*}" = "$(estado_head "${l#* }")" ] || printf '%s\n' "$l"
      done
    } | grava "$base"
    if [ "$commits" -eq 1 ] || [ -z "$(commits_da_principal)" ]; then
      git rev-parse "$ref_principal" | grava "$marca"
    fi
    ;;
esac
