# Inventario de utilitarios externos: GNU/Linux x FreeBSD base

| Campo | Valor |
|---|---|
| Demanda | `suporte-freebsd` (porte G); reabertura da `DP-07` em 2026-10-24 |
| Base | worktree `feature/chmod-portavel-bsd`, a partir de `master @ 6df321e` (v2.0.0) |
| Escopo varrido | `lib/*.sh`, `commands/*.sh`, `bin/dbx`, `install.sh`, `uninstall.sh` |
| Metodo | busca por expressao regular dos utilitarios externos e das opcoes GNU; leitura do contexto das linhas de risco. **Nao foi executado em FreeBSD**: o comportamento descrito e o do manual do FreeBSD 13/14 e precisa ser confirmado pelo solicitante (`DIV-355`) |
| Especificacao | `escopo-requisitos-e-criterios-de-aceite.md`, secao 5.22 |

Legenda da coluna **FreeBSD**: **FALHA** = o utilitario recusa a forma usada; **DIFERE** = roda, mas o resultado ou o ambiente muda; **IGUAL** = mesmo comportamento. Coluna **Fallback**: `sim` = a linha ja recua para outra forma; `parcial` = recua so em parte; `nao`.

Achado de contexto: o codigo nao usa `sed`, `date`, `awk`, `sort`, `cut`, `tr`, `grep` (exceto `commands/config.sh:128`), `base64`, `numfmt`, `tac`, `readlink -f` fora de `lib/cmd.sh`, `df`/`mktemp` com opcao longa, `cp`/`mv`/`ln` com opcao GNU nem `lsattr`/`getenforce` fora de guarda `command -v`. A epoca e o carimbo de data vem de `printf '%(...)T'` do proprio bash. Por isso a superficie de divergencia se concentra em `stat`, `chmod`, `find -printf`, `sha256sum` e `/dev/fd`/`/proc`.

## 1. Tabela

### 1.1 `bin/dbx`

| ID | Arquivo:linha | Construcao | FreeBSD | Alternativa portavel proposta | Fallback |
|---|---|---|---|---|---|
| I-01 | `bin/dbx:32-33` | `readlink -- "$_dbx_fonte"` | IGUAL | manter | n/a |
| I-02 | `bin/dbx:34-35` | `find "$f" -maxdepth 0 -printf '%l'` | FALHA (`find` BSD nao tem `-printf`) | irrelevante no FreeBSD (o ramo so roda sem `readlink`, que a base tem); manter como esta | e o proprio recuo de I-01 |

### 1.2 `lib/hash.sh`

| ID | Arquivo:linha | Construcao | FreeBSD | Alternativa portavel proposta | Fallback |
|---|---|---|---|---|---|
| I-03 | `lib/hash.sh:86,116-122` | lista de backends `sha256sum shasum openssl`, escolha por `command -v` | DIFERE (base sem `sha256sum` e sem `shasum`; tem `sha256` e `openssl`) | acrescentar `sha256` a lista, escolha por capacidade (`command -v`), sem `uname` | sim (`openssl`) |
| I-04 | `lib/hash.sh:134-135` | `sha256sum` (stdin) | FALHA (ausente na base) | `sha256 -q` (le stdin, imprime so o resumo) como 4o backend | sim, se `openssl` presente |
| I-05 | `lib/hash.sh:138-139` | `shasum -a 256` | FALHA (ausente na base; so com `p5-Digest-SHA`) | idem I-04 | sim |
| I-06 | `lib/hash.sh:144` | `openssl dgst -sha256` | DIFERE (saida `SHA2-256(stdin)= <hex>` ou `(stdin)= <hex>`, conforme a versao) | extrair o ultimo campo apos `= `; testar nos duplos | n/a |
| I-07 | `lib/hash.sh:223,285` | `tamanho=$(wc -c <arq)` | DIFERE (BSD preenche com espacos a esquerda) | ja tratado por `${t//[^0-9]/}` nas linhas 224 e 286; manter e cobrir por teste | sim |
| I-08 | `lib/hash.sh:284` | `head -c N >buf` | **DIFERE** (o `head -c` do FreeBSD le alem de N do descritor; medido no FreeBSD 15.1, 2026-10-26) | `dbx_ler_exato` (`RF-173`) | **sim** |
| I-09 | `lib/hash.sh:396` | `stat -c "%s<TAB>%Y\|%y\|%z\|%d\|%i\|%s" -- arq` | FALHA (`stat: illegal option -- c`) | formato BSD equivalente `stat -f '%z<TAB>%m\|%a\|%c\|%d\|%i\|%z'` tentado so quando a forma GNU falha (ver 2.1) | **nao** (o chamador `lib/walk.sh:162` recupera so o tamanho; identidade fica vazia e o resumo e sempre recalculado) |

