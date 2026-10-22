---
name: instrucoes-do-projeto
description: >
  Mantem enxuto o arquivo de instrucoes que a ferramenta de IA le no projeto (CLAUDE.md,
  .github/copilot-instructions.md, AGENTS.md na raiz ou equivalente): erratas e estado passado vao
  verbatim para docs/historico/, o estado vigente fica num bloco unico, e o script
  verificar-instrucoes-do-projeto.sh acusa, no gate rapido da pipeline e no inicio da sessao, as
  afirmacoes do arquivo que divergem do repositorio. Use para compactar, reorganizar ou prender o
  arquivo de instrucoes; prefira `documentation-sync` para atualizar a documentacao viva depois de
  uma entrega e `superficie-de-contrato` para conferir copias de um numero de contrato.
---

# Instrucoes do projeto enxutas e sem drift

## Security Handoff

Esta skill le e reescreve o arquivo de instrucoes do projeto e grava historico em `docs/`.

- Nada do que for movido para `docs/historico/` pode conter segredo, credencial, token, cookie, chave ou dado pessoal desnecessario: sanitizar antes de mover, nunca depois. O que nao puder ser sanitizado e descrito, nao copiado.
- Se o arquivo de instrucoes descrever autenticacao, autorizacao, segredos ou exposicao de API, aplicar tambem `security-best-practices` e `api-security-best-practices` ao reescreve-lo.
- Nunca incluir segredos em exemplos, fixtures, diagramas, logs ou artefatos gerados por esta skill.

## Scope Boundary

- [`documentation-sync`](../documentation-sync/SKILL.md) decide **quais documentos** mudaram depois de uma entrega; esta skill cuida de **um** documento, o arquivo de instrucoes, e do que ele afirma sobre o repositorio.
- [`superficie-de-contrato`](../superficie-de-contrato/SKILL.md) confere que N copias de um **numero** de contrato concordam; o verificador daqui confere **frases e caminhos** (branch principal, contagem de regras, repositorio canonico, arquivos citados) e nao repete aquela conferencia.
- [`governanca-por-hooks`](../governanca-por-hooks/SKILL.md) e quem roda o verificador no inicio da sessao, em modo aviso; a reprovacao fica na pipeline.
- [`memoria-por-janela`](../memoria-por-janela/SKILL.md) cuida do bootstrap da memoria; o arquivo de instrucoes nao substitui a memoria nem o protocolo (`AGENTS.md`, regra 39).

## Origem

Praticas adotadas num projeto governado por este pacote em 14 e 15/10/2026 (itens 1 e 10 de onze mods de governanca) e trazidas ao modelo em 15/10/2026 (entrada de memoria `2026-10-15-0914-skills-a-partir-dos-mods-de-governanca`). O arquivo de instrucoes daquele projeto tinha 1888 linhas e 153 KB, dos quais 54 blocos de errata de uma unica contagem; era lido inteiro em toda sessao e por todo subagent.

## O problema

O arquivo de instrucoes do projeto e carregado em toda sessao. Tudo o que ele acumula custa contexto a cada demanda, e o que ele afirma sobre o repositorio (branch principal, contagem de regras do protocolo, scripts e workflows existentes, repositorio canonico) envelhece em silencio: uma frase que ficou para tras nao avisa ninguem.

## Regras

1. **Um bloco de estado por assunto, nunca uma trilha de erratas.** O arquivo de instrucoes diz **o que vale hoje**. Quando um numero ou um estado muda, o bloco e atualizado na mesma entrega; a errata (o que mudou, quando, medido por quem) vai para `docs/historico/<assunto>.md`, no fim da secao do assunto. O arquivo de instrucoes nao acumula blocos "corrigido em".
2. **Mover e verbatim, na ordem original, com a origem declarada.** Ao compactar um arquivo que ja acumulou erratas, cada bloco movido vai inteiro para o historico, sem edicao, na ordem em que estava, sob um cabecalho que diz de onde veio (`<arquivo> @ <sha>`, intervalo de linhas). O historico abre com a regra de que novas erratas entram ali. O verbatim e conferido por `diff` antes do commit. Ver [references/historico-de-erratas.md](references/historico-de-erratas.md).
3. **Prosa normativa vigente fica.** Decisao do solicitante que ainda vale ("isso e decisao, nao defeito"; "nao corrija isso"), regra de testes, ordem da pipeline e restricoes de ambiente **nao** sao erratas e nao saem do arquivo de instrucoes, mesmo que sejam longas. Na duvida, fica.
4. **O que um hook ou um verificador garante sai da prosa.** Comando proibido que a [`governanca-por-hooks`](../governanca-por-hooks/SKILL.md) bloqueia, contagem que um verificador confere, passo que a pipeline exige: a prosa e reduzida a uma linha com a marca `garantido por hook` ou `garantido por verificador` e o nome do script.
5. **O arquivo descreve o repositorio; quando o repositorio muda, o texto muda na mesma entrega.** O verificador existe para dizer qual frase ficou para tras, nao para substituir a leitura.
6. **Cite o simbolo, nao a linha.** Contagem e estado citam a constante, o arquivo ou a entrada de memoria de onde vem, nunca um numero de linha.

## O verificador

`scripts/verificar-instrucoes-do-projeto.sh`, POSIX `sh`, com testes em `scripts/tests/verificar-instrucoes-do-projeto.bats`. Le o arquivo de instrucoes e confere, pulando com `pulada: <motivo>` a conferencia cuja frase ou fonte nao exista:

