#!/usr/bin/env sh
# Extrato de memoria por papel e por assunto, com teto de tamanho (regras 1, 43 e 49 do AGENTS.md).
# E o que o Tech Lead transpoe na delegacao e o que o hook SubagentStart injeta: as entradas ativas
# pertinentes ao papel, ordenadas por relevancia aos termos da demanda (ou por data, sem termos),
# cortadas no teto de bytes. O que ficou de fora e listado por id, para que o agent peca o que faltar
# em vez de abrir a memoria inteira (ate 12 ids; o resto vira contagem). O script so le.
#
# Uso:
#   sh scripts/memoria-extrato.sh --papel qa-expert --termos "turno alocacao presenca"
#   sh scripts/memoria-extrato.sh --papel dba --max-bytes 8000 --max-entradas 6
#   sh scripts/memoria-extrato.sh --papel senior-developer --desde 2026-09-01
#   --papel <p>         obrigatorio: tech-lead | senior-developer | qa-expert | ux-expert | dba | business-analyst |
#                       documentation-writer | commit-writer. Entradas com `agentes: todos` entram para qualquer papel;
#                       o tech-lead ve todas as entradas ativas.
#   --termos "<a b c>"  palavras da demanda (sem distincao de maiusculas); a pontuacao e: 3 por termo no titulo,
#                       1 por termo no corpo, +1 para decisao de pacote. Sem termos, ordena por data (mais nova primeiro).
#   --max-bytes <n>     teto do extrato (padrao 12000); a entrada que nao couber inteira fica de fora e e listada.
#   --max-entradas <n>  teto de entradas (padrao 10).
#   --desde <data>      so entradas com data no nome >= YYYY-MM-DD.
#   --entradas <dir>    diretorio das entradas (padrao: .github/agents/memoria/entradas, senao .claude/ai_team/memoria/entradas).
#
# Saida: blocos `## <id>` como em `memoria-index.sh --corpo`, depois uma linha
#   extrato: <k> de <n> entradas pertinentes, <bytes> bytes | omitidas: <ids...>
# Exit: 0; 2 em uso invalido; 1 sem diretorio de entradas.

set -u
papel=""; termos=""; max_bytes=12000; max_entradas=10; desde=""; dir=""
AGENTES="tech-lead senior-developer qa-expert ux-expert dba business-analyst documentation-writer commit-writer"
while [ $# -gt 0 ]; do
  case "$1" in
    --papel) [ $# -ge 2 ] || { echo "--papel exige um valor" >&2; exit 2; }; papel="$2"; shift 2 ;;
    --termos) [ $# -ge 2 ] || { echo "--termos exige um valor" >&2; exit 2; }; termos="$2"; shift 2 ;;
    --max-bytes) [ $# -ge 2 ] || { echo "--max-bytes exige um valor" >&2; exit 2; }; max_bytes="$2"; shift 2 ;;
    --max-entradas) [ $# -ge 2 ] || { echo "--max-entradas exige um valor" >&2; exit 2; }; max_entradas="$2"; shift 2 ;;
    --desde) [ $# -ge 2 ] || { echo "--desde exige um valor" >&2; exit 2; }; desde="$2"; shift 2 ;;
    --entradas) [ $# -ge 2 ] || { echo "--entradas exige um valor" >&2; exit 2; }; dir="$2"; shift 2 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done
[ -n "$papel" ] || { echo "--papel e obrigatorio" >&2; exit 2; }
case " $AGENTES " in *" $papel "*) ;; *) echo "papel desconhecido: $papel (validos: $AGENTES)" >&2; exit 2 ;; esac
case "$max_bytes" in ''|*[!0-9]*) echo "--max-bytes exige um inteiro" >&2; exit 2 ;; esac
case "$max_entradas" in ''|*[!0-9]*) echo "--max-entradas exige um inteiro" >&2; exit 2 ;; esac
desde_n=""
if [ -n "$desde" ]; then
  case "$desde" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) desde_n=$(printf '%s' "$desde" | tr -d -) ;; *) echo "data invalida em --desde: $desde" >&2; exit 2 ;; esac
fi
if [ -z "$dir" ]; then
  raiz=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
  dir="$raiz/.github/agents/memoria/entradas"
  [ -d "$dir" ] || dir="$raiz/.claude/ai_team/memoria/entradas"
fi
[ -d "$dir" ] || { echo "diretorio de entradas nao encontrado: $dir" >&2; exit 1; }

termos_min=$(printf '%s' "$termos" | tr '[:upper:]' '[:lower:]')

