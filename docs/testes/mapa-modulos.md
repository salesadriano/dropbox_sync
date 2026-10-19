# Mapa de modulos de teste

Mantido pelo QA Expert (Regra 8 de `protocolo-tdd`; detalhamento em `.github/skills/protocolo-tdd/references/execucao-por-modulo.md`). Levantado em 2026-10-18 (fase P2, achado QA-05 da P1) a partir do codigo, sem interpretacao.

## Origem das linhas

- **Modulo = arquivo.** Cada arquivo de `lib/`, `commands/` e `bin/` e um modulo; nao ha agrupamento por semelhanca de nome, entao nao ha separacao a pedir ao solicitante.
- **Dependencia automatica**, lida do codigo: `. "$dir/x.sh"` entre `lib/*.sh`, `commands/*.sh` e `bin/dbx`; e `. "$DBX_HARNESS_RAIZ/lib/x.sh"` nos testes. **Dependencia por chamada** (sem `source`, levantada na P2 por `grep -n 'dbx_http_\|DBX_HTTP_' lib/cmd.sh lib/transfer.sh commands/sync.sh bin/dbx`): marcada em negrito como "chama" ou "le canais de".
- **Direto** = o teste carrega o modulo (ou o audita por caminho). **Transitivo** = o teste exercita o modulo por um dependente (outra lib ou `bin/dbx`).
- Comando do teste: `bash tests/run.sh <filtro>`. O filtro e **um** trecho do nome do arquivo (`tests/run.sh` aceita um unico argumento; casa por substring em `tests/unit/` e `tests/integracao/`). Filtro sem correspondencia REPROVA.

## Regra 1: auditorias de diretorio (todo diff em `lib/*.sh`)

Estes testes varrem `lib/*.sh` inteiro e portanto cobrem arquivo novo sem alterar o mapa. **Todo diff em `lib/*.sh` seleciona `json`, `http`, `preflight`, `composicao` e `tmp_test`**, qualquer que seja a lib alterada:

| Teste | Auditoria (linhas) |
|---|---|
| `tests/unit/json_test.sh` | capturas e uso de `lib/*.sh` (495, 506) |
| `tests/unit/http_test.sh` | `lib/*.sh` (103) |
| `tests/unit/preflight_test.sh` | variaveis, vocabulario e comandos externos de `lib/*.sh` (347-354) |
| `tests/integracao/composicao_test.sh` | `lib/*.sh` (549, 602); `commands/*.sh` e `lib/cmd.sh` (657); ponto unico do caminho remoto em `commands/*.sh` (fase 1b, `teste_todo_caminho_remoto_de_comando_passa_pelo_ponto_unico`) |
| `tests/unit/tmp_test.sh` (fase 2 do backlog) | `lib/*.sh`, `commands/*.sh` e `bin/dbx`: nenhum `mktemp` nem `trap` fora de `lib/tmp.sh` (TC-TMP-01, com mutacao); `commands/sync.sh` e `commands/verificar.sh` sem area, remocao ou tratador proprio (TC-CNF-01) |

Conferido por `grep -l 'lib/\*.sh' tests/unit/*.sh tests/integracao/*.sh`: esses quatro e, desde a fase 2 do backlog, `tmp_test` (filtro proprio `tmp_test`). `trava_test` tambem le `lib/*.sh` (TC-TRV-36: criacao de trava so em `lib/state`). Auditorias de `commands/*.sh`: `cli_test` (150, 166, 201), `composicao_test` (657 e o ponto unico do caminho remoto, fase 1b) e `tmp_test` (TC-TMP-01, TC-CNF-01). **Todo diff em `commands/*.sh` seleciona `cli`, `composicao` e `tmp_test`.**

## Regra 2: testes `qa_*`

Teste `qa_*` novo entra no mapa na criacao. O filtro `qa_` seleciona os nove de uma vez; para um so, use o filtro proprio da tabela. O filtro `state` casa tambem `qa_state_p3` (substring), o que e desejado: diff em `lib/state.sh` seleciona os dois.

