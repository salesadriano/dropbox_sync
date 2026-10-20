# Parecer de Evidencias de Testes (TDD) — Revisoes, restauracao e lixeira (fase 3)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: revisoes, restauracao e lixeira com exclusao permanente (F-07, F-20); porte **G**
- Agent responsavel pela alteracao e pela verificacao: Senior Developer (gate local, regra 14); validacao independente a cargo do QA Expert
- Data: 2026-10-19
- Ciclos: 3 (ciclo 1 inicial; ciclo 2 apos a reprovacao QA-B3-01..03 e DIV-78; ciclo 3 apos QA-B3-04..06)
- Branch / base: `feature/recuperacao-b3` sobre `develop` @ `ef1efb2`, sem commit
- Log de prompt: [2026-10-19_1828_backlog-fase-3-recuperacao.md](../prompts/2026-10-19_1828_backlog-fase-3-recuperacao.md)
- Registro de entrega: [2026-10-19-1828-registro-recuperacao-b3.md](2026-10-19-1828-registro-recuperacao-b3.md)
- Parecer de conformidade: [2026-10-19-1828-parecer-conformidade-recuperacao-b3.md](2026-10-19-1828-parecer-conformidade-recuperacao-b3.md)
- Transcricao fiel dos pareceres do Senior Developer por gate; as secoes comuns aos dois gates (arquivos, ciclos 2 e 3) aparecem nos dois arquivos.

## Transcricao

Demanda: revisoes, restauracao e lixeira com exclusao permanente; porte G. Branch `feature/recuperacao-b3` (base `develop` ef1efb2). Sem commit.
Fonte autoritativa: memoria `2026-10-19-1828-recuperacao-e-lixeira` (DIV-54..69) e complemento da DIV-55 (com terminal, `--confirmar-caminho` identico dispensa a pergunta).

## Arquivos

- Novos: `commands/revisoes.sh`, `commands/restaurar.sh`, `commands/lixeira.sh`, `tests/integracao/recuperacao_test.sh`.
- Alterados: `lib/errors.sh` (DIV-58), `lib/cmd.sh` (`_dbx_cmd_escrita_remota` com modo `silencioso` e `in_progress`->14; `dbx_cmd_remoto_confinado`; `dbx_cmd_listar_nivel`; `dbx_cmd_campo_caminho`), `lib/sync.sh` (`dbx_sync_ordem_sem_caixa`), `lib/cli.sh` (tabela, aliases, arquivos literais), `bin/dbx` (ajudas), `commands/diagnostico.sh` (RF-77), `completions/dbx.bash`, `README.md` (secao 11), `docs/testes/mapa-modulos.md`.
- Testes existentes: so casos ACRESCENTADOS (`errors_test` 2, `diagnostico_test` 2, `completar_test` 1, `composicao_test` 1). Nenhum caso aprovado alterado ou removido (`verificar-remocao-de-casos.sh`: 1209 -> 1215, nenhuma reducao).

## Gate 1 — protocolo-tdd

**Parecer: APROVADO, sem achado bloqueante.**

