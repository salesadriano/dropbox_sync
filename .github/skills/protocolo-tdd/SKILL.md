---
name: protocolo-tdd
description: "Protocolo obrigatorio de engenharia de testes com TDD, integracao contra instancia real do banco da stack via Testcontainers e E2E real com Cypress (ou tecnologia similar quando o projeto nao o suportar) sem mocks de rede. Deve ser acionado obrigatoriamente sempre que a tarefa envolver desenvolvimento, refatoracao ou correcao de codigo. Conduz o ciclo red-green-refactor, verifica a piramide 70/20/10, a governanca de dados de teste e a resiliencia do E2E, e emite um parecer de evidencias com achados classificados por severidade. Achado bloqueante reprova a entrega e a devolve ao agent originador. O gate local roda com execucao seletiva pelos modulos atingidos, sem depender de pipeline, CI, workflow ou qualquer execucao remota; os testes executados durante a demanda cobrem apenas os itens afetados pelas alteracoes; a suite completa de regressao roda apenas na pipeline, em PR e no push ou merge para main ou master, ou quando o solicitante a pedir explicitamente, logo apos os passos de preparo e antes dos demais steps do projeto, e condiciona o merge, nunca o handoff local. Em ambas, a execucao de testes e configurada para parar no primeiro erro e reportar esse erro ao dono da correcao."
---

# Protocolo de Engenharia de Testes (TDD)

## Security Handoff

Esta skill nao substitui hardening de seguranca.

- Se o trabalho tocar autenticacao, autorizacao, segredos, dados sensiveis, sessao/cookies, CSP/CORS ou exposicao de API, aplicar tambem `security-best-practices` e `api-security-best-practices` como fonte das regras, e a Regra 6 deste protocolo como exigencia de **testes** que provem essas regras.
- Nunca incluir segredos, tokens, credenciais ou chaves privadas em exemplos, fixtures, seeders, diagramas, logs, evidencias ou artefatos gerados. Dado de teste deve ser sintetico.
- Evidencia copiada de ambiente real deve ser sanitizada antes de ser persistida no parecer.

## Scope Boundary

Esta skill e o gate de **testes** da entrega: responde se o comportamento esta provado por testes reais.

- [`protocolo-conformidade`](../protocolo-conformidade/SKILL.md) e o gate de **arquitetura e boas praticas**, obrigatorio e independente deste. Aquele verifica como o codigo foi construido; este verifica se o comportamento foi provado. Reprovacao em qualquer um bloqueia o handoff, e nenhum substitui o outro.
- [`tdd-test-design`](../tdd-test-design/SKILL.md) e a referencia de apoio dentro do ciclo red-green, para decidir o que cada teste afirma e em qual seam. Em caso de conflito, `protocolo-tdd` prevalece.
- [`testing-strategy`](../testing-strategy/SKILL.md) e para desenho conceitual de plano e cobertura quando nao ha alteracao de codigo.
- Skills de stack com conteudo de teste (por exemplo [`django-tdd`](../django-tdd/SKILL.md), `fastapi-expert`, `nestjs-best-practices`, `fastify-best-practices`, [`bats-testing-patterns`](../bats-testing-patterns/SKILL.md)) fornecem a **mecanica da ferramenta** na stack detectada. O **protocolo de entrega** e este, e prevalece sobre qualquer default dessas skills, inclusive quando elas sugerirem banco em memoria, SQLite de teste ou mock de repositorio, ou comando de teste que continua apos o primeiro erro (Regra 9).
- [`security-best-practices`](../security-best-practices/SKILL.md) e [`api-security-best-practices`](../api-security-best-practices/SKILL.md) dizem **o que** deve estar protegido. Este protocolo exige que isso seja **provado por teste** (Regra 6): cenarios negativos de acesso, isolamento e entrada maliciosa, contra backend e banco reais.
- [`review-documentation`](../review-documentation/SKILL.md) registra a entrega. Esta skill produz a evidencia de testes que alimenta esse registro, mas nao o substitui.
- A validacao funcional independente continua sendo do QA Expert, com suite propria. Este protocolo e precondicao dessa validacao, nao substituto dela.

