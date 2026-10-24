# Registro de entrega: teste de disponibilidade (entrega completa)

Log de prompt: `docs/prompts/2026-10-23_0900_teste-de-disponibilidade.md`. Porte M. Preenchido pelo Senior Developer so nas secoes do gate de testes e dos arquivos; o restante e do Tech Lead.

## Resumo da decisao

- Entrega: `dbx testar` (alias `check`) com checagens de internet (sonda neutra), servico Dropbox e credencial; checagem automatica nos comandos de nivel `credencial`, sem chamada extra no caminho feliz.
- Na falha, a causa e nomeada: sem internet, Dropbox inacessivel, servico indisponivel (5xx), credencial ausente ou invalida.
- Credencial ausente ou invalida com terminal interativo: oferta `[s/N]` de `dbx config`; configurado, o comando continua (ou as checagens sao refeitas, no `testar`). Sem terminal: codigo e mensagem de hoje, sem leitura de stdin.
- Variaveis opcionais: `DBX_TESTE_INTERNET_URL` (sonda; vazia desliga, com aviso, DIV-324); `DBX_TESTE_CONFIG` (`nao` fecha o portao da oferta).
- Divergencias decididas pelo solicitante (prompt log e registro): DIV-327 corrigir; DIV-328 manter; DIV-329 estender; DIV-330 opcao C (sem mudanca de codigo); DIV-331 opcao A, esperar o resultado da sonda (`DBX_DISP_ESPERA_MS`, padrao 10000).

## Arquivos alterados (conjunto final)

Conferido pelo Tech Lead com `git status --short` contra `develop` @ `877b708`.

- Codigo novo: `lib/disponibilidade.sh` (sonda memoizada e compartilhada entre processos, classificacao e mensagens, portao e oferta do `config`, aviso de URL invalida); `commands/testar.sh` (`dbx testar`/`check`).
- Codigo alterado: `lib/http.sh` (`dbx_http_sondar`, `--debug` mascarado); `lib/auth.sh` (ganchos registrados, classe, motivo e codigo HTTP do token, acessores); `lib/cmd.sh` (`_dbx_cmd_consultar` e `dbx_cmd_falha_registrar` pela classe do token); `lib/cli.sh` (`testar`/`check`); `bin/dbx` (ajuda, `dbx_iniciar_config`, oferta no despacho, registro dos ganchos, portao de stdin); `commands/sync.sh` (semeadura da sonda e emissao do aviso); `commands/revisoes.sh`, `commands/lixeira.sh`, `commands/restaurar.sh` (DIV-327); `completions/dbx.bash`.
- Testes: `tests/unit/disponibilidade_test.sh`, `tests/integracao/testar_test.sh`, `tests/integracao/disponibilidade_automatica_test.sh`, `tests/support/disponibilidade.sh` (novos); `tests/integracao/qa_disponibilidade_b11_test.sh` (suite do QA, sha256 `ffe3ef0ea7f4cf69d96465d2960828b30597b9735ec88412ca2231e4a3db96ec`); `tests/integracao/composicao_test.sh` (canais da sonda sem credencial).
- Documentacao: `README.md` (secao "Teste de disponibilidade"); `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` (secao 5.20, v1.28, DIV-307..331); `docs/requisitos/funcionalidades-candidatas.md` (F-50); `docs/arquitetura/system-design.md` (linha `testar`); `docs/testes/mapa-modulos.md` (fase 11).
- Trilha: este registro; `docs/reviews/2026-10-23-0900-validacao-qa-teste-de-disponibilidade.md`; `docs/prompts/2026-10-23_0900_teste-de-disponibilidade.md`; memoria `.github/agents/memoria/entradas/2026-10-23-0900-teste-de-disponibilidade.md` e `2026-10-23-0900-aceite-remocao-arquivo-alheio.md`.

## Riscos residuais e recomendacoes

- Recomendacoes da conformidade (menores, fora desta entrega; detalhe nas rodadas 3 a 5): R3, remedio de `ligacao_simbolica` no `testar` decidido por `[[ -L ]]` (o limpo e `lib/config` publicar `DBX_CONFIG_DETALHE`); R4b, URL de sonda malformada com `@` cru seguido de delimitador cru imprime no `--debug` o host que o curl usaria; R5a, aviso de URL invalida perdido com stderr fechado (`2>&-`) ou deixado na marca pelo principal depois do ultimo `wait` do `sync`.
- P2 do QA (`docs/reviews/2026-10-23-0900-validacao-qa-teste-de-disponibilidade.md`): remedio de `invalid_grant` sem terminal e a mensagem atual ("autorize de novo"), e RF-150(c) pede remedio acionavel (sugestao ao BA, nao bloqueia); RF-149(b) deve citar as duas metades (automatico sai 9 e `testar` sai 2); o duplo de curl nao prova o curl real com URL contendo aspas ou quebra de linha.
- Aceite do solicitante da suite do QA: concedido em 2026-10-23 (regra 12), sha256 `ffe3ef0ea7f4cf69d96465d2960828b30597b9735ec88412ca2231e4a3db96ec`.

## Rollback

Reverter o merge (`git revert -m 1 <sha-do-merge>`). Nao ha migracao de dado nem de configuracao: `DBX_TESTE_INTERNET_URL` e `DBX_TESTE_CONFIG` sao opcionais.

## Gate protocolo-tdd (testes)

Red: `disponibilidade_test` e `testar_test` reprovaram antes de lib e comando existirem. Selecao: modulos atingidos (lib/http, lib/cli, bin, commands, completions) e os testes que auditam lib/ inteiro. Parada no primeiro erro: `tests/run.sh` (Regra 9), sem interrupcao na execucao final.

| Comando | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| `bash tests/run.sh testar_test` | 21 | 21 | 0 | 0 |
| `bash tests/run.sh disponibilidade_test` | 8 | 8 | 0 | 0 |
| `bash tests/run.sh preflight_test` (auditoria de comandos de lib/) | 35 | 35 | 0 | 0 |
| `bash tests/run.sh json_test` (auditoria de massa por substituicao) | 62 | 62 | 0 | 0 |
| `bash tests/run.sh composicao_test` | 28 | 28 | 0 | 0 |
| `bash tests/run.sh tmp_test` | 16 | 16 | 0 | 0 |
| `bash tests/run.sh auth_test` | 42 | 42 | 0 | 0 |
| `bash tests/run.sh http_test` | 53 | 53 | 0 | 0 |
| `bash tests/run.sh path_test` | 58 | 58 | 0 | 0 |
| `bash tests/run.sh hash_test` | 44 | 44 | 0 | 0 |
| `bash tests/run.sh cli_test` | 27 | 27 | 0 | 0 |
| `bash tests/run.sh completar_test` | 17 | 17 | 0 | 0 |
| `bash tests/run.sh comandos_test` | 119 | 119 | 0 | 0 |
| `bash tests/run.sh qa_docs_aliases_p4` | 16 | 16 | 0 | 0 |
| `bash tests/run.sh diagnostico_test` (RF-154(e)) | 16 | 16 | 0 | 0 |
| `bash tests/run.sh harness_test` | 22 | 22 | 0 | 0 |

Lint (`sh scripts/lint.sh <arquivo>`, um por vez): limpo em `commands/testar.sh`, `lib/disponibilidade.sh`, `lib/http.sh`, `lib/cli.sh`, `bin/dbx`, `tests/unit/disponibilidade_test.sh`, `tests/integracao/testar_test.sh`. `completions/dbx.bash` nao passou pelo lint.

Regra 6: nenhum sentinela (segredo, chave, refresh, token) na saida em texto, `--json`, `--null` e `--debug`, nem nas opcoes da sonda e do servico (duplo de `curl` grava o `-K`); sem terminal, nenhum byte de stdin lido (`cat` apos o comando devolve a entrada inteira). Terminal: script(1) com Ctrl-D (o util-linux 2.41 nao converte EOF da fifo) e `timeout -s KILL 20`.

