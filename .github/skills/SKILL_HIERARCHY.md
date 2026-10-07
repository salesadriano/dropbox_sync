# Skill Hierarchy

Guia pratico para escolher a skill certa, evitar sobreposicao e reduzir invocacao ambigua dentro do pacote.

## Objetivo

Este documento responde a uma pergunta simples: qual skill usar para cada tipo de demanda?

Use este mapa antes de escolher uma skill em `.github/skills/`, especialmente quando houver varias alternativas parecidas no mesmo ecossistema.

Para adicionar ou atualizar uma skill vinda de fonte externa, veja [SKILLS_SYNC.md](./SKILLS_SYNC.md).

## Regra geral

Escolha skills nesta ordem:

1. Primeiro, identifique o dominio principal da tarefa.
2. Depois, veja se existe uma skill de framework ou stack mais especifica.
3. So use uma skill generica se nao houver uma skill especializada mais aderente.
4. Se a tarefa for transversal, combine no maximo a skill principal com uma skill de apoio documental ou de arquitetura.

## Skills por categoria

### Arquitetura e documentacao

Use estas skills quando a tarefa principal nao for uma implementacao de framework, mas sim estrutura, documentacao, revisao ou diagramacao.

- [.github/skills/clean-architecture/](./clean-architecture/): use para desenho tecnico, separacao de camadas, boundaries e revisao arquitetural; e a referencia agnostica a linguagem e continua sendo o padrao do pacote
- [.github/skills/dotnet-clean-architecture/](./dotnet-clean-architecture/): use apenas quando a stack detectada for .NET/C# e a duvida for layout de projetos, handlers, EF Core e endpoints; complementa, nao substitui, `clean-architecture`
- [.github/skills/documentation-sync/](./documentation-sync/): use depois de mudancas tecnicas para revisar impacto documental
- [.github/skills/review-documentation/](./review-documentation/): use para registrar review tecnico, consolidacao de mudancas e evidencias
- [.github/skills/mermaid-generator/](./mermaid-generator/): use quando a entrega pede diagramas Mermaid
- [.github/skills/design-md/](./design-md/): use quando a tarefa for consolidar artefatos de interface e sintetizar um `DESIGN.md` ou resumo de design system reutilizavel
- [.github/skills/gitflow/](./gitflow/): use para governanca de branches, nomenclatura Gitflow, branch principal declarada, verificacao de PRs abertos antes da demanda, worktree por demanda, remocao local de branches apagadas no remoto, avaliacao da branch principal antes de cada push e coordenacao entre instancias do Tech Lead
- [.github/skills/git-commit/](./git-commit/): use para gerar ou revisar commits com convencao semantica (Conventional Commits)
- [.github/skills/prompt-logger/](./prompt-logger/): skill transversal obrigatoria — registra cada prompt recebido em `docs/prompts/`, um arquivo por demanda, com texto integral sanitizado, porte, intencao e inferencias; plano e resultado ficam no registro de entrega

#### Decision tree rapido: `documentation-sync` vs `review-documentation`

Use `documentation-sync` quando a pergunta principal for: quais documentos existentes precisam ser atualizados depois da mudanca tecnica?

Use `review-documentation` quando a pergunta principal for: qual registro tecnico formal preciso criar ou completar para deixar a entrega auditavel?

Regra pratica:

1. Se voce precisa revisar README, docs, arquitetura, QA, requisitos ou guias operacionais ja existentes, comece com `documentation-sync`.
2. Se voce precisa criar um review, changelog tecnico, journal de entrega ou registro retroativo da mudanca, use `review-documentation`.
3. Se a entrega exigir os dois movimentos, execute primeiro `documentation-sync` para alinhar a base documental e depois `review-documentation` para registrar a entrega.
4. Nao use `review-documentation` como substituto de manutencao de documentacao viva, e nao use `documentation-sync` como substituto do registro tecnico formal da entrega.

### Produto e requisitos

- [.github/skills/use-case-specification/](./use-case-specification/): use como primeiro passo do escopo, para fixar problema de negocio, usuarios primarios e criterios mensuraveis de sucesso antes do PRD
- [.github/skills/prd-generator/](./prd-generator/): use para gerar PRD
- [.github/skills/user-story-writing/](./user-story-writing/): use para historias de usuario e criterios de aceite

