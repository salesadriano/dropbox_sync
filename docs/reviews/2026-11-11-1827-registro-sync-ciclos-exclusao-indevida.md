# Sync em ciclos: memoria gravada ao fim de cada ciclo e linha de progresso sem `nao`

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | No `sync` em ciclos (F-101, `--bloco N`), gravar a memoria (`memoria-*`) ao fim de cada ciclo, mantendo as entradas carregadas dos diretorios ainda nao processados; corrigir o sufixo `nao` da linha de progresso do ciclo |
| Porte | M - altera `commands/sync.sh` (fluxo de escrita de estado persistente) e o contrato de `lib/state.sh` |
| Log de prompt | `docs/prompts/2026-11-11_1827_sync-ciclos-exclusao-indevida.md` |
| Issues | nenhuma |
| Branch / base | `feature/sync-ciclos-exclusao-indevida` sobre `origin/develop` @ bae275f |
| Agents | Senior Developer (implementou); QA e TL: abaixo |
| Data | 2026-11-11 |

## 2. Causa ou decisao

Ajuste pedido (regra decidida pelo solicitante, nao rediscutida) mais defeito cosmetico. Analise de 3 abordagens dispensada: a regra e fechada pelo solicitante e o caminho e unico e evidente. Reutiliza o ramo sem `sim` de `dbx_state_gravar` (mapa inteiro, ja existente), sem funcao nova; nao toca contrato publico, schema nem fronteira. Cosmetico: `so_destino` nunca vira `sim`, entao `${so_destino/sim/...}` expandia para `nao`; variavel e os dois usos mortos removidos, sem mudar outra saida.

Decisao de implementacao: a gravacao por ciclo e pulada com `memoria_descartada=sim` (RF-41(f)): regravar so com o visto deixaria uma memoria nao marcada como descartada sem os ramos nao visitados; ela continua regravada so no fim. Aviso de permissao: flag `aviso_permissao`, uma vez por execucao (por ciclo ou no fim).

Nao foi achado caminho em que arquivo de ciclo anterior entre em `DBX_SYNC_APAGAR` de ciclo posterior (investigacao do TL nao reproduzida; o teste de regressao 1 cobre).

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `commands/sync.sh` | Alterado | +17/-4 |
| `lib/state.sh` | Alterado (so o comentario do contrato de `dbx_state_gravar`) | +8/-7 |
| `tests/integracao/sync_ciclos_memoria_test.sh` | Novo (6 casos) | +164 |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | Alterado (emenda de RF-38(b)) | +1/-1 |

Total de linhas de codigo (producao e teste, sem documentacao): **~203**.

## 4. Testes rodados

| Arquivo de teste | Item afetado | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `sync_ciclos_memoria_test.sh` | `commands/sync.sh` | `bash tests/run.sh sync_ciclos_memoria` | 6 | 6 | 0 | n/d |
| `sync_blocos_test.sh` (unit + integracao) | `commands/sync.sh` | `bash tests/run.sh sync_blocos_test` | 42 | 42 | 0 | n/d |
| `state_test.sh` | `lib/state.sh` | `bash tests/run.sh state_test` | 24 | 24 | 0 | n/d |
| `qa_sync_blocos_b21_test.sh` | `commands/sync.sh` | `bash tests/run.sh qa_sync_blocos_b21` | 25 | 25 | 0 | n/d |
| `comandos_test.sh` (memoria do sync) | `commands/sync.sh` | `bash tests/run.sh comandos_test` | 119 | 119 | 0 | n/d |
| `qa_sync_ciclos_memoria_f101_test.sh` (QA, novo) | `commands/sync.sh` | `bash tests/run.sh qa_sync_ciclos_memoria_f101_test.sh` | 6 | 6 | 0 | n/d |
| `sync_ciclos_memoria_test.sh` (SD, novo) | `commands/sync.sh` | `bash tests/run.sh sync_ciclos_memoria_test.sh` | 6 | 6 | 0 | n/d |
| `cursor_test.sh` (unit + integracao) | `commands/sync.sh` | `bash tests/run.sh cursor_test.sh` | 55 | 55 | 0 | n/d |

