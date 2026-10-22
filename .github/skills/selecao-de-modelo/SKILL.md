---
name: selecao-de-modelo
description: >
  Escolhe a faixa do modelo de cada delegacao pela classe da tarefa, nao pelo papel: economico para o
  que so renderiza o que ja foi decidido (documento, commit, log de prompt, indice), padrao para
  implementar, testar e validar, maximo para o que e caro errar (modelo de dados, arquitetura,
  seguranca, protocolo). A troca de modelo nao transfere contexto: transfere um pacote de
  transposicao, e `avaliar-troca-de-modelo.sh` diz se a economia sobrevive ao custo desse pacote e do
  cache perdido. Use ao delegar e ao fixar `model:` numa persona; prefira `entrega-por-porte` para o
  porte da demanda e `memoria-por-janela` para o que entra no pacote vindo da memoria.
---

# Selecao de modelo por complexidade da tarefa

## Security Handoff

Descer de faixa por economia nunca e admitido quando a tarefa toca autenticacao, autorizacao, segredo, schema ou fronteira arquitetural: `faixa-do-modelo.sh --toca` sobe a faixa para `maximo` por criterio, nao por juizo. O pacote de transposicao e texto que atravessa modelos e fica no log do cliente de IA: nunca leva segredo, token, credencial, cookie, chave nem dado pessoal desnecessario (regra 2 do `AGENTS.md`); caminho de arquivo sim, conteudo de arquivo protegido nao. A tabela de modelos nao e lugar de chave de API. Em demanda que toque seguranca, aplicar tambem `security-best-practices` e `api-security-best-practices` ao decidir a classe.

## Scope Boundary

- O `AGENTS.md` (paragrafo sobre `model:` das personas) diz **onde** o modelo de um subagent e declarado e que o protocolo nao repete identificador de modelo; esta skill diz **como escolher a faixa** e deixa os identificadores na tabela do projeto (`scripts/tabela-de-modelos.tsv`).
- [`entrega-por-porte`](../entrega-por-porte/SKILL.md) classifica o porte da demanda; o porte e uma entrada desta skill (G sobe `padrao` para `maximo`), nao a sua saida.
- [`memoria-por-janela`](../memoria-por-janela/SKILL.md) e a regra 43 definem o extrato de memoria que o Tech Lead transpoe; aqui ele e uma das partes do pacote de transposicao e entra na conta do custo da troca.
- As regras 42 e 43 do `AGENTS.md` ja dizem que `documentation-writer` e `commit-writer` recebem tudo na delegacao: e exatamente por isso que eles sao a faixa `economico` por padrao.
- [`governanca-por-hooks`](../governanca-por-hooks/SKILL.md) cuida dos hooks do cliente; um cliente que oferece hook de criacao de subagent pode fixar a faixa por ali (ver referencia por cliente), mas a decisao continua sendo a desta skill.

## Origem

Pedido do solicitante em 16/10/2026 no modelo: evitar modelo forte em acao corriqueira (documento, commit) e modelo fraco em acao complexa (modelo de dados), com a troca garantindo a transposicao do contexto necessario e avaliando se a troca para o mais barato economiza de verdade, descontada a transposicao. Entrada de memoria `2026-10-16-1802-selecao-de-modelo-por-classe-de-tarefa`.

## Principio

**A faixa e da tarefa, nao do papel.** O mesmo Senior Developer implementa um endpoint (padrao) e desenha uma migracao de schema (maximo). O mesmo Tech Lead redige um resumo (economico) e resolve um conflito de decisao entre instancias (maximo). Tres faixas, nomes agnosticos ao fornecedor:

| Faixa | O que faz | Classes (`faixa-do-modelo.sh --classes`) |
|---|---|---|
| `economico` | renderiza o que ja foi decidido; nao julga | `redacao`, `commit`, `log-de-prompt`, `sincronizacao-documental`, `indice`, `limpeza`, `formatacao`, `resumo`, `transcricao` |
| `padrao` | implementa, testa, valida, analisa dentro de criterios dados | `implementacao`, `teste`, `validacao-qa`, `revisao`, `requisitos`, `ux`, `conformidade`, `analise` |
| `maximo` | decide o que e caro errar | `modelo-de-dados`, `arquitetura`, `seguranca`, `decisao-de-protocolo`, `migracao`, `integracao-externa`, `resolucao-de-conflito`, `planejamento-g` |

A faixa da classe e um **piso**. Sobe, nunca desce: `--toca schema|auth|segredo|fronteira` leva a `maximo`; `--toca contrato|dado-sensivel|pipeline|dependencia` leva a `padrao`; `--porte G` leva `padrao` a `maximo` (renderizar continua `economico`, porque renderizar e renderizar); `--critico` leva a `maximo`. Economia nunca e argumento para ficar abaixo do piso: o que o calculo decide e se vale **sair** da faixa da sessao para a faixa da classe, dado o custo de transpor.

Duas consequencias praticas:

- Em porte P o Tech Lead implementa ele mesmo (fluxo P), na faixa da sessao; a skill vale para o que ele delega (`documentation-writer`, `commit-writer`) e para o `model:` fixado nas personas.
- `maximo` nunca e fixado abaixo da faixa da sessao: uma persona de faixa `maximo` **herda** o modelo da sessao ou declara explicitamente um da linha `maximo` da tabela. Persona `economico` declara o seu.

