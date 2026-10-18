#!/usr/bin/env sh
# Uso: sh conferir-copias.sh [--rotulo <nome>] <arquivo>=<ERE> [<arquivo>=<ERE> ...]
#
# Confere que N copias de um mesmo numero, em arquivos diferentes, dizem o mesmo valor: a constante
# de teste, o bloco de estado do arquivo de instrucoes e o pino de regressao do QA, por exemplo.
# Cada argumento e `<arquivo>=<ERE>`, separado no PRIMEIRO `=`; a ERE tem exatamente um grupo `( )`,
# que e o valor a comparar. Todas as ocorrencias da ERE no arquivo sao lidas: zero ocorrencias e
# erro, e ocorrencias com valores diferentes dentro do mesmo arquivo tambem (duas copias do mesmo
# padrao com valores diferentes e exatamente o defeito a pegar). Depois, todos os arquivos precisam
# concordar.
#
# ISTO E CONSISTENCIA ENTRE COPIAS, NAO MEDICAO. Nenhuma das copias e oraculo: quando o valor real
# muda, quem diz o numero novo e a medicao do projeto; este script so pega a copia que ficou para
# tras ou a constante que se fundiu "sem conflito e errada" na juncao de duas frentes.
#
# Saida: `<ok> <rotulo>: <valor> igual em <n> copia(s)` e exit 0; lista `- <arquivo>: <valor>` e
# `<erro> <rotulo>: copias divergem` com exit 1 (tambem 1 para padrao ausente ou duplicado
# divergente); exit 2 em argumento invalido (sem `=`, ERE sem exatamente um grupo, menos de dois
# argumentos, arquivo inexistente). Limite: o grupo e contado por `(` fora de escape; `(` dentro de
# colchetes conta como grupo.
set -eu

rotulo="copias"
if [ "${1:-}" = "--rotulo" ]; then
  [ $# -ge 2 ] || { echo "--rotulo exige um valor" >&2; exit 2; }
  rotulo="$2"; shift 2
fi
[ $# -ge 2 ] || { echo "informe pelo menos duas copias, cada uma como <arquivo>=<ERE>" >&2; exit 2; }

for arg in "$@"; do
  case "$arg" in
    --*) echo "opcao desconhecida: $arg" >&2; exit 2 ;;
    *=*) ;;
    *) echo "esperava <arquivo>=<ERE>, recebi: $arg" >&2; exit 2 ;;
  esac
  arquivo="${arg%%=*}"; ere="${arg#*=}"
  [ -f "$arquivo" ] || { echo "arquivo nao encontrado: $arquivo" >&2; exit 2; }
  grupos=$(printf '%s' "$ere" | sed 's/\\.//g' | tr -cd '(' | wc -c | tr -d ' ')
  [ "$grupos" -eq 1 ] || { echo "a ERE precisa ter exatamente um grupo ( ), achei $grupos: $ere" >&2; exit 2; }
done

# O delimitador do sed e \001 para que a ERE possa conter `/`, `|` e `#`.
D=$(printf '\001')
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

for arg in "$@"; do
  arquivo="${arg%%=*}"; ere="${arg#*=}"
  valores=$(grep -Eo -- "$ere" "$arquivo" | sed -E "s${D}^(${ere})\$${D}\\2${D}" | sort -u)
  if [ -z "$valores" ]; then
    printf '\342\234\226 nao achei %s em %s\n' "$ere" "$arquivo"
    exit 1
  fi
  if [ "$(printf '%s\n' "$valores" | wc -l)" -gt 1 ]; then
    vezes=$(grep -Eo -- "$ere" "$arquivo" | wc -l | tr -d ' ')
    lista=$(printf '%s\n' "$valores" | paste -sd, - | sed 's/,/, /g')
    printf '\342\234\226 %s aparece %s vez(es) com valores diferentes em %s: %s\n' "$ere" "$vezes" "$arquivo" "$lista"
    exit 1
  fi
  printf '%s\t%s\n' "$arquivo" "$valores" >> "$tmp"
done

distintos=$(cut -f 2 "$tmp" | sort -u | wc -l | tr -d ' ')
copias=$(wc -l < "$tmp" | tr -d ' ')
if [ "$distintos" -eq 1 ]; then
  printf '\342\234\224 %s: %s igual em %s copia(s)\n' "$rotulo" "$(head -n 1 "$tmp" | cut -f 2)" "$copias"
  exit 0
fi
sed 's/^\(.*\)\t\(.*\)$/- \1: \2/' "$tmp"
printf '\342\234\226 %s: copias divergem\n' "$rotulo"
exit 1
