# Validação do QA Expert — Cache único, skip do upload e segredo (fase 3)

## Identificação

- Demanda: fase 3 — cache único em `lib/state`, remoção do `lib/db`, skip do `upload` pelo `content_hash` remoto, identidade forte, `client_secret` obrigatório, P3.4
- Porte: **G** (validação independente sobre os itens afetados, com exaustão nos itens críticos)
- Responsável pela implementação: Senior Developer (pareceres [TDD](2026-10-18-2243-parecer-tdd-cache-unico.md) e [conformidade](2026-10-18-2243-parecer-conformidade-cache-unico.md), ciclos 1 e 2)
- Responsável pela validação: QA Expert (delegação do Tech Lead)
- Data da rodada: 2026-10-19
- Ciclo atual de revalidação do QA: **1**
- Branch / worktree: `feature/cache-unico-p3` em `/home/sales/dropbox_api.worktrees/feature-cache-unico-p3`, base `007f3ec`, diff só na árvore de trabalho
- Memória transposta (regra 43): `2026-10-18-2243-cache-unico-e-segredo`, `2026-10-18-2243-cache-do-upload` (DIV-26 a DIV-29, DIV-28 revista), `2026-10-18-1745-skip-upload-condicionado`, `2026-10-18-1745-selecao-inclui-auditorias-lib`
- Log de prompt: [2026-10-18_2243_cache-unico-p3.md](../prompts/2026-10-18_2243_cache-unico-p3.md)

## Precondições de entrada

| Item | Resultado |
|---|---|
| Parecer de evidências de testes (G, arquivo próprio) | Presente, **Aprovado** (ciclo 2) |
| Parecer de conformidade (G, arquivo próprio) | Presente, **Aprovado com ressalvas** (achado 2, menor, aberto com owner e prazo) |
| Parecer do DBA | Presente ([parecer](2026-10-18-2243-parecer-dba-cache-unico.md)) |
| `alteracoes-externas.sh --detectar` no início | exit `0` |
| Precondições documentais de frontend | Não aplicável (CLI sem interface) |

## Escopo validado

- Requisitos: RF-41 inteiro com RF-41(e) (TC-DEL-07), RF-60 (TC-SKP-01..09), RF-61 (TC-UPC), RF-62 (TC-CAN), RF-63 (TC-SCR), RNF-33 (TC-LEG), RF-38(e) (TC-MEM-04..06), RF-52 (TC-CONTA-02..04), RNF-02 (TC-DEP), RNF-25 (TC-EST-04), RNF-32(d), P3.4.
- Ambiente: WSL2, Linux 6.6, bash, uutils/coreutils do host, usuário não root (uid 1000); sem rede (duplo de `curl` no `PATH`, RNF-14).
- Massa: criada por cada caso (credencial sintética `ak`/`as`/`rt`, árvore local, duplo de rede, registros `upload-*` sintéticos para a poda). Nenhum dado manual; a primeira execução de cada caso é o semeador das seguintes; limpeza pela área do executor ao fim.
- Auditoria do diff: `git diff` de `lib/state.sh`, `lib/hash.sh`, `lib/walk.sh`, `lib/path.sh`, `lib/auth.sh`, `lib/errors.sh`, `lib/http.sh`, `commands/upload.sh`, `commands/sync.sh`, `bin/dbx`, `install.sh`, `README.md`, contra cada critério e contra os pareceres.

## Suíte independente (arquivos próprios)

| Arquivo | Casos | sha256 |
|---|---|---|
| `tests/integracao/qa_cache_unico_p3_test.sh` | 23 | `9cb78103c79cab57b5ab827c881a33234b02464c965a0e2d0f0d446b926db611` |
| `tests/unit/qa_state_p3_test.sh` | 8 | `abc531546531dec8209094ec3f0154af27fe4f27de83161c507dd1dbc496aa12` |

`shellcheck -x` dos dois arquivos: 0 achados. Mapa de módulos atualizado (Regra 2 e linhas de `lib/state.sh` e `lib/auth.sh`): filtros `qa_cache_unico` e `qa_state`.

### Casos e resultado (execução caso a caso, para diagnóstico)

