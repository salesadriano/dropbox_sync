# Parecer de Evidencias de Testes (TDD) — Link temporario e link compartilhado (fase 5)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: link temporario de download e link compartilhado com expiracao, senha ou audiencia (F-15, F-16); porte **G**
- Agent responsavel pela alteracao e pela verificacao: Senior Developer (gate local, regra 14); validacao independente a cargo do QA Expert
- Data: 2026-10-20
- Ciclos: 4 (ciclo 1 inicial, com a correcao da DIV-123 antes do QA; ciclo 2 apos a reprovacao QA-B5-01..07; ciclo 3 apos QA-B5-08..16 e DIV-128; ciclo 4 apos as ressalvas QA-B5-17..19 e DIV-129). No parecer original, a correcao da DIV-123 aparece como "ciclo 2", e os ciclos seguintes vem nas secoes 3, 4 e 5; aqui os titulos seguem a numeracao acima.
- Branch / base: `feature/compartilhamento-b5` sobre `develop` @ `e42168f`, sem commit
- Log de prompt: [2026-10-20_1110_backlog-fase-5-compartilhamento.md](../prompts/2026-10-20_1110_backlog-fase-5-compartilhamento.md)
- Registro de entrega: [2026-10-20-1110-registro-compartilhamento-b5.md](2026-10-20-1110-registro-compartilhamento-b5.md)
- Parecer de conformidade: [2026-10-20-1110-parecer-conformidade-compartilhamento-b5.md](2026-10-20-1110-parecer-conformidade-compartilhamento-b5.md)
- Transcricao fiel dos pareceres do Senior Developer por gate; as secoes comuns aos dois gates (arquivos, ciclos 2 a 4) aparecem nos dois arquivos.

## Transcricao

Worktree: `/home/sales/dropbox_api.worktrees/feature-compartilhamento-b5` (base `e42168f`, sem commit).
Requisitos: escopo v1.18, secao 5.13 (RF-84..92); decisoes: memoria `2026-10-20-1110-compartilhamento` (DIV-104..120); arquitetura: system design v1.13.

## Arquivos

| Arquivo | Natureza |
|---|---|
| `lib/compartilhamento.sh` | novo (DIV-117): `--expira`, senha, URL, corpo, confinamento por `path_lower`, exposicao |
| `commands/link_temporario.sh` | novo (RF-84; `link-temporario`, `temp-link`) |
| `commands/compartilhar.sh` | novo (RF-85..90; `share`) |
| `lib/errors.sh` | qualificador `settings_error`, 13 tags de RF-90(a) (+ `unsupported_parameter_field`), `link_password` sensivel (DIV-111) |
| `lib/cli.sh` | tabela de comandos e aliases; `dbx_cli_ler_oculto` (ponto unico sem eco, DIV-117) |
| `lib/cmd.sh` | `_dbx_cmd_escrita_remota` com 4o argumento de idempotencia (DIV-119) |
| `lib/tmp.sh` | `dbx_tmp_armar` (sinal na leitura da senha sai 14) |
| `commands/config.sh` | app secret pela leitura unica de lib/cli |
| `commands/diagnostico.sh` | `sharing.write`/`sharing.read` na linha `escopos` (RF-91) |
| `bin/dbx`, `completions/dbx.bash`, `README.md`, `docs/testes/mapa-modulos.md` | RF-92 |

Testes novos (nenhum teste aprovado alterado ou removido):

| Arquivo | Casos | Cobre |
|---|---|---|
| `tests/unit/compartilhamento_test.sh` | 16 | TC-CMP-02/03/05/06/07 (unidade), TC-SNH-05/06/11/14, TC-RVG-06/07/12, TC-LST-04/05, TC-LEX-03/10, TC-SHE-01, leitura sem eco de lib/cli |
| `tests/integracao/compartilhar_test.sh` | 72 | TC-LTP-01..10, TC-CMP-01..16, TC-SNH-01..14, TC-LEX-01..12 (+ `missing_scope` na listagem), TC-LST-01..10, TC-RVG-01..12 (sem 11 isolado: coberto em CMP-04), TC-SHE-02..05, TC-CPL-10, TC-DOC-04, TC-TST-08, ordem do ponto unico (DIV-121) |
| `tests/integracao/diagnostico_compartilhamento_test.sh` | 2 | TC-DIA-17, TC-DIA-18 |

Duble de `curl` por regra (modelo de `recuperacao_test`) que registra, por invocacao: corpo, `argv` (o dele e os de `/proc` dos dois processos acima), ambiente (o dele e o `environ` do processo do `dbx`) e a entrada `-K -`; `date` proibido por duble; `TMPDIR` privado; `setsid` para `TERM`; `script(1)` + `mkfifo` para o terminal, com a resposta escrita so depois da pergunta (sem eco espurio).

