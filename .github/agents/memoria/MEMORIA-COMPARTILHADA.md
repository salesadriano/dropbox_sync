# Memoria Geral Compartilhada dos Agents

> Arquivo versionavel e obrigatorio para todos os agents deste pacote.

## Regras de persistencia

- Esta memoria guarda **estado e decisoes ativas** do pacote. As **regras** de execucao vivem em [AGENTS.md](../AGENTS.md) e nao devem ser reescritas aqui.
- **Este arquivo e estavel e as tabelas abaixo estao congeladas** desde 2026-09-12: nenhuma sessao acrescenta linha aqui. Toda decisao nova, de qualquer escopo, e **uma entrada por arquivo** em [entradas/](entradas/README.md), com `escopo: pacote` para decisoes transversais e `escopo: projeto` para decisoes de demanda. Decisao que altera uma linha congelada e uma entrada com `substitui: DEC-STR-nn`.
- O estado consolidado e lido por `sh scripts/memoria-index.sh` (filtros `--escopo`, `--tipo`), que gera o indice a partir das entradas; o indice nao e versionado. Bootstrap por papel (regra 1): o Tech Lead le este arquivo, `MEMORIA-PROJETO.md` e o indice completo; os demais agents leem apenas `--agente <papel>` e recebem do Tech Lead o que faltar (regra 43).
- Detalhes extensos, cronologia e evidencias completas ficam em `historico/`, um arquivo por registro, nome `YYYY-MM-DD-HHMM-<slug>.md`; o indice de `historico/` tambem e gerado, nao mantido a mao.
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

- Protocolo comum centralizado em [AGENTS.md](../AGENTS.md); esta memoria e apenas o resumo duravel do baseline.
- Agents operam com personas explicitas, handoffs rastreaveis e gates obrigatorios por papel.
- Skills complementam o protocolo com especializacao reutilizavel, acionadas de forma disciplinada e sem duplicar o comportamento transversal.

## Decisoes consolidadas ate 2026-09-12 (tabela congelada)

Dono de todas as decisoes abaixo: **Tech Lead**. Status: **Ativa**, salvo entrada posterior em `entradas/` com `substitui:` apontando para o ID. Decisoes a partir de 2026-09-12 estao em `entradas/` e aparecem no indice gerado.
A coluna `Regra` aponta o item de `AGENTS.md` que implementa a decisao — a redacao normativa vive la, nao aqui.

