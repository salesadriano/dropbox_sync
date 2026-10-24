# Registro de entrega: depuracao das transferencias (em andamento)

Log de prompt: docs/prompts/2026-10-24_0330_debug-transferencias.md. Porte M.

## Tarefa 1: formato e chamadas HTTP (RF-156, RF-157)

Implementacao pelo Senior Developer (tarefa 1, sem testes: parou no teto); testes pelo Senior Developer (tarefa 1b, escritos sem execucao: parou no teto); execucao, red, correcoes e fechamento pelo Tech Lead.

Arquivos:
- `lib/debug.sh` (novo): `dbx_debug_linha <categoria> [chave=valor | posicional]...`, ponto unico de emissao; so com `DBX_CLI_DEBUG=sim`; controle vira `?` e depois redacao por `dbx_errors_redigir`; valor vazio ou com espaco, aspas ou barra entre aspas com escape; falha de escrita nunca muda o resultado.
- `lib/http.sh`: carrega `lib/debug.sh`; com `--debug` o `-w` do cURL leva `%{time_total} %{size_upload} %{size_download}` (`DIV-334`); uma linha `debug: http <metodo> <host><endpoint> tentativa= status= [curl=] duracao_ms= enviados= recebidos= [retry_after=] [espera_ms=]` por tentativa, antes da espera da retentativa (`RF-157`); endpoint com caminho so em `*.dropboxapi.com` (`DIV-335`); `_dbx_http_esperar` dividido em `_dbx_http_retry_after_efetivo`, `_dbx_http_espera_calcular` e `_dbx_http_dormir`, sem mudar o comportamento.
- `tests/unit/debug_test.sh` (novo, 10 casos); `tests/integracao/debug_http_test.sh` (novo, 14 casos).
- `tests/support/disponibilidade.sh` (duplo de cURL): `-D` com `Retry-After`, fila de respostas por papel, `content_corpo`, `-w` ampliado; `--fail` como o cURL real (>= 400 nao escreve corpo e sai 22: sem isso o canal de fluxo nunca repetia no duplo); `enviados` so na chamada com `--data-binary`.

Defeitos achados pelos testes e corrigidos (Tech Lead):
- `lib/debug.sh`: `{ printf ... >&2; } 2>/dev/null` mandava a linha para `/dev/null` (o redirecionamento externo vale antes do interno): nenhuma linha saia com `--debug`. Correcao: `printf ... >&2 2>/dev/null`.
- `lib/debug.sh`: a redacao vinha antes da troca de controle por `?`, e `dbx_errors_redigir` recusa inteiro o texto com caractere de controle: um nome com `\x01` virava `[REDIGIDO: ...]`. Correcao: controle primeiro, redacao depois.
- Testes: regex de `TC-DBG-01` exigia caminho tambem no host do token (`api.dropbox.com`, que `RF-157(b)` manda sair so como host) e so olhava a primeira linha; comparacao do upload com e sem `--debug` sem normalizar o diretorio temporario de cada cenario; `sync` chamado com sintaxe invalida (`sync --enviar <dir> /r`), que passava vazio (nenhuma requisicao nos dois lados); assercao do codigo do `sync` comparava a variavel com ela mesma; contagem de linhas por `$(printf ... | wc -l)` reprovada pela auditoria `json` (RNF-24).

Red (base extraida de `f0e81af` por `git archive`, so com os testes e o duplo novos): `debug_test` 0/1 (`lib/debug.sh` inexistente); `debug_http_test` 0/1 (`TC-DBG-01`: nenhuma linha `debug: http`).

| Comando | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| `bash tests/run.sh debug_test` | 10 | 10 | 0 | 0 |
| `bash tests/run.sh debug_http_test` | 14 | 14 | 0 | 0 |
| `bash tests/run.sh http_test` | 53 | 53 | 0 | 0 |
| `bash tests/run.sh comandos_test` | 119 | 119 | 0 | 0 |
| `bash tests/run.sh sync_test` | 85 | 85 | 0 | 0 |
| `bash tests/run.sh testar_test` | 29 | 29 | 0 | 0 |
| `bash tests/run.sh disponibilidade_automatica_test` | 48 | 48 | 0 | 0 |
| `bash tests/run.sh qa_disponibilidade_b11_test` | 33 | 33 | 0 | 0 |
| `bash tests/run.sh composicao_test` | 28 | 28 | 0 | 0 |
| `bash tests/run.sh json` | 62 | 62 | 0 | 0 |
| `bash tests/run.sh harness` | 22 | 22 | 0 | 0 |

Cobertura: `TC-DBG-01` a `07`, `22` a `30`. Cobertura reduzida (a completar nas tarefas seguintes ou pelo QA): `TC-DBG-24` (id de sessao) so pela resposta do upload simples e por chamada direta, sem `upload_session` com bloco grande; `TC-DBG-25` (cursor) e `TC-DBG-26` (URL temporaria) so por chamada direta ao `dbx_http_conteudo`.