Cobertura: TC-DSP-01..12, 13..17, 19, 22..26, 55, 57, 58 e TC-DSP-10 (recusa, fim de entrada, aceite com cancelamento, aceite com config bem-sucedido e checagens refeitas, portao fechado por `DBX_TESTE_CONFIG=nao` e `--dry-run`).
Nao cobertos nesta tarefa (os restantes de 37..43, 45, 46, 50..54, 57..60 e 64 foram cobertos na Tarefa 4; seguem 18, 20, 21, 27, 56 e 61..63 conforme abaixo, exceto o que a Tarefa 4 disser): TC-DSP-18 (DNS/TLS/tempo distintos, so "sem resposta" generico), 20 (proxy), 21 (sonda unica entre varias falhas, so a memoizacao unitaria), 27 (so as mensagens da lib), 56, 59 (so `diagnostico_test` existente verde), 60 (processos/tmp em sinal) e 61..64 (ajuda/README: ajuda de `testar` feita, README e `help config`/`diagnostico` fora desta retomada).

## Tarefa 2: DIV-326, checagem automatica (RF-151..154) e ajuda/README (RF-155)

Arquivos: `commands/testar.sh` (servico e servico_conteudo rodam sempre; sonda sem resposta com Dropbox respondendo = `internet=aviso`); `lib/auth.sh` (`DBX_AUTH_GANCHO_FALHA`, chamado uma vez na falha da PRIMEIRA obtencao de token); `lib/disponibilidade.sh` (`dbx_disp_ao_falhar_token`); `bin/dbx` (oferta no despacho de credencial local, `_dbx_disponibilidade_preparar`, ajuda de `config`/`diagnostico`/geral); `README.md` (secao Teste de disponibilidade); `tests/support/disponibilidade.sh` (novo: helpers e duplo de curl extraidos de `testar_test`, com papel `rpc` e `recusar_refresh`); `tests/integracao/disponibilidade_automatica_test.sh` (novo); `tests/integracao/testar_test.sh` (teste DIV-326; dsp03 passou a falhar tambem api/content); `tests/integracao/composicao_test.sh` (dois canais da sonda declarados sem credencial).

Red: `disponibilidade_automatica_test` reprovou antes da implementacao em `dsp32_invalid_grant_no_terminal_pergunta_invalida...` (sem pergunta) e em `dsp62` (ajuda sem `DBX_TESTE_CONFIG`); o runner para no primeiro erro (Regra 9), entao os demais casos novos nao tiveram red individual medido (dsp28 e dsp31 sao guardas de retrocompatibilidade, ja verdes na base por desenho). Red do DIV-326: teste novo escrito contra o comportamento de `internet=falha` descrito pelo Tech Lead; nao medido contra o codigo antigo (a implementacao foi feita no mesmo passo).

| Comando | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| `bash tests/run.sh disponibilidade_automatica_test` | 16 | 16 | 0 | 0 |
| `bash tests/run.sh testar_test` | 22 | 22 | 0 | 0 |
| `bash tests/run.sh disponibilidade_test` | 8 | 8 | 0 | 0 |
| `bash tests/run.sh preflight_test` | 35 | 35 | 0 | 0 |
| `bash tests/run.sh json_test` | 62 | 62 | 0 | 0 |
| `bash tests/run.sh composicao_test` | 28 | 28 | 0 | 0 |
| `bash tests/run.sh tmp_test` | 16 | 16 | 0 | 0 |
| `bash tests/run.sh auth_test` | 42 | 42 | 0 | 0 |
| `bash tests/run.sh http_test` | 53 | 53 | 0 | 0 |
| `bash tests/run.sh cli_test` | 27 | 27 | 0 | 0 |
| `bash tests/run.sh comandos_test` | 119 | 119 | 0 | 0 |
| `bash tests/run.sh diagnostico_test` | 16 | 16 | 0 | 0 |
| `bash tests/run.sh verificar_test` | 17 | 17 | 0 | 0 |
| `bash tests/run.sh recuperacao_test` | 61 | 61 | 0 | 0 |
| `bash tests/run.sh reter_test` | 84 | 84 | 0 | 0 |
| `bash tests/run.sh compartilhar_test` | 83 | 83 | 0 | 0 |
| `bash tests/run.sh cursor_test` | 48 | 48 | 0 | 0 |
| `bash tests/run.sh qa_consulta_diagnostico_b1_test` | 21 | 21 | 0 | 0 |
| `bash tests/run.sh qa_compartilhamento_b5_test` | 43 | 43 | 0 | 0 |
| `bash tests/run.sh qa_retencao_b6_test` | 60 | 60 | 0 | 0 |
| `bash tests/run.sh perfis_test` | 40 | 40 | 0 | 0 |

Cobertura nova: TC-DSP-28..32 (caminho feliz com 2 requisicoes, sem sonda nem content; sem terminal sem pergunta, sem sonda e sem ler stdin), 33/34 (sonda decide sem internet x Dropbox inacessivel; 5xx sem sonda), 35/36 (pergunta ausente/invalida, recusa mantem codigo), 44 (`upload -` sem oferta), 47..49 (aceite continua no mesmo processo, uma vez; cancelamento mantem codigo; invalid_grant aceito renova e continua), 55/56 (sentinelas fora da saida e da sonda), 62..63 (ajuda e README). Nao cobertos: TC-DSP-37..43, 45, 46, 50..54, 57..60 e 64 (perfil propagado ao config, `--json` com oferta, trava antes da oferta, processo orfao); a oferta com `--perfil` usa o mesmo caminho de `testar`, ja coberto la.

Lint (`sh scripts/lint.sh`, um por vez): limpo em `lib/auth.sh`, `lib/disponibilidade.sh`, `commands/testar.sh`, `tests/support/disponibilidade.sh`, `tests/integracao/disponibilidade_automatica_test.sh`, `testar_test.sh`, `composicao_test.sh`. `bin/dbx`: ver hand-back (o lint passa de 2 min).

## Divergencias (decididas pelo Tech Lead; a propagar ao escopo)

- DIV-320: segunda linha de servico com id `servico_conteudo`; `testar` faz 4 requisicoes (sonda, api, content, renovacao); TC-DSP-01 passa a 4 linhas.
- DIV-321: `config --substituir` aceita arquivo incompleto (nao le o antigo); nada a mudar.
- DIV-322: TC-DSP-07 vale para a saida estruturada do projeto (`contrato=1` + chave=valor).
- DIV-323: `TERM` indefinido conta como `dumb` (portao fechado).
- DIV-324: sonda desligada: `internet` sai `aviso` e as checagens seguem.
- DIV-325: lib/ nao carrega commands/; `bin/dbx` define `dbx_iniciar_config`, chamada por nome por `lib/disponibilidade` (sem ela, portao fechado).
- DIV-327 (solicitante): corrigir; falha da renovacao nos comandos de consulta sai pela classe do token (5) e recebe a oferta de config.
- DIV-328 (solicitante): manter; qualquer resposta HTTP do Dropbox prova a internet.
- DIV-329 (solicitante): estender; causa nomeada tambem em `DBX_AUTH_MOTIVO` e na falha no meio da execucao (RF-151(e)).
- DIV-330 (solicitante): C, `config` sob a trava do par; com `invalid_grant` em `sync`/`verificar` a unica trava viva durante o `config` e a do proprio comando (RF-69(b)), e o `config` nao adquire trava. `TC-DSP-54` reescrito; sem mudanca de codigo.

## Tarefa 3: DIV-327 e DIV-329