## Gate 1 — protocolo-tdd

**Parecer: APROVADO, sem achado bloqueante.**

Red confirmado contra `e42168f` (arvore da base por `git archive e42168f` com os tres arquivos de teste copiados, cada caso rodado isolado):

- `compartilhamento_test`: 16 de 16 reprovam.
- `diagnostico_compartilhamento_test`: 2 de 2 reprovam.
- `compartilhar_test`: 68 de 71 reprovam. Os 3 verdes na base sao de ausencia (`ltp02`, `cmp04`, `cmp06_07`: a base recusa o comando desconhecido com 2 e zero chamadas); a discriminacao deles vem dos mutantes abaixo (M8) e da execucao verde com a implementacao. `snh11` estava verde na base e foi reforcado (exige a chamada e o eco de `link_password` no diagnostico): agora reprova na base.

Green:

- Selecao pelo mapa (`compartilhamento_test`, `compartilhar_test`, `diagnostico`, `cli_test`, `composicao`, `tmp_test`, `json_test`, `http_test`, `preflight`, `errors`, `completar`, `comandos`, `config`, `cmd_test`, `filtro`, `banda`, `recuperacao`, `auth_test`): todos APROVADA.
- `shellcheck lib/*.sh commands/*.sh bin/* scripts/*.sh`: 0 achado (os tres testes novos tambem).
- `bash scripts/verificar-remocao-de-casos.sh`: nenhuma reducao.
- Suite completa `bash tests/run.sh < /dev/null`: APROVADA, 51 arquivos, 1490 casos aprovados, 0 reprovados, 2 pulados (pre-existentes), 13 min.

Correcao da DIV-123 (decidida na memoria `2026-10-20-1110-compartilhamento`, antes da validacao do QA):

- Caso novo `teste_div123_caminho_relativo_e_uso_invalido_em_todo_modo` (`compartilhar_test`): relativo sai 2 e sem rede em `--listar`, no alias `--list`, no criar, no `link-temporario` e no `--revogar`. O `--revogar` recebe URL e nao caminho, e a URL relativa ja e recusada pela validacao (2).
- **Red:** reprovou antes da correcao (`--listar docs` saia 13 pelo ponto unico).
- **Correcao:** `commands/compartilhar.sh` recusa o relativo do `--listar` com 2 antes do ponto unico, como ja faziam o criar e o `link-temporario`. Os comentarios dos tres pontos citam a DIV-123.
- **Green:** `bash tests/run.sh compartilh` APROVADA (3 arquivos, 90 casos); shellcheck sem achado; `verificar-remocao-de-casos` sem reducao.

Mutantes dos P0 (copias integrais em `/tmp/.../scratchpad/mutantes/`, script `scratchpad/mutantes.sh` da sessao):

| Id | P0 | Mutacao | Morto por |
|---|---|---|---|
| M1 | 1 senha | `export senha` depois da leitura | `compartilhar_test` (env.log do duble) |
| M2 | 1 senha | corpo em cabecalho no `argv` do `curl` | `compartilhar_test` (argv.log) |
| M3 | 1 senha | `link_password` fora das chaves sensiveis | `snh11` |
| M4/M4b | 1 senha | motivo de recusa cita a senha | `compartilhamento_test` (`snh05_06`); na ponta a ponta a guarda de linha de lib/output ja suprime a mensagem com byte de controle (dupla barreira) |
| M5 | 2 revogar | revoga sem conferir a raiz | `rvg02` |
| M6 | 2 revogar | `path_lower` ausente autoriza com raiz `/` | `rvg03` |
| M7 | 2 revogar | autorizacao lida de arquivo em `XDG_STATE_HOME` | `rvg04` |
| M8 | 3 visibilidade | `--publico` por omissao | `cmp01` |
| M9 | 2/listar | confinamento por prefixo textual | `lst04_05_rvg12` (unidade) |

Achados:

- **Nenhum bloqueante.**
- **Menor (registrado):** TC-CMP-07 pede "relogio fixado por duble"; o relogio e o `printf '%(...)T'` do proprio shell, sem ponto de injecao. Os casos usam carimbos relativos ao relogio real (passado, agora+30 s, agora+600 s, faixa de `7d`/`48h`), o que prova o mesmo criterio sem duble.
- **Menor:** os avisos com terminal (`--publico` e o do link temporario, condicionados a `-t 2`) nao tem caso; o caminho sem terminal (a suite) prova que nao poluem stderr.
- Piramide: unidade (16) cobre as regras puras; integracao (73) cobre ligacao e P0. Sem E2E/Testcontainers: stack shell sem banco nem UI (mesma adaptacao das fases anteriores).

## Ciclo 2 (QA-B5-01..07)

