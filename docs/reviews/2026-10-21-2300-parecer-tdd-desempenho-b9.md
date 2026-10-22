# Parecer de Evidencias de Testes (TDD) — Fase 9, desempenho (F-09 paralelismo, F-08 lote, F-34 bancada)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: backlog fase 9 (RF-133 a RF-139, DIV-256 a DIV-281); porte **G**
- Agent: Senior Developer (revisao do gate, sem alterar codigo nem testes); validacao independente a cargo do QA Expert (`docs/reviews/2026-10-21-2300-validacao-qa-desempenho-b9.md`)
- Data: 2026-10-22
- Branch / base: `feature/desempenho-b9` sobre `develop` @ `334394e`; nada commitado
- Log de prompt: [2026-10-21_2300_backlog-fase-9-desempenho.md](../prompts/2026-10-21_2300_backlog-fase-9-desempenho.md)
- Fonte das contagens: log da demanda e relatorio do QA. Reexecutei um seletivo (`bash tests/run.sh paralelo < /dev/null`: 14 aprovados, 0 reprovados, 0 pulados) para conferir a afirmacao do log. A suite completa nao foi rodada por mim (a cargo do Tech Lead).

## 1. Escopo do diff e mapa de modulos atingidos -> testes

| Modulo (arquivo) | Testes que o cobrem |
|---|---|
| `lib/lote.sh` (novo) | `integracao/lote_test.sh` 31, `qa_desempenho_b9` 15, `tests/support/lote_duplo.sh` (duplo) |
| `commands/sync.sh` (paralelo, lote de envio, exclusao em lote) | `paralelo_test` 14, `lote_test` 31, `sync_test` 85, `qa_desempenho_b9` 15, `qa_robustez_rede_p2` 21, `qa_filtros_banda_b4` 21, `qa_integridade_p1` 27, `cursor` 110 |
| `lib/transfer.sh` (`conferir_resumo`, `iniciar_pequeno`, limiar) | `lote_test`, `qa_integridade_p1`, `upload` 39, `retomada_upload` 39 |
| `lib/cli.sh`, `bin/dbx`, `completions/dbx.bash` (`--paralelo`) | `unit/cli_test.sh` (+17 linhas), `paralelo_test` (TC de validacao), `qa_desempenho_b9` qdb03 |
| `lib/http.sh` (contador de 429) | `paralelo_test` (resumo de `--debug`), `http` |
| `commands/upload.sh` (`DBX_CMD_SYNC_CHAMADOR`) | `upload` 39, `paralelo_test` (ambiente ignorado fora do `sync`) |
| `commands/diagnostico.sh` (linha `paralelo`) | `diagnostico` |
| `scripts/bancada.sh` (novo) | `scripts/tests/bancada.bats` 11, `qa_desempenho_b9` qdb14 e qdb15 |
| `commands/reter.sh` (sem diff) | `reter` 84 (prova DIV-269: `lote_test` lot12, `qa_desempenho_b9` qdb09) |
| Regra 1 (todo diff em `lib/*.sh`/`commands/*.sh`) | `json` 62, `harness` 22, `composicao` 28, `banda` 34, `filtros` 58, `trava` 101, `perfis` 150, `comandos` 119, `confinamento_remoto` 25 (selecao do Tech Lead, todos sem reprovacao) |

Gatilhos da Regra 6 tocados: exclusao remota destrutiva (`delete_batch`), entrada de usuario que vira argumento de API e caminho (`--paralelo`, caminhos no JSON do lote), segredo em log (bancada), upload (envio em lote), limite de uso/rate limit (429 sob paralelismo). Cenarios negativos presentes: guardas antes do lote (qdb06: sem `--confirmar`, origem vazia, `--dry-run`, `--excluir`, nada a apagar), nao confirmado nunca conta (qdb07), `--paralelo` invalido sem rede nem estado (qdb03), redacao de segredo na bancada (qdb14/qdb15), recusa de pasta remota fora do padrao (bats). Todos contra o duplo de `curl`, nunca contra a conta real (ver secao 4, camada).

