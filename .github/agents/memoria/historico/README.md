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

A tabela abaixo esta **congelada** em 2026-09-12: registros novos nao sao acrescentados a ela (duas sessoes editando a mesma tabela conflitam). O indice atual e o proprio diretorio ordenado por nome (`ls historico/`), e o nome carrega data e hora reais (`YYYY-MM-DD-HHMM-<slug>.md`); os registros de 2026-09-12 numerados `0001`..`0006` sao anteriores a esta regra. Se o arquivo ja existir, ler antes de gravar e, se for outro assunto, acrescentar sufixo ao slug.

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
| 2026-09-12 | [Protocolo de testes convertido em gate executavel](2026-09-12-0001-protocolo-tdd-como-gate-executavel.md) |
| 2026-09-12 | [Protocolo por porte, registro unico de entrega e bootstrap por contexto](2026-09-12-0002-protocolo-por-porte-e-registro-unico.md) |
| 2026-09-12 | [Testes de seguranca e acesso indevido no gate de testes](2026-09-12-0003-testes-de-seguranca-no-protocolo-tdd.md) |
| 2026-09-12 | [Validacao de formularios e feedback visual em E2E](2026-09-12-0004-validacao-de-formularios-em-e2e.md) |
| 2026-09-12 | [Genericizacao normativa do protocolo-tdd](2026-09-12-0005-genericizacao-normativa-protocolo-tdd.md) |
| 2026-09-12 | [Execucao seletiva por modulo e suite completa pre-push](2026-09-12-0006-execucao-seletiva-por-modulo.md) |
| 2026-09-17 | [Suite completa apenas na pipeline de main/master](2026-09-17-1307-suite-completa-na-pipeline.md) |

| 2026-09-19 | [Versionamento por worktree a partir da branch principal declarada](2026-09-19-0941-versionamento-worktree-branch-principal.md) |
| 2026-09-19 | [Modelo de referencia: ambiente de IA gerado por projeto](2026-09-19-0953-modelo-de-referencia-por-projeto.md) |
| 2026-09-19 | [Modulos determinados automaticamente ou definidos pelo solicitante](2026-09-19-1115-modulos-definidos-pelo-solicitante.md) |
| 2026-09-19 | [PRs abertos verificados antes de iniciar a demanda](2026-09-19-1144-prs-abertos-antes-da-demanda.md) |
| 2026-09-23 | [Coordenacao entre instancias do Tech Lead pela branch principal](2026-09-23-1249-coordenacao-multi-tech-lead.md) |
| 2026-09-25 | [Intervencao humana direta: deteccao, confirmacao, regularizacao e reversao autorizada](2026-09-25-0755-intervencao-humana-direta.md) |
| 2026-09-28 | [Testes interrompem no primeiro erro e o reportam para correcao](2026-09-28-1627-testes-interrompem-no-primeiro-erro.md) |
| 2026-09-28 | [Parada no primeiro erro aplicada aos blocos de teste das skills de stack](2026-09-28-1758-fail-fast-nos-blocos-das-skills-de-stack.md) |
| 2026-09-29 | [Ordem da suite completa na pipeline: preparo, suite, demais steps](2026-09-29-0849-ordem-da-suite-na-pipeline.md) |
| 2026-09-30 | [Testes da demanda restritos aos itens afetados; suite completa so na pipeline ou por pedido explicito](2026-09-30-1300-testes-somente-itens-afetados.md) |
