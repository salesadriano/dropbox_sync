# Integridade de dados P1: caixa no sync, recebimento atomico, umask, rev no envio e alvo somente leitura

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | Correcoes de integridade de dados, fase P1 da analise externa de melhorias ([fonte](../sources/2026-10-18-analise-melhorias.md)). |
| Porte | M. Defeitos de alta criticidade com risco de perda ou corrupcao de dados (caixa de caminho, recebimento nao atomico, `rm` de destino, envio sem `rev`), com escrita remota condicionada a `rev`. Toca contrato de `sync`/`download`/`upload` e codigos de saida. Sem mudanca de arquitetura. |
| Log de prompt | [docs/prompts/2026-10-18_1745_integridade-de-dados-p1.md](../prompts/2026-10-18_1745_integridade-de-dados-p1.md) |
| Branch / base | `bugfix/integridade-de-dados-p1` sobre `develop` @ `5aee478` (ancestral verificado) |
| Agents | Business Analyst (requisitos RF-54 a RF-57, RNF-29, DP-31, DP-32, RSK-37 a RSK-39); Senior Developer (implementacao, ciclos 1 a 4, sob `protocolo-tdd` e `protocolo-conformidade`); QA Expert (validacao independente, ciclos 1 e 2); Tech Lead (verificacao, correcao de status e fechamento). Instancia: `myPCWin/Adriano Sales Santos`. |
| Data | 2026-10-18 |

## 2. Causa ou decisao

Causa raiz por item, com a solucao adotada. Itens 1 e 3 tiveram tres abordagens comparadas; os demais tinham solucao unica.

- **Item 1, caixa no sync.** `dbx_sync_planejar` casava os lados pela grafia original. `Docs/Foto.JPG` e `docs/foto.jpg` geravam "transferir" e "apagar" ao mesmo tempo, e com `--espelhar` o envio era seguido de exclusao do arquivo recem-enviado. Escolhida a abordagem B: mapas mantidos na grafia original, chave sem caixa (`_dbx_sync_chave`) aplicada so na decisao, `DBX_SYNC_ALVO` com a grafia do destino. Descartadas: A (chavear tudo em minusculas, diff grande) e C (`path_lower` no remoto e `${,,}` no local, que divergem fora do ASCII).
- **Item 2, envio do sync.** Para cumprir RF-57(d) (um so ponto de escolha), a montagem do objeto de publicacao e o roteamento por tamanho foram movidos para `lib/transfer` e passam a ser usados por `upload` e `sync`. Por RF-49 (emenda do solicitante): arquivo existente vai em `update` com o `rev` da listagem da execucao; arquivo novo vai em `add`, sem `autorename`; conflito conta como falha do item e o sync sai com `nao_concluida`.
- **Item 3, recebimento atomico.** `dbx_http_conteudo_receber` gravava direto no alvo, e o hash do `download` era conferido depois da sobrescrita (e `lib/hash` nem era carregada nesse caminho). Escolhida a abordagem B: auxiliar `dbx_cmd_receber_arquivo` em `lib/cmd`, usado por `download` e `sync`; temporario `.<nome>.dbx-part.XXXXXX` no diretorio do alvo, conferencia por hash antes do `mv -f`. Descartadas: A (politica de integridade dentro de `lib/http`) e C (duplicacao por comando).
- **Item 4, `download` de pasta sobre arquivo.** O `rm -f` foi removido; destino que existe e nao e diretorio sai com `conflito`.
- **Itens 5 e 6, umask e area temporaria HTTP.** `_dbx_http_executar` cria a area com `umask 077` restrito a substituicao de comando, remove a area de forma explicita em cada nivel e nao arma `trap RETURN`. O paliativo sugerido na analise (`trap ...; trap - RETURN`) foi rejeitado, porque desarma o gancho do nivel externo e vazaria a area externa.
- **Item 7, alvo somente leitura (ciclo 4).** Decisao do solicitante: arquivo local sem permissao de escrita e recusado, nunca substituido (`permissao`, saida 6), no `download` e no `sync --receber`. Checagem antes do temporario e de novo antes do `mv`.