| Arquivo | Filtro proprio | Carrega / executa | Selecionado por diff em |
|---|---|---|---|
| `tests/integracao/qa_integridade_p1_test.sh` (P1) | `qa_integridade` | `bin/dbx` (download 12x, upload 1x); carrega `lib/errors.sh`, `lib/hash.sh` | `bin/dbx`, `commands/download.sh`, `commands/upload.sh`, `lib/transfer.sh`, `lib/hash.sh`, `lib/http.sh`, `lib/progress.sh`, `lib/state.sh`, `lib/path.sh` |
| `tests/unit/qa_rede_p2_test.sh` (P2) | `qa_rede` | carrega `lib/errors`, `json`, `http`, `auth`, `hash`, `transfer` (e `progress` por eles); copia e executa `tests/run.sh` e `tests/support/harness.sh` | `lib/http.sh`, `lib/transfer.sh`, `lib/json.sh`, `lib/auth.sh`, `lib/hash.sh`, `lib/errors.sh`, `lib/progress.sh`, `tests/run.sh`, `tests/support/harness.sh` |
| `tests/integracao/qa_robustez_rede_p2_test.sh` (P2) | `qa_robustez` | `bin/dbx` (download, upload, sync, space); carrega `lib/errors.sh`, `lib/hash.sh` | `bin/dbx`, `commands/download.sh`, `commands/sync.sh`, `commands/upload.sh`, `lib/http.sh`, `lib/cmd.sh`, `lib/transfer.sh`, `lib/output.sh`, `lib/auth.sh`, `lib/config.sh`, `lib/errors.sh`, `lib/hash.sh`, `lib/sync.sh`, `lib/walk.sh`, `lib/state.sh` |
| `tests/integracao/qa_cache_unico_p3_test.sh` (fase 3) | `qa_cache_unico` | `bin/dbx` (sync nos dois sentidos, upload); carrega `lib/errors.sh`, `lib/hash.sh`; audita o texto de `install.sh`, `README.md`, `bin/`, `lib/`, `commands/` | `bin/dbx`, `commands/sync.sh`, `commands/upload.sh`, `lib/state.sh`, `lib/hash.sh`, `lib/walk.sh`, `lib/path.sh`, `lib/sync.sh`, `lib/auth.sh`, `lib/config.sh`, `lib/http.sh`, `lib/errors.sh`, `lib/transfer.sh`, `lib/cmd.sh`, `install.sh`, `README.md` |
| `tests/integracao/qa_docs_aliases_p4_test.sh` (fase 4) | `qa_docs_aliases` | `bin/dbx` (sync nos dois sentidos, unlink, config, upload, help); carrega `lib/errors.sh`, `lib/hash.sh`; em processo isolado carrega `lib/errors`, `progress`, `json`, `sync`, `preflight`; audita o texto de `README.md`, `lib/`, `commands/`, `bin/dbx`, `install.sh` e `docs/arquitetura/system-design.md` | `bin/dbx`, `commands/sync.sh`, `commands/unlink.sh`, `commands/config.sh`, `commands/upload.sh`, `lib/sync.sh`, `lib/preflight.sh`, `lib/json.sh`, `lib/output.sh`, `lib/http.sh`, `lib/auth.sh`, `lib/config.sh`, `lib/state.sh`, `lib/hash.sh`, `lib/walk.sh`, `lib/transfer.sh`, `lib/cmd.sh`, `lib/errors.sh`, `lib/progress.sh`, `install.sh`, `README.md`, `docs/arquitetura/system-design.md` |
| `tests/unit/qa_state_p3_test.sh` (fase 3) | `qa_state` | carrega `lib/errors`, `json`, `config`, `state` (e `hash` por ele), `http`, `auth` | `lib/state.sh`, `lib/hash.sh`, `lib/config.sh`, `lib/json.sh`, `lib/http.sh`, `lib/auth.sh`, `lib/errors.sh`, `lib/progress.sh` |
| `tests/integracao/qa_pendencias_p0_test.sh` (fase 0) | `qa_pendencias_p0` | `bin/dbx` (upload com `get_metadata` de corpo vazio, truncado, sem campo, hash malformado, pasta e 5xx); carrega `lib/errors.sh`, `lib/hash.sh`; em processo isolado carrega `lib/errors`, `progress`, `json`, `hash`, `http`, `auth`, `cmd`; roda em copia um mutante de `tests/unit/identidade_gnustat_test.sh` | `bin/dbx`, `commands/upload.sh`, `lib/cmd.sh`, `lib/json.sh`, `lib/http.sh`, `lib/auth.sh`, `lib/hash.sh`, `lib/errors.sh`, `lib/progress.sh`, `tests/unit/identidade_gnustat_test.sh` |
| `tests/integracao/qa_consulta_diagnostico_b1_test.sh` (fase 1 do backlog) | `qa_consulta_diagnostico` | `bin/dbx` (verificar e verify nos dois sentidos, diagnostico com cada utilitario do preflight fora do `PATH` por `bin/dbx` direto e por vinculo simbolico, info, upload, upload -, sync, completar e completion); carrega `lib/errors.sh` e, em processo isolado, `lib/hash.sh`; carrega `completions/dbx.bash` num bash limpo; executa `install.sh` e `uninstall.sh` num `HOME` temporario | `bin/dbx`, `commands/verificar.sh`, `commands/diagnostico.sh`, `commands/completar.sh`, `commands/upload.sh`, `commands/sync.sh`, `completions/dbx.bash`, `install.sh`, `uninstall.sh`, `lib/sync.sh`, `lib/walk.sh`, `lib/cmd.sh`, `lib/auth.sh`, `lib/preflight.sh`, `lib/config.sh`, `lib/output.sh`, `lib/http.sh`, `lib/path.sh`, `lib/state.sh`, `lib/hash.sh`, `lib/errors.sh`, `lib/cli.sh` |
| `tests/integracao/qa_trava_tmp_b2_test.sh` (fase 2 do backlog) | `qa_trava_tmp` | `bin/dbx` (sync, `--dry-run`, verificar, download de pasta, unlink, diagnostico e `--json`, upload) com duplos proprios de `curl`, `ln` (SIGKILL em cada fase da retomada) e `sleep` (sinal durante a espera), processos simultaneos reais, `LC_ALL=C` e `C.UTF-8`; carrega `lib/errors.sh`, `lib/tmp.sh` e, em processo isolado, `lib/errors`, `json`, `path`, `config`, `state` | `bin/dbx`, `commands/sync.sh`, `commands/verificar.sh`, `commands/download.sh`, `commands/unlink.sh`, `commands/diagnostico.sh`, `lib/state.sh`, `lib/tmp.sh`, `lib/cmd.sh`, `lib/cli.sh`, `lib/config.sh`, `lib/path.sh`, `lib/http.sh`, `lib/hash.sh`, `lib/errors.sh` |
| `tests/integracao/qa_confinamento_remoto_b1b_test.sh` (fase 1b do backlog) | `qa_confinamento_remoto` | `bin/dbx` (upload de arquivo, de fluxo e de diretorio, download de arquivo e de pasta, list, delete, info, sync e verificar nos dois sentidos, `--dry-run`, sob `LC_ALL=C` e `C.UTF-8`); carrega `lib/errors.sh` | `bin/dbx`, `commands/upload.sh`, `commands/download.sh`, `commands/list.sh`, `commands/delete.sh`, `commands/info.sh`, `commands/sync.sh`, `commands/verificar.sh`, `commands/config.sh`, `lib/cmd.sh`, `lib/path.sh`, `lib/config.sh`, `lib/json.sh`, `lib/errors.sh` |

