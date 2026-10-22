# Mapa de modulos de teste

Mantido pelo QA Expert (Regra 8 de `protocolo-tdd`; detalhamento em `.github/skills/protocolo-tdd/references/execucao-por-modulo.md`). Levantado em 2026-10-18 (fase P2, achado QA-05 da P1); atualizado em 2026-10-22 com as fases 6 a 9 do backlog a partir do codigo, sem interpretacao.

## Origem das linhas

- **Modulo = arquivo.** Cada arquivo de `lib/`, `commands/` e `bin/` e um modulo; nao ha agrupamento por semelhanca de nome, entao nao ha separacao a pedir ao solicitante.
- **Dependencia automatica**, lida do codigo: `. "$dir/x.sh"` entre `lib/*.sh`, `commands/*.sh` e `bin/dbx`; e `. "$DBX_HARNESS_RAIZ/lib/x.sh"` nos testes. **Dependencia por chamada** (sem `source`, levantada na P2 por `grep -n 'dbx_http_\|DBX_HTTP_' lib/cmd.sh lib/transfer.sh commands/sync.sh bin/dbx`): marcada em negrito como "chama" ou "le canais de".
- **Direto** = o teste carrega o modulo (ou o audita por caminho). **Transitivo** = o teste exercita o modulo por um dependente (outra lib ou `bin/dbx`).
- Comando do teste: `bash tests/run.sh <filtro>`. O filtro e **um** trecho do nome do arquivo (`tests/run.sh` aceita um unico argumento; casa por substring em `tests/unit/` e `tests/integracao/`). Filtro sem correspondencia REPROVA.

## Regra 1: auditorias de diretorio (todo diff em `lib/*.sh`)

Estes testes varrem `lib/*.sh` inteiro e portanto cobrem arquivo novo sem alterar o mapa. **Todo diff em `lib/*.sh` seleciona `json`, `http`, `preflight`, `composicao`, `tmp_test`, `auth`, `hash`, `path`, `trava_test` e `qa_docs_aliases`**, qualquer que seja a lib alterada:

| Teste | Auditoria (linhas) |
|---|---|
| `tests/unit/json_test.sh` | capturas e uso de `lib/*.sh` (495, 506) |
| `tests/unit/http_test.sh` | `lib/*.sh` (103) |
| `tests/unit/preflight_test.sh` | variaveis, vocabulario e comandos externos de `lib/*.sh` (347-354) |
| `tests/integracao/composicao_test.sh` | `lib/*.sh` (549, 602); `commands/*.sh` e `lib/cmd.sh` (657); ponto unico do caminho remoto em `commands/*.sh` (fase 1b, `teste_todo_caminho_remoto_de_comando_passa_pelo_ponto_unico`) |
| `tests/unit/tmp_test.sh` (fase 2 do backlog) | `lib/*.sh`, `commands/*.sh` e `bin/dbx`: nenhum `mktemp` nem `trap` fora de `lib/tmp.sh` (TC-TMP-01, com mutacao); `commands/sync.sh` e `commands/verificar.sh` sem area, remocao ou tratador proprio (TC-CNF-01) |
| `tests/unit/auth_test.sh` | formularios de token sem segredo e ausencia de `code_verifier`/`code_challenge` em `lib/*.sh` (723, 732) |
| `tests/unit/hash_test.sh` | nenhum `stat -c %Y` fora de `lib/hash.sh` (666) |
| `tests/unit/path_test.sh` | nenhum `$(readlink` em `lib/*.sh` (451) |
| `tests/integracao/trava_test.sh` | criacao de trava so em `lib/state`, em `lib/*.sh`, `commands/*.sh` e `bin/dbx` (695; TC-TRV-36) |
| `tests/integracao/qa_docs_aliases_p4_test.sh` | texto de `README.md`, `lib/*.sh`, `commands/*.sh`, `bin/dbx` e `install.sh` (613) |

Conferido em 2026-10-22 por `grep -l 'lib/\*' tests/unit/*.sh tests/integracao/*.sh`: sao exatamente os dez da tabela. Os testes das fases 8 e 9 (`perfis_*`, `state_trava_raiz`, `lote_test`, `paralelo_test`) carregam libs especificas e nao varrem `lib/*.sh`; ficam nas tabelas das suas fases. O filtro `trava_test` leva o sufixo porque `trava` casa tambem `state_trava`, `perfis_trava_raiz` e `qa_trava_tmp`. Auditorias de `commands/*.sh`: `cli_test` (150, 166, 201), `composicao_test` (657 e o ponto unico do caminho remoto, fase 1b) e `tmp_test` (TC-TMP-01, TC-CNF-01). **Todo diff em `commands/*.sh` seleciona `cli`, `composicao` e `tmp_test`.**

## Regra 2: testes `qa_*`

