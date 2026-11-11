# Parecer de Evidencias de Testes (TDD) - protocolo atual 1.3.1

> **Modo do parecer:** Completo (porte G).

## Identificacao

- Projeto ou produto: dropbox_api (CLI)
- Agent responsavel pela alteracao: Tech Lead
- Agent responsavel pela verificacao: `ai-team:protocolo-tdd` (verificacao por QA independente: `ai-team:qa-expert`)
- Data da verificacao: 2026-11-11
- Ciclo de verificacao: 1
- Tipo de alteracao: Ajuste pontual (sincronizacao de protocolo e adaptacoes de scripts; sem codigo de produto)
- Execucao dos gates: local, sem pipeline (suite completa local antes do push da PR para `develop`, pelo comando oficial `sh scripts/suite-completa.sh`; o projeto nao tem pipeline, `.github/workflows/` ausente)
- Porte da demanda: G
- Modo do parecer: Completo

## Escopo verificado

- Comando usado para levantar o diff: `git status` e `git diff --stat origin/develop...HEAD` no worktree `chore-protocolo-atual-1-3-1`
- Base de comparacao: `origin/develop` @ `0d632e7`; modelo `433ed67` (base) para `a9d585e` (plugin 1.3.1)

| Arquivo | Tipo de alteracao | Camada / modulo | Coberto por teste |
|---|---|---|---|
| `scripts/inventario-de-testes.sh` | Alterado (adaptacao a) | Scripts do protocolo | Sim |
| `scripts/auditar-casos.sh` | Novo (adaptacao b) | Scripts do protocolo | Sim |
| `scripts/tests/qa-inventario-funcao-shell.bats` | Alterado (invertido para o projeto) | Testes do protocolo | Sim |
| `scripts/tests/auditar-casos-harness-do-projeto.bats` | Novo (Tech Lead) | Testes do protocolo | Sim |
| `scripts/tests/qa-auditar-casos-harness-do-projeto.bats` | Novo (QA) | Testes do protocolo | Sim |
| `scripts/tests/suite-completa-wrapper.bats` | Alterado (adaptacao c) | Testes do protocolo | Sim |
| `tests/integracao/qa_debug_transferencias_b12_test.sh` | Alterado (caso inerte removido) | Testes de produto | Sim |
| Demais scripts, Bats e templates sincronizados do modelo | Alterado / Novo | Scripts e templates do protocolo | Sim (Bats do modelo e do projeto) |

- Comportamento alterado e nao verificado, com motivo: nenhum. Os Bats do modelo que leem commits, settings de exemplo ou `hooks.json` do pacote nao foram trazidos (motivo: dependem de arquivos que so existem no repositorio do pacote); a cobertura deles nao e substituida neste repositorio.

## Criterios e seams acordadas

| # | Criterio BDD / criterio de aceite | Seam sob teste | Origem do acordo | Camada do teste | Coberto |
|---|---|---|---|---|---|
| 1 | Adaptacao (a): nome da funcao shell no inicio da linha vale antes das strings no inventario | `scripts/inventario-de-testes.sh` | Tech Lead / issue `ai_team#60` | Unitario (Bats) | Sim |
| 2 | Adaptacao (b): `_harness_falhar` e assercao direta; `VAR=valor` e braco de `case` nao impedem o reconhecimento | `scripts/auditar-casos.sh` | Tech Lead | Unitario (Bats) | Sim |
| 3 | Caso inerte real removido sem perda de cobertura | `tests/integracao/qa_debug_transferencias_b12_test.sh` e `tests/integracao/retomada_download_test.sh` | Solicitante ("Corrigir neste PR") | Integracao | Sim |
| 4 | Inventario sem divergencia | `scripts/inventario-de-testes.sh --check` | Regra 51 | Meta | Sim |

- Seams propostas e descartadas, com motivo: uso direto de `auditar-casos.sh` contra o repositorio inteiro como teste unitario, descartado por custo; a cobertura foi dividida entre os Bats de adaptacao e a execucao da auditoria no repositorio.

## Evidencia do ciclo red-green-refactor

