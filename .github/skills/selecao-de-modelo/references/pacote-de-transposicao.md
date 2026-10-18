# Pacote de transposicao

O que atravessa uma troca de modelo. Um subagent comeca vazio em todo cliente de IA: nao ve a conversa, o cache nem a memoria que o agent originador carregou. A regra 42 do `AGENTS.md` ja exige isso para `documentation-writer` e `commit-writer`; esta referencia generaliza para qualquer delegacao que mude de faixa e fixa a ordem, para que o pacote seja previsivel e medivel (`avaliar-troca-de-modelo.sh --pacote`).

## Ordem fixa das secoes

1. **Objetivo e contrato de saida.** Uma frase do que fazer e o formato exato do que devolver (arquivo e caminho, secoes, contagens literais). O modelo barato renderiza bem o que foi pedido com precisao e mal o que foi pedido por alusao.
2. **Porte e faixa.** `porte: M`, `faixa: economico (classe redacao)`; a faixa diz ao subagent o que **nao** e dele decidir.
3. **Arquivos, por caminho.** Lista de caminhos relativos a raiz, com uma linha por arquivo dizendo o que ha nele que importa. Nunca o conteudo inteiro: o subagent le o que precisar, e o custo dessa leitura ja esta em `--leitura`.
4. **Decisoes pertinentes.** Extrato de memoria no formato de `sh scripts/memoria-index.sh --agente <papel> --corpo` (regra 43), so das entradas que a tarefa usa, com id e titulo. Decisao fora do extrato nao existe para o subagent: na duvida, inclui; se o extrato cresce alem do ponto de equilibrio, a troca nao compensa e o pacote avisou.
5. **Criterios de aceite.** O que o originador vai conferir ao receber: lista curta e verificavel.
6. **O que nao fazer.** Limites explicitos: nao editar fora dos arquivos listados, nao inferir decisao, nao resumir contagem, devolver pedindo o que faltar.

## O que nunca entra

- Segredo, token, credencial, cookie, chave, dado pessoal desnecessario (regra 2). O pacote fica no log do cliente.
- Conteudo integral de arquivo que o subagent pode ler sozinho.
- A memoria inteira ou entradas de outros papeis (regra 43).
- Historico da conversa: o que importa dele ja virou decisao (secao 4) ou criterio (secao 5).

## Medir

```sh
sh scripts/avaliar-troca-de-modelo.sh --de <faixa da sessao> --para <faixa da classe> --saida <tokens> --leitura <tokens> --pacote pacote.md
```

`--saida` e o tamanho esperado do artefato; `--leitura` e o que o subagent vai ler pelos caminhos da secao 3; o pacote e medido do arquivo. Se o veredito for `FICAR`, a tarefa fica no modelo atual, e o pacote nao e enviado; o calculo custou menos que a troca errada.

## Quando a troca e sempre `FICAR`

- Tarefa de classe `maximo` numa sessao ja em `maximo`: nao ha para onde ir.
- Continuacao de trabalho em curso com muito contexto quente (`--cache` grande): o ponto de equilibrio cai para poucas centenas de tokens.
- Tarefa cujo retorno e quase do tamanho da saida (revisao linha a linha): `--retorno` explicito aproxima `trocar` de `ficar`.