| Conferencia | O que no arquivo de instrucoes | Contra o que no repositorio |
|---|---|---|
| (a) caminhos | todo caminho entre crases que comeca por `scripts/`, `.github/`, `docs/`, `.claude/` ou `.vscode/` | existencia no disco, relativa a raiz |
| (b) regras | a frase `**N regras**` (ou `N regras`) | regras numeradas `1.`..`N.` contiguas da secao `# Protocolo comum obrigatorio` do protocolo |
| (c) branch principal | a frase "branch principal declarada e `x`" | titulo da entrada `branch-principal` ativa |
| (d) canonico | a frase "repositorio canonico e `dono/repo`" | `git remote get-url origin` (ou `GITHUB_REPOSITORY` sem `.git`) |

```sh
sh .github/skills/instrucoes-do-projeto/scripts/verificar-instrucoes-do-projeto.sh
sh .github/skills/instrucoes-do-projeto/scripts/verificar-instrucoes-do-projeto.sh --instrucoes .github/copilot-instructions.md
```

Exit 0 sem drift; 1 com a lista `- (<letra>) <drift>`; 2 em argumento invalido ou arquivo de instrucoes nao encontrado (`--instrucoes` resolve). Padroes: raiz no topo do git; arquivo de instrucoes e o primeiro existente entre `CLAUDE.md`, `.github/copilot-instructions.md` e `AGENTS.md` da raiz; protocolo em `.github/agents/AGENTS.md` ou `.claude/ai_team/AGENTS.md`; entradas em `.github/agents/memoria/entradas` ou `.claude/ai_team/memoria/entradas`. `--raiz`, `--protocolo` e `--entradas` sobrescrevem.

E um verificador de **prosa**: prende as afirmacoes que envelhecem em silencio. Nao mede nada e nada do que le e oraculo de si mesmo; uma frase reescrita noutra forma deixa de ser conferida (a conferencia e pulada, nao reprovada), e por isso as quatro frases acima sao mantidas na forma literal.

**Limite declarado:** o verificador nao confere o formato `dono/repo` da frase (d) alem de exigir uma barra; um canonico escrito com erro de digitacao no arquivo e na URL do remoto passa. Herdado da origem (ressalva aberta la como QA-SG-1).

## Onde roda

- **Pipeline, gate rapido, antes da suite** (Regra 8 de [`protocolo-tdd`](../protocolo-tdd/SKILL.md)): reprova o job. Parada no primeiro erro: o passo e um comando so e o job para nele.

  ```yaml
  - name: instrucoes do projeto sem drift
    run: sh .github/skills/instrucoes-do-projeto/scripts/verificar-instrucoes-do-projeto.sh
  ```

- **Inicio da sessao, modo aviso**, pelo `resumo-de-estado.sh` de [`governanca-por-hooks`](../governanca-por-hooks/SKILL.md) (`--verificador`): avisa e a sessao abre de qualquer jeito. Quem reprova e a pipeline.
- **Local, antes do commit** de toda entrega que toque o arquivo de instrucoes, o protocolo, `scripts/`, `.github/workflows/` ou a entrada `branch-principal`.

## Como compactar um arquivo que ja acumulou

1. Medir antes: `wc -l`, `wc -c`, contagem dos blocos de errata (`grep -c` pela marca de errata usada no projeto). Registrar no registro de entrega.
2. Classificar cada bloco: **errata ou estado passado** (sai, verbatim) ou **norma vigente** (fica). Lista no registro de entrega, com o intervalo de linhas de cada secao movida.
3. Escrever o bloco de estado vigente de cada assunto, citando o simbolo e a ultima medicao (link para o registro que a fez).
4. Criar `docs/historico/<assunto>.md` conforme [references/historico-de-erratas.md](references/historico-de-erratas.md); conferir o verbatim por `diff` entre o trecho original (`git show <sha>:<arquivo>` recortado) e o historico.
5. Rodar o verificador; corrigir as frases que ele acusar (e comum encontrar drift antigo na primeira execucao).
6. Medir depois e registrar a reducao. A meta e do solicitante; o que nao pode sair por ser norma vigente e dito no registro, nao cortado.

## Testes

```sh
npx --yes bats@1.13.0 --abort --print-output-on-failure .github/skills/instrucoes-do-projeto/scripts/tests/
```

`--abort` para no primeiro teste falho (Regra 9 de `protocolo-tdd`; mecanica por ferramenta na referencia `interrupcao-no-primeiro-erro` de [`protocolo-tdd`](../protocolo-tdd/SKILL.md)). O script e POSIX `sh`: `shellcheck -s sh` sobre ele e item do gate de conformidade ([`shellcheck-configuration`](../shellcheck-configuration/SKILL.md)).

## Adocao num projeto

Levar a pasta inteira da skill. Copiar `scripts/verificar-instrucoes-do-projeto.sh` e o Bats para `scripts/` e `scripts/tests/` do projeto quando ele ja centralizar os scripts de governanca ali (e o caso dos projetos gerados pelo modelo), ou chama-lo no lugar. Registrar a adocao na memoria do projeto (`tipo: decisao`, `escopo: projeto`) com o arquivo de instrucoes escolhido e as quatro frases na forma literal.
