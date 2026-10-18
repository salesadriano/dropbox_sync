#!/usr/bin/env sh
# Guarda de comandos para o hook PreToolUse (Bash) do Claude Code (skill governanca-por-hooks).
# Le o JSON do hook em stdin, extrai `tool_input.command` e `cwd`, e BLOQUEIA (exit 2, motivo em stderr):
#   1. embutida: `git push` (tambem `git <opcoes> push`) quando `scripts/alteracoes-externas.sh --detectar`,
#      na raiz do repositorio do `cwd`, sai com 3 (regra 48 do AGENTS.md); a saida do detector vai no motivo.
#   2. por arquivo de padroes (--padroes), opcional: cada linha `padrao<TAB>motivo`; comando que contem o
#      padrao como substring e bloqueado com o motivo. Comando que roda em conteiner (`docker run`,
#      `docker compose`, `docker-compose`, `docker exec`) e isento desta regra por desenho.
#      Sem --padroes, ou com o arquivo ausente, so as regras 1 e 3 valem.
#   3. embutida, so quando o repositorio tem `scripts/suite-completa.sh`: `gh pr create`, e `git push` quando a
#      branch atual e a de integracao (a `branch-principal` declarada na memoria; sem ela, `main` ou `master`)
#      ou tem PR aberta para ela (consultado por `gh pr list`, so se ha remoto e `gh` responde), exigem
#      `scripts/suite-completa.sh --conferir` em 0: suite completa verde registrada para o HEAD (Regra 8 de
#      protocolo-tdd). Push de branch sem PR para a integracao nao e afetado; sem `gh`, so o caso da branch
#      de integracao e verificado.
#
# Uso fora do hook: printf '{"tool_input":{"command":"..."},"cwd":"..."}' | sh guarda-de-comandos.sh [--padroes <arquivo>]
# Exit: 0 permite; 2 bloqueia (ou uso invalido). Sem `node` nem `python3` para ler o JSON, permite e avisa
# em stderr: um hook que falha por falta de interprete bloquearia todo comando da sessao.
#
# O comando e o motivo sao entrada externa: nunca sao executados, expandidos nem passados a `eval`;
# o casamento e por `case` com o padrao entre aspas (literal). Sem `set -e`: a falha de qualquer fonte
# (JSON, git, detector) resulta em permitir, e so a regra que de fato casou bloqueia.
# Limite declarado: o casamento e por substring do texto do comando, sem ler os argumentos. Um padrao
# citado numa string (ex.: dentro de `grep`) bloqueia; um `docker run` citado isenta.

padroes=""
while [ $# -gt 0 ]; do
  case "$1" in
    --padroes) [ $# -ge 2 ] || { echo "--padroes exige um valor" >&2; exit 2; }; padroes="$2"; shift 2 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

entrada=$(cat)
[ -n "$entrada" ] || exit 0

extrair() {  # $1 = chave de primeiro nivel ou "tool_input.command"
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$entrada" | node -e '
      let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
        let j; try { j = JSON.parse(s); } catch { process.exit(0); }
        const v = process.argv[1].split(".").reduce((o, k) => (o && typeof o === "object") ? o[k] : undefined, j);
        if (typeof v === "string") process.stdout.write(v);
      });' "$1"
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$entrada" | python3 -I -c '
import json, sys
try: j = json.load(sys.stdin)
except Exception: sys.exit(0)
v = j
for k in sys.argv[1].split("."):
    v = v.get(k) if isinstance(v, dict) else None
if isinstance(v, str): sys.stdout.write(v)' "$1"
  else
    echo "guarda-de-comandos: sem node nem python3 para ler o JSON do hook; comando liberado sem verificacao" >&2
    return 1
  fi
}

comando=$(extrair tool_input.command) || exit 0
[ -n "$comando" ] || exit 0
cwd=$(extrair cwd) || cwd=""
[ -n "$cwd" ] || cwd=$(pwd)

bloquear() {
  printf 'BLOQUEADO por guarda-de-comandos.sh: %s\n' "$1" >&2
  exit 2
}

case "$comando" in *"git push"*|*"git "*" push"*)
  topo=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || topo=""
  if [ -n "$topo" ] && [ -f "$topo/scripts/alteracoes-externas.sh" ]; then
    saida=$(cd "$topo" && sh scripts/alteracoes-externas.sh --detectar 2>&1); codigo=$?
    if [ "$codigo" -eq 3 ]; then
      bloquear "ha alteracao nao realizada pelos agents (regra 48). Pergunte ao solicitante se foi intencional antes do push. Saida de --detectar:
$saida"
    fi
  fi ;;
esac

# Regra 3: suite completa registrada para o HEAD antes de abrir ou atualizar a PR de integracao.
principal_declarada() {  # $1 = topo; imprime a branch da entrada branch-principal ativa, ou nada
  for d in "$1/.github/agents/memoria/entradas" "$1/.claude/ai_team/memoria/entradas"; do
    [ -d "$d" ] || continue
    e=$(grep -l '^status: ativa' "$d"/????-??-??-????-branch-principal.md 2>/dev/null | tail -n 1)
    # shellcheck disable=SC2016 # crases literais do titulo
    [ -z "$e" ] || { sed -n 's/^titulo:[^`]*`\([^`]*\)`.*/\1/p' "$e"; return 0; }
  done
}
case "$comando" in *"git push"*|*"git "*" push"*|*"gh pr create"*)
  topo=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || topo=""
  if [ -n "$topo" ] && [ -f "$topo/scripts/suite-completa.sh" ]; then
    exige=0
    case "$comando" in *"gh pr create"*) exige=1 ;; esac
    if [ "$exige" -eq 0 ]; then
      branch=$(git -C "$topo" symbolic-ref --short -q HEAD 2>/dev/null) || branch=""
      integracao=$(principal_declarada "$topo"); [ -n "$integracao" ] || integracao="main master"
      for b in $integracao; do [ "$branch" = "$b" ] && exige=1; done
      if [ "$exige" -eq 0 ] && [ -n "$branch" ] && command -v gh >/dev/null 2>&1 && [ -n "$(git -C "$topo" remote 2>/dev/null)" ]; then
        for b in $integracao; do
          n=$(cd "$topo" && gh pr list --head "$branch" --base "$b" --state open --json number --jq length 2>/dev/null) || n=0
          case "$n" in ''|*[!0-9]*) n=0 ;; esac
          [ "$n" -eq 0 ] || exige=1
        done
      fi
    fi
    if [ "$exige" -eq 1 ]; then
      saida=$(cd "$topo" && sh scripts/suite-completa.sh --conferir 2>&1) || bloquear "a suite completa precisa estar verde e registrada para o commit atual antes de abrir ou atualizar a PR para a branch de integracao (Regra 8 de protocolo-tdd). $saida"
    fi
  fi ;;
esac

[ -n "$padroes" ] && [ -f "$padroes" ] || exit 0
case "$comando" in *"docker run"*|*"docker compose"*|*"docker-compose"*|*"docker exec"*) exit 0 ;; esac

tab=$(printf '\t')
while IFS= read -r linha || [ -n "$linha" ]; do
  case "$linha" in ''|'#'*) continue ;; esac
  padrao=${linha%%"$tab"*}
  motivo=${linha#*"$tab"}
  [ "$motivo" != "$linha" ] || motivo="bloqueado pelo arquivo de padroes"
  [ -n "$padrao" ] || continue
  case "$comando" in *"$padrao"*) bloquear "'$padrao': $motivo" ;; esac
done < "$padroes"

exit 0
