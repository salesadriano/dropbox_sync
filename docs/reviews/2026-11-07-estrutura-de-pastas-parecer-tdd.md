# Parecer de evidencias TDD — estrutura de pastas antes da transferencia (F-103)

Extraido do registro [2026-11-07-estrutura-de-pastas-registro.md](2026-11-07-estrutura-de-pastas-registro.md), secoes por tarefa e "Validacao independente do QA". Nenhum comando foi reexecutado para este parecer, exceto o que o registro ja documenta. Quando o registro nao traz um dado, a celula diz "nao consta no registro".

## Identificacao

- Projeto ou produto: dropbox_api (CLI em shell)
- Agent responsavel pela alteracao: Senior Developer (conforme o registro)
- Agent responsavel pela verificacao: Tech Lead (verificacao por tarefa); QA Expert (validacao independente de 2026-11-08, reexecutou `estrutura_pastas_cursor` e `estrutura_pastas_envio`)
- Data da verificacao: 2026-11-07 a 2026-11-08
- Ciclo de verificacao: escalonado ao Tech Lead
- Tipo de alteracao: Implementacao nova (com correcoes de defeito nas tarefas 2, 5 e 8a/8b)
- Execucao dos gates: local, sem pipeline
- Porte da demanda: G
- Modo do parecer: Completo

## Escopo verificado

- Comando usado para levantar o diff: `bash tests/run.sh <filtro>` (runner oficial do projeto, por arquivo e por filtro, conforme cada tarefa). `git diff develop --stat` nao foi reexecutado para este parecer.
- Base de comparacao: `origin/develop` @ e3628a6.
- Arquivos verificados: ver "Escopo e arquivos" do registro. Os 6 `estrutura_pastas_*_test.sh` (99 casos no levantamento do QA; 106 casos no filtro apos 8a e 8b).
- Comportamento alterado e nao verificado, com motivo: TC-ARV-15 (cursor, exclusao de pasta no delta) nao discriminava no ciclo da validacao do QA; correcao na tarefa 8a, sem registro de caso no registro original. TC-ARV-19 e TC-ARV-28 sem caso no QA; tarefa 8b, sem detalhe no registro original. TC-ARV-32 nao verificavel neste worktree (so `develop`).

## Criterios e seams acordadas

| # | Criterio (secao 5.26) | Seam sob teste | Origem do acordo | Camada | Coberto |
|---|---|---|---|---|---|
| 1 | `RF-209` a `RF-219`, `TC-ARV-01..32` | funcao publica (`dbx_lote_criar_pastas`), `commands/sync.sh` pelo runner, duble de `curl` | Solicitante (prompt 1) / System Design | Integracao (shell) | Sim, com as ressalvas de "Criterios por tarefa" |

- Seams propostas e descartadas, com motivo: nao consta no registro original.

## Evidencia do ciclo red-green-refactor (por tarefa)

