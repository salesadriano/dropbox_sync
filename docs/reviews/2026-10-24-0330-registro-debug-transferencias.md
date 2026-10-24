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