Arquivos: `lib/auth.sh` (`_dbx_auth_classe_de`, `dbx_auth_falha_e_do_token`, `dbx_auth_falhar_com`; `_dbx_auth_com_renovacao` publica `DBX_AUTH_CLASSE` na falha do token e chama `DBX_AUTH_GANCHO_MEIO` na falha da requisicao); `lib/cmd.sh` (`_dbx_cmd_consultar` sai pela classe e motivo do token); `lib/disponibilidade.sh` (causa tambem em `DBX_AUTH_MOTIVO`; `dbx_disp_ao_falhar_chamada`); `bin/dbx` (arma `DBX_AUTH_GANCHO_MEIO` em `_dbx_disponibilidade_preparar`); `tests/integracao/disponibilidade_automatica_test.sh` (dois casos de DIV-327 ajustados para 5; quatro casos novos). Os acessos a `DBX_AUTH_*` ficam em funcoes de `lib/auth.sh` para `lib/cmd.sh` nao passar a "lidar com credencial" na auditoria de `composicao_test`.

Red (medido por caso, filtro de caso do harness): reprovaram antes do codigo os seis casos `dsp32_invalid_grant_sem_terminal...` (esperado 5, obtido 2), `dsp32_invalid_grant_no_terminal...` (esperado 5, obtido 2), `dsp33_upload_falha_de_rede_na_renovacao_nomeia_a_causa_no_motivo`, `dsp33_falha_de_rede_na_chamada_do_comando_nomeia_sem_oferta_e_mantem_9`, `dsp33_falha_de_rede_na_chamada_do_comando_com_internet_diz_dropbox_inacessivel` e `dsp34_5xx_na_chamada_do_comando_diz_servico_indisponivel_sem_sonda` (causa nao nomeada). Guardas dsp28/dsp31 (RF-151(g)) verdes durante todo o ciclo.

| Comando | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| `bash tests/run.sh disponibilidade_automatica_test` | 20 | 20 | 0 | 0 |
| `bash tests/run.sh testar_test` | 22 | 22 | 0 | 0 |
| `bash tests/run.sh disponibilidade_test` | 8 | 8 | 0 | 0 |
| `bash tests/run.sh composicao_test` | 28 | 28 | 0 | 0 |
| `bash tests/run.sh cmd_test` | 23 | 23 | 0 | 0 |
| `bash tests/run.sh auth_test` | 42 | 42 | 0 | 0 |
| `bash tests/run.sh http_test` | 53 | 53 | 0 | 0 |
| `bash tests/run.sh cli_test` | 27 | 27 | 0 | 0 |
| `bash tests/run.sh comandos_test` | 119 | 119 | 0 | 0 |

Cobertura nova: TC-DSP-32 (invalid_grant sai 5 em `space`, sem e com terminal), TC-DSP-33 (upload via `dbx_auth_preparar` nomeia a causa; falha de rede na chamada do comando nomeia por sonda unica, sem oferta, codigo 9, chamada nao repetida; com internet diz Dropbox inacessivel), TC-DSP-34 (5xx na chamada: servico indisponivel, sem sonda, codigo 10). Nao coberto: a causa nomeada nos demais comandos que imprimem `DBX_AUTH_MOTIVO` (`sync`, `download`), pelo mesmo caminho do `upload`.

Lint (`sh scripts/lint.sh`, um por vez): limpo em `lib/auth.sh`, `lib/cmd.sh`, `lib/disponibilidade.sh`, `tests/integracao/disponibilidade_automatica_test.sh`. `bin/dbx` (uma linha) fica com o Tech Lead.


## Ajuste do Tech Lead: lint de `bin/dbx`

Causa: `dbx_iniciar_config` e o carregamento de `lib/disponibilidade.sh` em `bin/dbx` declaravam `source=commands/config.sh` e `source=lib/disponibilidade.sh`; com `external-sources=true`, o `shellcheck` de `bin/dbx` reanalisava as duas cadeias e passava do teto de 12288 MB (interrompido na branch; na `develop` @ `877b708`, rc 0). Correcao: `source=/dev/null` nos dois pontos, como ja fazem os comandos do despacho (os dois arquivos tem lint proprio), e `disable=SC2034` para `DBX_DISP_CONSOME_STDIN`, lida por `lib/disponibilidade.sh`. Sem mudanca de comportamento.

| Verificacao | Resultado |
|---|---|
| `sh scripts/lint.sh bin/dbx` | rc 0 (31 s) |
| `sh scripts/lint.sh tests/integracao/composicao_test.sh` | rc 0 |
| `disponibilidade_automatica_test` / `testar_test` / `cli_test` / `comandos_test` / `composicao_test` | 20 / 22 / 27 / 119 / 28 aprovados, 0 falhos, 0 pulados |

## Tarefa 4: cobertura dos TC-DSP restantes

Arquivos: `tests/integracao/disponibilidade_automatica_test.sh` (de 20 para 40 casos); `tests/support/disponibilidade.sh` (duplo de curl grava as travas vivas por chamada em `travas`, `troca_falha` falha so a troca de codigo do `config`, `sonda_lenta` prende a sonda; `DBX_T_TERM`, `DBX_T_REDIR_ERR`, `DBX_T_REDIR_OUT`, `DBX_T_CTRLC` em `_rodar_tty`); `lib/auth.sh` (defeito, abaixo). Numeracao dos TC: a do escopo (secao 5.20).

Defeito corrigido (DIV-329, `download`): o `download` pede o token duas vezes antes de qualquer efeito (`get_metadata` e depois o recebimento); o gancho `DBX_AUTH_GANCHO_FALHA` so rodava na primeira falha, e a segunda sobrescrevia a causa: a saida era `recebimento recusado: sem detalhe`. Red medido: `dsp33_download_falha_de_rede_na_renovacao_nomeia_a_causa` reprovou (trecho `sem acesso a internet` ausente). Correcao minima em `dbx_auth_token`: enquanto nenhum token foi obtido, cada falha passa pelo gancho (a oferta e a sonda ja sao de uma vez so no proprio gancho, por `DBX_DISP_OFERTA_FEITA` e pela memoizacao); a marca de primeira obtencao so cai quando o token e obtido. Green: o caso e os 40 do arquivo passam; `auth_test`, `cmd_test`, `cli_test`, `comandos_test`, `composicao_test` verdes. `sync` ja nomeava a causa (caso novo e verde de primeira).

