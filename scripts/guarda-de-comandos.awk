# Leitura por palavra de guarda-de-comandos.sh: `awk -v sq="'" [-v integracao="<branches>"] -f guarda-de-comandos.awk`,
# com o texto do comando em stdin. Imprime ` push` se ha `git [opcoes globais] push`, ` mira` se esse push nomeia como
# destino uma das branches de `integracao` (separadas por espaco: `<b>`, `+<b>`, `refs/heads/<b>`, `<ref>:<b>`; e
# `--all`, `--mirror`, `--branches`), ` pr` se ha `gh pr create` ou `gh pr new` (tambem por caminho, `/usr/bin/gh`, e
# com opcoes entre `pr` e o subcomando), ` forca` se esse push traz force em qualquer posicao (`--force*`,
# `--force-with-lease[=v]`, `--force-if-includes`, `--mirror`, abreviacoes (`--f`, `--for`, `--mi`; `--follow-tags` nao), `-f`, grupo de curtas com `f` como `-uf`, refspec iniciado por `+`),
# ` reversao` se ha `git switch` com `--discard-changes`/`--force`/`--force-create`/`-f`/`-C`, `git worktree remove` com
# `--force`/`-f` ou `git branch` com `-D`/`-M`/`-C`/`-f`/`--force`; em `switch`, `worktree remove` e `branch` a opcao longa
# vale tambem abreviada (`--disc`, `--f`, `--force-c`, com ao menos 3 caracteres e `=valor` ignorado; abreviacao
# ambigua so erra no git, entao pergunta de mais) e ` aberto` se alguma leitura terminou com aspa ou `$(` sem fechar. `sq` e a
# aspa simples, passada por -v.
#
# Tokens da autorizacao de sessao (leitura da primeira passada, o texto do comando; so o `sh` decide com eles):
# ` elegivel` se TODO segmento e `cd <dir>` ou git/gh da lista de rotina e reversao (git: worktree fetch merge
# merge-base rebase pull branch switch push log status rev-parse diff show rev-list ls-files ls-remote ls-tree show-ref
# symbolic-ref for-each-ref add commit tag cherry-pick revert reset clean restore checkout stash, e remote so sem
# subcomando, com -v, show ou get-url; gh: pr create|view|list|diff|ready|edit|checks|comment, run
# list|view|watch|rerun, issue view|list|comment) e nada mais: opcao global de git diferente de -C, rebase -x/--exec,
# --upload-pack/--receive-pack/--exec em fetch/pull/push, argumento iniciado por `$`, pipe, redirecao de saida que nao
# seja /dev/null ou descritor, `$( )`, crase, heredoc, aspa aberta, outro binario ou variavel de ambiente na frente
# tornam inelegivel. ` gatilho` se ha o que hoje pergunta (tag, cherry-pick, revert, remote, reversao, forma com -C,
# gh pr checks|comment, run list|view|watch, issue); ` rv-total` se ha reversao (a ` reversao` acima ou git reset,
# clean, restore, checkout, stash; tambem no texto citado, lado de perguntar); ` rv-sempre` se a reversao e daquelas
# em que o detector nao enxerga o alvo (`git worktree remove --force`, `git clean` com -x/-X, `git stash` com -a/--all,
# `git branch` com -D/-M/-C/-f/--force, reversao com `-C` ou com `cd` no comando). Tambem tornam inelegivel: escrita
# (tudo que nao e leitura, fetch ou worktree sem remove, e todo gh fora de pr view|list|diff|checks, run list|view|watch, issue view|list) em comando com `-C` ou `cd`; gh com -F/--body-file ou
# -R/--repo; palavra com `$` fora de aspas simples ou com chaves de expansao; --output/-o em log, diff e show.
#
# Tokenizador: fora de aspas, `; & | ( )` e quebra de linha fecham o segmento, espaco/tab/CR fecham a palavra e `\`
# seguida de quebra de linha continua a linha. Redirecionamento (descritor so numerico colado antes, operador `<`, `>`,
# `>>`, `>&`, `<&`, `&>`, `&>>`, `>|`, `<>`, e o alvo, colado ou na palavra seguinte) sai das palavras do segmento sem
# fecha-lo: `git 2>/dev/null push` e push; `<<` e `<<<` sao tratados a parte. O trecho entre aspas (inclusive `$'...'`) e parte da palavra. Trechos
# entre aspas, `$( )` (com aspas e parenteses aninhados), crase e corpo de heredoc sao enfileirados por `reler` e lidos
# de novo como comando, por causa de `sh -c '...'`; todas as faixas contam, entao texto citado tambem conta (o lado de
# bloquear). A leitura que termina com aspa ou `$(` aberto aplica tambem a regra antiga, por substring (`rede`,
# fail-closed). O texto e varrido por indice, em tempo linear, e palavra longa guarda so o comeco e o fim (`poe`).
#
# Alvo (2a linha em diante da saida, lida so pelo `sh`): `kinds<TAB>_C` por envio, com kinds `p` (envio), `pm` (envio que mira a
# integracao) ou `c` (criacao de PR); `_C` e a composicao dos `-C` do comando (`?` quando nao se resolve). `cd` nao e seguido.