| # | Caso | Critério | Resultado |
|---|---|---|---|
| 1 | `qa_exclusao_origem_vazia_sem_conta_nos_dois_sentidos_com_e_sem_confirmar` | RF-41(e), RF-48, TC-DEL-07 | ok |
| 2 | `qa_exclusao_origem_vazia_com_conta_e_memoria_recusa_sem_escrita_nos_dois_sentidos` | RF-41(b) | ok |
| 3 | `qa_exclusao_origem_ausente_ou_que_nao_e_diretorio_recusa_sem_escrita` | RF-41(b) (inexistente, arquivo, ligação pendente; com e sem conta) | ok |
| 4 | `qa_exclusao_ponto_de_montagem_ausente_nao_apaga` | RF-41(a)/(b)/(e) | ok |
| 5 | `qa_exclusao_travessia_parcial_e_conta_nao_identificada_acumulam_nos_dois_sentidos` | RF-41(a)+(e) | ok |
| 6 | `qa_exclusao_memoria_descartada_com_origem_vazia_nao_apaga` | RF-41(b) × RF-42 × memória v2 | **not ok** (QA-P3-01) |
| 7 | `qa_skip_falha_5xx_429_e_corpo_enganoso_no_metadado_envia` | RF-60(d) | ok |
| 8 | `qa_skip_remoto_pasta_ou_hash_malformado_nao_dispensa` | RF-60(e), (d) | ok |
| 9 | `qa_skip_cache_envenenado_nao_leva_a_dispensa_indevida` | RF-60(f), RF-42 | ok |
| 10 | `qa_skip_forcar_rev_e_entrada_padrao_ignoram_cache_valido` | RF-60(g), (h), (i) | ok |
| 11 | `qa_identidade_mtime_restaurado_por_touch_envia` | RF-61(b) | ok |
| 12 | `qa_identidade_troca_de_inode_por_mv_envia` | RF-61(b) | ok |
| 13 | `qa_identidade_hardlink_alterado_pelo_outro_nome_envia_e_tem_registro_proprio` | RF-61(b), RF-62(a) | ok |
| 14 | `qa_identidade_arquivo_alterado_entre_o_stat_e_o_resumo_nao_grava` | RF-61(c) | ok |
| 15 | `qa_identidade_janela_de_dois_segundos_no_upload` | RF-61(d) | ok |
| 16 | `qa_identidade_sync_envia_arquivo_com_mtime_restaurado` | RF-38(e) | ok |
| 17 | `qa_estado_0755_corrigido_por_upload_e_sync_com_legado_intacto` | RNF-25(b1), RNF-33(b), RNF-02(c), RNF-26 | ok |
| 18 | `qa_estado_diretorio_alheio_gravavel_nao_recebe_nada` | RNF-25(b1) (`/tmp`, 1777, de root) | ok |
| 19 | `qa_poda_acerto_de_registro_velho_sobrevive_e_so_os_velhos_saem` | RF-61(i) (10.002, 89 e 91 dias, acerto renova) | ok |
| 20 | `qa_poda_no_teto_exato_nao_remove_nem_os_velhos` | RF-61(i) (10.000) | ok |
| 21 | `qa_legado_install_readme_e_codigo_sem_sqlite_nem_python` | RNF-33(a), (c), (d), RNF-02(a) | **not ok** (QA-P3-04) |
| 22 | `qa_segredo_ausente_recusa_antes_da_rede_com_o_codigo_de_rf03` | RF-63(a) ponta a ponta | **not ok** (QA-P3-02) |
| 23 | `qa_p34_falha_de_rede_nao_vira_sucesso_no_upload_nem_no_sync` | P3.4 / RF-29 | **not ok** (QA-P3-03) |
| 24 | `qa_state_caminho_com_tab_e_quebra_de_linha_volta_intacto` | RF-42, estado hostil | ok |
| 25 | `qa_state_nul_no_meio_do_registro_nao_cria_entrada_espuria` | RF-42 | ok |
| 26 | `qa_state_registro_de_outro_namespace_e_rejeitado` | RF-61(a), RF-42 | ok |
| 27 | `qa_state_registro_como_ligacao_simbolica_nao_e_escrito_atraves` | RNF-25 | ok |
| 28 | `qa_state_diretorio_alheio_gravavel_devolve_permissao` | RNF-25(b1) | ok |
| 29 | `qa_state_anti_corrida_na_fronteira_de_dois_segundos` | RF-61(d) (2 s, 1 s, futuro, tamanho 0, 5 campos) | ok |
| 30 | `qa_auth_sem_segredo_recusa_antes_da_rede_na_classe_de_rf03` | RF-63(a) na biblioteca | **not ok** (QA-P3-02) |
| 31 | `qa_p34_classe_politica_e_codigo_iguais_a_referencia` | P3.4 | ok |

Total: 31 casos — 26 ok, 5 not ok (4 achados).

## Mutantes manuais (cópias em `scratchpad/qa-mut-p3/`, nunca no worktree)

| Id | Arquivo | Mutação | Casos que reprovaram | Estado |
|---|---|---|---|---|
| MQ1 | `commands/sync.sh` | `--confirmar` reabilita a exclusão sem conta (guarda RF-41(e)) | 1, 5 | morto |
| MQ2 | `commands/sync.sh` | exclusão sem conta desabilitada só no sentido `enviar` (guarda RF-41(e)) | 5 | morto |
| MQ3 | `commands/sync.sh` | guarda RF-41(b) ignora origem remota vazia (`receber`) | 2 | morto |
| MQ4 | `commands/upload.sh` | sem `[[ $tipo == 'file' ]]`: pasta com hash compara | 8 | morto |
| MQ5 | `commands/upload.sh` | falha do `get_metadata` ignorada (`|| :`): corpo do erro decide | 7 | morto |
| MQ6 | `lib/hash.sh` | identidade sem `ctime` (`%z` → `%y`) | 11, 16 | morto |
| MQ7 | `lib/state.sh` | anti-corrida `-ge 0` no lugar de 2 s | 29, 15 | morto |
| MQ8 | `lib/state.sh` | poda `-mtime +88` | 19 | morto |