Lacuna declarada pelo QA: `Retry-After`/429 sob paralelismo e a ordem de saida com falhas sob N=8 nao foram exercitados pela suite do QA; `paralelo_test` cobre sinais e 429 em N pequeno.

## 2. Vermelho

| Fatia | Red registrado | Fonte |
|---|---|---|
| F-09 (RF-133 a RF-135) | **Nenhum.** Testes escritos depois do codigo (desvio declarado, secao 3) | log, "F-09 entregue" |
| RF-136 (exclusao em lote) | **Nao ha red literal no log.** Registrado so o resultado verde (`lote` 15/0 com 8 `lou*` pulados) | log, "Estabilizacao do RF-136" |
| RF-137 (envio em lote) | Sim: `lou01`, mensagem literal "esperado 5, obtido 0" (nenhum `start` emitido antes da implementacao) | log, "RF-137 entregue" |
| DIV-278 (conferir `content_hash` no lote) | Nao por teste: o defeito (lote sem conferencia) foi achado pelo Tech Lead lendo o contrato no Context7; os testes qdb10/qdb11 e `lote` foram escritos na correcao | log |
| Bancada (F-34) | Nao registrado | n/a |

Nao verifiquei o vermelho contra `334394e` em worktree descartavel (nao era o pedido e nao havia mais que 3 execucoes seletivas). A afirmacao de que `lou01` reprovou antes do codigo repousa so no registro do log. Achado 3.

## 3. Desvio do F-09 (testes depois do codigo)

- O log declara: "testes escritos depois do codigo (desvio do red-green, registrado no registro de entrega)".
- Pela Regra 1 e pelo Passo 2 do protocolo-tdd, teste escrito depois da implementacao e achado; "implementacao escrita antes do teste em criterio acordado" esta na lista de bloqueantes do Passo 6.
- Atenuantes concretos: `paralelo_test` 14/14 foi reconferido pelo Tech Lead; o QA validou independentemente a equivalencia N=1 x N>1 (qdb01, qdb02) e RF-134(e) (qdb04), e rodou o seletivo `qa_robustez_rede_p2` 21/0; o proprio `paralelo_test` traz auditoria estatica de estado e contagem de pico de transferencias simultaneas por marca em `$base/vivos`, que prova paralelismo efetivo sem depender de tempo.
- O que o atenuante nao supre: o teste foi desenhado vendo o codigo, entao pode confirmar o que o codigo faz e nao o que o requisito pede. Para os tres comportamentos de risco mais alto o QA escreveu casos independentes (qdb01 a qdb04), o que reduz a lacuna. Para o restante dos 14 casos nao ha prova de que reprovam sem o codigo.
- Mitigacao possivel e barata, sem desfazer o codigo: provar o red por mutacao do proprio codigo de F-09 (por exemplo trocar `vivos < paralelo` por `vivos < 1` e conferir que o pico de `$base/vivos` do caso de N>1 reprova). Nao executada por mim (limite de execucoes).
- Classificacao: **Maior**, aceito como ressalva porque o desvio foi declarado ao Tech Lead no momento, nao foi escondido, e ha cobertura independente do QA para o comportamento. Nao e reincidente. Achado 1.

## 4. Piramide e proibicoes por camada

Projeto: CLI em Bash sem UI web, sem banco e sem backend proprio. O "backend" e a API Dropbox; a camada de integracao do projeto roda o `bin/dbx` real contra um duplo de `curl` determinista (nenhum acesso a rede nos testes). Nao ha Cypress nem Testcontainers aplicaveis.

