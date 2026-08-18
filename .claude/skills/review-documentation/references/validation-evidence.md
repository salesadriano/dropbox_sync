# Validation Evidence — Referência Rápida

Padrões de documentação da seção `## Evidências de validação` por tipo de entrega.

## Regra base

Evidência de validação deve sempre declarar explicitamente:
1. **O que foi executado** — comando, ferramenta ou inspeção manual
2. **Onde foi executado** — ambiente (local, CI, staging, prod)
3. **Resultado** — saída resumida ou status
4. **O que não foi executado** — declaração honesta de lacunas

> Regra editorial: se a validação não foi executada, **declare isso explicitamente**.
> Nunca omita a seção ou deixe campos vagos como "testado localmente".

---

## Por tipo de entrega

### Código / Testes unitários e integração

```markdown
## Evidências de validação

Ambiente: local + CI (GitHub Actions)

```bash
# Suite completa
pytest tests/ -v --tb=short

# Cobertura
pytest tests/ --cov=app --cov-report=term-missing
```

Resultado:
- `128 passed, 0 failed, 2 skipped` — skips documentados em `tests/SKIP_REASONS.md`
- Cobertura: `87%` — módulos novos cobertos; módulo legado `payments/legacy.py` excluído intencionalmente
- CI: pipeline verde no commit `abc1234`

Validação não executada:
- Testes E2E — dependem de ambiente de staging; executados pelo QA Expert em ciclo separado.
```

### Schema / Migration

```markdown
## Evidências de validação

Ambiente: banco de dados local (Docker), schema idêntico ao de staging.

```bash
# Aplicar migration
python manage.py migrate orders 0015_add_deleted_at

# Verificar estrutura
python manage.py dbshell
\d orders
```

Resultado:
- Coluna `deleted_at TIMESTAMP NULL DEFAULT NULL` criada com sucesso
- Índice `idx_orders_active` (WHERE deleted_at IS NULL) criado
- `SELECT COUNT(*) FROM orders WHERE deleted_at IS NULL;` retornou `14.832` registros — sem perda de dados

```bash
# Rollback testado
python manage.py migrate orders 0014
```
- Migration revertida com sucesso; coluna removida; dados preservados

Validação não executada:
- Performance sob carga real — DBA deve validar plano de execução em staging antes do deploy em prod.
```

### API / Endpoints

```markdown
## Evidências de validação

Ambiente: local com servidor dev (`uvicorn main:app --reload`)

```bash
# Smoke test manual
curl -X POST http://localhost:8000/api/orders \
  -H "Authorization: Bearer <token-de-teste>" \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "quantity": 2}'

# Resposta
HTTP 201 Created
{"id": 42, "status": "pending", "created_at": "2026-03-31T10:00:00Z"}

# Cenário de erro — token inválido
curl -X POST http://localhost:8000/api/orders \
  -H "Authorization: Bearer token-invalido" \
  -d '{...}'

# Resposta
HTTP 401 Unauthorized
{"detail": "Invalid or expired token"}
```

Resultado:
- Happy path: `201 Created` com payload correto
- Auth failure: `401` com mensagem adequada (sem stack trace exposto)
- Schema OpenAPI gerado automaticamente: `GET /openapi.json` retornou spec atualizada

Validação não executada:
- Rate limiting — requer ambiente com Redis; pendente para teste em staging.
- Teste de carga — pendente relatório do QA Expert.
```

### Segurança / Hardening

```markdown
## Evidências de validação

Ambiente: local + revisão manual de configuração.

```bash
# Verificar headers de segurança
curl -I https://localhost:3000

# Saída relevante
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Strict-Transport-Security: max-age=31536000; includeSubDomains
Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-<hash>'
```

Resultado:
- Todos os headers críticos presentes e com valores corretos
- Nonce CSP é dinâmico (verificado com 3 requests consecutivos — valores distintos)
- `SECRET_KEY` não presente em nenhum arquivo commitado (`git grep SECRET_KEY` retornou vazio)

Ferramentas complementares:
- `npm audit` — 0 vulnerabilidades críticas ou altas
- `bandit -r app/` — 0 issues de severidade alta (2 low ignorados: falsos positivos em `assert` de testes)

Validação não executada:
- Pentest formal — fora do escopo desta entrega; recomendado antes do lançamento em prod.
```

### Infraestrutura / CI

```markdown
## Evidências de validação

Ambiente: branch de feature no GitHub Actions.

```bash
# Pipeline executado em: github.com/<org>/<repo>/actions/runs/<run-id>
```

Resultado:
- Todos os jobs passaram: `build`, `test`, `lint`, `docker-build`
- Tempo de build Docker: `3m 12s` (baseline anterior: `4m 50s` — melhoria de ~34% com cache de layer)
- Imagem gerada: `ghcr.io/<org>/<repo>:sha-abc1234`
- Deploy em staging: `kubectl rollout status deployment/<nome>` — `successfully rolled out`

Validação não executada:
- Teste de rollback de infra em prod — executado apenas em staging; janela de prod pendente aprovação.
```

### Mudança puramente documental

```markdown
## Evidências de validação

Tipo: revisão editorial (sem execução de código).

Inspeção realizada:
- Links internos verificados manualmente: todos resolvem para seções existentes
- Exemplos de código revisados: sintaxe correta, sem anti-padrões
- Consistência com SKILL.md verificada: terminologia e referências alinhadas

```bash
# Verificar links quebrados (se disponível no projeto)
npx markdown-link-check docs/ONBOARD.md
# Resultado: 0 broken links
```

Validação não executada:
- Validação automatizada de links externos — não configurada no CI; recomendado como melhoria futura.
```

---

## Declaração de ausência de validação (template)

Quando a validação não pode ser executada, use:

```markdown
## Evidências de validação

Validação automatizada não executada nesta entrega.

Motivo: <razão objetiva — ex: "ambiente de staging indisponível no momento da entrega">

Mitigação adotada: <ex: "revisão manual do código + revisão por par antes do merge">

Pendência: <ex: "QA Expert deve executar suite completa em staging antes do merge para main">
```

> **Nunca** deixe a seção vazia ou com apenas "testado localmente". Declare o que foi feito e o que não foi.
