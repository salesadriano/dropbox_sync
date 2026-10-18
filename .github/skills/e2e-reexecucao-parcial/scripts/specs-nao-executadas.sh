#!/usr/bin/env sh
# Uso: sh specs-nao-executadas.sh [--log <arquivo>] [--raiz <dir>] [--clientes a,b] [--specs <subdir>]
#                                 [--extensao <sufixo>] [--saida <arquivo>] [--workflow <nome>]
#
# Passo `if: failure()` do job de E2E da pipeline, e do workflow de reexecucao parcial. Le o log das
# corridas do Cypress (`$RUNNER_TEMP/testes.log` por padrao), separa as corridas pela marca
# `(Run Starting)` na ordem dos clientes (`--clientes`, a ordem dos passos do job; padrao `.`, um
# unico cliente na raiz) e, para cada spec que existe no disco em `<raiz>/<cliente>/<specs>/`
# (padrao `cypress/e2e`, arquivos `*<extensao>`, padrao `.cy.ts`), decide:
#   falhou         - a corrida tem `N) teste` sob o `Running:` dela;
#   executada      - a corrida tem `<check> teste` sob o `Running:` dela e nenhuma falha;
#   nao executada  - sem `Running:`, ou so testes pendentes (`- teste`), que e o que o
#                    `cypress-fail-fast` (estrategia `run`) deixa nas specs depois da primeira falha.
# Spec impressa so pelo nome casa por sufixo `/<nome>` quando nao ha casamento exato; raiz e subpasta
# com o mesmo nome sao ambiguas nesse caso (limite conhecido). Spec inteiramente `it.skip` conta como
# nao executada, porque o log e identico. Codigos de cor do terminal sao removidos antes da leitura.
#
# CONTRATO DE SAIDA (arquivo `--saida`, padrao `diagnostico-e2e/specs-nao-executadas.txt`, relativo
# a raiz; e o mesmo texto no `$GITHUB_STEP_SUMMARY`, se definido). Outro runner que nao o Cypress
# precisa de um parser proprio que produza exatamente estas linhas, por cliente e na ordem dada:
#   # <comentario>                       (linhas iniciadas por `#` sao livres)
#   <cliente> executadas: <n>
#   <cliente> falhou: <a,b,...|nenhuma>
#   <cliente> nao executadas: <a,b,...|nenhuma>
#   <cliente> reexecutar: <falhou,nao executadas|nenhuma>   (caminhos relativos a <specs>/, sem espaco)
#   <cliente>: diretorio <cliente>/<specs> ausente          (no lugar das quatro, quando nao ha specs)
# Nao altera o resultado do job: sai sempre com 0, salvo argumento invalido (2). `--workflow` (padrao
# `e2e-parcial.yml`) so entra no texto do resumo, no comando de disparo da reexecucao parcial.
set -eu

