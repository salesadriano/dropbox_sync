---
id: 2026-11-04-1742-aceite-testes-qa-trava-raiz-diretorio-sumido
tipo: aceite
escopo: projeto
titulo: Solicitante aceita a suite do QA que prova a espera pela trava de raiz com o diretorio de estado sumido
data: 2026-11-04
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-11-04-1742-registro-trava-raiz-diretorio-sumido.md
---

Aceite do solicitante pela regra 12 (prompt 2, 2026-11-04, "accept the sha, both lines"), na demanda `trava-raiz-diretorio-sumido` (`DIV-396`, causa da intermitencia do `pft03` na suite legada), valendo para as duas linhas (`develop` e `support/bash-4.2`):

- `tests/integracao/qa_trava_raiz_diretorio_sumido_test.sh` (6 casos: espera conclui com o diretorio apagado na janela da sondagem, quem recriou remove ao soltar, diretorio alheio permanece, diretorio sem escrita e de outro dono continuam 6, limite de repeticoes; reprova 3 de 6 sem a correcao): sha256 `ccf0339924721ba1b6d5f088a542a5e4574a790c44916fee3243af1e21ab85d9`.
