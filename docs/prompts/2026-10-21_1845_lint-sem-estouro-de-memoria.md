---
date: 2026-10-21
hora: "1845"
domain: ferramenta de lint do projeto (shellcheck)
porte: M
status: aberto
registro_de_entrega: "docs/reviews/2026-10-21-1845-registro-lint-memoria.md"
---

# lint-sem-estouro-de-memoria

## Prompt 1 — 2026-10-21 18:45

> sim, edite o wslconfig e abra a demanda do lint

**Intencao:** corrigir o comando de lint do projeto, que roda `shellcheck` num processo unico sobre todos os scripts. Com `external-sources=true`, cada arquivo reanalisa a cadeia de `source` e o processo chegou a 18 GB de RAM (OOM em 2026-10-21 16:34 e 17:05, journal do boot anterior), travando a maquina. A edicao do `.wslconfig` (fora do repositorio) foi feita antes, na mesma rodada.

**Inferencias:**
- "demanda do lint" e o item 2 proposto na resposta anterior: um `shellcheck` por arquivo, paralelismo baixo, teto de memoria por processo e a linha de comando documentada apontando para o novo script.
- `external-sources=true` continua: desligar reduz a cobertura (SC1091) e o teto por processo ja evita o travamento.

**Porte:** P. `scripts/porte.sh` nao existe neste projeto nem no plugin 1.0.6; porte medido pelos criterios de `fluxo-p.md`: ferramenta de desenvolvimento, sem contrato, CLI do produto, schema, auth, segredo, dado sensivel, fronteira, pipeline (nao ha workflow de CI) nem dependencia nova; ate 50 linhas de codigo.

## Prompt 2 — 2026-10-21 (decisao sobre o modo do lint)

**Decisao do solicitante (AskUserQuestion):** "Completo, sequencial (Recomendado)". Mantem `external-sources=true`; `scripts/lint.sh` roda um arquivo por vez com teto de 12 GB. Gravada na memoria `2026-10-21-1845-lint-sequencial`.

**Porte:** P -> M, motivo: `git diff --numstat` de producao e teste soma 84 linhas (`scripts/lint.sh` 39, `scripts/tests/lint.bats` 45), acima do teto de 50 de `fluxo-p.md`. A implementacao ja feita pelo Tech Lead no fluxo P e mantida; a validacao do QA passa a ser independente e o registro e o commit vao ao `documentation-writer` e ao `commit-writer`.

## Prompt 3 — 2026-10-21 (aceite da suite do QA)

**Decisao do solicitante (AskUserQuestion):** "Aprovo". Suite do QA `scripts/tests/qa-lint.bats`, 10 casos, sha256 `8203f5b0117d3e5a7c239173698f2021f3056bf6c80d488d620cd9c60d92a0e9`.
