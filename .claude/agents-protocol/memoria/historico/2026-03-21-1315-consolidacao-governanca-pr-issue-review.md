# Consolidacao da governanca de PR, review e issue vinculada

## Contexto

O pacote passou a exigir governanca mais rigorosa para Pull Requests preparados sob consolidacao do Tech Lead, incluindo convencao semantica, Gitflow, labels de review, review request e sincronizacao do estado de review nas issues vinculadas.

## Decisao consolidada

- A logica de vinculo PR -> issue foi centralizada em um unico workflow de governanca.
- O workflow passou a validar branch Gitflow, commits semanticos e titulo semantico do PR.
- O workflow passou a gerir labels de review granulares no PR: `needs-review`, `in-review`, `review-approved`, `review-changes-requested`, `review-commented` e `review-dismissed`.
- O workflow passou a refletir o mesmo estado de review nas issues vinculadas.
- O workflow passou a registrar comentarios automaticos de transicao tanto na issue vinculada quanto no proprio PR para estados relevantes de review.
- O fechamento por merge da issue vinculada passou a ocorrer no mesmo workflow de governanca, com limpeza de labels de review e adicao de `done`.
- O workflow anterior dedicado ao vinculo de issue foi removido para eliminar sobreposicao funcional.

## Motivacoes

- Remover duplicidade entre workflows com responsabilidade parcialmente sobreposta.
- Evitar divergencia de estado entre PR e issue vinculada.
- Melhorar a auditabilidade do ciclo de review por meio de labels e comentarios automaticos.
- Tornar o fluxo de governanca de PR mais previsivel e operavel em um unico ponto.

## Impactos permanentes

- `pr-governance.yml` se torna o workflow canonico para validacao, review, sincronizacao de issue e fechamento no merge.
- O repositorio passa a operar com estados de review mais granulares e semanticamente distintos.
- O pacote passa a manter trilha textual automatica das transicoes de review em PR e issue vinculada.

## Artefatos impactados

- `.github/workflows/pr-governance.yml`
- `.github/workflows/label-management.yml`
- `CONTRIBUTING.md`
- `memoria/MEMORIA-COMPARTILHADA.md`

## Riscos observados

- Aumento de complexidade do workflow unificado de governanca.
- Dependencia maior da coerencia dos labels do repositorio para refletir o estado correto.

## Mitigacoes

- Manter labels e transicoes documentadas em `CONTRIBUTING.md`.
- Preservar comentarios com marcadores dedicados para atualizar a mesma trilha em vez de gerar ruido excessivo.
- Validar estruturalmente o workflow a cada ajuste de governanca.