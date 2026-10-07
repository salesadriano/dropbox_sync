# Template - Parecer de Evidencias de Testes (TDD)

Preenchido pelo agent que produziu a alteracao, conforme `../skills/protocolo-tdd/`, antes de qualquer handoff.

> **Modo do parecer (regra 40 e `Protocolo por porte` do `AGENTS.md`):** em porte **P** e **M**, preencher apenas Identificacao, Escopo, Criterios e seams acordadas, Execucao por camada, Interrupcao no primeiro erro, Achados, Veredito e, se reprovado, Devolucao; substituir as tabelas de verificacao pela linha `Checklist protocolo-tdd aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados`. As secoes `Testes de seguranca e acesso` e `Validacao de formularios em E2E` nunca sao compactadas: com gatilho ou formulario tocado, um cenario por linha em qualquer porte. Em porte **G**, preencher todas as secoes. Secao sem conteudo e omitida com `Nao aplicavel: <motivo>`, nunca preenchida com placeholders.

## Identificacao

- Projeto ou produto:
- Agent responsavel pela alteracao:
- Agent responsavel pela verificacao:
- Data da verificacao:
- Ciclo de verificacao: 1 | 2 | 3 | escalonado ao Tech Lead
- Tipo de alteracao: Implementacao nova | Refatoracao | Correcao de defeito | Ajuste pontual
- Execucao dos gates: local, sem pipeline (suite completa e da pipeline de `main`/`master`, Regra 8)
- Porte da demanda: P | M | G
- Modo do parecer: Compacto | Completo

## Escopo verificado

- Comando usado para levantar o diff:
- Base de comparacao (quando aplicavel):

| Arquivo | Tipo de alteracao | Camada / modulo | Coberto por teste |
|---|---|---|---|
|  | Novo / Alterado / Removido |  | Sim / Nao |

- Comportamento alterado e nao verificado, com motivo:

## Criterios e seams acordadas

| # | Criterio BDD / criterio de aceite | Seam sob teste | Origem do acordo | Camada do teste | Coberto |
|---|---|---|---|---|---|
| 1 |  |  | Solicitante / System Design | Unitario / Integracao / E2E | Sim / Nao |

- Seams propostas e descartadas, com motivo:

## Evidencia do ciclo red-green-refactor

| # | Fatia vertical | Teste escrito antes? | Evidencia do Red (falha observada) | Implementacao minima | Refactor aplicado |
|---|---|---|---|---|---|
| 1 |  | Sim / Nao |  |  | Sim / Nao / Nao aplicavel |

- Refatoracoes realizadas sem alteracao de comportamento externo:

## Execucao seletiva por modulo, local (Regra 8)

- Mapa de modulos do projeto (caminho):
- Separacao em modulos definida?: Automatica (fonte) | Pelo solicitante (log de prompt) | Aguardando definicao do solicitante (selecao sem mapa: testes do diff e relacionados pelo runner, ou definidos pelo solicitante)
- Arquivos do diff sem enquadramento automatico e definicao do solicitante para cada um (log de prompt): | Nenhum
- Modulos atingidos diretamente pelo diff:
- Dependentes diretos incluidos, conforme o mapa:
- Suite completa executada fora da pipeline?: Nao | Sim, por pedido explicito do solicitante (log de prompt) | Sim, sem pedido (achado Maior)
- Estrutura ou dependencia nova adicionada ao mapa nesta alteracao?: Sim (qual, com origem automatica ou do solicitante) | Nao | Nao aplicavel

| Modulo | Motivo da selecao (direto / dependente de ...) | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |

## Suite completa na pipeline de main/master (Regra 8)

Nao roda localmente: e a pipeline que a executa, no PR e no push ou merge para a branch de integracao. Esta secao registra a referencia da execucao, nao uma execucao do agent.

- Branch de integracao do projeto: `main` | `master`
- Workflow e job que rodam a suite completa:
- Eventos configurados (PR e push/merge para a branch de integracao)?: Sim | Nao (achado Maior, com owner e prazo)
- Ordem do job (checkout do estado integrado, dependencias e runner fixados, ambiente, gates rapidos, suite completa, demais steps apos a suite verde)?: Sim | Nao (achado Maior; publicacao ou deploy sem a suite verde e Bloqueante)
- Estado no momento do parecer: Verde | Vermelha | Ainda nao executada (PR para a branch de integracao nao aberto)
- Execucao referenciada (commit, evento, link ou id da run):

Preencher apenas em falha, uma linha por execucao interrompida (a pipeline para no primeiro erro; Regra 9):

| Modulo que interrompeu a execucao | Estava no escopo selecionado? | Classificacao | Devolvido ao Tech Lead em | Agent designado | Correcao do mapa necessaria? |
|---|---|---|---|---|---|
|  | Sim / Nao | Falha de implementacao / Regressao fora do escopo |  |  | Sim / Nao |

