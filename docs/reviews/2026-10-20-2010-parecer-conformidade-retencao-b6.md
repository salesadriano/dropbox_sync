# Parecer de Conformidade — Retencao e rotacao de backup (fase 6)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: `dbx reter`/`retain`, rotacao de artefatos de backup com `--manter N` ou `--dias D`, exclusao para a lixeira so com `--confirmar` (F-10); porte **G**
- Agent responsavel pela alteracao e pela verificacao: Senior Developer (gate local, regra 14); validacao independente a cargo do QA Expert
- Data: 2026-10-20
- Ciclos: 5 (ciclo 1 inicial; ciclo 2 apos a reprovacao QA-B6-01/02 e OBS-1; ciclo 3 apos QA-B6-03/04; ciclo 4 apos QA-B6-05/06; ciclo 5 apos QA-B6-07/08)
- Branch / base: `feature/retencao-b6` sobre `develop` @ `d696c1d`, sem commit
- Log de prompt: [2026-10-20_2010_backlog-fase-6-retencao.md](../prompts/2026-10-20_2010_backlog-fase-6-retencao.md)
- Registro de entrega: [2026-10-20-2010-registro-retencao-b6.md](2026-10-20-2010-registro-retencao-b6.md)
- Tambem: [2026-10-20-2010-parecer-tdd-retencao-b6.md](2026-10-20-2010-parecer-tdd-retencao-b6.md)
- Transcricao fiel dos pareceres do Senior Developer por gate; as secoes comuns aos dois gates (arquivos, ciclos 2 a 5) aparecem nos dois arquivos.

## Transcricao

Worktree: `/home/sales/dropbox_api.worktrees/feature-retencao-b6` (base `d696c1d`, sem commit).
Requisitos: escopo v1.19 e v1.20, secao 5.14 (RF-93..100); decisoes: memoria `2026-10-20-2010-retencao` (DIV-130..147 no ciclo 1; DIV-148..170 ao longo dos ciclos); arquitetura: system design v1.14.

## Arquivos

| Arquivo | Natureza |
|---|---|
| `lib/retencao.sh` | novo, dominio puro: politica, carimbo `server_modified`, data HTTP, plano, minimo de 1, guarda por item; nos ciclos 2 a 5, chave de RF-54, caminho normalizado e canonico, marca combinante, UTF-8 e identidade |
| `commands/reter.sh` | novo (RF-93..99; `reter`, `retain`) |
| `lib/filtro.sh` | validacao unica do glob em `_dbx_filtro_validar_padrao` (filtros de caminho e nome avulso, RNF-36) |
| `lib/http.sh` | `DBX_HTTP_DATA` (cabecalho `Date`, DIV-134), aparado e limitado a 64 bytes |
| `lib/cli.sh` | tabela de comandos, alias `retain`, arquivo do comando |
| `bin/dbx`, `completions/dbx.bash`, `README.md`, `docs/testes/mapa-modulos.md` | RF-100 |

Testes novos: `tests/unit/retencao_test.sh` (27 no ciclo 1, 38 no ciclo 5) e `tests/integracao/reter_test.sh` (69 no ciclo 1, 84 no ciclo 5). Teste aprovado alterado so o TC-CPL-08, com autorizacao do solicitante (DIV-148).

## Gate 2 — protocolo-conformidade

**Parecer (ciclo 1): APROVADO com ressalvas** (CNF-01 e CNF-02 preexistentes, fora do diff, com o Tech Lead; CNF-03 depende de verificacao contra o servico real).

Escopo do diff e stack: shell (bash 4.4+) e cURL. Dois arquivos novos de producao (`lib/retencao.sh`, `commands/reter.sh`), seis alterados (`lib/filtro.sh`, `lib/http.sh`, `lib/cli.sh`, `bin/dbx`, `completions/dbx.bash`, `README.md`) e o mapa. `shellcheck lib/*.sh commands/*.sh bin/* scripts/*.sh`: 0 achados; testes novos com `shellcheck -x`: 0.

Arquitetura (clean-architecture adaptada ao projeto):