Regra de prioridade para produto:

1. `use-case-specification` para enquadrar o problema e os criterios de sucesso.
2. `prd-generator` para formalizar o requisito.
3. `user-story-writing` para decompor em historias com criterios de aceite.

### Skills fora do escopo padrao do pacote

- [.github/skills/strategy-compare/](./strategy-compare/): comparacao de estrategias de backtesting financeiro (vectorbt/OpenAlgo/TA-Lib). Nao faz parte do fluxo de governanca do pacote e depende da skill upstream `vectorbt-expert`, que nao esta instalada aqui. Nao acionar em demandas comuns de engenharia; usar apenas em projetos de backtesting que ja tenham esse ecossistema.

### Testes e qualidade

- [.github/skills/protocolo-tdd/](./protocolo-tdd/): gate local obrigatorio de testes; use sempre que a tarefa envolver desenvolvimento, refatoracao ou correcao de codigo. Define o protocolo padrao de TDD, piramide 70/20/10, integracao com banco real via Testcontainers e E2E real com Cypress sem mocks de rede, e fecha com achados por severidade e veredito em `../agents/templates/evidencia-testes-template.md`. Achado bloqueante reprova e devolve ao agent originador. Nao depende de pipeline.
- [.github/skills/tdd-test-design/](./tdd-test-design/): use dentro do ciclo red-green para decidir o que cada teste afirma e em qual seam; cobre seams, mocking apenas em fronteiras de sistema e anti-patterns (teste acoplado a implementacao, teste tautologico, fatiamento horizontal)
- [.github/skills/protocolo-conformidade/](./protocolo-conformidade/): gate local obrigatorio de conformidade arquitetural e de boas praticas; use APOS implementar e ANTES de qualquer handoff, sobre o diff local, para verificar se o codigo entregue respeita `clean-architecture` e a skill da stack. Achado bloqueante reprova e devolve ao agent originador. Nao depende de pipeline.
- [.github/skills/testing-strategy/](./testing-strategy/): use para desenhar estrategia/plano de testes quando a demanda for conceitual e nao um protocolo operacional normativo

Regra de prioridade para testes:

1. `protocolo-tdd` obrigatoriamente quando houver desenvolvimento, refatoracao ou correcao de codigo. E a autoridade operacional: piramide 70/20/10, Testcontainers, Cypress sem stub de rede, DoD bloqueante e veredito registrado. Prevalece tambem sobre skills de stack com conteudo de teste (`django-tdd`, `fastapi-expert`, `nestjs-best-practices`, `fastify-best-practices`, `bats-testing-patterns`), que fornecem a mecanica da ferramenta, nunca o protocolo de entrega.
2. `tdd-test-design` como apoio dentro do ciclo exigido por `protocolo-tdd`, quando a duvida for a qualidade do teste em si. Em caso de conflito, `protocolo-tdd` prevalece.
3. `testing-strategy` quando a demanda for apenas desenho de plano, cobertura e abordagem, sem implementacao nem alteracao de codigo.

#### Decision tree rapido: `protocolo-tdd` vs `tdd-test-design` vs `testing-strategy`

1. Vou alterar codigo? Entao `protocolo-tdd` e obrigatoria, sempre.
2. Ja estou escrevendo o teste e a duvida e "o que asserto e onde testo"? Adicione `tdd-test-design`.
3. Nao vou alterar codigo e preciso apenas de um plano de testes? Use `testing-strategy` sozinha.

#### Os dois gates locais obrigatorios de uma entrega com codigo

Toda alteracao de codigo passa por dois gates locais, executados pelo proprio agent, sem pipeline:

| Gate | Skill | Pergunta que responde | Momento |
|---|---|---|---|
| Testes | [`protocolo-tdd`](./protocolo-tdd/) | o comportamento esta provado por testes reais? | durante a implementacao (red-green-refactor), fechando em `evidencia-testes-template.md` |
| Conformidade | [`protocolo-conformidade`](./protocolo-conformidade/) | o codigo entregue respeita a arquitetura e as boas praticas da stack? | apos implementar, antes de qualquer handoff |

