# Evidencia de testes: paralelismo no upload e no download

## Identificacao

- Projeto ou produto: `dropbox_sync`
- Agent responsavel pela alteracao: Tech Lead (implementacao das etapas 1, 2a e 2b)
- Agent responsavel pela verificacao: QA independente (suites `qa_paralelo_*`, uma por etapa); Tech Lead (red medido e coordenacao)
- Data da verificacao: 2026-10-26
- Ciclo de verificacao: escalonado ao Tech Lead (ciclo 2 de `qa_paralelo_upload_b19` e de `qa_paralelo_download_b20`)
- Tipo de alteracao: Implementacao nova
- Execucao dos gates: local, sem pipeline
- Porte da demanda: G
- Modo do parecer: Completo
- Registro de entrega: [2026-10-26-1900-registro-paralelo-upload-download.md](2026-10-26-1900-registro-paralelo-upload-download.md)
- Fonte: [log de prompt](../prompts/2026-10-26_1900_paralelo-upload-download.md) e [secao 5.23](../requisitos/escopo-requisitos-e-criterios-de-aceite.md)

## Escopo verificado

- Comando usado para levantar o diff: `git diff origin/develop...HEAD` (a confirmar pelo Tech Lead; esta rodada nao executou comandos)
- Base de comparacao: `origin/develop` @ `6df321e`, HEAD `c1af7e4` (reflog)

| Arquivo | Tipo de alteracao | Camada / modulo | Coberto por teste |
|---|---|---|---|
| `lib/transfer_paralelo.sh` | Novo | Transferencia / upload em partes | Sim (`qa_paralelo_upload_b19`) |
| `lib/download_paralelo.sh` | Novo | Transferencia / download em faixas | Sim (`qa_paralelo_download_b20`) |
| `commands/upload.sh`, `commands/download.sh` | Alterado | Comandos | Sim (`qa_paralelo_pastas_b18`, `paralelo_*`) |
| `commands/sync.sh` | Alterado | Comandos / ponto unico `dbx_cmd_paralelo` | Sim (`qa_paralelo_pastas_b18`) |
| `commands/diagnostico.sh` | Alterado | Comandos (aviso, linha 408) | Sim (`qa_paralelo_pastas_b18`) |
| `lib/state.sh` | Alterado | Estado / registro v2 | Sim (`qa_paralelo_upload_b19`) |
| `lib/http.sh` | Alterado | HTTP / `DBX_HTTP_MARCA_PAUSA`, `dbx_http_conteudo_receber_faixa` | Sim (`qa_paralelo_download_b20`) |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | Alterado | Especificacao (5.23, DIV-358..376) | Nao aplicavel (documental) |

- Comportamento alterado e nao verificado, com motivo: upload e download paralelos de arquivo grande no FreeBSD do solicitante (sem execucao registrada); suite do commit final com a falha intermitente `qa_d16` ignorada por decisao do solicitante.

## Criterios e seams acordadas

| # | Criterio BDD / criterio de aceite | Seam sob teste | Origem do acordo | Camada do teste | Coberto |
|---|---|---|---|---|---|
| 1 | Etapa 1: `--paralelo` e `DBX_PARALELO` em upload e download; pasta repassa N ao sync (RF-175, RF-176) | `dbx_cmd_paralelo`, sync interno | Solicitante / secao 5.23 | Integracao | Sim (10 casos, `qa_paralelo_pastas_b18`) |
| 2 | Etapa 2a: sessao concorrente, partes e `finish` (RF-177, RF-178, RF-179, RF-181) | `lib/transfer_paralelo.sh`, `lib/state.sh` | Solicitante / secao 5.23 | Integracao | Sim (35 casos, `qa_paralelo_upload_b19`) |
| 3 | Etapa 2b: faixas `Range`, escrita ordenada, conferencia (RF-180, RF-181(f)) | `lib/download_paralelo.sh`, `dbx_http_conteudo_receber_faixa` | Solicitante / secao 5.23 | Integracao | Sim (27 casos, `qa_paralelo_download_b20`) |
| 4 | Pausa de 429 vale para o conjunto (RF-182(a), DIV-365) | `DBX_HTTP_MARCA_PAUSA`, coordenadores | Solicitante (QA-B20-01) | Integracao | Sim (cobertura nas suites b19 e b20; caso a caso nao transcrito na fonte) |
| 5 | Contrato real da sessao concorrente (RF-178, RSK-98, DIV-367) | API real, conta do solicitante | Solicitante ("Pode testar") | Contrato (manual) | Sim (teste de 2026-10-26, log de prompt) |