## Regra 3: `scripts/tests/*.bats`

Nao fazem parte da suite oficial (`scripts/suite-completa.cmd` = `bash tests/run.sh`) e `bats` nao esta instalado neste ambiente. Cobrem apenas `scripts/*.sh` e os hooks, nunca `lib/`, `commands/` ou `bin/`. Selecionados somente por diff em `scripts/`, executados onde `bats` existir: `bats scripts/tests/<x>.bats`.

| Script alterado | Arquivos `.bats` |
|---|---|
| `alteracoes-externas.sh` | `alteracoes-externas`, `alteracoes-externas-merge-qa`, `alteracoes-externas-trava-qa`, `guarda-de-comandos`, `qa-guarda-de-comandos`, `qa-resumo-de-estado` |
| `suite-completa.sh`, `suite-completa.cmd` | `suite-completa`, `suite-completa-wrapper`, `qa-suite-completa-no-push`, `guarda-de-comandos` |
| `limpar-worktrees.sh` | `limpar-worktrees`, `qa-limpar-worktrees` |
| `memoria-index.sh` | `memoria-index`, `qa-memoria-index` |
| `resumo-de-estado.sh` | `resumo-de-estado`, `qa-resumo-de-estado` |
| `verificar-instrucoes-do-projeto.sh` | `verificar-instrucoes-do-projeto`, `qa-verificar-instrucoes-do-projeto` |
| `conferir-copias.sh` | `conferir-copias`, `qa-conferir-copias` |
| `faixa-do-modelo.sh`, `tabela-de-modelos.tsv`, `avaliar-troca-de-modelo.sh` | `faixa-do-modelo`, `qa-selecao-de-modelo`, `avaliar-troca-de-modelo` |
| `specs-nao-executadas.sh` | `specs-nao-executadas`, `qa-specs-nao-executadas` |
| `guarda-de-comandos.sh`, `.txt` | `guarda-de-comandos`, `qa-guarda-de-comandos` |

