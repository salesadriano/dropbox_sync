#!/usr/bin/env sh
# Guarda de comandos para o hook PreToolUse (Bash) do Claude Code (skill governanca-por-hooks).
# Le o JSON do hook em stdin, extrai `tool_input.command` e `cwd`, e BLOQUEIA (exit 2, motivo em stderr):
#   1. embutida: `git push` (tambem `git <opcoes globais> push`) quando `scripts/alteracoes-externas.sh --detectar`,
#      na raiz do repositorio alvo, sai com 3 (regra 48 do AGENTS.md); a saida do detector vai no motivo.
#      Repositorio alvo (regras 1 e 3): o de `git -C <dir>` (varios `-C` compoem; relativo ao `cwd` do hook), um por envio,
#      e todos precisam passar; sem `-C`, e o `cwd`. Limites declarados: `cd` NAO e seguido (so o `cwd` e o `-C` valem);
#      `-C` nao resolvido (`$`, til) ou diretorio inexistente cai no `cwd`; `gh pr create` confere o `cwd`.
#   2. por arquivo de padroes (--padroes), opcional: cada linha `padrao<TAB>motivo`; comando que contem o
#      padrao como substring e bloqueado com o motivo; linha vazia, so com espacos/tabs/CR ou iniciada por `#` e
#      ignorada. Comando que roda em conteiner (`docker run`, `docker compose`, `docker-compose`, `docker exec`) e
#      isento desta regra por desenho.
#      Sem --padroes, ou com o arquivo ausente, so as regras 1 e 3 valem.
#   3. embutida, so quando o repositorio tem `scripts/suite-completa.sh`: `gh pr create` e `gh pr new` (qualquer base), e
#      `git push` quando mira a branch de integracao (a `branch-principal` declarada na memoria; sem ela, `main` ou
#      `master`) por refspec (`<b>`, `+<b>`, `refs/heads/<b>`, `<ref>:<b>`) ou por `--all`, `--mirror` ou `--branches`
#      (fail-closed: empurram todas as branches), quando a branch atual e a de integracao
#      ou quando ela tem PR aberta para a integracao (consultado por `gh pr list`, so se ha remoto e `gh` responde),
#      exigem `scripts/suite-completa.sh --conferir` em 0: suite completa verde registrada para o HEAD (Regra 8 de
#      protocolo-tdd). Push de branch sem PR para a integracao e que nao a mira nao e afetado; sem `gh`, so o
#      refspec e a branch de integracao sao verificados.
#   4. embutida, antes das demais: `git push` com force em qualquer posicao do segmento (`--force`, `--force-with-lease`
#      com ou sem `=valor`, `--force-if-includes`, `--mirror`, abreviacao delas com 3+ caracteres como `--f`, `--for`, `--mi`, `-f`, grupo de
#      opcoes curtas com `f` como `-uf`, refspec iniciado por `+`) BLOQUEIA com o motivo da regra 47 do AGENTS.md (force e proibido e nao se autoriza). O prefixo de
#      `permissions.deny` do cliente so pega a opcao logo apos `push`; esta regra le a palavra em qualquer posicao.
#   5. embutida: `git switch` com `--discard-changes`, `-f`, `--force`, `-C` ou `--force-create` (ou grupo de curtas
#      com `f` ou `C`), `git worktree remove` com `--force`/`-f`, `git branch` com `-D`, `-M`, `-C`, `-f` ou `--force`
#      (reposiciona ou sobrescreve branch; com ou sem nome, com ou sem `-d`); a opcao longa vale abreviada
#      (`--disc`, `--f`, `--force-c`: prefixo de 3+ caracteres, `=valor` ignorado; o git so aceita abreviacao unica e
#      a ambigua so erra la, entao perguntar a mais e o lado seguro); `-c` minusculo (criar) e `branch -d` seguem
#      livres. NAO bloqueia: imprime em stdout a decisao `ask` do PreToolUse do Claude Code (JSON em
#      `hookSpecificOutput.permissionDecision`, exit 0), e o prompt do cliente e a autorizacao da regra 48. Vale
#      apos as regras 1 a 3 e 2 (padrao de arquivo bloqueia antes). Outros clientes sem esse JSON: o stdout e ignorado.
#   6. embutida, depois da 5 (autorizacao de sessao do git flow; par `autorizacao-de-sessao.sh` em PostToolUse e
#      PostToolUseFailure): a primeira autorizacao num prompt do cliente vale ate o fim da sessao. Comando ELEGIVEL (todo
#      segmento e `cd <dir>` ou git/gh da lista de rotina e reversao, sem opcao global que nao seja -C, sem pipe, expansao,
#      heredoc nem outro binario; `gh pr merge` fora) e: (a) reversao que o detector nao enxerga (-C, cd, `git clean -x/-X`,
#      `worktree remove --force`, `git stash -a/--all`, `git branch -D/-M/-C/-f/--force`: o detector so olha a branch atual
#      e nao ve arquivo ignorado) pergunta sempre; escrita com -C ou cd
#      (add, commit, merge, rebase, pull, push, tag, branch, switch, revert, cherry-pick) e inelegivel, sem allow e sem pendente, porque o detector e a suite leem o cwd e nao o destino (so leitura, fetch e worktree sem remove seguem elegiveis com -C ou cd);
#      gh com -F/--body-file ou -R/--repo, palavra com `$` fora de aspas simples ou com chaves de expansao, e --output/-o em log, diff e show tambem sao inelegiveis; (b) reversao com `scripts/alteracoes-externas.sh --detectar` diferente
#      de 0, ou sem o script, pergunta a cada vez (regra 48: alteracao humana); (c) com o marcador de sessao
#      `<git-common-dir>/agentes-autorizacao-sessao/sessao-<session_id>`, `allow`; (d) sem marcador, com gatilho (o que
#      hoje pergunta) ou reversao, `ask` e grava `pendente-<session_id>.<tool_use_id>`, salvo em permission_mode auto,
#      bypassPermissions ou dontAsk (ask sem pendente); (e) rotina sem gatilho e sem marcador: sem opiniao. Sem session_id
#      ou tool_use_id validos ([A-Za-z0-9_-]): reversao pergunta sem pendente, o resto fica sem opiniao. Limites
#      declarados: e barreira contra engano, nao contra um agent que grave o marcador na mao; o cliente nao informa a
#      resposta ao prompt (executar apos o `ask` e o indicio); se o session_id de subagent e o do pai nao esta
#      documentado, e o lado falho e perguntar de novo.
#   Nas regras 1 e 3, push e `gh pr create` sao lidos por palavra, em cada segmento do comando, por
#   `guarda-de-comandos.awk` (ao lado deste arquivo): `git fetch; gh run list --event push` nao e push. Fora de aspas,
#   o redirecionamento (descritor numerico, operador e alvo) sai das palavras sem fechar o segmento (`git push>log`,
#   `git 2>/dev/null push`); entre `git` e o subcomando sao puladas as opcoes globais (com valor:
#   `-C -c --git-dir --work-tree --namespace --config-env --attr-source`) e a palavra que comeca por `$` (`git $OPTS
#   push`); entre `gh pr` e o subcomando, as opcoes (`--repo`/`-R` com valor). O trecho entre aspas, `$( )`, a crase e o
#   corpo de heredoc sao lidos tambem como comando, para pegar `sh -c '...'`; a leitura que termina com aspa ou `$(` sem
#   fechar aplica tambem a regra antiga, por substring (fail-closed).
#   Limites declarados: `git push` e `gh pr create` citados em qualquer texto contam, com o destino do push (`echo 'git
#   push'`, `git commit -m "...git push origin main"`, `grep -rn "gh pr create" .`); nao se detecta o git chamado por
#   outro nome ou por variavel (`git.exe push`, `GIT=git; $GIT push`), o destino em variavel (`B=main; git push origin
#   $B`), alias de git, nem o subcomando que chega por `xargs` (`xargs git push` e detectado; `echo push | xargs git`
#   nao); `gh pr edit --base <integracao>` nao e verificado. Tambem escapam as opcoes de push, switch, worktree e branch
#   que chegam por variavel (`git push $OPT`, expansao so e vista como opcao global) e a opcao colada em outro nome
#   (`GIT_CONFIG` ou `alias.push` com force). A abreviacao das regras 4 e 5 e tratada; `--force` ou `--mirror` como valor
#   de outra opcao do push (`-o --force`) nao e distinguido e bloqueia (lado seguro).
#
# Uso fora do hook: printf '{"tool_input":{"command":"..."},"cwd":"..."}' | sh guarda-de-comandos.sh [--padroes <arquivo>]
# Exit: 0 permite (ou pergunta, com o JSON de ask em stdout); 2 bloqueia (ou uso invalido). Sem `node` nem `python3` para ler o JSON, ou sem
# `guarda-de-comandos.awk` legivel ao lado deste arquivo, permite e avisa em stderr: um hook que falha por falta de
# interprete ou de arquivo bloquearia todo comando da sessao.
#
# O comando e o motivo sao entrada externa: nunca sao executados, expandidos nem passados a `eval`;
# o casamento e por `case` com o padrao entre aspas (literal). Sem `set -e`: a falha de qualquer fonte
# (JSON, git, detector) resulta em permitir, e so a regra que de fato casou bloqueia.
# Limite declarado: na regra 2, e na isencao por conteiner, o casamento e por substring do texto do comando, sem
# ler os argumentos. Um padrao citado numa string (ex.: dentro de `grep`) bloqueia; um `docker run` citado isenta.

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