- Seams propostas e descartadas, com motivo: nenhuma informada na fonte.

## Evidencia do ciclo red-green-refactor

| # | Fatia vertical | Teste escrito antes? | Evidencia do Red (falha observada) | Implementacao minima | Refactor aplicado |
|---|---|---|---|---|---|
| 1 | Etapa 1: pastas com paralelismo | Sim | Casos `par20` a `par24` vermelhos antes da implementacao (fonte: Tech Lead) | `dbx_cmd_paralelo` ponto unico; sync interno recebe N | Sim (`commands/diagnostico.sh:408` corrigido na etapa 1) |
| 2 | Etapa 2a: upload em partes | Sim | Caso de debug vermelho antes de `lib/transfer_paralelo.sh` (fonte: Tech Lead; saida nao transcrita) | `lib/transfer_paralelo.sh`, registro v2 | Sim (`_dbx_state_intervalos_validos`, QA-B19-01) |
| 3 | Etapa 2b: download em faixas | Sim | Primeiro caso vermelho antes de `lib/download_paralelo.sh` (fonte: Tech Lead; saida nao transcrita) | `lib/download_paralelo.sh`, `dbx_http_conteudo_receber_faixa` | Sim (`DBX_HTTP_MARCA_PAUSA`, QA-B20-01) |

- Refatoracoes realizadas sem alteracao de comportamento externo: nao informadas na fonte.

## Execucao seletiva por modulo, local (Regra 8)

- Mapa de modulos do projeto (caminho): nao informado na fonte
- Separacao em modulos definida?: Automatica (fonte) (a confirmar)
- Arquivos do diff sem enquadramento automatico e definicao do solicitante para cada um: Nenhum (fonte)
- Suite completa executada durante a demanda, fora do push para a PR?: Nao informado na fonte
- Estrutura ou dependencia nova adicionada ao mapa nesta alteracao?: Nao informado na fonte

| Modulo | Motivo da selecao | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| Pastas (etapa 1) | Direto | `bash tests/integracao/qa_paralelo_pastas_b18_test.sh` | 10 | Nao informado na fonte | Nao informado na fonte | Nao informado na fonte |
| Upload em partes (etapa 2a) | Direto | `bash tests/integracao/qa_paralelo_upload_b19_test.sh` | 35 | Nao informado na fonte | Nao informado na fonte | Nao informado na fonte |
| Download em faixas (etapa 2b) | Direto | `bash tests/integracao/qa_paralelo_download_b20_test.sh` | 27 | Nao informado na fonte | Nao informado na fonte | Nao informado na fonte |

Contagens transcritas da fonte. A coluna de aprovados e falhos e a duracao nao constam da fonte e ficam para conferencia com o runner.

## Suite completa no push para a PR e na pipeline de main/master (Regra 8)

- Execucao local no push para a PR: `sh scripts/suite-completa.sh` no commit final. **Suite do commit final: duas execucoes reprovaram em `qa_retomada_b7a::qa_d16` (intermitente sob carga externa; passa isolado 6/6 e na sequencia curta); o solicitante decidiu ignorar a falha em 2026-10-27 (log de prompt).** Tech Lead completa.
- Branch de integracao do projeto: `master` (a confirmar; o briefing cita `develop` como principal)
- Workflow e job que rodam a suite completa: nao informado na fonte
- Estado no momento do parecer: Ainda nao executada

## Execucao por camada

- Comando oficial de execucao isolada: `bash tests/run.sh` (suite de desenvolvimento, conforme registros anteriores da branch)
- Tecnologia suporta execucao em container?: Nao informado na fonte
- Banco real da stack usado na integracao: Nao aplicavel (CLI shell, sem banco de dados)
- Ferramenta de E2E: Nao aplicavel (CLI, sem interface web)

| Camada | Comando | Total | Aprovados | Falhos | Ignorados | Nao executados por interrupcao | Duracao |
|---|---|---|---|---|---|---|---|
| Unitario | Nao informado na fonte | - | - | - | - | - | - |
| Integracao (QA da demanda) | suites `qa_paralelo_*_b18/b19/b20` | 10 + 35 + 27 = 72 | Aprovadas pelo solicitante por sha256 | Nao informado na fonte | - | - | - |
| E2E | Nao aplicavel (CLI) | - | - | - | - | - | - |