Teste `qa_*` novo entra no mapa na criacao. O filtro `qa_` seleciona os dezoito de uma vez (contagem conferida com `ls tests/unit/qa_* tests/integracao/qa_* | wc -l` na fase 9; eram treze na fase 5); para um so, use o filtro proprio da tabela. O filtro `state` casa tambem `qa_state_p3` (substring), o que e desejado: diff em `lib/state.sh` seleciona os dois.

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
| `tests/integracao/qa_recuperacao_b3_test.sh` (fase 3 do backlog) | `qa_recuperacao` | `bin/dbx` (revisoes, restaurar, lixeira e a exclusao permanente) com duplo de `curl` por regra e registro de chamadas, `XDG_STATE_HOME` vazio e terminal real para a confirmacao; carrega `lib/errors.sh` | `bin/dbx`, `commands/revisoes.sh`, `commands/restaurar.sh`, `commands/lixeira.sh`, `lib/cmd.sh`, `lib/sync.sh`, `lib/http.sh`, `lib/auth.sh`, `lib/json.sh`, `lib/errors.sh` |
| `tests/integracao/qa_filtros_banda_b4_test.sh` (fase 4 do backlog) | `qa_filtros_banda` (os filtros `filtro` e `banda` tambem o casam, por substring) | `bin/dbx` (sync nos dois sentidos com `--espelhar`, `--dry-run`, paginacao `list_folder/continue`, vinculo simbolico e fifo, nome local nao UTF-8, memoria do par; upload e download com `--limite-banda`/`--bwlimit` e `DBX_LIMITE_BANDA`; list; verificar) com duplos proprios de `curl` (registro de endpoint, `limit-rate` da configuracao e corpo) e de `rm`; carrega `lib/errors.sh` e, em processo isolado, `lib/hash.sh`; audita o texto de `lib/sync.sh` (ponto unico de `server_modified`, DIV-96) e o da propria suite (RNF-24) | `bin/dbx`, `commands/sync.sh`, `commands/upload.sh`, `commands/download.sh`, `commands/verificar.sh`, `lib/filtro.sh`, `lib/sync.sh`, `lib/walk.sh`, `lib/cmd.sh`, `lib/cli.sh`, `lib/http.sh`, `lib/state.sh`, `lib/hash.sh`, `lib/errors.sh` |
| `tests/integracao/qa_compartilhamento_b5_test.sh` (fase 5 do backlog) | `qa_compartilhamento` (o filtro `compartilh` tambem o casa, por substring) | `bin/dbx` (compartilhar criar, reuso, modificacao, `--listar`, `--revogar`, `--dry-run`, `--null`, `--debug`; link-temporario e temp-link; help; diagnostico) com duplo proprio de `curl` (registro de endpoint e corpo, `argv`, configuracao de `-K -`, varredura de `/proc/*/cmdline` e `environ` durante a chamada, modo do arquivo de corpo e `umask` herdada; ciclo 2: mascara da senha pelo valor, resposta 2xx malformada, paridade criacao/modify; ciclo 3: nenhum texto do servico com a senha no pedido, host hostil na recusa de URL, teto de 1000 paginas), sinais TERM/INT/HUP/KILL e pseudo-terminal por `python3` (pula sem ele); carrega `lib/errors.sh` e `completions/dbx.bash` num bash limpo; audita o texto da propria suite (RNF-24) | `bin/dbx`, `commands/compartilhar.sh`, `commands/link_temporario.sh`, `commands/diagnostico.sh`, `lib/compartilhamento.sh`, `lib/cli.sh`, `lib/cmd.sh`, `lib/http.sh`, `lib/tmp.sh`, `lib/json.sh`, `lib/path.sh`, `lib/errors.sh`, `completions/dbx.bash`, `README.md` |
| `tests/integracao/qa_retencao_b6_test.sh` (fase 6) | `qa_retencao` (nao casa `retencao_test`; o filtro `reter` nao o casa) | `bin/dbx` (reter e retain); carrega `lib/errors.sh`, `lib/retencao.sh` | `bin/dbx`, `commands/reter.sh`, `lib/retencao.sh`, `lib/filtro.sh`, `lib/cmd.sh`, `lib/http.sh`, `lib/errors.sh` |
| `tests/integracao/qa_retomada_b7a_test.sh` (fase 7a) | `qa_retomada` (o filtro `retomada` tambem o casa, por substring) | `bin/dbx` (upload e download retomados); carrega `lib/errors.sh`, `lib/hash.sh`; limpa os ambientes do caso anterior no tmp da suite | `bin/dbx`, `commands/upload.sh`, `commands/download.sh`, `commands/unlink.sh`, `commands/diagnostico.sh`, `lib/transfer.sh`, `lib/state.sh`, `lib/cmd.sh`, `lib/hash.sh`, `lib/http.sh`, `lib/errors.sh` |
| `tests/integracao/qa_cursor_b7b_test.sh` (fase 7b) | `qa_cursor` (o filtro `cursor` tambem o casa, por substring) | `bin/dbx` (sync com cursor); carrega `lib/errors.sh`, `lib/hash.sh` | `bin/dbx`, `commands/sync.sh`, `lib/state.sh`, `lib/sync.sh`, `lib/hash.sh`, `lib/errors.sh` |
| `tests/integracao/qa_perfis_b8_test.sh` (fase 8) | `qa_perfis` (o filtro `perfis` tambem o casa) | `bin/dbx` (perfis, config, unlink, sync com perfil); carrega `lib/errors.sh`, `lib/tmp.sh`, `lib/hash.sh`, `lib/json.sh`, `lib/config.sh`, `lib/state.sh` | `bin/dbx`, `commands/perfis.sh`, `commands/config.sh`, `commands/unlink.sh`, `commands/diagnostico.sh`, `commands/sync.sh`, `lib/config.sh`, `lib/state.sh`, `lib/preflight.sh`, `lib/cli.sh`, `lib/json.sh`, `lib/errors.sh` |
| `tests/integracao/qa_desempenho_b9_test.sh` (fase 9) | `qa_desempenho` | `bin/dbx` (sync em paralelo e em lote, reter); carrega `lib/errors.sh`, `lib/hash.sh`, `tests/support/lote_duplo.sh` | `bin/dbx`, `commands/sync.sh`, `commands/reter.sh`, `lib/lote.sh`, `lib/transfer.sh`, `lib/http.sh`, `lib/cmd.sh`, `lib/sync.sh`, `lib/hash.sh`, `lib/errors.sh`, `tests/support/lote_duplo.sh` |

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
| `lib/errors.sh` | | todas as libs | `errors`, `compartilhamento_test` (fase 5: tags de RF-90(a) com o qualificador `settings_error`; `link_password` mascarado, DIV-111) | toda a suite |
| `lib/tmp.sh` (fase 2 do backlog, RNF-35) | errors | http, hash, walk, transfer, cmd, state, config (`dbx_tmp_*`): toda area e todo `trap` do processo; commands/compartilhar (`dbx_tmp_armar`, sinal na leitura da senha, fase 5) | `tmp_test` (registro, sinais, composicao, OBS-03, auditorias), `state_trava` | `trava` (matriz de sinais por fase, OBS-02, OBS-04), `sync`, `verificar`, `comandos`, `qa_` |
| `lib/hash.sh` | errors, tmp | cmd, state, transfer, walk, config; **chamado por** commands/upload e commands/sync (`dbx_hash_identidade`, fase 3) | `hash`, `hash_vetor_oficial`, `transfer`, `walk`, `state`, `cmd`, `identidade_gnustat` (RSK-43: formato e regras da identidade sob o GNU coreutils; pula sem `/usr/bin/gnustat`) | `comandos`, `sync`, `qa_` |
| `lib/json.sh` | errors | config, http | `json`, `config`, `http`, `auth`, `cabecalho`, `transfer`, `state`, `cmd` | `comandos` |
| `lib/path.sh` | errors | output; **chamado por** commands/upload e commands/sync (`dbx_path_local_canonico`); lib/cmd (`dbx_path_remoto_argumento`, fase 1b) | `path`, `output`, `cli`, `cabecalho`, `cmd` | `comandos`, `sync`, `confinamento_remoto` |
| `lib/output.sh` | errors, path; **le canais de** auth e config por nome (`DBX_AUTH_TOKEN`, `DBX_AUTH_REFRESH_TOKEN`, `DBX_CONFIG_REFRESH_TOKEN`, `DBX_CONFIG_APP_SECRET`) | bin/dbx; **chamado por** commands/sync (`dbx_output_mascarar_segredos`) | `output`, `cli`, `composicao`, `cmd` | `comandos`, `sync`, `qa_robustez` (fase P2: todo diagnostico passa pela mascaracao por valor) |
| `lib/progress.sh` | | http, sync, transfer, bin/dbx | `progress`, `transfer`, `http`, `cmd` | `comandos`, `sync`, `qa_` |
| `lib/cli.sh` | | bin/dbx (tabela de comandos e aliases `verify`, `doctor`, `completion`, fase 1 do backlog; `link-temporario`, `temp-link`, `compartilhar`, `share`, fase 5; `reter`, `retain`, fase 6); commands/sync e commands/verificar (`dbx_cli_validar_espera`, fase 2); **chamado por** cmd (`dbx_cli_validar_taxa`, limite de banda, fase 4), commands/config e commands/compartilhar (`dbx_cli_ler_oculto`, leitura sem eco, fase 5) | `cli`, `banda`, `compartilhamento_test` | `comandos`, `verificar`, `diagnostico`, `completar`, `trava` (TC-ESR-01) |
| `lib/config.sh` | errors, json, tmp, hash | bin/dbx; **chamado por** state (`dbx_config_caminho_de_estado`) e cmd (`dbx_config_identidade`, chave da trava, fase 2) | `config`, `state`, `cmd` | `comandos`, `confinamento_remoto` (`raiz_remota` lida por lib/cmd, fase 1b), `trava` |
| `lib/http.sh` | errors, json, progress, tmp | bin/dbx; **chamado (sem `source`) por** cmd e transfer (`dbx_http_limite_banda`, `limit-rate` so no modo `conteudo`, fase 4); canais lidos por commands/sync | `http`, `auth`, `cabecalho`, `transfer`, `qa_rede`, `cmd`, `banda` (fase 4: `limit-rate` por chamada), `retencao_test` (fase 6: canal `DBX_HTTP_DATA`, cabecalho `Date`, DIV-134) | `comandos`, `sync`, `qa_` |
| `lib/auth.sh` | | bin/dbx; **le canais** `DBX_AUTH_ESCOPOS*` commands/diagnostico (DIV-35) | `auth`, `transfer`, `cmd`, `qa_state` (RF-63) | `comandos`, `qa_cache_unico`, `diagnostico`, `verificar` |
| `lib/cmd.sh` | hash, tmp, state; **chama** path (`dbx_path_local_canonico`) e config (`dbx_config_identidade`) no ciclo comum `dbx_cmd_ciclo_iniciar` (fase 2) | bin/dbx; commands/sync e commands/verificar (ciclo comum, RNF-36) | `cmd` (fase 3, RNF-32(d)); auditado por `composicao`. Auxiliar `dbx_cmd_ler_corpo_silencioso` (fase 0, O-5), usado por `commands/upload.sh`: `cmd` (unidade), `comandos` e `qa_pendencias_p0` (ponta a ponta). Espaco livre (`dbx_cmd_espaco_*`) e `dbx_cmd_caminho_exibivel` (fase 1 do backlog): `cmd` (unidade). Ponto unico `_dbx_cmd_caminho_remoto` (fase 1b, F-36/F-37): `cmd` (unidade), `confinamento_remoto` (ponta a ponta), auditado por `composicao`. `_dbx_cmd_escrita_remota` com idempotencia declarada (fase 5, DIV-119): `compartilhar_test` | `comandos`, `sync`, `cli`, `qa_robustez`, `espaco`, `verificar`, `diagnostico`, `completar`, `confinamento_remoto` |
| `lib/preflight.sh` | errors | bin/dbx (linha 185); commands/diagnostico (`dbx_preflight_ausentes`) | `preflight` | `comandos`, `diagnostico`, `qa_consulta_diagnostico` (lista com `ln`, fase 2) |
| `lib/transfer.sh` | errors, hash, progress, tmp; **chama** http (`DBX_HTTP_EFETIVO`) | commands/sync, commands/upload | `transfer`, `qa_rede` | `comandos`, `sync`, `qa_` |
| `lib/walk.sh` | errors, hash, tmp, filtro (fase 4: poda da pasta excluida, `DBX_WALK_PODADAS`) | commands/sync, commands/verificar | `walk`, `identidade_gnustat` | `sync`, `filtros` (TC-FES-04, 05) |
| `lib/state.sh` | errors, hash, tmp; **chama** config (`dbx_config_caminho_de_estado`) | cmd (trava, fase 2), commands/sync, commands/upload, commands/diagnostico e commands/unlink (listagem de travas) | `state` (fase 3, RNF-32(d); o filtro casa tambem `state_trava`, fase 2: trava, concorrencia real, matriz hostil), `qa_state`, `identidade_gnustat` | `sync`, `comandos`, `qa_cache_unico`, `trava` |
| `lib/sync.sh` | progress, filtro (fase 4: chave sem caixa de `lib/filtro`, predicado unico `dbx_sync_no_escopo`, descarte remoto, contagens) | commands/sync, commands/verificar, commands/diagnostico (`dbx_sync_localidade_disponivel`) | `sync_plano` (fase 1 do backlog: carrega errors, hash, sync; `dbx_sync_comparar`), `sync` (le o texto) | `sync`, `verificar`, `diagnostico`, `filtros` |
| `lib/filtro.sh` (fase 4, DIV-94) | errors | walk, sync, retencao (fase 6: nome avulso `dbx_filtro_nome_preparar`/`dbx_filtro_nome_casa`, validacao unica `_dbx_filtro_validar_padrao`); **chamado por** cmd (`dbx_cmd_filtros_preparar`, `dbx_cmd_campos_de_filtro`), commands/download e commands/reter | `filtro` (unidade: sintaxe, caixa, localidade, validacao, data e tamanho, pureza), `retencao_test` (nome avulso, fase 6) | `filtros` (sync, verificar e download de pasta; guarda do espelhamento), `filtros_ajuda`, `sync`, `verificar`, `reter_test` |
| `lib/state.sh` (fase 7a, F-03) | (ver a linha geral acima) | **acrescimo da fase 7a:** registro `retomada-*`, leitor limitado (tambem para `upload-*`), trava de registro, barreira do `.part`; **chamado por** cmd (`dbx_cmd_retomada_preparar`, `dbx_cmd_receber_retomavel`), transfer (gravacao e carga do registro), commands/unlink e commands/diagnostico (`dbx_state_retomada_listar`) | `retomada_estado` | `retomada_upload`, `retomada_download` |
| `lib/state.sh` (fase 7b, F-14) | (ver a linha geral acima) | **acrescimo da fase 7b:** registro `cursor-*` (cursor mais retrato remoto, leitor em fluxo com rodape SHA-256, gravacao com rodape pela funcao atomica existente, poda, varredura periodica, listagem so do cabecalho); **chamado por** commands/sync (`dbx_state_cursor_*`) e commands/diagnostico (`dbx_state_cursor_listar`) | `cursor_estado` (filtro `cursor`, que casa tambem `cursor_test`) | `cursor` |
| `lib/sync.sh` (fase 7b, F-14, DIV-g) | (ver a linha geral acima); **le** a constante `DBX_STATE_CURSOR_RE_CURSOR` de lib/state | **acrescimo da fase 7b:** tabela remota sem filtro (`dbx_sync_listar_completo`, `dbx_sync_tabela_emitir`; `dbx_sync_enumerar_remoto` virou a composicao das duas), delta (`dbx_sync_listar_delta`), retrato (`dbx_sync_retrato_entrada`, `dbx_sync_tabela_corpo`), confirmacao de exclusoes (`dbx_sync_confirmar_exclusoes`); **chamado por** commands/sync e, pela enumeracao completa, commands/verificar | `sync_tabela` (unidade; o filtro `sync` o casa) | `cursor`, `sync`, `verificar`, `filtros`, `qa_filtros_banda` (ponto unico de `server_modified`) |
| `lib/retencao.sh` (fase 6, RF-93 a RF-97) | errors, path, filtro | commands/reter | `retencao_test` (unidade: `--manter`/`--dias`, carimbo, data HTTP, politica pura com relogio fixado, propriedade, guarda por item; mutantes do minimo e da guarda do primeiro) | `reter_test` |
| `lib/compartilhamento.sh` (fase 5, DIV-117) | filtro (validacao de data de `--expira`); **chama** path (`dbx_path_remoto_confinar`) e json (`dbx_json_escapar_cadeia`) | commands/link_temporario, commands/compartilhar | `compartilhamento_test` (unidade: `--expira`, senha, URL, corpo, confinamento por `path_lower`, exposicao) | `compartilhar_test`, `completar` |
| `lib/lote.sh` (fase 9, F-08, RF-136, RF-137) | nenhum `source`: depende de auth, http, json, carregados pelo comando; **chama** auth (`dbx_auth_requisitar`), json (`dbx_json_*`), transfer (`dbx_transfer_conferir_resumo`) e **le canais de** http (`DBX_HTTP_CODIGO`, `_CLASSE`, `_CORPO`, `_RESUMO_*`) | commands/sync (`source`; `dbx_lote_excluir`, `dbx_lote_concluir_envio`, `DBX_LOTE_ENVIO_MAXIMO`); lib/transfer (limiar do pequeno para lote, sem `source`); o `reter` nao usa lote | `lote_test` (`dbx_lote_*`, conferencia por posicao, recuo do `check`) | `paralelo_test`, `sync`, `qa_desempenho`, `filtros`, `banda` |

