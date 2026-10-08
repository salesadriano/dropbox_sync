# Execucao seletiva por modulo no local e suite completa na pipeline de main/master

Detalhamento da Regra 8 de [`SKILL.md`](../SKILL.md). Abrir ao selecionar os modulos a executar, ao configurar ou conferir o job de suite completa da pipeline, ao tratar falha dessa suite ou ao criar e manter o mapa de modulos.

## Organizacao da suite

A suite do projeto e organizada por modulo ou estrutura dependente (dominio, pacote, workspace, servico, tela ou agrupamento equivalente da stack), de modo que seja possivel executar apenas os testes das estruturas atingidas por uma alteracao.

- **Rotina por modulo.** O QA Expert implementa e mantem a rotina: cada modulo tem um identificador estavel (tag, `project`, workspace, diretorio ou grupo, conforme a ferramenta da stack), os caminhos que cobre, um comando de execucao proprio e a lista dos modulos que dependem dele. A separacao em modulos e determinada automaticamente ou definida pelo solicitante, nunca inferida pelo agent (secao `Determinacao dos modulos`). Essa relacao vive em um **mapa de modulos** versionado no projeto (por exemplo `docs/testes/mapa-modulos.md` ou o arquivo de configuracao da ferramenta), mantido pelo QA e atualizado sempre que um modulo e criado, renomeado ou ganha dependencia nova. Estrutura nova com enquadramento definido pelo solicitante, mas ainda sem entrada no mapa, e achado Maior.
- **Local, durante a implementacao.** O Senior Developer executa, a cada ciclo red-green e no Passo 5, apenas os modulos **atingidos diretamente** pela alteracao (os arquivos do diff) e os **dependentes diretos** deles, conforme o mapa. O parecer registra quais modulos foram selecionados e por que. Selecionar menos do que o mapa indica e achado Maior.
- **Sem suite completa local.** A suite completa nao e precondicao de commit, de push da branch de trabalho nem de handoff ao QA. O gate local fecha com a execucao seletiva aprovada.
- **Somente os itens afetados, por qualquer agent.** Toda execucao de testes durante a demanda (ciclo red-green, Passo 5, validacao independente do QA, reexecucao apos correcao ou apos integrar a branch principal) cobre apenas os modulos da selecao. Fora da pipeline, a suite completa so roda com pedido explicito do solicitante para a demanda, registrado no log de prompt e no parecer; inferencia do agent, porte da demanda ou "por garantia" nao contam como pedido. Selecao maior que a indicada pelo mapa, ou suite completa local sem esse pedido, e achado Maior.
- **Pipeline, em `main` ou `master`.** A **suite completa** (todos os modulos, todas as camadas, contra banco real) roda exclusivamente na pipeline, nos eventos que envolvem a branch de integracao do projeto. Merge com essa execucao vermelha, ausente ou ignorada e achado Bloqueante.
- **Falha na suite completa.** O conjunto e devolvido ao **Tech Lead**, nao ao QA nem diretamente ao Senior Developer: o merge fica bloqueado; a execucao para no primeiro erro ([interrupcao-no-primeiro-erro.md](interrupcao-no-primeiro-erro.md)) e o registro classifica o modulo que a interrompeu como estando no escopo selecionado (falha de implementacao) ou fora dele (regressao nao prevista pelo mapa), com uma linha nova a cada reexecucao interrompida; o Tech Lead atribui a correcao ao agent dono do modulo e, se a regressao veio de dependencia ausente no mapa, o QA atualiza o mapa no mesmo ciclo. Apos a correcao, a pipeline e reexecutada e precisa ficar verde antes do merge.
- Modulo selecionado que falha durante a implementacao segue o ciclo normal do gate (Passo 6 e regra 17); a devolucao ao Tech Lead e exclusiva da suite completa da pipeline.

## Determinacao dos modulos

O mapa so registra separacoes que nao dependem de julgamento do agent. Ha duas origens validas para cada modulo, cada dependencia e cada enquadramento de arquivo:

- **Automatica:** a fronteira esta declarada pela propria stack ou ferramenta e e lida, nao interpretada. Exemplos: workspaces (`package.json`, `pnpm-workspace.yaml`, `Cargo.toml`, `go.work`), `projects` do runner de testes, projetos de uma solucao `.sln`, modulos Maven ou Gradle, apps declaradas no framework (`INSTALLED_APPS` no Django, `@Module` no NestJS), pacotes ou modulos declarados em manifesto, ou mapa ja existente no projeto. Dependencias sao automaticas quando declaradas em manifesto ou configuracao (dependencias entre workspaces, referencias de projeto, imports entre modulos declarados).
- **Solicitante:** tudo o que nao for automatico. Agrupar diretorios por semelhanca de nome, por leitura do codigo ou por analogia com outro projeto **nao** e determinacao automatica.

### Separacao inicial

Ao criar o mapa (QA Expert, na primeira demanda com codigo do projeto), se a separacao nao puder ser determinada automaticamente, no todo ou em parte:

1. Levantar o que e automatico e o que nao e. Para a parte nao automatica, o agent pode montar uma **proposta** (modulos, caminhos cobertos, dependencias), apresentada como sugestao.
2. Pedir ao solicitante, pelo Tech Lead (regra 44 do `AGENTS.md`), a definicao explicita da separacao: quais modulos existem, que caminhos cada um cobre e de quais modulos cada um depende. A proposta so e adotada com confirmacao explicita; silencio ou resposta vaga nao confirmam.
3. Registrar a resposta no log de prompt da demanda e gravar o mapa com a origem de cada linha. A primeira definicao da separacao tambem e gravada como entrada de memoria `tipo: decisao`, `escopo: projeto`, slug `mapa-modulos`, apontando para o mapa.
4. Enquanto a separacao nao for definida, vale a selecao sem mapa (secao `Mapa de modulos`), nunca a suite completa.

### Enquadramento de implementacao nova

No Passo 1 de cada demanda, cada arquivo do diff e enquadrado pelo mapa:

- **Enquadrado automaticamente:** o caminho do arquivo casa com os caminhos de exatamente um modulo do mapa. Nada a perguntar.
- **Nao enquadrado:** o caminho nao casa com nenhum modulo, casa com mais de um, ou a alteracao cria estrutura nova (diretorio, pacote, servico, tela) cujo lugar no mapa nao esta declarado. O enquadramento e **definido explicitamente pelo solicitante**, pelo Tech Lead, antes do ciclo red-green: incluir em um modulo existente, criar um modulo novo (com caminhos e dependencias) ou declarar que a estrutura nova depende de quais modulos. O agent pode sugerir; nao decide.
- Excecao: arquivo novo dentro dos caminhos ja cobertos por um unico modulo e enquadrado automaticamente, mesmo sendo novo.

A resposta vai para o log de prompt e o QA atualiza o mapa no mesmo ciclo, com a origem `solicitante` e a referencia ao log.

Severidade (Regra 8): arquivo do diff sem modulo, ou enquadrado, separado ou ligado a dependencia pelo agent sem definicao do solicitante, e achado **Bloqueante**, porque a selecao de modulos deixa de ser verificavel. Definicao recebida mas nao levada ao mapa e achado **Maior**.

## Mapa de modulos

Formato minimo, agnostico a ferramenta (adaptar ao arquivo de configuracao da stack quando ela suportar tags, `projects` ou workspaces):