Lint (`sh scripts/lint.sh`, um por vez, rc 0): `lib/debug.sh`, `lib/http.sh`, `tests/unit/debug_test.sh`, `tests/integracao/debug_http_test.sh`, `tests/support/disponibilidade.sh`.

`DIV-342` (posicao de `retry_after`): decidida pelo Tech Lead, A (letra de `RF-157`); `TC-DBG-03` alinhado.

## Tarefa 2: auxiliares do sync paralelo e resumo (RF-158, RF-162)

Implementacao pelo Senior Developer (tarefa 2, sem testes: parou no teto); testes, red, correcoes e fechamento pelo Tech Lead.

Arquivos:
- `lib/debug.sh`: `DBX_DEBUG_DESTINO` (auxiliar grava em arquivo proprio, `DIV-333`); contadores do processo alimentados pelas linhas `http`; `dbx_debug_descarregar` (o principal escreve as linhas do auxiliar e soma os contadores); `dbx_debug_resumo_armar`/`_dbx_debug_resumo_emitir` (linha `debug: resumo ...`, acao de `lib/tmp`, tambem em falha e sinal, `DIV-341`); `dbx_debug_canal_abrir` (descritor proprio com o stderr do operador).
- `lib/tmp.sh`: `DBX_TMP_SAIDA_CODIGO` (codigo real no termino; 14 no sinal) para o `saida=` do resumo.
- `bin/dbx`: com `--debug` em `download`, `upload` e `sync`, abre o canal e arma o resumo.
- `commands/sync.sh`: os dois lancamentos de auxiliar (etapa de lote e transferencia paralela) passam `DBX_DEBUG_DESTINO=<area 0700>/dbg.<indice>` so com `--debug`; descarga apos ler o resultado do item (transferencia) e em ordem apos o `wait` (lote); a linha `paralelo` de `RF-135(d)` sai (`DIV-338`); `antes_429` sem uso removido.
- `tests/integracao/paralelo_test.sh`: `par12`/`par13` passam a conferir o resumo unico (`DIV-338`); novos `par15` a `par18`.
- `tests/integracao/debug_http_test.sh`: resumo do `upload` (totais = soma das linhas `http`) e do `download` em falha.

Defeito achado pelos testes e corrigido (Tech Lead): a chamada de apoio `users/get_current_account` do `sync` (`commands/sync.sh:143`, feita com `>/dev/null 2>&1` de proposito, porque falhar ali nao impede o `sync`) contava no resumo mas a sua linha `http` ia para `/dev/null`, contra `RF-157(h)`. Correcao estrutural, nao pontual: `dbx_debug_canal_abrir` duplica o stderr do operador num descritor proprio no inicio do comando e `dbx_debug_linha` escreve nele; nenhum `2>/dev/null` do codigo esconde mais a trilha. O auxiliar continua no arquivo (`RF-158(c)`).

Red (base extraida de `cf21498`, so com os testes novos): `paralelo_test` 11/1 (`par12`: sem `debug: resumo`, linha `paralelo=4 transferencias simultaneas; respostas 429 observadas: 2` ainda presente); `debug_http_test` 14/1 (`TC-DBG-32`: sem resumo no download em falha). Os avisos `ignored null byte` de `paralelo_test` (linhas 239, 283, 292) aparecem igualmente na base: preexistentes.

| Comando | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| `bash tests/run.sh paralelo_test` | 18 | 18 | 0 | 0 |
| `bash tests/run.sh debug_http_test` | 16 | 16 | 0 | 0 |
| `bash tests/run.sh debug_test` | 10 | 10 | 0 | 0 |
| `bash tests/run.sh tmp_test` | 16 | 16 | 0 | 0 |
| `bash tests/run.sh qa_trava_tmp_b2_test` | 23 | 23 | 0 | 0 |
| `bash tests/run.sh sync_test` | 85 | 85 | 0 | 0 |
| `bash tests/run.sh comandos_test` | 119 | 119 | 0 | 0 |
| `bash tests/run.sh disponibilidade_automatica_test` | 48 | 48 | 0 | 0 |
| `bash tests/run.sh composicao_test` | 28 | 28 | 0 | 0 |
| `bash tests/run.sh json` | 62 | 62 | 0 | 0 |
| `bash tests/run.sh harness` | 22 | 22 | 0 | 0 |

Cobertura: `TC-DBG-20` (linhas dos auxiliares chegam ao operador e somam), `21` (arquivo de linhas removido no fim, em falha e no sinal), `30` (sem `--debug`, nenhum arquivo de linhas durante a execucao), `31` (resumo unico com `paralelo=4` e `limites_429`; N=1 sem `paralelo=`), `32` (falha e sinal com `saida=<codigo>` e a mensagem de sempre), `RF-162(e)` (`chamadas` = requisicoes feitas = linhas `tentativa=1`).

