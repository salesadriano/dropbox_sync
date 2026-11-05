# Espera pela trava de raiz nao desiste mais quando o detentor apaga o diretorio de estado

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "abra a demanda do pft03 nas duas linhas": eliminar a causa da falha intermitente de `pft03_espera_cobre_a_trava_e_conclui_quando_a_primeira_termina`, que derrubou a suite completa legada quatro vezes nas demandas DIV-395 e release 2.3.4 |
| Porte | M - defeito de concorrencia na trava (caminho de erro); `sh scripts/porte.sh`: 7 arquivos, 277 linhas de codigo (23 em `lib/state.sh`, o resto em testes), `porte: M` |
| Log de prompt | `docs/prompts/2026-11-04_1742_trava-raiz-diretorio-sumido.md` |
| Issues | nenhuma |
| Branch / base | `feature/trava-raiz-diretorio-sumido` sobre `origin/develop` @ `7d974bc`; a mesma correcao em `feature/trava-raiz-diretorio-sumido-bash42` sobre `origin/support/bash-4.2` @ `35b556f` (`lib/state.sh` difere so na expansao de `faltam`, preservada) |
| Agents | Tech Lead (diagnostico, sonda, porte para a linha legada, gates, fechamento das medicoes do QA), Senior Developer (TDD e correcao), QA Expert (suite independente) |
| Data | 2026-11-04 |

## 2. Causa ou decisao

