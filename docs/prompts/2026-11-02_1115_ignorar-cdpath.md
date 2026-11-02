# Defeito em producao: CDPATH do ambiente quebra e desvia a enumeracao do sync

**Branch:** `feature/ignorar-cdpath` (de `origin/develop` @ `0c80a1e`)
**Porte:** M. `sh scripts/porte.sh` (sem diff na abertura): `porte: P`; classificado M pelos gatilhos nao mensuraveis: defeito critico em producao e guarda destrutiva (`--espelhar` sobre a arvore errada).
**Issues:** nenhuma.

## Prompt 1 — 2026-11-02

> in prod i recive the error below
>
> ```
> # nohup  dbx sync --enviar -p --origem /mnt/e/. --destino /Amac --espelhar --confirmar > ~/inventario.log
> # tail -f ~/inventario.log
> [sync] enumerando diretorios locais em: /mnt/e/.
> /usr/local/share/dropbox_sync/commands/sync.sh: line 2165: /mnt/e/arquivos2/<pastas do operador>/SL2801
> 0: arithmetic syntax error: operand expected (error token is "/mnt/e/arquivos2/<pastas do operador>/SL2801
> 0")
> ```

Sanitizado: os nomes intermediarios das pastas do operador foram substituidos por `<pastas do operador>` (dado do cliente, nao necessario a analise).

**Intencao principal:** corrigir o erro do `sync` em producao.

**Causa (Tech Lead, reproduzida):** `CDPATH` exportado no ambiente. `cd` de nome relativo em `lib/walk.sh` imprime o destino no stdout, que e a lista de diretorios `n<TAB>caminho\0`; e, com `CDPATH` apontando outra arvore, entra na pasta homonima de la.

**Contorno entregue:** `env -u CDPATH dbx sync ...`.

**Decisao do solicitante (AskUserQuestion, 2026-11-02):** "Include in 2.3.0 and 2.3.0-bash42 (Recommended)": as suites das releases em curso foram paradas e a correcao entra nas duas linhas.

**Decisoes do solicitante (AskUserQuestion, 2026-11-02, segundo lote):** suite do QA `qa_cdpath_test.sh` aceita (sha256 `57be5d41...326d`); `BASH_ENV`/`ENV`/`SHELLOPTS`/`BASHOPTS`: "Fix now in the release" (recomeco limpo do `dbx`, `DIV-392`).
