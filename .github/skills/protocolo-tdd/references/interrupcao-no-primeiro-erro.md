# Interrupcao no primeiro erro e reporte para correcao

Detalhamento da Regra 9 de [`SKILL.md`](../SKILL.md). Abrir ao configurar o runner, os scripts ou o job de testes do projeto, ao conferir essa configuracao no gate, ao registrar uma execucao interrompida no parecer ou ao montar o reporte de falha da pipeline.

## Principio

A execucao de testes do projeto e montada para **parar no primeiro erro**. Nada roda depois dele: nem o proximo teste do mesmo arquivo, nem o proximo modulo da selecao, nem a proxima camada. O erro e reportado ao dono da correcao, e a execucao so e considerada valida quando recomeca do inicio e termina sem erro.

A interrupcao vem da configuracao (runner, script, job), nunca da atencao do agent: uma execucao que depende de alguem notar a falha no meio do log nao atende a regra.

## O que conta como erro

- falha de assercao;
- erro em setup, fixture, `beforeAll`/`setup_file`, teardown ou hook;
- timeout de teste, de hook ou do job;
- falha de compilacao, de transpilacao ou de coleta dos testes;
- container, banco de teste (Testcontainers) ou servico da stack que nao sobe, e seeder que falha;
- execucao que termina sem nenhum teste coletado ou executado, quando a selecao previa testes;
- na pipeline, falha em passo de preparo que antecede a suite completa (checkout, dependencias e runner, ambiente e pre-requisitos, gates rapidos): a suite fica nao executada;
- teste marcado como falho esperado (`xfail`, `.failing`) que passa sem que isso tenha sido acordado.

Teste ignorado (`skip`) nao e erro, mas continua sujeito ao Passo 4 do `SKILL.md`: desativar cenario para liberar a entrega e achado bloqueante por si so.

## Niveis de interrupcao

| Nivel | O que para | Como se garante |
|---|---|---|
| Runner | Os testes restantes do mesmo comando | Opcao de parada no primeiro teste falho da ferramenta (tabela abaixo) |
| Modulo | Os modulos seguintes da selecao (Regra 8) | Modulos executados em sequencia, cada comando com codigo de saida verificado; o primeiro diferente de zero encerra a execucao |
| Camada | As camadas seguintes | Ordem fixa da mais barata para a mais cara: **unitario, integracao, E2E**. Integracao so comeca com o unitario verde; E2E so comeca com a integracao verde |
| Paralelismo | As frentes que ainda estao rodando | Primeiro erro cancela as demais: matriz com `fail-fast: true`, shards com cancelamento, runner paralelo com parada global |

Em execucao paralela, testes que ja estavam em andamento podem terminar antes do cancelamento; o que importa e que nenhuma etapa nova comece e que o resultado final seja o erro, nunca um agregado verde.

## Mecanica por ferramenta

Exemplos de referencia. A opcao exata depende da versao da ferramenta: confirmar pela documentacao atual (Context7, regra 30 do `AGENTS.md`) e registrar o comando efetivo no mapa de modulos.

| Ferramenta | Parada no primeiro teste falho |
|---|---|
| pytest | `-x` (equivalente a `--maxfail=1`) |
| Django (`manage.py test`) | `--failfast` |
| Jest | `--bail` (ou `bail: 1` na configuracao) |
| Vitest | `--bail=1` |
| Mocha | `--bail` |
| Node.js (`node --test`) | sem opcao nativa (conferido no Node 23): um arquivo de teste por comando, em sequencia, com `set -e`, parando no primeiro arquivo falho; limitacao registrada no parecer |
| Playwright | `-x` (ou `--max-failures=1`) |
| Cypress | sem opcao nativa no runner aberto: `afterEach` que chama `Cypress.runner.stop()` quando o teste corrente falhou, e `cypress run` encerrando com codigo diferente de zero |
| PHPUnit | `--stop-on-defect` (ou `--stop-on-failure --stop-on-error`) |
| Pest | `--bail` |
| RSpec | `--fail-fast` |
| Go | `go test -failfast` para dentro do pacote; entre pacotes, rodar em sequencia e parar no primeiro pacote falho |
| Cargo | comportamento padrao entre alvos de teste; nunca usar `--no-fail-fast` |
| Gradle | `test --fail-fast` (ou `failFast = true` na task) |
| Maven Surefire/Failsafe | `-Dsurefire.skipAfterFailureCount=1` (e o equivalente do Failsafe) |
| Bats | `--abort` (bats-core 1.13 ou superior) |

Ferramenta sem opcao de parada no primeiro teste falho: o runner roda o menor grupo possivel por comando (arquivo ou modulo) e o script orquestrador para no primeiro comando falho. A limitacao e registrada no parecer.

Os blocos de teste das skills de stack seguem esta tabela: todo comando de execucao de testes ali ja traz a opcao de parada (ou o laco por arquivo, quando nao ha opcao), e a configuracao de exemplo do runner a inclui (`addopts = -x`, `bail: 1`, `stopOnDefect="true"`). Aplicado em `django-expert`, `django-tdd`, `fastapi-expert`, `fastify-best-practices`, `nodejs-best-practices`, `bats-testing-patterns` e `review-documentation`.

## Orquestracao em script

Vale para o comando oficial do projeto (`docker compose run --rm <service> test`, `make test`, script em `scripts/`):