Pendente para as tarefas seguintes: ordem das linhas por item na ordem do plano (`RF-158(b)`, `TC-DBG-20`) so e verificavel com as linhas de decisao de `RF-161` (tarefa 4); `RF-162(c)` (resumo antes da mensagem de interrupcao) nao tem assercao de ordem; com `--dry-run --paralelo N` o resumo diria `paralelo=N` embora a simulacao nunca use paralelismo (o valor vem do N pedido).

Lint (`sh scripts/lint.sh`, um por vez, rc 0): `lib/debug.sh` (apos trocar `>&"$fd"` por `1>&"$fd"`, SC2261), `lib/tmp.sh`, `commands/sync.sh`, `bin/dbx`, `tests/integracao/paralelo_test.sh`, `tests/integracao/debug_http_test.sh`.

## Tarefa 3: etapas do upload e do download (RF-159, RF-160)

Implementacao e testes pelo Senior Developer (tarefa 3; so o arquivo novo executado); bateria, red, lint e decisoes de divergencia pelo Tech Lead.

Arquivos:
- `lib/transfer.sh`: `modalidade=simples|sessao ... bloco_tamanho=` em `dbx_transfer_enviar_arquivo`; `bloco=<n> deslocamento= tamanho=` e `bloco=<n> confirmado=` no laco de `_dbx_transfer_percurso`; linhas de retomada em `_dbx_transfer_ret_abrir`, `_dbx_transfer_ret_mudou` e `_dbx_transfer_anexar_retomado`; `DBX_TRANSFER_DEBUG_SEM_RETOMADA`.
- `lib/cmd.sh`: `_dbx_cmd_debug_plano_download` (plano: `destino`, `bytes`, `retomada` com `faixa`/`part_bytes` ou `motivo`) e `_dbx_cmd_debug_hash` (`hash=ok|divergente bytes=`), nos dois caminhos de recebimento e nos dois pontos de faixa ignorada.
- `lib/http.sh`: a linha `http` ganha `faixa=<inicio>-` quando a requisicao leva `Range` (`RF-160(b)`), no fim da linha.
- `commands/upload.sh` (modalidade da sessao por stdin: `arquivo=- bytes=desconhecido`; repasse de `--sem-retomada`), `commands/download.sh` (plano para stdout sem `destino`; repasse de `--sem-retomada`; `disable=SC2034` comentado na variavel lida por `lib/cmd.sh`).
- Testes: `tests/integracao/debug_transferencia_test.sh` (novo, 5 casos); 4 casos novos em `retomada_upload_test.sh` e 4 em `retomada_download_test.sh` (onde estao os duplos com estado de sessao e de `Range`).

Vocabulario de motivos (conferido contra o codigo, `DIV-340`): upload `arquivo-alterado` (`_dbx_transfer_ret_mudou`), `estado-invalido` (registro descartado ou de outro usuario), `estado-ausente`, `sessao-expirada` (tag `not_found`/`closed`), `deslocamento-incorreto`, `sem-retomada`; download `hash-remoto-mudou`, `estado-invalido`, `servidor-ignorou-faixa`, `sem-retomada`. `DIV-343` e `DIV-344` decididas pelo Tech Lead (A): `part-maior-que-remoto` sai do `RF-160(a)` e cai em `estado-invalido`, como os casos de `.part` sumido/trocado e registro alheio; a retomada desligada no meio do upload nao ganha linha propria (ja emite aviso em stderr).

Red (base extraida de `23be9d4`, so com os testes novos): `debug_transferencia_test` 0/1 (sem `debug: upload modalidade=sessao`); `retomada_upload_test` 39/1 (`tc_dbg_08_09_24`: sem modalidade nem blocos); `retomada_download_test` 28/1 (`tc_dbg_13`: sem `retomada=encontrada faixa=... part_bytes=...`).

| Comando | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| `bash tests/run.sh debug_transferencia_test` | 5 | 5 | 0 | 0 |
| `bash tests/run.sh retomada_upload_test` | 43 | 43 | 0 | 0 |
| `bash tests/run.sh retomada_download_test` | 32 | 32 | 0 | 0 |
| `bash tests/run.sh debug_http_test` | 16 | 16 | 0 | 0 |
| `bash tests/run.sh http_test` (casou tambem `debug_http_test`) | 69 | 69 | 0 | 0 |
| `bash tests/run.sh comandos_test` | 119 | 119 | 0 | 0 |
| `bash tests/run.sh sync_test` | 85 | 85 | 0 | 0 |
| `bash tests/run.sh composicao_test` | 28 | 28 | 0 | 0 |
| `bash tests/run.sh json` | 62 | 62 | 0 | 0 |
| `bash tests/run.sh harness` | 22 | 22 | 0 | 0 |