| Tarefa | Fatia vertical | Red observado | Green observado | Lacuna declarada |
|---|---|---|---|---|
| 1 | `lib/lote.sh`, `dbx_lote_criar_pastas` (9 casos) | `bash tests/run.sh estrutura_pastas_lote_test.sh`: 1 reprovado (`dbx_lote_criar_pastas: command not found`, status 127); 8 nao executados (parada no primeiro erro) | mesmo comando: `casos aprovados: 9, reprovados: 0, pulados: 0, APROVADA` | nenhuma |
| 2 | Criacao unica depois das recusas do plano (`RF-210(g)`, `TC-ARV-05b`) | `estrutura_pastas_envio_test` 6/7 (duble registrou `/r/a`, `/r/c`, `/r/a/b`); `paralelo_test` red no par05 | envio 9/9; `paralelo_test` 25/25 (duble passou a carregar `lote_duplo.sh`); `qa_cache_unico_p3` 33/33 | nenhuma |
| 3 | Recebimento: `mkdir` por ciclo, falha de item e sistemica (`RF-211`, `RF-213`) | `estrutura_pastas_recebimento_test` 0/1 (`motivo da pasta`); caso da pasta vazia que falha no envio, red | recebimento 6/6, depois 8/8; caso da pasta vazia no envio, 10/10 | o red do caso de recebimento foi visto so no agregado (`ok=3 nao_ok=1`), sem execucao isolada; `download_de_pasta_sem_filtro_cria_subpasta_vazia` e de caracterizacao, sem red contra o codigo |
| 4 | Arquivo no lugar de pasta (`RF-214`, `DIV-400`) | `DIV-400` (presenca de `delete_batch`); `TC-ARV-17` envio e `TC-ARV-17c` recebimento, com o predicado neutralizado em copia temporaria restaurada depois | envio 17/17; recebimento 13/13 (verificacao do Tech Lead) | demais casos novos sem red isolado; os de "nada e apagado" valem como regressao |
| 5 | Pastas orfas no `--espelhar` (`RF-216`) | red isolado em 7/10 (recebimento) e 7/11 (envio); demais casos so exigem nao agir e ja passavam | `estrutura_pastas` 60/60 (relato do SD); verificacao do Tech Lead nas suites de regressao (abaixo) | tres asserts do proprio teste corrigidos (contagem de `list_folder`); codigo inalterado nesses casos |
| 5b | Regressao em `sync_test` (55) e `qa_integridade_p1` (15), causada pela tarefa 5 | `rf216_pasta_local_com_caixa_diferente_do_remoto_nao_e_orfa`: red | green; o segundo caso nasceu verde (guarda) | nenhuma |
| 6a | Simulacao, contadores e relatorio (`RF-214(e)`, `RF-217`, `RF-218`, `RF-219(a)`) | red observado por requisito | `estrutura_pastas` 75/75 | nenhuma declarada |
| 6b | Item 0 do ocupante na simulacao; `RF-217(c)`; `RF-217(d)` | nao consta no registro | nao consta no registro | itens conferidos pelo Tech Lead; detalhe de red e green nao registrado |
| 6c | Delta com cursor valido (`RF-212`, `TC-ARV-13..15`) | red nos casos 13 e 14; caso 15 negativo, verde sem o codigo novo | `estrutura_pastas_cursor_test` 3/3; filtro `estrutura_pastas` 84/84 com 5 arquivos | caso 15 nao discrimina (achado M2 da validacao do QA) |
| 6d | Barreira com `--paralelo`, `--debug` e paralelismo 1 e 8 (`RF-215`) | `--debug` de mkdir/rmdir: red observado; os demais 6 casos ja passavam (regressao) | filtro `estrutura_pastas` 91/91 com 6 arquivos; detector limpo | `RF-215(b)` sem caso proprio; `RF-215(d)` (`session_id`) conferido so no envio |
| 8a | Achado M2 (`tc_arv_15`) e ocupante no delta (m4), conforme o Tech Lead | nao consta no registro original | nao consta no registro original | detalhe por caso nao registrado |
| 8b | Achado M1 (`TC-ARV-19`, `TC-ARV-28`) e `TC-ARV-04` da 5.26, "so testes" | nao consta no registro original | nao consta no registro original | detalhe por caso nao registrado |

- Refatoracoes realizadas sem alteracao de comportamento externo: `_dbx_lote_ler_marca`, `_dbx_lote_resumo_http` e `_dbx_lote_dormir` reaproveitadas (tarefa 1); campos de contagem reordenados na saida para atender o contrato de `sync_test` (tarefa 6a). Nao consta mais refatoracao no registro original.

## Reaprovacao de suites do QA alteradas (regra 12)

| Suite | sha256 antes | sha256 depois | Resultado | Aceite |
|---|---|---|---|---|
| `tests/integracao/qa_paralelo_pastas_b18_test.sh` | 94f2b18c884f014b162632451ac28c2c1f0a2b372be37bcadf3d7e4e02071c44 | 29f9b2c9cf3cc5dd6784be0abcb555c57afa0b9ad9dfc2a6535e2119d6304834 | 10/10 | Solicitante, 2026-11-07 (lote 3) |
| `tests/integracao/qa_cursor_b7b_test.sh` | 15045c18464902f61c70069c513a506cd3ac8f7fa2e3ed251a82e26af4ab5159 | 21988dac2613d8265176f9fe5a848b17227b8f9cdf335d11e46fbae3d8a26fc0 | 49/49 | Solicitante, 2026-11-07 (lote 3) |
| `tests/integracao/qa_sync_blocos_b21_test.sh` | f5e8fc366fda4d77c41db5e1541d40060a273ad1532397f11466209502bbd6f8 | b5629912637e96058a545ac9b9ff3c45c4e7fb35b024bbc0046301dc94c6f541 | 25/25 | Solicitante, 2026-11-07 (lote 3) |
| `tests/integracao/qa_desempenho_b9_test.sh` | 2630f5364fd3da79f3f6a36ca67b61722b9f010e50a86f6d7603e312bef90c47 | 9ebfe1c95fa9e9e0087c80d482225cc2585344325544874d8e3530b49bfe5144 | 15/15 | Solicitante, 2026-11-08 (lote 5) |

