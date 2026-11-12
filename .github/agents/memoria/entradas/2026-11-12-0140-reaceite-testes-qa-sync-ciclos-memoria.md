---
id: 2026-11-12-0140-reaceite-testes-qa-sync-ciclos-memoria
tipo: aceite
escopo: projeto
titulo: Solicitante reaceita a suite do QA da memoria por ciclo apos a troca de $(printf) por literal
data: 2026-11-12
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, qa-expert
status: ativa
substitui: 2026-11-11-1827-aceite-testes-qa-sync-ciclos-memoria
regra: AGENTS.md 12
ref: docs/reviews/2026-11-11-1827-registro-sync-ciclos-exclusao-indevida.md
---

Reaceite do solicitante pela regra 12 (AskUserQuestion, 2026-11-12, "Reaceito"): a suite completa parou em `json_test.sh` (RSK-28, massa por `$(printf`) na linha do duble; o Tech Lead trocou `$(printf %064d 0)` por 64 zeros literais, sem mudar caso.

- `tests/integracao/qa_sync_ciclos_memoria_f101_test.sh` (6 casos): sha256 `cb8665e0e98b858a60cc108517d0462936eab5bb7d3e9cce36ec29a8c2eaa624`.
