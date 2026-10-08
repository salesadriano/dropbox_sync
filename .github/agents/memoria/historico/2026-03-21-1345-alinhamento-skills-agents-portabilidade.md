# Alinhamento entre skills, agents e portabilidade do pacote

## Contexto

Foi solicitada uma revisao da pasta `skills/` para alinhar seu escopo aos papeis definidos nos agents, reduzir redundancias nos próprios agents e remover acoplamentos desnecessarios a ferramentas ou projetos especificos.

## Decisao consolidada

- Skills transversais passaram a explicitar melhor seu papel de apoio aos agents sem substituir templates e gates obrigatorios.
- O pacote `design-md` foi genericizado para sintetizar `DESIGN.md` a partir de artefatos de interface de qualquer projeto, removendo dependencia conceitual de Stitch.
- Skills de requisitos e historias foram alinhadas ao papel do Business Analyst e ao uso conjunto com System Design.
- A skill `workers-best-practices` passou a deixar explicito que e ecossistema-especifica de Cloudflare e nao substitui orientacao serverless generica.
- Metadados da skill `fastapi-expert` foram corrigidos para referenciar skills locais e atuais do pacote.
- Agents de Business Analyst e Senior Developer tiveram redundancias reduzidas ao concentrar detalhe operacional em skills e templates, preservando obrigacoes, ownerships e gates.

## Motivacoes

- Melhorar descoberta e acionamento correto das skills.
- Evitar que agents repitam detalhamento que deveria morar em skills reutilizaveis.
- Remover acoplamento a fornecedores, ferramentas ou contextos que limitavam a portabilidade do pacote.
- Preservar o protocolo comum e os gates formais sem inflar as personas com instrucoes excessivamente procedurais.

## Artefatos impactados

- `skills/design-md/SKILL.md`
- `skills/design-md/README.md`
- `skills/design-md/examples/DESIGN.md`
- `skills/prd-generator/SKILL.md`
- `skills/user-story-writing/SKILL.md`
- `skills/documentation-sync/SKILL.md`
- `skills/review-documentation/SKILL.md`
- `skills/interface-design/SKILL.md`
- `skills/workers-best-practices/SKILL.md`
- `skills/fastapi-expert/SKILL.md`
- `business-analyst.agent.md`
- `senior-developer.agent.md`
- `memoria/MEMORIA-COMPARTILHADA.md`

## Impactos permanentes

- A baseline passa a privilegiar skills como ponto principal de detalhe operacional reutilizavel.
- Agents permanecem mais focados em papel, decisoes, handoffs, entregaveis e gates.
- O pacote reforca portabilidade para uso em qualquer projeto, sem depender de uma ferramenta de design especifica para sintese documental.

## Riscos observados

- Reducao excessiva em agents poderia ocultar obrigacoes importantes se feita sem criterio.
- Skills genericizadas demais poderiam perder valor de descoberta se suas fronteiras ficassem vagas.

## Mitigacoes

- Manter nos agents apenas obrigacoes, ownerships, gates e referencias explicitas para skills e templates.
- Ajustar descricoes das skills para deixar claro quando usar e quando nao usar.
- Validar frontmatter e referencias apos cada rodada de alinhamento.