Cobertura: `TC-DBG-08` (simples e sessao; lote pendente), `09`, `10`, `11`, `12`, `13`, `14`, `15`, `16`; `TC-DBG-24` agora com sessao real (bloco grande e sentinela de `session_id`), o que fecha a cobertura reduzida registrada na Tarefa 1.

Pendente para a Tarefa 4: `modalidade=lote` do `sync --enviar` (parte de `TC-DBG-08`) e `RF-159(d)` (`debug: upload resultado=ok|falha classe=` por item). Observacao aceita: depois de `hash=divergente` com recomeco, a segunda tentativa emite um segundo plano (`retomada=nenhuma`), porque e um recebimento novo.

Lint (`sh scripts/lint.sh`, um por vez, rc 0): `lib/cmd.sh`, `lib/transfer.sh`, `lib/http.sh`, `commands/upload.sh`, `commands/download.sh`, `tests/integracao/debug_transferencia_test.sh`, `tests/integracao/retomada_upload_test.sh`, `tests/integracao/retomada_download_test.sh`.

## Tarefa 4: decisoes do sync, cursor e resultado do envio (RF-161, RF-158(b), RF-159(a)(d))

Implementacao e testes pelo Senior Developer (tarefa 4; nenhum teste executado: a unica tentativa chamou o arquivo sem o executor); bateria, red, correcoes, lint e decisoes de divergencia pelo Tech Lead.

Arquivos:
- `commands/sync.sh`: `_dbx_cmd_sync_debug_decisoes` (uma linha `debug: sync decisao= motivo= item=<relativo>` por item, antes da primeira transferencia, tambem em simulacao); linha do cursor no `--receber` (`cursor=usado|reconstruido|desligado|forcado`, nunca o valor); `upload modalidade=lote` por item pequeno e `upload resultado=ok|falha classe=` por item do lote; `_dbx_cmd_sync_enviar` recebe o item relativo e o publica em `DBX_TRANSFER_DEBUG_ITEM`.
- `lib/sync.sh`: `_dbx_sync_contar_filtrado` emite `decisao=pular motivo=filtrado` uma vez por chave, so com `DBX_SYNC_DEBUG_DECISAO=sim` (o `verificar` nao emite).
- `lib/transfer.sh`: `_dbx_transfer_debug_resultado` (`RF-159(d)`) nas tres saidas de `dbx_transfer_enviar_arquivo`; a linha `modalidade` usa `DBX_TRANSFER_DEBUG_ITEM` quando o `sync` o publica.
- `tests/integracao/debug_sync_test.sh` (novo, 8 casos).

Correcoes do Tech Lead:
- `RF-161(c)` / `DIV-345`: o item so do destino sem `--espelhar` ficava sem linha, e o protegido sob `--espelhar` era pulado em silencio; agora `pular motivo=so-no-destino` e `pular motivo=protegido`. Caso novo `dbg17_so_no_destino_sem_espelhar...`.
- `RF-164(b)` / `DIV-332`: no `sync --enviar` a linha `upload modalidade=` trazia o caminho local completo; agora o item relativo a raiz. Assercao nova no caso `dbg159_envio_unitario...`.
- Testes: o item igual usava `dbx_hash_conteudo_arquivo` (imprime) em vez de `dbx_hash_publicar_arquivo` (publica em `DBX_HASH_RESULTADO`) e saia `content-hash-diferente`; `TC-DBG-20` procurava `download hash=ok`, que nao existe quando a listagem nao traz `content_hash` (passa a identificar o item pelo `destino` do plano); atribuicao morta de `DBX_SAIDA` (SC2034) trocada por assercao real da sentinela de cursor no texto dos dois canais.

Divergencias decididas pelo Tech Lead (A em todas; detalhe na secao 9 do escopo): `DIV-345` (so no destino e protegido tem linha), `DIV-346` (`mais-novo` e `cache-igual` saem do vocabulario: o `sync` so decide por `content_hash`), `DIV-347` (`guarda` e `filtro=<n>` saem: a guarda recusa o plano inteiro e ja tem mensagem), `DIV-348` (decisoes em bloco, depois as linhas por item na ordem do plano; `RF-161(f)` reescrito), `DIV-349` (`cursor=usado` sem `motivo=`).

Red (base extraida da Tarefa 3, so com o teste novo): `debug_sync_test` 0/1 (`dbg159_envio_unitario`: sem `upload resultado=ok`; a base ainda mostrava `arquivo=<caminho local completo>`). O red especifico das duas correcoes do Tech Lead (`so-no-destino` e item relativo) nao foi medido isoladamente: a base nao tem nenhuma linha de decisao, e o caso do item relativo reprova na base pela linha de resultado antes de chegar a ele.