### Fase 7b (F-14): cursor de listagem

`tests/integracao/cursor_test.sh` (filtro `cursor`) executa `bin/dbx` (sync `--receber` com e sem cursor, `--dry-run`, `--json`, `--null`, `--debug`, `--progresso`, `--enviar`, `verificar`, `download` de pasta, `unlink`, `diagnostico`, `help sync`) com duplo de `curl` por regras (endpoint, corpo do pedido, codigo, resposta; registro de cada pedido com o corpo) e `sleep` nulo; le `README.md` e `completions/dbx.bash`; audita o texto de `commands/sync.sh` (confirmacao antes do plano) e de `lib/sync.sh` (ponto unico da data remota). **Todo diff em `lib/state.sh`, `lib/sync.sh`, `commands/sync.sh`, `commands/download.sh`, `commands/diagnostico.sh`, `bin/dbx` (ajuda do `sync`), `completions/dbx.bash` ou no README (secao do cursor) seleciona `cursor`**, alem das linhas abaixo.

## Mapa por modulo: `commands/` e `bin/`

Nenhum comando tem teste unitario: todos sao exercitados por `bin/dbx` em testes ponta a ponta. Alem desta tabela, aplicar a Regra 1 (se o diff incluir `lib/`) e, para `commands/*.sh`, `cli` e `composicao`.

