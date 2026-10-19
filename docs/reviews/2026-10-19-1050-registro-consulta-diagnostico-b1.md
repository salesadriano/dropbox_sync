# Fase 1 do backlog: verificar, diagnostico, checagem de espaco e autocompletar (F-11, F-22, F-21, F-19)

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | Fase 1 do plano do backlog: `dbx verificar` (F-11), `dbx diagnostico` (F-22), checagem previa de espaco que recusa (F-21) e autocompletar de bash (F-19). Requisitos RF-65 a RF-68 (v1.10). |
| Porte | M. Toca contrato publico (comandos novos, `--forcar` no `sync`), credenciais e escopos, codigos de saida e erro. Sem gatilho de G: nenhuma fronteira nem integracao externa nova (mesmos endpoints da API ja usada). |
| Log de prompt | [docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md](../prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md) |
| Branch / base | `feature/consulta-diagnostico-b1` sobre `develop` @ `6eeb691` |
| Agents | Business Analyst (RF-65 a RF-68, v1.10); Senior Developer (implementacao, sob `protocolo-tdd` e `protocolo-conformidade`); QA Expert (validacao independente, 21 casos); Tech Lead (DIV-33 a DIV-37, decisoes do ciclo 2, fechamento). |
| Data | 2026-10-19 |

## 2. Causa ou decisao

Decisoes do solicitante e divergencias do BA decididas pelo Tech Lead na memoria [2026-10-19-1050-consulta-e-diagnostico](../../.github/agents/memoria/entradas/2026-10-19-1050-consulta-e-diagnostico.md): DIV-33 (`--forcar` pula as checagens previas; no `sync`, so o espaco e so com `--enviar`; `--forcar --receber` sai 2), DIV-34 (`verificar` sai 11 com divergencia), DIV-35 (escopos exigidos; sem o campo `scope`, aviso), DIV-36 (encerrada) e DIV-37 (alias `completion`).

Abordagens consideradas (detalhe nos pareceres do Senior Developer):

- **`verificar`:** comando proprio (`commands/verificar.sh`) com a comparacao em `dbx_sync_comparar` (`lib/sync`). Rejeitados: modo dentro do `sync` (acoplaria um comando so de leitura ao que escreve e apaga) e comparacao independente (divergiria do `sync` na primeira correcao).
- **`diagnostico`:** inspecao sem parada em `lib/preflight`, com a mesma lista de utilitarios. Rejeitadas: lista propria (duas listas divergentes, DIV-36) e laco sobre `dbx_preflight_verificar`.
- **Espaco:** auxiliar unico em `lib/cmd` (`dbx_cmd_espaco_consultar`, `_checar`, `_campos`), chamado por `upload`, `sync --enviar` e `diagnostico`.
- **Autocompletar:** script estatico `completions/dbx.bash`, com listas literais conferidas por teste contra a ajuda real.

Decisoes do Tech Lead no ciclo 2:

- **D-1, limite aceito:** o `bin/dbx` resolve o proprio caminho so com o shell; o alvo do vinculo vem por `readlink`, depois `find -printf %l`, e sem os dois ha recusa com codigo 3 nomeando o utilitario. Documentado no README e na linha `dependencias` do `diagnostico`.
- **O-3:** a simulacao do `upload` le o `content_hash` remoto antes da checagem de espaco, na ordem da execucao real. Hash igual sai `dispensado`, sem consultar o espaco; hash diferente segue a checagem e pode anunciar `recusaria`.
- **RF-15 e RF-44** proibem so escrita em simulacao; as leituras permitidas formam um conjunto fechado e contado.
- **Casos do QA** ajustados pelo proprio QA, nao pelo developer.

Requisitos: [escopo-requisitos-e-criterios-de-aceite](../requisitos/escopo-requisitos-e-criterios-de-aceite.md) (RF-65 a RF-68), [funcionalidades-candidatas](../requisitos/funcionalidades-candidatas.md) (F-11, F-19, F-21, F-22).

## 3. Arquivos

