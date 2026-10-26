---
date: 2026-10-24
hora: "2118"
domain: governanca do pacote de agents (remocao das copias locais que o plugin ai-team ja fornece)
porte: M
status: aberto
instancia: myPCWin/Desenvolvedor Hydros
registro_de_entrega: "docs/reviews/2026-10-24-2118-registro-remover-duplicados-do-plugin.md"
---

# remover-duplicados-do-plugin

## Prompt 1 — 2026-10-24

> remove os agents locais e skills duplicados

**Intencao:** deixar o plugin `ai-team` (1.0.8) como unica fonte das personas, skills, comandos e hooks que ele ja fornece, removendo as copias do projeto que rodam em duplicidade.

**Estado levantado pelo Tech Lead (develop @ `6df321e`):**
- `.github/agents/`: oito personas `*.agent.md` (o plugin traz sete como `ai-team:<papel>` e o Tech Lead como `/ai-team:tech-lead`), alem de `AGENTS.md`, `memoria/` e `templates/`, que sao do projeto.
- `.github/skills/`: 25 skills; 16 existem no plugin (copias locais mais antigas, sem conteudo proprio do projeto; so pastas `scripts/tests` de bats do pacote) e 9 so existem aqui (`bats-testing-patterns`, `clean-architecture`, `e2e-reexecucao-parcial`, `prd-generator`, `shellcheck-configuration`, `superficie-de-contrato`, `testing-strategy`, `use-case-specification`, `user-story-writing`).
- `.github/prompts/execucao-enxuta.prompt.md`: o plugin traz `/ai-team:execucao-enxuta`.
- `.claude/settings.json`: dois hooks (`resumo-de-estado`, `guarda-de-comandos`) que o plugin tambem registra; o resumo de estado aparece duas vezes no inicio da sessao.
- Dependencias: `scripts/suite-completa.sh` delega a `.github/skills/governanca-por-hooks/scripts/suite-completa.sh`, identico ao do plugin; links para as skills em `CLAUDE.md`, `AGENTS.md`, templates, `MEMORIA-PROJETO.md` e `SKILL_HIERARCHY.md`.

**Inferencias adotadas:** "agents locais" = as oito personas `*.agent.md` (protocolo, memoria e templates ficam); "skills duplicados" = as 16 que o plugin fornece; o prompt `execucao-enxuta` entra como duplicado. `scripts/suite-completa.sh` passa a ser a propria implementacao (copia da do plugin), que o despachante do plugin ja prefere. Os hooks saem por `migrar-para-o-plugin.sh --executar`, do proprio plugin. Arquivos de `memoria/historico/` ficam como estao (registro historico).

**Porte:** M. `scripts/porte.sh` nao existe no projeto. Toca a governanca do pacote (personas, skills, hooks) sem mudar regra nem arquitetura do produto; nenhum codigo de runtime.
