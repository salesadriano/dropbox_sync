# Memoria Geral Compartilhada dos Agents

> Arquivo versionavel e obrigatorio para todos os agents deste pacote.

## Regras de persistencia

- Esta memoria guarda **estado e decisoes ativas** do pacote. As **regras** de execucao vivem em [.claude/agents-protocol/AGENTS.md](../AGENTS.md) e nao devem ser reescritas aqui.
- Decisoes de demanda/projeto (escopo, arquitetura, implementacao, validacao, aceite) vao para `MEMORIA-PROJETO.md`; decisoes transversais ficam aqui e sao refletidas la com referencia cruzada.
- Detalhes extensos, cronologia e evidencias completas ficam em `historico/` — indice em [historico/README.md](historico/README.md).
- Conteudo curto, consolidado e sem duplicacao textual. Mermaid apenas quando explicar um fluxo estrutural nao descrito em outro arquivo.

## Contexto do pacote

| Campo | Valor |
|---|---|
| Projeto | Pacote de agents reutilizaveis (Agentes) |
| Objetivo atual | Manter um baseline enxuto de protocolo e comportamento para agents e skills |
| Stack detectada | Markdown (documentacao e configuracao de agents) |
| Estado do baseline | Estabilizado e portavel |
| Responsavel de consolidacao | Tech Lead |

## Resumo estrutural

- Protocolo comum centralizado em [.claude/agents-protocol/AGENTS.md](../AGENTS.md); esta memoria e apenas o resumo duravel do baseline.
- Agents operam com personas explicitas, handoffs rastreaveis e gates obrigatorios por papel.
- Skills complementam o protocolo com especializacao reutilizavel, acionadas de forma disciplinada e sem duplicar o comportamento transversal.

## Decisoes ativas de protocolo, agents e skills

Dono de todas as decisoes abaixo: **Tech Lead**. Status: **Ativa**, salvo indicacao contraria.
A coluna `Regra` aponta o item de `.claude/agents-protocol/AGENTS.md` que implementa a decisao — a redacao normativa vive la, nao aqui.

| ID | Decisao | Regra |
|---|---|---|
| DEC-STR-01 | Protocolo comum + memoria compartilhada concisa + historico versionado. | .claude/agents-protocol/AGENTS.md 1, 7 |
| DEC-STR-02 | Agents mantem persona explicita, handoffs rastreaveis e detectam stack antes de executar. | .claude/agents-protocol/AGENTS.md 3, 6 |
| DEC-STR-03 | Gates obrigatorios: QA para validacao independente, UX para frontend, DBA para persistencia. | Personas |
| DEC-STR-04 | Business Analyst e dono do System Design; DBA fornece plano de capacidade; handoff DBA -> BA e explicito. | .claude/agents-protocol/AGENTS.md 24 |
| DEC-STR-05 | Senior Developer usa TDD, avalia no minimo 3 abordagens, aplica Clean Architecture e prioriza reutilizacao. | .claude/agents-protocol/AGENTS.md 14 |
| DEC-STR-06 | Toda implementacao passa por QA; escalonamento ao solicitante apos mais de 3 ciclos de reprovacao. | Personas |
| DEC-STR-07 | Testes do QA exigem aprovacao explicita do solicitante; alteracoes posteriores exigem reaprovacao. | .claude/agents-protocol/AGENTS.md 12 |
| DEC-STR-08 | Cypress e o padrao de E2E; SD prepara prerequisitos, QA valida execucao real. | .claude/agents-protocol/AGENTS.md 13 |
| DEC-STR-09 | Em frontend, System Design referencia o Design System; QA valida o vinculo; TL trata como aceite. | .claude/agents-protocol/AGENTS.md 16 |
| DEC-STR-10 | UX define a estrutura funcional do Storybook; Senior Developer sustenta a implementacao tecnica. | .claude/agents-protocol/AGENTS.md 23 |
| DEC-STR-11 | Tech Lead consolida atividades, PRD/ARD, divergencias e impacto global antes do fechamento. | .claude/agents-protocol/AGENTS.md 10, 20, 21 |
| DEC-STR-12 | Todos os agents sinalizam divergencias do proprio dominio entre requisitos, arquitetura, implementacao e evidencias. | .claude/agents-protocol/AGENTS.md 22 |
| DEC-STR-13 | Templates e skills permanecem reutilizaveis, agnosticos ao projeto e alinhados aos papeis. | .claude/agents-protocol/AGENTS.md 36, 37 |
| DEC-STR-14 | Governanca de PR centralizada em um unico workflow, com labels de review e sincronizacao com issues. | .claude/agents-protocol/AGENTS.md 25, 26 |
| DEC-STR-15 | Skills concentram detalhamento operacional; protocolo fica em `.claude/agents-protocol/AGENTS.md`; personas guardam so o especifico do papel. | .claude/agents-protocol/AGENTS.md 36, 37 |
| DEC-STR-16 | `prompt-logger` obrigatorio em toda solicitacao, com sanitizacao previa de segredos e PII. | .claude/agents-protocol/AGENTS.md 2 |
| DEC-STR-17 | A deteccao de stack produz mapeamento explicito stack -> skill. | .claude/agents-protocol/AGENTS.md "Deteccao de stack" |
| DEC-STR-18 | Skills com sobreposicao declaram `Scope boundary` com links para as complementares. | Skills |
| DEC-STR-19 | Exemplos de codigo em skills nao podem conter vulnerabilidades; warnings devem ser explicitos. | Skills |
| DEC-STR-22 | O bootstrap de `.claude/agents-protocol/AGENTS.md` antes das memorias deve ser explicito em todo agent. | .claude/agents-protocol/AGENTS.md 1 + personas |
| DEC-STR-23 | Baseline de Context7 MCP versionado em `.vscode/mcp.json` quando ausente, sem expor segredos. | .claude/agents-protocol/AGENTS.md 27 |
| DEC-STR-24 | Context7, quando habilitado, e fonte preferencial de documentacao tecnica. | .claude/agents-protocol/AGENTS.md 28 |
| DEC-STR-25 | Documentos formais de governanca em portugues do Brasil por padrao; logs do `prompt-logger` seguem o idioma do prompt. | .claude/agents-protocol/AGENTS.md 29 |
| DEC-STR-26 | Gitflow aceita `feature/*`, `bugfix/*`, `release/*`, `hotfix/*` e `support/*`. | .claude/agents-protocol/AGENTS.md 25 |
| DEC-STR-27 | Feedback enxuto durante a execucao; detalhamento completo no encerramento ou handoff. | .claude/agents-protocol/AGENTS.md 30, 31 |
| DEC-STR-31 | Utilitarios opcionais podem ser versionados sem virar obrigacao protocolar sem decisao explicita. | — |
| DEC-STR-32 | Carga lazy de skills: ler `SKILL.md` primeiro e nunca o diretorio inteiro, evitando os monoliticos de 94-163 KB. | .claude/agents-protocol/AGENTS.md 35 |
| DEC-STR-33 | Cada regra e declarada uma unica vez na camada que a possui; personas nao repetem o protocolo transversal. | .claude/agents-protocol/AGENTS.md 36, 37 |