- Script POSIX `sh` com `set -e`, ou verificacao explicita do codigo de saida de cada comando de teste; o primeiro diferente de zero encerra o script com esse mesmo codigo.
- Proibido engolir o codigo de saida: `|| true`, `; true`, `set +e` em volta do comando de teste, `exit 0` incondicional ao final.
- Pipe perde o codigo de saida do runner em POSIX `sh` (`runner | tee log` retorna o do `tee`). Gravar a saida em arquivo e exibi-la depois (`runner > log 2>&1; status=$?; cat log; exit "$status"`), ou usar `set -o pipefail` apenas em Bash.
- Camadas e modulos em sequencia, na ordem da tabela de niveis; nunca um laco que roda todos e so avalia o resultado no fim.
- Container de teste: `docker compose run` propaga o codigo de saida do servico; `docker compose up` exige `--exit-code-from <service>` (com `--abort-on-container-exit`), senao a falha nao chega ao chamador.

## Pipeline

- Etapas de teste em passos (`steps`) sequenciais do mesmo job, ou em jobs encadeados por `needs:`: passo ou job falho impede os seguintes, que e o comportamento padrao do GitHub Actions.
- Proibido `continue-on-error: true` em passo ou job de teste, e `if: always()` ou `if: failure()` em passo que **execute teste**. Essas condicoes so sao admitidas no passo de **reporte** (resumo, anotacoes, upload de log).
- Matriz de testes com `strategy.fail-fast: true` (padrao do GitHub Actions), nunca `false`.
- Reexecucao cega de job falho nao e prova de correcao (Passo 4 do `SKILL.md`).
- A suite completa vem logo apos os passos de preparo (checkout do estado integrado, dependencias e runner com versoes fixadas, ambiente e pre-requisitos, gates rapidos) e antes dos demais steps do projeto; erro no preparo tambem interrompe o job e deixa a suite nao executada. Ordem completa em [execucao-por-modulo.md](execucao-por-modulo.md#ordem-dos-passos-no-job).

```yaml
# GitHub Actions - ajustar o comando de cada camada ao projeto
jobs:
  suite-completa:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: true            # padrao; explicito para nao ser trocado
    defaults:
      run:
        shell: bash              # bash -eo pipefail: o codigo do runner atravessa o tee
    steps:
      - uses: actions/checkout@v4
      # Passos 2 a 4 da ordem na pipeline (dependencias, ambiente, gates rapidos): execucao-por-modulo.md
      - name: Unitario
        run: <comando unitario com parada no primeiro erro> 2>&1 | tee testes.log
      - name: Integracao (banco real)
        run: <comando integracao com parada no primeiro erro> 2>&1 | tee -a testes.log
      - name: E2E
        run: <comando E2E com parada no primeiro erro> 2>&1 | tee -a testes.log
      - name: Reporte do erro
        if: failure()
        run: |
          {
            echo "## Testes interrompidos no primeiro erro"
            echo "- Commit: \`$GITHUB_SHA\` | Evento: \`$GITHUB_EVENT_NAME\` | Run: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
            echo '```'
            tail -n 80 testes.log
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"
      # Demais steps do projeto (build, publicacao, deploy) so depois daqui, ou em job com needs: suite-completa
```

O passo de reporte nao altera o resultado: o job continua vermelho. O log publicado e sanitizado como qualquer evidencia (Security Handoff do `SKILL.md`): sem segredo, token ou dado pessoal real.

## Reporte para correcao

O reporte existe para que o dono corrija sem reproduzir a investigacao. Campos minimos, local ou pipeline:

| Campo | Conteudo |
|---|---|
| Camada | Unitario, integracao ou E2E |
| Modulo | Identificador do mapa de modulos (Regra 8) |
| Teste | Nome do teste ou cenario que falhou |
| Local | `arquivo:linha` do teste e, quando o runner informar, do codigo que falhou |
| Tipo de erro | Assercao, setup/hook, timeout, compilacao/coleta, infraestrutura de teste, zero testes |
| Mensagem | Trecho do erro e da saida, sanitizado |
| Comando | Comando exato que falhou |
| Execucao | Local: ciclo do gate e data. Pipeline: workflow, evento, commit e id da run |
| Nao executados | Modulos e camadas que nao rodaram por causa da interrupcao |

Destino:

- **Local.** O erro e registrado no parecer de testes, na secao da execucao interrompida, e segue o ciclo normal do gate: devolucao acionavel ao agent originador (regra 17 do `AGENTS.md`). Enquanto a execucao seletiva nao terminar sem interrupcao, o gate nao aprova.
- **Pipeline.** O job falha com o reporte no resumo da execucao e o conjunto e devolvido ao **Tech Lead** (Regra 8), que classifica o modulo que interrompeu a execucao e atribui a correcao ao agent dono.

## Retomada apos a correcao

- A execucao recomeca **do inicio**: a selecao inteira no local, o job inteiro na pipeline. Rodar apenas o teste corrigido serve ao ciclo red-green, mas nao fecha o gate nem libera o merge.
- Com a parada no primeiro erro, cada execucao revela no maximo um modulo falho. O segundo aparece na reexecucao, recebe o mesmo tratamento e o parecer acumula uma linha por interrupcao, na ordem em que ocorreram.
- Testes que nao rodaram por causa da interrupcao sao declarados **nao executados**: nunca entram como aprovados no total, na distribuicao da piramide ou no DoD.
