---
id: 2026-11-02-0840-aceite-testes-qa-release-v230
tipo: aceite
escopo: projeto
titulo: Solicitante aceita os casos do QA na fronteira do tokenizador JSON e a suite de exclusao sem localidade na linha principal
data: 2026-11-02
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-11-02-0840-registro-release-v230.md
---

Aceite do solicitante pela regra 12 (AskUserQuestion, 2026-11-02, "Accept (Recommended)"), na demanda `release-v230` (retorno de `QA-B42-01` e do tokenizador linear a linha principal, PR #76):

- `tests/unit/json_test.sh`, casos `qa_rel230_03_*` (4 casos do QA: escape, multibyte, delimitadores e controle cru na fronteira de 4096 caracteres; equivalencia com o tokenizador anterior; 2 mutantes mortos): sha256 do arquivo `183c16f23d3e1c5ac312c45d6c5b9f5e514ff9d4709610b44e3528453851db4e`
- `tests/integracao/qa_exclusao_sem_localidade_b42_test.sh` (copia sem mudanca da suite aceita na linha legada): sha256 `7654cd1a2c966e00aa6d51519962bf3195c2ce76df62b56db809ba4c91e0d033`
