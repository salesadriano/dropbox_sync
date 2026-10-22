---
date: 2026-10-21
hora: "2300"
domain: desempenho (paralelismo controlado e operacoes em lote)
porte: G
status: aberto
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-21-2300-registro-desempenho-b9.md"
---

# backlog-fase-9-desempenho

## Prompt 1 — 2026-10-21 (depois do merge da PR #51)

> analise e implemente a fase 9 do backlog

**Intenção:** implementar a fase 9 do plano (`2026-10-19-1023-plano-do-backlog`): desempenho, com `F-34` (paralelismo limitado e APIs em lote, adiado com a exigência de medição prévia), `F-08` (operações em lote) e `F-09` (paralelismo controlado). Medição antes e depois.

**Restrições já registradas:**
- `RES-11` e `RNF-21`: nenhuma listagem simultânea para o mesmo usuário; o paralelismo é configurável, com padrão `1`.
- `F-34`: a medição prévia é o tempo de `sync`/`upload` sequencial em volume representativo (`DP-12`) e a taxa de `429` observada.
- Lição do projeto: guarda destrutiva nunca depende de estado; a exclusão em lote não pode afrouxar as guardas atuais do `sync --espelhar` nem do `reter`.

**Porte:** G. `scripts/porte.sh` não existe. A fase muda o modelo de execução (sequencial para concorrente), toca exclusão (destrutiva), integração externa (endpoints de lote e `check` assíncrono) e o System Design.

**Entrada:** branch principal `develop` @ `334394e`; nenhum PR aberto; worktree `feature/desempenho-b9` em `/home/sales/dropbox_api.worktrees/feature-desempenho-b9`; `alteracoes-externas.sh --inicial` feito no worktree, `--detectar` exit 0.

**Decisões do solicitante (AskUserQuestion, 2026-10-21):**
- **Medição:** "Conta real, pasta dedicada (Recomendado)".
- **Paralelismo:** "Transferências do sync (Recomendado)".
- **Lote:** "Exclusão em lote (Recomendado), Envio em lote de arquivos pequenos, Metadados em lote".
- **Volume:** "Misto padrão (Recomendado)".

Gravadas na memória `2026-10-21-2300-desempenho`, com os princípios do Tech Lead para a fase.

**Correção do Tech Lead:** a opção "Metadados em lote" não existe na API. O namespace `files` não tem `get_metadata` em lote, e `sharing/get_file_metadata/batch` só traz dados de compartilhamento. A opção foi oferecida sem conferência prévia.

**Decisão do solicitante (AskUserQuestion):** "Retirar da fase 9 (Recomendado)". A F-08 fica com exclusão em lote e envio em lote.

**Correção do Tech Lead (volume):** as quantidades escolhidas (1000 × 1–50 KB, 50 × 1–5 MB, 2 × 100 MB) somam cerca de 375 MB, não os "cerca de 500 MB" escritos na opção. O erro foi de soma na opção; valem as quantidades. A bancada (`scripts/bancada.sh`, bats 6/6) segue esse volume.

## Prompt 2 — 2026-10-21 21:44 (sessão nova, após interrupção)

> continue a sessão interrompida

**Intenção:** retomar a mesma demanda (fase 9) do ponto em que parou: requisitos formalizados pelo Business Analyst (RF-133 a RF-139, RNF-38, DIV-256 a DIV-265 pendentes), bancada `scripts/bancada.sh` criada (bats 6/6), nada commitado no worktree `feature/desempenho-b9`.

**Estado encontrado:** `alteracoes-externas.sh --detectar` exit 0 no worktree; `develop` segue em `334394e`; nenhum PR aberto.

**Próximos passos do Tech Lead:** decidir DIV-256 a DIV-265; pedir o ok do solicitante para a medição de base (`334394e`) na conta real; delegar a implementação de F-09 e F-08 ao Senior Developer em tarefas fechadas; QA independente; registro de entrega e PR.

