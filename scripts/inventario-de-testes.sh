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
# `<glob><TAB><ERE da linha que declara o teste>`; `#` abre comentario; `!<glob>` (sem TAB, em qualquer posicao)
# exclui da descoberta, para todos os padroes, os caminhos que casam o glob. Adaptacao do projeto: linha que
# comeca por declaracao de funcao shell (`nome() {`, harness proprio) vale o nome da funcao, antes das strings
# (o modelo so a usa por ultimo). Fora esse caso, o nome do caso e a string cujo
# delimitador (aspas duplas, aspas simples ou crase) abre primeiro na linha; dentro dela `\\` vira barra
# literal e `\<delimitador>` vira o delimitador. Sem string, o identificador apos `def ` ou `func `; sem
# nenhum, o nome da funcao shell declarada no inicio da linha (`nome() {` ou `nome () {`).
# Limite: aspas de outro tipo dentro da string ficam no nome (`@test 'a "b" c'` da `a "b" c`), mas o Bats as
# remove ao imprimir (`a b c`); nao ha `@test` com aspas simples no repositorio.
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
#   CONDICAO <arquivo> :: <caso>   coluna "Condicao de execucao" (quando o cabecalho da tabela a traz) preenchida
#                                  sem ` -> ` ou com o lado direito vazio; tabela sem ela e incondicional
#   NAO-DESCOBERTO <arquivo> :: linha <n>   AVISO, nao e divergencia: linha que casa a ERE sem produzir nome,
#                                  ou declaracao `it.each(`, `test.each(` ou `describe.each(` no inicio da linha
#   arquivos: <n> | casos: <n> | divergencias: <n>[ | nao descobertos: <n>]   (o sufixo so quando n > 0)
# Exit: 0 sem divergencia (e --listar/--faltantes; o aviso NAO-DESCOBERTO nao o altera), 1 com divergencia,
# 2 uso invalido ou inventario ausente.
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

# Padroes: <glob>TAB<ERE>, sem comentarios nem linhas vazias. Exclusoes: `!<glob>`, uma por linha.
: > "$tmp/exclusoes"
if [ -n "$padroes" ]; then
  grep -v '^[[:space:]]*#' "$padroes" | grep -v '^!' | grep "$tab" > "$tmp/padroes"
  grep '^!' "$padroes" | sed 's/^!//; s/[[:space:]]*$//' > "$tmp/exclusoes"
else
  printf '*.bats\t^@test \n' > "$tmp/padroes"
fi

# Pares <ERE>TAB<arquivo>: arquivo versionado, fora das exclusoes, cujo caminho casa com o glob do padrao.
git ls-files > "$tmp/todos" || { echo "git ls-files falhou" >&2; exit 2; }
: > "$tmp/versionados"
while IFS= read -r f; do
  excluido=0
  while IFS= read -r ex; do
    [ -n "$ex" ] || continue
    # shellcheck disable=SC2254
    case "$f" in $ex) excluido=1; break ;; esac
  done < "$tmp/exclusoes"
  if [ "$excluido" -eq 0 ]; then printf '%s\n' "$f" >> "$tmp/versionados"; fi
done < "$tmp/todos"
: > "$tmp/pares"
while IFS="$tab" read -r glob ere; do
  [ -n "$glob" ] || continue
  while IFS= read -r f; do
    # shellcheck disable=SC2254
    case "$f" in $glob) printf '%s\t%s\n' "$ere" "$f" >> "$tmp/pares" ;; esac
  done < "$tmp/versionados"
done < "$tmp/padroes"

