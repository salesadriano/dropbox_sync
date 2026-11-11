#!/usr/bin/env sh
# Audita os casos de teste versionados e acusa os casos inertes: os que passam sem provar nada (issue #67, item 2;
# referencia `.github/skills/protocolo-tdd/references/auditoria-de-casos-inertes.md`). Analise estatica, por
# adaptador de stack; o script so le e nunca altera a arvore.
#
# Uso (a partir de qualquer diretorio do repositorio; roda sempre da raiz):
#   sh scripts/auditar-casos.sh              # audita e lista os achados
#   sh scripts/auditar-casos.sh --listar     # casos descobertos: <arquivo><TAB><caso>, ordenados
#   opcoes: --padroes <arq>   padroes (padrao scripts/auditar-casos.txt, se existir; sem ele, o embutido
#                             `*.bats<TAB>bats`)
#           --so <arquivo>    audita so este arquivo (caminho a partir da raiz; repetivel); precisa casar com um
#                             padrao, e vale mesmo fora do indice (teste novo ainda nao versionado)
#
# Descoberta: arquivos versionados (`git ls-files`). O arquivo de padroes tem linhas `<glob><TAB><adaptador>`,
# adaptador em {bats, shell, jest}; `!<glob>` exclui caminhos; `#` abre comentario. O glob casa o caminho inteiro
# (o `*` cobre `/`); vale o primeiro padrao que casa. Casos por adaptador:
#   bats   `@test "<caso>" {` ate o `}` na indentacao da declaracao
#   shell  `teste_<nome>() {` (harness TAP proprio) ate o `}` na indentacao da declaracao
#   jest   `it(`, `test(` (Jest/Vitest), com modificadores (`.skip`, `.only`, `.each(...)`); `describe(` so conta
#          para o skip do grupo
#
# Saida, uma linha por achado, ordenadas, e o resumo final:
#   BLOQUEANTE SKIP <arquivo> :: <caso> :: linha <n>          skip/pular/return incondicional como 1a instrucao,
#                                                              ou it.skip/xit/describe.skip/...
#   BLOQUEANTE SEM-ASSERCAO <arquivo> :: <caso> :: linha <n>  corpo sem assercao direta nem transitiva (um nivel;
#                                                              dois no jest)
#   AVISO PENDENTE <arquivo> :: <caso> :: linha <n>           so Bats: esqueleto cuja unica instrucao e
#                                                              `skip "pendente: <motivo>"` (motivo nao vazio, sem
#                                                              codigo depois, so comentarios); contado em avisos
#   MAIOR LITERAL <arquivo> :: <caso> :: linha <n>            assercao literal contra literal
#   AVISO AUSENCIA <arquivo> :: <caso> :: linha <n>           ausencia de caminho que nem o teste nem arquivo
#                                                              versionado fora dos testes cita
#   arquivos: <n> | casos: <n> | bloqueantes: <n> | maiores: <n> | avisos: <n>
# Exit: 0 sem bloqueante nem maior (e --listar), 1 com algum, 2 uso invalido. Aviso nao muda o exit.
# Adaptacoes do projeto (adaptador shell, harness proprio em tests/support/harness.sh): `_harness_falhar` conta como
# assercao direta, e o braco de `case` e as atribuicoes `VAR=valor` no inicio do segmento sao ignorados antes de
# reconhecer a assercao. Propostas ao pacote ai_team.
# Nao usa `set -e`: cada fonte que falha vira mensagem e codigo de saida.

modo=auditar; padroes=""; so=""
nl='
'
while [ $# -gt 0 ]; do
  case "$1" in
    --listar) modo=listar; shift ;;
    --padroes) [ $# -ge 2 ] || { echo "--padroes exige um valor" >&2; exit 2; }; padroes="$2"; shift 2 ;;
    --so) [ $# -ge 2 ] || { echo "--so exige um valor" >&2; exit 2; }; so="$so$2$nl"; shift 2 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

raiz="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "fora de um repositorio git" >&2; exit 2; }
cd "$raiz" || exit 2
if [ -z "$padroes" ] && [ -f scripts/auditar-casos.txt ]; then padroes="scripts/auditar-casos.txt"; fi
if [ -n "$padroes" ] && [ ! -f "$padroes" ]; then echo "arquivo de padroes inexistente: $padroes" >&2; exit 2; fi

tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
tab="$(printf '\t')"

# Padroes: inclusoes (<glob>TAB<adaptador>) e exclusoes (!<glob>), sem comentarios nem linhas vazias.
if [ -n "$padroes" ]; then
  grep -v '^[[:space:]]*#' "$padroes" | grep -v '^[[:space:]]*$' > "$tmp/linhas"
else
  printf '*.bats\tbats\n' > "$tmp/linhas"
fi
: > "$tmp/inclui"; : > "$tmp/exclui"
while IFS= read -r l; do
  case "$l" in
    !*) printf '%s\n' "${l#!}" >> "$tmp/exclui" ;;
    *"$tab"*)
      ad="${l#*"$tab"}"
      case "$ad" in
        bats|shell|jest) printf '%s\n' "$l" >> "$tmp/inclui" ;;
        *) echo "adaptador desconhecido em $padroes: $ad (use bats, shell ou jest)" >&2; exit 2 ;;
      esac ;;
    *) echo "linha de padrao invalida em $padroes: $l" >&2; exit 2 ;;
  esac