**Decisão do solicitante (AskUserQuestion, 2026-10-21 21:50):** "Sim, rodar agora (Recomendado)" para a medição de base na conta real (`/dbx-bancada-base`, ~375 MB, sobre `334394e`). O Tech Lead passa `--confirmo-conta-real` com base nesse ok.

**F-09 entregue pelo Senior Developer (handback 2026-10-21):** `paralelo_test` 14/14 (reconferido pelo Tech Lead), sem commit. Divergências `DIV-SD-1..3` decididas pelo Tech Lead como `DIV-266` a `DIV-268`. Ressalvas: testes escritos depois do código (desvio do red-green, registrado no registro de entrega); a suíte inteira parou uma vez em `retomada_download` caso `rmo01`, que não reproduziu isolado (27/27) e coincidiu com a bancada consumindo memória em paralelo. A suíte completa será refeita pelo Tech Lead antes do push.

**Medição de base (2026-10-21, `bin/dbx` da `develop` @ `334394e`, N=1, semente 42, 1052 arquivos, 369 MB em disco, `/dbx-bancada-base`):**

| etapa | segundos | chamadas | 429 | status |
|---|---|---|---|---|
| envio | 1996.418 | 1056 | 0 | 0 |
| reenvio_sem_mudancas | 24.838 | 14 | 0 | 0 |
| recebimento | 1344.439 | 1066 | 0 | 14 |

O recebimento saiu `14` (`nao_concluida`: ao menos um item falhou). A saída da etapa ficou no temporário da bancada e foi apagada pelo `trap`, então a causa não é conhecida. A bancada também não apagou a pasta remota ao fim. As duas lacunas foram para a tarefa do Senior Developer (preservar a saída de cada etapa; limpeza garantida).

**Decisão do solicitante (AskUserQuestion):** "Repetir só o recebimento (Recomendado)". Só leitura na conta, saída guardada, depois apagar `/dbx-bancada-base`.

**Recebimento de diagnóstico (2026-10-22, develop @ `334394e`, N=1):** status 0, 1327.982 s, 1052 arquivos, 0 falhas, árvore idêntica ao volume (`diff -rq`). A falha `14` da primeira execução foi transitória, causa desconhecida. Base de recebimento adotada: **1327.982 s**. `/dbx-bancada-base` apagada e conferida ausente.

**Decisão do solicitante (AskUserQuestion, 2026-10-22):** "Reter item a item (Recomendado)" (`DIV-269`). O lote de exclusão fica só no `sync --espelhar`; `RF-97` e os testes do QA da fase 6 ficam intactos.

**Handback parcial do F-08:** RF-136 e bancada prontos; RF-137 incompleto. `DIV-SD-1..5` decididas como `DIV-270` a `DIV-274`.

**Estabilização do RF-136 (handback parcial, 2026-10-22):** reter fora do lote nos testes de lote; guarda `_dbx_cmd_sync_protegido` aplicada por item antes da fatia (mutação não detectada por caixa-preta: o plano já descarta o protegido; fica como defesa em profundidade); vazamento do corpo HTTP na linha `falha` corrigido (`_dbx_lote_resumo_http`, RF-59(c)). Verdes: `lote` 15/0 (8 `lou*` pulados), `sync_test` 85, `composicao` 28, `cursor` 110, `paralelo` 14, `comandos` 119, `confinamento_remoto` 25, `trava` 101, `perfis` 150. Pendentes: 6 `qa_*` por causa do duplo, delegados ao QA Expert. RF-137 delegado em paralelo a um Senior Developer novo. README da `DIV-267` feito pelo Tech Lead.

**QA Expert, duplos dos `qa_*` (handback parcial, 2026-10-22):** verdes `qa_cache_unico_p3` 33, `qa_docs_aliases_p4` 16, `qa_filtros_banda_b4` 21, `qa_cursor_b7b` 49, `banda` 34, `filtros` 58, `harness` 22; nenhuma asserção afrouxada; `div95` reforçado para o corpo do `delete_batch`. Reprovam `qa_integridade_p1` e `qa_robustez_rede_p2` caso 16 por causa do RF-137 (com o lote de envio desligado numa cópia, todos verdes) e `json` caso 42 por `$(printf ...)` em `lote_test.sh`. Achado médio: `lote_responder` zera `codigo` ao devolver 1. Interrupção durante o `check` decidida como `DIV-275`.