### 1.3 `lib/tmp.sh`, `lib/progress.sh`, `lib/path.sh`, `lib/walk.sh`

| ID | Arquivo:linha | Construcao | FreeBSD | Alternativa portavel proposta | Fallback |
|---|---|---|---|---|---|
| I-10 | `lib/tmp.sh:244` | `mktemp [-d] -- "$modelo"` | IGUAL (a verificar: modelo com menos de 6 `X`; o guarda `*XXX` na linha 230 aceita 3) | exigir 6 `X` no guarda | n/a |
| I-11 | `lib/tmp.sh:108` | `kill -s SIG "$BASHPID"` | IGUAL (builtin do bash) | manter | n/a |
| I-12 | `lib/tmp.sh:192,271` | `rm -rf -- "$alvo"` | IGUAL | manter | n/a |
| I-13 | `lib/progress.sh:506` | `stat -c %s -- f \|\| stat -f %z -- f` | IGUAL (recuo BSD ja existe) | manter; passar a usar o auxiliar unico de 2.1 | sim |
| I-14 | `lib/progress.sh:414,490` | `kill -0`, `mv -f -- a b` | IGUAL | manter | n/a |
| I-15 | `lib/path.sh:350` | `readlink -- "$c" && printf '\0'` | IGUAL | manter | n/a |
| I-16 | `lib/walk.sh:159` | via `dbx_hash_identidade` (I-09) | FALHA (identidade vazia) | ver I-09 | parcial |
| I-17 | `lib/walk.sh:162` | `stat -f '%z' "$nome"` apos a forma GNU falhar | IGUAL | manter | sim |

### 1.4 `lib/cmd.sh`

| ID | Arquivo:linha | Construcao | FreeBSD | Alternativa portavel proposta | Fallback |
|---|---|---|---|---|---|
| I-18 | `lib/cmd.sh:592,869` | `readlink -f -- "$2"` | IGUAL no FreeBSD 13+ (a verificar: semantica de alvo inexistente) | manter; cobrir por teste no FreeBSD real | n/a |
| I-19 | `lib/cmd.sh:660,1046` | `stat -c %a -- "$alvo"` com `\|\| modo=''` | FALHA (modo fica vazio; o modo do arquivo substituido deixa de ser preservado) | auxiliar de 2.1 | **nao** |
| I-20 | `lib/cmd.sh:663,1049` | `chmod "$modo" -- "$temporario"` | **FALHA** (`chmod: --: No such file or directory`; `getopt` BSD nao permuta, o `--` apos o modo e operando) | `chmod -- "$modo" "$arquivo"` (valido nos dois) | **nao** (`\|\| :` esconde o erro) |
| I-21 | `lib/cmd.sh:664,1052` | `mv -f -- a b` | IGUAL | manter | n/a |
| I-22 | `lib/cmd.sh:765-773` | `[[ -f /dev/fd/N && -O /dev/fd/N ]]`, `exec {w}>>"/dev/fd/N"` | DIFERE (so existe com `fdescfs` montado; por padrao o devfs tem apenas `/dev/fd/0..2`) | ver `DIV-352` | **nao** |
| I-23 | `lib/cmd.sh:766` | `stat -L -c '%d\|%i\|%s' -- /dev/fd/N` | FALHA | auxiliar de 2.1 com `-L`; sujeito a `DIV-352` | **nao** (`\|\| info=''`) |
| I-24 | `lib/cmd.sh:834` | `stat -c %s -- "$2"` com `\|\| gravados=0` | FALHA (bytes gravados passam a 0: resultado errado, nao erro) | auxiliar de 2.1 | **nao** |
| I-25 | `lib/cmd.sh:942` | `stat -c '%d\|%i' -- "$part"` com `\|\| devino=''` | FALHA (identidade do `.part` vazia) | auxiliar de 2.1 | **nao** |
| I-26 | `lib/cmd.sh:972,975` | `/dev/fd/$_DBX_CMD_PART_FD` como operando de funcao | DIFERE | `DIV-352` | **nao** |

### 1.5 `lib/state.sh`