- Nao era falta de folga no teste: quem espera saia 6 (`permissao`), nao 7 (`conflito`). Sonda no conteiner `centos:7` (bash 4.2.46) sob carga, cenario do `pft03` repetido 15 vezes: 4 sairam `6|diretorio de estado sem escrita: <xdg>/dbx`.
- Causa (`DIV-396`): ao soltar, o detentor remove o diretorio de estado que a sua aquisicao criou (`_dbx_state_trava_raiz_desfazer_diretorio`). Quem espera recria o diretorio a cada sondagem (`_dbx_state_trava_raiz_garantir_diretorio`). Duas intercalacoes viravam permissao: (1) o detentor remove o diretorio entre a conferencia e a sondagem, e a sondagem nao consegue gravar; (2) o `mkdir -p -m 700` perde a corrida e falha com o diretorio ja existindo.
- Efeito em producao: com `--esperar N`, quando o diretorio de estado nasce na execucao que detem a trava (primeira execucao no host, ou depois de limpeza), quem espera podia desistir com um erro de permissao enganoso em vez de adquirir.
- Decisao: o detentor continua removendo so o que criou. `_dbx_state_trava_raiz_garantir_diretorio` so devolve permissao se o `mkdir` falhar e o diretorio continuar inexistente, e so anota como seu o que criou; no laco de `dbx_state_trava_raiz_adquirir`, permissao com o diretorio sumido recria e tenta de novo, ate 50 vezes, e o motivo e limpo quando a trava e adquirida. Diretorio existente sem escrita ou de outro dono continua 6.
- O `pft03` nao teve a folga alterada.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/state.sh` | Alterado: `mkdir` tolerante ao diretorio recriado; nova tentativa com o diretorio sumido; motivo limpo ao adquirir | +23/-4 |
| `tests/unit/state_trava_raiz_test.sh` | Alterado: 3 casos `pft_espera_*` (Senior Developer), com um duble unico de `sleep` | +65/-0 |
| `tests/integracao/qa_trava_raiz_diretorio_sumido_test.sh` | Novo: suite do QA, 6 casos | +185/-0 |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | v1.41, `DIV-396` | doc |
| `docs/testes/inventario-de-testes.md` | 9 -> 12 em `state_trava_raiz`; secao da suite do QA | doc |
| `docs/prompts/2026-11-04_1742_trava-raiz-diretorio-sumido.md` | Novo | doc |

## 4. Testes rodados

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos |
|---|---|---|---|---|---|
| `tests/unit/state_trava_raiz_test.sh` | trava de raiz | `bash tests/run.sh state_trava_raiz_test.sh < /dev/null` | 12 | 12 | 0 |
| `tests/integracao/qa_trava_raiz_diretorio_sumido_test.sh` | idem | idem | 6 | 6 | 0 |
| `state_test`, `state_trava_test`, `perfis_trava_raiz_test`, `qa_trava_tmp_b2_test` | `lib/state.sh` e travas | `bash tests/run.sh <arquivo> < /dev/null` | 24, 28, 10, 23 | todos | 0 |
| `json_test`, `harness_test`, `composicao_test` | auditorias | idem | 66, 23, 28 | todos | 0 |

- Red observado (base `7d974bc` por `git archive`, um caso por vez): `pft_espera_adquire_quando_o_detentor_remove_o_diretorio_depois_da_checagem` e `pft_espera_adquire_quando_a_criacao_do_diretorio_perde_a_corrida` reprovam com `esperado: [0]`, `obtido: [6]`; o de guarda passa. Suite do QA: 3 de 6 reprovam, os 3 de guarda passam.
- Sonda depois da correcao, no conteiner `centos:7` sob a mesma carga: 30 de 30 adquiriram (antes, 4 de 15 desistiram).
- `qa_trava_tmp_b2_test` reprovou uma vez na linha principal enquanto a suite do QA rodava em paralelo no mesmo worktree; passou 23/0 tres vezes em seguida, isolado.
- Linha legada, no bash 4.2.46 real (`sh scripts/suite-bash42.sh <arquivo>`): `state_trava_raiz` 12/0 (tres vezes), `qa_trava_raiz_diretorio_sumido` 6/0, `state_test` 24/0, `perfis_trava_raiz` 10/0, `qa_trava_tmp_b2` 21/0 (2 pulados).
- Barreiras estaticas: `sh scripts/lint.sh lib/state.sh tests/unit/state_trava_raiz_test.sh tests/integracao/qa_trava_raiz_diretorio_sumido_test.sh` sem achado nas duas linhas.
- Testes de seguranca e acesso (Regra 6): diretorio sem escrita e diretorio de outro dono continuam recusados (casos de guarda nas duas suites); a conferencia de dono nao foi afrouxada.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: CLI sem formulario.
- Suite completa local no push para a PR: secao 8.

## 5. Gates

| Gate | Skills aplicadas | Achados | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9 | Corrigido no ciclo: o teste do developer redefinia `sleep` duas vezes (auditoria `harness_test`); unificado num duble so, ligado por `APOS_SOLTAR`. Red antes do green, intercalacao forcada sem carga | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + boas praticas de shell | nenhum: correcao local ao laco de espera e ao auxiliar de diretorio; sem contrato, flag, schema ou dependencia; nova tentativa limitada | Aprovado |

- Ciclo: 1

## 6. QA

- Validacao independente: `docs/reviews/2026-11-04-1742-validacao-qa-trava-raiz-diretorio-sumido.md`. Aprovado, com a suite `tests/integracao/qa_trava_raiz_diretorio_sumido_test.sh` aceita (sha256 `ccf0339924721ba1b6d5f088a542a5e4574a790c44916fee3243af1e21ab85d9`). Achado menor (motivo antigo apos sucesso) corrigido. Ciclos de reprovacao: 0.

## 7. Riscos e rollback

- Riscos residuais: a nova tentativa e limitada a 50 repeticoes sem espera entre elas; um diretorio que some sem parar ainda termina em 6, como antes.
- Impacto: nenhum em contrato, CLI, schema ou dependencia.
- Rollback: `git revert` do commit basta.

## 8. Links e aceites

- Entradas de memoria: `2026-11-04-1742-aceite-testes-qa-trava-raiz-diretorio-sumido` (aceite da suite do QA, regra 12).
- Documentacao sincronizada: `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` (v1.41, `DIV-396`); inventario de testes.
- Commit(s): correcao com os testes e a validacao, nas duas linhas.
- PR: para `develop` e para `support/bash-4.2`, push e abertura pelo solicitante.
- Tech Lead: **Aprovado**, 2026-11-04 - gates e QA verdes; merge condicionado a suite completa registrada.
- Solicitante: suite `qa_trava_raiz_diretorio_sumido_test.sh` aceita em 2026-11-04 (prompt 2), sha256 `ccf0339924721ba1b6d5f088a542a5e4574a790c44916fee3243af1e21ab85d9`, nas duas linhas.
