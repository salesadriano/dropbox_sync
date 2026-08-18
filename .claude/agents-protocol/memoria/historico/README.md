# Historico das Memorias dos Agents

Este diretorio deve manter apenas registros estruturais e reutilizaveis para o futuro dos agents, cobrindo memoria geral e memoria de projeto.

Nao manter aqui:

- iteracoes editoriais de curta duracao;
- etapas intermediarias de consolidacao de templates;
- ajustes operacionais ja absorvidos pela memoria geral, memoria de projeto ou pelos artefatos permanentes.

Cada atualizacao estrutural relevante das memorias deve gerar um arquivo:

- Padrao: `YYYY-MM-DD-HHMM-<slug>.md`
- Conteudo minimo:
  - Contexto da mudanca
  - Decisao tomada
  - Impacto tecnico/negocio
  - Proximos passos
  - Bloco Mermaid (quando aplicavel)

Exemplo de nome:

`2026-03-20-2330-definicao-fluxo-handoff.md`

## Indice de registros estruturais

Este indice vive aqui, e nao em `MEMORIA-COMPARTILHADA.md`, porque e trilha de auditoria consultada sob demanda — nao contexto que todo agent precise carregar a cada execucao.

| Data | Registro |
|---|---|
| 2026-03-21 | [Alinhamento de arquetipos dos agents](2026-03-21-0903-alinhamento-arquetipos-agents.md) |
| 2026-03-21 | [Premissas de precedencia e dados de teste do QA](2026-03-21-0942-premissas-precedencia-dados-qa.md) |
| 2026-03-21 | [Senior Developer: TDD e Clean Architecture](2026-03-21-1047-senior-developer-tdd-clean-architecture.md) |
| 2026-03-21 | [UX: Design System, Storybook e Figma](2026-03-21-1113-ux-design-system-storybook-figma.md) |
| 2026-03-21 | [Tech Lead: criterio de aceite do Design System](2026-03-21-1121-tech-lead-criterio-aceite-design-system.md) |
| 2026-03-21 | [Skills genericizadas e alinhadas](2026-03-21-1223-skills-genericizadas-e-alinhadas.md) |
| 2026-03-21 | [Definicao das personas dos agents](2026-03-21-1224-definicao-personas-agents.md) |
| 2026-03-21 | [Limpeza estrutural da memoria](2026-03-21-1245-limpeza-memoria-estrutural.md) |
| 2026-03-21 | [Consolidacao da governanca de PR, issue e review](2026-03-21-1315-consolidacao-governanca-pr-issue-review.md) |
| 2026-03-21 | [Alinhamento skills/agents e portabilidade](2026-03-21-1345-alinhamento-skills-agents-portabilidade.md) |
| 2026-03-22 | [Obrigatoriedade do prompt-logger](2026-03-22-0001-obrigatoriedade-prompt-logger.md) |
| 2026-03-23 | [Centralizacao do protocolo e genericizacao da skill](2026-03-23-0001-centralizacao-protocolo-genericizacao-skill.md) |
| 2026-03-23 | [Diferenciacao de skills documentais e limpeza do catalogo](2026-03-23-0002-diferenciacao-skills-documentais-e-limpeza-catalogo.md) |
| 2026-03-23 | [Validacao de links em skills e desambiguacao de acessibilidade](2026-03-23-0003-validacao-links-skills-e-desambiguacao-acessibilidade.md) |
| 2026-03-31 | [Evolucao de skills, agents, vulnerabilidades e governanca](2026-03-31-0001-evolucao-skills-agents-vulnerabilidades-governanca.md) |
| 2026-04-18 | [Bootstrap: agents carregam AGENTS.md](2026-04-18-0001-bootstrap-agents-carregam-agents-md.md) |
| 2026-04-18 | [Context7 MCP: baseline de workspace](2026-04-18-0002-context7-mcp-workspace-baseline.md) |
| 2026-04-18 | [Context7: uso operacional em todos os agents](2026-04-18-0003-context7-uso-operacional-todos-agents.md) |
| 2026-04-18 | [Governanca: portugues do Brasil como padrao](2026-04-18-0004-governanca-ptbr-padrao.md) |
| 2026-04-18 | [Alinhamento das branches Gitflow](2026-04-18-0005-alinhamento-gitflow-branches.md) |
| 2026-04-18 | [Onboarding: bugfix versus support](2026-04-18-0006-onboarding-gitflow-bugfix-support.md) |
| 2026-04-27 | [Comunicacao enxuta dos agents](2026-04-27-0001-comunicacao-enxuta-agents.md) |
| 2026-04-27 | [Prompt de workspace e exemplos de comunicacao](2026-04-27-0002-prompt-workspace-e-exemplos-comunicacao.md) |
| 2026-04-27 | [Relatorio final com total de tokens](2026-04-27-0003-relatorio-final-com-total-de-tokens.md) |
| 2026-04-27 | [Resumo de memoria, protocolo, agents e skills](2026-04-27-0004-resumo-memoria-protocolo-agents-skills.md) |
| 2026-04-27 | [Calculo continuo de tokens](2026-04-27-0005-calculo-continuo-de-tokens.md) |
| 2026-04-27 | [Remocao dos tokens do protocolo](2026-04-27-0009-remocao-tokens-do-protocolo.md) |
| 2026-04-27 | [Remocao do helper de tokens](2026-04-27-0010-remocao-helper-tokens.md) |
| 2026-05-11 | [Sanitizacao do prompt-logger e normalizacao de skills](2026-05-11-0001-sanitizacao-promptlogger-e-normalizacao-skills.md) |
| 2026-08-17 | [Otimizacao de contexto dos agents e modelo dos subagents utilitarios](2026-08-17-0001-otimizacao-contexto-e-modelo-subagents.md) |
| 2026-08-18 | [Fechamento da Etapa 1 — camada de dominio (dropbox_api)](2026-08-18-0001-fechamento-etapa-1-camada-dominio.md) |