Os dois sao obrigatorios e nao se substituem. `protocolo-tdd` valida que o comportamento funciona; `protocolo-conformidade` valida como ele foi construido. Ambos rodam localmente, classificam achados por severidade e emitem veredito em template proprio, no modo definido pelo porte da demanda (`AGENTS.md`, regra 40): compacto em P e M, completo em G. Reprovacao em qualquer um bloqueia o handoff e devolve a entrega ao agent originador.

#### Decision tree rapido: `protocolo-conformidade` vs `clean-architecture` vs skill de stack

1. Preciso decidir como desenhar antes de escrever o codigo? Use `clean-architecture` ou a skill da stack diretamente.
2. Ja escrevi o codigo e preciso verificar se ele aderiu? Use `protocolo-conformidade`, que aplica as duas anteriores sobre o diff e emite um veredito.
3. Preciso registrar formalmente a entrega depois do gate? Use `review-documentation`, referenciando o parecer de conformidade.

### Seguranca

As skills abaixo definem o que deve estar protegido. A prova por teste (cenarios negativos de autenticacao, autorizacao, tenant, entrada maliciosa e vazamento, contra backend e banco reais) e exigida pela Regra 6 de [`protocolo-tdd`](./protocolo-tdd/), que e o gate; as skills de seguranca sao a fonte das regras que esses testes provam.

#### Quando a tarefa for seguranca transversal web

Use:

- [.github/skills/security-best-practices/](./security-best-practices/)

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

- [.github/skills/api-security-best-practices/](./api-security-best-practices/)

Escopo ideal:

- auth
- authz
- token handling
- schema validation
- rate limiting
- API hardening

#### Quando a tarefa for Better Auth especificamente

Use:

- [.github/skills/better-auth-best-practices/](./better-auth-best-practices/)

Nao use esta skill para auth generica. Ela e para integracao com Better Auth.

Para os plugins do Better Auth, use as skills dedicadas:

- [.github/skills/better-auth-organization/](./better-auth-organization/): multi-tenancy, organizacoes, membros, convites, times, papeis customizados e RBAC pelo plugin `organization()`
- [.github/skills/better-auth-two-factor/](./better-auth-two-factor/): TOTP, OTP por email/SMS, backup codes, dispositivos confiaveis e fluxos de sign-in 2FA pelo plugin `twoFactor()`

Regra de prioridade para Better Auth:

1. `better-auth-best-practices` para setup do servidor/cliente, adapters, sessao e wiring de plugins.
2. `better-auth-organization` quando a demanda for multi-tenant, times ou RBAC de organizacao.
3. `better-auth-two-factor` quando a demanda for MFA, autenticador, backup codes ou step-up de login.
4. `api-security-best-practices` sempre que a modelagem de autorizacao, rate limiting ou exposicao de endpoint nao for especifica do Better Auth.

## Skills por stack

### Boas praticas genericas web

Use quando a tarefa for auditoria ou modernizacao generica sem stack especifica:

- [.github/skills/best-practices/](./best-practices/): compatibilidade de browser, baseline de seguranca e qualidade de codigo generica

Quando nao usar: prefira skills de framework (fastapi-expert, django-expert) ou skills de seguranca especializadas (security-best-practices, api-security-best-practices) quando o escopo for claro.

### Python generico

Use:

- [.github/skills/python-best-practices/](./python-best-practices/)

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

- [.github/skills/fastapi-templates/](./fastapi-templates/)

#### Quero implementar endpoints, schemas, auth ou operacao principal

Use:

- [.github/skills/fastapi-expert/](./fastapi-expert/)

#### Quero uma orientacao leve de estilo em um servico FastAPI ja existente

Use:

- [.github/skills/fastapi-python/](./fastapi-python/)

#### Quero tratar concorrencia, performance async ou event loop safety

Use:

- [.github/skills/fastapi-async-patterns/](./fastapi-async-patterns/)

Regra de prioridade para FastAPI:

1. `fastapi-expert` para implementacao principal
2. `fastapi-templates` para bootstrap e estrutura
3. `fastapi-async-patterns` para tuning async
4. `fastapi-python` para guidance leve em codigo existente

### Django

#### Quero implementar feature, model, serializer, view ou depurar ORM

Use:

- [.github/skills/django-expert/](./django-expert/)