- Red observado (base `bae275f`, alteracao guardada em stash): `memoria_por_ciclo_sobrevive_a_interrupcao_com_carregadas` falha (`A/novo.txt` ausente da memoria apos SIGKILL no ciclo 3); `linha_de_progresso_do_ciclo_sem_sufixo_nao` falha (`nao` presente). Os outros 4 casos (completa grava so visitadas, parcial e simulacao nao gravam, regressao `--espelhar` em 4 ciclos com remoto mutavel) passam na base: guardas do comportamento mantido, nao provam a alteracao.
- Parada no primeiro erro (Regra 9): `tests/run.sh` com bail-out no primeiro caso reprovado, conferido; execucoes finais sem interrupcao.
- Barreiras estaticas: `sh scripts/lint.sh lib/state.sh commands/sync.sh tests/integracao/sync_ciclos_memoria_test.sh`: saida 0, sem achados.
- Testes de seguranca e acesso (Regra 6): Nao aplicavel: sem rota, auth, tenant ou entrada nova; a memoria continua chaveada pela conta (RF-52).
- Validacao de formularios (Regra 7): Nao aplicavel: CLI sem interface.
- Suite completa local no push para a PR: Ainda nao houve push para a PR.

## 5. Gates

| Gate | Skills aplicadas | Achados | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9 e 11; Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | Maior (pendencia): `tests/integracao/sync_ciclos_memoria_test.sh` sem linha em `docs/testes/mapa-modulos.md` e no inventario (fora do escopo autorizado; QA/TL definem modulo, Regra 8). Distribuicao: 6 casos de integracao, desvio justificado (CLI de shell, comportamento so observavel de ponta a ponta com duble de `curl`). Guardas de casos de borda passam na base (ver red). Ciclo 2: QA-F101-01 corrigido (red: caso 1 de `qa_sync_ciclos_memoria_f101_test.sh` vermelho; green: 5/5; `sync_ciclos_memoria` 6/6, `sync_blocos_test` 42/0, `qa_sync_blocos_b21` 25/0, `state_test` 24/0, `comandos_test` 119/0) | Aprovado com ressalvas |
| `protocolo-conformidade` | `clean-architecture` + `bash-best-practices`/shellcheck; Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | Nenhum. Reuso do ramo existente de `dbx_state_gravar`; variavel morta removida; escrita continua pela mesma funcao atomica. Ciclo 2 (QA-F101-01, corrigido): `commands/sync.sh` pula a gravacao final com `modo_ciclos=sim` e `ciclo_falho>0` (condicao negativa explicita, comentario atualizado, sem nova abstracao); lint limpo | Aprovado |

- Ciclo: 2 (1 reprovacao do QA: QA-F101-01, corrigido)
- `alteracoes-externas.sh --detectar`: sem divergencias acusadas.

## 6. QA

Veredito final do QA (porte M, ciclo 2 de 2): **APROVADO**. QA-F101-01 **corrigido** (ciclo 1: REPROVADO; ciclo 2: reexecucao verde).

Arquivo criado: `tests/integracao/qa_sync_ciclos_memoria_f101_test.sh`, 6 casos, sha256 final `cea807f4a2d606cc654a168bca2d9a252af192c725f56ef73808694a14a186c1` (supera o do ciclo 1, `fa4c0361...`; aceite do solicitante pendente, regra 12). Mapa de contencao: nenhum. Depois da suite completa (RSK-28), o Tech Lead trocou `$(printf %064d 0)` por literal: sha256 vigente `cb8665e0e98b858a60cc108517d0462936eab5bb7d3e9cce36ec29a8c2eaa624`, reaceito.

Ciclo 2: correcao do SD em `commands/sync.sh` (gravacao final nao roda em ciclos com `ciclo_falho > 0`) conferida contra o caso 1, que passou a verde (a memoria mantem o ciclo 1, as carregadas de B e D e nao grava o que o ciclo falho viu; sem exclusao remota). Risco vizinho: acrescentado o caso 6 (`qa_ciclos_sem_falha_mantem_a_gravacao_final_mesmo_apos_uma_execucao_falha`): apos execucao falha, a seguinte sem falha apaga no remoto o arquivo removido da origem e a gravacao final remove-o da memoria (ciclos sem falha continuam com a gravacao final). O caso 2 ja cobre a execucao em ciclos sem falha. Execucao SEM ciclos (delta com cursor valido): nao alcancavel pelo duble (nao reproduz o retrato recursivo do cursor); protegida pelo conjunto `modo_ciclos == sim` da condicao, que o diff nao altera para esse ramo, e pelas suites `cursor_test.sh` 55/0 e `comandos_test.sh` 119/0, ambas verdes. Limite aceito.

