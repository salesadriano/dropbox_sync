# Skill Hierarchy

Guia pratico para escolher a skill certa, evitar sobreposicao e reduzir invocacao ambigua dentro do pacote.

## Objetivo

Este documento responde a uma pergunta simples: qual skill usar para cada tipo de demanda?

Use este mapa antes de escolher uma skill, especialmente quando houver varias alternativas parecidas no mesmo ecossistema.

As skills e personas do pacote vem do plugin `ai-team` do Claude Code; o repositorio guarda o protocolo, a memoria, os templates e as skills proprias do projeto.

Para adicionar ou atualizar uma skill vinda de fonte externa, veja [SKILLS_SYNC.md](./SKILLS_SYNC.md).

## Origem das skills

- **Do plugin `ai-team`** (instalado no usuario do Claude Code, nao no repositorio; referenciadas como `ai-team:<nome>`): `api-security-best-practices`, `documentation-sync`, `entrega-por-porte`, `git-commit`, `gitflow`, `governanca-por-hooks`, `instrucoes-do-projeto`, `memoria-por-janela`, `mermaid-generator`, `prompt-logger`, `protocolo-conformidade`, `protocolo-tdd`, `review-documentation`, `security-best-practices`, `selecao-de-modelo`, `tdd-test-design`.
- **Do projeto** (`.github/skills/<nome>/`, versionadas neste repositorio): `bats-testing-patterns`, `clean-architecture`, `e2e-reexecucao-parcial`, `prd-generator`, `shellcheck-configuration`, `superficie-de-contrato`, `testing-strategy`, `use-case-specification`, `user-story-writing`.

Nas listas abaixo, cada entrada indica a origem entre parenteses.

## Regra geral

Escolha skills nesta ordem:

1. Primeiro, identifique o dominio principal da tarefa.
2. Depois, veja se existe uma skill de framework ou stack mais especifica.
3. So use uma skill generica se nao houver uma skill especializada mais aderente.
4. Se a tarefa for transversal, combine no maximo a skill principal com uma skill de apoio documental ou de arquitetura.

## Skills por categoria

### Arquitetura e documentacao

Use estas skills quando a tarefa principal nao for uma implementacao de framework, mas sim estrutura, documentacao, revisao ou diagramacao.

- [.github/skills/clean-architecture/](./clean-architecture/) (projeto): use para desenho tecnico, separacao de camadas, boundaries e revisao arquitetural; e a referencia agnostica a linguagem e continua sendo o padrao do pacote
- `ai-team:documentation-sync` (plugin): use depois de mudancas tecnicas para revisar impacto documental
- `ai-team:review-documentation` (plugin): use para registrar review tecnico, consolidacao de mudancas e evidencias
- `ai-team:mermaid-generator` (plugin): use quando a entrega pede diagramas Mermaid
- `ai-team:gitflow` (plugin): use para governanca de branches, nomenclatura Gitflow, branch principal declarada, verificacao de PRs abertos antes da demanda, worktree por demanda, remocao local de branches apagadas no remoto, avaliacao da branch principal antes de cada push e coordenacao entre instancias do Tech Lead
- `ai-team:git-commit` (plugin): use para gerar ou revisar commits com convencao semantica (Conventional Commits)
- `ai-team:prompt-logger` (plugin): skill transversal obrigatoria — registra cada prompt recebido em `docs/prompts/`, um arquivo por demanda, com texto integral sanitizado, porte, intencao e inferencias; plano e resultado ficam no registro de entrega

### Governanca operacional (custo por demanda)

Skills trazidas de um projeto governado pelo pacote em 15/10/2026, que reduzem o contexto carregado por sessao e o custo fixo de cada demanda. `memoria-por-janela`, `entrega-por-porte` e a limpeza de worktrees sao norma do pacote desde 15/10/2026 (regras 1, 7, 40 e 46 e secao *Protocolo por porte* do `AGENTS.md`); as demais sao adotadas por decisao registrada do projeto.

