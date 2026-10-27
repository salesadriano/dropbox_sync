---
name: superficie-de-contrato
description: >
  Remede a superficie de um contrato (contagem de rotas, endpoints, eventos, tabelas, comandos)
  so quando o diff pode te-la mudado, e prende, no gate rapido da pipeline, a concordancia entre
  as copias desse numero (constante de teste, bloco de estado do arquivo de instrucoes, pino de
  regressao do QA) com o script conferir-copias.sh. Use para decidir se uma entrega exige
  remedicao e para conferir as copias; prefira `protocolo-tdd` para a medicao em si (Regra 6 e
  testes de contrato) e `instrucoes-do-projeto` para frases e caminhos do arquivo de instrucoes.
---

# Superficie de contrato: remedir so quando muda, conferir sempre

## Security Handoff

A superficie de contrato de uma API inclui quem alcanca cada rota. Mudanca de alcance por papel e mudanca de superficie e exige a remedicao e os cenarios negativos de acesso da Regra 6 de `protocolo-tdd`, contra backend e banco reais; `api-security-best-practices` e a fonte das regras que esses testes provam. Nunca gravar no bloco de estado, no pino ou no registro de entrega token, credencial, cookie ou dado pessoal copiados de uma medicao.

## Scope Boundary

- A **medicao** da superficie (contar por HTTP, por introspeccao do roteador, por leitura do contrato publicado) e parte dos testes de contrato de `ai-team:protocolo-tdd`; esta skill diz **quando** ela e exigida e confere as **copias** do resultado.
- `ai-team:instrucoes-do-projeto` prende frases e caminhos do arquivo de instrucoes; o `conferir-copias.sh` prende um **numero** em N arquivos e nao repete aquilo.
- `ai-team:gitflow`, regra 47, manda avaliar a branch principal antes de cada push; a recontagem na juncao de duas frentes e um caso desta skill.

## Origem

Pratica adotada num projeto governado por este pacote em 14/10/2026 (item 6 de onze mods de governanca) e trazida ao modelo em 15/10/2026 (entrada `2026-10-15-0914-skills-a-partir-dos-mods-de-governanca`). La, a contagem de rotas era remedida por HTTP, por duas vias independentes, em **toda** entrega, com errata no arquivo de instrucoes a cada numero novo; e por tres vezes a constante se fundiu "sem conflito e errada" na juncao de duas frentes que tinham chegado sozinhas ao mesmo numero antigo.

## Regras

1. **O que e a superficie.** Um numero (ou um conjunto pequeno de numeros) que descreve o contrato publico do sistema: rotas autenticadas, anonimas e por papel; endpoints de um contrato; eventos publicados; tabelas e colunas expostas; comandos de uma CLI. O projeto declara a sua na entrada de adocao, com a fonte de cada parcela.
2. **A superficie muda quando o diff toca o que a define.** O projeto lista os caminhos: a camada de apresentacao (controllers, rotas, handlers), a matriz ou as constantes de autorizacao, guards e decorators de acesso, o contrato publicado (OpenAPI, schema de eventos). Diff que toca um deles, na demanda ou na juncao com a principal, **exige remedicao**; diff que nao toca, **nao**.
3. **Quando muda:** medir por **duas vias independentes por construcao** (por exemplo, de dentro da suite pela introspeccao do roteador e do contrato, e de fora da cadeia, contra o servidor real servido pelo proxy, com sessoes reais por papel), sem que nenhuma leia a constante como oraculo; as duas precisam concordar **parcela a parcela**, nao so no total. A constante, o bloco de estado do arquivo de instrucoes, o pino de regressao do QA e a errata no historico mudam **no mesmo diff**. Uma via so e registrada como uma via so.
4. **Quando nao muda:** os pinos de regressao existentes bastam. Ninguem remede, ninguem reescreve o pino e **nao se escreve errata**. O registro de entrega diz "superficie inalterada: o diff nao toca <caminhos>", conferido pelo autor e pelo QA.
5. **Conferir as copias sempre.** `conferir-copias.sh` roda no gate rapido da pipeline e localmente antes do commit; reprova quando uma copia difere das outras ou quando o mesmo padrao aparece duas vezes com valores diferentes no mesmo arquivo. E **consistencia entre copias, nao medicao**: uma divergencia coerente nas N copias passa, e e por isso que a regra 3 exige as duas vias quando a superficie muda.
6. **Na juncao de duas frentes** que acrescentaram parcelas, quem mescla por ultimo soma e reconta pela regra 3; a constante que o merge fundiu sem conflito nao e evidencia de nada.
7. **Leia as parcelas, nao a soma.** Um instrumento que classifica mal o caso degradado devolve um total plausivel com parcelas erradas; o pino e o bloco de estado trazem todas as parcelas, e a concordancia e verificada em cada uma.

