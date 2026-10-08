#!/usr/bin/env sh
# Gera o indice consolidado das entradas de memoria (.github/agents/memoria/entradas/*.md).
# O indice e derivado, nunca editado a mao e nunca versionado: cada sessao o regenera no bootstrap.
#
# Uso:
#   sh scripts/memoria-index.sh                      # tabela markdown de todas as entradas ativas
#   sh scripts/memoria-index.sh --escopo projeto     # filtra por escopo: pacote | projeto
#   sh scripts/memoria-index.sh --tipo decisao       # filtra por tipo: decisao | aceite | bloqueio | backlog | stack | contexto | reserva
#   sh scripts/memoria-index.sh --tipo reserva       # reservas de escopo ativas das demais instancias (regra 47)
#   sh scripts/memoria-index.sh --status todas       # inclui substituidas e encerradas (padrao: so ativas)
#   sh scripts/memoria-index.sh --agente qa-expert   # so entradas pertinentes ao agente (campo agentes:); tech-lead ve tudo
#   sh scripts/memoria-index.sh --agente dba --corpo # extrato com o corpo de cada entrada, para o Tech Lead transpor na delegacao
#   sh scripts/memoria-index.sh --check              # valida frontmatter e unicidade de id; exit 1 em erro
#   sh scripts/memoria-index.sh --write              # grava .github/agents/memoria/INDICE.md (ignorado pelo git)

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
dir="$repo_root/.github/agents/memoria/entradas"
out="$repo_root/.github/agents/memoria/INDICE.md"

escopo=""; tipo=""; status="ativa"; agente=""; corpo=0; check=0; write=0
AGENTES="tech-lead senior-developer qa-expert ux-expert dba business-analyst documentation-writer commit-writer todos"
while [ $# -gt 0 ]; do
  case "$1" in
    --escopo) escopo="$2"; shift 2 ;;
    --tipo) tipo="$2"; shift 2 ;;
    --status) status="$2"; shift 2 ;;
    --agente) agente="$2"; shift 2 ;;
    --corpo) corpo=1; shift ;;
    --check) check=1; shift ;;
    --write) write=1; shift ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

[ -d "$dir" ] || { echo "diretorio nao encontrado: $dir" >&2; exit 1; }
if [ -n "$agente" ]; then
  case " $AGENTES " in *" $agente "*) ;; *) echo "agente desconhecido: $agente (validos: $AGENTES)" >&2; exit 2 ;; esac
  [ "$agente" != "todos" ] || agente=""
  [ "$agente" != "tech-lead" ] || agente=""   # o Tech Lead carrega toda a memoria
fi

# Extrai frontmatter de cada arquivo em uma linha TSV: arquivo, id, tipo, escopo, data, dono, status, substitui, regra, titulo, agentes, origem, instancia
extract() {
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in README.md) continue ;; esac
    awk -v file="$(basename "$f" .md)" '
      BEGIN { fm=0; id=""; t=""; e=""; d=""; o=""; s=""; sub_=""; r=""; ti=""; ag=""; og=""; inst="" }
      NR==1 && $0=="---" { fm=1; next }
      fm==1 && $0=="---" { fm=2; next }
      fm==1 {
        key=$0; sub(/:.*/, "", key); val=$0; sub(/^[^:]*:[ ]*/, "", val)
        if (key=="id") id=val; else if (key=="tipo") t=val; else if (key=="escopo") e=val;
        else if (key=="data") d=val; else if (key=="dono") o=val; else if (key=="status") s=val;
        else if (key=="substitui") sub_=val; else if (key=="regra") r=val; else if (key=="titulo") ti=val;
        else if (key=="agentes") ag=val; else if (key=="origem") og=val; else if (key=="instancia") inst=val
      }
      function nz(v) { return (v=="" ? "-" : v) }
      END { printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", file, nz(id), nz(t), nz(e), nz(d), nz(o), nz(s), nz(sub_), nz(r), nz(ti), nz(ag), nz(og), nz(inst) }
    ' "$f"
  done
}

rows=$(extract | sort)

