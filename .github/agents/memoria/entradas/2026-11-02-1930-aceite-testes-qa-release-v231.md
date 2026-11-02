---
id: 2026-11-02-1930-aceite-testes-qa-release-v231
tipo: aceite
escopo: projeto
titulo: Solicitante reaceita tres suites do QA da linha legada apos a sonda de localidade ir para tests/support
data: 2026-11-02
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-11-02-1930-registro-release-v231.md
---

Aceite do solicitante pela regra 12 (AskUserQuestion, 2026-11-02, "Accept the 3 suites"), na demanda `release-v231` (`QA-B42-03`), linha legada `support/bash-4.2`. As tres suites mudam so pela troca da copia de `_localidade_disponivel` pela carga de `tests/support/localidade.sh`, sem assert tocado (validacao do QA em `docs/reviews/2026-11-02-1930-validacao-qa-release-v231.md`):

- `tests/integracao/qa_debug_transferencias_b12_test.sh`: sha256 `4021027bd57c99cb1ab920a48650313f5bc0e4cd205b841856dc00a31c17ef4c`
- `tests/integracao/qa_filtros_banda_b4_test.sh`: sha256 `cfb707a2c555024fe121850e71d0c62729c805d5f4aec89147dc9017ae51d589`
- `tests/integracao/qa_retencao_b6_test.sh`: sha256 `6a9d2e1a662884bf26b90ce067dc4ff0a0cba9511289187f0e55bf37563417a6`