A suite do QA `tests/integracao/qa_compartilhamento_b5_test.sh` nao foi alterada (sha256 `72f035f8...`).

| Achado | Red antes da correcao | Correcao | Green |
|---|---|---|---|
| QA-B5-01 | `qa_x02` reprovava | `_dbx_cmd_compartilhar_antes_depois` compara a visibilidade resolvida do depois com a pedida: `visibilidade_pedida` e aviso "o servico aplicou X no lugar de Y", saida 0 como na criacao; `senha_redefinida=sim` so quando o depois tem senha | `qa_x02` ok |
| QA-B5-02 | `qa_s04` reprovava | `_dbx_cmd_compartilhar_mascarar_senha`, logo depois de `create` e de `modify`, troca o VALOR da senha por `[REDIGIDO]` nos canais que chegam ao diagnostico (`DBX_HTTP_RESUMO_DE_ERRO`, `_DO_SERVICO`, `_DIAGNOSTICO`, `_CORPO`, `DBX_CMD_FALHA_MOTIVO`). So substituicao de parametro do shell, enquanto a senha ainda e o `local` da execucao: nada vai a argv nem ao ambiente | `qa_s04` ok |
| QA-B5-03 | `qa_l03` girava ate o teto (124) | no `--listar`, pagina sem item com `has_more` verdadeiro e pagina que nao avanca: 10 | `qa_l03` ok |
| QA-B5-04 | `qab5_04` (novo) reprovava | a recusa de URL corta a credencial embutida do host e diz "com credencial embutida (omitida)" | ok |
| QA-B5-05 | `qab5_05` (novo; o duble registra o modo do arquivo de corpo no instante da chamada) reprovava com 644 | `lib/http` escreve o arquivo de corpo num subshell com `umask 077`: nasce 0600, mascara do processo intacta (RNF-29(a)). Resto apos SIGKILL fica como limitacao do RSK-58 | ok |
| QA-B5-06 | `qab5_06` (novo) reprovava (saia 0 sem nada) | `link-temporario`: link com byte de controle ou que nao e `https://` e resposta malformada: 10, sem imprimir | ok |
| QA-B5-07 | `qab5_07` (novo) reprovava (saia 0 com `url=` vazio) | `create` e `modify` bem sucedidos sem `url` (ou com url malformada): 10 | ok |

Teste proprio ajustado: `lst06` (deste ciclo de desenvolvimento, nao aprovado em ciclo anterior) tinha pagina vazia com `has_more`; pela decisao de QA-B5-03 ela agora sai na primeira pagina, entao as paginas do caso passaram a ter um link cada, e o caso continua provando o cursor repetido. Nenhum teste aprovado alterado.

Verificacoes: `bash tests/run.sh compartilh` APROVADA (4 arquivos, 126 casos); `bash tests/run.sh qa_` APROVADA (13 arquivos, 279 casos); `json` APROVADA (62); shellcheck sem achado; `verificar-remocao-de-casos` sem reducao; suite completa `bash tests/run.sh < /dev/null` APROVADA (52 arquivos, 1527 aprovados, 0 reprovados, 2 pulados pre-existentes).

Conformidade: nenhum `$(...)` novo em `lib/`; o subshell de `lib/http` so isola a mascara; a mascaracao por valor usa a variavel `local` ja aceita pela DIV-110, sem canal publico novo. Sem DIV nova.

## Ciclo 3 (QA-B5-08..16; DIV-128)

Suite do QA `qa_compartilhamento_b5_test.sh` intacta (sha256 `97935ad1...`).

| Achado | Red | Correcao | Green |
|---|---|---|---|
| QA-B5-08 | `qa_c01` | a classificacao (reuso, plano, corrida) usa o resumo ORIGINAL; a mascara por valor roda depois, so nos canais | `qa_c01` ok |
| QA-B5-09 | `qa_c03` | com a senha no pedido (criar/modificar com `--senha*`), `_dbx_cmd_compartilhar_recusa ... sim` nao cita texto do servico: so mensagem propria, `codigo HTTP N` e a tag de `dbx_errors_tag_reconhecida` (novo em `lib/errors`, vocabulario fechado da tabela). Sem leitura de `required_scope` do corpo nesse modo | `qa_c03` ok |
| QA-B5-11 | `qa_c04` | a recusa de URL cita o host so se casa `^[A-Za-z0-9.-]+(:[0-9]+)?$` e o esquema so se casa `^[a-z]{1,16}$`; senao `(omitido)` | `qa_c04` ok |
| QA-B5-12 | `qa_c07` | 2xx com corpo malformado em create, modify e revoke devolve o 10 de lib/cmd, sem a segunda mensagem; a recusa nunca usa a classe `sucesso` | `qa_c07` ok |
| QA-B5-13 | `qab5_13` (novo) | link listado sem `url` (ou malformada) no reuso: 10, sem `modify` | ok |
| QA-B5-14 | `qab5_14` (novo; o duble ganhou `@N@` = numero da chamada) pendurava | `--listar` com teto de 1000 paginas: 10 "listagem nao terminou em 1000 paginas" | ok (1000 chamadas exatas) |
| QA-B5-15 | `qab5_15` (novo) | `link-temporario` e url de link com espaco: 10 | ok |
| QA-B5-16 | `qab5_16` (novo) | `password` com `require_password false` na criacao e no modify: 10 com "confira o link com dbx compartilhar --listar" | ok |
| `lst06` | mutante pendurava | `_rodar` do `compartilhar_test` com `timeout` (60 s, `DBX_T_TETO`) e falha explicita em 124/137 | o mutante "sem cursor visto" agora REPROVA ("o comando pendurou (124)") |