| Modulo | Carrega | Teste direto | Transitivo (executa `bin/dbx <cmd>`) |
|---|---|---|---|
| `bin/dbx` | errors, path, output, progress, cli (ajuda com `--esperar`, fase 2); sob demanda json, config, http, auth, cmd, preflight; **chama** `dbx_http_validar_ambiente` | `comandos` (`DBX_EXEC`), `completar` (ajuda como fonte unica das opcoes), `reter_test` (ajuda de `reter`, TC-CPL-11, TC-DOC-05) | `sync`, `verificar`, `diagnostico`, `espaco`, `qa_`, `confinamento_remoto` |
| `commands/config.sh` | **chama** cli (`dbx_cli_ler_oculto`, app secret, fase 5) | | `comandos`, `qa_docs_aliases`; raiz explicita no ponto unico auditada por `composicao` (fase 1b) |
| `commands/delete.sh` | | `comandos` (le o fonte) | `comandos`, `confinamento_remoto` |
| `commands/download.sh` | filtro (fase 4), transfer (limiar de 150 MiB, fase 7a); **chama** cmd (`dbx_cmd_filtros_preparar`, `dbx_cmd_limite_banda`; `dbx_cmd_receber_retomavel`, `dbx_cmd_retomada_limpar`, fase 7a) e auth (`get_metadata`, fase 7a) | | `comandos`, `qa_integridade`, `qa_robustez`, `confinamento_remoto`, `filtros` (TC-FES-19), `banda`, `retomada_download` |
| `commands/info.sh` | | | `comandos`, `confinamento_remoto` |
| `commands/list.sh` | | | `comandos`, `confinamento_remoto` |
| `commands/space.sh` | | | `comandos` |
| `commands/unlink.sh` | state (listagem de travas, fase 2; `.part` pela barreira, fase 7a) | | `comandos`, `qa_docs_aliases`, `trava` (TC-TRV-19, 20), `retomada_download` (TC-RML-05) |
| `commands/upload.sh` | transfer, state; **chama** path (`dbx_path_local_canonico`), hash (`dbx_hash_identidade`) e cmd (`dbx_cmd_espaco_checar`, fase 1 do backlog; `dbx_cmd_limite_banda`, fase 4; `dbx_cmd_retomada_preparar`, `dbx_cmd_retomada_limpar`, `dbx_cmd_avisar`, fase 7a) | | `comandos`, `espaco`, `completar`, `qa_`, `confinamento_remoto`, `banda`, `retomada_upload` |
| `commands/sync.sh` | walk, state, sync, transfer; **chama** path (`dbx_path_local_canonico`), cli (`dbx_cli_validar_espera`) e cmd (`dbx_cmd_ciclo_iniciar`, fase 2; `dbx_cmd_espaco_checar`, `dbx_cmd_caminho_exibivel`, fase 1 do backlog); **le canais de** http (`DBX_HTTP_REQUISICOES`, `DBX_HTTP_RESUMO_DO_SERVICO`, `DBX_HTTP_CODIGO`, `DBX_HTTP_CLASSE`) | `sync` (le o fonte), `tmp_test` (TC-CNF-01), `filtros` (fase 4: muta `_dbx_cmd_sync_protegido`, TC-FES-11) | `sync`, `trava`, `espaco`, `completar` (ajuda e opcoes), `qa_robustez`, `qa_cache_unico`, `qa_docs_aliases`, `confinamento_remoto`, `banda`, `filtros_ajuda` |
| `commands/verificar.sh` (fase 1 do backlog, RF-65) | walk, sync; **chama** cmd (`dbx_cmd_ciclo_iniciar`, fase 2), cli (`dbx_cli_validar_espera`) e auth | `tmp_test` (TC-CNF-01) | `verificar`, `trava`, `completar`, `qa_consulta_diagnostico`, `confinamento_remoto`, `filtros` (TC-FES-17, TC-FDT-12), `banda` (TC-BND-10) |
| `commands/diagnostico.sh` (fase 1 do backlog, RF-66) | preflight, sync; camada de credencial por `dbx_carregar_camada_de_credencial` (bin/dbx); **le canais de** auth (`DBX_AUTH_ESCOPOS*`), preflight (`DBX_PREFLIGHT_AUSENTES`) e state (`DBX_STATE_TRAVAS_*`, checagem `trava`, fase 2) | | `diagnostico` (o filtro casa tambem `diagnostico_compartilhamento`, TC-DIA-17..18, fase 5), `trava` (TC-DIA-11..14, TC-TRV-35), `completar`, `qa_consulta_diagnostico`, `retomada_download` (checagem `retomada`, TC-RML-06, 07, TC-RMC-06, fase 7a), `retomada_upload` (TC-RME-02) |
| `commands/completar.sh` (fase 1 do backlog, RF-68) | cmd; **le** `completions/dbx.bash` | | `completar`, `qa_consulta_diagnostico` |
| `commands/revisoes.sh` (fase 3 do backlog, RF-72) | **chama** cmd (`_dbx_cmd_caminho_remoto`, `_dbx_cmd_metadado_em`, `dbx_cmd_remoto_confinado`, `dbx_cmd_campo_caminho`) e auth | `recuperacao_test` (TC-RVS-01..08); ponto unico auditado por `composicao` | `completar` (TC-CPL-08) |
| `commands/restaurar.sh` (fase 3, RF-73, RF-74) | sync (`dbx_sync_ordem_sem_caixa`, so na pasta); **chama** cmd (`_dbx_cmd_escrita_remota` silencioso, `dbx_cmd_listar_nivel`, `dbx_cmd_remoto_confinado`), tmp (`dbx_tmp_acao_registrar`, resumo parcial no sinal) e auth | `recuperacao_test` (TC-RST-01..14, TC-RPA-01..10) | `completar` (TC-CPL-08) |
| `commands/lixeira.sh` (fase 3, RF-75, RF-76) | **chama** cmd (`dbx_cmd_listar_nivel`, `_dbx_cmd_escrita_remota` silencioso, `dbx_cmd_remoto_confinado`) e auth | `recuperacao_test` (TC-LIX-01..07, TC-EXP-01..14, TC-DOC-02; usa `script(1)` para o terminal de TC-EXP-05 e pula sem ele) | `completar` (TC-CPL-08) |
| `commands/link_temporario.sh` (fase 5, RF-84; nomes `link-temporario` e `temp-link`) | compartilhamento; **chama** cmd (`_dbx_cmd_caminho_remoto`, `_dbx_cmd_consultar`, `_dbx_cmd_metadado_em`) e auth | `compartilhar_test` (TC-LTP-01..10; ordem do ponto unico conferida no proprio arquivo, DIV-121) | `completar` (TC-CPL-10 em `compartilhar_test`) |
| `commands/reter.sh` (fase 6, RF-93 a RF-99; alias `retain`) | retencao; **chama** cmd (`_dbx_cmd_caminho_remoto`, `_dbx_cmd_escrita_remota` silencioso e idempotente, `dbx_cmd_caminho_exibivel`), auth (`dbx_auth_colecao`, `dbx_auth_requisitar`, `dbx_auth_preparar`), tmp (`dbx_tmp_acao_registrar`, resumo no sinal); **le canais de** http (`DBX_HTTP_DATA`, DIV-134) | `reter_test` (TC-RTA, TC-RTS, TC-RTP, TC-RTC, TC-RTG, TC-RTX, TC-RTO; mutantes em copia do produto; `script(1)` em TC-RTC-05, pula sem ele) | `completar` (TC-CPL-11 em `reter_test`) |
| `commands/compartilhar.sh` (fase 5, RF-85 a RF-90; alias `share`) | compartilhamento; **chama** cli (`dbx_cli_ler_oculto`), tmp (`dbx_tmp_armar`), cmd (`_dbx_cmd_caminho_remoto`, `_dbx_cmd_escrita_remota` silencioso e idempotente) e auth | `compartilhar_test` (TC-CMP, TC-SNH com `script(1)` e pula sem ele, TC-LEX, TC-LST, TC-RVG, TC-SHE) | `completar` |
| `commands/perfis.sh` (fase 8, RF-126, F-18; alias `profiles`) | nenhum `source`; **chama** config (`dbx_config_perfis_listar`, `DBX_CONFIG_PERFIS_*`), cmd (`dbx_cmd_falhar`, `dbx_cmd_iniciar_saida`, `dbx_cmd_campo_caminho`), output (`dbx_output_campo`, `dbx_output_render`) e `dbx_carregar_camada_de_credencial` (bin/dbx); so le, requisito `ambiente` | `perfis_test` (ponta a ponta), `perfis_cli_test` (tabela de comandos e alias, `lib/cli`) | `perfis_unlink`, `perfis_trava_raiz`, `qa_perfis`, `completar` |