Requisitos: [RF-54 a RF-57, RNF-29, RF-49 (TC-REV-01..02), RNF-04 emendado](../requisitos/escopo-requisitos-e-criterios-de-aceite.md), [DP-31 e DP-32](../requisitos/decisoes-pendentes.md), [RSK-37 a RSK-39](../requisitos/riscos-restricoes-e-licenciamento.md), [backlog F-23 a F-32](../requisitos/funcionalidades-candidatas.md), [System Design](../arquitetura/system-design.md).

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| [commands/download.sh](../../commands/download.sh) | Alterado | +39/-44 |
| [commands/sync.sh](../../commands/sync.sh) | Alterado | +42/-20 |
| [commands/upload.sh](../../commands/upload.sh) | Alterado | +22/-91 |
| [lib/cmd.sh](../../lib/cmd.sh) | Alterado | +188/-0 |
| [lib/hash.sh](../../lib/hash.sh) | Alterado (ciclo 5) | +16/-0 |
| [lib/http.sh](../../lib/http.sh) | Alterado | +30/-30 |
| [lib/sync.sh](../../lib/sync.sh) | Alterado | +111/-8 |
| [lib/transfer.sh](../../lib/transfer.sh) | Alterado | +111/-4 |
| [tests/integracao/comandos_test.sh](../../tests/integracao/comandos_test.sh) | Alterado | +236/-2 |
| [tests/integracao/sync_test.sh](../../tests/integracao/sync_test.sh) | Alterado | +278/-4 |
| [tests/unit/http_test.sh](../../tests/unit/http_test.sh) | Alterado | +57/-6 |
| [tests/integracao/qa_integridade_p1_test.sh](../../tests/integracao/qa_integridade_p1_test.sh) | Novo (QA) | +574/-0 |
| [docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md](../requisitos/escopo-requisitos-e-criterios-de-aceite.md) | Alterado (BA) | +18/-4 |
| [docs/requisitos/decisoes-pendentes.md](../requisitos/decisoes-pendentes.md) | Alterado (BA) | +26/-0 |
| [docs/requisitos/funcionalidades-candidatas.md](../requisitos/funcionalidades-candidatas.md) | Alterado (BA) | +20/-0 |
| [docs/requisitos/riscos-restricoes-e-licenciamento.md](../requisitos/riscos-restricoes-e-licenciamento.md) | Alterado (BA) | +3/-0 |
| [docs/arquitetura/system-design.md](../arquitetura/system-design.md) | Alterado (BA) | +11/-0 |

Total de linhas de codigo (producao e teste, sem documentacao): **1913** (soma de +/- dos 12 arquivos de `commands/`, `lib/`, `tests/`). Medido por `git diff --numstat 5aee478 -- lib commands tests`.

## 4. Testes rodados

Comando e contagem literais, por arquivo de teste. Pulados: 0 em todos os itens abaixo, conforme os pareceres. Total = aprovados.

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `json_test` | Auditoria estatica de todo `lib/*.sh` (RNF-24, RSK-27) | `bash tests/run.sh json_test` | 60 | 60 | 0 | 1 s |
| `http_test` | [lib/http.sh](../../lib/http.sh); auditoria de `lib/*.sh` | `bash tests/run.sh http_test` | 36 | 36 | 0 | 4 s |
| `preflight_test` | Auditoria de comandos de `lib/*.sh` | `bash tests/run.sh preflight_test` | 25 | 25 | 0 | 3 s |
| `composicao_test` | Auditoria de `lib/*.sh` | `bash tests/run.sh composicao_test` | 24 | 24 | 0 | 6 s |
| `hash_test` | [lib/hash.sh](../../lib/hash.sh) (ciclo 5) | `bash tests/run.sh hash_test` | 40 | 40 | 0 | 6 s |
| `transfer_test` | [lib/transfer.sh](../../lib/transfer.sh) | `bash tests/run.sh transfer_test` | 26 | 26 | 0 | 3 s |
| `cli_test` | Selecao do Tech Lead | `bash tests/run.sh cli_test` | 17 | 17 | 0 | < 1 s |
| `comandos_test` | [lib/cmd.sh](../../lib/cmd.sh), [commands/download.sh](../../commands/download.sh), [commands/upload.sh](../../commands/upload.sh) | `bash tests/run.sh comandos_test` | 84 | 84 | 0 | 12 s |
| `sync_test` | [lib/sync.sh](../../lib/sync.sh), [lib/cmd.sh](../../lib/cmd.sh), [lib/transfer.sh](../../lib/transfer.sh), [commands/sync.sh](../../commands/sync.sh) | `bash tests/run.sh sync_test` | 39 | 39 | 0 | 18 s |
| `qa_integridade_p1` | Validacao independente de todos os itens acima | `bash tests/run.sh qa_integridade_p1` | 27 | 27 | 0 | 11 s |