| # | Fatia vertical | Teste escrito antes? | Evidencia do Red (falha observada) | Implementacao minima | Refactor aplicado |
|---|---|---|---|---|---|
| 1 | Adaptacao (b): `auditar-casos-harness-do-projeto.bats` | Sim | Contra o script do modelo: 4 `not ok` de 7 | Adaptacao (b) em `scripts/auditar-casos.sh` | Sim |
| 2 | Adaptacao (a): `qa-inventario-funcao-shell.bats` invertido para o projeto | Sim | Caso "aspas prevalecem" falha com a precedencia do modelo | Precedencia da funcao shell em `scripts/inventario-de-testes.sh` | Nao aplicavel |
| 3 | Fronteira de palavra (achado do QA): `_harness_falhar_x` e `afirmarX` | Sim | Aceitos pelo script antes da correcao (QA) | Fronteira de palavra em `scripts/auditar-casos.sh:338` | Nao aplicavel |

- Refatoracoes realizadas sem alteracao de comportamento externo: nenhuma.

## Execucao seletiva por modulo, local (Regra 8)

- Mapa de modulos do projeto (caminho): `docs/testes/mapa-modulos.md` e o inventario `docs/testes/inventario-de-testes.md`; os Bats de `scripts/tests/` sao do protocolo e ficam fora do mapa
- Separacao em modulos definida?: Automatica (fonte)
- Arquivos do diff sem enquadramento automatico e definicao do solicitante para cada um (log de prompt): Nenhum
- Suite completa executada durante a demanda, fora do push para a PR?: Nao
- Estrutura ou dependencia nova adicionada ao mapa nesta alteracao?: Nao

| Modulo | Motivo da selecao | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| Scripts e skills (Bats) | Direto (scripts do protocolo) | Bats sobre `scripts/tests/` | 705 | 705 | 0 | Nao registrada |
| Auditoria (Bats, 4 arquivos) | Direto (`auditar-casos.sh`) | Bats sobre os 4 arquivos da auditoria | 66 | 66 | 0 | Nao registrada |
| Caso removido (integracao) | Direto (`qa_debug_transferencias_b12_test.sh`) | `bash tests/run.sh qa_debug_transferencias_b12_test.sh` | Nao registrado | APROVADA | Nao registrada | Nao registrada |
| Retomada de download (integracao) | Dependente direto (cobertura equivalente) | `tests/integracao/retomada_download_test.sh` | 32 | 32 | 0 | Nao registrada |

Nota: o total do caso removido nao foi transcrito do runner; o resultado registrado e o veredito do runner (`APROVADA`).

## Suite completa no push para a PR e na pipeline de main/master (Regra 8)

- Execucao local antes do envio para a PR: `sh scripts/suite-completa.sh` (`bash tests/run.sh`) sobre `d734f3b`, arvore limpa: 126 arquivos, 3040 aprovados, 0 reprovados, 3 pulados, APROVADA, 3525 s, registrada em 2026-11-11T20:45:52Z (`--conferir` = 0).
- Branch de integracao do projeto: `develop` (branch principal declarada; releases vao a `master`)
- Workflow e job que rodam a suite completa: Nao aplicavel: o projeto nao tem pipeline (`.github/workflows/` ausente); vale a execucao local registrada no registro de entrega
- Eventos configurados (PR e push/merge para a branch de integracao)?: Nao aplicavel nesta etapa (verificacao local; pipeline roda no PR)
- Ordem do job (checkout do estado integrado, dependencias e runner fixados, ambiente, gates rapidos, suite completa, demais steps apos a suite verde)?: Nao aplicavel nesta etapa
- Estado no momento do parecer: Ainda nao executada (PR para a branch de integracao nao aberto)
- Execucao referenciada: nenhuma ainda

Falhas de execucao interrompida: Nao aplicavel: nenhuma execucao interrompida nesta etapa.

## Execucao por camada

- Comando oficial de execucao isolada definido pelo projeto: `bash tests/run.sh <arquivo>` (CLI sem container)
- Tecnologia suporta execucao em container?: Nao (motivo: CLI em shell, sem servico)
- Comando efetivamente executado: Bats sobre `scripts/tests/`; Bats sobre os 4 arquivos da auditoria; `sh scripts/inventario-de-testes.sh --check`; `bash tests/run.sh qa_debug_transferencias_b12_test.sh`; `tests/integracao/retomada_download_test.sh`
- Divergencia em relacao ao comando oficial, com motivo: Bats executado diretamente por ser o runner dos scripts do protocolo
- Banco real da stack usado na integracao: Nao aplicavel (CLI sem banco)
- Ferramenta de E2E: Nao aplicavel (projeto sem interface)

