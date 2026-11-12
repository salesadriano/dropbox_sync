---
id: 2026-11-11-2210-aceite-testes-qa-sync-orfaos-no-fim
tipo: aceite
escopo: projeto
titulo: Solicitante aceita a suite do QA dos orfaos apagados so no fim do sync
data: 2026-11-11
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-11-11-2210-registro-sync-orfaos-no-fim.md
---

Aceite do solicitante pela regra 12 (AskUserQuestion, 2026-11-11, "Aceito a suite"), na demanda `sync-orfaos-no-fim`:

- `tests/integracao/qa_sync_orfaos_no_fim_test.sh` (12 casos: pasta movida com envio do novo antes da exclusao do antigo, ciclo falho, morte por sinal, `--receber` interrompido, travessia parcial, origem vazia recusada e permitida, filtro, caixa, `--dry-run`, nome-isca com substituicao de comando): sha256 `d4a02858cc1663350b976b187ed35c01bac098cf5a1d2d70c6ad2f843c1c61eb`.
