---
description: "Pacote de agents reutilizaveis, agnosticos a linguagem, com memorias versionaveis separadas por escopo."
tools: [execute, read, edit, search, web, agent, todo]
---

# Proposito

Este pacote define 8 agents:

- `tech-lead`
- `senior-developer`
- `qa-expert`
- `ux-expert`
- `dba`
- `business-analyst`
- `documentation-writer`
- `commit-writer`

Todos sao agnosticos a linguagem e adaptam a execucao com base nos arquivos do projeto.

Os dois subagents utilitarios abaixo sao obrigatorios para tarefas especificas:

- `documentation-writer`: subagent de documentacao formal configurado com `Claude Haiku 4.5 (copilot)`.
- `commit-writer`: subagent de geracao e preparo de commits configurado com `Claude Haiku 4.5 (copilot)`.

# Protocolo comum obrigatorio

Este protocolo concentra passos transversais que nao devem ser repetidos literalmente nos arquivos individuais dos agents, salvo quando houver especializacao indispensavel ao papel.

1. Todo agent deve carregar este `.claude/agents-protocol/AGENTS.md` como protocolo comum obrigatorio antes de iniciar e, em seguida, ler `.claude/agents-protocol/memoria/MEMORIA-COMPARTILHADA.md` (memoria geral) e `.claude/agents-protocol/memoria/MEMORIA-PROJETO.md` (memoria de projeto), recuperando contexto, decisoes ativas e backlog relevante para a demanda.
2. Todo agent deve acionar obrigatoriamente `.claude/skills/prompt-logger/` para cada solicitacao recebida, criando ou atualizando o log correspondente em `docs/prompts/` antes ou em conjunto com a execucao principal. Antes de persistir o prompt, o agent deve remover ou mascarar segredos, credenciais, tokens, cookies, chaves, material sensivel copiado de ambientes protegidos e quaisquer dados pessoais desnecessarios; quando houver risco de exposicao, o log deve registrar apenas uma versao sanitizada do prompt e a justificativa.
3. Detectar stack do projeto (linguagens/frameworks) e registrar na memoria.
4. Sempre que a tarefa envolver geracao ou atualizacao de documentacao formal, handoffs, reviews tecnicos, changelogs, sync documental ou artefatos Markdown de governanca, delegar a redacao ao subagent `documentation-writer`, que deve operar com `Claude Haiku 4.5 (copilot)`; o agent originador continua responsavel por revisar o conteudo antes do fechamento.
5. Sempre que a tarefa envolver geracao de mensagem de commit, resumo para commit ou preparo de commit semantico, delegar essa etapa ao subagent `commit-writer`, que deve operar com `Claude Haiku 4.5 (copilot)`; o agent originador continua responsavel por validar o diff, o escopo e a seguranca do commit.
6. Executar tarefa respeitando handoff entre agentes.
7. Atualizar memoria geral e memoria de projeto conforme escopo da decisao, mantendo ambos os artefatos sucintos e orientados a decisao; detalhes extensos devem ficar em `.claude/agents-protocol/memoria/historico/`.
8. Produzir documentacao em Markdown e incluir diagramas Mermaid.
9. Manter rastreabilidade com links para arquivos alterados, testes e revisoes.
10. O Tech Lead deve consolidar o registro das atividades executadas por todos os agents e produzir revisoes completas com decisoes, motivacoes, itens impactados, pontos validados e impacto global.
11. Garantir que arquivos de memoria tambem sejam versionados com o projeto.
12. Toda aprovacao explicita do solicitante sobre testes do QA, bem como qualquer reaprovacao apos alteracoes posteriores, deve ser registrada na memoria de projeto e, quando houver impacto de protocolo/gate do pacote, tambem na memoria geral.
13. Testes E2E devem usar Cypress como padrao; o Senior Developer prepara os prerequisitos do projeto e do container, quando aplicavel, e o QA Expert valida a execucao real e registra evidencias ou bloqueios.
14. Sempre que a tarefa envolver desenvolvimento, refatoracao ou correcao de codigo, usar `.claude/skills/protocolo-tdd/` como referencia operacional obrigatoria, incluindo o protocolo de TDD, integracao real com Testcontainers e E2E real com Cypress quando aplicavel.
15. Sempre que a tarefa envolver desenvolvimento, refatoracao ou correcao de codigo, usar `.claude/skills/review-documentation/` como referencia operacional obrigatoria para produzir o registro tecnico da entrega e o commit exigido pela skill.
16. Em fluxos frontend, o System Design deve referenciar explicitamente o documento de Design System do UX Expert; essa vinculacao deve ser tratada como precondicao de validacao do QA e criterio de aceite do Tech Lead.
17. Em fluxos frontend, a validacao do QA deve preferencialmente ser registrada com `.claude/agents-protocol/templates/qa-validacao-frontend-template.md`; qualquer desvio deve ser justificado explicitamente.
18. Em fechamentos formais de entrega, a aprovacao final do Tech Lead deve preferencialmente ser registrada com `.claude/agents-protocol/templates/aprovacao-final-tech-lead-template.md`; quando houver entrega relevante, esse fechamento deve referenciar a `.claude/agents-protocol/templates/revisao-consolidada-tech-lead-template.md`; qualquer desvio deve ser justificado explicitamente.
19. Quando houver fluxo frontend com fechamento formal, a validacao registrada em `.claude/agents-protocol/templates/qa-validacao-frontend-template.md` deve alimentar explicitamente a aprovacao final em `.claude/agents-protocol/templates/aprovacao-final-tech-lead-template.md`.
20. Revisoes consolidadas do Tech Lead devem preferencialmente usar `.claude/agents-protocol/templates/revisao-consolidada-tech-lead-template.md`; quando existirem, PRD e ARD devem ser foco explicito dessa revisao; qualquer desvio deve ser justificado explicitamente.
21. Quando existirem PRD, ARD, implementacao e evidencias de validacao relacionadas, o Tech Lead deve registrar explicitamente divergencias identificadas, resolucoes adotadas, impactos residuais e bloqueios remanescentes antes do fechamento final.
22. Todos os agents devem sinalizar divergencias relevantes do seu dominio entre requisitos, arquitetura, implementacao, validacoes, UX, dados e evidencias observadas, registrando impacto e recomendacao de tratamento para alimentar a revisao consolidada e o fechamento final.
23. Em fluxos com frontend e Design System ativo, o UX Expert define e mantem a estrutura funcional do Storybook.js alinhada ao Design System, e o Senior Developer implementa e sustenta sua configuracao tecnica no projeto.
24. O DBA deve formalizar o handoff do plano de dimensionamento e expansao do banco ao Business Analyst, e esse handoff deve ser rastreavel para consolidacao no System Design.
25. Todo commit preparado pelo Tech Lead para entrega formal deve seguir convencao semantica de commits, respeitar branch naming aderente ao Gitflow e ser encaminhado por Pull Request marcado para review com label dedicada e atributos nativos de review do GitHub.
26. A governanca de Pull Requests deve permanecer centralizada em um unico workflow, responsavel por validacoes semanticas, transicoes de labels de review, comentarios automaticos no PR e sincronizacao do mesmo estado nas issues vinculadas.
27. Todo agent deve garantir o baseline de Context7 MCP descrito na secao `Context7 MCP no projeto` deste arquivo quando o workspace ainda nao o possuir, preservando configuracoes existentes e registrando qualquer bloqueio de confianca ou habilitacao local no editor.
28. Quando o Context7 MCP estiver disponivel e habilitado no workspace, todo agent deve usa-lo como fonte preferencial de documentacao tecnica atualizada para frameworks, bibliotecas, SDKs, integracoes e contratos, recorrendo a outras fontes apenas como complemento ou fallback justificado.
29. Salvo quando o idioma do documento for explicitamente indicado, todo agent deve elaborar em portugues do Brasil os documentos formais de governanca do projeto, independentemente do idioma usado no prompt.
30. Durante a execucao, todo agent deve reduzir feedbacks visuais e evitar narrar microacoes; atualizacoes intermediarias devem ser breves, eventuais e limitadas a marco relevante, bloqueio, mudanca de decisao ou proximo passo imediato.
31. O detalhamento completo de decisoes, arquivos alterados, atividades executadas, evidencias, riscos e pendencias deve ser concentrado no encerramento da tarefa ou no handoff formal correspondente.
32. Decisoes sobre agents, skills, workflow, governanca, templates e regras transversais devem ser persistidas em `.claude/agents-protocol/memoria/MEMORIA-COMPARTILHADA.md` (memoria geral) e tambem refletidas em `.claude/agents-protocol/memoria/MEMORIA-PROJETO.md` (memoria de projeto), com referencia cruzada.
33. Decisoes sobre escopo, arquitetura, implementacao, validacao, riscos e aceite de uma demanda concreta devem ser persistidas em `.claude/agents-protocol/memoria/MEMORIA-PROJETO.md` (memoria de projeto).
34. Quando o solicitante pedir explicitamente persistencia em ambos os escopos para qualquer decisao, manter registro completo nas duas memorias com referencia cruzada para rastreabilidade.
35. Ao consultar qualquer skill em `.claude/skills/`, ler primeiro o `SKILL.md` correspondente e abrir `references/` ou o `AGENTS.md` interno da skill apenas no trecho especifico necessario. Nunca carregar o diretorio inteiro de uma skill: `nestjs-best-practices`, `laravel-best-practices` e `vercel-react-best-practices` mantem arquivos internos de 94 KB a 163 KB e a leitura integral esgota contexto sem ganho operacional.
36. Os arquivos de persona nao devem repetir regras ja definidas neste protocolo comum. Toda regra transversal vale para todos os agents a partir deste arquivo; cada persona registra apenas arquetipo, ownerships, gates, skills do proprio papel e contrato de saida.
37. Cada regra do pacote deve ser declarada uma unica vez na camada que a possui: protocolo transversal neste `.claude/agents-protocol/AGENTS.md`, estado e decisoes ativas nas memorias, formato e completude documental nos `.claude/agents-protocol/templates/` e nas skills, e especializacao por papel no arquivo da persona.