Levantado com `git status --short` e `git diff --numstat 6eeb691`; arquivos novos contados por `wc -l`.

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `bin/dbx` | Alterado (ajuda, aliases, resolucao do caminho) | +109/-20 |
| `commands/sync.sh` | Alterado (`--forcar`, checagem de espaco) | +46/-6 |
| `commands/upload.sh` | Alterado (espaco, ordem na simulacao) | +54/-1 |
| `commands/verificar.sh` | Novo | +272/-0 |
| `commands/diagnostico.sh` | Novo | +278/-0 |
| `commands/completar.sh` | Novo | +43/-0 |
| `completions/dbx.bash` | Novo | +113/-0 |
| `lib/auth.sh` | Alterado (escopos da renovacao) | +17/-0 |
| `lib/cli.sh` | Alterado | +22/-2 |
| `lib/cmd.sh` | Alterado (leitura aninhada, espaco) | +145/-1 |
| `lib/output.sh` | Alterado (mascara a app key por valor) | +4/-1 |
| `lib/preflight.sh` | Alterado (inspecao sem parada) | +25/-0 |
| `lib/sync.sh` | Alterado (`dbx_sync_comparar`) | +128/-0 |
| `install.sh` | Alterado | +23/-1 |
| `uninstall.sh` | Alterado | +8/-0 |
| `scripts/empacotar.sh` | Alterado | +5/-2 |
| `tests/unit/sync_plano_test.sh` | Novo | +76/-0 |
| `tests/unit/auth_test.sh` | Alterado | +23/-0 |
| `tests/unit/cmd_test.sh` | Alterado | +115/-0 |
| `tests/unit/output_test.sh` | Alterado | +11/-0 |
| `tests/unit/preflight_test.sh` | Alterado | +33/-1 |
| `tests/integracao/verificar_test.sh` | Novo | +367/-0 |
| `tests/integracao/diagnostico_test.sh` | Novo | +349/-0 |
| `tests/integracao/espaco_test.sh` | Novo | +325/-0 |
| `tests/integracao/completar_test.sh` | Novo | +350/-0 |
| `tests/integracao/qa_consulta_diagnostico_b1_test.sh` | Novo (QA) | +832/-0 |
| `tests/integracao/qa_cache_unico_p3_test.sh` | Alterado (QA de fase anterior, reaprovado) | +16/-2 |
| `tests/integracao/qa_robustez_rede_p2_test.sh` | Alterado (QA de fase anterior, reaprovado) | +3/-0 |
| `README.md` | Alterado | +43/-2 |
| `docs/arquitetura/system-design.md` | Alterado (BA) | +31/-2 |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | Alterado (BA) | +34/-7 |
| `docs/requisitos/funcionalidades-candidatas.md` | Alterado (BA) | +7/-5 |
| `docs/testes/mapa-modulos.md` | Alterado | +21/-9 |
| `.github/agents/memoria/entradas/2026-10-19-1023-plano-do-backlog.md` | Alterado (plano) | +1/-0 |
| `.github/agents/memoria/entradas/2026-10-19-1050-consulta-e-diagnostico.md` | Novo (decisao) | documental |
| `.github/agents/memoria/entradas/2026-10-19-1050-aceite-testes-qa-b1.md` | Novo (aceite) | documental |
| `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md` | Novo (log de prompt) | documental |

Total de linhas de codigo (producao e teste, sem documentacao): **3829** (3792 adicionadas, 37 removidas), somando `bin/`, `commands/`, `completions/`, `lib/`, `install.sh`, `uninstall.sh`, `scripts/` e `tests/`.

## 4. Testes rodados