Pares sem referencia textual ao script no corpo do `.bats` foram ligados pelo nome do arquivo.

## Mapa por modulo: `lib/`

"Carrega" e o que o modulo carrega (a cadeia transitiva vem do mapa dos carregados). Alem desta tabela, aplicar a Regra 1.

| Modulo | Carrega | Dependentes diretos | Teste direto | Transitivo |
|---|---|---|---|---|
| `lib/errors.sh` | | todas as libs | `errors` | toda a suite |
| `lib/tmp.sh` (fase 2 do backlog, RNF-35) | errors | http, hash, walk, transfer, cmd, state, config (`dbx_tmp_*`): toda area e todo `trap` do processo | `tmp_test` (registro, sinais, composicao, OBS-03, auditorias), `state_trava` | `trava` (matriz de sinais por fase, OBS-02, OBS-04), `sync`, `verificar`, `comandos`, `qa_` |
| `lib/hash.sh` | errors, tmp | cmd, state, transfer, walk, config; **chamado por** commands/upload e commands/sync (`dbx_hash_identidade`, fase 3) | `hash`, `hash_vetor_oficial`, `transfer`, `walk`, `state`, `cmd`, `identidade_gnustat` (RSK-43: formato e regras da identidade sob o GNU coreutils; pula sem `/usr/bin/gnustat`) | `comandos`, `sync`, `qa_` |
| `lib/json.sh` | errors | config, http | `json`, `config`, `http`, `auth`, `cabecalho`, `transfer`, `state`, `cmd` | `comandos` |
| `lib/path.sh` | errors | output; **chamado por** commands/upload e commands/sync (`dbx_path_local_canonico`); lib/cmd (`dbx_path_remoto_argumento`, fase 1b) | `path`, `output`, `cli`, `cabecalho`, `cmd` | `comandos`, `sync`, `confinamento_remoto` |
| `lib/output.sh` | errors, path; **le canais de** auth e config por nome (`DBX_AUTH_TOKEN`, `DBX_AUTH_REFRESH_TOKEN`, `DBX_CONFIG_REFRESH_TOKEN`, `DBX_CONFIG_APP_SECRET`) | bin/dbx; **chamado por** commands/sync (`dbx_output_mascarar_segredos`) | `output`, `cli`, `composicao`, `cmd` | `comandos`, `sync`, `qa_robustez` (fase P2: todo diagnostico passa pela mascaracao por valor) |
| `lib/progress.sh` | | http, sync, transfer, bin/dbx | `progress`, `transfer`, `http`, `cmd` | `comandos`, `sync`, `qa_` |
| `lib/cli.sh` | | bin/dbx (tabela de comandos e aliases `verify`, `doctor`, `completion`, fase 1 do backlog); commands/sync e commands/verificar (`dbx_cli_validar_espera`, fase 2) | `cli` | `comandos`, `verificar`, `diagnostico`, `completar`, `trava` (TC-ESR-01) |
| `lib/config.sh` | errors, json, tmp, hash | bin/dbx; **chamado por** state (`dbx_config_caminho_de_estado`) e cmd (`dbx_config_identidade`, chave da trava, fase 2) | `config`, `state`, `cmd` | `comandos`, `confinamento_remoto` (`raiz_remota` lida por lib/cmd, fase 1b), `trava` |
| `lib/http.sh` | errors, json, progress, tmp | bin/dbx; **chamado (sem `source`) por** cmd e transfer; canais lidos por commands/sync | `http`, `auth`, `cabecalho`, `transfer`, `qa_rede`, `cmd` | `comandos`, `sync`, `qa_` |
| `lib/auth.sh` | | bin/dbx; **le canais** `DBX_AUTH_ESCOPOS*` commands/diagnostico (DIV-35) | `auth`, `transfer`, `cmd`, `qa_state` (RF-63) | `comandos`, `qa_cache_unico`, `diagnostico`, `verificar` |
| `lib/cmd.sh` | hash, tmp, state; **chama** path (`dbx_path_local_canonico`) e config (`dbx_config_identidade`) no ciclo comum `dbx_cmd_ciclo_iniciar` (fase 2) | bin/dbx; commands/sync e commands/verificar (ciclo comum, RNF-36) | `cmd` (fase 3, RNF-32(d)); auditado por `composicao`. Auxiliar `dbx_cmd_ler_corpo_silencioso` (fase 0, O-5), usado por `commands/upload.sh`: `cmd` (unidade), `comandos` e `qa_pendencias_p0` (ponta a ponta). Espaco livre (`dbx_cmd_espaco_*`) e `dbx_cmd_caminho_exibivel` (fase 1 do backlog): `cmd` (unidade). Ponto unico `_dbx_cmd_caminho_remoto` (fase 1b, F-36/F-37): `cmd` (unidade), `confinamento_remoto` (ponta a ponta), auditado por `composicao` | `comandos`, `sync`, `cli`, `qa_robustez`, `espaco`, `verificar`, `diagnostico`, `completar`, `confinamento_remoto` |
| `lib/preflight.sh` | errors | bin/dbx (linha 185); commands/diagnostico (`dbx_preflight_ausentes`) | `preflight` | `comandos`, `diagnostico`, `qa_consulta_diagnostico` (lista com `ln`, fase 2) |
| `lib/transfer.sh` | errors, hash, progress, tmp; **chama** http (`DBX_HTTP_EFETIVO`) | commands/sync, commands/upload | `transfer`, `qa_rede` | `comandos`, `sync`, `qa_` |
| `lib/walk.sh` | errors, hash, tmp | commands/sync, commands/verificar | `walk`, `identidade_gnustat` | `sync` |
| `lib/state.sh` | errors, hash, tmp; **chama** config (`dbx_config_caminho_de_estado`) | cmd (trava, fase 2), commands/sync, commands/upload, commands/diagnostico e commands/unlink (listagem de travas) | `state` (fase 3, RNF-32(d); o filtro casa tambem `state_trava`, fase 2: trava, concorrencia real, matriz hostil), `qa_state`, `identidade_gnustat` | `sync`, `comandos`, `qa_cache_unico`, `trava` |
| `lib/sync.sh` | progress | commands/sync, commands/verificar, commands/diagnostico (`dbx_sync_localidade_disponivel`) | `sync_plano` (fase 1 do backlog: carrega errors, hash, sync; `dbx_sync_comparar`), `sync` (le o texto) | `sync`, `verificar`, `diagnostico` |

