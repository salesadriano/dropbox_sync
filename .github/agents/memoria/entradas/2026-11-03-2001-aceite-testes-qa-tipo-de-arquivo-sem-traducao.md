---
id: 2026-11-03-2001-aceite-testes-qa-tipo-de-arquivo-sem-traducao
tipo: aceite
escopo: projeto
titulo: Solicitante aceita a suite do QA que prova a trava legivel com stat traduzido
data: 2026-11-03
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-11-03-2001-registro-tipo-de-arquivo-sem-traducao.md
---

Aceite do solicitante pela regra 12 (prompt 2, 2026-11-03, "accept the sha, legacy line too"), na demanda `tipo-de-arquivo-sem-traducao` (defeito em producao na 2.3.3-bash42, Oracle Linux 7 em pt_BR, `DIV-395`), valendo para as duas linhas (`develop` e `support/bash-4.2`):

- `tests/integracao/qa_tipo_sem_traducao_test.sh` (6 casos: trava orfa retomada, trava viva dita ocupada, `LC_ALL` exportado em pt_BR, `diagnostico` com trava viva, cursor do `--receber` continuado, controle de trava realmente ilegivel; reprova 5 de 6 sem a correcao): sha256 `c88e5c4a7cfe3666c5ab3f5649964d786ab44e48939929ef05385d9f1c91132e` (prompt 3, "accept the new sha, both lines"), que substitui `83bff6c50d1ea8741c20b567cc2da06d9dcbf5989f1d00aabe106bc0c6b0b2c1` (prompt 2) depois da troca de `grep -c` por `_harness_contar` na linha 150, exigida pela auditoria `composicao_test`.

No mesmo prompt o solicitante decidiu levar a correcao tambem a linha legada.
