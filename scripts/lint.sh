#!/usr/bin/env sh
# Lint do projeto: um `shellcheck` por arquivo, com teto de memoria por processo e paralelismo baixo.
#
# Uso: sh scripts/lint.sh [arquivo...]
#
# Sem argumentos, analisa lib/*.sh commands/*.sh bin/* scripts/*.sh. Com `external-sources=true` no
# `.shellcheckrc`, cada arquivo reanalisa a cadeia de `source`: `bin/dbx` sozinho chega a 4,5 GB, e um
# processo unico sobre todos os arquivos passou de 18 GB e travou a maquina (OOM em 2026-10-21).
# LINT_PARALELO (padrao 1, porque `commands/download.sh` sozinho chega a 9 GB) limita os processos simultaneos;
# LINT_MEMORIA_MB (padrao 12288) e o teto de cada um, por `systemd-run --user` ou, sem ele, `ulimit -v`.
# Saida: 0 sem achados; 1 com achado ou processo morto pelo teto; 2 sem shellcheck ou variavel invalida.

set -eu

if [ "${1:-}" = --um ]; then
  sc=$2; mb=$3; f=$4
  if [ "${LINT_SEM_SYSTEMD:-0}" = 0 ] && systemd-run --user --quiet --wait --collect --pipe true >/dev/null 2>&1; then
    rc=0; out=$(systemd-run --user --quiet --wait --collect --pipe --same-dir \
      -p MemoryMax="${mb}M" -p MemorySwapMax=0 "$sc" "$f" 2>&1) || rc=$?
  else
    rc=0
    # shellcheck disable=SC3045 # dash e bash aceitam `ulimit -v`; e so o fallback sem systemd.
    out=$(ulimit -v $((mb * 1024)); "$sc" "$f" 2>&1) || rc=$?
  fi
  [ -n "$out" ] && printf '%s\n' "$out"
  # Morto pelo teto, o systemd-run sai com 1 e sem texto; achado do shellcheck sai com 1 e com texto.
  if [ "$rc" -ne 0 ] && { [ "$rc" -ne 1 ] || [ -z "$out" ]; }; then
    echo "lint: $f interrompido (saida $rc; teto de ${mb} MB?)" >&2
  fi
  [ "$rc" -eq 0 ] || exit 1
  exit 0
fi

eu=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
sc=$(command -v shellcheck) || { echo "shellcheck nao encontrado" >&2; exit 2; }
[ $# -gt 0 ] || { cd "$(dirname "$eu")/.."; set -- lib/*.sh commands/*.sh bin/* scripts/*.sh; }
paralelo=${LINT_PARALELO:-1}; mb=${LINT_MEMORIA_MB:-12288}
# `xargs -P 0` e paralelismo ilimitado: exatamente o estouro que este script evita.
case "$paralelo,$mb" in
  *[!0-9,]*|,*|*,|0*|*,0*) echo "LINT_PARALELO e LINT_MEMORIA_MB: inteiros >= 1" >&2; exit 2 ;;
esac
rc=0
printf '%s\0' "$@" | xargs -0 -n 1 -P "$paralelo" sh "$eu" --um "$sc" "$mb" || rc=1
exit "$rc"
