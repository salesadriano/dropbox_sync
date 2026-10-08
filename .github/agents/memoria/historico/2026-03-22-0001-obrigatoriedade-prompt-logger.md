# Obrigatoriedade transversal da skill prompt-logger

## Contexto

Foi solicitada a implementacao do uso obrigatorio da skill `prompt-logger` para todos os agents do pacote, de forma que cada solicitacao recebida passe a gerar trilha auditavel em `docs/prompts/` com prompt original, interpretacao e plano de acao.

## Decisao consolidada

- O protocolo comum em `.github/agents/AGENTS.md` passou a exigir explicitamente o acionamento da skill `prompt-logger` para toda solicitacao recebida.
- Os seis agents do pacote passaram a declarar a mesma obrigacao em seus arquivos individuais para evitar dependencia exclusiva do protocolo comum.
- A memoria compartilhada passou a registrar essa exigencia como decisao estrutural ativa do pacote.
- O repositorio passou a conter `docs/prompts/` como local padrao para os logs gerados pela skill.

## Motivacoes

- Garantir rastreabilidade por solicitacao em todo o pacote de agents.
- Evitar comportamento inconsistente entre agentes executados de forma isolada.
- Tornar a exigencia auditavel tanto no protocolo comum quanto na memoria estrutural.
- Alinhar o pacote com a propria skill `prompt-logger`, que determina o registro do prompt antes ou durante a execucao.

## Artefatos impactados

- `.github/agents/AGENTS.md`
- `.github/agents/business-analyst.agent.md`
- `.github/agents/tech-lead.agent.md`
- `.github/agents/senior-developer.agent.md`
- `.github/agents/qa-expert.agent.md`
- `.github/agents/ux-expert.agent.md`
- `.github/agents/dba.agent.md`
- `.github/agents/memoria/MEMORIA-COMPARTILHADA.md`
- `docs/prompts/2026-03-22_001_tornar-prompt-logger-obrigatorio.md`

## Impactos permanentes

- Todo agent passa a iniciar sua atuacao com a expectativa de registrar o prompt e sua interpretacao.
- O pacote ganha trilha auditavel por solicitacao em local unificado.
- A governanca do pacote passa a tratar ausencia desse log como desvio de protocolo.

## Riscos observados

- Agents ou fluxos externos que ignorem `docs/prompts/` podem deixar residuos de execucao sem consolidacao posterior.
- Regras duplicadas entre protocolo comum e arquivos individuais exigem manutencao sincronizada em futuras alteracoes.

## Mitigacoes

- Preservar a obrigatoriedade no protocolo comum como fonte canonica e manter nos arquivos individuais apenas a referencia operacional objetiva.
- Revisar `docs/prompts/` e a decisao estrutural correspondente sempre que novos agents forem adicionados ao pacote.
- Incluir essa regra em futuras revisoes de governanca e alinhamento entre skills e agents.