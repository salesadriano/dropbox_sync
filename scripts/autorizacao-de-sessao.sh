#!/usr/bin/env sh
# Autorizacao de sessao do git flow (skill governanca-por-hooks), hook PostToolUse e PostToolUseFailure (Bash).
# Par do `guarda-de-comandos.sh` (regra 6): quando o guarda pergunta (`ask`) pela primeira vez, grava o pendente
# `<git-common-dir>/agentes-autorizacao-sessao/pendente-<session_id>.<tool_use_id>`. Este hook le `session_id`,
# `tool_use_id` e `cwd` do JSON em stdin; se existe o pendente daquele par, o comando executou depois do `ask`, e isso e a
# evidencia de que o solicitante aprovou (recusa nao gera Post, e o pendente fica inerte): grava o marcador
# `sessao-<session_id>` e apaga o pendente. Dai em diante o guarda devolve `allow` para o git flow elegivel naquela sessao.
# Limpa marcadores e pendentes com mais de 7 dias. session_id e tool_use_id so valem em [A-Za-z0-9_-]; o resto e ignorado.
#
# Nunca bloqueia: sempre exit 0. Sem repositorio git, sem `node` nem `python3` para ler o JSON, ou sem JSON valido, nao faz nada.
# Limites declarados: e barreira contra engano, nao contra um agent que grave o marcador na mao; e a documentacao do
# Claude Code nao diz se o `session_id` de um subagent e o do pai (se for outro, o subagent pergunta de novo: lado seguro).

entrada=$(cat)
[ -n "$entrada" ] || exit 0

extrair() {  # $1 = chave de primeiro nivel
  if command -v node >/dev/null 2>&1; then
    printf '%s' "$entrada" | node -e '
      let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
        let j; try { j = JSON.parse(s); } catch { process.exit(0); }
        const v = j && typeof j === "object" ? j[process.argv[1]] : undefined;
        if (typeof v === "string") process.stdout.write(v);
      });' "$1"
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$entrada" | python3 -I -c '
import json, sys
try: j = json.load(sys.stdin)
except Exception: sys.exit(0)
v = j.get(sys.argv[1]) if isinstance(j, dict) else None
if isinstance(v, str): sys.stdout.write(v)' "$1"
  else
    return 1
  fi
}

sid=$(extrair session_id) || exit 0
tid=$(extrair tool_use_id) || exit 0
cwd=$(extrair cwd) || exit 0
[ -n "$cwd" ] || cwd=$(pwd)

comum=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null) || exit 0
[ -n "$comum" ] || exit 0
comum=$(cd "$cwd" 2>/dev/null && cd "$comum" 2>/dev/null && pwd) || exit 0
d="$comum/agentes-autorizacao-sessao"
[ -d "$d" ] || exit 0

find "$d" -type f -mmin +10080 -exec rm -f {} + 2>/dev/null

for v in "$sid" "$tid"; do
  case "$v" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
done
if [ -f "$d/pendente-$sid.$tid" ]; then
  : > "$d/sessao-$sid" 2>/dev/null && rm -f "$d/pendente-$sid.$tid"
fi
exit 0
