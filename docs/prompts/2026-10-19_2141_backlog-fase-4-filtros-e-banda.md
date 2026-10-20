---
date: 2026-10-19
hora: "2141"
domain: filtros de sincronizacao e limite de banda
porte: M
status: concluido
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-19-2141-registro-filtros-e-banda-b4.md"
---

# backlog-fase-4-filtros-e-banda

## Prompt 1 — 2026-10-19 (depois do merge da PR #44)

> gh pr merge 44 --merge

**Intenção:** o solicitante mesclou a PR #44, que fecha a fase 3. Isso retoma a instrução "analise e implemente os itens no backlog". Esta é a fase 4 do plano (`2026-10-19-1023-plano-do-backlog`):
- F-13: filtros avançados (hoje não existe nenhum filtro);
- F-17: limitação de banda.

**Decisões do solicitante (AskUserQuestion):**
- **Filtros de caminho:** `--excluir PADRAO` e `--incluir PADRAO`, repetíveis, em `sync`, `verificar` e no `download` de pasta.
  - A sintaxe segue o gitignore, sobre o caminho relativo à raiz: padrão sem `/` casa o nome em qualquer nível; `*` não cruza `/`; `**` cruza.
  - A comparação é sem caixa, como no `sync`.
  - A exclusão vence a inclusão.
- **Com `--espelhar`:** item filtrado fica fora do escopo nos dois lados, nem transferido nem apagado. Um filtro novo nunca apaga o que deixou de fora.
- **Data e tamanho:** `--modificado-desde`/`--modificado-ate DATA` e `--tamanho-min`/`--tamanho-max N[K|M|G]` avaliam só o item da origem e são recusados (uso inválido) quando combinados com `--espelhar`.
- **Limite de banda:** `--limite-banda TAXA` (alias `--bwlimit`; por exemplo `500K`, `2M`) em todo comando que transfere (`upload`, `download`, `sync`). A variável `DBX_LIMITE_BANDA` serve de padrão, e a opção vence. O limite usa o `--limit-rate` do cURL, por transferência.

**Porte M:** contrato público da CLI (flags novas) e uma interação com a exclusão do `--espelhar`, crítica para a segurança dos dados. Não altera arquitetura, schema nem integração externa. Branch `feature/filtros-e-banda-b4`, a partir de `develop` (`4d54729`); nenhum PR aberto.

## Aprovação do solicitante — 2026-10-20 (regra 12)

> Aprovo

**Contexto:** a suíte do QA `tests/integracao/qa_filtros_banda_b4_test.sh` foi aprovada no ciclo 2 da validação independente.
- 21 casos, com sha256 `5f8978afe165a914e673f6ee319dc56249005dcc303c575c0e9894dc38d9a1b0`.
- O ciclo 1 reprovou a fase com o QA-B4-01 (P0): `--excluir` não protegia um nome local que não é UTF-8 válido quando o padrão tinha caractere fora do ASCII.
- O ciclo 2 aprovou depois da correção e da DIV-103 revisada pelo Tech Lead.