| ID | Arquivo:linha | Construcao | FreeBSD | Alternativa portavel proposta | Fallback |
|---|---|---|---|---|---|
| I-27 | `lib/state.sh:146,1013,1133,1415` | `mkdir -p -m 700 -- "$d"` | IGUAL | manter | n/a |
| I-28 | `lib/state.sh:153` | `chmod 700 -- "$diretorio"` | **FALHA** (mesmo defeito de I-20) | `chmod -- 700 "$diretorio"` | **nao** (`\|\| return 1`: o estado nao e criado) |
| I-29 | `lib/state.sh:158-160,539-540` | `find d -maxdepth 1 -type f \( -name .. \) -mtime +N -exec rm -f -- {} +` | IGUAL | manter | n/a |
| I-30 | `lib/state.sh:250,728,2016` | `[[ -f /dev/fd/$fd && -O /dev/fd/$fd ]]` | DIFERE (`fdescfs`) | `DIV-352` | **nao** (recusa o registro como nao regular) |
| I-31 | `lib/state.sh:658-659` | leitura de `/proc/sys/kernel/hostname` | IGUAL (guardado por `-r`; `$HOSTNAME` do shell cobre) | manter | sim |
| I-32 | `lib/state.sh:664-667` | leitura de `/proc/sys/kernel/random/boot_id` | DIFERE (inexistente; `boot` vira `x`) | `DIV-353` | sim (degrada para `x`) |
| I-33 | `lib/state.sh:668` | `stat -L -c %i -- /proc/self/ns/pid` | IGUAL na pratica (guardado por `-e`; `ns` vira `x`) | manter | sim |
| I-34 | `lib/state.sh:773` | `kill -0 pid \|\| [[ -e /proc/$pid ]]` | DIFERE (sem `/proc`; `kill -0` de pid de outro usuario devolve EPERM, tratado como morto) | `DIV-353` | parcial |
| I-35 | `lib/state.sh:802` | `ln -- "$tmp" "$dest"` (elo duro como trava) | IGUAL | manter | n/a |
| I-36 | `lib/state.sh:1114` | `stat -L -c '%d:%i' -- "$1"` com `\|\| return 1` | **FALHA** (identidade da trava sempre falha) | auxiliar de 2.1 | **nao** |
| I-37 | `lib/state.sh:1611` | `stat -c '%d\|%i' -- "$caminho"` com `\|\| return 1` | **FALHA** | auxiliar de 2.1 | **nao** |
| I-38 | `lib/state.sh:1666,2267` | `find .. -maxdepth 1 -type f -name .. -mtime +N -print0` | IGUAL | manter | n/a |
| I-39 | `lib/state.sh:1687,2288` | `find .. -printf '%T@ %p\0'` (poda pelo teto) | **FALHA** (sem `-printf`; o erro e descartado e a poda por teto nunca remove nada) | escolher o mais antigo com o teste `-ot` do bash sobre o glob `"$diretorio"/retomada-*`, sem utilitario | **nao** |
| I-40 | `lib/state.sh:1795` | `stat -c %Y -- "$arquivo"` com `\|\| mtime=$agora` | FALHA (idade passa a 0: nada e podado por idade) | auxiliar de 2.1 | **nao** |
| I-41 | `lib/state.sh:1812` | `stat -c %s -- "$part"` com `\|\| bytes=0` | FALHA (resultado errado) | auxiliar de 2.1 | **nao** |
| I-42 | `lib/state.sh:2052` | `head -c N -- /dev/fd/$fd` | DIFERE (`head` aceita; o caminho depende de `fdescfs`) | `DIV-352` | **nao** |
| I-43 | `lib/state.sh:2089` | `stat -L -c %s -- /dev/fd/$fd` com `\|\| tamanho=-1` | FALHA | auxiliar de 2.1; `DIV-352` | **nao** |
| I-44 | `lib/state.sh:2204` | `stat -c %s -- "$temporario"` com `\|\| return 1` | **FALHA** (gravacao de estado falha) | auxiliar de 2.1 | **nao** |
| I-45 | `lib/state.sh:188,950-2290` | `mv -f --`, `rm -f --`, `rmdir --` | IGUAL | manter | n/a |

### 1.6 `lib/config.sh`, `lib/transfer.sh`, `lib/preflight.sh`, demais