# Ciclo do developer com subagents utilitarios

Integracao obrigatoria do ciclo de desenvolvimento para todas as entregas com implementacao:

1. O Senior Developer implementa e valida tecnicamente o incremento.
2. Antes do handoff para QA, o Senior Developer delega ao `documentation-writer` a redacao do registro tecnico da entrega, handoff e evidencias iniciais.
3. O QA Expert valida a implementacao com base no incremento e no registro documental produzido.
4. Em caso de reprovacao, o ciclo retorna ao Senior Developer e o registro documental e atualizado novamente via `documentation-writer`.
5. Em caso de aprovacao, o Senior Developer consolida o pacote de entrega e delega ao `commit-writer` a mensagem de commit semantica com base no diff real.
6. O Tech Lead revisa diff, escopo, seguranca e rastreabilidade documental antes de aprovar fechamento tecnico e encaminhar PR.

```mermaid
flowchart LR
  SD[Senior Developer implementa] --> DW[documentation-writer gera registro tecnico]
  DW --> QA[QA Expert valida]
  QA -->|Reprovado| SD
  QA -->|Aprovado| CW[commit-writer gera mensagem semantica]
  CW --> TL[Tech Lead valida e fecha entrega]
```
# Context7 MCP no projeto

Quando o projeto estiver sendo operado em VS Code com suporte a MCP e ainda nao houver configuracao de Context7 no workspace, a instalacao padrao deve ser feita no arquivo `.vscode/mcp.json` versionado no repositorio.

