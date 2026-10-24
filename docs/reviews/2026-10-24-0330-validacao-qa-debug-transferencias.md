# Validacao independente do QA - debug de transferencias (porte M) - ciclo 1 (fechamento 1d)

**Veredito do ciclo 1: APROVADO, com uma ressalva de lint (abaixo) e uma limitacao de fixture.** Nenhum defeito de producao encontrado.

## Suite

- `tests/integracao/qa_debug_transferencias_b12_test.sh` (28 casos). sha256 final: `78c1c61cbfd042cac49cc058c5d724ef542a214eba6d08a6c976b48713acd60d`.
- Fixture do sync copiada de `debug_sync_test.sh` sob prefixo `_qd_` (reuso de fixture, nao de teste).

## Totais

| Execucao | Resultado |
|---|---|
| `bash tests/run.sh qa_debug_transferencias_b12_test` (arquivo final) | 27 aprovados, 0 reprovados, 1 pulado, APROVADA |
| `bash tests/run.sh json` (arquivo anterior a ultima edicao cosmetica) | APROVADA 62/62 (RNF-24 ok) |
| `bash tests/run.sh harness` (idem) | APROVADA 22/22 (nenhuma funcao redefinida, nem em heredoc) |
| `sh scripts/lint.sh <suite>` | 1 aviso SC2317 (info) em `return 0` apos `pular` no caso pulado; todo o resto limpo |

Nota: apos o ultimo json/harness a unica mudanca foi esvaziar o corpo do caso pulado (remocao de codigo inalcancavel). O `harness` nao foi reexecutado sobre esse arquivo final; o lint tambem nao apos remover o corpo (restou so o `return 0` a retirar).

## Cobertura (todos aprovados, salvo o pulado)

- Segredo: sentinelas de token, refresh, app_secret, chave, session_id, cursor, URL temporaria, query/senha e `Authorization` ausentes de stdout e stderr em upload (simples, sessao por stdin, 409, 5xx, rede, retentativa 429), download (arquivo, stdout, 5xx, rede), sync (enviar, receber, paralelo, falha de download), e nos 7 casos de sinal.
- Invariantes: codigo de saida, stdout byte a byte, numero de requisicoes e mensagens fora das linhas `debug:` iguais com e sem `--debug`, em sucesso e falha (rede, 5xx, 409, credencial ausente).
- Sinal: INT e TERM antes da primeira requisicao (pedido de token) e durante upload, download, sync e sync paralelo: mesmo codigo com e sem `--debug`, exatamente um `resumo` com `saida=` igual ao codigo (RF-162(c)), formato valido, sem segredo.
- Formato: toda linha `debug:` valida pelo regex (categoria do vocabulario, `chave=valor`, aspas escapadas), sem `\r`, uma linha fisica por evento com caminho de origem local contendo espaco, aspas, barra invertida, quebra de linha e controle (controle vira `?`).
- Resumo: exatamente um por execucao, `saida=` igual ao codigo real, `chamadas + tentativas_extras` igual as requisicoes do duplo, e (DIV-351 A) igual as linhas `debug: http` mais as linhas `debug: sonda`; `paralelo=N` no resumo do sync paralelo e sem linha `paralelo` antiga; `limites_429=2` e `retry_after=1` com teto na retentativa.
- Progresso: `--debug --progresso` em upload e sync sem `\r` e sem linha misturada.

## Caso pulado e justificativa

`qa_download_hash_divergente_registra_e_mantem_codigo`: o duplo de curl nao envia `Dropbox-API-Result`, entao nao ha `content_hash` para conferir (limite da fixture, nao defeito). RF-160(c) `hash=divergente` esta coberto pelo `tc_dbg_15` de `tests/integracao/retomada_download_test.sh` (developer).

## Defeitos e observacoes

- Defeitos de producao: nenhum.
- QA-DBG-01: erro de premissa do QA, nao defeito. Na falha de rede a terceira requisicao e a sonda de disponibilidade (`debug: sonda`); resumo e duplo concordavam em 3. Resolvido pela emenda DIV-351 A (RF-162(e): `chamadas` = linhas `http` com `tentativa=1` + linhas `sonda`), que a suite agora assere.
- QA-DBG-02: observacao. `debug: sonda GET https://www.gstatic.com -> status 204` mantem o formato proprio (DIV-337 A, decidido); o regex da suite isenta a categoria `sonda`.
- Premissas corrigidas durante o ciclo (erros do QA, nao do produto): destino remoto com caractere de controle e recusado com 13 (correto); upload identico ao remoto pula a transferencia; upload nao retenta 503 (nao idempotente), so 429; resposta de sessao precisa de `content_hash` coerente (o produto reprova com 11 quando nao confere); sinal enviado ao grupo de processos (`setsid`).

## Sem evidencia / limitacoes

- `hash=divergente` no download: ver acima (cobertura do developer).
- Sinal "antes da primeira requisicao" foi exercido no pedido de token (a primeira requisicao ja em voo); nao ha janela anterior a ela na ferramenta.
- Suite completa do projeto nao executada (nao pedida); execucao seletiva dos modulos acima.

## Ressalva

Retirar o `return 0` do caso pulado (aviso SC2317, info) e reexecutar lint e harness no sha final antes do merge.

## Fechamento pelo Tech Lead (arquivo final da suite)

O QA aprovou o ciclo 1 com o sha256 `78c1c61c...acd60d` e a ressalva de lint SC2317 (`return 0` inalcancavel depois do `pular` em `teste_qa_download_hash_divergente_registra_e_mantem_codigo`). O Tech Lead removeu so essa linha morta (nenhum caso muda) e rodou tudo sobre o arquivo final, como pede a memoria do projeto antes do aceite do sha256:

| Verificacao | Resultado |
|---|---|
| `sh scripts/lint.sh tests/integracao/qa_debug_transferencias_b12_test.sh` | rc 0 |
| `bash tests/run.sh qa_debug_transferencias_b12_test` | 28 casos: 27 aprovados, 0 reprovados, 1 pulado (`download_hash_divergente`, limite da fixture; `RF-160(c)` coberto por `retomada_download_test` `tc_dbg_15`) |
| `bash tests/run.sh harness` | 22/22 |
| `bash tests/run.sh json` | 62/62 |

**sha256 final da suite:** `ef18bce7a96fe4f10ecde9d5fc7f6a9fd4b1d16d878b99b99caeee8fbfb6386d`.