| ID | Arquivo:linha | Construcao | FreeBSD | Alternativa portavel proposta | Fallback |
|---|---|---|---|---|---|
| I-46 | `lib/config.sh:131,134,136,723,728` | `kill -0`, `find "$f" -mmin +N`, `rm -f --`, `rmdir --` | IGUAL (`find -mmin` existe) | manter | n/a |
| I-47 | `lib/config.sh:265-266,608,623,628` | `stat -c '%a'/'%u' -- x \|\| stat -f '%Lp'/'%u' x` | IGUAL | manter; migrar ao auxiliar de 2.1 | sim |
| I-48 | `lib/config.sh:480,485,488,526` | `mkdir -p --`, `chmod 700 "$d"`, `mv -f --` | IGUAL (um operando; sem `--` depois do modo) | manter | n/a |
| I-49 | `lib/config.sh:525` | `chmod 600 -- "$temporario"` | **FALHA** (a causa do relato do solicitante: `dbx config`) | `chmod -- 600 "$temporario"` | **nao** |
| I-50 | `lib/transfer.sh:188,679` | `wc -c <arq` + `${v//[^0-9]/}` | IGUAL (sanitizado) | manter | sim |
| I-51 | `lib/transfer.sh:445,674,1031` | `head -c N <&fd >bloco` | **DIFERE** (mesmo motivo de `I-08`; partes perdidas entre leituras) | `dbx_ler_exato` (`RF-173`) | **sim** |
| I-52 | `lib/transfer.sh:1149` | `stat -c %Y -- "$origem"` (carimbo `client_modified`) | FALHA (silencioso: o envio segue sem a data de modificacao) | auxiliar de 2.1 (`stat -f %m`) | **nao** |
| I-53 | `lib/transfer.sh:655,1152`; `lib/compartilhamento.sh:64,70`; `lib/state.sh` (`%(%s)T`); `commands/reter.sh:176`; `lib/cmd.sh` (`%(%s)T`) | `printf '%(%s)T'` | IGUAL (builtin do bash 4.2+) | manter | n/a |
| I-54 | `lib/preflight.sh:77` | lista `curl mktemp mv rm chmod mkdir stat head dd wc readlink dirname find cat sleep tail df ln rmdir` | IGUAL (todos na base) | manter | n/a |
| I-55 | `lib/preflight.sh:126,135,138` | `stat -c .. \|\| stat -f ..` | IGUAL | manter | sim |
| I-56 | `lib/preflight.sh:175,222-223` | `command -v sha256sum \|\| command -v shasum` (so a linha 223 tem `openssl`) | FALHA/DIFERE (sem coreutils, a linha 175 recusa mesmo havendo `openssl`/`sha256`) | usar a mesma lista de I-03 nos dois pontos | parcial |
| I-57 | `lib/disponibilidade.sh:109-110`; `lib/debug.sh:153,190` | `EPOCHREALTIME` (bash 5.0) | IGUAL (guardado por `-n`; o `bash` do `pkg` e 5.x) | manter | sim |
| I-58 | `lib/http.sh:747,758` | `curl -o /dev/fd/$saida` | DIFERE (`fdescfs`) | `DIV-352` | **nao** |
| I-59 | `lib/disponibilidade.sh:147,181`; `lib/debug.sh:143` | `kill -0`, `mv -f --`, `rm -f --` | IGUAL | manter | n/a |

### 1.7 `commands/*.sh`