8 de 8 mortos; 3 na guarda de exclusão. P3.4, adicionalmente, por diferencial: 830 combinações (código HTTP × resumo × idempotência, mais o código de saída por classe) de `dbx_errors_classificar`, `dbx_errors_politica_retentativa` e `dbx_errors_codigo_saida`, executadas contra o `HEAD` exportado por `git archive` e contra o worktree: **idênticas** (`diff` vazio).

## Execução seletiva (Regra 8) — `lib/errors.sh` no diff: tudo

| # | Comando | Resultado literal |
|---|---|---|
| 1 | `bash tests/run.sh < /dev/null` (1ª) | interrompida no 11º arquivo: `json` 41 ok, 1 not ok (`massa_adversarial_nao_e_construida_por_substituicao_de_comando`, em `qa_cache_unico_p3_test.sh:443`, arquivo do QA). Corrigido (`printf -v`/arquivo) e reexecutado do início |
| 2 | `bash tests/run.sh < /dev/null` (2ª) | 17 arquivos executados, exit `1`: `auth` 39, `cabecalho` 17, `cli` 17, `cmd` 8, `config` 40, `errors` 80, `harness` 22, `hash` 44, `hash_vetor_oficial` 0 (2 pulados, exige rede), `http` 53, `json` 60, `output` 30, `path` 47, `preflight` 30, `progress` 16, `qa_rede_p2` 25 — todos 0 falhas; **Bail out** em `qa_state_p3`: 0 ok, 1 not ok (`qa_auth_sem_segredo…`), 7 não executados |
| 3 | `bash tests/run.sh state_test` | 23 ok, 0 falhas |
| 4 | `bash tests/run.sh transfer` | 36 ok |
| 5 | `bash tests/run.sh walk` | 13 ok |
| 6 | `bash tests/run.sh comandos` | 111 ok |
| 7 | `bash tests/run.sh composicao` | 24 ok |
| 8 | `bash tests/run.sh qa_integridade` | 27 ok |
| 9 | `bash tests/run.sh qa_robustez` | 20 ok |
| 10 | `bash tests/run.sh sync_test` | 59 ok |
| 11 | `bash tests/run.sh qa_cache_unico` | exit `1`: 2 ok, **Bail out** em `qa_exclusao_memoria_descartada…`, 20 não executados |

Suíte do desenvolvimento e das fases anteriores: **841 aprovados, 2 pulados, 0 falhas**, em 24 arquivos (itens 2 a 10). Os comandos 3 a 10 completam os arquivos que a parada da execução 2 não alcançou; a parada no primeiro erro foi respeitada em cada um. A execução caso a caso das suítes do QA (tabela acima) foi feita fora do executor oficial, só para diagnosticar todos os achados de uma vez.

## Resultado da validação

- Status: **Reprovado** (ciclo 1 do QA)
- Resumo executivo: os três pontos de risco centrais resistiram à exaustão — sem conta, nenhuma combinação de sentido, `--confirmar`, origem vazia, ausente, não diretório, ponto de montagem ou travessia parcial produziu exclusão; o skip nunca dispensa com remoto diferente, ausente, pasta, malformado ou com consulta falha, nem com cache envenenado com hash diferente do remoto; a identidade detecta `touch -d`, troca de inode, ligação física e alteração entre `stat` e resumo, e a janela de 2 s vale na fronteira. A reprovação vem de quatro achados: um bloqueante de segurança na exclusão (memória descartada), dois maiores de código de saída (RF-63 e enumeração remota) e um menor de documentação.
- Risco para o negócio: QA-P3-01 permite, na **primeira execução após a atualização**, que uma rotina `sync --espelhar` sobre origem vazia (montagem que não subiu) apague o destino inteiro sem `--confirmar`. QA-P3-03 faz uma rotina agendada terminar com `0` sem ter sincronizado nada.
- Impacto técnico: correções localizadas em `commands/sync.sh`, `lib/state.sh`/`commands/sync.sh` (decisão de requisito pendente em QA-P3-01), `lib/auth.sh`, `commands/upload.sh` e `README.md`; dois casos do desenvolvimento assumem o código errado em RF-63.

## Falhas documentadas