## Mapa por modulo: `commands/` e `bin/`

Nenhum comando tem teste unitario: todos sao exercitados por `bin/dbx` em testes ponta a ponta. Alem desta tabela, aplicar a Regra 1 (se o diff incluir `lib/`) e, para `commands/*.sh`, `cli` e `composicao`.

| Modulo | Carrega | Teste direto | Transitivo (executa `bin/dbx <cmd>`) |
|---|---|---|---|
| `bin/dbx` | errors, path, output, progress, cli (ajuda com `--esperar`, fase 2); sob demanda json, config, http, auth, cmd, preflight; **chama** `dbx_http_validar_ambiente` | `comandos` (`DBX_EXEC`), `completar` (ajuda como fonte unica das opcoes) | `sync`, `verificar`, `diagnostico`, `espaco`, `qa_`, `confinamento_remoto` |
| `commands/config.sh` | | | `comandos`, `qa_docs_aliases`; raiz explicita no ponto unico auditada por `composicao` (fase 1b) |
| `commands/delete.sh` | | `comandos` (le o fonte) | `comandos`, `confinamento_remoto` |
| `commands/download.sh` | | | `comandos`, `qa_integridade`, `qa_robustez`, `confinamento_remoto` |
| `commands/info.sh` | | | `comandos`, `confinamento_remoto` |
| `commands/list.sh` | | | `comandos`, `confinamento_remoto` |
| `commands/space.sh` | | | `comandos` |
| `commands/unlink.sh` | state (listagem de travas, fase 2) | | `comandos`, `qa_docs_aliases`, `trava` (TC-TRV-19, 20) |
| `commands/upload.sh` | transfer, state; **chama** path (`dbx_path_local_canonico`), hash (`dbx_hash_identidade`) e cmd (`dbx_cmd_espaco_checar`, fase 1 do backlog) | | `comandos`, `espaco`, `completar`, `qa_`, `confinamento_remoto` |
| `commands/sync.sh` | walk, state, sync, transfer; **chama** path (`dbx_path_local_canonico`), cli (`dbx_cli_validar_espera`) e cmd (`dbx_cmd_ciclo_iniciar`, fase 2; `dbx_cmd_espaco_checar`, `dbx_cmd_caminho_exibivel`, fase 1 do backlog); **le canais de** http (`DBX_HTTP_REQUISICOES`, `DBX_HTTP_RESUMO_DO_SERVICO`, `DBX_HTTP_CODIGO`, `DBX_HTTP_CLASSE`) | `sync` (le o fonte), `tmp_test` (TC-CNF-01) | `sync`, `trava`, `espaco`, `completar` (ajuda e opcoes), `qa_robustez`, `qa_cache_unico`, `qa_docs_aliases`, `confinamento_remoto` |
| `commands/verificar.sh` (fase 1 do backlog, RF-65) | walk, sync; **chama** cmd (`dbx_cmd_ciclo_iniciar`, fase 2), cli (`dbx_cli_validar_espera`) e auth | `tmp_test` (TC-CNF-01) | `verificar`, `trava`, `completar`, `qa_consulta_diagnostico`, `confinamento_remoto` |
| `commands/diagnostico.sh` (fase 1 do backlog, RF-66) | preflight, sync; camada de credencial por `dbx_carregar_camada_de_credencial` (bin/dbx); **le canais de** auth (`DBX_AUTH_ESCOPOS*`), preflight (`DBX_PREFLIGHT_AUSENTES`) e state (`DBX_STATE_TRAVAS_*`, checagem `trava`, fase 2) | | `diagnostico`, `trava` (TC-DIA-11..14, TC-TRV-35), `completar`, `qa_consulta_diagnostico` |
| `commands/completar.sh` (fase 1 do backlog, RF-68) | cmd; **le** `completions/dbx.bash` | | `completar`, `qa_consulta_diagnostico` |