| ID | Arquivo:linha | Construcao | FreeBSD | Alternativa portavel proposta | Fallback |
|---|---|---|---|---|---|
| I-60 | `commands/config.sh:94-95,108-109` | `stat -c '%a (%A)'/'%u:%g' \|\| stat -f '%Lp (%Sp)'/'%u:%g'` | IGUAL | manter | sim |
| I-61 | `commands/config.sh:120,122` | `df -h d \| tail -n 1`, `df -i d \| tail -n 1` | DIFERE (colunas diferentes; so texto de `--debug`) | manter; teste nao deve casar colunas | n/a |
| I-62 | `commands/config.sh:126-128` | `mount \| grep -E " on (/ \|..)" \| head -n 3` | IGUAL (`dev on / (ufs, ...)` casa) | manter | n/a |
| I-63 | `commands/config.sh:132-133,136-138` | `getenforce`, `lsattr -d` sob `command -v` | IGUAL (ausentes: o bloco e pulado) | manter | sim |
| I-64 | `commands/diagnostico.sh:155` | `stat -f -c %T -- "$estado"` (tipo de sistema de arquivos) | FALHA silenciosa (`\|\| return 0`: o aviso de FS de rede nunca sai) | sem forma portavel unica; registrar como nao verificado | sim (pula) |
| I-65 | `commands/diagnostico.sh:385-386` | `stat -c '%a'/'%u' -- "$estado"` com `\|\| modo=''` | FALHA (sem recuo BSD, ao contrario de `lib/config.sh`; o diagnostico reporta permissao incorreta) | auxiliar de 2.1 | **nao** |
| I-66 | `commands/diagnostico.sh:195-207` | verifica `readlink`/`find` por `command -v` | IGUAL | manter | n/a |
| I-67 | `commands/testar.sh:93-94`; `commands/diagnostico.sh:254,259,391`; `lib/config.sh:201` | texto de remedio `chmod 600 $arquivo` | IGUAL (so mensagem) | manter | n/a |
| I-68 | `commands/sync.sh:283,294,299,306,321,335,383,424,482,492,501` | `mv -f --`, `kill -TERM -- -pid`, `kill -0`, `mkdir -m 0700 --`, `rm -f --` | IGUAL (`kill` e builtin) | manter | n/a |
| I-69 | `commands/sync.sh:432,514` | `wait -n` | IGUAL (bash 4.3+) | manter | n/a |
| I-70 | `commands/upload.sh:156`; `commands/download.sh:32,216,266,271,279` | `basename -- x`, `mkdir -p -- x` | IGUAL | manter | n/a |
| I-71 | `commands/unlink.sh:104,111,249,258,273` | `rm -rf --`, `rmdir --`, `rm -f --` | IGUAL | manter | n/a |

### 1.8 `install.sh` e `uninstall.sh`

| ID | Arquivo:linha | Construcao | FreeBSD | Alternativa portavel proposta | Fallback |
|---|---|---|---|---|---|
| I-72 | `install.sh:68-69` | piso do bash 4.4 | IGUAL (o `bash` do `pkg` e 5.x, em `/usr/local/bin`) | manter | n/a |
| I-73 | `install.sh:79` | `for cmd in mkdir rm cp chmod mktemp stat` | IGUAL | manter | n/a |
| I-74 | `install.sh:85-88` | `sha256sum` ou `shasum`, senao erro | **FALHA** (base sem os dois: o instalador recusa) | aceitar tambem `sha256` e `openssl`, pela mesma lista de I-03 | **nao** |
| I-75 | `install.sh:96` | `cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")"` | IGUAL | manter | n/a |
| I-76 | `install.sh:106` | `mktemp -d "${TMPDIR:-/tmp}/dbx-install.XXXXXXXX"` | IGUAL | manter | n/a |
| I-77 | `install.sh:123` | `tar -xzf f -C d` (bsdtar) | IGUAL | manter | n/a |
| I-78 | `install.sh:125` | `find d -maxdepth 1 -type d -name "dropbox_sync*" \| head -n 1` | IGUAL | manter | n/a |
| I-79 | `install.sh:186-212` | `mkdir -p --`, `cp -p a b`, `cp -p lib/*.sh d/` | IGUAL | manter | n/a |
| I-80 | `install.sh:197-222` | `chmod 644/755 "$arq"` (um modo, sem `--`) | IGUAL | manter; ao tocar, usar `chmod -- 644 ...` por uniformidade | n/a |
| I-81 | `install.sh:221` | `ln -sf alvo vinculo` | IGUAL | manter | n/a |
| I-82 | `install.sh:149-162`; `uninstall.sh:82-104` | `rm -f --`, `rm -rf --` | IGUAL | manter | n/a |
| I-83 | `install.sh:297`; `uninstall.sh:70` | `id -u` | IGUAL | manter | n/a |
| I-84 | `install.sh:74,2,42,63` | texto "sudo apt install", "para Linux" | IGUAL (so mensagem; FreeBSD nao tem `sudo`/`apt`) | texto neutro de pacote (`pkg install curl bash`) | n/a |

## 2. Propostas transversais

### 2.1 Auxiliar unico de `stat` (cobre I-09, I-13, I-19, I-23 a I-25, I-36, I-37, I-40, I-41, I-43, I-44, I-47, I-52, I-55, I-60, I-65)