Selecao por arquivo de teste, so dos itens afetados (Regra 8 de `protocolo-tdd`), pelo comando `bash tests/run.sh <filtro>`, um por vez. Contagens literais da ultima execucao completa e sem interrupcao do Senior Developer (pareceres, secao 2).

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `tests/unit/json_test.sh` | auditoria de `lib/*.sh` | `bash tests/run.sh json` | 60 | 60 | 0 | 1s |
| `tests/integracao/http_test.sh` | auditoria de `lib/*.sh` | `bash tests/run.sh http` | 53 | 53 | 0 | 39s |
| `tests/unit/preflight_test.sh` | `lib/preflight.sh` | `bash tests/run.sh preflight` | 34 | 34 | 0 | 4s |
| `tests/integracao/composicao_test.sh` | `commands/*.sh` | `bash tests/run.sh composicao` | 25 | 25 | 0 | 7s |
| `tests/unit/cli_test.sh` | `lib/cli.sh` | `bash tests/run.sh cli` | 17 | 17 | 0 | 0s |
| `tests/unit/cmd_test.sh` | `lib/cmd.sh` | `bash tests/run.sh cmd` | 17 | 17 | 0 | 1s |
| `tests/unit/auth_test.sh` | `lib/auth.sh` | `bash tests/run.sh auth` | 41 | 41 | 0 | 1s |
| `tests/integracao/transfer_test.sh` | `commands/upload.sh` | `bash tests/run.sh transfer` | 36 | 36 | 0 | 5s |
| `sync_test` e `sync_plano_test` | `lib/sync.sh`, `commands/sync.sh` | `bash tests/run.sh sync` | 91 | 91 | 0 | 36s |
| `tests/integracao/comandos_test.sh` | `commands/*.sh` | `bash tests/run.sh comandos` | 119 | 119 | 0 | 22s |
| 7 arquivos `qa_*` | suites de QA das fases anteriores | `bash tests/run.sh qa_` | 139 | 139 | 0 | 48s |
| `tests/integracao/verificar_test.sh` | `commands/verificar.sh` (RF-65) | `bash tests/run.sh verificar` | 17 | 17 | 0 | 4s |
| `tests/integracao/diagnostico_test.sh` | `commands/diagnostico.sh` (RF-66) | `bash tests/run.sh diagnostico` | 12 | 12 | 0 | 2s |
| `tests/integracao/espaco_test.sh` | `lib/cmd.sh`, `commands/upload.sh`, `commands/sync.sh` (RF-67) | `bash tests/run.sh espaco` | 12 | 12 | 0 | 4s |
| `tests/integracao/completar_test.sh` | `completions/dbx.bash`, `commands/completar.sh` (RF-68) | `bash tests/run.sh completar` | 16 | 16 | 0 | 2s |
| **Total, 22 arquivos** | | | **689** | **689** | **0** | **176s** |

- Lacuna: essa tabela e do ciclo 1 do developer, com 0 pulados. A selecao final do ciclo 2 foi rodada arquivo a arquivo (35 arquivos, 1038 aprovados, 2 reprovados que o QA reajustou, 2 pulados, 224s) e nao veio por filtro; vale a execucao da suite inteira abaixo.
- Execucao do QA no ciclo 2: `bash tests/run.sh </dev/null`, 35 arquivos, **1054 aprovados, 0 reprovados, 2 pulados** (ja existiam), APROVADA, sem interrupcao; a duracao nao veio na delegacao. Inclui os 21 casos de `qa_consulta_diagnostico_b1` e os 33 de `qa_cache_unico_p3`. Execucao do developer no ciclo 2, antes do ajuste do QA: 1053 aprovados, 0 reprovados, 2 pulados, 255s.
- Red observado: `sync_plano` (0 ok, 1 nao ok), `verificar`, `diagnostico`, `espaco` e `completar` (0/1 cada), `auth` (`renovacao_expoe_os_escopos_concedidos`), `preflight` (`inspecao_sem_parada_inclui_o_resumo_sha256`), `cmd` (`checar_espaco_...`), `output` (`mascara_pelo_valor_cobre_a_chave_do_aplicativo`, nao ok 13) e `esp06_simulacao_segue_a_ordem_real...`. Excecoes por inspecao da base: `cpl06_uninstall_sh_remove_so_o_autocompletar_do_dbx` (achado T-3) e a assercao nova de `dia02_pelo_vinculo_sem_dirname_nem_readlink_ainda_roda`.
- Parada no primeiro erro (Regra 9): atendida pelo runner (`Bail out!`); as interrupcoes do ciclo 1 e 2 foram corrigidas e reexecutadas do inicio.
- Barreiras estaticas: `shellcheck` sobre `lib/*.sh`, `commands/*.sh`, `bin/dbx`, `completions/dbx.bash`, `install.sh`, `uninstall.sh`, `scripts/empacotar.sh` e os testes alterados com 0 achados (supressoes novas so SC2034 de canal publico e um SC2004 em nameref de mapa associativo, cada uma com o motivo na linha acima); `scripts/*.sh` POSIX com 0 achados. Auditorias de `lib/` (json, http, preflight, composicao) verdes. Guarda `bash scripts/verificar-remocao-de-casos.sh`: 967 para 979 casos, nenhuma reducao.
- Testes de seguranca e acesso (Regra 6): sentinelas de app key, app secret, refresh e access token ausentes de stdout e stderr em texto, `--json`, `--json --null` e `--debug`, inclusive com corpo de erro que ecoa os segredos; caminho remoto hostil recusado com 13 antes de qualquer chamada; vinculo simbolico para fora da raiz nao seguido; `verificar` sem escrita (estado byte a byte identico, sem temporario); recusa por espaco sem nenhuma escrita; autocompletar sem `curl`, sem leitura de credencial ou estado, `install.sh` sem `sudo` e `.bashrc` intacto.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: projeto e CLI em shell, sem formulario.
- Suite completa local no push para a PR de `develop` (Regra 8), pelo comando oficial `sh scripts/suite-completa.sh` (`bash tests/run.sh`): **verde** em `5b94299`, 35 arquivos, 1054 aprovados, 0 reprovados, 2 pulados (vetor oficial sem rede), 206 s; `--conferir` com saida 0. O commit de documentacao que preenche este registro reexecuta a suite antes do proprio push.