| ID | Decisao | Regra |
|---|---|---|
| DEC-STR-01 | Protocolo comum + memoria compartilhada concisa + historico versionado. | AGENTS.md 1, 7 |
| DEC-STR-02 | Agents mantem persona explicita, handoffs rastreaveis e detectam stack antes de executar. | AGENTS.md 3, 6 |
| DEC-STR-03 | Gates obrigatorios: QA para validacao independente, UX para frontend, DBA para persistencia. | Personas |
| DEC-STR-04 | Business Analyst e dono do System Design; DBA fornece plano de capacidade; handoff DBA -> BA e explicito. | AGENTS.md 26 |
| DEC-STR-05 | Senior Developer usa TDD, aplica Clean Architecture e prioriza reutilizacao. A analise minima de 3 abordagens e obrigatoria em nova implementacao, refinamento e melhoria; em correcao de defeito e opcional, tornando-se exigida quando houver multiplas solucoes plausiveis, alta criticidade, causa raiz nao isolada ou mudanca de contrato/fronteira/schema. Usar a excecao exige registrar a justificativa. | AGENTS.md 14 + persona do Senior Developer |
| DEC-STR-06 | Toda implementacao passa por QA; escalonamento ao solicitante apos mais de 3 ciclos de reprovacao. | Personas |
| DEC-STR-07 | Testes do QA exigem aprovacao explicita do solicitante; alteracoes posteriores exigem reaprovacao. | AGENTS.md 12 |
| DEC-STR-08 | Cypress e o padrao de E2E; SD prepara prerequisitos, QA valida execucao real. | AGENTS.md 13 |
| DEC-STR-09 | Em frontend, System Design referencia o Design System; QA valida o vinculo; TL trata como aceite. | AGENTS.md 18 |
| DEC-STR-10 | UX define a estrutura funcional do Storybook; Senior Developer sustenta a implementacao tecnica. | AGENTS.md 25 |
| DEC-STR-11 | Tech Lead consolida atividades, PRD/ARD, divergencias e impacto global antes do fechamento. | AGENTS.md 10, 22, 23 |
| DEC-STR-12 | Todos os agents sinalizam divergencias do proprio dominio entre requisitos, arquitetura, implementacao e evidencias. | AGENTS.md 24 |
| DEC-STR-13 | Templates e skills permanecem reutilizaveis, agnosticos ao projeto e alinhados aos papeis. | AGENTS.md 38, 39 |
| DEC-STR-14 | Governanca de PR centralizada em um unico workflow, com labels de review e sincronizacao com issues. | AGENTS.md 27, 28 |
| DEC-STR-15 | Skills concentram detalhamento operacional; protocolo fica em `AGENTS.md`; personas guardam so o especifico do papel. | AGENTS.md 38, 39 |
| DEC-STR-16 | `prompt-logger` obrigatorio em toda solicitacao, com sanitizacao previa de segredos e PII; um arquivo por demanda, texto integral de cada prompt, intencao e inferencias; plano e resultado ficam no registro de entrega. | AGENTS.md 2 |
| DEC-STR-17 | A deteccao de stack produz mapeamento explicito stack -> skill. | AGENTS.md "Deteccao de stack" |
| DEC-STR-18 | Skills com sobreposicao declaram `Scope boundary` com links para as complementares. | Skills |
| DEC-STR-19 | Exemplos de codigo em skills nao podem conter vulnerabilidades; warnings devem ser explicitos. | Skills |
| DEC-STR-22 | O bootstrap de `AGENTS.md` antes das memorias deve ser explicito em todo agent. | AGENTS.md 1 + personas |
| DEC-STR-23 | Baseline de Context7 MCP versionado em `.vscode/mcp.json` quando ausente, sem expor segredos. | AGENTS.md 29 |
| DEC-STR-24 | Context7, quando habilitado, e fonte preferencial de documentacao tecnica. | AGENTS.md 30 |
| DEC-STR-25 | Documentos formais de governanca em portugues do Brasil por padrao; logs do `prompt-logger` seguem o idioma do prompt. | AGENTS.md 31 |
| DEC-STR-26 | Gitflow aceita `feature/*`, `bugfix/*`, `release/*`, `hotfix/*` e `support/*`. | AGENTS.md 27 |
| DEC-STR-27 | Feedback enxuto durante a execucao; detalhamento completo no encerramento ou handoff. | AGENTS.md 32, 33 |
| DEC-STR-31 | Utilitarios opcionais podem ser versionados sem virar obrigacao protocolar sem decisao explicita. | — |
| DEC-STR-32 | Carga lazy de skills: ler `SKILL.md` primeiro e nunca o diretorio inteiro, evitando os monoliticos de 94-163 KB. | AGENTS.md 37 |
| DEC-STR-33 | Cada regra e declarada uma unica vez na camada que a possui; personas nao repetem o protocolo transversal. | AGENTS.md 38, 39 |
| DEC-STR-34 | Duas verificacoes locais obrigatorias por entrega com codigo: `protocolo-tdd` (comportamento) e `protocolo-conformidade` (arquitetura e boas praticas). Ambas classificam achados por severidade, emitem veredito em template proprio e bloqueiam o handoff quando reprovadas. Nenhuma delas depende de pipeline. | AGENTS.md 14, 16, 17 |
| DEC-STR-35 | A trilha de prompts e versionada: `docs/prompts/` fica fora do ignore e a sanitizacao e precondicao de escrita, nao revisao posterior. | AGENTS.md 2 |
| DEC-STR-36 | Subagents utilitarios (`documentation-writer`, `commit-writer`) nao fazem o bootstrap: recebem o contexto na delegacao e carregam apenas a skill do oficio; renderizam, nao decidem. Substitui a redacao anterior. | AGENTS.md 4, 5, 42 |
| DEC-STR-37 | Nome de modelo vive apenas no `model:` da persona; o protocolo nao replica identificador de modelo. | AGENTS.md "Proposito" |
| DEC-STR-38 | Skill de stack com conteudo de teste fornece mecanica de ferramenta, nunca protocolo de entrega: `protocolo-tdd` prevalece sobre qualquer default de SQLite, banco em memoria ou mock de repositorio na camada de integracao. | `protocolo-tdd` Scope Boundary + `django-tdd`, `testing-strategy`, `fastapi-expert`, `nestjs-best-practices` |
| DEC-STR-39 | Toda demanda tem porte P, M ou G, classificado na entrada com gatilhos objetivos; o porte define o modo de cada artefato (`Protocolo por porte`) e nunca dispensa gate. Descer exige justificativa; subir, nao. | AGENTS.md 40 |
| DEC-STR-40 | Um unico registro de entrega por demanda; todo fato e escrito uma vez e os demais artefatos referenciam por link. Pareceres de gate em modo compacto (por excecao) em P e M. Secao vazia e omitida com `Nao aplicavel`. | AGENTS.md 41, 33, 34, 35 |
| DEC-STR-41 | Diagrama Mermaid apenas quando houver fluxo que o texto nao descreva; templates indicam onde e obrigatorio. Commit referencia registro e log de prompt em vez de repetir intencao. | AGENTS.md 8; `review-documentation` |
| DEC-STR-42 | Gate de testes exige cenarios negativos de seguranca e acesso indevido (autenticacao, autorizacao, tenant/IDOR, entrada maliciosa, vazamento, arquivo, rate limit) sempre que a alteracao tocar esses gatilhos, contra backend e banco reais; ausencia e bloqueante sem justificativa possivel. Secao nunca compactada por porte. | AGENTS.md 14; `protocolo-tdd` Regra 6 |
| DEC-STR-43 | E2E com interface de entrada cobre obrigatoriamente campos obrigatorios vazios, valores indevidos por tipo e por regra, e feedback visual do erro associado ao campo por seletor estavel; formulario tocado sem esses cenarios e bloqueante. Secao nunca compactada por porte. | AGENTS.md 13; `protocolo-tdd` Regra 7 |
| DEC-STR-44 | `protocolo-tdd` genericizado: integracao contra instancia real do banco da stack (nunca em memoria, SQLite substituto ou mock); Cypress obrigatorio quando o projeto suportar, senao tecnologia similar de E2E real justificada; execucao isolada em container quando a tecnologia suportar; 70/20/10 como alvo com desvio justificado na tabela do parecer; referencia ao Design System sai do DoD de testes (dona: regra 18). | `protocolo-tdd` Regras 2 e 5 |
| DEC-STR-45 | Suite organizada por modulo com mapa de modulos versionado e mantido pelo QA; durante a implementacao executam-se so os modulos atingidos e dependentes diretos; suite completa obrigatoria apos o commit e antes do push; falha na completa bloqueia o push e devolve o conjunto ao Tech Lead, que atribui a correcao. | AGENTS.md ciclo 9; `protocolo-tdd` Regra 8 |

## Ownerships criticos

| Tema | Ownership principal | Apoio obrigatorio |
|---|---|---|
| Consolidacao final | Tech Lead | Todos os agents alimentam evidencias, divergencias e handoffs |
| System Design | Business Analyst | DBA para capacidade e dados; UX para referencia ao Design System em frontend |
| Design System | UX Expert | Senior Developer para implementacao tecnica de Storybook quando houver frontend |
| Implementacao | Senior Developer | QA para validacao independente |
| E2E com Cypress | QA Expert na validacao | Senior Developer nos prerequisitos tecnicos |
| Plano de banco e expansao | DBA | Business Analyst para consolidacao no System Design |

Artefatos padrao e templates: ver secao `Templates operacionais` em [AGENTS.md](../AGENTS.md).
Fluxo de colaboracao entre agents: ver secao `Fluxo de colaboracao` em [AGENTS.md](../AGENTS.md).

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