## O verificador

`scripts/conferir-copias.sh`, POSIX `sh`, com testes em `scripts/tests/conferir-copias.bats`. Recebe pares `arquivo=ERE` com exatamente um grupo de captura e exige que todas as ocorrencias, em todos os arquivos, digam o mesmo valor:

```sh
sh .github/skills/superficie-de-contrato/scripts/conferir-copias.sh --rotulo "rotas autenticadas" \
  'test/matriz-de-autorizacao.ts=ROTAS_AUTENTICADAS_ESPERADAS = ([0-9]+);' \
  'CLAUDE.md=\*\*([0-9]+) autenticadas' \
  'test/pino-de-contagem.spec.ts=AUTENTICADAS=([0-9]+)'
```

Saida `✔ <rotulo>: <valor> igual em <n> copia(s)` e exit 0; lista `- <arquivo>: <valor>` e exit 1 quando divergem, quando uma copia nao e encontrada ou quando o mesmo arquivo traz o padrao com valores diferentes; exit 2 em argumento invalido. Uma chamada por parcela (autenticadas, anonimas, total...); a soma das parcelas, quando o bloco de estado a declara, e uma chamada a mais com a ERE do total, e a aritmetica e conferida pelo teste de contrato do projeto, nao por este script.

Na pipeline, no gate rapido antes da suite (Regra 8 de `protocolo-tdd`), um passo por parcela ou um script do projeto que encadeie as chamadas com `set -e`: o job para na primeira divergencia.

## Registro

No registro de entrega, uma de duas linhas, sempre:

- `Superficie inalterada: o diff nao toca <caminhos listados na adocao>; pinos existentes bastam; conferir-copias ✔.`
- `Superficie remedida: <parcelas> por <via 1> e <via 2>, concordantes parcela a parcela; constante, bloco de estado, pino e historico atualizados neste diff.`

A ultima medicao fica linkada no bloco de estado do arquivo de instrucoes (`ai-team:instrucoes-do-projeto`); a errata vai ao historico.

## Testes

```sh
npx --yes bats@1.13.0 --abort --print-output-on-failure .github/skills/superficie-de-contrato/scripts/tests/
```

`--abort` para no primeiro teste falho (Regra 9 de `protocolo-tdd`; mecanica por ferramenta na referencia `interrupcao-no-primeiro-erro` de `ai-team:protocolo-tdd`). O script e POSIX `sh`; `shellcheck -s sh` e item do gate de conformidade.

## Adocao num projeto

Levar a pasta inteira da skill; copiar o script e o Bats para `scripts/` e `scripts/tests/` quando o projeto centralizar ali os scripts de governanca. Registrar numa entrada `tipo: decisao`, `escopo: projeto`, `agentes: senior-developer, qa-expert, tech-lead`: as parcelas da superficie e a fonte de cada uma, os caminhos cujo diff exige remedicao, as duas vias de medicao e as chamadas do `conferir-copias.sh` que a pipeline executa.
