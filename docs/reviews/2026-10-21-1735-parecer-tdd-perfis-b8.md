# Parecer de Evidencias de Testes (TDD) — Perfis nomeados de credencial, F-18 (fase 8)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: perfis nomeados de credencial (`--perfil`, `DBX_PERFIL`, `dbx perfis`, `unlink --perfil`, trava por raiz local), F-18; porte **G**
- Agent: Senior Developer (gate local, retomada); validacao independente a cargo do QA Expert
- Data: 2026-10-21
- Branch / base: `feature/perfis-b8` sobre `develop` @ `dd129fb`; implementacao no commit WIP `915cb52` (nao reescrito nesta retomada)
- Log de prompt: [2026-10-21_1735_backlog-fase-8-perfis.md](../prompts/2026-10-21_1735_backlog-fase-8-perfis.md)

## 1. Escopo do diff e mapa de modulos atingidos -> testes

| Modulo (arquivo) | Testes que o cobrem |
|---|---|
| `lib/config.sh` (validacao de nome, resolucao, 0600/cadeia, listagem) | `perfis_config` 36, `config_test` 77, `auth_test` 42 |
| `lib/cli.sh`, `bin/dbx` (`--perfil`, `DBX_PERFIL`) | `perfis_cli` 9, `perfis` 40, `cli` |
| `lib/state.sh` (trava por raiz local) | `state_trava_raiz` 9, `perfis_trava_raiz` 10, `state`, `trava` |
| `commands/perfis.sh` | `perfis` 40 |
| `commands/unlink.sh` (`--perfil`) | `perfis_unlink` 18 |
| `commands/config.sh`, `commands/diagnostico.sh`, `commands/sync.sh`, `lib/cmd.sh`, `lib/preflight.sh`, `completions/dbx.bash` | `perfis`, `perfis_unlink`, `diagnostico`, `preflight` |
| Regra 1 (todo diff em `lib/*.sh` e `commands/*.sh`) | `json`, `http`, `preflight`, `composicao`, `tmp_test`, `cli` |

Gatilhos da Regra 6 tocados: credencial/segredo (arquivos de perfil), permissao 0600, entrada de usuario que vira caminho de arquivo (nome de perfil), exclusao de credencial (`unlink --perfil`).

## 2. Vermelho contra a base `dd129fb`
Worktree descartavel em `dd129fb` (git worktree, removido ao fim) com SO os 6 arquivos de teste novos copiados. O harness aborta no primeiro caso reprovado (Regra 9), entao cada arquivo mostra 1 caso reprovado e os demais "nao executados" (nao contados como aprovados).

| Arquivo | Casos no arquivo | Resultado na base | Primeiro caso reprovado |
|---|---|---|---|
| `unit/perfis_cli_test.sh` | 9 | REPROVADO (1; 8 nao executados) | `pfn09_variavel_invalida_so_e_validada_quando_usada` |
| `unit/perfis_config_test.sh` | 36 | REPROVADO (1; 1 aprovado antes; 34 nao executados) | `pfc02_outro_nome_resolve_perfis_nome_json` |
| `unit/state_trava_raiz_test.sh` | 9 | REPROVADO (1; 8 nao executados) | `pft01_segunda_aquisicao_da_mesma_raiz_recusa_com_conflito` |
| `integracao/perfis_test.sh` | 40 | REPROVADO (1; 39 nao executados) | `pfa01_a_pfa03_ajuda_lista_perfis_a_opcao_e_a_variavel` |
| `integracao/perfis_trava_raiz_test.sh` | 10 | REPROVADO (1; 9 nao executados) | `pfe06_cursor_de_outra_identidade_...` (`opcao global desconhecida: --perfil`) |
| `integracao/perfis_unlink_test.sh` | 18 | REPROVADO (1; 17 nao executados) | `pfe01_leitores_expoem_cred_lendo_so_o_cabecalho` |

Resultado: 6 de 6 arquivos reprovam na base; 6 casos reprovados confirmados diretamente, 1 aprovado (guarda de regressao que ja vale na base), 115 casos nao executados por interrupcao. Limitacao: a contagem caso a caso so seria possivel sem a parada no primeiro erro, que o projeto exige; a prova e por arquivo.

## 3. Mutantes das guardas
Cada mutacao foi aplicada em producao, so o arquivo de teste indicado foi executado (`bash tests/run.sh <filtro>`), e a mutacao desfeita com `git checkout -- <arquivo>`; `git status` limpo em lib/ commands/ bin/ apos cada uma. Resultado: reprovou = morto.