| Item | Verificacao |
|---|---|
| Dominio puro | `lib/retencao.sh` sem rede, disco, estado nem relogio (auditoria `rtg12_lib_retencao_nao_cita_rota_destrutiva_nem_rede`); depende so de `lib/errors`, `lib/path`, `lib/filtro` (dominio) |
| Ponto unico de rede | so `lib/http` invoca o cliente; o comando usa `dbx_auth_colecao`/`dbx_auth_requisitar` e `_dbx_cmd_escrita_remota` (ponto unico de escrita, silencioso e idempotente) |
| Ponto unico de caminho | `_dbx_cmd_caminho_remoto "$pasta" \|\| return $?` antes de qualquer rede (auditoria `composicao` verde) |
| Sem codigo gemeo (RNF-36) | glob de nome reusa `_dbx_filtro_validar_padrao`/`_dbx_filtro_compilar`; chave sem caixa de `dbx_filtro_chave`; nenhum segundo compilador |
| Contexto JSON | nome literal `reter_pagina` (RNF-24); corpo do transporte limpo depois da analise (DIV-95); `DBX_HTTP_DATA` aparado e limitado a 64 bytes |
| Saida | so por `lib/output`; nome e `path_display` por `dbx_cmd_campo_caminho` (escapado no texto, intacto no `--null`); avisos so em stderr |
| Sinal | acao registrada em `lib/tmp` (sem `trap` proprio, auditoria `tmp_test` verde) e cancelada no fim |
| Estado | nada em `lib/state`; sem trava (DIV-140); nenhum arquivo criado (TC-RTC-08) |
| Codigos | so a taxonomia 0..15 |

Achados:

| ID | Severidade | Achado | Regra |
|---|---|---|---|
| CNF-01 | Maior (preexistente, fora do diff) | `_dbx_cmd_escrita_remota` e `_dbx_cmd_consultar` (`lib/cmd`) classificam pela `DBX_HTTP_CLASSE`, que, quando a RENOVACAO do token falha, descreve a resposta do endpoint de token (400 -> `uso_invalido` 2) e nao o status devolvido (5). O `reter` contorna: `dbx_auth_preparar` antes de cada `delete_v2` e classe pelo status na listagem. DIV-151 | consistencia da taxonomia (RF-35) |
| CNF-02 | Maior (preexistente, fora do diff) | `dbx_http_colecao` acrescenta `limit` tambem no `list_folder/continue` usado por `lib/sync`, `commands/list` e `dbx_cmd_listar_nivel`; `ListFolderContinueArg` so tem `cursor` (`files.stone`). O `reter` manda so o cursor no continue. DIV-150 | contrato externo |
| CNF-03 | Menor | Tag exata da recusa por `parent_rev` divergente nao existe no `files.stone`; tratamento por `*conflict*` -> `conflito`, demais -> falha do item com a classe; nunca repete sem `parent_rev`. Conferir contra o servico real (DIV-149) | contrato externo |

Nota do registro: o Tech Lead aceitou a DIV-149 (risco RSK-67) e mandou a DIV-150 e a DIV-151 ao backlog como F-40 e F-41 (funcionalidades-candidatas v0.12).

## Ciclo 2 (QA-B6-01, QA-B6-02, OBS-1; DIV-158 a DIV-160)

A suite do QA `tests/integracao/qa_retencao_b6_test.sh` e os testes aprovados nao foram alterados (sha256 `21fc8c1f...`).

| Achado | Correcao | Marca do mutante |
|---|---|---|
| QA-B6-01 (P0), DIV-158 | Tres barreiras independentes: `_dbx_cmd_reter_inedito` (`commands/reter.sh`): `path_lower` repetido, caixa ASCII dobrada, qualquer pagina e qualquer `.tag`, sai 10 e zero `delete_v2`; `_dbx_retencao_caminhos_unicos` (`lib/retencao.sh`): o plano recusa caminho repetido; guarda por item, condicao (7) nova: recusa quando o caminho de quem sai e igual ao de algum que fica, por caminho e nao por indice (o comando passa o vetor dos `path_lower` que ficam) | `duplicado`, `unico`, `fica` |
| QA-B6-02 (P1), DIV-159 | `_dbx_cmd_reter_normalizado` recusa `name` `.`/`..` e `path_lower` com `//`, segmento `.`/`..` ou barra final, ja na conferencia da listagem: 10 e zero `delete_v2` | `normalizado` |
| OBS-1, DIV-160 | o `Date` vem da ULTIMA pagina; o "agora" e lido logo depois dela | `data` |

