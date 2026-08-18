# Atualizacao de memoria - criterio de aceite do Tech Lead para referencia ao Design System

## Contexto da mudanca

Foi solicitado que a referencia explicita ao documento de Design System do UX dentro do System Design passe a ser um criterio obrigatorio de aceite do Tech Lead em entregas com frontend.

## Decisao tomada

O `tech-lead.agent.md` foi atualizado para exigir, no foco, na decisao, no protocolo de atuacao e nos criterios de aprovacao, a verificacao explicita desse vinculo documental antes da aprovacao final de entregas com frontend.

## Impacto tecnico/negocio

- Impede aprovacao final de entregas frontend com lacuna entre arquitetura e experiencia.
- Reforca governanca documental entre Business Analyst, UX Expert e Tech Lead.
- Melhora auditabilidade da relacao entre Figma, Storybook.js, System Design e implementacao real.

## Proximos passos

1. Avaliar se o `AGENTS.md` deve elevar essa exigencia para o protocolo comum obrigatorio.
2. Verificar se o QA Expert deve citar essa checagem como precondicao em testes E2E de frontend.

## Rastreabilidade

- Memoria atualizada: `Agentes/memoria/MEMORIA-COMPARTILHADA.md`
- Arquivos alterados:
  - `Agentes/tech-lead.agent.md`
  - `Agentes/memoria/MEMORIA-COMPARTILHADA.md`
- Solicitacao base: tornar a referencia ao Design System um criterio explicito de aceite no Tech Lead para entregas com frontend

## Diagrama da mudanca

```mermaid
flowchart LR
  BA[Business Analyst atualiza System Design] --> UX[Design System do UX referenciado]
  UX --> TL[Tech Lead valida criterio de aceite]
  TL --> A[Aprovacao final da entrega frontend]
```