| Comando | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| `bash tests/run.sh debug_sync_test` | 8 | 8 | 0 | 0 |
| `bash tests/run.sh sync_test` (casou tambem `debug_sync_test`) | 93 | 93 | 0 | 0 |
| `bash tests/run.sh paralelo_test` | 18 | 18 | 0 | 0 |
| `bash tests/run.sh verificar_test` | 17 | 17 | 0 | 0 |
| `bash tests/run.sh retomada_upload_test` | 43 | 43 | 0 | 0 |
| `bash tests/run.sh comandos_test` | 119 | 119 | 0 | 0 |
| `bash tests/run.sh debug_transferencia_test` | 5 | 5 | 0 | 0 |
| `bash tests/run.sh composicao_test` | 28 | 28 | 0 | 0 |
| `bash tests/run.sh json` | 62 | 62 | 0 | 0 |
| `bash tests/run.sh harness` | 22 | 22 | 0 | 0 |

Cobertura: `TC-DBG-08` (lote), `17`, `18`, `19` (`reconstruido`, `desligado`, `forcado`), `20` (decisao antes das linhas do item com `--paralelo 4`), `25` (sentinela de cursor ausente de stdout e stderr: fecha a cobertura reduzida da Tarefa 1), `RF-159(d)`.

Pendente: `cursor=usado` sem caso (o duplo devolve a mesma listagem no `list_folder/continue`); `upload -` (fluxo, `commands/upload.sh`) nao emite `resultado=`; no `--receber` com segunda rodada de varredura completa (contradicao na exclusao) o `filtrado` pode sair duas vezes para o mesmo item.

Lint (`sh scripts/lint.sh`, um por vez, rc 0): `commands/sync.sh`, `lib/sync.sh`, `lib/transfer.sh`, `tests/integracao/debug_sync_test.sh`.

## Tarefa 5: progresso, ativacao, ajuda e README (RF-165, RF-163, RF-159(d) no fluxo; TC-DBG-33 a 35)

Implementacao e testes pelo Senior Developer (tarefa 5; arquivo proprio executado, 9/9); bateria, red e lint pelo Tech Lead.

Arquivos:
- `lib/progress.sh`: `_dbx_progress_terminal` confere `--debug` antes da semente `DBX_PROGRESS_TERMINAL` (`DIV-350`): a semente `sim` religava o retorno de carro e a linha `debug:` saia colada a linha de progresso.
- `commands/upload.sh`: `upload -` (fluxo) emite `debug: upload resultado=ok|falha classe=` (`RF-159(d)`, lacuna da Tarefa 4).
- `bin/dbx`: paragrafo de `--debug` em `help upload`, `help download`, `help sync` e na ajuda geral (prefixo `debug: <categoria>`, categorias, so stderr, `DBX_DEBUG=1`, o que nunca aparece).
- `README.md`: sub-item de `--debug` com o mesmo conteudo. `completions/dbx.bash` ja completava `--debug` (conferido, sem mudanca).
- `tests/integracao/debug_ajuda_progresso_test.sh` (novo, 9 casos).

Red (base extraida da Tarefa 4, so com o teste novo): 2/1 (`tc_dbg_33_semente_de_terminal_nao_reabilita_o_retorno_de_carro`: na base, `... 0% 0 B / 10 KiB\e[Kdebug: upload modalidade=simples ...` na mesma linha fisica). Os dois casos de TC-DBG-33 sem semente ja passavam na base (`DIV-287` cobria a deteccao real).

| Comando | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| `bash tests/run.sh debug_ajuda_progresso_test` | 9 | 9 | 0 | 0 |
| `bash tests/run.sh progress` (progress, progresso_linha, progresso_arquivo, qa_progresso_arquivo_b10 e o novo) | 87 | 87 | 0 | 0 |
| `bash tests/run.sh comandos_test` | 119 | 119 | 0 | 0 |
| `bash tests/run.sh composicao_test` | 28 | 28 | 0 | 0 |
| `bash tests/run.sh json` | 62 | 62 | 0 | 0 |
| `bash tests/run.sh harness` | 22 | 22 | 0 | 0 |

Cobertura: `TC-DBG-33` (sem terminal, com terminal por pty e com a semente), `34`, `35`, `RF-159(d)` no fluxo.

Lint (`sh scripts/lint.sh`, um por vez, rc 0): `lib/progress.sh`, `commands/upload.sh`, `bin/dbx`, `tests/integracao/debug_ajuda_progresso_test.sh`.

## Gate protocolo-conformidade (rodada 1): APROVADO COM RESSALVAS