- `ai-team:instrucoes-do-projeto` (plugin): use para compactar o arquivo de instrucoes da ferramenta de IA (erratas verbatim para `docs/historico/`, bloco de estado vigente) e prender com `verificar-instrucoes-do-projeto.sh` as frases e caminhos que ele afirma sobre o repositorio
- `ai-team:memoria-por-janela` (plugin): use para dimensionar o bootstrap da memoria (`memoria-index.sh --desde`, janela de 90 dias por padrao) e para declarar `agentes:` sem `todos` fora de decisao de pacote
- `ai-team:governanca-por-hooks` (plugin): use quando o cliente de IA oferecer hooks ou permissoes versionaveis: resumo de estado no inicio da sessao, guarda de comandos antes de cada shell (detector antes do push; suite completa registrada por `suite-completa.sh` antes do push para a PR de integracao e do `gh pr create`), permissoes para comandos ja autorizados por demanda; secao por cliente em `references/clientes-de-ia.md`
- `ai-team:entrega-por-porte` (plugin): use ao classificar o porte e escolher o formato do registro: criterios objetivos de P, Tech Lead implementa, parecer combinado, QA por amostragem, e o registro curto de um arquivo (`../agents/templates/registro-de-entrega-curto-template.md`) em P e M
- [.github/skills/superficie-de-contrato/](./superficie-de-contrato/) (projeto): use para decidir se a entrega exige remedir a superficie do contrato (so quando o diff toca o que a define) e para conferir, com `conferir-copias.sh`, que as copias do numero concordam
- [.github/skills/e2e-reexecucao-parcial/](./e2e-reexecucao-parcial/) (projeto): use para o diagnostico do E2E vermelho na pipeline (`specs-nao-executadas.sh`) e para a reexecucao so das specs que falharam ou nao rodaram, por workflow de disparo manual
- `ai-team:selecao-de-modelo` (plugin): use ao delegar e ao fixar `model:` numa persona: faixa do modelo pela classe da tarefa (`faixa-do-modelo.sh`: economico renderiza, padrao implementa e valida, maximo decide o que e caro errar; so sobe), pacote de transposicao e `avaliar-troca-de-modelo.sh`, que diz se sair da faixa da sessao economiza descontados o pacote e o cache perdido
- `ai-team:gitflow`, referencia `limpeza-de-worktrees.md` (plugin): referencia da `gitflow` para o fechamento: `scripts/limpar-worktrees.sh` remove os worktrees mesclados e lista os pendentes

#### Decision tree rapido: `instrucoes-do-projeto` vs `documentation-sync` vs `superficie-de-contrato`

1. Mudei o repositorio e preciso saber quais documentos ficaram para tras? `documentation-sync`.
2. O arquivo de instrucoes da ferramenta de IA cresceu ou afirma algo que o repositorio nao confirma? `instrucoes-do-projeto`.
3. Um numero de contrato (rotas, endpoints) vive em mais de um arquivo e preciso saber se devo remedi-lo e se as copias concordam? `superficie-de-contrato`.

#### Decision tree rapido: `documentation-sync` vs `review-documentation`

Use `documentation-sync` quando a pergunta principal for: quais documentos existentes precisam ser atualizados depois da mudanca tecnica?

Use `review-documentation` quando a pergunta principal for: qual registro tecnico formal preciso criar ou completar para deixar a entrega auditavel?

Regra pratica:

1. Se voce precisa revisar README, docs, arquitetura, QA, requisitos ou guias operacionais ja existentes, comece com `documentation-sync`.
2. Se voce precisa criar um review, changelog tecnico, journal de entrega ou registro retroativo da mudanca, use `review-documentation`.
3. Se a entrega exigir os dois movimentos, execute primeiro `documentation-sync` para alinhar a base documental e depois `review-documentation` para registrar a entrega.
4. Nao use `review-documentation` como substituto de manutencao de documentacao viva, e nao use `documentation-sync` como substituto do registro tecnico formal da entrega.

### Produto e requisitos

- [.github/skills/use-case-specification/](./use-case-specification/) (projeto): use como primeiro passo do escopo, para fixar problema de negocio, usuarios primarios e criterios mensuraveis de sucesso antes do PRD
- [.github/skills/prd-generator/](./prd-generator/) (projeto): use para gerar PRD
- [.github/skills/user-story-writing/](./user-story-writing/) (projeto): use para historias de usuario e criterios de aceite

Regra de prioridade para produto:

1. `use-case-specification` para enquadrar o problema e os criterios de sucesso.
2. `prd-generator` para formalizar o requisito.
3. `user-story-writing` para decompor em historias com criterios de aceite.

### Skills fora do escopo padrao do pacote

`strategy-compare` (backtesting financeiro): nao incluida neste repositorio; fonte: `ai_team`.

### Testes e qualidade