- Reexecucao do Tech Lead apos o ciclo 5, os dez arquivos em sequencia com `bash tests/run.sh <arquivo> < /dev/null`: 378 aprovados, 0 reprovados, 0 pulados; duracoes na tabela. `shellcheck lib/*.sh commands/*.sh bin/* tests/integracao/qa_integridade_p1_test.sh` com saida 0; `--detectar` com saida 0.
- **Selecao insuficiente ate o ciclo 4 (licao):** `json_test`, `http_test`, `preflight_test` e `composicao_test` auditam todo o `lib/*.sh`; o `json_test` ficou fora da selecao e a primeira suite completa local (commit `d4ef8a1`) reprovou em `nenhuma_captura_pode_carregar_byte_externo` (RNF-24: capturas `$(readlink)`, `$(dbx_hash_conteudo_arquivo)` e `$(date)` em `lib/`). Corrigido no ciclo 5 sem nova excecao na auditoria; regra gravada em [selecao-inclui-auditorias-lib](../../.github/agents/memoria/entradas/2026-10-18-1745-selecao-inclui-auditorias-lib.md).
- **Instabilidade conhecida:** `hash_test` `nao_deixa_residuo_temporario` conta `dbx-http.*` no `/tmp` compartilhado e reprovou 2 vezes em cerca de 20 execucoes do Tech Lead, com outro processo `dbx` do solicitante ativo na maquina; o arquivo nao foi alterado nesta entrega. Mesma classe do QA-04 (ja corrigido em `http_test`); backlog com F-30.
- Red observado: ciclo 1, `http_test` 3 de 4 novos casos falharam, `comandos_test` 5 de 6, `sync_test` 10 de 12. Ciclo 2, 4 casos novos com red comprovado (mute, temporario orfao em sync e em recebimento, temporario por sinal); `upload_de_arquivo_unico_mantem_mute_falso` e guarda, ja passava. Ciclo 4, os 3 casos de alvo somente leitura com red contra o ciclo 3. Ciclo 5, `upload_formata_client_modified_em_utc` com red contra a primeira versao (fuso local); `download_para_vinculo_simbolico_atualiza_o_arquivo_apontado` e guarda. Casos de guarda (ja passavam na base) estao identificados nos pareceres e nao sao prova de red.
- Parada no primeiro erro (regra 9): nao atendida. `tests/run.sh` percorre todos os arquivos e casos. Defeito anterior ao P1, registrado como F-30 ([backlog](../requisitos/funcionalidades-candidatas.md)).
- Barreiras estaticas: `shellcheck lib/*.sh commands/*.sh bin/* scripts/*.sh tests/unit/http_test.sh tests/integracao/comandos_test.sh tests/integracao/sync_test.sh` com saida 0 (shellcheck 0.10.0, modo bash), e `shellcheck tests/integracao/qa_integridade_p1_test.sh` com saida 0. No ciclo 4, o developer registra saida 0. Um SC2153 em `lib/cmd.sh` (`DBX_PATH_RESULTADO`) foi silenciado com justificativa.
- Testes de seguranca e acesso (regra 6): colisao de caixa (envio, recebimento e simulacao); pasta remota sobre arquivo regular; hash divergente em `download` e `sync`; interrupcao no meio do recebimento; alvo somente leitura (recusa sem efeito); vinculo simbolico para arquivo e vinculo quebrado; area do token em 0700; `umask` do processo preservado. Cada cenario verifica codigo de saida, ausencia de efeito colateral e diagnostico nomeado.
- Validacao de formularios em E2E (regra 7): Nao aplicavel: o projeto e CLI em shell, sem formulario nem frontend.
- Suite completa local no push para a PR de `develop` (regra 8), pelo comando oficial `sh scripts/suite-completa.sh` (`bash tests/run.sh`):
  - `d4ef8a1`: **vermelha**, 660 aprovados, 1 reprovado (`json_test` `nenhuma_captura_pode_carregar_byte_externo`, RNF-24), 2 pulados, 68 s; push bloqueado; corrigido no ciclo 5.
  - `67e521b`: **verde**, 21 arquivos, 667 aprovados, 0 reprovados, 2 pulados (`hash_vetor_oficial_test`, sem rede), 76 s, registrada em 2026-10-19T01:28:18Z; `--conferir` com saida 0. Base do push que abriu a PR.
  - O commit so de documentacao que preenche este registro tem a suite completa reexecutada antes do proprio push, conforme a guarda.

