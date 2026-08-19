# Registro Tecnico — Comandos Diretos (parcial: 4 de 6)

## Identificacao

| Campo | Valor |
|---|---|
| Bloco | seis comandos diretos da Etapa 4 |
| Entregue | `space`, `info`, `list`, `delete` |
| Pendente | `upload`, `download`, atras do modo de conteudo em `lib/http` |
| Branch | `feature/comandos-diretos` |
| Estado | 416 casos aprovados, 0 reprovados, 2 pulados; `shellcheck` 0 nos dois modos |

## Decisoes de desenho

### ONDE VIVE UM COMANDO — entrada fina, um arquivo por comando

| Alternativa | Custo |
|---|---|
| Um executavel por comando | nove executaveis no caminho de busca e **nove copias** da interpretacao de opcoes globais — nove lugares para a regra divergir |
| Executavel unico com tudo dentro | e o monolito de 1834 linhas que `RNF-16` e `DIV-06` recusam; com o `sync` dentro, um arquivo passaria de metade do projeto |
| **Entrada fina + arquivo por comando** | **escolhido**: o custo de partida deixa de crescer com a quantidade de comandos, e cada comando vira unidade auditavel isolada — condicao para a guarda de remocao e as auditorias por arquivo continuarem funcionando com nove |

**Sub-decisao que muda seguranca, e nao estilo:** o despacho nao compoe o caminho a partir do nome recebido. `commands/$1.sh` derivaria caminho de codigo executado de origem externa — a classe que `RNF-24` proibe no analisador, aqui com consequencia pior: la o pior caso e colisao de contexto, aqui e execucao arbitraria. Tabela de nomes literais, com auditoria que reprova a interpolacao.

### QUANDO A VERIFICACAO PREVIA RODA — cada comando declara

Vocabulario fechado `nenhum | ambiente | credencial`, com auditoria que **enumera os arquivos de `commands/`**.

O que decide e o custo do falso negativo. `RNF-04` manda recusar execucao quando a credencial nao esta em `0600`. Se isso rodasse em todo comando, o assistente de configuracao ficaria impossivel de usar exatamente quando e necessario — nao daria para consertar a credencial com a ferramenta que se recusa a rodar porque a credencial esta errada. Impasse fechado criado por zelo.

### ESCRITA REMOTA NASCE GENERICA

`_dbx_cmd_escrita_remota` e o unico caminho de escrita, com o conjunto declarado: `delete`, `upload` e `sync`. Escrever como auxiliar de dois e descobrir o terceiro depois e a forma exata das oito ocorrencias da familia de gemeos. A verificacao de simulacao (`RF-15`) vem **antes** da chamada, e nao dentro: dentro existiria um caminho de escrita que a pula.

## Defeitos proprios encontrados e corrigidos

| Defeito | Como apareceu | Tratamento |
|---|---|---|
| `dbx_http_colecao` **descarta** o documento antes de retornar | comentario meu em `list` afirmava o contrario; a listagem saia vazia | `_dbx_cmd_analisar_corpo`, compartilhada pela chamada simples e pela de colecao |
| `dbx_path_remoto_para_api` imprime alem de publicar no canal | poluia a saida estruturada e quebraria o consumidor (`RF-28`); `info` passava porque `assert_contem` procura subcadeia | `_dbx_cmd_caminho_remoto` |
| Curto-circuito `_dbx_cli_recusar ... && return` | a funcao devolve status nao zero, entao o `return` nunca corria | bloco explicito |

As duas primeiras sao a mesma coisa: **uma funcao publica em dois canais e o chamador so considerou um**. E a familia de gemeos com o eixo trocado — nao dois lugares para a mesma regra, e sim dois canais para o mesmo valor.

## Prova fraca reconhecida, com pergunta precisa

O caso que verifica o conflito de `RF-49` no `delete` **nao discrimina**: passa mesmo com o mapeamento removido.

`dbx_errors_classificar` nao classifica por status, e sim pela **tag** do resumo. Medido:

| Status | Tag | Classe |
|---|---|---|
| 409 | `conflict/file/...` | conflito |
| 409 | (vazio) | desconhecido |
| 409 | `too_many_write_operations` | limite_taxa |
| 200 | `conflict/x` | sucesso |
| 500 | `conflict/y` | erro_remoto |

A taxonomia e o `case *conflict*` olham o mesmo sinal, e por isso um cobre o outro. Eu havia registrado que a taxonomia classificava por `409`; era falso. **Conclusao certa por motivo errado e fragil, porque quem lesse depois herdaria o motivo e nao a conclusao.**

Pergunta para a verificacao contra o servico real: **qual e a tag exata que a Dropbox devolve ao recusar escrita por `rev` divergente?** Se for `conflict`, a linha sai por redundante; se for outra, e a unica coisa que produz a classificacao certa e ganha caso que a exercita.

## Caracterizacao do cliente, por medicao

Modo de fluxo, cinco status medidos:

| Situacao | Status | Saida |
|---|---|---|
| sucesso | 0 | corpo integro |
| recusa HTTP sob `--fail` | 22 | **zero bytes** |
| consumidor morto | 23 | parcial |
| conexao recusada | 7 | — |
| recurso local ilegivel | 37 | — |

**Sem `--fail`, um `409` sai pela saida padrao com status zero** — resposta de erro virando conteudo de arquivo, falha que se parece com exito e que um `sync` posterior trataria como arquivo legitimo.

### VULNERABILIDADE REPRODUZIDA: injecao de cabecalho HTTP

```
-H 'X-Arg: antes<LF>X-Injetado: sim'    -> curl exit 0 -> servidor recebe X-Injetado
-H 'X-Arg: antes<CRLF>X-Injetado: sim'  -> curl exit 0 -> servidor recebe X-Injetado
```

A fonte do valor e **nome de arquivo do usuario**, via `Dropbox-API-Arg`. Um arquivo chamado `a<CRLF>Authorization: Bearer outro` reescreve a autenticacao da requisicao. O cliente nao avisa.

Encontrada **antes de existir codigo**, porque a ordem foi invertida para pos o transporte antes dos comandos. Na ordem original teria entrado em producao.

Consequencia: a recusa de `\n`, `\r` e byte de controle acontece **do nosso lado**, e o caso que a fixa prova que **nos recusamos** — nunca que o cliente descarta. Um caso escrito contra o comportamento do cliente teria passado e **codificado a conclusao falsa**, tornando-a permanente.

Byte UTF-8 cru e byte de controle passam sem escape (confirmado: `X-Arg-D='com\ttab-e-\x01controle'`).

## Perguntas em aberto, nao afirmadas

1. Regra de escape da Dropbox para `Dropbox-API-Arg` — depende de fonte externa.
2. Limite de tamanho de cabecalho — **nao medido**; a tentativa foi invalida.
3. Tag exata da recusa por `rev` divergente.

## Tres formas de o instrumento responder pergunta mais estreita que a feita

Apareceram todas nesta sessao, e sao a mesma coisa vista de angulos diferentes:

1. **Medir o status quando a pergunta e sobre bytes transmitidos.**
2. **Observar so onde se espera o efeito** — o probe filtrava `X-Arg*`, e cabecalho injetado por definicao tem outro nome. A ausencia observada era artefato do filtro.
3. **Ausencia de variacao onde se esperava transicao** — `exit 7` identico em quatro tamanhos era sinal de que nao havia servidor, nao de que nao havia limite. Limiar produz transicao; resultado uniforme na faixa inteira nao responde a pergunta.

A regra do conjunto vale para **instrumento de medicao**, e nao so para codigo: o probe enumerou o esperado, que e o oposto de enumerar. As oito ocorrencias anteriores da familia eram todas do lado do produto; esta e a primeira do lado da medicao.

**Sofisticacao sobre premissa nao verificada e mais perigosa que erro simples, porque convence.** O raciocinio construido sobre a premissa falsa ("descarte silencioso e pior que injecao") era bom, e foi a qualidade dele que o tornou dificil de duvidar.
