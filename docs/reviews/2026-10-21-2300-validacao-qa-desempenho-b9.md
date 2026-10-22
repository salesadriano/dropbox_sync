# Validacao independente do QA: fase 9, desempenho (F-09, RF-136, RF-137)

Porte G. Papel: QA Expert. Suite nova: `tests/integracao/qa_desempenho_b9_test.sh`
(sha256 `8591aa3f6d7d572406ae5bb6718f6fe7e9191eb01a9a234d10439ccb37db5115`). Executavel real
`bin/dbx`, duplo de `curl` proprio (rotas de lote delegadas a `tests/support/lote_duplo.sh`, sem
alteracao), sem rede e sem conta real.

## Escopo

F-09 / RF-133 / RF-134 (paralelismo, equivalencia N=1 x N>1), RF-136 (exclusao em lote so no `sync
--espelhar`; `reter` item a item, DIV-269), RF-137 (envio em lote, DIV-278), RF-138 (bancada sem
segredo nos logs). Casos escritos pelos requisitos, sem consultar os testes do developer.

## Adaptacao dos duplos (tarefa 1, so duplos; nenhuma asserção afrouxada)

- `qa_integridade_p1` caso 1: a garantia (client_modified em UTC, fusos vazio, New_York, Sao_Paulo, verao
  e inverno) agora e provada no `commit` de cada entrada do `finish_batch_v2` (o helper le o corpo do lote
  quando nao ha `Dropbox-API-Arg` de `files/upload`, reaplicando o escape). Acrescentei asserções de que
  os 2 pequenos foram pelo lote (0 `files/upload`, 1 `finish_batch_v2`). O lote manda UTC: sem defeito de produto.
- `qa_robustez_rede_p2` caso 16: o duplo traduz `falhar_envio` em falhas por entrada do lote, nas tres
  classes (conflict, insufficient_space, outra). Asserção acrescentada: 3 classes distintas (`sort -u` = 3).

## Casos (15) e resultado

| Caso | Requisito | Resultado |
|---|---|---|
| qdb01 12+1 pequenos, N=1,2,4,8: mesmo codigo, saida, erro, cache (hash+nome) e bytes publicados; 13 starts, 0 `files/upload` | RF-134(a)(d), RF-137(g) | aprovado |
| qdb02 3 falhas (2 por entrada, 1 por start): N=1 = N=4, cada falha uma vez, demais 8 seguem | RF-134(b), RF-137(c) | aprovado |
| qdb03 `--paralelo` 0,9,-1,vazio,abc,08,+2,' 2',1.5,100 e `DBX_PARALELO=99`: exit 2, 0 rede, 0 estado; opcao vence ambiente; fora do `sync`: 2 | RF-133(b)(c)(e) | aprovado |
| qdb04 `--dry-run --paralelo 4 --espelhar --confirmar`: 0 chamadas de escrita, 0 lote, cache nao gravado | RF-134(e) | aprovado |
| qdb05 espelho: 1 `delete_batch` + 1 `check`, 0 `delete_v2`, `parent_rev` por item, o que existe na origem nao entra | RF-136(a)(b)(f) | aprovado |
| qdb06 guardas antes do lote: sem `--confirmar`, origem vazia, `--dry-run`, `--excluir`, nada a apagar | RF-136(a) | aprovado |
| qdb07 nao confirmado nunca conta: entrada com erro, `check` failed (lote nao relancado), `delete_batch` 400, check com menos entradas, `in_progress` ate `complete` | RF-136(b)(c) | aprovado |
| qdb08 251 exclusoes: 2 fatias, 250 + 1 | RF-136(b), DIV-259 | aprovado |
| qdb09 `reter`: sem `delete_batch`/lote no fonte e na execucao, com `delete_v2` por item; `sync.sh` sem `delete_v2` fora de comentario | RF-136(e)(f), DIV-269 | aprovado |
| qdb10 hash divergente no finish: so o item falha com classe `integridade`, os outros contam; sem hash devolvido nao falha | DIV-278 | aprovado |
| qdb11 o `start` envia o `content_hash` local de cada arquivo | DIV-278 | aprovado |
| qdb12 `finish_batch_v2` recusado: 0 enviados; `start` recusado de um: so ele falha | RF-137(c)(d) | aprovado |
| qdb13 identico nao entra no lote; 2 arquivos de 2 MiB ficam fora do lote (`files/upload`) | RF-137(a)(e) | aprovado |
| qdb14 bancada: `sl.*`, `Bearer`, `access_token` JSON redigidos nos logs, stdout e stderr | RF-138, RNF-03 | aprovado |
| qdb15 bancada: caracteriza a lacuna QA-B9-01 (ver achados) | RF-138, RNF-03 | aprovado (caracterizacao) |

