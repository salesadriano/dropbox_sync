# Defeito em producao: arquivo remoto com o nome de uma pasta local encerra o sync (`path/not_folder`)

**Branch:** `feature/arquivo-remoto-no-lugar-da-pasta` (de `origin/develop` @ `6c29d28`)
**Porte:** M. `sh scripts/porte.sh` (sem diff na abertura): `porte: P`; classificado M pelos gatilhos nao mensuraveis: defeito critico em producao (o `sync --espelhar` nao termina) e tratamento de erro da enumeracao remota, mesmo criterio das demandas `ignorar-cdpath` e `diretorio-chamado-hifen`.
**Issues:** nenhuma.
**PRs abertas no inicio:** nenhuma.

## Prompt 1 — 2026-11-03 10:17

> in prod on run  nohup dbx --debug sync -p --enviar --origem /mnt/c/Unimake/UniNFe/. --destino /ASJ/ASJASS/UniNFe --espelhar --confirmar i recive
>
> ```
> [sync] consultando remoto: obtendo proxima pagina (pagina 2)...
> debug: http POST api.dropboxapi.com/2/files/list_folder/continue tentativa=1 status=200 duracao_ms=1216 enviados=379 recebidos=64387
> [sync] consultando remoto: obtendo proxima pagina (pagina 3)...
> debug: http POST api.dropboxapi.com/2/files/list_folder/continue tentativa=1 status=200 duracao_ms=989 enviados=379 recebidos=4506
> debug: http POST api.dropboxapi.com/2/files/list_folder tentativa=1 status=200 duracao_ms=1264 enviados=97 recebidos=63837
> [sync] consultando remoto: obtendo proxima pagina (pagina 2)...
> debug: http POST api.dropboxapi.com/2/files/list_folder/continue tentativa=1 status=200 duracao_ms=1118 enviados=379 recebidos=49022
> debug: http POST api.dropboxapi.com/2/files/list_folder tentativa=1 status=200 duracao_ms=1228 enviados=97 recebidos=63527
> [sync] consultando remoto: obtendo proxima pagina (pagina 2)...
> debug: http POST api.dropboxapi.com/2/files/list_folder/continue tentativa=1 status=200 duracao_ms=1343 enviados=379 recebidos=63336
> [sync] consultando remoto: obtendo proxima pagina (pagina 3)...
> debug: http POST api.dropboxapi.com/2/files/list_folder/continue tentativa=1 status=200 duracao_ms=1032 enviados=379 recebidos=26349
> debug: http POST api.dropboxapi.com/2/files/list_folder tentativa=1 status=200 duracao_ms=2276 enviados=97 recebidos=63355
> [sync] consultando remoto: obtendo proxima pagina (pagina 2)...
> debug: http POST api.dropboxapi.com/2/files/list_folder/continue tentativa=1 status=200 duracao_ms=1231 enviados=379 recebidos=63312
> [sync] consultando remoto: obtendo proxima pagina (pagina 3)...
> debug: http POST api.dropboxapi.com/2/files/list_folder/continue tentativa=1 status=200 duracao_ms=1011 enviados=379 recebidos=23652
> debug: http POST api.dropboxapi.com/2/files/list_folder tentativa=1 status=409 duracao_ms=747 enviados=97 recebidos=89
> erro=enumeracao remota recusada: path/not_folder/
> debug: resumo comando=sync chamadas=27 tentativas_extras=0 limites_429=0 enviados=6213 recebidos=1047871 duracao_ms=3434038 saida=2
> root@frwASJAB:/usr/home/suporte #
> ```

Sanitizado: nenhum segredo no log; caminhos de origem e destino mantidos (necessarios a analise, sem dado pessoal).

**Intencao principal:** corrigir o erro do `sync --enviar --espelhar` em producao (2.3.2) que encerra a execucao com `saida=2` na enumeracao remota do primeiro ciclo.

**Causa (Tech Lead, localizada no codigo):** no `sync` em ciclos (`RF-189`), cada diretorio local do ciclo e listado no destino por `list_folder` nao recursivo (`dbx_sync_listar_diretorio`, `lib/sync.sh`). Quando o caminho remoto com o nome dessa pasta e um **arquivo**, a Dropbox responde `409 path/not_folder` ("o caminho dado e um arquivo, nao uma pasta"). `_dbx_sync_listar_paginas` so tolera `path/not_found` (pasta ainda inexistente = lista vazia); qualquer outro erro vira `enumeracao remota recusada` e, por `RF-193`, o ciclo 1 encerra o `sync` com o codigo da classe (`not_folder` -> `uso_invalido` = 2). O arquivo que ocupa o nome da pasta nao e apagado porque a exclusao so roda ao fim do ciclo que terminou de ler. A mensagem de erro tampouco diz QUAL caminho remoto foi recusado.

**Contorno imediato:** na Dropbox, apagar ou renomear o arquivo que tem o mesmo nome de uma das subpastas de `/mnt/c/Unimake/UniNFe` (a 7a pasta na ordem da travessia, contando a raiz); `dbx listar /ASJ/ASJASS/UniNFe` mostra os arquivos diretos da raiz remota para a comparacao.

**Inferencias adotadas:** (a) na listagem de um subdiretorio do ciclo, `path/not_folder` passa a valer como pasta remota vazia, com aviso em stderr nomeando o caminho; sob `--espelhar` o arquivo homonimo ja e orfao pela regra existente (`RF-47`: so no destino) e e apagado ao fim do ciclo em que o pai foi lido; os envios para dentro da pasta nesse mesmo ciclo podem falhar por item (`path/conflict/file`) e completam na execucao seguinte; (b) na raiz do destino, `not_folder` continua falha (destino e um arquivo), com mensagem propria; (c) toda recusa de enumeracao passa a nomear o caminho remoto.

## Andamento — 2026-11-03

Correcao em `047cbd3`; validacao independente do QA aprovada (suite `qa_pasta_ocupada_test.sh`, 6 casos, sha256 `d7cd09d4127d25750aa9b10acda60bbc465846a079599688e34babd368d754eb`), aguardando o aceite do solicitante (regra 12).

## Prompt 2 — 2026-11-03

> accept the sha and fix the legacy line too

**Decisao do solicitante:** aceite da suite do QA `tests/integracao/qa_pasta_ocupada_test.sh` (sha256 `d7cd09d4127d25750aa9b10acda60bbc465846a079599688e34babd368d754eb`), regra 12; entrada de memoria `2026-11-03-1017-aceite-testes-qa-arquivo-remoto-no-lugar-da-pasta`. A correcao entra tambem na linha legada `support/bash-4.2`, como nas demandas `ignorar-cdpath` e `diretorio-chamado-hifen`: branch `feature/arquivo-remoto-no-lugar-da-pasta-bash42` sobre `origin/support/bash-4.2` por cherry-pick dos commits da principal. Push e PR #86 feitos pelo solicitante (o hook de push avalia o checkout principal).
