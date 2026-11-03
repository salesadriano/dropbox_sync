---
id: 2026-11-03-1203-reaceite-testes-qa-robustez-rede-p2
tipo: aceite
escopo: projeto
titulo: Solicitante reaprova a suite do QA qa_robustez_rede_p2 com o bloco de quatro registros falha_* do RF-208
data: 2026-11-03
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
substitui: 2026-10-27-1500-aceite-reaprovacao-inventario
regra: AGENTS.md 12
ref: docs/reviews/2026-11-03-1203-registro-relatorio-com-tamanho-e-motivo.md
---

Reaprovacao do solicitante pela regra 12 (prompt 3, 2026-11-03, "accept the sha"), na demanda `relatorio-com-tamanho-e-motivo`, valendo para as duas linhas (`develop` e `support/bash-4.2`):

- `tests/integracao/qa_robustez_rede_p2_test.sh` (21 casos; dois casos de `--json`, `teste_qa_json_com_null_emite_os_pares_terminados_em_nul` e `teste_qa_json_com_tres_falhas_de_classes_distintas_mantem_a_ordem`, passaram a esperar o bloco `falha_caminho`/`falha_classe`/`falha_motivo`/`falha_tamanho` do `RF-208(d)` em vez do par de `RF-59(b)`): sha256 `b6ce38a8dccdcc650781bfe642798ded7827a9e7d6406f6682be21b1caa92477`.

A entrada substituida continua valendo para as outras quatro suites que ela reaprovou; so a de `qa_robustez_rede_p2` muda de sha aqui.