raiz=""; log=""; clientes="."; specs="cypress/e2e"; extensao=".cy.ts"
saida="diagnostico-e2e/specs-nao-executadas.txt"; workflow="e2e-parcial.yml"
while [ $# -gt 0 ]; do
  case "$1" in
    --log) [ $# -ge 2 ] || { echo "--log exige um valor" >&2; exit 2; }; log="$2"; shift 2 ;;
    --raiz) [ $# -ge 2 ] || { echo "--raiz exige um valor" >&2; exit 2; }; raiz="$2"; shift 2 ;;
    --clientes) [ $# -ge 2 ] || { echo "--clientes exige um valor" >&2; exit 2; }; clientes="$2"; shift 2 ;;
    --specs) [ $# -ge 2 ] || { echo "--specs exige um valor" >&2; exit 2; }; specs="$2"; shift 2 ;;
    --extensao) [ $# -ge 2 ] || { echo "--extensao exige um valor" >&2; exit 2; }; extensao="$2"; shift 2 ;;
    --saida) [ $# -ge 2 ] || { echo "--saida exige um valor" >&2; exit 2; }; saida="$2"; shift 2 ;;
    --workflow) [ $# -ge 2 ] || { echo "--workflow exige um valor" >&2; exit 2; }; workflow="$2"; shift 2 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done
[ -n "$raiz" ] || raiz=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
[ -n "$log" ] || log="${RUNNER_TEMP:-/tmp}/testes.log"
case "$saida" in /*) ;; *) saida="$raiz/$saida" ;; esac

ESC=$(printf '\033')
CHECK=$(printf '\342\234\223')
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Classificacao por (corrida, spec impressa): uma linha `corrida<TAB>spec<TAB>estado` por spec vista.
if [ -s "$log" ]; then
  sed -E "s/${ESC}\[[0-9;]*m//g" "$log" | awk -v ok="$CHECK" '
    /\(Run Starting\)/ { corrida++; spec = ""; next }
    corrida > 0 && match($0, /^[ \t]*Running:[ \t]+.*[ \t]+\([0-9]+ of [0-9]+\)[ \t]*$/) {
      s = $0; sub(/^[ \t]*Running:[ \t]+/, "", s); sub(/[ \t]+\([0-9]+ of [0-9]+\)[ \t]*$/, "", s)
      spec = s; chave = corrida SUBSEP spec
      if (!(chave in estado)) { estado[chave] = "nao-executada"; ordem[++n] = chave }
      next
    }
    spec != "" && /^[ \t]+[0-9]+\) / { estado[corrida SUBSEP spec] = "falhou"; next }
    spec != "" && $0 ~ ("^[ \t]+" ok " ") { if (estado[corrida SUBSEP spec] != "falhou") estado[corrida SUBSEP spec] = "executada"; next }
    END { for (i = 1; i <= n; i++) { split(ordem[i], p, SUBSEP); print p[1] "\t" p[2] "\t" estado[ordem[i]] } }
  ' > "$tmp/vistas"
else
  : > "$tmp/vistas"
fi

mkdir -p "$(dirname -- "$saida")"
{
  echo "# specs do E2E por estado, derivado de $(basename -- "$log") (specs-nao-executadas.sh)"
  [ -s "$log" ] || echo "# log ausente ou vazio: nenhuma corrida chegou a comecar"
} > "$saida"

corrida=0
printf '%s\n' "$clientes" | tr ',' '\n' | while IFS= read -r cliente; do
  [ -n "$cliente" ] || continue
  corrida=$((corrida + 1))
  dir="$raiz/$cliente/$specs"
  if [ ! -d "$dir" ]; then
    echo "$cliente: diretorio $cliente/$specs ausente" >> "$saida"
    continue
  fi
  falhou=""; nao=""; executadas=0
  # Lista em arquivo e `while read` por redirecionamento: nome com espaco fica inteiro e os
  # acumuladores sobrevivem (nao ha subshell de pipe).
  (cd "$dir" && find . -name "*$extensao" | sed 's#^\./##' | sort) > "$tmp/arquivos"
  while IFS= read -r arquivo; do
    estado=$(awk -F '\t' -v c="$corrida" -v a="$arquivo" '
      $1 == c && a == $2 { print $3; exato = 1; exit }
      $1 == c && substr(a, length(a) - length($2)) == "/" $2 && sufixo == "" { sufixo = $3 }
      END { if (!exato && sufixo != "") print sufixo }' "$tmp/vistas")
    case "${estado:-nao-executada}" in
      falhou) falhou="${falhou:+$falhou,}$arquivo" ;;
      executada) executadas=$((executadas + 1)) ;;
      *) nao="${nao:+$nao,}$arquivo" ;;
    esac
  done < "$tmp/arquivos"
  reexecutar="$falhou${falhou:+${nao:+,}}$nao"
  {
    echo "$cliente executadas: $executadas"
    echo "$cliente falhou: ${falhou:-nenhuma}"
    echo "$cliente nao executadas: ${nao:-nenhuma}"
    echo "$cliente reexecutar: ${reexecutar:-nenhuma}"
  } >> "$saida"
done

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Specs do E2E que nao rodaram"
    echo
    echo "A corrida para na primeira falha; abaixo, por cliente, o que falhou e o que ficou sem exercicio. Para rodar so isso na branch de release, sem publicar nada: \`gh workflow run $workflow --ref <branch de release> -f specs='<lista>'\`, com a linha \`reexecutar:\` de cada cliente (lista separada por virgula, specs relativas a \`$specs/\`). Um verde ali nao substitui a suite completa nem publica nada."
    echo
    echo '```'
    cat "$saida"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || echo "AVISO: nao foi possivel escrever em GITHUB_STEP_SUMMARY ($GITHUB_STEP_SUMMARY)" >&2
fi
cat "$saida"
exit 0