## Testes da fase 9 do backlog (desempenho, F-08, F-09, F-34)

Conferido por `ls tests/unit tests/integracao tests/support` e `grep -o 'lib/...'` em cada arquivo.

| Arquivo | Filtro proprio | Carrega / executa | Selecionado por diff em |
|---|---|---|---|
| `tests/integracao/lote_test.sh` (fase 9, RF-136, RF-137) | `lote_test` (o filtro `lote` tambem o casa) | carrega `lib/errors`, `hash`, `progress`, `tmp`, `filtro`, `transfer`, `lote` e `tests/support/lote_duplo.sh`; `bin/dbx` (sync `--espelhar` e envio em lote); le `commands/sync.sh` e `commands/reter.sh` (reter nao usa lote) | `lib/lote.sh`, `lib/transfer.sh`, `commands/sync.sh`, `bin/dbx`, `tests/support/lote_duplo.sh` |
| `tests/integracao/paralelo_test.sh` (fase 9, F-09, RF-133 a RF-135) | `paralelo` (o filtro `paralelo_test` tambem) | `bin/dbx sync` com N=1 e N>1, duplo de `curl` que mede o pico de transferencias simultaneas; audita o texto de `commands/sync.sh`; carrega `lib/errors.sh` | `bin/dbx`, `commands/sync.sh`, `lib/transfer.sh`, `lib/cmd.sh`, `lib/http.sh`, `lib/lote.sh`, `lib/cli.sh` |

