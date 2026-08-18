# Skill Hierarchy

Guia pratico para escolher a skill certa, evitar sobreposicao e reduzir invocacao ambigua dentro do pacote.

## Objetivo

Este documento responde a uma pergunta simples: qual skill usar para cada tipo de demanda?

Use este mapa antes de escolher uma skill em `.claude/skills/`, especialmente quando houver varias alternativas parecidas no mesmo ecossistema.

## Regra geral

Escolha skills nesta ordem:

1. Primeiro, identifique o dominio principal da tarefa.
2. Depois, veja se existe uma skill de framework ou stack mais especifica.
3. So use uma skill generica se nao houver uma skill especializada mais aderente.
4. Se a tarefa for transversal, combine no maximo a skill principal com uma skill de apoio documental ou de arquitetura.

## Skills por categoria

### Arquitetura e documentacao

Use estas skills quando a tarefa principal nao for uma implementacao de framework, mas sim estrutura, documentacao, revisao ou diagramacao.

- [.claude/skills/clean-architecture/](./clean-architecture/): use para desenho tecnico, separacao de camadas, boundaries e revisao arquitetural
- [.claude/skills/documentation-sync/](./documentation-sync/): use depois de mudancas tecnicas para revisar impacto documental
- [.claude/skills/review-documentation/](./review-documentation/): use para registrar review tecnico, consolidacao de mudancas e evidencias
- [.claude/skills/mermaid-generator/](./mermaid-generator/): use quando a entrega pede diagramas Mermaid
- [.claude/skills/design-md/](./design-md/): use quando a tarefa for consolidar artefatos de interface e sintetizar um `DESIGN.md` ou resumo de design system reutilizavel
- [.claude/skills/gitflow/](./gitflow/): use para governanca de branches, nomenclatura Gitflow e politicas de sincronizacao
- [.claude/skills/git-commit/](./git-commit/): use para gerar ou revisar commits com convencao semantica (Conventional Commits)
- [.claude/skills/prompt-logger/](./prompt-logger/): skill transversal obrigatoria — registra cada prompt recebido com interpretacao, raciocinio e plano de acao em `docs/prompts/`

#### Decision tree rapido: `documentation-sync` vs `review-documentation`

Use `documentation-sync` quando a pergunta principal for: quais documentos existentes precisam ser atualizados depois da mudanca tecnica?

Use `review-documentation` quando a pergunta principal for: qual registro tecnico formal preciso criar ou completar para deixar a entrega auditavel?

Regra pratica:

1. Se voce precisa revisar README, docs, arquitetura, QA, requisitos ou guias operacionais ja existentes, comece com `documentation-sync`.
2. Se voce precisa criar um review, changelog tecnico, journal de entrega ou registro retroativo da mudanca, use `review-documentation`.
3. Se a entrega exigir os dois movimentos, execute primeiro `documentation-sync` para alinhar a base documental e depois `review-documentation` para registrar a entrega.
4. Nao use `review-documentation` como substituto de manutencao de documentacao viva, e nao use `documentation-sync` como substituto do registro tecnico formal da entrega.

### Produto e requisitos

- [.claude/skills/prd-generator/](./prd-generator/): use para gerar PRD
- [.claude/skills/user-story-writing/](./user-story-writing/): use para historias de usuario e criterios de aceite

### Testes e qualidade

- [.claude/skills/protocolo-tdd/](./protocolo-tdd/): use obrigatoriamente sempre que a tarefa envolver desenvolvimento, refatoracao ou correcao de codigo; esta skill define o protocolo padrao de TDD, piramide 70/20/10, integracao com banco real via Testcontainers e E2E real com Cypress sem mocks de rede
- [.claude/skills/testing-strategy/](./testing-strategy/): use para desenhar estrategia/plano de testes quando a demanda for conceitual e nao um protocolo operacional normativo

Regra de prioridade para testes:

1. `protocolo-tdd` obrigatoriamente quando houver desenvolvimento, refatoracao ou correcao de codigo.
2. `testing-strategy` quando a demanda for apenas desenho de plano, cobertura e abordagem, sem implementacao nem alteracao de codigo.

### Seguranca

#### Quando a tarefa for seguranca transversal web

Use:

- [.claude/skills/security-best-practices/](./security-best-practices/)

Escopo ideal:

- HTTPS
- CORS
- cookies
- headers
- CSP
- secret handling
- hardening web em geral

#### Quando a tarefa for seguranca especifica de API

Use:

- [.claude/skills/api-security-best-practices/](./api-security-best-practices/)