| # | Guarda | Arquivo:linha | Mutacao | Teste que deveria matar | Resultado | Caso que reprovou |
|---|---|---|---|---|---|---|
| 1 | Validacao do nome antes de tocar disco | lib/config.sh:181 | `[[ $nome =~ RE ]] && return 0` vira `return 0` (aceita `..` e `/`) | tests/unit/perfis_config_test.sh | morto | 12 pfc_composicao_so_com_nome_validado |
| 2 | Perfil inexistente nunca recua para `padrao` | lib/config.sh:260 | `dbx_config_caminho` resolve sempre o `padrao` | tests/unit/perfis_config_test.sh; tests/integracao/perfis_test.sh | morto (2 de 2) | 2 pfc02_outro_nome_resolve_perfis_nome_json; 2 pfc03_perfil_ausente_sai_3_sem_rede_e_sem_recuo |
| 3 | Permissao 0600 do arquivo de perfil | lib/config.sh:525 | `chmod 600` vira `chmod 644` | tests/unit/perfis_config_test.sh; tests/unit/config_test.sh | morto (2 de 2) | 15 pfg01_gravar_cria_perfis_0700_e_arquivo_0600; 11 diretorio_acessivel_a_terceiros_e_recusado |
| 4 | `perfis/padrao.json` reservado (DIV-239) | lib/config.sh:358 | listagem deixa de excluir `padrao.json` | tests/unit/perfis_config_test.sh; tests/integracao/perfis_test.sh | morto (2 de 2) | 21 pfl08_entradas_anomalas_nao_viram_registro; 24 pfl08_entradas_anomalas_geram_um_aviso |
| 5a | `unlink --perfil` so remove `retomada-*` do proprio `cred-` (DIV-236) | commands/unlink.sh:229 | filtro `creds[indice] == cred` vira `:` | tests/integracao/perfis_unlink_test.sh | morto | 3 pfu01_pfe02_pfe04_unlink_de_um_perfil_so_toca_o_que_e_dele |
| 5b | Nao revoga com identidade compartilhada (DIV-237), decisao de revogar | commands/unlink.sh:425 | `-eq 0` vira `-ge 0` (revoga sempre) | tests/integracao/perfis_unlink_test.sh | morto | 10 pfu08_identidade_compartilhada_nao_revoga_e_mantem_o_estado |
| 5c | Idem, aviso "NAO sera revogado" | commands/unlink.sh:370 | `-gt 0` vira `-gt 99` (aviso some, decisao intacta) | tests/integracao/perfis_unlink_test.sh; tests/integracao/perfis_test.sh | SOBREVIVEU | nenhum |
| 6 | Trava por raiz local dev:inode recusa com 7 (DIV-250) | lib/state.sh:1116 | resumo da trava inclui `$RANDOM` (chave deixa de ser a raiz fisica) | tests/unit/state_trava_raiz_test.sh; tests/integracao/perfis_trava_raiz_test.sh | morto (2 de 2) | 1 pft01_segunda_aquisicao_da_mesma_raiz_recusa_com_conflito; 2 pft01_outro_perfil_sobre_a_mesma_raiz_sai_7_sem_escrever_e_sem_perfil_na_mensagem |
| 7a | `DBX_PERFIL` vazio = nao definida (DIV-240) | lib/config.sh:206 | remove o teste `-n ${DBX_PERFIL:-}` | tests/unit/perfis_config_test.sh (perfis_cli_test e integracao/perfis_test nao o cobrem) | morto (so por perfis_config_test) | 31 pfs_ambiente_vazio_equivale_a_nao_definida |
| 7b | Opcao `--perfil` repetida sai com 2 (DIV-241) | lib/cli.sh:281 | `DBX_CLI_PERFIL_DADO == 'sim'` vira `'nunca'` | tests/unit/perfis_cli_test.sh; tests/unit/cli_test.sh; tests/integracao/perfis_test.sh | morto (3 de 3) | 6 pfs07_repeticao_sai_2_mesmo_igual (x2); 37 pfs06_a_pfs08_uso_invalido_da_opcao |
| 8 | `dbx perfis` nao imprime segredo | commands/perfis.sh:51 | campo extra `refresh` com o conteudo do arquivo do perfil | tests/integracao/perfis_test.sh | morto | 22 pfl06_nenhum_segredo_nem_identidade_em_nenhum_modo |

Mutantes: 10 mortos de 11; sobreviventes: 5c (commands/unlink.sh:370). Achado Menor: o aviso "Este perfil tem a MESMA credencial ... NAO sera revogado" (stderr, antes da confirmacao) nao e afirmado por nenhum teste; a decisao de nao revogar (5b, linha 425) esta coberta. Producao nao foi alterada nesta tarefa. Observacao: o mutante 7a so morre em perfis_config_test; os testes de CLI e de integracao nao distinguem `DBX_PERFIL` vazia.