## Ownerships criticos

| Tema | Ownership principal | Apoio obrigatorio |
|---|---|---|
| Consolidacao final | Tech Lead | Todos os agents alimentam evidencias, divergencias e handoffs |
| System Design | Business Analyst | DBA para capacidade e dados; UX para referencia ao Design System em frontend |
| Design System | UX Expert | Senior Developer para implementacao tecnica de Storybook quando houver frontend |
| Implementacao | Senior Developer | QA para validacao independente |
| E2E com Cypress | QA Expert na validacao | Senior Developer nos prerequisitos tecnicos |
| Plano de banco e expansao | DBA | Business Analyst para consolidacao no System Design |

Artefatos padrao e templates: ver secao `Templates operacionais` em [.claude/agents-protocol/AGENTS.md](../AGENTS.md).
Fluxo de colaboracao entre agents: ver secao `Fluxo de colaboracao` em [.claude/agents-protocol/AGENTS.md](../AGENTS.md).

## Estado do backlog

| Item | Estado |
|---|---|
| Baseline estrutural do pacote | Concluido e sem backlog estrutural ativo no momento |

## Riscos permanentes

| Risco | Mitigacao permanente |
|---|---|
| Agents perderem especificidade operacional ao longo do tempo | Preservar personas explicitas, handoffs e metricas por papel |
| Divergencia entre protocolo, templates, skills e agents | Consolidar nesta memoria e detalhar ajustes no historico |
| Fechamentos sem rastreabilidade suficiente | Exigir revisao consolidada, evidencias e registros de aprovacao |
| Skills do mapeamento de stack nao existirem no workspace-alvo | Verificar disponibilidade antes de consumir; auditar o mapeamento ao portar o pacote |
| Exemplos de codigo em skills introduzirem vulnerabilidades | Revisao de seguranca obrigatoria ao adicionar exemplos; criterio em `DEC-STR-19` |
| Regra transversal voltar a ser duplicada em personas ou memorias | Aplicar `DEC-STR-33` em toda revisao de agent |

Owner de todos os riscos acima: Tech Lead.