## Objetivo

Padronizar a engenharia de testes com foco em confiabilidade real de ambiente, garantindo que desenvolvimento, QA e aprovacao final usem as mesmas regras operacionais de TDD, integracao e E2E, e que a conclusao do gate seja um veredito verificavel, nao uma declaracao de intencao.

## Regra de acionamento obrigatorio

Esta skill deve ser usada obrigatoriamente sempre que a tarefa envolver qualquer uma das situacoes abaixo:

- desenvolvimento de codigo novo
- refatoracao de codigo existente
- correcao de defeitos ou bugs em codigo
- ajuste pontual de codigo, por menor que seja

Essa obrigatoriedade vale mesmo quando a solicitacao do usuario nao mencionar testes explicitamente. Nesses casos, o protocolo TDD continua sendo a referencia operacional padrao para orientar implementacao, validacao e handoff.

## Execucao local e execucao na pipeline

Gate local, nos termos da regra 16 do `AGENTS.md`: roda no ambiente do agent sobre alteracoes locais, inclusive nao commitadas, e nao pode ser adiado para o CI. O que roda localmente e a **execucao seletiva** pelos modulos atingidos e seus dependentes diretos (Regra 8); nenhuma verificacao deste gate (ciclo red-green, cenarios negativos de seguranca, cenarios de formulario, governanca de dados, tratamento de flaky) pode esperar pela pipeline.

Unica execucao delegada a pipeline: a **suite completa** de regressao, que roda no PR e no push ou merge para `main` ou `master` (Regra 8). Ela condiciona o **merge**, nao o handoff: o parecer fecha sem ela e referencia a execucao da pipeline quando ja houver. Fora da pipeline, a suite completa so roda quando o solicitante a pede explicitamente, com o pedido registrado no log de prompt; mesmo assim nao substitui a execucao da pipeline. Na execucao das demandas, por qualquer agent, os testes cobrem apenas os itens afetados pelas alteracoes (Regra 8).

Nas duas execucoes, a local e a da pipeline, o primeiro erro interrompe tudo o que viria depois e e reportado para correcao (Regra 9).

Recurso de apoio ausente no projeto (runner de E2E, Testcontainers, seeder) e achado registrado, nunca "nao aplicavel" por conveniencia.

## Regras obrigatorias

### 1) Ciclo TDD Red-Green-Refactor

1. Red: escrever teste antes da implementacao, guiado pelos criterios BDD.
2. Green: implementar o minimo necessario para o teste passar.
3. Refactor: melhorar design e legibilidade sem alterar comportamento externo.

Codigo escrito por pessoa e confirmado como intencional (regra 48 do `AGENTS.md`) chega antes do teste. O ciclo continua valendo: os testes sao guiados pelos criterios de aceite escritos pelo Business Analyst, e o red e comprovado executando-os contra a base (worktree temporario em `origin/<base>`, descartado ao fim), nunca desfazendo, comentando ou isolando a alteracao humana. Teste que ja passa na base nao prova a alteracao e e reescrito ou justificado no parecer. Defeito revelado no codigo humano e achado como outro qualquer, mas a correcao que remova ou reescreva trecho humano depende de autorizacao explicita do solicitante.

### 2) Piramide de testes 70/20/10

A proporcao 70/20/10 e o **alvo**. O parecer registra a distribuicao real do conjunto entregue; desvio e admitido quando a natureza do projeto o justificar (biblioteca sem UI nem HTTP, gateway ou BFF quase todo integracao, tela sem regra de negocio quase toda E2E) e a justificativa estiver registrada na tabela de distribuicao do parecer. Desvio justificado e aceito nao e achado; desvio sem justificativa e achado Maior. O que nao admite desvio: a existencia de cada camada que o projeto suporta, e as proibicoes de cada camada.

- 70% Unitario:
  - Foco em regras de negocio puras, isoladas de rede e banco.
  - Usar padrao AAA (Arrange, Act, Assert).
  - Tratar unidade como caixa-preta pela API publica.