## 5. Gates

Parecer combinado dos dois gates locais, executados pelo Senior Developer, nesta ordem. Pareceres completos: secoes 1 a 5 do material do Senior Developer.

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | T-1 (maior): `qa_cache_unico_p3_test.sh:947` fixava simulacao sem chamada, contra RF-67(f); T-2 (maior): duplo de `qa_robustez_rede_p2_test.sh` sem `get_space_usage`; ambos aceitos pelo QA e reaprovados pelo solicitante. T-3 (menor): `cpl06_...` com red por inspecao. | Aprovado com ressalvas |
| `protocolo-conformidade` | `clean-architecture` + `shellcheck-configuration`; `security-best-practices` pelo gatilho de credencial; Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | C-1 (maior): `commands/verificar.sh:29-48`, par area/tratador de RNF-31 gemeo do de `commands/sync.sh`; extrair para `lib/cmd`. C-2 (menor): `commands/diagnostico.sh` com 278 linhas, aceito. C-3 (menor): `bin/dbx` com ajuda maior, aceito. | Aprovado com ressalvas |

- Ciclo: 2. Status dos achados do QA no ciclo 1: D-1 corrigido (limite do vinculo aceito pelo Tech Lead); D-2 corrigido; O-4 corrigido; O-3 corrigido apos a decisao do Tech Lead (primeira tentativa revertida por bloquear o criterio do QA).
- Divergencias de dominio registradas pelo Senior Developer (regra 24), todas tratadas: o Tech Lead as aceitou e o Business Analyst alinhou os requisitos na v1.10 (RF-65(c), RF-65 limite TC-VER-10, RF-66, RF-67(i), RF-68(a), RF-15/RF-44). Eram: RF-68(a) lista `--raiz` no `config`, mas la e a raiz remota (sem completar caminho); DIV-35 sem confirmacao contra o servico real (sem rede, o campo `scope` da renovacao nao foi observado; a checagem e tolerante e emite aviso); `dependencias` sai com uma linha por utilitario ausente; motivo `tipo` com o mesmo limite "so arquivos" do `sync`; `espaco` achatado em `espaco_necessario`, `espaco_livre` e `espaco_verificado`; ajuda de `upload`, `download`, `list`, `delete` e `space` passou a documentar `--forcar` e as opcoes.
- `sh scripts/alteracoes-externas.sh --detectar`: exit 0 antes de editar, entre os passos e antes de cada gate, pelo developer, pelo QA e pelo Tech Lead.

## 6. QA

- Validacao independente do QA Expert, 21 casos, em [tests/integracao/qa_consulta_diagnostico_b1_test.sh](../../tests/integracao/qa_consulta_diagnostico_b1_test.sh), sha256 `9bf94d63b95a359ccf30c665e17c9783360d08b46e599257df2bc57e88df7ed8`. Massa, duplo de `curl` com lista branca de endpoints, sentinelas e retrato do estado sao proprios do QA. Distribuicao: RF-65, 7 casos; RF-66, 3; RF-67, 8; RF-68, 3.
- Revisao de testes aprovados em fases anteriores (regra 12):
  - `tests/integracao/qa_cache_unico_p3_test.sh`, sha256 `337adb847e88833c18144dd27383d0766d491ac5892462791edd039232e3c98c`: o QA aceitou com redacao propria (conjunto fechado de leituras, contagem exata) no ciclo 1 e a reajustou no ciclo 2 para o conjunto de `oauth2/token`, `files/get_metadata` e `get_space_usage`, 1 de cada, total 3, escrita 0.
  - `tests/integracao/qa_robustez_rede_p2_test.sh`, sha256 `5289027e4170c9cfc2566a04c7e9756aa67c2bb59331371e2dbd3c9808ac4a77`: aceito como esta, so completude do duplo; sem alteracao do QA.