| ID | Cenário | Resultado esperado | Resultado obtido | Severidade | Evidência |
|---|---|---|---|---|---|
| QA-P3-01 | Par já sincronizado; `memoria-*` da versão anterior (v1) — ou truncada — e origem vazia; rotina `sync --enviar --espelhar` **sem** `--confirmar` | Zero exclusões, saída ≠ 0 (a linha de base não existe, como em RF-41(e)) | 1 exclusão (`files/delete_v2`): a memória é descartada na carga (`lib/state.sh:277`), mas `VISTO=sim` dispensa o reconhecimento (RF-48) e a guarda `commands/sync.sh:430` conta zero entradas | **Bloqueante (segurança)** | Caso 6; variante `truncada` também reprova no `HEAD` (pré-existente), a variante `versao_anterior` passa no `HEAD` e reprova no diff: a troca `DBX_STATE_VERSAO=2` (`lib/state.sh:83`) torna a janela **sistemática** para toda instalação existente |
| QA-P3-02 | Credencial com `"app_secret":""` (carregada); `upload` e `sync`; e a biblioteca (`dbx_auth_renovar`, `dbx_auth_trocar_codigo`) sem segredo | Recusa antes da rede, classe e código de RF-03 (`configuracao`, 3), motivo nomeando o segredo (RF-63(a)) | Biblioteca devolve `uso_invalido` (2) (`lib/auth.sh:196`, `:379`); ponta a ponta o `upload` sai com **10** e `envio recusado: sem detalhe` (o motivo se perde: a consulta falha em silêncio e a recusa do envio vira `erro_remoto`); o `sync` sai com **0** (QA-P3-03). Os casos `auth_test` `renovacao_sem_segredo…` e `troca_de_codigo_sem_segredo…` afirmam o código 2 chamando-o "como RF-03" | Maior | Casos 22 e 30; campo **ausente** já sai com 3 e zero chamadas (lido por `lib/config.sh:345-348`), mas `lib/config.sh:369-371` ainda declara o segredo opcional |
| QA-P3-03 | `sync` cuja enumeração remota falha (5xx esgotado; ou renovação recusada por RF-63) | Saída com o código da classe (`erro_remoto` 10, ou o da recusa) | **0**: `commands/sync.sh:405-406` lê `$?` dentro do `then` de `if ! …`, que vale 0 | Maior (pré-existente; reproduzido no `HEAD` 007f3ec; agora alcançável também por RF-63) | Caso 23 |
| QA-P3-04 | README após RNF-33(c) | Sem anúncio do cache SQLite fora do parágrafo do legado | `README.md:136` ainda descreve "status de cache SQLite/memória" no `--progresso` | Menor | Caso 21 |

### Observações sem reprovação (risco residual, para o Tech Lead)

| # | Observação | Severidade |
|---|---|---|
| O-1 | No sentido `receber`, a guarda de `commands/sync.sh:430` conta também as entradas registradas na própria execução (arquivos locais percorridos): com remoto vazio e local povoado ela recusa até na primeira execução e sem conta, com a mensagem "a memória registra caminhos de execução anterior", que não é o motivo real. Lado seguro; pré-existente; mensagem enganosa | Info |
| O-2 | A poda usa `find -mtime +90`, que só remove com idade de **91 dias inteiros** ou mais; um registro com 90 dias e 12 h não é podado. Compatível com os exemplos de RF-61(i) (89 e 91) | Info |
| O-3 | A anti-corrida compara só o `mtime`; logo após um `touch -d`, o `ctime` é recente e não entra na janela. Explorável apenas com reescrita e restauração dentro do mesmo tique do relógio de carimbos | Info |
| O-4 | Cache envenenado com hash **igual ao remoto** e identidade igual leva à dispensa: é o modelo de confiança do cache (diretório 0700 do próprio usuário, RNF-25(b1), provado nos casos 18, 27 e 28). Hash falso diferente do remoto nunca dispensa (caso 9) | Info |
| O-5 | Ressalva do parecer de conformidade (achado 2, leitura silenciosa de JSON em `commands/upload.sh`) segue aberta; ela é também a razão de o motivo de QA-P3-02 se perder no `upload` | Info |

## Devolução ao agent

| ID | Arquivo:linha | Achado | Regra violada | Correção esperada | Severidade |
|---|---|---|---|---|---|
| QA-P3-01 | `lib/state.sh:83`, `:272-289`; `commands/sync.sh:318-330`, `:430` | Memória existente mas descartada (versão anterior, truncada, corrompida, de outra conta no cabeçalho) mantém `VISTO=sim` e zera a linha de base: a rotina sem `--confirmar` apaga o destino de origem vazia | RF-41 (P0, bloqueante), RF-41(e) por analogia, RF-48; regra 14 (achado de segurança não se encerra por justificativa) | **Decisão do Tech Lead antes da correção** (lacuna de requisito, como a DIV-28): p. ex., memória presente e descartada desabilita a exclusão naquela execução, com a semântica de RF-41(a)/(e) e saída ≠ 0, ou a carga da v1 preserva os caminhos para a guarda. O caso 6 aceita qualquer das duas (afirma só zero exclusões e saída ≠ 0) | Bloqueante |
| QA-P3-02 | `lib/auth.sh:196`, `:379`; `commands/upload.sh` (`_dbx_cmd_upload_hash_remoto` e falha do envio); `lib/config.sh:369-371`; `tests/unit/auth_test.sh` (`renovacao_sem_segredo…`, `troca_de_codigo_sem_segredo…`) | Recusa sem segredo sai como `uso_invalido` (2) e, no `upload`, como `erro_remoto` (10) sem motivo | RF-63(a) ("mesma classe e código de saída de RF-03"), RF-03 | Recusa na classe `configuracao` (3) na biblioteca; `upload` e `sync` propagam classe e motivo da recusa de autenticação; ajustar os dois casos do `auth_test` e o comentário de `lib/config.sh` | Maior |
| QA-P3-03 | `commands/sync.sh:405-406` | `local estado_remoto=$?` dentro de `if ! …; then` captura 0: falha da enumeração remota termina o `sync` com sucesso | RF-29 (código da classe), RNF de operação agendada | Capturar o status antes da negação (`dbx_sync_enumerar_remoto …; estado_remoto=$?; if [[ $estado_remoto -ne 0 ]]`) e devolver o código da classe; pré-existente — o Tech Lead decide se entra nesta demanda (arquivo já está no diff e o caminho ficou alcançável por RF-63) | Maior |
| QA-P3-04 | `README.md:136` | Texto do `--progresso` ainda cita "cache SQLite" | RNF-33(c) | Trocar por "cache em memória (`lib/state`)" | Menor |