**RF-137 entregue (handback 2026-10-22):** red literal registrado (lou01 "esperado 5, obtido 0"); verdes `lote` 24, `sync_test` 85, `paralelo` 14, `upload` 39, `retomada_upload` 39, `composicao` 28. Tech Lead conferiu o contrato no Context7 (`DIV-279`) e achou defeito bloqueante: o lote não conferia o `content_hash` devolvido (`DIV-278`). `DIV-SD-6/7` aceitas como `DIV-276/277`. Fechamento do código delegado a um Senior Developer novo; depois, validação independente do QA (inclui adaptar `qa_integridade_p1` e `qa_robustez_rede_p2` ao envio em lote).

## Prompt 3 — 2026-10-22

> continue

**Intenção:** seguir a mesma demanda (fase 9) do ponto atual: bateria seletiva em execução, depois validação do QA, suíte completa, medição final com ok do solicitante, registro de entrega e PR.

**Decisão do solicitante (AskUserQuestion, 2026-10-22):** "N=1 e N=4 (Recomendado)" para a medição final na conta real, depois da aprovação do QA, mesmo volume e semente da base.

## Prompt 4 — 2026-10-22

> continue

**Intenção:** seguir a mesma demanda (fase 9).

**Tech Lead, 2026-10-22:** `json` caso 42 corrigido (`printf -v` em `lote_test.sh`), 62/0. `comandos` caso 94 (`upload_de_diretorio_transfere_recursivamente`) reprovava porque o upload de pasta passou pelo envio em lote; o duplo de `comandos_test.sh` ganhou as rotas de lote via `lote_responder`, sem mudar asserção, 119/0. Bateria seletiva: `lote` 31, `harness` 22, `sync_test` 85, `paralelo` 14, `upload` 39, `retomada_upload` 39, `composicao` 28, `banda` 34, `filtros` 58, `cursor` 110, `trava` 101, `perfis` 150, `reter` 84, `qa_cache_unico_p3` 33, `qa_docs_aliases_p4` 16, todos sem reprovação.

**QA Expert, validação independente (2026-10-22):** APROVADO COM RESSALVAS, sem bloqueante nem maior; relatório `docs/reviews/2026-10-21-2300-validacao-qa-desempenho-b9.md`. `qa_desempenho_b9` 15/0, `qa_integridade_p1` 27/0 (client_modified em UTC provado no commit do `finish_batch_v2`), `qa_robustez_rede_p2` 21/0, `json` 62/0, `harness` 22/0. Bats da bancada 11/11 (rodado pelo Tech Lead).

**Decisões do solicitante (AskUserQuestion, 2026-10-22):** suíte do QA: "Aceito (Recomendado)". `QA-B9-01`: "Corrigir nesta fase (Recomendado)". Tech Lead ampliou a máscara dos logs da bancada (Basic em base64, `refresh_token`, `access_token`, `app_secret`, `app_key`, `client_secret`, `client_id`, `code`) e inverteu `qdb15` para `assert_nao_contem`; `qa_desempenho_b9` 15/0, bats 11/11, lint limpo.

**Suíte completa, 1ª tentativa válida (2026-10-22):** vermelha em `composicao_test.sh` caso 13 (duas contagens com `grep -c` fora de `_harness_contar` em `qa_desempenho_b9_test.sh:379-380`), 1145 aprovados até ali. Tech Lead trocou as contagens pelo auxiliar sem mudar o que provam; `composicao` 28/0, `qa_desempenho_b9` 15/0. Suíte completa refeita.

