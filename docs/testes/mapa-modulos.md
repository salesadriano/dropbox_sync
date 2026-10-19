# Mapa de modulos de teste

Mantido pelo QA Expert (Regra 8 de `protocolo-tdd`; detalhamento em `.github/skills/protocolo-tdd/references/execucao-por-modulo.md`). Levantado em 2026-10-18 (fase P2, achado QA-05 da P1) a partir do codigo, sem interpretacao.

## Origem das linhas

- **Modulo = arquivo.** Cada arquivo de `lib/`, `commands/` e `bin/` e um modulo; nao ha agrupamento por semelhanca de nome, entao nao ha separacao a pedir ao solicitante.
- **Dependencia automatica**, lida do codigo: `. "$dir/x.sh"` entre `lib/*.sh`, `commands/*.sh` e `bin/dbx`; e `. "$DBX_HARNESS_RAIZ/lib/x.sh"` nos testes. **Dependencia por chamada** (sem `source`, levantada na P2 por `grep -n 'dbx_http_\|DBX_HTTP_' lib/cmd.sh lib/transfer.sh commands/sync.sh bin/dbx`): marcada em negrito como "chama" ou "le canais de".
- **Direto** = o teste carrega o modulo (ou o audita por caminho). **Transitivo** = o teste exercita o modulo por um dependente (outra lib ou `bin/dbx`).
- Comando do teste: `bash tests/run.sh <filtro>`. O filtro e **um** trecho do nome do arquivo (`tests/run.sh` aceita um unico argumento; casa por substring em `tests/unit/` e `tests/integracao/`). Filtro sem correspondencia REPROVA.

## Regra 1: auditorias de diretorio (todo diff em `lib/*.sh`)

Estes testes varrem `lib/*.sh` inteiro e portanto cobrem arquivo novo sem alterar o mapa. **Todo diff em `lib/*.sh` seleciona `json`, `http`, `preflight` e `composicao`**, qualquer que seja a lib alterada:

| Teste | Auditoria (linhas) |
|---|---|
| `tests/unit/json_test.sh` | capturas e uso de `lib/*.sh` (495, 506) |
| `tests/unit/http_test.sh` | `lib/*.sh` (103) |
| `tests/unit/preflight_test.sh` | variaveis, vocabulario e comandos externos de `lib/*.sh` (347-354) |
| `tests/integracao/composicao_test.sh` | `lib/*.sh` (549, 602); `commands/*.sh` e `lib/cmd.sh` (657) |

Conferido por `grep -l 'lib/\*.sh' tests/unit/*.sh tests/integracao/*.sh`: apenas esses quatro. Auditorias de `commands/*.sh`: `cli_test` (150, 166, 201) e `composicao_test` (657). **Todo diff em `commands/*.sh` seleciona `cli` e `composicao`.**

## Regra 2: testes `qa_*`

Teste `qa_*` novo entra no mapa na criacao. O filtro `qa_` seleciona os cinco de uma vez; para um so, use o filtro proprio da tabela. O filtro `state` casa tambem `qa_state_p3` (substring), o que e desejado: diff em `lib/state.sh` seleciona os dois.