done < "$tmp/linhas"

# Adaptador do arquivo $1 (vazio quando excluido ou sem padrao).
adaptador() {
  while IFS= read -r g; do
    # shellcheck disable=SC2254
    case "$1" in $g) return 0 ;; esac
  done < "$tmp/exclui"
  while IFS="$tab" read -r g a; do
    # shellcheck disable=SC2254
    case "$1" in $g) printf '%s' "$a"; return 0 ;; esac
  done < "$tmp/inclui"
}

: > "$tmp/alvos"
if [ -n "$so" ]; then
  printf '%s' "$so" > "$tmp/candidatos"
  while IFS= read -r f; do
    f="${f#./}"
    a="$(adaptador "$f")"
    if [ ! -f "$f" ] || [ -z "$a" ]; then echo "--so: arquivo inexistente ou fora dos padroes: $f" >&2; exit 2; fi
    printf '%s\t%s\n' "$a" "$f" >> "$tmp/alvos"
  done < "$tmp/candidatos"
else
  git ls-files > "$tmp/candidatos" || { echo "git ls-files falhou" >&2; exit 2; }
  while IFS= read -r f; do
    a="$(adaptador "$f")"
    [ -n "$a" ] && [ -f "$f" ] && printf '%s\t%s\n' "$a" "$f" >> "$tmp/alvos"
  done < "$tmp/candidatos"
fi
sort -u "$tmp/alvos" -o "$tmp/alvos"

# Analise: um awk portavel (sem gensub, sem length(array)) sobre os pares <adaptador>TAB<arquivo>.
cat > "$tmp/auditar.awk" <<'AWK'
# ---------- utilitarios ----------
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function achado(sev, tipo, f, c, n) {
  print sev " " tipo " " f " :: " c " :: linha " n
  if (sev == "BLOQUEANTE") nb++; else if (sev == "MAIOR") nm++; else na++
}
# Nome do caso, pela mesma regra do inventario-de-testes.sh: a string do delimitador (aspas duplas, simples ou
# crase) que abre primeiro na linha, com `\\` e `\<delimitador>` desfeitos.
function nome_aspas(l,   p, pd, ps, pc) {
  pd = index(l, "\""); ps = index(l, "\047"); pc = index(l, "`")
  p = pd
  if (ps > 0 && (p == 0 || ps < p)) p = ps
  if (pc > 0 && (p == 0 || pc < p)) p = pc
  return (p > 0) ? string_em(l, p) : ""
}
# String que comeca na posicao p de l (p aponta para o delimitador), sem os delimitadores.
function string_em(l, p,   q, i, c, out) {
  q = substr(l, p, 1); out = ""
  for (i = p + 1; i <= length(l); i++) {
    c = substr(l, i, 1)
    if (c == "\\" && (substr(l, i + 1, 1) == "\\" || substr(l, i + 1, 1) == q)) { out = out substr(l, i + 1, 1); i++ }
    else if (c == q) return out
    else out = out c
  }
  return out
}
# Palavras shell de s, respeitando aspas; as aspas ficam no token. Devolve a quantidade.
function palavras(s, w,   n, i, c, st, cur) {
  split("", w); n = 0; st = 0; cur = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (st == 0 && (c == " " || c == "\t")) { if (cur != "") { w[++n] = cur; cur = "" }; continue }
    cur = cur c
    if (st == 0 && c == "\\") { cur = cur substr(s, i + 1, 1); i++ }
    else if (st == 0 && c == "\047") st = 1
    else if (st == 0 && c == "\"") st = 2
    else if (st == 1 && c == "\047") st = 0
    else if (st == 2 && c == "\\") { cur = cur substr(s, i + 1, 1); i++ }
    else if (st == 2 && c == "\"") st = 0
  }
  if (cur != "") w[++n] = cur
  return n
}
# Literal: numero, string sem expansao ou booleano.
function literal(t) {
  return (t ~ /^-?[0-9]+(\.[0-9]+)?$/ || t ~ /^\047[^\047]*\047$/ || t ~ /^"[^"$`\\]*"$/ || t == "true" || t == "false")
}
# Ultimo componente literal de um caminho (sem aspas); vazio quando nao e literal.
function base_literal(t,   b) {
  gsub(/["\047]/, "", t)
  b = t; sub(/^.*\//, "", b)
  if (b == "" || b ~ /[$*?`(){}]/) return ""
  return b
}

