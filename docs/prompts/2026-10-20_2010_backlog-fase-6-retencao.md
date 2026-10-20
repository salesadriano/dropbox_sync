---
date: 2026-10-20
hora: "2010"
domain: retencao e rotacao de backup
porte: G
status: em-andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-20-2010-registro-retencao-b6.md"
---

# backlog-fase-6-retencao

## Prompt 1 — 2026-10-20 (depois do merge da PR #46)

> gh pr merge 46 --merge

**Intenção:** o solicitante mesclou a PR #46, que fecha a fase 5. O trabalho volta à instrução "analise e implemente os itens no backlog", agora na fase 6 do plano (`2026-10-19-1023-plano-do-backlog`): F-10, retenção e rotação de backup.

**Decisões do solicitante (AskUserQuestion):**
- **Comando próprio:** `dbx reter <pasta-remota> --padrao GLOB (--manter N | --dias D)`, com o alias `retain`. Roda sozinho, por exemplo num cron depois do upload.
- **Ordem:** pela data do servidor (`server_modified`); em empate, pelo nome.
- **Exclusão:** para a lixeira, por `delete_v2`. O item pode ser recuperado com `dbx lixeira` ou `dbx restaurar` dentro do prazo do plano.
- **Proteção:** sem `--confirmar`, o comando só mostra o plano, o que fica e o que sai, e sai 0 sem apagar. Sempre mantém pelo menos 1 artefato.

**Porte G:** a operação é destrutiva e roda em lote no destino remoto, que é uma fronteira de segurança dos dados. Branch `feature/retencao-b6`, a partir de `develop` (`d696c1d`); nenhum PR aberto.

## Prompt 2 — 2026-10-20 (aprovações depois do ciclo 5 do QA)

**Respostas do solicitante (AskUserQuestion):**
- **Suíte do QA** `tests/integracao/qa_retencao_b6_test.sh` (60 casos, sha256 `cd0178992648fc24132d992c86927c29b418e7cdcf3ac873ae426c591e258cad`): "Aprovo" (regra 12).
- **TC-CPL-08 (DIV-148):** "Autorizo (Recomendado)". O `re` exato vira três asserções exatas: `res`, `rev` e `ret`.
- **Risco residual DIV-170 (OBS-2):** "Aceito o risco (Recomendado)". Fica no RSK-68.

**Intenção:** a validação está fechada. A fase segue para o registro de entrega, o commit, a suíte completa e a PR.
