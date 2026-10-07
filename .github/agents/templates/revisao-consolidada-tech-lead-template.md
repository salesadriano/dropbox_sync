# Template - Revisao Consolidada do Tech Lead

> **Modo (regra 40, `Protocolo por porte`):** porte P nao usa este template (aprovacao em uma linha no registro de entrega). Porte M preenche em modo compacto: Identificacao, Artefatos consolidados, Divergencias, Pendencias e Encaminhamento. Porte G preenche todas as secoes. Esta revisao consolida **por referencia** (regra 41): cada linha aponta para o artefato do agent, nunca reescreve seu conteudo.

## Identificacao

- Projeto ou produto:
- Responsavel Tech Lead:
- Data da revisao:
- Escopo revisado:
- Agents envolvidos:
- Status da revisao: Em andamento | Concluida | Concluida com ressalvas
- Porte da demanda: M | G
- Registro de entrega: <link>
- Log de prompt: <link>

## Resumo executivo

- Objetivo da entrega:
- Contexto consolidado:
- Resultado executivo da revisao:
- Recomendacao do Tech Lead:

## PRD e ARD

- PRD aplicavel?: Sim | Nao
- Referencia do PRD:
- ARD aplicavel?: Sim | Nao
- Referencia do ARD:

| Artefato | Item revisado | Consistencia com entrega | Lacunas encontradas | Observacoes |
|---|---|---|---|---|
| PRD |  |  |  |  |
| ARD |  |  |  |  |

## Divergencias entre PRD, ARD, implementacao e evidencias de validacao

| Divergencia | Origem | Impacto | Resolucao adotada | Status |
|---|---|---|---|---|
|  |  |  |  |  |

- Conclusao especifica sobre divergencias entre PRD e ARD:
- Conclusao especifica sobre divergencias entre artefatos, implementacao e evidencias de validacao:

## Artefatos consolidados por agent

| Agent | Artefato (link) | Veredito ou resultado registrado la | Ressalva do Tech Lead |
|---|---|---|---|
| Senior Developer | registro de entrega, parecer de testes, parecer de conformidade |  |  |
| QA Expert | validacao / relatorio de ciclos |  |  |
| Business Analyst | PRD / System Design |  |  |
| UX Expert | Design System / parecer UX |  |  |
| DBA | plano de dimensionamento / parecer de dados |  |  |

Linha sem artefato: `Nao aplicavel: <motivo>`.

## Decisoes proprias do Tech Lead

Apenas decisoes tomadas nesta revisao (desempate, aceite de ressalva, reclassificacao de porte). Decisoes dos agents ja estao nos artefatos referenciados.

| Decisao | Motivacao | Impacto | Status |
|---|---|---|---|
|  |  |  |  |

## Itens impactados e pontos validados (porte G)

| Item | Tipo | Evidencia (link) | Risco | Mitigacao |
|---|---|---|---|---|
|  |  |  |  |  |

## Pendencias, bloqueios e riscos residuais

| Tipo | Descricao | Impacto | Owner | Proxima acao |
|---|---|---|---|---|
| Pendencia |  |  |  |  |

## Impacto global da entrega

- Impacto no negocio:
- Impacto tecnico:
- Impacto operacional:
- Impacto em UX:
- Impacto em dados:

## Encaminhamento para fechamento

- Pronto para aprovacao final?: Sim | Nao
- Dependencias para `templates/aprovacao-final-tech-lead-template.md`:
- Arquivo concreto desta revisao consolidada para referencia no fechamento final:
- Resumo das divergencias resolvidas que devem constar no fechamento final:
- Bloqueios remanescentes que precisam constar no fechamento final:
- Observacoes finais do Tech Lead:

Diagrama Mermaid apenas em porte G, quando houver fluxo de decisao ou dependencia entre agents que o texto nao descreva.