| TC | Caso de teste | Resultado |
|---|---|---|
| 37 | `dsp37_stderr_em_arquivo_nao_pergunta` | cobertura (verde de primeira) |
| 38 | `dsp38_term_dumb_nao_pergunta` | cobertura |
| 39 | `dsp39_enter_n_x_e_fim_de_entrada_recusam_com_o_codigo_original` | cobertura |
| 40 | `dsp40_s_maiusculo_e_sim_aceitam_a_oferta` (o `s` ja estava em `dsp47`) | cobertura |
| 41 | `dsp41_arquivo_incompleto_aceito_e_substituido` (prova `--substituir` pelo efeito: sem ele o `config` recusa o arquivo existente) | cobertura |
| 42 | `dsp42_perfil_aceito_grava_so_o_perfil_pedido` | cobertura |
| 43 | `dsp43_upload_de_fluxo_com_terminal_nao_pergunta_nem_le_a_entrada` | cobertura |
| 45 | `dsp45_dbx_teste_config_nao_nao_pergunta` | cobertura |
| 46 | `dsp46_json_com_oferta_aceita_stdout_so_o_json` (stdout em arquivo, pty so no stderr; a "saida JSON" e a estruturada `contrato=1`, DIV-322) | cobertura |
| 50 | `dsp35_...recusa_mantem_3` e `dsp32_...recusa_mantem_o_codigo` (codigos 3 e 5, remedio, "nenhuma alteracao feita"), reforcados por `dsp39` | cobertura (casos ja existentes) |
| 51 | `dsp48` (fim de entrada, codigo 3) e `dsp51_sigint_dentro_do_config...` (Ctrl-C: comando nao executa, nada gravado) | cobertura; o codigo de saida de SIGINT nao e observavel sob o pty (o grupo inteiro morre), so o de fim de entrada |
| 52 | `dsp52_falha_de_rede_no_config_mantem_codigo_e_mensagem_do_config` | cobertura |
| 53 | `dsp53_config_substituir_que_falha_preserva_a_credencial_anterior` (retrato byte a byte do diretorio de config) | cobertura |
| 54 | `dsp54_oferta_aceita_nao_adquire_trava_antes_e_o_comando_adquire_depois` (credencial ausente, `sync`) | cobertura; o caso `invalid_grant` em `sync` **nao** vale: ver DIV-330 |
| 57 | `dsp57_sonda_e_servico_nao_levam_segredo_nem_cabecalho_de_autorizacao` | cobertura |
| 58 | `dsp58_sem_terminal_nenhum_byte_de_stdin_nos_caminhos_de_falha` (`invalid_grant` e rede com sonda sem resposta) | cobertura |
| 59 | `dsp59_diagnostico_nunca_oferece_o_config`; a igualdade antes/depois e de `diagnostico_test` (16 verdes) | cobertura parcial; `info` recebe a oferta (nao esta na lista do TC-34): sem DIV |
| 60 | `dsp60_fim_normal_e_falha_nao_deixam_processo_nem_tmp` e `dsp60_sinal_durante_a_sonda...` (SIGTERM no grupo com sonda presa) | cobertura |
| 64 | `dsp63_readme...` reforcado (terceiro e `gstatic`); `help diagnostico` ja em `dsp62` | cobertura |
| DIV-329 `sync` | `dsp33_sync_falha_de_rede_na_renovacao_nomeia_a_causa` | cobertura |
| DIV-329 `download` | `dsp33_download_falha_de_rede_na_renovacao_nomeia_a_causa` | defeito corrigido |

DIV-330 (decidida C; ver Tarefa 4b): **DIV-330**, TC-DSP-54 x RF-69(b). No `sync` (e `verificar`) a trava do par e adquirida em `dbx_cmd_ciclo_iniciar` ANTES de `dbx_auth_preparar`. Com credencial ausente a oferta ocorre no despacho, antes do comando, e nao ha trava (caso coberto). Com `invalid_grant` a oferta ocorre na primeira obtencao de token, ja sob a trava do `sync`: a troca de codigo do `config` roda com 1 trava viva (medido com o caso removido). O TC diz "nenhuma trava antes"; RF-69(b) manda travar antes de qualquer chamada a API. Opcoes: (a) restringir o TC a credencial ausente; (b) mover a obtencao do token do `sync`/`verificar` para antes da trava (altera a ordem de RF-69(b)); (c) aceitar o `config` sob a trava (e curto, mas bloqueia outro `sync` do par durante o dialogo).

| Comando | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| `bash tests/run.sh disponibilidade_automatica_test` | 40 | 40 | 0 | 0 |
| `bash tests/run.sh testar_test` | 22 | 22 | 0 | 0 |
| `bash tests/run.sh comandos_test` | 119 | 119 | 0 | 0 |
| `bash tests/run.sh composicao_test` | 28 | 28 | 0 | 0 |
| `bash tests/run.sh auth_test` | 42 | 42 | 0 | 0 |
| `bash tests/run.sh cmd_test` | 23 | 23 | 0 | 0 |
| `bash tests/run.sh cli_test` | 27 | 27 | 0 | 0 |
| `bash tests/run.sh disponibilidade_test` | 8 | 8 | 0 | 0 |

Guardas dsp28 e dsp31 (RF-151(g)) verdes. Lint (`sh scripts/lint.sh`, um por vez): limpo em `lib/auth.sh`, `tests/support/disponibilidade.sh`, `tests/integracao/disponibilidade_automatica_test.sh`. `bin/dbx` nao foi tocado. Os antes descobertos (18, 20, 21, 27, 56) foram fechados na Tarefa 4b.

### Tarefa 4b

Arquivos: `tests/integracao/disponibilidade_automatica_test.sh` (de 40 para 44 casos); `tests/support/disponibilidade.sh` (`falha:<codigo>` escolhe o codigo de saida do curl; o duplo grava `HTTPS_PROXY` por chamada em `proxies`). Sem mudanca de codigo de producao: todos os casos passaram de primeira (cobertura de comportamento existente).

| TC | Caso de teste | Resultado |
|---|---|---|
| 54 (`invalid_grant`, DIV-330 C) | `dsp54_invalid_grant_aceito_o_config_roda_sob_a_unica_trava_do_par` (nenhuma chamada ve mais de 1 trava viva; a troca de codigo do `config` ve exatamente 1, a do par do `sync`) | cobertura (caso restaurado, agora assertando a decisao C) |
| 18 | `dsp18_falhas_de_dns_conexao_tls_e_tempo_contam_como_nao_responde` (curl 6, 7, 35, 28 -> "sem acesso a internet", codigo 9) | cobertura |
| 20 | `dsp20_sonda_usa_o_mesmo_transporte_e_nao_le_variavel_de_proxy_nova` (a sonda e a renovacao veem o mesmo `HTTPS_PROXY`; sem `--proxy`/`-x` na sonda; `lib/disponibilidade.sh` nao le variavel de proxy) | cobertura |
| 21 | integracao: `dsp33_download_falha_de_rede_na_renovacao_nomeia_a_causa` (duas falhas de token na mesma execucao, 1 sonda) e `dsp33_falha_de_rede_na_chamada_do_comando_nomeia...` (falha de token e de chamada, 1 sonda); unitario: `disponibilidade_test::teste_sonda_uma_por_execucao` | ja coberto por esses casos |
| 27 | `disponibilidade_test::teste_mensagens_sem_segredo_url_com_parametro_nem_corpo` (todas as mensagens da lib) e `dsp55`/`dsp56` (saida real) | ja coberto por esses casos |
| 56 | `dsp56_oferta_e_classificacao_nao_vazam_sentinela_na_saida_nem_no_log` (oferta aceita por `invalid_grant`, `--debug`; saida e arvore de estado sem sentinela); `dsp55` cobre a classificacao sem oferta | cobertura |

| Comando | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| `bash tests/run.sh disponibilidade_automatica_test` | 44 | 44 | 0 | 0 |
| `bash tests/run.sh testar_test` | 22 | 22 | 0 | 0 |
| `bash tests/run.sh comandos_test` | 119 | 119 | 0 | 0 |
| `bash tests/run.sh composicao_test` | 28 | 28 | 0 | 0 |
| `bash tests/run.sh disponibilidade_test` | 8 | 8 | 0 | 0 |

`composicao_test` reprovou uma vez no meio da tarefa (contagem de arquivo fora do `_harness_contar`, no meu proprio teste); corrigido e reexecutado verde. Lint limpo (um por vez) em `tests/support/disponibilidade.sh` e `tests/integracao/disponibilidade_automatica_test.sh`. Nenhum TC-DSP do escopo 5.20 segue sem caso.

## Gate protocolo-conformidade (rodada 1): REPROVADO

Revisor independente (subagent sem o contexto da implementacao), diff contra `877b708` mais nao rastreados; skills clean-architecture, security-best-practices e api-security-best-practices. Sem bloqueante; 5 importantes (regra: mais de 3 maiores reprova). Testes reexecutados pelo revisor: disponibilidade_test 8, testar_test 22, disponibilidade_automatica_test 44, composicao_test 28, todos verdes.

