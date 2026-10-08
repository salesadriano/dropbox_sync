# Evolucao do Pacote: Skills, Vulnerabilidades, Sobreposicoes e Governanca dos Agents

**Data:** 2026-03-31
**Responsavel:** Tech Lead (consolidacao autonoma)
**Commits de referencia:** `16dded4`, `b04d18a` e commits do loop autoresearch

---

## Contexto

Esta sessao cobriu quatro frentes de evolucao autonoma do pacote:

1. **Loop autoresearch em `.github/agents/`**: maximizacao de referencias a skills nos arquivos de agent.
2. **Loop autoresearch em `.github/skills/`**: adicao de subdiretórios `references/` com material operacional rapido.
3. **Analise e correcao de vulnerabilidades e sobreposicoes em `.github/skills/`**.
4. **Analise e correcao de lacunas estruturais e de governanca em `.github/agents/`**.

---

## 1. Loops autoresearch — referencias e references

### Agents — novas referencias a skills inseridas

| Agent | Skills adicionadas |
|---|---|
| `ux-expert.agent.md` | `interface-design`, `accessibility`, `design-md` |
| `dba.agent.md` | `security-best-practices`, `api-security-best-practices` |
| `qa-expert.agent.md` | `accessibility-review`, `accessibility-compliance` |
| `senior-developer.agent.md` | `frontend-react-best-practices`, `best-practices` |
| `tech-lead.agent.md` | `security-best-practices` |
| `AGENTS.md` | Tabela de mapeamento stack → skill (Django, FastAPI, NestJS, React, etc.) |

### Skills — subdiretórios `references/` criados

| Skill | Arquivo criado |
|---|---|
| `security-best-practices` | `references/owasp-top10.md` — exemplos por categoria OWASP A01–A10 |
| `accessibility-review` | `references/checklist.md` — checklist WCAG AA, padroes de componente, ferramentas |
| `python-best-practices` | `references/patterns.md` — type safety, error handling, testing, módulos |
| `nodejs-best-practices` | `references/patterns.md` — async patterns, streams, graceful shutdown |
| `api-security-best-practices` | `references/auth-patterns.md` — JWT RS256, API key hashing, OAuth/PKCE, ABAC |
| `frontend-react-best-practices` | `references/hooks-patterns.md` — data fetching, stale closures, context splitting |
| `user-story-writing` | `references/templates.md` — Gherkin, DoD checklist, Fibonacci sizing |
| `best-practices` | `references/principles.md` — SOLID, DRY/DAMP, YAGNI, KISS, CQS |
| `documentation-sync` | `references/sync-strategy.md` — decision tree, atomic PR checklist |
| `frontend-design` | `references/design-tokens.md` — color system, spacing, typography, dark mode |

---

## 2. Vulnerabilidades corrigidas em skills

### CSP nonce estatico (`security-best-practices/SKILL.md`)

**Problema:** O exemplo Helmet no SKILL.md usava `'nonce-random123'` — um nonce estatico/hardcoded, que e equivalente a nenhum nonce e invalida a protecao CSP contra scripts injetados.

**Correcao:** Substituido por middleware per-request usando `crypto.randomBytes(16).toString('base64')`, com `res.locals.cspNonce` propagado para o template e para a configuracao do Helmet. Comentario explicito foi adicionado: "NEVER use a static/hardcoded string — a fixed nonce is equivalent to no nonce."

### MD5PasswordHasher sem aviso suficiente (`django-tdd/SKILL.md`)

**Problema:** O exemplo de teste Django configurava `MD5PasswordHasher` com apenas um comentario `# Testing only` — insuficiente para prevenir uso acidental em staging/production, dado que MD5 e trivialmente craqueavel com rainbow tables.

**Correcao:** O comentario foi substituido por um bloco `# SECURITY WARNING` explícito descrevendo que MD5 é um algoritmo quebrado para senhas, restrito a test suites por velocidade, e proibido em development, staging e production.

---

## 3. Sobreposicoes resolvidas entre skills

### `accessibility-review` desatualizada para WCAG 2.1 (`accessibility-review/SKILL.md`)

**Problema:** `accessibility` e `accessibility-compliance` ja cobriam WCAG 2.2, mas `accessibility-review` ainda auditava contra WCAG 2.1, omitindo 6 novos criterios AA (2.4.11, 2.5.7, 2.5.8, 3.2.6, 3.3.7, 3.3.8).