| Camada | Arquivos / casos novos desta fase | Parcela aproximada | Observacao |
|---|---|---|---|
| Unitario (funcao isolada, sem processo) | `unit/cli_test.sh` (validacao de `--paralelo`, +17 linhas) | menos de 5% | Alvo 70% nao atingido |
| Integracao (CLI real + duplo de `curl`) | `lote` 31, `paralelo` 14, `qa_desempenho_b9` 15, ajustes nos `qa_*`/`sync`/`comandos` | cerca de 85% | Concentra a regra porque o valor esta na orquestracao de processos, ordem e HTTP |
| Script de ferramenta (bats) | `bancada.bats` 11 | cerca de 15% | Cobre `scripts/bancada.sh` |
| E2E contra a conta real | Bancada (`bancada.sh medir`), N=1 e N=4, com ok do solicitante, previsto apos a aprovacao do QA | manual, nao automatizado | Mede tempo e 429, nao afirma comportamento |

- Desvio do 70/20/10: justificado pela natureza do projeto (CLI Bash; a regra de negocio nova e orquestracao de processos e protocolo HTTP, sem entidade pura para isolar). A regra de `protocolo-tdd` admite desvio justificado; nao e achado.
- Falta de unitario puro para o que seria isolavel: `_dbx_lote_conferir`, `_dbx_lote_resumo_http`, `_dbx_cmd_sync_banda_por_transferencia` e `dbx_cli_validar_paralelo` (so este tem unitario) sao funcoes de entrada e saida de texto que se testariam sem processo. Recomendacao Menor 6.
- Proibicoes: nenhum banco simulado ou mock de camada de dados (nao ha banco); o duplo de `curl` e a fronteira externa (API Dropbox), permitido pela natureza do projeto. O duplo compartilhado `tests/support/lote_duplo.sh` e usado por `lote`, `sync_test`, `comandos`, `qa_robustez_rede_p2`, `qa_filtros_banda_b4` (ver secao 6 sobre o risco de um duplo unico).

## 5. Mutacao da guarda `_dbx_cmd_sync_protegido` que nenhum teste de caixa-preta mata

- Fato (log, "Estabilizacao do RF-136"): "guarda `_dbx_cmd_sync_protegido` aplicada por item antes da fatia (mutacao nao detectada por caixa-preta: o plano ja descarta o protegido; fica como defesa em profundidade)".
- Confirmado por leitura do codigo: a funcao e chamada em `commands/sync.sh:1008` (`_dbx_cmd_sync_sem_protegidos`, que tira os protegidos de `DBX_SYNC_APAGAR` ainda no plano) e de novo em `:1491` na montagem do lote. Qualquer mutacao em um dos pontos e compensada pelo outro, e a funcao em si (`:1418`) so e alcancavel por esses dois. Logo a mutacao e **equivalente do ponto de vista externo**: nenhum teste que enxergue so a rede e a saida consegue distingui-la.
- Isso nao e um defeito do codigo: e defesa em profundidade deliberada, exigida pela memoria `guarda-de-seguranca-sem-estado` (a guarda age "no ponto da escrita", RF-80(d)). E sim uma lacuna de prova: a segunda barreira, a que impede o dano se o primeiro filtro regredir, nao tem teste que a exercite sozinha.
- Evidencia indireta de que a guarda como um todo e testada: qdb05/qdb06 (o que existe na origem nao entra; `--excluir` protege) e `qa_filtros_banda_b4` (zero `delete_v2`/`delete_batch` sobre filtrado, em qualquer direcao) reprovam se os dois pontos forem removidos juntos. Nao rodei essa mutacao conjunta (limite de execucoes); o relatorio do QA nao a registra como feita.
- Classificacao: **Maior**, aceito como ressalva, porque a guarda e destrutiva e a segunda barreira existe justamente para a regressao do primeiro filtro. Correcao esperada: (a) teste de nivel de funcao que injeta `DBX_SYNC_APAGAR` com um item fora do escopo do filtro e chama `_dbx_cmd_sync_apagar_remoto_em_lote` direto, afirmando que o item nao entra no corpo do `delete_batch`; e (b) registrar o resultado da mutacao conjunta dos dois pontos. Achado 2.

## 6. Testes existentes alterados e por que