- 20% Integracao:
  - Foco em contratos HTTP e persistencia real.
  - Proibido mockar camada de dados para validar repositorios/DAO.
  - Executar queries contra uma **instancia real do banco da stack** (PostgreSQL, MySQL, SQL Server, Mongo ou outro), provisionada via Testcontainers ou equivalente; banco em memoria, SQLite substituto ou mock de driver nao atendem.
- 10% E2E:
  - Cypress e obrigatorio quando o projeto suportar (frontend web); quando nao suportar, tecnologia similar de E2E real para a plataforma (por exemplo Playwright, Detox ou Maestro em mobile), com a escolha e o motivo registrados no parecer. Em qualquer caso, contra frontend + backend + banco reais.
  - Proibido mockar/stubar backend no fluxo principal de E2E.
  - Proibido smoke test superficial; exigir jornadas de negocio completas.
  - Preferir multiplas assercoes por jornada para reduzir custo de setup.

### 3) Governanca de dados de teste

- Dados devem vir de seeder padrao ou de criacao programatica no roteiro.
- Nao depender de dado manual nem adivinhacao de IDs.
- Estado gerado no roteiro deve permanecer disponivel entre cenarios relacionados.
- Limpeza/teardown deve ocorrer apenas ao final do roteiro completo.

### 4) Resiliencia E2E e anti-flaky

- Frontend deve expor seletores `data-cy` ou `data-test` para elementos interativos.
- Nao usar seletor baseado em classe de estilo como estrategia principal.
- Falha flaky em ambiente integrado deve ser tratada como bloqueio ate a correcao da causa raiz, conforme o Passo 4.

### 5) DoD bloqueante para handoff ao QA

1. Evidencia de TDD aplicada e testes de unidade/integracao aprovados.
2. Evidencia de execucao isolada em container, quando a tecnologia do projeto suportar, com o comando oficial definido pelo projeto (por exemplo `docker compose run --rm <service> test`). Quando nao suportar (biblioteca, mobile, worker sem container), evidencia de execucao isolada pelo comando oficial equivalente do projeto, com a limitacao registrada no parecer. Ausencia de execucao isolada e achado; ausencia de suporte a container nao e.
3. Cobertura E2E dos criterios BDD Given/When/Then contra base real de homologacao.
4. Quando houver gatilho de seguranca (Regra 6), os cenarios negativos obrigatorios executados e aprovados.
5. Quando houver interface com entrada de dados (Regra 7), os cenarios de formulario executados e aprovados.
6. Execucao seletiva aprovada nos modulos atingidos pelo diff e em seus dependentes diretos, conforme o mapa de modulos (Regra 8). A suite completa nao e item deste DoD: roda na pipeline e condiciona o merge para `main` ou `master`, nao o handoff ao QA.
7. Execucao local e job da pipeline configurados para parar no primeiro erro e reporta-lo, e execucao seletiva final concluida sem interrupcao (Regra 9).

A referencia do System Design ao Design System em frontend nao e criterio deste gate: e a regra 18 do `AGENTS.md`, verificada por `protocolo-conformidade` e cobrada pelo Tech Lead.

### 6) Testes de seguranca e acesso indevido

Aplica-se sempre que a alteracao tocar qualquer gatilho abaixo (os mesmos que forcam porte M na regra 40 do `AGENTS.md`):

- autenticacao, sessao, cookies ou tokens;
- autorizacao, papeis, permissoes ou escopos;
- isolamento por tenant, organizacao ou conta;
- dado sensivel ou pessoal, segredo ou chave;
- endpoint novo ou alterado, webhook, fila ou integracao exposta;
- entrada de usuario que chega a banco, shell, template, arquivo ou URL;
- upload, download ou geracao de arquivo;
- limite de uso, cota ou rate limit.

Para cada gatilho tocado, a suite deve conter os **cenarios negativos** e respeitar as regras de camada e assercao de [references/cenarios-obrigatorios.md](references/cenarios-obrigatorios.md): contra backend e banco reais, nunca contra mock, com assercao sobre codigo, corpo e ausencia de efeito colateral.

