# Parecer de Evidencias de Testes (TDD) — Retencao e rotacao de backup (fase 6)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: `dbx reter`/`retain`, rotacao de artefatos de backup com `--manter N` ou `--dias D`, exclusao para a lixeira so com `--confirmar` (F-10); porte **G**
- Agent responsavel pela alteracao e pela verificacao: Senior Developer (gate local, regra 14); validacao independente a cargo do QA Expert
- Data: 2026-10-20
- Ciclos: 5 (ciclo 1 inicial; ciclo 2 apos a reprovacao QA-B6-01/02 e OBS-1; ciclo 3 apos QA-B6-03/04; ciclo 4 apos QA-B6-05/06; ciclo 5 apos QA-B6-07/08). No parecer original, os ciclos 2 a 5 vem nas secoes 3 a 6, com o titulo do ciclo do QA que os motivou; aqui os titulos seguem a numeracao do developer.
- Branch / base: `feature/retencao-b6` sobre `develop` @ `d696c1d`, sem commit
- Log de prompt: [2026-10-20_2010_backlog-fase-6-retencao.md](../prompts/2026-10-20_2010_backlog-fase-6-retencao.md)
- Registro de entrega: [2026-10-20-2010-registro-retencao-b6.md](2026-10-20-2010-registro-retencao-b6.md)
- Parecer de conformidade: [2026-10-20-2010-parecer-conformidade-retencao-b6.md](2026-10-20-2010-parecer-conformidade-retencao-b6.md)
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

Testes novos (no ciclo 1; o unico teste aprovado alterado e o TC-CPL-08, depois da autorizacao do solicitante, DIV-148):

| Arquivo | Casos (ciclo 1 -> ciclo 5) | Cobre |
|---|---|---|
| `tests/unit/retencao_test.sh` | 27 -> 38 | politica, carimbo, data HTTP, guarda, glob de nome, com relogio fixado; propriedade sobre 200 listagens geradas (semente fixa); nos ciclos 2 a 5, chave, caminho canonico, marca combinante, UTF-8, identidade e mutantes da lib |
| `tests/integracao/reter_test.sh` | 69 -> 84 | ponta a ponta pelo `bin/dbx`: confirmacao, `--dry-run`, selecao, `parent_rev`, politica, listagem, relogio (DIV-134), delete, sinal, saidas; nos ciclos 2 a 5, DIV-158 a DIV-168 e mutantes em camadas |

Duble de `curl` por regra (fronteira de rede, unica dependencia externa), `setsid` + `timeout` no `_rodar`, `TMPDIR`, `HOME` e estado privados por caso, sentinelas de segredo. Sem E2E contra o servico real (nao ha credencial de teste; mesmo criterio das fases 3 a 5). Nenhum dado real. RNF-24 da suite: nenhum `$(printf ...)` de massa e nenhum `grep -c` sobre arquivo (contagens por `_harness_contar`); auditorias `json` e `composicao` verdes.

## Gate 1 — protocolo-tdd

**Parecer (ciclo 1): APROVADO com ressalva bloqueante para o push** (TDD-01, resolvida pela autorizacao do solicitante, DIV-148).

Ciclo red-green-refactor:

| Fase | Evidencia |
|---|---|
| Red | Testes escritos antes do codigo de producao, rodados contra a base `d696c1d` (HEAD inalterado). `retencao_test`: `lib/retencao.sh: No such file or directory`, 1o caso `not ok`. `reter_test`: `not ok` em cada caso P0 rodado isolado (`rtc01_rtc02`, `rts09`, `rtp05`, `rtg06_rtg11`, `rtg09`, `rtp01_rtx01`, `div134_relogio`, `rtg07`, `rts07_cursor`, `rts10`): `comando desconhecido: reter`. Logs `red-unit-1.log` e `red-integ-1.log` do scratchpad da sessao. |
| Green | `retencao_test` 27/27; `reter_test` 69/69 (cada caso isolado, `green-integ-casos.log`, e pelo runner). |
| Refactor | validacao do glob unificada em `_dbx_filtro_validar_padrao` (usada pelos filtros de caminho e pelo nome avulso, RNF-36); `filtro_test` 34/34 sem alteracao. |

Mutantes dos P0 (copias do produto; cada um reprova o caso que o protege):