# Testes descobertos: <arquivo>TAB<caso>. Avisos em $tmp/naodesc: <arquivo>TAB<linha> (linha que casa a ERE sem
# nome, ou declaracao `it.each(`/`test.each(`/`describe.each(` no inicio da linha, que a descoberta nao expande).
awk -F '\t' -v avisos="$tmp/naodesc" '
function nome(l,   q, p, i, c, out, s, pd, ps, pc) {
  # Adaptacao do projeto (harness proprio em shell): a funcao shell declarada no inicio da linha (`nome() {`)
  # vale ANTES das strings, porque o caso de uma linha so (`nome() { cmd "texto"; }`) traz string no corpo.
  if (match(l, /^[A-Za-z_][A-Za-z0-9_]*[ ]*\(\)/)) {
    s = substr(l, RSTART, RLENGTH)
    sub(/[ ]*\(\)$/, "", s)
    return s
  }
  pd = index(l, "\""); ps = index(l, "\047"); pc = index(l, "`")
  p = 0; q = ""
  if (pd > 0) { p = pd; q = "\"" }
  if (ps > 0 && (p == 0 || ps < p)) { p = ps; q = "\047" }
  if (pc > 0 && (p == 0 || pc < p)) { p = pc; q = "`" }
  if (p > 0) {
    out = ""
    for (i = p + 1; i <= length(l); i++) {
      c = substr(l, i, 1)
      if (c == "\\" && substr(l, i + 1, 1) == "\\") { out = out "\\"; i++ }
      else if (c == "\\" && substr(l, i + 1, 1) == q) { out = out q; i++ }
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
  if (match(l, /^[A-Za-z_][A-Za-z0-9_]*[ ]*\(\)/)) {
    s = substr(l, RSTART, RLENGTH)
    sub(/[ ]*\(\)$/, "", s)
    return s
  }
  return ""
}
{
  ere = $1; f = $2; n = 0
  while ((getline l < f) > 0) {
    n++; aviso = 0
    if (l ~ ere) { c = nome(l); if (c != "") print f "\t" c; else aviso = 1 }
    if (l ~ /^[ \t]*(it|test|describe)\.each[ \t]*\(/) aviso = 1
    if (aviso) print f "\t" n > avisos
  }
  close(f)
}' "$tmp/pares" | sort > "$tmp/testes"
[ -f "$tmp/naodesc" ] || : > "$tmp/naodesc"

if [ "$modo" = listar ]; then cat "$tmp/testes"; exit 0; fi

# Inventario: B<TAB>arq (bloco) | F<TAB>arq<TAB>campo<TAB>valor | R<TAB>arq<TAB>caso<TAB>verifica<TAB>condicao.
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
  cur = ""; ccol = 0
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
  if (cel[1] == "Caso") {
    # A coluna Condicao de execucao vale so quando o cabecalho a declara; tabela sem ela e incondicional.
    ccol = 0
    for (i = 2; i <= n; i++) if (cel[i] ~ /^Condi/) ccol = i
    next
  }
  if (cel[1] ~ /^:?-+:?$/) next
  print "R\t" cur "\t" cel[1] "\t" cel[2] "\t" (ccol ? cel[ccol] : "")
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
# Condicao de execucao: vazia (incondicional) ou `<condicao> -> <onde ela e satisfeita>`.
function cond_ruim(v,   p) {
  v = trim(v)
  if (v == "") return 0
  p = index(v, " -> ")
  if (p == 0) return 1
  return (trim(substr(v, p + 4)) == "")
}
FILENAME == ARGV[1] {
  k = $1 SUBSEP $2
  t[k]++
  if (!($1 in tf)) { tf[$1] = 1; ord[++nf] = $1 }
  if (t[k] == 1) { nc[$1]++; cas[$1, nc[$1]] = $2 }
  next
}
$1 == "B" { blk[$2] = 1; next }
$1 == "F" { fld[$2, $3] = $4; next }
$1 == "R" { k = $2 SUBSEP $3; r[k]++; ver[k] = $4; cnd[k] = $5; if (r[k] == 1) { ro[++nr] = k } ; next }
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
        print "| Caso | O que verifica | Regra especifica | Condicao de execucao |"
        print "|---|---|---|---|"
      } else {
        print "<!-- linhas a acrescentar na tabela do bloco existente `" f "` -->\n"
      }
      for (j = 1; j <= nc[f]; j++)
        if (!((f SUBSEP cas[f, j]) in r)) print "| " esc(cas[f, j]) " | <condicao, acao e resultado esperado> | | |"
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
    if (p[1] in tf && cond_ruim(cnd[k])) div("CONDICAO " p[1] " :: " p[2])
  }
  split("Alvo|Modulo|Camada|Autoria|Regras de origem|Comando", obr, "|")
  for (f in blk) {
    if (!(f in tf)) { div("ARQUIVO " f); continue }
    for (i = 1; i <= 6; i++) if (ruim(fld[f, obr[i]])) div("CAMPO " f " :: " obr[i])
    if (fld[f, "Autoria"] ~ /QA/ && ruim(fld[f, "Aceite do solicitante"])) div("CAMPO " f " :: Aceite do solicitante")
  }
  print "arquivos: " (nf + 0) " | casos: " (ncasos + 0) " | divergencias: " nd + 0
  exit (nd > 0) ? 1 : 0
}' "$tmp/testes" "$tmp/inv" > "$tmp/saida"
rc=$?

if [ "$modo" = faltantes ]; then cat "$tmp/saida"; exit 0; fi
# Avisos: um por <arquivo, linha>, ainda que o arquivo case mais de um padrao.
sort -u "$tmp/naodesc" | awk -F '\t' '{ print "NAO-DESCOBERTO " $1 " :: linha " $2 }' > "$tmp/avisos"
nnd="$(awk 'END { print NR }' "$tmp/avisos")"
{ grep -v '^arquivos: ' "$tmp/saida"; cat "$tmp/avisos"; } | sort
if [ "$nnd" -gt 0 ]; then
  sed "s/\$/ | nao descobertos: $nnd/" "$tmp/saida" | grep '^arquivos: '
else
  grep '^arquivos: ' "$tmp/saida"
fi
exit "$rc"