Testes proprios ajustados: `snh11` (deste ciclo de desenvolvimento) exigia `link_password` no diagnostico; pela decisao de QA-B5-09 passou a exigir `codigo HTTP 400` e nenhum trecho do corpo. Nenhum teste aprovado alterado.

**DIV-128 (nova, conflito na suite do QA):** `qa_c02_mascara_com_metacaracteres` exige que o "resto da mensagem" do servico (`y`) apareca em stderr quando a senha foi enviada. A decisao de QA-B5-08/09 proibe citar qualquer texto do servico nesse caso. `c02` reprova so na assercao `assert_contem 'y'`; as assercoes de seguranca dele (`assert_segredo_ausente`) passam. Nao foi contornado (por exemplo, pondo um `y` na mensagem). Pede decisao do Tech Lead e ajuste do caso pelo QA.

Verificacoes: `compartilhar_test` APROVADA; suite do QA caso a caso: 39 de 40 (so `c02`, DIV-128); `json` e `http` APROVADAS; shellcheck sem achado; `verificar-remocao-de-casos` sem reducao. Suite completa `bash tests/run.sh < /dev/null`: REPROVADA so por `qa_c02` (bail no 39o arquivo, 1126 ok antes); os outros 51 arquivos, rodados um a um, todos APROVADOS.

## Ciclo 4 (QA-B5-17..19; DIV-129)

Suite do QA intacta (sha256 `8adf6802...`).

| Achado | Red (caso novo em `compartilhar_test`) | Correcao | Green |
|---|---|---|---|
| QA-B5-17 | `qab5_17` (senha `banned_member`, tag `banned_member`) citava a tag | a tag reconhecida so e citada se diferente da senha enviada | ok (sai 6, `codigo HTTP 409`, sem a tag) |
| QA-B5-18 | `qab5_18` (U+00A0 no link temporario; U+2028 na url criada; U+00A0 na url reusada e na do modify) saia 0 | `^[!-~]+$` sob `LC_ALL=C` no link do `link-temporario` e em `_dbx_cmd_compartilhar_url_valida` (criar, reusar, modificar): fora disso, 10 | ok |
| QA-B5-19 | `qab5_19` (`public`/`team_only` com `true`, `team_and_password` com `false`, na criacao e no modify) saia 0 | `_dbx_cmd_compartilhar_coerente` generalizado: {password, team_and_password} se e somente se `require_password`; incoerente: 10 com "confira o link com dbx compartilhar --listar". `team_and_password` com `true` segue 0 | ok |

**DIV-129 (nova, reuso de link incoerente):** a decisao pede 10 tambem no reuso, mas `qa_x01` (suite intacta) exige que um link existente `public` com `require_password true`, pedido `--publico`, seja MODIFICADO (saida 0). Os dois cabem juntos: um link incoerente nunca e igual ao pedido, entao nunca e devolvido como esta; ele cai no `modify`, cuja resposta e conferida (10 se continuar incoerente). A guarda tambem foi posta no ramo do reuso sem escrita, que um link incoerente nao alcanca. O `qab5_19` prova o reuso por esse caminho. Pede confirmacao do Tech Lead.

Verificacoes: `compartilh` APROVADA (4 arquivos, 144 casos); `qa_` APROVADA (13, 290), inclusive a suite do QA inteira; `json` (62) e `http` (53) APROVADAS; shellcheck sem achado; `verificar-remocao-de-casos` sem reducao; suite completa APROVADA (52 arquivos, 1545 aprovados, 0 reprovados, 2 pulados pre-existentes).

Parecer gate 1 (protocolo-tdd): APROVADO nos ciclos 1 a 4, sem achado bloqueante. A DIV-128 foi decidida pelo Tech Lead (o QA ajustou o `qa_c02`, reaprovado pelo solicitante) e a DIV-129 foi aceita.
