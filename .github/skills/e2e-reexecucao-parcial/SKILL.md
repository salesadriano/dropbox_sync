---
name: e2e-reexecucao-parcial
description: >
  Quando a suite E2E da pipeline para na primeira falha (Regra 9 de protocolo-tdd), deriva do log
  do runner o que falhou e o que ficou sem exercicio (scripts/specs-nao-executadas.sh, com a
  implementacao de referencia para a saida do Cypress e o contrato para outros runners) e reexecuta
  so isso por um workflow de disparo manual, na mesma cadeia real, sem publicar nada. Use ao
  configurar o diagnostico do job E2E e a reexecucao parcial; prefira `protocolo-tdd` para a regra
  da parada no primeiro erro e para o E2E em si.
---

# E2E: fail-fast com reexecucao parcial

## Security Handoff

O diagnostico do E2E sobe como artefato da pipeline: log da cadeia, screenshots e videos. Segredos efemeros do ambiente de E2E sao mascarados antes de o log subir (o projeto mantem o script de mascaramento ao lado da cadeia); screenshots **nao** sao mascaradas e, por isso, o ambiente de E2E so recebe dados sinteticos. O workflow de reexecucao parcial recebe listas de specs por `workflow_dispatch`: os inputs sao tratados como texto, nunca expandidos por `eval`, e so chegam ao runner pelo argumento `--spec`. Em fluxo com autenticacao ou dado sensivel, aplicar tambem `security-best-practices` e `api-security-best-practices`.

## Scope Boundary

- `ai-team:protocolo-tdd` e a fonte da Regra 9 (parar no primeiro erro e reporta-lo) e da Regra 8 (suite completa na pipeline, antes dos demais steps); esta skill cuida do que acontece **depois** da parada: dizer o que nao rodou e reexecutar so isso.
- A mecanica da parada por ferramenta vive na referencia `interrupcao-no-primeiro-erro` de `protocolo-tdd`; nao e repetida aqui.
- `ai-team:governanca-por-hooks` e quem impede a suite inteira **local**; esta skill so trata da pipeline.

## Origem

Pratica adotada num projeto governado por este pacote em 14/10/2026 (item 8 de onze mods de governanca) e trazida ao modelo em 15/10/2026 (entrada `2026-10-15-0914-skills-a-partir-dos-mods-de-governanca`). La, um E2E vermelho na branch de release custava a cadeia inteira de novo (o E2E completo levava 44 minutos) para confirmar uma correcao de uma spec; o primeiro uso real reexecutou 55 specs em vez da suite.

## Como funciona

1. **A suite para na primeira falha** (Regra 9), e o que vem depois dela fica sem exercicio: nao falhou, nao passou.
2. **Passo `if: failure()` do job E2E:** `specs-nao-executadas.sh` le o log do runner, separa as corridas por cliente (na ordem dos passos do job) e classifica cada spec que existe no disco em **falhou**, **executada** ou **nao executada**. Publica no resumo da execucao e em `diagnostico-e2e/specs-nao-executadas.txt`, que entra no artefato de diagnostico, com a linha `reexecutar:` pronta por cliente. Nao altera o resultado do job: sai sempre com 0.
3. **Workflow de reexecucao parcial**, so por `workflow_dispatch`, que recusa ref diferente da branch de release, repete **verbatim** os passos de preparo, subida e derrubada do job E2E e passa `--spec` ao runner. Exemplo agnostico em [references/workflow-reexecucao-parcial.exemplo.yml](references/workflow-reexecucao-parcial.exemplo.yml).
4. **O que o parcial nao e:** nao publica imagem nem implanta (por construcao: a publicacao escuta so o workflow principal) e **nao substitui** o run completo da pipeline, que continua o unico portao da publicacao. Um verde no parcial confirma a correcao; o verde que libera e o do run completo seguinte.

## O script

`scripts/specs-nao-executadas.sh`, POSIX `sh` + `awk`, testes em `scripts/tests/specs-nao-executadas.bats`.

```sh
sh scripts/specs-nao-executadas.sh --log "$RUNNER_TEMP/testes.log" --clientes app-web,app-admin
sh scripts/specs-nao-executadas.sh --clientes . --specs e2e/specs --extensao .spec.ts --workflow e2e-parcial.yml
```

