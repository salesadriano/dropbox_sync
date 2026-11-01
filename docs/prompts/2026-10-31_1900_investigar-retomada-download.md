# Investigar a falha do retomada_download na suite completa

**Branch:** `chore/investigar-retomada-download` (de `origin/develop` @ `bbc8504`)
**Porte:** a definir pela causa. `sh scripts/porte.sh` na abertura (sem diff): `porte: P`. Investigacao primeiro; se a causa for defeito de producao no recebimento retomado (integridade, `content_hash`), o porte sobe para no minimo M (defeito de alta criticidade).
**Issues:** nenhuma citada pelo solicitante.

## Prompt 1 — 2026-10-31

> investigue a falha do retomada_download na suite completa

**Intencao principal:** achar a causa de `tests/integracao/retomada_download_test.sh` reprovar sempre dentro da suite completa (3 de 3 na demanda `sync-em-blocos`, commit `195af1e`) e nunca isolado (6 de 6, ramo e base), e propor a correcao.

**Fatos de partida (logs da suite completa guardados pelo Tech Lead):** as tres execucoes sairam com codigo `11` (integridade) onde o caso espera `0`: `rmd07_200_a_um_pedido_de_faixa_nunca_e_anexado` e `rmd08_206_de_outro_inicio_outro_total_ou_outra_rev_recomeca`, ambos no caminho "recomeca do zero" (servico responde `200` sem a faixa, ou `206` de outro inicio/total/rev); mensagem: "o conteudo recebido nao confere com o resumo publicado pelo servico; o destino foi preservado". Mesmo sintoma do problema conhecido das notas da v2.1.0 (`qa_retomada_b7a`, `content_hash` divergente sob carga).

**Investigacao (Tech Lead):** suite inteira monitorada (`df /tmp` a cada 10 s): a area temporaria unica do executor (`DBX_TESTES_TMP`, removida so no fim) chegou a 9,4 GB num `/tmp` `tmpfs` de 9,8 GB, com 523 MB livres no inicio de `retomada_download_test.sh`; maiores acumuladores `paralelo_upload_test.sh` (~4,2 GB) e `paralelo_download_test.sh` (~1,4 GB). Escrita truncada -> `content_hash` divergente -> saida `11` (comportamento correto do produto). Causa: espaco, nao carga.

**Porte:** P, medido depois do diff (`sh scripts/porte.sh`: 46 linhas de codigo, nenhum gatilho de M ou G); criterios nao mensuraveis conferidos (sem contrato, fronteira, dado sensivel; defeito de infraestrutura de teste). Correcao: area temporaria por arquivo de teste em `tests/run.sh` (abordagem A de tres, registro de entrega). Suite inteira depois da correcao: 111 arquivos, 2817 aprovados, 0 reprovados, 4 pulados, pico de `/tmp` 4,6 GB. Junto, residuo do PR #70: `lib/walk.sh:51` sem `|| return` (SC2164).