| Arquivo | Filtro proprio | Carrega / executa | Selecionado por diff em |
|---|---|---|---|
| `tests/integracao/qa_integridade_p1_test.sh` (P1) | `qa_integridade` | `bin/dbx` (download 12x, upload 1x); carrega `lib/errors.sh`, `lib/hash.sh` | `bin/dbx`, `commands/download.sh`, `commands/upload.sh`, `lib/transfer.sh`, `lib/hash.sh`, `lib/http.sh`, `lib/progress.sh`, `lib/state.sh`, `lib/path.sh` |
| `tests/unit/qa_rede_p2_test.sh` (P2) | `qa_rede` | carrega `lib/errors`, `json`, `http`, `auth`, `hash`, `transfer` (e `progress` por eles); copia e executa `tests/run.sh` e `tests/support/harness.sh` | `lib/http.sh`, `lib/transfer.sh`, `lib/json.sh`, `lib/auth.sh`, `lib/hash.sh`, `lib/errors.sh`, `lib/progress.sh`, `tests/run.sh`, `tests/support/harness.sh` |
| `tests/integracao/qa_robustez_rede_p2_test.sh` (P2) | `qa_robustez` | `bin/dbx` (download, upload, sync, space); carrega `lib/errors.sh`, `lib/hash.sh` | `bin/dbx`, `commands/download.sh`, `commands/sync.sh`, `commands/upload.sh`, `lib/http.sh`, `lib/cmd.sh`, `lib/transfer.sh`, `lib/output.sh`, `lib/auth.sh`, `lib/config.sh`, `lib/errors.sh`, `lib/hash.sh`, `lib/sync.sh`, `lib/walk.sh`, `lib/state.sh` |
| `tests/integracao/qa_cache_unico_p3_test.sh` (fase 3) | `qa_cache_unico` | `bin/dbx` (sync nos dois sentidos, upload); carrega `lib/errors.sh`, `lib/hash.sh`; audita o texto de `install.sh`, `README.md`, `bin/`, `lib/`, `commands/` | `bin/dbx`, `commands/sync.sh`, `commands/upload.sh`, `lib/state.sh`, `lib/hash.sh`, `lib/walk.sh`, `lib/path.sh`, `lib/sync.sh`, `lib/auth.sh`, `lib/config.sh`, `lib/http.sh`, `lib/errors.sh`, `lib/transfer.sh`, `lib/cmd.sh`, `install.sh`, `README.md` |
| `tests/unit/qa_state_p3_test.sh` (fase 3) | `qa_state` | carrega `lib/errors`, `json`, `config`, `state` (e `hash` por ele), `http`, `auth` | `lib/state.sh`, `lib/hash.sh`, `lib/config.sh`, `lib/json.sh`, `lib/http.sh`, `lib/auth.sh`, `lib/errors.sh`, `lib/progress.sh` |

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
| `lib/hash.sh` | errors | cmd, state, transfer, walk; **chamado por** commands/upload e commands/sync (`dbx_hash_identidade`, fase 3) | `hash`, `hash_vetor_oficial`, `transfer`, `walk`, `state`, `cmd` | `comandos`, `sync`, `qa_` |
| `lib/json.sh` | errors | config, http | `json`, `config`, `http`, `auth`, `cabecalho`, `transfer`, `state`, `cmd` | `comandos` |
| `lib/path.sh` | errors | output; **chamado por** commands/upload e commands/sync (`dbx_path_local_canonico`) | `path`, `output`, `cli`, `cabecalho`, `cmd` | `comandos`, `sync` |
| `lib/output.sh` | errors, path; **le canais de** auth e config por nome (`DBX_AUTH_TOKEN`, `DBX_AUTH_REFRESH_TOKEN`, `DBX_CONFIG_REFRESH_TOKEN`, `DBX_CONFIG_APP_SECRET`) | bin/dbx; **chamado por** commands/sync (`dbx_output_mascarar_segredos`) | `output`, `cli`, `composicao`, `cmd` | `comandos`, `sync`, `qa_robustez` (fase P2: todo diagnostico passa pela mascaracao por valor) |
| `lib/progress.sh` | | http, sync, transfer, bin/dbx | `progress`, `transfer`, `http`, `cmd` | `comandos`, `sync`, `qa_` |
| `lib/cli.sh` | | bin/dbx | `cli` | `comandos` |
| `lib/config.sh` | errors, json | bin/dbx; **chamado por** state (`dbx_config_caminho_de_estado`) | `config`, `state`, `cmd` | `comandos` |
| `lib/http.sh` | errors, json, progress | bin/dbx; **chamado (sem `source`) por** cmd e transfer; canais lidos por commands/sync | `http`, `auth`, `cabecalho`, `transfer`, `qa_rede`, `cmd` | `comandos`, `sync`, `qa_` |
| `lib/auth.sh` | | bin/dbx | `auth`, `transfer`, `cmd`, `qa_state` (RF-63) | `comandos`, `qa_cache_unico` |
| `lib/cmd.sh` | hash; **chama** http (`dbx_http_interrompido`, `dbx_http_sinais_devolver`) | bin/dbx | `cmd` (fase 3, RNF-32(d)); auditado por `composicao` | `comandos`, `sync`, `cli`, `qa_robustez` |
| `lib/preflight.sh` | errors | bin/dbx (linha 185) | `preflight` | `comandos` |
| `lib/transfer.sh` | errors, hash, progress; **chama** http (`dbx_http_interrompido`, `dbx_http_sinais_devolver`, `DBX_HTTP_EFETIVO`) | commands/sync, commands/upload | `transfer`, `qa_rede` | `comandos`, `sync`, `qa_` |
| `lib/walk.sh` | errors, hash | commands/sync | `walk` | `sync` |
| `lib/state.sh` | errors, hash; **chama** config (`dbx_config_caminho_de_estado`) | commands/sync, commands/upload | `state` (fase 3, RNF-32(d)), `qa_state` | `sync`, `comandos`, `qa_cache_unico` |
| `lib/sync.sh` | progress | commands/sync | `sync` (so audita o texto, nao carrega) | `sync` |

## Mapa por modulo: `commands/` e `bin/`

Nenhum comando tem teste unitario: todos sao exercitados por `bin/dbx` em testes ponta a ponta. Alem desta tabela, aplicar a Regra 1 (se o diff incluir `lib/`) e, para `commands/*.sh`, `cli` e `composicao`.

| Modulo | Carrega | Teste direto | Transitivo (executa `bin/dbx <cmd>`) |
|---|---|---|---|
| `bin/dbx` | errors, path, output, progress, cli; sob demanda json, config, http, auth, cmd, preflight; **chama** `dbx_http_validar_ambiente` | `comandos` (`DBX_EXEC`) | `sync`, `qa_` |
| `commands/config.sh` | | | `comandos` |
| `commands/delete.sh` | | `comandos` (le o fonte) | `comandos` |
| `commands/download.sh` | | | `comandos`, `qa_integridade`, `qa_robustez` |
| `commands/info.sh` | | | `comandos` |
| `commands/list.sh` | | | `comandos` |
| `commands/space.sh` | | | `comandos` |
| `commands/unlink.sh` | | | `comandos` |
| `commands/upload.sh` | transfer, state; **chama** path (`dbx_path_local_canonico`) e hash (`dbx_hash_identidade`) | | `comandos`, `qa_` |
| `commands/sync.sh` | walk, state, sync, transfer; **chama** path (`dbx_path_local_canonico`); **le canais de** http (`DBX_HTTP_REQUISICOES`, `DBX_HTTP_RESUMO_DO_SERVICO`, `DBX_HTTP_CODIGO`, `DBX_HTTP_CLASSE`, `DBX_HTTP_TRATADOR_EXTERNO`) | `sync` (le o fonte) | `sync`, `qa_robustez` |

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