- `ai-team:protocolo-tdd` (plugin): gate local obrigatorio de testes; use sempre que a tarefa envolver desenvolvimento, refatoracao ou correcao de codigo. Define o protocolo padrao de TDD, piramide 70/20/10, integracao com banco real via Testcontainers e E2E real com Cypress sem mocks de rede, e fecha com achados por severidade e veredito em `../agents/templates/evidencia-testes-template.md`. Achado bloqueante reprova e devolve ao agent originador. Nao depende de pipeline.
- `ai-team:tdd-test-design` (plugin): use dentro do ciclo red-green para decidir o que cada teste afirma e em qual seam; cobre seams, mocking apenas em fronteiras de sistema e anti-patterns (teste acoplado a implementacao, teste tautologico, fatiamento horizontal)
- `ai-team:protocolo-conformidade` (plugin): gate local obrigatorio de conformidade arquitetural e de boas praticas; use APOS implementar e ANTES de qualquer handoff, sobre o diff local, para verificar se o codigo entregue respeita `clean-architecture` e a skill da stack. Achado bloqueante reprova e devolve ao agent originador. Nao depende de pipeline.
- [.github/skills/testing-strategy/](./testing-strategy/) (projeto): use para desenhar estrategia/plano de testes quando a demanda for conceitual e nao um protocolo operacional normativo
- [.github/skills/e2e-reexecucao-parcial/](./e2e-reexecucao-parcial/) (projeto): use depois de um E2E vermelho na pipeline, para listar o que nao rodou e reexecutar so isso; a Regra 9 (parar no primeiro erro) continua sendo de `protocolo-tdd`

Regra de prioridade para testes:

1. `protocolo-tdd` obrigatoriamente quando houver desenvolvimento, refatoracao ou correcao de codigo. E a autoridade operacional: piramide 70/20/10, Testcontainers, Cypress sem stub de rede, DoD bloqueante e veredito registrado. Prevalece tambem sobre skills de stack com conteudo de teste (`bats-testing-patterns`), que fornecem a mecanica da ferramenta, nunca o protocolo de entrega.
2. `tdd-test-design` como apoio dentro do ciclo exigido por `protocolo-tdd`, quando a duvida for a qualidade do teste em si. Em caso de conflito, `protocolo-tdd` prevalece.
3. `testing-strategy` quando a demanda for apenas desenho de plano, cobertura e abordagem, sem implementacao nem alteracao de codigo.

#### Decision tree rapido: `protocolo-tdd` vs `tdd-test-design` vs `testing-strategy`

1. Vou alterar codigo? Entao `protocolo-tdd` e obrigatoria, sempre.
2. Ja estou escrevendo o teste e a duvida e "o que asserto e onde testo"? Adicione `tdd-test-design`.
3. Nao vou alterar codigo e preciso apenas de um plano de testes? Use `testing-strategy` sozinha.

#### Os dois gates locais obrigatorios de uma entrega com codigo

Toda alteracao de codigo passa por dois gates locais, executados pelo proprio agent, sem pipeline:

| Gate | Skill | Pergunta que responde | Momento |
|---|---|---|---|
| Testes | `ai-team:protocolo-tdd` | o comportamento esta provado por testes reais? | durante a implementacao (red-green-refactor), fechando em `evidencia-testes-template.md` |
| Conformidade | `ai-team:protocolo-conformidade` | o codigo entregue respeita a arquitetura e as boas praticas da stack? | apos implementar, antes de qualquer handoff |

Os dois sao obrigatorios e nao se substituem. `protocolo-tdd` valida que o comportamento funciona; `protocolo-conformidade` valida como ele foi construido. Ambos rodam localmente, classificam achados por severidade e emitem veredito em template proprio, no modo definido pelo porte da demanda (`AGENTS.md`, regra 40): compacto em P e M, completo em G. Reprovacao em qualquer um bloqueia o handoff e devolve a entrega ao agent originador.

#### Decision tree rapido: `protocolo-conformidade` vs `clean-architecture` vs skill de stack

1. Preciso decidir como desenhar antes de escrever o codigo? Use `clean-architecture` ou a skill da stack diretamente.
2. Ja escrevi o codigo e preciso verificar se ele aderiu? Use `protocolo-conformidade`, que aplica as duas anteriores sobre o diff e emite um veredito.
3. Preciso registrar formalmente a entrega depois do gate? Use `review-documentation`, referenciando o parecer de conformidade.

### Seguranca

As skills abaixo definem o que deve estar protegido. A prova por teste (cenarios negativos de autenticacao, autorizacao, tenant, entrada maliciosa e vazamento, contra backend e banco reais) e exigida pela Regra 6 de `ai-team:protocolo-tdd`, que e o gate; as skills de seguranca sao a fonte das regras que esses testes provam.

#### Quando a tarefa for seguranca transversal web

Use:

- `ai-team:security-best-practices` (plugin)

Escopo ideal:

- HTTPS
- CORS
- cookies
- headers
- CSP
- secret handling
- hardening web em geral

#### Quando a tarefa for seguranca especifica de API

Use:

- `ai-team:api-security-best-practices` (plugin)

Escopo ideal:

- auth
- authz
- token handling
- schema validation
- rate limiting
- API hardening

#### Better Auth

Skills de Better Auth: nao incluidas neste repositorio; fonte: `ai_team`.

## Skills por stack