#### Quero definir estrutura, organizacao do projeto ou padroes de arquitetura Django

Use:

- [.github/skills/django-patterns/](./django-patterns/)

#### Quero hardening e revisao de seguranca Django

Use:

- [.github/skills/django-security/](./django-security/)

#### Quero testes, TDD, pytest-django ou infraestrutura de testes

Use:

- [.github/skills/django-tdd/](./django-tdd/)

Regra de prioridade para Django:

1. `django-expert` para implementacao
2. `django-patterns` para estrutura
3. `django-security` para seguranca
4. `django-tdd` para testes

### React e frontend

#### Quero performance e composicao em React generico

Use:

- [.github/skills/frontend-react-best-practices/](./frontend-react-best-practices/)

#### Quero performance orientada a Next.js, App Router ou Vercel

Use:

- [.github/skills/vercel-react-best-practices/](./vercel-react-best-practices/)

#### Quero apoio de design de interface

Use:

- [.github/skills/interface-design/](./interface-design/)

#### Quero construir ou estilizar componentes e paginas com alta qualidade visual

Use:

- [.github/skills/frontend-design/](./frontend-design/): use para criar interfaces frontend production-grade com direcao estetica forte — componentes, landing pages, dashboards ou qualquer UI que exija qualidade visual acima do padrao generico

Regra de prioridade para frontend:

1. `react-native-best-practices` se o alvo for mobile React Native ou Expo
2. `vercel-react-best-practices` se o problema for claramente Next.js/Vercel
3. `frontend-react-best-practices` para React web framework-agnostico
4. `interface-design` para problema de sistema visual, interface ou estrutura de UX
5. `frontend-design` para construcao de UI com alta qualidade estetica e visual diferenciado

### Acessibilidade

#### Quero auditar uma pagina, tela ou design antes do handoff

Use:

- [.github/skills/accessibility-review/](./accessibility-review/)

#### Quero corrigir acessibilidade web em UI ja implementada

Use:

- [.github/skills/accessibility/](./accessibility/)

#### Quero implementar padroes acessiveis, ARIA, foco, leitores de tela ou acessibilidade mobile

Use:

- [.github/skills/accessibility-compliance/](./accessibility-compliance/)

Regra de prioridade para acessibilidade:

1. `accessibility-review` para diagnostico e parecer de auditoria, sem foco principal em implementar
2. `accessibility` para remediacao web e melhoria de acessibilidade em interfaces existentes
3. `accessibility-compliance` para implementacao de padroes acessiveis, componentes e fluxos com escopo mais construtivo e inclusive mobile

### Node.js, Fastify e NestJS

- [.github/skills/nodejs-best-practices/](./nodejs-best-practices/): use para Node.js generico, decisoes de runtime, async e arquitetura sem framework definido
- [.github/skills/fastify-best-practices/](./fastify-best-practices/): use quando a stack for Fastify; cobre rotas, plugins, JSON Schema, hooks, serializacao, Pino, WebSockets e deploy
- [.github/skills/nestjs-best-practices/](./nestjs-best-practices/): use quando a stack for NestJS

Regra de prioridade para Node.js:

1. `fastify-best-practices` ou `nestjs-best-practices` quando o framework estiver identificado.
2. `nodejs-best-practices` apenas quando a decisao for agnostica de framework.

### .NET

- [.github/skills/dotnet-clean-architecture/](./dotnet-clean-architecture/): use quando a stack for .NET/C#, para layout de projetos, use case handlers, EF Core e endpoints finos; combine com `clean-architecture` para os principios

### Mobile e React Native

- [.github/skills/react-native-best-practices/](./react-native-best-practices/): use para React Native e Expo, em FPS, TTI, tamanho de bundle, memory leaks, re-renders, Turbo Modules e animacoes

Nao use `react-native-best-practices` para React web. Nao carregue o diretorio `references/` inteiro: use o `POWER.md` da skill para escolher o arquivo especifico.

### Banco de dados e Postgres

- [.github/skills/supabase-postgres-best-practices/](./supabase-postgres-best-practices/): skill padrao de camada de dados do pacote; use antes de criar ou alterar tabelas, colunas, migrations, indices, policies RLS, funcoes, filas e jobs, e tambem para diagnosticar query lenta, EXPLAIN, lock, pooling, bloat ou vazamento entre tenants