| Camada | Comando | Total | Aprovados | Falhos | Ignorados | Nao executados por interrupcao | Duracao |
|---|---|---|---|---|---|---|---|
| Unitario (Bats de scripts) | Bats sobre `scripts/tests/` | 705 | 705 | 0 | Nao registrado | 0 | Nao registrada |
| Unitario (Bats da auditoria) | Bats sobre os 4 arquivos | 66 | 66 | 0 | Nao registrado | 0 | Nao registrada |
| Integracao | `tests/integracao/retomada_download_test.sh` | 32 | 32 | 0 | Nao registrado | 0 | Nao registrada |
| Integracao (caso removido) | `bash tests/run.sh qa_debug_transferencias_b12_test.sh` | Nao registrado | APROVADA | Nao registrado | Nao registrado | 0 | Nao registrada |
| E2E | Nao aplicavel | - | - | - | - | - | - |

- Falhas em aberto: nenhuma nesta etapa.

## Interrupcao no primeiro erro (Regra 9)

- Parada no primeiro teste falho no runner de cada camada (opcao usada): padrao do runner Bats e de `tests/run.sh`
- Modulos e camadas em sequencia (unitario, integracao, E2E), sem iniciar o seguinte apos erro?: Sim
- Codigo de saida propagado ate o fim, sem `|| true`, `set +e`, `continue-on-error` ou pipe que o perca?: Sim
- Job da pipeline: passos de teste sequenciais, matriz com `fail-fast: true` e passo de reporte com `if: failure()`?: Nao aplicavel nesta etapa (sem pipeline local)
- Execucao final concluida sem interrupcao?: Sim

Nao houve interrupcao nas execucoes registradas.

## Distribuicao da piramide

| Camada | Alvo | Real entregue | Desvio justificado? | Justificativa |
|---|---|---|---|---|
| Unitario | 70% | Bats de scripts (771 casos) | Nao aplicavel | Alteracao sem codigo de produto; piramide do produto nao se altera |
| Integracao | 20% | Caso removido e retomada (32) | Nao aplicavel | Idem |
| E2E | 10% | Nao aplicavel (projeto sem interface) | Nao aplicavel | Projeto sem interface |

## Verificacao das proibicoes por camada

| Verificacao | Camada | Resultado | Evidencia |
|---|---|---|---|
| Teste unitario isolado de rede e banco | Unitario | Conforme | Bats de scripts operam sobre arquivos temporarios e shell |
| Teste pela interface publica, sem metodo privado ou estado interno | Unitario | Conforme | Testes chamam os scripts pela linha de comando |
| Padrao AAA e nome que descreve comportamento | Unitario | Conforme | Nomes dos casos descrevem o comportamento (`qa-auditar-casos-harness-do-projeto.bats`) |
| Banco real via Testcontainers para repositorio/DAO | Integracao | Nao aplicavel | Sem repositorio/DAO |
| Ausencia de mock da camada de dados | Integracao | Nao aplicavel | Sem camada de dados |
| Contrato HTTP verificado na fronteira real | Integracao | Nao aplicavel | Sem HTTP na alteracao |
| Fluxo principal contra frontend, backend e banco reais | E2E | Nao aplicavel | Sem interface |
| Ausencia de `cy.intercept()` com fixture/stub no fluxo principal | E2E | Nao aplicavel | Sem interface |
| Jornada de negocio completa, sem smoke superficial | E2E | Nao aplicavel | Sem interface |
| Cada criterio BDD acordado com cenario correspondente | E2E | Nao aplicavel | Sem interface; criterios 1 a 4 cobertos por Bats e integracao |

## Governanca de dados de teste

| Item | Resultado | Evidencia |
|---|---|---|
| Dado originado de seeder padrao ou criacao programatica | Conforme | Arquivos temporarios criados pelos proprios testes |
| Ausencia de dado manual e de ID adivinhado | Conforme | Sem dado manual nos Bats |
| Estado preservado entre cenarios relacionados | Nao aplicavel | Cenarios independentes |
| Teardown apenas ao final do roteiro completo | Conforme | Limpeza de temporarios pelos proprios testes |
| Dado de teste sintetico, sem segredo, credencial ou dado pessoal real | Conforme | Dados sinteticos nos fixtures |

## Resiliencia E2E e tratamento de flaky

Nao aplicavel: sem E2E no projeto e sem instabilidade observada nesta etapa. A retomada de download sob carga ja e conhecida e nao foi alterada por esta demanda.

## Testes de seguranca e acesso (Regra 6 do protocolo)

