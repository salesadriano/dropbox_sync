# Sanitizacao do prompt-logger e normalizacao de skills afetadas

## Contexto

Foi identificada uma combinacao de riscos altos e sobreposicoes operacionais no catalogo de skills:

- o `prompt-logger` e o protocolo comum permitiam a persistencia literal de prompts sem regra explicita de sanitizacao de dados sensiveis;
- havia exemplos de CSP com nonce estatico em skills de seguranca;
- `django-security` misturava guidance moderno com exemplos contraditorios de CSRF e headers legados;
- skills de seguranca, design e acessibilidade ainda tinham boundaries suficientemente proximos para gerar roteamento ambíguo.

## Decisoes

1. O `prompt-logger` passa a exigir sanitizacao obrigatoria antes de persistir prompts com segredos, credenciais, tokens, cookies, PII desnecessaria ou material sensivel copiado de ambientes protegidos.
2. O protocolo comum em `AGENTS.md` passa a exigir explicitamente a remocao ou mascaramento desses dados antes da criacao do log.
3. Exemplos com nonce estatico foram removidos ou substituidos por placeholders de nonce por request nas skills de seguranca afetadas.
4. `security-best-practices` foi reduzida ao escopo browser-facing e cross-cutting; `api-security-best-practices` ficou responsavel por auth/authz, throttling, quotas e token handling no boundary de API.
5. `django-security` passou a enfatizar hardening/auditoria, removendo guidance obsoleto e corrigindo o fluxo de CSRF para cenarios com `CSRF_COOKIE_HTTPONLY = True`.
6. `frontend-design`, `interface-design` e o trio de acessibilidade tiveram descricoes e boundaries ajustados para reduzir ambiguidade de roteamento.

## Arquivos impactados

- `.github/agents/AGENTS.md`
- `.github/agents/memoria/MEMORIA-COMPARTILHADA.md`
- `.github/skills/prompt-logger/SKILL.md`
- `.github/skills/security-best-practices/SKILL.md`
- `.github/skills/api-security-best-practices/SKILL.md`
- `.github/skills/django-security/SKILL.md`
- `.github/skills/best-practices/SKILL.md`
- `.github/skills/interface-design/SKILL.md`
- `.github/skills/frontend-design/SKILL.md`
- `.github/skills/accessibility/SKILL.md`
- `.github/skills/accessibility-review/SKILL.md`
- `.github/skills/accessibility-compliance/SKILL.md`

## Efeito esperado

- Reduzir risco de vazamento de dados sensiveis para o repositório.
- Eliminar exemplos inseguros que poderiam ser copiados para projetos consumidores.
- Melhorar previsibilidade na selecao de skills por escopo.
- Preservar o pacote como baseline portavel e auditavel.
