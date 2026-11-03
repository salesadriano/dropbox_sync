# Defeito em producao: subdiretorio chamado `-` corrompe a enumeracao do sync

**Branch:** `feature/diretorio-chamado-hifen` (de `origin/develop` @ `4f5be61`)
**Porte:** M. `sh scripts/porte.sh` (sem diff na abertura): `porte: P`; classificado M pelos gatilhos nao mensuraveis: defeito critico em producao e guarda destrutiva (`--espelhar` sobre a arvore errada), mesmo criterio da demanda `ignorar-cdpath`.
**Issues:** nenhuma.

## Prompt 1 — 2026-11-02 20:59

> check error ───────────────────────────────────────────────────────────────────────────────────── ❯ Try "how does dbx.bash work?"

Sem conteudo util (linha do terminal colada por engano); a demanda real veio no prompt 2.

## Prompt 2 — 2026-11-02 21:02

> check error
>
> ```
> # dbx --debug sync --enviar -p --origem /mnt/e/. --destino /Amac --espelhar --confirmar
> debug: http POST api.dropbox.com tentativa=1 status=200 duracao_ms=793 enviados=159 recebidos=1524
> debug: http POST api.dropboxapi.com/2/users/get_current_account tentativa=1 status=200 duracao_ms=1402 enviados=4 recebidos=1468
> [sync] enumerando diretorios locais em: /mnt/e/.
> /usr/local/share/dropbox_sync/commands/sync.sh: line 2192: /mnt/e/arquivos2/<pastas do operador>/sl2801/SL2801
> 0: arithmetic syntax error: operand expected (error token is "/mnt/e/arquivos2/<pastas do operador>/sl2801/SL2801
> 0")
> debug: resumo comando=sync chamadas=2 tentativas_extras=0 limites_429=0 enviados=163 recebidos=2992 duracao_ms=268785 saida=1
> ```

Sanitizado: os nomes intermediarios das pastas do operador foram substituidos por `<pastas do operador>` (dado do cliente, nao necessario a analise).

**Intencao principal:** corrigir o erro do `sync` em producao (2.3.1, ja com a correcao de `CDPATH`).

**Causa (Tech Lead, reproduzida em bash 5.3):** `cd -- -` NAO trata `-` como nome: mesmo apos `--`, o bash o le como `OLDPWD`, vai ao diretorio anterior e imprime o destino no stdout. Na travessia (`lib/walk.sh`), um subdiretorio chamado `-` visitado logo depois do irmao `SL2801` leva o `cd` de volta a `.../sl2801/SL2801` e a linha impressa entra na lista `n<TAB>caminho\0`; o registro corrompido vira o operando do erro aritmetico em `commands/sync.sh`. Sem o erro, a travessia seguiria na pasta errada (enumeracao incorreta sob `--espelhar`).

**Contorno:** renomear a pasta `-` na origem ou exclui-la com `--excluir`.

**Inferencias adotadas:** correcao em `lib/walk.sh`, todo `cd` de nome relativo passa a `cd -- "./$nome"` (unico nome que o bash nunca reinterpreta); linha legada `support/bash-4.2` registrada como pendencia para o solicitante.