Execucao (`bash tests/run.sh <basename>`, primeiro plano): `qa_sync_ciclos_memoria_f101_test.sh` 6/0; `sync_ciclos_memoria_test.sh` 6/0; `sync_blocos_test.sh` 42/0; `qa_sync_blocos_b21_test.sh` 25/0; `comandos_test.sh` 119/0; `cursor_test.sh` 55/0; `state_test.sh` 24/0 (Tech Lead). Auditoria `sh scripts/auditar-casos.sh --so` no arquivo do QA: 0 bloqueantes, 0 maiores, 0 avisos. Inventario: `sh scripts/inventario-de-testes.sh --check` com os arquivos novos em indice temporario: ver hand-back (sem divergencia).

Cenarios: (1) falha sistemica 403 no ciclo 2: aprovado; (2) morte no ciclo 3, arquivo unico sem temporario, execucao seguinte apaga o removido: aprovado; (3) `--receber --espelhar` interrompido: aprovado; (4) estado de outro dono, aviso unico: aprovado; (5) remoto mutavel: nada apagado: aprovado; (6) recuperacao apos falha com gravacao final: aprovado.

Limites: o duble nao reproduz o retrato recursivo, entao o cursor integral nao e gravado nele; atomicidade provada por ausencia de temporario e arquivo unico apos SIGKILL. Gates documentais de frontend: nao aplicavel.

## 7. Riscos e rollback

- Riscos: memoria gravada por ciclo e lida pela execucao seguinte apos interrupcao; seguro porque a memoria nao decide (RF-38) e nada sai dela fora da gravacao final. Custo: uma escrita atomica extra por ciclo.
- Impacto: contrato de `dbx_state_gravar` (comentario), spec RF-38(b); nenhum schema, UI ou pipeline.
- Rollback: `git revert <sha>` basta.

## 8. Links e aceites

- Entradas de memoria: `2026-11-11-1827-memoria-por-ciclo`, `2026-11-11-1827-aceite-testes-qa-sync-ciclos-memoria` (substituida), `2026-11-12-0140-reaceite-testes-qa-sync-ciclos-memoria`.
- Documentacao sincronizada: `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` (RF-38(b)); `docs/testes/inventario-de-testes.md` e `docs/testes/mapa-modulos.md`.
- Commit(s) / PR: na branch `feature/sync-ciclos-exclusao-indevida`, PR para `develop`.
- DBA (persistencia): Nao aplicavel como gate proprio: sem schema nem formato novo; o arquivo `memoria-*` mantem versao, cabecalho e escrita atomica, e muda so a frequencia de gravacao. Avaliado pelo Tech Lead.
- Tech Lead: Aprovado em 2026-11-11, com ressalva: a causa do relato de origem (arquivos de ciclo anterior marcados `a apagar`) nao foi reproduzida; fica aberta ate o solicitante trazer a saida do ciclo 2 (owner: Tech Lead; prazo: proxima demanda que o solicitante abrir com a evidencia). Analise de abordagens dispensada: regra de persistencia decidida pelo solicitante e correcao QA-F101-01 de caminho unico.
- Solicitante: aceite da suite do QA (sha256 `cea807f4...86c1`, entrada `2026-11-11-1827-aceite-testes-qa-sync-ciclos-memoria`) e reaceite apos a correcao RSK-28 abaixo (sha256 `cb8665e0...a624`, entrada `2026-11-12-0140-reaceite-testes-qa-sync-ciclos-memoria`).
- Suite completa, 1a execucao (`sh scripts/suite-completa.sh -- bash tests/run.sh` sobre `4a0fd1e`): REPROVADA em `json_test.sh` (`massa_adversarial_nao_e_construida_por_substituicao_de_comando`, RSK-28: `$(printf %064d 0)` no duble dos dois testes novos); 22 arquivos, 539 aprovados, 1 reprovado, 2 pulados. Corrigido pelo Tech Lead (literal de 64 zeros); json 66/0, harness 23/0, composicao 28/0, os dois arquivos 6/0.
