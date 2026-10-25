---
date: 2026-10-24
hora: "1153"
domain: suporte a FreeBSD (reabre DP-07), a partir da falha do chmod na gravacao da credencial
porte: G
status: aberto
instancia: myPCWin/Desenvolvedor Hydros
registro_de_entrega: "docs/reviews/2026-10-24-1153-registro-suporte-freebsd.md"
---

# suporte-freebsd

## Prompt 1 — 2026-10-24

> how fix
>
> (colagem da saida de `dbx --debug config`, sanitizada; client_id, URL de autorizacao e codigo de autorizacao removidos)
>
> ```
> chmod: --: No such file or directory
> [debug] === DIAGNOSTICO OPERACIONAL DE CONFIGURACAO ===
> [debug] Processo: PID=<pid> EUID=0 UID=0 USER=root
> [debug] Alvo da credencial: /root/.config/dbx/credencial.json
> [debug] Diretorio existe: sim (tipo: dir, perm: 700 (drwx------), dono: 0:0, gravavel: sim)
> [debug] Arquivo existe: sim (perm: 644 (-rw-r--r--), dono: 0:0)
> [debug] Montagens relevantes:
> /dev/da0p2 on / (ufs, local, soft-updates, journaled soft-updates)
> erro: gravacao da credencial falhou: gravacao (falha ao gravar ou mover credencial)
> ```

**Intencao:** fazer o `dbx config` (e o resto da CLI) funcionar no FreeBSD do solicitante (UFS, root).

**Causa levantada pelo Tech Lead:** o `chmod` do FreeBSD usa `getopt` sem permutacao: em `chmod 600 -- arq` o `--` vem depois do primeiro operando e vira nome de arquivo. Mesmo padrao em `lib/config.sh:525` (credencial), `lib/state.sh:153` (memoria do sync), `lib/cmd.sh:663` e `:1049` (modo do arquivo baixado, falha engolida). Alem disso ha ~40 usos de construcoes GNU em `lib/`, `commands/` e `bin/` (`stat -c`, `sed -i`, entre outras). `DP-07` fixou "So cURL, bash 4+, Linux" e `tests/unit/preflight_test.sh` impede reintroduzir camada BSD.

**Decisao do solicitante (AskUserQuestion, 2026-10-24):** "Suportar FreeBSD": reabre a `DP-07`; auditoria de todos os usos GNU, alternativa portavel e testes.

**Porte:** G. `scripts/porte.sh` nao existe no projeto. Altera regra de plataforma (decisao de arquitetura `DP-07`), toca credencial, estado e transferencias em todo o runtime.

**Seguranca:** a colagem trazia o `client_id` do app e um codigo de autorizacao de uso unico; nenhum dos dois foi persistido.

**Decisoes do solicitante sobre as DIV da secao 5.22 (AskUserQuestion, 2026-10-24):**
- DIV-352 "Preflight recusa (Recomendado)"; DIV-353 "Degradar e documentar (Recomendado)"; DIV-354 "Aceitar sha256 e openssl (Recomendado)"; DIV-355 "Duble + voce no FreeBSD (Recomendado)"; DIV-357 "Mensagens neutras + pkg (Recomendado)".
- DIV-356 "Liberar deteccao" (contra a recomendacao): o Tech Lead complementa com ponto unico de deteccao, `dbx_preflight_plataforma`.

## Prompt 2 — 2026-10-24

> (colagem da saida de `bash bin/dbx diagnostico` no FreeBSD do solicitante, passo 2 do roteiro; sanitizada, sem segredo)
> `dependencias: ok ... resumo SHA-256 via sha256sum`; `credencial: falha: a credencial tem permissao para grupo ou outros: /root/.config/dbx/credencial.json; remedio: chmod 600 ...`; `estado: ok: ainda nao criado`; `trava: ok: sem travas`; `saida=3`.

**Leitura do Tech Lead:** o modo `644` da credencial e o arquivo gravado pela tentativa de `dbx config` anterior a correcao (`chmod` falhou depois da escrita); o diagnostico o leu corretamente pelo `stat` do FreeBSD (`dbx_atributo`), o que ja confirma parte do RF-167 no sistema real. O FreeBSD do solicitante tem `sha256sum`. A linha "tipo do sistema de arquivos nao verificado" nao aparece porque o diretorio de estado ainda nao existe. Proximo passo: `chmod 600` (ou refazer o `dbx config`) e seguir o roteiro.

## Prompt 3 — 2026-10-24

> (colagem: passo 2 do roteiro e o teste de /dev/fd no FreeBSD 15.1-RELEASE-p3 do solicitante; sem segredo)
> Com `fdescfs` montado, `dbx space` ainda recusa com a instrucao do fdescfs. Sem opcao: `/dev/fd/3` e `Character Device`, `stat -L` da `1493237509|6`, `/etc/passwd` da `95|6572838`. Com `-o linrdlnk`: `/dev/fd/3 -> /etc/passwd`, mas `stat -L` da `1493237510|6|Symbolic Link` (o no do fdescfs, nao o arquivo).

**Leitura do Tech Lead:** no FreeBSD, nenhuma forma do `fdescfs` faz o `stat -L /dev/fd/<n>` externo devolver o `dev:ino` do arquivo, que e o que o produto usa (barreira do `.part`, cursor, preflight). A premissa da `DIV-352` (montar o fdescfs resolve) nao vale. Alternativa verificada no Linux: ler os atributos pelo proprio descritor (`stat -L -c <fmt> - <&N` no GNU; `stat -f <fmt>` sem operando no BSD) e, onde o produto reabre o arquivo por `/dev/fd/<n>` para escrita, abrir pelo caminho e conferir o `dev:ino` do novo descritor. Decisao levada ao solicitante.

**Decisao do solicitante (AskUserQuestion, 2026-10-24):** "Conferir pelo descritor (Recomendado)": substitui a DIV-352 C; atributos lidos do proprio descritor, reabertura por `/dev/fd` trocada por abertura pelo caminho com conferencia do `dev:ino`, sem exigir `fdescfs`.

**Decisao do solicitante (AskUserQuestion, 2026-10-25):** "Versionar o bloco (Recomendado)": o bloco `ai-team:roteamento` que o plugin escreve no `CLAUDE.md` e versionado nesta branch, para a suite oficial nao registrar a arvore como suja.