Regra de prioridade para dados:

1. `supabase-postgres-best-practices` para schema, SQL, indices, RLS e diagnostico, mesmo em Postgres fora do Supabase.
2. `clean-architecture` quando a duvida for onde a persistencia mora nas camadas, e nao como modelar ou consultar.
3. `security-best-practices` e `api-security-best-practices` quando a mudanca alterar quais linhas um tenant ou usuario enxerga.

### PHP e Laravel

- [.github/skills/php-best-practices/](./php-best-practices/): use para PHP generico
- [.github/skills/laravel-best-practices/](./laravel-best-practices/): use quando a stack for Laravel

### Cloudflare Workers

- [.github/skills/workers-best-practices/](./workers-best-practices/): use para Workers, wrangler, bindings, observability e praticas do ecossistema Cloudflare

### Shell scripts (POSIX sh e Bash)

- [.github/skills/shellcheck-configuration/](./shellcheck-configuration/): use ao escrever, alterar ou revisar script shell (`*.sh` ou shebang `sh`/`bash`), para analise estatica com ShellCheck no dialeto do shebang, `.shellcheckrc`, diretivas e leitura dos codigos SC
- [.github/skills/bats-testing-patterns/](./bats-testing-patterns/): use para escrever ou revisar testes de script shell com Bats, dentro do ciclo de `protocolo-tdd`

Regra de prioridade para shell:

1. `protocolo-tdd` continua obrigatoria em qualquer alteracao de script; `bats-testing-patterns` fornece apenas a mecanica da ferramenta.
2. `shellcheck-configuration` e a skill de stack que `protocolo-conformidade` aplica sobre o diff de script shell.
3. O dialeto e o do shebang: os scripts do pacote sao POSIX `sh` (`set -eu`). Construcao exclusiva de Bash (`[[ ]]`, arrays, `local`, `pipefail`, `source`) em script `sh` e achado, nunca motivo para trocar o shebang.
4. `security-best-practices` quando o script manipular segredo, repassar entrada externa a comando ou `eval`, ou baixar e executar conteudo.

## Combinacoes recomendadas

Combinacoes seguras e uteis:

- `fastapi-expert` + `api-security-best-practices`
- `django-expert` + `django-security`
- `frontend-react-best-practices` + `interface-design`
- `vercel-react-best-practices` + `interface-design`
- `clean-architecture` + `review-documentation`
- `documentation-sync` + `mermaid-generator`
- `prd-generator` + `user-story-writing`
- `protocolo-tdd` + `tdd-test-design`
- `protocolo-conformidade` + `clean-architecture`
- `protocolo-conformidade` + a skill da stack detectada
- `protocolo-conformidade` + `review-documentation`
- `supabase-postgres-best-practices` + `api-security-best-practices`
- `fastify-best-practices` + `api-security-best-practices`
- `better-auth-best-practices` + `better-auth-organization`
- `better-auth-best-practices` + `better-auth-two-factor`
- `clean-architecture` + `dotnet-clean-architecture`
- `react-native-best-practices` + `accessibility-compliance`
- `shellcheck-configuration` + `bats-testing-patterns`
- `protocolo-tdd` + `bats-testing-patterns`

## Combinacoes a evitar

Evite carregar juntas sem necessidade:

- `fastapi-expert` + `fastapi-python` quando o objetivo ja estiver claro
- `django-expert` + `django-patterns` para uma unica tarefa pequena
- `security-best-practices` + `api-security-best-practices` se a demanda for claramente apenas web ou apenas API
- `frontend-react-best-practices` + `vercel-react-best-practices` quando a stack ja estiver definida
- `accessibility` + `accessibility-review` quando a necessidade for claramente apenas auditar ou claramente apenas corrigir
- `nodejs-best-practices` + `fastify-best-practices` quando o framework ja estiver definido como Fastify
- `frontend-react-best-practices` + `react-native-best-practices` quando o alvo for claramente web ou claramente mobile
- `tdd-test-design` + `testing-strategy` na mesma tarefa: uma e para escrever o teste, a outra e para planejar sem implementar
- `clean-architecture` + `dotnet-clean-architecture` quando a duvida for so principio ou so layout de projeto

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

