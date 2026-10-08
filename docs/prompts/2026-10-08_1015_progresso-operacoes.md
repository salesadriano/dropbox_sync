---
date: 2026-10-08
hora: "1015"
domain: cli / progresso / ux
porte: M
status: concluido
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-08-1015-registro-progresso-operacoes.md"
---

# progresso-operacoes

## Prompt 1 — 2026-10-08 1011

> @tech-lead implements parameter to show progress of operations

**Intenção:** Implementar sinalizador de linha de comando (`--progresso` / `--progress` / `-p` e `--sem-progresso` / `--no-progress`) para exibição de progresso em tempo real das operações de transferência e sincronização (`upload`, `download`, `sync`).

**Inferências e Decisões do Solicitante:**
- **Porte M:** Toca contrato público de linha de comando (novas flags globais e locais, interação em tempo real com operador e testes automatizados).
- **Branch base:** Merge da branch anterior `fix/rpc-content-type-json` concluído em `develop`; nova branch criada como `feature/progresso-operacoes` a partir de `develop`.
- **Canal de emissão de progresso:** Toda emissão de progresso deve sair exclusivamente pelo descritor de erro padrão (`stderr` / `>&2`), garantindo isolamento absoluto de `stdout`, em conformidade estrita com `RF-28` (saída estruturada em JSON/chave-valor sem poluição) e `RF-32` (recebimento de conteúdo por stdout em pipes/fluxo sem corrupção).
- **Escopo operacional:**
  - `upload`: emissão de progresso em uploads de arquivo único e por blocos de sessão em partes (`lib/transfer.sh`).
  - `download`: emissão de progresso na recepção de arquivo remoto.
  - `sync`: indicação de progresso item a item durante a sincronização direcional (`[1/N] enviando ...`).
- **Detecção de terminal (RNF-19):** O sinalizador `--progresso` sobrepõe o comportamento padrão para permitir testes automatizados e forçar exibição quando desejado pelo operador; `--sem-progresso` desativa explicitamente.
