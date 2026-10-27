# Template - Registro de entrega curto (porte P e M)

Um unico arquivo em `docs/reviews/`, nomeado `YYYY-MM-DD-HHMM-<slug>.md`, que e o registro de entrega da demanda (regra 41 do `AGENTS.md`) **e** carrega, como secoes, o parecer de evidencias de testes (`protocolo-tdd`), o parecer de conformidade (`protocolo-conformidade`) e a validacao do QA. Em P e M nao se cria arquivo separado para nenhum desses tres; em G continuam os arquivos proprios (`evidencia-testes-template.md`, `parecer-conformidade-template.md`, validacao do QA e os templates de fechamento). Skill: `ai-team:entrega-por-porte`.

Preenchimento por porte: em **P**, cada secao tem o minimo que o fluxo P exige (skill `ai-team:entrega-por-porte`, referencia `fluxo-p.md`): gates num parecer combinado, QA por amostragem, abordagens dispensadas em uma linha. Em **M**, a secao *QA* traz a validacao independente como secao e a secao *Causa ou decisao* traz as abordagens com trade-offs quando exigidas. As oito secoes abaixo sao fixas e aparecem nesta ordem; secao sem conteudo recebe uma linha `Nao aplicavel: <motivo>`, nunca placeholder; contagens de testes sao **literais** copiadas da saida do runner (total, aprovados, falhos, duracao), nunca arredondadas; fato ja escrito aqui nao e repetido em memoria, commit ou PR, que apontam para este arquivo por link. Em reprovacao de gate ou do QA, o ciclo seguinte **atualiza este mesmo arquivo** (as secoes *Gates* e *QA* ganham a linha do ciclo), nunca abre outro.

---

# <Titulo objetivo da alteracao>

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | <uma linha: o que foi pedido, com o literal do solicitante quando houver> |
| Porte | P \| M - <criterios que o sustentam; em P, confirmar um a um os de `fluxo-p.md`: ate 50 linhas de codigo, sem contrato, schema, auth, segredo, dado sensivel, fronteira, pipeline, dependencia, sem criticidade alta> |
| Log de prompt | `docs/prompts/<arquivo>.md` |
| Branch / base | `<branch>` sobre `origin/<base>` @ `<sha>` |
| Agents | <quem implementou (em P, o Tech Lead), quem validou> |
| Data | <AAAA-MM-DD> |

## 2. Causa ou decisao

<Em correcao: a causa raiz em uma ou duas linhas e por que a solucao e unica ou evidente (dispensa registrada da analise comparativa; em P ela e sempre dispensada). Em implementacao, refinamento ou melhoria em M: a decisao e as abordagens consideradas com os trade-offs, em ate cinco linhas, ou link para o ADR quando houver.>

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `<caminho>` | Novo \| Alterado \| Removido | +n/-m |

Total de linhas de codigo (producao e teste, sem documentacao): **<n>** (em P, ate 50).

## 4. Testes rodados

Selecao por arquivo de teste, so dos itens afetados (Regra 8 de `protocolo-tdd`). Comando e contagem literais, por linha; red observado antes do green quando houver teste novo.

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `<teste>` | `<arquivo do diff>` | `<comando>` | n | n | 0 | s |

- Red observado: <teste e falha vista antes da implementacao, ou `Nao aplicavel: <motivo>`>
- Parada no primeiro erro (Regra 9): <mecanismo do runner conferido; execucao final sem interrupcao>
- Barreiras estaticas do modulo tocado (typecheck, lint, analise estatica): <comando e resultado>
- Testes de seguranca e acesso (Regra 6): <um cenario por linha quando o diff toca rota, guard, sessao, dado sensivel ou entrada de usuario; senao `Nao aplicavel: <motivo>`>
- Validacao de formularios em E2E (Regra 7): <um cenario por linha quando houver formulario tocado; senao `Nao aplicavel: <motivo>`>
- Suite completa local no push para a PR de `main`/`master` (Regra 8): <comando oficial, total, aprovados, falhos, duracao, sha do commit testado, uma linha por push; ou `Ainda nao houve push para a PR`>

## 5. Gates

Parecer combinado dos dois gates locais, executados pelo agent que produziu a alteracao, nesta ordem.

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; `Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados` | <nenhum \| lista> | Aprovado \| Aprovado com ressalvas \| Reprovado |
| `protocolo-conformidade` | `clean-architecture` + `<skill de stack>`; `Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados` | <nenhum \| lista> | Aprovado \| Aprovado com ressalvas \| Reprovado |

- Ciclo: <1 \| 2 \| 3; em ciclo 2 ou 3, o status de cada achado anterior: corrigido \| nao corrigido \| justificado>
- `sh scripts/alteracoes-externas.sh --detectar`: <exit 0 antes de cada gate, commit e push, ou o que foi acusado e a decisao do solicitante>

## 6. QA

- Porte P: `QA: amostragem <n> de <N> - validada em <data> | nao validada` (`fluxo-p.md`, secao 3). Quando validada: o que o QA auditou, o que reexecutou e os cenarios de risco que acrescentou, sem mutantes nem arquivo `qa-*`.
- Porte M: validacao independente sobre os itens afetados, aqui como secao: cenarios proprios (risco, borda, contrato, acesso indevido), arquivos `qa-*` criados com o sha256 de cada um para o aceite do solicitante, comando e contagem literais, achados com severidade, ciclo e veredito. Em reprovacao, a devolucao ao agent originador fica aqui e o ciclo seguinte acrescenta a linha nova abaixo desta.
- Veredito do QA: <Aprovado \| Aprovado com ressalvas \| Reprovado>, <data>.

## 7. Riscos e rollback

- Riscos residuais: <um por linha, com owner e prazo quando houver ressalva; ou `Nenhum identificado alem do escopo do diff`>
- Impacto: <contrato, schema, UI, dependencia, pipeline: o que mudou ou `Nenhum: <motivo>`>
- Rollback: <`git revert <sha>` basta \| passos quando nao basta (migration, imagem, dado)>

## 8. Links e aceites

- Entradas de memoria: <ids, ou `Nenhuma: sem decisao duravel`>
- Documentacao sincronizada: <arquivos, ou `Nenhuma`>
- Commit(s): `<sha>` - <assunto>
- PR: <link>
- Tech Lead: **<Aprovado \| Aprovado com ressalvas>**, <data> - <ressalva, se houver>
- Solicitante: <aceite dos `qa-*` por sha256 quando houver (M), ou `Nao aplicavel: sem arquivo do QA`>
