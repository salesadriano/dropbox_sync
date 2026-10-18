#!/usr/bin/env sh
# Uso: sh verificar-instrucoes-do-projeto.sh [--raiz <dir>] [--instrucoes <arquivo>] [--protocolo <arquivo>] [--entradas <dir>]
#
# Confere que o que o arquivo de instrucoes do projeto (o que a ferramenta de IA le) AFIRMA sobre o
# repositorio e o que o repositorio E. Quatro conferencias, cada uma pulada quando a frase ou a fonte
# nao existir (linha `pulada <letra>: <motivo>`):
#   (a) caminhos citados entre crases que comecam por scripts/, .github/, docs/, .claude/ ou .vscode/
#       existem no disco (citacao com espaco, `*`, `?`, `<` ou `{` nao e caminho e e ignorada);
#   (b) a frase `**N regras**` ou `N regras` (primeira com numero) bate com as regras `1.`..`N.`
#       da secao `# Protocolo comum obrigatorio` do protocolo, que precisam ser 1..N sem buraco;
#   (c) a frase "branch principal declarada e `x`" (ou "branch principal e `x`") bate com o titulo
#       entre crases da entrada `????-??-??-????-branch-principal.md` ativa mais recente;
#   (d) a frase "repositorio canonico e `dono/repo`" bate com `git remote get-url origin`, ou com
#       GITHUB_REPOSITORY quando nao ha .git.
# Padroes: raiz = topo do git do diretorio corrente ou `.`; instrucoes = o primeiro existente entre
# CLAUDE.md, .github/copilot-instructions.md e AGENTS.md na raiz; protocolo = .github/agents/AGENTS.md
# ou .claude/ai_team/AGENTS.md; entradas = .github/agents/memoria/entradas ou .claude/ai_team/memoria/entradas.
# Saida: exit 0 sem drift, 1 com a lista `- (<letra>) <drift>`, 2 em argumento invalido ou arquivo
# de instrucoes nao encontrado. E verificador de prosa, nao medicao: nada do que ele le e oraculo de si mesmo.
set -eu

