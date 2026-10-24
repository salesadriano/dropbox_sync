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