## Histórico de ciclos QA → Developer

| Ciclo | Data | Status | Resumo da devolução | Responsável |
|---|---|---|---|---|
| 1 | 2026-10-19 | Reprovado | QA-P3-01 (bloqueante, segurança, depende de decisão do Tech Lead), QA-P3-02 e QA-P3-03 (maiores), QA-P3-04 (menor) | QA Expert → Tech Lead → Senior Developer |

## Critério de escalonamento

- Reprovações acumuladas no QA: 1
- Ultrapassou 3 ciclos? Não
- Encaminhar ao solicitante? Não por ciclos; QA-P3-01 pede decisão de requisito do Tech Lead (e, se ele julgar, do solicitante), como a DIV-28.

## Divergências (regra 24)

- RF-41(b) e RF-42 não tratam "memória presente e descartada": a razão escrita em RF-41(e) ("sem identidade de conta não há linha de base, e a guarda de (b) não protege") vale igualmente para ela. Recomendação: o Business Analyst emenda RF-41 com a alínea correspondente na mesma rodada da decisão.
- `lib/config.sh:369-371` contradiz RF-63 (segredo "opcional").
- Os pareceres do desenvolvimento afirmam RF-63(a) "como RF-03" com o código 2; RF-03 fixa 3.

## Aprovação do solicitante (regra 12)

Pendente. Conjunto submetido: os dois arquivos acima (31 casos), com os sha256 registrados. Na reaprovação após as correções, os casos 6, 21, 22, 23 e 30 devem passar sem alteração de asserção; se a decisão de QA-P3-01 mudar o comportamento esperado, o caso 6 é revisto e submetido de novo.

## Próximos passos

1. Tech Lead decide QA-P3-01 (e se QA-P3-03 entra nesta demanda) e grava a decisão na memória e nos requisitos.
2. Senior Developer corrige, reexecuta os dois gates e devolve ao QA (ciclo 2).
3. QA reexecuta tudo (`lib/errors.sh` no diff) com os arquivos `qa_*` sem alteração.

## Ciclo 2 do QA (2026-10-19) — revalidação sobre o ciclo 3 do developer

### Status dos achados do ciclo 1

| ID | Status | Evidência |
|---|---|---|
| QA-P3-01 | **Corrigido** para o caso pedido (`DBX_STATE_DESCARTADA`, RF-41(f), TC-DEL-08) | Casos 6 (agora também com `--confirmar`) e `qa_exclusao_memoria_descartada_duas_execucoes_a_segunda_propaga` (variantes v1, outra conta, só NUL): a primeira não apaga, sai ≠ 0, regrava em v2; a segunda apaga o órfão e sai 0. Mutantes MC1 e MC2 mortos. **Mas veja QA-P3-05 a QA-P3-07** |
| QA-P3-02 | **Corrigido** | Casos 22 e 30 verdes; `qa_segredo_preparo_nao_vaza_e_nao_incide_onde_nao_ha_rede`: nenhum valor de credencial no diagnóstico, simulação de `upload` sem chamada alguma, uma única renovação no `upload` real. Mutantes MC3 (sem o preparo no `upload`) e MC4 (biblioteca volta a 2) mortos |
| QA-P3-03 | **Corrigido** | Caso 23 verde; mutante MC5 (`return 0`) morto. `grep` de `if ! …; then … $?` e `elif !`/`until` em `bin/`, `lib/` e `commands/`: nenhum outro ponto lê o `$?` da negação (as ocorrências em `lib/auth.sh:441`, `lib/config.sh:228,340,346` e `commands/sync.sh:382` leem o status de outra função, chamada antes do `return $?`) |
| QA-P3-04 | **Corrigido** | Caso 21 verde; mutante MC6 morto |

### Pontos de risco pedidos pelo Tech Lead

1. **Ramos de descarte.** Versão anterior, truncada, cabeçalho de outra conta e só NUL marcam descartada; a carga válida limpa a marca. Memória **ausente** não marca: RF-48 inalterado (`qa_exclusao_memoria_ausente_nao_conta_como_descartada`). Porém **arquivo ilegível não marca** (QA-P3-07): ao contrário do declarado, ele sai em `lib/state.sh:248` antes de `VISTO=sim` e de `DESCARTADA=sim`, ou seja, conta como ausente.
2. **Regravação só após travessia completa: não se cumpre** (QA-P3-06). `commands/sync.sh:624` grava com `completa=nao` também quando a memória foi descartada, o que deixa uma v2 sem os caminhos não visitados.
3. **Duas execuções seguidas:** a segunda propaga e sai com 0 quando a origem tem conteúdo (verde). Quando a origem **continua vazia**, a primeira regrava uma v2 sem caminho algum e a segunda apaga o destino (QA-P3-05).
4. **`dbx_auth_preparar`:** sem vazamento; só é chamado em `upload` (depois do portão de simulação) e `sync`, que precisam do token de qualquer forma.
5. **Padrão `if ! …; then …$?`:** nenhuma outra ocorrência.

### Novos achados

