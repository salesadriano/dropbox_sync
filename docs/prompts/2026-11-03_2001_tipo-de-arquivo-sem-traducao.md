# Defeito em producao: toda trava existente sai como ilegivel em pt_BR (Oracle Linux 7)

**Branch:** `feature/tipo-de-arquivo-sem-traducao` (de `origin/develop` @ `fc3ba8f`) e `feature/tipo-de-arquivo-sem-traducao-bash42` (de `origin/support/bash-4.2` @ `ba0a110`)
**Porte:** M. `sh scripts/porte.sh`: 2 arquivos, 112 linhas de codigo (limite de P 50), `porte: M`; defeito critico em producao (nenhum `sync` ou `verificar` do par roda enquanto houver trava).
**Issues:** nenhuma.
**PRs abertas no inicio:** nenhuma.

## Prompt 1 — 2026-11-03 20:01

> in oracle linux after upload in new request i recive
>
> ```
> aviso: localidade C.UTF-8 ausente: a comparacao sem caixa de caminhos vale so no ASCII (nomes que so diferem na caixa de letras acentuadas contam como distintos)
> erro: trava ilegivel: /root/.local/state/dbx/trava-b5a4bca3fe7684596b6f9169187a37b0 nunca e retomada nem apagada automaticamente; confirme que nenhum sync ou verificar deste par esta em curso e remova-a com: rm /root/.local/state/dbx/trava-b5a4bca3fe7684596b6f9169187a37b0
> [root@srvOracle oracle]#
> ```

**Intencao principal:** a nova execucao no Oracle Linux nao pode ser barrada por uma trava valida dada como ilegivel.

**Inferencias adotadas:**
- "after upload" = depois de atualizar o `dbx` para a 2.3.3 (instalador rodado na mesma rodada); o aviso `C.UTF-8 ausente` indica Oracle Linux 7 (bash 4.2, linha legada `2.3.3-bash42`).
- Causa medida pelo Tech Lead num conteiner `oraclelinux:7` com as traducoes do coreutils: `LANG=pt_BR.UTF-8 stat -c %F` responde `arquivo comum`; `dbx_fd_regular_proprio` espera `regular*` e a leitura da trava (`_dbx_state_trava_ler`) devolve "ilegivel" para TODA trava existente, viva ou orfa. `local LC_ALL=C` da funcao nao chega ao `stat` porque nao e exportado. `LC_MESSAGES=C` no ambiente contorna.
- O aviso de localidade e informativo (`DIV-391`), fora do escopo.
- Correcao nas duas linhas, como nas demandas anteriores de producao.