| # | Sev. | Local | Achado |
|---|---|---|---|
| 1 | importante | `commands/testar.sh:93` | `${DBX_CONFIG_MOTIVO/permissao/chmod 600 $arquivo}` gera remedio errado para `permissao_diretorio` e `ligacao_simbolica` |
| 2 | importante | `lib/disponibilidade.sh:79-80` | sonda memoizada por processo; auxiliares em background do `sync` herdam `nao` e cada um pode sondar (contra RF-149(g)) |
| 3 | importante | `commands/revisoes.sh:65`, `lixeira.sh:189`, `restaurar.sh:58,204`, `lib/cmd.sh:1205`, `commands/upload.sh:413` | DIV-327 corrigida so em `_dbx_cmd_consultar`; demais chamadores de `dbx_auth_requisitar` seguem com codigo 2 em `invalid_grant` (RF-150(a)) |
| 4 | importante | `lib/disponibilidade.sh:84-85,159` | URL de sonda invalida no automatico nao emite o aviso de RF-149(b)/DIV-310 A; sem teste |
| 5 | importante | `lib/disponibilidade.sh:222,233,259`; `bin/dbx:46-47` | escrita direta de `DBX_AUTH_MOTIVO`/`DBX_AUTH_GANCHO_*` fora de lib/auth; deteccao de 5xx por texto (`*'codigo 5'*`) |
| 6 | menor | `lib/disponibilidade.sh:258` | substitui `DBX_HTTP_RESUMO_DE_ERRO` em vez de enriquecer (RF-151(e)) |
| 7 | menor | `lib/http.sh:567-570` | sonda sem registro em `--debug` (RF-149(c)(f)); `-D cabecalhos` sem leitor |
| 8 | menor | `bin/dbx:51` | `*stdin*` casa caminhos como `/bkp/stdin.log` (fecha o portao; direcao segura) |
| 9 | menor | `lib/disponibilidade.sh:25-27` | `$(cd -P ...)` e um fork a mais no caminho feliz; `DBX_CLI_RAIZ` ja existe |
| 10 | menor | `commands/testar.sh:66,98,114,193` | indice posicional fragil; mensagem de campo faltando inconsistente; reuso de `DBX_CMD_LIDO` |
| 11 | menor | `lib/disponibilidade.sh:5-7` | cabecalho omite dependencias (config, auth, `dbx_iniciar_config`, `DBX_CLI_SIMULACAO`) |

Decisao do Tech Lead: devolvido ao Senior Developer (Tarefa 5) com 1 a 9 e 11; 10 so a mensagem inconsistente e a credencial "nao executada" sem nomear a internet.

## Tarefa 5: correcao dos achados de conformidade

Encerrada ANTES do fim por limite de chamadas (ordem do Tech Lead). Estado: pela metade; nada abaixo foi reexecutado em verde, exceto onde dito.

| Achado | Correcao aplicada | Teste (red/green) |
|---|---|---|
| #3 | `dbx_auth_falha_e_do_token`/`dbx_auth_falhar_com` em `commands/revisoes.sh`, `commands/lixeira.sh`, `commands/restaurar.sh` (get_metadata e list_revisions); `dbx_cmd_falha_registrar` novo em `lib/cmd.sh`, usado por `dbx_cmd_espaco_consultar`. `upload.sh:413` nao muda: vem depois de `dbx_auth_preparar` (:238), nao e a primeira obtencao, e a falha e silenciosa por desenho (RF-60(d)). | `teste_dsp32_invalid_grant_sai_5_nos_demais_comandos_de_consulta` (revisoes, restaurar, lixeira): RED medido (esperado 5, obtido 2 em `revisoes`, com os 3 comandos revertidos para HEAD). GREEN NAO reexecutado. |
| #5 | `lib/auth.sh`: `dbx_auth_registrar_ganchos`, `dbx_auth_definir_motivo`, `dbx_auth_falha_de_servidor`, `DBX_AUTH_CODIGO_HTTP` (publicado na falha da renovacao); `bin/dbx` usa o registro; `lib/disponibilidade.sh` nao escreve mais `DBX_AUTH_*` e detecta 5xx pelo codigo. | sem teste novo; cobertura pelos casos dsp33/dsp34 existentes, NAO reexecutados. |
| #6 | `_dbx_disp_publicar_causa` preserva o resumo original entre parenteses. | `teste_causa_enriquece_o_resumo_de_erro_sem_perder_o_original`: RED medido; GREEN apos a edicao (disponibilidade_test: 6 ok, 1 falha, ver #2). |
| #2 | `dbx_disp_compartilhar_sonda <dir>` + marca por `mkdir` com resultado em arquivo, causa `indeterminada` para quem perde a corrida. SEMEADURA NO `commands/sync.sh` (chamar `dbx_disp_compartilhar_sonda "$pasta"` antes do laco de auxiliares, ~:322) NAO FEITA. | `teste_sonda_uma_por_execucao_entre_processos_com_marca_compartilhada`: REPROVADO ao fim (esperado 1 sonda; `mv` de `sonda/resultado.tmp` falhou: o diretorio da marca/arquivo temporario nao existe na hora do `mv`; causa nao investigada). |
| #4 | `_dbx_disp_avisar_sonda_invalida` (stderr, sem o valor, uma vez; chamado em `dbx_disp_nomear_falha`). | `teste_sonda_invalida_avisa_uma_vez_sem_o_valor` escrito; nao executado (a suite parou no caso anterior). |
| #8 | `bin/dbx`: portao casa `-`, `--senha`, `--password`, `--senha-stdin`, `--password-stdin`. | sem teste; nao executado. |
| #9 | `lib/disponibilidade.sh` usa `DBX_CLI_RAIZ` quando definido; cai no calculo anterior no carregamento isolado. | coberto pelos testes existentes; nao executado fora do unitario. |
| #11 | cabecalho de `lib/disponibilidade.sh` com dependencias reais. | n/a |