`git diff --stat` mostra 12 arquivos de teste existentes alterados (cerca de 230 linhas). Lidos os trechos removidos e adicionados; nao encontrei asserção afrouxada ou removida sem equivalente.

| Arquivo | Alteracao | Por que | Risco |
|---|---|---|---|
| `integracao/sync_test.sh` | Duplo de `curl` ganha `--data-binary` e roteamento ao `lote_responder` (delete_batch/check ecoa `files/delete_v2` por item confirmado); arquivos `x.txt` passam de 13 bytes para 1.048.577 bytes | O espelho passou de `delete_v2` por item para lote; um envio de 2 ou mais pequenos agora vai por `start`; `x.txt` precisa ficar acima do limiar (DIV-256) para continuar exercitando o envio unitario que RF-49 verifica | O teste de RF-49 agora depende do limiar de 1 MiB: se o limiar mudar na bancada (DP-12), os dois casos precisam acompanhar. Menor |
| `integracao/comandos_test.sh` | Duplo ganha rotas de lote via `lote_responder` | `upload_de_diretorio_transfere_recursivamente` (caso 94) reprovava porque a pasta passou pelo envio em lote; Tech Lead corrigiu o duplo "sem mudar asserção" (log, Prompt 4) | Baixo |
| `integracao/qa_robustez_rede_p2_test.sh` (+76) | Duplo traduz `falhar_envio` em falhas por entrada do `finish_batch_v2`; caso do sinal passa de `files/delete_v2` para `files/delete_batch` (e novo caso de sinal durante o `check`); asserção nova de 3 classes distintas (`sort -u` = 3) | A exclusao do espelho e lote agora; a falha por item continua observavel com a mesma classe | A asserção de classe foi reforçada, nao afrouxada. O sinal agora e afirmado em dois pontos (lancamento e conferencia) |
| `integracao/qa_integridade_p1_test.sh` (+25) | Adaptado ao envio em lote (`client_modified` em UTC provado no commit do `finish_batch_v2`) | Mesmo conteudo, rota nova | Baixo |
| `integracao/qa_filtros_banda_b4`, `banda`, `filtros`, `cursor`, `qa_cache_unico_p3`, `qa_docs_aliases_p4` | Duplo de `curl` ganha `--data-binary`/`corpo_arquivo` e o `lote_duplo`; `qa_filtros_banda_b4` troca a contagem de `delete_v2` por `delete_batch` mantendo o eco por item (`LOTE_ECOA_V2`) | A exclusao do espelho e lote; o eco preserva a mesma prova de "zero apagamentos sobre filtrado" | Ver risco do duplo unico abaixo |
| `integracao/cursor_test.sh` | Auditoria de ordem passa a buscar `_dbx_cmd_sync_apagar_remoto_em_lote "$remoto"` e `apaga_local`, ambos depois do plano | O ponto de exclusao remota mudou de nome | A auditoria e por posicao de linha no texto do fonte; frágil a renomeacao, mas aqui ela falhou alto e foi ajustada (nao silenciosa) |
| `unit/cli_test.sh` (+17) | Casos novos de validacao de `--paralelo` | RF-133(b) | n/a |

- Risco comum: o eco `LOTE_ECOA_V2` faz o duplo de lote simular `delete_v2`, para que testes antigos que contam `delete_v2` sigam valendo. Isso mantem a cobertura, mas desloca a verdade para o duplo: se `lote_duplo.sh` ecoar um item que o codigo nao enviaria, os testes antigos passam em falso. Mitigacao ja existente: `lote_test` lot01 afirma que **nenhum** `delete_v2` real sai (`assert_nao_contem DELETE_V2`) e lot11 afirma por grep que `commands/sync.sh` nao tem `delete_v2`.
- Guarda de remocao: o QA registra `2155 -> 2157 casos; nenhuma reducao nao declarada` (`scripts/verificar-remocao-de-casos.sh`). Nao reexecutei.

