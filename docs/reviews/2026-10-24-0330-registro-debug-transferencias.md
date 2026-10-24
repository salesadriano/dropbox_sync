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
