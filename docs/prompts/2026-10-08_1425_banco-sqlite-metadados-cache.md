---
date: 2026-10-08
hora: "1425"
domain: cli / storage / database / sync / upload
porte: G
status: em_andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-08-1425-registro-banco-sqlite-metadados.md"
---

# banco-sqlite-metadados

## Prompt 1 — 2026-10-08 1425

> @tech-lead implemente o uso de sqlite para manutenção de uma banco local que registre os metadados e hash dos arquivos locais de modo a só realizar o upload o sync com origem local houve alteração no arquivo desde a ultima operação

**Intenção:** Implementar uma camada de persistência local baseada em SQLite para armazenar metadados (`tamanho`, `mtime`) e `content_hash` dos arquivos locais. Com isso, os comandos `upload` e `sync` (com origem local / `--enviar`) só realizarão o envio se o arquivo local tiver sofrido alteração desde a última operação bem-sucedida, dispensando transferências redundantes e evitando recálculos pesados de hash e re-uploads de arquivos idênticos.

**Decisões e Diretrizes Técnicas do Tech Lead & DBA:**
- **Porte G (estrutural):** Introduz camada de banco de dados relacional local (SQLite), novo componente de persistência (`lib/db.sh`), evolução de `lib/state.sh`, ajuste no fluxo de `commands/upload.sh` e `commands/sync.sh`, além de tratamento de dependências de execução.
- **Análise de Abordagens de Dependência:**
  1. *Abordagem 1 (CLI estrita `sqlite3`):* Depende de `/usr/bin/sqlite3`. No ambiente atual, o utilitário CLI não está instalado (apenas `libsqlite3-0`). Sem sudo interativo, travaria a execução se for dependência rígida.
  2. *Abordagem 2 (Script Python 3 dedicado):* Utiliza o runtime nativo de `python3` com módulo padrão `sqlite3` já presente no sistema.
  3. *Abordagem 3 (Híbrida / Resiliente — Recomendada):* Adaptador em `lib/db.sh` que detecta preferencialmente a CLI `sqlite3` e realiza fallback transparente para execução via Python 3 embutido, garantindo compatibilidade imediata no ambiente atual sem exigir intervenção manual no APT.
- **Schema SQLite:**
  - Tabela `metadados_arquivos` (`caminho_local`, `tamanho`, `mtime`, `content_hash`, `atualizado_em`).
  - Tabela `operacoes_arquivos` (`caminho_local`, `caminho_remoto`, `tipo_operacao`, `content_hash`, `tamanho`, `mtime`, `rev_remoto`, `sucesso`, `executado_em`).
  - Índices para busca ultra-rápida por `(caminho_local, tamanho, mtime)`.
