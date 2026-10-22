---
date: 2026-10-19
hora: "1828"
domain: recuperacao (revisoes, restauracao, lixeira)
porte: G
status: em-andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-19-1828-registro-recuperacao-b3.md"
---

# backlog-fase-3-recuperacao

## Prompt 1 — 2026-10-19 (depois do merge da PR #43)

> gh pr merge 43 --merge

**Intenção:** o solicitante mesclou a PR #43, que fecha a fase 2. Isso retoma a instrução "analise e implemente os itens no backlog". Esta é a fase 3 do plano (`2026-10-19-1023-plano-do-backlog`):
- F-07: revisões e restauração;
- F-20: lixeira (listar, restaurar e excluir permanentemente).

**Decisões do solicitante (AskUserQuestion):**
- **Nomes:** `dbx revisoes <arq>` (alias `revisions`), `dbx restaurar <arq> --rev R` ou `--antes-de DATA` (alias `restore`) e `dbx lixeira [pasta]` (alias `trash`). O `restaurar` também traz de volta item apagado.
- **Exclusão permanente:** incluída. É irreversível, só existe em contas Dropbox Business e exige o escopo novo `files.permanent_delete`, que o solicitante habilitará no App Console antes de reautorizar. Isso torna a fase porte **G**.
- **Pasta apagada:** é restaurada de forma recursiva, arquivo por arquivo, na última revisão, com `--dry-run` e resumo. Falha parcial sai 14 e diz o que faltou.
- **Restaurar sobre arquivo existente:** permitido direto, porque a versão atual vira revisão anterior. A saída mostra a revisão substituída, para que a operação possa ser desfeita.

**Porte G:** fluxo destrutivo e irreversível, escopo OAuth novo e integração externa nova (endpoints `files/list_revisions`, `files/restore`, `files/permanently_delete` e `list_folder` com `include_deleted`). O `scripts/porte.sh` não existe neste projeto, então o porte foi classificado pelos gatilhos da regra 40. Branch `feature/recuperacao-b3`, a partir de `develop` (`ef1efb2`); nenhum PR aberto.

## Prompt 2 — 2026-10-19 (aprovação da regra 12)

> Aprovo

**Intenção:** o solicitante aprova a suíte do QA da fase 3, `tests/integracao/qa_recuperacao_b3_test.sh` (26 casos, ciclo 1, sha256 `c34c2120…`). Qualquer mudança posterior volta para reaprovação.

## Prompt 3 — 2026-10-19 (reaprovação da regra 12)

> Aprovo

**Intenção:** o solicitante aprova a nova versão da suíte do QA da fase 3, com 30 casos, do ciclo 2 (sha256 `e77153d5…`).

As mudanças em relação à versão `c34c2120…`:
- as massas de item apagado passam a incluir `path_lower`;
- E08 e D03 ficaram mais rígidos;
- E13, R09, R10 e L03 são novos.

## Prompt 4 — 2026-10-19 (reaprovação da regra 12)

> Aprovo

**Intenção:** o solicitante aprova a versão `2044fa23…` da suíte do QA da fase 3 (30 casos). A única mudança em relação à `e77153d5…` é a correção do padrão de contagem do R10, que nunca casava.

## Prompt 5 — 2026-10-19 (teste instável; regras 12 e 48)

> Corrigir nesta PR (Recomendado)
>
> Aprovo

**Intenção:** a suíte completa da PR #44 ficou vermelha no caso `qa_p4_alias_sync_execucao_real...` de `tests/integracao/qa_docs_aliases_p4_test.sh`. O caso já era instável no `develop`, onde falha cerca de 2 a cada 5 rodadas. A causa é a memória do sync, que grava ctime e inode: o `cp -a` entre as rodadas troca os dois, e o registro depende da regra dos 2 s. O solicitante decidiu corrigir nesta PR e aprovou a mudança do QA (sha256 `8df6bf4e…`): as fixtures ganham mtime antigo e a memória passa a ser comparada pelo conteúdo semântico (cabeçalho e, por registro, caminho, content_hash, mtime e tamanho). O solicitante também confirmou a alteração como feita pelos agents (regra 48).