## 7. Parada no primeiro erro e execucao seletiva (Regras 8 e 9)

- Runner `tests/run.sh` para no primeiro erro (registro de perfis-b8 e do QA: "para no primeiro erro" ja era comportamento da fase anterior); o QA registra ter reexecutado do inicio apos o erro que achou em `json` caso 42 (`$(printf` em `lote_test.sh`), corrigido pelo Tech Lead. Interrupcoes ocorridas na demanda: `json` caso 42 (corrigido, 62/0), `comandos` caso 94 (corrigido no duplo, 119/0), `retomada_download` caso `rmo01` na suite inteira durante a bancada (nao reproduziu isolado, 27/27; coincidiu com a bancada consumindo memoria). Nenhum contado como aprovado.
- Selecao registrada no log (Tech Lead, Prompt 4): `lote` 31, `harness` 22, `sync_test` 85, `paralelo` 14, `upload` 39, `retomada_upload` 39, `composicao` 28, `banda` 34, `filtros` 58, `cursor` 110, `trava` 101, `perfis` 150, `reter` 84, `qa_cache_unico_p3` 33, `qa_docs_aliases_p4` 16, todos 0 reprovados; QA: `qa_desempenho_b9` 15/0, `qa_integridade_p1` 27/0, `qa_robustez_rede_p2` 21/0, `json` 62/0, `harness` 22/0, `bancada.bats` 11/11. Lint: exit 0 nos arquivos tocados (QA e Tech Lead).
- Suite completa local do push que abre a PR para `master`: **ainda nao registrada** (Tech Lead esta rodando). Pipeline: ainda sem PR. Sem a execucao verde registrada para o commit, o push que abre a PR fica bloqueado pela Regra 8 (e pelo guarda de comandos); nao e achado deste parecer, e pendencia do fechamento.
- Enquadramento em modulos: o projeto nao tem mapa de modulos separado por pasta alem dos nomes curtos de `tests/run.sh`; a selecao acima foi feita pelo Tech Lead e pelo QA. Nao reverifiquei o mapa por falta de pedido; limitacao registrada.

## 8. Achados

| # | Sev. | Local | Achado | Regra | Status |
|---|---|---|---|---|---|
| 1 | Maior | `tests/integracao/paralelo_test.sh` (14 casos) | Testes do F-09 escritos depois do codigo; sem red registrado | Regra 1, Passo 2 | Aberto; aceito como ressalva (atenuantes na secao 3); correcao: provar o red por mutacao de F-09 e registrar |
| 2 | Maior | `commands/sync.sh:1008`, `:1491` | Mutacao da segunda barreira de `_dbx_cmd_sync_protegido` nao e morta por nenhum teste de caixa-preta (mutante equivalente externo); guarda destrutiva | Regra 1 (prova), memoria `guarda-de-seguranca-sem-estado` | Aberto; correcao: teste direto do ponto do lote e mutacao conjunta registrada |
| 3 | Menor | log, RF-136 e RF-137 | Red de RF-136 nao registrado; red de RF-137 registrado so por mensagem no log, sem execucao contra a base | Regra 1 | Aberto |
| 4 | Menor | `tests/integracao/paralelo_test.sh:342-360` | Auditoria de estado nao cobre `_dbx_cmd_sync_aux_iniciar` e nao e transitiva (ver parecer de conformidade, achado 3) | RF-135(a) | Aberto |
| 5 | Menor | `tests/support/lote_duplo.sh` | Duplo unico compartilhado por 5 suites com eco de `delete_v2`; um erro nele afeta todas | AAA/isolamento | Mitigado por lot01 e lot11 |
| 6 | Menor | `lib/lote.sh`, `lib/cli.sh` | Sem unitario puro para `_dbx_lote_conferir`, `_dbx_lote_resumo_http`, banda por transferencia | Piramide | Recomendacao |

Contagem: 0 bloqueantes, 2 maiores (dentro do limite de 3, nenhum reincidente), 4 menores.