Revisor independente (subagent sem o contexto da implementacao), leitura do diff contra `1e37b75` (21 arquivos de codigo, testes, completions e README); skills clean-architecture e security-best-practices. Sem bloqueante; 3 importantes (no limite da regra), 8 menores.

Conferido sem achado: nenhum segredo nas linhas (todo valor passa por controle -> `?`, `dbx_errors_redigir` e aspas; nenhum id de sessao, cursor, corpo, query ou cabecalho entra em `dbx_debug_linha`; o link temporario nao passa pelos tres comandos); sem `--debug` nao nasce `-w` ampliado, descritor, arquivo `dbg.N`, `stat` nem `wc`; o `-w` sai pela captura, nunca pelo stdout; o resumo e filtrado por `BASHPID` (os auxiliares nao o emitem); os contadores dos auxiliares sao somados uma vez, na descarga.

| # | Sev. | Local | Achado |
|---|---|---|---|
| 1 | importante | `lib/debug.sh:160`, `lib/tmp.sh:144-147`, `bin/dbx:770` | no sinal o resumo sai DEPOIS da mensagem de interrupcao (acoes em ordem inversa e o resumo e a primeira registrada), contra `RF-162(c)` |
| 2 | importante | `lib/debug.sh:175-182` | lib le globais de commands (`DBX_CMD_SYNC_PARALELO`, `DBX_CMD_SYNC_LIMITES_429`): dependencia para fora |
| 3 | importante | `bin/dbx:736-771`, `lib/http.sh:640-678` | resumo armado depois do preflight e da preparacao de disponibilidade: falha de configuracao/credencial sai sem resumo (`RF-162(a)`); a sonda soma `DBX_HTTP_REQUISICOES` sem passar pelos contadores (`RF-162(e)`) |
| 4 | menor | `lib/tmp.sh:130` | `DBX_TMP_SAIDA_CODIGO` vem do ambiente (nao inicializado) |
| 5 | menor | `lib/http.sh:276-294` | `_dbx_http_endpoint_debug` sem a protecao de userinfo da sonda (so URL interna passa: defesa em profundidade) |
| 6 | menor | `lib/transfer.sh:~842` | indentacao |
| 7 | menor | `commands/sync.sh:637-645` | `upload resultado=` do lote sem `arquivo=`: no lote paralelo o resultado nao se liga ao item |
| 8 | menor | `commands/sync.sh:1618`, `lib/transfer.sh:1204,1213` | `DBX_TRANSFER_DEBUG_ITEM` como `local` dinamico sem declaracao na lib |
| 9 | menor | `commands/upload.sh:339` | `DBX_TRANSFER_DEBUG_SEM_RETOMADA` nao volta a `nao` |
| 10 | menor | `lib/transfer.sh`, `lib/cmd.sh`, `lib/sync.sh` | chamam `dbx_debug_linha` sem carregar `lib/debug.sh` (vem por `lib/http.sh`) |
| 11 | menor | `lib/debug.sh:31` | um fork por valor redigido e truncamento sem marca; descritor do canal herdado pelos filhos (segue o padrao de `saida_padrao`) |

Decisao do Tech Lead: as ressalvas nao ficam para depois. Tarefa 6 com 1, 2, 3, 4, 6, 7, 8 e 9; 5, 10 e 11 ficam como recomendacao registrada (5 e 11 sem efeito com as URLs e volumes de hoje; 10 funciona pela carga de `lib/http.sh`, que todos os chamadores fazem).

## Tarefa 6: achados da conformidade (rodada 1)

Implementacao pelo Senior Developer (tarefa 6, sem testes: parou no teto); testes, red, bateria e lint pelo Tech Lead.

| # | Correcao | Teste |
|---|---|---|
| 1 | `lib/tmp.sh`: `dbx_tmp_gancho_antes <funcao>` (um gancho por processo, so nome de funcao, roda uma vez no termino normal ou por sinal ANTES de todas as acoes, sem mudar a ordem delas); `lib/debug.sh`: o resumo usa o gancho em vez de uma acao | `tmp_test`: `gancho_antes_roda_antes_das_acoes_no_termino_normal`, `..._no_sinal` (INT e TERM, com o codigo 14), `gancho_antes_recusa_texto_que_nao_e_funcao` |
| 2 | `lib/debug.sh`: `dbx_debug_resumo_campo <chave> <valor>` e `dbx_debug_somar_429 <n>`; o resumo nao le mais `DBX_CMD_*`; `commands/sync.sh` publica `paralelo=N` e soma os 429 por esses canais | `paralelo_test` `par12`, `par15`, `par17` (saida identica a de antes) |
| 3 | `bin/dbx`: o resumo e armado ANTES do bloco de requisito (so `download`/`upload`/`sync`, so com `--debug`); `lib/http.sh` `dbx_http_sondar`: a sonda entra nos contadores (a linha `debug: sonda` nao muda) | `debug_http_test`: `rf162a_credencial_ausente_tambem_tem_resumo_com_o_codigo` (`saida=3`, `chamadas=0`), `rf162e_sonda_entra_em_chamadas` |
| 4 | `lib/tmp.sh`: `DBX_TMP_SAIDA_CODIGO=''` ao carregar | `debug_http_test`: `rf162_codigo_do_resumo_nao_vem_do_ambiente` |
| 6, 8, 9, 7 | indentacao em `lib/transfer.sh`; `DBX_TRANSFER_DEBUG_ITEM=''` declarado; `DBX_TRANSFER_DEBUG_SEM_RETOMADA` volta a `nao` no `upload`; `upload resultado=` do lote com `arquivo=` | `debug_sync_test` `dbg159_lote...` (resultado nomeia o item) |