## Comandos e contagens literais

| Comando | Resultado |
|---|---|
| `bash tests/run.sh qa_desempenho_b9 < /dev/null` | aprovados 15, reprovados 0, pulados 0 |
| `bash tests/run.sh qa_integridade_p1 < /dev/null` | aprovados 27, reprovados 0, pulados 0 |
| `bash tests/run.sh qa_robustez_rede_p2 < /dev/null` | aprovados 21, reprovados 0, pulados 0 |
| `bash tests/run.sh lote < /dev/null` | aprovados 31, reprovados 0, pulados 0 |
| `bash tests/run.sh reter < /dev/null` | aprovados 84, reprovados 0, pulados 0 |
| `bash tests/run.sh json < /dev/null` | aprovados 62, reprovados 0, pulados 0 (1a vez reprovou por `$(printf` na MINHA linha de p2; corrigido) |
| `bash tests/run.sh harness < /dev/null` | aprovados 22, reprovados 0, pulados 0 |
| `sh scripts/lint.sh` nos 3 arquivos | exit 0 cada |
| `bash scripts/verificar-remocao-de-casos.sh` | 2155 -> 2157 casos; nenhuma reducao nao declarada |

Agregado `qa_` (todas as suites qa_*), ultimas linhas da execucao: ver hand-back.

## Achados

| ID | Severidade | Local | Descricao | Prova |
|---|---|---|---|---|
| QA-B9-01 | Menor | `scripts/bancada.sh:210` | A redacao dos logs cobre `sl.*` e `Bearer/Authorization <1 palavra>`. `Authorization: Basic <b64>` (so a palavra Basic e redigida, o base64 sobrevive) e `refresh_token=`/`app_secret=` sem prefixo passam ao log. O `dbx` nunca emite esses formatos; e defesa em profundidade (RNF-03). Recomendacao: redigir ate o fim do valor depois de `Authorization:` e as chaves `refresh_token`/`app_secret`/`access_token`. | qdb15 caracteriza o comportamento atual (inverte ao corrigir); qdb14 verde |
| QA-B9-02 | Informativo | `lib/state.sh` / RF-137(d) | A "memoria" do sync guarda hash local, nao confirmacao remota; item com envio falho tem o hash registrado, como no envio unitario. RF-137(d) ("cache so com sucesso") vale para a decisao de envio, que e o hash REMOTO (RF-60). Sem efeito: equivalencia N=1 x N>1 e igualdade de cache comprovadas em qdb01/02. | qdb01, qdb02 |
| QA-B9-03 | Informativo | RF-137 / codigo de saida | Falha de integridade no lote sai `14` (nao concluida, RF-29), com a classe `integridade` por item (`falha f2.txt: integridade ...`), nao `11` no processo. Coerente com RF-29/35. | qdb10 |

Sem achado bloqueante ou maior. Lacuna de cobertura declarada: `Retry-After`/429 sob paralelismo, sinais
(INT/TERM) com N>1 e a ordem de saida com falhas sob N=8 nao foram exercitados por esta suite.

## Veredito

**Aprovado com ressalvas** (QA-B9-01 Menor, a criterio do Tech Lead; informativos sem acao). Aceite do
solicitante pendente sobre `qa_desempenho_b9_test.sh` (sha acima) e sobre os duplos adaptados de p1 e p2.