Escopo ideal:

- auth
- authz
- token handling
- schema validation
- rate limiting
- API hardening

#### Quando a tarefa for Better Auth especificamente

Use:

- [.claude/skills/better-auth-best-practices/](./better-auth-best-practices/)

Nao use esta skill para auth generica. Ela e para integracao com Better Auth.

## Skills por stack

### Boas praticas genericas web

Use quando a tarefa for auditoria ou modernizacao generica sem stack especifica:

- [.claude/skills/best-practices/](./best-practices/): compatibilidade de browser, baseline de seguranca e qualidade de codigo generica

Quando nao usar: prefira skills de framework (fastapi-expert, django-expert) ou skills de seguranca especializadas (security-best-practices, api-security-best-practices) quando o escopo for claro.

### Python generico

Use:

- [.claude/skills/python-best-practices/](./python-best-practices/)

Quando usar:

- type-first design
- modelagem de dominio
- contratos
- Protocol, NewType, dataclasses e fronteiras tipadas

Quando nao usar:

- nao use so porque o arquivo e Python; prefira skills de framework se a tarefa for claramente Django ou FastAPI

### FastAPI

#### Quero estruturar ou iniciar um servico

Use:

- [.claude/skills/fastapi-templates/](./fastapi-templates/)

#### Quero implementar endpoints, schemas, auth ou operacao principal

Use:

- [.claude/skills/fastapi-expert/](./fastapi-expert/)

#### Quero uma orientacao leve de estilo em um servico FastAPI ja existente

Use:

- [.claude/skills/fastapi-python/](./fastapi-python/)

#### Quero tratar concorrencia, performance async ou event loop safety

Use:

- [.claude/skills/fastapi-async-patterns/](./fastapi-async-patterns/)

Regra de prioridade para FastAPI:

1. `fastapi-expert` para implementacao principal
2. `fastapi-templates` para bootstrap e estrutura
3. `fastapi-async-patterns` para tuning async
4. `fastapi-python` para guidance leve em codigo existente

### Django

#### Quero implementar feature, model, serializer, view ou depurar ORM

Use:

- [.claude/skills/django-expert/](./django-expert/)

#### Quero definir estrutura, organizacao do projeto ou padroes de arquitetura Django

Use:

- [.claude/skills/django-patterns/](./django-patterns/)

#### Quero hardening e revisao de seguranca Django

Use:

- [.claude/skills/django-security/](./django-security/)

#### Quero testes, TDD, pytest-django ou infraestrutura de testes

Use:

- [.claude/skills/django-tdd/](./django-tdd/)

Regra de prioridade para Django:

1. `django-expert` para implementacao
2. `django-patterns` para estrutura
3. `django-security` para seguranca
4. `django-tdd` para testes

### React e frontend

#### Quero performance e composicao em React generico

Use:

- [.claude/skills/frontend-react-best-practices/](./frontend-react-best-practices/)

#### Quero performance orientada a Next.js, App Router ou Vercel

Use:

- [.claude/skills/vercel-react-best-practices/](./vercel-react-best-practices/)

#### Quero apoio de design de interface

Use:

- [.claude/skills/interface-design/](./interface-design/)

#### Quero construir ou estilizar componentes e paginas com alta qualidade visual

Use:

- [.claude/skills/frontend-design/](./frontend-design/): use para criar interfaces frontend production-grade com direcao estetica forte — componentes, landing pages, dashboards ou qualquer UI que exija qualidade visual acima do padrao generico

Regra de prioridade para frontend:

1. `vercel-react-best-practices` se o problema for claramente Next.js/Vercel
2. `frontend-react-best-practices` para React framework-agnostico
3. `interface-design` para problema de sistema visual, interface ou estrutura de UX
4. `frontend-design` para construcao de UI com alta qualidade estetica e visual diferenciado

### Acessibilidade

#### Quero auditar uma pagina, tela ou design antes do handoff

Use:

- [.claude/skills/accessibility-review/](./accessibility-review/)

#### Quero corrigir acessibilidade web em UI ja implementada

Use:

- [.claude/skills/accessibility/](./accessibility/)

#### Quero implementar padroes acessiveis, ARIA, foco, leitores de tela ou acessibilidade mobile

Use:

- [.claude/skills/accessibility-compliance/](./accessibility-compliance/)

Regra de prioridade para acessibilidade:

1. `accessibility-review` para diagnostico e parecer de auditoria, sem foco principal em implementar
2. `accessibility` para remediacao web e melhoria de acessibilidade em interfaces existentes
3. `accessibility-compliance` para implementacao de padroes acessiveis, componentes e fluxos com escopo mais construtivo e inclusive mobile

### Node.js e NestJS

- [.claude/skills/nodejs-best-practices/](./nodejs-best-practices/): use para Node.js generico
- [.claude/skills/nestjs-best-practices/](./nestjs-best-practices/): use quando a stack for NestJS

### PHP e Laravel

- [.claude/skills/php-best-practices/](./php-best-practices/): use para PHP generico
- [.claude/skills/laravel-best-practices/](./laravel-best-practices/): use quando a stack for Laravel

### Cloudflare Workers

- [.claude/skills/workers-best-practices/](./workers-best-practices/): use para Workers, wrangler, bindings, observability e praticas do ecossistema Cloudflare

## Combinacoes recomendadas

Combinacoes seguras e uteis:

- `fastapi-expert` + `api-security-best-practices`
- `django-expert` + `django-security`
- `frontend-react-best-practices` + `interface-design`
- `vercel-react-best-practices` + `interface-design`
- `clean-architecture` + `review-documentation`
- `documentation-sync` + `mermaid-generator`
- `prd-generator` + `user-story-writing`

## Combinacoes a evitar

Evite carregar juntas sem necessidade:

- `fastapi-expert` + `fastapi-python` quando o objetivo ja estiver claro
- `django-expert` + `django-patterns` para uma unica tarefa pequena
- `security-best-practices` + `api-security-best-practices` se a demanda for claramente apenas web ou apenas API
- `frontend-react-best-practices` + `vercel-react-best-practices` quando a stack ja estiver definida
- `accessibility` + `accessibility-review` quando a necessidade for claramente apenas auditar ou claramente apenas corrigir

## Regras de desempate

Se duas skills parecerem servir:

1. escolha a mais especifica para a stack;
2. se ambas forem da mesma stack, escolha a que mais se aproxima do objetivo principal:
   - implementar
   - estruturar
   - proteger
   - testar
   - documentar
3. adicione uma segunda skill apenas se ela cobrir uma dimensao diferente e complementar.

## Atalho por intencao

### Quero criar arquitetura ou organizar camadas

- [.claude/skills/clean-architecture/](./clean-architecture/)

### Quero revisar impacto documental apos uma entrega

- [.claude/skills/documentation-sync/](./documentation-sync/)

### Quero escrever ou consolidar um review tecnico

- [.claude/skills/review-documentation/](./review-documentation/)

### Quero atualizar docs existentes e tambem registrar a entrega

1. [.claude/skills/documentation-sync/](./documentation-sync/)
2. [.claude/skills/review-documentation/](./review-documentation/)

### Quero gerar diagrama Mermaid

- [.claude/skills/mermaid-generator/](./mermaid-generator/)

### Quero escrever PRD ou historias

- [.claude/skills/prd-generator/](./prd-generator/)
- [.claude/skills/user-story-writing/](./user-story-writing/)

### Quero proteger uma API

- [.claude/skills/api-security-best-practices/](./api-security-best-practices/)

### Quero endurecer uma aplicacao web

- [.claude/skills/security-best-practices/](./security-best-practices/)

### Quero iniciar um servico FastAPI

- [.claude/skills/fastapi-templates/](./fastapi-templates/)

### Quero implementar um endpoint FastAPI

- [.claude/skills/fastapi-expert/](./fastapi-expert/)

### Quero estruturar ou depurar Django

- [.claude/skills/django-expert/](./django-expert/)

### Quero testar Django com TDD

- [.claude/skills/django-tdd/](./django-tdd/)

### Quero otimizar React

- [.claude/skills/frontend-react-best-practices/](./frontend-react-best-practices/)

### Quero otimizar Next.js

- [.claude/skills/vercel-react-best-practices/](./vercel-react-best-practices/)

### Quero auditar acessibilidade antes do handoff

- [.claude/skills/accessibility-review/](./accessibility-review/)

### Quero corrigir acessibilidade em interface web existente

- [.claude/skills/accessibility/](./accessibility/)

### Quero implementar componentes e padroes acessiveis

- [.claude/skills/accessibility-compliance/](./accessibility-compliance/)

## Resultado esperado

Ao usar este arquivo, voce deve conseguir:

- reduzir sobreposicao entre skills;
- acionar a skill certa mais cedo;
- evitar combinacoes redundantes;
- tornar a descoberta do catalogo mais previsivel.