## 9. Veredito

**Aprovado com ressalvas.**

- Sem bloqueante: ha cenarios negativos para os gatilhos tocados, selecao verde registrada, QA independente aprovado com ressalvas, parada no primeiro erro mantida, nenhum teste nao executado contado como aprovado.
- Ressalvas com owner e prazo: achados 1 e 2, owner Senior Developer, antes do push que abre a PR; achados 3 a 6 sao recomendacoes.
- Pendencia fora do gate: suite completa local verde e registrada para o commit final (Tech Lead), e pipeline da PR, conforme Regra 8.

## Fechamento dos achados maiores (2026-10-22)

Executado numa copia do worktree, sem tocar `commands/` nem `lib/`; toda mutacao foi restaurada e conferida com `cmp` contra o original.

### Achado 2 (guarda destrutiva, `commands/sync.sh:1008` e `:1489`)

Teste novo: `tests/integracao/lote_test.sh`, `teste_lot13_montagem_do_lote_barra_o_protegido_mesmo_se_o_plano_falhar`. Carrega `lib/filtro`, `lib/tmp`, `lib/progress`, `lib/lote` e `commands/sync.sh` num subshell, troca `dbx_lote_excluir` por um duplo que grava os `DBX_LOTE_CAMINHOS` que receberia (o corpo do `delete_batch`), monta `DBX_SYNC_APAGAR=(protegido/a.txt livre.txt)` com `--excluir 'protegido/*'` e chama `_dbx_cmd_sync_apagar_remoto_em_lote /r` direto. Afirma: um unico item chega ao lote (`/r/livre.txt`), contagem `apagados=1 falhas=0`.

| Mutacao | Resultado |
|---|---|
| Remove a chamada da linha 1489 (montagem do lote) | MORTA por `lot13`: `# FALHA: so um item chega ao lote  esperado: [1]  obtido: [2]` |
| Remove as duas (1008 e 1489) | MORTA por `fes11_d5_mutacao_que_filtra_so_um_lado_e_detectada` (`filtros_test`: `a segunda barreira, sem estado, segura sozinha`) e por `lot13` (mesma mensagem acima) |

### Achado 1 (red do F-09, `tests/integracao/paralelo_test.sh`)

| Mutacao | Resultado |
|---|---|
| (a) `vivos < paralelo` vira `vivos < 1` (ignora N; as duas ocorrencias, :316 e :451) | MORTA por `par04` e `par05`: `# FALHA: N=2 sem simultaneidade: pico 1` |
| (b) descarga atribui o resultado ao item de ordem invertida (`itens[total - 1 - descarregados]`) | MORTA por `par06`: `# FALHA: mesmas linhas de falha, na mesma ordem, mesmos arquivos e cache`. Limite: e a variante de ordem errada na descarga, nao a de conclusao real; ambas quebram a mesma propriedade (saida na ordem do plano) |
| (c1) `dbx_state_registrar` no inicio de `_dbx_cmd_sync_aux_item` | MORTA por `par09`: `# FALHA: _dbx_cmd_sync_aux_item nao toca lib/state` |
| (c2) `dbx_state_registrar` no inicio de `_dbx_cmd_sync_aux_iniciar` | NAO morta antes da correcao (`par09` verde); morta depois: `# FALHA: _dbx_cmd_sync_aux_iniciar nao toca lib/state` |

Teste alterado (achado Menor 4): a auditoria de `par09` passou a incluir `_dbx_cmd_sync_aux_iniciar` na lista de funcoes. Continua nao transitiva (nao segue funcoes chamadas pelos auxiliares).

### Verificacao

`sh scripts/lint.sh` limpo em `lote_test.sh` e `paralelo_test.sh`. Na copia: `lote` ok=32 nao_ok=0; `paralelo` ok=14 nao_ok=0; `composicao` ok=28 nao_ok=0; `json` ok=62 nao_ok=0 (`_harness_contar` no teste novo, sem `$(printf ...)`).