case "$0" in */*) dir=${0%/*} ;; *) dir=. ;; esac
programa_awk="$dir/guarda-de-comandos.awk"
if [ ! -r "$programa_awk" ]; then
  echo "guarda-de-comandos: $programa_awk ausente ou ilegivel; comando liberado sem verificacao" >&2
  exit 0
fi

bloquear() {
  printf 'BLOQUEADO por guarda-de-comandos.sh: %s\n' "$1" >&2
  exit 2
}

# Leitura por palavra: ` push`, ` pr` (gh pr create), ` aberto`, ` forca`, ` reversao`; ` mira` so quando `integracao` e passada.
analise=$(printf '%s\n' "$comando" | awk -v sq="'" -f "$programa_awk")
# 1a linha: as palavras acima; 2a em diante: um alvo por envio (`kinds<TAB>_C`), lido so por `topo_do_alvo` (regras 1 e 3).
nl='
'
tab=$(printf '\t')
alvos=""; case "$analise" in *"$nl"*) alvos=${analise#*"$nl"}; analise=${analise%%"$nl"*} ;; esac
topo_do_alvo() {  # $1 = linha `kinds<TAB>_C`; `git -C <dir>` relativo ao cwd; nao resolvido ou inexistente: o cwd. Imprime o topo
  c=${1#*"$tab"}; c=${c#_}; d=$cwd
  if [ -n "$c" ] && [ "$c" != "?" ]; then
    case "$c" in /*) d=$c ;; *) d="$cwd/$c" ;; esac
    [ -d "$d" ] || d=$cwd
  fi
  # `-C` para diretorio que nao e repositorio: tambem o cwd, para nao deixar o envio sem conferencia.
  git -C "$d" rev-parse --show-toplevel 2>/dev/null || git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true
}

# Regra 4: force em push e proibido (regra 47 do AGENTS.md) e nao se autoriza; vale antes de qualquer outra regra.
case "$analise" in *forca*)
  bloquear "push com force (--force, --force-with-lease, --force-if-includes, --mirror, abreviacoes, -f, grupo de opcoes curtas com f ou refspec iniciado por +) e proibido (regra 47 do AGENTS.md); force nunca e autorizado. Use push comum; para reescrever historia, devolva ao Tech Lead." ;;
esac

# Regra 5 e 6: reversao (regra 48) e git flow elegivel pedem autorizacao; o prompt e a autorizacao e, na regra 6, vale a sessao.
decidir() {  # $1 = ask|allow; $2 = motivo
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
  exit 0
}
id_valido() { case "$1" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac; return 0; }
diretorio_de_sessao() {  # imprime <git-common-dir>/agentes-autorizacao-sessao, ou nada fora de repositorio git
  c=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null) || return 1
  [ -n "$c" ] || return 1
  c=$(cd "$cwd" 2>/dev/null && cd "$c" 2>/dev/null && pwd) || return 1
  printf '%s/agentes-autorizacao-sessao' "$c"
}
fim() {
  rv=0; eleg=0; gat=0
  case "$analise" in *reversao*|*rv-total*|*rv-sempre*) rv=1 ;; esac
  case "$analise" in *elegivel*) eleg=1 ;; esac
  case "$analise" in *gatilho*) gat=1 ;; esac
  motivo_rv="Operacao de reversao (git switch --discard-changes/-f/-C, worktree remove --force, branch -D/-f, reset, clean, restore, checkout, stash): a regra 48 do AGENTS.md exige autorizacao explicita do solicitante. Confirme so se ele autorizou."
  sid=$(extrair session_id) || sid=""; tid=$(extrair tool_use_id) || tid=""; modo=$(extrair permission_mode) || modo=""
  id_valido "$sid" || sid=""; id_valido "$tid" || tid=""
  if [ "$rv" -eq 1 ]; then
    case "$analise" in *rv-sempre*) decidir ask "$motivo_rv Reversao com -C, com cd, git clean -x/-X, git stash -a, git branch -D/-M/-C/-f ou worktree remove --force: o detector da regra 48 nao enxerga o alvo, entao pergunta sempre." ;; esac
    [ "$eleg" -eq 1 ] || decidir ask "$motivo_rv"
    topo=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || topo=""
    if [ -z "$topo" ] || [ ! -f "$topo/scripts/alteracoes-externas.sh" ]; then
      decidir ask "$motivo_rv Sem scripts/alteracoes-externas.sh para conferir se ha alteracao humana (regra 48): pergunta a cada vez."
    fi
    (cd "$topo" && sh scripts/alteracoes-externas.sh --detectar >/dev/null 2>&1) \
      || decidir ask "$motivo_rv Ha alteracao nao realizada pelos agents (regra 48): a autorizacao de sessao nao cobre, pergunta a cada vez."
  fi
  [ "$eleg" -eq 1 ] || exit 0
  if [ -z "$sid" ] || [ -z "$tid" ]; then
    [ "$rv" -eq 0 ] || decidir ask "$motivo_rv"
    exit 0
  fi
  d=$(diretorio_de_sessao) || d=""
  if [ -n "$d" ] && [ -f "$d/sessao-$sid" ]; then
    decidir allow "Autorizacao de sessao do git flow (regra 6 do guarda): ja confirmada nesta sessao; force, gh pr merge e alteracao humana (regra 48) seguem fora."
  fi
  if [ "$rv" -eq 1 ] || [ "$gat" -eq 1 ]; then
    case "$modo" in
      auto|bypassPermissions|dontAsk) ;;  # nao houve autorizacao humana: nao grava pendente
      *) [ -z "$d" ] || { mkdir -p "$d" 2>/dev/null && : > "$d/pendente-$sid.$tid" 2>/dev/null; } ;;
    esac
    decidir ask "Primeira autorizacao do git flow nesta sessao: confirmar libera, ate o fim da sessao, a rotina e a reversao de trabalho dos agents sem novo prompt. Force, gh pr merge e alteracao humana (regra 48) seguem fora. Confirme so se o solicitante autorizou."
  fi
  exit 0
}

while IFS= read -r alvo_linha; do
  case "${alvo_linha%%"$tab"*}" in *p*) ;; *) continue ;; esac
  topo=$(topo_do_alvo "$alvo_linha")
  if [ -n "$topo" ] && [ -f "$topo/scripts/alteracoes-externas.sh" ]; then
    saida=$(cd "$topo" && sh scripts/alteracoes-externas.sh --detectar 2>&1); codigo=$?
    if [ "$codigo" -eq 3 ]; then
      bloquear "ha alteracao nao realizada pelos agents (regra 48) em $topo. Pergunte ao solicitante se foi intencional antes do push. Saida de --detectar:
$saida"
    fi
  fi
done <<EOF
$alvos
EOF

# Regra 3: suite completa registrada para o HEAD antes de abrir ou atualizar a PR de integracao.
principal_declarada() {  # $1 = topo; imprime a branch da entrada branch-principal ativa, ou nada
  for d in "$1/.github/agents/memoria/entradas" "$1/.claude/ai_team/memoria/entradas"; do
    [ -d "$d" ] || continue
    e=$(grep -l '^status: ativa' "$d"/????-??-??-????-branch-principal.md 2>/dev/null | tail -n 1)
    # shellcheck disable=SC2016 # crases literais do titulo
    [ -z "$e" ] || { sed -n 's/^titulo:[^`]*`\([^`]*\)`.*/\1/p' "$e"; return 0; }
  done
}
ordem=0
while IFS= read -r alvo_linha; do
  ordem=$((ordem + 1)); kinds=${alvo_linha%%"$tab"*}
  case "$kinds" in ''|*[!pcm]*) continue ;; esac
  topo=$(topo_do_alvo "$alvo_linha")
  if [ -n "$topo" ] && [ -f "$topo/scripts/suite-completa.sh" ]; then
    exige=0
    case "$kinds" in *c*) exige=1 ;; esac
    if [ "$exige" -eq 0 ]; then
      integracao=$(principal_declarada "$topo"); [ -n "$integracao" ] || integracao="main master"
      alvo=$(printf '%s\n' "$comando" | awk -v sq="'" -v integracao="$integracao" -f "$programa_awk")
      case "$(printf '%s\n' "$alvo" | sed -n "$((ordem + 1))p")" in pm*) exige=1 ;; esac  # mesma ordem de alvos da 1a leitura
      branch=$(git -C "$topo" symbolic-ref --short -q HEAD 2>/dev/null) || branch=""
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
      saida=$(cd "$topo" && sh scripts/suite-completa.sh --conferir 2>&1) || bloquear "a suite completa precisa estar verde e registrada para o commit atual antes de abrir ou atualizar a PR para a branch de integracao (Regra 8 de protocolo-tdd). Repositorio conferido: $topo. $saida"
    fi
  fi
done <<EOF
$alvos
EOF

if [ -z "$padroes" ] || [ ! -f "$padroes" ]; then fim; fi
case "$comando" in *"docker run"*|*"docker compose"*|*"docker-compose"*|*"docker exec"*) fim ;; esac

tab=$(printf '\t')
while IFS= read -r linha || [ -n "$linha" ]; do
  case "$linha" in ''|'#'*) continue ;; esac
  padrao=${linha%%"$tab"*}
  motivo=${linha#*"$tab"}
  [ "$motivo" != "$linha" ] || motivo="bloqueado pelo arquivo de padroes"
  [ -n "$(printf '%s' "$padrao" | tr -d ' \t\r')" ] || continue  # so espacos viraria substring de todo comando
  case "$comando" in *"$padrao"*) bloquear "'$padrao': $motivo" ;; esac
done < "$padroes"

fim