| ID | Arquivo:linha | Cenário | Esperado | Obtido | Regra | Correção sugerida | Severidade |
|---|---|---|---|---|---|---|---|
| QA-P3-05 | `commands/sync.sh:620-630` com `lib/state.sh` (regravação após descarte) | Memória v1, origem vazia (montagem caiu), rotina `--espelhar` a cada hora | Zero exclusões enquanto a origem estiver vazia | 1ª execução: zero exclusões e ≠ 0, mas regrava a v2 **sem caminhos**; 2ª execução: `VISTO=sim`, base vazia, guarda de RF-41(b) inerte, **apaga o destino** e sai 0 | RF-41 (P0), RF-41(b)/(f) | Decisão do Tech Lead: não regravar, ou manter a marca de descarte, enquanto a travessia não registrar caminho algum; ou preservar na regravação os caminhos legíveis da v1 para a guarda | **Bloqueante (segurança)** |
| QA-P3-06 | `commands/sync.sh:622-625` | Memória descartada e travessia parcial (só um ramo ilegível); na execução seguinte a origem fica vazia | Sem regravação, porque a travessia não foi completa (RF-41(f)); e zero exclusões na seguinte | Regrava uma v2 só com o que foi visitado (nada); a seguinte apaga | RF-41(f) | Não chamar `dbx_state_gravar` quando `memoria_descartada=sim` e `parcial=sim` | **Bloqueante (segurança)** |
| QA-P3-07 | `lib/state.sh:248` | Memória do par existe mas está ilegível (modo 0000); origem vazia; rotina `--espelhar --confirmar` | Tratada como descartada: zero exclusões, saída ≠ 0 | Tratada como ausente: `VISTO=nao`, e `--confirmar` libera; **2 exclusões** | RF-41(f) (memória existente descartada), regra 24 (o ciclo 3 declara "arquivo ilegível" coberto) | Arquivo existente do usuário e não legível: `VISTO=sim` e `DESCARTADA=sim`; manter a recusa para arquivo alheio | Maior (segurança; exige `--confirmar`) |

Casos: `qa_exclusao_memoria_descartada_com_origem_vazia_segunda_execucao_nao_apaga` (QA-P3-05), `qa_exclusao_memoria_descartada_com_travessia_parcial_nao_regrava_base_vazia` (QA-P3-06), `qa_exclusao_memoria_ilegivel_com_confirmar_nao_apaga` (QA-P3-07). Os três asseguram só "zero exclusões e saída ≠ 0", de modo que aceitam qualquer correção que atenda à regra.

### Mutantes do ciclo 2 (cópias em `scratchpad/qa-mut-p3/`)

| Id | Correção | Mutação | Casos que reprovaram | Estado |
|---|---|---|---|---|
| MC1 | QA-P3-01 | a carga não marca descartada | 6, duas_execucoes | morto |
| MC2 | QA-P3-01 | `--confirmar` reabilita com memória descartada | 6, segunda_execucao | morto |
| MC3 | QA-P3-02 | `upload` sem `dbx_auth_preparar` | 22 | morto |
| MC4 | QA-P3-02 | biblioteca volta a `uso_invalido` | 30 | morto |
| MC5 | QA-P3-03 | `return 0` após enumeração falha | 23 | morto |
| MC6 | QA-P3-04 | README volta a citar "cache SQLite" | 21 | morto |

### Execução (`lib/errors.sh` no diff: tudo, parando no primeiro erro)

| Comando | Resultado literal |
|---|---|
| `bash tests/run.sh < /dev/null` | exit `1`, 23 arquivos executados: `auth` 39, `cabecalho` 17, `cli` 17, `cmd` 8, `config` 40, `errors` 80, `harness` 22, `hash` 44, `hash_vetor_oficial` 0 (2 pulados), `http` 53, `json` 60, `output` 30, `path` 47, `preflight` 30, `progress` 16, `qa_rede_p2` 25, `qa_state_p3` 8, `state` 23, `transfer` 36, `walk` 13, `comandos` 112, `composicao` 24 (todos com 0 falhas); **Bail out** em `qa_cache_unico_p3`: 4 ok, 1 not ok (`…segunda_execucao_nao_apaga`), 24 não executados |
| `bash tests/run.sh qa_integridade` | 27 ok |
| `bash tests/run.sh qa_robustez` | 20 ok |
| `bash tests/run.sh sync_test` | 62 ok |

Suíte do desenvolvimento e das fases anteriores: **845 aprovados, 2 pulados, 0 falhas**. Suíte do QA, caso a caso: `qa_cache_unico_p3` com 29 casos (26 ok, 3 not ok); `qa_state_p3` com 8 casos (8 ok). `shellcheck -x` nos dois arquivos: 0 achados.

| Arquivo | Casos | sha256 |
|---|---|---|
| `tests/integracao/qa_cache_unico_p3_test.sh` | 29 | `1b49727736c51f76cc238b6b03c764297524750f26b4e44c45d2ef7d3c23cb3c` |
| `tests/unit/qa_state_p3_test.sh` | 8 | `abc531546531dec8209094ec3f0154af27fe4f27de83161c507dd1dbc496aa12` |