| P0 | Mutacao | Caso que pega |
|---|---|---|
| 1 sem `--confirmar` nada apaga | `confirmar=sim` forcado (`MUTACAO:confirmar`) | `rtc01_mutantes_da_confirmacao_reprovam` (`delete_v2` aparece no registro) |
| 1 `--dry-run` | leitura do `--dry-run` removida no comando: sobrevive pela 2a barreira (`_dbx_cmd_escrita_remota`, RF-15); removidas as duas, o registro pega | idem |
| 2 listagem coerente | item incoerente pulado em vez de abortar (`\|\| continue`) | `rts09_mutante_que_pula_o_item_incoerente_reprova` |
| 2 guarda no ponto do delete | conferencia da listagem removida: a guarda ainda barra (10, zero delete); removidas as duas, `delete_v2` fora da pasta aparece | `rtg03_mutante_sem_a_conferencia_da_listagem_ainda_e_barrado_pela_guarda` |
| 2 `parent_rev` | `parent_rev` tirado do corpo | `rtg06_mutante_sem_parent_rev_reprova` |
| 2 pasta / fora do padrao | filtro de `.tag` ou casamento do padrao trocados por `:` (com a guarda removida) | `p02_mutantes_de_selecao_reprovam` |
| 3 minimo de 1 | linha do minimo removida | `rtp12_mutante_sem_o_minimo_reprova` (propriedade, 200 listagens) |
| 3 N corrompido | `valor=0`: o primeiro nunca e apagado (minimo); `valor=0` sem o minimo: a guarda do primeiro barra com 10 | `rtg09_mutante_que_zera_o_n_nunca_apaga_o_primeiro`; unidade: `rtg09_mutante_sem_a_guarda_do_primeiro_reprova` |
| 4 `server_modified` invalido | validacao removida (lib e comando) | `p04_mutante_sem_a_validacao_de_server_modified_reprova` |
| 4 relogio (DIV-134) | conferencia do `Date` removida | `div134_mutante_sem_a_conferencia_do_relogio_reprova` |
| 4 cursor repetido | conferencia removida | `p04_mutante_sem_o_cursor_repetido_reprova` |

Execucao por camada:

| Camada / comando | Resultado |
|---|---|
| `shellcheck lib/*.sh commands/*.sh bin/* scripts/*.sh` | 0 achados (`shellcheck -x` nos 2 testes novos: 0) |
| Selecao pelo mapa (regra 1 + diff): `retencao_test`, `json`, `http`, `preflight`, `composicao`, `tmp_test`, `cli`, `filtro` | todos APROVADOS (27, 62, 53, 35, 28, 16, 17, 34) |
| `completar` | 16 ok, 1 not ok: TC-CPL-08 (TDD-01) |
| `reter_test` | 69/69 (caso a caso e pelo runner) |
| `bash scripts/verificar-remocao-de-casos.sh` | 1557 -> 1557, nenhuma reducao |
| Suite completa `bash tests/run.sh < /dev/null` no worktree | REPROVADA: 31 arquivos, 1012 ok, 1 not ok (TC-CPL-08), 2 pulados; parou no primeiro erro em `completar_test.sh` (23 arquivos nao executados), `suite-1.log` |
| Suite completa numa COPIA do worktree com so a linha 150 de `completar_test.sh` trocada (`res`/`rev` em vez de `re`) | APROVADA: 54 arquivos, 1641 ok, 0 not ok, 2 pulados (`suite-copia.log`). Serve so como evidencia de que nada mais quebra; o worktree NAO foi alterado pelo developer. |

Seguranca e acesso (regra 6): confinamento (13 sem chamada, inclusive `\n`/`\r`), guarda sem estado (estado envenenado identico ao vazio), `parent_rev` sempre, item fora da pasta, da raiz, do padrao ou pasta nunca apagado, sentinelas de token, refresh e segredo ausentes de stdout, stderr e `--debug`, padrao como dado (`$(touch S)` nao executa), nenhuma rota `permanently_delete`/`delete_batch` (auditoria estatica).

Achados:

| ID | Severidade | Achado | Regra |
|---|---|---|---|
| TDD-01 | Maior (bloqueia a suite) | Teste APROVADO `tests/integracao/completar_test.sh:150` (TC-CPL-08) afirma que `_completar re` devolve exatamente `restaurar restore revisions revisoes`; os nomes decididos `reter`/`retain` tambem comecam com `re`. Nao alterado pelo developer. Proposta: completar `res`/`rev`. Ver DIV-148. | Regras 8 e 9 (suite vermelha com falha devolvida ao Tech Lead) |
| TDD-02 | Menor | TC-RTC-05 depende de `script(1)`; pula sem ele (mesmo criterio de TC-SNH). | Regra 4 |

Nota do registro: a DIV-148 foi autorizada pelo solicitante em 2026-10-20. A assercao exata de `re` virou tres assercoes exatas, `res`, `rev` e `ret` (este ultimo prova `retain` e `reter`). `bash tests/run.sh completar`: APROVADA, 17/17, no worktree, em 2026-10-20. A suite completa do worktree fica com o Tech Lead, antes do push (registro, secao 4).

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

Parecer gate 1 (protocolo-tdd): APROVADO nos ciclos 1 a 5, sem achado bloqueante no codigo. A ressalva TDD-01 foi resolvida pela autorizacao do solicitante (DIV-148). Os conflitos com a suite do QA, ainda nao aprovada (DIV-163, DIV-166, DIV-169), foram decididos pelo Tech Lead e ajustados pelo QA; a suite final, com 60 casos, foi aprovada pelo solicitante.