Ausencia de cenario negativo para gatilho tocado, autorizacao provada contra mock, ou 500 aceito como prova: achado **bloqueante**, nao encerravel por justificativa (regra 14 do `AGENTS.md`).

### 7) Validacao de formularios e feedback visual em E2E

Aplica-se a todo fluxo E2E que envolva interface com entrada de dados (formulario, campo editavel, filtro, upload, dialogo com entrada). Para cada formulario tocado, alem da jornada feliz, a suite E2E deve conter os cenarios de [references/cenarios-obrigatorios.md](references/cenarios-obrigatorios.md): campos obrigatorios vazios, valor indevido por tipo e por regra, feedback visual do erro associado ao campo por seletor estavel, estado apos o erro e correcao com reenvio. O bloqueio no frontend nao dispensa a prova de rejeicao no backend (Regra 6).

Formulario tocado sem os cenarios de obrigatorios e valor indevido: achado **bloqueante**. Feedback verificado por texto generico ou sem associacao ao campo: achado **maior**.

### 8) Execucao seletiva por modulo no local e suite completa na pipeline de main/master

A suite e organizada por modulo ou estrutura dependente, com um **mapa de modulos** versionado no projeto, implementado e mantido pelo QA Expert.

- **Modulos nunca sao inferidos pelo agent.** A separacao em modulos, os caminhos que cada um cobre e as dependencias entre eles sao determinados automaticamente, quando declarados pela stack ou pela ferramenta (workspaces, `projects` do runner, projetos da solucao, apps ou modulos declarados pelo framework, mapa existente), ou definidos explicitamente pelo solicitante. Quando a separacao nao puder ser determinada automaticamente, no todo ou em parte, o solicitante e consultado pelo Tech Lead e define a separacao; o agent pode propor, nunca adotar sem confirmacao explicita.
- **Implementacao nova sem enquadramento automatico.** Arquivo do diff que nao casa com os caminhos de exatamente um modulo do mapa, ou estrutura nova cujo lugar no mapa nao esta declarado, tem o enquadramento (modulo existente, modulo novo e suas dependencias) definido explicitamente pelo solicitante antes do ciclo red-green. A definicao fica no log de prompt e no mapa, com a origem de cada linha.

- **Local, durante a implementacao e no fechamento do gate.** O Senior Developer executa apenas os modulos atingidos diretamente pelo diff e seus dependentes diretos, conforme o mapa, e registra a selecao no parecer. Nao ha suite completa local: ela nao e precondicao de commit, de push da branch de trabalho nem de handoff ao QA.
- **Somente os itens afetados, em toda a demanda.** A restricao vale para toda execucao de testes durante a demanda, por qualquer agent: ciclo red-green, Passo 5, validacao independente do QA, reexecucao apos correcao e reexecucao apos integrar a branch principal (regra 47). Cenarios novos do QA entram nos modulos da selecao. A **suite completa fora da pipeline** so roda com **pedido explicito do solicitante** para a demanda, registrado no log de prompt; inferencia do agent, porte da demanda ou "por garantia" nao contam como pedido.
- **Pipeline, em `main` ou `master`.** A **suite completa** (todos os modulos, todas as camadas, contra banco real) roda exclusivamente na pipeline do projeto, disparada no PR que aponta para `main` ou `master` (conforme a branch de integracao do projeto) e no push ou merge que entra nessa branch. O merge so ocorre com essa execucao verde.
- **Ordem na pipeline.** O job da suite completa segue uma sequencia fixa: (1) checkout do estado integrado (no PR, o merge com a branch de integracao; no push, o commit que entrou nela); (2) instalacao das dependencias e do runner com versoes fixadas; (3) validacao do ambiente e dos pre-requisitos (arquivos e scripts obrigatorios, ferramentas, servicos de teste); (4) gates rapidos estaticos (lint, formatacao, tipos, validacoes estruturais); (5) logo em seguida, a **suite completa**, camada a camada (Regra 9). Os **demais steps do projeto** (build de artefato ou imagem, empacotamento, publicacao, deploy e validacoes que nao sao pre-requisito dos testes) so rodam depois dela verde: no mesmo job, apos o passo de reporte, ou em job encadeado por `needs:` ao job da suite. Erro em qualquer passo de 1 a 4 tambem interrompe o job, e a suite fica **nao executada**.
- **Falha da suite completa.** Bloqueia o merge e devolve o conjunto ao **Tech Lead**, nao ao QA nem diretamente ao Senior Developer: o Tech Lead classifica o modulo que interrompeu a execucao (Regra 9), atribui a correcao ao agent dono do modulo e aciona o QA para corrigir o mapa quando houver regressao fora do escopo. A pipeline e reexecutada e precisa ficar verde antes do merge.

