# Template - Parecer de Conformidade Arquitetural e de Boas Praticas

Preenchido pelo agent que produziu a alteracao, conforme `../skills/protocolo-conformidade/`, antes de qualquer handoff.

> **Modo do parecer (regra 40 e `Protocolo por porte` do `AGENTS.md`):** em porte **P** e **M**, preencher apenas Identificacao, Escopo, Stack detectada e skills aplicadas, Achados, Veredito e, se reprovado, Devolucao; substituir as tabelas de verificacao pela linha `Checklist clean-architecture + <skill de stack> aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados`. Em porte **G**, preencher todas as secoes. Secao sem conteudo e omitida com `Nao aplicavel: <motivo>`, nunca preenchida com placeholders.

## Identificacao

- Projeto ou produto:
- Agent responsavel pela alteracao:
- Agent responsavel pela verificacao:
- Data da verificacao:
- Ciclo de verificacao: 1 | 2 | 3 | escalonado ao Tech Lead
- Tipo de alteracao: Implementacao nova | Refatoracao | Correcao de defeito | Ajuste pontual
- Execucao: local, sem pipeline
- Porte da demanda: P | M | G
- Modo do parecer: Compacto | Completo

## Escopo verificado

- Comando usado para levantar o diff:
- Base de comparacao (quando aplicavel):

| Arquivo | Tipo de alteracao | Camada / modulo | Verificado |
|---|---|---|---|
|  | Novo / Alterado / Removido |  | Sim / Nao |

- Arquivos alterados e nao verificados, com motivo:

## Stack detectada e skills aplicadas

- Stack detectada:
- Evidencia da deteccao (arquivo de manifesto, extensao predominante):

| Skill aplicada | Motivo da selecao | Regras consultadas |
|---|---|---|
| `clean-architecture` | obrigatoria em qualquer stack |  |
|  |  |  |

- Skills consideradas e descartadas, com motivo:

## Verificacao arquitetural

| Verificacao | Regra | Resultado | Evidencia |
|---|---|---|---|
| Direcao de dependencia | `dep-inward-only` | Conforme / Nao conforme / Nao aplicavel |  |
| Propriedade da interface | `dep-interface-ownership` |  |  |
| Pureza de dominio | `frame-domain-purity` |  |  |
| Dados na fronteira | `dep-data-crossing-boundaries` |  |  |
| Ciclos de dependencia | `dep-acyclic-dependencies` |  |  |
| Modelo rico | `entity-rich-not-anemic` |  |  |
| Invariantes na entidade | `entity-encapsulate-invariants` |  |  |
| Entidade sem persistencia | `entity-no-persistence-awareness` |  |  |
| Caso de uso orquestra | `usecase-orchestrates-not-implements` |  |  |
| Sem logica de apresentacao no caso de uso | `usecase-no-presentation-logic` |  |  |
| Dependencias explicitas | `usecase-explicit-dependencies` |  |  |
| Fronteira transacional | `usecase-transaction-boundary` |  |  |
| Controller fino | `adapt-controller-thin` |  |  |
| Sistema externo isolado | `adapt-gateway-abstraction` |  |  |
| Coesao e estrutura do dominio | `comp-common-closure`, `comp-screaming-architecture` |  |  |

## Verificacao da skill de stack

| Regra verificada | Skill | Resultado | Evidencia |
|---|---|---|---|
|  |  |  |  |

## Verificacao de seguranca acionada

- O diff toca autenticacao, autorizacao, segredos, dados sensiveis, sessao/cookies, CSP/CORS ou exposicao de API?: Sim | Nao
- Se sim, skills aplicadas: `security-best-practices` | `api-security-best-practices`

| Item | Resultado | Evidencia |
|---|---|---|
| Ausencia de segredo no diff |  |  |
| Validacao de entrada nas novas fronteiras |  |  |
| Autorizacao verificada nos novos acessos |  |  |
| Isolamento por tenant quando aplicavel |  |  |

## Consistencia com o projeto

| Item | Resultado | Observacoes |
|---|---|---|
| Segue padrao ja adotado em modulos equivalentes |  |  |
| Nao reimplementa componente existente |  |  |
| Coerente com System Design / ARD |  |  |
| Coerente com decisoes nas memorias do pacote |  |  |
| Vocabulario de dominio preservado |  |  |

## Ferramentas locais executadas

| Ferramenta | Comando | Resultado | Disponivel no projeto |
|---|---|---|---|
| Linter |  |  | Sim / Nao |
| Type checker |  |  | Sim / Nao |
| Analise de ciclos |  |  | Sim / Nao |

- Limitacoes por ausencia de ferramenta:

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correcao esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 |  |  |  |  | Bloqueante / Maior / Menor | Aberto / Corrigido / Justificado |

- Total de bloqueantes:
- Total de maiores:
- Total de menores:

## Achados do ciclo anterior

Preencher a partir do ciclo 2.

| # do ciclo anterior | Achado | Status atual | Evidencia da correcao |
|---|---|---|---|
|  |  | Corrigido / Nao corrigido / Justificado |  |

## Veredito

- Resultado: Aprovado | Aprovado com ressalvas | Reprovado
- Justificativa objetiva:
- Ressalvas registradas, com owner e prazo:
- Handoff liberado?: Sim | Nao
- Proximo passo do ciclo do developer:

## Devolucao ao agent (preencher apenas se Reprovado)

| # | Arquivo:linha | Achado | Regra violada | Correcao esperada | Severidade |
|---|---|---|---|---|---|
|  |  |  |  |  |  |

- Agent destinatario:
- Acao requerida: corrigir os itens acima e reexecutar `protocolo-conformidade` antes de qualquer handoff.
- Reincidencia de achado ja apontado?: Sim | Nao
- Escalonamento ao Tech Lead necessario?: Sim | Nao

## Registro

- Quando houver decisao duravel ou justificativa aceita, gravar uma entrada em `../memoria/entradas/` (`escopo: projeto`, ou `pacote` se mudar regra transversal) com `ref:` para este parecer (regra 35).
- Referenciar este parecer no registro tecnico produzido por `../skills/review-documentation/`.