Uma funcao em `lib/` (ex.: `dbx_stat_campo <campo> <arquivo>`, campo em `modo|dono|grupo|tamanho|mtime|dev_ino`) que **tenta primeiro a forma GNU (`stat -c`) e, se o utilitario a recusar, a forma BSD (`stat -f`)**, e memoriza qual formato o utilitario aceitou. E deteccao **por capacidade do utilitario**, nunca por `uname`. A ordem importa: no GNU, `stat -f` significa "estado do sistema de arquivos" e **sucede** com saida errada; por isso a forma GNU vem sempre antes.

| Campo | GNU | BSD |
|---|---|---|
| modo octal | `%a` | `%Lp` |
| modo simbolico | `%A` | `%Sp` |
| dono / grupo | `%u` / `%g` | `%u` / `%g` |
| tamanho | `%s` | `%z` |
| mtime em segundos | `%Y` | `%m` |
| dispositivo e inode | `%d` / `%i` | `%d` / `%i` |
| segue ligacao | `-L` | `-L` |

### 2.2 `chmod` (I-20, I-28, I-49)

`chmod -- "$modo" "$arquivo"`. Funciona com o `getopt` de ambos, nao detecta plataforma e nao depende de o caminho comecar por `-`.

### 2.3 Poda por teto sem `find -printf` (I-39)

Percorrer o glob `"$diretorio"/retomada-*` (ou `cursor-*`) com `nullglob` e escolher o mais antigo com `[[ a -ot b ]]`, teste do proprio bash. Zero utilitario.

### 2.4 Hash (I-03 a I-06, I-56, I-74)

Uma lista unica, compartilhada por `lib/hash.sh`, `lib/preflight.sh` e `install.sh`: `sha256sum`, `shasum`, `sha256`, `openssl`.

## 3. Contagem

Linhas de runtime relevantes por arquivo (itens do inventario que citam o arquivo; uma linha de codigo conta uma vez, mesmo agrupada). **Falha** = linhas em que a forma usada e recusada pelo utilitario BSD ou produz resultado errado em silencio.

| Arquivo | Linhas inventariadas | Falham no FreeBSD | Das quais sem recuo |
|---|---|---|---|
| `lib/state.sh` | 40 | 12 (153, 1114, 1611, 1687, 1795, 1812, 2089, 2204, 2288 e as de `/dev/fd`: 250, 728, 2016 em `DIFERE`) | 9 |
| `lib/cmd.sh` | 15 | 9 (660, 663, 766, 834, 942, 1046, 1049, e `/dev/fd`: 765, 773) | 9 |
| `lib/hash.sh` | 11 | 3 (134, 138, 396) | 1 |
| `lib/config.sh` | 17 | 1 (525) | 1 |
| `lib/transfer.sh` | 8 | 1 (1149) | 1 |
| `lib/walk.sh` | 2 | 1 (159, parcial) | 0 |
| `lib/preflight.sh` | 8 | 1 (175) | 0 |
| `lib/http.sh` | 2 | 2 (747, 758: `fdescfs`) | 2 |
| `commands/diagnostico.sh` | 8 | 2 (155, 385-386) | 1 |
| `bin/dbx` | 3 | 1 (35, irrelevante no FreeBSD) | 0 |
| `install.sh` | 22 | 1 (86) | 1 |
| demais (`tmp`, `progress`, `path`, `disponibilidade`, `debug`, `compartilhamento`, `sync`, `upload`, `download`, `unlink`, `uninstall`) | 41 | 0 | 0 |

Totais: **84 itens** de inventario; **24 itens FALHAM** (ou produzem resultado errado em silencio) no FreeBSD; **15 deles sem nenhum recuo**. Os 4 pontos que impedem o uso hoje, em ordem de gravidade: `chmod` (I-20, I-28, I-49), identidade/tamanho por `stat` no estado (I-36, I-37, I-44), `install.sh` sem `sha256sum` (I-74) e `/dev/fd` (`DIV-352`).

> Contagem por leitura de grep e de contexto, nao por execucao. Os numeros de linha refletem `6df321e` e mudam quando o codigo e alterado.

## 4. O que nao foi coberto

- `commands/completar.sh` e `completions/dbx.bash`: nao varridos (usam builtins `compgen`/`complete`; nao ha utilitario externo esperado).
- `scripts/` e `tests/`: fora do escopo pedido. Os testes existentes usam `stat -c`, `sha256sum` e `/proc` do Linux e rodam em Linux; nao foram auditados.
- Comportamento real do FreeBSD 13/14 (opcoes, mensagens, `fdescfs`, `readlink -f`, `mktemp` com `X` curto, formato do `openssl dgst`): descrito pelo manual, **nao observado**.