Suporte de teste: `tests/support/lote_duplo.sh` (duplo compartilhado dos endpoints de lote) e carregado por `lote_test`, `qa_desempenho_b9` e, conforme `grep -ln lote_duplo tests/*/*.sh`, por `banda`, `qa_cache_unico`, `espaco`, `qa_robustez`, `filtros`, `qa_integridade`, `comandos`, `qa_filtros_banda`, `qa_docs_aliases` e `sync`. **Diff nele seleciona esses doze** (alem de `harness` por `tests/support/*`).

Diff em `lib/lote.sh` aplica tambem a Regra 1, que cobre a lib nova sem mudar as tabelas dela, e seleciona `lote`, `paralelo` e `qa_desempenho`.

## Testes da fase 8 do backlog (perfis de credencial, F-18)

Conferido por `ls tests/unit tests/integracao tests/support` e `grep -o 'lib/...'` em cada arquivo. Nenhum filtro existente casa `perfis_*` por substring, exceto onde indicado.

| Arquivo | Filtro proprio | Carrega / executa | Selecionado por diff em |
|---|---|---|---|
| `tests/unit/perfis_config_test.sh` (fase 8) | `perfis_config` (o filtro `config` tambem o casa; `perfis` casa os seis) | carrega `lib/errors`, `json`, `config` | `lib/config.sh`, `lib/json.sh`, `lib/errors.sh` |
| `tests/unit/perfis_cli_test.sh` (fase 8) | `perfis_cli` (o filtro `cli` tambem o casa) | carrega `lib/errors`, `json`, `path`, `output`, `config`, `cli` | `lib/cli.sh`, `lib/config.sh`, `lib/output.sh`, `lib/path.sh`, `lib/json.sh`, `lib/errors.sh` |
| `tests/unit/state_trava_raiz_test.sh` (fase 8, RF-132) | `state_trava_raiz` (os filtros `state_trava`, `state` e `trava` tambem o casam) | processos proprios com `lib/errors`, `json`, `config`, `state`; disputantes reais da trava por raiz | `lib/state.sh`, `lib/config.sh`, `lib/json.sh`, `lib/errors.sh` |
| `tests/integracao/perfis_test.sh` (fase 8) | `perfis_test` (o filtro `perfis` tambem o casa) | `bin/dbx` (perfis, profiles, config com perfil, help); carrega `lib/errors.sh` | `bin/dbx`, `commands/perfis.sh`, `commands/config.sh`, `lib/config.sh`, `lib/cli.sh`, `lib/preflight.sh`, `lib/output.sh` |
| `tests/integracao/perfis_trava_raiz_test.sh` (fase 8) | `perfis_trava_raiz` (os filtros `trava` e `perfis` tambem o casam) | `bin/dbx sync --receber` com processo que detem a trava de raiz; carrega `lib/errors`, `json`, `config`, `state` | `bin/dbx`, `commands/sync.sh`, `lib/state.sh`, `lib/config.sh` |
| `tests/integracao/perfis_unlink_test.sh` (fase 8) | `perfis_unlink` (o filtro `unlink` tambem o casa) | `bin/dbx unlink` com perfis; carrega `lib/errors`, `tmp`, `hash`, `json`, `config`, `state` | `bin/dbx`, `commands/unlink.sh`, `lib/state.sh`, `lib/config.sh`, `lib/tmp.sh` |