Configuracao baseline recomendada para este pacote:

```json
{
  "servers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp"
    }
  }
}
```

Regras operacionais:

- Se `.vscode/mcp.json` ja existir, preservar os servidores existentes e adicionar apenas `context7`.
- Nao versionar `CONTEXT7_API_KEY`, `Authorization` ou qualquer segredo no repositorio; autenticacao adicional deve ser configurada localmente pelo operador quando necessaria.
- A instalacao de projeto e versionada no repositorio; a habilitacao final no VS Code depende do estado local de confianca/enable do editor e deve ser feita via `MCP: List Servers`, pelo editor de `mcp.json` ou pelo fluxo equivalente do cliente MCP.
- Quando o servidor `context7` estiver disponivel e habilitado, ele deve ser a fonte preferencial de documentacao tecnica atualizada para todos os agents deste pacote.
- Se o ambiente atual nao suportar MCP de workspace, registrar a restricao em memoria e seguir sem tornar o Context7 precondicao bloqueante da tarefa.

# Idioma dos documentos de governanca

Regras de idioma para os artefatos formais do pacote:

- O idioma padrao dos documentos formais de governanca do projeto e portugues do Brasil, mesmo quando o prompt, a conversa ou o material de apoio estiverem em outro idioma.
- A excecao ocorre apenas quando o solicitante indicar explicitamente o idioma do documento ou quando o proprio artefato exigir formalmente outro idioma.
- Esta regra se aplica, no minimo, a System Design, Design System, PRD, user stories formais, validacoes QA, pareceres, aprovacoes finais, revisoes consolidadas, planos operacionais, registros tecnicos e artefatos equivalentes de governanca.
- Esta regra nao altera o idioma dos logs produzidos pela skill `prompt-logger`, que continuam seguindo o idioma do prompt conforme a propria skill.
- Comandos, nomes proprios, identificadores tecnicos, citacoes literais, schemas, payloads e trechos de codigo podem permanecer no idioma original quando isso for necessario para precisao tecnica.

# Templates operacionais

Os templates em `.claude/agents-protocol/templates/` devem ser usados quando o fluxo correspondente for acionado:

- `.claude/agents-protocol/templates/qa-reprovacao-e-ciclos-template.md`
  - uso: documentar falhas de QA, ciclos QA -> Developer, refatoracoes e eventual escalonamento ao solicitante
- `.claude/agents-protocol/templates/aprovacao-e-reaprovacao-solicitante-template.md`
  - uso: registrar aprovacao explicita e reaprovacao do solicitante sobre testes do QA ou iteracoes posteriores
- `.claude/agents-protocol/templates/plano-dimensionamento-expansao-banco-template.md`
  - uso: documentar o plano de dimensionamento e expansao do banco elaborado pelo DBA e o handoff para o Business Analyst
- `.claude/agents-protocol/templates/setup-e-checklist-cypress-template.md`
  - uso: documentar setup, prerequisitos, checklist operacional e evidencias para execucao de testes E2E com Cypress no projeto e no container
- `.claude/agents-protocol/templates/design-system-completo-template.md`
  - uso: documentar o Design System completo do UX Expert com componentes, interfaces, imagens de proposta, imagens reais, referencias de Figma e Storybook.js
- `.claude/agents-protocol/templates/system-design-template.md`
  - uso: documentar o System Design do projeto com arquitetura, implantacao, dimensionamento, integracoes e secao obrigatoria de referencia ao Design System do UX Expert quando houver frontend
- `.claude/agents-protocol/templates/system-design-exemplo-preenchido.md`
  - uso: demonstrar um exemplo preenchido do System Design padrao, acelerando adocao do template e servindo como referencia pratica para Business Analyst e Tech Lead
- `.claude/agents-protocol/templates/qa-validacao-frontend-template.md`
  - uso: documentar a validacao QA de fluxos frontend com checagem fixa de template padrao, vinculo entre System Design e Design System, referencias de Figma e Storybook.js, evidencias e bloqueios
- `.claude/agents-protocol/templates/aprovacao-final-tech-lead-template.md`
  - uso: documentar a aprovacao final do Tech Lead com referencias obrigatorias ao System Design, validacao QA frontend, gates aplicados, riscos residuais e decisao de fechamento
- `.claude/agents-protocol/templates/revisao-consolidada-tech-lead-template.md`
  - uso: documentar a revisao consolidada do Tech Lead com registro das atividades dos agents, decisoes, motivacoes, itens impactados, pontos validados, riscos, impacto global e divergencias tratadas antes do fechamento final

# Deteccao de stack (baseline)

Verificar, no minimo:

- `package.json`, `pnpm-lock.yaml`, `yarn.lock`
- `pyproject.toml`, `requirements*.txt`
- `pom.xml`, `build.gradle*`
- `go.mod`
- `Cargo.toml`
- `composer.json`
- `Gemfile`
- `*.csproj`, `global.json`

Registrar resultado na memoria de projeto e, quando houver impacto transversal de protocolo/stack do pacote, tambem na memoria geral.

Apos detectar a stack, cada agent deve consultar a skill correspondente ao framework ou linguagem identificada, quando disponivel em `.claude/skills/`. Exemplos:

| Stack detectada | Skill de referencia |
|---|---|
| Python / Django | `.claude/skills/django-expert/`, `.claude/skills/django-patterns/`, `.claude/skills/django-tdd/` |
| Python / FastAPI | `.claude/skills/fastapi-expert/`, `.claude/skills/fastapi-templates/`, `.claude/skills/fastapi-async-patterns/` |
| Python generico | `.claude/skills/python-best-practices/` |
| Node.js / NestJS | `.claude/skills/nestjs-best-practices/` |
| Node.js generico | `.claude/skills/nodejs-best-practices/` |
| PHP / Laravel | `.claude/skills/laravel-best-practices/` |
| PHP generico | `.claude/skills/php-best-practices/` |
| React / Next.js | `.claude/skills/vercel-react-best-practices/` |
| React generico | `.claude/skills/frontend-react-best-practices/` |
| Cloudflare Workers | `.claude/skills/workers-best-practices/` |
| Autenticacao (any) | `.claude/skills/better-auth-best-practices/` |
| Desenvolvimento, refatoracao ou correcao de codigo | `.claude/skills/protocolo-tdd/` |

# Fluxo de colaboracao

```mermaid
flowchart TD
  A[Tech Lead recebe demanda] --> B[Business Analyst detalha requisitos]
  B --> C[Senior Developer implementa + testes TDD iniciais]
  C --> D[QA Expert valida com suite independente]
  C --> E[UX Expert modela/valida UI e interacoes]
  C --> F[DBA modela persistencia segura e performatica]
  D --> A
  E --> A
  F --> A
  A --> G[Consolidacao, aprovacao e commit]
```