| Opcao | Padrao | Significado |
|---|---|---|
| `--log` | `$RUNNER_TEMP/testes.log` | log do runner, com as corridas em sequencia |
| `--raiz` | topo do repositorio | raiz a partir da qual os diretorios dos clientes sao resolvidos |
| `--clientes` | `.` | diretorios dos clientes, na ordem das corridas do log; `.` e um cliente so, na raiz |
| `--specs` | `cypress/e2e` | subdiretorio das specs dentro de cada cliente |
| `--extensao` | `.cy.ts` | sufixo dos arquivos de spec |
| `--saida` | `diagnostico-e2e/specs-nao-executadas.txt` | arquivo publicado no artefato |
| `--workflow` | `e2e-parcial.yml` | nome do workflow citado no resumo |

**Contrato de saida** (o que o workflow parcial e o operador leem), por cliente e nesta ordem: `<cliente> executadas: <n>`, `<cliente> falhou: <lista|nenhuma>`, `<cliente> nao executadas: <lista|nenhuma>`, `<cliente> reexecutar: <falhou,nao executadas|nenhuma>`; listas separadas por virgula, caminhos relativos ao subdiretorio de specs.

**Implementacao de referencia para o Cypress**, o runner padrao do pacote (regra 13 do `AGENTS.md`): corridas separadas por `(Run Starting)`, spec por `Running: <caminho> (i of n)`, falha por `N) <teste>`, sucesso por `✓ <teste>`, pendente por `- <teste>` (o que o `cypress-fail-fast` deixa nas specs depois da primeira falha). Outro runner (Playwright, WebdriverIO) recebe o seu parser com o **mesmo contrato de saida**, no mesmo lugar do job, e com Bats proprio; o workflow parcial nao muda.

**Limites declarados:** spec inteiramente pulada (`it.skip` em todos os casos) conta como nao executada, porque o log e identico; sufixo ambiguo entre uma spec na raiz e outra em subpasta e resolvido pelo caminho exato quando ele aparece e pelo sufixo mais longo quando nao; no parcial, as specs que nao foram pedidas aparecem como nao executadas, por desenho.

## O workflow parcial

Do exemplo em `references/`, o projeto preenche: a branch de release aceita, os comandos de preparo e de subida da cadeia (os mesmos do job E2E, verbatim), os clientes e o artefato. Regras:

- so `workflow_dispatch`; recusa qualquer ref que nao seja a branch de release, e recusa disparo sem nenhuma spec;
- os inputs sao listas separadas por virgula, relativas ao subdiretorio de specs, no formato que o runner imprime; o passo monta o `--spec` com `sed`/`paste`, sem `eval`;
- `specs-nao-executadas.sh --clientes` recebe **so os clientes que correram** (input vazio pula o cliente; sem isso a primeira corrida do log seria atribuida ao cliente errado);
- um teste de estrutura do projeto prende a paridade entre os passos do parcial e os do job E2E (mudou la, muda aqui), e prende que a publicacao escuta so o workflow principal;
- o workflow e lido pelo GitHub a partir da branch de release: o primeiro exercicio real e o primeiro E2E vermelho depois do merge, e o registro de entrega diz isso.

## Operacao

Quando o E2E da release fica vermelho: abrir o resumo da execucao ou o `specs-nao-executadas.txt` do artefato; corrigir; disparar o parcial com a linha `reexecutar:` de cada cliente (`gh workflow run <workflow> --ref <release> -f specs_<cliente>='<lista>'`); com o parcial verde, o run completo seguinte da pipeline e o que libera a publicacao. O procedimento vai para o guia de operacao do projeto.

## Testes

```sh
npx --yes bats@1.13.0 --abort --print-output-on-failure .github/skills/e2e-reexecucao-parcial/scripts/tests/
```

`--abort` para no primeiro teste falho (Regra 9). O script e POSIX `sh`; `shellcheck -s sh` e item do gate de conformidade. O workflow parcial e validado por teste de estrutura e so e exercido de verdade na pipeline.

## Adocao num projeto

Levar a pasta inteira da skill; copiar o script e o Bats para `scripts/` e `scripts/tests/`; acrescentar o passo `if: failure()` ao job E2E e o arquivo ao artefato de diagnostico; criar o workflow parcial a partir do exemplo; registrar numa entrada `tipo: decisao`, `escopo: projeto`, `agentes: qa-expert, senior-developer, tech-lead` os clientes, o runner, a branch de release e o nome do workflow.
