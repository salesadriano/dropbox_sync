#!/usr/bin/env sh
# Avalia se delegar uma tarefa a outro modelo compensa, descontado o custo de transpor o contexto.
#
# Uso: sh avaliar-troca-de-modelo.sh --de <faixa|alias> --para <faixa|alias> --saida <tokens>
#        [--leitura <tokens>] [--cache <tokens>] [--transposicao <tokens> | --pacote <arquivo>]
#        [--retorno <tokens>] [--retrabalho <0-100>] [--tabela <tsv>]
#
# Um subagent comeca vazio: o que atravessa a troca e o pacote de transposicao (regras 42 e 43), e o que
# ficou em cache no modelo atual vira entrada nova no outro (cache e por modelo). O calculo compara:
#   ficar  = leitura*in(A) + cache*cache(A) + saida*out(A)
#   trocar = transposicao*out(A)                       escrever o pacote, no modelo atual
#          + (transposicao + leitura + cache)*in(B)    o outro modelo le o pacote e o que o atual ja tinha
#          + saida*out(B)
#          + retorno*in(A)                             o modelo atual le o resultado de volta
#          + retrabalho% * ficar                       chance de refazer no modelo atual
# Tokens: --saida e o que a tarefa produz; --leitura e o que ela precisa ler de qualquer modo (arquivos, diff);
# --cache e o que o modelo atual ja tem em cache e a tarefa reusaria; --retorno e o tamanho do resultado que
# volta (padrao: 10% da saida, minimo 200). --pacote estima a transposicao por bytes/4 (heuristica declarada;
# `count_tokens` da API mede exato). Precos em USD por milhao de tokens, da tabela (ver faixa-do-modelo.sh).
# Saida: ficar, trocar, economia (USD e %), ponto de equilibrio da transposicao e `veredito: TROCAR|FICAR`.
# Exit: 0 trocar compensa, 3 ficar, 2 uso invalido, 1 erro. A economia nunca desce a faixa minima da classe:
# isso e decisao de faixa-do-modelo.sh, nao deste script.
set -eu

aqui=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
de=""; para=""; saida=""; leitura=0; cache=0; transposicao=""; pacote=""; retorno=""; retrabalho=0; tabela=""

inteiro() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }
valor() { [ $# -ge 2 ] || { echo "$1 exige um valor" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --de) valor "$@"; de="$2"; shift 2 ;;
    --para) valor "$@"; para="$2"; shift 2 ;;
    --saida) valor "$@"; saida="$2"; shift 2 ;;
    --leitura) valor "$@"; leitura="$2"; shift 2 ;;
    --cache) valor "$@"; cache="$2"; shift 2 ;;
    --transposicao) valor "$@"; transposicao="$2"; shift 2 ;;
    --pacote) valor "$@"; pacote="$2"; shift 2 ;;
    --retorno) valor "$@"; retorno="$2"; shift 2 ;;
    --retrabalho) valor "$@"; retrabalho="$2"; shift 2 ;;
    --tabela) valor "$@"; tabela="$2"; shift 2 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$de" ] || [ -z "$para" ]; then echo "informe --de e --para (faixa ou alias da tabela)" >&2; exit 2; fi
[ -n "$saida" ] || { echo "informe --saida <tokens> (o que a tarefa produz)" >&2; exit 2; }
for v in "$saida" "$leitura" "$cache" "$retrabalho"; do inteiro "$v" || { echo "valor nao inteiro: $v" >&2; exit 2; }; done
[ "$retrabalho" -le 100 ] || { echo "--retrabalho e percentual de 0 a 100: $retrabalho" >&2; exit 2; }
if [ -n "$pacote" ]; then
  [ -z "$transposicao" ] || { echo "use --transposicao ou --pacote, nao os dois" >&2; exit 2; }
  [ -f "$pacote" ] || { echo "pacote nao encontrado: $pacote" >&2; exit 1; }
  transposicao=$(( ($(wc -c < "$pacote") + 3) / 4 ))
fi
[ -n "$transposicao" ] || { echo "informe --transposicao <tokens> ou --pacote <arquivo>" >&2; exit 2; }
inteiro "$transposicao" || { echo "valor nao inteiro: $transposicao" >&2; exit 2; }
if [ -z "$retorno" ]; then retorno=$(( saida / 10 )); [ "$retorno" -ge 200 ] || retorno=200; fi
inteiro "$retorno" || { echo "valor nao inteiro: $retorno" >&2; exit 2; }

[ -n "$tabela" ] || { if [ -f "$aqui/tabela-de-modelos.tsv" ]; then tabela="$aqui/tabela-de-modelos.tsv"; else tabela="$aqui/../references/tabela-de-modelos.exemplo.tsv"; fi; }
[ -f "$tabela" ] || { echo "tabela nao encontrada: $tabela" >&2; exit 1; }

# Linha da tabela por faixa (primeira) ou por alias: "alias id in out cache".
modelo() {
  awk -F'\t' -v k="$1" '$0 !~ /^#/ && NF >= 6 && ($1 == k || $2 == k) { print $2, $3, $4, $5, $6; exit }' "$tabela"
}
A=$(modelo "$de"); [ -n "$A" ] || { echo "modelo desconhecido na tabela: $de" >&2; exit 2; }
B=$(modelo "$para"); [ -n "$B" ] || { echo "modelo desconhecido na tabela: $para" >&2; exit 2; }
# shellcheck disable=SC2086 # campos separados por espaco, vindos do awk; e o split desejado
set -- $A; aliasA=$1; idA=$2; inA=$3; outA=$4; cacheA=$5
# shellcheck disable=SC2086
set -- $B; aliasB=$1; idB=$2; inB=$3; outB=$4

echo "de: $aliasA ($idA)"
echo "para: $aliasB ($idB)"
echo "tokens: saida=$saida leitura=$leitura cache=$cache transposicao=$transposicao retorno=$retorno retrabalho=${retrabalho}%"

if [ "$idA" = "$idB" ]; then
  echo "veredito: FICAR (mesmo modelo; a troca so custaria a transposicao)"
  exit 3
fi

awk -v saida="$saida" -v leitura="$leitura" -v cache="$cache" -v T="$transposicao" -v retorno="$retorno" -v r="$retrabalho" \
    -v inA="$inA" -v outA="$outA" -v cacheA="$cacheA" -v inB="$inB" -v outB="$outB" 'BEGIN {
  M = 1000000
  ficar  = (leitura * inA + cache * cacheA + saida * outA) / M
  fixo   = ((leitura + cache) * inB + saida * outB + retorno * inA) / M + ficar * r / 100
  porT   = (outA + inB) / M
  trocar = fixo + T * porT
  econ   = ficar - trocar
  pct    = ficar > 0 ? econ / ficar * 100 : 0
  printf "ficar: %.4f USD\n", ficar
  printf "trocar: %.4f USD\n", trocar
  printf "economia: %.4f USD (%.1f%%)\n", econ, pct
  eq = (ficar - fixo) / porT
  if (eq < 0) printf "equilibrio: nenhum (trocar nao compensa nem com transposicao zero)\n"
  else printf "equilibrio: transposicao de ate %d tokens\n", int(eq)
  if (econ > 0) { print "veredito: TROCAR"; exit 0 } else { print "veredito: FICAR"; exit 3 }
}'
