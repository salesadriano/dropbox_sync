#!/usr/bin/env sh
# Roda a suite completa pelo comando oficial do projeto e registra o resultado para o commit atual, para
# que o guarda de comandos (regra 3 de guarda-de-comandos.sh) libere o push para a PR de main/master e o
# `gh pr create` so com a suite verde sobre o que vai ser enviado (Regra 8 de protocolo-tdd).
#
# Uso: sh scripts/suite-completa.sh -- <comando oficial e argumentos>   # roda e registra; exit = o do comando
#      sh scripts/suite-completa.sh                                     # idem, com o comando de scripts/suite-completa.cmd
#      sh scripts/suite-completa.sh --conferir                          # exit 0 se ha registro verde e limpo para HEAD; 3 se nao
#      sh scripts/suite-completa.sh --mostrar                           # imprime os registros deste worktree
#
# Registro: `<git-dir>/agentes-suite-completa` (por worktree, fora do versionamento), uma linha por execucao:
#   <sha do HEAD> <limpo|sujo> <exit> <data ISO> <segundos>
# `sujo` = havia alteracao em arquivo rastreado quando a suite rodou (a suite nao testou o commit que vai
# ser enviado); arquivo novo nao rastreado nao conta e e so lembrado na saida. --conferir aceita apenas a
# ultima linha cujo sha e o HEAD atual, com `limpo` e exit 0. Commit novo invalida o registro: rode de novo.
# O comando e executado como recebido ("$@"), sem eval; o conteudo de scripts/suite-completa.cmd e do
# projeto e roda por `sh -c`, como um script versionado. Exit: 2 uso invalido, 1 fora de repositorio ou
# sem HEAD; no modo de execucao, o exit do proprio comando.
set -u

modo=run
case "${1:-}" in
  --conferir) modo=conferir; shift ;;
  --mostrar) modo=mostrar; shift ;;
  --) shift ;;
  --*) echo "argumento desconhecido: $1" >&2; exit 2 ;;
esac
[ "$modo" = run ] || [ $# -eq 0 ] || { echo "$modo nao aceita argumentos" >&2; exit 2; }

topo=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "fora de um repositorio git" >&2; exit 1; }
gd=$(git rev-parse --absolute-git-dir 2>/dev/null) || exit 1
registro="$gd/agentes-suite-completa"
cabeca=$(git rev-parse -q --verify HEAD 2>/dev/null) || { echo "repositorio sem commit (HEAD inexistente)" >&2; exit 1; }

case "$modo" in
  mostrar)
    if [ -s "$registro" ]; then cat "$registro"; else echo "sem registro de suite completa neste worktree"; fi
    exit 0 ;;
  conferir)
    linha=$(awk -v h="$cabeca" '$1 == h { l = $0 } END { print l }' "$registro" 2>/dev/null)
    if [ -z "$linha" ]; then
      echo "sem registro da suite completa para o commit atual ($(git rev-parse --short HEAD)): rode sh scripts/suite-completa.sh -- <comando oficial>" >&2; exit 3
    fi
    # shellcheck disable=SC2086 # campos separados por espaco, gravados por este script
    set -- $linha
    [ $# -ge 5 ] || { echo "registro da suite completa malformado para o commit atual: rode sh scripts/suite-completa.sh -- <comando oficial>" >&2; exit 3; }
    [ "$2" = limpo ] || { echo "a suite completa rodou com alteracao nao commitada em arquivo rastreado ($4): commit e rode de novo" >&2; exit 3; }
    [ "$3" -eq 0 ] || { echo "a ultima suite completa deste commit ficou vermelha (exit $3, $4): corrija e rode de novo" >&2; exit 3; }
    echo "suite completa verde para $(git rev-parse --short HEAD) em $4 (${5}s)"
    exit 0 ;;
esac

# modo run
if [ $# -eq 0 ]; then
  if [ -s "$topo/scripts/suite-completa.cmd" ]; then
    set -- sh -c "$(cat "$topo/scripts/suite-completa.cmd")"
  else
    echo "informe o comando oficial apos -- (ou grave-o em scripts/suite-completa.cmd)" >&2; exit 2
  fi
fi

if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then estado=sujo; else estado=limpo; fi
if [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
  echo "aviso: ha arquivo nao rastreado; ele nao vai no push e nao conta como sujo" >&2
fi

inicio=$(date +%s)
(cd "$topo" && "$@"); codigo=$?
fim=$(date +%s)
data=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s %s %s %s %s\n' "$cabeca" "$estado" "$codigo" "$data" "$((fim - inicio))" >> "$registro"
if [ "$codigo" -eq 0 ] && [ "$estado" = limpo ]; then
  echo "suite completa: verde, registrada para $(git rev-parse --short HEAD) ($((fim - inicio))s)"
elif [ "$codigo" -eq 0 ]; then
  echo "suite completa: verde, mas com alteracao nao commitada em arquivo rastreado: registrada como suja; commit e rode de novo antes do push" >&2
else
  echo "suite completa: vermelha (exit $codigo), registrada para $(git rev-parse --short HEAD); o push para a PR fica bloqueado ate ficar verde" >&2
fi
exit "$codigo"
