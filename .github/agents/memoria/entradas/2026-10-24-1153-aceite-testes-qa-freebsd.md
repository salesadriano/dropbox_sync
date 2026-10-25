---
id: 2026-10-24-1153-aceite-testes-qa-freebsd
tipo: aceite
escopo: projeto
titulo: Solicitante aprova a suite do QA do suporte a FreeBSD e reaprova a da fase 4
data: 2026-10-24
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-10-24-1153-registro-suporte-freebsd.md
---

O solicitante aprovou explicitamente (AskUserQuestion, 2026-10-24):
- `tests/integracao/qa_freebsd_b13_test.sh` (novo, 5 casos, sha256 `fb7e9191…ca7488`);
- `tests/integracao/qa_docs_aliases_p4_test.sh` (reaprovacao; o filtro dos utilitarios de resumo passou a incluir `sha256`, DIV-354; sha256 `17192612…708467`).

Reaprovacao (AskUserQuestion, 2026-10-25): `tests/integracao/qa_freebsd_b13_test.sh` com 10 casos (o caso da recusa sem fdescfs saiu pela decisao "Conferir pelo descritor"; entraram 6 casos do comportamento novo), sha256 `20420830…711d006b`.

Reaprovacao (AskUserQuestion, 2026-10-25): `tests/integracao/qa_trava_tmp_b2_test.sh` (suite da fase 2), caso `qa_b2_01` corrigido para aceitar as 2 travas (par e raiz, RF-132) quando a vencedora e um `sync`; defeito do teste anterior a demanda; sha256 `2114eaa2…df6d3333`.
