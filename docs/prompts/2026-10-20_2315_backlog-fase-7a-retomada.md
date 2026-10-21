---
date: 2026-10-20
hora: "2315"
domain: retomada de transferencia entre execucoes
porte: G
status: em-andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-20-2315-registro-retomada-b7a.md"
---

# backlog-fase-7a-retomada

## Prompt 1 — 2026-10-20 (depois do merge da PR #47)

> gh pr merge 47 --merge

**Intenção:** o solicitante mesclou a PR #47, que fecha a fase 6. O trabalho segue a instrução "analise e implemente os itens no backlog", agora na fase 7 do plano (`2026-10-19-1023-plano-do-backlog`): cursor e retomada (F-14, F-03).

**Decisões do solicitante (AskUserQuestion):**
- **Divisão:** "Duas PRs: 7a F-03, 7b F-14 (Recomendado)". Esta é a 7a.
- **Alcance da retomada (F-03):** "Upload e download (Recomendado)".
  - **Upload:** guarda a sessão e o deslocamento; só retoma se o arquivo local não mudou; confere o `content_hash` final.
  - **Download:** retoma um arquivo `.part` por `Range`; confere o `content_hash` antes de trocar o destino.
- **Cursor (F-14, fase 7b):** "No sync remoto→local (Recomendado)". O estado só acelera; cursor inválido ou expirado volta à varredura completa.
- **Exclusão via cursor (F-14, fase 7b):** "Confirmar no servidor antes (Recomendado)". Na mesma execução, sem confirmação, nada é apagado.

**Porte G:** introduz estado local persistente entre execuções, reabre a `DP-09` e aciona o DBA. Branch `feature/retomada-b7a`, a partir de `develop` (`3c9a702`); nenhum PR aberto.

## Prompt 2 — 2026-10-21 (decisões do solicitante após o ciclo 2 do QA)

**Decisões do solicitante (AskUserQuestion):**
- **Suíte do QA da fase 7a:** "Aprovo". `tests/integracao/qa_retomada_b7a_test.sh`, 41 casos, sha256 `445ba4fc6cf83dc85972e12e93ace6b6ec67d0d9a2ead5a594b600abbd263a34`.
- **OBS-3 (corrida entre a conferência de arquivo regular e a abertura):** "Aceito o risco (Recomendado)". Fica registrado como RSK-76.

## Prompt 3 — 2026-10-21 (suíte completa reprovada no `harness_test`)

**Decisão do solicitante (AskUserQuestion):** "Autorizo e aprovo (Recomendado)". A suíte do QA definia `erro()` duas vezes, em dois dublês de curl. O do download foi renomeado para `erro_download`, em 3 linhas e sem mudar nenhum caso. Novo sha256 aprovado: `bb76e2637255b4410e41aabe64163bd490dccbdc24c12bb74f0d3c91c91ff900`, que substitui o `445ba4fc…`.
