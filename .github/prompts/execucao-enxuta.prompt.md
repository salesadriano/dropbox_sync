---
name: execucao-enxuta
description: Executa uma tarefa com feedback intermediario minimo e relatorio final detalhado.
argument-hint: Descreva a tarefa, objetivo ou entrega desejada.
agent: tech-lead
---

Execute a tarefa abaixo seguindo o padrao de comunicacao enxuta do workspace.

Tarefa solicitada:

${input:tarefa:Descreva a tarefa ou cole a solicitacao completa}

Instrucoes obrigatorias:

1. Use atualizacoes intermediarias apenas quando houver marco relevante, bloqueio, mudanca de decisao ou proximo passo imediato.
2. Mantenha cada atualizacao intermediaria curta, sem narrar microacoes.
3. No encerramento, entregue o relatorio por referencia (regras 33 e 41 do protocolo comum): link para o registro de entrega e para os pareceres de gate, e apenas o que nao esta neles:
   - decisoes proprias desta etapa e respectivas motivacoes;
   - riscos residuais, pendencias e proximo passo, quando existirem.
   Nao reescreva arquivos alterados, atividades ou validacoes ja registrados no registro de entrega.
4. Preserve a rastreabilidade com base no protocolo comum em [AGENTS.md](../agents/AGENTS.md) e na memoria estrutural em [MEMORIA-COMPARTILHADA.md](../agents/memoria/MEMORIA-COMPARTILHADA.md).
5. Se o pedido envolver alteracoes no repositorio, sincronize a documentacao materialmente impactada antes de encerrar.

Formato esperado durante a execucao:

- Exemplo de status curto: `Marco concluido: criterios levantados. Proximo passo: aplicar a alteracao principal.`

Formato esperado ao final:

- Exemplo de relatorio final: `Registro de entrega: docs/reviews/2026-09-12-1030-slug.md (porte M, gates aprovados). Decisao desta etapa: ... Pendencia: ... Proximo passo: ...`
