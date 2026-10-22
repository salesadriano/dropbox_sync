---
id: 2026-10-18-2243-cache-unico-e-segredo
tipo: decisao
escopo: projeto
titulo: lib/state e o cache unico, lib/db sai; client_secret obrigatorio; paralelismo adiado
data: 2026-10-18
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst, dba
status: ativa
ref: docs/prompts/2026-10-18_2243_cache-unico-p3.md
---

Decididos pelo solicitante em 2026-10-18 (fase 3):
- **Cache único:** o `lib/state` (arquivo NUL, sem dependência, RNF-26) é o único cache de `content_hash`. O `lib/db` (SQLite) é removido, junto com a dependência de `sqlite3`/`python3`. O upload passa a usar o `lib/state`.
- **Autenticação:** o `client_secret` é obrigatório também na biblioteca; PKCE não é implementado e deixa de constar como disponível.
- **Paralelismo e APIs em lote:** ficam adiados, no backlog, com medição prévia.
