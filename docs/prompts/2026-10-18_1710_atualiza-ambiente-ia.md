---
date: 2026-10-18
hora: "1710"
domain: governanca / pacote de agents
porte: G
status: em-andamento
instancia: myNote/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-18-1710-registro-atualiza-ambiente-ia.md"
---

# atualiza-ambiente-ia

## Prompt 1 — 2026-10-18 1710

> leia @../ai_team e atualize skills, agents, mods, hooks, protocolos e instruções neste projeto

**Intenção:** Atualizar o ambiente de governança e interação com IA do projeto (protocolo comum, personas dos agents, skills, templates, hooks, scripts utilitários e instruções de IA) a partir do modelo de referência upstream `ai_team` (`../ai_team`), avançando do commit `ed927bb18678241c777346e7ad94ac0d0f2dd5c4` para `e3f1deb44a6d2fdb4b94dff51a83f26a88284f82`.

**Inferências e Decisões do Solicitante:**
- **Modelo de referência:** `git@github.com:salesadriano/ai_team.git` em `e3f1deb44a6d2fdb4b94dff51a83f26a88284f82`.
- **Branch principal:** `develop` (conforme entrada de memória `branch-principal`).
- **Branch de trabalho:** `feature/atualiza-ambiente-ia`.
- **Porte da demanda:** G (estrutural: altera protocolo transversal, incorpora skills vindas dos mods, ativa governança por hooks e atualiza regras de suíte completa local).
- **Escopo a atualizar:**
  - **Skills:** `entrega-por-porte`, `governanca-por-hooks`, `instrucoes-do-projeto`, `memoria-por-janela`, `selecao-de-modelo`, `superficie-de-contrato`, `e2e-reexecucao-parcial`; atualização de `gitflow`, `protocolo-tdd`, `protocolo-conformidade`, `review-documentation`, `SKILL_HIERARCHY.md`.
  - **Scripts:** `alteracoes-externas.sh` (com trava O_EXCL, aviso de HEAD e recusa de diretório), `limpar-worktrees.sh`, `memoria-index.sh` (com suporte a `--desde` e `--todas`), `guarda-de-comandos.txt`, `suite-completa.sh`, `suite-completa.cmd`, `tabela-de-modelos.tsv` e testes bats em `scripts/tests/`.
  - **Hooks:** Configuração em `.claude/settings.json` acionando `resumo-de-estado.sh` em `SessionStart` e `guarda-de-comandos.sh` em `PreToolUse` (Bash).
  - **Protocolos / Agents:** `AGENTS.md` (regras 40, 46, 47, 48, suíte completa local no push para PR, Fluxo P); personas `tech-lead.agent.md`, `senior-developer.agent.md`, `qa-expert.agent.md`, `documentation-writer.agent.md`; templates `registro-de-entrega-curto-template.md`, `evidencia-testes-template.md`, `templates/README.md`.
  - **Instruções:** `CLAUDE.md` atualizado com comandos novos, Fluxo P e referências.
