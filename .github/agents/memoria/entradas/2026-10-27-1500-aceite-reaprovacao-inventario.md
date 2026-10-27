---
id: 2026-10-27-1500-aceite-reaprovacao-inventario
tipo: aceite
escopo: projeto
titulo: Solicitante reaprova cinco suites do QA alteradas apos o aceite, achadas na adocao do inventario de testes
data: 2026-10-27
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-10-27-1500-registro-protocolo-atual.md
---

Na adocao da regra 51 (inventario de testes), cinco suites do QA nao tinham registro de aceite para o sha256 atual: foram alteradas depois do aceite original sem nova aprovacao (a mais recente em 2026-10-22). O solicitante reaprovou as versoes atuais (AskUserQuestion, 2026-10-27, "Reaprovo as 5"):

- `tests/integracao/qa_desempenho_b9_test.sh`: sha256 `2630f5364fd3da79f3f6a36ca67b61722b9f010e50a86f6d7603e312bef90c47`
- `tests/integracao/qa_robustez_rede_p2_test.sh`: sha256 `1f1731bf33212622ad5e5bc4777cd415faf7fea39c7cd2adeb9f668741edd565`
- `tests/integracao/qa_integridade_p1_test.sh`: sha256 `f87cadfaa15b3168a0180b3bb89b23dbd94124ba7b3f5b3f5c566a5ac1d50952`
- `tests/integracao/qa_retomada_b7a_test.sh`: sha256 `593d475f63d8e06738cccd88342bb27af38094077e2754a8d8ed4896a1ecf8dc`
- `tests/integracao/qa_filtros_banda_b4_test.sh`: sha256 `61080fd0fbdff324ca537c683ab3f41610725b51a50b6b76dc870c93e852ab42`

Licao: toda alteracao em arquivo `qa_*` volta ao lote da regra 12 no mesmo ciclo; o inventario (campo Aceite do solicitante) e o ponto onde a divergencia aparece.
