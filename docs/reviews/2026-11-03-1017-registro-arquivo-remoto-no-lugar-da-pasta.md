# Arquivo remoto com o nome de uma pasta local deixa de encerrar o `sync` em ciclos

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | Log de producao (2.3.2): `dbx --debug sync -p --enviar --origem /mnt/c/Unimake/UniNFe/. --destino /ASJ/ASJASS/UniNFe --espelhar --confirmar` termina no ciclo 1 com `erro=enumeracao remota recusada: path/not_folder/` e `saida=2` |
| Porte | M - defeito critico em producao (o espelhamento nao termina) e tratamento de erro da enumeracao remota; `sh scripts/porte.sh`: 69 linhas de codigo, gatilho `commands/*.sh`, `porte: M` |
| Log de prompt | `docs/prompts/2026-11-03_1017_arquivo-remoto-no-lugar-da-pasta.md` |
| Issues | nenhuma |
| Branch / base | `feature/arquivo-remoto-no-lugar-da-pasta` sobre `origin/develop` @ `6c29d28` |
| Agents | Tech Lead (diagnostico, implementacao e gates), QA Expert (validacao independente) |
| Data | 2026-11-03 |

## 2. Causa ou decisao

- Causa (localizada no codigo e reproduzida pelo teste com a mesma mensagem do log): no `sync --enviar` em ciclos (`RF-189`) cada diretorio local do ciclo e listado no destino por `list_folder` nao recursivo (`dbx_sync_listar_diretorio`). Quando o caminho remoto homonimo e um ARQUIVO, a Dropbox responde `409 path/not_folder`; `_dbx_sync_listar_paginas` so tolerava `path/not_found`, dava a enumeracao como recusada e `RF-193` encerrava o `sync` no ciclo 1 com `uso_invalido` (2), sem nomear o caminho. O arquivo que ocupa o nome nunca era apagado, porque a exclusao so roda ao fim do ciclo lido.
- Decisao (`DIV-394`): num subdiretorio do ciclo, `not_folder` vale como pasta remota vazia, com um aviso por pasta nomeando o caminho (`DBX_SYNC_PASTAS_OCUPADAS`, avisado por `commands/sync.sh`); o arquivo homonimo ja e orfao de `RF-47` pela listagem do pai e sai no plano de exclusao sob `--espelhar`. Na raiz do destino `not_folder` continua falha. Toda recusa de enumeracao passa a nomear o caminho (`enumeracao remota recusada em <caminho>: ...`). Solucao unica: e a mesma tolerancia ja dada a `not_found`, limitada ao subdiretorio; a alternativa de apagar o arquivo antes de listar criaria uma exclusao fora do plano anunciado (`RF-41(d)`), inaceitavel.
- Efeito residual, documentado no aviso: os envios para dentro da pasta ocupada podem falhar por item nesse ciclo (`path/conflict/file`) porque a exclusao do orfao roda ao fim do ciclo; a execucao seguinte completa.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/sync.sh` | Alterado: ramo `*not_folder*` em `_dbx_sync_listar_paginas`; canal `DBX_SYNC_PASTAS_OCUPADAS`; motivo da recusa nomeia o caminho | +19/-1 |
| `commands/sync.sh` | Alterado: zera o canal no inicio do ciclo e emite um `dbx_cmd_avisar` por pasta ocupada | +9/-0 |
| `tests/integracao/sync_test.sh` | Alterado: gancho `nao_pasta` no duble de `curl`; `teste_arquivo_remoto_com_o_nome_de_uma_pasta_local_nao_encerra_o_sync`, `teste_destino_remoto_que_e_um_arquivo_falha_nomeando_o_caminho` | +40/-0 |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | v1.38, `DIV-394` | doc |
| `docs/prompts/2026-11-03_1017_arquivo-remoto-no-lugar-da-pasta.md` | Novo | doc |

Total de linhas de codigo (producao e teste, sem documentacao): **69**.

## 4. Testes rodados

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `tests/integracao/sync_test.sh` (+ `debug_sync_test.sh` pelo filtro) | `lib/sync.sh`, `commands/sync.sh` | `bash tests/run.sh sync_test.sh < /dev/null` | 102 | 102 | 0 | nao exibida pelo runner |
| `tests/integracao/qa_sync_blocos_*` | ciclos (`RF-189`) | `bash tests/run.sh qa_sync_blocos < /dev/null` | 25 | 25 | 0 | idem |
| `tests/integracao/verificar_test.sh` | `dbx_sync_listar_completo` | `bash tests/run.sh verificar_test.sh < /dev/null` | 17 | 17 | 0 | idem |
| `json_test`, `http_test`, `preflight_test`, `composicao_test` | auditorias de `lib/` inteiro (memoria `2026-10-18-1745-selecao-inclui-auditorias-lib`) | `bash tests/run.sh <arquivo> < /dev/null` | - | todos | 0 | idem |
| `sync_blocos_test`, `sync_plano_test`, `sync_tabela_test` | `lib/sync.sh` | idem | - | todos | 0 | idem |

- Red observado: `teste_arquivo_remoto_com_o_nome_de_uma_pasta_local_nao_encerra_o_sync` reprovou antes da correcao com `diagnostico: erro=enumeracao remota recusada: path/not_folder/..` (a mensagem do log de producao), `obtido: [2]`; o runner parou ali (parada no primeiro erro, Regra 9). Execucao final sem interrupcao.
- Barreiras estaticas: `shellcheck -x -s bash lib/sync.sh commands/sync.sh tests/integracao/sync_test.sh` sem aviso.
- Testes de seguranca e acesso (Regra 6): a guarda destrutiva do `--espelhar` e o cenario do teste (o orfao apagado e o que a listagem do pai mostrou; nada e apagado por inferencia); nenhuma rota, sessao ou segredo tocado.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: CLI sem formulario.
- Suite completa local no push para a PR: ver secao 8 (preenchida no push).

## 5. Gates

| Gate | Skills aplicadas | Achados | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; checklist aplicado integralmente | nenhum: red antes do green, selecao pelos itens afetados mais as auditorias de `lib/`, parada no primeiro erro | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + boas praticas de shell; checklist aplicado integralmente | nenhum: `lib/sync.sh` segue sem depender de `lib/cmd` (o aviso sai pelo canal, emitido no comando); sem contrato publico, flag ou schema tocado; mensagem de erro so ganha o caminho | Aprovado |

- Ciclo: 1
- `sh scripts/alteracoes-externas.sh --detectar`: exit 0 antes dos gates (so os arquivos desta demanda, todos registrados)

## 6. QA

- (pendente: validacao independente do QA Expert, ciclo 1)

## 7. Riscos e rollback

- Riscos residuais: envios para dentro da pasta ocupada podem falhar por item no ciclo em que o orfao ainda existe (aviso explicito; a execucao seguinte completa). Sem `--espelhar` o arquivo homonimo permanece e os envios para dentro da pasta seguem falhando por item ate o operador remover ou renomear o arquivo na Dropbox.
- Impacto: nenhum em contrato, CLI, schema ou dependencia; uma mensagem de erro ganha o caminho remoto.
- Rollback: `git revert` do commit basta.

## 8. Links e aceites

- Entradas de memoria: (pendente: aceite da suite do QA, regra 12)
- Documentacao sincronizada: `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` (v1.38); inventario de testes pelo QA.
- Commit(s): (pendente)
- PR: (pendente) para `develop`
- Tech Lead: gates verdes; aprovacao condicionada ao QA
- Solicitante: (pendente)