raiz=""; instrucoes=""; protocolo=""; entradas=""
while [ $# -gt 0 ]; do
  case "$1" in
    --raiz) [ $# -ge 2 ] || { echo "--raiz exige um valor" >&2; exit 2; }; raiz="$2"; shift 2 ;;
    --instrucoes) [ $# -ge 2 ] || { echo "--instrucoes exige um valor" >&2; exit 2; }; instrucoes="$2"; shift 2 ;;
    --protocolo) [ $# -ge 2 ] || { echo "--protocolo exige um valor" >&2; exit 2; }; protocolo="$2"; shift 2 ;;
    --entradas) [ $# -ge 2 ] || { echo "--entradas exige um valor" >&2; exit 2; }; entradas="$2"; shift 2 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$raiz" ]; then
  raiz=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
raiz=$(CDPATH='' cd -- "$raiz" && pwd)
abs() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s\n' "$raiz/$1" ;; esac; }

if [ -z "$instrucoes" ]; then
  for c in CLAUDE.md .github/copilot-instructions.md AGENTS.md; do
    if [ -f "$raiz/$c" ]; then instrucoes="$c"; break; fi
  done
  if [ -z "$instrucoes" ]; then
    echo "arquivo de instrucoes nao encontrado em $raiz (CLAUDE.md, .github/copilot-instructions.md, AGENTS.md): informe --instrucoes" >&2
    exit 2
  fi
fi
instrucoes=$(abs "$instrucoes")
[ -f "$instrucoes" ] || { echo "arquivo de instrucoes nao encontrado: $instrucoes (informe --instrucoes)" >&2; exit 2; }

if [ -z "$protocolo" ]; then
  for c in .github/agents/AGENTS.md .claude/ai_team/AGENTS.md; do
    if [ -f "$raiz/$c" ]; then protocolo="$c"; break; fi
  done
fi
[ -z "$protocolo" ] || protocolo=$(abs "$protocolo")
if [ -z "$entradas" ]; then
  for c in .github/agents/memoria/entradas .claude/ai_team/memoria/entradas; do
    if [ -d "$raiz/$c" ]; then entradas="$c"; break; fi
  done
fi
[ -z "$entradas" ] || entradas=$(abs "$entradas")

drifts=""
ok() { echo "ok $1: $2"; }
pulada() { echo "pulada $1: $2"; }
drift() { echo "drift $1: $2"; drifts="${drifts}- ($1) $2
"; }
# Acentos do portugues entram por byte, para que este arquivo fique em ASCII.
e_=$(printf '\303\251'); o_=$(printf '\303\263'); oc=$(printf '\303\264')
# As frases (b), (c) e (d) sao procuradas no texto achatado em uma linha, sem a marca de blockquote,
# porque prosa quebra linha no meio da frase; (a) continua linha a linha.
plano=$(sed 's/^[> ]*//' "$instrucoes" | tr '\n' ' ' | tr -s ' ')
primeira() { printf '%s\n' "$plano" | grep -o -E -- "$1" | head -n 1 || true; }
# As crases nos padroes de sed e grep abaixo sao literais de proposito (SC2016 e falso positivo).
# shellcheck disable=SC2016
entre_crases() { printf '%s\n' "$1" | sed 's/^[^`]*`\([^`]*\)`.*$/\1/'; }

# (a) caminhos citados
# shellcheck disable=SC2016
citados=$(grep -o '`[^`]*`' "$instrucoes" | tr -d '`' | grep -E '^(scripts|\.github|docs|\.claude|\.vscode)/' | grep -v -E '[*?<{[:space:]]' | sort -u || true)
if [ -z "$citados" ]; then
  pulada a "nenhum caminho citado entre crases"
else
  n=0; ausentes=0
  for c in $citados; do
    n=$((n + 1))
    if [ ! -e "$raiz/$c" ]; then ausentes=$((ausentes + 1)); drift a "caminho citado nao existe: $c"; fi
  done
  [ "$ausentes" -gt 0 ] || ok a "$n caminho(s) citado(s) existem"
fi

# (b) contagem de regras do protocolo
frase=$(primeira '(\*\*)?[0-9]+[[:space:]]+regras')
if [ -z "$frase" ]; then
  pulada b "frase 'N regras' nao encontrada"
elif [ -z "$protocolo" ] || [ ! -f "$protocolo" ]; then
  pulada b "protocolo nao encontrado${protocolo:+: $protocolo}"
else
  ditas=$(printf '%s' "$frase" | tr -cd '0-9')
  numeros=$(awk '
    /^# Protocolo comum obrigatorio[ \t]*$/ { dentro = 1; next }
    dentro && /^# / { dentro = 0 }
    dentro && /^[0-9]+\. / { sub(/\..*$/, ""); print }' "$protocolo")
  if [ -z "$numeros" ]; then
    pulada b "nenhuma regra numerada na secao '# Protocolo comum obrigatorio' de $protocolo"
  else
    esperado=1; quebra=""
    for n in $numeros; do
      if [ "$n" -ne "$esperado" ]; then quebra="esperava $esperado, achei $n"; break; fi
      esperado=$((esperado + 1))
    done
    total=$((esperado - 1))
    if [ -n "$quebra" ]; then drift b "regras do protocolo nao sao 1..N continuas: $quebra"
    elif [ "$ditas" -ne "$total" ]; then drift b "instrucoes dizem $ditas regras, protocolo tem $total"
    else ok b "$total regras"
    fi
  fi
fi

# (c) branch principal declarada
frase=$(primeira "branch[[:space:]]+principal[[:space:]]+(declarada[[:space:]]+)?(e|$e_)[[:space:]]+\`[^\`]+\`")
if [ -z "$frase" ]; then
  pulada c "frase 'branch principal' nao encontrada"
else
  dita=$(entre_crases "$frase")
  entrada=""
  if [ -n "$entradas" ] && [ -d "$entradas" ]; then
    for f in "$entradas"/????-??-??-????-branch-principal.md; do
      [ -f "$f" ] || continue
      if grep -q -E '^status:[ \t]*ativa[ \t]*$' "$f"; then entrada="$f"; fi
    done
  fi
  if [ -z "$entrada" ]; then
    pulada c "entrada branch-principal ativa nao encontrada${entradas:+ em $entradas}"
  else
    titulo=$(grep -E '^titulo:' "$entrada" | head -n 1 || true)
    declarada=$(entre_crases "$titulo")
    id=$(basename -- "$entrada" .md)
    if [ -z "$declarada" ] || [ "$declarada" = "$titulo" ]; then
      pulada c "titulo de $id sem branch entre crases"
    elif [ "$dita" != "$declarada" ]; then
      drift c "instrucoes dizem branch principal \`$dita\`, entrada $id declara \`$declarada\`"
    else
      ok c "branch principal $dita"
    fi
  fi
fi

# (d) repositorio canonico
frase=$(primeira "reposit(o|$o_)rio[[:space:]]+can(o|$oc)nico[[:space:]]+(e|$e_)[[:space:]]+\`[^\`]+\`")
if [ -z "$frase" ]; then
  pulada d "frase 'repositorio canonico' nao encontrada"
else
  dito=$(entre_crases "$frase")
  remoto=""
  if git -C "$raiz" rev-parse --git-dir >/dev/null 2>&1; then
    remoto=$(git -C "$raiz" remote get-url origin 2>/dev/null || true)
    [ -n "$remoto" ] || pulada d "repositorio git sem remoto origin"
  elif [ -n "${GITHUB_REPOSITORY:-}" ]; then
    remoto="$GITHUB_REPOSITORY"
  else
    pulada d "sem .git e sem GITHUB_REPOSITORY"
  fi
  if [ -n "$remoto" ]; then
    # git@host:dono/repo.git, https://host/dono/repo(.git) ou ssh://git@host/dono/repo -> dono/repo
    reduzido=$(printf '%s\n' "$remoto" | sed -E 's#/+$##; s#\.git$##; s#^.*[:/]([^/:]+/[^/]+)$#\1#')
    if [ "$dito" != "$reduzido" ]; then
      drift d "instrucoes dizem repositorio canonico \`$dito\`, remoto origin e \`$reduzido\`"
    else
      ok d "repositorio canonico $reduzido"
    fi
  fi
fi

if [ -z "$drifts" ]; then
  printf '\342\234\224 sem drift: %s\n' "$instrucoes"
  exit 0
fi
printf '\342\234\226 drift entre %s e o repositorio:\n%s' "$instrucoes" "$drifts"
exit 1