## Execucao por camada

- Comando oficial de execucao isolada definido pelo projeto (ex.: `docker compose run --rm <service> test`):
- Tecnologia suporta execucao em container?: Sim | Nao (motivo)
- Comando efetivamente executado:
- Divergencia em relacao ao comando oficial, com motivo:
- Banco real da stack usado na integracao (tecnologia e forma de provisionamento):
- Ferramenta de E2E: Cypress | outra (motivo: projeto nao suporta Cypress)

| Camada | Comando | Total | Aprovados | Falhos | Ignorados | Nao executados por interrupcao | Duracao |
|---|---|---|---|---|---|---|---|
| Unitario |  |  |  |  |  |  |  |
| Integracao |  |  |  |  |  |  |  |
| E2E |  |  |  |  |  |  |  |

- Falhas em aberto:

## Interrupcao no primeiro erro (Regra 9)

- Parada no primeiro teste falho no runner de cada camada (opcao usada):
- Modulos e camadas em sequencia (unitario, integracao, E2E), sem iniciar o seguinte apos erro?: Sim | Nao
- Codigo de saida propagado ate o fim, sem `|| true`, `set +e`, `continue-on-error` ou pipe que o perca?: Sim | Nao
- Job da pipeline: passos de teste sequenciais, matriz com `fail-fast: true` e passo de reporte com `if: failure()`?: Sim | Nao | Sem job (achado Maior da Regra 8)
- Execucao final concluida sem interrupcao?: Sim | Nao

Preencher apenas se houve interrupcao, uma linha por execucao interrompida, na ordem em que ocorreram:

| # | Camada | Modulo | Teste | Arquivo:linha | Tipo de erro | Mensagem (sanitizada) | Comando | Nao executados | Correcao e reexecucao do inicio |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Unitario / Integracao / E2E |  |  |  | Assercao / Setup-hook / Timeout / Compilacao-coleta / Infraestrutura de teste / Zero testes |  |  |  |  |

## Distribuicao da piramide

Alvo 70/20/10 (Regra 2). Desvio justificado e aceito nao e achado; desvio sem justificativa e achado Maior.

| Camada | Alvo | Real entregue | Desvio justificado? | Justificativa |
|---|---|---|---|---|
| Unitario | 70% |  | Sim / Nao / Nao aplicavel |  |
| Integracao | 20% |  |  |  |
| E2E | 10% |  |  |  |

## Verificacao das proibicoes por camada

| Verificacao | Camada | Resultado | Evidencia |
|---|---|---|---|
| Teste unitario isolado de rede e banco | Unitario | Conforme / Nao conforme / Nao aplicavel |  |
| Teste pela interface publica, sem metodo privado ou estado interno | Unitario |  |  |
| Padrao AAA e nome que descreve comportamento | Unitario |  |  |
| Banco real via Testcontainers para repositorio/DAO | Integracao |  |  |
| Ausencia de mock da camada de dados | Integracao |  |  |
| Contrato HTTP verificado na fronteira real | Integracao |  |  |
| Fluxo principal contra frontend, backend e banco reais | E2E |  |  |
| Ausencia de `cy.intercept()` com fixture/stub no fluxo principal | E2E |  |  |
| Jornada de negocio completa, sem smoke superficial | E2E |  |  |
| Cada criterio BDD acordado com cenario correspondente | E2E |  |  |

## Governanca de dados de teste

| Item | Resultado | Evidencia |
|---|---|---|
| Dado originado de seeder padrao ou criacao programatica |  |  |
| Ausencia de dado manual e de ID adivinhado |  |  |
| Estado preservado entre cenarios relacionados |  |  |
| Teardown apenas ao final do roteiro completo |  |  |
| Dado de teste sintetico, sem segredo, credencial ou dado pessoal real |  |  |

## Resiliencia E2E e tratamento de flaky

| Item | Resultado | Evidencia |
|---|---|---|
| Seletores `data-cy`/`data-test` nos elementos interativos |  |  |
| Ausencia de seletor por classe de estilo como estrategia principal |  |  |

Preencher apenas se houve instabilidade observada.

| Cenario | Execucoes (resultado de cada uma) | Causa raiz identificada | Correcao aplicada | Status |
|---|---|---|---|---|
|  |  |  |  | Corrigido / Em aberto |

- Houve `sleep` fixo, retry cego ou quarentena para estabilizar?: Sim | Nao
- Se sim, registrar como achado bloqueante na secao seguinte.

## Testes de seguranca e acesso (Regra 6 do protocolo)

- Gatilhos considerados: autenticacao | autorizacao | tenant | dado sensivel | endpoint exposto | entrada maliciosa | arquivo | rate limit | fluxo sensivel
- Gatilhos tocados pela alteracao:
- Se nenhum: `Nao aplicavel: nenhum gatilho da Regra 6 tocado` e encerrar a secao.