- Alteracao em cada suite: duble de `curl` (`create_folder_batch`), sem alteracao de assert ou caso, nas tres primeiras; auditoria estatica `qdb09` restrita a duas funcoes (RF-136(f)), na quarta. `verificar-remocao-de-casos.sh` 2948 para 2948 (registro original).
- Auditoria `lot11` (`lote_test`): mesma excecao RF-136(f); `lote_test` 41/41 (dois arquivos), conferido pelo Tech Lead.
- Lint: achados de `qa_cursor_b7b` (SC2034, linha 255) e `qa_sync_blocos_b21` (SC1105, SC2211, SC2288, SC2086, SC2210, SC2034, linhas 28 e 42) sao pre-existentes, reproduzidos na `develop` (e3628a6) com os mesmos codigos; fora do escopo.

## Execucao por camada

- Comando oficial de execucao isolada: `bash tests/run.sh <filtro>` (runner do projeto; CLI sem container).
- Tecnologia suporta execucao em container: nao aplicavel (projeto CLI; execucao pelo runner oficial).
- Banco real: nao aplicavel (adaptador sem persistencia).
- E2E: nao aplicavel (projeto sem interface).

| Camada | Comando | Total | Aprovados | Falhos | Ignorados | Nao executados por interrupcao | Duracao |
|---|---|---|---|---|---|---|---|
| Integracao (filtro `estrutura_pastas`) | `bash tests/run.sh estrutura_pastas` | 106 casos (8b, duas rodadas seguidas) | 106 | 0 | nao consta | nao consta | nao consta |
| Integracao (mapeamento por arquivo isolado, apos 6d) | runner por arquivo, 126 arquivos | 126 arquivos | 126 | 0 | nao consta | nao consta | 3674 s |
| Integracao (mapeamento por arquivo isolado, apos 6a) | runner por arquivo, 124 arquivos | 124 arquivos | 122 | 2 (`qa_pasta_ocupada` caso 2; `qa_cursor_b7b` caso a06) | nao consta | nao consta | 3807 s |
| Integracao (mapeamento por arquivo isolado, apos T4 e T5) | runner por arquivo, 123 arquivos | 123 arquivos | 118 | 5 (`composicao_test`; `sync_test`; `qa_integridade_p1`; `lote_test`; `qa_desempenho_b9`) | nao consta | nao consta | 4110 s |
| Integracao (mapeamento por arquivo isolado, apos T3) | runner por arquivo, 123 arquivos | 123 arquivos | 123 | 0 | nao consta | nao consta | 3299 s |
| Integracao (QA, reexecucao) | `estrutura_pastas_cursor` e `estrutura_pastas_envio` | 3 e 28 | 3 e 28 | 0 | nao consta | nao consta | nao consta |
| Unitario | nao consta no registro original | nao consta | nao consta | nao consta | nao consta | nao consta | nao consta |
| E2E | nao aplicavel (sem interface) | nao aplicavel | nao aplicavel | nao aplicavel | nao aplicavel | nao aplicavel | nao aplicavel |

- Suite completa: nao rodada pelo QA (regra 8 do `protocolo-tdd`).
- Lint: `lint` sai 0 na tarefa 6d; `shellcheck -x` dos arquivos alterados limpo nas tarefas 1 a 6d (exceto achados pre-existentes acima). `commands/download.sh` interrompido de forma intermitente pelo teto de memoria; rodadas isoladas dao 0. Teto `LINT_MEMORIA_MB` subido para 14336 pelo solicitante.
- Falhas em aberto: TC-ARV-19, TC-ARV-28 sem caso (QA, M1); TC-ARV-15 nao discrimina (QA, M2); TC-ARV-04 sem caso (QA, m1). Reconferir apos 8a e 8b.

## Interrupcao no primeiro erro

- Parada no primeiro teste falho: sim, o runner interrompe ao primeiro erro no reds registrados (tarefa 1: 8 casos nao executados).
- Execucao final concluida sem interrupcao: sim, nas rodadas de 6d e 8a/8b (106/106 e 91/91 com filtros); suite completa nao rodada.

## Distribuicao da piramide

Nao consta no registro original. Por ser shell sem projeto de camadas declaradas, a distribuicao nao foi calculada.

## Verificacao das proibicoes por camada

- Teste unitario isolado de rede e banco: nao consta no registro.
- Integracao com duble de `curl` e sem chamada real: sim, nas suites novas ("dubles de `curl` locais, nenhuma chamada real sem ok", `RF-209` a `RF-219`).
- Demais itens: nao aplicavel (projeto CLI sem banco, interface ou E2E).

## Governanca de dados de teste