**Correcao:** SKILL.md e o template de output foram atualizados para WCAG 2.2 AA. Os 6 novos criterios foram adicionados com marcacao `*(new in 2.2)*` para rastreabilidade.

### Escopo ambiguo entre `django-security` e `security-best-practices`

**Problema:** `django-security` nao delimitava seu escopo em relacao a `security-best-practices`, criando risco de uso duplicado ou omissao de hardening generico (HTTPS headers, CSP, CORS, rate limiting, segredos).

**Correcao:** Adicionada nota de delimitacao de escopo no topo de `## When to Activate` em `django-security/SKILL.md`, com links explícitos para `security-best-practices` (hardening generico) e `api-security-best-practices` (JWT, OAuth, API keys).

---

## 4. Lacunas estruturais e de governanca corrigidas nos agents

### `ux-expert.agent.md` — entrega obrigatoria formalizada

**Problema:** A secao de entregas estava rotulada como `## Artefatos recomendados`, sinalizando opcionalidade, enquanto todos os outros agents usavam `## Entrega obrigatoria`.

**Correcao:**
- Renomeado para `## Entrega obrigatoria`.
- Adicionado item obrigatorio: "Parecer formal de UX encaminhado ao Tech Lead."
- Adicionado item obrigatorio: "Registro das divergencias identificadas entre Design System, implementacao e evidencias visuais, com recomendacao para o Tech Lead."
- Adicionada referencia obrigatoria a `frontend-design` skill.

### `dba.agent.md` — trigger de acionamento indefinido

**Problema:** O DBA descrevia o que faz, mas nao quando/como e acionado. O Senior Developer tem regra de gate obrigatorio com o DBA, mas o DBA nao tinha visibilidade explicita desse trigger nem das excecoes.

**Correcao:**
- Adicionada secao `## Quando atuar` descrevendo que o DBA e acionado pelo Senior Developer em qualquer mudanca de persistencia (novo modelo, migracao, nova entidade, indices, politicas de acesso) e diretamente pelo Tech Lead para revisoes de capacidade ou auditorias de seguranca.
- Reforçada a regra: "o Senior Developer nao pode fechar implementacao de persistencia sem parecer do DBA."

### `AGENTS.md` — stack detection sem mapeamento para skills

**Problema:** A secao de deteccao de stack listava arquivos a verificar, mas nao mapeava os resultados para skills disponíveis. Agents detectavam Django, FastAPI, NestJS etc. mas nao sabiam qual skill consultar.

**Correcao:** Adicionada tabela de mapeamento stack → skill:

| Stack detectada | Skill de referencia |
|---|---|
| Python / Django | `django-expert`, `django-patterns`, `django-tdd` |
| Python / FastAPI | `fastapi-expert`, `fastapi-templates`, `fastapi-async-patterns` |
| Python generico | `python-best-practices` |
| Node.js / NestJS | `nestjs-best-practices` |
| Node.js generico | `nodejs-best-practices` |
| PHP / Laravel | `laravel-best-practices` |
| React / Next.js | `vercel-react-best-practices` |
| React generico | `frontend-react-best-practices` |
| Cloudflare Workers | `workers-best-practices` |
| Autenticacao (any) | `better-auth-best-practices` |

---

## Impacto global

- Agents passam a referenciar skills especializadas de forma sistematica, reduzindo lacunas de conhecimento operacional.
- Skills possuem material de referencia rapida (`references/`) alinhado ao papel dos agents que as consomem.
- Vulnerabilidades de segurança em exemplos de codigo foram corrigidas antes de chegarem a uso em projetos reais.
- Sobreposicao entre skills de acessibilidade foi eliminada pela unificacao da versao WCAG.
- Governanca dos agents esta mais explicita: triggers de acionamento, entregas obrigatorias vs. recomendadas, e mapeamento de skills por stack.

---

## Riscos residuais

- Skills de stack (`django-expert`, `fastapi-expert`, `laravel-best-practices`, etc.) referenciadas na tabela de mapeamento podem nao existir no workspace atual — agents devem verificar disponibilidade antes de consumir.
- A tabela de mapeamento em `AGENTS.md` deve ser mantida atualizada quando novas skills forem adicionadas ao pacote.