Execucoes: `bash tests/run.sh disponibilidade_test` = 7 casos, 6 aprovados, 1 reprovado (o do #2; o runner para no primeiro erro, entao #4 nao rodou). `bash -n` limpo nos 7 arquivos alterados. Lint NAO rodado. Nenhum outro modulo reexecutado.

Pendentes (fechados por 5a, 5b e 5c: #1, #7, #10 pela 5c; #2 e #4 pela 5b; #3, #5, #6, #8, #9, #11 pela 5a; restava so o gate final): #1 (remedio do `testar`), #7 (`--debug` da sonda e `-D` em `lib/http.sh`), #10 (credencial "nao executada" nomeando a internet; mensagem de campo faltando :98/:114), teste do #8, semeadura do #2 em `sync.sh` e correcao do `mv` da marca, execucao verde de #3/#4/#5, composicao_test, comandos_test, auth_test, cmd_test, http_test, cli_test, testes de revisoes/lixeira/restaurar/sync/upload, guardas dsp28/dsp31, lint. DIV candidata: DIV-331 (sonda uma por execucao entre processos, com causa `indeterminada` para os que perdem a reserva); a decidir.

### Tarefa 5a

Escopo: estabilizar #3, #5, #6, #8, #9, #11 (sem tocar #1, #2, #4, #7, #10).

| Modulo (um por vez, stdin de /dev/null) | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| composicao_test | 28 | 28 | 0 | 0 |
| auth_test | 42 | 42 | 0 | 0 |
| cmd_test | 23 | 23 | 0 | 0 |
| disponibilidade_automatica_test (1a: dsp32 reprovou) | 6 (parou) | 5 | 1 | 0 |
| disponibilidade_automatica_test (final, com dsp32 e dsp35b) | 46 | 46 | 0 | 0 |
| comandos_test | 119 | 119 | 0 | 0 |
| reter_test (revisoes/lixeira/restaurar) | 84 | 84 | 0 | 0 |
| recuperacao_test (lixeira/restaurar) | 61 | 61 | 0 | 0 |
| qa_recuperacao_b3_test | 30 | 30 | 0 | 0 |

Corrigido:
- #3: o codigo ja saia 5 (`revisoes`, `restaurar`, `lixeira`); o dsp32 reprovava por assercao larga demais: `'recusada'` casava com "renovacao recusada: invalid_grant", a mensagem correta. Trocada por `'codigo 400'` (a classe da requisicao), igual ao dsp32 de `space`. Sem mudanca de requisito. Green: 46/46.
- #8: teste novo `dsp35b_caminho_com_stdin_no_nome_nao_fecha_o_portao_da_oferta` (`revisoes /bkp/stdin.log` sem credencial, em terminal, mantem a oferta e sai 3). RED medido com o portao `*stdin*` temporario em `bin/dbx:110` ("oferta mantida"); GREEN com a casa exata atual; `bin/dbx` restaurado.
- #5, #6, #9, #11: verdes pelos modulos acima; nenhuma edicao adicional.

Lint (`scripts/lint.sh`, um por vez): lib/auth.sh, lib/cmd.sh, commands/revisoes.sh, commands/lixeira.sh, commands/restaurar.sh, bin/dbx limpos.
DIV candidatas: nenhuma.

### Tarefa 5b

Escopo: #2 (sonda unica entre processos, DIV-331 A) e #4 (aviso de sonda invalida).

- #2a causa raiz: a reserva por `mkdir` nao e exclusiva neste sistema de arquivos (medido: 34/300 e 40/300 pares de `mkdir` simultaneos ambos tiveram sucesso; `set -C` e `ln` 0/300). Dois processos sondavam e disputavam `resultado.tmp` (o `mv` do segundo falhava). Teste flaky (2 de 6 rodadas). Correcao: reserva por criacao exclusiva de arquivo (`set -C`, O_EXCL) `sonda.reserva`; resultado em `sonda.resultado` (via `sonda.tmp` + `mv`), na mesma marca.
- #2b: `commands/sync.sh` semeia `dbx_disp_compartilhar_sonda "$area"` antes do laco de auxiliares.
- #2c (DIV-331 A): quem perde a reserva espera `sonda.resultado` em laco de `sleep 0.05` ate `DBX_DISP_ESPERA_MS` (padrao 10000 = max-time da sonda) e adota a causa; sem resultado, `indeterminada`. Saida inalterada.
- #4: `teste_sonda_invalida_avisa_uma_vez_sem_o_valor` ja passava (aviso de `dbx_disp_nomear_falha` existente); sem alteracao de codigo. Red nao reproduzivel: o comportamento ja existia no HEAD de trabalho.
- Testes novos: `perdedor_da_reserva_espera_e_recebe_a_causa_do_vencedor` (red esperado contra o codigo anterior: o perdedor devolvia `indeterminada` na hora), `perdedor_sem_resultado_no_prazo_da_causa_indeterminada` (prazo 200 ms).

| Execucao (um por vez, stdin de /dev/null) | Total | Aprovados | Falhos |
|---|---|---|---|
| disponibilidade_test (1a, flaky) | 7 (parou) | 6 | 1 |
| disponibilidade_test (final, 3 rodadas) | 13 | 13 | 0 |
| disponibilidade_automatica_test | 46 | 46 | 0 |
| composicao_test | 28 | 28 | 0 |
| integracao/sync_test | 85 | 85 | 0 |

Lint (rc): lib/disponibilidade.sh 0, commands/sync.sh 0, tests/unit/disponibilidade_test.sh 0. DIV candidatas: nenhuma.

### Tarefa 5c

Escopo: #1, #7 e #10 (parcial).

| Achado | Correcao | Teste (red -> green) |
|---|---|---|
| #1 | `commands/testar.sh`: remedio por motivo: `permissao` = `chmod 600 <arquivo>`; `permissao_diretorio` = `chmod 700 <diretorio de DBX_CONFIG_DETALHE>`; `ligacao_simbolica` = "remova a ligacao simbolica em <dir> e rode dbx config". Antes saia `chmod 600 ...a.json_diretorio`. | `teste_dsp26b_remedio_da_recusa_acompanha_o_motivo` (3 motivos). RED medido (saida antiga acima); GREEN. |
| #7 | `lib/http.sh` `dbx_http_sondar`: com `--debug`, stderr recebe `debug: sonda GET https://<host> -> status N` (so esquema e host; sem caminho nem parametros); `-D <area>/cabecalhos` removido. Nota: nao havia mecanismo de debug de requisicao em `lib/http.sh` (so `DBX_CLI_DEBUG` em cli/sync/config); usei `DBX_CLI_DEBUG`. | `teste_dsp55b_debug_da_sonda_traz_status_sem_segredo_nem_parametro`. RED medido (debug desligado); GREEN. |
| #10a | Credencial "nao executada" nomeia `sem acesso a internet` quando sonda/API/content estao mudos; `servico Dropbox com falha` so quando ha resposta. Indexacao `RESULTADOS[1]` trocada por `_dbx_cmd_testar_resultado_de servico`. | `teste_dsp03b_credencial_nao_executada_nomeia_a_falta_de_internet`. RED medido; GREEN. |
| #10b | Mensagem unificada: `campo obrigatorio ausente ou vazio (<arquivo>): <campos>`. | coberto por dsp04/dsp06 (verdes). |

| Execucao (um por vez, stdin /dev/null) | Total | Aprovados | Falhos |
|---|---|---|---|
| testar_test | 25 | 25 | 0 |
| http_test | 53 | 53 | 0 |
| disponibilidade_automatica_test (dsp28/dsp31) | 46 | 46 | 0 |
| composicao_test | 28 | 28 | 0 |

Lint: commands/testar.sh, lib/http.sh, tests/integracao/testar_test.sh sem achados (rc=0). DIV candidatas: nenhuma.

## Gate protocolo-conformidade (rodada 2): REPROVADO

Mesmo revisor, apos as tarefas 5, 5a, 5b e 5c. Rodada 1: #1, #3, #5, #8, #9, #11 fechados; #2 fechado no essencial; #4, #6, #10 parciais; #7 reaberto (N1). Testes reexecutados pelo revisor: disponibilidade_test 13 (2 rodadas), testar_test 25, disponibilidade_automatica_test 46, composicao_test 28, todos verdes. Conferidos sem achado: exclusividade da reserva (`set -C` abre com O_EXCL), publicacao por `mv`, limpeza pela area do ciclo, ausencia de `mkdir` como trava, acessores de auth.

| # | Sev. | Local | Achado |
|---|---|---|---|
| N1 | **bloqueante** | `lib/http.sh` `dbx_http_sondar` (~576-581) | `--debug` da sonda imprime userinfo da URL (`https://u:senha@host`), sem `dbx_errors_redigir` (RF-149(e), RF-150(c), RNF-22) |
| N2 | importante | `lib/disponibilidade.sh:116`; `commands/sync.sh:364` | perdedor marca o aviso de URL invalida como feito sem avisar; vencedor auxiliar tem stderr em `/dev/null`: aviso se perde (RF-149(b)) |
| N3 | importante | `commands/testar.sh:207-213` | credencial "nao executada: sem acesso a internet" mesmo com a sonda respondendo (contradiz `internet: ok`) |
| N4 | menor | `lib/disponibilidade.sh:95-97,110-114` | diretorio compartilhado ausente/sem escrita, ou reserva orfa apos `kill -KILL` do vencedor: espera 10 s e sai `indeterminada` sem sondar |
| N5 | menor | `lib/disponibilidade.sh:117-125` | prazo contado por voltas, nao por relogio; padrao igual ao max-time do vencedor, sem folga |
| N6 | menor | `lib/http.sh` `dbx_http_sondar` | area temporaria criada e removida por sonda sem uso |
| N7 | menor | `lib/disponibilidade.sh:119` | valor de `sonda.resultado` nao validado contra o vocabulario |
| #1 resto | menor | `commands/testar.sh:92-95` | `ligacao_simbolica` aponta `${arquivo%/*}`; a ligacao pode ser a base ou `perfis/` |
| #6 resto | menor | `lib/disponibilidade.sh:339` | ainda substitui o motivo da autenticacao em vez de enriquecer |

Decisao do Tech Lead: tarefa 6a (N1, N3, N6, resto de #1) e 6b (N2, N4, N5, N7, resto de #6), em sequencia.

## Tarefa 6a: achados da rodada 2 (N1, N3, N6, #1)

| Achado | Correcao | Teste (red -> green) |
|---|---|---|
| N1 (bloqueante, seguranca): `--debug` da sonda imprimia userinfo da URL | `lib/http.sh` `dbx_http_sondar`: `anfitriao=${anfitriao##*@}` e a linha passa por `dbx_errors_redigir` antes do stderr | `dsp55c_debug_da_sonda_nao_vaza_userinfo` (URL `https://u:SENTINELA@proxy.ex:8443/p?q=1`): red com o corte removido (ok=25 nao_ok=1), green com ele (ok=27); contem host e status, sem senha, `u:`, caminho nem query |
| N3: causa da credencial "nao executada" nao vinha da classificacao | `commands/testar.sh`: `dbx_disp_nomear_falha rede` e `causa=$DBX_DISP_MENSAGEM` (so chamada, sem alterar `lib/disponibilidade.sh`) | `dsp03c_credencial_nao_executada_nomeia_dropbox_inacessivel`: red ("sem acesso a internet" com sonda 204), green; `dsp03b` segue verde |
| N6: area temporaria sem uso apos retirar o `-D` | `lib/http.sh`: removidos `dbx_tmp_area http`, `dbx_tmp_remover`, variavel `area` e a menção no comentario | remocao pura; `http_test` existente verde |
| #1: remedio de `ligacao_simbolica` apontava sempre `perfis/` | `commands/testar.sh`: usa `DBX_CONFIG_DETALHE` e, como `lib/config.sh` nao o publica para esse motivo, escolhe por `[[ -L ]]` entre base, `perfis/` e arquivo | `dsp26b` ampliado: ligacao no arquivo e ligacao em `perfis/` (a segunda aponta `perfis`, nao o pai) |

| Execucao | Resultado |
|---|---|
| testar_test | ok=27 nao_ok=0 |
| http_test | ok=53 nao_ok=0 |
| disponibilidade_automatica_test (dsp28/dsp31) | ok=46 nao_ok=0 |
| composicao_test | ok=28 nao_ok=0 |
| lint lib/http.sh, commands/testar.sh, tests/integracao/testar_test.sh | rc=0, rc=0, rc=0 |

Observacao: `lib/config.sh` nao publica `DBX_CONFIG_DETALHE` em `ligacao_simbolica`; fazê-lo e a solucao mais limpa, mas saiu do escopo desta tarefa.

## Tarefa 6b: achados da rodada 2 (N2, N4, N5, N7, #6)

| Achado | Correcao | Teste (red -> green) |
|---|---|---|
| N2: aviso de URL invalida perdido (auxiliar com stderr em /dev/null) | `dbx_disp_compartilhar_sonda` grava o PID do principal; `_dbx_disp_avisar_sonda_invalida` em processo diferente do principal so deixa a marca `sonda.aviso` (nao consome o aviso); `dbx_disp_emitir_aviso_pendente` (chamada em `commands/sync.sh` apos o `wait` dos auxiliares) emite uma vez; o perdedor deixou de marcar o aviso como feito | `aviso_de_sonda_invalida_do_auxiliar_sai_pelo_principal` (um aviso, sem o valor); red observado no desenvolvimento (0 avisos, ao usar BASHPID dentro de `$()`), green apos emissao direta pelo principal. Sem teste de integracao do sync com URL invalida (nao escrito) |
| N4: diretorio ausente / reserva orfa | `compartilhar_sonda` zera o diretorio nao utilizavel (sonda local); reserva grava o PID do vencedor; "ja existe" distinguido de outra falha (`-e`); perdedor para se `kill -0` falhar | `diretorio_compartilhado_ausente_sonda_localmente`, `reserva_orfa_nao_espera_o_prazo` (espera 20 s configurada, termina em < 3 s) |
| N5: prazo por relogio | `EPOCHREALTIME` (fallback `SECONDS`); padrao 12000 ms (max-time 10 s + 2000 ms) | testes de espera existentes (5000 e 200 ms) verdes |
| N7: resultado fora do vocabulario | validado por `case`; senao `indeterminada` | `resultado_fora_do_vocabulario_vira_indeterminada` |
| #6: motivo da autenticacao substituido | novo acessor `dbx_auth_enriquecer_motivo` em `lib/auth.sh` (a guarda de `composicao_test` proibe `disponibilidade.sh` ler `DBX_AUTH_MOTIVO`); preserva o original entre parenteses | `motivo_da_autenticacao_preserva_o_original` |

Nota: o red de N4/N7/#6 nao foi medido contra versao anterior (lib/disponibilidade.sh nao esta no HEAD do worktree).

| Execucao (um por vez, stdin /dev/null) | Resultado |
|---|---|
| disponibilidade_test | ok=18 nao_ok=0 |
| disponibilidade_automatica_test | ok=46 nao_ok=0 |
| composicao_test | ok=28 nao_ok=0 (1a execucao reprovou no teste de canal; corrigido com o acessor) |
| testar_test | ok=27 nao_ok=0 |
| tests/integracao/sync_test.sh | ok=85 nao_ok=0 |
| lint lib/disponibilidade.sh, lib/auth.sh, tests/unit/disponibilidade_test.sh, commands/sync.sh | rc=0 (sync.sh rc=0 antes do acessor) |

DIV candidatas: nenhuma.

## Gate protocolo-conformidade (rodada 3): REPROVADO

Mesmo revisor, apos 6a e 6b. Fechados: N1, N3, N4, N5, N6, N7, resto de #6. Parciais: N2 (aberto na etapa de lote do sync, R2), resto de #1 (R3). Testes reexecutados pelo revisor, rc real: disponibilidade_test 18, testar_test 27, disponibilidade_automatica_test 46, composicao_test 28. Pontos levados pelo Tech Lead: falta de red em N4/N7/#6 e falta de teste de integracao do sync nao bloqueiam este gate (materia do protocolo-tdd/QA); o teste de integracao vem com R2. `dbx_auth_enriquecer_motivo`, PID na reserva e prazo por `EPOCHREALTIME`: conformes.

| # | Sev. | Local | Achado |
|---|---|---|---|
| R1 | **bloqueante** | `lib/http.sh:580` | `dbx_errors_redigir` imprime em stdout; a linha de debug da sonda sai tambem em stdout e quebra `--json`/`--null` (reproduzido) |
| R2 | importante | `commands/sync.sh:1320` x `:322`/`:496`/`:507` | etapa de lote lanca auxiliares antes da semeadura da sonda: ate N+1 sondas e aviso de URL invalida perdido (RF-149(g), N2, #2) |
| R3 | menor | `commands/testar.sh:98-102` | sem candidato ligacao, remedio aponta o proprio arquivo; ligacao no pai de `perfis` nao coberta; solucao: `DBX_CONFIG_DETALHE` em lib/config |
| R4 | menor (seguranca) | `lib/http.sh:577-579` | ordem de corte vaza parte do userinfo com `/`, `?` ou `#` na senha (`https://u:pa/ss@host` -> `https://u:pa`) |
| R5 | menor | `lib/disponibilidade.sh:248-256`; `lib/cmd.sh:1212` | aviso consumido em chamada com stderr descartado; no sync, pedido do principal em `$()` apos o `wait` fica na marca |

Decisao do Tech Lead: tarefa 7 com R1, R4, R2 (com teste de integracao do sync), R5; R3 se couber.

## Tarefa 7: achados da rodada 3

| Achado | Correcao | Teste (red -> green) |
|---|---|---|
| R1 (bloqueante): linha de debug da sonda em stdout | `lib/http.sh` `dbx_http_sondar`: `dbx_errors_redigir ... >/dev/null`; a linha segue so a stderr | `dsp55d_debug_da_sonda_nao_polui_stdout` (testar_test): red (stdout com `debug:` x3), green (testar_test 29/0) |
| R4: userinfo com `/`, `?` ou `#` na senha vazava pedaco | `lib/http.sh`: com `@` na URL, se houver `/?#` antes do primeiro `@` imprime `<host omitido>`; senao corta apos o `@` e depois a autoridade | `dsp55e_debug_da_sonda_nao_vaza_senha_com_delimitador` (3 URLs): red (`https://u:pasENT`), green |
| R2: etapa de lote lancava auxiliares antes da semeadura da sonda | `commands/sync.sh`: `dbx_disp_compartilhar_sonda "$area"` uma vez antes de `_dbx_cmd_sync_lote_envio` (removida a do paralelo); `dbx_disp_emitir_aviso_pendente` apos o `wait` da etapa de lote | `dsp34r_sync_paralelo_com_url_invalida_avisa_uma_vez_na_etapa_de_lote` (red: 0 avisos; green: 1, sem o valor) e `dsp34s_..._sonda_uma_vez` (no maximo 1 sonda), em disponibilidade_automatica_test |
| R5: aviso consumido com stderr descartado | `lib/disponibilidade.sh`: `[[ /dev/stderr -ef /dev/null ]]` -> com area, deixa a marca; sem area, nao marca como feito; stderr visivel escreve direto (cobre o principal em `$()` apos o `wait`) | `aviso_nao_e_consumido_com_stderr_descartado` (disponibilidade_test): red (AVISO_FEITO=sim), green (19/0) |
| R3 | nao feito (teto de chamadas) | pendente |

| Execucao (um por vez, stdin /dev/null) | Resultado |
|---|---|
| http_test | ok=53 nao_ok=0 |
| testar_test | ok=29 nao_ok=0 |
| disponibilidade_test | ok=19 nao_ok=0 |
| disponibilidade_automatica_test | ok=48 nao_ok=0 (rodada antes da edicao de R5; reexecucao final pendente) |
| composicao_test, tests/integracao/sync_test.sh | NAO reexecutados apos R2/R5 (pendente) |
| lint dos arquivos alterados | NAO executado (pendente) |

Pendentes: R3; reexecutar disponibilidade_automatica_test (dsp28/dsp31), composicao_test, sync_test; lint de lib/http.sh, lib/disponibilidade.sh, commands/sync.sh e dos 3 testes alterados; `DBX_DISP_MARCA_PID` ficou sem leitura em `lib/disponibilidade.sh` apos R5 (remover). DIV candidatas: nenhuma.

### Tarefa 7: fechamento pelo Tech Lead

A tarefa 7 parou no teto sem a bateria final nem o lint; o Tech Lead completou a verificacao e removeu `DBX_DISP_MARCA_PID` (atribuida, sem leitor depois de R5). R3 fica pendente como recomendacao (menor). Regra 48: `disponibilidade_automatica_test.sh` acusado pelo detector era edicao da propria tarefa 7 (casos dsp34r/dsp34s) posterior ao seu `--registrar`; registrado.

| Verificacao (rc real) | Resultado |
|---|---|
| `composicao_test` | 28 aprovados, 0 reprovados |
| `disponibilidade_automatica_test` (dsp28/dsp31), apos R5 e a remocao | 48 / 0 |
| `disponibilidade_test` | 19 / 0 |
| `sync_test` | 85 / 0 |
| lint `lib/http.sh`, `lib/disponibilidade.sh`, `commands/sync.sh`, `tests/integracao/testar_test.sh`, `tests/integracao/disponibilidade_automatica_test.sh`, `tests/unit/disponibilidade_test.sh` | rc 0 em todos |

## Gate protocolo-conformidade (rodada 4): REPROVADO, e correcao R4a pelo Tech Lead

Fechados: R1, R2 (unicos lancamentos em background do sync cobertos; fora dele so `lib/progress.sh:446`, sem rede), R5; remocao de `DBX_DISP_MARCA_PID` sem resto. Recomendacoes (menores, nao bloqueiam): R3 (`DBX_CONFIG_DETALHE` em `ligacao_simbolica`) e R5a (aviso com stderr fechado `2>&-`; pedido deixado na marca pelo principal depois do ultimo `wait`).

R4a (bloqueante): `lib/http.sh` `dbx_http_sondar` cortava o userinfo pelo PRIMEIRO `@`; com `@` na senha (`https://u:p@ss@h/`) vazava `ss`. Correcao (Tech Lead, troca de duas linhas): autoridade ate o primeiro delimitador e userinfo ate o ULTIMO `@`, como o curl. Caso `https://u:p@zzSENT@host.ex/` acrescentado ao `dsp55e`.

| Verificacao (rc real) | Resultado |
|---|---|
| red: `testar_test` com o caso novo, codigo antigo | 27 aprovados, 1 reprovado (`dsp55e`: `https://zzSENT@host.ex`) |
| green: `testar_test` / `http_test` / `disponibilidade_automatica_test` | 29 / 53 / 48 aprovados, 0 reprovados |
| lint `lib/http.sh`, `tests/integracao/testar_test.sh` | rc 0 |

## Gate protocolo-conformidade (rodada 5): APROVADO

R4a fechado (expansoes simuladas: `https://u:p@ss@h/` -> `https://h`; `https://u:p@h:8443/a?b` -> `https://h:8443`; `https://@h/` -> `https://h`; `https://u@` -> `https://`). Sem bloqueante nem importante abertos no diff inteiro. Recomendacoes registradas, menores, fora desta entrega: R3 (`DBX_CONFIG_DETALHE` em `ligacao_simbolica`), R5a (aviso com stderr fechado / pedido na marca apos o ultimo `wait`), R4b (URL malformada com `@` cru seguido de delimitador cru imprime o host que o curl usaria, ex. `https://u:p@s/s@h/` -> `https://s`; endurecimento opcional: `<host omitido>` com mais de um `@`).

## Validacao independente do QA

Detalhe em [validacao-qa-teste-de-disponibilidade](2026-10-23-0900-validacao-qa-teste-de-disponibilidade.md). Ciclo 1 REPROVADO (QA-DSP-01, P1: `testar_test.sh:399-400` montava massa com `$(printf ...)`, contra RNF-24; corrigido pelo Tech Lead com here-string); ciclo 2 APROVADO: `qa_disponibilidade_b11_test` 33/0, `json` 62/0, `harness` 22/0, `testar_test` 29/0.

- **Aceite do solicitante pela regra 12, em 2026-10-23 ("Aprovo"):** suite `tests/integracao/qa_disponibilidade_b11_test.sh`, 33 casos, sha256 `ffe3ef0ea7f4cf69d96465d2960828b30597b9735ec88412ca2231e4a3db96ec`.

## Suite completa (regra 8 do protocolo-tdd)

- 1a execucao em `23eb37a` (2026-10-24T03:14Z): **VERMELHA**, 841 aprovados, 1 reprovado, 3 pulados, 30 arquivos. Reprovou `state_trava_test::leitor_concorrente_nunca_ve_trava_vazia_ou_parcial` (TC-TRV-14): 1 leitura de trava parcial em 372, com 15 processos adquirindo a mesma trava. Fora do diff desta demanda (`lib/state.sh` e o teste intocados desde `877b708`); o mesmo arquivo passou 5/5 no worktree e 5/5 na `develop`. Unica ocorrencia no `tests/.diagnostico/reprovacoes.log`. Leitura do Tech Lead: corrida rara e preexistente na leitura da trava de `lib/state` (risco **RSK-DSP-01**, a abrir como demanda propria; nao corrigido aqui, para nao ampliar o escopo).
