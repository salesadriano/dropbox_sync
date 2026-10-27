#!/usr/bin/env sh
# Confere se o inventario de testes do projeto (regra 51 do AGENTS.md; mantido pelo QA) esta completo e
# coerente com os testes versionados. O formato do inventario e o de
# `.github/agents/templates/inventario-de-testes-template.md`. O script so le; nunca altera a arvore.
#
# Uso (a partir de qualquer diretorio do repositorio; roda sempre da raiz):
#   sh scripts/inventario-de-testes.sh [--check]     # padrao: confere e lista as divergencias
#   sh scripts/inventario-de-testes.sh --listar      # testes descobertos: <arquivo><TAB><caso>, ordenados
#   sh scripts/inventario-de-testes.sh --faltantes   # esqueleto Markdown so do que falta, para o QA completar
#   opcoes: --inventario <arq>   inventario (padrao docs/testes/inventario-de-testes.md)
#           --padroes <arq>      padroes de descoberta (padrao scripts/inventario-de-testes.txt, se existir;
#                                sem ele, o embutido: `*.bats` com `^@test `)
#
# Descoberta: so arquivos versionados (`git ls-files`). O arquivo de padroes tem linhas
# `<glob><TAB><ERE da linha que declara o teste>`; `#` abre comentario. O nome do caso e a primeira string entre
# aspas duplas da linha (com `\"` tratado); sem ela, a primeira entre aspas simples; sem nenhuma, o
# identificador apos `def ` ou `func `. Linha que comeca por declaracao de funcao shell (`nome() {`, harness
# proprio em shell) vale o nome da funcao, antes das aspas.
#
# Campos obrigatorios do bloco: Alvo, Modulo, Camada, Autoria, Regras de origem, Comando; "Aceite do
# solicitante" quando a Autoria contem "QA". `Nao aplicavel: <motivo>` conta como preenchido se o motivo nao
# for placeholder. Placeholder e qualquer `<...>` fora de trecho entre crases.
#
# Saida do --check, uma linha por divergencia (prefixo estavel), ordenadas, e o resumo final:
#   FALTA <arquivo> :: <caso>      teste sem linha no inventario
#   SOBRA <arquivo> :: <caso>      linha sem teste correspondente
#   ARQUIVO <arquivo>              bloco de arquivo que nao e teste descoberto
#   CAMPO <arquivo> :: <campo>     campo obrigatorio ausente, vazio ou com placeholder
#   VAZIO <arquivo> :: <caso>      coluna "O que verifica" vazia ou com placeholder
#   DUPLICADO <arquivo> :: <caso>  caso com mais de uma linha
#   arquivos: <n> | casos: <n> | divergencias: <n>     (arquivos e casos descobertos)
# Exit: 0 sem divergencia (e --listar/--faltantes), 1 com divergencia, 2 uso invalido ou inventario ausente.
# Nao usa `set -e`: cada fonte que falha vira mensagem e codigo de saida.

modo=check; inventario=""; padroes=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) modo=check; shift ;;
    --listar) modo=listar; shift ;;
    --faltantes) modo=faltantes; shift ;;
    --inventario) [ $# -ge 2 ] || { echo "--inventario exige um valor" >&2; exit 2; }; inventario="$2"; shift 2 ;;
    --padroes) [ $# -ge 2 ] || { echo "--padroes exige um valor" >&2; exit 2; }; padroes="$2"; shift 2 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

raiz="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "fora de um repositorio git" >&2; exit 2; }
cd "$raiz" || exit 2
[ -n "$inventario" ] || inventario="docs/testes/inventario-de-testes.md"
if [ -z "$padroes" ] && [ -f scripts/inventario-de-testes.txt ]; then padroes="scripts/inventario-de-testes.txt"; fi
if [ -n "$padroes" ] && [ ! -f "$padroes" ]; then echo "arquivo de padroes inexistente: $padroes" >&2; exit 2; fi
if [ "$modo" = check ] && [ ! -f "$inventario" ]; then echo "inventario inexistente: $inventario" >&2; exit 2; fi

tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
tab="$(printf '\t')"
[ -f "$inventario" ] || inventario_lido=/dev/null

# Padroes: <glob>TAB<ERE>, sem comentarios nem linhas vazias.
if [ -n "$padroes" ]; then
  grep -v '^[[:space:]]*#' "$padroes" | grep "$tab" > "$tmp/padroes"
else
  printf '*.bats\t^@test \n' > "$tmp/padroes"
fi

# Pares <ERE>TAB<arquivo>: arquivo versionado cujo caminho casa com o glob do padrao.
git ls-files > "$tmp/versionados" || { echo "git ls-files falhou" >&2; exit 2; }
: > "$tmp/pares"
while IFS="$tab" read -r glob ere; do
  [ -n "$glob" ] || continue
  while IFS= read -r f; do
    # shellcheck disable=SC2254
    case "$f" in $glob) printf '%s\t%s\n' "$ere" "$f" >> "$tmp/pares" ;; esac
  done < "$tmp/versionados"