Determinacao dos modulos, enquadramento de implementacao nova, procedimento, configuracao do job, formato do mapa e classificacao das falhas em [references/execucao-por-modulo.md](references/execucao-por-modulo.md).

Execucao seletiva local ausente ou com falha em aberto; arquivo do diff sem modulo, ou modulo, enquadramento ou dependencia decididos pelo agent sem determinacao automatica nem definicao do solicitante; e merge para `main` ou `master` com a suite completa da pipeline vermelha, ausente ou ignorada, ou com falha nao devolvida ao Tech Lead: achado **bloqueante**. Publicacao ou deploy executado com a suite completa vermelha, ausente ou ainda em andamento: achado **bloqueante**. Selecao menor que a indicada pelo mapa, selecao maior que ela ou suite completa fora da pipeline sem pedido explicito do solicitante, definicao do solicitante nao levada ao mapa, projeto sem job de suite completa na pipeline de `main`/`master`, passos de preparo fora da ordem, ou demais steps do projeto antes da suite completa, em paralelo a ela ou sem depender dela verde: achado **maior**, com owner e prazo.

### 9) Interrupcao no primeiro erro e reporte para correcao

A execucao de testes do projeto (runner, scripts, comando oficial e job da pipeline) e **configurada** para parar no primeiro erro, na execucao seletiva local e na suite completa da pipeline. A interrupcao vem da configuracao, nunca da atencao do agent.

- **O que e erro.** Falha de assercao; erro de setup, fixture, hook ou teardown; timeout; falha de compilacao ou de coleta; container, banco de teste ou seeder que nao sobe; execucao sem nenhum teste quando a selecao previa testes.
- **O que para.** O runner nao executa o proximo teste; o proximo modulo da selecao nao comeca; a proxima camada nao comeca. As camadas rodam da mais barata a mais cara: unitario, integracao, E2E. Em execucao paralela ou em matriz, o primeiro erro cancela as demais frentes.
- **O codigo de saida chega ao fim.** Nenhum script, pipe ou job engole a falha (`|| true`, `set +e`, `continue-on-error`, pipe sem propagacao, zero testes tratado como sucesso). O resultado final de uma execucao interrompida e sempre falha.
- **Reporte para correcao.** O erro e reportado com camada, modulo, teste, `arquivo:linha`, tipo de erro, mensagem sanitizada, comando, execucao e o que deixou de rodar. Localmente, vai ao parecer e a devolucao ao agent originador (regra 17 do `AGENTS.md`); na pipeline, o job falha com o reporte no resumo da execucao e o conjunto vai ao Tech Lead (Regra 8).
- **Skills de stack.** A regra vale tambem para os blocos de teste das skills de stack (comandos, configuracao do runner, `package.json`, scripts e exemplos de pipeline): todo comando de execucao de testes mostrado ali ja traz a parada no primeiro erro, e a configuracao de exemplo a inclui (por exemplo `addopts = -x`). Default upstream que roda a suite inteira sem parada nao se aplica; bloco novo ou ingerido sem a parada e corrigido na propria skill (`SKILLS_SYNC.md`, normalizacao).
- **Retomada.** Corrigido o erro, a execucao recomeca do inicio (a selecao inteira no local, o job inteiro na pipeline). Testes que nao rodaram por causa da interrupcao sao **nao executados**, nunca aprovados.

O diagnostico de flaky (Passo 4) reexecuta o cenario suspeito isolado e nao e continuacao da execucao apos o erro.