- [.github/skills/clean-architecture/](./clean-architecture/)

### Quero revisar impacto documental apos uma entrega

- [.github/skills/documentation-sync/](./documentation-sync/)

### Quero escrever ou consolidar um review tecnico

- [.github/skills/review-documentation/](./review-documentation/)

### Quero atualizar docs existentes e tambem registrar a entrega

1. [.github/skills/documentation-sync/](./documentation-sync/)
2. [.github/skills/review-documentation/](./review-documentation/)

### Quero gerar diagrama Mermaid

- [.github/skills/mermaid-generator/](./mermaid-generator/)

### Quero escrever PRD ou historias

- [.github/skills/prd-generator/](./prd-generator/)
- [.github/skills/user-story-writing/](./user-story-writing/)

### Quero proteger uma API

- [.github/skills/api-security-best-practices/](./api-security-best-practices/)

### Quero endurecer uma aplicacao web

- [.github/skills/security-best-practices/](./security-best-practices/)

### Quero iniciar um servico FastAPI

- [.github/skills/fastapi-templates/](./fastapi-templates/)

### Quero implementar um endpoint FastAPI

- [.github/skills/fastapi-expert/](./fastapi-expert/)

### Quero estruturar ou depurar Django

- [.github/skills/django-expert/](./django-expert/)

### Quero testar Django com TDD

- [.github/skills/django-tdd/](./django-tdd/)

### Quero otimizar React

- [.github/skills/frontend-react-best-practices/](./frontend-react-best-practices/)

### Quero otimizar Next.js

- [.github/skills/vercel-react-best-practices/](./vercel-react-best-practices/)

### Quero auditar acessibilidade antes do handoff

- [.github/skills/accessibility-review/](./accessibility-review/)

### Quero corrigir acessibilidade em interface web existente

- [.github/skills/accessibility/](./accessibility/)

### Quero implementar componentes e padroes acessiveis

- [.github/skills/accessibility-compliance/](./accessibility-compliance/)

### Quero criar ou alterar schema, migration, indice ou policy RLS

- [.github/skills/supabase-postgres-best-practices/](./supabase-postgres-best-practices/)

### Quero diagnosticar query lenta, lock ou esgotamento de conexao

- [.github/skills/supabase-postgres-best-practices/](./supabase-postgres-best-practices/)

### Quero construir ou depurar um servidor Fastify

- [.github/skills/fastify-best-practices/](./fastify-best-practices/)

### Quero otimizar performance de um app React Native

- [.github/skills/react-native-best-practices/](./react-native-best-practices/)

### Quero estruturar um projeto .NET com Clean Architecture

- [.github/skills/dotnet-clean-architecture/](./dotnet-clean-architecture/)

### Quero verificar se a implementacao que acabei de fazer respeita a arquitetura

- [.github/skills/protocolo-conformidade/](./protocolo-conformidade/)

### Quero saber se posso encaminhar a entrega para QA

- [.github/skills/protocolo-tdd/](./protocolo-tdd/): o handoff so e liberado com parecer de evidencias de testes Aprovado ou Aprovado com ressalvas
- [.github/skills/protocolo-conformidade/](./protocolo-conformidade/): o handoff so e liberado com parecer Aprovado ou Aprovado com ressalvas

### Quero escrever um teste melhor dentro do ciclo TDD

1. [.github/skills/protocolo-tdd/](./protocolo-tdd/)
2. [.github/skills/tdd-test-design/](./tdd-test-design/)

### Quero escrever, revisar ou testar um script shell

1. [.github/skills/shellcheck-configuration/](./shellcheck-configuration/)
2. [.github/skills/bats-testing-patterns/](./bats-testing-patterns/)

### Quero implementar multi-tenancy ou 2FA com Better Auth

- [.github/skills/better-auth-organization/](./better-auth-organization/)
- [.github/skills/better-auth-two-factor/](./better-auth-two-factor/)

## Resultado esperado

Ao usar este arquivo, voce deve conseguir:

- reduzir sobreposicao entre skills;
- acionar a skill certa mais cedo;
- evitar combinacoes redundantes;
- tornar a descoberta do catalogo mais previsivel.