done < "$tmp/padroes"

# Testes descobertos: <arquivo>TAB<caso>.
awk -F '\t' '
function nome(l,   q, p, i, c, out, n, s) {
  # Funcao shell declarada no inicio da linha (`nome() {`, harness proprio): o nome da funcao vale antes das
  # aspas, porque um caso de uma linha so (`nome() { cmd "texto"; }`) traz string no corpo.
  if (match(l, /^[A-Za-z_][A-Za-z0-9_]*[ ]*\(\)/)) {
    s = substr(l, RSTART, RLENGTH)
    sub(/[ ]*\(\)$/, "", s)
    return s
  }
  for (n = 1; n <= 2; n++) {
    q = (n == 1) ? "\"" : "\047"
    p = index(l, q)
    if (p == 0) continue
    out = ""
    for (i = p + 1; i <= length(l); i++) {
      c = substr(l, i, 1)
      if (c == "\\" && substr(l, i + 1, 1) == q) { out = out q; i++ }
      else if (c == q) return out
      else out = out c
    }
    return out
  }
  if (match(l, /(^|[^A-Za-z0-9_])(def|func) +[A-Za-z0-9_]+/)) {
    s = substr(l, RSTART, RLENGTH)
    sub(/^.*(def|func) +/, "", s)
    return s
  }
  return ""
}
{
  ere = $1; f = $2
  while ((getline l < f) > 0) {
    if (l ~ ere) { c = nome(l); if (c != "") print f "\t" c }
  }
  close(f)
}' "$tmp/pares" | sort > "$tmp/testes"

if [ "$modo" = listar ]; then cat "$tmp/testes"; exit 0; fi

