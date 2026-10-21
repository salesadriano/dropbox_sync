---
date: 2026-10-21
hora: "0713"
domain: deteccao de mudancas por cursor no sync remoto para local
porte: G
status: em-andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-21-0713-registro-cursor-b7b.md"
---

# backlog-fase-7b-cursor

## Prompt 1 — 2026-10-21 (depois do merge da PR #48)

> gh pr merge 48 --merge

**Intenção:** o solicitante mesclou a PR #48, que fecha a fase 7a (F-03). O trabalho segue a instrução "analise e implemente os itens no backlog", agora na fase 7b do plano (`2026-10-19-1023-plano-do-backlog`): F-14, detecção de mudanças por cursor.

**Decisões do solicitante, tomadas na abertura da fase 7 (memória `2026-10-20-2315-retomada`):**
- **Cursor (F-14):** "No sync remoto→local (Recomendado)". O estado só acelera; cursor inválido ou expirado volta à varredura completa.
- **Exclusão via cursor:** "Confirmar no servidor antes (Recomendado)". Sem confirmação na mesma execução, nada é apagado.

**Porte G:** estado local persistente entre execuções (namespace `cursor-*`), reabre a `DP-09` e aciona o DBA. Branch `feature/cursor-b7b`, a partir de `develop` (`a6b5376`); nenhum PR aberto.

## Prompt 2 — 2026-10-21 (aprovação da suíte do QA)

**Decisão do solicitante (AskUserQuestion):** "Aprovo". A suíte do QA da fase 7b é `tests/integracao/qa_cursor_b7b_test.sh`, com 49 casos e sha256 `8c40c6f0f77ea0dd9e147e4ba6e21898366e7e131f5b51043e021ce05235e4b6`.
