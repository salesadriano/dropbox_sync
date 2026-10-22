---
date: 2026-10-22
hora: "1440"
domain: documentacao (status pos-merge das fases 1 a 9)
porte: P
status: aberto
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-22-1440-registro-atualiza-documentacao.md"
---

# atualiza-documentacao

## Prompt 1 — 2026-10-22 (depois do merge da PR #52 e da PR #53 para a master)

> atualize a documentação do projeto

**Intenção:** sincronizar a documentação viva com o que já foi mesclado na `develop`.

**Inferência do Tech Lead (pedido genérico, escopo deduzido por levantamento):**
- As fases 1 a 9 do backlog (PRs #40 a #52) foram mescladas, mas as candidatas, os requisitos e o System Design ainda as marcam como "em andamento".
- `docs/testes/mapa-modulos.md` não lista `lib/lote.sh` (fase 9) nem `commands/perfis.sh` (fase 8).
- O README já cobre as fases (ex.: `--paralelo`); conferido por amostragem e não alterado sem defeito encontrado.

**Porte:** P. `scripts/porte.sh` não existe no projeto. A demanda só altera documentação, sem código, contrato, segredo, pipeline ou dependência.

**Entrada:** branch principal `develop` @ `a39a89e`, igual à `origin/develop`; nenhum PR aberto; worktree `chore/atualiza-documentacao` em `/home/sales/dropbox_api.worktrees/chore-atualiza-documentacao`; `alteracoes-externas.sh --inicial` exit 0.

## Prompt 2 — 2026-10-22 (depois do commit da documentacao, antes do push)

> corrija também os dois pontos do mapa

**Intencao:** corrigir os dois pontos do mapa de modulos de teste que ficaram como ressalva: a frase da Regra 1 sobre os testes que leem `lib/*.sh` e o agrupamento das fases 8 e 9 numa secao so.

**Achado do Tech Lead:** o diagnostico do QA para a Regra 1 nao conferia. Os testes `perfis_*` e `state_trava_raiz` carregam libs especificas. Faltavam na tabela `auth`, `hash`, `path`, `trava_test` e `qa_docs_aliases`, que varrem `lib/*.sh` atras de um padrao.

**Efeito:** a suite completa que rodava no primeiro commit foi interrompida, porque o commit novo a invalidaria; ela roda de novo no HEAD final.