if [ "$check" -eq 1 ]; then
  err=0
  printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r file id t e d o s sub_ r ti ag og inst; do
    [ -n "$file" ] || continue
    [ "$id" = "$file" ] || { echo "ERRO $file: id '$id' difere do nome do arquivo"; err=1; }
    case "$t" in decisao|aceite|bloqueio|backlog|stack|contexto|reserva) ;; *) echo "ERRO $file: tipo invalido '$t'"; err=1 ;; esac
    case "$e" in pacote|projeto) ;; *) echo "ERRO $file: escopo invalido '$e'"; err=1 ;; esac
    case "$s" in ativa|substituida|encerrada) ;; *) echo "ERRO $file: status invalido '$s'"; err=1 ;; esac
    [ "$d" != "-" ] || { echo "ERRO $file: data ausente"; err=1; }
    [ "$o" != "-" ] || { echo "ERRO $file: dono ausente"; err=1; }
    [ "$ti" != "-" ] || { echo "ERRO $file: titulo ausente"; err=1; }
    [ "$ag" != "-" ] || { echo "ERRO $file: agentes ausente (lista de papeis ou 'todos')"; err=1; }
    case "$og" in -|delegacao|chamada-direta|intervencao-humana) ;; *) echo "ERRO $file: origem invalida '$og' (delegacao | chamada-direta | intervencao-humana)"; err=1 ;; esac
    for a in $(echo "$ag" | tr ',' ' '); do
      case " $AGENTES " in *" $a "*) ;; *) echo "ERRO $file: agente invalido '$a' em agentes"; err=1 ;; esac
    done
    echo "$file" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}-[a-z0-9-]+$' || { echo "ERRO $file: nome fora do padrao YYYY-MM-DD-HHMM-slug"; err=1; }
    [ "$err" -eq 0 ] || exit 1
  done || exit 1
  dups=$(printf '%s\n' "$rows" | cut -f2 | sort | uniq -d)
  [ -z "$dups" ] || { echo "ERRO ids duplicados: $dups"; exit 1; }
  echo "entradas validas: $(printf '%s\n' "$rows" | grep -c .)"
  exit 0
fi

render() {
  echo "# Indice de entradas de memoria (gerado por scripts/memoria-index.sh; nao editar, nao versionar)"
  echo
  echo "Filtros: escopo=${escopo:-todos} tipo=${tipo:-todos} status=${status} agente=${agente:-tech-lead (tudo)}"
  echo
  [ "$corpo" -eq 1 ] || { echo "| Id | Tipo | Escopo | Agentes | Dono | Status | Substitui | Regra | Titulo |"; echo "|---|---|---|---|---|---|---|---|---|"; }
  printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r file id t e d o s sub_ r ti ag og inst; do
    [ -n "$file" ] || continue
    [ -z "$escopo" ] || [ "$e" = "$escopo" ] || continue
    [ -z "$tipo" ] || [ "$t" = "$tipo" ] || continue
    [ "$status" = "todas" ] || [ "$s" = "$status" ] || continue
    if [ -n "$agente" ]; then
      case ",$(echo "$ag" | tr -d ' ')," in *",todos,"*|*",$agente,"*) ;; *) continue ;; esac
    fi
    [ "$sub_" != "-" ] || sub_=""; [ "$r" != "-" ] || r=""
    if [ "$corpo" -eq 1 ]; then
      [ "$og" != "-" ] || og=""; [ "$inst" != "-" ] || inst=""
      printf '## %s\n\n- tipo: %s | escopo: %s | agentes: %s | dono: %s | status: %s%s%s%s%s\n- titulo: %s\n\n' "$id" "$t" "$e" "$ag" "$o" "$s" "${sub_:+ | substitui: $sub_}" "${r:+ | regra: $r}" "${og:+ | origem: $og}" "${inst:+ | instancia: $inst}" "$ti"
      awk 'BEGIN{fm=0} NR==1 && $0=="---"{fm=1;next} fm==1 && $0=="---"{fm=2;next} fm==2{print}' "$dir/$file.md"
      echo
    else
      printf '| [%s](entradas/%s.md) | %s | %s | %s | %s | %s | %s | %s | %s |\n' "$id" "$file" "$t" "$e" "$ag" "$o" "$s" "$sub_" "$r" "$ti"
    fi
  done
}

if [ "$write" -eq 1 ]; then
  render > "$out"; echo "indice gravado em $out"
else
  render
fi
