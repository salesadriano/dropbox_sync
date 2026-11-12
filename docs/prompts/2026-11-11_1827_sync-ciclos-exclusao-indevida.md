# Sync em ciclos: exclusao indevida a partir do segundo ciclo e memoria gravada por ciclo

**Branch:** `feature/sync-ciclos-exclusao-indevida` (de `origin/develop` @ `bae275f`), worktree `../dropbox_api.worktrees/feature-sync-ciclos-exclusao-indevida`
**Porte:** M. `sh scripts/porte.sh` na entrada (arvore sem diff): `porte: P` (0 arquivos, 0 linhas). Reclassificado para M pelo Tech Lead: toca persistencia (`lib/state.sh`, memoria do sync) e o relato e de defeito de alta criticidade (exclusao no destino com `--espelhar`).
**Instancia:** myPCWin/Adriano Sales Santos
**issues:** nenhuma
**PRs abertas na entrada:** nenhuma. Reservas ativas: nenhuma. `alteracoes-externas.sh --detectar` (checkout principal): sem divergencia; `--inicial` no worktree.

## Prompt 1 — 2026-11-11 18:00

> no processamento de arquivos em multiplos ciclos, a partir do segundo ciclo, aparentemente a aplicação está considerando os arquivos processados no ciclo anterior como ausentes na origem e marcando para exclusão no destino, verifique e corrija, altere a persistencia dos dados de processamento no banco local para ocorrer a cada fim de ciclo e não no fim do processo completo

**Intencao:** (1) investigar e corrigir a marcacao de arquivos de ciclos anteriores como `ausente na origem (a apagar)` no `sync` em ciclos (F-101); (2) gravar a memoria local do sync (`lib/state`, `memoria-*`) ao fim de cada ciclo, e nao so ao fim da execucao.

**Inferencias do Tech Lead:**
- "Banco local" e a memoria do sync em `lib/state.sh` (cache unico de `content_hash`, entrada `2026-10-18-2243-cache-unico-e-segredo`); o cursor/retrato do `--receber` nao entra (decisao abaixo).
- "Ciclo" e o ciclo da varredura em blocos (`--bloco N`, entrada `2026-10-31-1200-sync-em-blocos`).

**Investigacao (Tech Lead, antes da delegacao):** codigo da `develop` identico ao instalado (`dbx 2.4.0`). Reproducao tentada com o duble de `sync_blocos_test.sh` (remoto estatico) e com um duble com estado (remoto em disco, `list_folder` nao recursivo, `upload`, `finish_batch_v2`, `create_folder_batch`, `download`), `--enviar` e `--receber` com `--espelhar`, de 4 a 7 ciclos, nomes com caixa, espaco, hifen, ponto e acento, duas execucoes seguidas: nenhum arquivo de ciclo anterior marcado para exclusao. O plano de cada ciclo compara so a origem e o destino dos diretorios do ciclo (`dbx_sync_planejar`); a memoria nao entra na decisao de apagar. Defeito cosmetico encontrado: a linha de progresso `[sync] ciclo N: diretorios X a Y` termina com `nao` (`${so_destino/sim/...}` com `so_destino=nao`).

**Decisoes do solicitante (AskUserQuestion, 2026-11-11):**
- Comando: `sync --enviar --espelhar`; versao `v2.4.0` (bash 4.4+); evidencia: "Progresso (-p) mostrou 'a apagar'" (linhas da saida nao fornecidas).
- Persistencia: "Sim, assim (Recomendado)" — a cada fim de ciclo grava o que foi visto ate ali e mantem as entradas dos diretorios ainda nao processados; so a gravacao final remove o que sumiu da origem; com travessia parcial nada e gravado; o cursor do `--receber` continua gravado so no fim.

**Aceite dos testes do QA (AskUserQuestion, 2026-11-11):** "Aceito a suite" — `tests/integracao/qa_sync_ciclos_memoria_f101_test.sh`, sha256 `cea807f4a2d606cc654a168bca2d9a252af192c725f56ef73808694a14a186c1`; entrada `2026-11-11-1827-aceite-testes-qa-sync-ciclos-memoria`.

## Prompt 2 — 2026-11-11 (pergunta na mesma demanda)

> como defino o número de arquivos em cada ciclo ?

**Resposta:** `--bloco N` (alias `--batch`) ou `DBX_BLOCO=N`, de 1 a 1000000, padrao 50000, a opcao vence a variavel; corte por diretorio.

**Reaceite dos testes do QA (AskUserQuestion, 2026-11-12):** "Reaceito" — sha256 `cb8665e0e98b858a60cc108517d0462936eab5bb7d3e9cce36ec29a8c2eaa624` apos a troca de `$(printf` por literal (suite completa reprovada em `json_test.sh`, RSK-28); entrada `2026-11-12-0140-reaceite-testes-qa-sync-ciclos-memoria`.
