---
id: 2026-10-19-1050-aceite-testes-qa-b1
tipo: aceite
escopo: projeto
titulo: Solicitante aprova a suite do QA da fase 1 do backlog e reaprova dois arquivos de fases anteriores
data: 2026-10-19
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-10-19-1050-registro-consulta-diagnostico-b1.md
---

O solicitante aprovou explicitamente:
- `tests/integracao/qa_consulta_diagnostico_b1_test.sh` (novo, 21 casos, sha256 `9bf94d63…7ed8`);
- `tests/integracao/qa_cache_unico_p3_test.sh` (reaprovação; a simulação passou a proibir só escrita e fixa as leituras permitidas; sha256 `337adb84…c98c`);
- `tests/integracao/qa_robustez_rede_p2_test.sh` (reaprovação; o duplo responde `get_space_usage`; sha256 `5289027e…ac4a77`).

Também decidiu corrigir o F-36 (`raiz_remota` nunca aplicada) e o F-37 (quebra de linha em caminho remoto) numa fase extra, logo após a fase 1 e antes da trava.