- Falhas em aberto: suite do commit final com a falha intermitente `qa_d16` ignorada por decisao do solicitante; FreeBSD do solicitante (pendente).

## Interrupcao no primeiro erro (Regra 9)

- Parada no primeiro teste falho no runner de cada camada (opcao usada): nao informado na fonte
- Execucao final concluida sem interrupcao?: Nao informado na fonte (suite do commit final pendente)

## Distribuicao da piramide

Nao informado na fonte: contagens de unitario e de integracao da suite de desenvolvimento nao foram transcritas. Os 72 casos de QA desta demanda sao de integracao.

## Verificacao das proibicoes por camada

| Verificacao | Camada | Resultado | Evidencia |
|---|---|---|---|
| Teste pela interface publica, sem metodo privado ou estado interno | Integracao | Nao informado na fonte | - |
| Ausencia de mock de camada de dados | Integracao | Nao aplicavel (sem camada de dados; estado em arquivo local) | - |
| Contrato HTTP verificado na fronteira real | Integracao | Conforme (contrato real de 2026-10-26; dobros de `curl` nas suites) | Log de prompt |

## Governanca de dados de teste

Nao aplicavel: nenhum dado de conta ou de teste persistido neste parecer. O arquivo de 40 MiB do teste de contrato foi removido ao fim, conforme o log de prompt.

## Resiliencia E2E e tratamento de flaky

Nao aplicavel: sem E2E. Instabilidade preexistente `state_trava_test::leitor_concorrente_nunca_ve_trava_vazia_ou_parcial` (RSK-DSP-01), nao atribuida a esta alteracao.

## Testes de seguranca e acesso (Regra 6 do protocolo)

- Gatilhos considerados: autenticacao | autorizacao | tenant | dado sensivel | endpoint exposto | entrada maliciosa | arquivo | rate limit | fluxo sensivel
- Gatilhos tocados pela alteracao: entrada maliciosa (campo do registro v2), arquivo (barreira do `.part` por dono, symlink e `dev:ino`), rate limit (`429`)
- Cenarios previstos na especificacao: TC-PUD-22 (SHA-256 por parte alterada), TC-PUD-24 (registro v2 corrompido, fora da regex ou com intervalo sobreposto), TC-PUD-31 (`.part` trocado por symlink ou outro inode), TC-PUD-17 (`429`)

| # | Gatilho | Cenario negativo | Ator ou entrada usada | Resultado esperado | Camada | Contra backend/banco real | Resultado |
|---|---|---|---|---|---|---|---|
| 1 | arquivo | `.part` trocado por symlink ou outro inode | Dobro de sistema de arquivos | Nada escrito; registro removido | Integracao | Nao | Nao informado na fonte (cobertura caso a caso a confirmar) |
| 2 | entrada maliciosa | Registro v2 com intervalo sobreposto | Arquivo de estado forjado | Descartado, recomeco do zero | Integracao | Nao | Corrigido (QA-B19-01); aprovado no ciclo 2 |
| 3 | rate limit | `429` em uma parte com outras em voo | Dobro de `curl` | Nenhuma parte nova durante a pausa | Integracao | Nao | Corrigido (QA-B20-01); aprovado no ciclo 2 |

- Cenarios do catalogo nao implementados para gatilho tocado, com motivo: nenhum informado na fonte.
- Resposta, log e evidencia verificados sem segredo, PII desnecessaria ou detalhe interno?: Sim (`session_id` ausente das saidas, conforme o log de prompt; conferir em `--debug`, TC-PUD-27).

## Validacao de formularios em E2E (Regra 7 do protocolo)

Nao aplicavel: a alteracao nao toca interface com entrada de dados.

## DoD bloqueante para handoff ao QA

| # | Item | Resultado | Evidencia |
|---|---|---|---|
| 1 | TDD aplicado, unidade e integracao aprovados | Atendido (red por etapa; QA aprovado por etapa) | Secao "Evidencia do ciclo" |
| 2 | Execucao isolada com o comando oficial | Nao atendido nesta rodada (suite do commit final pendente) | - |
| 3 | Cobertura E2E | Nao aplicavel (CLI) | - |
| 4 | Cenarios negativos de seguranca e acesso | Atendido parcialmente (cenarios previstos; cobertura caso a caso a confirmar) | Tabela de seguranca |
| 5 | Cenarios de formulario | Nao aplicavel | - |
| 6 | Execucao seletiva aprovada nos modulos atingidos | Nao informado na fonte | - |
| 7 | Parada no primeiro erro e execucao seletiva final sem interrupcao | Nao informado na fonte | - |

