---
id: 2026-11-03-1017-aceite-testes-qa-arquivo-remoto-no-lugar-da-pasta
tipo: aceite
escopo: projeto
titulo: Solicitante aceita a suite do QA que prova o sync tolerante a arquivo remoto no lugar de uma pasta
data: 2026-11-03
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-11-03-1017-registro-arquivo-remoto-no-lugar-da-pasta.md
---

Aceite do solicitante pela regra 12 (prompt 2, 2026-11-03, "accept the sha and fix the legacy line too"), na demanda `arquivo-remoto-no-lugar-da-pasta` (defeito em producao na 2.3.2, `DIV-394`), valendo para as duas linhas (`develop` e `support/bash-4.2`):

- `tests/integracao/qa_pasta_ocupada_test.sh` (6 casos: subpasta ocupada por arquivo com `--espelhar`, aviso sem `-p`, sem `--espelhar`, raiz do destino que e arquivo, `--dry-run`, pasta ocupada em ciclo posterior com `--bloco 1`; reprova 6 de 6 sem a correcao): sha256 `d7cd09d4127d25750aa9b10acda60bbc465846a079599688e34babd368d754eb`.

No mesmo prompt o solicitante decidiu levar a correcao tambem a linha legada.