# ---------- shell (bats e harness proprio) ----------
# Branqueia o conteudo entre aspas e os comentarios (mesmo comprimento) e marca linhas de heredoc em H.
# `$(` dentro de aspas duplas abre um contexto novo de aspas (pilha em dp/PC, com a contagem de parenteses de
# cada nivel), que volta as aspas duplas no `)` que o fecha; o conteudo do contexto aninhado sai branqueado.
function prep_sh(A, n, B, H,   i, j, c, st, out, l, p, w, fim, tira, k, dp, PC) {
  st = 0; fim = ""; dp = 0; split("", PC)
  for (i = 1; i <= n; i++) {
    l = A[i]
    if (fim != "") {
      H[i] = 1; B[i] = ""
      k = l; if (tira) sub(/^\t+/, "", k)
      if (k == fim) fim = ""
      continue
    }
    H[i] = 0; out = ""
    for (j = 1; j <= length(l); j++) {
      c = substr(l, j, 1)
      if (st == 0 && dp > 0) {
        if (c == "\\") { out = out "  "; j++; continue }
        if (c == "(") PC[dp]++
        else if (c == ")" && --PC[dp] == 0) { dp--; st = 2 }
        else if (c == "\047") st = (j > 1 && substr(l, j - 1, 1) == "$") ? 3 : 1
        else if (c == "\"") st = 2
        out = out " "
      } else if (st == 0) {
        if (c == "\\") { out = out c substr(l, j + 1, 1); j++; continue }
        if (c == "#" && (j == 1 || substr(l, j - 1, 1) ~ /[ \t;]/)) { while (j <= length(l)) { out = out " "; j++ }; break }
        if (c == "\047") st = (j > 1 && substr(l, j - 1, 1) == "$") ? 3 : 1; else if (c == "\"") st = 2
        out = out c
      } else if (st == 2 && c == "$" && substr(l, j + 1, 1) == "(") {
        dp++; PC[dp] = 1; st = 0; out = out "  "; j++
      } else if (st == 3) {
        if (c == "\\") { out = out "  "; j++; continue }
        if (c == "\047") { st = 0; out = out (dp > 0 ? " " : c) } else out = out " "
      } else if (st == 1) {
        if (c == "\047") { st = 0; out = out (dp > 0 ? " " : c) } else out = out " "
      } else {
        if (c == "\\") { out = out "  "; j++; continue }
        if (c == "\"") { st = 0; out = out (dp > 0 ? " " : c) } else out = out " "
      }
    }
    B[i] = out
    p = index(out, "<<")
    if (p > 0 && substr(out, p + 2, 1) != "<") {
      w = substr(l, p + 2); tira = (substr(w, 1, 1) == "-")
      sub(/^-?[ \t]*["\047]?/, "", w)
      if (match(w, /^[A-Za-z_][A-Za-z0-9_]*/)) fim = substr(w, 1, RLENGTH)
    }
  }
}
# Fim do bloco aberto na linha i (o `}` na indentacao da declaracao, ou menor); n se nao houver.
function fim_bloco(A, B, H, n, i,   ind, j, lw) {
  match(A[i], /^[ \t]*/); ind = RLENGTH
  for (j = i + 1; j <= n; j++) {
    if (H[j]) continue
    if (B[j] ~ /^[ \t]*}/) { match(B[j], /^[ \t]*/); if (RLENGTH <= ind) return j }
  }
  return n
}
# Segmentos de uma linha: corta em &&, ||, ;, | fora de aspas (posicoes de bl) e devolve pares em SL/SB.
function segmentos(ll, bl, SL, SB,   n, i, c, ini, d) {
  split("", SL); split("", SB); n = 0; ini = 1
  for (i = 1; i <= length(bl); i++) {
    c = substr(bl, i, 1); d = substr(bl, i, 2)
    if (d == "&&" || d == "||") { n++; SL[n] = substr(ll, ini, i - ini); SB[n] = substr(bl, ini, i - ini); i++; ini = i + 1 }
    else if (c == ";" || c == "|") { n++; SL[n] = substr(ll, ini, i - ini); SB[n] = substr(bl, ini, i - ini); ini = i + 1 }
  }
  n++; SL[n] = substr(ll, ini); SB[n] = substr(bl, ini)
  for (i = 1; i <= n; i++) {
    SL[i] = trim(SL[i]); SB[i] = trim(SB[i])
    while (SB[i] ~ /^(then|do|else|time|\{|\()([ \t]|$)/) {
      match(SB[i], /^(then|do|else|time|\{|\()[ \t]*/)
      SL[i] = substr(SL[i], RLENGTH + 1); SB[i] = substr(SB[i], RLENGTH + 1)
    }
  }
  return n
}
# Adaptacao do projeto (harness proprio, adaptador shell): tira do inicio do segmento o braco de `case` (`*) cmd`) e
# as atribuicoes de ambiente que prefixam o comando (`VAR=valor cmd`), para que a assercao que vem depois conte.
function sem_prefixo(sb, ad) {
  if (ad != "shell") return sb
  sub(/^[^ \t()]+\)[ \t]*/, "", sb)
  while (match(sb, /^[A-Za-z_][A-Za-z0-9_]*=(\047[^\047]*\047|"[^"]*"|[^ \t]*)[ \t]+/)) sb = substr(sb, RLENGTH + 1)
  return sb
}
function assercao_sh(sb, ad, sl,   w) {
  sb = sem_prefixo(sb, ad)
  if (direta(sb, ad, sl)) return 1
  w = sb; sub(/[ \t].*$/, "", w)
  return (w in HA)
}
# Programa awk com `exit` de valor diferente de 0, na linha j (texto original A, branqueado B), limitado ao bloco
# que termina na linha e. O programa e o texto das strings entre aspas que seguem a palavra `awk` ate o fim do
# comando (`;`, `|`, `&` ou fim de linha fora de aspas); pode continuar nas linhas seguintes ate a aspa que fecha.
function awk_exit(A, B, j, e,   pos, i, c, q, lin, prog, ini, parte, nl) {
  if (!match(B[j], /(^|[^A-Za-z0-9_.\/-])awk[ \t]/)) return 0
  lin = j; i = RSTART + RLENGTH - 1; q = ""; prog = ""
  while (lin < e) {
    nl = length(B[lin])
    for (; i <= nl; i++) {
      c = substr(B[lin], i, 1)
      if (q == "") {
        if (c == "\\") { i++; continue }
        if (c == "\047" || c == "\"") { q = c; prog = prog " " }
        else if (c == ";" || c == "|" || c == "&") return awk_exit_valor(prog)
      } else if (c == q) { q = ""; prog = prog " " }
      else prog = prog substr(A[lin], i, 1)
    }
    if (q == "" && B[lin] !~ /\\[ \t]*$/) break
    prog = prog "\n"; lin++; i = 1
  }
  return awk_exit_valor(prog)
}
# Programa awk sem comentario (`#` ate o fim da linha) e sem string entre aspas duplas (substituida por um espaco),
# fora de uma da outra: `exit` dentro de comentario ou string nao e `exit` do programa.
function awk_sem_texto(prog,   i, c, out, q, n) {
  out = ""; q = 0; n = length(prog)
  for (i = 1; i <= n; i++) {
    c = substr(prog, i, 1)
    if (q) { if (c == "\\") i++; else if (c == "\"") { q = 0; out = out " " } }
    else if (c == "\"") q = 1
    else if (c == "#") { while (i < n && substr(prog, i + 1, 1) != "\n") i++ }
    else out = out c
  }
  return out
}
# `exit` como palavra inteira seguido de valor diferente de 0 (`exit;` e `exit 0` nao contam).
function awk_exit_valor(prog,   r, p, d, a, c) {
  r = awk_sem_texto(prog)
  while ((p = index(r, "exit")) > 0) {
    a = (p > 1) ? substr(r, p - 1, 1) : " "
    d = substr(r, p + 4); r = d
    if (a ~ /[A-Za-z0-9_]/ || d ~ /^[A-Za-z0-9_]/) continue
    sub(/^[ \t]*\(?[ \t]*/, "", d); c = substr(d, 1, 1)
    if (c == "" || c == ";" || c == "}" || c == ")" || c == "\n") continue
    if (c == "0" && substr(d, 2, 1) !~ /[0-9.A-Za-z_]/) continue
    return 1
  }
  return 0
}
# Funcoes do arquivo cujo corpo tem assercao direta (assercao transitiva de um nivel) entram em HA.
function helpers(A, B, H, n, ad,   i, j, e, nomef, s, k, ok, SL, SB, m) {
  for (i = 1; i <= n; i++) {
    if (H[i]) continue
    if (!match(B[i], /^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_:.-]*[ \t]*\(\)/) && !match(B[i], /^[ \t]*function[ \t]+[A-Za-z_][A-Za-z0-9_:.-]*/)) continue
    nomef = substr(B[i], 1, RLENGTH); sub(/^[ \t]*(function[ \t]+)?/, "", nomef); sub(/[ \t]*(\(\))?$/, "", nomef)
    ok = 0
    if (B[i] ~ /\{.*}[ \t;]*$/) {
      s = B[i]; k = index(s, "{")
      m = segmentos(substr(A[i], k + 1), substr(s, k + 1), SL, SB)
      for (j = 1; j <= m; j++) if (direta(SB[j], ad, SL[j])) ok = 1
      if (ok) HA[nomef] = 1
      continue
    }
    e = fim_bloco(A, B, H, n, i)
    for (j = i + 1; j < e; j++) {
      if (H[j]) continue
      m = segmentos(A[j], B[j], SL, SB)
      for (k = 1; k <= m; k++) if (direta(SB[k], ad, SL[k])) ok = 1
      if (awk_exit(A, B, j, e)) ok = 1
    }
    if (ok) HA[nomef] = 1
    i = e
  }
}
# Assercao direta: a ERE do adaptador; ou interpretador com assercao inline (python3 -c "...assert...", jq -e).
function direta(sb, ad, sl) {
  sb = sem_prefixo(sb, ad)
  if (sb ~ /^(\[|\[\[|assert|refute|run |test |diff |cmp |grep|\(\(|! )/) return 1
  # `_harness_falhar` e a primitiva de falha do harness do projeto (tests/support/harness.sh): `cond || _harness_falhar`.
  if (ad == "shell" && sb ~ /^(afirmar|esperar|_harness_falhar)([ \t]|$)/) return 1
  if (sb ~ /^(python3?|node|ruby|perl)[ \t]/ && sl ~ /assert/) return 1
  if (sb ~ /^(return|exit)[ \t]+[1-9]/) return 1
  return (sb ~ /^jq[ \t]+(-[A-Za-z]*e|--exit-status)/)
}
function ler(f, A,   n, l) {
  split("", A); n = 0
  while ((getline l < f) > 0) A[++n] = l
  close(f)
  return n
}
# Funcoes de arquivos carregados (load, source, .) do mesmo diretorio.
function carregados(A, B, H, n, dir, ad,   i, w, nw, arg, c, LA, LB, LH, ln, n2) {
  for (i = 1; i <= n; i++) {
    if (H[i] || B[i] !~ /^[ \t]*(load|source|\.)[ \t]/) continue
    nw = palavras(A[i], w)
    if (nw < 2) continue
    arg = w[2]; gsub(/["\047]/, "", arg)
    if (arg ~ /\$/) sub(/^.*\//, "", arg)
    c = dir arg
    if ((getline ln < c) <= 0) { close(c); c = dir arg ".bash"; if ((getline ln < c) <= 0) { close(c); continue } }
    close(c)
    n2 = ler(c, LA); split("", LB); split("", LH)
    prep_sh(LA, n2, LB, LH)
    helpers(LA, LB, LH, n2, ad)
  }
}
function auditar_sh(f, ad, dir,   A, B, H, n, i, e, s, k, caso, ni, IL, IB, IN, j, m, SL, SB, sk, tem, w, nw, p, base, PA, PC, PN, np, achou) {
  n = ler(f, A); split("", B); split("", H); split("", HA); split("", AUS)
  prep_sh(A, n, B, H)
  helpers(A, B, H, n, ad)
  carregados(A, B, H, n, dir, ad)
  np = 0
  for (i = 1; i <= n; i++) {
    if (H[i]) continue
    if (ad == "bats") {
      if (B[i] !~ /^[ \t]*@test[ \t]/) continue
      caso = nome_aspas(A[i])
    } else {
      if (!match(B[i], /^[ \t]*(function[ \t]+)?teste_[A-Za-z0-9_]*[ \t]*\(\)/)) continue
      caso = substr(B[i], 1, RLENGTH); sub(/^[ \t]*(function[ \t]+)?/, "", caso); sub(/[ \t]*\(\)$/, "", caso)
    }
    ncasos++
    if (modo == "listar") { print f "\t" caso }
    # Instrucoes do corpo: linha, texto, texto branqueado.
    ni = 0
    if (B[i] ~ /\{.*}[ \t;]*$/) {
      k = index(B[i], "{"); s = B[i]; sub(/}[ \t;]*$/, "", s)
      if (trim(substr(s, k + 1)) != "") { ni++; IN[ni] = i; IL[ni] = substr(A[i], k + 1, length(s) - k); IB[ni] = substr(s, k + 1) }
      e = i
    } else {
      e = fim_bloco(A, B, H, n, i)
      for (j = i + 1; j < e; j++) {
        if (H[j] || trim(B[j]) == "" || trim(B[j]) == "{") continue
        ni++; IN[ni] = j; IL[ni] = A[j]; IB[ni] = B[j]
      }
    }
    if (modo == "listar") { i = e; continue }
    # SKIP: skip/pular/return incondicional como primeira instrucao.
    sk = 0
    if (ni > 0) {
      s = trim(IB[1])
      if ((s ~ /^skip([ \t;]|$)/ || (ad == "shell" && s ~ /^pular([ \t;]|$)/)) && s !~ /&&|\|\||\[|(^|[ \t;])if[ \t]/) sk = 1
      if (s ~ /^return([ \t]+0)?[ \t]*(;|$)/) sk = 1
    }
    # Esqueleto pendente (so Bats): unica instrucao `skip "pendente: <motivo>"`, motivo nao vazio, sem codigo depois.
    if (sk && ad == "bats" && ni == 1 && trim(IB[1]) ~ /^skip[ \t]+["\047][ \t]*["\047][ \t;]*$/ && trim(IL[1]) ~ /^skip[ \t]+["\047]pendente:[ \t]*[^ \t"\047]/) {
      print "PENDENTE\tAVISO PENDENTE " f " :: " caso " :: linha " IN[1]; i = e; continue
    }
    if (sk) { achado("BLOQUEANTE", "SKIP", f, caso, IN[1]); i = e; continue }
    tem = 0
    for (j = 1; j <= ni; j++) {
      if (awk_exit(A, B, IN[j], e + 1)) tem = 1
      m = segmentos(IL[j], IB[j], SL, SB)
      for (k = 1; k <= m; k++) {
        if (assercao_sh(SB[k], ad, SL[k])) tem = 1
        # LITERAL
        nw = palavras(SL[k], w)
        if (SB[k] ~ /^(\[|\[\[|test)[ \t]/) {
          if (w[nw] == "]" || w[nw] == "]]") nw--
          if (nw == 4 && w[3] ~ /^(=|==|!=|=~|-eq|-ne|-lt|-le|-gt|-ge)$/ && literal(w[2]) && literal(w[4])) achado("MAIOR", "LITERAL", f, caso, IN[j])
          if (nw == 4 && w[2] == "!" && w[3] ~ /^-[efdsL]$/) { base = base_literal(w[4]); if (base != "") { np++; PA[np] = base; PC[np] = caso; PN[np] = IN[j]; AUS[IN[j]] = 1 } }
        } else if (SB[k] ~ /^assert_(igual|equal|equals|eq)[ \t]/) {
          if (nw == 3 && literal(w[2]) && literal(w[3])) achado("MAIOR", "LITERAL", f, caso, IN[j])
        } else if (SB[k] ~ /^(assert_arquivo_ausente|assert_file_not_exists?|assert_not_exists?|assert_dir_not_exists?|refute_file_exists?)[ \t]/) {
          base = base_literal(w[2]); if (base != "") { np++; PA[np] = base; PC[np] = caso; PN[np] = IN[j]; AUS[IN[j]] = 1 }
        }
      }
    }
    if (!tem) achado("BLOQUEANTE", "SEM-ASSERCAO", f, caso, i)
    i = e
  }
  for (p = 1; p <= np; p++) {
    achou = 0
    for (j = 1; j <= n && !achou; j++) if (!(j in AUS) && index(A[j], PA[p]) > 0) achou = 1
    if (!achou) print "CANDIDATO\t" PA[p] "\tAVISO AUSENCIA " f " :: " PC[p] " :: linha " PN[p]
  }
}

# ---------- jest / vitest ----------
# Branqueia strings (mantendo as aspas) e comentarios, com estado entre linhas.
function prep_js(A, n, C,   i, j, c, st, out, l, pv, k, cl, fim_re, ult) {
  st = 0; pv = ""
  for (i = 1; i <= n; i++) {
    l = A[i]; out = ""
    for (j = 1; j <= length(l); j++) {
      c = substr(l, j, 1)
      if (st == 0) {
        if (c == "/" && substr(l, j + 1, 1) == "/") { while (j <= length(l)) { out = out " "; j++ }; break }
        if (c == "/" && substr(l, j + 1, 1) == "*") { st = 4; out = out "  "; j++; continue }
        if (c == "/" && inicio_regex(out, pv)) {
          # literal de regex: branqueia o miolo (ate a barra que fecha, fora de classe, na mesma linha)
          fim_re = 0; cl = 0
          for (k = j + 1; k <= length(l); k++) {
            ult = substr(l, k, 1)
            if (ult == "\\") { k++; continue }
            if (ult == "[") cl = 1; else if (ult == "]") cl = 0
            else if (ult == "/" && !cl) { fim_re = k; break }
          }
          if (fim_re > 0) {
            out = out "/"
            for (k = j + 1; k < fim_re; k++) out = out " "
            out = out "/"; j = fim_re; pv = "/"; continue
          }
        }
        if (c == "\047") st = 1; else if (c == "\"") st = 2; else if (c == "`") st = 3
        out = out c
        if (c != " " && c != "\t") pv = c
      } else if (st == 4) {
        if (c == "*" && substr(l, j + 1, 1) == "/") { st = 0; out = out "  "; j++ } else out = out " "
      } else {
        if (c == "\\") { out = out "  "; j++; continue }
        if ((st == 1 && c == "\047") || (st == 2 && c == "\"") || (st == 3 && c == "`")) { st = 0; out = out c; pv = c }
        else out = out " "
      }
    }
    C[i] = out
  }
}
# A "/" que vem depois de out (texto ja branqueado da linha) e de pv (ultimo caractere util antes) abre um regex? So
# depois de operador, abertura ou palavra-chave; depois de identificador, numero, `)`, `]` ou string e divisao.
function inicio_regex(out, pv,   w) {
  if (match(out, /[A-Za-z_$][A-Za-z0-9_$]*[ \t]*$/)) {
    w = substr(out, RSTART, RLENGTH); sub(/[ \t]+$/, "", w)
    return (w ~ /^(return|typeof|case|in|of|void|delete|throw|else|do|yield|await)$/)
  }
  if (pv == "") return 1
  return (index("(,=:[!&|?{};+-*%<>~^", pv) > 0)
}
# A partir do "(" em C[i], coluna p, acha o ")" correspondente: EL/EC.
function fecha(C, n, i, p,   d, j, c, ini) {
  d = 0
  for (; i <= n; i++) {
    for (j = p; j <= length(C[i]); j++) {
      c = substr(C[i], j, 1)
      if (c == "(") d++
      else if (c == ")") { d--; if (d == 0) { EL = i; EC = j; return 1 } }
    }
    p = 1
  }
  EL = n; EC = length(C[n]); return 0
}
# Texto de C entre (i,p) e (EL,EC), linha a linha, em T[1..] com numero em TN.
function trecho(C, i, p, el, ec, T, TN,   k, n) {
  split("", T); split("", TN); n = 0
  for (k = i; k <= el; k++) {
    n++; TN[n] = k
    if (k == i && k == el) T[n] = substr(C[k], p, ec - p + 1)
    else if (k == i) T[n] = substr(C[k], p)
    else if (k == el) T[n] = substr(C[k], 1, ec)
    else T[n] = C[k]
  }
  return n
}
# Assercao direta em texto JS ja sem strings nem comentarios: expect, assert, toThrow, resolves/rejects; formas do
# Cypress (.should, .and, cy.contains, .its) e `throw new Error`.
function js_direta(t) {
  return (t ~ /expect[ \t]*\(|assert|toThrow|\.resolves|\.rejects|\.should[ \t]*\(|\.and[ \t]*\(|cy\.contains[ \t]*\(|\.its[ \t]*\(|throw[ \t]+new[ \t]+Error/)
}
# O texto t chama a funcao `nome` (palavra inteira, nao membro de objeto, seguida de "(")?
function js_chama(t, nome,   p, r, a, d) {
  r = t
  while ((p = index(r, nome)) > 0) {
    a = (p > 1) ? substr(r, p - 1, 1) : " "
    d = substr(r, p + length(nome))
    sub(/^[ \t]+/, "", d)
    if (a !~ /[A-Za-z0-9_$.]/ && substr(d, 1, 1) == "(" && substr(r, p + length(nome), 1) !~ /[A-Za-z0-9_$]/) return 1
    r = substr(r, p + length(nome))
  }
  return 0
}
# Funcoes e consts do arquivo (texto F, sem strings nem comentarios): corpo de cada uma em JB[nome]. Os que tem
# assercao direta entram em JH0; os que chamam um de JH0 entram em JH1 (dois niveis; tres niveis nao contam).
function js_helpers(F,   r, off, m, nome, ini, k, d, c, corpo, q, fimc, nn, N, i, ch) {
  split("", JB); split("", JH0); split("", JH1); nn = 0; off = 0
  while (match(substr(F, off + 1), /(^|[^A-Za-z0-9_$.])(function[ \t]*\*?[ \t]*[A-Za-z_$][A-Za-z0-9_$]*[ \t]*\(|(const|let|var)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=[ \t]*(async[ \t]+)?(function|\(|[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=>))/)) {
    ini = off + RSTART; m = substr(F, ini, RLENGTH); off = ini + RLENGTH - 1
    nome = m
    if (nome ~ /function/) { sub(/^[^f]*function[ \t]*\*?[ \t]*/, "", nome) } else { sub(/^[^a-z]*(const|let|var)[ \t]+/, "", nome) }
    sub(/[^A-Za-z0-9_$].*$/, "", nome)
    # corpo: do primeiro "{" (ou da expressao apos "=>") ate o fim
    r = substr(F, off + 1); corpo = ""
    q = index(r, "=>")
    k = index(r, "{")
    if (m !~ /function/ && q > 0 && (k == 0 || q < k)) {
      d = substr(r, q + 2); sub(/^[ \t\n]+/, "", d)
      if (substr(d, 1, 1) != "{") {
        # expressao: ate o fim do statement (";" ou fim de linha com parenteses fechados)
        corpo = ""; k = 0
        for (i = 1; i <= length(d); i++) {
          ch = substr(d, i, 1)
          if (ch == "(") k++; else if (ch == ")") k--
          if ((ch == ";" || ch == "\n") && k <= 0) break
          corpo = corpo ch
        }
        nn++; N[nn] = nome; JB[nome] = corpo; continue
      }
      r = d; k = 1
    }
    if (k == 0) continue
    d = 0; corpo = ""
    for (i = k; i <= length(r); i++) {
      ch = substr(r, i, 1)
      if (ch == "{") d++
      else if (ch == "}") { d--; if (d == 0) break }
      corpo = corpo ch
    }
    nn++; N[nn] = nome; JB[nome] = corpo
  }
  for (i = 1; i <= nn; i++) if (js_direta(JB[N[i]])) JH0[N[i]] = 1
  for (i = 1; i <= nn; i++) if (!(N[i] in JH0)) for (k in JH0) if (js_chama(JB[N[i]], k)) { JH1[N[i]] = 1; break }
}
# O texto t chama algum helper de ate dois niveis?
function js_via_helper(t,   k) {
  for (k in JH0) if (js_chama(t, k)) return 1
  for (k in JH1) if (js_chama(t, k)) return 1
  return 0
}
function auditar_js(f,   A, C, n, i, off, rest, kw, mods, p, q, caso, grupo, sk, el, ec, T, TN, nt, k, tem, s, achou, np, PA, PC, PN, AUS, u, lit, x, j, pos, T2, F) {
  n = ler(f, A); split("", C); split("", AUS)
  prep_js(A, n, C)
  F = ""; for (k = 1; k <= n; k++) F = F C[k] "\n"
  js_helpers(F)
  np = 0
  lit = "(-?[0-9]+(\\.[0-9]+)?|\"[^\"$]*\"|\047[^\047]*\047|true|false|null|undefined)"
  for (i = 1; i <= n; i++) {
    off = 0
    while (match(substr(C[i], off + 1), /(^|[^A-Za-z0-9_$.])(xdescribe|xit|xtest|describe|it|test)(\.[A-Za-z]+)*[ \t]*\(/)) {
      pos = off + RSTART; rest = substr(C[i], pos, RLENGTH)
      off = pos + RLENGTH - 1
      sub(/^[^A-Za-z]/, "", rest); sub(/[ \t]*\($/, "", rest)
      kw = rest; sub(/\..*$/, "", kw); mods = rest; sub(/^[A-Za-z]+/, "", mods)
      if (mods ~ /\.todo/) continue
      grupo = (kw ~ /describe$/)
      p = off                       # coluna do "("
      if (mods ~ /\.(each|skipIf|runIf)/) {
        fecha(C, n, i, p)
        if (EL != i || substr(C[i], EC + 1, 1) != "(") continue
        p = EC + 1
      }
      sk = (kw ~ /^x/ || mods ~ /\.skip(\.|$)/)
      q = index(substr(C[i], p), "\"") ; u = index(substr(C[i], p), "\047"); x = index(substr(C[i], p), "`")
      if (q == 0 || (u > 0 && u < q)) q = u
      if (q == 0 || (x > 0 && x < q)) q = x
      caso = (q > 0) ? string_em(A[i], p + q - 1) : "(sem titulo)"
      if (!grupo) ncasos++
      if (modo == "listar") { if (!grupo) print f "\t" caso; continue }
      if (sk) { achado("BLOQUEANTE", "SKIP", f, caso, i); continue }
      if (grupo) continue
      fecha(C, n, i, p); el = EL; ec = EC
      nt = trecho(C, i, p, el, ec, T, TN)
      # return incondicional como primeira instrucao do corpo
      s = ""
      for (k = 1; k <= nt; k++) {
        if (s == "") { j = index(T[k], "{"); if (j == 0) continue; s = "x"; T2 = substr(T[k], j + 1) } else T2 = T[k]
        if (trim(T2) == "") continue
        if (trim(T2) ~ /^return[ \t]*(;|}|$)/) { achado("BLOQUEANTE", "SKIP", f, caso, TN[k]); sk = 1 }
        break
      }
      if (sk) continue
      tem = 0
      for (k = 1; k <= nt; k++) if (js_direta(T[k]) || js_via_helper(T[k])) tem = 1
      if (!tem) achado("BLOQUEANTE", "SEM-ASSERCAO", f, caso, i)
      for (k = 1; k <= nt; k++) {
        j = TN[k]
        if (A[j] ~ ("expect\\(" lit "\\)(\\.not)?\\.(toBe|toEqual|toStrictEqual)\\(" lit "\\)")) achado("MAIOR", "LITERAL", f, caso, j)
        if (A[j] ~ /expect\([ \t]*(fs\.)?existsSync\(/ && A[j] ~ /\)\)(\.toBe\(false\)|\.toBeFalsy\(\)|\.not\.toBeTruthy\(\)|\.not\.toBe\(true\))/) {
          s = A[j]; sub(/\)\)\.(toBe|toBeFalsy|not).*$/, "", s)
          if (match(s, /["\047][^"\047]*["\047][^"\047]*$/)) {
            s = substr(s, RSTART + 1); sub(/["\047].*$/, "", s); s = base_literal(s)
            if (s != "") { np++; PA[np] = s; PC[np] = caso; PN[np] = j; AUS[j] = 1 }
          }
        }
      }
    }
  }
  for (k = 1; k <= np; k++) {
    achou = 0
    for (j = 1; j <= n && !achou; j++) if (!(j in AUS) && index(A[j], PA[k]) > 0) achou = 1
    if (!achou) print "CANDIDATO\t" PA[k] "\tAVISO AUSENCIA " f " :: " PC[k] " :: linha " PN[k]
  }
}

{
  ad = $1; f = $2; narq++
  dir = f; if (dir ~ /\//) sub(/[^\/]*$/, "", dir); else dir = ""
  if (ad == "jest") auditar_js(f); else auditar_sh(f, ad, dir)
}
END {
  print "arquivos: " narq + 0 " | casos: " ncasos + 0 " | bloqueantes: " nb + 0 " | maiores: " nm + 0
  exit (nb + nm > 0) ? 1 : 0
}
AWK
awk -F '\t' -v modo="$modo" -f "$tmp/auditar.awk" "$tmp/alvos" > "$tmp/saida"
rc=$?
[ "$rc" -le 1 ] || { echo "falha na analise (awk saiu $rc)" >&2; exit 2; }

if [ "$modo" = listar ]; then grep -v '^arquivos: ' "$tmp/saida" | sort; exit 0; fi

# Ausencia: o candidato (caminho que nenhuma outra linha do proprio teste cita) so vira AVISO se o nome, ou o nome
# sem a ultima extensao (o produto pode compor `$x.trava`), tambem nao aparece em nenhum arquivo versionado que
# nao seja teste auditado (o produto que poderia cria-lo).
cut -f 2 "$tmp/alvos" > "$tmp/testes"
grep "^CANDIDATO$tab" "$tmp/saida" > "$tmp/candidatos"
: > "$tmp/avisos"
no_produto() {
  [ -n "$1" ] && git grep -F -l -e "$1" 2>/dev/null | grep -v -x -F -f "$tmp/testes" | grep -q .
}
while IFS="$tab" read -r _ base linha; do
  radical="${base%.*}"
  [ "$radical" != "$base" ] || radical=""
  no_produto "$base" || no_produto "$radical" || printf '%s\n' "$linha" >> "$tmp/avisos"
done < "$tmp/candidatos"
# Esqueleto pendente: uma linha propria por caso, contado em avisos; nao muda o exit.
grep "^PENDENTE$tab" "$tmp/saida" | cut -f 2 >> "$tmp/avisos"
sort -u "$tmp/avisos" -o "$tmp/avisos"

{ grep -v -e '^arquivos: ' -e "^CANDIDATO$tab" -e "^PENDENTE$tab" "$tmp/saida"; cat "$tmp/avisos"; } | sort -u
printf '%s | avisos: %s\n' "$(grep '^arquivos: ' "$tmp/saida")" "$(wc -l < "$tmp/avisos" | tr -d ' ')"
exit "$rc"