## Limitacoes do ambiente

| Recurso ausente | Impacto na verificacao | Achado registrado |
|---|---|---|
| FreeBSD 13 e 14 (somente duplos em Linux) | Comportamento de `dd`, `wait` e `stat` no sistema real nao verificado | Sim (`RSK-103`, pendencia) |
| FreeBSD 15.1 do solicitante para paralelismo | Upload e download paralelos de arquivo grande nao executados no sistema real | Sim (pendencia) |
| Suite do commit final | Regressao geral nao verificada nesta rodada | Sim (pendencia) |

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correcao esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 | `commands/diagnostico.sh:408` | Aviso citava so o sync; paralelismo agora vale tambem para upload e download | Consistencia de mensagem (RF-133(e)) | Mensagem alinhada | Menor | Corrigido (etapa 1) |
| 2 | `lib/state.sh` (registro v2) | Intervalos fora de ordem ou sobrepostos aceitos (QA-B19-01) | `RF-181(a)(e)`, `P2` | `_dbx_state_intervalos_validos`, descarte com aviso | Maior | Corrigido (ciclo 2 da QA-B19-01) |
| 3 | `lib/http.sh`, `lib/download_paralelo.sh`, `lib/transfer_paralelo.sh` | Pausa por 429 nao valia durante o `Retry-After` (QA-B20-01): coordenador despachava partes enquanto um auxiliar esperava | `RF-182(a)`, DIV-365 | Marca `DBX_HTTP_MARCA_PAUSA` criada antes da espera; coordenador nao despacha com marca | Maior | Corrigido (ciclo 2 da QA-B20-01) |
| 4 | Especificacao, DIV-365 | Texto da opcao A ("Retry-After maior vale para todos") diverge da implementacao (sem propagacao do maior `Retry-After`; efeito de pausa mantido) | Coerencia da especificacao | Nota de refinamento na DIV-365 | Menor | Aberto |
| 5 | Especificacao, secao 5.23 | Status "especificada, aguardando as decisoes; nada implementado" desatualizado | Coerencia documental | Atualizar status (documentation-sync) | Menor | Aberto |

- Total de bloqueantes: 0
- Total de maiores: 2 (ambos corrigidos e aprovados no ciclo 2 pelo solicitante)
- Total de menores: 3 (1 corrigido; 2 abertos, documentais)

## Achados do ciclo anterior

Ciclo 1 das suites de QA `qa_paralelo_upload_b19` e `qa_paralelo_download_b20`:

| # do ciclo anterior | Achado | Status atual | Evidencia da correcao |
|---|---|---|---|
| QA-B19-01 | Intervalos do registro v2 fora de ordem ou sobrepostos aceitos | Corrigido | `_dbx_state_intervalos_validos`; aprovacao por sha256 `96fe8d65...` |
| QA-B20-01 | Pausa por 429 nao valia para o coordenador | Corrigido | `DBX_HTTP_MARCA_PAUSA` nos dois sentidos; aprovacao por sha256 `efbdda63...` |

## Veredito

- Resultado: Aprovado com ressalvas (veredito proposto por este parecer; confirmar pelo Tech Lead)
- Justificativa objetiva: QA independente aprovado pelo solicitante por etapa, com red medido e os dois achados Maiores corrigidos; a suite do commit final e a validacao no FreeBSD do solicitante estao pendentes.
- Ressalvas registradas, com owner e prazo:
  - Suite do commit final (`sh scripts/suite-completa.sh`): owner Tech Lead; prazo antes do merge.
  - Validacao no FreeBSD do solicitante (upload e download paralelos de arquivo grande): owner solicitante.
  - FreeBSD 13 e 14: sem sistema real; owner solicitante.
  - Nota de refinamento da DIV-365 e status da secao 5.23: owner Tech Lead / documentation-sync.
- Handoff liberado?: Sim, para revisao do Tech Lead; merge condicionado a suite do commit final
- Gate de conformidade liberado para execucao?: Sim

## Registro

- Decisoes de QA (aprovacoes por sha256) estao no log de prompt, no lugar de entrada de aceite em `.github/agents/memoria/entradas/`; criar entrada se o Tech Lead exigir (regra 35).
- Referenciado pelo [registro de entrega](2026-10-26-1900-registro-paralelo-upload-download.md) e pelo [parecer de conformidade](2026-10-26-1900-parecer-conformidade-paralelo-upload-download.md).