# Inventario: B<TAB>arq (bloco) | F<TAB>arq<TAB>campo<TAB>valor | R<TAB>arq<TAB>caso<TAB>verifica.
awk '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
{ sub(/\r$/, "") }
function celulas(l, cel,   i, c, n, cur) {
  n = 0; cur = ""
  l = trim(l)
  if (substr(l, 1, 1) == "|") l = substr(l, 2)
  for (i = 1; i <= length(l); i++) {
    c = substr(l, i, 1)
    if (c == "\\" && substr(l, i + 1, 1) == "|") { cur = cur "|"; i++ }
    else if (c == "|") { cel[++n] = trim(cur); cur = "" }
    else cur = cur c
  }
  if (trim(cur) != "") cel[++n] = trim(cur)
  return n
}
/^## / {
  cur = ""
  if (match($0, /^## `[^`]+`[ \t]*$/)) {
    cur = $0; sub(/^## `/, "", cur); sub(/`[ \t]*$/, "", cur)
    print "B\t" cur
  }
  next
}
cur == "" { next }
/^- \*\*[^*]+:\*\*/ {
  match($0, /^- \*\*[^*]+:\*\*/)
  k = substr($0, 5, RLENGTH - 7)
  v = trim(substr($0, RLENGTH + 1))
  print "F\t" cur "\t" k "\t" v
  next
}
/^[ \t]*\|/ {
  delete cel
  n = celulas($0, cel)
  if (n == 0) next
  if (cel[1] == "Caso" || cel[1] ~ /^:?-+:?$/) next
  print "R\t" cur "\t" cel[1] "\t" cel[2]
}' "${inventario_lido:-$inventario}" > "$tmp/inv"

# Comparacao. Em --faltantes imprime o esqueleto; em --check, as divergencias.
awk -F '\t' -v modo="$modo" '
function ph(v,   s) {
  if (v ~ /^`<[A-Za-z][^<>`]*>`$/) return 1
  s = v; gsub(/`[^`]*`/, "", s)
  return (s ~ /<[A-Za-z][^<>]*>/)
}
function ruim(v,   m) {
  if (trim(v) == "") return 1
  if (v ~ /^N[^ ]*o aplic[^ ]*:/) {
    m = v; sub(/^[^:]*:/, "", m)
    return (trim(m) == "" || ph(m))
  }
  return ph(v)
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function esc(s) { gsub(/\|/, "\\|", s); return s }
function div(msg) { print msg; nd++ }
FILENAME == ARGV[1] {
  k = $1 SUBSEP $2
  t[k]++
  if (!($1 in tf)) { tf[$1] = 1; ord[++nf] = $1 }
  if (t[k] == 1) { nc[$1]++; cas[$1, nc[$1]] = $2 }
  next
}
$1 == "B" { blk[$2] = 1; next }
$1 == "F" { fld[$2, $3] = $4; next }
$1 == "R" { k = $2 SUBSEP $3; r[k]++; ver[k] = $4; if (r[k] == 1) { ro[++nr] = k } ; next }
END {
  ncasos = 0
  for (i = 1; i <= nf; i++) ncasos += nc[ord[i]]
  if (modo == "faltantes") {
    for (i = 1; i <= nf; i++) {
      f = ord[i]
      falta = 0
      for (j = 1; j <= nc[f]; j++) if (!((f SUBSEP cas[f, j]) in r)) falta = 1
      if (!falta) continue
      if (!(f in blk)) {
        print "## `" f "`\n"
        print "- **Alvo:** <arquivo, funcao, rota ou fluxo exercitado>"
        print "- **Modulo:** <identificador do mapa de modulos>"
        print "- **Camada:** <unitario | integracao | E2E | contrato | fumaca>"
        print "- **Autoria:** <Senior Developer (TDD da demanda `<slug>`) | QA Expert (suite independente da demanda `<slug>`)>"
        print "- **Regras de origem:** <AGENTS.md n; protocolo-tdd Regra n; entrada; requisito; #n; log>"
        print "- **Aceite do solicitante:** <entrada de aceite com sha256 | Nao aplicavel: teste do Senior Developer>"
        print "- **Comando:** `<comando que roda so este arquivo, com parada no primeiro erro>`\n"
        print "| Caso | O que verifica | Regra especifica |"
        print "|---|---|---|"
      } else {
        print "<!-- linhas a acrescentar na tabela do bloco existente `" f "` -->\n"
      }
      for (j = 1; j <= nc[f]; j++)
        if (!((f SUBSEP cas[f, j]) in r)) print "| " esc(cas[f, j]) " | <condicao, acao e resultado esperado> | |"
      print ""
    }
    exit 0
  }
  for (k in t) if (!(k in r)) { split(k, p, SUBSEP); div("FALTA " p[1] " :: " p[2]) }
  for (k in r) {
    split(k, p, SUBSEP)
    if (!(k in t)) div("SOBRA " p[1] " :: " p[2])
    if (r[k] > 1) div("DUPLICADO " p[1] " :: " p[2])
    if (p[1] in tf && ruim(ver[k])) div("VAZIO " p[1] " :: " p[2])
  }
  split("Alvo|Modulo|Camada|Autoria|Regras de origem|Comando", obr, "|")
  for (f in blk) {
    if (!(f in tf)) { div("ARQUIVO " f); continue }
    for (i = 1; i <= 6; i++) if (ruim(fld[f, obr[i]])) div("CAMPO " f " :: " obr[i])
    if (fld[f, "Autoria"] ~ /QA/ && ruim(fld[f, "Aceite do solicitante"])) div("CAMPO " f " :: Aceite do solicitante")
  }
  print "arquivos: " nf " | casos: " ncasos " | divergencias: " nd + 0
  exit (nd > 0) ? 1 : 0
}' "$tmp/testes" "$tmp/inv" > "$tmp/saida"
rc=$?

if [ "$modo" = faltantes ]; then cat "$tmp/saida"; exit 0; fi
grep -v '^arquivos: ' "$tmp/saida" | sort
grep '^arquivos: ' "$tmp/saida"
exit "$rc"
