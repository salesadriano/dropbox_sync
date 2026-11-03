# Relatorio final do `sync` lista cada arquivo com o tamanho e cada falha com o motivo

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "no relatorio final, ao lado dos arquivos transferidos, inclua o tamanho dos arquivos, em MB, GB ou TB conforme o caso, nos caso de erro deve tambem apresentar o motivo da falhar" |
| Porte | M - contrato publico de saida do `sync` (`RF-35`, `RF-36`, `RF-46`, `RF-59`); `sh scripts/porte.sh`: 226 linhas de codigo, gatilho `commands/*.sh`, `porte: M` |
| Log de prompt | `docs/prompts/2026-11-03_1203_relatorio-com-tamanho-e-motivo.md` |
| Issues | nenhuma |
| Branch / base | `feature/relatorio-com-tamanho-e-motivo` sobre `origin/develop` @ `6c29d28` |
| Agents | Tech Lead (desenho, implementacao e gates), QA Expert (validacao independente), UX Expert (parecer sobre a forma do relatorio) |
| Data | 2026-11-03 |

## 2. Causa ou decisao

- Situacao: a lista por arquivo saia so no plano, antes da execucao (`transferir=`), sem tamanho; ao fim saiam contadores; a falha por item ia so para stderr e, no `--json`, sem o resumo.
- Decisao (`RF-208`): ao fim, antes dos contadores e em qualquer modo de saida, uma linha por arquivo concluido (`enviado=<caminho> (<tamanho>)` / `recebido=...`) e uma por falha (`falha=<caminho> (<tamanho>): <classe> <motivo>`). Tamanho em unidades decimais (KB, MB, GB, TB, uma casa decimal; bytes abaixo de 1 KB), funcao nova `dbx_output_tamanho_humano` em `lib/output.sh` (a barra de progresso segue em KiB/MiB, `lib/progress`). `--json`: nenhum campo existente muda; `falha_motivo`/`falha_tamanho` ao lado de `falha_caminho`/`falha_classe`, e `enviado_caminho`/`enviado_tamanho` (`recebido_*`) em bytes.
- Por que assim: sem terminal (o `nohup` da producao) a saida ja e `chave=valor` sem `--json`, entao a linha legivel precisa sair nos dois modos; o consumidor automatizado recebe bytes em campos proprios (acrescimo compativel, `RF-35`). Alternativa descartada: pendurar o tamanho na linha `transferir=` do plano, que sai ANTES da execucao e mudaria o valor de um campo existente.
- Ponto unico: `_dbx_cmd_sync_concluido` nos quatro caminhos de sucesso (lote, sequencial de envio, sequencial de recebimento, paralelo) e `_dbx_cmd_sync_falha_emitir` (ja unico) guardando motivo e tamanho; o relatorio le os vetores ao fim, inclusive em ciclos.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/output.sh` | Novo `dbx_output_tamanho_humano` | +28/-0 |
| `commands/sync.sh` | Vetores de concluidos e de motivo/tamanho das falhas; `_dbx_cmd_sync_tamanho_do_item`, `_dbx_cmd_sync_concluido`, `_dbx_cmd_sync_relatorio_itens`; `size` da listagem lido sempre no `--receber`; mapa `tam_item`; relatorio final | +109/-2 |
| `tests/unit/output_test.sh` | `teste_tamanho_humano_usa_unidades_decimais_com_uma_casa` | +16/-0 |
| `tests/integracao/sync_test.sh` | `teste_relatorio_final_lista_cada_arquivo_enviado_com_o_tamanho` (sequencial e `--paralelo 2`), `teste_relatorio_final_traz_a_falha_com_tamanho_e_motivo`, `teste_relatorio_final_estruturado_acrescenta_motivo_tamanho_e_arquivos_concluidos`, `teste_relatorio_final_do_recebimento_traz_o_tamanho_do_arquivo_recebido` | +71/-0 |
| `README.md` | Paragrafo "Relatorio final por arquivo" na secao do `sync` | doc |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | v1.39, `RF-208` | doc |
| `docs/prompts/2026-11-03_1203_relatorio-com-tamanho-e-motivo.md` | Novo | doc |

Total de linhas de codigo (producao e teste, sem documentacao): **226**.

## 4. Testes rodados

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `tests/integracao/sync_test.sh` (+ `debug_sync_test.sh` pelo filtro) | `commands/sync.sh` | `bash tests/run.sh sync_test.sh < /dev/null` | 104 | 104 | 0 | nao exibida pelo runner |
| `tests/unit/output_test.sh` | `lib/output.sh` | `bash tests/run.sh output_test.sh < /dev/null` | 32 | 32 | 0 | idem |
| `json_test`, `http_test`, `preflight_test`, `composicao_test` | auditorias de `lib/` inteiro | idem | - | todos | 0 | idem |
| `cursor_test`, `verificar_test`, `qa_sync_blocos`, `progresso_linha_test` | saida e ciclos do `sync` | idem | - | todos | 0 | idem |
| `tests/integracao/qa_*` (todas) | saida do `sync` lida pelas suites do QA | `bash tests/run.sh qa_ < /dev/null` | (secao 6) | | | |

- Red observado: `teste_tamanho_humano_*` reprovou sem a funcao (`Bail out!`); `teste_relatorio_final_do_recebimento_*` reprovou sem a correcao (`trecho ausente: [recebido...]`), interrompendo o arquivo (parada no primeiro erro, Regra 9). Execucao final sem interrupcao.
- Barreiras estaticas: `shellcheck -x -s bash` nos quatro arquivos sem aviso.
- Testes de seguranca e acesso (Regra 6): motivo mascarado pelo valor dos segredos em memoria (mesma guarda da linha de stderr); caminho pela exibicao segura de `RF-59(d)`; nenhuma rota, sessao ou segredo tocado.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: CLI sem formulario.
- Suite completa local no push para a PR: ver secao 8.

## 5. Gates

| Gate | Skills aplicadas | Achados | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; checklist aplicado integralmente | nenhum: red antes do green nos dois arquivos, selecao pelos itens afetados mais as auditorias de `lib/`, parada no primeiro erro | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + boas praticas de shell; checklist aplicado integralmente | nenhum: formatacao na camada de apresentacao (`lib/output`), registro no comando, ponto unico de sucesso e de falha; acrescimo compativel ao contrato (`RF-35`) | Aprovado |

- Ciclo: 1
- `sh scripts/alteracoes-externas.sh --detectar`: exit 0 antes dos gates

## 6. QA

- (pendente: validacao independente do QA Expert e parecer do UX Expert, ciclo 1)

## 7. Riscos e rollback

- Riscos residuais: saida mais longa em execucoes com milhares de arquivos (uma linha por concluido, na mesma escala do plano `transferir=` que ja existe); consumidor que le a saida sem `--json` e ignora chaves desconhecidas nao e afetado.
- Impacto: contrato de saida do `sync` recebe chaves novas; nenhum campo existente muda. `upload`/`download` de pasta fora desta demanda.
- Rollback: `git revert` do commit basta.

## 8. Links e aceites

- Entradas de memoria: (pendente: aceite da suite do QA, regra 12)
- Documentacao sincronizada: `README.md`, `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` (v1.39); inventario de testes pelo QA.
- Commit(s): (pendente)
- PR: (pendente) para `develop`; integrar apos a PR #86 (mesmo arquivo `commands/sync.sh`, regioes distintas).
- Tech Lead: gates verdes; aprovacao condicionada ao QA e ao UX
- Solicitante: (pendente)
