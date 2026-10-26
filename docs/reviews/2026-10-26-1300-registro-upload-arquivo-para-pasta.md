# Upload de arquivo para pasta existente

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "a origem é um arquivo e o destino é uma pasta, nesta casos a aplicação deve entender que o arquivo deve ser enviado para a pasta e não retornar erro" |
| Porte | M - muda o contrato do argumento `destino` do `dbx upload` (CLI) e a emenda de `RF-60(g)(h)`; sem schema, credencial, segredo nem dependencia nova |
| Log de prompt | `docs/prompts/2026-10-26_1300_upload-arquivo-para-pasta.md` |
| Branch / base | `feature/upload-arquivo-para-pasta` sobre `origin/develop` @ `6df321e` |
| Agents | `senior-developer` (implementacao), `qa-expert` (validacao independente), Tech Lead (gates e registro) |
| Data | 2026-10-26 |

## 2. Causa ou decisao

Com origem arquivo e destino que ja e pasta no Dropbox, o envio ia ate o `finish` e voltava `409 path/conflict/folder`; a pre-checagem `get_metadata` (`RF-60`) ja via a pasta e seguia. Decisao (`RF-174`): o alvo passa a ser `<pasta>/<nome da origem>`, pela `/` final (sem consulta) ou pelo tipo `folder` da consulta da pre-checagem, reaproveitada; com `--forcar` ou entrada padrao, uma consulta so de tipo. Alternativa descartada: recusar cedo com mensagem, porque o solicitante pediu o envio para a pasta. O alvo final passa pelo ponto unico de confinamento do caminho remoto.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `commands/upload.sh` | Alterado | +75/-1 |
| `bin/dbx` | Alterado (ajuda) | +3/-1 |
| `README.md` | Alterado | +5/-0 |
| `tests/integracao/comandos_test.sh` | Alterado (`RF-60(g)(h)` emendado: 1 consulta de tipo) | +5/-2 |
| `tests/integracao/upload_pasta_test.sh` | Novo | +262 |
| `tests/integracao/qa_upload_para_pasta_b15_test.sh` | Novo (QA) | +381 |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | Alterado (`RF-174`, emenda `RF-60`, v1.31) | +3/-1 |

Total de linhas de codigo (producao e teste, sem documentacao): **731**.

## 4. Testes rodados

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `upload_pasta_test.sh` | `commands/upload.sh` | `bash tests/run.sh upload_pasta` | 13 | 13 | 0 | - |
| filtro `upload` | `commands/upload.sh` | `bash tests/run.sh upload` | 56 | 56 | 0 | - |
| filtro `transfer` | objeto de publicacao refeito | `bash tests/run.sh transfer` | 68 | 68 | 0 | - |
| filtro `retomada` | chave da retomada com alvo final | `bash tests/run.sh retomada` | 142 | 141 | 0 | - (1 pulado) |
| `comandos_test.sh` | emenda `RF-60(g)(h)` | `bash tests/run.sh comandos` | - | APROVADA | 0 | - |
| `json`, `harness`, `preflight` | auditorias | `bash tests/run.sh <filtro>` | - | APROVADA | 0 | - |

- Red observado: `upload_pasta_test.sh` contra `git archive HEAD`, caso a caso: 11 de 13 reprovam e o caso de arquivo identico reprova na medicao seguinte; os 2 restantes (destino inexistente e destino arquivo) preservam o comportamento anterior.
- Parada no primeiro erro (Regra 9): runner `tests/run.sh` para no primeiro erro; execucoes finais sem interrupcao.
- Barreiras estaticas do modulo tocado: `shellcheck` limpo em `commands/upload.sh`, `bin/dbx` e nos testes novos.
- Testes de seguranca e acesso (Regra 6): confinamento do alvo final (nome com `..x`, aspas, unicode; `raiz_remota`; `/../fora/` recusado sem escrita) na suite do QA.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: CLI sem formulario.
- Suite completa local no push para a PR: Ainda nao houve push para a PR.

## 5. Gates

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; `Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados` | Menor: asserção de `caminho` do caso identico removida por engano no ciclo do developer; reinserida (`upload_pasta_test.sh:173`) | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + shell; `Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados` | Nenhum: resolucao em `commands/upload.sh` (`_dbx_cmd_upload_alvo_em_pasta`, `_dbx_cmd_upload_trocar_para_pasta`), alvo pelo ponto unico `_dbx_cmd_caminho_remoto` | Aprovado |

- Ciclo: 1
- `sh scripts/alteracoes-externas.sh --detectar`: so o log de prompt do proprio Tech Lead foi acusado e registrado.

## 6. QA

- Validacao independente: `tests/integracao/qa_upload_para_pasta_b15_test.sh`, 26 casos (pasta existente simples e por sessao, `/` final, destino `/`, nomes especiais, `raiz_remota`, dispensa por hash, `--forcar`, entrada padrao, `--rev`, `--dry-run`, comportamento anterior). sha256 `dabdb304830025c12209554ab6111c31b2d8765015bcc8919d1f871d5934a867`.
- Comando: `bash tests/run.sh qa_upload_para_pasta_b15`: 26 aprovados, 0 reprovados; `json` 62/62; `harness` 22/22. Red no codigo antigo: 20 de 26 reprovam; 6 sao guardas de preservacao.
- Achados: nenhum no produto. Observacao levada ao Tech Lead e resolvida: `RF-174(f)` explicita que `--rev` com `/` final segue a regra da barra.
- Veredito do QA: Aprovado, 2026-10-26.

## 7. Riscos e rollback

- Riscos residuais: com `--forcar` e entrada padrao ha uma chamada `get_metadata` a mais (so leitura) por execucao.
- Impacto: contrato do `destino` do `dbx upload` de arquivo (ajuda e README atualizados); nenhum schema ou dependencia.
- Rollback: `git revert <sha>` basta.

## 8. Links e aceites

- Entradas de memoria: Nenhuma: decisao e aceite registrados no log de prompt.
- Documentacao sincronizada: `README.md`, ajuda do `dbx upload`, `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md`.
- Commit(s): ver historico da branch.
- PR: a abrir.
- Tech Lead: **Aprovado**, 2026-10-26.
- Solicitante: "Aprovo (Recomendado)" para `qa_upload_para_pasta_b15_test.sh`, sha256 `dabdb304830025c12209554ab6111c31b2d8765015bcc8919d1f871d5934a867` (AskUserQuestion, 2026-10-26).