## Testes da fase 2 do backlog (trava e `lib/tmp`)

| Arquivo | Filtro proprio | Carrega / executa | Selecionado por diff em |
|---|---|---|---|
| `tests/unit/tmp_test.sh` | `tmp_test` | carrega `lib/errors.sh`; processos proprios com `lib/tmp.sh`; audita `lib/*.sh`, `commands/*.sh`, `bin/dbx` | todo `lib/*.sh` e todo `commands/*.sh` (Regra 1), `bin/dbx` |
| `tests/unit/state_trava_test.sh` | `state_trava` (o filtro `state` tambem o casa) | processos proprios com `lib/errors`, `json`, `config`, `state` (e `hash`, `tmp` por eles); 20 disputantes reais | `lib/state.sh`, `lib/tmp.sh`, `lib/hash.sh`, `lib/config.sh`, `lib/json.sh`, `lib/errors.sh` |
| `tests/integracao/trava_test.sh` | `trava_test` | `bin/dbx` (sync, verificar, unlink, diagnostico, upload, download, list, info, space, delete, help); carrega `lib/errors.sh` e, em processo isolado, `lib/errors`, `json`, `path`, `config`, `state`, `hash`; audita `lib/*.sh`, `commands/*.sh`, `bin/dbx` (TC-TRV-36); usa `python3` so para o socket de OBS-04 (pula sem ele) | `bin/dbx`, `commands/sync.sh`, `commands/verificar.sh`, `commands/unlink.sh`, `commands/diagnostico.sh`, `completions/dbx.bash`, `lib/state.sh`, `lib/tmp.sh`, `lib/cmd.sh`, `lib/cli.sh`, `lib/config.sh`, `lib/http.sh`, `lib/hash.sh`, `lib/walk.sh`, `lib/transfer.sh`, `lib/path.sh`, `lib/preflight.sh`, `lib/output.sh`, `lib/errors.sh` |

