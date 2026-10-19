# Historico dos comentarios de `lib/http.sh` e `lib/transfer.sh`

- **Data:** 2026-10-19
- **Demanda:** `docs-e-aliases-p4` (fase 4)
- **Decisao:** do solicitante, memoria `2026-10-19-0829-aliases-poda-e-comentarios` — os comentarios de `lib/http.sh` e `lib/transfer.sh` ficam so com o porque atual; o historico vem para este registro.
- **Prompt:** [docs/prompts/2026-10-19_0829_docs-e-aliases-p4.md](../prompts/2026-10-19_0829_docs-e-aliases-p4.md)

Este registro transcreve, por funcao, o que saiu dos comentarios: historico de defeitos, medicoes e narrativas. Nenhuma linha de codigo mudou junto com a poda. O texto abaixo descreve o estado e as medicoes da epoca em que cada comentario foi escrito; quando ele cita "antes" ou "a versao anterior", e em relacao aquele momento.

---

## lib/http.sh — cabecalho do arquivo

- **RSK-23.** O cabecalho dizia "nao ha estado local persistente". Desde a fase 3 existem a memoria do `sync` e a do `upload` em `lib/state` (RF-38, RF-61, RNF-26), e a frase passou a contradizer o codigo (RNF-34(a), achado P5.1). O comentario agora diz que `lib/http` nao persiste nada e que todo estado persistente passa so por `lib/state`.

## lib/http.sh — constantes de limite

- **`DBX_HTTP_LIMITE_MAXIMO` (RNF-23).** O teto de entrada de `lib/json` e 256 KiB, o que comporta cerca de 537 entradas tipicas de listagem; uma listagem sem limite pode devolver 2.000 entradas, quase quatro vezes o teto. Cem entradas dao cerca de 49 KiB por pagina.
- **`DBX_HTTP_LIMITE_CABECALHO`.** Medido contra o cliente: valor de cabecalho integro ate cerca de 100.000 bytes, truncagem silenciosa a partir dai e descarte em 1.000.000 — os tres casos sem aviso do cliente. 8 KiB fica uma ordem de grandeza abaixo da primeira falha observada.

## lib/http.sh — `DBX_HTTP_TRATADOR_EXTERNO`

- Antes deste canal (fase 2, RNF-31), um sinal recebido com os tratadores internos armados (`lib/cmd` no recebimento, `lib/transfer` na sessao) deixava para tras a area de quem os chamou, e o `trap -` do fim deles desarmava o tratador de fora.

## lib/http.sh — `dbx_http_sinais_devolver`

- A funcao e o "salvar e restaurar" que o `trap -` de `lib/transfer` e de `lib/cmd` declarava como pendente antes da fase 2.

## lib/http.sh — `_dbx_http_correlacao_de`

- Uma versao anterior parava a leitura no identificador de correlacao e perdia todo cabecalho que viesse depois dele (inclusive `Retry-After`).
- A regra de aparar so as pontas do `Retry-After` (espaco interno invalida o valor) veio do achado `QA-P2-03`.
- "O primeiro identificador vence" ja era o comportamento antes da leitura completa dos cabecalhos.

## lib/http.sh — `_dbx_http_opcoes`

- O escape de aspas e barras no `Dropbox-API-Arg` do modo de conteudo faltava: medido, `{"path":"/a.txt"}` chegava ao servidor como `{`, porque a aspa crua encerrava a cadeia no arquivo de configuracao do cliente e o resto era descartado em silencio. O mesmo escape ja existia no modo formulario — a disciplina existia no gemeo e nao ali.

## lib/http.sh — `dbx_http_cabecalho_valido`

- Medido contra o cliente real: um valor com `\n` ou `\r\n` NAO e descartado — o cliente transmite, o servidor interpreta o que vem depois da quebra como cabecalho proprio, e o cliente sai com status 0 sem aviso.
- Por isso a garantia nao pode ser "o cliente sanitiza": um caso escrito contra o comportamento do cliente teria passado e codificado a conclusao falsa.

## lib/http.sh — `_dbx_http_conduzir`