Casos acrescentados no ciclo 2: `qa_exclusao_memoria_descartada_duas_execucoes_a_segunda_propaga`, `qa_exclusao_memoria_ausente_nao_conta_como_descartada`, `qa_exclusao_memoria_ilegivel_com_confirmar_nao_apaga`, `qa_exclusao_memoria_descartada_com_travessia_parcial_nao_regrava_base_vazia`, `qa_exclusao_memoria_descartada_com_origem_vazia_segunda_execucao_nao_apaga`, `qa_segredo_preparo_nao_vaza_e_nao_incide_onde_nao_ha_rede`. O caso 6 passou a cobrir também `--confirmar`.

### Veredito do ciclo 2

- Status: **Reprovado** (ciclo 2 do QA; 2 reprovações acumuladas, abaixo do limite de 3).
- Os quatro achados do ciclo 1 foram corrigidos, mas a correção de QA-P3-01 tem três brechas na mesma classe de risco. Duas são bloqueantes: a exclusão em massa só é **adiada em uma execução** quando a origem continua vazia (QA-P3-05) e a base é regravada após travessia parcial (QA-P3-06). A terceira é maior: a memória ilegível conta como ausente (QA-P3-07).
- QA-P3-05 e QA-P3-07 pedem decisão do Tech Lead sobre o requisito antes da correção, por emenda de RF-41(f). QA-P3-06 é descumprimento direto do texto de RF-41(f).

| Ciclo | Data | Status | Resumo | Responsável |
|---|---|---|---|---|
| 2 | 2026-10-19 | Reprovado | QA-P3-01..04 corrigidos; novos QA-P3-05 e QA-P3-06 (bloqueantes) e QA-P3-07 (maior) | QA Expert → Tech Lead → Senior Developer |

Aprovação do solicitante (regra 12): pendente. Ela vale para o conjunto acima, com os sha256 do ciclo 2.

## Ciclo 3 do QA (2026-10-19) — revalidação final sobre o ciclo 4 do developer

Contexto: o solicitante decidiu a guarda de origem vazia **sem memória** (memória `2026-10-18-2243-guarda-origem-vazia`; RF-41(b) reescrito, RF-53(e), TC-DEL-09..12). RF-41(e) e RF-41(f) passam a defesa em profundidade.

### Status dos achados do ciclo 2

| ID | Status | Evidência |
|---|---|---|
| QA-P3-05 | **Corrigido** pela guarda nova | `…segunda_execucao_nao_apaga` verde: a segunda execução com a origem vazia é recusada |
| QA-P3-06 | **Corrigido** (`commands/sync.sh:671`: nenhuma gravação com travessia parcial) | `…travessia_parcial_nao_regrava_base_vazia` **alterado** neste ciclo: a origem ganhou um arquivo legível, para que a guarda de origem vazia não mascare a regravação, e agora afirma que a memória continua v1 após a execução parcial. Mata o MG3 (equivalente ao M31) |
| QA-P3-07 | **Corrigido** (`lib/state.sh:254-260`) | `…memoria_ilegivel_com_confirmar_nao_apaga` **alterado**: primeiro passo com a origem **povoada** e um órfão (só o RF-41(f) protege, e sai `memoria descartada`). Mata o MG4b (equivalente ao M32) |

### Pontos pedidos

1. **Sem atalho na guarda (decisão do QA, com base no RF-41(b): "raiz local sem nenhum arquivo").** Origem só com diretórios vazios, só com temporários de recebimento (`.x.txt.dbx-part.XXXXXX`, filtrados por `dbx_sync_sem_temporarios`) ou só com uma ligação simbólica (não percorrida; vira travessia parcial) **conta como vazia** e é recusada com 14, `recusada=origem vazia` e nenhuma escrita (nem o diretório de estado é criado). No `--receber`, listagem remota vazia ou só com pastas conta como vazia e é recusada com o destino local intacto. Raiz remota **inexistente** (409 `path/not_found`) não é "vazia": a enumeração falha e sai ≠ 0 sem apagar nada, mesmo com `--permitir-origem-vazia`.
2. **`--permitir-origem-vazia`:** sem `--espelhar` não tem efeito (sai 0, nada apagado), o que é coerente com o RF-53(e) ("só tem efeito com `--espelhar`"). `--dry-run` sem a opção anuncia `recusaria=origem vazia`, não lista `apagar=` e sai 0; com a opção, lista as exclusões e sai 0, sem escrita. Com conta não identificada, o RF-41(e) continua desabilitando a exclusão. Com `--confirmar` na primeira execução, as 2 exclusões ocorrem e o comando sai 0.
3. **Nenhuma escrita antes da recusa:** nem remota nem local; nem o diretório de estado (variantes de vazio). Com memória existente, conteúdo e `mtime` ficam intactos (caso 2 **alterado**).
4. **Caso alterado do developer** (`sem_conta_origem_vazia_com_confirmar_nao_apaga_nada`): continua afirmando zero exclusões e saída ≠ 0, mas **já não protege o RF-41(e)**, porque quem recusa agora é a guarda (b): o mutante MG5, que remove o RF-41(e), sobrevive a ele. O RF-41(e) segue protegido por `sem_conta_origem_povoada_transfere_e_nao_apaga` (developer) e por `qa_exclusao_travessia_parcial_e_conta_nao_identificada_acumulam_nos_dois_sentidos` (QA), que matam o MG5. Observação O-6 (Info): o nome do caso já não descreve o que ele prova.
5. **M30 a M32:** casos do QA que matam agora os equivalentes:
   - MG1 (guarda sem memória anulada): matam os casos de variantes de vazio e de combinações.
   - MG3 (parcial volta a gravar): mata o caso de parcial alterado.
   - MG4b (ilegível volta a contar como ausente): mata o caso de ilegível alterado.

   O MG4 (`if false` no ramo do ilegível) é **equivalente**: o arquivo ilegível cai no ramo de "truncada", que também o marca como descartado.