function poe(c) {  # lit: 1 dentro de aspas simples ou $'...' (`$` e chaves literais), 2 dentro de aspas duplas (chaves literais)
  if (lit) { if (c == "{" || c == "}") c = "\003"; else if (lit == 1 && c == "$") c = "\002" }
  if (++wl <= 200) { wv = wv c; return }
  if (wl == 201) { tail = substr(wv, 169); tl = 32 }
  tail = tail c
  if (++tl > 64) { tail = substr(tail, 33); tl = 32 }
}
function fecha_palavra() {
  if (wl > 0) { if (alvo_redir) { alvo_redir = 0; if (princ && rdo && wv !~ /^(\/dev\/null|[0-9]+|-)$/) el = 0 } else seg[++ns] = (wl <= 200) ? wv : wv "\001" tail }
  wv = ""; wl = 0; tail = ""
}
function redirecao(i, z,   i0) {
  i0 = i  # i aponta para `<`, `>` ou o `&` de `&>`; descarta descritor e alvo; devolve o ultimo indice lido
  if (ch[i] != "&" && wl > 0 && wv ~ /^[0-9]+$/) { wv = ""; wl = 0; tail = "" } else fecha_palavra()
  if (ch[i] == "&") i++
  if (i < z && ((ch[i] == ">" && index(">&|", ch[i + 1])) || (ch[i] == "<" && index("&>", ch[i + 1])))) i++
  alvo_redir = 1; rdo = (ch[i0] == ">" || ch[i0] == "&")
  return i
}
function mira(w,   k, t) {  # w e destino de push que nomeia uma branch de integracao
  if (ni == 0 || w ~ /^-/) return 0
  sub(/^[+]/, "", w)
  k = index(w, ":"); if (k) w = substr(w, k + 1)
  sub(/^refs\/heads\//, "", w)
  for (t = 1; t <= ni; t++) if (w == integ[t]) return 1
  return 0
}
function todas(w) { return w == "--all" || w == "--mirror" || w == "--branches" }  # push de todas as branches: conta como mira
function curto(w, c) { return w ~ /^-[A-Za-z]+$/ && index(w, c) }  # grupo de opcoes curtas (-uf) que contem a letra c
function pref(w, longo,   k) {  # w (sem `=valor`) tem 3+ caracteres, comeca por `--` e e prefixo de `longo`: o git aceita a abreviacao unica
  k = index(w, "="); if (k) w = substr(w, 1, k - 1)
  return length(w) >= 3 && substr(w, 1, 2) == "--" && index(longo, w) == 1
}
function forca(w) {  # w e force em push: --force*, abreviacao dela, --mirror (e abreviacao), -f, grupo com f, refspec +
  return w ~ /^--force/ || pref(w, "--force-with-lease") || pref(w, "--force-if-includes") || pref(w, "--mirror") || curto(w, "f") || w ~ /^[+]./
}
function forca_f(w) { return pref(w, "--force") || curto(w, "f") }
function reversao(cmd, j, k,   d, D, f) {  # subcomando rotineiro com flag destrutiva (regra 48): switch, worktree remove, branch
  if (cmd == "switch") {
    for (k = j + 1; k <= ns; k++) if (pref(seg[k], "--discard-changes") || pref(seg[k], "--force-create") || forca_f(seg[k]) || curto(seg[k], "C")) return 1
  } else if (cmd == "worktree" && j + 1 <= ns && seg[j + 1] == "remove") {
    for (k = j + 2; k <= ns; k++) if (forca_f(seg[k])) return 1
  } else if (cmd == "branch") {  # -D, -M e -C (forca embutida), ou -f/--force (reposiciona ou sobrescreve; com -d/--delete tambem)
    for (k = j + 1; k <= ns; k++) if (seg[k] ~ /^-[A-Za-z]*[DMC]/ || forca_f(seg[k])) return 1
  }
  return 0
}
function setgat() { if (princ) gat = 1 }
function palavra_simples(w) { return w !~ /[ \t\001]/ }
function arg_perigoso(sc, k,   w, b) {  # argumento que torna o comando inelegivel (opcao que executa programa, expansao)
  for (; k <= ns; k++) {
    w = seg[k]
    if (w ~ /[$]/ || w ~ /[{].*[}]/) return 1  # expansao em qualquer posicao da palavra (fora de aspas simples) ou chaves de expansao
    if (sc == "gh") {  # -F/--body-file le arquivo local; -R/--repo troca o repositorio (colados ou separados, abreviados)
      b = w; sub(/=.*/, "", b)
      if (w ~ /^-[A-Za-z]*[FR]/ || (pref(w, "--body-file") && b != "--body") || pref(w, "--repo")) return 1
    }
    if ((sc == "log" || sc == "diff" || sc == "show") && (w ~ /^-o/ || pref(w, "--output"))) return 1
    if (sc == "rebase" && (w ~ /^-x/ || curto(w, "x") || pref(w, "--exec"))) return 1
    if ((sc == "fetch" || sc == "pull" || sc == "push") && (pref(w, "--upload-pack") || pref(w, "--receive-pack") || pref(w, "--exec"))) return 1
  }
  return 0
}
function classe_git(sc, j,   k, cflag) {  # seg[j] = sc; devolve por efeito: el, gat, rvt, rvs
  if (!palavra_simples(sc)) { if (princ) el = 0; return }
  cflag = (cmdc > 0)
  if (index(ROTINA, " " sc " ")) { }
  else if (index(NOVOS, " " sc " ")) setgat()
  else if (index(REVERSAO, " " sc " ")) { setgat(); rvt = 1 }
  else if (sc == "remote") {
    setgat()
    if (!(j == ns || (j + 1 == ns && seg[ns] == "-v") || (j + 1 <= ns && (seg[j + 1] == "show" || seg[j + 1] == "get-url")))) { if (princ) el = 0 }
  } else { if (princ) el = 0; return }
  if (arg_perigoso(sc, j + 1) && princ) el = 0
  if (reversao(sc, j)) { setgat(); rvt = 1; if (sc == "worktree") rvs = 1 }
  if (sc == "clean") for (k = j + 1; k <= ns; k++) if (curto(seg[k], "x") || curto(seg[k], "X")) rvs = 1
  if (sc == "stash") for (k = j + 1; k <= ns; k++) if (pref(seg[k], "--all") || curto(seg[k], "a")) rvs = 1  # -a leva arquivo ignorado, que o detector nao ve
  if (sc == "branch" && reversao(sc, j)) rvs = 1  # -D/-M/-C/-f: o detector so olha a branch atual
  if (cflag) { setgat(); if (rvt) rvs = 1; if (princ) mdir = 1 }
  if (princ && !index(LEITURA, " " sc " ") && sc != "fetch" && sc != "remote" && !(sc == "worktree" && seg[j + 1] != "remove")) escreve = 1
}
function classe_gh(i,   g, s) {  # seg[i] = gh
  g = seg[i + 1]; s = seg[i + 2]
  if (!(i + 2 <= ns && index(GH, " " g " " s " "))) { if (princ) el = 0; return }
  if (arg_perigoso("gh", i + 3) && princ) el = 0
  if (princ && !index(GHLEIT, " " g " " s " ")) escreve = 1  # gh que nao e de leitura: com `cd` o repositorio alvo muda, entao fica inelegivel
  if (index(GHGAT, " " g " " s " ") || g == "issue") setgat()
}
function classifica(  j, c) {  # seg[1..ns] e um segmento; so a primeira palavra e o comando da rotina
  if (ns == 0) return
  if (princ) nseg++
  if (seg[1] == "cd") { if (ns == 2 && seg[2] !~ /^-/) { cd = 1; if (princ) mdir = 1 } else if (princ) el = 0; return }
  if (seg[1] == "git") {
    j = 2; cmdc = 0
    while (j <= ns && seg[j] ~ /^[-$]/) {
      if (seg[j] == "-C" && j + 1 <= ns) { cmdc = 1; j += 2; continue }
      if (princ) el = 0
      return
    }
    if (j > ns) { if (princ) el = 0; return }
    classe_git(seg[j], j)
    return
  }
  if (seg[1] == "gh") { classe_gh(1); return }
  if (princ) el = 0
}
function compoe(base, w) {  # `-C` composto: `w` relativo a `base`; "?" quando nao se resolve (expansao, til, vazio)
  if (w == "" || w ~ /[\001\002\003\t$]/ || w ~ /^~/) return "?"
  if (w ~ /^\//) return w
  if (base == "?") return "?"
  return (base == "") ? w : base "/" w
}
function grava(kinds, cw) { ne++; ek[ne] = kinds; ecw[ne] = cw }
function fecha_segmento(  i, j, k, cw, mm) {
  fecha_palavra(); alvo_redir = 0
  classifica()
  for (i = 1; i <= ns; i++) {
    if (seg[i] == "git" || seg[i] ~ /\/git$/) {
      j = i + 1; cw = ""
      while (j <= ns && seg[j] ~ /^[-$]/) {  # opcoes globais; palavra que comeca por `$` pode expandir em opcoes
        if (seg[j] ~ /^[$]/) cw = "?"
        if (seg[j] == "-C" && j + 1 <= ns) cw = compoe(cw, seg[j + 1])
        if (seg[j] ~ /^-C./) cw = compoe(cw, substr(seg[j], 3))  # `-C<dir>` colado
        if (seg[j] == "-C" || seg[j] == "-c" || seg[j] == "--git-dir" || seg[j] == "--work-tree" || seg[j] == "--namespace" || seg[j] == "--config-env" || seg[j] == "--attr-source") j++
        j++
      }
      # `--git-dir`, `--work-tree` e GIT_DIR/GIT_WORK_TREE mudam o repositorio sem o `-C`: o alvo nao se resolve, confere o cwd.
      for (k = 1; k < j; k++) if (seg[k] ~ /^--(git-dir|work-tree)(=|$)/ || (k < i && seg[k] ~ /^GIT_(DIR|WORK_TREE)=/)) cw = "?"
      if (j <= ns && seg[j] == "push") {
        p = 1; mm = 0
        for (k = j + 1; k <= ns; k++) { if (mira(seg[k]) || (ni && todas(seg[k]))) { m = 1; mm = 1 } if (forca(seg[k])) fo = 1 }
        grava(mm ? "pm" : "p", cw)
      }
      if (j <= ns && reversao(seg[j], j)) rv = 1
    }
    if ((seg[i] == "gh" || seg[i] ~ /\/gh$/) && i + 1 <= ns && seg[i + 1] == "pr") {
      j = i + 2
      while (j <= ns && seg[j] ~ /^-/) { if (seg[j] == "--repo" || seg[j] == "-R") j++; j++ }
      if (j <= ns && (seg[j] == "create" || seg[j] == "new")) { cria = 1; grava("c", "") }
    }
  }
  for (i = 1; i <= ns; i++) delete seg[i]
  ns = 0
}
function reler(a, z) { if (z >= a) { fi[++nf] = a; ff[nf] = z } }
function fim_simples(i, z, por) { for (; i <= z; i++) { if (ch[i] == sq) return i; if (por) { lit = 1; poe(ch[i]); lit = 0 } } return z + 1 }
function fim_ansi(i, z, por) {
  for (; i <= z; i++) {
    if (ch[i] == "\\" && i < z) { i++; if (por) { lit = 1; poe(ch[i]); lit = 0 } continue }
    if (ch[i] == sq) return i
    if (por) { lit = 1; poe(ch[i]); lit = 0 }
  }
  return z + 1
}
function fim_crase(i, z, por) {
  for (; i <= z; i++) {
    if (ch[i] == "\\" && i < z) { i++; if (por) poe(ch[i]); continue }
    if (ch[i] == "`") return i
    if (por) poe(ch[i])
  }
  return z + 1
}
function fim_dupla(i, z, por,   c) {
  for (; i <= z; i++) {
    c = ch[i]
    if (c == "\\" && i < z && index("\"\\`$\n", ch[i + 1])) { i++; if (por && ch[i] != "\n") poe(ch[i]); continue }
    if (c == "\"") return i
    if (c == "`") { if (princ) el = 0; i = fim_crase(i + 1, z, 0); if (por) poe("$"); continue }
    if (c == "$" && i < z && ch[i + 1] == "(") { if (princ) el = 0; i = fim_subst(i + 2, z); if (por) poe("$"); continue }
    if (por) { lit = 2; poe(c); lit = 0 }
  }
  return z + 1
}
function delimitador(i, z,   k, d, c) {  # i aponta para o primeiro `<` de `<<`; devolve o ultimo indice lido
  k = i + 2; hdt[nh + 1] = 0
  if (k <= z && ch[k] == "-") { hdt[nh + 1] = 1; k++ }
  while (k <= z && (ch[k] == " " || ch[k] == "\t")) k++
  d = ""
  for (; k <= z; k++) {
    c = ch[k]
    if (index(" \t\n;&|()<>", c)) break
    if (c != sq && c != "\"" && c != "\\" && length(d) < 100) d = d c
  }
  if (d != "") hd[++nh] = d
  return k - 1
}
function corpos(i, z, base,   h, pos, bi, k, t, d, L, igual, achou) {  # i aponta para a quebra de linha; devolve o ultimo indice lido
  pos = i + 1
  for (h = base + 1; h <= nh; h++) {
    d = hd[h]; L = length(d); bi = pos; achou = 0
    while (pos <= z) {
      k = pos
      if (hdt[h]) while (k <= z && ch[k] == "\t") k++
      igual = 1
      for (t = 1; t <= L; t++) if (k + t - 1 > z || ch[k + t - 1] != substr(d, t, 1)) { igual = 0; break }
      if (igual && (k + L > z || ch[k + L] == "\n")) { reler(bi, pos - 1); pos = k + L + 1; achou = 1; break }
      while (pos <= z && ch[pos] != "\n") pos++
      pos++
    }
    if (!achou) { reler(bi, z); pos = z + 1 }
  }
  nh = base
  return pos - 1
}
function fim_subst(i, z,   c, prof, base) {
  prof = 1; base = nh
  for (; i <= z; i++) {
    c = ch[i]
    if (c == "\\") { i++; continue }
    if (c == sq) { i = fim_simples(i + 1, z, 0); continue }
    if (c == "\"") { i = fim_dupla(i + 1, z, 0); continue }
    if (c == "`") { i = fim_crase(i + 1, z, 0); continue }
    if (c == "$" && i < z && ch[i + 1] == sq) { i = fim_ansi(i + 2, z, 0); continue }
    if (c == "<" && i < z && ch[i + 1] == "<") { if (i + 1 < z && ch[i + 2] == "<") i += 2; else i = delimitador(i, z); continue }
    if (c == "\n" && nh > base) { i = corpos(i, z, base); continue }
    if (c == "(") prof++
    if (c == ")" && --prof == 0) { nh = base; return i }
  }
  nh = base
  return z + 1
}
function juntar(a, z,   s, i, meio) {
  if (z - a < 64) { s = ""; for (i = a; i <= z; i++) s = s ch[i]; return s }
  meio = int((a + z) / 2)
  return juntar(a, meio) juntar(meio + 1, z)
}
function rede(a, z,   s, n, w, k, mm) {
  s = juntar(a, z)
  gsub("[;&|()\t\n\r\"`\\\\" sq "]", " ", s)
  s = " " s " "
  if (s ~ /[ \/]gh +pr .*(create|new) /) { cria = 1; grava("c", "") }
  if (s ~ /[ \/]git .*push /) {
    p = 1; mm = 0
    n = split(s, w, " ")
    for (k = 1; k <= n; k++) { if (mira(w[k]) || (ni && todas(w[k]))) { m = 1; mm = 1 } if (forca(w[k])) fo = 1 }
    grava(mm ? "pm" : "p", "")
  }
}
function ler(a, z,   i, c, j, aberto) {
  ns = 0; nh = 0; wv = ""; wl = 0; tail = ""; aberto = 0; alvo_redir = 0
  for (i = a; i <= z; i++) {
    c = ch[i]
    if (c == "\\") { if (i < z) { i++; if (ch[i] != "\n" && ch[i] != "\"" && ch[i] != sq) poe(ch[i]) } continue }
    if (c == sq) { j = fim_simples(i + 1, z, 1); reler(i + 1, j - 1); i = j; continue }
    if (c == "\"") { j = fim_dupla(i + 1, z, 1); reler(i + 1, j - 1); i = j; continue }
    if (c == "`") { if (princ) el = 0; j = fim_crase(i + 1, z, 0); poe("$"); reler(i + 1, j - 1); i = j; continue }
    if (c == "$" && i < z && ch[i + 1] == sq) { j = fim_ansi(i + 2, z, 1); reler(i + 2, j - 1); i = j; continue }
    if (c == "$" && i < z && ch[i + 1] == "(") { if (princ) el = 0; j = fim_subst(i + 2, z); poe("$"); reler(i + 2, j - 1); i = j; continue }
    if (c == "<" && i < z && ch[i + 1] == "<") {
      if (princ) el = 0
      fecha_palavra()
      if (i + 1 < z && ch[i + 2] == "<") i += 2; else i = delimitador(i, z)
      continue
    }
    if (c == "<" || c == ">" || (c == "&" && i < z && ch[i + 1] == ">")) { i = redirecao(i, z); continue }
    if (c == "\n") { fecha_segmento(); if (nh > 0) i = corpos(i, z, 0); continue }
    if (c == "|" && princ) el = 0
    if (index(";&|()", c)) { fecha_segmento(); continue }
    if (c == " " || c == "\t" || c == "\r") { fecha_palavra(); continue }
    poe(c)
  }
  if (i > z + 1) aberto = 1
  fecha_segmento()
  if (aberto) { ab = 1; rede(a, z) }
}
{ linha[NR] = $0 }
END {
  ni = split(integracao, integ, " ")
  N = 0
  for (r = 1; r <= NR; r++) { n = split(linha[r], parte, ""); for (k = 1; k <= n; k++) ch[++N] = parte[k]; ch[++N] = "\n" }
  nf = 1; fi[1] = 1; ff[1] = N
  ROTINA = " worktree fetch merge merge-base rebase pull branch switch push log status rev-parse diff show rev-list ls-files ls-remote ls-tree show-ref symbolic-ref for-each-ref add commit "
  NOVOS = " tag cherry-pick revert "
  REVERSAO = " reset clean restore checkout stash "
  GH = " pr create pr view pr list pr diff pr ready pr edit pr checks pr comment run list run view run watch run rerun issue view issue list issue comment "
  GHLEIT = " pr view pr list pr diff pr checks run list run view run watch issue view issue list "
  GHGAT = " pr checks pr comment run list run view run watch "
  LEITURA = " log status rev-parse diff show rev-list ls-files ls-remote ls-tree show-ref symbolic-ref for-each-ref merge-base "
  el = 1
  for (q = 1; q <= nf; q++) { princ = (q == 1); ler(fi[q], ff[q]) }
  if (p) printf " push"; if (m) printf " mira"; if (cria) printf " pr"; if (ab) printf " aberto"; if (fo) printf " forca"; if (rv) printf " reversao"
  if (rv || rvt) printf " rv-total"
  if (rvs || (cd && (rv || rvt))) printf " rv-sempre"
  if (mdir && escreve) el = 0  # -C ou cd junto de escrita: o detector e a suite leem o cwd, nao o destino; o prompt do cliente decide
  if (el && !ab && nseg > 0) printf " elegivel"
  if (gat) printf " gatilho"
  printf "\n"
  for (r = 1; r <= ne; r++) printf "%s\t_%s\n", ek[r], ecw[r]  # 2a linha em diante, lida so pelo `sh`: `kinds<TAB>_C` por envio
}
