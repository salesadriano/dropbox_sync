---
date: 2026-10-07
hora: "1256"
domain: governanca / pacote de agents
porte: G
status: concluido
instancia: myNote/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-07-1256-registro-atualiza-ambiente-ia.md"
---

# atualiza-ambiente-ia

## Prompt 1 — 2026-10-07 1256

> update project with current protocols

**Intenção:** Atualizar o ambiente de governança e interação com IA do projeto (protocolo comum, personas dos agents, skills, templates, memória por entradas, scripts utilitários e instruções de IA) a partir do modelo de referência `ai_team`, alinhando à versão mais recente (`ed927bb18678241c777346e7ad94ac0d0f2dd5c4`).

**Inferências e Decisões do Solicitante:**
- **Modelo de referência:** `git@github.com:salesadriano/ai_team.git` em `ed927bb18678241c777346e7ad94ac0d0f2dd5c4`.
- **Branch principal:** `develop` (confirmada explicitamente pelo solicitante sob a regra 46).
- **Tratamento do PR #14:** Incorporar as decisões PRJ-DEC-76 a 81 do PR #14 recém-concluído na tabela congelada da `MEMORIA-PROJETO.md`, garantindo continuidade histórica das decisões do projeto sem perder o histórico do incremento de upload em partes.
- **Ferramentas de IA:** Claude Code (instruções em `CLAUDE.md` na raiz apontando para `.github/agents/AGENTS.md`).
- **Porte da demanda:** G (estrutural: atualiza o protocolo transversal do pacote, regras 1 a 48, estrutura da memória para entradas individuais e scripts de governança).
- **Estrutura de diretórios:** Migração da estrutura legada em `.claude/` para a estrutura padrão canônica do modelo: `.github/agents/`, `.github/skills/`, `.github/prompts/`, `scripts/`, `docs/reviews/`, `docs/sources/`.
- **Worktree:** Devido às restrições do ambiente de execução do IDE com workspace único fixado em `/home/sales/dropbox_api`, a demanda é executada diretamente na branch de trabalho `feature/atualiza-ambiente-ia` originada de `develop`.

## Prompt 2 — 2026-10-08 0528

> continue a implementação do projeto

**Intenção:** Continuar a implementação do projeto, integrando a branch `feature/atualiza-ambiente-ia` com as entregas recentes mescladas em `origin/develop` (PR #13 e PR #14), validando a suíte completa de testes, linter e scripts de governança, e submetendo o Pull Request para `develop`.

**Inferências e Decisões do Solicitante:**
- Solicitante selecionou explicitamente via confirmação: finalizar a integração da branch atual `feature/atualiza-ambiente-ia` (rebase sobre `origin/develop` com PRs #13 e #14 mesclados, rodar testes/shellcheck e abrir PR).