Diff em `commands/perfis.sh` seleciona `cli`, `composicao` e `tmp_test` (auditorias de `commands/*.sh`) mais `perfis` e `completar`.

## Testes da fase 7a do backlog (retomada entre execucoes, F-03)

| Arquivo | Filtro proprio | Carrega / executa | Selecionado por diff em |
|---|---|---|---|
| `tests/unit/retomada_estado_test.sh` | `retomada_estado` | em processo isolado, `lib/errors`, `json`, `config`, `state` (e `hash`, `tmp` por ele): registro `retomada-*` (formato NUL v1, chave com NUL, leitor limitado, descarte, barreira do `.part`, trava de registro, poda, listagem) e leitor limitado do `upload-*` (TC-UPC-13, bytes lidos medidos por `/proc/self/io`) | `lib/state.sh`, `lib/hash.sh`, `lib/tmp.sh`, `lib/config.sh`, `lib/errors.sh` |
| `tests/integracao/retomada_upload_test.sh` | `retomada_upload` | `bin/dbx` (upload retomado, `--sem-retomada`/`--no-resume`, `--json`, `--null`, `--debug`, `--dry-run`, texto por `script(1)`, help, diagnostico, sync e list com a opcao) com duplo de `curl` que e servidor de sessao com estado (`content_hash` calculado sobre as partes recebidas), duplos de `stat` (identidade forjada), `head` (bytes lidos da origem), `mktemp` (gravacao do registro que falha) e `sleep`; sinais e `kill -9` pelo duplo; execucoes simultaneas reais; copias mutantes de `lib/transfer`, `lib/state` e `lib/cmd` | `bin/dbx`, `commands/upload.sh`, `commands/diagnostico.sh`, `lib/transfer.sh`, `lib/state.sh`, `lib/cmd.sh`, `lib/hash.sh`, `lib/http.sh`, `lib/auth.sh`, `lib/tmp.sh`, `lib/output.sh`, `completions/dbx.bash`, `README.md` |
| `tests/integracao/retomada_download_test.sh` | `retomada_download` | `bin/dbx` (download retomado por `Range`, `--no-resume`, diagnostico, unlink) com duplo de `curl` que segue o contrato medido do cliente para `continue-at` (anexo, status 33 sem escrita, `416`), duplos de `stat` (troca do nome entre a conferencia e a abertura) e `mktemp`; sinais pelo duplo; execucoes simultaneas reais; copias mutantes de `lib/cmd` e `lib/state` | `bin/dbx`, `commands/download.sh`, `commands/unlink.sh`, `commands/diagnostico.sh`, `lib/cmd.sh`, `lib/state.sh`, `lib/http.sh`, `lib/auth.sh`, `lib/hash.sh`, `lib/tmp.sh`, `lib/transfer.sh` (limiar) |

O filtro `retomada` seleciona os tres. Diff em `lib/*.sh` da fase 7a aplica tambem a Regra 1; diff em `commands/*.sh`, `cli`, `composicao` e `tmp_test`. Diff em `lib/state.sh` seleciona tambem `state` (o filtro casa `state_test`, `state_trava_test` e `qa_state`), `trava` e `qa_trava_tmp`; em `lib/transfer.sh`, `transfer` e `qa_rede`; em `lib/http.sh` ou `lib/auth.sh`, `http`, `auth`, `banda` e `qa_robustez`; em `commands/download.sh` ou `commands/upload.sh`, `comandos`, `qa_integridade`, `qa_cache_unico`, `qa_pendencias_p0`, `confinamento_remoto` e `banda`; em `commands/diagnostico.sh`, `diagnostico`; em `commands/unlink.sh`, `qa_docs_aliases`; em `bin/dbx` ou `completions/dbx.bash`, `completar`.

## Testes da fase 6 do backlog (retencao e rotacao de backup)

| Arquivo | Filtro proprio | Carrega / executa | Selecionado por diff em |
|---|---|---|---|
| `tests/unit/retencao_test.sh` | `retencao_test` | carrega `lib/errors`, `path`, `filtro`, `retencao`; em processo isolado, `lib/http` (cabecalho `Date`) e copias mutantes de `lib/retencao` | `lib/retencao.sh`, `lib/filtro.sh`, `lib/http.sh`, `lib/path.sh`, `lib/errors.sh` |
| `tests/integracao/reter_test.sh` | `reter_test` | `bin/dbx` (reter e retain nos tres modos, `--dry-run`, `--json`, `--null`, `--debug`, help) com duplo de `curl` por regra (registro de endpoint e corpo, cabecalho `Date`, `@PATH@`, sinal ao `dbx`, regra `uma` atomica), duplos de `date` (proibido) e `sleep` (registra a espera); `setsid` e `timeout` no `_rodar`; execucoes simultaneas reais; copias mutantes de `commands/reter.sh`, `lib/retencao.sh` e `lib/cmd.sh`; `script(1)` em TC-RTC-05 (pula sem ele); carrega `lib/errors.sh`, `lib/filtro.sh`; le `completions/dbx.bash`, `README.md`, este mapa e o texto de `commands/reter.sh`, `lib/retencao.sh` e `commands/diagnostico.sh` | `bin/dbx`, `commands/reter.sh`, `completions/dbx.bash`, `lib/retencao.sh`, `lib/filtro.sh`, `lib/cli.sh`, `lib/cmd.sh`, `lib/http.sh`, `lib/auth.sh`, `lib/json.sh`, `lib/path.sh`, `lib/tmp.sh`, `lib/output.sh`, `lib/errors.sh`, `README.md`, `docs/testes/mapa-modulos.md` |