- **Red** (`red-qa1.log`): os casos novos de DIV-158/159/160 e os do QA `qa_s01`, `qa_s02` e `qa_s03` deram `not ok` antes do codigo. O primeiro red de DIV-160 estava contaminado por um defeito do duble (campo vazio na regra colapsava com IFS tab); a regra passou a usar `-`, e o red ficou provado pelo mutante que le so a primeira pagina, que e o comportamento anterior.
- **Green** (`green-qa1.log`): `qa_retencao_b6` 41/41; `reter` 76/76; `retencao` 71/71 (`retencao_test` 30 e `qa_retencao_b6` 41); `json`, `composicao` e `tmp_test` aprovados; shellcheck 0; `verificar-remocao-de-casos` 1557 -> 1557.

Mutantes (todos pegos):

| Correcao | Mutante e resultado | Caso |
|---|---|---|
| DIV-158 | So a conferencia da listagem removida: o plano segura (10) | `div158_mutantes_das_tres_barreiras` |
| DIV-158 | Listagem e plano removidos: a guarda por caminho segura (zero delete do que fica) | idem |
| DIV-158 | As tres removidas: o registro acusa o `delete_v2` do que fica | idem |
| DIV-158 | Cada barreira da lib removida isoladamente | `div158_mutantes_da_lib_reprovam` (unidade) |
| DIV-159 | Conferencia de normalizacao removida | `div159_mutante_sem_a_conferencia_de_normalizacao_reprova` |
| DIV-160 | `Date` lido so da primeira pagina | `div160_mutante_que_le_so_a_primeira_pagina_reprova` |

Caso novo `marcas_de_mutacao_existem`: garante que toda linha marcada usada pelos mutantes existe (a recusa de `_copia_mutante` dentro de substituicao de comando nao reprovava o caso).

## Ciclo 3 (QA-B6-03, QA-B6-04; DIV-161 a DIV-163)

Suite do QA intacta (sha256 `08cc0440...`).

Custo da DIV-161, medido em `medir_chave.sh` com o `lower()` do Python 3.14 (Unicode 16.0) como aproximacao do `path_lower` da Dropbox, sobre 154.903 pontos de codigo atribuidos fora do ASCII: a chave do produto (`${s,,}` sob `C.UTF-8`, glibc 2.43) devolve o proprio `s` em todos, **zero falsos 10** com `C.UTF-8` disponivel (inclui `ß`, `İ`, `ς` e as digrafas titulo). Custo residual nao mensuravel aqui: tabela Unicode da Dropbox diferente da glibc, e qualquer entrada fora do ASCII sem `C.UTF-8` sai 10 (falha fechada por decisao). NFC e NFD nao entram na chave.

| Achado | Correcao | Marca do mutante |
|---|---|---|
| QA-B6-03 (P0), DIV-161 | `dbx_retencao_chave`: chave de RF-54 pela funcao unica `dbx_filtro_chave`; sem a localidade, texto fora do ASCII nao tem chave (status 1). Usada na unicidade do plano (`_dbx_retencao_caminhos_unicos`), na guarda (7) (`_dbx_retencao_fora_dos_que_ficam`) e na unicidade da listagem (`_dbx_cmd_reter_inedito`). `_dbx_cmd_reter_minusculo`: em toda entrada, `path_lower` diferente da propria chave, ou sem chave, sai 10 sem delete | `unicode`, `localidade`, `minusculo` |
| QA-B6-04 (P1), DIV-162 | a guarda (7) recusa sem o argumento, com nome invalido ou inexistente, com variavel que nao e vetor e com vetor vazio | `lista` |

- **Red** (`red-qa2.log`): os 7 casos novos e `qa_s15`, `qa_s17` e `qa_s18` deram `not ok`.
- **Green** (`green-qa2.log`): `reter` 78/78; `retencao_test` 34/34; `json`, `composicao`, `tmp_test` aprovados; shellcheck 0; `verificar-remocao-de-casos` 1557 -> 1557.
- Mutantes pegos: sem a exigencia de minuscula (o `path_lower` `/bk/É.tar` passava e era apagado); sem a conferencia da localidade; minuscula removida e chave trocada para a dobra so ASCII (a duplicata `é`/`É` apagava o que fica); na unidade, dobra so ASCII na guarda, sem a localidade e sem a recusa da lista ausente (`div161_div162_mutantes_da_lib_reprovam`). `marcas_de_mutacao_existem` cobre as marcas novas.
- Testes desta fase ajustados (do developer, nao aprovados): `_guarda` e `_guarda_do_primeiro` de `retencao_test.sh` passam a lista de quem fica.
- **Conflito na suite do QA (DIV-163):** `qa_s11_guarda_por_item_recusa_cada_condicao` chamava a guarda com 7 argumentos, sem a lista, e esperava 0, o que a DIV-162 (`qa_s18`) proibe. Caso a caso: 47 de 48. Decisao do Tech Lead: o QA passa a lista nas linhas de `qa_s11`.