Os achados 5, 10 e 11 ficam como recomendacao (ver a rodada 1).

`RF-162(c)` no comando inteiro: no `sync --receber` interrompido durante o download nao ha mensagem de interrupcao (so o resumo, com `saida=14`); a mensagem citada pelo revisor so existe na exclusao em lote do `--enviar --espelhar`, que o duplo nao interrompe de forma deterministica. Por isso a ordem e provada em `lib/tmp`, onde ela e decidida.

Teste instavel corrigido: `par15` (Tarefa 2) exigia pico 4 de transferencias simultaneas sem atraso no duplo; numa rodada deu 2. Agora cada download tem 1 s de atraso.

Red (base extraida de `a78f6a8`, so com os testes desta tarefa): `tmp_test` 6/1 (`dbx_tmp_gancho_antes: command not found`); `debug_http_test` 0/1 (`saida=0` semeado pelo ambiente); `debug_sync_test` 1/1 (`resultado=` do lote sem `arquivo=`).

| Comando | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| `bash tests/run.sh tmp_test` | 19 | 19 | 0 | 0 |
| `bash tests/run.sh debug_http_test` | 19 | 19 | 0 | 0 |
| `bash tests/run.sh debug_sync_test` | 8 | 8 | 0 | 0 |
| `bash tests/run.sh paralelo_test` | 18 | 18 | 0 | 0 |
| `bash tests/run.sh disponibilidade_automatica_test` | 48 | 48 | 0 | 0 |
| `bash tests/run.sh qa_disponibilidade_b11_test` | 33 | 33 | 0 | 0 |
| `bash tests/run.sh qa_trava_tmp_b2_test` | 23 | 23 | 0 | 0 |
| `bash tests/run.sh comandos_test` | 119 | 119 | 0 | 0 |
| `bash tests/run.sh sync_test` (com `debug_sync_test`) | 93 | 93 | 0 | 0 |
| `bash tests/run.sh retomada_upload_test` | 43 | 43 | 0 | 0 |
| `bash tests/run.sh progress` (5 arquivos) | 87 | 87 | 0 | 0 |
| `bash tests/run.sh composicao_test` | 28 | 28 | 0 | 0 |
| `bash tests/run.sh json` | 62 | 62 | 0 | 0 |
| `bash tests/run.sh harness` | 22 | 22 | 0 | 0 |

Lint (`sh scripts/lint.sh`, um por vez, rc 0): `lib/tmp.sh`, `lib/debug.sh`, `lib/http.sh`, `lib/transfer.sh`, `commands/sync.sh`, `commands/upload.sh`, `bin/dbx`, `tests/unit/tmp_test.sh`, `tests/integracao/debug_http_test.sh`, `tests/integracao/debug_sync_test.sh`, `tests/integracao/paralelo_test.sh`.

## Gate protocolo-conformidade (rodada 2): APROVADO COM RESSALVAS, e correcao N1 pelo Tech Lead

Mesmo revisor, diff `a78f6a8..a718ec4`. Rodada 1: 1, 2, 3, 4, 6, 7 e 9 fechados; 8 parcial (`_dbx_cmd_sync_debug_decisoes` le os locais do executor por escopo dinamico: recomendacao). Mecanismo do gancho conferido: subshell e auxiliar herdam o alvo mas o dono (`BASHPID`) impede a execucao; sinal durante o gancho fica anotado e a finalizacao nao se repete; falha do gancho absorvida por `|| :`.