- **Saida padrao em fluxo (RF-32(b), F-28).** Com o cliente escrevendo em `/dev/stdout` dentro da substituicao que captura o codigo HTTP, o conteudo saia colado ao codigo, o codigo deixava de ser numero e o recebimento virava falha de rede. A correcao duplicou a saida padrao do processo antes da captura.
- **Stderr dentro da substituicao.** Na primeira versao a redirecao do stderr ficava fora da substituicao: o canal `DBX_HTTP_DIAGNOSTICO` existia e chegava sempre vazio.
- **`--fail` no canal de fluxo.** Medido: sem ele, um 409 sai pela saida padrao com status ZERO — um erro que se parece com exito, com nome de arquivo correto e um JSON dentro. Com ele, zero bytes emitidos e status 22. Tratar o 22 como falha de rede mandaria o operador investigar DNS e TLS diante de um 404 perfeitamente informativo.
- **Defeito do programa como problema de rede.** Antes, qualquer status nao zero do cliente virava `codigo=0` e era classificado como falha de rede; opcao mal formada ou arquivo de corpo ilegivel — defeitos do proprio programa — chegavam ao operador como "verifique conectividade, DNS, proxy e TLS". O stderr do cliente era descartado: pedir `show-error` e jogar a mensagem fora era pedir diagnostico para nao le-lo. Dai a lista de status 2, 3, 26 e 43 como `DBX_HTTP_DEFEITO_CLIENTE`.
- **Leitura do corpo.** A leitura byte a byte evita a substituicao de comando que removeria quebras finais. A auditoria estatica nao alcanca este caso (o utilitario de copia nao tem prefixo do projeto), mas a classe de defeito e a mesma de D1, C2-01 e E2-04. O limite de canal textual foi escrito antes de existir o `download`, que passou a usar o canal de fluxo.
- **Taxonomia.** Reimplementar a decisao de retentativa por codigo HTTP foi defeito real, em que classe e politica se contradiziam. Na fase 3 (P3.4) a consulta passou a ser por variavel: antes eram dois subshells (tres, com o da politica por dentro) a cada tentativa de cada requisicao, e duas chamadas para o codigo de saida no fim, uma delas em subshell.
- **Erro de escrita 23 na saida padrao.** A classificacao entre `consumidor_encerrou` (cano ou FIFO) e `configuracao` (arquivo ou dispositivo) veio de RF-32, `OBS-01` e `QA-P2-05`.
- **Retentativa no canal de fluxo.** Medido contra o cliente real: sob `--fail`, uma recusa HTTP emite zero bytes (status 22), e conexao recusada tambem (status 7).

## lib/transfer.sh — cabecalho do arquivo

- **Tamanho de parte fixo (lacuna de RF-08).** RF-08 pede tamanho de parte configuravel; a entrega nao o tornou configuravel. Uma divergencia de `content_hash` causada por parte diferente do bloco so apareceria na comparacao com o servico, e tornar o valor configuravel sem separar as duas nocoes quebraria a cadeia em silencio, "a pior forma de errar". Trabalho futuro declarado: separar `parte de rede` de `bloco de resumo`, permitindo parte multipla do bloco, e so entao expor o valor.
- **Leitura sem cano.** O motivo foi medido em `lib/hash`: por cano, EIO, truncamento sob leitura ou produtor morto no meio produziam resumo bem formado de conteudo incompleto com status 0.
- **Produtor que morre no meio (RSK-36).** Medido: com um produtor que escreve 5.000.000 bytes e sai com status 3, o comando publica os 5.000.000 bytes e sai com ZERO. Com `set -o pipefail` no shell do operador, o encadeamento devolve 3 — a falha reaparece do lado de quem tem a informacao. Por isso a recomendacao ao operador, e nao uma promessa que o componente nao pode cumprir.
- **`content_hash` por parte.** Errar a interpretacao do campo por chamada (resumo da parte, do acumulado ou do arquivo final) quebraria todo envio em partes de um jeito que a suite nao apanha, porque o duplo aceita qualquer valor. Melhoria futura declarada: enviar por parte depois de verificar o campo contra o servico real.

## lib/transfer.sh — `DBX_TRANSFER_AREA_TEMP`

- Variavel local na acao do `trap` ja foi defeito corrigido em `lib/hash` e em `lib/http`: a expansao virava vazia e a limpeza nao removia nada. O comentario registrava que ele voltaria aqui se a disciplina fosse reescrita em vez de reusada.

## lib/transfer.sh — estado da retomada (RF-58)

- "F-03 continua fora de escopo": a retomada entre execucoes nao existe.

## lib/transfer.sh — `_dbx_transfer_falhar`

- A forma `return "$(...)"` e o defeito C2-01, ja pago duas vezes no projeto.

## lib/transfer.sh — `_dbx_transfer_ler_campo`

- A restauracao do contexto pelo canal `DBX_JSON_CONTEXTO_ANTERIOR`, e nao por copia local, nao e estilo: a auditoria de procedencia de contexto so aceita nome literal ou este canal porque um nome vindo de variavel qualquer poderia ter procedencia externa, e nome de contexto derivado de dado remoto faz dois corpos de erro colidirem no mesmo contexto, destruindo o primeiro. Guardar numa local escaparia da auditoria sem mudar o risco.

## lib/transfer.sh — `_dbx_transfer_deslocamento_correto`