Skills de Python, FastAPI, Django, React, acessibilidade, Node.js, .NET, React Native, Postgres/Supabase, PHP/Laravel e Cloudflare Workers: nao incluidas neste repositorio; fonte: `ai_team`.

### Shell scripts (POSIX sh e Bash)

- [.github/skills/shellcheck-configuration/](./shellcheck-configuration/) (projeto): use ao escrever, alterar ou revisar script shell (`*.sh` ou shebang `sh`/`bash`), para analise estatica com ShellCheck no dialeto do shebang, `.shellcheckrc`, diretivas e leitura dos codigos SC
- [.github/skills/bats-testing-patterns/](./bats-testing-patterns/) (projeto): use para escrever ou revisar testes de script shell com Bats, dentro do ciclo de `protocolo-tdd`

Regra de prioridade para shell:

1. `protocolo-tdd` continua obrigatoria em qualquer alteracao de script; `bats-testing-patterns` fornece apenas a mecanica da ferramenta.
2. `shellcheck-configuration` e a skill de stack que `protocolo-conformidade` aplica sobre o diff de script shell.
3. O dialeto e o do shebang: os scripts do pacote sao POSIX `sh` (`set -eu`). Construcao exclusiva de Bash (`[[ ]]`, arrays, `local`, `pipefail`, `source`) em script `sh` e achado, nunca motivo para trocar o shebang.
4. `security-best-practices` quando o script manipular segredo, repassar entrada externa a comando ou `eval`, ou baixar e executar conteudo.

## Combinacoes recomendadas

Combinacoes seguras e uteis:

- `clean-architecture` + `review-documentation`
- `documentation-sync` + `mermaid-generator`
- `prd-generator` + `user-story-writing`
- `protocolo-tdd` + `tdd-test-design`
- `protocolo-conformidade` + `clean-architecture`
- `protocolo-conformidade` + a skill da stack detectada
- `protocolo-conformidade` + `review-documentation`
- `shellcheck-configuration` + `bats-testing-patterns`
- `protocolo-tdd` + `bats-testing-patterns`

## Combinacoes a evitar

Evite carregar juntas sem necessidade:

- `security-best-practices` + `api-security-best-practices` se a demanda for claramente apenas web ou apenas API
- `tdd-test-design` + `testing-strategy` na mesma tarefa: uma e para escrever o teste, a outra e para planejar sem implementar

## Regras de desempate

Se duas skills parecerem servir:

1. escolha a mais especifica para a stack;
2. se ambas forem da mesma stack, escolha a que mais se aproxima do objetivo principal:
   - implementar
   - estruturar
   - proteger
   - testar
   - documentar
3. adicione uma segunda skill apenas se ela cobrir uma dimensao diferente e complementar.

## Atalho por intencao

### Quero criar arquitetura ou organizar camadas

- [.github/skills/clean-architecture/](./clean-architecture/) (projeto)

### Quero revisar impacto documental apos uma entrega

- `ai-team:documentation-sync` (plugin)

### Quero escrever ou consolidar um review tecnico

- `ai-team:review-documentation` (plugin)

### Quero atualizar docs existentes e tambem registrar a entrega

1. `ai-team:documentation-sync` (plugin)
2. `ai-team:review-documentation` (plugin)

### Quero gerar diagrama Mermaid

- `ai-team:mermaid-generator` (plugin)

### Quero escrever PRD ou historias

- [.github/skills/prd-generator/](./prd-generator/) (projeto)
- [.github/skills/user-story-writing/](./user-story-writing/) (projeto)

### Quero proteger uma API

- `ai-team:api-security-best-practices` (plugin)

### Quero endurecer uma aplicacao web

- `ai-team:security-best-practices` (plugin)

### Quero verificar se a implementacao que acabei de fazer respeita a arquitetura

- `ai-team:protocolo-conformidade` (plugin)

### Quero saber se posso encaminhar a entrega para QA

- `ai-team:protocolo-tdd` (plugin): o handoff so e liberado com parecer de evidencias de testes Aprovado ou Aprovado com ressalvas
- `ai-team:protocolo-conformidade` (plugin): o handoff so e liberado com parecer Aprovado ou Aprovado com ressalvas

### Quero escrever um teste melhor dentro do ciclo TDD

1. `ai-team:protocolo-tdd` (plugin)
2. `ai-team:tdd-test-design` (plugin)

### Quero escrever, revisar ou testar um script shell

1. [.github/skills/shellcheck-configuration/](./shellcheck-configuration/) (projeto)
2. [.github/skills/bats-testing-patterns/](./bats-testing-patterns/) (projeto)

## Resultado esperado

Ao usar este arquivo, voce deve conseguir:

- reduzir sobreposicao entre skills;
- acionar a skill certa mais cedo;
- evitar combinacoes redundantes;
- tornar a descoberta do catalogo mais previsivel.