```markdown
| Modulo | Caminhos cobertos | Identificador na ferramenta | Comando | Depende de | Dependentes diretos | Origem | Dono |
|---|---|---|---|---|---|---|---|
| pedidos | `src/pedidos/**`, `tests/pedidos/**` | tag `@pedidos` / `projects: pedidos` | `<comando> --module pedidos` | catalogo, clientes | faturamento, expedicao | automatica: `pnpm-workspace.yaml` | Senior Developer |
| relatorios | `src/relatorios/**` | tag `@relatorios` | `<comando> --module relatorios` | pedidos | — | solicitante: `docs/prompts/<log>.md` | Senior Developer |
```

- **Caminhos cobertos** sao padroes de caminho que nao se sobrepoem entre modulos: e o que torna o enquadramento de cada arquivo do diff mecanico.
- **Origem** registra, por linha, se o modulo e as dependencias vieram de fonte automatica (qual) ou do solicitante (link para o log de prompt da definicao). Dependencia com origem diferente da do modulo e anotada na propria celula.

Regras de manutencao:

- Entrada nova ao criar modulo; atualizacao ao renomear ou ao ganhar dependencia. Modulo, caminhos ou dependencia que nao sejam automaticos so entram com definicao do solicitante.
- Regressao fora do escopo na suite completa e sinal de dependencia ausente: o QA corrige o mapa no mesmo ciclo em que o Tech Lead atribui a correcao do codigo.
- Ate o mapa existir em um projeto, inclusive enquanto a separacao inicial aguarda definicao do solicitante, a **selecao sem mapa** cobre apenas os testes ligados aos arquivos do diff: os arquivos de teste do proprio diff e os testes que o runner associa por conta propria aos arquivos alterados (por exemplo `jest --findRelatedTests`, `vitest related`). Quando o runner nao oferecer essa associacao, os testes a executar sao definidos pelo solicitante, pelo Tech Lead, como no enquadramento; o agent pode propor, nao decide. A suite completa local so roda com pedido explicito do solicitante. O parecer declara a selecao sem mapa e a origem de cada item.

## Selecao durante a implementacao

1. Levantar os arquivos do diff (Passo 1) e enquadrar cada um pelos caminhos cobertos do mapa.
2. Arquivo nao enquadrado automaticamente: obter a definicao explicita do solicitante antes do ciclo red-green (secao `Enquadramento de implementacao nova`) e atualizar o mapa.
3. Incluir os dependentes diretos de cada modulo atingido, conforme o mapa, e nada alem disso: modulo fora da selecao so entra por nova definicao do mapa, e a suite completa so com pedido explicito do solicitante.
4. Executar os modulos selecionados em sequencia, cada um com parada no primeiro erro; o primeiro modulo falho encerra a execucao e os seguintes ficam como nao executados (Regra 9).
5. Registrar no parecer a lista, o motivo de cada inclusao (direto ou dependente de qual), o comando por modulo e, para cada arquivo que dependeu de definicao do solicitante, a referencia ao log de prompt.
6. Falha em modulo selecionado segue o ciclo normal do gate (Passo 6 e regra 17 do `AGENTS.md`); corrigida, a selecao inteira e reexecutada do inicio.

## Suite completa na pipeline

A suite completa e responsabilidade da pipeline do projeto, nao do ambiente do agent. O QA Expert define o comando que a executa por inteiro; o Senior Developer implementa e mantem o job que o roda; o Tech Lead so libera o merge com o job verde.

### Eventos que a disparam

A branch de integracao e `main` ou `master`, conforme o projeto. O job roda em dois momentos: no PR que aponta para ela, para que a regressao apareca antes do merge, e no push ou merge que efetivamente entra nela, para cobrir push direto e merge sem PR.

```yaml
# GitHub Actions - ajustar nome da branch de integracao e o comando do projeto
on:
  pull_request:
    branches: [ main ]
  push:
    branches: [ main ]

jobs:
  suite-completa:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Suite completa (todos os modulos, todas as camadas, banco real)
        run: <comando oficial de execucao isolada do projeto, com parada no primeiro erro>
```

### Ordem dos passos no job

Quando a suite completa roda na pipeline, a sequencia e fixa e e a mesma em todo projeto:

| Ordem | Passo | O que inclui |
|---|---|---|
| 1 | Checkout do estado integrado | No PR, o merge do PR com a branch de integracao (ref padrao do `actions/checkout` no evento `pull_request`, nunca o `head` isolado); no push ou merge, o commit que entrou na branch |
| 2 | Dependencias e runner com versoes fixadas | Instalacao pelo lockfile, versao explicita do runner e das ferramentas de teste; nada resolvido por versao flutuante |
| 3 | Ambiente e pre-requisitos | Arquivos, scripts e diretorios obrigatorios, ferramentas no `PATH`, Docker disponivel para Testcontainers, variaveis de configuracao nao secretas |
| 4 | Gates rapidos estaticos | Lint, formatacao, verificacao de tipos, validacoes estruturais e de links; tudo o que falha em segundos sem executar teste |
| 5 | **Suite completa** | Logo em seguida ao passo 4: unitario, integracao e E2E, nessa ordem, com parada no primeiro erro e passo de reporte ([interrupcao-no-primeiro-erro.md](interrupcao-no-primeiro-erro.md#pipeline)) |
| 6 | Demais steps do projeto | Build de artefato ou imagem, empacotamento, publicacao, deploy e validacoes que nao sao pre-requisito dos testes; so depois da suite verde |

- Os testes unitarios sao a primeira camada da suite (passo 5), nao um gate rapido do passo 4: nao rodam duas vezes.
- Build que os proprios testes exigem (compilacao antes do unitario, aplicacao construida para o E2E) faz parte da preparacao da camada que o usa, dentro do passo 5, e nao e um "demais step".
- Demais steps ficam no mesmo job, depois do passo de reporte, ou em job proprio encadeado por `needs:` ao job da suite. Nunca antes dela, nunca em job paralelo sem `needs:`, e nunca com `if: always()` ou `if: failure()`.
- Erro em qualquer passo de 1 a 4 interrompe o job como erro de teste (Regra 9): a suite completa fica **nao executada**, o reporte indica o passo de preparo que falhou e o conjunto vai ao Tech Lead como qualquer falha da suite.

```yaml
jobs:
  suite-completa:
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash
    steps:
      - uses: actions/checkout@v4                       # 1. estado integrado
      - name: Dependencias e runner (versoes fixadas)   # 2.
        run: <instalacao pelo lockfile e runner com versao explicita>
      - name: Ambiente e pre-requisitos                 # 3.
        run: <verificacao de arquivos, ferramentas e servicos de teste>
      - name: Gates rapidos                             # 4.
        run: <lint, formatacao, tipos, validacoes estruturais>
      - name: Suite completa                            # 5. camadas em passos: ver interrupcao-no-primeiro-erro.md
        run: <comando oficial de execucao isolada do projeto, com parada no primeiro erro>

  build-e-deploy:                                       # 6. demais steps do projeto
    needs: suite-completa                               # so roda com a suite verde
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build, publicacao e deploy
        run: <passos do projeto>
```

Passo de preparo fora dessa ordem, ou demais step antes da suite, em paralelo a ela ou sem depender dela verde: achado Maior, com owner e prazo. Publicacao ou deploy executado com a suite vermelha, ausente ou ainda em andamento: achado Bloqueante.

O job para no primeiro erro e publica o reporte dele no resumo da execucao, com camadas em passos sequenciais, matriz com `fail-fast: true` e nenhum `continue-on-error` em passo de teste: modelo completo em [interrupcao-no-primeiro-erro.md](interrupcao-no-primeiro-erro.md#pipeline).

Push e PR de branch de trabalho nao disparam a suite completa: ali vale a execucao seletiva local. Projeto sem esse job na pipeline da branch de integracao e achado Maior, com owner e prazo; enquanto ele nao existir, nenhuma execucao global cobre o merge, e isso e declarado no parecer e no registro de entrega.

### Tratamento do resultado

1. O Tech Lead confere o resultado do job no PR ou no commit antes de liberar o merge; execucao ausente, vermelha ou ignorada nao se compensa por execucao local.
2. Em falha: merge bloqueado; o job parou no primeiro erro e o reporte aponta o modulo que o interrompeu; classificar esse modulo como **falha de implementacao** (estava no escopo selecionado) ou **regressao fora do escopo** (nao estava) e devolver o conjunto ao Tech Lead. Modulos que nao rodaram por causa da interrupcao nao sao classificados nem contados como aprovados.
3. O Tech Lead atribui a correcao ao agent dono do modulo e aciona o QA para o mapa quando houver regressao fora do escopo.
4. Apos a correcao, a pipeline e reexecutada do inicio; cada nova interrupcao volta ao passo 2. O merge ocorre somente com o job verde, e o parecer registra o workflow, o evento, o commit e o resultado.
5. Falha intermitente na pipeline recebe o mesmo tratamento de flaky do Passo 4: causa raiz corrigida, nunca rerun cego como prova.
