---
date: 2026-10-21
hora: "1735"
domain: perfis nomeados de credencial
porte: G
status: em-andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-21-1735-registro-perfis-b8.md"
---

# backlog-fase-8-perfis

## Prompt 1 — 2026-10-21 (depois do merge da PR #49)

> gh pr merge 49 --merge

**Intenção:** o solicitante mesclou a PR #49, que fecha a fase 7b (F-14). O trabalho segue a instrução "analise e implemente os itens no backlog", agora na fase 8 do plano (`2026-10-19-1023-plano-do-backlog`): F-18, perfis nomeados de credencial. A fase reabre a `DP-05`, em que o solicitante havia fixado "uma conta só, sem noção de perfil".

**Decisões do solicitante (AskUserQuestion, 2026-10-21), todas na opção recomendada:**
- **Seleção:** "Opção + variável (Recomendado)". `--perfil NOME` (alias `--profile`) em todos os comandos e `DBX_PERFIL` no ambiente; a opção vence a variável. A variável carrega só o nome, nunca segredo, e a `DP-11` continua valendo.
- **Compatibilidade:** "Atual vira o padrão (Recomendado)". O `credencial.json` atual segue como perfil `padrao`, sem mudança para quem não usa perfil; os demais ficam em `perfis/<nome>.json`, 0600.
- **Gestão:** "Listar e remover (Recomendado)". `dbx perfis` lista nomes e se a credencial está completa, sem segredo; remover é `unlink --perfil NOME`; criar é `config --perfil NOME`.
- **Nomes:** "Restrito e minúsculo (Recomendado)". `[a-z0-9_-]`, 1 a 32 caracteres, começando por letra ou dígito; fora disso, saída 2.

**Porte G:** reabre `DP-05`, altera o desenho fechado de `lib/config` (credencial, segredo) e o System Design. Branch `feature/perfis-b8`, a partir de `develop` (`dd129fb`); nenhum PR aberto.

## Prompt 2 — 2026-10-21 (detector de alterações externas)

**Decisão do solicitante (AskUserQuestion):** "Sim, registre (Recomendado)". A correção que o Tech Lead fez na entrada `2026-10-21-1735-perfis`, vinda do parecer do DBA, ficou sem registro logo depois da edição. O detector acusou o arquivo, e o solicitante confirmou que a alteração é do agent. O arquivo foi registrado com `--registrar`.

## Prompt 3 — 2026-10-21 (nova sessão)

> continue a fase 8 de perfis

**Intenção:** retomar a fase 8 no worktree `feature/perfis-b8`. Ela parou com a implementação do Senior Developer quase completa: faltam o vermelho contra a base, os mutantes das guardas, as rodadas finais, o mapa de módulos, o parecer e o handback. Faltam também a conformidade, o QA, o registro, o commit e a PR.

**Porte:** G, mantido. `scripts/porte.sh` não existe neste projeto (saída: `cannot open scripts/porte.sh`). O porte segue a classificação do Prompt 1, porque a fase reabre a `DP-05` e mexe em credencial e no System Design.

**Detector (regra 48):** `--detectar` no worktree e no checkout principal saiu sem divergências.

**Decisão do Tech Lead, DIV-255 C:** o valor de `--perfil` não é completado no autocompletar. Só a opção é completada. Com isso o `TC-CPL-04` fica intacto: o script não lê arquivo do dbx nem caminho de configuração. A `DIV-246` fica parcialmente atendida, e a completação do valor vai para o backlog como `F-45`. A alternativa de chamar `dbx perfis` no autocompletar foi descartada, porque ela lê as credenciais a cada TAB.
