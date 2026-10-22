# Parecer de Conformidade — Link temporario e link compartilhado (fase 5)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: link temporario de download e link compartilhado com expiracao, senha ou audiencia (F-15, F-16); porte **G**
- Agent responsavel pela alteracao e pela verificacao: Senior Developer (gate local, regra 14); validacao independente a cargo do QA Expert
- Data: 2026-10-20
- Ciclos: 4 (ciclo 1 inicial, com a correcao da DIV-123 antes do QA; ciclo 2 apos a reprovacao QA-B5-01..07; ciclo 3 apos QA-B5-08..16 e DIV-128; ciclo 4 apos as ressalvas QA-B5-17..19 e DIV-129)
- Branch / base: `feature/compartilhamento-b5` sobre `develop` @ `e42168f`, sem commit
- Log de prompt: [2026-10-20_1110_backlog-fase-5-compartilhamento.md](../prompts/2026-10-20_1110_backlog-fase-5-compartilhamento.md)
- Registro de entrega: [2026-10-20-1110-registro-compartilhamento-b5.md](2026-10-20-1110-registro-compartilhamento-b5.md)
- Tambem: [2026-10-20-1110-parecer-tdd-compartilhamento-b5.md](2026-10-20-1110-parecer-tdd-compartilhamento-b5.md)
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

Testes novos: `tests/unit/compartilhamento_test.sh` (16), `tests/integracao/compartilhar_test.sh` (72 no ciclo 1), `tests/integracao/diagnostico_compartilhamento_test.sh` (2). Nenhum teste aprovado alterado ou removido.

## Gate 2 — protocolo-conformidade

**Parecer: APROVADO, sem achado bloqueante; achados maiores ja decididos como DIV-121..127.**

Arquitetura:

- `lib/compartilhamento` e puro (sem rede, disco ou estado), camada de dominio, depende de errors/path/json/filtro; reusa `dbx_filtro_validar_data` (sem gemeo de validacao de data) e `dbx_path_remoto_confinar` (mesma dobra so ASCII de RNF-20(b4), DIV-118).
- Rede so por lib/auth -> lib/http; corpo por arquivo da area de lib/http (`--data-binary @`), limpo por chamada (DIV-95 intacto). Escritas pelo ponto unico `_dbx_cmd_escrita_remota` (agora com idempotencia declarada); leituras por `dbx_auth_requisitar`.
- Caminho do operador pelo ponto unico `_dbx_cmd_caminho_remoto` antes de qualquer rede; caminho devolvido pela API confinado por `dbx_compartilhamento_confinado` (presente, absoluto, por componente).
- Nenhum `mktemp`/`trap` fora de lib/tmp; nenhum `$(...)` novo em lib/ capturando bytes externos (os dois de lib/compartilhamento sao `cd -P` do proprio diretorio e o codigo da taxonomia); nenhum `grep -c` em teste; nenhum estado persistente; sem trava; codigos so de 0..15.
- Leitura sem eco unica em lib/cli (`config` migrou); eco restaurado pelo proprio `read -s` (medido em pseudo-terminal com TERM), sem `stty` (fora do preflight, RNF-02).

Seguranca (P0):

1. **Senha:** so `read` embutido; variavel `local` do comando, apagada apos a chamada e em toda recusa; escape por lib/json com `DBX_JSON_ESCAPADO` esvaziado na hora; nunca em argv, ambiente, `-K -`, saida, `--debug`, `--json`, `--null`, erro ou arquivo restante (provado com sentinela, inclusive apos `TERM` durante a chamada). Formas `--senha=V` e opcoes desconhecidas com `=` sao recusadas sem citar o valor; posicional excedente so e contado. `link_password` mascarado pela redacao.
2. **Revogar:** URL validada antes da rede (host exato, prefixo, sem espaco/controle, ate 2048); guarda por `get_shared_link_metadata` da mesma execucao: chave repetida ou documento malformado -> 10; `path_lower` ausente/nulo -> 13 mesmo com raiz `/`; vazio ou nao texto -> 10; fora da raiz -> 13; `revoke_shared_link` so depois. `--dry-run` executa a guarda.
3. **Visibilidade:** sem `--publico`/`--equipe`/`--senha*` sai 2 antes de rede e de leitura de senha.

Achados:

- **Nenhum bloqueante.**
- **Maior:** DIV-121 a DIV-127, ja decididas na memoria; a DIV-123 foi corrigida no ciclo 2 (relativo = 2 tambem no `--listar`) (auditoria de ponto unico, redacao de "Basic", relativo = 2, `list_shared_links` sem `limit`, vocabulario de `resolved_visibility`, eco sem acao registrada, idempotencia das escritas).
- **Menor:** `dbx link_temporario` (nome do arquivo) e aceito como terceira grafia, exigencia de `cli_test` (todo arquivo de `commands/` tem nome valido).
- Documentacao de arquitetura e escopo (system design v1.13, secao 5.13) nao foram editadas aqui: ficam com BA/documentation-writer, que devem marcar `lib/compartilhamento` como implementado e incorporar DIV-121..127.

Nota do registro: o "ciclo 2" citado no achado Maior e a correcao da DIV-123, feita antes da validacao do QA (ver a identificacao). A DIV-121..127 foi depois propagada pelo BA ao escopo v1.18 (terceira rodada).

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

Parecer gate 2 (protocolo-conformidade): APROVADO nos ciclos 1 a 4. A guarda do `--revogar` continua sem estado local; a senha so vive na variavel `local` da execucao; com a senha no pedido, nenhum texto do servico chega ao stderr nem ao `--debug`; nenhuma captura nova em `lib/`. DIV-128 e DIV-129 decididas pelo Tech Lead.
