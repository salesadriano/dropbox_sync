---
id: 2026-10-21-1845-lint-sequencial
tipo: decisao
escopo: projeto
titulo: Lint por scripts/lint.sh, completo e sequencial, com teto de memoria por processo
data: 2026-10-21
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert
status: ativa
ref: docs/prompts/2026-10-21_1845_lint-sem-estouro-de-memoria.md
---

Decisao do solicitante: "Completo, sequencial (Recomendado)".
- O lint do projeto e `sh scripts/lint.sh` (sem argumentos, ou com os arquivos do diff nos gates). Nunca `shellcheck` sobre varios arquivos num processo so: com `external-sources=true` o processo unico passou de 18 GB e travou a maquina em 2026-10-21.
- `external-sources=true` continua: o modo sem seguir `source` da falso positivo (SC2034 em `commands/upload.sh`) e perde as checagens entre arquivos.
- Padrao: um arquivo por vez, teto de 12 GB por processo. Medido: 142 s, pico de 9,2 GB (`commands/download.sh` sozinho chega a 9 GB).