Diff em `lib/*.sh` da fase 6 aplica tambem a Regra 1; `lib/retencao.sh` entra pelas auditorias de diretorio sem mudar as tabelas dela. Diff em `commands/*.sh` seleciona `cli`, `composicao` e `tmp_test`; diff em `lib/filtro.sh` seleciona tambem `filtro`, `filtros`, `retencao_test` e `reter_test`; em `lib/http.sh`, tambem `retencao_test` e `reter_test`.

## Testes da fase 5 do backlog (link temporario e link compartilhado)

| Arquivo | Filtro proprio | Carrega / executa | Selecionado por diff em |
|---|---|---|---|
| `tests/unit/compartilhamento_test.sh` | `compartilhamento_test` | carrega `lib/errors`, `path`, `json`, `cli`, `compartilhamento` (e `filtro` por ele) | `lib/compartilhamento.sh`, `lib/filtro.sh`, `lib/errors.sh`, `lib/cli.sh`, `lib/path.sh`, `lib/json.sh` |
| `tests/integracao/compartilhar_test.sh` | `compartilhar_test` | `bin/dbx` (link-temporario, temp-link, compartilhar, share em todos os modos, `--dry-run`, `--json`, `--null`, `--debug`) com duplo de `curl` por regra que registra corpo, `argv` (o dele e dos processos acima), ambiente e a entrada `-K -`; duplo de `date` proibido; `setsid` para o `TERM`; `script(1)` e `mkfifo` para o terminal de TC-SNH (pula sem `script`); carrega `lib/errors.sh`; le `completions/dbx.bash`, `README.md`, este mapa e o texto de `commands/link_temporario.sh` e `commands/compartilhar.sh` | `bin/dbx`, `commands/link_temporario.sh`, `commands/compartilhar.sh`, `commands/config.sh`, `completions/dbx.bash`, `lib/compartilhamento.sh`, `lib/cli.sh`, `lib/cmd.sh`, `lib/tmp.sh`, `lib/http.sh`, `lib/auth.sh`, `lib/json.sh`, `lib/path.sh`, `lib/errors.sh`, `lib/output.sh`, `README.md`, `docs/testes/mapa-modulos.md` |
| `tests/integracao/diagnostico_compartilhamento_test.sh` | `diagnostico_compartilhamento` (o filtro `diagnostico` tambem o casa) | `bin/dbx diagnostico` com o `scope` da renovacao variando `sharing.write` e `sharing.read` | `commands/diagnostico.sh`, `lib/auth.sh`, `bin/dbx` |

Diff em `lib/*.sh` da fase 5 aplica tambem a Regra 1; `lib/compartilhamento.sh` entra pelas auditorias de diretorio sem mudar as tabelas dela. Diff em `commands/*.sh` seleciona `cli`, `composicao` e `tmp_test`.

## Testes da fase 4 do backlog (filtros e limite de banda)

| Arquivo | Filtro proprio | Carrega / executa | Selecionado por diff em |
|---|---|---|---|
| `tests/unit/filtro_test.sh` | `filtro_test` (o filtro `filtro` casa tambem `filtros` e `filtros_ajuda`) | carrega `lib/errors.sh` e `lib/filtro.sh`; processos proprios sob `LC_ALL=C`, `TZ` e localidade ausente | `lib/filtro.sh`, `lib/errors.sh` |
| `tests/integracao/filtros_test.sh` | `filtros_test` | `bin/dbx` (sync nos dois sentidos, `--dry-run`, `--json --null`, verificar, download de pasta e de arquivo, upload, list, info, restaurar, lixeira) com duplos de `curl` (registro de URL e corpo), `rm` e `date`; copias mutantes de `lib/sync.sh` e `commands/sync.sh` (TC-FES-11) | `lib/filtro.sh`, `lib/walk.sh`, `lib/sync.sh`, `lib/cmd.sh`, `lib/http.sh`, `commands/sync.sh`, `commands/verificar.sh`, `commands/download.sh`, `bin/dbx` |
| `tests/integracao/banda_test.sh` | `banda` | `bin/dbx` (upload de arquivo e de fluxo, download de arquivo, de fluxo e de pasta, sync nos dois sentidos, verificar, list, info, space) com duplo de `curl` que registra `limit-rate` e `argv` por chamada | `lib/http.sh`, `lib/cli.sh`, `lib/cmd.sh`, `lib/transfer.sh`, `commands/upload.sh`, `commands/download.sh`, `commands/sync.sh`, `commands/verificar.sh`, `bin/dbx` |
| `tests/integracao/filtros_ajuda_test.sh` | `filtros_ajuda` | `bin/dbx help` (sync, verificar, download, upload, lixeira), `completions/dbx.bash`; le `README.md` e este mapa | `bin/dbx`, `completions/dbx.bash`, `README.md`, `docs/testes/mapa-modulos.md`, `commands/*.sh` com opcao nova |

Diff em `lib/*.sh` da fase 4 aplica tambem a Regra 1. `lib/filtro.sh` entra pelas auditorias de diretorio sem mudar as tabelas da Regra 1.

## Testes da fase 3 do backlog (revisoes, restauracao e lixeira)

| Arquivo | Filtro proprio | Carrega / executa | Selecionado por diff em |
|---|---|---|---|
| `tests/integracao/recuperacao_test.sh` | `recuperacao` | `bin/dbx` (revisoes, restaurar, lixeira e os aliases, `--dry-run`, `--json --null`, `--debug`) com duplo de `curl` por regra (endpoint e corpo) e registro de chamadas; `setsid` para o `TERM` de TC-RPA-10; `script(1)` para TC-EXP-05; carrega `lib/errors.sh`; le `README.md` | `bin/dbx`, `commands/revisoes.sh`, `commands/restaurar.sh`, `commands/lixeira.sh`, `lib/cmd.sh`, `lib/sync.sh`, `lib/errors.sh`, `lib/http.sh`, `lib/auth.sh`, `lib/json.sh`, `lib/path.sh`, `lib/output.sh`, `lib/tmp.sh`, `lib/cli.sh`, `README.md` |

Casos novos em arquivos existentes: `errors_test` (DIV-58), `diagnostico_test` (TC-DIA-15..16), `completar_test` (TC-CPL-08) e `composicao_test` (ponto unico dos tres comandos).

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