## Mapa por modulo: autocompletar e instalacao (fase 1 do backlog)

| Modulo | Teste direto | Observacao |
|---|---|---|
| `completions/dbx.bash` | `completar`, `qa_consulta_diagnostico`, `trava` (TC-ESR-08, ajuda) | Opcoes conferidas contra `dbx help <comando>` nos dois sentidos: diff em `bin/dbx` (ajuda) ou em qualquer `commands/*.sh` com opcao nova seleciona `completar` |
| `install.sh`, `uninstall.sh` | `completar` (TC-CPL-06), `qa_consulta_diagnostico` | Alem de `qa_cache_unico` e `qa_docs_aliases` (auditoria de texto do `install.sh`) |
| `scripts/empacotar.sh` | `completar` (TC-CPL-07, roda numa copia do projeto) | Fora da Regra 3: nao tem `.bats` |

## Como usar

1. `git diff --name-only <base>...HEAD` (mais o working tree).
2. Para cada arquivo, juntar os filtros das tabelas; acrescentar a Regra 1 se houver `lib/*.sh` e `cli` mais `composicao` se houver `commands/*.sh`.
3. Arquivo de teste no diff: seu proprio filtro (`tests/unit/x_test.sh` vira `x`). `tests/support/*` e `tests/run.sh`: `harness`, e a suite inteira so com pedido explicito do solicitante (Regra 8).
4. Eliminar duplicados e rodar um por vez, parando no primeiro erro: `bash tests/run.sh <filtro>`.
5. Exemplo: diff em `lib/http.sh` e `commands/upload.sh` seleciona `http`, `json`, `preflight`, `composicao`, `auth`, `cabecalho`, `transfer`, `comandos`, `sync`, `qa_`, `cli`.
6. Arestas sem `source` (fase P2): `lib/cmd` e `lib/transfer` chamam funcoes de `lib/http`, e `commands/sync` le canais dele. Elas nao aparecem no `grep` de `. "$dir/x.sh"`: diff em `lib/http.sh` seleciona tambem `sync` e os `qa_`, mesmo que nenhum carregue `lib/http` diretamente.
7. Arquivo do diff sem linha no mapa e nao enquadrado (Regra 8): parar e pedir a definicao ao Tech Lead.

## Lacunas de cobertura reveladas

- ~~`lib/state.sh` e `lib/cmd.sh`: nenhum teste os carrega~~ — fechada na fase 3 (RNF-32(d)): `tests/unit/state_test.sh` e `tests/unit/cmd_test.sh` carregam os dois diretamente. `lib/db.sh` e `tests/unit/db_test.sh` foram removidos (RNF-33).
- `lib/sync.sh`: `sync_test` apenas audita o texto; a logica so e exercitada pelo e2e.
- `commands/*.sh`: sem teste unitario; dependem da suite ponta a ponta.
- `scripts/tests/*.bats`: fora da suite oficial e sem `bats` instalado; sem evidencia de execucao.

## Manutencao

Dono: QA Expert. Atualizar no mesmo ciclo quando houver: modulo novo ou renomeado em `lib/`, `commands/` ou `bin/`; teste novo (inclusive `qa_*`) ou novo carregamento de modulo em teste; carga nova entre libs (`. "$dir/x.sh"`); auditoria nova ou removida sobre `lib/*.sh` ou `commands/*.sh`; regressao fora da selecao na suite completa (dependencia ausente aqui).
