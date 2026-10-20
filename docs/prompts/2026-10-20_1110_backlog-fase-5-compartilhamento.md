---
date: 2026-10-20
hora: "1110"
domain: compartilhamento (link temporario e link compartilhado)
porte: G
status: concluido
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-20-1110-registro-compartilhamento-b5.md"
---

# backlog-fase-5-compartilhamento

## Prompt 1 — 2026-10-20 (depois do merge da PR #45)

> continue the backlog from phase 5

**Contexto:**
- O solicitante habilitou `sharing.write` e `files.permanent_delete` no App Console e refez a autorização (`dbx unlink`, `dbx config`).
- Esta é a fase 5 do plano (`2026-10-19-1023-plano-do-backlog`):
  - F-15: link temporário de download direto;
  - F-16: link compartilhado com expiração, senha ou restrição de audiência.

**Decisões do solicitante (AskUserQuestion):**
- **Dois comandos:**
  - `dbx link-temporario <arquivo>` (alias `temp-link`): URL direta de 4 h, pela API `files/get_temporary_link`.
  - `dbx compartilhar <caminho>` (alias `share`): cria link compartilhado. Tem `--listar` e `--revogar <url>`.
- **Visibilidade explícita:** sem `--publico`, `--equipe` ou `--senha`, o `compartilhar` sai com 2 (uso inválido). Nunca publica por omissão.
- **Senha nunca no argv:**
  - `--senha` pede a senha no terminal, sem eco;
  - em automação, `--senha-stdin` lê uma linha da entrada;
  - não há variável de ambiente.
- **Link existente:**
  - sem configurações pedidas, devolve o link existente;
  - com configurações diferentes, aplica `modify_shared_link_settings` e mostra o antes e o depois.

**Porte G:** integração externa nova (endpoints `sharing/*`, escopo `sharing.write`), exposição de dado para fora da conta (fronteira de segurança) e segredo novo (senha do link). Branch `feature/compartilhamento-b5`, a partir de `develop` (`e42168f`); nenhum PR aberto.

## Decisão do solicitante — 2026-10-20 (DIV-106)

> Já está habilitado

O escopo `sharing.read` já estava concedido. A fase saiu completa, com `--listar`, o reuso e a guarda do `--revogar`.

## Aprovação do solicitante — 2026-10-20 (regra 12)

> Aprovo

**Suíte aprovada:** `tests/integracao/qa_compartilhamento_b5_test.sh`, do QA, com 43 casos e sha256 `8adf68023874b67e2fb51de3b946d43b489b2a5952621b3b01203e4ecb566a76`.

**Ciclos da validação:**
- Ciclo 1, reprovado: QA-B5-01..07.
- Ciclo 2, reprovado: QA-B5-08..16.
- Ciclo 3, aprovado com três ressalvas menores, QA-B5-17..19. As três foram corrigidas antes do commit.