| # | Sev. | Local | Achado | Destino |
|---|---|---|---|---|
| N1 | importante | `bin/dbx:727-740`, `lib/tmp.sh:80-86` | armar o resumo antes do requisito armava tambem os tratadores completos de INT/TERM/HUP: so com `--debug`, Ctrl-C no preflight ou nas perguntas do `config` oferecido saia 14 (`nao_concluida`); sem `--debug`, 130. Fere `RF-163(b)` | corrigido (abaixo) |
| N2 | menor | `lib/tmp.sh:305-315` | segundo `dbx_tmp_gancho_antes` substituia o primeiro sem aviso | corrigido: o segundo registro no mesmo processo e recusado (erro de uso) |
| N3 | menor | `lib/tmp.sh:16-20` | cabecalho "ORDEM DA LIMPEZA" sem o gancho | corrigido |
| N4 | menor | `lib/http.sh:704-708` | `dbx_tmp_area http` que falha ja contou `DBX_HTTP_REQUISICOES` e nao emite linha `http` (`chamadas` menor; TMPDIR cheio) | recomendacao |
| N5 | menor | `commands/sync.sh:232` | `paralelo=` passa a sair tambem no `download` de pasta com `DBX_PARALELO`, e `+=` repetiria o campo se o executor rodasse duas vezes | aceito o primeiro (o `download` de pasta usa o mesmo motor paralelo, o campo e verdadeiro); o segundo corrigido: `dbx_debug_resumo_campo` troca o valor da chave ja publicada |

Correcao N1 (Tech Lead): `dbx_tmp_gancho_antes` deixa de chamar `_dbx_tmp_armar` e usa `_dbx_tmp_armar_leve`: EXIT mais INT/TERM/HUP que gravam `128+N` em `DBX_TMP_SAIDA_CODIGO`, finalizam (o gancho) e devolvem ao processo o proprio sinal, que morre com o codigo de sempre. O primeiro `_dbx_tmp_armar` real (area ou acao) substitui os leves pelos completos, no mesmo ponto em que ja os arma sem `--debug`. Conferido antes no bash: com so o trap de EXIT o sinal mantem 130, mas `$?` dentro do trap vale 0; por isso o armamento leve grava o codigo do sinal em vez de deixar o resumo com `saida=0`.

Red (base extraida de `a718ec4`, so com o `tmp_test` novo): 8/1 (`gancho_sozinho_mantem_o_codigo_do_proprio_sinal`: INT saia 14, esperado 130).

| Comando | Total | Aprovados | Falhos | Pulados |
|---|---|---|---|---|
| `bash tests/run.sh tmp_test` | 21 | 21 | 0 | 0 |
| `bash tests/run.sh disponibilidade_automatica_test` (inclui `dsp51`, SIGINT dentro do `config`) | 48 | 48 | 0 | 0 |
| `bash tests/run.sh paralelo_test` | 18 | 18 | 0 | 0 |
| `bash tests/run.sh debug_http_test` | 19 | 19 | 0 | 0 |
| `bash tests/run.sh qa_trava_tmp_b2_test` | 23 | 23 | 0 | 0 |
| `bash tests/run.sh sync_test` (com `debug_sync_test`) | 93 | 93 | 0 | 0 |
| `bash tests/run.sh composicao_test` | 28 | 28 | 0 | 0 |
| `bash tests/run.sh json` | 62 | 62 | 0 | 0 |
| `bash tests/run.sh harness` | 22 | 22 | 0 | 0 |

Lint (`sh scripts/lint.sh`, um por vez, rc 0): `lib/tmp.sh`, `lib/debug.sh`, `tests/unit/tmp_test.sh`.

Recomendacoes que ficam (menores, fora desta entrega): 5, 10 e 11 da rodada 1; 8 (parcial) da rodada 1; N4 da rodada 2.

## Validacao independente do QA

Detalhe em [validacao-qa-debug-transferencias](2026-10-24-0330-validacao-qa-debug-transferencias.md). Ciclo 1 (em quatro retomadas, 1 a 1d, pelo teto de chamadas) APROVADO, sem defeito de produto: `qa_debug_transferencias_b12_test` 27 aprovados, 0 reprovados, 1 pulado (`download_hash_divergente`: o duplo nao envia `Dropbox-API-Result`; `RF-160(c)` coberto por `retomada_download_test` `tc_dbg_15`). `QA-DBG-01` (linhas `http` x `chamadas` na falha de rede) foi erro de premissa da suite: a terceira requisicao era a sonda, que sai como `debug: sonda`; o Tech Lead acrescentou `rf162e_reemissao_diagnostica_do_503_conta_igual_nos_tres_lugares` (`debug_http_test`) e decidiu `DIV-351`. `QA-DBG-02` (linha `sonda` fora de `chave=valor`) e a decisao `DIV-337` A.

- **Aceite do solicitante pela regra 12, em 2026-10-24 ("Aprovo"):** suite `tests/integracao/qa_debug_transferencias_b12_test.sh`, 28 casos, sha256 `ef18bce7a96fe4f10ecde9d5fc7f6a9fd4b1d16d878b99b99caeee8fbfb6386d` (arquivo final, depois de o Tech Lead remover a linha morta do SC2317; lint rc 0, `harness` 22/22, `json` 62/62).