## 4. shellcheck e guarda de remocao

Antes (lint da fase, `sh scripts/lint.sh` nos arquivos shell de `git diff --name-only dd129fb 915cb52`): 208,94 s, exit 1; achados em lib/cli.sh (SC2178/SC2128), 3 testes (SC2034, SC2097/SC2098) e 1 (SC2086, info). bin/dbx estourava o teto de memoria (>14 GB, morto em duas rodadas) por causa das diretivas `source=lib/json.sh` e `source=lib/config.sh` em `_dbx_cli_carregar_config`.
Medicao previa (copia descartavel, Tech Lead): bin/dbx 4747908 KB / 29,53 s / 0 achados; lib/cli.sh 31520 KB / 0,20 s / 0 achados.
Depois (`sh scripts/lint.sh lib/cli.sh bin/dbx tests/unit/perfis_cli_test.sh tests/unit/perfis_config_test.sh tests/unit/state_trava_raiz_test.sh tests/integracao/perfis_test.sh tests/integracao/perfis_unlink_test.sh`): 38,27 s, exit 0, 0 achados.
Guarda de remocao (`bash scripts/verificar-remocao-de-casos.sh`): "2118 -> 2119 caso(s); nenhuma reducao nao declarada."
Testes afetados (contagens literais, `bash tests/run.sh <nome>`): perfis_cli_test 9/0 reprovados; perfis_config_test 36/0; state_trava_raiz_test 9/0; perfis_test 40/0; perfis_unlink_test 19/0 (18 + 1 novo); cli_test (2 arquivos) 26/0; pulados 0 em todos.

## 5. Achados

| # | Sev. | Local | Achado | Status |
|---|---|---|---|---|
| 1 | Maior | lib/cli.sh:267-271 | source redundante de json.sh/config.sh reanalisado pelo shellcheck (SC2178/SC2128 e lint de bin/dbx >14 GB) | corrigido: `source=/dev/null` com comentario; bin/dbx segue os arquivos diretamente |
| 2 | Menor | tests/unit/perfis_cli_test.sh:11, :102; tests/unit/perfis_config_test.sh:112 | SC2034: variaveis lidas so pelas libs carregadas por source | justificado: `disable=SC2034` individual com motivo (consumidas por lib/cli.sh e dbx_config_perfil_do_ambiente) |
| 3 | Menor | tests/unit/state_trava_raiz_test.sh:27, :36 | SC2097/SC2098: `AREA="$AREA"` e `"$AREA/xdg"` na mesma linha | corrigido; o teste NAO estava errado (AREA ja era global, valores identicos), era falso positivo de leitura; paths agora vindos de locais `xdg`/`tmp` |
| 4 | Menor | tests/integracao/perfis_test.sh:82 | SC2086 `${DBX_ENV_EXTRA:-}` | corrigido: `read -ra extra` e `"${extra[@]}"` |
| 5 | Menor | commands/unlink.sh:370 | mutante 5c sobrevivia: nenhum teste afirmava o aviso "MESMA credencial ... NAO sera revogado" no stderr | corrigido: caso `pfu08_aviso_de_credencial_compartilhada_sai_no_stderr_com_o_texto`; vermelho comprovado com `-gt 99` (reprova em "aviso nomeia a origem"), mutacao desfeita por `git checkout -- commands/unlink.sh` |
| 6 | Menor | tests/unit/perfis_config_test.sh caso 31 | observacao: o mutante 7a (`DBX_PERFIL` vazia) so morre neste caso; CLI e integracao nao o distinguem | aceito, sem acao |

Veredito do gate protocolo-tdd: **Aprovado** (sem bloqueante nem maior em aberto; execucao seletiva verde; suite completa nao executada, conforme Regra 8).

Ciclo 2 (CNF-03/QA-PF-01): red observado em `pfl_carregar_confere_a_cadeia_pelo_caminho_e_nao_pelo_rotulo` (rc=0 com `dbx/` 777 e rotulo `padrao`; a runner para no primeiro erro, entao `pfl_carregar_outro_perfil_revalida_o_nome_antes_do_disco` nao chegou a rodar antes da correcao). Green apos `lib/config.sh` (validacao do nome no ramo de 2 argumentos; cadeia decorre do caminho `perfis/`): perfis_config_test 38/0/0, perfis_unlink_test 19/0/0, perfis_test 40/0/0, config_test 79/0/0, auth_test 42/0/0 (aprovados/reprovados/pulados). qa_perfis_b8: 30 aprovados, 1 reprovado (qpf31, esperado; para no primeiro erro, qpf33 nao executado). Lint `scripts/lint.sh` 0; guarda de remocao de casos sem reducao (2118 -> 2121).