- Dado de teste sintetico, sem segredo nem dado pessoal: sim, o token do teste da tarefa 1 e sintetico (registro original).

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correcao esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 | `tests/integracao/estrutura_pastas_cursor_test.sh:180-191` | M2: `tc_arv_15` nao discrimina; `rmdir` falharia por `a1.txt` local, e o assert nao distingue "nao tentou" de "tentou e ENOTEMPTY" | Caso de teste que nao prova o requisito (RF-212(c)) | Apagar `a1.txt` local e/ou forjar o retrato; afirmar `pasta apagada` ausente e `pasta` existente | Maior | Corrigido na tarefa 8a (registro original; detalhe nao consta) |
| 2 | nao consta (`commands/sync.sh`, linha 2729) | M1: `TC-ARV-19` (ENOSPC/EROFS no ciclo 2) sem caso | Criterio de aceite acordado sem teste (regra 14 do `AGENTS.md`) | Caso novo | Maior | Corrigido na tarefa 8b (registro original; detalhe nao consta) |
| 3 | `commands/sync.sh`, linhas 3216-3222 | M1: `TC-ARV-28` (pagina que falha numa subarvore so do destino) sem caso | Criterio de aceite acordado sem teste | Caso novo | Maior | Corrigido na tarefa 8b (registro original; detalhe nao consta) |
| 4 | `tests/integracao/` (6 arquivos novos) | m1: colisao de ID com `TC-EST-01..04` do RNF-25 | Rastreabilidade | Renumerar a serie nova | Menor | Corrigido: serie renumerada para `TC-ARV-NN`; `TC-EST-01..04` do RNF-25 mantidos |
| 5 | `commands/sync.sh` (ocupante no delta) | m4: ocupante no delta tratado como falha de item, sem exclusao antecipada (contra DIV-401) | Decisao do solicitante em DIV-401 | Apagar antes de criar tambem no delta | Maior (reclassificado pelo Tech Lead) | Corrigido na tarefa 8a (registro original; detalhe nao consta) |
| 6 | `tests/integracao/` | m2: cobertura por proxy de TC-ARV-18, 20, 23, 27; RF-215(b) sem caso | Cobertura de criterio | Casos proprios ou justificativa | Menor | Aceito como ressalva |
| 7 | `tests/integracao/` | m3: auditorias estaticas (`rf216_a_decisao_nao_le_memoria_retrato_nem_cursor`, `lot11`, `qdb09`) em caso de produto | Governanca de teste | Revisar nomes e classificacao | Menor | Aceito como ressalva |
| 8 | `tests/integracao/` (4 suites `qa_*`) | m5: alteracoes em suites do QA fora do dominio | Regra 12 | Aceite do solicitante | Menor | Encerrado: sha256 atual igual ao reaprovado |
| 9 | Mapa de contencao SD x QA | m6: nao feito por falta de suite `qa-*` propria | Auditoria de duplicidade | Auditoria separada | Menor | Aberto (registro original) |

- Total de bloqueantes: 0 (validacao do QA, B1: nenhum).
- Total de maiores: achados 1, 2, 3 e 5 do quadro, tratados em 8a e 8b (detalhe nao consta no registro original). Achado 5 e reclassificado como defeito.
- Total de menores: achados 4, 6, 7, 8 e 9.

## Achados do ciclo anterior

Nao consta: a validacao do QA e a unica revisao de ciclo registrada, e as correcoes 8a e 8b nao trazem o status por achado.

## Veredito

- Resultado: Aprovado com ressalvas (validacao do QA, 2026-11-08; sem bloqueante).
- Justificativa objetiva: a guarda destrutiva depende so do observado na execucao; as sequencias de ordem (pai antes de filho, criacao antes do primeiro envio, apagar antes de criar com `parent_rev`) estao provadas por assert de ordem; 126/126 isolados verdes antes das tarefas 8a e 8b; 106/106 no filtro depois delas.
- Ressalvas registradas, com owner e prazo: M1 e M2 com dono Senior Developer (tratadas em 8a e 8b); m1 a m6 como recomendacao.
- Handoff liberado?: nao consta no registro; aceite final do Tech Lead pendente.
- Gate de conformidade liberado para execucao?: nao aplicavel a este parecer (ver `2026-11-07-estrutura-de-pastas-parecer-conformidade.md`).
- Proximo passo do ciclo do developer: reconferir TC-ARV-15, 19 e 28 e o mapeamento completo apos 8a e 8b; decidir a linha `support/bash-4.2` (pendencia do registro).

## Devolucao ao agent

Nao aplicavel: o veredito e aprovado com ressalvas; nenhuma devolucao registrada.

## Registro

- Este parecer e referenciado pelo registro tecnico [2026-11-07-estrutura-de-pastas-registro.md](2026-11-07-estrutura-de-pastas-registro.md).
- Entrada de memoria com `ref:` para este parecer: nao consta no registro original.