### Observações sem reprovação

| # | Observação | Severidade |
|---|---|---|
| O-1 (mantida) | No `--receber`, a guarda antiga, dependente da memória e alimentada pelos arquivos locais da própria execução, recusa **antes** do plano. A recusa fica certa (14, sem escrita, mensagem que cita `--permitir-origem-vazia`), mas o plano não traz `recusada=origem vazia` e a mensagem fala em "memória de execução anterior" | Info |
| O-6 | Ver o ponto 4 | Info |
| O-7 | Com travessia parcial, nada é gravado, nem as entradas novas. O RF-38(b) previa "mapa carregado mais os novos". A diferença custa só recálculo e segue o texto do RF-41(f) | Info |

### Mutantes do ciclo 3

| Id | Mutação | Casos que reprovaram | Estado |
|---|---|---|---|
| MG1 | Guarda sem memória anulada (`-gt 999999`) | variantes de vazio; combinações de `--permitir-origem-vazia` | morto |
| MG2 | `--confirmar` dispensa a guarda | variantes de vazio | morto |
| MG3 | Travessia parcial volta a gravar | parcial (alterado) | morto |
| MG4b | Ilegível volta a contar como ausente | ilegível (alterado) | morto |
| MG4 | `if false` no ramo do ilegível | — | equivalente (truncada) |
| MG5 | RF-41(e) removido | `sem_conta_origem_povoada…` (developer), `qa_…travessia_parcial_e_conta…` | morto (o caso alterado do developer sobrevive; ponto 4) |

### Execução

| Comando | Resultado literal |
|---|---|
| `bash tests/run.sh < /dev/null` | exit `0`, 26 arquivos: `auth` 39, `cabecalho` 17, `cli` 17, `cmd` 8, `config` 40, `errors` 80, `harness` 22, `hash` 44, `hash_vetor_oficial` 0 (2 pulados), `http` 53, `json` 60, `output` 30, `path` 47, `preflight` 30, `progress` 16, `qa_rede_p2` 25, `qa_state_p3` 8, `state` 24, `transfer` 36, `walk` 13, `comandos` 112, `composicao` 24, `qa_cache_unico_p3` 33, `qa_integridade_p1` 27, `qa_robustez_rede_p2` 20, `sync` 69 — **894 aprovados, 2 pulados, 0 falhas** |

`shellcheck -x` nos dois arquivos: 0 achados. `--registrar` e `--detectar`: exit 0.

### Suíte final do QA

| Arquivo | Casos | sha256 |
|---|---|---|
| `tests/integracao/qa_cache_unico_p3_test.sh` | 33 | `a77147099fef95b28ac2ded66b02820612866e11080399ad4f241263ec316649` |
| `tests/unit/qa_state_p3_test.sh` | 8 | `abc531546531dec8209094ec3f0154af27fe4f27de83161c507dd1dbc496aa12` |

Mudanças em relação ao ciclo 2:
- **Novos (4):**
  - `qa_guarda_origem_vazia_sem_memoria_recusa_variantes_de_vazio_no_enviar`
  - `qa_guarda_origem_vazia_no_receber_e_raiz_remota_inexistente`
  - `qa_guarda_permitir_origem_vazia_combinacoes`
  - `qa_guarda_origem_vazia_sem_nada_a_apagar_nao_recusa`
- **Alterados (3):**
  - `qa_exclusao_origem_vazia_com_conta_e_memoria_recusa_sem_escrita_nos_dois_sentidos`: memória intacta após a recusa.
  - `qa_exclusao_memoria_ilegivel_com_confirmar_nao_apaga`: passo com a origem povoada.
  - `qa_exclusao_memoria_descartada_com_travessia_parcial_nao_regrava_base_vazia`: arquivo legível na origem e memória não regravada.

  Nenhuma asserção anterior foi enfraquecida.

### Veredito do ciclo 3

- Status: **Aprovado**, com as observações O-1, O-6 e O-7 (Info, sem impacto em exclusão).
- Todos os achados QA-P3-01 a QA-P3-07 estão corrigidos e cobertos por caso e por mutante. A guarda de origem vazia não tem atalho nos dois sentidos, e o RF-41(e) e o RF-41(f) seguem ativos como defesa em profundidade.

| Ciclo | Data | Status | Resumo | Responsável |
|---|---|---|---|---|
| 3 | 2026-10-19 | Aprovado | QA-P3-05..07 corrigidos; guarda sem memória validada | QA Expert → Tech Lead |

Aprovação do solicitante (regra 12): **pendente**, sobre os dois arquivos acima, com os sha256 do ciclo 3.