**Pareceres de gate (2026-10-22):** conformidade aprovado com ressalvas (0 bloqueante, 0 maior, 7 menores), `docs/reviews/2026-10-21-2300-parecer-conformidade-desempenho-b9.md`; TDD aprovado com ressalvas (0 bloqueante, 2 maiores, 4 menores), `docs/reviews/2026-10-21-2300-parecer-tdd-desempenho-b9.md`. Tech Lead decidiu fechar os 2 maiores antes do PR, só com testes: teste direto da guarda `_dbx_cmd_sync_protegido` no ponto do lote com mutação morta, e reds por mutação do F-09.

## Prompt 5 — 2026-10-22

> continue

**Intenção:** seguir a mesma demanda (fase 9).

**Achados maiores do TDD fechados (2026-10-22):** 5 mutações mortas. Guarda no ponto do lote: `lot13` (novo) mata a remoção da 2ª chamada; a remoção das duas é morta por `fes11_d5` e `lot13`. F-09: `par04`/`par05` matam N ignorado, `par06` mata ordem trocada, `par09` mata escrita de estado no auxiliar, estendido a `_dbx_cmd_sync_aux_iniciar`. Na cópia: `lote` 32/0, `paralelo` 14/0, `composicao` 28/0, `json` 62/0. Seção de fechamento no parecer de TDD.

## Prompt 6 — 2026-10-22

> continue

**Intenção:** seguir a mesma demanda (fase 9).

**Suíte completa, 2ª tentativa:** vermelha em `espaco_test.sh` caso 3 (`esp03`), 1241 aprovados até ali; o duplo não conhecia o `delete_batch`. Tech Lead ligou `lote_responder` no duplo, sem mudar asserção. Arquivos restantes rodados um a um para achar todas as falhas de uma vez.

**Rodada arquivo a arquivo (2026-10-22):** só `espaco_test` (`esp03`) e `qa_consulta_diagnostico_b1` (casos 7 e 13) reprovavam, ambos pelo envio/exclusão em lote. `espaco_test`: duplo ligado ao `lote_responder`, 13/0. `qa_consulta_diagnostico_b1`: cenários escalados acima de 1 MiB para seguir no envio unitário, com a mesma conta de espaço (cabe exatamente, falta um byte) e as mesmas asserções, 21/0. Demais 32 arquivos de integração verdes.

## Prompt 7 — 2026-10-22

> check tasks

**Intenção:** consultar o estado das tarefas em andamento da fase 9.

**Suíte completa, 3ª tentativa:** 2006 aprovados e 0 reprovados em 69 arquivos; parou em `retomada_download_test.sh` por "No space left on device" no `/tmp` (tmpfs de 7,9 GB), sem defeito de código. Tech Lead apagou 738 MB de cópias de trabalho próprias na scratchpad (o volume da bancada ficou) e refez a suíte oficial com `TMPDIR=/home/sales/.cache/dbx-testes-tmp` (disco).

**Suíte completa, 4ª tentativa (TMPDIR no disco):** reprovou `retomada_estado_test.sh` caso 2 (`c2_descarte_por_cabecalho_leva_o_part_pela_barreira`). O caso passa com o `/tmp` padrão (25/0) e reprova com TMPDIR no disco também na `develop` @ `334394e`: dependência de ambiente anterior à fase 9, registrada para o backlog. Volume da bancada apagado para liberar o tmpfs (sha256 agregado guardado; recriado com a semente 42 antes da medição). Suíte oficial refeita com o `/tmp` padrão.

## Prompt 8 — 2026-10-22

> check tasks

**Contexto:** o solicitante atualizou o plugin ai-team (`/plugin`, `/reload-plugins`) antes do pedido.

**Suíte completa, 5ª tentativa (/tmp padrão):** 2030 aprovados e 1 reprovado em 69 arquivos; `retomada_download_test.sh` caso 25 (`rmo01_rmo02_rmo04...`) com código 11 (integridade), o mesmo caso da 1ª suíte do F-09, que passa isolado. Hipótese do Tech Lead: o tmpfs enche durante a suíte e uma escrita truncada diverge o hash; pico de uso de `/tmp` medido por arquivo de teste novo. `--conferir`: a suíte oficial exige árvore commitada; o commit vem antes da suíte final.

## Prompt 9 — 2026-10-22

> check tasks