Mecanica por ferramenta, orquestracao em script, configuracao do job, formato do reporte e retomada em [references/interrupcao-no-primeiro-erro.md](references/interrupcao-no-primeiro-erro.md).

Erro mascarado (execucao com teste falho, ou sem testes, que termina com sucesso), execucao interrompida registrada como aprovada, ou teste nao executado contado como aprovado: achado **bloqueante**. Runner, script ou job que continua apos o primeiro erro (sem parada no runner, modulo ou camada seguinte iniciado, matriz com `fail-fast: false`), ou erro reportado sem os campos minimos: achado **maior**, com owner e prazo.

## Procedimento

### Passo 1 - Delimitar o escopo real e as seams sob teste

Levantar exatamente o que mudou, sem depender de memoria da conversa:

```bash
git status --short
git diff --stat
git diff --name-only            # nao commitado
git diff --cached --name-only   # em stage
git diff                        # conteudo completo para leitura
```

Quando a alteracao ja estiver commitada localmente, comparar com a base da branch:

```bash
git diff --name-only <base>...HEAD
git diff <base>...HEAD
```

Em seguida, listar os criterios BDD ou criterios de aceite que a alteracao deve satisfazer e, para cada um, a seam onde ele sera verificado. Marcar quais gatilhos da Regra 6 a alteracao toca: cada gatilho tocado gera criterios negativos que entram nesta lista como criterios de aceite, mesmo que o solicitante nao os tenha pedido. Seam nao acordada nao recebe teste: confirmar com o solicitante ou com o System Design aprovado, conforme [`tdd-test-design`](../tdd-test-design/SKILL.md).

Enquadrar cada arquivo do diff em um modulo pelos caminhos cobertos do mapa (Regra 8). Arquivo que nao casa com exatamente um modulo, ou estrutura nova sem lugar declarado no mapa, vai ao solicitante pelo Tech Lead para definicao explicita do enquadramento antes do Passo 2; sem mapa ou sem separacao definida, a pergunta e sobre a separacao do sistema inteiro.

Registrar a lista final de arquivos avaliados, com o modulo de cada um, e a de criterios cobertos. Comportamento alterado que nao entrou nessa lista nao foi verificado, e isso deve constar como limitacao do parecer.

### Passo 2 - Executar o ciclo red-green-refactor em fatias verticais

Para cada criterio, uma fatia: um teste que falha, a implementacao minima que o faz passar, e so entao o refactor.

- Registrar a evidencia do Red: o teste falhou antes da implementacao existir. Teste escrito depois do codigo nao satisfaz este protocolo e e achado.
- Uma seam, um teste, uma implementacao minima por ciclo. Nao antecipar teste de comportamento futuro.
- O refactor nao pertence ao ciclo red-green: e etapa propria e nao pode alterar comportamento externo.

### Passo 3 - Verificar a piramide e as proibicoes por camada

Percorrer, para o conjunto entregue, os itens da secao `Verificacao das proibicoes por camada` do template (isolamento, interface publica e AAA no unitario; banco real, ausencia de mock de dados e contrato HTTP na integracao; backend real, ausencia de stub, jornada completa e cobertura BDD no E2E), mais as verificacoes das Regras 6, 7, 8 e 9 nas secoes proprias do template. Cada item aponta para a regra que o sustenta. Registrar a distribuicao real contra o alvo 70/20/10 e, se houver desvio, a justificativa na tabela de distribuicao (Regra 2).

### Passo 4 - Verificar governanca de dados e resiliencia do E2E

Percorrer os itens das secoes `Governanca de dados de teste` e `Resiliencia E2E e tratamento de flaky` do template (origem do dado no seeder ou roteiro, ausencia de dado manual ou ID adivinhado, estado preservado entre cenarios, teardown ao final, seletores `data-cy`/`data-test`, ausencia de seletor de estilo, dado sintetico sem segredo).

Tratamento obrigatorio de flaky:

1. Reexecutar o cenario suspeito ao menos tres vezes e registrar o resultado de cada execucao no parecer.
2. Identificar a causa raiz: espera implicita, concorrencia, dado residual, seletor instavel ou dependencia de ordem entre cenarios.
3. Corrigir a causa raiz. E proibido estabilizar com `sleep` fixo, retry cego no cenario ou quarentena do teste.
4. Enquanto a causa raiz nao for corrigida, o achado permanece bloqueante e o handoff fica bloqueado.
5. Desativar ou pular cenario instavel para liberar a entrega e achado bloqueante por si so.

### Passo 5 - Executar a suite isolada e coletar as evidencias

Uma execucao local, registrada: a **seletiva** pelos modulos atingidos e seus dependentes diretos (Regra 8; procedimento em [references/execucao-por-modulo.md](references/execucao-por-modulo.md)). A suite completa nao roda neste passo, salvo pedido explicito do solicitante registrado no log de prompt: e a pipeline de `main`/`master` que a executa, e o parecer registra apenas a referencia dessa execucao (workflow, evento, commit e resultado) quando ela ja existir, ou que o PR para a branch de integracao ainda nao foi aberto.

Executar com o comando oficial definido pelo projeto para execucao isolada (em container quando a tecnologia suportar, por exemplo `docker compose run --rm <service> test`) e registrar a saida real.

Antes de executar, conferir que o comando oficial, o runner e os scripts param no primeiro erro e propagam o codigo de saida (Regra 9). Execucao interrompida e registrada com o reporte do erro e reiniciada do inicio apos a correcao; so a execucao que termina sem interrupcao fecha o passo.

Coletar, por camada, o comando executado, o total de testes, aprovados, falhos, ignorados, nao executados por interrupcao e a duracao. Evidencia relatada sem execucao e achado bloqueante. Quando o projeto nao expuser um comando oficial, registrar a limitacao como achado e informar o comando efetivamente usado; quando a tecnologia nao suportar container, registrar apenas a limitacao, sem achado (Regra 5, item 2).

### Passo 6 - Classificar os achados

| Severidade | Criterio | Efeito |
|---|---|---|
| **Bloqueante** | Gatilho da Regra 6 tocado sem os cenarios negativos correspondentes; formulario tocado sem cenarios de campos obrigatorios vazios e valor indevido (Regra 7); cenario de autorizacao ou tenant validado contra mock; cenario negativo que aceita 500 como prova; comportamento alterado sem teste que o cubra; implementacao escrita antes do teste em criterio acordado; mock da camada de dados em teste de integracao; stub ou `cy.intercept()` (ou equivalente) do backend no fluxo principal de E2E; E2E sem Cypress em projeto que o suporta, ou com outra tecnologia sem justificativa registrada; criterio BDD acordado sem cenario E2E; suite seletiva nao executada localmente ou com falha em aberto; arquivo do diff sem modulo, ou modulo, enquadramento ou dependencia decididos pelo agent sem determinacao automatica nem definicao do solicitante (Regra 8); merge para `main` ou `master` com a suite completa da pipeline vermelha, ausente ou ignorada, ou com falha nao devolvida ao Tech Lead, e publicacao ou deploy sem a suite completa verde (Regra 8); erro mascarado, execucao interrompida registrada como aprovada ou teste nao executado contado como aprovado (Regra 9); flaky sem correcao de causa raiz; cenario desativado para liberar a entrega; segredo, credencial ou dado pessoal real em fixture, seeder ou evidencia. | **Reprova.** Devolve ao agent originador. |
| **Maior** | Feedback de erro de formulario verificado por texto generico ou sem associacao ao campo (Regra 7); desvio do alvo 70/20/10 sem justificativa registrada na tabela de distribuicao; selecao de modulos menor ou maior que a indicada pelo mapa, suite completa fora da pipeline sem pedido explicito do solicitante, definicao do solicitante nao levada ao mapa, projeto sem job de suite completa na pipeline de `main`/`master`, ou job fora da ordem preparo, suite completa, demais steps (Regra 8); runner, script ou job que continua apos o primeiro erro, ou erro reportado sem os campos minimos (Regra 9); smoke superficial no lugar de jornada de negocio; dado de teste nao rastreavel ou ID adivinhado; teardown fora do fim do roteiro; seletor por classe de estilo; teste acoplado a implementacao ou tautologico fora de caminho critico; ausencia de caso de borda ou de validacao em fluxo com regra relevante. | Reprova se houver mais de tres achados maiores, ou se um deles se repetir apos correcao. Caso contrario, vira ressalva com owner e prazo. |
| **Menor** | Nome de teste que nao descreve comportamento; AAA nao explicito; duplicacao de setup; organizacao de arquivos de teste. | Nao reprova. Registrar como recomendacao. |