## Ciclo 4 (QA-B6-05, QA-B6-06; DIV-164 a DIV-166)

Suite do QA intacta (sha256 `d4ca76fe...`).

`lib/retencao.sh` ganhou funcoes de conferencia unicas, usadas pelo comando e pela guarda: `dbx_retencao_caminho_normalizado` (a regra da DIV-159, movida de `commands/reter.sh` para a lib, sem duplicacao); `dbx_retencao_sem_combinante` (detecta por bytes UTF-8, sob `LC_ALL=C`, os cinco blocos de marca combinante, sem depender da localidade); `dbx_retencao_caminho_canonico` (normalizado, sem marca combinante e igual a sua chave de RF-54).

| Achado | Correcao | Marca do mutante |
|---|---|---|
| QA-B6-05 (P0), DIV-164 | listagem: toda entrada com marca combinante sai 10 sem delete (`_dbx_cmd_reter_composto`); guarda: recusa marca combinante em quem sai e, em quem fica, pela verificacao de caminho canonico | `combinante`, `combinante_guarda` |
| QA-B6-06 (P1), DIV-165 | cada elemento da lista de quem fica passa por `dbx_retencao_caminho_canonico`: vazio, relativo, com `//`, `.`, barra final, maiuscula ou NFD e recusado | `formato` |

- **Red** (`red-qa3.log`): os 5 casos novos e `qa_s22`/`qa_s23` deram `not ok`.
- **Green** (`green-qa3.log`): `reter` 80/80; `retencao_test` 36/36; `json`, `composicao`, `tmp_test` aprovados; shellcheck 0; `verificar-remocao-de-casos` 1557 -> 1557.
- Mutantes pegos: sem a conferencia na listagem (a guarda ainda segura o NFD que sai; a pasta nao candidata com marca passa, pego); sem a listagem e sem a guarda (o NFD do mesmo arquivo e apagado, pego); na unidade, sem a conferencia de formato da lista e sem a de marca combinante na guarda.
- **Conflitos na suite do QA (DIV-166):** `qa_s09_nfc_nao_casa_nfd` (NFD esperava 0 com "nada casa") e `qa_s20_minusculas_unicode_legitimas_sem_falso_10` (usava `i̇`) contradiziam a regra larga da DIV-164. Caso a caso: 51 de 53. Decisao do Tech Lead: o QA ajusta os dois para esperar 10 com zero `delete_v2`, ou troca o exemplo, sem enfraquecer o que cada caso prova.

## Ciclo 5 (QA-B6-07, QA-B6-08; DIV-167 a DIV-169)

Suite do QA intacta (sha256 `bb17b865...`).

Contrato (`files.stone`, ramo `main`): `struct FileMetadata` tem `id Id`, obrigatorio, com `alias Id = String(min_length=1)` ("A unique identifier for the file"); `rev Rev` tambem e obrigatorio. Sem divergencia.

| Achado | Correcao | Marca do mutante |
|---|---|---|
| QA-B6-07 (P0), DIV-167, listagem | `_dbx_cmd_reter_identidade`: todo ARQUIVO da listagem precisa de `id` textual nao vazio e `rev` no formato `Rev`, inclusive o que esta fora do padrao; `id` ou `rev` repetido entre arquivos, em qualquer pagina, sai 10 sem delete. Vale so para `.tag file`; pasta e apagado seguem como antes | `identidade` |
| QA-B6-07 (P0), DIV-167, guarda (7) | `_dbx_retencao_identidade_fora`: recebe o `rev` (o `parent_rev`) e o `id` de quem sai e os vetores de `rev` e `id` de quem fica, por nome; recusa quando ha coincidencia. Falha fechada: recusa tambem com `rev` ou `id` vazio, vetor ausente, inexistente, que nao e vetor ou vazio, elemento vazio, ou tamanho diferente do da lista de caminhos. Assinatura nova: `dbx_retencao_guarda <tag> <path_lower> <name> <pasta> <raiz> <acao> <e_primeiro> <vetor_ficam> <rev> <id> <vetor_revs> <vetor_ids>` | `identidade_guarda` |
| QA-B6-08 (P1), DIV-168 | `dbx_retencao_utf8_valido` e `_dbx_cmd_reter_utf8`: UTF-8 valido por bytes (RFC 3629, sob `LC_ALL=C`) no `name` e no `path_lower` de toda entrada; recusa overlong (C0, C1, E0 80-9F, F0 80-8F), surrogate (ED A0-BF), acima de U+10FFFF (F4 90+, F5-FF), 5 e 6 bytes, truncado e continuacao solta; o invalido sai 10 sem delete | `utf8` |

