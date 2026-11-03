# Validacao QA - arquivo-remoto-no-lugar-da-pasta (DIV-394)

Demanda: `arquivo-remoto-no-lugar-da-pasta` | Porte: M | Log: `docs/prompts/2026-11-03_1017_arquivo-remoto-no-lugar-da-pasta.md` | Papel: QA Expert

## 1. Veredito

**Aprovado.** Sem achado bloqueante nem maior. Os 6 casos da suite independente passam com a correcao e os 6 reprovam sem ela. Falta apenas o aceite do solicitante sobre a suite.

## 2. Suite independente

`tests/integracao/qa_pasta_ocupada_test.sh`, 6 casos, duplo de `curl` proprio (nao reutiliza o do `sync_test.sh`), HTTP 409 `path/not_folder` reproduzido. sha256 `d7cd09d4127d25750aa9b10acda60bbc465846a079599688e34babd368d754eb` (atualizar se o arquivo mudar antes do aceite).

| Criterio | Caso |
|---|---|
| (1) espelhar: sync segue, `transferir=sub/b.txt`, `apagar=sub`, exclusao executada | `espelhar_nao_encerra_planeja_o_conteudo_e_apaga_o_arquivo_homonimo` |
| (2) aviso em stderr nomeia `/r/sub`, sem `-p` | `aviso_sai_em_stderr_sem_progresso_e_nomeia_o_caminho` |
| (3) sem `--espelhar`: `apenas_no_destino`, nada apagado | `sem_espelhar_o_arquivo_homonimo_fica_e_nada_e_apagado` |
| (4) raiz do destino que e arquivo: codigo 2, `recusada em /r:`, sem escrita | `raiz_do_destino_que_e_arquivo_continua_falha_nomeando_o_caminho` |
| (5) `--dry-run`: plano mostra a exclusao, zero escrita | `dry_run_nao_escreve_nada` |
| (6) `--bloco 1`: orfao apagado no ciclo do pai, conteudo enviado, ciclo seguinte segue | `em_ciclo_posterior_o_orfao_sai_no_ciclo_do_pai_e_o_conteudo_e_enviado` |

Mapa de contencao: nenhum. Os casos do Tech Lead no `sync_test.sh` cobrem espelhar e raiz com um cenario cada; os do QA repetem com duplo e valores proprios e acrescentam (2) sem `-p`, (3), (5) e (6), que o Tech Lead nao cobre; a contencao nao e total, nada sai.

## 3. Vermelho contra a base

`git archive origin/develop bin lib commands` em pasta temporaria, executavel apontado por `DBX_QA_EXEC`, cada caso isolado (o runner para no primeiro erro): **6 de 6 reprovam** (5 por `erro=enumeracao remota recusada: path/not_folder/..` com codigo 2; o da raiz pelo motivo sem o caminho).

## 4. Achados

- Maior: nenhum. Bloqueante: nenhum.
- Menor (efeito residual, ja admitido no registro do Tech Lead, secoes 2 e 7): o duplo nao simula `path/conflict/file` do envio para dentro da pasta ocupada no mesmo ciclo; o caso (1) prova que o envio e tentado, nao que ele conclui. Sem `--espelhar` o arquivo fica e o envio para dentro falha por item a cada execucao: comportamento documentado, nao testavel sem a Dropbox real.
- Menor: aviso e pasta ocupada so existem no sentido `--enviar` (o canal e zerado e lido apenas nele); `--receber` nao lista subpastas remotas ocupadas por esse caminho. Fora do escopo da demanda.
- Governanca: `inventario-de-testes.sh` so enxerga arquivo versionado; usei `git add -N` na suite (so indice, sem commit) para o `--check` passar. O Tech Lead faz o `git add` real.

## 5. Execucao seletiva (contagens literais)

- `bash tests/run.sh qa_pasta_ocupada_test.sh`: 1 arquivo, 6 aprovados, 0 reprovados.
- `bash tests/run.sh sync_test.sh`: 2 arquivos, 102 aprovados, 0 reprovados.
- `bash tests/run.sh qa_sync_blocos`: 1 arquivo, 25 aprovados, 0 reprovados.
- `bash tests/run.sh harness_test.sh`: 23 aprovados. `bash tests/run.sh json_test.sh`: 66 aprovados (a primeira execucao reprovou 1 caso por `$(printf ...)` na massa da suite; corrigido para `printf -v`).
- `shellcheck -x -s bash tests/integracao/qa_pasta_ocupada_test.sh`: sem aviso.

## 6. Inventario

`docs/testes/inventario-de-testes.md`: linha nova no Resumo e secao para a suite (aceite pendente, sha256 acima); `sync_test.sh` 90 -> 92 com os dois casos DIV-394. `sh scripts/inventario-de-testes.sh --check` -> `arquivos: 117 | casos: 2916 | divergencias: 0`.

## 7. Recomendacao

Aprovar o merge; o solicitante aceita a suite pelo sha256 acima. Registrar o efeito residual (envio para dentro da pasta ocupada) como conhecido, a validar na Dropbox real se ocorrer de novo.