## Os dois scripts

Ambos em POSIX `sh`, em `scripts/` desta skill, com Bats em `scripts/tests/`. O projeto os copia para `scripts/` e `scripts/tests/`, junto com a tabela.

### `faixa-do-modelo.sh` (ao delegar)

```sh
sh scripts/faixa-do-modelo.sh --classe modelo-de-dados --porte M
sh scripts/faixa-do-modelo.sh --classe redacao --porte G --toca contrato
```

Imprime `faixa:`, `motivo:` (a classe e cada criterio que subiu) e `modelo: <alias> (<id>)` pela tabela. Exit 2 em classe, item de `--toca` ou porte desconhecidos: a lista de classes e fechada de proposito, para que "complexidade" nao seja um adjetivo.

### `avaliar-troca-de-modelo.sh` (antes de sair da faixa da sessao)

```sh
sh scripts/avaliar-troca-de-modelo.sh --de opus --para haiku --saida 3000 --leitura 8000 --pacote /tmp/pacote.md
sh scripts/avaliar-troca-de-modelo.sh --de maximo --para economico --saida 300 --cache 60000 --transposicao 4000 --retrabalho 30
```

Compara **ficar** (a tarefa segue no modelo atual) com **trocar** (um subagent no outro modelo), em USD pela tabela:

```text
ficar  = leitura*in(A) + cache*cache(A) + saida*out(A)
trocar = transposicao*out(A)                      o modelo atual escreve o pacote
       + (transposicao + leitura + cache)*in(B)   o outro le o pacote e tudo o que o atual ja tinha
       + saida*out(B)
       + retorno*in(A)                            o atual le o resultado de volta
       + retrabalho% * ficar                      chance de ter de refazer no atual
```

Saida: `ficar`, `trocar`, `economia` (USD e %), `equilibrio: transposicao de ate N tokens` (o tamanho de pacote a partir do qual a troca deixa de compensar) e `veredito: TROCAR | FICAR`. Exit 0 trocar, 3 ficar. Tres fatos que o calculo torna visiveis:

- **Cache e por modelo.** O que o modelo atual tem em cache (`--cache`) vira entrada integral no outro. Tarefa pequena no meio de uma sessao com muito contexto quente raramente compensa trocar, mesmo para um modelo dez vezes mais barato.
- **O pacote custa duas vezes:** e saida no modelo atual (o preco mais caro da tabela) e entrada no novo. Por isso o ponto de equilibrio e a linha que importa: pacote maior que ele, fica.
- **Retrabalho** (`--retrabalho`, percentual) e a confissao de que a faixa de baixo erra mais. O projeto calibra o valor por classe com a propria historia (registros de entrega devolvidos); sem historia, 0 para `economico` em classe de renderizacao e 20 a 30 para `padrao` em tarefa com julgamento.

`--pacote <arquivo>` estima a transposicao por bytes/4, heuristica declarada e suficiente para a decisao; o endpoint de contagem de tokens da API mede exato quando o projeto quiser prender o numero. Decisao: `TROCAR` so quando `economia > 0`; empate fica.

## Pacote de transposicao

A troca de modelo **nao transfere contexto**: o subagent comeca vazio em qualquer cliente, e o que atravessa e o pacote. O que nao estiver nele nao existe para o novo modelo. Conteudo, ordem e o que nunca entra: [references/pacote-de-transposicao.md](references/pacote-de-transposicao.md). Em resumo: objetivo e contrato de saida; porte e faixa; caminhos dos arquivos (nunca o conteudo inteiro); as decisoes pertinentes como extrato de memoria (`memoria-index.sh --agente <papel> --corpo`, regra 43); criterios de aceite; o que nao fazer. O pacote e o arquivo que `--pacote` mede.

## Por cliente de IA

Onde a faixa vira configuracao em cada cliente (campo `model:` da persona, parametro por invocacao, variavel de ambiente, hook de criacao de subagent): [references/clientes-de-ia.md](references/clientes-de-ia.md). Sintaxe conferida na documentacao vigente em 16/10/2026; reconferir na adocao (regra 30).

## Tabela de modelos

[references/tabela-de-modelos.exemplo.tsv](references/tabela-de-modelos.exemplo.tsv): `faixa`, `alias`, `id`, preco de entrada, de saida e de leitura de cache, em USD por milhao de tokens. A primeira linha de cada faixa e a usada quando se pede a faixa; as demais sao alcancadas pelo alias. Precos envelhecem: o exemplo traz a data da conferencia, e o projeto copia a tabela para `scripts/tabela-de-modelos.tsv` e a reconfere a cada mudanca de modelo ou de preco. Identificador de modelo vive so na tabela e no `model:` das personas (paragrafo do `AGENTS.md` sobre `model:`), nunca em regra.

## Adocao num projeto

Registrar numa entrada `tipo: decisao`, `escopo: projeto`, `agentes: tech-lead, senior-developer, qa-expert, dba, documentation-writer, commit-writer`: a tabela adotada (aliases do cliente, ids, precos e data da conferencia); quais personas levam `model:` fixo e em que faixa; o `--retrabalho` por classe, quando calibrado; e o cliente de IA com o mecanismo usado (persona, invocacao ou hook). Projeto com mais de um cliente mantem uma configuracao por cliente apontando para a mesma tabela.