As barreiras por grafia (chave, combinante, normalizacao) seguem como defesa adicional.

- **Red** (`red-qa4.log`): os 6 casos novos e `qa_s25` e `qa_s26` deram `not ok`. `div168_mutante_sem_a_validacao_reprova` saiu `ok` vacuo no red, porque a marca ainda nao existia.
- **Green** (`green-qa4.log`): `reter` 84/84; `retencao_test` 38/38; `json`, `composicao`, `tmp_test` aprovados; shellcheck 0; `verificar-remocao-de-casos` 1557 -> 1557.

Mutantes (todos pegos):

| Mutante | Resultado |
|---|---|
| Sem a unicidade de `id`/`rev` na listagem | **a guarda (7) segura sozinha**: a copia NFD de kana com o mesmo `rev` e o arquivo com o mesmo `id` dao zero delete e 10 |
| Sem a listagem e sem a guarda | o delete da copia aparece |
| Unidade: sem a comparacao de `rev`/`id` na guarda | pego (`div167_guarda_por_rev_e_id_e_mutante`) |
| Sem a validacao de UTF-8 | as formas invalidas passam (pego) |

Os mutantes em camadas dos ciclos 2 a 4 (por grafia) agora removem tambem as barreiras de `id`/`rev` no passo "sem nenhuma barreira"; sem isso, a barreira estrutural seguraria o caso e o mutante pareceria nao pego.

Testes desta fase ajustados (do developer, nao aprovados): entradas montadas a mao ganharam `id` (`rtp04`, `rtp05`, `rto03`, `_qa159`, `_qa161`); `rev` repetido por acaso com o `CINCO` trocado em `_qa159` e `_qa161`; as chamadas da guarda em `retencao_test` passam `rev` e `id` alheios ao item (`_ids_teste`); o mutante da lista ausente tira tambem `identidade_guarda`.

**Conflitos na suite do QA (DIV-169):** caso a caso, 49 de 57. Oito casos decorrem da DIV-167: `qa_s07`, `qa_s08`, `qa_p01` e `qa_s20` montavam a massa com `id`/`rev` repetidos entre arquivos distintos (`_qa_arq` gerava `id:<rev>`); `qa_s11`, `qa_s17`, `qa_s22` e `qa_s27` chamavam a guarda sem as listas de `rev`/`id` onde o controle espera aprovacao. Decisao do Tech Lead: o QA usa `rev`/`id` unicos por arquivo e passa `rev`/`id` alheios ao item nas chamadas diretas. No ciclo 5 do QA, os 60 casos passaram.

Conformidade nos ciclos 2 a 5 (vereditos do developer apos cada ciclo):

- Ciclo 2: o dominio continua puro; a guarda ganhou a condicao (7), com o parametro `vetor_ficam`, que o unico chamador sempre passa (a falha aberta sem ele foi o QA-B6-04, fechada no ciclo 3).
- Ciclo 3: a chave de caminho tem fonte unica (`dbx_filtro_chave`), sem codigo gemeo; a comparacao com a pasta pedida (`dbx_retencao_pai_igual`) continua ASCII com falha fechada (DIV-137).
- Ciclo 4: as regras de caminho tem fonte unica em `lib/retencao` (a normalizacao saiu de `commands/reter.sh`); a deteccao de marca combinante nao depende da localidade.
- Ciclo 5: barreira estrutural por identidade, independente da grafia, conforme a especificacao; validacao de UTF-8 sem depender da localidade.

Parecer gate 2 (protocolo-conformidade): APROVADO com ressalvas nos ciclos 1 a 5. CNF-01 a CNF-03 inalteradas e decididas pelo Tech Lead (F-41, F-40, RSK-67). A guarda continua sem estado local: toda autorizacao vem da listagem da mesma execucao; `lib/retencao` segue puro; nenhuma captura nova de bytes externos em `lib/`.