- Gatilhos considerados: autenticacao | autorizacao | tenant | dado sensivel | endpoint exposto | entrada maliciosa | arquivo | rate limit | fluxo sensivel
- Gatilhos tocados pela alteracao: nenhum gatilho do produto. Os scripts de guarda de comandos e de autorizacao de sessao sao protocolo do agente, nao produto; a permissao `deny` para push com force foi mantida.
- Nao aplicavel: nenhum gatilho da Regra 6 tocado no produto (sem autenticacao, endpoint, tenant ou dado sensivel na entrega).

- Cenarios do catalogo nao implementados para gatilho tocado: Nao aplicavel
- Resposta, log e evidencia verificados sem segredo, PII desnecessaria ou detalhe interno?: Sim

## Validacao de formularios em E2E (Regra 7 do protocolo)

Nao aplicavel: a alteracao nao toca interface com entrada de dados.

## DoD bloqueante para handoff ao QA

| # | Item | Resultado | Evidencia |
|---|---|---|---|
| 1 | TDD aplicado, unidade e integracao aprovados | Atendido | Red-green registrado; Bats 705/705, 66/66 e integracao 32/32 |
| 2 | Execucao isolada com o comando oficial do projeto (em container quando a tecnologia suportar) | Atendido | `bash tests/run.sh` (CLI sem container) |
| 3 | Cobertura E2E dos criterios BDD contra base real de homologacao | Nao aplicavel | Projeto sem interface |
| 4 | Cenarios negativos de seguranca e acesso executados e aprovados quando houver gatilho | Nao aplicavel | Sem gatilho no produto |
| 5 | Cenarios de formulario executados e aprovados quando houver interface com entrada | Nao aplicavel | Sem interface |
| 6 | Execucao seletiva aprovada nos modulos atingidos e dependentes diretos | Atendido | Tabela de execucao seletiva acima |
| 7 | Parada no primeiro erro configurada no local e na pipeline, com reporte, e execucao seletiva final sem interrupcao (Regra 9) | Atendido | Padrao do runner; execucao final sem interrupcao |

## Limitacoes do ambiente

| Recurso ausente | Impacto na verificacao | Achado registrado |
|---|---|---|
| Testcontainers / runner E2E / seeder | Nao aplicavel (CLI sem servico) | Nao |
| Suite completa local | Verde: 3040 aprovados, 0 reprovados, 3 pulados (126 arquivos, 3525 s, `d734f3b`) | Sim |

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correcao esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 | `scripts/auditar-casos.sh:338` | `_harness_falhar_x` e `afirmarX` aceitos por falta de fronteira de palavra (achado do QA) | `protocolo-tdd / Regra 1` | Fronteira de palavra | Menor | Corrigido |
| 2 | `scripts/auditar-casos.sh` (`VAR=$(cmd arg)` antes de assercao) | Falso positivo ainda possivel; lado seguro (acusa a mais) | `protocolo-tdd / Regra 1` | Tratar em demanda propria | Menor | Justificado |
| 3 | `docs/reviews/` (suite completa) | Suite completa local ainda nao anexada | `protocolo-tdd / Regra 8 - Suite completa` | Anexar antes do envio | Menor | Corrigido (suite verde registrada antes do envio) |

- Total de bloqueantes: 0
- Total de maiores: 0
- Total de menores: 3 (1 corrigido, 1 justificado, 1 aberto ate o push)

## Achados do ciclo anterior

Nao aplicavel: ciclo 1.

## Veredito

- Resultado: Aprovado
- Justificativa objetiva: red-green comprovado para a adaptacao (b); adaptacao (a) coberta pelo caso invertido e pelo `--check` sem divergencia; achado do QA corrigido com 11/11 verdes; caso inerte removido com cobertura equivalente; sem codigo de produto alterado; Regra 6 nao aplicavel.
- Ressalvas registradas, com owner e prazo: nenhuma aberta; a suite completa local foi registrada verde antes do envio.
- Handoff liberado?: Sim
- Gate de conformidade liberado para execucao?: Sim
- Proximo passo do ciclo do developer: nenhum; PR #109 mesclada.

## Devolucao ao agent (preencher apenas se Reprovado)

Nao aplicavel: parecer aprovado.

## Registro

- Entrada de aceite na memoria: `2026-11-11-1413-aceite-testes-qa-protocolo-1-3-1` (ref: este parecer).
- Referenciado no registro tecnico `docs/reviews/2026-11-11-1413-registro-protocolo-atual-1-3-1.md` e no parecer de `protocolo-conformidade`.
