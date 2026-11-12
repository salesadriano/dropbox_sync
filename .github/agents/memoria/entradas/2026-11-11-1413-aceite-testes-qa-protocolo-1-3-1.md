---
id: 2026-11-11-1413-aceite-testes-qa-protocolo-1-3-1
tipo: aceite
escopo: projeto
titulo: Solicitante aprova a remocao do caso inerte da suite qa_debug_transferencias_b12 e o Bats do QA da auditoria de casos adaptada
data: 2026-11-11
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-11-11-1413-registro-protocolo-atual-1-3-1.md
---

Aceite em lote (AskUserQuestion, 2026-11-11, "Aprovo os dois"):
- `tests/integracao/qa_debug_transferencias_b12_test.sh` (27 casos; sai `teste_qa_download_hash_divergente_registra_e_mantem_codigo`, coberto por `teste_tc_dbg_15_hash_divergente_aparece_antes_do_erro_11`): sha256 `3edd64eb7e81b0ca49490de2031c9ff77b5a2afe1cfc37a826440efc9a458ec6`.
- `scripts/tests/qa-auditar-casos-harness-do-projeto.bats` (11 casos): sha256 `c80c6c069331b3c784d9530bac764b180f739e6013f5fcc7efe9b80453a040f8`.
