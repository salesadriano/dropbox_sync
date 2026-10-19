---
id: 2026-10-18-1745-reaceite-2-testes-qa-p1
tipo: aceite
escopo: projeto
titulo: Solicitante reaprova a suite do QA da fase P1 com 27 casos apos a correcao do RNF-24
data: 2026-10-18
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-10-18-1745-registro-integridade-de-dados-p1.md
---

O solicitante reaprovou `tests/integracao/qa_integridade_p1_test.sh` com 27 casos. Os quatro novos cobrem a cadeia de vínculos relativos até um nome com quebra final, o vínculo em ciclo, o `client_modified` em UTC num fuso com horário de verão e o hash publicado sem valor residual. Complementa `2026-10-18-1745-reaceite-testes-qa-p1`.