## 5. Gates

Parecer combinado dos dois gates locais, executados pelo Senior Developer. Os dois gates estao em Aprovado com ressalvas nos quatro ciclos.

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | Nenhum achado de codigo. Ressalvas: (1) runner nao para no primeiro erro (F-30); (2) `upload <diretorio>` acima de 150 MiB sem caso proprio: fechada pelo caso do QA (secao 6). | Aprovado com ressalvas |
| `protocolo-conformidade` | `clean-architecture` + `shellcheck-configuration`; Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | Ciclo 1, quatro menores: (a) `lib/transfer.sh`, `mute` do sync: corrigido no ciclo 2; (b) `lib/cmd.sh`, temporario orfao em sinal: corrigido no ciclo 2 (filtro em `lib/sync` e tratador em `lib/cmd`); (c) `lib/sync.sh`, dobra fora do ASCII depende de `C.UTF-8` e pasta irma: limite registrado (F-32), aceito pelo Tech Lead; (d) `lib/cmd.sh` carrega `lib/hash`: sem acao. Ciclo 4: nenhum achado novo; o limite (c) segue aberto. | Aprovado com ressalvas |

- Ciclos: 1 (inicial), 2 (correcoes de mute e temporario orfao), 3 (QA-02 `chmod` depois da conferencia do hash; QA-04 teste com `TMPDIR` privado), 4 (decisao do solicitante: alvo somente leitura recusado), 5 (suite completa vermelha: achado de seguranca RNF-24, bloqueante, corrigido por publicacao em variavel: `dbx_hash_publicar_arquivo` em `lib/hash`, leitura de vinculo sem captura em `lib/cmd`, carimbo por `stat` e `printf %()T` sob `TZ=UTC` em `lib/transfer`). Vigente: 5. Status dos achados anteriores: corrigido nos itens (a), (b) e (d); (c) nao corrigido, limite registrado.
- `sh scripts/alteracoes-externas.sh --detectar`: saida 0 no inicio de cada ciclo e antes de cada gate. Nas etapas de registro, saida 3 acusou apenas os arquivos editados pelo agent; apos `--registrar`, saida 0.

## 6. QA

- Validacao independente do QA Expert sobre os itens afetados, em tres ciclos. Ciclo 1 (21 casos), ciclo 2 (23 casos, sobre o ciclo 4) e ciclo 3 (27 casos, sobre o ciclo 5): Aprovado com ressalvas em todos.
- Arquivo do QA: [tests/integracao/qa_integridade_p1_test.sh](../../tests/integracao/qa_integridade_p1_test.sh), 574 linhas, sha256 `371a93ae5a2a7800cb970fa7b5d370e65ba811655331eea004cfb5902b9cbfb3` (versao de 27 casos, reaprovada).
- Cenarios independentes: RF-54 (colisao em subdiretorio, simulacao e execucao, `--espelhar` com caixa diferente); RF-49 (`rev` casado sem caixa; sem `rev` nunca sai em `overwrite` nem `autorename`); RF-57 (teto exato de 157286400 bytes; `upload <diretorio>` acima do teto por sessao com `client_modified`); RF-55 (hash divergente, hash malformado, alvo 0444 nunca afrouxado, alvo somente leitura recusado); RF-56 (vinculo simbolico e vinculo quebrado); RNF-29 (umask 027 com 640/750; reemissao diagnostica e sinal sem residuo); filtro do `.dbx-part` (so o padrao exato e retirado).
- Mutantes: M1 a M7 no ciclo 1, todos mortos. M2 e M4 sobreviveram ao `sync_test` do developer e foram mortos pelos casos do QA. Ciclo 2: M8 e M9 mortos; M10 (retorno `conflito` em vez de `permissao`) sobreviveu e e equivalente, pois o codigo de saida vem de `DBX_CMD_FALHA_CLASSE`. Ciclo 3: M11 a M15 mortos (vinculo, carimbo UTC, hash residual); M13 (sem `-x` no `TZ`) so e detectavel em host fora de UTC.
- Achados do QA:

| ID | Severidade | Achado | Status |
|---|---|---|---|
| QA-01 | Menor (documental) | TC-SYE-03 contradizia RF-57(c) e RF-49 | Corrigido no ciclo 2 do QA (texto reescrito pelo BA) |
| QA-02 | Menor | `chmod` aplicado ao temporario antes da escrita, com diagnostico enganoso em alvo 0444 | Corrigido no ciclo 3 do developer (`chmod` depois da conferencia do hash) |
| QA-03 | Menor (anterior ao P1) | Sinal durante `sync --receber` deixa `dbx-sync.XXXX` em `TMPDIR` | Aberto, backlog [F-31](../requisitos/funcionalidades-candidatas.md) |
| QA-05 | Maior (processo) | O projeto nao tem mapa de modulos; a lacuna deixou o `json_test` fora da selecao | Regra vigente em memoria (`selecao-inclui-auditorias-lib`); mapa em `docs/testes/mapa-modulos.md` pendente, owner QA Expert, fase 2 |
| QA-04 | Menor (teste anterior) | `nao_deixa_residuo_temporario` contava `dbx-http*` no `/tmp` compartilhado | Corrigido no ciclo 3 do developer (`TMPDIR` privado); o status aberto no ciclo 2 do QA estava desatualizado, conferido pelo Tech Lead |

- Limites: a recusa por alvo somente leitura nao e exercida como `root` (o teste `-w` e sempre verdadeiro e os casos se pulam). Um arquivo do usuario com o nome exato `.<n>.dbx-part.XXXXXX` e ignorado pelo sync, consequencia do desenho.
- Veredito do QA: **Aprovado com ressalvas**, 2026-10-18 (ciclo 2). Aceite do solicitante registrado em [aceite-testes-qa-p1](../../.github/agents/memoria/entradas/2026-10-18-1745-aceite-testes-qa-p1.md) (21 casos) e [reaceite-testes-qa-p1](../../.github/agents/memoria/entradas/2026-10-18-1745-reaceite-testes-qa-p1.md) (23 casos) e [reaceite-2-testes-qa-p1](../../.github/agents/memoria/entradas/2026-10-18-1745-reaceite-2-testes-qa-p1.md) (27 casos).

## 7. Riscos e rollback

- Riscos residuais (owner e prazo, conforme a aprovacao do Tech Lead):
  - F-28, `dbx download <remoto>` sem destino sai com codigo 9; defeito anterior, presente no HEAD. Owner Senior Developer, fase 2.
  - F-29, `commands/upload.sh` le `DBX_TRANSFER_HASH` (inexistente); o canal e `DBX_TRANSFER_CONTENT_HASH`. Owner Senior Developer, fase 3.
  - F-30, `tests/run.sh` nao para no primeiro erro (regra 9). Owner Senior Developer, fase 2.
  - F-31, sinal durante `sync --receber` deixa `dbx-sync.XXXX` em `TMPDIR` (QA-03). Owner Senior Developer, fase 2.
  - QA-05, mapa de modulos inexistente. Owner QA Expert, fase 2.
  - F-32, comparacao sem caixa fora do ASCII depende de `C.UTF-8`. Owner Business Analyst, fase 5.
  - Limite de SIGKILL e de `exit` fora da janela do tratador: um `.dbx-part` pode ficar no disco, mas o filtro do sync impede que seja publicado. Sem owner por ora, fora do backlog.
  - Limite de execucao como `root`: a recusa de alvo somente leitura nao ocorre. Sem owner por ora.
  - DIV-22 (`RNF-07` exige `Retry-After`, nao implementado) permanece aberta, fora do escopo desta entrega, na fase 2 ([DIV-22](../requisitos/escopo-requisitos-e-criterios-de-aceite.md)).
- Impacto: contrato do `sync` (envio passa de sobrescrita a `update` com `rev`; conflito vira falha do item, codigo `nao_concluida`); `download` recusa alvo somente leitura (codigo 6, `permissao`) e destino que e diretorio ou pasta sobre arquivo (`conflito`); arquivos baixados seguem o `umask` do usuario (RNF-29); `upload <diretorio>` acima de 150 MiB passa por sessao com `client_modified`. Sem schema, sem migracao, sem dependencia nova.
- Rollback: `git revert <sha>` basta. Nao ha migracao de dado. Residuos `.<nome>.dbx-part.*` de execucoes interrompidas por SIGKILL, se existirem, sao removiveis manualmente.

## 8. Links e aceites