# Uma linha por entrada pertinente: pontuacao, data (do nome), id, bytes do arquivo. Um unico awk sobre todos
# os arquivos: por entrada, um processo a mais custaria segundos em memorias com centenas de entradas.
pontuar() {
  set -- "$dir"/*.md
  [ -f "$1" ] || return 0
  # shellcheck disable=SC2016
  awk -v papel="$papel" -v termos="$termos_min" -v desde_n="$desde_n" '
    function emitir() {
      if (nome == "" || nome == "README") return
      if (desde_n != "" && substr(gsubdata(nome), 1, 8) + 0 < desde_n + 0) return
      if (st != "ativa") return
      gsub(/ /, "", ag); ag="," ag ","
      if (papel != "tech-lead" && index(ag, ",todos,")==0 && index(ag, "," papel ",")==0) return
      p=0
      if (t=="decisao" && e=="pacote") p+=1
      n=split(minus(termos), T, /[ \t]+/)
      lti=minus(ti); lco=minus(corpo)
      for (i=1;i<=n;i++) { if (T[i]=="") continue; if (index(lti, T[i])>0) p+=3; if (index(lco, T[i])>0) p+=1 }
      printf "%d\t%s\t%s\t%d\n", p, substr(nome,1,15), nome, bytes
    }
    function gsubdata(n,   d) { d=substr(n,1,10); gsub(/-/, "", d); return d }
    # tolower do awk so rebaixa ASCII: as maiusculas acentuadas do portugues sao mapeadas a mao (bytes UTF-8).
    function minus(s) {
      s=tolower(s)
      gsub(/\303\201/, "\303\241", s); gsub(/\303\200/, "\303\240", s); gsub(/\303\202/, "\303\242", s); gsub(/\303\203/, "\303\243", s)
      gsub(/\303\211/, "\303\251", s); gsub(/\303\212/, "\303\252", s); gsub(/\303\215/, "\303\255", s)
      gsub(/\303\223/, "\303\263", s); gsub(/\303\224/, "\303\264", s); gsub(/\303\225/, "\303\265", s)
      gsub(/\303\232/, "\303\272", s); gsub(/\303\207/, "\303\247", s)
      return s
    }
    FNR==1 { emitir(); nome=FILENAME; sub(/.*\//, "", nome); sub(/\.md$/, "", nome); fm=0; st=""; ag=""; t=""; e=""; ti=""; corpo=""; bytes=0 }
    { bytes += length($0) + 1 }
    FNR==1 && $0=="---" { fm=1; next }
    fm==1 && $0=="---" { fm=2; next }
    fm==1 {
      k=$0; sub(/:.*/, "", k); v=$0; sub(/^[^:]*:[ ]*/, "", v)
      if (k=="status") st=v; else if (k=="agentes") ag=v; else if (k=="tipo") t=v; else if (k=="escopo") e=v; else if (k=="titulo") ti=v
      next
    }
    fm==2 { corpo = corpo " " $0 }
    END { emitir() }' "$dir"/*.md
}

lista=$(pontuar | sort -t "$(printf '\t')" -k1,1nr -k2,2r)
total=$(printf '%s\n' "$lista" | grep -c . || true)
[ "$total" -gt 0 ] || { echo "extrato: 0 de 0 entradas pertinentes, 0 bytes | omitidas: nenhuma"; exit 0; }

usados=0; k=0
printf '%s\n' "$lista" | while IFS="$(printf '\t')" read -r _p _d nome bytes; do
  [ -n "$nome" ] || continue
  if [ "$k" -lt "$max_entradas" ] && [ $((usados + bytes)) -le "$max_bytes" ]; then
    f="$dir/$nome.md"
    awk 'BEGIN{fm=0} NR==1 && $0=="---"{fm=1;next} fm==1 && $0=="---"{fm=2;next}
      fm==1 { k=$0; sub(/:.*/, "", k); v=$0; sub(/^[^:]*:[ ]*/, "", v); if (k=="id") id=v; else if (k=="tipo") t=v; else if (k=="escopo") e=v; else if (k=="agentes") ag=v; else if (k=="titulo") ti=v; else if (k=="substitui") s=v; else if (k=="regra") r=v; else if (k=="ref") rf=v; next }
      fm==2 { c = c $0 "\n" }
      END { printf "## %s\n\n- tipo: %s | escopo: %s | agentes: %s%s%s%s\n- titulo: %s\n\n%s\n", id, t, e, ag, (s!=""?" | substitui: " s:""), (r!=""?" | regra: " r:""), (rf!=""?" | ref: " rf:""), ti, c }' "$f"
    usados=$((usados + bytes)); k=$((k + 1))
    echo "$k $usados" > "${TMPDIR:-/tmp}/memoria-extrato.$$"
  else
    printf '%s\n' "$nome" >> "${TMPDIR:-/tmp}/memoria-extrato.$$.omitidas"
  fi
done
if [ -f "${TMPDIR:-/tmp}/memoria-extrato.$$" ]; then read -r k usados < "${TMPDIR:-/tmp}/memoria-extrato.$$"; fi
om="nenhuma"
if [ -f "${TMPDIR:-/tmp}/memoria-extrato.$$.omitidas" ]; then
  om=$(head -12 "${TMPDIR:-/tmp}/memoria-extrato.$$.omitidas" | tr '\n' ' ' | sed 's/ $//')
  n_om=$(grep -c . "${TMPDIR:-/tmp}/memoria-extrato.$$.omitidas"); [ "$n_om" -le 12 ] || om="$om (+$((n_om - 12)) mais; peca ao Tech Lead por assunto)"
fi
rm -f "${TMPDIR:-/tmp}/memoria-extrato.$$" "${TMPDIR:-/tmp}/memoria-extrato.$$.omitidas"
echo "extrato: $k de $total entradas pertinentes, $usados bytes | omitidas: $om"
exit 0