- A razao das duas formas aceitas "esta escrita porque nao foi medida": a serializacao da carga de uniao nao foi verificada contra o servico. Aceitar as duas formas nao cria risco.

## lib/transfer.sh — `_dbx_transfer_interrompida`

- **Paliativo declarado.** Desde a fase 2 a remocao da area de `lib/http` e feita por `dbx_http_interrompido`, do proprio `lib/http`, e a disciplina "quem enche o canal o esvazia" deixou de ser violada em `lib/transfer`. O que continua paliativo e o arranjo entre os ciclos de vida.
- **O defeito original.** `lib/http` remove a propria area quando `_dbx_http_executar` retorna, e so entao; esta funcao faz `exit`. Sem a remocao, uma interrupcao no meio de um `append` deixava `dbx-http.XXXX/{erro_cliente,cabecalhos,resposta}` em `$TMPDIR`, com corpo do usuario dentro.
- **Por que nao a correcao obvia.** Fazer `lib/http` armar `EXIT INT TERM HUP` resolveria a limpeza dele e quebraria a da sessao: `trap` e global ao shell, e `dbx_transfer_sessao` ja arma `EXIT` para remover a propria area — o segundo `trap` atropelaria o primeiro, trocando um vazamento por uma regressao de limpeza.
- **Correcao estrutural.** O componente `lib/tmp`, dono unico de area temporaria, esta no backlog. Enquanto ele nao existir, tres componentes criam area sob `$TMPDIR` com tres ciclos de vida diferentes.
- **Recorte que permanece** (declarado pelo caso de teste): sinal fora da janela do tratador — antes do `trap`, depois do `trap -`, ou durante um `upload` por requisicao unica — continua vazando pela area de `lib/http`. Pendencia aberta.

## lib/transfer.sh — `_dbx_transfer_emitir`

- O prejuizo de um comando da cadeia de autenticacao ler a entrada padrao seria silencioso: o arquivo remoto sairia menor, com resumo coerente com o que sobrou.

## lib/transfer.sh — `_dbx_transfer_anexar`

- **Contrato e reconciliacao.** O contrato documentado confirma o desenho — `incorrect_offset` e descrito exatamente como o caso da resposta perdida —, mas o desenho nao depende dessa confirmacao.
- **Dois donos da regra.** A versao anterior decidia de novo, com glob de substring (`*incorrect_offset*`), e a regra passou a ter dois donos que ja divergiam. Medido com `error_summary=path/conflict/incorrect_offset_like`: a taxonomia dava classe `conflito`, politica `nenhuma`; `lib/transfer` entrava no ramo de deslocamento e abortava "por deslocamento incorreto". Falha fechada nos dois, mas com diagnostico errado: mandava investigar deslocamento diante de um conflito de caminho. Familia de gemeos que o projeto ja tinha pago oito vezes. A regra passou a ter um dono so: a taxonomia, que casa prefixo em fronteira de componente (`_dbx_errors_prefixo_casa`) e remove qualificadores de uniao um a um.
- **`reiniciar`.** Antes caia no ramo generico: falha fechada, sem dizer que a causa era invalidacao da sessao.

## lib/transfer.sh — `_dbx_transfer_validar_retomada`

- A faixa valida do `correct_offset` foi decisao do Tech Lead no ciclo 2 da fase 2.

## lib/transfer.sh — `dbx_transfer_sessao`

- **Um laco so.** Dois lacos — um para fluxo, outro para arquivo — seriam a nona ocorrencia da familia de gemeos.
- **RF-15, segunda linha de defesa.** A guarda nao e duplicacao da regra de simulacao: e recusa de executar sem ela, para o chamador futuro que esquecer.
- **`umask`.** Medido antes da correcao: `0022` na entrada e `0077` na saida — a mascara ficava endurecida para o chamador. Nenhum consumidor da epoca observava a diferenca, e o valor deixado era o mais restritivo; ainda assim era a forma exata da familia de gemeos ja paga oito vezes: `lib/config.sh` fazia o par salvar/restaurar (`mascara_anterior`) e o irmao novo nao fazia.

## lib/transfer.sh — `_dbx_transfer_conduzir`

- **Canal do identificador de sessao.** O identificador nao e credencial, mas a disciplina nao e "so limpe o que for segredo"; ela so vale se nao tiver excecoes negociadas caso a caso.
- **Tentativas por parte.** O contador de retomadas que zera so quando o confirmado passa do maior ja visto veio do achado `QA-P2-01`.

## lib/transfer.sh — `dbx_transfer_objeto_de_publicacao`

- Montar o objeto em cada comando faria a proxima correcao em `mode` ou em `client_modified` valer para um caminho so, com o sintoma — metadado diferente conforme o comando — longe da causa.
