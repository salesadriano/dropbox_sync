# Catalogo de templates operacionais

Consultar apenas quando o fluxo correspondente for acionado. A obrigatoriedade de cada template vem do protocolo comum (`../AGENTS.md`), do porte da demanda (regra 40 e secao `Protocolo por porte`) ou da persona. Em porte P e M, os pareceres de gate sao preenchidos em modo compacto (instrucao no topo de cada template).

| Template | Uso | Quem preenche |
|---|---|---|
| `evidencia-testes-template.md` | Gate local de testes exigido por `../../skills/protocolo-tdd/`: criterios BDD e seams acordadas, evidencia do ciclo red-green-refactor, execucao por camada, distribuicao real da piramide, governanca de dados, tratamento de flaky, achados por severidade, veredito e devolucao acionavel quando reprovado | Agent que produziu a alteracao |
| `parecer-conformidade-template.md` | Gate local de conformidade arquitetural e de boas praticas exigido por `../../skills/protocolo-conformidade/`: escopo do diff, skills aplicadas, achados por severidade, veredito e devolucao acionavel quando reprovado | Agent que produziu a alteracao |
| `qa-reprovacao-e-ciclos-template.md` | Falhas de QA, ciclos QA -> Developer, refatoracoes e eventual escalonamento ao solicitante | QA Expert |
| `qa-validacao-frontend-template.md` | Validacao QA de fluxos frontend: template padrao, vinculo System Design -> Design System, referencias de Figma e Storybook.js, evidencias e bloqueios | QA Expert |
| `aprovacao-e-reaprovacao-solicitante-template.md` | Aprovacao explicita e reaprovacao do solicitante sobre testes do QA ou iteracoes posteriores | QA Expert |
| `setup-e-checklist-cypress-template.md` | Setup, prerequisitos, checklist operacional e evidencias para execucao de E2E com Cypress no projeto e no container | Senior Developer e QA Expert |
| `plano-dimensionamento-expansao-banco-template.md` | Plano de dimensionamento e expansao do banco e handoff ao Business Analyst | DBA |
| `design-system-completo-template.md` | Design System completo: componentes, interfaces, imagens de proposta e reais, referencias de Figma e Storybook.js | UX Expert |
| `system-design-template.md` | System Design: arquitetura, implantacao, dimensionamento, integracoes e referencia obrigatoria ao Design System quando houver frontend | Business Analyst |
| `system-design-exemplo-preenchido.md` | Exemplo preenchido do System Design, como referencia pratica | Leitura apenas |
| `revisao-consolidada-tech-lead-template.md` | Revisao consolidada por referencia aos artefatos dos agents: decisoes, divergencias tratadas, riscos residuais e impacto global | Tech Lead |
| `aprovacao-final-tech-lead-template.md` | Aprovacao final: referencias ao System Design, validacao QA frontend, gates aplicados, riscos residuais e decisao de fechamento | Tech Lead |

Regra de preenchimento comum a todos: secao ou tabela sem conteudo nao recebe placeholder; e omitida com a linha `Nao aplicavel: <motivo>` (regra 41). Fato ja registrado em outro artefato e referenciado por link, nunca copiado.