- Entradas de memoria: `2026-10-18-1745-padroes-integridade-p1`, `2026-10-18-1745-melhorias-em-fases`, `2026-10-18-1745-skip-upload-condicionado`, `2026-10-18-1745-aceite-commit-c492085` (regra 48), `2026-10-18-1745-aceite-testes-qa-p1`, `2026-10-18-1745-reaceite-testes-qa-p1`, `2026-10-18-1745-reaceite-2-testes-qa-p1`, `2026-10-18-1745-selecao-inclui-auditorias-lib`. Links em [.github/agents/memoria/entradas/](../../.github/agents/memoria/entradas/).
- Documentacao sincronizada: [escopo-requisitos-e-criterios-de-aceite.md](../requisitos/escopo-requisitos-e-criterios-de-aceite.md), [decisoes-pendentes.md](../requisitos/decisoes-pendentes.md), [funcionalidades-candidatas.md](../requisitos/funcionalidades-candidatas.md), [riscos-restricoes-e-licenciamento.md](../requisitos/riscos-restricoes-e-licenciamento.md), [system-design.md](../arquitetura/system-design.md).
- Intervencao humana (regra 48): nenhum arquivo desta entrega tem origem humana. O unico item acusado foi o commit `c492085` na `develop`, anterior a esta demanda e fora dela, confirmado intencional pelo solicitante ([aceite](../../.github/agents/memoria/entradas/2026-10-18-1745-aceite-commit-c492085.md)).
- Commit(s): `d4ef8a1` (implementacao, ciclos 1 a 4), `67e521b` (ciclo 5, RNF-24) e o commit de documentacao que preenche este registro. **Desvio:** a mensagem de `67e521b` foi redigida pelo Tech Lead, e nao delegada ao `commit-writer` (obrigatorio em M); o conteudo segue o formato e as linhas `Ref:`/`Prompt:`.
- PR: [#35](https://github.com/salesadriano/dropbox_sync/pull/35) para `develop`, labels `review` e `bug`. Review request nativo nao aplicado: o unico colaborador e o proprio autor.
- Limite do pacote observado: `guarda-de-comandos.sh` confere a suite pelo `cwd` da sessao, e nao pelo `cd` dentro do comando; com o checkout principal como `cwd`, bloqueou o push conferindo `5aee478`. Contornado legitimamente com a sessao dentro do worktree. Candidato a correcao no pacote `ai_team`.
- Tech Lead: **Aprovado com ressalvas**, 2026-10-18. Aprovacao final vale somente com a suite completa local verde registrada na secao 4.
- Solicitante: aceite dos `qa-*` registrado por entrada de memoria, citada na secao 6. O sha256 acima nao consta dos aceites, que citam a contagem de casos.

## 9. Revisao consolidada e aprovacao (compacta)

- Identificacao: porte M; Tech Lead; 2026-10-18; branch `bugfix/integridade-de-dados-p1`.
- Artefatos consolidados, por referencia: este registro (secoes 5 e 6 com os gates e o QA); [prompt](../prompts/2026-10-18_1745_integridade-de-dados-p1.md); [fonte](../sources/2026-10-18-analise-melhorias.md); requisitos da secao 2.
- Divergencias tratadas:
  - DIV-23 (`RF-49` x sobrescrita sem `rev`): resolvida, `RF-49` emendado, `TC-REV-01..02` exigidos.
  - DIV-24 (`RNF-04` x `umask` restritivo): resolvida, `RNF-04` emendado; `umask` 077 restrito a area com token.
  - DIV-22 (`RNF-07` x `Retry-After`): aberta, fase 2, fora desta entrega.
  - Alvo somente leitura (decisao do ciclo 4): recusado, RF-55(f) e TC-ATM-05; o ciclo 3 substituia o alvo e foi revogado.
  - Achado do gate de conformidade sobre memoria e RF-57(c) (ciclo 1): RF-57(c) emendado pelo BA; a entrada `padroes-integridade-p1` foi atualizada pelo Tech Lead na mesma rodada e registra a revisao do padrao "sem rev". Conferido.
- Pendencias: merge da PR #35 (pipeline, se houver, e revisao do solicitante).
- Decisao de fechamento: **Aprovado com ressalvas**, 2026-10-18. Ressalvas: F-28, F-30 e F-31 (Senior Developer, fase 2); QA-05 (QA Expert, fase 2); F-29 (Senior Developer, fase 3); F-32 (Business Analyst, fase 5). Validacao QA frontend: Nao aplicavel: sem frontend.
