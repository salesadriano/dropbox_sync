# Atualizacao de memoria - premissas de precedencia e dados de teste do QA Expert

## Contexto da mudanca

Foi solicitada a atualizacao do `qa-expert.agent.md` para explicitar que os roteiros de teste devem considerar precedencia entre cenarios, persistencia dos dados ao longo da execucao e descarte apenas ao final.

## Decisao tomada

O QA Expert passou a incorporar as seguintes premissas operacionais:

- a ordem dos testes deve ser explicitada quando houver dependencia de estado
- os dados gerados por um teste podem e devem ser reutilizados por testes subsequentes do mesmo roteiro quando isso fizer parte do fluxo validado
- a limpeza dos dados de teste deve ocorrer apenas ao encerramento do roteiro
- toda massa de dados deve vir do seeder inicial ou de testes anteriores, sem dependencia de criacao manual externa

Essas premissas foram refletidas na missao, nas responsabilidades, na politica operacional e nos entregaveis obrigatorios do QA Expert.

## Impacto tecnico/negocio

- Melhora aderencia dos testes a fluxos reais de uso e persistencia.
- Reduz fragilidade causada por pre-condicoes ocultas ou massas de dados fora do controle do roteiro.
- Aumenta rastreabilidade entre preparacao, execucao e limpeza dos dados de teste.

## Proximos passos

1. Verificar se o Senior Developer tambem deve explicitar dependencia entre cenarios de preparacao de dados quando houver suites integradas.
2. Padronizar futuros planos de teste com um bloco obrigatorio de origem e ciclo de vida dos dados.

## Rastreabilidade

- Memoria atualizada: `Agentes/memoria/MEMORIA-COMPARTILHADA.md`
- Arquivo alterado: `Agentes/qa-expert.agent.md`
- Solicitacao base: atualizar o QA Expert para considerar precedencia entre testes e persistencia controlada dos dados

## Diagrama da mudanca

```mermaid
flowchart LR
  S[Seeder inicial] --> T1[Teste 1 cria ou usa dados]
  T1 --> T2[Teste 2 reutiliza estado anterior]
  T2 --> T3[Teste 3 valida fluxo dependente]
  T3 --> L[Limpeza final controlada]
  L --> P[Parecer QA]
```