Toda decisao de severidade deve citar a regra que a sustenta. Achado sem regra de referencia nao pode ser bloqueante.

### Passo 7 - Emitir o parecer e decidir

Preencher `../../agents/templates/evidencia-testes-template.md`.

Veredito possivel:

- **Aprovado**: DoD integralmente atendido, nenhum achado bloqueante e no maximo tres achados maiores tratados como ressalva.
- **Aprovado com ressalvas**: sem bloqueante, com ressalvas registradas, owner e prazo definidos.
- **Reprovado**: existe achado bloqueante, ou mais de tres maiores, ou reincidencia de achado ja apontado.

## Devolucao e ciclos de correcao

Seguem a regra 17 do `AGENTS.md`: devolucao acionavel (arquivo:linha, achado, regra violada, correcao esperada, severidade) na secao `Devolucao ao agent` do template; reexecucao apos correcao com status de cada achado anterior; terceira reincidencia escala ao Tech Lead. Especifico deste gate: achado de ausencia de teste em criterio acordado nao pode ser encerrado por justificativa, assim como achado de seguranca.

## Modo compacto (porte P e M)

Conforme `Protocolo por porte` do `AGENTS.md`, em porte P e M o parecer e preenchido por excecao: identificacao, escopo e criterios cobertos, execucao por camada (numeros reais, com a conferencia da parada no primeiro erro e cada interrupcao ocorrida, Regra 9), achados, veredito e, se houver, devolucao. As tabelas de verificacao dos Passos 3 e 4 sao substituidas pela linha `Checklist protocolo-tdd aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados`. Excecao: as secoes `Testes de seguranca e acesso` (Regra 6) e `Validacao de formularios em E2E` (Regra 7) do template sao sempre transcritas quando houver gatilho ou formulario tocado, em qualquer porte, com um cenario por linha; quando nao houver, uma linha `Nao aplicavel: <motivo>` com o que foi considerado. O procedimento e o mesmo; muda apenas o que e transcrito. Em porte G, todas as secoes do template sao preenchidas.

## Saida

Parecer de evidencias de testes em `../../agents/templates/evidencia-testes-template.md`, no modo do porte, com veredito explicito. Em aprovacao, libera o gate de conformidade; em reprovacao, devolucao acionavel e handoff bloqueado. O parecer e referenciado pelo registro de entrega (regra 41), nunca copiado nele.

## Reference Files

Nao carregar `references/` por padrao. Abrir apenas o arquivo necessario:

| Arquivo | Quando abrir |
|---|---|
| [references/cenarios-obrigatorios.md](references/cenarios-obrigatorios.md) | a alteracao toca gatilho de seguranca (Regra 6) ou interface com entrada de dados (Regra 7): catalogo dos cenarios e regras de camada e assercao |
| [references/interrupcao-no-primeiro-erro.md](references/interrupcao-no-primeiro-erro.md) | configurar ou conferir a parada no primeiro erro no runner, no script ou no job, registrar execucao interrompida no parecer, montar o reporte de falha da pipeline ou retomar apos a correcao (Regra 9) |
| [references/execucao-por-modulo.md](references/execucao-por-modulo.md) | determinar os modulos ou enquadrar implementacao nova (quando perguntar ao solicitante), selecionar modulos a executar, configurar ou conferir o job de suite completa na pipeline de `main`/`master` e a ordem dos seus passos, tratar falha da completa ou criar e manter o mapa de modulos (Regra 8) |