| # | Gatilho | Cenario negativo | Ator ou entrada usada | Resultado esperado (codigo, corpo, sem efeito colateral) | Camada | Contra backend/banco real | Resultado |
|---|---|---|---|---|---|---|---|
| 1 |  |  |  |  | Integracao / E2E | Sim / Nao | Aprovado / Falhou |

- Cenarios do catalogo nao implementados para gatilho tocado, com motivo (cada um e achado bloqueante):
- Resposta, log e evidencia verificados sem segredo, PII desnecessaria ou detalhe interno?: Sim | Nao

## Validacao de formularios em E2E (Regra 7 do protocolo)

- Formularios ou grupos de campos tocados pela alteracao:
- Se nenhum: `Nao aplicavel: a alteracao nao toca interface com entrada de dados` e encerrar a secao.

| # | Formulario | Cenario | Campo(s) e valor usado | Resultado esperado (bloqueio, mensagem, campo apontado, nada persistido) | Seletor do erro | Resultado |
|---|---|---|---|---|---|---|
| 1 |  | Obrigatorios vazios / Valor indevido por tipo / Valor indevido por regra / Feedback visual / Estado apos erro / Correcao e reenvio |  |  | `data-cy=...` |  |

- Campos obrigatorios do formulario e quais foram cobertos:
- Campos tipados (numero, moeda, data, e-mail, documento, select) e quais receberam valor indevido:
- Mensagens esperadas vieram do Design System ou do criterio de aceite?: Sim | Nao
- Rejeicao equivalente provada no backend (Regra 6, entrada fora do schema)?: Sim | Nao | Nao aplicavel

## DoD bloqueante para handoff ao QA

| # | Item | Resultado | Evidencia |
|---|---|---|---|
| 1 | TDD aplicado, unidade e integracao aprovados | Atendido / Nao atendido |  |
| 2 | Execucao isolada com o comando oficial do projeto (em container quando a tecnologia suportar) | Atendido / Nao atendido |  |
| 3 | Cobertura E2E dos criterios BDD contra base real de homologacao | Atendido / Nao atendido |  |
| 4 | Cenarios negativos de seguranca e acesso executados e aprovados quando houver gatilho | Atendido / Nao atendido / Nao aplicavel |  |
| 5 | Cenarios de formulario (obrigatorios, valor indevido, feedback visual) executados e aprovados quando houver interface com entrada | Atendido / Nao atendido / Nao aplicavel |  |
| 6 | Execucao seletiva aprovada nos modulos atingidos e dependentes diretos (suite completa nao e item deste DoD: condiciona o merge, na pipeline) | Atendido / Nao atendido |  |
| 7 | Parada no primeiro erro configurada no local e na pipeline, com reporte, e execucao seletiva final sem interrupcao (Regra 9) | Atendido / Nao atendido |  |

## Limitacoes do ambiente

| Recurso ausente | Impacto na verificacao | Achado registrado |
|---|---|---|
| Testcontainers / runner E2E / seeder / comando oficial |  | Sim / Nao |

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correcao esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 |  |  | `protocolo-tdd / Regra <n> - <titulo>` |  | Bloqueante / Maior / Menor | Aberto / Corrigido / Justificado |

- Total de bloqueantes:
- Total de maiores:
- Total de menores:

## Achados do ciclo anterior

Preencher a partir do ciclo 2.

| # do ciclo anterior | Achado | Status atual | Evidencia da correcao |
|---|---|---|---|
|  |  | Corrigido / Nao corrigido / Justificado |  |

## Veredito

- Resultado: Aprovado | Aprovado com ressalvas | Reprovado
- Justificativa objetiva:
- Ressalvas registradas, com owner e prazo:
- Handoff liberado?: Sim | Nao
- Gate de conformidade liberado para execucao?: Sim | Nao
- Proximo passo do ciclo do developer:

## Devolucao ao agent (preencher apenas se Reprovado)

| # | Arquivo:linha | Achado | Regra violada | Correcao esperada | Severidade |
|---|---|---|---|---|---|
|  |  |  |  |  |  |

- Agent destinatario:
- Acao requerida: corrigir os itens acima e reexecutar `protocolo-tdd` antes de qualquer handoff.
- Reincidencia de achado ja apontado?: Sim | Nao
- Escalonamento ao Tech Lead necessario?: Sim | Nao

## Registro

- Quando houver decisao duravel ou justificativa aceita, gravar uma entrada em `../memoria/entradas/` (`escopo: projeto`, ou `pacote` se mudar regra transversal) com `ref:` para este parecer (regra 35).
- Referenciar este parecer no registro tecnico produzido por `../skills/review-documentation/` e no parecer de `../skills/protocolo-conformidade/`.