- Ciclo 1: **Reprovado** (1 de 3). D-1 (maior, `bin/dbx:11-15`): `dirname` e `readlink` antes do despacho abortavam o `diagnostico` sem esses utilitarios, caso exato de RF-66(e). D-2 (maior, seguranca, `commands/diagnostico.sh:148-149` e `lib/output.sh:167`): a app key ecoada no `error_summary` de `check/user` saia em texto, `--json` e `--debug`. Observacoes O-1 (`raiz_remota` carregada e nunca aplicada, preexistente), O-2 (quebra de linha em caminho remoto aceita, preexistente), O-3 e O-4. Suite do ciclo 1: 29 arquivos, 857 aprovados, 2 pulados, parada no primeiro erro (Regra 9).
- Ciclo 2: **Aprovado**. D-1, D-2, O-3 e O-4 corrigidos e auditados caso a caso (17 utilitarios ausentes, um por vez, por `bin/dbx` direto e pelo vinculo do `install.sh`; segredos em cinco modos de saida; hash igual e diferente na simulacao).
- Mutantes: ciclo 1, M1 a M6 mortos e M7 (leitura extra em simulacao) sobrevivente a redacao do developer e morto pela do QA; ciclo 2, c2m6 (`files/upload` em simulacao), c2m7 (leitura extra `get_current_account`) e c2m8 (`get_metadata` duplicado), todos mortos.
- Execucao: ver a secao 4 (35 arquivos, 1054 aprovados, 0 reprovados, 2 pulados; guarda de remocao de 967 para 979 casos).
- Veredito do QA: **Aprovado**, 2026-10-19 (ciclo 2).

## 7. Riscos e rollback

- Riscos residuais:
  - C-1: tratamento da area temporaria do `verificar`, gemeo do `sync`, a extrair para `lib/cmd`. Owner Senior Developer, fase 2, junto do `lib/tmp`.
  - Limite do `verificar`: pasta local vazia contra arquivo remoto nao e detectada como `tipo` (TC-VER-10), mesmo limite "so arquivos" do `sync`. Sem prazo definido.
  - F-36 (`raiz_remota` carregada e nunca aplicada, O-1) e F-37 (quebra de linha em caminho remoto, O-2): preexistentes, a corrigir na fase extra 1b, logo apos esta fase e antes da trava (decisao do solicitante).
  - DIV-35: o campo `scope` da renovacao nao foi confirmado contra o servico real; sem o campo, a checagem de escopos e aviso.
  - D-1: sem `readlink` e sem `find`, o `dbx` chamado pelo vinculo recusa com codigo 3 (limite aceito pelo Tech Lead).
- Impacto: dois comandos novos (`verificar`/`verify`, `diagnostico`/`doctor`) e `completar`/`completion`; `sync` ganha `--forcar`/`--force` (so com `--enviar`); `upload` e `sync --enviar` passam a recusar envio que nao cabe no espaco livre, e `--forcar` pula a checagem; `lib/auth` expoe `scope` da renovacao; `install.sh` instala `completions/dbx.bash` e `uninstall.sh` o remove; `bin/dbx` resolve o proprio caminho so com o shell. Sem schema, sem migracao, sem dependencia nova (nenhum utilitario novo fora do preflight).
- Rollback: `git revert 5b94299` (e do commit de documentacao) basta. Nao ha migracao de dado.

## 8. Links e aceites

- Entradas de memoria: `2026-10-19-1050-consulta-e-diagnostico`, `2026-10-19-1050-aceite-testes-qa-b1`.
- Documentacao sincronizada: [escopo-requisitos-e-criterios-de-aceite.md](../requisitos/escopo-requisitos-e-criterios-de-aceite.md), [funcionalidades-candidatas.md](../requisitos/funcionalidades-candidatas.md), [system-design.md](../arquitetura/system-design.md), [mapa-modulos.md](../testes/mapa-modulos.md), [README.md](../../README.md).
- Commit(s): `5b94299` e o commit de documentacao que preenche este registro.
- PR: [#40](https://github.com/salesadriano/dropbox_sync/pull/40) para `develop`, labels `review` e `enhancement`.
- Tech Lead: **Aprovado com ressalvas — Tech Lead, 2026-10-19**, valida so com a suite completa local verde.
- Solicitante: aceite dos `qa-*` registrado em [2026-10-19-1050-aceite-testes-qa-b1](../../.github/agents/memoria/entradas/2026-10-19-1050-aceite-testes-qa-b1.md): `qa_consulta_diagnostico_b1_test.sh` (21 casos, sha256 `9bf94d63…7ed8`), reaprovacao de `qa_cache_unico_p3_test.sh` (`337adb84…c98c`) e de `qa_robustez_rede_p2_test.sh` (`5289027e…ac4a77`).