- Red confirmado caso a caso contra a base (cada caso rodado isolado): 56 casos em `recuperacao_test` + 6 nos arquivos existentes = 62, todos reprovando antes da implementacao. Cinco casos passavam por acaso (comando desconhecido tambem sai 2: rvs02, rst03, rpa03, rpa08, exp11); ganharam assercao de mensagem/resultado e passaram a reprovar antes de qualquer codigo de producao.
- Green: `recuperacao` 56/56; `errors_test`, `diagnostico_test`, `completar_test`, `composicao_test` aprovados.
- Selecao pelo mapa (diff em lib/*.sh e commands/*.sh): `json_test` 60, `http_test` 53, `preflight_test` 35, `composicao` 28, `tmp_test` 16, `cli_test` 17, `cmd_test` 23, `sync_plano` 6, `trava_test` 59 — todos aprovados. `json_test` reprovou uma vez (massa por `$(printf %q)` no teste novo) e foi corrigido com `printf -v`.
- Suite completa (`bash tests/run.sh < /dev/null`), uma vez no fim: 42 arquivos, 1259 aprovados, 0 reprovados, 2 pulados (vetor oficial de content_hash, pre-existentes, sem rede).
- Piramide: projeto shell sem banco nem UI; Testcontainers/Cypress nao se aplicam (mesma excecao das fases anteriores). Integracao ponta a ponta pelo `bin/dbx` real com duplo de `curl` na fronteira de rede (unico mock), registrando cada chamada; unidade em `errors_test`.
- Seguranca provada por teste: toda recusa da exclusao permanente antes da chamada destrutiva (`permanently_delete` contado = 0 em exp02/03/04/05/06/10/11); recusas de uso, raiz, confinamento e confirmacao sem NENHUMA chamada, nem a renovacao do token (arquivo de chamadas ausente); guarda pela API (`get_metadata` com `include_deleted` antes do expurgo, ordem conferida em exp01); sentinelas de credencial ausentes de stdout/stderr/`--debug` (exp14).
- TTY real por `script(1)` (exp05; pula sem ele). Sinal real por `setsid` + `kill -TERM 0` (rpa10: 14, resumo parcial, TMPDIR vazio).
- shellcheck 0.10.0 (modo do shebang, bash) em `lib/*.sh commands/*.sh bin/dbx completions/dbx.bash scripts/*.sh` e nos testes tocados: limpo. Nenhum `scripts/*.sh` alterado (modo posix inalterado).

## Ciclo 2 (reprovacao do QA)

Correcoes sob protocolo-tdd; red confirmado caso a caso contra o ciclo 1 (rst05, exp_guarda_exige_path_lower_do_proprio_alvo, rpa_div78 reprovaram antes do conserto).

- QA-B3-01: `rev` fora do historico do caminho sai 2 (`uso_invalido`); `--antes-de` sem revisao segue 4. `rst05` renomeado e ajustado (era caso meu, do ciclo 1).
- QA-B3-02 (seguranca): a guarda do expurgo le `.tag` e `path_lower`; exige `path_lower` presente e igual ao alvo normalizado, dobrados so no ASCII sob `LC_ALL=C`. Ausente, vazio ou divergente (inclusive caixa nao ASCII) sai 10 sem expurgo, mensagem com o valor citado (sem byte cru). Caso novo cobre outro caminho, ausente, vazio, prefixo, caixa ASCII (passa) e caixa nao ASCII (recusa, com e sem byte de controle). Massas de `deleted` dos meus testes ganharam `path_lower`.
- DIV-78: na pasta, item fora da pasta pedida (por componente, apos normalizar), mesmo dentro da `raiz_remota`, nunca e sondado nem restaurado e conta como falha `caminho_recusado` (14). `dbx_cmd_remoto_confinado` ganhou o argumento opcional da pasta.
- QA-B3-03: so comentario em `_dbx_cmd_escrita_remota` (in_progress -> 14 vale para delete, restore e expurgo; upload, por lib/transfer, mantem 10). A ajuda nao citava.

Resultados: `recuperacao_test` 58/58, `errors_test` 82, `cli_test` 17, `composicao` 28, `json_test` 60, `http_test` 53, todos aprovados; shellcheck limpo; guarda de remocao sem reducao (1209 -> 1215).
`qa_recuperacao_b3_test` (nao alterado): R01 e E08 passam; 23 de 27 passam. E07, E10, E11 e E12 reprovam porque a massa `_qa_apagado`/`_qa_expurgo_padrao` do QA devolve `DeletedMetadata` SEM `path_lower`, que a decisao QA-B3-02 agora recusa (10) antes da pergunta/expurgo. Conserto e da massa do QA (acrescentar `path_lower`), nao do codigo.

Parecer gate 1 (protocolo-tdd): APROVADO. Parecer gate 2 (protocolo-conformidade): APROVADO; guarda continua sem estado local, toda recusa antes da chamada destrutiva, nenhuma captura nova em lib/.

## Ciclo 3 (QA-B3-04..06)

Red confirmado antes do conserto: 2 casos novos em `json_test` e 3 em `recuperacao_test`, todos reprovando contra o ciclo 2.

- QA-B3-04 (seguranca): `lib/json` recusa o escape `\u0000` como `malformado` em todo documento (cadeia, chave, aninhado), ANTES do `printf` que o descartaria. Custo: uma comparacao por escape `\u`.
- QA-B3-05: opcao escolhida = recusa SO NA GUARDA. A recusa global quebraria dois casos aprovados de `json_test` (E2-08 `chave_duplicada_nao_deixa_filha_fantasma` e E3-03 `contador_e_enumeracao_concordam_com_chave_duplicada`, que fixam "vence a ultima"). O parser so CONTA as duplicadas (`DBX_JSON_DUPLICADAS`, zerado a cada analise e incrementado no ramo ja existente de chave repetida: custo zero no caminho comum do sync); `dbx_cmd_ler_corpo_silencioso` publica `DBX_CMD_DUPLICADAS`, e a guarda do expurgo sai 10 sem expurgo com qualquer chave repetida no documento (mais estrito que "so no topo").
- QA-B3-06: `dbx_cmd_descendente_estrito` (lib/cmd; normaliza e compara por componente, caixa dobrada so no ASCII sob `LC_ALL=C`) e conjunto de visitados (`dbx_cmd_chave_ascii`) na descida da restauracao de pasta e da `lixeira -R`. A propria pasta, um ancestral, outra grafia da mesma pasta ou item repetido sao ignorados; o item enfileirado e o normalizado. O DIV-78 (fora da pasta pedida = falha) continua antes e prevalece.

Resultados: `qa_recuperacao_b3_test` 30/30 (inclusive E08, E13, R10 e L03; arquivo nao alterado), `recuperacao_test` 61, `json_test` 62, `http_test` 53, `cabecalho` 17, `qa_rede` 25, `errors_test` 82, `cli_test` 17, `composicao` 28, `sync_test` 85, `sync_plano` 6, `verificar_test` 17, `auth_test` 41, `cmd_test` 23, `config_test` 40, todos aprovados. shellcheck limpo; guarda de remocao 1209 -> 1217, sem reducao. Nenhum caso aprovado alterado.

Parecer gate 1 (protocolo-tdd): APROVADO. Parecer gate 2 (protocolo-conformidade): APROVADO; sem captura nova em lib/ (auditoria RNF-24 verde), guarda sem estado local, recusas antes da chamada destrutiva.
