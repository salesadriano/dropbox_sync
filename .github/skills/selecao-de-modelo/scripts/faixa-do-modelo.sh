#!/usr/bin/env sh
# Decide a faixa do modelo de uma delegacao pela classe da tarefa, nao pelo papel que a executa.
#
# Uso: sh faixa-do-modelo.sh --classe <classe> [--porte P|M|G] [--toca <lista>] [--critico] [--tabela <tsv>]
#      sh faixa-do-modelo.sh --classes            # lista as classes e a faixa minima de cada uma
#
# Faixas: economico (renderiza o que ja foi decidido), padrao (implementa, testa, valida, analisa),
# maximo (decide o que e caro errar: modelo de dados, arquitetura, seguranca, protocolo).
# A faixa minima vem da classe. Sobe, nunca desce:
#   --toca schema|auth|segredo|fronteira     -> maximo     (criterios que tiram a demanda de P, fluxo-p.md)
#   --toca contrato|dado-sensivel|pipeline|dependencia -> padrao
#   --porte G                                -> padrao vira maximo (economico continua: renderizar e renderizar)
#   --critico                                -> maximo
# --toca aceita lista separada por virgula (espaco apos a virgula e tolerado; item repetido conta uma vez).
# Saida: `faixa: <faixa>`, `motivo: <classe e o que subiu>` e, com tabela, `modelo: <alias> (<id>)`.
# Exit: 0 ok, 2 uso invalido (classe desconhecida, item de --toca desconhecido, porte invalido), 1 erro.
# Tabela: --tabela, ou scripts/tabela-de-modelos.tsv ao lado do script, ou references/tabela-de-modelos.exemplo.tsv.
set -eu

aqui=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
classe=""; porte=""; toca=""; critico=0; tabela=""; listar=0

# classe<TAB>faixa minima
CLASSES='redacao	economico
commit	economico
log-de-prompt	economico
sincronizacao-documental	economico
indice	economico
limpeza	economico
formatacao	economico
resumo	economico
transcricao	economico
implementacao	padrao
teste	padrao
validacao-qa	padrao
revisao	padrao
requisitos	padrao
ux	padrao
conformidade	padrao
analise	padrao
modelo-de-dados	maximo
arquitetura	maximo
seguranca	maximo
decisao-de-protocolo	maximo
migracao	maximo
integracao-externa	maximo
resolucao-de-conflito	maximo
planejamento-g	maximo'

while [ $# -gt 0 ]; do
  case "$1" in
    --classe) [ $# -ge 2 ] || { echo "--classe exige um valor" >&2; exit 2; }; classe="$2"; shift 2 ;;
    --porte) [ $# -ge 2 ] || { echo "--porte exige um valor" >&2; exit 2; }; porte="$2"; shift 2 ;;
    --toca) [ $# -ge 2 ] || { echo "--toca exige um valor" >&2; exit 2; }; toca="$2"; shift 2 ;;
    --critico) critico=1; shift ;;
    --tabela) [ $# -ge 2 ] || { echo "--tabela exige um valor" >&2; exit 2; }; tabela="$2"; shift 2 ;;
    --classes) listar=1; shift ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

if [ "$listar" -eq 1 ]; then printf '%s\n' "$CLASSES" | tr '\t' ' '; exit 0; fi
[ -n "$classe" ] || { echo "informe --classe <classe> (ou --classes para listar)" >&2; exit 2; }

nivel() { case "$1" in economico) echo 1 ;; padrao) echo 2 ;; maximo) echo 3 ;; esac; }
nome() { case "$1" in 1) echo economico ;; 2) echo padrao ;; 3) echo maximo ;; esac; }

faixa=$(printf '%s\n' "$CLASSES" | awk -F'\t' -v c="$classe" '$1 == c { print $2; exit }')
[ -n "$faixa" ] || { echo "classe desconhecida: $classe (sh $0 --classes lista as validas)" >&2; exit 2; }
n=$(nivel "$faixa"); motivo="classe $classe e $faixa"

case "$porte" in
  ""|P|M) ;;
  G) if [ "$n" -eq 2 ]; then n=3; motivo="$motivo; porte G sobe padrao para maximo"; fi ;;
  *) echo "porte invalido: $porte (P, M ou G)" >&2; exit 2 ;;
esac

if [ -n "$toca" ]; then
  for t in $(printf '%s' "$toca" | tr ',' ' '); do
    case "$t" in
      schema|auth|segredo|fronteira) m=3 ;;
      contrato|dado-sensivel|pipeline|dependencia) m=2 ;;
      *) echo "item desconhecido em --toca: $t (schema, auth, segredo, fronteira, contrato, dado-sensivel, pipeline, dependencia)" >&2; exit 2 ;;
    esac
    if [ "$m" -gt "$n" ]; then n=$m; motivo="$motivo; toca $t sobe para $(nome "$n")"; fi
  done
fi

if [ "$critico" -eq 1 ] && [ "$n" -lt 3 ]; then n=3; motivo="$motivo; critico sobe para maximo"; fi
faixa=$(nome "$n")

echo "faixa: $faixa"
echo "motivo: $motivo"

[ -n "$tabela" ] || { if [ -f "$aqui/tabela-de-modelos.tsv" ]; then tabela="$aqui/tabela-de-modelos.tsv"; elif [ -f "$aqui/../references/tabela-de-modelos.exemplo.tsv" ]; then tabela="$aqui/../references/tabela-de-modelos.exemplo.tsv"; fi; }
if [ -n "$tabela" ]; then
  [ -f "$tabela" ] || { echo "tabela nao encontrada: $tabela" >&2; exit 1; }
  linha=$(awk -F'\t' -v f="$faixa" '$0 !~ /^#/ && NF >= 3 && $1 == f { print $2 " (" $3 ")"; exit }' "$tabela")
  [ -n "$linha" ] || { echo "tabela sem linha para a faixa $faixa: $tabela" >&2; exit 1; }
  echo "modelo: $linha"
fi
