# Inventario de testes - dropbox_sync

Atualizado em: 2026-10-31, demanda `investigar-retomada-download` (`docs/prompts/2026-10-31_1900_investigar-retomada-download.md`), pelo Tech Lead (Fluxo P: linhas do `harness_test.sh`); antes, demanda `sync-em-blocos`, por QA Expert.
Conferencia: `sh scripts/inventario-de-testes.sh --check` -> 111 arquivos, 2833 casos, 0 divergencias.
Comando da suite completa: `sh scripts/suite-completa.sh -- bash tests/run.sh` (Regra 8 de `protocolo-tdd`). Mapa de modulos: [`docs/testes/mapa-modulos.md`](mapa-modulos.md).

## Como ler

Os testes rodam pelo harness proprio `tests/run.sh` (TAP 13, parada no primeiro erro); cada caso e uma funcao `teste_<nome>()` num arquivo `*_test.sh`, e e esse nome que a coluna *Caso* traz. **Unitario** (`tests/unit/`) carrega as libs de `lib/` e exercita funcoes isoladas; **integracao** (`tests/integracao/`) roda `bin/dbx` ponta a ponta com o `curl` substituido por um duble (sem rede real), salvo onde *Dados e precondicoes* diz outra coisa. Arquivos `qa_*` sao suites independentes do QA Expert, aceitas pelo solicitante por sha256 (regra 12): o campo *Aceite do solicitante* aponta o registro do aceite. Para rodar um arquivo isolado, use o *Comando* do bloco. Arquivos anteriores a trilha do protocolo trazem *Regras de origem* `Nao aplicavel: anterior a trilha do protocolo` e o comportamento descrito a partir do proprio teste.

## Resumo

| Arquivo | Alvo | Modulo | Camada | Autoria | Casos | Regras de origem principais |
|---|---|---|---|---|---|---|
| `tests/integracao/banda_test.sh` | `bin/dbx` com `lib/cli.sh` (`dbx_cli_validar_taxa`), `lib/cmd.sh` e `lib/http.sh`: limite de banda (`--limite-banda`, `--bwlimit`, `DBX_L... | `bin/dbx` | integracao | Senior Developer (TDD da demanda `backlog-fase-4-filtros-e-banda`) | 13 | RF-82; TC-BND-01..14; log `docs/prompts/2026-10-19_2141_backlog-fase-4-filtros-e-banda.md` |
| `tests/integracao/bloco_cli_test.sh` | `bin/dbx` com `--bloco`/`--batch` e `DBX_BLOCO`: validacao antes de rede e estado | `bloco_cli_test` | integracao | Senior Developer (TDD da demanda `sync-em-blocos`) | 6 | RF-186; F-101; TC-BLC-nn |
| `tests/integracao/comandos_test.sh` | `bin/dbx` ponta a ponta (entrada, opcoes globais, credencial, autenticacao, transporte, analise e saida) e os comandos `upload`, `downloa... | `comandos` (filtro do mapa de modulos; arquivo `tests/integracao/comandos_test.sh`) | integracao | Senior Developer (TDD; commit de criacao b2179b4 `feat(comandos): entrada fina com despacho por tabela literal`, anterior a trilha de log... | 119 | Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste |
| `tests/integracao/compartilhar_test.sh` | `bin/dbx` nos comandos `link-temporario` (`temp-link`) e `compartilhar` (`share`) em todos os modos (criar, reusar, modificar, `--listar`... | compartilhar_test | integracao | Senior Developer (TDD da demanda `backlog-fase-5-compartilhamento`) | 83 | F-15; F-16; RF-84..RF-92; RF-86(g); TC-LTP; TC-CMP; TC-SNH; TC-LEX; TC-LST; TC-RVG; TC-SHE; TC-CPL-10; TC-DOC-04; TC-TST-08; DIV-117; DIV... |
| `tests/integracao/completar_test.sh` | `completions/dbx.bash`, `commands/completar.sh` (`dbx completar bash`), `install.sh`, `uninstall.sh` e `scripts/empacotar.sh`, confrontad... | completar | integracao | Senior Developer (TDD da demanda `backlog-fase-1-consulta-diagnostico`) | 17 | RF-68; TC-CPL-01..08; log `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md` |
| `tests/integracao/composicao_test.sh` | `lib/*.sh`, `commands/*.sh` e `lib/cmd.sh` em composicao (auditorias entre componentes: ponto unico do caminho remoto, taxonomia de saida... | `composicao` | integracao | Senior Developer (TDD; commit `f4e645d` "test: auditoria de procedencia e suite de integracao", sem log de prompt) | 28 | QF-01 (defeito que so existia em cadeia); RNF-24 (auditoria de procedencia); `docs/testes/mapa-modulos.md` (Regra 1: todo diff em `lib/*.... |
| `tests/integracao/confinamento_remoto_test.sh` | `bin/dbx` (todos os comandos com caminho remoto), `lib/cmd.sh` (`dbx_cmd_remoto_confinado`), `lib/path.sh`: confinamento a `raiz_remota` ... | confinamento_remoto | integracao | Senior Developer (TDD da demanda `backlog-fase-1b-confinamento-remoto`) | 12 | F-36, RNF-20(b1..b6), TC-SEC-18..27; F-37, RNF-10(b), TC-SEC-28..29; protocolo-tdd Regra 6 (cenarios negativos de acesso); log `docs/prom... |
| `tests/integracao/cursor_test.sh` | `bin/dbx sync --receber` com cursor de listagem (`commands/sync.sh`, `lib/state.sh`, `lib/sync.sh`), incluindo `--dry-run`, `--json`, `--... | `cursor` | integracao | Senior Developer (TDD da demanda `backlog-fase-7b-cursor`) | 48 | RF-110..RF-119; TC-CUA, TC-CUR, TC-CUV, TC-CUF, TC-CUD, TC-CUM, TC-CUS, TC-CUL, TC-CUO; F-14; parecer do DBA (C1 a C11); log `docs/prompt... |
| `tests/integracao/debug_ajuda_progresso_test.sh` | `bin/dbx` (`--debug`/`DBX_DEBUG` em upload, ajuda, README e completions), `lib/progress.sh`, `commands/upload.sh` | debug_ajuda | integracao | Senior Developer (TDD da demanda `debug-transferencias`) | 9 | RF-156; RF-159(d); RF-165; TC-DBG-33..35; log `docs/prompts/2026-10-24_0330_debug-transferencias.md` |
| `tests/integracao/debug_http_test.sh` | `bin/dbx` (upload, download e sync com `--debug`), `lib/http.sh` e `lib/progress.sh`: linha de depuracao por tentativa HTTP e resumo | `debug_http` | integracao | Senior Developer (TDD da demanda `debug-transferencias`) | 20 | RF-156; RF-157; RF-162; RF-163; RF-164; TC-DBG-01..07; TC-DBG-22..32; log `docs/prompts/2026-10-24_0330_debug-transferencias.md` |
| `tests/integracao/debug_sync_test.sh` | `bin/dbx sync` com `--debug` (`commands/sync.sh`, `lib/sync.sh`, `lib/transfer.sh`) | debug_sync | integracao | Senior Developer (TDD da demanda `debug-transferencias`) | 8 | RF-158(b); RF-159(a)(d); RF-161; RF-164; TC-DBG-17..20; TC-DBG-25; log `docs/prompts/2026-10-24_0330_debug-transferencias.md` |
| `tests/integracao/debug_transferencia_test.sh` | `bin/dbx upload` e `bin/dbx download` com `--debug` (etapas de transferencia), `lib/transfer.sh`, `lib/cmd.sh` | debug_transferencia | integracao | Senior Developer (TDD da demanda `debug-transferencias`) | 5 | RF-159, RF-160, RF-164; TC-DBG-08, 09, 16, 24; log `docs/prompts/2026-10-24_0330_debug-transferencias.md` |
| `tests/integracao/diagnostico_compartilhamento_test.sh` | `bin/dbx diagnostico` (`commands/diagnostico.sh`, `lib/auth.sh`): linha `escopos` com os escopos opcionais de compartilhamento | `diagnostico_compartilhamento` | integracao | Senior Developer (TDD da demanda `backlog-fase-5-compartilhamento`) | 2 | RF-91; TC-DIA-17; TC-DIA-18; log `docs/prompts/2026-10-20_1110_backlog-fase-5-compartilhamento.md` |
| `tests/integracao/diagnostico_test.sh` | `bin/dbx diagnostico`, `verificar` e preflight com utilitarios fora do `PATH` (`commands/diagnostico.sh`, `lib/preflight.sh`) | `diagnostico` | integracao | Senior Developer (TDD da demanda `backlog-fase-1-consulta-diagnostico`) | 17 | RF-66; TC-DIA-01..16; protocolo-tdd Regra 6 (nenhuma credencial em saida); log `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diag... |
| `tests/integracao/disponibilidade_automatica_test.sh` | `bin/dbx` nos comandos de nivel `credencial` (exercitado por `space`, `upload`, `download`, `sync`, `diagnostico`), com a checagem automa... | disponibilidade_automatica | integracao | Senior Developer (TDD da demanda `teste-de-disponibilidade`) | 48 | RF-151..RF-154; TC-DSP-18, 20, 28..64; RNF-03; log `docs/prompts/2026-10-23_0900_teste-de-disponibilidade.md` |
| `tests/integracao/espaco_test.sh` | `bin/dbx upload` e `bin/dbx sync --enviar` com a checagem previa de espaco (`dbx_cmd_espaco_checar` em `lib/cmd.sh`) | `lib/cmd.sh` | integracao | Senior Developer (TDD da demanda `backlog-fase-1-consulta-diagnostico`) | 13 | RF-67; TC-ESP-01..10; RF-136; RF-137; RF-15; RF-44; log `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md` |
| `tests/integracao/filtros_ajuda_test.sh` | ajuda (`bin/dbx help`), autocompletar (`completions/dbx.bash`), `README.md` e mapa de modulos para as opcoes de filtro e limite de banda | `bin/dbx` | integracao | Senior Developer (TDD da demanda `backlog-fase-4-filtros-e-banda`) | 4 | RF-83; TC-CPL-09; TC-DOC-03; TC-TST-07; log `docs/prompts/2026-10-19_2141_backlog-fase-4-filtros-e-banda.md` |
| `tests/integracao/filtros_test.sh` | `bin/dbx` (sync nos dois sentidos, `--dry-run`, `verificar`, download de pasta e de arquivo, upload) com filtros de caminho, data e taman... | filtros_test | integracao | Senior Developer (TDD da demanda `backlog-fase-4-filtros-e-banda`) | 33 | RF-79; RF-80; RF-80(d); RF-81; RF-12 (emendado pela DIV-90); TC-FLT; TC-FES; TC-FDT; DIV-95; DIV-103; log `docs/prompts/2026-10-19_2141_b... |
| `tests/integracao/instalador_diagnostico_freebsd_test.sh` | `install.sh` (instalar e desinstalar com prefixo) e `commands/diagnostico.sh`, no ambiente simulado do FreeBSD | `instalador_diagnostico_freebsd` (linha ausente do mapa de modulos; id derivado do nome do arquivo) | integracao | Senior Developer (TDD da demanda `suporte-freebsd`) | 7 | RF-170; RF-172; TC-FBSD-08, TC-FBSD-09, TC-FBSD-23; DIV-357; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md` |
| `tests/integracao/lote_test.sh` | `lib/lote.sh` e `bin/dbx sync` (exclusao em lote no `--espelhar`, envio em lote de pequenos no `--enviar`); `reter` fica item a item | lote_test | integracao | Senior Developer (TDD da demanda `backlog-fase-9-desempenho`) | 32 | F-08; F-34; RF-136; RF-137; DIV-269; TC-LOT-*; TC-LOU-*; log `docs/prompts/2026-10-21_2300_backlog-fase-9-desempenho.md` |
| `tests/integracao/paralelo_download_test.sh` | `bin/dbx download` de arquivo grande em faixas simultaneas (`commands/download.sh`, `lib/transfer.sh`, `lib/http.sh`) | paralelo_download | integracao | Senior Developer (TDD da demanda `paralelo-upload-download`) | 12 | F-100; RF-180; RF-181 (download); RF-182; RF-183; RF-184; DIV-369..371; DIV-373..376; TC-PUD-30..33; log `docs/prompts/2026-10-26_1900_pa... |
| `tests/integracao/paralelo_test.sh` | `bin/dbx sync`, `download` e `upload` de pasta com `--paralelo` (`commands/sync.sh`, `lib/lote.sh`), incluindo selecao, equivalencia N=1 ... | paralelo | integracao | Senior Developer (TDD da demanda `backlog-fase-9-desempenho`) | 25 | F-09; F-08; F-34; RF-133..RF-135; RF-139; TC-PAR-01..; DIV-338; log `docs/prompts/2026-10-21_2300_backlog-fase-9-desempenho.md` |
| `tests/integracao/paralelo_upload_test.sh` | `bin/dbx upload` de arquivo grande em partes simultaneas (`commands/upload.sh`, `lib/transfer.sh`, registro de retomada v2) | `paralelo_upload` | integracao | Senior Developer (TDD da demanda `paralelo-upload-download`) | 12 | F-100 (etapa 2a); RF-177..RF-179, RF-181 (upload), RF-182..RF-184, RF-175(c); DIV-358..DIV-368, DIV-373..DIV-376; TC-PUD; log `docs/promp... |
| `tests/integracao/perfis_test.sh` | `bin/dbx perfis`, `config --perfil`, opcao `--perfil` e variavel de perfil (`commands/perfis.sh`, `commands/config.sh`, `lib/config.sh`) | `commands/perfis.sh` | integracao | Senior Developer (TDD da demanda `backlog-fase-8-perfis`) | 40 | F-18; RF-120..RF-123; RF-126..RF-131; TC-PFS; TC-PFN; TC-PFC; TC-PFG; TC-PFL; TC-PFD; TC-PFA; TC-PFR; log `docs/prompts/2026-10-21_1735_b... |
| `tests/integracao/perfis_trava_raiz_test.sh` | trava por raiz local canonica no `sync --receber`, independente do perfil (`commands/sync.sh`, `lib/state.sh`, `lib/cmd.sh`) | `lib/state.sh` | integracao | Senior Developer (TDD da demanda `backlog-fase-8-perfis`) | 10 | F-18; TC-PFT; TC-PFE-06; log `docs/prompts/2026-10-21_1735_backlog-fase-8-perfis.md` |
| `tests/integracao/perfis_unlink_test.sh` | `bin/dbx unlink` com perfis, `commands/unlink.sh`, `lib/state.sh`, `lib/config.sh`, `lib/tmp.sh` | `perfis_unlink` | integracao | Senior Developer (TDD da demanda `backlog-fase-8-perfis`) | 19 | F-18; RF-124; RF-125; TC-PFU; TC-PFE; log `docs/prompts/2026-10-21_1735_backlog-fase-8-perfis.md` |
| `tests/integracao/progresso_arquivo_test.sh` | `bin/dbx` (upload simples, em sessao e de pasta; download de arquivo, de pasta e para stdout; sync nos dois sentidos com N=1 e N>1) e `li... | progresso_arquivo_test | integracao | Senior Developer (TDD da demanda `progresso-por-arquivo`) | 36 | F-49; RF-140..RF-147; TC-PRG-02, 06..10, 13..15, 21..23, 25, 28, 31..35; log `docs/prompts/2026-10-22_1600_progresso-por-arquivo.md` |
| `tests/integracao/qa_cache_unico_p3_test.sh` | `bin/dbx sync` (dois sentidos) e `upload` sobre o cache unico de estado (`lib/state.sh`): exclusao do espelhamento, dispensa do envio, id... | `lib/state.sh` | integracao | QA Expert (suite independente da demanda `cache-unico-p3`) | 33 | RF-41; RF-60; RF-38(e); RF-61; RF-03; RNF-02; log `docs/prompts/2026-10-18_2243_cache-unico-p3.md`; protocolo-tdd Regra 6 |
| `tests/integracao/qa_compartilhamento_b5_test.sh` | `bin/dbx compartilhar` (criar, reuso, modificar, listar, revogar, dry-run) e `link-temporario` (`commands/compartilhar.sh`, `commands/lin... | `commands/compartilhar.sh` | integracao | QA Expert (suite independente da demanda `backlog-fase-5-compartilhamento`) | 43 | F-15; F-16; RF-84; RF-85..RF-92; DIV-104..DIV-127; RSK-57..RSK-61; log `docs/prompts/2026-10-20_1110_backlog-fase-5-compartilhamento.md`;... |
| `tests/integracao/qa_confinamento_remoto_b1b_test.sh` | `bin/dbx` (upload, download, list, delete, info, sync, verificar), `lib/path.sh` e `lib/cmd.sh`: confinamento a `raiz_remota` e recusa de... | `qa_confinamento_remoto` | integracao | QA Expert (suite independente da demanda `backlog-fase-1b-confinamento-remoto`) | 13 | F-36; F-37; RNF-20(b1..b8); RNF-10(b); TC-SEC-18..32; log `docs/prompts/2026-10-19_1243_backlog-fase-1b-confinamento-remoto.md` |
| `tests/integracao/qa_consulta_diagnostico_b1_test.sh` | `bin/dbx` (`verificar`/`verify`, `diagnostico`, checagem previa de espaco em `upload` e `sync --enviar`, autocompletar de bash e `install... | `qa_consulta_diagnostico` | integracao | QA Expert (suite independente da demanda `backlog-fase-1-consulta-diagnostico`) | 21 | RF-65 a RF-68; log `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md`; protocolo-tdd Regra 6 (cenarios negativos de ca... |
| `tests/integracao/qa_cursor_b7b_test.sh` | `bin/dbx sync --receber` com cursor de listagem (`commands/sync.sh`, `lib/state.sh`, `lib/sync.sh`, `lib/hash.sh`) | qa_cursor | integracao | QA Expert (suite independente da demanda `backlog-fase-7b-cursor`) | 49 | F-14; RF-110..RF-119; RF-43; RF-48; DIV-204..DIV-234; condicoes C1..C11 do DBA; TC-CUL-04; TC-CUL-05; log `docs/prompts/2026-10-21_0713_b... |
| `tests/integracao/qa_debug_transferencias_b12_test.sh` | `bin/dbx` nos tres comandos de transferencia (download, upload e sync) com `--debug` (`lib/http.sh`, `lib/transfer.sh`, `commands/sync.sh... | qa_debug | integracao | QA Expert (suite independente da demanda `debug-transferencias`) | 28 | RF-156..RF-165; regra 12 do `AGENTS.md` (aceite pela regra 12); log `docs/prompts/2026-10-24_0330_debug-transferencias.md`; [entrada](../... |
| `tests/integracao/qa_desempenho_b9_test.sh` | `bin/dbx` (`sync` em paralelo e em lote, `sync --espelhar`, `reter`), `commands/sync.sh`, `commands/reter.sh`, `lib/lote.sh`, bancada de ... | qa_desempenho | integracao | QA Expert (suite independente da demanda `backlog-fase-9-desempenho`) | 15 | F-09, F-08, F-34; RF-136, RF-137, RF-138; DIV-269, DIV-278; protocolo-tdd Regra 6; log `docs/prompts/2026-10-21_2300_backlog-fase-9-desem... |
| `tests/integracao/qa_disponibilidade_b11_test.sh` | `bin/dbx testar` e a deteccao automatica de disponibilidade (internet, servico Dropbox, credencial) nos comandos de nivel credencial, com... | `qa_disponibilidade` | integracao | QA Expert (suite independente da demanda `teste-de-disponibilidade`) | 33 | RF-148..RF-155; protocolo-tdd Regra 6 (nenhum segredo em canal algum); log `docs/prompts/2026-10-23_0900_teste-de-disponibilidade.md` |
| `tests/integracao/qa_docs_aliases_p4_test.sh` | `bin/dbx` (aliases em ingles dos comandos e opcoes, guarda de origem vazia pelo plano, fixacao de localidade na comparacao do sync), `REA... | qa_docs_aliases | integracao | QA Expert (suite independente da demanda `docs-e-aliases-p4`) | 16 | RF-64; RF-41(b); RF-54(e)(f)(g); RNF-34; RNF-03; DIV-30; DIV-31; DIV-32; TC-ALI-02; TC-ALI-03; TC-CX-04; TC-CX-05; log `docs/prompts/2026... |
| `tests/integracao/qa_download_curl_real_b16_test.sh` | `dbx_http_conteudo_receber` de `lib/http.sh` com destino `fd:<n>` e `-`, usando curl real contra servidor HTTP local real | qa_download_curl_real | integracao | QA Expert (suite independente da demanda `suporte-freebsd`) | 7 | RF-171; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`; [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-24-1153-... |
| `tests/integracao/qa_filtros_banda_b4_test.sh` | `bin/dbx` com filtros de caminho, data e tamanho (`--incluir`, `--excluir`, `--espelhar`) e limite de banda, no sync nos dois sentidos, u... | qa_filtros_banda | integracao | QA Expert (suite independente da demanda `backlog-fase-4-filtros-e-banda`) | 21 | F-13; F-17; RF-79..RF-82; RF-80(d); DIV-79..DIV-102; DIV-99; DIV-103; log `docs/prompts/2026-10-19_2141_backlog-fase-4-filtros-e-banda.md` |
| `tests/integracao/qa_freebsd_b13_test.sh` | `bin/dbx` (config, upload, download, sync, retomada) com os dubles BSD de `chmod`, `stat`, `find` e `sha256` a frente do `PATH` | `qa_freebsd` | integracao | QA Expert (suite independente da demanda `suporte-freebsd`) | 10 | RF-166..172; RNF-39; TC-FBSD-*; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`; protocolo-tdd Regra 6 |
| `tests/integracao/qa_integridade_p1_test.sh` | `bin/dbx` (download de arquivo e de pasta, sync, upload) com `lib/transfer.sh`, `lib/hash.sh`, `lib/walk.sh`: integridade de dados no rec... | `bin/dbx` | integracao | QA Expert (suite independente da demanda `integridade-de-dados-p1`) | 27 | RF-49, RF-54, RF-55, RF-56, RF-57, RNF-29, RNF-04 (emendado); log `docs/prompts/2026-10-18_1745_integridade-de-dados-p1.md` |
| `tests/integracao/qa_leitura_exata_b14_test.sh` | `lib/atributos.sh` (`dbx_ler_exato`), calculo do `content_hash` em `lib/hash.sh` e upload em sessao de `bin/dbx` sob o duble `head` do Fr... | qa_leitura_exata (sem linha propria no mapa de modulos; ver observacoes) | integracao | QA Expert (suite independente da demanda `suporte-freebsd`) | 10 | RF-173, TC-FBSD-25..27; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`; [entrada de aceite](../../.github/agents/memoria/entradas/... |
| `tests/integracao/qa_paralelo_download_b20_test.sh` | `bin/dbx download` de arquivo grande em faixas simultaneas (`commands/download.sh`, `lib/transfer.sh`, `lib/http.sh`) | `qa_paralelo_download` (linha ausente do mapa de modulos; id derivado do nome do arquivo) | integracao | QA Expert (suite independente da demanda `paralelo-upload-download`) | 21 | F-100 etapa 2b; RF-180 a RF-184; RF-104(c)(d); RF-106(a); DIV-369 a DIV-371; DIV-373 a DIV-376; log `docs/prompts/2026-10-26_1900_paralel... |
| `tests/integracao/qa_paralelo_pastas_b18_test.sh` | `--paralelo`/`--parallel` e `DBX_PARALELO` em `bin/dbx upload` e `download` (pasta repassa N ao sync), com `commands/upload.sh`, `command... | `qa_paralelo_pastas` (linha ausente do mapa de modulos; id derivado do nome do arquivo) | integracao | QA Expert (suite independente da demanda `paralelo-upload-download`) | 10 | RF-175; RF-176; DIV-372; DIV-373; DIV-374 (opcao A); log `docs/prompts/2026-10-26_1900_paralelo-upload-download.md` |
| `tests/integracao/qa_paralelo_upload_b19_test.sh` | `bin/dbx upload` de arquivo grande em partes simultaneas, `lib/transfer_paralelo.sh`, `lib/state.sh` (registro de retomada v2) | qa_paralelo_upload (sem linha propria no mapa de modulos; ver observacoes) | integracao | QA Expert (suite independente da demanda `paralelo-upload-download`) | 19 | F-100; RF-177 a RF-183; RF-181; DIV-358 a DIV-368; protocolo-tdd Regra 6 (registro hostil); log `docs/prompts/2026-10-26_1900_paralelo-up... |
| `tests/integracao/qa_pendencias_p0_test.sh` | `dbx_cmd_ler_corpo_silencioso` de `lib/cmd.sh` e seu uso em `_dbx_cmd_upload_hash_remoto` de `commands/upload.sh`; prova de que `identida... | qa_pendencias | integracao | QA Expert (suite independente da demanda `backlog-fase-0-pendencias`) | 10 | O-5; RSK-43; RNF-03; log `docs/prompts/2026-10-19_1023_backlog-fase-0-pendencias.md`; [entrada de aceite](../../.github/agents/memoria/en... |
| `tests/integracao/qa_perfis_b8_test.sh` | `bin/dbx` (perfis, `config`, `unlink`, `sync` com perfil), `lib/config.sh`, `lib/state.sh`, `lib/tmp.sh` | `qa_perfis` | integracao | QA Expert (suite independente da demanda `backlog-fase-8-perfis`) | 34 | F-18; RF-120 a RF-132; DIV-236 a DIV-255; TC-CNF-03; log `docs/prompts/2026-10-21_1735_backlog-fase-8-perfis.md`; protocolo-tdd Regra 6 (... |
| `tests/integracao/qa_progresso_arquivo_b10_test.sh` | `bin/dbx` (upload de fluxo, download, `sync` nos dois sentidos com N=1 e N=3), `lib/progress.sh` | qa_progresso | integracao | QA Expert (suite independente da demanda `progresso-por-arquivo`) | 8 | F-49; RF-140 a RF-147; secao 5.19 da especificacao; DIV-302, DIV-303; log `docs/prompts/2026-10-22_1600_progresso-por-arquivo.md` |
| `tests/integracao/qa_recuperacao_b3_test.sh` | `bin/dbx` nos comandos `revisoes`, `restaurar` e `lixeira` (com exclusao permanente), `commands/revisoes.sh`, `commands/restaurar.sh`, `c... | qa_recuperacao | integracao | QA Expert (suite independente da demanda `backlog-fase-3-recuperacao`) | 30 | F-07; F-20; RF-72..RF-78; DIV-54..DIV-77; log `docs/prompts/2026-10-19_1828_backlog-fase-3-recuperacao.md` |
| `tests/integracao/qa_regex_portavel_b17_test.sh` | todas as expressoes regulares de `lib/`, `commands/`, `bin/`, `install.sh` e `uninstall.sh` (limite de repeticao RE_DUP_MAX 255 do FreeBS... | qa_regex_portavel_b17 | integracao | QA Expert (suite independente da demanda `suporte-freebsd`) | 19 | RF-166; TC-FBSD-19 (parte regex); log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`; [entrada](../../.github/agents/memoria/entradas/... |
| `tests/integracao/qa_retencao_b6_test.sh` | `bin/dbx` (comandos `reter` e `retain`) com `commands/reter.sh`, `lib/retencao.sh`, `lib/filtro.sh`: plano de retencao, lixeira e guarda ... | `bin/dbx` | integracao | QA Expert (suite independente da demanda `backlog-fase-6-retencao`) | 60 | log `docs/prompts/2026-10-20_2010_backlog-fase-6-retencao.md`; [entrada](../../.github/agents/memoria/entradas/2026-10-20-2010-retencao.m... |
| `tests/integracao/qa_retomada_b7a_test.sh` | `bin/dbx` (upload e download retomados) com `commands/upload.sh`, `commands/download.sh`, `commands/unlink.sh`, `commands/diagnostico.sh`... | `bin/dbx` | integracao | QA Expert (suite independente da demanda `backlog-fase-7a-retomada`) | 41 | log `docs/prompts/2026-10-20_2315_backlog-fase-7a-retomada.md`; grupos de cenario D (download), L (nao pendurar em entradas nao regulares... |
| `tests/integracao/qa_robustez_rede_p2_test.sh` | `bin/dbx` download, upload, sync e diagnostico sob falhas de rede, consumidor que fecha cedo, sinais e segredos (`commands/download.sh`, ... | `qa_robustez` | integracao | QA Expert (suite independente da demanda `robustez-de-rede-p2`) | 21 | RNF-30(c); RNF-07(e); RF-32(b); RF-59; RNF-31; log `docs/prompts/2026-10-18_2045_robustez-de-rede-p2.md` |
| `tests/integracao/qa_sync_blocos_b21_test.sh` | `bin/dbx` sync, upload e download de pasta em blocos cortados por diretorio | `qa_sync_blocos_b21` | integracao | QA Expert (suite independente da demanda `sync-em-blocos`) | 25 | F-101; RF-186..RF-197; DIV-377..DIV-384 |
| `tests/integracao/qa_trava_tmp_b2_test.sh` | `bin/dbx` (sync, `--dry-run`, verificar, download de pasta, unlink, diagnostico, upload), `lib/state.sh` (trava de concorrencia por par),... | qa_trava_tmp | integracao | QA Expert (suite independente da demanda `backlog-fase-2-trava-e-tmp`) | 23 | F-12, F-31; RF-69, RF-70, RF-71; DIV-38..49; DIV-51; RNF-35, RNF-36; protocolo-tdd Regra 6; log `docs/prompts/2026-10-19_1419_backlog-fas... |
| `tests/integracao/qa_upload_para_pasta_b15_test.sh` | `bin/dbx upload` de arquivo para pasta remota existente (`commands/upload.sh`, `lib/cmd.sh`), com e sem raiz remota e barra final | `qa_upload_para_pasta` | integracao | QA Expert (suite independente da demanda `upload-arquivo-para-pasta`) | 26 | RF-174; emenda de RF-60(g)(h); log `docs/prompts/2026-10-26_1300_upload-arquivo-para-pasta.md` |
| `tests/integracao/recuperacao_test.sh` | `bin/dbx` (`revisoes`, `restaurar`, `lixeira` e aliases, incluindo expurgo permanente), `commands/revisoes.sh`, `commands/restaurar.sh`, ... | recuperacao | integracao | Senior Developer (TDD da demanda `backlog-fase-3-recuperacao`) | 61 | F-07, F-20; RF-72 a RF-78; TC-RVS, TC-RST, TC-RPA, TC-LIX, TC-EXP, TC-DOC-02; log `docs/prompts/2026-10-19_1828_backlog-fase-3-recuperaca... |
| `tests/integracao/reter_test.sh` | `bin/dbx reter` (alias `retain`): `commands/reter.sh`, `lib/retencao.sh`, `lib/filtro.sh`; plano, lixeira e guarda por identidade | `reter_test` | integracao | Senior Developer (TDD da demanda `backlog-fase-6-retencao`) | 84 | F-10; RF-93..100; TC-RTA; TC-RTS; TC-RTP; TC-RTC; TC-RTG; TC-RTX; TC-RTO; TC-CPL-11; TC-DOC-05; TC-TST-09; DIV-130..147; DIV-158..168; lo... |
| `tests/integracao/retomada_download_test.sh` | `bin/dbx download` retomado entre execucoes (`Range`), `--no-resume`, `diagnostico` e `unlink`; `commands/download.sh`, `lib/cmd.sh`, `li... | retomada_download | integracao | Senior Developer (TDD da demanda `backlog-fase-7a-retomada`) | 32 | F-03; RF-102, RF-104 a RF-108; TC-RMD-01..15, TC-RMO-01, 02, 04, 05, TC-RMC-01, 06, TC-RML-05..07, TC-RMS-06, TC-DBG-13..15; DIV-176 a DI... |
| `tests/integracao/retomada_upload_test.sh` | `bin/dbx upload` retomado entre execucoes (`commands/upload.sh`, `lib/transfer.sh`, `lib/state.sh`, registro `retomada-*`) | retomada_upload | integracao | Senior Developer (TDD da demanda `backlog-fase-7a-retomada`) | 43 | F-03; RF-101..RF-109; DIV-171..DIV-190; TC-RMU-01..16; TC-RME-02, 12, 14; TC-RMO-01..03, 05..11; TC-RMC-01, 04, 05; TC-RMS-01..06; TC-DBG... |
| `tests/integracao/sync_blocos_test.sh` | `bin/dbx sync` e `download` de pasta em ciclos por diretorio | `sync_blocos_test` | integracao | Senior Developer (TDD da demanda `sync-em-blocos`) | 23 | F-101; RF-187..RF-197; TC-BLC-nn |
| `tests/integracao/sync_test.sh` | `bin/dbx sync` direcional (`commands/sync.sh`, `lib/sync.sh`, `lib/walk.sh`, `lib/transfer.sh`, `lib/state.sh`) | `commands/sync.sh` | integracao | Senior Developer (TDD; sem log de prompt, commit de criacao `f8b9ed0` `feat(sync): sincronizacao direcional com a origem como autoridade`) | 85 | DP-27; DP-28; RF-37..RF-53; RF-54; RF-55(e); RF-57; RF-59; RF-64; RF-137; RNF-29; RNF-31; RSK-35; TC-FLH-01..04; TC-SIG-01..03; DIV-28 (v... |
| `tests/integracao/testar_test.sh` | `bin/dbx testar` (alias `check`) e a sonda de disponibilidade (`commands/testar.sh`, `lib/disponibilidade.sh`) | `commands/testar.sh` | integracao | Senior Developer (TDD da demanda `teste-de-disponibilidade`) | 29 | RF-148; RF-149; RF-150; RF-154; TC-DSP-01..25; TC-DSP-55; TC-DSP-57; TC-DSP-58; DIV-326; log `docs/prompts/2026-10-23_0900_teste-de-dispo... |
| `tests/integracao/trava_test.sh` | `bin/dbx` (sync, verificar, unlink, diagnostico, upload, download, list, info, space, delete, help) com `lib/state.sh` e `lib/tmp.sh`: tr... | `lib/state.sh` | integracao | Senior Developer (TDD da demanda `backlog-fase-2-trava-e-tmp`) | 31 | RF-69, RF-70, RF-71, RNF-35; TC-TRV, TC-ESR, TC-DIA-11..14, TC-TMP-02, 05, 06; DIV-50, DIV-51; F-12, F-31; log `docs/prompts/2026-10-19_1... |
| `tests/integracao/upload_pasta_test.sh` | `bin/dbx` (`upload` de arquivo para destino que e pasta) com `commands/upload.sh`: grava em `<pasta>/<nome>` sem falhar com `path/conflic... | `commands/upload.sh` | integracao | Senior Developer (TDD da demanda `upload-arquivo-para-pasta`) | 13 | RF-174; log `docs/prompts/2026-10-26_1300_upload-arquivo-para-pasta.md` |
| `tests/integracao/verificar_test.sh` | `bin/dbx verificar` (alias `verify`) (`commands/verificar.sh`, `lib/walk.sh`, `lib/sync.sh`) | `commands/verificar.sh` | integracao | Senior Developer (TDD da demanda `backlog-fase-1-consulta-diagnostico`) | 17 | RF-65; TC-VER-01..09; log `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md`; protocolo-tdd Regra 6 |
| `tests/unit/atributos_portavel_test.sh` | `lib/atributos.sh` (`dbx_atributo`), `lib/http.sh` e `lib/transfer.sh` na leitura de atributos de arquivo com `stat` GNU ou BSD | `atributos_portavel` (linha ausente do mapa de modulos; id derivado do nome do arquivo) | unitario | Senior Developer (TDD da demanda `suporte-freebsd`) | 11 | RF-167; TC-FBSD-02; TC-FBSD-11; TC-FBSD-19 (parte `stat`); log `docs/prompts/2026-10-24_1153_suporte-freebsd.md` |
| `tests/unit/auth_test.sh` | `lib/auth.sh` (troca de codigo e renovacao de token de curta duracao, revogacao, esquecimento de credencial) | auth_test | unitario | Senior Developer (TDD da demanda `feat(auth): renovacao de token sem escrita do segredo em disco`) | 42 | Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste |
| `tests/unit/cabecalho_test.sh` | `lib/http.sh` (recusa de valor de cabecalho HTTP com CR, LF ou byte de controle antes de chegar ao cliente) | `cabecalho` | unitario | Senior Developer (commit de criacao e0cee97 `test: casos adversariais da recusa de cabecalho, escritos pelo QA`, sem log de prompt) | 17 | Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste |
| `tests/unit/chmod_portavel_test.sh` | chamadas de `chmod` de `lib/auth.sh`, `lib/state.sh` e `lib/http.sh` (gravacao da credencial, diretorio de estado, modo do alvo no recebi... | chmod_portavel | unitario | Senior Developer (TDD da demanda `suporte-freebsd`) | 6 | RF-166; TC-FBSD-01; TC-FBSD-19 (parte chmod); log `docs/prompts/2026-10-24_1153_suporte-freebsd.md` |
| `tests/unit/cli_test.sh` | `lib/cli.sh`: interpretacao de opcoes globais, despacho por tabela fechada de comandos e requisito de ambiente de cada comando | `lib/cli.sh` | unitario | Senior Developer (TDD; commit de criacao `b2179b4`, "feat(comandos): entrada fina com despacho por tabela literal") | 18 | Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste |
| `tests/unit/cmd_test.sh` | `lib/cmd.sh`: servicos comuns dos comandos (`dbx_cmd_falhar`, `dbx_cmd_iniciar_saida`, `dbx_cmd_bytes_legiveis`, `dbx_cmd_content_hash_do... | `lib/cmd.sh` | unitario | Senior Developer (TDD da demanda `cache-unico-p3`) | 23 | RNF-32(d); log `docs/prompts/2026-10-18_2243_cache-unico-p3.md` |
| `tests/unit/compartilhamento_test.sh` | `lib/compartilhamento.sh` (visibilidade, `--expira`, URL, senha, corpo), leitura sem eco de `lib/cli.sh` e tags e chave sensivel novas de... | `compartilhamento_test` | unitario | Senior Developer (TDD da demanda `backlog-fase-5-compartilhamento`) | 16 | RF-85..RF-89; RF-90(a); DIV-104..DIV-120; DIV-111; DIV-117; TC-SHE-01; TC-SNH-11; log `docs/prompts/2026-10-20_1110_backlog-fase-5-compar... |
| `tests/unit/config_test.sh` | `lib/config.sh` (leitura e escrita atomica do arquivo de credencial, caminhos XDG, permissoes, remocao) | `config` | unitario | Senior Developer (commit de criacao ebec9ae `test: preflight, config e composicao dos caminhos gemeos`, sem log de prompt) | 41 | PRJ-DEC-07; DP-05; DP-11; RNF-04 |
| `tests/unit/cursor_estado_test.sh` | registro `cursor-*` do estado em `lib/state.sh` (cursor de listagem do `sync --receber`) | `lib/state.sh` | unitario | Senior Developer (TDD da demanda `backlog-fase-7b-cursor`) | 13 | F-14; RF-111; RF-113(d); RF-117(e)(f); parecer do DBA C1, C2, C4, C8, C10, C11; log `docs/prompts/2026-10-21_0713_backlog-fase-7b-cursor.md` |
| `tests/unit/debug_test.sh` | `lib/debug.sh`, ponto unico de emissao das linhas `debug:` em stderr | `debug_test` | unitario | Senior Developer (TDD da demanda `debug-transferencias`) | 10 | RF-156; RF-163(d); RF-164(b); TC-DBG-22; TC-DBG-27; TC-DBG-30; log `docs/prompts/2026-10-24_0330_debug-transferencias.md` |
| `tests/unit/descritor_portavel_test.sh` | `lib/atributos.sh` (`dbx_atributo_fd`) e os chamadores em `lib/state.sh`, `lib/transfer.sh`, `lib/hash.sh`: conferencia de arquivo aberto... | `lib/atributos.sh` | unitario | Senior Developer (TDD da demanda `suporte-freebsd`) | 11 | RF-171(a); TC-FBSD-20; DIV-352; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md` |
| `tests/unit/disponibilidade_test.sh` | `lib/disponibilidade.sh` e `dbx_http_sondar` em `lib/http.sh` (sonda de disponibilidade, reserva compartilhada entre processos, classific... | disponibilidade_test | unitario | Senior Developer (TDD da demanda `teste-de-disponibilidade`) | 19 | RF-149, RF-150, RF-152(a); TC-DSP-13..21, 22..25, 27; DIV-331; log `docs/prompts/2026-10-23_0900_teste-de-disponibilidade.md` |
| `tests/unit/errors_test.sh` | `lib/errors.sh` (taxonomia de erro, codigos de saida, politica de retentativa, redacao de segredos, idempotencia) | `errors` | unitario | Senior Developer (TDD; commit `a03d2c0` "first commit", sem log de prompt) | 82 | RF-29; RF-35 (contrato congelado dos codigos); RNF-08; DIV-58 (tags da recuperacao); `docs/testes/mapa-modulos.md` (Regra 1: `errors` e c... |
| `tests/unit/filtro_test.sh` | `lib/filtro.sh`: casamento de padroes estilo gitignore sem diferenca de caixa, validacao de padroes, filtros de data e de tamanho | `filtro_test` | unitario | Senior Developer (TDD da demanda `backlog-fase-4-filtros-e-banda`) | 34 | RF-79; RF-80(a); RF-81; TC-FLT; TC-FES-01; TC-FES-03; TC-FDT; DIV-94; DIV-103; log `docs/prompts/2026-10-19_2141_backlog-fase-4-filtros-e... |
| `tests/unit/harness_test.sh` | `tests/support/harness.sh` e `tests/run.sh`: assercoes e executor do arcabouco de teste | `harness_test` | unitario | Senior Developer (commit `64e6139`, `test: fixa todas as assercoes do arcabouco nos dois sentidos`; sem log de prompt) | 28 | Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste (commit `64e6139`); protocolo-tdd Regra 9 (parad... |
| `tests/unit/hash_test.sh` | `lib/hash.sh`: `content_hash` da Dropbox (blocos de 4 MiB), API incremental, comparacao e identidade do arquivo | `hash` | unitario | Senior Developer (commit `a03d2c0`, `first commit`; sem log de prompt) | 44 | RF-33; RF-34; `docs/registros/vetores-content-hash.md` (vetores derivados de oraculo independente em Python); log de prompt: Nao aplicave... |
| `tests/unit/hash_vetor_oficial_test.sh` | `lib/hash.sh` (`content_hash` da Dropbox) contra o arquivo de exemplo oficial da Dropbox | hash_vetor_oficial | unitario | Senior Developer (TDD da demanda `first commit`) | 2 | RF-34 (criterio de aceite: vetor oficial da Dropbox); Nao aplicavel como log de prompt: anterior a trilha do protocolo |
| `tests/unit/http_fd_curl_real_test.sh` | `lib/http.sh`: destino `fd:n` e saida padrao do download, com o `curl` real do sistema (URL `file://`) | `http_fd_curl_real` | unitario | Senior Developer (TDD da demanda `suporte-freebsd`) | 4 | RF-171; RF-166..172; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md` |
| `tests/unit/http_test.sh` | `lib/http.sh` (ponto unico de saida de rede: paginacao, retentativa, recuo, `Retry-After`, classificacao de erro, canal do segredo) | http | unitario | Senior Developer (TDD da demanda `feat(http): cliente com paginacao, retentativa e contexto isolado`) | 53 | RNF-14 (a suite padrao nao usa rede); Nao aplicavel como log de prompt: anterior a trilha do protocolo; comportamento inferido do codigo ... |
| `tests/unit/identidade_gnustat_test.sh` | `lib/hash.sh` (identidade forte do arquivo lida com `stat -c`) sob o GNU coreutils | `identidade_gnustat` | unitario | Senior Developer (TDD da demanda `backlog-fase-0-pendencias`) | 7 | RSK-43; log `docs/prompts/2026-10-19_1023_backlog-fase-0-pendencias.md` |
| `tests/unit/json_test.sh` | `lib/json.sh` (interpretador JSON proprio, sem `jq`) | json | unitario | Senior Developer (TDD da demanda `feat(json): interpretador JSON proprio sem dependencia externa`; sem log de prompt) | 62 | RNF-11; DIV-04 (citados no cabecalho do teste); sem log de prompt (commit de criacao `edfd8ad`, anterior a trilha do protocolo) |
| `tests/unit/leitura_exata_portavel_test.sh` | `lib/atributos.sh` (`dbx_ler_exato`, sobre `dd`), `lib/hash.sh` e `lib/transfer.sh` na leitura em partes do mesmo descritor | `leitura_exata_portavel` (linha ausente do mapa de modulos; id derivado do nome do arquivo) | unitario | Senior Developer (TDD da demanda `suporte-freebsd`) | 7 | RF-173; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md` |
| `tests/unit/output_test.sh` | `lib/output.sh`: modelo de resultado unico com duas apresentacoes (texto e estruturada), terminador nulo, restricao de linha e mascaramen... | `output` | unitario | Senior Developer (commit `74b3567`, `feat(output): apresentacao dupla com terminador selecionavel`; sem log de prompt) | 31 | RF-28; RF-35; RNF-19; RNF-22; log de prompt: Nao aplicavel: anterior a trilha do protocolo |
| `tests/unit/path_test.sh` | `lib/path.sh`: normalizacao, confinamento a raiz (remoto sem distincao de caixa, local com distincao), recusa de travessia, vinculos simb... | `lib/path.sh` | unitario | Senior Developer (TDD; commit de criacao `a03d2c0`, "first commit") | 58 | Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste |
| `tests/unit/perfis_cli_test.sh` | `lib/cli.sh`, opcao global `--perfil` e variavel de perfil | `lib/cli.sh` | unitario | Senior Developer (TDD da demanda `backlog-fase-8-perfis`) | 9 | F-18; RF-120; RF-121(g); DIV-241; TC-PFS-01..08; TC-PFN-09; TC-PFN-10; log `docs/prompts/2026-10-21_1735_backlog-fase-8-perfis.md` |
| `tests/unit/perfis_config_test.sh` | `lib/config.sh`: perfis nomeados de credencial (nome, selecao, resolucao, permissoes, gravacao, remocao, identidade e listagem) | `perfis_config` | unitario | Senior Developer (TDD da demanda `backlog-fase-8-perfis`) | 38 | F-18; RF-120..122; RF-125; RF-126; RNF-37; TC-PFN; TC-PFC; TC-PFS; TC-PFG; TC-PFU; TC-PFL; log `docs/prompts/2026-10-21_1735_backlog-fase... |
| `tests/unit/plataforma_freebsd_test.sh` | `lib/state.sh` (`dbx_state_host_id`): identificador do host sem `/proc`, como no FreeBSD | `lib/state.sh` | unitario | Senior Developer (TDD da demanda `suporte-freebsd`) | 1 | RF-171(b); TC-FBSD-21; DIV-353 (opcao A); log `docs/prompts/2026-10-24_1153_suporte-freebsd.md` |
| `tests/unit/poda_portavel_test.sh` | `lib/state.sh` (`_dbx_state_retomada_podar` e poda equivalente de `cursor-*`): poda por teto sem `find -printf` | `lib/state.sh` | unitario | Senior Developer (TDD da demanda `suporte-freebsd`) | 5 | RF-168; TC-FBSD-03; TC-FBSD-19 (parte `find`); log `docs/prompts/2026-10-24_1153_suporte-freebsd.md` |
| `tests/unit/preflight_test.sh` | `lib/preflight.sh`: verificacao de ambiente (utilitarios, versao do bash, permissao da credencial, area temporaria, XDG), auditorias de `... | `lib/preflight.sh` | unitario | Senior Developer (TDD; commit de criacao `ebec9ae`, "test: preflight, config e composicao dos caminhos gemeos") | 35 | Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste |
| `tests/unit/progress_test.sh` | `lib/progress.sh` (formatacao de bytes, barra, etapa e transferencia de progresso em stderr) | progress | unitario | Senior Developer (TDD da demanda `progresso-operacoes`) | 16 | log `docs/prompts/2026-10-08_1015_progresso-operacoes.md` (parametros de progresso para operacoes) |
| `tests/unit/progresso_linha_test.sh` | `lib/progress.sh`: progresso por arquivo (`dbx_progress_arquivo_*`), linha com percentual, terminal simulado, observador do `.part` e can... | `progresso_linha` | unitario | Senior Developer (TDD da demanda `progresso-por-arquivo`) | 18 | F-49; RF-140..147; TC-PRG-01; TC-PRG-03; TC-PRG-04; TC-PRG-10..13; TC-PRG-15; TC-PRG-27; TC-PRG-29..32; log `docs/prompts/2026-10-22_1600... |
| `tests/unit/qa_rede_p2_test.sh` | `lib/http.sh` (timeouts, retentativas, `Retry-After`), `lib/transfer.sh` (retomada em partes, `correct_offset`) e o executor de testes `t... | `qa_rede` | unitario | QA Expert (suite independente da demanda `robustez-de-rede-p2`) | 27 | RNF-07; RNF-30; RF-09; RF-58; RNF-32(a); log `docs/prompts/2026-10-18_2045_robustez-de-rede-p2.md`; protocolo-tdd Regra 9 (parada no prim... |
| `tests/unit/qa_state_p3_test.sh` | `lib/state.sh` (estado hostil, anti-corrida na fronteira de dois segundos), `lib/errors.sh` e `lib/http.sh` (regressao da P3.4 por tabela... | `lib/state.sh` | unitario | QA Expert (suite independente da demanda `cache-unico-p3`) | 8 | RNF-25, RF-42, RF-61(a), RF-61(d), RF-63(a); log `docs/prompts/2026-10-18_2243_cache-unico-p3.md`; [entrada](../../.github/agents/memoria... |
| `tests/unit/regex_portavel_test.sh` | expressoes regulares de `lib/state.sh` (registro de retomada e cursor) e a regra de portabilidade com RE_DUP_MAX do FreeBSD | `lib/state.sh` | unitario | Senior Developer (TDD da demanda `suporte-freebsd`) | 3 | RF-166; TC-FBSD-19 (parte regex); log `docs/prompts/2026-10-24_1153_suporte-freebsd.md` |
| `tests/unit/resumo_freebsd_test.sh` | resumo SHA-256 por capacidade (`lib/hash.sh`), `lib/preflight.sh` e `lib/tmp.sh` sob os utilitarios da base do FreeBSD | `resumo_freebsd` | unitario | Senior Developer (TDD da demanda `suporte-freebsd`) | 6 | RF-168; RF-169; TC-FBSD-04, TC-FBSD-05, TC-FBSD-06, TC-FBSD-07, TC-FBSD-10; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md` |
| `tests/unit/retencao_test.sh` | `lib/retencao.sh` (politica pura de `--manter` e `--dias`, carimbo, guardas) e casamento de nome avulso de `lib/filtro.sh` | `retencao_test` | unitario | Senior Developer (TDD da demanda `backlog-fase-6-retencao`) | 38 | F-10; RF-93(e)(f)(g)(h)(j); RF-95; RF-97(b); TC-RTA-05..07; TC-RTP-01..12; TC-RTG-03..05; TC-RTG-09; log `docs/prompts/2026-10-20_2010_ba... |
| `tests/unit/retomada_estado_test.sh` | registro de retomada (`retomada-*`), travas de registro, poda e barreira do `.part` em `lib/state.sh` | `lib/state.sh` | unitario | Senior Developer (TDD da demanda `backlog-fase-7a-retomada`) | 26 | F-03; RF-61 (emenda C3); RF-101; RF-105; RF-107; TC-RME-01, 03..11, 13; TC-UPC-13; TC-RMC-02; TC-RMC-03; TC-RML-01..04; parecer do DBA C1... |
| `tests/unit/state_test.sh` | `lib/state.sh` (cache unico de `content_hash`: carga, gravacao atomica, namespaces `memoria-*` do sync e `upload-*` do upload, identidade... | state | unitario | Senior Developer (TDD da demanda `cache-unico-p3`) | 24 | RNF-32(d); RNF-33; log `docs/prompts/2026-10-18_2243_cache-unico-p3.md` |
| `tests/unit/state_trava_raiz_test.sh` | `lib/state.sh`: trava por raiz local canonica entre processos | `state_trava_raiz` | unitario | Senior Developer (TDD da demanda `backlog-fase-8-perfis`) | 9 | F-18; RF-132; DIV-250; TC-PFT-01..03; TC-PFT-06..08; log `docs/prompts/2026-10-21_1735_backlog-fase-8-perfis.md` |
| `tests/unit/state_trava_test.sh` | `lib/state.sh` (trava de concorrencia por par, retomada de trava orfa, listagem), com apoio de `lib/tmp.sh` e `lib/hash.sh` | state_trava | unitario | Senior Developer (TDD da demanda `backlog-fase-2-trava-e-tmp`) | 28 | RF-69; parecer do DBA de 2026-10-19; TC-TRV-12..15, 17, 21..30, 32..34 e a parte de biblioteca de TC-TRV-01, 09..11, 18; DIV-53; log `doc... |
| `tests/unit/sync_blocos_test.sh` | `dbx_cli_validar_bloco`, `dbx_cmd_bloco`, planejador de ciclos e `dbx_sync_listar_diretorio` | `sync_blocos_test` | unitario | Senior Developer (TDD da demanda `sync-em-blocos`) | 19 | RF-186; RF-187; RF-189; TC-BLC-nn |
| `tests/unit/sync_plano_test.sh` | `lib/sync.sh` (`dbx_sync_comparar`, traducao do plano para os quatro estados do `verificar`) | sync_plano | unitario | Senior Developer (TDD da demanda `backlog-fase-1-consulta-diagnostico`) | 6 | RF-65(c)(d); log `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md` |
| `tests/unit/sync_tabela_test.sh` | `lib/sync.sh` (tabela remota: retrato carregado, delta aplicado, confinamento e agrupamento das confirmacoes de exclusao) | sync_tabela | unitario | Senior Developer (TDD da demanda `backlog-fase-7b-cursor`) | 12 | F-14; DIV-g; RF-112; RF-114; RF-115; parecer do DBA (secao 5; C3, C4, C5); log `docs/prompts/2026-10-21_0713_backlog-fase-7b-cursor.md` |
| `tests/unit/tmp_test.sh` | `lib/tmp.sh` (registro unico de areas temporarias e acoes de liberacao com tratadores de sinal) e auditoria de `mktemp` e `trap` em `lib/... | `lib/tmp.sh` | unitario | Senior Developer (TDD da demanda `backlog-fase-2-trava-e-tmp`) | 21 | RNF-35; RNF-36; TC-TMP-01..09; TC-CNF-01; F-12; F-31; log `docs/prompts/2026-10-19_1419_backlog-fase-2-trava-e-tmp.md`; mapa de modulos R... |
| `tests/unit/transfer_test.sh` | `lib/transfer.sh` (sessao de envio em partes sequencial com retentativa e retomada na mesma execucao) | transfer | unitario | Senior Developer (TDD da demanda `feat(transfer): envio em partes por sessao sequencial com retentativa`; sem log de prompt) | 36 | RF-08; RF-09; RF-31 (citados no cabecalho do teste); sem log de prompt (commit de criacao `ca64c8d`) |
| `tests/unit/walk_test.sh` | `lib/walk.sh`: travessia da arvore local por descida | `walk` | unitario | Senior Developer (commit `f8b9ed0`, `feat(sync): sincronizacao direcional com a origem como autoridade`; sem log de prompt) | 13 | RNF-28; RF-41a; log de prompt: Nao aplicavel: anterior a trilha do protocolo |

## `tests/integracao/banda_test.sh`

- **Alvo:** `bin/dbx` com `lib/cli.sh` (`dbx_cli_validar_taxa`), `lib/cmd.sh` e `lib/http.sh`: limite de banda (`--limite-banda`, `--bwlimit`, `DBX_LIMITE_BANDA`) em upload, download, sync, verificar, list, info e space
- **Modulo:** `bin/dbx`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-4-filtros-e-banda`)
- **Regras de origem:** RF-82; TC-BND-01..14; log `docs/prompts/2026-10-19_2141_backlog-fase-4-filtros-e-banda.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` que registra por chamada a URL, a linha `limit-rate` (ou `-`) e o `argv`; credencial e ambiente temporarios por caso; variavel `DBX_LIMITE_BANDA` ajustada por caso
- **Comando:** `bash tests/run.sh tests/integracao/banda_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_bnd01_taxas_viram_limit_rate_inteiro_em_bytes | Taxas com sufixo (k, M, etc.) informadas ao limite chegam ao `curl` como `limit-rate` inteiro em bytes | TC-BND-01 |
| teste_bnd02_valores_invalidos_saem_2_antes_da_rede | Valor de limite invalido termina com codigo 2 sem nenhuma chamada de rede | TC-BND-02 |
| teste_bnd03_piso_e_o_dobro_da_velocidade_minima_efetiva | Taxa abaixo do piso (dobro da velocidade minima efetiva) e recusada e a igual ao piso e aceita | TC-BND-03 |
| teste_bnd04_aspa_e_quebra_de_linha_recusadas_e_valor_nunca_no_argv | Valor com aspa ou quebra de linha e recusado, e o texto do operador nunca aparece no `argv` do `curl` | TC-BND-04 |
| teste_bnd05_so_requisicoes_de_conteudo_levam_o_limite | Somente as requisicoes que transferem conteudo levam `limit-rate`; chamadas de metadados seguem sem limite | TC-BND-05 |
| teste_bnd06_cada_parte_e_cada_retentativa_levam_o_limite | Cada parte de envio por sessao e cada retentativa de requisicao levam o limite | TC-BND-06 |
| teste_bnd07_variavel_sem_a_opcao_e_a_opcao_vence | A variavel de ambiente vale quando a opcao esta ausente e a opcao vence quando ambas existem | TC-BND-07 |
| teste_bnd08_variavel_invalida_recusa_so_onde_vale | Variavel invalida recusa a execucao apenas nos comandos que aplicam o limite | TC-BND-08 |
| teste_bnd09_alias_identico_e_repetida_o_ultimo_vence | Os dois nomes da opcao sao equivalentes e, repetida, vale o ultimo valor | TC-BND-09 |
| teste_bnd10_verificar_e_demais_comandos_recusam_a_opcao | Verificar e os comandos sem transferencia recusam a opcao de limite como uso invalido | TC-BND-10 |
| teste_bnd11_bnd12_com_e_sem_limite_mesmos_bytes_e_fluxo_aplica | Com e sem limite os bytes transferidos sao identicos e o envio por fluxo tambem aplica o limite | TC-BND-11; TC-BND-12 |
| teste_bnd13_limite_banda_na_saida | O limite efetivo aparece na saida do comando em formato legivel | TC-BND-13 |
| teste_bnd14_sync_nos_dois_sentidos_e_download_de_pasta_aplicam | Sync nos dois sentidos e download de pasta aplicam o limite em todas as transferencias | TC-BND-14 |


## `tests/integracao/bloco_cli_test.sh`

- **Alvo:** `bin/dbx` (`sync`, `upload`, `download`, `list`, `diagnostico`) com a opcao `--bloco`/`--batch` e a variavel `DBX_BLOCO` (`lib/cli.sh`, `lib/cmd.sh`, `commands/diagnostico.sh`): validacao antes de rede e estado
- **Modulo:** `bloco_cli` (filtro do mapa de modulos)
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `sync-em-blocos`)
- **Regras de origem:** F-101; RF-186..RF-197; TC-BLC-nn (secao 5.24 do escopo); log `docs/prompts/2026-10-31_1200_sync-em-blocos.md`; registro `docs/reviews/2026-10-31-1200-registro-sync-em-blocos.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** `curl` do cenario so registra a chamada e falha (exit 22); credencial e diretorios temporarios sinteticos; ambiente isolado por `env -i`; sem rede
- **Comando:** `bash tests/run.sh tests/integracao/bloco_cli_test.sh`
- **Observacoes:** Chamada registrada onde nao devia e achado: a verificacao e a ausencia do arquivo de chamadas.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_blc_sync_valor_invalido_sai_2_antes_da_rede_e_do_estado | `sync` com `--bloco` e `--batch` em valores invalidos (0, 1000001, -1, +2, 01, texto, vazio, com espaco, decimal) e sem valor sai com 2, a mensagem nomeia a opcao, nenhuma chamada de rede e nenhum estado sao criados. | RF-186 |
| teste_blc_sync_variavel_invalida_nomeia_a_variavel_e_a_opcao_vence | `DBX_BLOCO` invalida (0, 1000001, texto, vazia, 01) sai com 2 nomeando a variavel e sem rede; com `--bloco 100` valido a opcao vence e a variavel nao e lida. | RF-186 |
| teste_blc_upload_e_download_de_pasta_validam_antes_da_rede | Upload e download de pasta recusam com 2, antes de qualquer rede, a opcao invalida e a variavel invalida (esta nomeada na mensagem). | RF-186 |
| teste_blc_upload_de_arquivo_unico_ignora_a_opcao_e_a_variavel_invalida | Upload de arquivo unico nao le a variavel invalida e aceita e ignora a opcao valida: so ha validacao onde ha pasta. | RF-186(e) |
| teste_blc_outro_comando_recusa_a_opcao_e_ignora_a_variavel | `list --bloco 5` sai com 2; com `DBX_BLOCO` invalida `list` ignora a variavel. | RF-186 |
| teste_blc_diagnostico_mostra_o_valor_efetivo_e_a_origem_da_variavel | `diagnostico` mostra a linha `bloco` com valor e origem (`7 (origem: ambiente, DBX_BLOCO)`), avisa nomeando a variavel quando invalida e nao a menciona quando ausente. | RF-186 |


## `tests/integracao/comandos_test.sh`

- **Alvo:** `bin/dbx` ponta a ponta (entrada, opcoes globais, credencial, autenticacao, transporte, analise e saida) e os comandos `upload`, `download`, `list`, `info`, `delete`, `space`, `config`, `unlink`
- **Modulo:** `comandos` (filtro do mapa de modulos; arquivo `tests/integracao/comandos_test.sh`)
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD; commit de criacao b2179b4 `feat(comandos): entrada fina com despacho por tabela literal`, anterior a trilha de logs de prompt)
- **Regras de origem:** Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** credencial em area temporaria propria por caso (`_ambiente`, sob `DBX_TESTES_TMP`), duble de `curl` que responde token no endpoint de autenticacao e o corpo dado nos demais; sem rede
- **Comando:** `bash tests/run.sh tests/integracao/comandos_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_ajuda_de_unlink_e_config_lista_os_dois_nomes | A ajuda de `unlink` e de `config` lista o nome em portugues e o alias em ingles | |
| teste_ajuda_geral_documenta_as_variaveis_de_rede_e_os_padroes | A ajuda geral documenta as variaveis de ajuste de rede e seus valores padrao | |
| teste_ajuda_geral_e_especifica_recomenda_pipefail_para_upload_por_fluxo | A ajuda geral e a de `upload` recomendam `set -o pipefail` ao enviar por entrada padrao | |
| teste_ajuste_de_rede_invalido_e_recusado_antes_de_qualquer_chamada | Variavel de ajuste de rede com valor invalido encerra com erro de uso sem chamar o cliente HTTP | |
| teste_alteracao_remota_concorrente_vira_conflito_e_nao_sobrescrita | Revisao remota alterada durante o envio resulta em conflito e o remoto nao e sobrescrito | |
| teste_comando_autenticado_apos_unlink_falha_com_erro_de_configuracao | Comando que exige credencial executado depois de `unlink` falha com erro de configuracao | |
| teste_comando_desconhecido_sai_com_uso_invalido | Comando inexistente encerra com o codigo de uso invalido | |
| teste_comando_do_bloco_seguinte_e_recusado_e_nao_silenciosamente_aceito | Comando de bloco ainda nao entregue e recusado explicitamente, nao aceito em silencio | |
| teste_config_aceita_entrada_sem_quebra_de_linha_final | `config` aceita o codigo de autorizacao lido sem quebra de linha final | |
| teste_config_aceita_sinalizador_debug_e_emite_diagnostico | `config --debug` e aceito e emite diagnostico no canal de erro | |
| teste_config_debug_emite_detalhe_em_falha_de_gravacao | Com `--debug`, falha de gravacao da credencial emite o detalhe operacional | |
| teste_config_em_simulacao_nao_toca_a_rede_nem_o_disco | `config` em simulacao nao chama a rede nem grava arquivo | |
| teste_config_grava_credencial_com_permissao_restrita | `config` grava o arquivo de credencial com modo restrito ao dono | |
| teste_config_nao_expoe_segredo_nem_codigo_na_linha_de_comando | Segredo e codigo de autorizacao nao aparecem na linha de comando do cliente HTTP | |
| teste_config_nao_sobrescreve_credencial_existente_sem_sinalizador | Credencial ja existente nao e substituida sem o sinalizador de substituicao | |
| teste_config_pede_autorizacao_offline_e_nao_ecoa_o_segredo | `config` pede a autorizacao sem rede e nao ecoa o segredo digitado | |
| teste_config_recusa_chave_que_nao_pertence_a_uma_url | Chave de aplicativo contendo caracteres de URL e recusada | |
| teste_config_recusa_resposta_sem_refresh_token_e_nao_grava_credencial | Resposta de autorizacao sem refresh token e recusada e nenhuma credencial e gravada | |
| teste_config_replace_substitui_como_substituir | O alias `--replace` tem o mesmo efeito de `--substituir` | |
| teste_config_roda_com_credencial_em_permissao_larga_e_info_nao | `config` executa mesmo com credencial de permissao ampla, mas `info` a recusa | |
| teste_config_root_tem_o_mesmo_efeito_de_raiz | `--root` tem o mesmo efeito de `--raiz` na gravacao da raiz remota | |
| teste_config_subcomando_aceita_sinalizador_debug | O sinalizador de depuracao e aceito depois do subcomando `config` | |
| teste_credencial_com_permissao_ampla_recusa_a_execucao | Credencial legivel por terceiros faz o comando recusar a execucao | |
| teste_delete_aceita_sinalizador_confirmar | `delete` aceita o sinalizador de confirmacao e prossegue | |
| teste_delete_com_rev_carrega_o_rev_esperado | `delete` com revisao esperada a envia na chamada da API | |
| teste_delete_conclui_e_emite_metadado | `delete` confirmado conclui e emite o metadado do item removido | |
| teste_delete_em_simulacao_nao_emite_escrita | `delete` em simulacao nao emite chamada de escrita | |
| teste_delete_exige_confirmacao_explicita | `delete` sem confirmacao explicita nao remove e sai com erro de uso | |
| teste_download_com_falha_de_escrita_em_arquivo_nao_culpa_consumidor | Falha ao gravar o arquivo de destino e reportada como erro local, nao como consumidor fechado | |
| teste_download_com_hash_conferido_substitui_e_nao_deixa_temporario | Download com resumo conferido substitui o destino e nao deixa temporario | |
| teste_download_com_hash_divergente_preserva_o_arquivo_anterior | Resumo divergente falha e preserva o arquivo anterior do destino | |
| teste_download_com_progresso_configura_progress_bar_no_cliente | Com progresso, o cliente HTTP recebe a opcao de barra de progresso | |
| teste_download_com_progresso_emite_em_stderr_e_preserva_stdout | O progresso do download vai para stderr e o stdout permanece so com o resultado | |
| teste_download_com_progresso_exibe_barra_grafica_em_stderr | A barra grafica de progresso do download aparece em stderr | |
| teste_download_cria_diretorio_de_destino_caso_nao_exista | Download cria o diretorio de destino ausente | |
| teste_download_cujo_alvo_perde_a_escrita_durante_o_recebimento_recusa | Alvo que perde a permissao de escrita durante o recebimento faz o download recusar sem corromper | |
| teste_download_de_pasta_com_progresso_nao_vaza_erro_bruto_do_cliente_em_stderr | Download de pasta com progresso nao repassa a mensagem bruta do cliente em stderr | |
| teste_download_de_pasta_sobre_arquivo_existente_recusa_e_preserva | Download de pasta cujo destino e um arquivo recusa e preserva o arquivo | |
| teste_download_de_pasta_transfere_recursivamente | Download de pasta transfere recursivamente todos os arquivos | |
| teste_download_grava_no_destino_e_relata_integridade | Download grava no destino e relata a integridade conferida | |
| teste_download_interrompido_por_sinal_remove_o_temporario | Sinal durante o download remove o arquivo temporario | |
| teste_download_interrompido_preserva_o_arquivo_anterior | Download interrompido mantem o arquivo anterior do destino intacto | |
| teste_download_nao_afirma_integridade_sem_resumo_do_servico | Sem resumo devolvido pelo servico, o download nao afirma integridade | |
| teste_download_para_consumidor_que_fecha_sai_com_codigo_proprio | Consumidor da saida padrao que fecha o cano faz o download sair com codigo proprio | |
| teste_download_para_o_hifen_escreve_so_o_conteudo_no_stdout | Destino `-` escreve apenas o conteudo no stdout | |
| teste_download_para_vinculo_simbolico_atualiza_o_arquivo_apontado | Destino que e vinculo simbolico tem o arquivo apontado atualizado, mantendo o vinculo | |
| teste_download_pasta_sem_destino_recusa_com_uso_invalido | Download de pasta sem destino sai com uso invalido | |
| teste_download_segue_o_umask_do_usuario | Arquivo novo baixado respeita o umask do usuario | |
| teste_download_sem_destino_escreve_so_o_conteudo_no_stdout | Download sem destino escreve so o conteudo no stdout | |
| teste_download_sem_destino_sobre_arquivo_com_conteudo_recusa_e_preserva | Saida redirecionada para arquivo com conteudo e recusada e o arquivo e preservado | |
| teste_download_sem_progresso_mantem_cliente_silencioso | Sem progresso, o cliente HTTP e invocado em modo silencioso | |
| teste_download_sobre_arquivo_existente_preserva_o_modo_dele | Download sobre arquivo existente preserva o modo dele | |
| teste_download_sobre_arquivo_somente_leitura_recusa_e_preserva | Destino somente leitura e recusado e o conteudo e preservado | |
| teste_erro_remoto_vira_codigo_da_taxonomia | Erros HTTP da API sao mapeados para o codigo de saida da taxonomia do projeto | |
| teste_estado_apos_upload_e_sync_so_contem_os_dois_namespaces | Apos upload e sync, o diretorio de estado contem apenas os dois namespaces previstos | |
| teste_info_emite_metadado_do_item | `info` emite o metadado do item consultado | |
| teste_info_sem_caminho_e_uso_invalido | `info` sem caminho sai com uso invalido | |
| teste_list_aceita_sinalizadores_em_portugues | `list` aceita os sinalizadores em portugues | |
| teste_list_e_info_emitem_o_mesmo_vocabulario_de_metadado | `list` e `info` emitem os mesmos campos de metadado | |
| teste_list_envia_content_type_json | `list` envia o cabecalho de tipo de conteudo JSON | |
| teste_list_envia_limite_explicito_em_toda_chamada | `list` envia o limite de itens explicito em toda chamada de paginacao | |
| teste_list_pagina_ate_o_fim_sem_truncar | `list` segue a paginacao ate o fim sem truncar a listagem | |
| teste_list_recusa_limite_fora_do_teto | `list` recusa limite acima do teto da API | |
| teste_segredo_nunca_aparece_na_saida_nem_no_diagnostico | Valor sentinela de segredo nao aparece em saida nem em diagnostico de nenhum comando | |
| teste_space_aceita_sinalizador_humano | `space` aceita o sinalizador de formato humano | |
| teste_space_legivel_por_humano_sob_sinalizador | `space` com o sinalizador imprime tamanhos legiveis por humano | |
| teste_space_percorre_o_caminho_completo | `space` percorre credencial, autenticacao, chamada e saida | |
| teste_terminador_nulo_nao_emite_quebra_de_linha | Com terminador nulo a saida nao emite quebra de linha | |
| teste_unlink_adverte_a_cascata_antes_de_agir | `unlink` adverte sobre a cascata de revogacao antes de agir | |
| teste_unlink_com_manter_aplicativo_preserva_a_chave_e_ainda_invalida_o_vinculo | `unlink --manter-aplicativo` preserva a chave do aplicativo e invalida o vinculo | |
| teste_unlink_com_revogacao_recusada_limpa_o_local_e_nao_sai_com_zero | Revogacao recusada pelo servico limpa o local e sai com codigo diferente de zero | |
| teste_unlink_em_simulacao_nao_revoga_nem_remove | `unlink` em simulacao nao revoga nem remove nada | |
| teste_unlink_keep_app_preserva_a_chave_como_manter_aplicativo | `--keep-app` tem o mesmo efeito de `--manter-aplicativo` | |
| teste_unlink_nao_apaga_atraves_de_ligacao_simbolica | `unlink` nao apaga alvo alcancado por ligacao simbolica | |
| teste_unlink_remove_memorias_temporarios_e_legado | `unlink` remove memorias de estado, temporarios e o legado | |
| teste_unlink_revoga_remove_credencial_e_bases | `unlink` revoga o token e remove a credencial e as bases de estado | |
| teste_unlink_sem_terminal_exige_sinalizador_explicito | Sem terminal, `unlink` exige confirmacao explicita por sinalizador | |
| teste_unlink_sem_yes_continua_recusado_sem_terminal | `unlink` sem `--yes` continua recusado quando nao ha terminal | |
| teste_unlink_yes_tem_o_mesmo_efeito_de_confirmar | `--yes` tem o mesmo efeito do sinalizador de confirmacao | |
| teste_upload_acerto_de_cache_renova_o_carimbo_de_uso | Dispensa por acerto de cache renova o carimbo de uso da entrada | |
| teste_upload_com_falha_na_consulta_do_metadado_envia | Falha na consulta do metadado remoto nao impede o envio | |
| teste_upload_com_modo_overwrite_segue_a_mesma_regra | Modo de escrita `overwrite` segue a mesma regra de comparacao | |
| teste_upload_com_progresso_analisa_arquivo_e_emite_resultado | Upload com progresso ainda analisa a resposta e emite o resultado | |
| teste_upload_com_progresso_configura_progress_bar_no_cliente | Upload com progresso configura a barra de progresso no cliente HTTP | |
| teste_upload_com_progresso_emite_em_stderr_e_preserva_stdout | O progresso do upload vai para stderr e o stdout so tem o resultado | |
| teste_upload_com_progresso_exibe_barra_grafica_em_stderr | A barra grafica do upload aparece em stderr | |
| teste_upload_com_remoto_ausente_envia_sem_calcular_o_resumo_local | Remoto ausente leva ao envio sem calcular o resumo local | |
| teste_upload_com_remoto_pasta_tenta_o_envio | Remoto que e pasta nao dispensa o envio; o envio e tentado | |
| teste_upload_com_rev_envia_em_update_sem_consulta_de_comparacao | Upload com revisao esperada envia em modo update sem consultar o remoto | |
| teste_upload_com_segredo_vazio_recusa_antes_da_rede_na_classe_de_rf03 | Segredo de aplicativo vazio recusa o upload antes de qualquer chamada, na classe de RF-03 | RF-03 |
| teste_upload_de_arquivo_abaixo_do_teto_vai_por_requisicao_unica | Arquivo abaixo do teto e enviado por uma unica requisicao | |
| teste_upload_de_arquivo_acima_do_teto_vai_por_sessao | Arquivo acima do teto e enviado por sessao de upload em partes | |
| teste_upload_de_arquivo_unico_mantem_mute_falso | Upload de arquivo unico mantem o indicador de notificacao silenciosa como falso | |
| teste_upload_de_diretorio_transfere_recursivamente | Upload de diretorio envia recursivamente todos os arquivos | |
| teste_upload_de_entrada_padrao_com_resumo_divergente_sai_por_integridade | Entrada padrao com resumo devolvido divergente sai com erro de integridade | |
| teste_upload_de_entrada_padrao_confere_o_resumo_devolvido_pelo_servico | Upload por entrada padrao confere o resumo devolvido pelo servico | |
| teste_upload_de_entrada_padrao_em_simulacao_nao_emite_chamada | Entrada padrao em simulacao nao emite chamada de rede | |
| teste_upload_de_entrada_padrao_percorre_a_sessao_em_partes | Entrada padrao percorre a sessao de upload em partes consecutivas | |
| teste_upload_define_client_modified_a_partir_do_mtime | `client_modified` enviado deriva do mtime do arquivo local | |
| teste_upload_dispensa_quando_o_hash_remoto_e_igual_ao_local | Hash remoto igual ao local dispensa o envio | |
| teste_upload_e_download_nao_montam_cabecalho_por_conta_propria | `upload` e `download` nao montam cabecalho HTTP por conta propria, so pela biblioteca | |
| teste_upload_em_simulacao_nao_invoca_o_cliente | `upload` em simulacao nao invoca o cliente HTTP | |
| teste_upload_envia_arquivo_e_publica_metadado | `upload` envia o arquivo e publica o metadado devolvido | |
| teste_upload_envia_quando_o_hash_remoto_difere | Hash remoto diferente do local leva ao envio | |
| teste_upload_falha_ao_gravar_o_cache_nao_muda_o_resultado | Falha ao gravar o cache nao altera o resultado nem o codigo de saida | |
| teste_upload_forcar_e_entrada_padrao_nao_consultam_o_metadado | Com `--forcar` ou entrada padrao o metadado remoto nao e consultado | |
| teste_upload_formata_client_modified_em_utc | `client_modified` e formatado em UTC no padrao esperado pela API | |
| teste_upload_grava_cache_proprio_e_nao_marca_o_par_do_sync_como_visto | O cache do upload e proprio e nao marca o par do sync como visto | |
| teste_upload_nao_dispensa_pelo_cache_quando_o_remoto_mudou_ou_sumiu | Remoto alterado ou ausente invalida o cache e o envio ocorre | |
| teste_upload_nao_grava_cache_quando_a_origem_muda_durante_o_envio | Origem alterada durante o envio nao grava cache | |
| teste_upload_nao_identifica_a_conta | `upload` nao consulta nem grava a identidade da conta | |
| teste_upload_nao_usa_sqlite_nem_python_e_preserva_o_legado | `upload` nao usa sqlite nem python e preserva o arquivo legado de cache | |
| teste_upload_nomeia_classe_e_motivo_quando_a_resposta_da_consulta_e_ilegivel | Resposta ilegivel da consulta gera mensagem com classe e motivo | |
| teste_upload_por_sessao_grava_o_hash_do_canal_de_conteudo | Upload por sessao grava o hash calculado sobre o canal de conteudo | |
| teste_upload_reescrita_no_mesmo_segundo_com_remoto_antigo_envia | Arquivo reescrito no mesmo segundo com remoto antigo ainda e enviado | |
| teste_upload_relativo_absoluto_e_ligacao_usam_o_mesmo_cache | Caminho relativo, absoluto e por ligacao usam a mesma entrada de cache | |
| teste_upload_sem_cache_para_arquivo_recente_vazio_ou_fluxo | Arquivo recente, vazio ou por fluxo nao e dispensado por cache | |
| teste_upload_sem_progresso_mantem_cliente_silencioso | Sem progresso, o cliente HTTP do upload e silencioso | |
| teste_versao_nao_exige_ambiente_nem_credencial | `versao` funciona sem credencial nem ambiente configurado | |


## `tests/integracao/compartilhar_test.sh`

- **Alvo:** `bin/dbx` nos comandos `link-temporario` (`temp-link`) e `compartilhar` (`share`) em todos os modos (criar, reusar, modificar, `--listar`, `--revogar`, `--dry-run`, `--json`, `--null`, `--debug`); `commands/link_temporario.sh`, `commands/compartilhar.sh`, `lib/compartilhamento.sh`
- **Modulo:** compartilhar_test
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-5-compartilhamento`)
- **Regras de origem:** F-15; F-16; RF-84..RF-92; RF-86(g); TC-LTP; TC-CMP; TC-SNH; TC-LEX; TC-LST; TC-RVG; TC-SHE; TC-CPL-10; TC-DOC-04; TC-TST-08; DIV-117; DIV-123; log `docs/prompts/2026-10-20_1110_backlog-fase-5-compartilhamento.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de `curl` por regra (`endpoint`, filtro do corpo, codigo, arquivo) que registra corpo, `argv`, ambiente e entrada de opcoes `-K -`, com chamada sem regra respondendo 400 marcada `SEM_REGRA`; senha sintetica com sentinela; terminal simulado nos casos de senha; credencial sintetica
- **Comando:** `bash tests/run.sh tests/integracao/compartilhar_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_ltp01_arquivo_valido_gera_link_com_validade_e_metadados | Arquivo valido gera link temporario com validade e metadados | TC-LTP-01 |
| teste_ltp02_uso_invalido_sem_rede | Uso invalido do `link-temporario` sai como erro de uso sem chamada de rede | TC-LTP-02 |
| teste_ltp03_fora_da_raiz_e_controle_sao_recusados_sem_chamada | Caminho fora da raiz ou com caracteres de controle e recusado sem chamada | TC-LTP-03 |
| teste_ltp04_pasta_tipo_sem_link_e_inexistente | Pasta, tipo nao suportado, resposta sem link e arquivo inexistente falham com o codigo proprio de cada caso | TC-LTP-04 |
| teste_ltp05_permissao_e_escopo | Falta de permissao ou de escopo e reportada com o codigo e o remedio do caso | TC-LTP-05 |
| teste_ltp06_resposta_sem_path_lower_repetida_ou_fora_da_raiz_nao_imprime_o_link | Resposta sem `path_lower`, repetida ou fora da raiz nao imprime o link | TC-LTP-06 |
| teste_ltp07_dry_run_so_consulta_metadado | `--dry-run` so consulta o metadado e nao cria link | TC-LTP-07 |
| teste_ltp08_link_so_no_resultado_nunca_em_stderr_nem_debug | O link aparece so no resultado, nunca em stderr nem no `--debug` | TC-LTP-08 |
| teste_ltp09_json_null_mesmos_campos_e_nenhum_date | `--json` e `--null` trazem os mesmos campos e nao chamam `date` | TC-LTP-09 |
| teste_ltp10_alias_sem_estado_e_sem_trava | O alias `temp-link` funciona sem estado local e sem trava | TC-LTP-10 |
| teste_cmp01_sem_visibilidade_e_uso_invalido_antes_de_tudo | `compartilhar` sem visibilidade sai como uso invalido antes de qualquer acao | TC-CMP-01 |
| teste_cmp02_publico_cria_com_audience_public_sem_campo_depreciado | `--publico` cria o link com `audience` public e sem o campo depreciado | TC-CMP-02 |
| teste_cmp03_equipe_usa_audience_team | `--equipe` usa `audience` team | TC-CMP-03 |
| teste_cmp04_combinacoes_invalidas_sao_uso_invalido_sem_rede | Combinacoes invalidas de opcoes sao uso invalido, sem rede | TC-CMP-04 |
| teste_cmp04_publico_com_senha_equivale_a_senha | `--publico` com senha equivale a `--senha` | TC-CMP-04 |
| teste_cmp05_expira_validas_viram_expires_normalizado_no_corpo | `--expira` valido vira `expires` normalizado no corpo da chamada | TC-CMP-05 |
| teste_cmp06_07_expira_invalida_ou_no_passado_sem_rede | `--expira` invalido ou no passado e recusado sem rede | TC-CMP-06; TC-CMP-07 |
| teste_cmp08_fora_da_raiz_antes_da_senha_e_sem_rede | Caminho fora da raiz e recusado antes de pedir a senha e sem rede | TC-CMP-08 |
| teste_cmp09_raiz_da_conta_e_recusada_e_a_raiz_remota_e_alvo_valido | A raiz da conta e recusada como alvo, mas a raiz remota configurada e alvo valido | TC-CMP-09 |
| teste_cmp11_visibilidade_resolvida_diferente_avisa_e_sai_zero | Visibilidade resolvida diferente da pedida avisa e sai com 0 | TC-CMP-11 |
| teste_cmp12_dry_run_so_lista_e_nao_le_a_senha | `--dry-run` so lista e nao le a senha | TC-CMP-12 |
| teste_cmp13_json_e_null_com_os_campos | `--json` e `--null` emitem os campos esperados | TC-CMP-13 |
| teste_cmp14_she02_conta_sem_permissao_de_configuracao_sai_6_com_remedio | Conta sem permissao de configuracao sai com 6 e informa o remedio | TC-CMP-14; TC-SHE-02 |
| teste_cmp15_aliases_em_ingles | Os aliases em ingles de `compartilhar` funcionam como os nomes em portugues | TC-CMP-15 |
| teste_cmp16_nada_em_lib_state_nem_trava | `compartilhar` nao grava estado nem adquire trava | TC-CMP-16 |
| teste_snh01_terminal_pergunta_duas_vezes_sem_eco_e_envia_no_corpo | Em terminal, a senha e pedida duas vezes sem eco e enviada no corpo | TC-SNH-01 |
| teste_snh02_confirmacao_divergente_sai_14_sem_chamada | Confirmacao de senha divergente sai com 14 sem chamada | TC-SNH-02 |
| teste_snh03_senha_sem_terminal_e_uso_invalido | Senha pedida sem terminal e uso invalido | TC-SNH-03 |
| teste_snh04_senha_stdin_le_so_a_primeira_linha | Senha por stdin le apenas a primeira linha | TC-SNH-04 |
| teste_snh05_06_senha_invalida_e_recusada_sem_rede_e_sem_citar | Senha invalida e recusada sem rede e sem ser citada na mensagem | TC-SNH-05; TC-SNH-06 |
| teste_snh07_senha_na_linha_de_comando_e_recusada_sem_citar | Senha na linha de comando e recusada sem ser citada | TC-SNH-07 |
| teste_snh08_variavel_de_ambiente_e_ignorada | Senha em variavel de ambiente e ignorada | TC-SNH-08 |
| teste_snh09_10_sentinela_so_no_corpo_em_sucesso_e_em_erro | O sentinela da senha aparece so no corpo da chamada, em sucesso e em erro, nunca no `argv` nem no ambiente | TC-SNH-09; TC-SNH-10 |
| teste_snh11_corpo_de_erro_que_ecoa_a_senha_e_mascarado | Corpo de erro que ecoa a senha e mascarado na saida | TC-SNH-11 |
| teste_snh12_term_durante_a_chamada_nao_deixa_arquivo | SIGTERM durante a chamada nao deixa arquivo com a senha | TC-SNH-12 |
| teste_snh13_sinal_durante_a_leitura_restaura_o_eco_e_sai_14 | Sinal durante a leitura da senha restaura o eco do terminal e sai com 14 | TC-SNH-13 |
| teste_snh14_senha_com_caracteres_especiais_chega_identica | Senha com caracteres especiais chega identica ao corpo | TC-SNH-14 |
| teste_lex01_estado_igual_reusa_sem_escrita | Link existente com o mesmo estado e reusado sem escrita | TC-LEX-01 |
| teste_lex02_metadados_no_erro_nao_dispensam_a_listagem | Metadados vindos no erro de criacao nao dispensam a listagem de links | TC-LEX-02 |
| teste_lex03_link_de_ancestral_nao_e_candidato | Link de pasta ancestral nao e candidato ao reuso | TC-LEX-03 |
| teste_lex04_nenhum_candidato_sai_10 | Nenhum link candidato apos o erro de criacao sai com 10 | TC-LEX-04 |
| teste_lex05_dois_candidatos_sai_7_com_as_urls | Dois candidatos saem com 7 e mostram as URLs | TC-LEX-05 |
| teste_lex06_visibilidade_diferente_modifica_e_mostra_o_depois_da_resposta | Visibilidade diferente modifica o link e mostra o estado depois da resposta | TC-LEX-06 |
| teste_lex07_expiracao_so_comparada_quando_dada | A expiracao so e comparada quando pedida | TC-LEX-07 |
| teste_lex08_senha_sobre_link_existente_sempre_redefine | Senha sobre link existente sempre redefine a senha | TC-LEX-08 |
| teste_lex09_10_publico_sobre_link_com_senha_remove_e_avisa_exposicao | `--publico` sobre link com senha remove a senha e avisa da exposicao | TC-LEX-09; TC-LEX-10 |
| teste_lex11_dry_run_mostra_antes_e_depois_previsto_sem_modify | `--dry-run` mostra o antes e o depois previsto sem chamar modify | TC-LEX-11 |
| teste_lex12_link_revogado_entre_listagem_e_modify_sai_4 | Link revogado entre a listagem e o modify sai com 4 | TC-LEX-12 |
| teste_lex_missing_scope_sharing_read_na_listagem_sai_5 | Falta do escopo `sharing.read` na listagem sai com 5 | TC-LEX |
| teste_lst01_segue_o_cursor_sem_path_ate_o_fim | `--listar` segue o cursor sem `path` ate o fim da listagem | TC-LST-01 |
| teste_lst02_03_sem_argumento_usa_a_raiz_e_omite_fora_e_sem_path_lower | `--listar` sem argumento usa a raiz e omite itens fora dela e sem `path_lower` | TC-LST-02; TC-LST-03 |
| teste_lst04_05_pasta_por_componente_e_caixa | Filtro de pasta casa por componente de caminho e sem diferenciar caixa | TC-LST-04; TC-LST-05 |
| teste_lst06_cursor_repetido_sai_10_e_reset_14 | Cursor repetido sai com 10 e reset de cursor sai com 14 | TC-LST-06 |
| teste_lst07_08_vazia_e_recusas_de_argumento | Listagem vazia sai com 0 e argumentos invalidos sao recusados | TC-LST-07; TC-LST-08 |
| teste_div123_caminho_relativo_e_uso_invalido_em_todo_modo | Caminho relativo e uso invalido em todos os modos | DIV-123 |
| teste_lst09_json_null_e_ordem_pela_chave_sem_caixa | `--listar` com `--json` e `--null` ordena pela chave sem diferenciar caixa | TC-LST-09 |
| teste_lst10_missing_scope_sharing_read_e_nenhuma_escrita | Falta do escopo `sharing.read` na listagem nao faz nenhuma escrita | TC-LST-10 |
| teste_rvg01_link_dentro_da_raiz_e_revogado | Link dentro da raiz e revogado | TC-RVG-01 |
| teste_rvg02_fora_da_raiz_sai_13_sem_revoke | Link fora da raiz sai com 13 sem chamar revoke | TC-RVG-02 |
| teste_rvg03_sem_path_lower_sai_13_mesmo_com_raiz_da_conta | Link sem `path_lower` sai com 13 mesmo com a raiz da conta | TC-RVG-03 |
| teste_rvg04_guarda_sem_estado_ignora_estado_local_adulterado | A guarda de revogacao nao depende de estado e ignora estado local adulterado | TC-RVG-04 |
| teste_rvg05_path_lower_vazio_repetido_ou_malformado_sai_10 | `path_lower` vazio, repetido ou malformado sai com 10 | TC-RVG-05 |
| teste_rvg06_07_url_invalida_ou_temporaria_sem_rede | URL invalida ou de link temporario e recusada sem rede | TC-RVG-06; TC-RVG-07 |
| teste_rvg08_dry_run_executa_a_guarda_sem_revogar | `--dry-run` executa a guarda sem revogar | TC-RVG-08 |
| teste_rvg09_10_link_inexistente_e_de_outro_membro | Link inexistente ou de outro membro e tratado com o codigo proprio | TC-RVG-09; TC-RVG-10 |
| teste_rvg12_raiz_x_nao_esta_em_raiz | Raiz `x` nao esta contida na raiz `x/y` de outro nome (prefixo textual nao basta) | TC-RVG-12 |
| teste_she03_04_invalid_settings_e_missing_scope_de_escrita | `invalid_settings` e falta de escopo de escrita sao tratados com codigo e remedio | TC-SHE-03; TC-SHE-04 |
| teste_she05_resposta_perdida_e_retentativa_com_link_existente_segue_o_reuso | Resposta perdida seguida de retentativa com link existente segue o reuso | TC-SHE-05 |
| teste_qab5_04_recusa_de_url_nao_cita_credencial_embutida | Recusa de URL nao cita credencial embutida nela | TC-QAB5-04 |
| teste_qab5_05_arquivo_de_corpo_com_a_senha_nasce_0600 | O arquivo de corpo com a senha nasce com modo 0600 | TC-QAB5-05 |
| teste_qab5_06_link_temporario_com_controle_sai_10_sem_imprimir | Link temporario com caractere de controle sai com 10 sem imprimir | TC-QAB5-06 |
| teste_qab5_07_resposta_sem_url_sai_10 | Resposta sem URL sai com 10 | TC-QAB5-07 |
| teste_qab5_13_link_reusado_sem_url_sai_10 | Link reusado sem URL sai com 10 | TC-QAB5-13 |
| teste_qab5_14_listar_tem_teto_de_1000_paginas | A listagem tem teto de 1000 paginas | TC-QAB5-14 |
| teste_qab5_15_link_temporario_com_espaco_sai_10 | Link temporario com espaco sai com 10 | TC-QAB5-15 |
| teste_qab5_16_password_sem_require_password_e_incoerente | Resposta com senha sem `require_password` e incoerente e falha | TC-QAB5-16 |
| teste_qab5_17_tag_igual_a_senha_nao_e_citada | Marca igual a senha nao e citada na mensagem | TC-QAB5-17 |
| teste_qab5_18_url_ou_link_fora_do_ascii_imprimivel_sai_10 | URL ou link fora do ASCII imprimivel sai com 10 | TC-QAB5-18 |
| teste_qab5_19_coerencia_entre_visibilidade_e_senha | Visibilidade e senha precisam ser coerentes entre si | TC-QAB5-19 |
| teste_cpl10_opcoes_da_ajuda_e_do_autocompletar_coincidem | As opcoes da ajuda e as do autocompletar coincidem | TC-CPL-10 |
| teste_doc04_ajuda_e_readme_trazem_as_frases | A ajuda e o README trazem as frases obrigatorias do compartilhamento | TC-DOC-04 |
| teste_tst08_mapa_de_modulos_tem_as_entradas_da_fase | O mapa de modulos tem as entradas da fase de compartilhamento | TC-TST-08 |
| teste_ponto_unico_vem_antes_de_qualquer_rede_nos_comandos_novos | O ponto unico de validacao de caminho roda antes de qualquer rede nos comandos novos | RF-84 |


## `tests/integracao/completar_test.sh`

- **Alvo:** `completions/dbx.bash`, `commands/completar.sh` (`dbx completar bash`), `install.sh`, `uninstall.sh` e `scripts/empacotar.sh`, confrontados com a ajuda real de `bin/dbx`
- **Modulo:** completar
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-1-consulta-diagnostico`)
- **Regras de origem:** RF-68; TC-CPL-01..08; log `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** ajuda real lida de `dbx help` e `dbx help <comando>` como fonte unica; areas temporarias de usuario para `install.sh` e `uninstall.sh`; copia do projeto para o empacotamento; scripts mutantes para a prova de discriminacao
- **Comando:** `bash tests/run.sh tests/integracao/completar_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_cpl01_completa_comandos_aliases_e_help_conforme_a_ajuda | O autocompletar oferece exatamente os comandos, aliases e `help` que a ajuda lista | TC-CPL-01 |
| teste_cpl01_completa_as_opcoes_globais_conforme_a_ajuda | O autocompletar oferece exatamente as opcoes globais da ajuda | TC-CPL-01 |
| teste_cpl02_opcoes_de_cada_comando_coincidem_com_a_ajuda | Para cada comando, as opcoes completadas coincidem com as da ajuda dele | TC-CPL-02 |
| teste_cpl02_toda_opcao_da_ajuda_existe_no_codigo_do_comando | Toda opcao documentada na ajuda existe no codigo do comando (nenhuma opcao fantasma) | TC-CPL-02 |
| teste_cpl08_revisoes_restaurar_lixeira_coincidem_com_a_ajuda | Os comandos revisoes, restaurar e lixeira completam as mesmas opcoes que a ajuda | TC-CPL-08 |
| teste_cpl02_a_conferencia_reprova_opcao_de_um_lado_so | Script mutante com opcao a mais ou a menos diverge da ajuda e reprova a conferencia | TC-CPL-02 |
| teste_cpl03_caminho_local_com_espaco_e_acento | Caminho local com espaco e acento e completado corretamente | TC-CPL-03 |
| teste_cpl03_caminho_remoto_nao_e_completado | Caminho remoto nao e completado e nao dispara consulta | TC-CPL-03 |
| teste_cpl04_nenhuma_invocacao_de_curl_nem_leitura_de_credencial | Completar nao invoca curl nem le a credencial | TC-CPL-04 |
| teste_cpl04_carregar_nao_imprime_nem_muda_opcoes_do_shell | Carregar o script nao imprime nada nem altera as opcoes do shell | TC-CPL-04 |
| teste_cpl05_completar_bash_imprime_o_script_identico | `dbx completar bash` imprime script identico ao arquivo versionado | TC-CPL-05 |
| teste_cpl05_sem_argumento_ou_outro_shell_e_uso_invalido | `dbx completar` sem argumento ou com outro shell sai como uso invalido | TC-CPL-05 |
| teste_cpl05_roda_onde_o_preflight_recusaria | `dbx completar bash` roda mesmo onde o preflight recusaria o ambiente | TC-CPL-05 |
| teste_cpl06_install_poe_o_script_no_diretorio_do_usuario_sem_sudo | `install.sh` instala o script no diretorio do usuario sem sudo | TC-CPL-06 |
| teste_cpl06_prefix_e_uninstall | `install.sh` respeita `--prefix` e o desinstalador remove o que instalou | TC-CPL-06 |
| teste_cpl06_uninstall_sh_remove_so_o_autocompletar_do_dbx | `uninstall.sh` remove apenas o autocompletar do dbx e preserva os demais | TC-CPL-06 |
| teste_cpl07_pacote_contem_o_script | O pacote gerado por `scripts/empacotar.sh` contem o script de autocompletar | TC-CPL-07 |


## `tests/integracao/composicao_test.sh`

- **Alvo:** `lib/*.sh`, `commands/*.sh` e `lib/cmd.sh` em composicao (auditorias entre componentes: ponto unico do caminho remoto, taxonomia de saida, redacao, prefixos e estado persistente)
- **Modulo:** `composicao`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD; commit `f4e645d` "test: auditoria de procedencia e suite de integracao", sem log de prompt)
- **Regras de origem:** QF-01 (defeito que so existia em cadeia); RNF-24 (auditoria de procedencia); `docs/testes/mapa-modulos.md` (Regra 1: todo diff em `lib/*.sh` seleciona `composicao`)
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** Nao aplicavel: carrega as libs e audita o texto do repositorio; arquivos temporarios do harness em `TMPDIR` da suite
- **Comando:** `bash tests/run.sh tests/integracao/composicao_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_ambos_os_canais_de_saida_recusam_valor_que_parte_o_registro | Valor com separador de registro e recusado pelos dois canais de saida (texto e `--null`), sem partir o registro | |
| teste_auditoria_de_gemeos_detecta_guarda_nova_em_um_lado_so | A auditoria de gemeos reprova quando uma guarda nova existe em um caminho e nao no irmao | |
| teste_auditoria_do_ponto_unico_discrimina | A auditoria do ponto unico distingue chamada correta de desvio, nao aprova nem reprova tudo | |
| teste_auxiliar_de_contagem_discrimina | A auditoria do auxiliar de contagem distingue uso correto de uso direto indevido | |
| teste_cadeia_json_para_saida_preserva_o_valor | Valor passado do JSON para a saida chega identico, sem perda nem escape duplo | |
| teste_canal_de_corpo_nunca_e_alimentado_na_apresentacao | O canal de corpo de resposta nunca recebe dado da camada de apresentacao | |
| teste_canal_publico_alheio_com_dado_de_credencial_e_limpo_por_quem_o_encheu | Canal publico que recebeu dado de credencial e limpo por quem o preencheu antes de seguir | |
| teste_carga_multipla_e_idempotente | Carregar a mesma lib mais de uma vez nao altera o estado nem falha | |
| teste_codigos_de_saida_concordam_entre_componentes | Os componentes usam os mesmos codigos de saida da taxonomia | |
| teste_codigos_de_saida_de_preflight_e_config_concordam_com_a_taxonomia | Preflight e config devolvem codigos de saida iguais aos da taxonomia | |
| teste_comandos_da_recuperacao_passam_pelo_ponto_unico | Revisoes, restaurar e lixeira resolvem o caminho remoto pelo ponto unico | |
| teste_config_nao_destroi_documento_de_outro_contexto | Gravar o config preserva documentos de outro contexto no mesmo arquivo | |
| teste_contagem_sobre_arquivo_passa_pelo_auxiliar | Contagem sobre arquivo usa o auxiliar comum, sem reimplementacao local | |
| teste_credencial_gravada_e_integralmente_redigida_pela_taxonomia | Credencial gravada e mascarada por inteiro pela redacao da taxonomia | |
| teste_documentacao_nao_contradiz_o_estado_persistente_nem_as_dependencias | A documentacao concorda com o estado persistente real e com as dependencias declaradas | |
| teste_gemeos_aplicam_o_mesmo_conjunto_de_guardas_de_metadado | Os caminhos gemeos aplicam o mesmo conjunto de guardas sobre o metadado remoto | QF-01 |
| teste_gemeos_decidem_igual_em_todo_o_espaco_de_permissao | Os gemeos decidem igual para toda combinacao de permissao do arquivo | QF-01 |
| teste_nenhum_canal_emite_registro_forjado_antes_de_recusar | Nenhum canal escreve registro forjado antes de recusar o valor | |
| teste_nenhum_componente_novo_introduz_estado_persistente | Nenhum componente novo grava estado persistente fora do declarado | |
| teste_nenhum_sitio_de_chamada_deriva_contexto_de_dado_externo | Nenhuma chamada deriva o contexto de erro de dado vindo de fora | |
| teste_nenhuma_funcao_publica_colide | Nao existem duas funcoes publicas com o mesmo nome entre as libs | |
| teste_nenhuma_global_sem_prefixo_do_projeto | Toda variavel global das libs tem o prefixo do projeto | |
| teste_preflight_e_config_entram_em_qualquer_ordem_de_carregamento | Preflight e config funcionam carregados em qualquer ordem | |
| teste_qualquer_ordem_de_carregamento_funciona | As libs podem ser carregadas em qualquer ordem sem erro | |
| teste_tags_reais_da_dropbox_seriam_recusadas_como_contexto | Tags reais de erro da Dropbox, usadas como contexto, seriam recusadas | |
| teste_toda_consulta_de_json_recusa_sem_documento_analisado | Toda consulta de JSON recusa quando nenhum documento foi analisado | |
| teste_toda_funcao_publica_tem_prefixo_do_projeto | Toda funcao publica das libs tem o prefixo do projeto | |
| teste_todo_caminho_remoto_de_comando_passa_pelo_ponto_unico | Todo comando que usa caminho remoto o resolve pelo ponto unico de confinamento | fase 1b do backlog |


## `tests/integracao/confinamento_remoto_test.sh`

- **Alvo:** `bin/dbx` (todos os comandos com caminho remoto), `lib/cmd.sh` (`dbx_cmd_remoto_confinado`), `lib/path.sh`: confinamento a `raiz_remota` e recusa de byte de controle em caminho remoto
- **Modulo:** confinamento_remoto
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-1b-confinamento-remoto`)
- **Regras de origem:** F-36, RNF-20(b1..b6), TC-SEC-18..27; F-37, RNF-10(b), TC-SEC-28..29; protocolo-tdd Regra 6 (cenarios negativos de acesso); log `docs/prompts/2026-10-19_1243_backlog-fase-1b-confinamento-remoto.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` que grava log de chamadas (na recusa o log nao existe); diretorios temporarios por caso; credencial sintetica com raiz de conta configuravel; sem rede
- **Comando:** `bash tests/run.sh tests/integracao/confinamento_remoto_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_sec18_24_fora_da_raiz_e_recusado_em_todo_comando_sem_chamada | Caminho remoto fora da raiz configurada e recusado por todo comando, sem nenhuma chamada a API (nem renovacao de token) | TC-SEC-18, TC-SEC-24 |
| teste_sec18_raiz_da_conta_fora_da_raiz_configurada_e_recusada | A raiz da conta (`/`) quando ha raiz configurada diferente e tratada como fora do confinamento e recusada | TC-SEC-18 |
| teste_sec25_26_dentro_da_raiz_e_aceito_em_todo_comando | Caminho dentro da raiz configurada e aceito por todo comando e a chamada sai com o caminho completo | TC-SEC-25, TC-SEC-26 |
| teste_sec25_derivado_do_download_de_pasta_fica_dentro_da_raiz | Caminhos derivados ao baixar uma pasta permanecem dentro da raiz configurada | TC-SEC-25 |
| teste_sec25_derivado_do_upload_de_diretorio_fica_dentro_da_raiz | Caminhos derivados ao enviar um diretorio permanecem dentro da raiz configurada | TC-SEC-25 |
| teste_sec26_caixa_fora_do_ascii_nao_escapa_em_nenhuma_localidade | Letras fora do ASCII com caixa diferente nao permitem escapar da raiz, qualquer que seja a localidade do processo | TC-SEC-26 |
| teste_sec26_list_sem_argumento_lista_a_raiz_configurada | `list` sem argumento lista a raiz configurada e nao a raiz da conta | TC-SEC-26 |
| teste_sec27_raiz_da_conta_nao_recusa_caminho_valido | Sem raiz configurada (raiz da conta) um caminho valido nao e recusado | TC-SEC-27 |
| teste_sec27_raiz_malformada_na_credencial_falha_fechado | Raiz malformada na credencial faz o comando falhar fechado, sem chamada a API | TC-SEC-27 |
| teste_sec28_quebra_de_linha_e_recusada_em_todo_comando_sem_chamada | Quebra de linha em caminho remoto e recusada em todo comando antes de qualquer chamada | TC-SEC-28 |
| teste_sec29_demais_bytes_de_controle_sao_recusados | Os demais bytes de controle (ESC, NUL-like, DEL e semelhantes) em caminho remoto tambem sao recusados | TC-SEC-29 |
| teste_sec31_raiz_com_controle_e_list_sem_argumento_sai_3 | Raiz configurada com byte de controle faz `list` sem argumento sair com codigo 3 | TC-SEC-31 |


## `tests/integracao/cursor_test.sh`

- **Alvo:** `bin/dbx sync --receber` com cursor de listagem (`commands/sync.sh`, `lib/state.sh`, `lib/sync.sh`), incluindo `--dry-run`, `--json`, `--null`, `--debug`, `verificar`, `download` de pasta, `unlink`, `diagnostico` e `help sync`
- **Modulo:** `cursor`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-7b-cursor`)
- **Regras de origem:** RF-110..RF-119; TC-CUA, TC-CUR, TC-CUV, TC-CUF, TC-CUD, TC-CUM, TC-CUS, TC-CUL, TC-CUO; F-14; parecer do DBA (C1 a C11); log `docs/prompts/2026-10-21_0713_backlog-fase-7b-cursor.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` por regras (endpoint, corpo e resposta por cenario) com registro de chamadas; `XDG_STATE_HOME` e raiz de sync temporarios por caso; servidor simulado com mapa remoto e cursor
- **Comando:** `bash tests/run.sh tests/integracao/cursor_test.sh`
- **Observacoes (demanda `sync-em-blocos`):** o duplo de `curl` passou a responder `list_folder` nao recursivo e `get_latest_cursor` (RF-189); nenhum caso foi criado ou removido.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_cua02_03_enviar_verificar_e_download_de_pasta_nao_tocam_o_registro | `--enviar`, `verificar` e `download` de pasta nao criam nem alteram o registro do cursor | TC-CUA-02, TC-CUA-03 |
| teste_cua04_cur01_primeira_execucao_completa_grava_registro_0600 | A primeira execucao faz varredura completa e grava o registro com modo 0600 | TC-CUA-04, TC-CUR-01 |
| teste_cud01_02_deleted_confirmado_apaga_so_com_espelhar | Item `deleted` confirmado como nao encontrado so e apagado localmente com `--espelhar` | TC-CUD-01, TC-CUD-02 |
| teste_cud03_04_contradicao_nunca_apaga_e_volta_a_completa | Contradicao entre delta e confirmacao nao apaga nada e volta a varredura completa | TC-CUD-03, TC-CUD-04 |
| teste_cud05_cus02_retrato_que_omite_arquivo_nao_apaga | Retrato que omite um arquivo nao causa exclusao local dele | TC-CUD-05, TC-CUS-02 |
| teste_cud06_falha_na_confirmacao_falha_sem_plano_e_sem_escrita | Falha na confirmacao de exclusao termina em erro, sem plano e sem escrita local | TC-CUD-06 |
| teste_cud07_deleted_desconhecido_e_ignorado | Entrada `deleted` de item que o retrato nao conhece e ignorada | TC-CUD-07 |
| teste_cud08_pasta_apagada_uma_confirmacao_cobre_os_descendentes | Pasta apagada exige uma confirmacao que cobre todos os descendentes | TC-CUD-08 |
| teste_cud09_cuf10_cinquenta_confirmacoes_e_cinquenta_e_uma | Ate 50 confirmacoes seguem no incremental; a 51a leva a varredura completa | TC-CUD-09, TC-CUF-10 |
| teste_cud10_cus10_guardas_valem_com_cursor | As guardas de exclusao do espelho continuam valendo no modo incremental | TC-CUD-10, TC-CUS-10 |
| teste_cud13_cul01_simulacao_confirma_e_nao_grava_nem_apaga | `--dry-run` confirma exclusoes no servidor mas nao grava registro nem apaga | TC-CUD-13, TC-CUL-01 |
| teste_cuf01_cuf12_reset_varredura_completa_zero_e_memoria_intacta | Resposta `reset` leva a varredura completa, codigo 0 e memoria local intacta | TC-CUF-01, TC-CUF-12 |
| teste_cuf02_outro_409_e_4xx_voltam_a_varredura_completa | Outro 409 ou 4xx no continue volta a varredura completa | TC-CUF-02 |
| teste_cuf03_04_transitorio_no_continue_e_completa_que_tambem_falha | Erro transitorio no continue cai na completa; se ela tambem falha, a execucao falha | TC-CUF-03, TC-CUF-04 |
| teste_cuf05_401_no_continue_mantem_a_classe_5 | 401 no continue mantem a classe de erro 5 (credencial) | TC-CUF-05 |
| teste_cuf06_cursor_repetido_e_laco_abandonam_o_incremental | Cursor repetido ou laco de paginas abandona o incremental | TC-CUF-06 |
| teste_cuf07_08_varredura_periodica_obrigatoria | Registro com varredura completa vencida forca nova varredura completa | TC-CUF-07, TC-CUF-08 |
| teste_cuf09_cuo01_02_05_forcada_e_desligado | Opcao de varredura completa forcada e o desligamento do cursor ignoram o registro | TC-CUF-09, TC-CUO-01, TC-CUO-02, TC-CUO-05 |
| teste_cuf11_cus05_mapa_vazio_com_retrato_nao_vazio_vai_a_completa | Mapa local vazio com retrato nao vazio vai a varredura completa | TC-CUF-11, TC-CUS-05 |
| teste_cuf12_cursor_sem_memoria_ainda_exige_o_reconhecimento | Cursor sem memoria local ainda exige o reconhecimento do estado antes de usar | TC-CUF-12 |
| teste_cul02_simulacao_sem_registro_nao_cria | `--dry-run` sem registro previo nao cria registro | TC-CUL-02 |
| teste_cul06_unlink_remove_cursor | `unlink` remove o registro de cursor | TC-CUL-06 |
| teste_cul08_diagnostico_le_so_o_cabecalho | `diagnostico` le apenas o cabecalho do registro de cursor | TC-CUL-08 |
| teste_cul09_poda_101_registros_e_mais_de_8_dias | A poda remove registros acima de 100 e os com mais de 8 dias | TC-CUL-09 |
| teste_cul11_varredura_completa_de_duas_paginas_continue_sem_limit | Varredura completa de duas paginas usa `list_folder/continue` sem limite indevido | TC-CUL-11 |
| teste_cuo03_04_opcoes_invalidas_saem_2_antes_do_estado | Opcoes de cursor invalidas saem com codigo 2 antes de tocar o estado | TC-CUO-03, TC-CUO-04 |
| teste_cuo06_campos_em_texto_json_e_null | Os campos do cursor aparecem nas saidas de texto, `--json` e `--null` | TC-CUO-06 |
| teste_cuo09_10_11_ajuda_readme_e_autocompletar | Ajuda, README e autocompletar descrevem as opcoes de cursor | TC-CUO-09, TC-CUO-10, TC-CUO-11 |
| teste_cur05_06_registro_invalido_e_descartado_com_aviso_e_codigo_0 | Registro invalido e descartado com aviso e a execucao termina com codigo 0 | TC-CUR-05, TC-CUR-06 |
| teste_cur07_fifo_e_ligacao_no_lugar_do_registro_nao_sao_lidos | Fifo ou vinculo simbolico no lugar do registro nao e lido | TC-CUR-07 |
| teste_cur08_cuo08_cursor_nunca_sai_do_processo | O valor do cursor nunca aparece em argv, ambiente, saida nem log | TC-CUR-08, TC-CUO-08 |
| teste_cur10_cuv06_falha_nao_avanca_o_registro | Execucao que falha nao avanca o cursor gravado | TC-CUR-10, TC-CUV-06 |
| teste_cur11_temporario_orfao_varrido_apos_um_dia | Temporario orfao do registro e varrido depois de um dia | TC-CUR-11 |
| teste_cur13_sem_trava_sem_cursor_e_codigo_normal | Sem a trava da raiz o cursor nao e usado e o codigo de saida e o normal | TC-CUR-13 |
| teste_cus03_retrato_com_hash_falso_o_download_confere | Retrato com hash falso e pego porque o download confere o conteudo | TC-CUS-03 |
| teste_cuv02_cul11_delta_vazio_sem_listagem_recursiva_e_continue_so_com_cursor | Delta vazio nao faz listagem recursiva e o continue so e chamado com cursor | TC-CUV-02, TC-CUL-11 |
| teste_cuv03_diferencial_dez_cenarios | Em dez cenarios, o incremental produz o mesmo plano da varredura completa | TC-CUV-03 |
| teste_cuv04_05_lado_local_igual_a_varredura_completa | O lado local resultante do incremental e igual ao da varredura completa | TC-CUV-04, TC-CUV-05 |
| teste_cuv07_delta_de_varias_paginas | Delta com varias paginas e consumido por inteiro e aplicado | TC-CUV-07 |
| teste_cuv09_delta_incoerente_volta_a_varredura_completa_sem_10 | Delta incoerente volta a varredura completa sem sair com codigo 10 | TC-CUV-09 |
| teste_cuv10_continue_malformado_volta_a_varredura_completa | Resposta malformada do continue volta a varredura completa | TC-CUV-10 |
| teste_cuv11_cul10_filtros_sobre_o_mapa_reconstruido | Filtros de inclusao e exclusao valem sobre o mapa reconstruido pelo cursor | TC-CUV-11, TC-CUL-10 |
| teste_cuv12_pasta_excluida_pelo_filtro_nunca_apagada_com_cursor | Pasta excluida pelo filtro nunca e apagada localmente no modo incremental | TC-CUV-12 |
| teste_cuv14_cus04_auditoria_exclusao_so_apos_confirmacao | Auditoria do codigo: exclusao local so ocorre depois da confirmacao de `not_found` | TC-CUV-14, TC-CUS-04 |
| teste_download_not_found_de_item_incremental_apaga_o_registro | `not_found` no download de item vindo do incremental apaga o registro do cursor | |
| teste_qa_b7b_01_raiz_barra_grava_e_usa_o_cursor | Com raiz remota `/`, o cursor e gravado e reaproveitado | |
| teste_qa_b7b_02_subpasta_com_a_propria_pasta_grava_e_usa_o_cursor | Com subpasta como raiz remota, o cursor e gravado e reaproveitado | |
| teste_qa_b7b_o1_remedio_nao_promete_substituir_registro_nao_regular | A mensagem de registro nao regular nao promete substituicao que nao ocorre | |


## `tests/integracao/debug_ajuda_progresso_test.sh`

- **Alvo:** `bin/dbx` (`--debug`/`DBX_DEBUG` em upload, ajuda, README e completions), `lib/progress.sh`, `commands/upload.sh`
- **Modulo:** debug_ajuda
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `debug-transferencias`)
- **Regras de origem:** RF-156; RF-159(d); RF-165; TC-DBG-33..35; log `docs/prompts/2026-10-24_0330_debug-transferencias.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de `curl` de `tests/support/disponibilidade.sh`, terminal simulado por pty (`_rodar_tty`), semente `DBX_PROGRESS_TERMINAL`, arquivos temporarios por caso; sem rede
- **Comando:** `bash tests/run.sh tests/integracao/debug_ajuda_progresso_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_tc_dbg_33_com_terminal_progresso_e_debug_nao_se_misturam | Com terminal (pty), `--debug` e progresso saem sem retorno de carro nem desenho, e as chamadas do resumo igualam as linhas http da tentativa 1. | TC-DBG-33 |
| teste_tc_dbg_33_sem_terminal_progresso_e_debug_nao_se_misturam | Sem terminal, o progresso por arquivo continua saindo, nenhuma linha mistura `debug:` com outro texto e nao ha `\r`. | TC-DBG-33 |
| teste_tc_dbg_33_semente_de_terminal_nao_reabilita_o_retorno_de_carro | Com a semente de terminal definida mas stderr nao sendo terminal, a saida segue sem `\r` nem sequencias de escape. | TC-DBG-33 |
| teste_tc_dbg_34_dbx_debug_0_e_nao_nao_ativam | `DBX_DEBUG=0` e `DBX_DEBUG=nao` nao ativam o debug: o comando termina bem e nenhuma linha `debug:` aparece. | TC-DBG-34 |
| teste_tc_dbg_34_dbx_debug_1_ativa | `DBX_DEBUG=1` ativa o debug sem a opcao: o comando termina com 0 e emite linhas `debug: http`. | TC-DBG-34 |
| teste_tc_dbg_35_ajuda_de_cada_comando_e_a_geral_descrevem_o_debug | A ajuda de cada comando e a geral descrevem `--debug` (categoria, stderr, resumo, cursor, token) e `DBX_DEBUG=1`. | TC-DBG-35 |
| teste_tc_dbg_35_readme_e_completions | O README documenta `debug: categoria chave=valor` e a URL temporaria, e a lista de completions traz `--debug`. | TC-DBG-35 |
| teste_tc_dbg_rf159_upload_de_fluxo_bem_sucedido_emite_resultado_ok | `upload -` bem-sucedido emite `debug: upload resultado=ok` sem vazar o id de sessao. | RF-159(d) |
| teste_tc_dbg_rf159_upload_de_fluxo_falho_emite_resultado_falha_com_classe | `upload -` que falha emite `debug: upload resultado=falha classe=` e nunca `resultado=ok`. | RF-159(d) |


## `tests/integracao/debug_http_test.sh`

- **Alvo:** `bin/dbx` (upload, download e sync com `--debug`), `lib/http.sh` e `lib/progress.sh`: linha de depuracao por tentativa HTTP e resumo
- **Modulo:** `debug_http`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `debug-transferencias`)
- **Regras de origem:** RF-156; RF-157; RF-162; RF-163; RF-164; TC-DBG-01..07; TC-DBG-22..32; log `docs/prompts/2026-10-24_0330_debug-transferencias.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` de `tests/support/disponibilidade.sh` (filas por papel, `-D`, corpo, `-w` ampliado); cenario criado por `_dbg_cenario` em diretorio temporario da suite; sentinelas de segredo sinteticas
- **Comando:** `bash tests/run.sh debug_http`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_tc_dbg_01_upload_emite_linha_http_com_medidas | Upload com `--debug` emite no stderr uma linha HTTP com as medidas da tentativa | TC-DBG-01 |
| teste_tc_dbg_02_retentativa_5xx_gera_uma_linha_por_tentativa | Resposta 5xx seguida de retentativa gera uma linha de depuracao por tentativa | TC-DBG-02 |
| teste_tc_dbg_03_429_com_retry_after_vem_depois_de_recebidos | Resposta 429 com `Retry-After` mostra a espera depois dos bytes recebidos na linha | TC-DBG-03 |
| teste_tc_dbg_04_retry_after_acima_do_teto_mostra_o_valor_efetivo | `Retry-After` acima do teto aparece com o valor efetivo (limitado), nao o do servidor | TC-DBG-04 |
| teste_tc_dbg_05_falha_de_transporte_tem_status_zero_e_curl | Falha de transporte sai com status 0 e o codigo de saida do `curl` na linha | TC-DBG-05 |
| teste_tc_dbg_06_endpoint_nao_tem_esquema_userinfo_porta_query_nem_fragmento | O endpoint exibido perde esquema, credencial embutida, porta, query e fragmento | TC-DBG-06 |
| teste_tc_dbg_07_host_fora_de_dropboxapi_sai_so_como_host | URL de host fora de dropboxapi.com aparece apenas como host, sem caminho nem token | TC-DBG-07 |
| teste_tc_dbg_22_26_sentinelas_ausentes_de_stdout_e_stderr_com_retentativa_e_falha | Com retentativa e falha, nenhuma sentinela de segredo aparece em stdout nem stderr | TC-DBG-22..26 |
| teste_tc_dbg_24_26_id_de_sessao_query_e_url_temporaria_ficam_fora_da_linha | Id de sessao, query e URL temporaria nao entram na linha de depuracao | TC-DBG-24..26 |
| teste_tc_dbg_28_29_stdout_e_requisicoes_iguais_com_e_sem_debug_no_upload | No upload, stdout e requisicoes enviadas sao identicos com e sem `--debug` | TC-DBG-28..29 |
| teste_tc_dbg_28_29_stdout_e_requisicoes_iguais_com_e_sem_debug_no_download | No download, stdout e requisicoes enviadas sao identicos com e sem `--debug` | TC-DBG-28..29 |
| teste_tc_dbg_28_29_stdout_e_requisicoes_iguais_com_e_sem_debug_no_sync | No sync, stdout e requisicoes enviadas sao identicos com e sem `--debug` | TC-DBG-28..29 |
| teste_tc_dbg_30_sem_debug_nenhuma_linha_nos_tres_comandos | Sem `--debug`, upload, download e sync nao emitem nenhuma linha de depuracao | TC-DBG-30 |
| teste_tc_dbg_27_nome_com_controle_sai_em_uma_so_linha | Nome com quebra de linha e byte de controle e neutralizado e sai em uma so linha | TC-DBG-27 |
| teste_tc_dbg_rf162_upload_tem_um_resumo_com_totais_das_linhas_http | Upload termina com um unico resumo cujos totais batem com a soma das linhas HTTP | RF-162 |
| teste_tc_dbg_32_download_com_falha_tem_resumo_com_o_codigo_e_a_mensagem_de_sempre | Download que falha emite resumo com o codigo de saida e a mensagem habituais | TC-DBG-32 |
| teste_rf162a_credencial_ausente_tambem_tem_resumo_com_o_codigo | Credencial ausente tambem produz o resumo, com o codigo de saida correspondente | RF-162 |
| teste_rf162e_sonda_entra_em_chamadas | A chamada de sonda conta no total de chamadas do resumo | RF-162 |
| teste_rf162e_reemissao_diagnostica_do_503_conta_igual_nos_tres_lugares | A reemissao diagnostica de um 503 e contada igual nas linhas, no resumo e nas requisicoes reais | RF-162 |
| teste_rf162_codigo_do_resumo_nao_vem_do_ambiente | O codigo exibido no resumo vem do resultado real, nao de variavel de ambiente herdada | RF-162 |


## `tests/integracao/debug_sync_test.sh`

- **Alvo:** `bin/dbx sync` com `--debug` (`commands/sync.sh`, `lib/sync.sh`, `lib/transfer.sh`)
- **Modulo:** debug_sync
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `debug-transferencias`)
- **Regras de origem:** RF-158(b); RF-159(a)(d); RF-161; RF-164; TC-DBG-17..20; TC-DBG-25; log `docs/prompts/2026-10-24_0330_debug-transferencias.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de `curl` copiado de `paralelo_test.sh` (controles por arquivo em base temporaria: `remoto/`, `falha/`, `listagem`), cursor sentinela, sem rede
- **Comando:** `bash tests/run.sh tests/integracao/debug_sync_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_dbg159_envio_unitario_tem_resultado_ok_e_falha_com_classe | No envio unitario, `--debug` registra resultado ok com o item relativo a raiz (sem caminho local completo) e resultado falha com a classe quando ha 409. | RF-159(a)(d) |
| teste_dbg159_lote_tem_modalidade_e_resultado_por_item | No envio em lote, cada item tem linha de modalidade lote e uma linha de resultado que o nomeia, sem sentinela de segredo. | RF-159(a)(d) |
| teste_dbg17_cada_item_tem_decisao_com_o_motivo_do_vocabulario | O sync emite uma linha de decisao por item (receber novo, receber diferente, pular igual, pular filtrado, apagar orfao) com o motivo do vocabulario. | TC-DBG-17; TC-DBG-18 |
| teste_dbg17_sem_debug_nao_ha_linha_de_decisao | Sem `--debug` nenhuma linha `debug:` e emitida. | TC-DBG-17 |
| teste_dbg17_so_no_destino_sem_espelhar_e_protegido_tambem_tem_linha | Item so no destino sem `--espelhar` recebe decisao pular com motivo so-no-destino e nada e apagado. | TC-DBG-17 |
| teste_dbg19_cursor_com_motivo_e_sem_o_valor | A linha de cursor traz o motivo (reconstruido, desligado, forcado) e o valor do cursor nunca aparece em stdout nem stderr. | TC-DBG-19; TC-DBG-25 |
| teste_dbg19_enviar_nao_tem_linha_de_cursor | No sentido `--enviar` nao ha linha de cursor, pois o cursor so existe no `--receber`. | TC-DBG-19 |
| teste_dbg20_decisao_do_item_vem_antes_das_linhas_do_download_dele | Com `--paralelo 4`, a decisao de cada item precede as linhas de plano e download dele, e as linhas http dos auxiliares chegam ao operador. | TC-DBG-20; RF-158(b) |


## `tests/integracao/debug_transferencia_test.sh`

- **Alvo:** `bin/dbx upload` e `bin/dbx download` com `--debug` (etapas de transferencia), `lib/transfer.sh`, `lib/cmd.sh`
- **Modulo:** debug_transferencia
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `debug-transferencias`)
- **Regras de origem:** RF-159, RF-160, RF-164; TC-DBG-08, 09, 16, 24; log `docs/prompts/2026-10-24_0330_debug-transferencias.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` de `tests/support/disponibilidade.sh`; arquivos sinteticos temporarios; sem rede
- **Comando:** `bash tests/run.sh tests/integracao/debug_transferencia_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_tc_dbg_08_09_upload_em_sessao_tem_modalidade_e_blocos_com_confirmado_acumulado | Upload em sessao com `--debug` emite a modalidade e uma linha por bloco com o total confirmado acumulado | TC-DBG-08, TC-DBG-09 |
| teste_tc_dbg_08_sem_debug_o_upload_nao_emite_linha_de_etapa | Sem `--debug` o upload nao emite nenhuma linha de etapa | TC-DBG-08 |
| teste_tc_dbg_08_upload_simples_emite_modalidade_antes_da_chamada_de_conteudo | Upload simples com `--debug` emite a modalidade antes da chamada de conteudo | TC-DBG-08 |
| teste_tc_dbg_16_download_para_stdout_emite_o_plano_em_stderr_e_so_o_conteudo_em_stdout | Download para stdout com `--debug` escreve o plano em stderr e somente o conteudo em stdout | TC-DBG-16 |
| teste_tc_dbg_24_id_de_sessao_real_nunca_aparece_em_stdout_nem_stderr | O identificador de sessao real de upload nunca aparece em stdout nem em stderr, mesmo com `--debug` | TC-DBG-24 |


## `tests/integracao/diagnostico_compartilhamento_test.sh`

- **Alvo:** `bin/dbx diagnostico` (`commands/diagnostico.sh`, `lib/auth.sh`): linha `escopos` com os escopos opcionais de compartilhamento
- **Modulo:** `diagnostico_compartilhamento`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-5-compartilhamento`)
- **Regras de origem:** RF-91; TC-DIA-17; TC-DIA-18; log `docs/prompts/2026-10-20_1110_backlog-fase-5-compartilhamento.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** credencial com sentinelas sinteticas em diretorio temporario; duplo de `curl` cujo `scope` da renovacao e lido de arquivo (`sharing.write`, `sharing.read`)
- **Comando:** `bash tests/run.sh diagnostico_compartilhamento`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_dia17_opcionais_de_compartilhamento_concedidos_na_mesma_linha | Com `sharing.write` e `sharing.read` concedidos, aparecem na propria linha `escopos`, sem checagem nova nem mudanca de resultado ou de codigo de saida | TC-DIA-17 |
| teste_dia18_opcional_ausente_cita_modos_afetados_e_remedio_sem_mudar_resultado | Escopo opcional ausente e citado com os modos afetados e o remedio, sem mudar o resultado da linha | TC-DIA-18 |


## `tests/integracao/diagnostico_test.sh`

- **Alvo:** `bin/dbx diagnostico`, `verificar` e preflight com utilitarios fora do `PATH` (`commands/diagnostico.sh`, `lib/preflight.sh`)
- **Modulo:** `diagnostico`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-1-consulta-diagnostico`)
- **Regras de origem:** RF-66; TC-DIA-01..16; protocolo-tdd Regra 6 (nenhuma credencial em saida); log `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` escrito sem expansao, `PATH` restrito por caso (diretorio de vinculos), sentinelas de credencial, estado temporario com permissoes variadas; no caso FreeBSD, duplo de `stat` BSD
- **Comando:** `bash tests/run.sh tests/integracao/diagnostico_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_dia01_ambiente_sao_tem_todas_as_checagens_ok | Em ambiente sao, todas as checagens do diagnostico saem ok | TC-DIA-01 |
| teste_dia02_pelo_vinculo_sem_dirname_nem_readlink_ainda_roda | Invocado por vinculo simbolico sem `dirname` nem `readlink`, o diagnostico ainda roda | TC-DIA-02 |
| teste_dia02_sem_stat_mktemp_readlink_roda_e_lista_cada_ausente | Sem `stat`, `mktemp` e `readlink`, roda e lista cada utilitario ausente | TC-DIA-02 |
| teste_dia02_sem_stat_o_estado_existente_e_aviso_e_dono_e_conferido_pelo_shell | Sem `stat`, o estado existente vira aviso e o dono e conferido pelo shell | TC-DIA-02 |
| teste_dia03_sem_curl_as_checagens_de_rede_falham_como_nao_executadas | Sem `curl`, as checagens de rede aparecem como nao executadas | TC-DIA-03 |
| teste_dia04_info_continua_recusado_pelo_preflight_no_mesmo_ambiente | No mesmo ambiente sem utilitarios, `info` continua recusado pelo preflight | TC-DIA-04 |
| teste_dia05_credencial_ausente_larga_ou_incompleta_tem_remedio_proprio | Credencial ausente, com permissao larga ou incompleta recebe remedio proprio | TC-DIA-05 |
| teste_dia06_check_user_rejeitado_ou_rede_indisponivel_falha_a_conectividade | `check/user` rejeitado ou rede indisponivel falha a checagem de conectividade | TC-DIA-06 |
| teste_dia07_escopo_faltante_e_nomeado_e_sem_campo_e_aviso | Escopo faltante e nomeado; resposta sem o campo de escopo vira aviso | TC-DIA-07 |
| teste_dia08_espaco_a_noventa_por_cento_avisa_e_cheio_falha | Disco a 90% avisa e disco cheio falha a checagem de espaco | TC-DIA-08 |
| teste_dia09_localidade_ausente_avisa_e_estado_largo_falha | Localidade ausente avisa e estado com permissao larga falha | TC-DIA-09 |
| teste_dia10_ambiente_identico_e_so_tres_endpoints_de_leitura | O ambiente nao muda e so tres endpoints de leitura sao chamados | TC-DIA-10 |
| teste_dia10_argumento_desconhecido_e_uso_invalido | Argumento desconhecido sai como uso invalido | TC-DIA-10 |
| teste_dia10_nenhum_sentinela_aparece_em_saida_alguma | Nenhum valor sentinela de credencial aparece em saida alguma | TC-DIA-10; protocolo-tdd Regra 6 |
| teste_dia15_escopo_opcional_concedido_e_ok_habilitada | Escopo opcional concedido aparece como ok e funcionalidade habilitada | TC-DIA-15 |
| teste_dia16_escopo_opcional_ausente_e_ok_informativo_sem_mudar_o_codigo | Escopo opcional ausente e informativo e nao muda o codigo de saida | TC-DIA-16 |
| teste_fbsd15_estado_0700_com_stat_bsd_nao_reporta_permissao_falsa | Estado com modo 0700 lido por `stat` BSD nao gera aviso falso de permissao | RF-168; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md` |


## `tests/integracao/disponibilidade_automatica_test.sh`

- **Alvo:** `bin/dbx` nos comandos de nivel `credencial` (exercitado por `space`, `upload`, `download`, `sync`, `diagnostico`), com a checagem automatica de disponibilidade, a oferta de `config` e a sonda de internet e de servico (`lib/disponibilidade.sh`)
- **Modulo:** disponibilidade_automatica
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `teste-de-disponibilidade`)
- **Regras de origem:** RF-151..RF-154; TC-DSP-18, 20, 28..64; RNF-03; log `docs/prompts/2026-10-23_0900_teste-de-disponibilidade.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de `curl` e de terminal (pty) de `tests/support/disponibilidade.sh` (sonda, api, content, rpc, proxies por chamada); credencial sintetica com sentinela reconhecivel que nao pode aparecer em saida nem log; `XDG_CONFIG_HOME` temporario
- **Comando:** `bash tests/run.sh tests/integracao/disponibilidade_automatica_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_dsp28_caminho_feliz_so_a_renovacao_e_a_chamada_do_comando | No caminho feliz so ocorrem a renovacao do token e a chamada do comando, sem sonda extra | TC-DSP-28..30 |
| teste_dsp31_sem_terminal_credencial_ausente_sai_3_sem_pergunta_sem_sonda_sem_ler_stdin | Sem terminal e sem credencial: sai com 3, sem pergunta, sem sonda e sem ler stdin | TC-DSP-31 |
| teste_dsp35_terminal_credencial_ausente_pergunta_e_recusa_mantem_3 | Com terminal e sem credencial, pergunta se deve configurar; a recusa mantem o codigo 3 | TC-DSP-35 |
| teste_dsp35b_caminho_com_stdin_no_nome_nao_fecha_o_portao_da_oferta | Caminho de arquivo com `stdin` no nome nao fecha o portao da oferta | TC-DSP-35 |
| teste_dsp36_terminal_campo_faltando_pergunta_invalida | Com terminal e campo faltando na credencial, pergunta se deve reconfigurar | TC-DSP-36 |
| teste_dsp47_aceite_configura_e_o_comando_continua_no_mesmo_processo | Aceitar a oferta roda o config e o comando original continua no mesmo processo | TC-DSP-47 |
| teste_dsp48_config_cancelado_mantem_o_codigo_original_e_nada_do_comando_roda | Config cancelado mantem o codigo original e o comando nao executa | TC-DSP-48 |
| teste_dsp32_invalid_grant_sem_terminal_sem_oferta_sem_sonda_e_codigo_de_hoje | `invalid_grant` sem terminal: sem oferta, sem sonda e com o codigo de saida atual | TC-DSP-32 |
| teste_dsp32_invalid_grant_no_terminal_pergunta_invalida_e_recusa_mantem_o_codigo | `invalid_grant` com terminal pergunta sobre credencial invalida; a recusa mantem o codigo | TC-DSP-32 |
| teste_dsp32_invalid_grant_sai_5_nos_demais_comandos_de_consulta | `invalid_grant` sai com 5 nos demais comandos de consulta | TC-DSP-32 |
| teste_dsp49_invalid_grant_aceite_configura_renova_e_o_comando_continua | `invalid_grant` com oferta aceita configura, renova o token e o comando continua | TC-DSP-49 |
| teste_dsp33_falha_de_rede_na_renovacao_sem_internet_nomeia_e_mantem_9 | Falha de rede na renovacao sem internet nomeia a causa e mantem o codigo 9 | TC-DSP-33 |
| teste_dsp33_falha_de_rede_na_renovacao_com_internet_diz_dropbox_inacessivel | Falha de rede na renovacao com internet disponivel informa que o Dropbox esta inacessivel | TC-DSP-33 |
| teste_dsp34_5xx_na_renovacao_diz_servico_indisponivel_sem_sonda | 5xx na renovacao informa servico indisponivel, sem sonda | TC-DSP-34 |
| teste_dsp33_upload_falha_de_rede_na_renovacao_nomeia_a_causa_no_motivo | No upload, falha de rede na renovacao nomeia a causa no motivo | TC-DSP-33 |
| teste_dsp33_falha_de_rede_na_chamada_do_comando_nomeia_sem_oferta_e_mantem_9 | Falha de rede na chamada do comando nomeia a causa, sem oferta de config, e mantem 9 | TC-DSP-33 |
| teste_dsp33_falha_de_rede_na_chamada_do_comando_com_internet_diz_dropbox_inacessivel | Falha de rede na chamada do comando com internet informa Dropbox inacessivel | TC-DSP-33 |
| teste_dsp34_5xx_na_chamada_do_comando_diz_servico_indisponivel_sem_sonda | 5xx na chamada do comando informa servico indisponivel, sem sonda | TC-DSP-34 |
| teste_dsp44_upload_de_fluxo_nao_oferece_o_config | Upload de fluxo (stdin) nunca oferece o config | TC-DSP-44 |
| teste_dsp55_nenhum_sentinela_na_saida_nem_na_sonda_dos_caminhos_de_falha | O sentinela de segredo nao aparece na saida nem na sonda em nenhum caminho de falha | TC-DSP-55; RNF-03 |
| teste_dsp37_stderr_em_arquivo_nao_pergunta | Com stderr redirecionado a arquivo nao ha pergunta | TC-DSP-37 |
| teste_dsp38_term_dumb_nao_pergunta | Com `TERM=dumb` nao ha pergunta | TC-DSP-38 |
| teste_dsp45_dbx_teste_config_nao_nao_pergunta | Com `DBX_TESTE_CONFIG=nao` nao ha pergunta | TC-DSP-45 |
| teste_dsp39_enter_n_x_e_fim_de_entrada_recusam_com_o_codigo_original | Enter, `n`, `x` e fim de entrada recusam a oferta e mantem o codigo original | TC-DSP-39 |
| teste_dsp40_s_maiusculo_e_sim_aceitam_a_oferta | `S` maiusculo e `sim` aceitam a oferta | TC-DSP-40 |
| teste_dsp41_arquivo_incompleto_aceito_e_substituido | Arquivo de credencial incompleto aceito pela oferta e substituido | TC-DSP-41 |
| teste_dsp42_perfil_aceito_grava_so_o_perfil_pedido | Oferta aceita com perfil grava apenas o perfil pedido | TC-DSP-42 |
| teste_dsp43_upload_de_fluxo_com_terminal_nao_pergunta_nem_le_a_entrada | Upload de fluxo com terminal nao pergunta nem le a entrada | TC-DSP-43 |
| teste_dsp46_json_com_oferta_aceita_stdout_so_o_json | Com `--json` e oferta aceita, o stdout contem so o JSON | TC-DSP-46 |
| teste_dsp51_sigint_dentro_do_config_mantem_o_codigo_e_nada_do_comando_roda | SIGINT dentro do config mantem o codigo e o comando nao executa | TC-DSP-51 |
| teste_dsp52_falha_de_rede_no_config_mantem_codigo_e_mensagem_do_config | Falha de rede dentro do config mantem codigo e mensagem do config | TC-DSP-52 |
| teste_dsp53_config_substituir_que_falha_preserva_a_credencial_anterior | Config que falha ao substituir preserva a credencial anterior | TC-DSP-53 |
| teste_dsp54_oferta_aceita_nao_adquire_trava_antes_e_o_comando_adquire_depois | A oferta aceita nao adquire trava antes; o comando a adquire depois | TC-DSP-54 |
| teste_dsp54_invalid_grant_aceito_o_config_roda_sob_a_unica_trava_do_par | Com `invalid_grant` aceito, o config roda sob a unica trava do par | TC-DSP-54 |
| teste_dsp18_falhas_de_dns_conexao_tls_e_tempo_contam_como_nao_responde | Falhas de DNS, conexao, TLS e tempo esgotado contam como nao responde | TC-DSP-18 |
| teste_dsp20_sonda_usa_o_mesmo_transporte_e_nao_le_variavel_de_proxy_nova | A sonda usa o mesmo transporte e nao le variavel de proxy nova | TC-DSP-20 |
| teste_dsp56_oferta_e_classificacao_nao_vazam_sentinela_na_saida_nem_no_log | Oferta e classificacao nao vazam o sentinela na saida nem no log | TC-DSP-56; RNF-03 |
| teste_dsp57_sonda_e_servico_nao_levam_segredo_nem_cabecalho_de_autorizacao | Sonda e checagem de servico nao levam segredo nem cabecalho de autorizacao | TC-DSP-57; RNF-03 |
| teste_dsp58_sem_terminal_nenhum_byte_de_stdin_nos_caminhos_de_falha | Sem terminal, nenhum byte de stdin e lido nos caminhos de falha | TC-DSP-58 |
| teste_dsp59_diagnostico_nunca_oferece_o_config | `diagnostico` nunca oferece o config | TC-DSP-59 |
| teste_dsp60_fim_normal_e_falha_nao_deixam_processo_nem_tmp | Fim normal e falha nao deixam processo nem arquivo temporario | TC-DSP-60 |
| teste_dsp60_sinal_durante_a_sonda_nao_deixa_processo_nem_tmp | Sinal durante a sonda nao deixa processo nem arquivo temporario | TC-DSP-60 |
| teste_dsp34r_sync_paralelo_com_url_invalida_avisa_uma_vez_na_etapa_de_lote | Sync paralelo com URL invalida avisa uma vez na etapa de lote | TC-DSP-34 |
| teste_dsp34s_sync_paralelo_com_falha_de_rede_sonda_uma_vez | Sync paralelo com falha de rede faz a sonda uma unica vez | TC-DSP-34 |
| teste_dsp33_sync_falha_de_rede_na_renovacao_nomeia_a_causa | No sync, falha de rede na renovacao nomeia a causa | TC-DSP-33 |
| teste_dsp33_download_falha_de_rede_na_renovacao_nomeia_a_causa | No download, falha de rede na renovacao nomeia a causa | TC-DSP-33 |
| teste_dsp62_ajuda_de_config_e_diagnostico_e_geral_informam_a_oferta | A ajuda de config, a de diagnostico e a geral informam a oferta de configuracao | TC-DSP-62 |
| teste_dsp63_readme_descreve_o_teste_a_sonda_e_o_comportamento_sem_terminal | O README descreve o teste, a sonda e o comportamento sem terminal | TC-DSP-63 |


## `tests/integracao/espaco_test.sh`

- **Alvo:** `bin/dbx upload` e `bin/dbx sync --enviar` com a checagem previa de espaco (`dbx_cmd_espaco_checar` em `lib/cmd.sh`)
- **Modulo:** `lib/cmd.sh`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-1-consulta-diagnostico`)
- **Regras de origem:** RF-67; TC-ESP-01..10; RF-136; RF-137; RF-15; RF-44; log `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** arvore temporaria por caso em `DBX_TESTES_TMP`, credencial sintetica, duplo de `curl` que responde `get_space_usage` e as rotas de lote (`tests/support/lote_duplo.sh`), arquivos locais de tamanho exato
- **Comando:** `bash tests/run.sh tests/integracao/espaco_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_esp01_upload_maior_que_a_folga_e_recusado_sem_nenhuma_escrita | Upload de arquivo maior que a folga da conta sai com o codigo de espaco antes de qualquer envio, sessao ou memoria gravada | TC-ESP-01 |
| teste_esp02_sync_que_nao_cabe_recusa_antes_da_primeira_acao | Sync --enviar cujo total a transferir nao cabe e recusado antes da primeira acao, inclusive da exclusao do --espelhar | TC-ESP-02 |
| teste_esp03_soma_so_a_parte_transferir_e_consulta_uma_vez | A conta soma apenas o que sera transferido (identicos ficam fora) e a API de espaco e consultada uma unica vez por execucao | TC-ESP-03 |
| teste_esp04_sobrescrita_conta_o_arquivo_novo_inteiro | Ao sobrescrever arquivo remoto, o tamanho do arquivo novo conta inteiro na checagem | TC-ESP-04 |
| teste_esp05_forcar_pula_a_checagem_no_upload_e_no_sync | --forcar e --force pulam a checagem de espaco no upload e no sync e o envio acontece | TC-ESP-05 |
| teste_esp05_forcar_no_sync_nao_muda_a_decisao_por_conteudo | --forcar no sync nao altera o plano: arquivo de conteudo igual continua dispensado | TC-ESP-05 |
| teste_esp05_forcar_com_receber_e_uso_invalido | --forcar junto de sync --receber e uso invalido e sai com o codigo de uso | TC-ESP-05 |
| teste_esp06_simulacao_so_avisa_que_recusaria | Com --dry-run a falta de espaco apenas avisa que a execucao real recusaria e sai com 0 | TC-ESP-06 |
| teste_esp06_simulacao_segue_a_ordem_real_e_nao_anuncia_recusa_do_que_seria_dispensado | A simulacao le o content_hash remoto antes do espaco, na ordem real, e nao anuncia recusa para item que seria dispensado | TC-ESP-06; RF-15; RF-44 |
| teste_esp07_falha_da_consulta_avisa_uma_vez_e_o_envio_segue | Falha da consulta de espaco (500 ou 401) emite um unico aviso e o envio prossegue | TC-ESP-07 |
| teste_esp08_upload_da_entrada_padrao_nao_consulta | Upload da entrada padrao nao consulta espaco e envia o fluxo | TC-ESP-08 |
| teste_esp09_conta_de_equipe_usa_a_menor_folga_e_sem_alocacao_nao_recusa | Conta de equipe usa a menor folga entre as cotas; sem alocacao conhecida nao recusa | TC-ESP-09 |
| teste_esp10_campos_de_espaco_na_saida_estruturada | A saida --json traz espaco_necessario, espaco_livre e espaco_verificado | TC-ESP-10 |


## `tests/integracao/filtros_ajuda_test.sh`

- **Alvo:** ajuda (`bin/dbx help`), autocompletar (`completions/dbx.bash`), `README.md` e mapa de modulos para as opcoes de filtro e limite de banda
- **Modulo:** `bin/dbx`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-4-filtros-e-banda`)
- **Regras de origem:** RF-83; TC-CPL-09; TC-DOC-03; TC-TST-07; log `docs/prompts/2026-10-19_2141_backlog-fase-4-filtros-e-banda.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** Nao aplicavel: le textos reais de `README.md`, `docs/testes/mapa-modulos.md` e do script de autocompletar, sem rede nem estado
- **Comando:** `bash tests/run.sh tests/integracao/filtros_ajuda_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_cpl09_opcoes_novas_por_comando_na_ajuda_e_no_autocompletar | As opcoes novas de filtro e banda aparecem na ajuda e no autocompletar dos comandos certos e so neles | TC-CPL-09 |
| teste_doc03_ajuda_traz_sintaxe_desvios_seguranca_unidade_piso_e_variavel | A ajuda traz sintaxe dos padroes, desvios, cuidados de seguranca, unidade, piso do limite e a variavel de ambiente | TC-DOC-03 |
| teste_doc03_readme_traz_filtros_e_limite_de_banda | O README tem as secoes de Filtros e Limite de banda e explica a interacao com --espelhar | TC-DOC-03 |
| teste_tst07_mapa_de_modulos_tem_lib_filtro_com_seus_testes | O mapa de modulos tem a linha de lib/filtro.sh com seus testes diretos | TC-TST-07 |


## `tests/integracao/filtros_test.sh`

- **Alvo:** `bin/dbx` (sync nos dois sentidos, `--dry-run`, `verificar`, download de pasta e de arquivo, upload) com filtros de caminho, data e tamanho; `lib/filtro.sh`, `lib/walk.sh`, `lib/sync.sh`
- **Modulo:** filtros_test
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-4-filtros-e-banda`)
- **Regras de origem:** RF-79; RF-80; RF-80(d); RF-81; RF-12 (emendado pela DIV-90); TC-FLT; TC-FES; TC-FDT; DIV-95; DIV-103; log `docs/prompts/2026-10-19_2141_backlog-fase-4-filtros-e-banda.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de `curl` com registro de URL e corpo e duble de `rm` com registro de chamadas; arvores locais e listagens remotas sinteticas; `LC_ALL=C` e `TZ` ajustados por caso; credencial sintetica
- **Comando:** `bash tests/run.sh tests/integracao/filtros_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_flt13_flt14_malformado_sai_2_antes_de_trava_memoria_rede_e_escrita | Padrao malformado sai com codigo 2 antes de trava, memoria, rede e escrita | TC-FLT-13; TC-FLT-14 |
| teste_flt16_padrao_e_dado_na_linha_de_comando | Padrao com caracteres de shell e tratado como dado na linha de comando, nunca executado | TC-FLT-16 |
| teste_flt18_repetivel_acumula_e_a_ordem_nao_importa | Opcoes de filtro repetidas acumulam e a ordem entre elas nao muda o resultado | TC-FLT-18 |
| teste_flt19_sem_valor_vazio_e_comandos_que_nao_aceitam | Opcao sem valor, valor vazio e comandos que nao aceitam filtro sao recusados | TC-FLT-19 |
| teste_flt20_malformado_com_trava_ocupada_sai_2_e_nao_7 | Padrao malformado com trava ocupada sai com 2 e nao com 7 | TC-FLT-20 |
| teste_flt21_aceito_em_sync_verificar_e_download_de_pasta_com_aliases | Filtros sao aceitos em sync, verificar e download de pasta, inclusive pelos aliases | TC-FLT-21 |
| teste_fes02_so_incluir_pdf_e_pasta_sem_pdf_nao_e_criada | Com `--incluir` so de pdf, pasta sem pdf nao e criada | TC-FES-02 |
| teste_fes04_pasta_excluida_nao_e_percorrida_e_erro_dentro_dela_nao_conta | Pasta excluida nao e percorrida e erro dentro dela nao conta | TC-FES-04 |
| teste_fes05_regressao_ilegivel_fora_de_pasta_excluida_desabilita_a_exclusao | Item ilegivel fora de pasta excluida segue contando como erro (a exclusao nao o esconde) | TC-FES-05 |
| teste_fes06_remoto_sob_pasta_excluida_e_descartado_e_a_pasta_conta_1 | Item remoto sob pasta excluida e descartado e a pasta conta uma exclusao | TC-FES-06 |
| teste_fes07_d1_enviar_espelhar_zero_delete_de_filtrado | Enviar com `--espelhar` nao emite nenhum delete para item filtrado | TC-FES-07; RF-80(d) |
| teste_div95_chamada_json_depois_de_um_envio_leva_o_proprio_corpo | Chamada JSON depois de um envio leva o proprio corpo, e nao o do envio anterior | DIV-95 |
| teste_div103_receber_espelhar_incluir_impreciso_nao_apaga_nome_nao_utf8 | Receber com `--espelhar` e `--incluir '[!e]*'` nao apaga nome local nao UTF-8 ausente no remoto | DIV-103 |
| teste_fes08_d2_receber_espelhar_filtrado_local_intacto_sem_rm | Receber com `--espelhar` deixa o item local filtrado intacto, sem chamar `rm` | TC-FES-08; RF-80(d) |
| teste_fes09_d3_incluir_nao_apaga_o_que_nao_casa_nos_dois_sentidos | `--incluir` nao apaga o que nao casa, nos dois sentidos | TC-FES-09; RF-80(d) |
| teste_fes10_d4_filtro_novo_nao_apaga_o_que_deixou_de_fora | Filtro novo nao apaga o que deixou de fazer parte do escopo | TC-FES-10; RF-80(d) |
| teste_fes11_d5_mutacao_que_filtra_so_um_lado_e_detectada | Mutacao que filtra so um lado faz a guarda ceder e e detectada pelo teste | TC-FES-11 |
| teste_fes_guarda_sem_estado_nao_apaga_filtrado_mesmo_com_memoria_que_o_conhece | A guarda sem estado mantem o item filtrado mesmo com memoria que o conhece | RF-80(d) |
| teste_fes12_origem_toda_filtrada_e_vazia_para_a_guarda | Origem toda filtrada e tratada como vazia pela guarda de espelhamento | TC-FES-12 |
| teste_fes13_memoria_sem_filtrados_e_sem_poder_de_decisao | A memoria nao registra filtrados e nao decide sobre eles | TC-FES-13 |
| teste_fes15_colisao_de_caixa_dentro_de_pasta_excluida_nao_recusa | Colisao de caixa dentro de pasta excluida nao causa recusa | TC-FES-15 |
| teste_fes16_plano_simulado_igual_ao_real_e_campos_do_plano | O plano simulado e igual ao real e traz os campos de filtro esperados | TC-FES-16 |
| teste_fes17_verificar_nao_conta_filtrado_como_divergencia | `verificar` nao conta item filtrado como divergencia | TC-FES-17 |
| teste_fes18_avisos_de_filtro_mal_escrito_em_stderr | Avisos de filtro mal escrito saem em stderr | TC-FES-18 |
| teste_fes19_download_de_pasta_filtra_e_de_arquivo_recusa | Download de pasta aplica o filtro e download de arquivo o recusa | TC-FES-19 |
| teste_fes19_espaco_soma_so_o_escopo_e_filtrado_nao_gera_falha | A checagem de espaco soma so o escopo e item filtrado nao gera falha | TC-FES-19 |
| teste_fdt01_fdt06_valores_invalidos_saem_2_sem_rede | Valores invalidos de data e tamanho saem com codigo 2 sem rede | TC-FDT-01..06 |
| teste_fdt04_local_por_mtime_em_utc_sem_date_em_qualquer_fuso | Filtro de data local usa mtime em UTC, sem `date`, em qualquer fuso | TC-FDT-04 |
| teste_fdt05_remoto_por_server_modified_ignorando_client_modified | Filtro de data remoto usa `server_modified` e ignora `client_modified` | TC-FDT-05 |
| teste_fdt08_data_e_tamanho_com_espelhar_saem_2_antes_de_tudo | Data ou tamanho com `--espelhar` saem com codigo 2 antes de qualquer acao | TC-FDT-08 |
| teste_fdt09_fdt10_so_a_origem_e_conjuncao_com_caminho | Filtros de data e tamanho valem so para a origem e em conjuncao com os de caminho | TC-FDT-09; TC-FDT-10 |
| teste_fdt11_pastas_nunca_sao_filtradas_por_data_ou_tamanho | Pastas nunca sao filtradas por data ou tamanho | TC-FDT-11 |
| teste_fdt12_verificar_recusa_data_e_tamanho_e_o_ultimo_valor_vence | `verificar` recusa data e tamanho; em repeticao, o ultimo valor vence | TC-FDT-12 |


## `tests/integracao/instalador_diagnostico_freebsd_test.sh`

- **Alvo:** `install.sh` (instalar e desinstalar com prefixo) e `commands/diagnostico.sh`, no ambiente simulado do FreeBSD
- **Modulo:** `instalador_diagnostico_freebsd` (linha ausente do mapa de modulos; id derivado do nome do arquivo)
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `suporte-freebsd`)
- **Regras de origem:** RF-170; RF-172; TC-FBSD-08, TC-FBSD-09, TC-FBSD-23; DIV-357; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** diretorio de links com a base de utilitarios e extras por caso (`_bin`), dubles de `pkg`, `apt`, `curl` e dubles do FreeBSD em `tests/duplos/freebsd`; prefixo de instalacao temporario
- **Comando:** `bash tests/run.sh tests/integracao/instalador_diagnostico_freebsd_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_curl_ausente_com_apt_sugere_apt_install | Sem `curl` e com `apt` no host, o instalador sugere `apt install` | RF-170 |
| teste_curl_ausente_com_pkg_sugere_pkg_install | Sem `curl` e com `pkg` no host, o instalador sugere `pkg install` | RF-170 |
| teste_curl_ausente_sem_gerenciador_conhecido_e_neutro | Sem gerenciador conhecido, a mensagem sobre `curl` ausente e neutra | DIV-357 |
| teste_diagnostico_diz_de_qual_utilitario_vem_o_resumo | O diagnostico informa de qual utilitario vem o resumo SHA-256 | RF-172 |
| teste_diagnostico_marca_nao_verificado_onde_o_tipo_do_sistema_de_arquivos_falha | Onde o tipo do sistema de arquivos nao pode ser lido, o diagnostico marca "nao verificado" | RF-172 |
| teste_install_prefix_conclui_com_os_dubles_e_uninstall_remove_o_instalado | Instalacao com prefixo conclui com os dubles e a desinstalacao remove o que foi instalado | TC-FBSD-08 |
| teste_resumo_ausente_com_pkg_tambem_sugere_pkg_install | Sem utilitario de resumo e com `pkg`, o instalador tambem sugere `pkg install` | RF-170 |


## `tests/integracao/lote_test.sh`

- **Alvo:** `lib/lote.sh` e `bin/dbx sync` (exclusao em lote no `--espelhar`, envio em lote de pequenos no `--enviar`); `reter` fica item a item
- **Modulo:** lote_test
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-9-desempenho`)
- **Regras de origem:** F-08; F-34; RF-136; RF-137; DIV-269; TC-LOT-*; TC-LOU-*; log `docs/prompts/2026-10-21_2300_backlog-fase-9-desempenho.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de `curl` que delega rotas de lote a `tests/support/lote_duplo.sh`; duble de `sleep` que registra a espera em arquivo (sem esperar de verdade); arquivos temporarios por caso
- **Comando:** `bash tests/run.sh tests/integracao/lote_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_lot01_espelhar_apaga_em_um_lote_e_nunca_por_delete_v2 | O `--espelhar` apaga os orfaos por `delete_batch` em um lote e nao chama `delete_v2` por item. | TC-LOT-01 |
| teste_lot02_fatias_de_250 | Mais de 250 exclusoes sao divididas em fatias de ate 250 itens por lote. | TC-LOT-02 |
| teste_lot03_item_com_erro_no_check_e_falha_do_item_e_so_dele | Item que falha na conferencia do lote e falha so dele, os demais seguem. | TC-LOT-03 |
| teste_lot04_entrada_ausente_no_complete_e_falha_nunca_sucesso | Entrada ausente na resposta de conclusao do lote conta como falha, nunca como sucesso. | TC-LOT-04 |
| teste_lot05_in_progress_recua_1_2_4_e_volta_a_consultar | Enquanto o lote esta em andamento, a consulta recua 1, 2, 4 segundos e volta a consultar. | TC-LOT-05 |
| teste_lot06_recuo_limitado_a_10s_e_teto_de_120s_e_falha_da_fatia_inteira | O recuo e limitado a 10 s, e ao passar do teto de 120 s a fatia inteira falha. | TC-LOT-06 |
| teste_lot07_check_failed_e_falha_da_fatia_inteira_sem_repetir | Falha geral na conferencia falha a fatia inteira, sem repetir a chamada. | TC-LOT-07 |
| teste_lot08_guardas_agem_antes_do_lote | As guardas (confirmacao, escopo, simulacao) agem antes de qualquer chamada de lote. | TC-LOT-08 |
| teste_lot09_filtrado_nunca_entra_no_lote | Arquivo remoto fora do filtro nunca entra no corpo do lote de exclusao. | TC-LOT-09 |
| teste_lot09b_protegido_fora_do_escopo_nunca_entra_no_corpo_do_delete_batch | Item protegido fora do escopo nunca aparece no corpo de `delete_batch`. | TC-LOT-09 |
| teste_lot10_parent_rev_quando_o_rev_e_conhecido | O corpo de exclusao leva `parent_rev` quando o rev do item e conhecido. | TC-LOT-10 |
| teste_lot11_sem_delete_v2_em_laco_no_espelhar | O `--espelhar` nunca apaga em laco por `delete_v2`. | TC-LOT-11 |
| teste_lot12_interrupcao_na_conferencia_diz_que_a_exclusao_pode_ter_sido_concluida | Sinal durante a conferencia do lote avisa que a exclusao pode ter sido concluida no servico. | TC-LOT-12 |
| teste_lot12_reter_segue_com_delete_v2_por_item_e_sem_delete_batch | `reter` continua apagando por `delete_v2` item a item e nao usa `delete_batch`. | TC-LOT-12; DIV-269 |
| teste_lot13_montagem_do_lote_barra_o_protegido_mesmo_se_o_plano_falhar | A montagem do lote barra o item protegido mesmo que o plano o tenha deixado passar. | TC-LOT-13 |
| teste_lot14_reter_sem_confirmar_nao_chama_o_lote | `reter` sem confirmacao nao chama nenhuma rota de lote. | TC-LOT-14 |
| teste_lot15_reter_ignora_os_controles_do_lote_e_confirma_item_a_item | `reter` ignora os controles de lote e confirma item a item. | TC-LOT-15 |
| teste_lou01_pequenos_vao_em_sessoes_e_um_finish_batch | Arquivos pequenos sao enviados em sessoes de inicio e fechados por um unico `finish_batch`. | TC-LOU-01 |
| teste_lou02_acima_do_limiar_segue_o_caminho_atual_e_a_fronteira_e_1_mib | Arquivo acima de 1 MiB segue o envio atual; a fronteira do lote e exatamente 1 MiB. | TC-LOU-02 |
| teste_lou03_falha_por_entrada_e_so_do_item | Falha por entrada do `finish_batch` falha somente aquele item. | TC-LOU-03 |
| teste_lou04_falha_do_lote_inteiro_falha_todos_e_nao_grava_retomada | Falha do lote inteiro falha todos os itens e nao grava registro de retomada. | TC-LOU-04 |
| teste_lou05_grupos_de_ate_250_em_serie | Os pequenos sao agrupados em ate 250 por `finish_batch`, executados em serie. | TC-LOU-05 |
| teste_lou06_arquivo_ja_igual_nao_entra_no_lote | Arquivo ja igual no destino e dispensado e nao entra no lote. | TC-LOU-06 |
| teste_lou07_com_paralelo_os_starts_correm_juntos_e_o_finish_e_um_so_e_igual_a_n1 | Com paralelo, os starts correm juntos, o finish e um so e o resultado e igual ao de N=1. | TC-LOU-07 |
| teste_lou08_dry_run_nao_chama_o_lote_e_um_unico_pequeno_segue_o_upload_unitario | `--dry-run` nao chama o lote e um unico arquivo pequeno segue o upload unitario. | TC-LOU-08 |
| teste_lou09_resultado_do_lote_e_igual_ao_do_envio_unitario_para_n1_e_n4 | O resultado do envio em lote e igual ao do envio unitario, com N=1 e N=4. | TC-LOU-09 |
| teste_lou10_hash_divergente_falha_so_a_entrada_com_integridade_igual_ao_unitario | Hash divergente falha so a entrada, com a mesma classe de integridade do envio unitario. | TC-LOU-10 |
| teste_lou11_hash_ausente_nao_conferida_como_no_unitario | Resposta sem hash deixa a integridade nao conferida, como no envio unitario. | TC-LOU-11 |
| teste_lou12_o_corpo_do_start_leva_content_hash | O corpo do start da sessao leva o `content_hash` do arquivo. | TC-LOU-12 |
| teste_lou13_sinal_no_meio_do_lote_de_envio_sem_estado_nem_processo | Sinal no meio do lote de envio sai sem deixar estado persistente nem processo filho. | TC-LOU-13 |
| teste_lou14_paralelo_4_com_falha_de_start_de_um_item_falha_so_ele | Com paralelo 4, falha de start de um item falha so ele. | TC-LOU-14 |
| teste_lou15_plano_misto_n4_igual_a_n1 | Plano misto (pequenos e grandes) com N=4 produz o mesmo resultado que N=1. | TC-LOU-15 |


## `tests/integracao/paralelo_download_test.sh`

- **Alvo:** `bin/dbx download` de arquivo grande em faixas simultaneas (`commands/download.sh`, `lib/transfer.sh`, `lib/http.sh`)
- **Modulo:** paralelo_download
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `paralelo-upload-download`)
- **Regras de origem:** F-100; RF-180; RF-181 (download); RF-182; RF-183; RF-184; DIV-369..371; DIV-373..376; TC-PUD-30..33; log `docs/prompts/2026-10-26_1900_paralelo-upload-download.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de `curl` que serve `Range` fechado com `206` e `Content-Range` a partir de `remoto.bin`, registra pedidos em `chamadas`, marca `vivos/<pid>` e segura cada faixa 0,3 s; controles `ignora`, `falha` e `sinal_em` em `$base/ctl`; credencial sintetica
- **Comando:** `bash tests/run.sh tests/integracao/paralelo_download_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_limiar_mais_cinco_faixa_final_curta_bytes_identicos_e_pico | Arquivo logo acima do limiar, com faixa final curta, sai com bytes identicos e pico de faixas simultaneas acima de 1 | RF-180 |
| teste_limiar_mais_um_byte | Arquivo com um byte acima do limiar tambem e baixado em faixas e fica identico | RF-180 |
| teste_progresso_ativo_nao_pendura_o_fim_das_faixas | Com progresso ativo, o observador do `.part` em segundo plano nao impede o termino das faixas | RF-182 |
| teste_multiplo_exato_de_16_mib | Arquivo de tamanho multiplo exato do bloco de 16 MiB e baixado sem faixa vazia e identico | RF-180 |
| teste_n1_e_abaixo_do_limiar_seguem_o_caminho_de_hoje | Com N=1 ou abaixo do limiar o download segue o caminho sequencial atual, sem faixas | RF-181 |
| teste_queda_de_rede_numa_faixa_preserva_part_e_reexecucao_completa | Queda de rede numa faixa preserva o `.part` e a reexecucao completa o arquivo | RF-183 |
| teste_403_numa_faixa_segue_a_regra_do_sequencial_descarta_part_e_registro | 403 numa faixa descarta `.part` e registro, como no download sequencial | RF-183 |
| teste_sigterm_sem_orfaos_e_retomada_pelo_prefixo_contiguo | SIGTERM nao deixa processo orfao e a retomada continua pelo prefixo contiguo ja baixado | RF-183 |
| teste_servidor_que_ignora_range_recomeca_sequencial_com_aviso | Servidor que responde 200 ao Range faz o download recomecar sequencial com aviso | RF-184 |
| teste_limite_de_banda_dividido_entre_as_faixas | O limite de banda total e dividido entre as faixas simultaneas | RF-181 |
| teste_debug_registra_paralelo_e_partes | `--debug` registra o paralelismo e as partes baixadas | RF-182 |
| teste_429_pausa_o_despacho_durante_o_retry_after | Resposta 429 pausa o despacho de novas faixas durante o `Retry-After`, compartilhada entre elas | RF-182 |


## `tests/integracao/paralelo_test.sh`

- **Alvo:** `bin/dbx sync`, `download` e `upload` de pasta com `--paralelo` (`commands/sync.sh`, `lib/lote.sh`), incluindo selecao, equivalencia N=1 e N>1, sinais, banda e `--debug`
- **Modulo:** paralelo
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-9-desempenho`)
- **Regras de origem:** F-09; F-08; F-34; RF-133..RF-135; RF-139; TC-PAR-01..; DIV-338; log `docs/prompts/2026-10-21_2300_backlog-fase-9-desempenho.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de `curl` que marca cada transferencia em `$base/vivos` e anota o pico em `$base/pico` (prova o paralelismo sem depender de tempo); arvores sinteticas locais e remotas; credencial sintetica
- **Comando:** `bash tests/run.sh tests/integracao/paralelo_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_par01_valores_invalidos_saem_2_antes_da_rede_e_do_estado | Valores invalidos de `--paralelo` saem com codigo 2 antes de rede e de estado | TC-PAR-01 |
| teste_par02_variavel_invalida_nomeia_a_variavel_e_a_opcao_vence | Variavel invalida nomeia a variavel na recusa e a opcao vence a variavel | TC-PAR-02 |
| teste_par03_fora_do_sync_upload_download_a_opcao_e_recusada_e_a_variavel_ignorada | Fora de sync, upload e download a opcao e recusada e a variavel e ignorada | TC-PAR-03 |
| teste_par04_receber_com_n4_e_igual_a_n1_e_e_efetivo | Receber com N=4 produz o mesmo resultado que N=1 e o pico de transferencias passa de 1 | TC-PAR-04 |
| teste_par05_enviar_com_n4_e_igual_a_n1_e_e_efetivo | Enviar com N=4 produz o mesmo resultado que N=1 e o pico de transferencias passa de 1 | TC-PAR-05 |
| teste_par06_falha_por_item_sob_n_maior_continua_por_item_e_na_ordem_do_plano | Falha de um item sob N>1 nao interrompe os demais e a saida segue a ordem do plano | TC-PAR-06 |
| teste_par07_dry_run_nunca_dispara_paralelismo_nem_transferencia | `--dry-run` nao dispara paralelismo nem transferencia | TC-PAR-07 |
| teste_par08_listagem_nunca_concorre_com_transferencia | A listagem remota e sempre sequencial e nunca concorre com transferencias | TC-PAR-08 |
| teste_par09_auditoria_estatica_o_auxiliar_nao_alcanca_escrita_de_estado | Auditoria do texto: o auxiliar paralelo nao alcanca nenhuma escrita de estado | TC-PAR-09 |
| teste_par10_sigterm_nao_deixa_auxiliar_vivo_nem_parcial | SIGTERM nao deixa auxiliar vivo nem arquivo parcial | TC-PAR-10 |
| teste_par11_limite_de_banda_e_o_teto_total_dividido_por_n | O limite de banda de cada transferencia e o teto total dividido por N | TC-PAR-11 |
| teste_par12_debug_informa_n_e_quantos_429_sem_reduzir_n | `--debug` informa N e a contagem de 429 no resumo unico sem reduzir N | DIV-338 |
| teste_par13_sem_a_opcao_e_sem_a_variavel_nada_muda_e_nao_ha_auxiliar | Sem opcao e sem variavel o comportamento e o de hoje, sem auxiliares | DIV-338 |
| teste_par14_ajuda_autocompletar_readme_e_diagnostico | A ajuda, o autocompletar, o README e o diagnostico documentam a opcao de paralelismo | TC-PAR-14 |
| teste_par15_debug_linhas_dos_auxiliares_chegam_ao_operador_e_somam_no_resumo | Linhas de `--debug` dos auxiliares chegam ao operador e entram na soma do resumo | TC-PAR-15 |
| teste_par16_sem_debug_nenhuma_linha_nem_arquivo_de_auxiliar | Sem `--debug` nao ha linha de depuracao nem arquivo de auxiliar | TC-PAR-16 |
| teste_par17_falha_de_item_tem_resumo_com_o_codigo_de_saida | Falha de item produz resumo com o codigo de saida | TC-PAR-17 |
| teste_par18_sinal_tem_resumo_em_melhor_esforco_e_nao_deixa_arquivo_de_linhas | Sinal gera resumo em melhor esforco e nao deixa arquivo de linhas | TC-PAR-18 |
| teste_par20_opcao_e_alias_validam_nos_dois_comandos_antes_da_rede | A opcao e o alias validam em upload e download de pasta antes de qualquer chamada de rede | TC-PAR-20 |
| teste_par21_variavel_vale_a_opcao_vence_e_variavel_invalida_recusa | A variavel vale, a opcao vence e variavel invalida e recusada, em upload e download | TC-PAR-21 |
| teste_par22_download_de_pasta_com_n3_e_igual_a_n1_e_efetivo | Download de pasta com N=3 produz o mesmo resultado que N=1 e e efetivamente paralelo | TC-PAR-22 |
| teste_par23_upload_de_pasta_com_n3_e_igual_a_n1_e_efetivo | Upload de pasta com N=3 produz o mesmo resultado que N=1 e e efetivamente paralelo | TC-PAR-23 |
| teste_par24_dry_run_de_pasta_aceita_valida_e_ignora | `--dry-run` de pasta aceita e valida a opcao, mas nao paraleliza | TC-PAR-24 |
| teste_par25_entrada_e_saida_padrao_recusam_a_opcao_e_ignoram_a_variavel | Entrada e saida padrao recusam a opcao e ignoram a variavel | TC-PAR-25 |
| teste_par26_outros_comandos_continuam_recusando | Os demais comandos continuam recusando a opcao de paralelismo | TC-PAR-26 |


## `tests/integracao/paralelo_upload_test.sh`

- **Alvo:** `bin/dbx upload` de arquivo grande em partes simultaneas (`commands/upload.sh`, `lib/transfer.sh`, registro de retomada v2)
- **Modulo:** `paralelo_upload`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `paralelo-upload-download`)
- **Regras de origem:** F-100 (etapa 2a); RF-177..RF-179, RF-181 (upload), RF-182..RF-184, RF-175(c); DIV-358..DIV-368, DIV-373..DIV-376; TC-PUD; log `docs/prompts/2026-10-26_1900_paralelo-upload-download.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` que e servidor de sessao concorrente (guarda corpo por deslocamento, marca `vivos/pid`, monta o arquivo no `finish` e calcula o `content_hash`); controles em `ctl` (`recusa`, `falha`, `r429`); arquivo grande sintetico, `TMPDIR` e estado por caso
- **Comando:** `bash tests/run.sh tests/integracao/paralelo_upload_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_429_pausa_o_despacho_durante_o_retry_after | Um 429 com `Retry-After` pausa o despacho de novas partes durante a espera | |
| teste_tc_pud_429_em_uma_parte_nao_perde_nem_duplica_e_entra_no_resumo | 429 em uma parte nao perde nem duplica dados e aparece no resumo | TC-PUD |
| teste_tc_pud_abaixo_do_limiar_o_n_nao_tem_efeito | Arquivo abaixo do limiar de tamanho ignora o numero de partes simultaneas | TC-PUD |
| teste_tc_pud_auxiliar_que_ignora_term_e_morto_a_forca_sem_residuo_no_tmpdir | Auxiliar que ignora `TERM` e morto a forca, sem residuo no `TMPDIR` | TC-PUD |
| teste_tc_pud_debug_traz_paralelo_no_resumo_e_uma_linha_por_parte | `--debug` traz o paralelismo no resumo e uma linha por parte | TC-PUD |
| teste_tc_pud_falha_definitiva_de_parte_nao_faz_finish_e_preserva_o_registro_v2 | Falha definitiva de uma parte nao chama `finish` e preserva o registro v2 | TC-PUD |
| teste_tc_pud_n1_e_o_caminho_sequencial_de_sempre | Com N igual a 1 o envio segue o caminho sequencial de sempre | TC-PUD |
| teste_tc_pud_partes_simultaneas_montam_o_mesmo_arquivo_e_o_content_hash | Partes simultaneas montam no servidor o mesmo arquivo e o mesmo `content_hash` | TC-PUD |
| teste_tc_pud_registro_v1_com_n_maior_que_1_retoma_em_sequencia | Registro v1 retomado com N maior que 1 continua em sequencia | TC-PUD |
| teste_tc_pud_registro_v2_com_intervalos_nao_canonicos_e_descartado_com_aviso | Registro v2 com intervalos nao canonicos e descartado com aviso | TC-PUD |
| teste_tc_pud_retomada_v2_reenvia_so_as_nao_confirmadas | A retomada pelo registro v2 reenvia somente as partes nao confirmadas | TC-PUD |
| teste_tc_pud_servico_que_recusa_concurrent_cai_para_sequencial_com_aviso | Servico que recusa sessao concorrente faz o envio cair para sequencial com aviso | TC-PUD |


## `tests/integracao/perfis_test.sh`

- **Alvo:** `bin/dbx perfis`, `config --perfil`, opcao `--perfil` e variavel de perfil (`commands/perfis.sh`, `commands/config.sh`, `lib/config.sh`)
- **Modulo:** `commands/perfis.sh`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-8-perfis`)
- **Regras de origem:** F-18; RF-120..RF-123; RF-126..RF-131; TC-PFS; TC-PFN; TC-PFC; TC-PFG; TC-PFL; TC-PFD; TC-PFA; TC-PFR; log `docs/prompts/2026-10-21_1735_backlog-fase-8-perfis.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** diretorios de configuracao e estado temporarios por caso, arquivos de perfil sinteticos com credencial sentinela, duplo de `curl` que registra chamadas
- **Comando:** `bash tests/run.sh tests/integracao/perfis_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_pfs01_opcao_vence_a_variavel | Quando --perfil e a variavel de perfil divergem, a opcao vence | TC-PFS-01 |
| teste_pfs02_so_a_variavel_usa_o_perfil_dela | Sem a opcao, a variavel de ambiente seleciona o perfil | TC-PFS-02 |
| teste_pfs03_a_pfs05_sem_selecao_vazio_e_alias | Sem selecao, com valor vazio e com o alias --profile o comportamento e o esperado | TC-PFS-03..05 |
| teste_pfs06_a_pfs08_uso_invalido_da_opcao | Opcao sem valor, repetida ou fora de posicao permitida sai com codigo de uso | TC-PFS-06..08 |
| teste_pfn02_a_pfn08_nome_invalido_sai_2_sem_efeito | Nome de perfil invalido sai com 2 sem tocar disco nem rede | TC-PFN-02..08 |
| teste_pfn_nome_invalido_em_config_nao_cria_nada | config com nome invalido nao cria diretorio nem arquivo | TC-PFN |
| teste_pfn09_pfd11_variavel_invalida_sai_2_sem_ecoar_e_sem_aviso | Variavel de perfil invalida sai com 2 sem ecoar o valor e sem aviso de ambiente | TC-PFN-09; TC-PFD-11 |
| teste_pfn10_help_version_e_completar_nao_leem_a_variavel | help, version e completar nao leem a variavel de perfil | TC-PFN-10 |
| teste_pfc03_perfil_ausente_sai_3_sem_rede_e_sem_recuo | Perfil selecionado inexistente sai com 3, sem rede e sem recuar para o padrao | TC-PFC-03 |
| teste_pfc04_a_pfc09_perfil_inseguro_sai_3 | Arquivo de perfil com permissao ou dono inseguro sai com 3 | TC-PFC-04..09 |
| teste_pfc07_pfc08_ligacoes_simbolicas_recusadas_sem_ler | Ligacao simbolica no diretorio ou no arquivo do perfil e recusada sem ler o conteudo | TC-PFC-07; TC-PFC-08 |
| teste_pfc10_preflight_inspeciona_o_arquivo_do_perfil | O preflight inspeciona o arquivo do perfil selecionado | TC-PFC-10 |
| teste_pfc14_so_config_cria_perfis | Somente config cria o diretorio de perfis; os demais comandos nao | TC-PFC-14 |
| teste_pfg01_cria_perfis_0700_e_arquivo_0600_sem_tocar_o_padrao | config --perfil cria diretorio 0700 e arquivo 0600 sem alterar a credencial padrao | TC-PFG-01 |
| teste_pfg02_pfg03_perfil_existente_exige_substituir_e_nomeia | Perfil existente exige --substituir e a mensagem nomeia o perfil | TC-PFG-02; TC-PFG-03 |
| teste_pfg04_pfg05_destino_inseguro_recusa_antes_de_perguntar | Destino inseguro recusa a gravacao antes de qualquer pergunta | TC-PFG-04; TC-PFG-05 |
| teste_pfg06_perfil_padrao_grava_credencial_json | O perfil padrao grava a credencial em credencial.json | TC-PFG-06 |
| teste_pfg07_raiz_e_propria_de_cada_perfil | Cada perfil guarda a sua propria raiz remota | TC-PFG-07 |
| teste_pfg08_dry_run_nao_cria_nada_e_mostra_o_perfil | config --dry-run nao cria nada e mostra o perfil alvo | TC-PFG-08 |
| teste_pfg09_pfr01_sem_selecao_a_saida_de_config_e_a_de_hoje | Sem selecao, a saida de config e identica a anterior aos perfis | TC-PFG-09; TC-PFR-01 |
| teste_pfg10_pfg11_debug_mostra_perfil_e_nunca_segredo | --debug mostra o perfil e nunca o segredo | TC-PFG-10; TC-PFG-11 |
| teste_pfl01_pfl04_lista_ordem_total_e_ativo | dbx perfis lista em ordem estavel, com total e marca do perfil ativo | TC-PFL-01..04 |
| teste_pfl02_pfl03_sem_credencial_total_zero_e_padrao_so_se_existir | Sem credencial o total e zero e o padrao so aparece se existir | TC-PFL-02; TC-PFL-03 |
| teste_pfl06_nenhum_segredo_nem_identidade_em_nenhum_modo | Nenhum modo de saida de perfis traz segredo nem identidade da conta | TC-PFL-06 |
| teste_pfl07_somente_leitura_sem_criar_diretorio | perfis so le e nao cria diretorio | TC-PFL-07 |
| teste_pfl08_entradas_anomalas_geram_um_aviso | Entradas anomalas no diretorio de perfis geram um aviso | TC-PFL-08 |
| teste_pfl09_pfl10_codigos | Os codigos de saida de perfis em sucesso e uso invalido sao os definidos | TC-PFL-09; TC-PFL-10 |
| teste_pfl11_alias_e_ajuda_equivalem | O alias profiles e a ajuda equivalem ao comando perfis | TC-PFL-11 |
| teste_pfd01_pfd02_diagnostico_com_selecao_traz_a_linha_perfil | diagnostico com perfil selecionado traz a linha de perfil | TC-PFD-01; TC-PFD-02 |
| teste_pfd03_pfr_diagnostico_sem_selecao_e_igual_a_base | diagnostico sem selecao e igual ao anterior aos perfis | TC-PFD-03; TC-PFR |
| teste_pfd05_perfis_inseguro_aponta_chmod_700 | Diretorio de perfis inseguro faz o diagnostico apontar chmod 700 | TC-PFD-05 |
| teste_pfd08_info_nao_muda_com_selecao | info nao muda com a selecao de perfil | TC-PFD-08 |
| teste_pfd09_pfd10_aviso_so_quando_o_perfil_vem_do_ambiente | O aviso de perfil so aparece quando o perfil vem da variavel de ambiente | TC-PFD-09; TC-PFD-10 |
| teste_pfs09_a_pfs11_nenhuma_saida_traz_credencial_sentinela | Nenhuma saida, de nenhum comando, contem a credencial sentinela | TC-PFS-09..11 |
| teste_pfs13_perfil_inexistente_ou_invalido_nunca_chama_a_rede | Perfil inexistente ou invalido nunca dispara chamada de rede | TC-PFS-13 |
| teste_pfs14_nenhum_codigo_novo | Os perfis nao introduzem codigo de saida novo | TC-PFS-14 |
| teste_pfa01_a_pfa03_ajuda_lista_perfis_a_opcao_e_a_variavel | A ajuda lista o comando perfis, a opcao --perfil e a variavel | TC-PFA-01..03 |
| teste_pfr01_pfr04_sem_selecao_nada_muda | Sem selecao de perfil, nada do comportamento anterior muda | TC-PFR-01..04 |
| teste_pfr05_perfil_padrao_e_omitir_a_selecao_exceto_o_campo_perfil | Selecionar o perfil padrao equivale a omitir a selecao, exceto o campo perfil na saida | TC-PFR-05 |
| teste_pfr06_credencial_json_nunca_e_movida_nem_regravada | A credencial.json existente nunca e movida nem regravada pelos perfis | TC-PFR-06 |


## `tests/integracao/perfis_trava_raiz_test.sh`

- **Alvo:** trava por raiz local canonica no `sync --receber`, independente do perfil (`commands/sync.sh`, `lib/state.sh`, `lib/cmd.sh`)
- **Modulo:** `lib/state.sh`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-8-perfis`)
- **Regras de origem:** F-18; TC-PFT; TC-PFE-06; log `docs/prompts/2026-10-21_1735_backlog-fase-8-perfis.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** processo auxiliar que detem a trava de raiz, raizes locais temporarias (inclusive por ligacao simbolica), duplo de `curl`, duas credenciais sinteticas de perfis diferentes
- **Comando:** `bash tests/run.sh tests/integracao/perfis_trava_raiz_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_pft01_outro_perfil_sobre_a_mesma_raiz_sai_7_sem_escrever_e_sem_perfil_na_mensagem | Segundo perfil sobre a mesma raiz local sai com 7 sem escrever e sem citar perfil na mensagem | TC-PFT-01 |
| teste_pft02_mesma_pasta_por_ligacao_simbolica_e_por_ponto_ponto | A mesma pasta alcancada por ligacao simbolica ou por .. e reconhecida como a mesma raiz | TC-PFT-02 |
| teste_pft03_esperar_conclui_quando_a_primeira_termina | Com --esperar o segundo processo aguarda e conclui quando o primeiro termina | TC-PFT-03 |
| teste_pft04_enviar_e_verificar_nao_sao_bloqueados_pela_trava_de_raiz | sync --enviar e verificar nao sao bloqueados pela trava de raiz | TC-PFT-04 |
| teste_pft05_download_de_pasta_usa_a_trava_de_raiz | download de pasta adquire a trava de raiz | TC-PFT-05 |
| teste_pft09_unlink_recusa_com_a_trava_viva_e_diagnostico_a_lista | unlink recusa com a trava viva e o diagnostico a lista | TC-PFT-09 |
| teste_pft10_dry_run_adquire_as_duas | A simulacao adquire a trava de par e a de raiz | TC-PFT-10 |
| teste_pft_raiz_inexistente_em_dry_run_nao_e_criada_nem_travada | Raiz inexistente em dry-run nao e criada nem travada | TC-PFT |
| teste_pft_raiz_livre_adquire_e_libera | Raiz livre e adquirida durante a execucao e liberada ao final | TC-PFT |
| teste_pfe06_cursor_de_outra_identidade_nao_e_usado_nem_alterado | Cursor gravado por outra identidade nao e usado nem alterado | TC-PFE-06 |


## `tests/integracao/perfis_unlink_test.sh`

- **Alvo:** `bin/dbx unlink` com perfis, `commands/unlink.sh`, `lib/state.sh`, `lib/config.sh`, `lib/tmp.sh`
- **Modulo:** `perfis_unlink`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-8-perfis`)
- **Regras de origem:** F-18; RF-124; RF-125; TC-PFU; TC-PFE; log `docs/prompts/2026-10-21_1735_backlog-fase-8-perfis.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** estado montado a mao no formato de `lib/state` (cabecalho v1 de `retomada-*` e `cursor-*`) com identidade `cred-` calculada a partir da credencial de cada perfil; duble de `curl`; area temporaria por caso
- **Comando:** `bash tests/run.sh tests/integracao/perfis_unlink_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_pfe01_leitores_expoem_cred_lendo_so_o_cabecalho | Os leitores de estado expoem a identidade `cred-` lendo apenas o cabecalho do arquivo | TC-PFE-01 |
| teste_pfr02_unlink_do_padrao_sem_perfis_apaga_o_estado_inteiro | `unlink` do padrao sem perfis apaga todo o estado como antes dos perfis | TC-PFR-02 |
| teste_pfu01_pfe02_pfe04_unlink_de_um_perfil_so_toca_o_que_e_dele | `unlink` de um perfil remove so o estado e a credencial desse perfil | TC-PFU-01; TC-PFE-02; TC-PFE-04 |
| teste_pfu02_revoga_o_token_do_perfil_e_adverte_a_cascata | `unlink` revoga o token do perfil e adverte sobre a cascata | TC-PFU-02 |
| teste_pfu03_sem_terminal_sem_confirmar_sai_2_e_nao_remove | Sem terminal e sem confirmar, sai com 2 e nao remove nada | TC-PFU-03 |
| teste_pfu04_perfil_inexistente_sai_3_antes_de_tudo | Perfil inexistente sai com 3 antes de qualquer efeito | TC-PFU-04 |
| teste_pfu05_unlink_do_padrao_sem_credencial_segue_saindo_0 | `unlink` do padrao sem credencial continua saindo com 0 | TC-PFU-05 |
| teste_pfu06_manter_aplicativo_regrava_o_perfil | `--manter-aplicativo` regrava o perfil preservando a chave do aplicativo | TC-PFU-06 |
| teste_pfu07_perfil_ilegivel_remove_o_arquivo_e_nao_toca_o_estado | Perfil ilegivel tem o arquivo removido e o estado fica intacto | TC-PFU-07 |
| teste_pfu08_aviso_de_credencial_compartilhada_sai_no_stderr_com_o_texto | Aviso de credencial compartilhada sai no stderr com o texto previsto | TC-PFU-08 |
| teste_pfu08_identidade_compartilhada_nao_revoga_e_mantem_o_estado | Identidade compartilhada com outro perfil nao revoga o token e mantem o estado | TC-PFU-08 |
| teste_pfu09_perfil_nao_comparavel_entra_no_aviso_com_a_contagem | Perfil nao comparavel entra no aviso com a contagem | TC-PFU-09 |
| teste_pfu10_pfu16_trava_viva_de_qualquer_par_recusa_com_7 | Trava viva de qualquer par recusa o `unlink` com codigo 7 | TC-PFU-10; TC-PFU-16 |
| teste_pfu11_perfis_vazio_e_removido | Diretorio `perfis` que ficou vazio e removido | TC-PFU-11 |
| teste_pfu12_dry_run_so_simula | `--dry-run` so simula, sem rede nem remocao | TC-PFU-12 |
| teste_pfu13_ilegivel_sendo_a_ultima_credencial_a_remocao_e_total | Credencial ilegivel que e a ultima faz a remocao ser total | TC-PFU-13 |
| teste_pfu13_nao_sobrando_nenhuma_a_remocao_e_total_como_hoje | Sem outra credencial restante, a remocao e total como antes dos perfis | TC-PFU-13 |
| teste_pfu13_sobrando_outra_credencial_a_remocao_e_seletiva_inclusive_no_padrao | Com outra credencial restante, a remocao e seletiva, inclusive no padrao | TC-PFU-13 |
| teste_pfu15_identidade_que_muda_depois_da_revogacao_nao_apaga_e_sai_7 | Identidade alterada depois da revogacao nao apaga estado e sai com 7 | TC-PFU-15 |


## `tests/integracao/progresso_arquivo_test.sh`

- **Alvo:** `bin/dbx` (upload simples, em sessao e de pasta; download de arquivo, de pasta e para stdout; sync nos dois sentidos com N=1 e N>1) e `lib/progress.sh`
- **Modulo:** progresso_arquivo_test
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `progresso-por-arquivo`)
- **Regras de origem:** F-49; RF-140..RF-147; TC-PRG-02, 06..10, 13..15, 21..23, 25, 28, 31..35; log `docs/prompts/2026-10-22_1600_progresso-por-arquivo.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de `curl` de `tests/integracao/sync_test.sh`; terminal simulado e semente `DBX_PROGRESS_TERMINAL`; areas temporarias sinteticas; credencial sintetica
- **Comando:** `bash tests/run.sh tests/integracao/progresso_arquivo_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_sync_enviar_mostra_linha_do_arquivo_de_0_a_100 | `sync --enviar` com progresso mostra a linha do arquivo indo de 0% a 100% | TC-PRG-02 |
| teste_sync_enviar_em_lote_mostra_posicao_no_plano | Envio em lote mostra a posicao do arquivo no plano | TC-PRG-06 |
| teste_sync_receber_mostra_linha_com_total_da_listagem | `sync --receber` mostra a linha com o total da listagem | TC-PRG-07 |
| teste_sync_stdout_igual_com_e_sem_progresso | O stdout do sync e identico com e sem progresso | TC-PRG-08 |
| teste_sync_sem_progresso_e_sem_terminal_nao_emite_linha_de_arquivo | Sem progresso e sem terminal nenhuma linha de arquivo e emitida | TC-PRG-09 |
| teste_sync_dry_run_nao_emite_linha_por_arquivo | `--dry-run` nao emite linha por arquivo | TC-PRG-10 |
| teste_sync_enviar_com_falha_deixa_ultimo_percentual_e_falhou | Falha no envio deixa o ultimo percentual e marca a linha como falhou | TC-PRG-13 |
| teste_upload_simples_tem_so_zero_e_cem | Upload simples tem so as linhas de 0% e 100% | TC-PRG-14 |
| teste_upload_com_falha_termina_a_linha_com_falhou | Upload com falha termina a linha com falhou | TC-PRG-15 |
| teste_upload_em_sessao_avanca_por_parte_sem_linha_de_parte | Upload em sessao avanca o percentual por parte, sem linha de parte | TC-PRG-21 |
| teste_download_mostra_linha_e_conclui_em_cem | Download mostra a linha do arquivo e conclui em 100% | TC-PRG-22 |
| teste_download_para_stdout_nao_emite_progresso | Download para stdout nao emite progresso | TC-PRG-23 |
| teste_paralelo_terminal_redesenha_bloco_e_deixa_linhas_finais | Com paralelismo e terminal, o bloco e redesenhado e restam as linhas finais | TC-PRG-25 |
| teste_paralelo_sem_terminal_uma_linha_nova_por_atualizacao_com_posicao | Com paralelismo e sem terminal, cada atualizacao e uma linha nova com a posicao | TC-PRG-25 |
| teste_paralelo_stdout_estado_e_cache_iguais_a_n1_e_a_sem_progresso | Com paralelismo, stdout, estado e cache sao iguais aos de N=1 e aos sem progresso | TC-PRG-28 |
| teste_paralelo_canal_de_status_so_com_progresso_ativo_e_em_diretorio_privado | O canal de status do paralelo so existe com progresso ativo e em diretorio privado | TC-PRG-28 |
| teste_paralelo_falha_fecha_a_linha_com_falhou_e_nao_deixa_orfaos | Falha no paralelo fecha a linha com falhou e nao deixa processos orfaos | TC-PRG-31 |
| teste_int_com_n1_fecha_a_linha_com_quebra_de_linha | Interrupcao com N=1 fecha a linha com quebra de linha | TC-PRG-32 |
| teste_int_com_n3_fecha_o_bloco_e_nao_deixa_orfaos | Interrupcao com N=3 fecha o bloco e nao deixa orfaos | TC-PRG-32 |
| teste_download_de_pasta_com_progresso_nao_imprime_falhou | Download de pasta com progresso bem-sucedido nao imprime falhou | TC-PRG-33 |
| teste_download_com_falha_do_servidor_termina_em_falhou_sem_cem | Download com falha do servidor termina em falhou sem chegar a 100% | TC-PRG-33 |
| teste_download_grande_amostra_o_part_e_chega_a_cem_ao_fim_sem_orfaos | Download grande amostra o `.part`, chega a 100% ao fim e nao deixa orfaos | TC-PRG-34 |
| teste_download_grande_com_hash_divergente_nao_chega_a_cem | Download grande com hash divergente nao chega a 100% | TC-PRG-34 |
| teste_nenhum_segredo_aparece_na_saida_de_progresso | Nenhum segredo aparece na saida de progresso | RNF-03 |
| teste_paralelo_falha_de_um_arquivo_nao_derruba_os_demais_e_iguala_n1 | No paralelo, falha de um arquivo nao derruba os demais e o resultado iguala o de N=1 | TC-PRG-35 |
| teste_sync_sem_progresso_e_sem_terminal_tem_stderr_igual_ao_da_base | Sem progresso e sem terminal o stderr do sync e igual ao da versao base | RF-146 |
| teste_download_de_pasta_sem_terminal_nao_emite_linha_de_arquivo | Download de pasta sem terminal nao emite linha de arquivo | RF-146 |
| teste_upload_em_sessao_com_erro_na_parte_2_para_no_percentual_da_parte_1 | Upload em sessao com erro na segunda parte para no percentual da primeira | RF-141 |
| teste_lote_com_uma_entrada_em_erro_no_finish_falha_so_a_linha_dela | Em lote, entrada com erro no fechamento falha so a linha dela | RF-141 |
| teste_download_com_metadado_de_hash_invalido_abre_a_linha_do_arquivo | Download com metadado de hash invalido ainda abre a linha do arquivo | RF-141 |
| teste_linha_zero_sai_antes_da_primeira_requisicao_de_conteudo | A linha de 0% sai antes da primeira requisicao de conteudo | RF-140 |
| teste_com_paralelo_so_o_processo_principal_escreve_em_stderr | Com paralelismo, so o processo principal escreve em stderr | RF-142 |
| teste_upload_e_download_de_pasta_mostram_a_linha_por_arquivo_via_sync | Upload e download de pasta mostram a linha por arquivo pela via do sync | RF-140 |
| teste_codigo_de_saida_cache_e_plano_iguais_com_e_sem_progresso | Codigo de saida, cache e plano sao iguais com e sem progresso | RF-146 |
| teste_ajuda_e_readme_descrevem_o_progresso_com_e_sem_terminal | A ajuda e o README descrevem o progresso com e sem terminal | RF-147 |
| teste_mensagens_de_analise_do_sync_neutralizam_controles_no_nome | Mensagens de analise do sync neutralizam caracteres de controle no nome do arquivo | RF-146 |


## `tests/integracao/qa_cache_unico_p3_test.sh`

- **Alvo:** `bin/dbx sync` (dois sentidos) e `upload` sobre o cache unico de estado (`lib/state.sh`): exclusao do espelhamento, dispensa do envio, identidade forte do arquivo e segredo
- **Modulo:** `lib/state.sh`
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `cache-unico-p3`)
- **Regras de origem:** RF-41; RF-60; RF-38(e); RF-61; RF-03; RNF-02; log `docs/prompts/2026-10-18_2243_cache-unico-p3.md`; protocolo-tdd Regra 6
- **Aceite do solicitante:** [registro de aceite](../prompts/2026-10-26_1300_upload-arquivo-para-pasta.md) com sha256 `f97c852faca1803d02f895e1dc1f2499647aad51ac6d78cc8bae975b24166a6a`
- **Dados e precondicoes:** cada caso monta o proprio cenario (credencial sintetica, duplos de `curl` proprios do QA, memoria de estado e arvores temporarias); sem dependencia entre casos
- **Comando:** `bash tests/run.sh tests/integracao/qa_cache_unico_p3_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_exclusao_origem_vazia_sem_conta_nos_dois_sentidos_com_e_sem_confirmar | Origem vazia sem identidade de conta recusa a exclusao nos dois sentidos, com e sem --confirmar | RF-41 |
| teste_qa_exclusao_origem_vazia_com_conta_e_memoria_recusa_sem_escrita_nos_dois_sentidos | Origem vazia com conta e memoria povoada recusa sem nenhuma escrita nos dois sentidos | RF-41 |
| teste_qa_exclusao_origem_ausente_ou_que_nao_e_diretorio_recusa_sem_escrita | Origem ausente ou que nao e diretorio recusa sem escrita | RF-41 |
| teste_qa_exclusao_ponto_de_montagem_ausente_nao_apaga | Ponto de montagem ausente (origem aparentemente vazia) nao leva a exclusao | RF-41 |
| teste_qa_exclusao_travessia_parcial_e_conta_nao_identificada_acumulam_nos_dois_sentidos | Travessia parcial e conta nao identificada acumulam as restricoes de exclusao nos dois sentidos | RF-41 |
| teste_qa_exclusao_memoria_descartada_com_origem_vazia_nao_apaga | Memoria descartada com origem vazia nao apaga nada | RF-41 |
| teste_qa_exclusao_memoria_descartada_com_origem_vazia_segunda_execucao_nao_apaga | Na segunda execucao apos o descarte, a origem vazia continua sem apagar | RF-41 |
| teste_qa_exclusao_memoria_descartada_duas_execucoes_a_segunda_propaga | Com origem povoada, a execucao seguinte ao descarte volta a propagar exclusoes | RF-41 |
| teste_qa_exclusao_memoria_ausente_nao_conta_como_descartada | Memoria ausente nao e tratada como descartada | RF-41 |
| teste_qa_exclusao_memoria_ilegivel_com_confirmar_nao_apaga | Memoria ilegivel, mesmo com --confirmar, nao leva a exclusao | RF-41 |
| teste_qa_exclusao_memoria_descartada_com_travessia_parcial_nao_regrava_base_vazia | Descarte com travessia parcial nao regrava uma base vazia | RF-41; RF-38 |
| teste_qa_guarda_origem_vazia_sem_memoria_recusa_variantes_de_vazio_no_enviar | Sem memoria, as variantes de origem vazia recusam o --espelhar no enviar | RF-41(b) |
| teste_qa_guarda_origem_vazia_no_receber_e_raiz_remota_inexistente | No --receber, origem remota vazia ou raiz remota inexistente recusa a exclusao local | RF-41(b) |
| teste_qa_guarda_permitir_origem_vazia_combinacoes | --permitir-origem-vazia libera a exclusao apenas nas combinacoes previstas | RF-41 |
| teste_qa_guarda_origem_vazia_sem_nada_a_apagar_nao_recusa | Origem vazia sem nada a apagar nao e recusada | RF-41 |
| teste_qa_skip_falha_5xx_429_e_corpo_enganoso_no_metadado_envia | Falha 5xx, 429 ou corpo enganoso no metadado remoto nunca dispensa: o upload envia | RF-60 |
| teste_qa_skip_remoto_pasta_ou_hash_malformado_nao_dispensa | Remoto que e pasta ou com hash malformado nao dispensa o envio | RF-60 |
| teste_qa_skip_cache_envenenado_nao_leva_a_dispensa_indevida | Cache de hash adulterado nao leva a dispensa indevida | RF-60; RF-38 |
| teste_qa_skip_forcar_rev_e_entrada_padrao_ignoram_cache_valido | --forcar, --rev e entrada padrao ignoram cache valido e enviam | RF-60 |
| teste_qa_identidade_mtime_restaurado_por_touch_envia | Arquivo alterado com mtime restaurado por touch e enviado | RF-38(e); RF-61 |
| teste_qa_identidade_troca_de_inode_por_mv_envia | Troca de inode por mv invalida o cache e envia | RF-38(e); RF-61 |
| teste_qa_identidade_hardlink_alterado_pelo_outro_nome_envia_e_tem_registro_proprio | Hardlink alterado pelo outro nome e enviado e cada nome tem registro proprio | RF-61 |
| teste_qa_identidade_arquivo_alterado_entre_o_stat_e_o_resumo_nao_grava | Arquivo alterado entre o stat e o calculo do resumo nao grava registro | RF-61 |
| teste_qa_identidade_janela_de_dois_segundos_no_upload | Alteracao dentro da janela de dois segundos nao dispensa o upload | RF-61 |
| teste_qa_identidade_sync_envia_arquivo_com_mtime_restaurado | O sync envia arquivo com mtime restaurado e conteudo alterado | RF-38(e) |
| teste_qa_estado_0755_corrigido_por_upload_e_sync_com_legado_intacto | Diretorio de estado 0755 e corrigido por upload e sync e o legado fica intacto | RNF-02 |
| teste_qa_estado_diretorio_alheio_gravavel_nao_recebe_nada | Diretorio de estado alheio e gravavel nao recebe nenhuma gravacao | RNF-02 |
| teste_qa_poda_acerto_de_registro_velho_sobrevive_e_so_os_velhos_saem | Registro velho que teve acerto sobrevive a poda e saem apenas os velhos nao usados | RF-62 |
| teste_qa_poda_no_teto_exato_nao_remove_nem_os_velhos | No teto exato de registros a poda nao remove nenhum, nem os velhos | RF-62 |
| teste_qa_legado_install_readme_e_codigo_sem_sqlite_nem_python | install.sh, README e codigo nao referenciam mais SQLite nem Python | RF-62 |
| teste_qa_segredo_ausente_recusa_antes_da_rede_com_o_codigo_de_rf03 | Segredo ausente recusa antes de qualquer chamada de rede com o codigo de RF-03 | RF-03 |
| teste_qa_segredo_preparo_nao_vaza_e_nao_incide_onde_nao_ha_rede | O preparo do segredo nao vaza o valor e nao incide onde nao ha rede | RF-03 |
| teste_qa_p34_falha_de_rede_nao_vira_sucesso_no_upload_nem_no_sync | Falha de rede nunca vira sucesso no upload nem no sync | protocolo-tdd Regra 6 |


## `tests/integracao/qa_compartilhamento_b5_test.sh`

- **Alvo:** `bin/dbx compartilhar` (criar, reuso, modificar, listar, revogar, dry-run) e `link-temporario` (`commands/compartilhar.sh`, `commands/link_temporario.sh`, `lib/compartilhamento.sh`)
- **Modulo:** `commands/compartilhar.sh`
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `backlog-fase-5-compartilhamento`)
- **Regras de origem:** F-15; F-16; RF-84; RF-85..RF-92; DIV-104..DIV-127; RSK-57..RSK-61; log `docs/prompts/2026-10-20_1110_backlog-fase-5-compartilhamento.md`; protocolo-tdd Regra 6
- **Aceite do solicitante:** [registro de aceite](../prompts/2026-10-20_1110_backlog-fase-5-compartilhamento.md) com sha256 `8adf68023874b67e2fb51de3b946d43b489b2a5952621b3b01203e4ecb566a76`
- **Dados e precondicoes:** duplo de `curl` proprio do QA (varre /proc em busca da senha sentinela lida de arquivo), terminal real por `script` nos casos de senha interativa, estado e raizes temporarias por caso
- **Comando:** `bash tests/run.sh tests/integracao/qa_compartilhamento_b5_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_s01_senha_so_no_corpo_em_todo_modo | A senha do link so trafega no arquivo de corpo, nunca em argv nem ambiente, em todo modo | RF-86; RSK-58 |
| teste_qa_s02_senha_na_modificacao_e_dry_run | A senha na modificacao e no dry-run tambem nao vaza | RF-86 |
| teste_qa_s03_eco_de_link_password_no_erro_e_redigido | Eco de link_password em mensagem de erro do servico e redigido | RF-86 |
| teste_qa_s04_error_summary_com_a_senha_nao_vaza | error_summary que contem a senha nao vaza na saida | RF-86 |
| teste_qa_s05_sinal_durante_a_chamada_limpa_tudo | Sinal durante a chamada remove o corpo e demais temporarios | RF-86 |
| teste_qa_s06_sigkill_deixa_a_senha_so_em_diretorio_privado | SIGKILL deixa a senha apenas em diretorio privado de permissao restrita | RF-86 |
| teste_qa_s07_terminal_sem_eco_e_confirmacao | Em terminal a senha e lida sem eco e com confirmacao | RF-86 |
| teste_qa_s08_senha_stdin_em_terminal_sem_eco_sem_confirmacao | Senha por entrada padrao em terminal e lida sem eco e sem confirmacao | RF-86 |
| teste_qa_s09_validacao_da_senha_antes_da_rede | A senha e validada antes de qualquer chamada de rede | RF-86 |
| teste_qa_s10_senha_na_linha_de_comando_recusada_sem_citar | Senha na linha de comando e recusada sem citar o valor | RF-86 |
| teste_qa_r01_metadados_hostis_nunca_revogam | Metadados hostis nunca levam a revogar link indevido | RF-89; DIV-104..DIV-127 |
| teste_qa_r02_raiz_barra_e_unicode | Raiz com barra e unicode e tratada no confinamento da revogacao | RF-89 |
| teste_qa_r03_urls_hostis_recusadas_antes_da_rede | URLs hostis sao recusadas antes da rede | RF-89 |
| teste_qa_r04_retentativa_e_dry_run_da_revogacao | Revogacao com retentativa e dry-run se comportam como especificado | RF-89 |
| teste_qa_r05_guarda_sem_estado | A revogacao nao depende nem grava estado local | RF-89 |
| teste_qa_v01_combinacoes_invalidas_saem_2_sem_rede | Combinacoes invalidas de opcoes saem com 2 sem chamar a rede | RF-85 |
| teste_qa_v02_ambiente_nao_escolhe_visibilidade | O ambiente nao escolhe a visibilidade do link | RF-85 |
| teste_qa_v03_corpo_corresponde_ao_pedido | O corpo enviado ao servico corresponde ao pedido feito | RF-85 |
| teste_qa_x01_reuso_so_quando_igual | Link existente so e reutilizado quando identico ao pedido | RF-87 |
| teste_qa_x02_publico_que_continua_publico_nao_atende_senha_nem_equipe | Link publico existente nao atende pedido com senha ou restrito a equipe | RF-87 |
| teste_qa_x03_varios_links_ou_nenhum_candidato | Varios links ou nenhum candidato levam ao tratamento definido | RF-87 |
| teste_qa_x04_dry_run_e_retentativa_da_criacao | Criacao em dry-run e com retentativa se comporta como especificado | RF-87 |
| teste_qa_l01_listagem_filtra_fora_da_raiz | A listagem filtra links fora da raiz configurada | RF-88 |
| teste_qa_l02_paginacao_que_nao_avanca | Paginacao cujo cursor nao avanca termina sem laco | RF-88 |
| teste_qa_l03_has_more_infinito_com_pagina_vazia_termina | has_more verdadeiro com pagina vazia termina | RF-88 |
| teste_qa_l04_confinamento_antes_da_rede | O confinamento do caminho e verificado antes da rede | RF-88 |
| teste_qa_l05_link_temporario_confere_a_resposta | link-temporario confere a resposta do servico antes de aceitar | RF-84 |
| teste_qa_e01_mapeamento_de_erros | Erros do servico sao mapeados para os codigos de saida corretos | RF-90 |
| teste_qa_e02_link_password_na_redacao | link_password e redigido na mensagem de erro | RF-90; RF-86 |
| teste_qa_d01_grafia_do_arquivo_nao_documentada | A grafia dos nomes de arquivo nao documentada nao altera o comportamento | DIV-104..DIV-127 |
| teste_qa_d02_diagnostico_escopos_de_compartilhamento | O diagnostico informa os escopos de compartilhamento da credencial | RF-91 |
| teste_qa_c01_senha_trecho_da_tag_nao_muda_a_classificacao | Senha igual a trecho da tag de erro nao muda a classificacao do erro | RF-86 |
| teste_qa_c02_mascara_com_metacaracteres | A mascara funciona com senha contendo metacaracteres | RF-86 |
| teste_qa_c03_senha_em_pedacos_nao_vaza | Senha dividida em pedacos na saida nao vaza | RF-86 |
| teste_qa_c04_credencial_embutida_nunca_citada | Credencial embutida em URL nunca e citada | RF-86 |
| teste_qa_c05_corpo_0600_e_mascara_intacta | O corpo da chamada tem permissao 0600 e a mascara permanece intacta | RF-86 |
| teste_qa_c06_pagina_vazia_em_qualquer_posicao | Pagina vazia em qualquer posicao da listagem nao quebra o resultado | RF-88 |
| teste_qa_c07_resposta_malformada_nunca_sai_0 | Resposta malformada do servico nunca resulta em saida 0 | RF-90 |
| teste_qa_c08_paridade_criacao_e_modify | Criacao e modificacao se comportam em paridade | RF-85 |
| teste_qa_c09_nenhum_texto_do_servico_com_a_senha_no_pedido | Nenhum texto do servico e exibido contendo a senha enviada no pedido | RF-86 |
| teste_qa_c10_host_hostil_na_recusa_de_url | Host hostil na recusa de URL nao e exibido de forma insegura | RF-89 |
| teste_qa_c11_teto_de_1000_paginas | A listagem respeita o teto de 1000 paginas | RF-88 |
| teste_qa_a01_suite_sem_captura_de_bytes_externos | A propria suite nao captura bytes externos, so o que o duplo registra | RSK-58 |


## `tests/integracao/qa_confinamento_remoto_b1b_test.sh`

- **Alvo:** `bin/dbx` (upload, download, list, delete, info, sync, verificar), `lib/path.sh` e `lib/cmd.sh`: confinamento a `raiz_remota` e recusa de byte de controle em caminho remoto
- **Modulo:** `qa_confinamento_remoto`
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `backlog-fase-1b-confinamento-remoto`)
- **Regras de origem:** F-36; F-37; RNF-20(b1..b8); RNF-10(b); TC-SEC-18..32; log `docs/prompts/2026-10-19_1243_backlog-fase-1b-confinamento-remoto.md`
- **Aceite do solicitante:** [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-19-1243-aceite-testes-qa-b1b.md) com sha256 `235b95e2fa46f9a40d7498c8031d6b856cf7bca14f212b29aa77fa0937830c62`
- **Dados e precondicoes:** duplo de `curl` proprio do QA cujo diario nao existe em recusa (prova de nenhuma chamada); `raiz_remota` configurada por `_qa_cenario`; localidades `C` e `C.UTF-8` (casos pulam se a ultima faltar)
- **Comando:** `bash tests/run.sh qa_confinamento_remoto`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_b1b_fuga_de_raiz_recusada_em_toda_forma_sem_chamada | Travessia, prefixo, caixa, relativo, id e demais formas de fugir da raiz sao recusadas antes de qualquer chamada de rede | TC-SEC-18..30 |
| teste_qa_b1b_dentro_da_raiz_aceito_e_enviado_literal | Nomes estranhos dentro da raiz sao aceitos e chegam a API com o prefixo da raiz, sem decodificacao | |
| teste_qa_b1b_caixa_unicode_nao_escapa_em_nenhuma_localidade | Caixa Unicode (ex.: U+0130) nao faz um caminho fora da raiz passar por dentro dela em nenhuma localidade | |
| teste_qa_b1b_dobra_especial_nao_casa_com_a_raiz_em_nenhuma_localidade | Dobras especiais e normalizacoes Unicode (NFC e NFD) nao casam com a raiz de forma indevida | |
| teste_qa_b1b_raiz_com_acento_identica_ou_so_ascii_em_outra_caixa_e_aceita | Raiz com acento identica, ou so ASCII em outra caixa, e aceita | |
| teste_qa_b1b_dobra_ascii_nao_vaza_localidade_para_o_processo | A dobra ASCII do confinamento nao deixa `LC_ALL=C` ativo no processo apos o retorno | |
| teste_qa_b1b_controle_em_cada_posicao_recusado_sem_byte_cru | Byte de controle em qualquer posicao do caminho e recusado e nunca ecoado cru na saida | RNF-10(b) |
| teste_qa_b1b_destino_derivado_do_upload_de_diretorio_e_reconfinado | Destino derivado do upload de diretorio (nome local com quebra de linha) e confinado de novo e recusado | TC-SEC-32 |
| teste_qa_b1b_simulacao_tambem_recusa_fora_da_raiz | `--dry-run` tambem recusa caminho fora da raiz | |
| teste_qa_b1b_raiz_da_conta_nada_muda | Com raiz `/` ou vazia (raiz da conta) o comportamento nao muda | |
| teste_qa_b1b_list_sem_argumento_lista_a_raiz_configurada | `list` sem argumento lista a raiz configurada, em qualquer grafia equivalente dela | |
| teste_qa_b1b_raiz_malformada_falha_fechado_com_3 | Raiz malformada (relativa, com `..`, com controle, id) falha fechada com saida 3 | |
| teste_qa_b1b_raiz_com_controle_list_sem_argumento_sai_3 | `list` sem argumento com raiz contendo controle sai com 3 | TC-SEC-31; RNF-20(b8) |


## `tests/integracao/qa_consulta_diagnostico_b1_test.sh`

- **Alvo:** `bin/dbx` (`verificar`/`verify`, `diagnostico`, checagem previa de espaco em `upload` e `sync --enviar`, autocompletar de bash e `install.sh`)
- **Modulo:** `qa_consulta_diagnostico`
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `backlog-fase-1-consulta-diagnostico`)
- **Regras de origem:** RF-65 a RF-68; log `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md`; protocolo-tdd Regra 6 (cenarios negativos de caminho hostil e vazamento de segredo)
- **Aceite do solicitante:** [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md) e [log de prompt](../prompts/2026-10-24_1153_suporte-freebsd.md), com sha256 `9a0dab8d0dca3ec9db4e40eed20c3b5b37c4512995c133f30a15ca9ee661920a`
- **Dados e precondicoes:** cada caso cria a propria massa (`_qa_cenario`, massa derivada sob `DBX_TESTES_TMP`); duble de `curl`, valores sentinela e retrato do estado proprios do QA; casos independentes entre si, descarte ao fim do roteiro
- **Comando:** `bash tests/run.sh tests/integracao/qa_consulta_diagnostico_b1_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_cpl_funciona_sem_curl_e_sem_rede | O script de autocompletar funciona sem `curl` e sem rede | |
| teste_qa_cpl_install_idempotente_sem_sudo_e_uninstall_remove | A instalacao do autocompletar e idempotente, dispensa sudo e a desinstalacao remove | |
| teste_qa_cpl_opcoes_do_script_batem_com_a_ajuda | As opcoes oferecidas pelo autocompletar coincidem com as da ajuda | |
| teste_qa_dia_cada_utilitario_ausente_um_por_um | Com cada utilitario do preflight ausente do `PATH`, o diagnostico o aponta como ausente | |
| teste_qa_dia_credencial_larga_ausente_ou_corrompida_nao_vaza_nada | Credencial larga, ausente ou corrompida nao vaza segredo no diagnostico | |
| teste_qa_dia_falha_de_rede_que_ecoa_segredos_nao_vaza | Falha de rede cujo corpo ecoa segredos nao os vaza no diagnostico | |
| teste_qa_esp_consulta_que_falha_so_avisa_uma_vez | Consulta de espaco que falha avisa uma unica vez e a transferencia segue | |
| teste_qa_esp_entrada_padrao_nao_consulta | Upload por entrada padrao nao consulta o espaco disponivel | |
| teste_qa_esp_forcar_pula_e_forcar_com_receber_e_recusado | `--forcar` pula a checagem de espaco e combinado com receber e recusado | |
| teste_qa_esp_ordem_em_relacao_as_guardas_do_sync | A checagem de espaco ocorre na ordem prevista em relacao as guardas do `sync` | |
| teste_qa_esp_simulacao_so_avisa_e_nao_escreve | Em simulacao a checagem de espaco so avisa e nada e escrito | |
| teste_qa_esp_sobrescrita_conta_o_arquivo_inteiro_no_upload_e_no_sync | Sobrescrita conta o arquivo inteiro na checagem de espaco, no upload e no sync | |
| teste_qa_esp_sync_cabe_exatamente_e_falta_um_byte_sem_memoria | No sync, espaco exato passa e falta de um byte recusa, sem usar memoria de estado | |
| teste_qa_esp_upload_cabe_exatamente_e_falta_um_byte | No upload, espaco exato passa e falta de um byte recusa | |
| teste_qa_ver_caixa_decide_por_conteudo_e_colisao_recusa_sem_rede | `verificar` decide diferenca de caixa pelo conteudo e recusa colisao sem usar a rede | |
| teste_qa_ver_caminhos_hostis_recusados_antes_da_api | Caminhos hostis sao recusados por `verificar` antes de qualquer chamada a API | |
| teste_qa_ver_erro_de_execucao_prevalece_sobre_divergencia | Erro de execucao prevalece sobre divergencia no codigo de saida de `verificar` | |
| teste_qa_ver_estado_fica_byte_a_byte_igual_presente_ou_ausente | `verificar` deixa o diretorio de estado byte a byte igual, presente ou ausente | |
| teste_qa_ver_opcoes_do_sync_sao_recusadas_sem_nenhum_efeito | Opcoes exclusivas do `sync` passadas a `verificar` sao recusadas sem efeito algum | |
| teste_qa_ver_quebra_de_linha_no_remoto_nao_forja_linha | Nome remoto com quebra de linha nao forja linha na saida de `verificar` | |
| teste_qa_ver_vinculo_para_fora_nao_vaza_nome_nem_conteudo | Vinculo simbolico apontando para fora nao vaza nome nem conteudo do alvo | |


## `tests/integracao/qa_cursor_b7b_test.sh`

- **Alvo:** `bin/dbx sync --receber` com cursor de listagem (`commands/sync.sh`, `lib/state.sh`, `lib/sync.sh`, `lib/hash.sh`)
- **Modulo:** qa_cursor
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `backlog-fase-7b-cursor`)
- **Regras de origem:** F-14; RF-110..RF-119; RF-43; RF-48; DIV-204..DIV-234; condicoes C1..C11 do DBA; TC-CUL-04; TC-CUL-05; log `docs/prompts/2026-10-21_0713_backlog-fase-7b-cursor.md`; [entrada](../../.github/agents/memoria/entradas/2026-10-21-0713-cursor.md)
- **Aceite do solicitante:** [entrada](../../.github/agents/memoria/entradas/2026-10-21-0713-cursor.md) com sha256 `8c40c6f0f77ea0dd9e147e4ba6e21898366e7e131f5b51043e021ce05235e4b6`; alterado na demanda `sync-em-blocos`: novo sha256 `15045c18464902f61c70069c513a506cd3ac8f7fa2e3ed251a82e26af4ab5159`, reaprovado em 2026-10-31, [entrada](../../.github/agents/memoria/entradas/2026-10-31-1200-aceite-testes-qa-sync-em-blocos.md)
- **Dados e precondicoes:** duble de `curl` proprio por regras (endpoint, filtro do corpo, codigo, resposta; codigos especiais `REDE` e `SINAL:NOME`), registros de chamadas, argv e ambiente em arquivos temporarios; sem rede
- **Comando:** `bash tests/run.sh tests/integracao/qa_cursor_b7b_test.sh`
- **Observacoes (demanda `sync-em-blocos`):** o duplo de `curl` passou a responder `list_folder` nao recursivo e `get_latest_cursor` (RF-189); nenhum caso foi criado ou removido.
- **Observacoes:** escrita como adversario, com foco em P0: o registro (cursor mais retrato) nunca causa sozinho exclusao local; o cursor nunca vaza.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_a01_retrato_forjado_com_rodape_valido_nunca_apaga | Retrato forjado com rodape recalculado valido nao leva a apagar nenhum arquivo local. | |
| teste_qa_a02_retrato_forjado_sem_arquivo_algum_nao_vira_origem_vazia | Retrato forjado sem arquivo algum nao e tratado como origem vazia e nada e apagado. | |
| teste_qa_a03_deleted_de_item_que_ainda_existe_nunca_apaga | Entrada deleted do delta para item que ainda existe no servidor nunca apaga o arquivo local. | |
| teste_qa_a04_resposta_duvidosa_na_confirmacao_nunca_apaga | Resposta duvidosa na confirmacao de exclusao (diferente de not_found) nunca apaga. | |
| teste_qa_a05_pasta_apagada_e_arquivo_readicionado_no_mesmo_delta | Pasta apagada e arquivo readicionado no mesmo delta: o arquivo readicionado e preservado. | |
| teste_qa_a06_arquivo_no_lugar_de_pasta_e_pasta_no_lugar_de_arquivo | Troca de tipo (arquivo no lugar de pasta e o inverso) e tratada sem apagar conteudo indevido. | |
| teste_qa_a07_renomeacao_so_de_caixa_relatada_nunca_apaga | Renomeacao so de caixa relatada pelo delta nunca apaga o arquivo. | |
| teste_qa_a08_simulacao_com_confirmacoes_nunca_apaga_nem_toca_o_estado | Simulacao com confirmacoes nao apaga nada nem altera o registro de estado. | |
| teste_qa_a09_sem_espelhar_confirmada_vira_apenas_no_destino_e_fica | Sem `--espelhar`, exclusao confirmada vira apenas-no-destino e o arquivo local permanece. | |
| teste_qa_a10_registro_adulterado_sem_recalcular_rodape_e_descartado | Registro adulterado sem recalcular o rodape SHA-256 e descartado e a varredura completa e usada. | |
| teste_qa_b01_cadeia_de_execucoes_reais_converge_para_o_servidor | Cadeia de execucoes reais incrementais converge para o mesmo estado do servidor. | |
| teste_qa_b02_filtros_trocados_entre_execucoes_mesmo_plano | Trocar filtros entre execucoes produz o mesmo plano que a varredura completa. | |
| teste_qa_b03_filtro_de_data_sem_data_no_retrato_vai_a_completa_com_mesmo_plano | Filtro de data sem data no retrato cai na varredura completa com o mesmo plano. | |
| teste_qa_b04_filtro_de_data_nas_duas_execucoes_incremental_com_mesmo_plano | Filtro de data nas duas execucoes usa o incremental e produz o mesmo plano da completa. | |
| teste_qa_b05_edicao_local_extra_local_e_remoto_alterado | Edicao local, arquivo local extra e remoto alterado geram plano igual ao da completa. | |
| teste_qa_c01_erros_do_continue_voltam_a_completa_na_mesma_execucao | Erros do `list_folder/continue` (reset, 409, 4xx, 5xx, 429, rede) voltam a varredura completa na mesma execucao. | |
| teste_qa_c02_401_e_403_no_continue_mantem_a_classe_5_e_nao_avancam | 401 e 403 no continue mantem a classe de erro 5 e nao avancam o registro. | |
| teste_qa_c03_cursor_repetido_e_has_more_sem_cursor_abandonam_o_incremental | Cursor repetido ou has_more sem cursor abandona o incremental. | |
| teste_qa_c04_varredura_periodica_por_idade_contagem_e_relogio | Varredura completa periodica dispara por idade (7 dias), contagem (100 incrementais) e relogio anomalo. | |
| teste_qa_c05_cabecalho_de_outra_conta_raiz_listagem_versao_e_descartado | Registro com cabecalho de outra conta, raiz, listagem ou versao e descartado. | |
| teste_qa_c06_retrato_forjado_com_campo_invalido_e_descartado | Retrato forjado com campo invalido ou acima do teto e descartado. | |
| teste_qa_c07_ligacao_simbolica_para_registro_valido_nao_e_seguida | Ligacao simbolica apontando para registro valido nao e seguida. | |
| teste_qa_c08_fifo_no_registro_nao_pendura_diagnostico_nem_unlink | FIFO no lugar do registro nao pendura `diagnostico` nem `unlink`. | |
| teste_qa_d01_falha_parcial_nao_avanca_o_registro | Execucao com falha parcial nao avanca o registro de cursor. | |
| teste_qa_d02_memoria_descartada_nao_toca_o_cursor_e_vice_versa | Descartar a memoria nao toca o cursor, e descartar o cursor nao toca a memoria. | RF-43; RF-48 |
| teste_qa_d03_cursor_sem_memoria_nao_vale_como_par_visto | Cursor existente sem memoria correspondente nao vale como par ja visto. | |
| teste_qa_d04_enviar_verificar_e_download_de_pasta_nao_tocam_cursor | `--enviar`, `verificar` e download de pasta nao leem nem gravam o cursor. | |
| teste_qa_e01_sinal_durante_o_continue | Sinal durante o `continue` sai sem gravar registro de cursor. | TC-CUL-04 |
| teste_qa_e02_sinal_durante_as_confirmacoes | Sinal durante as confirmacoes de exclusao sai sem apagar nem gravar registro. | TC-CUL-05 |
| teste_qa_e03_falha_de_transporte_na_confirmacao_falha_sem_plano | Falha de transporte na confirmacao falha a execucao sem produzir plano. | |
| teste_qa_f01_opcoes_invalidas_saem_2_sem_tocar_estado | Opcoes invalidas de cursor saem com 2 sem tocar o estado. | |
| teste_qa_f02_sem_cursor_nao_le_nao_grava_nao_apaga | Com `--sem-cursor`, o registro nao e lido, nao e gravado e nao e apagado. | |
| teste_qa_f03_cursor_nunca_sai_por_saida_argv_ambiente_ou_residuo | O valor do cursor nunca aparece em stdout, stderr, `--json`, `--null`, `--debug`, `diagnostico`, argv, ambiente do cliente HTTP nem residuo temporario. | C10 |
| teste_qa_f04_umask_000_registro_0600_e_diretorio_0700 | Mesmo com umask 000, o registro nasce 0600 e o diretorio de estado 0700. | |
| teste_qa_f05_campos_em_json_e_null | Os campos de cursor aparecem corretos nas saidas `--json` e `--null`. | |
| teste_qa_f06_poda_de_registros_de_outros_pares_nunca_alcanca_outros_namespaces | A poda de registros de cursor de outros pares nunca alcanca arquivos de outros namespaces. | |
| teste_qa_f07_unlink_remove_cursor_e_diagnostico_lista | `unlink` remove o registro de cursor e `diagnostico` o lista (so o cabecalho). | |
| teste_qa_g01_continue_sem_limit_no_verificar_e_no_enviar | O `continue` nao leva `limit`, tambem no `verificar` e no `--enviar`. | DIV-214; DIV-233 |
| teste_qa_h01_raiz_barra_incremental_confirma_e_contradiz_por_servidor | Com raiz `/`, o incremental confirma e a contradicao vem do servidor. | |
| teste_qa_h02_entrada_da_raiz_na_completa_nao_vira_porta | Entrada da propria raiz na varredura completa e ignorada e nao vira porta de exclusao. | |
| teste_qa_h03_entrada_da_raiz_no_delta | Entrada da propria raiz no delta e ignorada sem invalidar o retrato. | |
| teste_qa_h04_delta_com_caminho_fora_do_confinamento_vai_a_completa | Delta com caminho fora do confinamento da raiz cai na varredura completa. | |
| teste_qa_h05_deleted_com_grafia_diferente_nunca_apaga_o_que_o_mapa_tem | Deleted com grafia diferente (caixa) nunca apaga o que o mapa ainda tem. | |
| teste_qa_h06_raiz_na_linha_de_comando_com_caixa_e_barra_final | Raiz na linha de comando com caixa diferente e barra final usa o mesmo registro. | |
| teste_qa_h07_raiz_unicode_em_localidade_c_e_segura | Raiz com caracteres unicode sob localidade C funciona de forma segura. | |
| teste_qa_h08_registros_da_raiz_barra_e_da_subpasta_nao_se_cruzam | Registros da raiz `/` e de uma subpasta nao se cruzam. | |
| teste_qa_z01_raiz_remota_barra_usa_o_cursor | Com raiz remota `/`, o cursor e usado normalmente. | |
| teste_qa_z02_listagem_com_a_propria_pasta_grava_o_registro | Listagem que inclui a propria pasta como entrada grava o registro de cursor. | |
| teste_qa_z03_delta_com_path_lower_fora_da_raiz_e_incoerente | Delta com `path_lower` fora da raiz e tratado como incoerente e recusado. | |


## `tests/integracao/qa_debug_transferencias_b12_test.sh`

- **Alvo:** `bin/dbx` nos tres comandos de transferencia (download, upload e sync) com `--debug` (`lib/http.sh`, `lib/transfer.sh`, `commands/sync.sh`, `commands/upload.sh`, `commands/download.sh`)
- **Modulo:** qa_debug
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `debug-transferencias`)
- **Regras de origem:** RF-156..RF-165; regra 12 do `AGENTS.md` (aceite pela regra 12); log `docs/prompts/2026-10-24_0330_debug-transferencias.md`; [entrada](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md)
- **Aceite do solicitante:** [entrada](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md) com sha256 `fa2d971d2a3da45c09e11f31f40ece3d78de01210901406cdae3c069e2fca987`
- **Dados e precondicoes:** duble de `curl` de `tests/support/disponibilidade.sh`, sentinelas sinteticas (sessao, cursor, URL, senha, token, refresh, segredo, chave) e cenario de sync proprio em diretorio temporario; sem rede
- **Comando:** `bash tests/run.sh tests/integracao/qa_debug_transferencias_b12_test.sh`
- **Observacoes:** os invariantes sao stdout, codigo de saida e numero de requisicoes iguais com e sem `--debug`, sem sentinela de segredo em nenhum canal.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_caminho_com_espaco_aspas_quebra_e_controle_fica_em_uma_linha | Caminho com espaco, aspas, quebra de linha e controle sai escapado em uma unica linha de debug. | |
| teste_qa_credencial_ausente_invariantes_e_um_resumo | Sem credencial, o codigo de saida e o stdout sao os mesmos com e sem debug, e ha um unico resumo. | |
| teste_qa_debug_com_progresso_sem_carriage_return_e_sem_mistura | Debug com progresso ativo nao emite `\r` e nao mistura linhas. | |
| teste_qa_download_5xx_e_rede_invariantes | Download com 5xx e com falha de rede mantem os invariantes e nao vaza segredo. | |
| teste_qa_download_arquivo_invariantes_e_segredos | Download de arquivo mantem os invariantes e nenhuma sentinela aparece. | |
| teste_qa_download_hash_divergente_registra_e_mantem_codigo | Download com hash divergente registra o fato no debug e mantem o codigo de saida de integridade. | |
| teste_qa_download_stdout_conteudo_intacto_e_debug_so_em_stderr | Download para stdout entrega o conteudo intacto e o debug vai so para stderr. | |
| teste_qa_download_stdout_omitido_destino_conteudo_intacto | Download com destino omitido (stdout) entrega o conteudo intacto com debug ligado. | |
| teste_qa_sinal_int_antes_da_primeira_requisicao_upload | INT antes da primeira requisicao do upload sai limpo, sem segredo e com resumo coerente. | |
| teste_qa_sinal_int_durante_a_transferencia_upload | INT durante a transferencia do upload sai limpo, sem segredo nem linha truncada. | |
| teste_qa_sinal_int_durante_o_sync_enviar | INT durante o `sync --enviar` sai limpo e sem vazar segredo. | |
| teste_qa_sinal_term_antes_da_primeira_requisicao_de_dados_upload | TERM antes da primeira requisicao de dados do upload sai limpo. | |
| teste_qa_sinal_term_durante_a_transferencia_upload | TERM durante a transferencia do upload sai limpo, sem segredo. | |
| teste_qa_sinal_term_durante_o_download | TERM durante o download sai limpo, sem segredo e sem residuo. | |
| teste_qa_sinal_term_durante_o_sync_paralelo | TERM durante o sync paralelo sai limpo e sem vazar segredo. | |
| teste_qa_sync_com_arquivo_de_nome_hostil_uma_linha_por_evento | Sync com arquivo de nome hostil emite uma linha de debug por evento. | |
| teste_qa_sync_enviar_credencial_ausente_invariantes | `sync --enviar` sem credencial mantem os invariantes com debug. | |
| teste_qa_sync_enviar_invariantes_e_segredos | `sync --enviar` mantem os invariantes e nao vaza segredo. | |
| teste_qa_sync_enviar_paralelo_resumo_soma_auxiliares_e_sem_segredo | `sync --enviar` paralelo tem resumo unico que soma as chamadas dos auxiliares, sem segredo. | |
| teste_qa_sync_receber_download_5xx_invariantes | `sync --receber` com download 5xx mantem os invariantes. | |
| teste_qa_sync_receber_invariantes_cursor_nunca_aparece | `sync --receber` mantem os invariantes e o valor do cursor nunca aparece. | RF-164 |
| teste_qa_sync_receber_paralelo_invariantes_e_ordem | `sync --receber` paralelo mantem os invariantes e a ordem das linhas por item. | |
| teste_qa_upload_409_conflito_invariantes | Upload com 409 de conflito mantem os invariantes e registra a classe de falha. | |
| teste_qa_upload_5xx_falha_invariantes | Upload com 5xx definitivo mantem os invariantes e registra a falha. | |
| teste_qa_upload_rede_falha_invariantes | Upload com falha de rede mantem os invariantes e registra a falha. | |
| teste_qa_upload_retentativa_429_503_linha_por_tentativa_e_retry_after_com_teto | Retentativas por 429 e 503 geram uma linha por tentativa, com `Retry-After` limitado ao teto. | |
| teste_qa_upload_sessao_stdin_sem_id_de_sessao_e_resumo_correto | Upload de stdin por sessao nunca expoe o id da sessao e o resumo esta correto. | |
| teste_qa_upload_simples_sucesso_invariantes_e_segredos | Upload simples bem-sucedido mantem os invariantes e nenhum segredo aparece. | |


## `tests/integracao/qa_desempenho_b9_test.sh`

- **Alvo:** `bin/dbx` (`sync` em paralelo e em lote, `sync --espelhar`, `reter`), `commands/sync.sh`, `commands/reter.sh`, `lib/lote.sh`, bancada de desempenho
- **Modulo:** qa_desempenho
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `backlog-fase-9-desempenho`)
- **Regras de origem:** F-09, F-08, F-34; RF-136, RF-137, RF-138; DIV-269, DIV-278; protocolo-tdd Regra 6; log `docs/prompts/2026-10-21_2300_backlog-fase-9-desempenho.md`
- **Aceite do solicitante:** [entrada de reaprovacao](../../.github/agents/memoria/entradas/2026-10-27-1500-aceite-reaprovacao-inventario.md), sha256 `2630f5364fd3da79f3f6a36ca67b61722b9f010e50a86f6d7603e312bef90c47` (reaprovado em 2026-10-27; a versao aceita antes havia sido alterada sem novo aceite)
- **Dados e precondicoes:** duplo de `curl` proprio delegando as rotas de lote a `tests/support/lote_duplo.sh`; arquivos sinteticos temporarios; sem rede nem conta real
- **Comando:** `bash tests/run.sh tests/integracao/qa_desempenho_b9_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qdb01_envio_de_pequenos_e_equivalente_com_n_1_2_4_e_8 | O envio em lote de arquivos pequenos produz o mesmo resultado com paralelismo 1, 2, 4 e 8 | RF-137 |
| teste_qdb02_falha_por_item_e_igual_em_n_1_e_n_4_e_nao_entra_no_cache | Falha de um item e reportada igual com N=1 e N=4 e o item falho nao entra no cache | RF-137 |
| teste_qdb03_paralelo_invalido_sai_2_antes_da_rede_e_a_opcao_vence_o_ambiente | `--paralelo` invalido sai com codigo 2 antes de qualquer chamada, e a opcao prevalece sobre a variavel de ambiente | F-09 |
| teste_qdb04_dry_run_com_paralelo_nao_usa_rede_de_escrita | `--dry-run` com paralelismo nao faz nenhuma chamada de escrita | F-09 |
| teste_qdb05_espelhar_exclui_em_um_lote_com_parent_rev_e_sem_delete_v2 | `sync --espelhar` exclui em lote com `parent_rev` por item e sem usar a rota `delete_v2` | RF-136 |
| teste_qdb06_guardas_agem_antes_de_montar_o_lote | As guardas de seguranca da exclusao agem antes de o lote ser montado | RF-136 |
| teste_qdb07_item_nao_confirmado_nunca_conta_como_apagado | Item cuja exclusao nao foi confirmada pelo servidor nunca e contado como apagado | RF-136 |
| teste_qdb08_lote_de_exclusao_vai_em_fatias_de_250 | A exclusao em lote e enviada em fatias de no maximo 250 itens | RF-136 |
| teste_qdb09_reter_nunca_usa_rota_de_lote_e_o_sync_nao_tem_delete_v2 | `reter` nunca usa a rota de lote e o `sync` nao chama `delete_v2` | DIV-269 |
| teste_qdb10_hash_divergente_no_lote_falha_so_o_item_com_integridade | Hash divergente no lote faz falhar apenas o item afetado, com erro de integridade | RF-137 |
| teste_qdb11_start_leva_o_content_hash_local | A abertura de sessao do lote leva o `content_hash` local de cada item | RF-137, DIV-278 |
| teste_qdb12_falha_do_finish_inteiro_nao_grava_cache_e_start_recusado_falha_so_o_item | Falha do `finish` inteiro nao grava cache; `start` recusado falha so o item correspondente | RF-137 |
| teste_qdb13_identico_nunca_entra_no_lote_e_acima_do_limiar_segue_o_caminho_unitario | Arquivo identico ao remoto nunca entra no lote e arquivo acima do limiar segue o caminho unitario | RF-137 |
| teste_qdb14_bancada_nao_deixa_segredo_de_formato_conhecido_nos_logs | A bancada nao deixa segredo de formato conhecido nos logs gerados | RF-138 |
| teste_qdb15_bancada_redige_basic_e_chaves_de_credencial | A bancada redige cabecalho Basic e chaves de credencial na saida | RF-138 |


## `tests/integracao/qa_disponibilidade_b11_test.sh`

- **Alvo:** `bin/dbx testar` e a deteccao automatica de disponibilidade (internet, servico Dropbox, credencial) nos comandos de nivel credencial, com oferta de inicio do `config`
- **Modulo:** `qa_disponibilidade`
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `teste-de-disponibilidade`)
- **Regras de origem:** RF-148..RF-155; protocolo-tdd Regra 6 (nenhum segredo em canal algum); log `docs/prompts/2026-10-23_0900_teste-de-disponibilidade.md`
- **Aceite do solicitante:** [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-23-0900-teste-de-disponibilidade.md) com sha256 `ffe3ef0ea7f4cf69d96465d2960828b30597b9735ec88412ca2231e4a3db96ec`
- **Dados e precondicoes:** duplo de `curl` e pty de `tests/support/disponibilidade.sh`; cenarios, valores e sentinelas de URL proprios do QA; estado e `TMPDIR` temporarios por caso
- **Comando:** `bash tests/run.sh tests/integracao/qa_disponibilidade_b11_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_api_429_continua_limite_de_taxa | 429 da API continua classificado como limite de taxa, nao como indisponibilidade | |
| teste_qa_api_503_e_servico_indisponivel_dez | 503 da API e classificado como servico indisponivel com codigo 10 | |
| teste_qa_automatico_dropbox_inacessivel_nao_culpa_a_internet | Com Dropbox inacessivel e internet ok, a mensagem nomeia o servico e nao a internet | |
| teste_qa_automatico_json_com_debug_stdout_igual | Com `--json` e `--debug`, o stdout e igual ao do `--json` sem debug | |
| teste_qa_automatico_renovacao_503_sai_dez | 503 na renovacao do token sai com codigo 10 | |
| teste_qa_automatico_sem_internet_nomeia_internet_com_uma_so_sonda | Sem internet, a mensagem nomeia a internet e so uma sonda e feita | |
| teste_qa_caminho_feliz_com_url_invalida_continua_sem_sonda | No caminho feliz, URL de sonda invalida nao impede o comando nem dispara sonda | |
| teste_qa_caminho_feliz_nao_faz_requisicao_extra | No caminho feliz nenhuma requisicao extra de disponibilidade e feita | |
| teste_qa_campo_vazio_e_nomeado_sem_valor | Campo de config vazio e nomeado na mensagem sem exibir valor | |
| teste_qa_comandos_de_fora_nao_oferecem | Comandos fora do nivel credencial nao oferecem o `config` | |
| teste_qa_content_503_falha_so_o_servico_conteudo | 503 no host de conteudo acusa apenas o servico de conteudo | |
| teste_qa_dropbox_inacessivel_com_internet_ok_sai_nove_e_nomeia_o_servico | Dropbox inacessivel com internet ok sai com codigo 9 e nomeia o servico | |
| teste_qa_dry_run_com_terminal_nao_oferece | `--dry-run` com terminal nao oferece o `config` | |
| teste_qa_falha_no_meio_com_terminal_nao_oferece_config | Falha no meio do comando, mesmo com terminal, nao oferece o `config` | |
| teste_qa_json_com_terminal_recusa_deixa_stdout_vazio | `--json` com terminal e oferta recusada deixa o stdout vazio | |
| teste_qa_json_e_null_com_debug_tem_o_mesmo_stdout | `--json` e `--null` com `--debug` mantem o mesmo stdout do contrato | |
| teste_qa_nenhum_segredo_em_nenhum_canal_nem_na_url_da_sonda | Nenhum segredo aparece em canal algum nem na URL da sonda | protocolo-tdd Regra 6 |
| teste_qa_nenhum_temporario_sobrevive | Nenhum temporario da deteccao sobrevive ao fim do comando | |
| teste_qa_null_so_tem_registros_do_contrato | A saida `--null` contem apenas os registros do contrato | |
| teste_qa_permissao_aberta_nao_oferece_o_config | Arquivo de config com permissao aberta nao recebe a oferta de `config` | |
| teste_qa_recusa_com_credencial_recusada_mantem_o_arquivo_e_sai_cinco | Recusar a oferta com credencial recusada mantem o arquivo e sai com codigo 5 | |
| teste_qa_requisicoes_sem_token_nao_carregam_credencial | Requisicoes da sonda, sem token, nao carregam credencial | protocolo-tdd Regra 6 |
| teste_qa_resposta_diferente_de_s_recusa_sem_alterar_nada | Qualquer resposta diferente de `s` recusa a oferta sem alterar nada | |
| teste_qa_resposta_s_maiusculo_aceita | A resposta `S` maiuscula aceita a oferta | |
| teste_qa_resposta_sim_por_extenso_aceita_e_o_comando_continua | A resposta `sim` aceita a oferta e o comando original continua | |
| teste_qa_sem_terminal_invalid_grant_sai_cinco_sem_pergunta | Sem terminal, `invalid_grant` sai com codigo 5 sem fazer pergunta | |
| teste_qa_sem_terminal_nunca_consome_stdin_credencial_ausente | Sem terminal e sem credencial, o stdin nunca e consumido | |
| teste_qa_sonda_com_qualquer_status_http_conta_como_internet | Qualquer status HTTP na sonda conta como internet disponivel | |
| teste_qa_sonda_desligada_nao_faz_requisicao_e_nao_distingue_a_causa | Com a sonda desligada nao ha requisicao e a causa nao e distinguida | |
| teste_qa_sync_paralelo_com_rede_caida_faz_uma_sonda | `sync` paralelo com rede caida faz uma unica sonda, nao uma por processo | |
| teste_qa_sync_paralelo_url_invalida_avisa_uma_vez_sem_o_valor | `sync` paralelo com URL de sonda invalida avisa uma vez, sem exibir o valor | |
| teste_qa_testar_url_invalida_sai_dois_sem_requisicao | `testar` com URL de sonda invalida sai com codigo 2 sem requisicao | |
| teste_qa_url_da_sonda_nao_injeta_opcao_no_curl | URL de sonda iniciada por hifen nao vira opcao do `curl` | protocolo-tdd Regra 6 |


## `tests/integracao/qa_docs_aliases_p4_test.sh`

- **Alvo:** `bin/dbx` (aliases em ingles dos comandos e opcoes, guarda de origem vazia pelo plano, fixacao de localidade na comparacao do sync), `README.md` e System Design
- **Modulo:** qa_docs_aliases
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `docs-e-aliases-p4`)
- **Regras de origem:** RF-64; RF-41(b); RF-54(e)(f)(g); RNF-34; RNF-03; DIV-30; DIV-31; DIV-32; TC-ALI-02; TC-ALI-03; TC-CX-04; TC-CX-05; log `docs/prompts/2026-10-19_0829_docs-e-aliases-p4.md`; [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md)
- **Aceite do solicitante:** [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md) com sha256 `17192612b94d60d51b855e482d9a499101de505d81b85f1ec89bb28346708467`
- **Dados e precondicoes:** cada caso monta seu cenario (credencial sintetica, duble de `curl`, arvore local); primeira execucao de um caso serve de seeder das seguintes; localidade `C.UTF-8` quando disponivel (caso pula se ausente); limpeza da area do executor ao fim
- **Comando:** `bash tests/run.sh tests/integracao/qa_docs_aliases_p4_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_p4_alias_sync_execucao_real_em_ingles_misto_e_portugues_deixa_o_mesmo_estado | Sync real com espelhamento nos dois sentidos deixa o mesmo estado, saida e chamadas em ingles, misto e portugues | RF-64(b)(d) |
| teste_qa_p4_alias_formas_nao_aceitas_recusam_como_o_portugues_sem_rede | Forma `--opcao=valor` e abreviacao sao recusadas como uso invalido, igual ao portugues, sem chamada de rede | RF-64 |
| teste_qa_p4_alias_repeticao_pelos_dois_nomes_segue_a_regra_do_portugues | Segundo sentido e recusado em qualquer combinacao de nomes; opcao sem valor e idempotente; com valor vale o ultimo | RF-64(e); DIV-31 |
| teste_qa_p4_alias_unlink_ingles_misto_e_repetido_deixam_o_estado_do_portugues | `unlink` com nomes em ingles, misto e repetido produz mesmo codigo, saida, credencial e estado que o portugues | TC-ALI-02 |
| teste_qa_p4_alias_config_recusas_e_ultimo_valor_iguais_ao_portugues | `config` com alias recusa sem valor, forma com `=`, credencial existente e raiz invalida como o portugues, e o ultimo valor vence | TC-ALI-03 |
| teste_qa_p4_alias_ajuda_e_readme_documentam_os_onze_pares | A ajuda do comando e o README trazem os onze pares portugues/ingles na mesma linha | RF-64(c) |
| teste_qa_p4_guarda_pull_mirror_yes_sem_memoria_recusa_pelo_plano_e_so_allow_libera | Par nunca visto com origem remota vazia e destino povoado: recusa pelo plano e so a autorizacao explicita libera | RF-41(b) |
| teste_qa_p4_guarda_sem_espelhar_origem_vazia_nao_escreve_nada_e_sai_zero | Sem `--espelhar`, origem vazia e operacao vazia: nada e escrito e a saida e 0 | DIV-30 |
| teste_qa_p4_guarda_raiz_ausente_ou_arquivo_segue_recusada_sem_espelhar | Raiz ausente ou que e arquivo continua recusada mesmo sem `--espelhar` | RF-41(b) |
| teste_qa_p4_localidade_receber_espelhado_com_lc_all_c_nao_duplica_nem_apaga | Receber espelhado sob `LC_ALL=C` com `É` local e `é` remoto de mesmo conteudo nao duplica nem apaga | TC-CX-04 |
| teste_qa_p4_localidade_fixacao_nao_vaza_para_o_processo_sob_c_e_sob_utf8 | Depois da comparacao, `LC_ALL` volta ao valor anterior (inclusive ausente) e medida de `${#x}` e escape de JSON ficam iguais | RF-54(e); DIV-32 |
| teste_qa_p4_localidade_valor_fora_do_alfabeto_cai_no_padrao_e_c_puro_avisa | `DBX_SYNC_LOCALIDADE` fora do alfabeto vale o padrao sem aviso; nome valido so ASCII (`C`) avisa uma vez | RF-54(f) |
| teste_qa_p4_localidade_ausente_aviso_unico_fora_do_stdout_sem_segredo | Localidade ausente: aviso unico apenas em stderr, sem segredo, com codigo e stdout iguais aos da execucao normal | TC-CX-05; RF-54(f); RNF-03 |
| teste_qa_p4_localidade_nao_muda_bytes_enviados_a_rede | Envio de arquivo de nome multibyte sai com os mesmos cabecalhos e corpo sob `LC_ALL=C` e sob o padrao | RF-54(e) |
| teste_qa_p4_doc_readme_lista_os_utilitarios_do_preflight_e_nao_tem_frase_revogada | O README lista os utilitarios do preflight e nao traz a frase revogada | RNF-34 |
| teste_qa_p4_doc_system_design_marca_a_decisao_revogada_na_propria_linha | A linha da decisao de estado local persistente no System Design traz a marca de revogacao nela mesma | RNF-34(f) |


## `tests/integracao/qa_download_curl_real_b16_test.sh`

- **Alvo:** `dbx_http_conteudo_receber` de `lib/http.sh` com destino `fd:<n>` e `-`, usando curl real contra servidor HTTP local real
- **Modulo:** qa_download_curl_real
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `suporte-freebsd`)
- **Regras de origem:** RF-171; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`; [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md)
- **Aceite do solicitante:** [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md) com sha256 `d0c1dd4911a947119d8c4a980cf9a1a5e458e570c1796b9a721ae8bfb65af129`
- **Dados e precondicoes:** curl real (caminho absoluto resolvido antes de qualquer duble); servidor `python3` em porta efemera com Range/206 e 409; arquivo de origem gerado pelo proprio teste e comparado por `cmp`
- **Comando:** `bash tests/run.sh tests/integracao/qa_download_curl_real_b16_test.sh`
- **Observacoes:** o caso de mutacao altera uma copia da lib para provar que o teste reprova o defeito original; exige `python3`.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_fd_download_completo_acima_do_limiar_tem_bytes_identicos | Download completo por descritor de arquivo grande produz bytes identicos aos da origem | RF-171 |
| teste_fd_retomada_com_range_206_anexa_e_confere | Retomada com Range e resposta 206 anexa ao `.part` e o resultado final e identico a origem | RF-171 |
| teste_saida_padrao_em_arquivo_tem_bytes_identicos | Download para a saida padrao redirecionada a arquivo tem bytes identicos aos da origem | |
| teste_saida_padrao_em_cano_tem_bytes_identicos | Download para a saida padrao por cano tem bytes identicos aos da origem | |
| teste_fd_resposta_409_nao_grava_corpo_nem_mensagem_no_part | Resposta 409 no destino por descritor falha classificada e nao grava corpo nem mensagem no `.part` | |
| teste_saida_padrao_resposta_409_nao_emite_corpo_de_erro | Resposta 409 na saida padrao falha classificada e nao emite o corpo de erro | |
| teste_mutacao_stderr_arquivo_reprova_o_download_completo | Numa copia da lib com `--stderr` reposto, o download completo reprova (prova que o teste detecta o defeito) | |


## `tests/integracao/qa_filtros_banda_b4_test.sh`

- **Alvo:** `bin/dbx` com filtros de caminho, data e tamanho (`--incluir`, `--excluir`, `--espelhar`) e limite de banda, no sync nos dois sentidos, upload e download, com a protecao de itens filtrados contra exclusao
- **Modulo:** qa_filtros_banda
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `backlog-fase-4-filtros-e-banda`)
- **Regras de origem:** F-13; F-17; RF-79..RF-82; RF-80(d); DIV-79..DIV-102; DIV-99; DIV-103; log `docs/prompts/2026-10-19_2141_backlog-fase-4-filtros-e-banda.md`
- **Aceite do solicitante:** [entrada de reaprovacao](../../.github/agents/memoria/entradas/2026-10-27-1500-aceite-reaprovacao-inventario.md), sha256 `61080fd0fbdff324ca537c683ab3f41610725b51a50b6b76dc870c93e852ab42` (reaprovado em 2026-10-27; a versao aceita antes havia sido alterada sem novo aceite)
- **Dados e precondicoes:** duble de `curl` e de `rm` proprios, com regras por linha e registro de chamadas e `argv`; arvores locais e listagens remotas sinteticas por caso; credencial sintetica; todo caso de protecao inclui um item no escopo que deve ser apagado
- **Comando:** `bash tests/run.sh tests/integracao/qa_filtros_banda_b4_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_e01_enviar_espelhar_filtro_de_pasta_ancorado_e_caixa | Enviar com `--espelhar` e filtro de pasta ancorado e sensivel a caixa nao apaga o filtrado no remoto e apaga o que esta no escopo | RF-80(d) |
| teste_qa_e02_receber_espelhar_filtrado_local_intacto | Receber com `--espelhar` mantem intacto o item local filtrado e apaga o do escopo | RF-80(d) |
| teste_qa_e03_div99_nome_nao_utf8_com_caractere_nao_ascii_e_protegido | Nome nao UTF-8 com caractere nao ASCII que casa o filtro e protegido contra exclusao | DIV-99 |
| teste_qa_e04_origem_toda_filtrada_e_vazia_para_a_guarda | Origem inteira filtrada conta como vazia para a guarda de espelhamento | RF-80 |
| teste_qa_e05_filtro_novo_com_memoria_que_conhece_o_item | Filtro novo sobre item que a memoria ja conhece nao apaga o item filtrado | RF-80(d) |
| teste_qa_e06_pasta_excluida_na_segunda_pagina_da_listagem | Pasta excluida que so aparece na segunda pagina da listagem continua protegida | RF-80 |
| teste_qa_e07_vinculo_e_especial_filtrados_e_so_pasta | Vinculos e arquivos especiais filtrados, e filtro que so casa pasta, sao protegidos | RF-80 |
| teste_qa_e08_data_e_tamanho_com_espelhar_saem_2_antes_de_tudo | Filtro de data ou tamanho combinado com `--espelhar` sai com codigo 2 antes de qualquer chamada | RF-81 |
| teste_qa_e09_server_modified_nunca_decide_transferencia | A data de modificacao do servidor nunca decide se um arquivo e transferido | RF-81 |
| teste_qa_e10_corpo_do_envio_nao_vaza_para_chamadas_seguintes | O corpo de um envio nao vaza para o registro das chamadas seguintes | |
| teste_qa_e11_padrao_e_dado_nunca_codigo_nem_regex | Padrao de filtro hostil e tratado como dado literal, nunca como codigo nem regex | RF-79 |
| teste_qa_e12_limites_de_padroes_em_quantidade_e_bytes | Padroes acima dos limites de quantidade e de bytes sao recusados com uso invalido | RF-79 |
| teste_qa_e13_div99_variacoes_niveis_curingas_ancora_e_nfd | Variacoes de niveis, curingas, ancora e normalizacao NFD casam como especificado | DIV-99 |
| teste_qa_e14_div99_enviar_nao_envia_nem_apaga_filtrado | Enviar nao envia nem apaga item que o filtro exclui | DIV-99 |
| teste_qa_e15_div103_incluir_impreciso_nunca_apaga_nome_nao_utf8 | Filtro `--incluir` impreciso nunca apaga nome nao UTF-8 | DIV-103 |
| teste_qa_e16_conjunto_com_fecha_literal_e_leitura_da_pasta | Conjunto de caracteres com fecha-colchete literal e a leitura da pasta casam como especificado | RF-79 |
| teste_qa_a02_ressalva_nfc_nfd_na_ajuda_e_no_readme | A ajuda e o README documentam a ressalva sobre NFC e NFD | RF-79 |
| teste_qa_b01_limite_so_no_conteudo_e_em_bytes | O limite de banda e aplicado so as requisicoes de conteudo e convertido em bytes | RF-82 |
| teste_qa_b02_taxa_invalida_ou_hostil_sai_2_sem_rede | Taxa de banda invalida ou hostil sai com codigo 2 sem nenhuma chamada de rede | RF-82 |
| teste_qa_b03_variavel_e_opcao | A variavel de ambiente do limite vale sem a opcao e a opcao vence a variavel | RF-82 |
| teste_qa_a01_suite_sem_captura_de_bytes_externos | Auditoria: a suite nao captura bytes externos nem depende de rede real | |


## `tests/integracao/qa_freebsd_b13_test.sh`

- **Alvo:** `bin/dbx` (config, upload, download, sync, retomada) com os dubles BSD de `chmod`, `stat`, `find` e `sha256` a frente do `PATH`
- **Modulo:** `qa_freebsd`
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `suporte-freebsd`)
- **Regras de origem:** RF-166..172; RNF-39; TC-FBSD-*; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`; protocolo-tdd Regra 6
- **Aceite do solicitante:** [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md) com sha256 `2042083016266ba97e2a568c879a72144b212203724a5ad4ef9af720711d006b`
- **Dados e precondicoes:** dubles BSD de `chmod`, `stat`, `find` e `sha256` e duplo de rede proprios; `_qa_cenario` e `_qa_cenario_retomada` em diretorio temporario; sentinelas sinteticas de credencial
- **Comando:** `bash tests/run.sh qa_freebsd`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_config_com_chmod_bsd_grava_0600_em_0700_sem_vazar_segredo | `config` com `chmod` BSD grava o arquivo em 0600 no diretorio 0700 sem vazar o segredo | |
| teste_upload_e_download_reais_com_dubles_bsd_sem_erro_nem_vazamento | Upload e download pelo executavel com dubles BSD concluem sem erro de uso e sem vazamento | |
| teste_sync_enviar_repetido_tem_o_mesmo_efeito_em_bsd_e_em_gnu | `sync --enviar` repetido tem o mesmo efeito nos dubles BSD e no GNU | |
| teste_credencial_4600_e_diretorio_1700_recusados_igualmente_em_gnu_e_bsd | Credencial com modo 4600 e diretorio com 1700 sao recusados igualmente em GNU e BSD | |
| teste_premissa_dubles_bsd_fazem_de_qualquer_dev_fd_um_no_do_fdescfs | Premissa: com os dubles BSD, qualquer `/dev/fd` aberto e visto como no do fdescfs | |
| teste_download_retomavel_com_dubles_bsd_funciona_como_no_linux | Download retomavel com dubles BSD anexa ao `.part` como no Linux | |
| teste_part_trocado_por_outro_inode_com_dubles_bsd_nao_recebe_anexo | `.part` trocado por outro inode nao recebe anexo sob dubles BSD | |
| teste_part_trocado_por_ligacao_com_dubles_bsd_nao_e_seguido | `.part` trocado por ligacao simbolica nao e seguido sob dubles BSD | |
| teste_download_para_saida_padrao_com_dubles_bsd_entrega_o_corpo_pelo_descritor | Download para a saida padrao com dubles BSD entrega o corpo pelo descritor | RF-171 |
| teste_nenhum_caminho_do_produto_monta_dev_fd_com_variavel | Auditoria: nenhum arquivo de `bin/`, `lib/` ou `commands/` monta `/dev/fd` com variavel | |


## `tests/integracao/qa_integridade_p1_test.sh`

- **Alvo:** `bin/dbx` (download de arquivo e de pasta, sync, upload) com `lib/transfer.sh`, `lib/hash.sh`, `lib/walk.sh`: integridade de dados no recebimento atomico, envio com `rev` e colisao de caixa
- **Modulo:** `bin/dbx`
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `integridade-de-dados-p1`)
- **Regras de origem:** RF-49, RF-54, RF-55, RF-56, RF-57, RNF-29, RNF-04 (emendado); log `docs/prompts/2026-10-18_1745_integridade-de-dados-p1.md`
- **Aceite do solicitante:** [entrada de reaprovacao](../../.github/agents/memoria/entradas/2026-10-27-1500-aceite-reaprovacao-inventario.md), sha256 `f87cadfaa15b3168a0180b3bb89b23dbd94124ba7b3f5b3f5c566a5ac1d50952` (reaprovado em 2026-10-27; a versao aceita antes havia sido alterada sem novo aceite)
- **Dados e precondicoes:** duplo de `curl` proprio; `TMPDIR` proprio por cenario para contar residuos; destinos temporarios (somente leitura, vinculos simbolicos, `umask 027`); fuso de horario ajustado por variavel no caso de horario de verao
- **Comando:** `bash tests/run.sh tests/integracao/qa_integridade_p1_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_client_modified_sai_em_utc_em_fuso_com_horario_de_verao | Em fuso com horario de verao o `client_modified` enviado sai em UTC | |
| teste_qa_colisao_de_caixa_em_subdiretorio_e_recusada | Dois arquivos cujos nomes diferem so pela caixa em um subdiretorio sao recusados no recebimento | |
| teste_qa_download_de_pasta_para_destino_novo_sem_residuo | Download de pasta para destino novo conclui sem deixar temporario nem area HTTP | |
| teste_qa_download_de_pasta_sobre_vinculo_para_arquivo_recusa | Download de pasta cujo destino e vinculo simbolico para arquivo e recusado sem alterar o arquivo | |
| teste_qa_download_de_pasta_sobre_vinculo_quebrado_recusa | Download de pasta cujo destino e vinculo simbolico quebrado e recusado sem criar nada | |
| teste_qa_download_em_diretorio_somente_leitura_falha_sem_efeito | Download em diretorio somente leitura falha com erro e sem deixar efeito | |
| teste_qa_download_hash_divergente_em_alvo_novo_nao_cria_nada | Hash recebido divergente do publicado, com alvo novo, falha e nao cria o arquivo | |
| teste_qa_download_hash_malformado_nao_conta_como_conferido | Hash malformado no cabecalho nao conta como conferido e o recebimento nao e dado como verificado | |
| teste_qa_download_por_cadeia_de_vinculos_relativos_ate_nome_com_quebra_final | Download por cadeia de vinculos relativos ate um nome terminado em quebra de linha grava o arquivo correto | |
| teste_qa_download_por_vinculo_em_ciclo_recusa_sem_transferir | Destino que e vinculo em ciclo e recusado antes de qualquer transferencia | |
| teste_qa_download_por_vinculo_para_alvo_somente_leitura_recusa | Destino por vinculo cujo alvo e somente leitura e recusado preservando o conteudo | |
| teste_qa_download_segue_umask_027 | O arquivo baixado respeita a `umask 027` do processo | |
| teste_qa_download_sobre_alvo_somente_leitura_recusa_e_preserva | Download sobre arquivo existente somente leitura e recusado e o conteudo original e preservado | |
| teste_qa_espelhar_enviar_com_pasta_de_caixa_diferente_apaga_so_o_ausente | Espelhar no envio com pasta remota de caixa diferente apaga somente o que esta ausente no local | |
| teste_qa_espelhar_receber_identico_com_caixa_diferente_nada_faz | Espelhar no recebimento com conteudo identico e caixa diferente nao altera nem apaga nada | |
| teste_qa_falha_de_rede_no_download_nao_deixa_area_http | Falha de rede durante o download termina com erro e sem deixar area HTTP residual | |
| teste_qa_hash_publicado_nao_carrega_valor_da_chamada_anterior | O hash publicado por uma chamada nao herda o valor da chamada anterior | |
| teste_qa_nomes_parecidos_com_temporario_continuam_sincronizados | Arquivos com nomes parecidos com o temporario de recebimento seguem sendo sincronizados como arquivos normais | |
| teste_qa_pastas_irmas_sem_colisao_de_arquivo_nao_sao_recusadas | Pastas irmas cujos arquivos nao colidem pela caixa nao sao recusadas | |
| teste_qa_rev_ausente_na_listagem_nunca_vira_sobrescrita_cega | Arquivo sem `rev` na listagem remota nunca e enviado como sobrescrita cega | |
| teste_qa_rev_e_casado_pela_chave_sem_caixa | O `rev` remoto e casado pela chave sem distincao de caixa | |
| teste_qa_sinal_no_sync_receber_remove_temporario_e_area_http | Sinal durante o sync de recebimento remove o temporario e a area HTTP | |
| teste_qa_sync_arquivo_exatamente_no_teto_vai_por_requisicao_unica | Arquivo exatamente no teto de sessao e enviado por requisicao unica | |
| teste_qa_sync_receber_espelhar_com_alvo_somente_leitura_falha_o_item_sem_apagar | Sync receber com espelhar e alvo somente leitura falha o item sem apagar nada | |
| teste_qa_sync_receber_hash_divergente_em_arquivo_novo_nao_cria_nada | Sync receber com hash divergente em arquivo novo nao cria o arquivo | |
| teste_qa_sync_receber_segue_umask_027_e_preserva_modo_existente | Sync receber respeita `umask 027` em arquivo novo e preserva o modo de arquivo existente | |
| teste_qa_upload_de_diretorio_acima_do_teto_vai_por_sessao | Upload de diretorio com arquivo acima do teto envia esse arquivo por sessao | |


## `tests/integracao/qa_leitura_exata_b14_test.sh`

- **Alvo:** `lib/atributos.sh` (`dbx_ler_exato`), calculo do `content_hash` em `lib/hash.sh` e upload em sessao de `bin/dbx` sob o duble `head` do FreeBSD
- **Modulo:** qa_leitura_exata (sem linha propria no mapa de modulos; ver observacoes)
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `suporte-freebsd`)
- **Regras de origem:** RF-173, TC-FBSD-25..27; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`; [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md)
- **Aceite do solicitante:** [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md) e [log de prompt](../prompts/2026-10-24_1153_suporte-freebsd.md), sha256 `c7de4ca5b460a226aede1abf7cd20b8b015967c38a0f03d96e50257576c920b8`
- **Dados e precondicoes:** duble `head` do FreeBSD a frente do PATH (consome N mais 4096 bytes e imprime N); servidor duble que grava os bytes recebidos; arquivos sinteticos gerados por urandom; oraculo do hash por python3 (hashlib)
- **Comando:** `bash tests/run.sh tests/integracao/qa_leitura_exata_b14_test.sh`
- **Observacoes:** o arquivo nao aparece no mapa de modulos; o Tech Lead trata.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_content_hash_arquivo_de_zero_bytes_e_arquivo_pequeno | `content_hash` de arquivo vazio e de arquivo pequeno igual ao de referencia sob o duble `head` | TC-FBSD-25 |
| teste_content_hash_arquivo_grande_de_muitos_blocos_com_resto | `content_hash` de arquivo grande de muitos blocos com resto parcial igual ao de referencia | TC-FBSD-25 |
| teste_content_hash_de_fluxo_lento_igual_ao_de_referencia_sob_o_duble | `content_hash` de entrada lenta (fluxo) igual ao de referencia, sem perder bytes | TC-FBSD-25 |
| teste_content_hash_tamanho_exato_multiplo_de_4_mib | `content_hash` de arquivo com tamanho exato multiplo de 4 MiB igual ao de referencia | TC-FBSD-25 |
| teste_content_hash_varios_blocos_e_resto_igual_ao_de_referencia | `content_hash` de varios blocos mais resto igual ao de referencia | TC-FBSD-25 |
| teste_leitura_curta_de_cano_nao_e_tomada_como_fim_e_nao_perde_bytes | Leitura curta de um cano nao e tomada como fim do fluxo e nenhum byte se perde | TC-FBSD-26 |
| teste_mutacao_head_c_no_lugar_de_dbx_ler_exato_e_reprovada_sob_o_duble | Mutante que troca `dbx_ler_exato` por `head -c` e reprovado sob o duble, provando que o teste detecta o defeito | TC-FBSD-26 |
| teste_retomada_de_upload_interrompido_deixa_o_arquivo_final_identico | Upload interrompido e retomado deixa o arquivo remoto final identico ao de origem | TC-FBSD-27 |
| teste_upload_por_sessao_acima_do_limiar_envia_o_tamanho_e_bytes_identicos | Upload por sessao acima do limiar envia o tamanho exato e bytes identicos (`cmp`) ao arquivo de origem | TC-FBSD-27 |
| teste_upload_por_sessao_de_tamanho_exato_multiplo_de_4_mib | Upload por sessao de tamanho multiplo exato de 4 MiB envia bytes identicos e o resumo final correto | TC-FBSD-27 |


## `tests/integracao/qa_paralelo_download_b20_test.sh`

- **Alvo:** `bin/dbx download` de arquivo grande em faixas simultaneas (`commands/download.sh`, `lib/transfer.sh`, `lib/http.sh`)
- **Modulo:** `qa_paralelo_download` (linha ausente do mapa de modulos; id derivado do nome do arquivo)
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `paralelo-upload-download`)
- **Regras de origem:** F-100 etapa 2b; RF-180 a RF-184; RF-104(c)(d); RF-106(a); DIV-369 a DIV-371; DIV-373 a DIV-376; log `docs/prompts/2026-10-26_1900_paralelo-upload-download.md`; protocolo-tdd Regra 9 (auditoria de repeticao)
- **Aceite do solicitante:** [log de prompt](../prompts/2026-10-26_1900_paralelo-upload-download.md), com sha256 `86fc839a8d914d1c44b834f726e995fd63560ac79490dd116876c1d85d668d3e`
- **Dados e precondicoes:** duble de `curl` que e um servidor de `Range` proprio (serve 206 com `Content-Range` exato a partir de `remoto.bin` e registra ordem de chegada em `ev`); massa de tamanhos derivados do limiar de faixas (`T_LIMIAR_MAIS_1`, `T_MULTIPLO`, `T_FINAL_CURTA`) em area temporaria por caso
- **Comando:** `bash tests/run.sh tests/integracao/qa_paralelo_download_b20_test.sh`
- **Observacoes:** o `--listar` extrai o nome do primeiro texto entre aspas das funcoes de uma linha; por isso seis casos aparecem com o texto citado em vez do nome da funcao. Linha da tabela, com a funcao real entre parenteses na descricao.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_faixa_final_curta_bytes_e_hash | (teste_faixa_final_curta_bytes_e_hash) Download com faixa final curta chega com bytes e resumo iguais aos da origem | |
| teste_limiar_mais_um_byte_bytes_e_hash | (teste_limiar_mais_um_byte_bytes_e_hash) Arquivo de limiar mais um byte e baixado em faixas com bytes e resumo iguais aos da origem | |
| teste_multiplo_exato_de_16_mib_bytes_e_hash | (teste_multiplo_exato_de_16_mib_bytes_e_hash) Arquivo multiplo exato do tamanho de faixa chega com bytes e resumo iguais aos da origem | |
| teste_content_range_errado_numa_faixa_nao_e_gravado | (teste_content_range_errado_numa_faixa_nao_e_gravado) Faixa com `Content-Range` errado nao e gravada | |
| teste_revisao_divergente_numa_faixa_nao_e_gravada | (teste_revisao_divergente_numa_faixa_nao_e_gravada) Faixa com revisao divergente nao e gravada e a faixa e repetida | |
| teste_revisao_divergente_persistente_falha_sem_gravar_a_faixa | (teste_revisao_divergente_persistente_falha_sem_gravar_a_faixa) Revisao divergente que persiste faz o download falhar sem gravar a faixa | |
| teste_200_ignorando_range_avisa_e_recomeca_sequencial_unico_sem_laco | Servidor que responde 200 ignorando `Range` gera aviso e recomeco sequencial unico, sem laco | |
| teste_200_ignorando_range_so_a_partir_da_faixa_3_recomeca_sequencial_unico | Servidor que ignora `Range` so a partir da faixa 3 leva a um unico recomeco sequencial | |
| teste_403_numa_faixa_descarta_part_e_registro_sem_mv | 403 numa faixa descarta o `.part` e o registro, sem mover para o destino | |
| teste_429_numa_faixa_conclui_certo_e_a_faixa_repete_so_a_sua | 429 numa faixa conclui corretamente e repete apenas essa faixa | |
| teste_area_temporaria_limitada_a_n_mesmo_com_a_faixa_zero_presa | A area temporaria fica limitada a N faixas mesmo com a faixa zero retida | |
| teste_auditoria_dos_arquivos_novos | Os arquivos novos da etapa passam na auditoria estatica do projeto | |
| teste_content_range_errado_so_na_faixa_2_nenhum_byte_adulterado_chega_ao_alvo | `Content-Range` errado so na faixa 2 nao deixa nenhum byte adulterado chegar ao alvo | |
| teste_debug_registra_paralelo_partes_e_cada_parte | Com `--debug`, o registro mostra o paralelismo, as partes e cada parte | |
| teste_faixa_do_meio_atrasada_part_so_tem_o_prefixo_contiguo | Com faixa do meio atrasada, o `.part` contem so o prefixo contiguo | |
| teste_faixa_zero_atrasada_chega_por_ultimo_e_nada_e_gravado_antes | Com a faixa zero atrasada, nada e gravado antes de ela chegar | |
| teste_limite_de_banda_dividido_entre_as_faixas | O limite de banda e dividido entre as faixas simultaneas | |
| teste_mutacao_a_gravar_a_faixa_assim_que_chega_e_pega_pela_ordem | Mutante que grava a faixa assim que chega e detectado pela ordem de gravacao | |
| teste_mutacao_b_contar_como_prefixo_faixa_nao_gravada_e_pega_pelos_bytes | Mutante que conta faixa nao gravada como prefixo e detectado pelos bytes | |
| teste_n1_abaixo_do_limiar_e_saida_padrao_nao_usam_faixa_fechada | Com N igual a 1, abaixo do limiar ou em saida padrao, nao se usa faixa fechada | |
| teste_o_auditor_de_repeticao_reconhece_as_formas_de_fronteira | O auditor de repeticao de regex reconhece as formas de fronteira | |
| teste_pico_e_area_temporaria_com_n_2 | Com N igual a 2, o pico de simultaneidade e a area temporaria respeitam o limite | |
| teste_pico_e_area_temporaria_com_n_4 | Com N igual a 4, o pico de simultaneidade e a area temporaria respeitam o limite | |
| teste_queda_de_rede_preserva_prefixo_e_registro_e_reexecucao_continua | Queda de rede preserva prefixo e registro e a reexecucao continua de onde parou | |
| teste_sigterm_sem_orfaos_part_prefixo_contiguo_e_retomada_completa | SIGTERM nao deixa processos orfaos, o `.part` fica com prefixo contiguo e a retomada completa | |
| teste_troca_do_part_durante_o_download_e_recusada_sem_tocar_no_outro_arquivo | `.part` trocado durante o download e recusado sem tocar no outro arquivo | |
| teste_z_429_sem_faixa_nova_durante_a_pausa_compartilhada | Durante a pausa compartilhada de 429 nenhuma faixa nova e iniciada | |


## `tests/integracao/qa_paralelo_pastas_b18_test.sh`

- **Alvo:** `--paralelo`/`--parallel` e `DBX_PARALELO` em `bin/dbx upload` e `download` (pasta repassa N ao sync), com `commands/upload.sh`, `commands/download.sh`, `commands/diagnostico.sh`
- **Modulo:** `qa_paralelo_pastas` (linha ausente do mapa de modulos; id derivado do nome do arquivo)
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `paralelo-upload-download`)
- **Regras de origem:** RF-175; RF-176; DIV-372; DIV-373; DIV-374 (opcao A); log `docs/prompts/2026-10-26_1900_paralelo-upload-download.md`
- **Aceite do solicitante:** [log de prompt](../prompts/2026-10-26_1900_paralelo-upload-download.md), com sha256 `94f2b18c884f014b162632451ac28c2c1f0a2b372be37bcadf3d7e4e02071c44`
- **Dados e precondicoes:** duble de `curl` proprio; simultaneidade provada por marcas em `B/vivos` e pico em `B/picos`, sem depender de tempo de parede; bytes conferidos por `cmp` contra massa gerada com valores proprios; area temporaria por caso
- **Comando:** `bash tests/run.sh tests/integracao/qa_paralelo_pastas_b18_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qpb01_validacao_nas_duas_formas_e_nos_dois_comandos_antes_da_rede | Valor invalido de N, por opcao ou por variavel, e recusado em `upload` e `download` antes da rede | |
| teste_qpb02_precedencia_opcao_sobre_variavel_e_ultima_opcao_vence | A opcao prevalece sobre a variavel e a ultima opcao repetida vence | |
| teste_qpb03_download_de_pasta_n4_simultaneo_bytes_e_resumo_iguais_ao_n1 | Download de pasta com N igual a 4 e simultaneo e produz bytes e resumo iguais aos de N igual a 1 | |
| teste_qpb04_upload_de_pasta_n4_simultaneo_bytes_e_resumo_iguais_ao_n1 | Upload de pasta com N igual a 4 e simultaneo e produz bytes e resumo iguais aos de N igual a 1 | |
| teste_qpb05_falha_de_um_item_com_n4_nao_derruba_os_outros_e_mantem_o_codigo | Falha de um item com N igual a 4 nao derruba os demais e mantem o codigo de saida | |
| teste_qpb06_dry_run_com_n_aceita_valida_e_nao_transfere | `--dry-run` com N aceita e valida a opcao e nao transfere | |
| teste_qpb07_stdin_e_stdout_recusam_a_opcao_e_ignoram_a_variavel | Entrada ou saida padrao recusam a opcao e ignoram a variavel | |
| teste_qpb08_arquivo_unico_aceita_e_segue_sequencial | Arquivo unico aceita a opcao e segue sequencial | |
| teste_qpb09_comandos_sem_suporte_recusam_a_opcao_e_ignoram_a_variavel | Comandos sem suporte recusam a opcao e ignoram a variavel | |
| teste_qpb10_diagnostico_mostra_o_n_efetivo_da_variavel | O diagnostico mostra o N efetivo vindo da variavel | |


## `tests/integracao/qa_paralelo_upload_b19_test.sh`

- **Alvo:** `bin/dbx upload` de arquivo grande em partes simultaneas, `lib/transfer_paralelo.sh`, `lib/state.sh` (registro de retomada v2)
- **Modulo:** qa_paralelo_upload (sem linha propria no mapa de modulos; ver observacoes)
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `paralelo-upload-download`)
- **Regras de origem:** F-100; RF-177 a RF-183; RF-181; DIV-358 a DIV-368; protocolo-tdd Regra 6 (registro hostil); log `docs/prompts/2026-10-26_1900_paralelo-upload-download.md`
- **Aceite do solicitante:** [log de prompt](../prompts/2026-10-26_1900_paralelo-upload-download.md), sha256 `e1dc693fe4e65bb82d5d278bbe64e51c12459b0726dfce32bdeb9e6ab7bd5526`
- **Dados e precondicoes:** duplo de `curl` que implementa servidor de sessao concorrente (registra `ini`/`fim`, guarda cada parte e monta o arquivo no `finish`); controles em `ctl`; arquivos sinteticos por urandom; hash esperado calculado na propria suite; sem rede
- **Comando:** `bash tests/run.sh tests/integracao/qa_paralelo_upload_b19_test.sh`
- **Observacoes:** `sh scripts/inventario-de-testes.sh --listar` extrai deste arquivo, no lugar do nome de 15 casos de uma linha (`teste_b19_bytes_e_hash_*` e `teste_b19_registro_hostil_*`), o argumento literal da chamada (`$T_LIMIAR_MAIS_1`, `x-y` e semelhantes). A coluna Caso segue a listagem; a descricao indica o caso real. O arquivo nao aparece no mapa de modulos. O Tech Lead trata ambos.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_b19_bytes_e_hash_parte_final_de_5_bytes | Caso `teste_b19_bytes_e_hash_parte_final_de_5_bytes`: arquivo cuja ultima parte tem 5 bytes chega com bytes e hash identicos | RF-178 |
| teste_b19_bytes_e_hash_limiar_mais_1 | Caso `teste_b19_bytes_e_hash_limiar_mais_1`: arquivo com um byte acima do limiar chega com bytes e hash identicos | RF-178 |
| teste_b19_bytes_e_hash_multiplo_exato_de_16_mib | Caso `teste_b19_bytes_e_hash_multiplo_exato_de_16_mib`: arquivo multiplo exato de 16 MiB chega com bytes e hash identicos | RF-178 |
| teste_b19_registro_hostil_intervalo_alem_das_partes | Caso `teste_b19_registro_hostil_intervalo_alem_das_partes`: registro com intervalo alem do numero de partes e descartado e o upload recomeca sem apagar dado | RF-181 |
| teste_b19_registro_hostil_intervalos_adjacentes_nao_fundidos | Caso `teste_b19_registro_hostil_intervalos_adjacentes_nao_fundidos`: registro com intervalos adjacentes nao canonicos e descartado | RF-181 |
| teste_b19_registro_hostil_intervalos_sobrepostos | Caso `teste_b19_registro_hostil_intervalos_sobrepostos`: registro com intervalos sobrepostos e descartado | RF-181 |
| teste_b19_registro_hostil_tamanho_de_parte_invalido | Caso `teste_b19_registro_hostil_tamanho_de_parte_invalido`: registro com tamanho de parte invalido (16777217) e descartado | RF-181 |
| teste_b19_registro_hostil_intervalo_repetido | Caso `teste_b19_registro_hostil_intervalo_repetido`: registro com intervalo repetido e descartado | RF-181 |
| teste_b19_registro_hostil_intervalo_invertido | Caso `teste_b19_registro_hostil_intervalo_invertido`: registro com intervalo invertido e descartado | RF-181 |
| teste_b19_registro_hostil_intervalos_fora_de_ordem | Caso `teste_b19_registro_hostil_intervalos_fora_de_ordem`: registro com intervalos fora de ordem e descartado | RF-181 |
| teste_b19_registro_hostil_total_diferente_do_arquivo | Caso `teste_b19_registro_hostil_total_diferente_do_arquivo`: registro cujo total difere do tamanho do arquivo e descartado | RF-181 |
| teste_b19_registro_hostil_sessao_com_espaco | Caso `teste_b19_registro_hostil_sessao_com_espaco`: registro com identificador de sessao contendo espaco e descartado | RF-181 |
| teste_b19_registro_hostil_total_nao_numerico | Caso `teste_b19_registro_hostil_total_nao_numerico`: registro com total nao numerico e descartado | RF-181 |
| teste_b19_registro_hostil_identidade_invalida | Caso `teste_b19_registro_hostil_identidade_invalida`: registro com identidade do arquivo invalida e descartado | RF-181 |
| teste_b19_registro_hostil_tipo_diferente_de_concurrent | Caso `teste_b19_registro_hostil_tipo_diferente_de_concurrent`: registro com tipo de sessao diferente de `concurrent` e descartado | RF-181 |
| teste_b19_registro_hostil_intervalo_nao_numerico | Caso `teste_b19_registro_hostil_intervalo_nao_numerico`: registro com intervalo nao numerico e descartado | RF-181 |
| teste_b19_429_nao_despacha_parte_nova_durante_a_pausa | Ao receber 429 o upload nao despacha parte nova durante a pausa pedida pelo servidor | RF-180 |
| teste_b19_erro_5xx_no_start_nao_cai_para_sequencial | Erro 5xx na abertura da sessao concorrente nao faz cair para o modo sequencial e e tratado como erro | RF-179 |
| teste_b19_falha_definitiva_sem_finish_registro_v2_e_reexecucao_so_do_que_falta | Parte com falha definitiva impede o `finish`, grava registro v2 e a reexecucao envia somente as partes que faltam | RF-181 |
| teste_b19_finish_recusado_em_modo_concorrente_falha_sem_vazar_e_reexecucao_so_finaliza | `finish` recusado em modo concorrente falha sem vazar dados e a reexecucao apenas finaliza | RF-181 |
| teste_b19_limite_de_banda_dividido_entre_as_partes | O limite de banda e dividido entre as partes em voo (`limit-rate` por parte) | RF-182 |
| teste_b19_n1_e_abaixo_do_limiar_nao_tem_chamada_concorrente | Com N=1 ou arquivo abaixo do limiar nao ha nenhuma chamada de sessao concorrente | RF-177 |
| teste_b19_nenhuma_repeticao_de_regex_acima_de_255_nos_arquivos_novos | Nenhum arquivo novo usa repeticao de expressao regular acima de 255 (RE_DUP_MAX do FreeBSD) | RF-173 |
| teste_b19_no_maximo_n_em_voo_e_mais_de_um | Nunca ha mais de N partes em voo e ha mais de uma simultaneamente | RF-177, RF-178 |
| teste_b19_recusa_400_do_concurrent_cai_para_sequencial | Recusa 400 do modo concorrente faz o upload cair para o modo sequencial e concluir | RF-179 |
| teste_b19_recusa_403_do_concurrent_cai_para_sequencial | Recusa 403 do modo concorrente faz o upload cair para o modo sequencial e concluir | RF-179 |
| teste_b19_recusa_409_do_concurrent_cai_para_sequencial | Recusa 409 do modo concorrente faz o upload cair para o modo sequencial e concluir | RF-179 |
| teste_b19_registro_hostil_mais_de_256_intervalos | Registro com mais de 256 intervalos e descartado como hostil | RF-181 |
| teste_b19_registro_hostil_truncado | Registro truncado e descartado como hostil | RF-181 |
| teste_b19_registro_v1_com_n_maior_que_1_retoma_em_sequencia | Registro v1 retomado com N maior que 1 continua em modo sequencial | RF-181 |
| teste_b19_registro_v2_com_n1_e_descartado_com_aviso_e_recomeca | Registro v2 retomado com N igual a 1 e descartado com aviso e o upload recomeca | RF-181 |
| teste_b19_sessao_expirada_de_novo_nao_entra_em_laco | Sessao que expira de novo apos recomecar nao entra em laco infinito e falha | RF-183 |
| teste_b19_sessao_expirada_not_found_recomeca_do_zero_uma_vez | Sessao expirada (`not_found`) recomeca do zero uma unica vez | RF-183 |
| teste_b19_sessao_fechada_closed_recomeca_do_zero | Sessao fechada (`closed`) recomeca do zero | RF-183 |
| teste_b19_sigterm_sem_orfaos_sem_publicacao_registro_coerente_e_retomada | SIGTERM no meio do envio nao deixa processos orfaos nem publica arquivo parcial, deixa registro coerente e a reexecucao retoma | RF-181 |


## `tests/integracao/qa_pendencias_p0_test.sh`

- **Alvo:** `dbx_cmd_ler_corpo_silencioso` de `lib/cmd.sh` e seu uso em `_dbx_cmd_upload_hash_remoto` de `commands/upload.sh`; prova de que `identidade_gnustat_test` passa pelo duble `gnustat`
- **Modulo:** qa_pendencias
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `backlog-fase-0-pendencias`)
- **Regras de origem:** O-5; RSK-43; RNF-03; log `docs/prompts/2026-10-19_1023_backlog-fase-0-pendencias.md`; [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-19-1023-aceite-testes-qa-p0.md)
- **Aceite do solicitante:** [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-19-1023-aceite-testes-qa-p0.md) com sha256 `fdbb69c4e4465640d06e38b2fb57c8604c491d6ee03eefbcdbbac5a83fa39af1`
- **Dados e precondicoes:** duble de `curl` proprio que devolve o metadado remoto do caso; arquivo de origem sintetico; token sintetico reconhecivel que nao pode aparecer em saida alguma
- **Comando:** `bash tests/run.sh tests/integracao/qa_pendencias_p0_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_corpo_vazio_propaga_classe_e_motivo_e_envia | Metadado remoto com corpo vazio: o upload propaga classe `erro_remoto` e o motivo, e segue enviando | O-5 |
| teste_json_truncado_propaga_classe_e_motivo_e_envia | Metadado em JSON truncado: propaga classe e motivo de resposta nao interpretavel e envia | O-5 |
| teste_campo_ausente_propaga_classe_e_motivo_e_envia | Metadado sem o campo de hash: propaga classe e motivo de campo ausente ou malformado e envia | O-5 |
| teste_hash_malformado_propaga_classe_e_motivo_e_envia | Hash remoto malformado: propaga classe e motivo e envia | O-5 |
| teste_destino_pasta_propaga_classe_e_motivo_e_envia | Destino remoto que e pasta: propaga motivo de nao ser arquivo comparavel e envia | O-5 |
| teste_erro_5xx_propaga_classe_e_motivo_e_envia | Erro 5xx na consulta do metadado nao aborta o upload e o diagnostico traz classe e motivo | O-5 |
| teste_token_em_corpo_de_erro_nunca_aparece | Corpo de erro contendo token sintetico: o token nao aparece em nenhuma saida | RNF-03 |
| teste_hash_bom_remoto_igual_dispensa_sem_classe_nem_motivo | Controle: hash remoto igual dispensa o envio sem emitir diagnostico de falha | O-5 |
| teste_leitura_nao_vaza_contexto_nem_canais | Em processo isolado, o auxiliar descarta documento, corpo e resultado e nao emite nada, em sucesso e em falha | RSK-43 |
| teste_gnustat_do_senior_passa_pelo_duplo_registrado | Um mutante do duble de `gnustat` reprova o caso do Senior Developer, provando que ele depende do duble e nao do `stat` da maquina | RSK-43 |


## `tests/integracao/qa_perfis_b8_test.sh`

- **Alvo:** `bin/dbx` (perfis, `config`, `unlink`, `sync` com perfil), `lib/config.sh`, `lib/state.sh`, `lib/tmp.sh`
- **Modulo:** `qa_perfis`
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `backlog-fase-8-perfis`)
- **Regras de origem:** F-18; RF-120 a RF-132; DIV-236 a DIV-255; TC-CNF-03; log `docs/prompts/2026-10-21_1735_backlog-fase-8-perfis.md`; protocolo-tdd Regra 6 (nome hostil, symlink, permissoes, vazamento de segredo)
- **Aceite do solicitante:** [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-21-1735-perfis.md) e [log de prompt](../prompts/2026-10-21_1735_backlog-fase-8-perfis.md), com sha256 `9e6617c358b02608124dfd721e711226f5c5ca3e2b47b1da7ef44515b05932d7`
- **Dados e precondicoes:** duble de `curl` proprio, sem rede; perfis, estado e travas montados por caso em area temporaria; symlinks e permissoes plantados pelo caso
- **Comando:** `bash tests/run.sh tests/integracao/qa_perfis_b8_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qpf01_nomes_hostis_sao_recusados_com_2_sem_rede_e_sem_tocar_o_disco | Nomes de perfil hostis sao recusados com 2, sem rede e sem tocar o disco | |
| teste_qpf02_nome_de_32_caracteres_vale_e_de_33_nao | Nome de perfil com 32 caracteres e valido e com 33 e recusado | |
| teste_qpf03_digito_inicial_e_hifen_interno_validos | Nome iniciado por digito ou com hifen interno e valido | |
| teste_qpf04_padrao_explicito_usa_credencial_json_e_ignora_perfis_padrao_json | Perfil `padrao` explicito usa `credencial.json` e ignora `perfis/padrao.json` | |
| teste_qpf05_unlink_padrao_com_padrao_json_plantado_nao_apaga_o_plantado | `unlink` do padrao com `perfis/padrao.json` plantado nao apaga o arquivo plantado | |
| teste_qpf06_symlink_no_lugar_do_arquivo_do_perfil_e_recusado_e_nao_lido | Symlink no lugar do arquivo do perfil e recusado e nao e lido | |
| teste_qpf07_symlink_no_lugar_do_diretorio_perfis_e_recusado | Symlink no lugar do diretorio `perfis` e recusado | |
| teste_qpf08_permissoes_frouxas_no_arquivo_no_perfis_e_no_dbx_sao_recusadas | Permissoes frouxas no arquivo, em `perfis` e em `dbx` sao recusadas | |
| teste_qpf09_dbx_perfil_com_segredo_e_recusado_sem_ecoar_o_valor | `DBX_PERFIL` contendo segredo e recusado sem ecoar o valor | |
| teste_qpf10_dbx_perfil_vazio_vale_como_nao_definido_e_a_opcao_vence_ambiente_invalido | `DBX_PERFIL` vazio vale como nao definido e a opcao vence ambiente invalido | DIV-241 |
| teste_qpf11_opcao_repetida_e_recusada_em_qualquer_posicao_inclusive_alias | Opcao `--perfil` repetida e recusada em qualquer posicao, inclusive pelo alias | DIV-241 |
| teste_qpf12_perfil_sem_valor_e_recusado | `--perfil` sem valor e recusado | |
| teste_qpf13_perfil_inexistente_sai_3_sem_rede_e_sem_recuar_ao_padrao | Perfil inexistente sai com 3 sem rede e sem recuar ao padrao | |
| teste_qpf14_identidade_compartilhada_com_o_padrao_nao_revoga_nem_toca_o_estado | Identidade compartilhada com o padrao nao revoga o token nem toca o estado | |
| teste_qpf15_unlink_do_padrao_com_identidade_igual_a_de_perfil_nao_revoga | `unlink` do padrao com identidade igual a de um perfil nao revoga | |
| teste_qpf16_credencial_ilegivel_nao_remove_estado_algum | Credencial ilegivel nao remove estado algum | |
| teste_qpf17_credencial_com_modo_000_nao_remove_estado_nem_apaga_outro | Credencial com modo 000 nao remove estado nem apaga outro arquivo | |
| teste_qpf18_ultimo_perfil_remove_todo_o_estado_da_credencial_mas_nao_a_trava_do_par | Ultimo perfil remove todo o estado da credencial, mas preserva a trava do par | |
| teste_qpf19_estado_de_identidade_alheia_com_nome_parecido_nao_e_removido | Estado de identidade alheia com nome parecido nao e removido | |
| teste_qpf20_estado_simbolico_nao_e_seguido_nem_removido_alem_do_proprio_link | Estado simbolico nao e seguido e so o proprio link e removido | |
| teste_qpf21_trava_viva_de_outro_par_recusa_com_7_sem_remover_nada | Trava viva de outro par recusa com 7 sem remover nada | |
| teste_qpf22_simulacao_do_unlink_nao_altera_disco_nem_chama_a_rede | Simulacao do `unlink` nao altera o disco nem chama a rede | |
| teste_qpf23_unlink_sem_confirmar_nao_remove | `unlink` sem confirmar nao remove nada | |
| teste_qpf24_perfis_nao_exibe_segredo_em_nenhuma_saida | `dbx perfis` nao exibe segredo em nenhuma saida | |
| teste_qpf25_perfis_ignora_arquivos_anomalos_sem_travar | `dbx perfis` ignora arquivos anomalos sem travar | |
| teste_qpf26_dois_perfis_na_mesma_raiz_local_o_segundo_sai_7_sem_escrever | Segundo perfil na mesma raiz local sai com 7 sem escrever | |
| teste_qpf27_esperar_conclui_depois_que_a_trava_de_raiz_e_solta | Com `--esperar`, a execucao conclui depois que a trava de raiz e liberada | |
| teste_qpf28_esperar_curto_esgota_e_sai_7 | `--esperar` curto esgota o tempo e sai com 7 | |
| teste_qpf29_raizes_diferentes_nao_se_bloqueiam | Raizes locais diferentes nao se bloqueiam | |
| teste_qpf30_cnf03_carregar_com_nome_padrao_e_arquivo_de_perfis_pula_a_cadeia | `carregar` com nome padrao e arquivo de perfis pula a cadeia de resolucao | TC-CNF-03 |
| teste_qpf31_cnf03_carregar_com_nome_invalido_e_aceito_sem_validar | `carregar` com nome invalido e aceito sem validar o nome | TC-CNF-03 |
| teste_qpf32_cnf03_carregar_com_nome_padrao_segue_symlink_de_perfis | `carregar` com nome padrao segue symlink de `perfis` | TC-CNF-03 |
| teste_qpf33_cnf03_rotulo_padrao_nao_confere_o_diretorio_dbx | O rotulo padrao nao confere o diretorio `dbx` | TC-CNF-03 |
| teste_qpf34_ultimo_perfil_ilegivel_remove_o_estado_total_mas_preserva_trava_do_par | Ultimo perfil ilegivel remove o estado total e preserva a trava do par | |


## `tests/integracao/qa_progresso_arquivo_b10_test.sh`

- **Alvo:** `bin/dbx` (upload de fluxo, download, `sync` nos dois sentidos com N=1 e N=3), `lib/progress.sh`
- **Modulo:** qa_progresso
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `progresso-por-arquivo`)
- **Regras de origem:** F-49; RF-140 a RF-147; secao 5.19 da especificacao; DIV-302, DIV-303; log `docs/prompts/2026-10-22_1600_progresso-por-arquivo.md`
- **Aceite do solicitante:** [log de prompt](../prompts/2026-10-22_1600_progresso-por-arquivo.md), sha256 `fab96fad4e4aa1c67b3905c728b7004870031975618c030cba7987fc10ff5956`
- **Dados e precondicoes:** duplo de `curl` proprio; arquivos sinteticos temporarios; sem rede nem conta real
- **Comando:** `bash tests/run.sh tests/integracao/qa_progresso_arquivo_b10_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qpa01_cache_normalizado_igual_entre_n1_e_n3_no_receber | O cache de estado gravado no `sync` de recebimento e igual, normalizado, com N=1 e N=3 | |
| teste_qpa02_cache_normalizado_igual_entre_n1_e_n3_no_enviar | O cache de estado gravado no `sync` de envio e igual, normalizado, com N=1 e N=3 | |
| teste_qpa03_amostragem_sem_terminal_n3_uma_linha_por_decil_com_posicao_certa | Sem terminal e com N=3, o progresso emite uma linha por decil, com a posicao correta do arquivo | |
| teste_qpa04_upload_de_stdin_tem_stdout_identico_com_e_sem_progresso | Upload vindo da entrada padrao tem stdout identico com e sem progresso | |
| teste_qpa05_download_para_arquivo_tem_stdout_identico_e_conteudo_igual | Download para arquivo tem stdout identico e conteudo igual com e sem progresso | |
| teste_qpa06_nome_com_esc_bel_e_quebra_de_linha_nao_injeta_nada_na_linha | Nome de arquivo com ESC, BEL e quebra de linha nao injeta caracteres de controle na linha de progresso | protocolo-tdd Regra 6 |
| teste_qpa07_falha_do_metadado_baixa_sem_linha_e_sem_erro_novo | Falha ao obter o metadado no download baixa o arquivo sem linha de progresso e sem erro novo | |
| teste_qpa08_download_n1_grande_com_terminal_nunca_diminui_e_termina_em_cem | Download grande com N=1 e terminal: o percentual nunca diminui e termina em 100 | |


## `tests/integracao/qa_recuperacao_b3_test.sh`

- **Alvo:** `bin/dbx` nos comandos `revisoes`, `restaurar` e `lixeira` (com exclusao permanente), `commands/revisoes.sh`, `commands/restaurar.sh`, `commands/lixeira.sh`
- **Modulo:** qa_recuperacao
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `backlog-fase-3-recuperacao`)
- **Regras de origem:** F-07; F-20; RF-72..RF-78; DIV-54..DIV-77; log `docs/prompts/2026-10-19_1828_backlog-fase-3-recuperacao.md`
- **Aceite do solicitante:** [log de prompt, unico registro onde o sha aparece](../prompts/2026-10-19_1828_backlog-fase-3-recuperacao.md) com sha256 `2044fa23362ee52d2b370344f255d3038e7689e25335c9d2e2beba0160c1a48a`
- **Dados e precondicoes:** duble de `curl` proprio com regras por linha e registro de chamadas (que nunca pode conter `files/permanently_delete` nas recusas); `XDG_STATE_HOME` vazio (a guarda nao depende de estado local); terminal simulado por `script(1)` nos casos de confirmacao; credencial sintetica
- **Comando:** `bash tests/run.sh tests/integracao/qa_recuperacao_b3_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_e01_item_vivo_ou_tag_estranha_nunca_e_expurgado | Item vivo ou com marca desconhecida nunca e expurgado de forma permanente | RF-76 |
| teste_qa_e02_raiz_em_qualquer_grafia_e_recusada_sem_rede | A raiz, em qualquer grafia, e recusada na exclusao permanente sem nenhuma chamada de rede | RF-76 |
| teste_qa_e03_fora_da_raiz_e_bytes_hostis_sem_rede | Caminho fora da raiz ou com bytes hostis e recusado sem chamada de rede | RF-76 |
| teste_qa_e04_confirmacao_divergente_e_2_sem_rede | Confirmacao digitada que diverge do esperado sai com codigo 2 sem rede | RF-76 |
| teste_qa_e05_atalhos_de_confirmacao_nao_existem | Nenhum atalho de confirmacao (ex.: sim, y, forcar) dispensa a confirmacao completa | RF-76 |
| teste_qa_e06_stdin_nao_terminal_com_dados_nao_confirma | Entrada que nao e terminal, mesmo com dados, nao confirma a exclusao permanente | RF-76 |
| teste_qa_e07_terminal_resposta_errada_vazia_ou_eof_e_14 | Em terminal, resposta errada, vazia ou fim de entrada cancela com codigo 14 | RF-76 |
| teste_qa_e08_deleted_de_outro_caminho_nao_autoriza | Item apagado em outro caminho nao autoriza o expurgo do caminho pedido | RF-76 |
| teste_qa_e13_guarda_formas_equivalentes_e_campo_duplicado | Formas equivalentes do caminho e campo duplicado na resposta da guarda nao a contornam | RF-76 |
| teste_qa_e09_guarda_com_erro_da_api_nunca_expurga | Erro da API ao consultar a guarda nunca leva ao expurgo | RF-76 |
| teste_qa_e10_dry_run_nunca_expurga | Com `--dry-run` nenhuma chamada de exclusao permanente e feita | RF-76 |
| teste_qa_e11_in_progress_no_expurgo_e_14_apos_retentar | Resposta in_progress no expurgo e retentada e, persistindo, sai com codigo 14 | RF-76 |
| teste_qa_e12_mesmo_alvo_na_guarda_e_no_expurgo_sem_segredo | A guarda e o expurgo atuam sobre o mesmo alvo e nenhuma saida traz segredo | RF-76; RNF-03 |
| teste_qa_r01_rev_de_outro_arquivo_e_2_sem_restore | Revisao pertencente a outro arquivo sai com codigo 2 sem chamar restore | RF-73 |
| teste_qa_r02_rev_malformado_ou_injecao_sem_rede | Identificador de revisao malformado ou com injecao e recusado sem rede | RF-73 |
| teste_qa_r03_antes_de_limites_e_formas_invalidas | A opcao `--antes` rejeita formas invalidas e respeita os limites de data | RF-73 |
| teste_qa_r04_vigente_e_ja_atual_sem_restore | Restaurar a revisao vigente nao faz restore e informa que ja e a atual | RF-73 |
| teste_qa_r05_item_hostil_fora_da_raiz_e_falha_14 | Restaurar pasta com item hostil fora da raiz falha com codigo 14 | RF-74 |
| teste_qa_r06_falha_parcial_e_14_com_a_lista | Falha parcial na restauracao de pasta sai com codigo 14 e lista os itens | RF-74 |
| teste_qa_r07_dry_run_de_pasta_sem_escrita | Restauracao de pasta com `--dry-run` nao faz nenhuma escrita remota | RF-74 |
| teste_qa_r08_term_no_meio_sem_residuo | Sinal de termino no meio da restauracao nao deixa residuo local | RF-74 |
| teste_qa_r09_item_fora_da_pasta_pedida_e_falha_14 | Item listado fora da pasta pedida falha com codigo 14 | RF-74 |
| teste_qa_r10_pasta_que_contem_a_si_mesma_termina | Pasta que contem a si mesma na listagem termina sem repeticao infinita | RF-74 |
| teste_qa_l03_lixeira_recursiva_com_ciclo_termina | Listagem recursiva da lixeira com ciclo termina | RF-75 |
| teste_qa_l01_paginacao_por_cursor | A listagem da lixeira percorre todas as paginas pelo cursor | RF-75 |
| teste_qa_l02_nomes_hostis_e_json_valido | Nomes hostis na lixeira saem escapados e o JSON produzido e valido | RF-75 |
| teste_qa_d01_delete_in_progress_retenta_e_sai_14 | Exclusao com in_progress e retentada e, persistindo, sai com codigo 14 | RF-77 |
| teste_qa_d02_restore_in_progress_recupera_ou_sai_14 | Restore com in_progress recupera na retentativa ou sai com codigo 14 | RF-77 |
| teste_qa_d03_upload_in_progress_nao_sai_0 | Upload com in_progress persistente nao termina com codigo 0 | RF-77 |
| teste_qa_d04_sync_in_progress_no_envio_sai_14 | Sync com in_progress no envio sai com codigo 14 | RF-77 |


## `tests/integracao/qa_regex_portavel_b17_test.sh`

- **Alvo:** todas as expressoes regulares de `lib/`, `commands/`, `bin/`, `install.sh` e `uninstall.sh` (limite de repeticao RE_DUP_MAX 255 do FreeBSD) e o comportamento de `bin/dbx` (retomada do upload e cursor do sync)
- **Modulo:** qa_regex_portavel_b17
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `suporte-freebsd`)
- **Regras de origem:** RF-166; TC-FBSD-19 (parte regex); log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`; [entrada](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md)
- **Aceite do solicitante:** [entrada](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md) com sha256 `1406718ce5010677ca044cfaaa5acb2b2c042078d6ba627da2fcd55138a015d8`; alterado na demanda `sync-em-blocos`: novo sha256 `87de2391cc3bd773d8884e35510ea0ce0e0f67870b0abce7332b1ba5dc62bb9e`, reaprovado em 2026-10-31, [entrada](../../.github/agents/memoria/entradas/2026-10-31-1200-aceite-testes-qa-sync-em-blocos.md)
- **Dados e precondicoes:** fixture de texto com todas as formas de repeticao; copias do codigo para a mutacao; duble de `curl` proprio; session_id e cursor sinteticos de tamanhos de fronteira; diretorio de estado temporario; sem rede
- **Comando:** `bash tests/run.sh tests/integracao/qa_regex_portavel_b17_test.sh`
- **Observacoes (demanda `sync-em-blocos`):** o duplo de `curl` passou a responder `list_folder` nao recursivo e `get_latest_cursor` (RF-189); nenhum caso foi criado ou removido.
- **Observacoes:** o defeito so e visivel por auditoria do texto das regex, pois o glibc aceita ate 32767; a parte M prova por mutacao que a auditoria reprova.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_a01_o_auditor_pega_toda_forma_de_repeticao_acima_de_255 | O auditor reprova cada forma de repeticao acima de 255 (`{n}`, `{n,}`, `{,m}`, `{n,m}`, BRE `\{n,m\}`) e aceita 255 e valores menores. | |
| teste_qa_a02_o_auditor_cobre_todas_as_raizes_do_produto | O auditor percorre `lib/`, `commands/`, `bin/`, `install.sh` e `uninstall.sh`. | |
| teste_qa_a03_nenhuma_repeticao_do_produto_passa_de_255_em_qualquer_consumidor | Nenhuma repeticao do produto passa de 255 em `[[ =~ ]]`, grep, sed, awk ou `find -regex`. | |
| teste_qa_a04_nenhum_limite_de_repeticao_vem_de_variavel | Nenhum limite de repeticao e montado por variavel (`{1,$N}`) no produto. | |
| teste_qa_b01_upload_interrompido_grava_o_registro_e_a_execucao_seguinte_retoma | Upload por sessao interrompido grava o registro de retomada com session_id realista e a execucao seguinte retoma. | |
| teste_qa_b02_session_id_de_256_caracteres_e_aceito_e_retomado | Session_id de 256 caracteres e aceito e a retomada ocorre. | |
| teste_qa_b03_session_id_de_257_caracteres_nao_vira_registro | Session_id de 257 caracteres nao vira registro de retomada. | |
| teste_qa_c01_cursor_de_300_caracteres_e_gravado_e_reaproveitado | Cursor de 300 caracteres e gravado e reaproveitado na execucao seguinte. | |
| teste_qa_c02_cursor_de_2000_caracteres_e_gravado_e_reaproveitado | Cursor de 2000 caracteres e gravado e reaproveitado. | |
| teste_qa_c03_cursor_de_8192_caracteres_e_aceito | Cursor de 8192 caracteres (limite) e aceito. | |
| teste_qa_c04_cursor_de_8193_caracteres_nao_e_gravado_e_a_execucao_segue | Cursor de 8193 caracteres nao e gravado e a execucao segue pela varredura completa. | |
| teste_qa_c05_cursor_com_caractere_fora_do_alfabeto_nao_e_gravado | Cursor com caractere fora do alfabeto permitido nao e gravado. | |
| teste_qa_c06_assinatura_aceita_256_e_recusa_257_e_vazia | A assinatura de contexto do cursor aceita 256 caracteres e recusa 257 e vazia. | |
| teste_qa_m00_a_copia_sem_mutacao_passa_na_auditoria | A copia do codigo sem mutacao passa na auditoria (controle). | |
| teste_qa_m01_cursor_volta_a_1_8192_e_a_auditoria_reprova | Mutante que volta a repeticao do cursor a 1..8192 e reprovado pela auditoria. | |
| teste_qa_m02_assinatura_volta_a_1_256_e_a_auditoria_reprova | Mutante que volta a assinatura a 1..256 e reprovado pela auditoria. | |
| teste_qa_m03_session_id_volta_a_1_256_e_a_auditoria_reprova | Mutante que volta o session_id a 1..256 e reprovado pela auditoria. | |
| teste_qa_m04_o_mutante_so_aparece_na_auditoria_e_nao_no_comportamento_em_linux | O mutante e visivel so pela auditoria e nao pelo comportamento em Linux. | |
| teste_qa_m05_mutante_em_grep_e_sed_tambem_reprova | Mutante com repeticao acima de 255 em `grep` e `sed` tambem e reprovado. | |


## `tests/integracao/qa_retencao_b6_test.sh`

- **Alvo:** `bin/dbx` (comandos `reter` e `retain`) com `commands/reter.sh`, `lib/retencao.sh`, `lib/filtro.sh`: plano de retencao, lixeira e guarda por identidade antes de cada delete
- **Modulo:** `bin/dbx`
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `backlog-fase-6-retencao`)
- **Regras de origem:** log `docs/prompts/2026-10-20_2010_backlog-fase-6-retencao.md`; [entrada](../../.github/agents/memoria/entradas/2026-10-20-2010-retencao.md); grupos de cenario C (confirmacao), D (delete), L (listagem), P (plano), R (corpo), S (guarda) e X (sinal)
- **Aceite do solicitante:** [entrada](../../.github/agents/memoria/entradas/2026-10-20-2010-retencao.md) e [log de prompt](../prompts/2026-10-20_2010_backlog-fase-6-retencao.md), sha256 `cd0178992648fc24132d992c86927c29b418e7cdcf3ac873ae426c591e258cad`
- **Dados e precondicoes:** duplo de `curl` por regra com registro de chamadas e corpos; listagens sinteticas com nomes datados; ambientes temporarios por caso; `LC_ALL` variado nos casos de localidade
- **Comando:** `bash tests/run.sh tests/integracao/qa_retencao_b6_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_c00_controle_positivo_do_duplo | Com confirmacao valida o duplo recebe o delete esperado, provando que a ausencia nos outros casos e real | |
| teste_qa_c01_sem_confirmar_nenhum_delete_em_qualquer_ordem | Sem a confirmacao explicita nenhum delete e emitido, em qualquer ordem das opcoes | |
| teste_qa_c02_dry_run_vence_confirmar_em_toda_combinacao | `--dry-run` vence a confirmacao em toda combinacao e nada e apagado | |
| teste_qa_c03_grafias_vizinhas_sao_2_sem_rede | Grafias vizinhas da opcao de confirmacao saem com codigo 2 sem rede | |
| teste_qa_d01_not_found_e_ja_ausente | Resposta `not_found` ao apagar conta o item como ja ausente e a execucao segue | |
| teste_qa_d02_autenticacao_taxa_e_rede_param | Falha de autenticacao, limite de taxa ou rede interrompe a execucao com o codigo da classe | |
| teste_qa_d03_resposta_2xx_incoerente_para | Resposta 2xx incoerente a um delete interrompe a execucao | |
| teste_qa_d04_falha_do_item_segue | Falha restrita a um item e registrada e os demais itens seguem | |
| teste_qa_d05_sem_segredo_com_debug_e_falhas | Com `--debug` e falhas nenhuma saida ou diagnostico revela segredo | |
| teste_qa_d06_saidas_coerentes | Contagens e mensagens de saida batem com o que foi apagado, mantido e falhou | |
| teste_qa_l01_server_modified_invalido_e_10_sem_delete | `server_modified` invalido na listagem termina com codigo 10 sem emitir delete | |
| teste_qa_l02_cursor_repetido_nao_consecutivo | Cursor repetido de forma nao consecutiva e tratado como listagem incoerente | |
| teste_qa_l03_has_more_e_cursor_incoerentes | `has_more` e cursor incoerentes entre si terminam como falha sem delete | |
| teste_qa_l04_pagina_2xx_malformada | Pagina 2xx malformada termina como falha de resposta sem delete | |
| teste_qa_l05_teto_de_paginas | Listagem que excede o teto de paginas e interrompida sem delete | |
| teste_qa_l06_date_com_dias | O corte por dias usa a data corrente da execucao de forma coerente | |
| teste_qa_l07_date_da_ultima_pagina | O corte usa a data fixada no inicio e nao a da ultima pagina | |
| teste_qa_p01_empate_pelo_nome_sem_caixa | Empate de data e desfeito pelo nome sem distincao de caixa | |
| teste_qa_p02_manter_n_exato | `--manter N` mantem exatamente os N mais recentes | |
| teste_qa_p03_dias_corte_exato | No corte por dias o item exatamente no limite e mantido e o mais velho e apagado | |
| teste_qa_p04_minimo_de_um_com_empate | Com empate, o minimo de um item mantido continua valendo | |
| teste_qa_p05_carimbo_do_corte_em_datas_limite | O carimbo do corte e calculado corretamente em datas limite (virada de mes e ano) | |
| teste_qa_p06_carimbo_valido_so_na_forma_normalizada | Somente carimbo na forma normalizada e aceito como data valida | |
| teste_qa_p07_dias_com_tudo_velho_mantem_o_mais_novo | Com todos os itens mais velhos que o corte, o mais novo ainda e mantido | |
| teste_qa_p08_dias_pelo_executavel | O corte por dias, usado pelo executavel real, produz o plano esperado | |
| teste_qa_r01_corpo_exato_com_parent_rev_listado | O corpo do delete leva o `parent_rev` listado, exatamente nos campos esperados | |
| teste_qa_r02_rev_malformado_e_10_sem_delete | `rev` malformado na listagem termina com codigo 10 sem delete | |
| teste_qa_r03_conflito_segue_e_nunca_repete_sem_parent_rev | Conflito no delete segue para o proximo item e nunca repete a chamada sem `parent_rev` | |
| teste_qa_s01_entrada_duplicada_nunca_apaga_o_que_fica | Entrada duplicada na listagem nunca leva a apagar o item que deve ficar | |
| teste_qa_s02_duplicata_entre_paginas_e_em_outra_caixa | Duplicata entre paginas ou com caixa diferente e detectada e nenhum item mantido e apagado | |
| teste_qa_s03_ponto_e_ponto_ponto_como_nome | Nomes `.` e `..` na listagem sao tratados como incoerentes e nunca apagados | |
| teste_qa_s04_name_incoerente_com_path_lower | `name` incoerente com `path_lower` impede o delete do item | |
| teste_qa_s05_path_lower_fora_da_pasta | `path_lower` fora da pasta pedida impede o delete | |
| teste_qa_s06_nao_arquivo_nunca_e_apagado | Entrada que nao e arquivo (pasta, por exemplo) nunca e apagada | |
| teste_qa_s07_fora_do_padrao_nunca_e_apagado | Arquivo cujo nome foge do padrao informado nunca e apagado | |
| teste_qa_s08_padroes_ardilosos_nao_alargam_o_casamento | Padroes com metacaracteres ardilosos nao alargam o casamento alem do pretendido | |
| teste_qa_s09_nfc_nao_casa_nfd | Nome em forma NFC nao e confundido com a forma NFD equivalente | |
| teste_qa_s10_plano_anterior_nao_autoriza_nada | Um plano anterior nao autoriza deletes numa execucao nova | |
| teste_qa_s11_guarda_por_item_recusa_cada_condicao | A guarda por item recusa o delete para cada condicao de risco isoladamente | |
| teste_qa_s12_pasta_fora_da_raiz_e_13_sem_chamada | Pasta fora da raiz termina com codigo 13 sem nenhuma chamada | |
| teste_qa_s13_duplicata_com_outra_tag | Duplicata com outra `.tag` e tratada como incoerencia sem delete | |
| teste_qa_s14_duplicata_em_caixa_ascii_entre_paginas | Duplicata so na caixa ASCII entre paginas e detectada | |
| teste_qa_s15_duplicata_em_caixa_nao_ascii | Duplicata so na caixa de caractere fora do ASCII e detectada | |
| teste_qa_s16_normalizacao_em_toda_entrada_e_porcento_literal | A normalizacao vale para toda entrada e o `%` literal no nome nao e reinterpretado | |
| teste_qa_s17_guarda_7_compara_caminho_e_falha_fechada | A guarda 7 compara o caminho e falha fechada quando nao consegue comparar | |
| teste_qa_s18_guarda_sem_a_lista_de_quem_fica_falha_fechada | A guarda sem a lista de quem fica falha fechada e nada e apagado | |
| teste_qa_s19_path_lower_fora_da_minuscula_unicode_e_10 | `path_lower` que nao e a minuscula Unicode do nome termina com codigo 10 | |
| teste_qa_s20_minusculas_unicode_legitimas_sem_falso_10 | Minusculas Unicode legitimas nao geram falso codigo 10 | |
| teste_qa_s21_falha_fechada_sem_localidade_e_com_lc_all_c | Sem localidade UTF-8 ou com `LC_ALL=C` a guarda falha fechada em vez de apagar | |
| teste_qa_s22_guarda_7_com_vetor_malformado | A guarda 7 com vetor de identidade malformado falha fechada | |
| teste_qa_s23_duplicata_nfc_e_nfd | Duplicata em formas NFC e NFD e detectada | |
| teste_qa_s24_bordas_dos_blocos_combinantes | Os limites dos blocos de caracteres combinantes Unicode sao tratados corretamente | |
| teste_qa_s25_utf8_invalido_no_path_lower | UTF-8 invalido em `path_lower` impede o delete | |
| teste_qa_s26_composicao_canonica_fora_dos_blocos | Composicao canonica fora dos blocos tratados nao gera falso casamento | |
| teste_qa_s27_guarda_7_elementos_malformados | A guarda 7 com elementos individuais malformados falha fechada | |
| teste_qa_s28_guarda_7_identidade | A guarda 7 recusa o delete quando a identidade do item difere da esperada | |
| teste_qa_s29_identidade_na_listagem | A identidade do item e conferida ja na listagem e divergencia impede o delete | |
| teste_qa_s30_duplicatas_com_identidades_distintas | Duplicatas com identidades distintas nao apagam nenhum dos itens envolvidos | |
| teste_qa_x01_sinal_na_listagem_nada_apaga | Sinal recebido durante a listagem encerra sem apagar nada | |
| teste_qa_x02_sinal_no_delete_para_e_sai_14 | Sinal recebido durante os deletes interrompe a execucao e sai com codigo 14 | |


## `tests/integracao/qa_retomada_b7a_test.sh`

- **Alvo:** `bin/dbx` (upload e download retomados) com `commands/upload.sh`, `commands/download.sh`, `commands/unlink.sh`, `commands/diagnostico.sh`, `lib/transfer.sh`, `lib/state.sh`: retomada de arquivo grande entre execucoes pelo registro `retomada-*` e pelo `.part`
- **Modulo:** `bin/dbx`
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `backlog-fase-7a-retomada`)
- **Regras de origem:** log `docs/prompts/2026-10-20_2315_backlog-fase-7a-retomada.md`; grupos de cenario D (download), L (nao pendurar em entradas nao regulares) e U (upload)
- **Aceite do solicitante:** [entrada de reaprovacao](../../.github/agents/memoria/entradas/2026-10-27-1500-aceite-reaprovacao-inventario.md), sha256 `593d475f63d8e06738cccd88342bb27af38094077e2754a8d8ed4896a1ecf8dc` (reaprovado em 2026-10-27; a versao aceita antes havia sido alterada sem novo aceite)
- **Dados e precondicoes:** duplo de `curl` com sessoes, `Content-Range` e respostas 206 por regra; estado (`XDG_STATE_HOME`) e area temporaria por caso, com limpeza dos ambientes do caso anterior; fifos, ligacoes fisicas e simbolicas criadas pelo caso; `stat` forjado por duplo quando o caso exige
- **Comando:** `bash tests/run.sh tests/integracao/qa_retomada_b7a_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_d01_part_trocado_por_fifo_ou_diretorio_nao_pendura_nem_e_tocado | `.part` trocado por fifo ou diretorio nao trava a execucao e nao e tocado | |
| teste_qa_d02_part_trocado_por_ligacao_fisica_a_arquivo_do_usuario_fica_intacto | `.part` trocado por ligacao fisica a arquivo do usuario deixa esse arquivo intacto | |
| teste_qa_d03_part_ligacao_simbolica_para_fora_e_listada_pelo_unlink_sem_apagar | `.part` que e vinculo simbolico para fora e listado pelo `unlink` sem apagar o alvo | |
| teste_qa_d04_unlink_com_nome_de_part_com_quebra_de_linha_cita_sem_byte_cru | `unlink` com nome de `.part` contendo quebra de linha o cita escapado, sem byte cru | |
| teste_qa_d05_part_adulterado_no_prefixo_recomeca_e_nunca_troca_com_divergencia | `.part` adulterado no prefixo faz recomecar e nunca publica arquivo com divergencia | |
| teste_qa_d06_206_com_rev_diferente_no_resultado_nunca_e_usado | Resposta 206 com `rev` diferente do registrado nunca e usada para completar o arquivo | |
| teste_qa_d07_varias_quedas_durante_a_faixa_cada_uma_continua_do_tamanho_do_part | Varias quedas durante a faixa fazem cada tentativa continuar do tamanho atual do `.part` | |
| teste_qa_d08_remoto_trocado_de_mesmo_tamanho_nunca_mistura_revisoes | Remoto trocado por outro de mesmo tamanho nunca mistura bytes de revisoes diferentes | |
| teste_qa_d09_dry_run_e_sem_retomada_nao_tocam_registro_nem_part | `--dry-run` e a execucao sem retomada nao tocam o registro nem o `.part` | |
| teste_qa_d10_sinal_durante_a_faixa_preserva_part_e_registro | Sinal durante a faixa preserva o `.part` e o registro para a retomada seguinte | |
| teste_qa_d11_diretorio_de_estado_inutilizavel_recebe_sem_residuo | Diretorio de estado inutilizavel nao impede o download e nao deixa residuo | |
| teste_qa_d12_registro_de_download_copiado_para_outro_alvo_nao_anexa_ao_part_alheio | Registro copiado para outro alvo nao anexa bytes a um `.part` alheio | |
| teste_qa_d13_registro_descartado_por_cabecalho_nao_deixa_part_invisivel | Registro descartado por cabecalho invalido nao deixa `.part` invisivel e sem dono | |
| teste_qa_d14_trava_do_registro_fifo_no_download_nao_pendura_nem_toca_o_part | Trava do registro substituida por fifo nao pendura o download nem toca o `.part` | |
| teste_qa_d15_mesmo_alvo_por_ligacao_no_pai_ou_caminho_relativo_retoma_sem_orfao | O mesmo alvo alcancado por ligacao no diretorio pai ou caminho relativo retoma sem deixar `.part` orfao | |
| teste_qa_d16_descarte_por_cabecalho_so_apaga_pela_barreira_e_so_do_proprio_alvo | O descarte por cabecalho so apaga passando pela barreira e somente o `.part` do proprio alvo | |
| teste_qa_l01_fifo_retomada_nao_pendura_diagnostico | Fifo no lugar de registro de retomada nao pendura o diagnostico | |
| teste_qa_l02_fifo_retomada_nao_pendura_unlink | Fifo no lugar de registro de retomada nao pendura o `unlink` | |
| teste_qa_l03_diagnostico_cita_caminhos_hostis_e_nao_vaza_sessao | O diagnostico cita caminhos hostis de forma segura e nao vaza o identificador da sessao | |
| teste_qa_l04_entradas_nao_regulares_em_todo_namespace_nao_penduram_diagnostico | Entradas nao regulares em todo o namespace de estado nao penduram o diagnostico | |
| teste_qa_l05_entradas_nao_regulares_nao_penduram_unlink_e_o_fora_fica | Entradas nao regulares nao penduram o `unlink` e o que esta fora do estado permanece | |
| teste_qa_l06_entradas_nao_regulares_nao_penduram_upload_download_nem_poda | Entradas nao regulares nao penduram upload, download nem a poda | |
| teste_qa_u01_sufixo_alterado_com_stat_forjado_publica_o_conteudo_corrente | Arquivo cujo sufixo mudou com `stat` forjado publica o conteudo corrente, nao o antigo | |
| teste_qa_u02_parte_em_voo_alterada_com_stat_forjado_recomeca_sem_misturar | Parte em voo alterada com `stat` forjado recomeca a sessao sem misturar conteudos | |
| teste_qa_u03_truncado_recomeca_e_a_sessao_antiga_nao_recebe_nada | Arquivo truncado recomeca e a sessao antiga nao recebe mais nenhum byte | |
| teste_qa_u04_outro_inode_com_o_mesmo_conteudo_recomeca | Outro inode com o mesmo conteudo nao herda o registro e recomeca | |
| teste_qa_u05_ligacao_fisica_nao_herda_o_registro_e_muda_o_ctime | Ligacao fisica nao herda o registro (o `ctime` muda) e o envio recomeca | |
| teste_qa_u06_correct_offset_fora_do_aceito_nunca_corrompe | `correct_offset` fora do aceito pelo servidor nunca corrompe o arquivo remoto | |
| teste_qa_u07_not_found_na_retomada_recomeca_e_o_resultado_e_o_local | `not_found` da sessao na retomada recomeca e o resultado final e o arquivo local | |
| teste_qa_u08_registro_copiado_para_o_nome_de_outra_transferencia_e_descartado | Registro copiado para o nome de outra transferencia e descartado | |
| teste_qa_u09_injecao_de_nul_e_quebra_de_linha_e_outro_host_sao_descartados | Registro com NUL ou quebra de linha injetados, ou de outro host, e descartado | |
| teste_qa_u10_registro_acima_de_16_kib_e_gigante_sem_nul_sao_descartados_rapido | Registro acima de 16 KiB ou gigante sem NUL e descartado rapidamente, sem leitura integral | |
| teste_qa_u11_upload_cache_gigante_e_tratado_como_ausente_c3 | Cache de upload gigante e tratado como ausente | C3 |
| teste_qa_u12_registro_fifo_diretorio_e_ligacao_nao_penduram_nem_sao_tocados | Registro que e fifo, diretorio ou ligacao nao pendura a execucao nem e tocado | |
| teste_qa_u13_trava_de_registro_ilegivel_segue_sem_retomada_sem_tocar_em_nada | Trava de registro ilegivel segue sem retomada e sem tocar em nada | |
| teste_qa_u14_session_id_fora_de_argv_ambiente_saidas_e_arquivos | O `session_id` nunca aparece em `argv`, ambiente, saidas ou arquivos | |
| teste_qa_u15_umask_000_registro_0600_diretorio_0700_e_sem_temporario | Com `umask 000` o registro sai com modo 0600, o diretorio com 0700 e sem temporario residual | |
| teste_qa_u16_dry_run_e_sem_retomada_nao_leem_nem_gravam_estado | `--dry-run` e a execucao sem retomada nao leem nem gravam estado | |
| teste_qa_u17_sinal_na_execucao_retomada_avanca_o_registro_e_a_seguinte_conclui | Sinal numa execucao retomada avanca o registro e a execucao seguinte conclui o envio | |
| teste_qa_u18_diretorio_de_estado_inutilizavel_segue_sem_retomada | Diretorio de estado inutilizavel faz o envio seguir sem retomada | |
| teste_qa_u19_trava_do_registro_fifo_ou_ligacao_para_fifo_segue_sem_retomada | Trava do registro que e fifo (ou ligacao para fifo) faz o envio seguir sem retomada | |


## `tests/integracao/qa_robustez_rede_p2_test.sh`

- **Alvo:** `bin/dbx` download, upload, sync e diagnostico sob falhas de rede, consumidor que fecha cedo, sinais e segredos (`commands/download.sh`, `commands/upload.sh`, `commands/sync.sh`, `lib/http.sh`, `lib/output.sh`, `lib/cmd.sh`)
- **Modulo:** `qa_robustez`
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `robustez-de-rede-p2`)
- **Regras de origem:** RNF-30(c); RNF-07(e); RF-32(b); RF-59; RNF-31; log `docs/prompts/2026-10-18_2045_robustez-de-rede-p2.md`
- **Aceite do solicitante:** [entrada de reaprovacao](../../.github/agents/memoria/entradas/2026-10-27-1500-aceite-reaprovacao-inventario.md), sha256 `1f1731bf33212622ad5e5bc4777cd415faf7fea39c7cd2adeb9f668741edd565` (reaprovado em 2026-10-27; a versao aceita antes havia sido alterada sem novo aceite)
- **Dados e precondicoes:** duplo de rede proprio e binario-seguro (conteudo do download por `cat`, preserva NUL); `TMPDIR` proprio por cenario para contar residuos; tokens sentinela sinteticos
- **Comando:** `bash tests/run.sh tests/integracao/qa_robustez_rede_p2_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_ajuste_invalido_no_download_para_a_saida_padrao_nao_chama_a_rede | Ajuste invalido no download para a saida padrao sai antes de qualquer chamada de rede | |
| teste_qa_ajuste_invalido_no_envio_nao_chama_a_rede | Ajuste invalido no envio sai antes de qualquer chamada de rede | |
| teste_qa_caminho_com_tabulacao_e_escape_sai_citado_em_uma_linha | Caminho com tabulacao e sequencia de escape sai citado, em uma unica linha | RF-59 |
| teste_qa_conteudo_baixado_que_contem_o_token_nao_e_alterado | Conteudo baixado que contem texto igual ao token nao e mascarado nem alterado | RNF-07(e) |
| teste_qa_diagnostico_mascara_pelo_valor_token_com_metacaracteres_colado_a_prefixo | O diagnostico mascara pelo valor um token com metacaracteres colado a prefixo | RNF-07(e) |
| teste_qa_diagnostico_mascara_token_no_formato_sl_u_pelo_valor | O diagnostico mascara pelo valor um token no formato `sl.u` | RNF-07(e) |
| teste_qa_diagnostico_redige_token_sl_u_alheio_pela_forma_sem_consumir_o_vizinho | Token `sl.u` alheio e redigido pela forma sem consumir o texto vizinho | RNF-07(e) |
| teste_qa_download_com_hifen_e_com_json_nao_suja_a_saida_padrao | Download para a saida padrao com `--json` nao mistura mensagens no stdout | RF-32(b) |
| teste_qa_download_para_consumidor_que_fecha_cedo_termina_sem_travar | Download cujo consumidor fecha cedo termina sem travar | RF-32(b) |
| teste_qa_download_sem_destino_de_binario_grande_com_nul_e_byte_a_byte | Binario grande com bytes NUL baixado sem destino sai identico byte a byte | RF-32(b) |
| teste_qa_falha_real_de_escrita_em_arquivo_nao_vira_consumidor_encerrou | Falha real de escrita em arquivo nao e confundida com consumidor que encerrou | |
| teste_qa_hup_durante_o_recebimento_do_sync_nao_deixa_area | `HUP` durante o recebimento do sync nao deixa area temporaria | RNF-31 |
| teste_qa_int_durante_a_conferencia_do_lote_nao_deixa_area_nem_repete | `INT` durante a conferencia do lote nao deixa area nem repete trabalho | RNF-31 |
| teste_qa_int_durante_a_exclusao_do_espelho_nao_deixa_area | `INT` durante a exclusao do espelho nao deixa area temporaria | RNF-31 |
| teste_qa_json_com_null_emite_os_pares_terminados_em_nul | `--json` com `--null` emite os pares terminados em NUL | RF-59 |
| teste_qa_json_com_tres_falhas_de_classes_distintas_mantem_a_ordem | `--json` com tres falhas de classes distintas mantem a ordem dos registros | RF-59 |
| teste_qa_renovacao_recusada_nao_ecoa_refresh_token_nem_app_secret | Renovacao recusada nao ecoa refresh token nem app secret | RNF-30(c); protocolo-tdd Regra 6 |
| teste_qa_resumo_com_token_colado_a_prefixo_nao_vaza | Resumo de erro com token colado a prefixo nao vaza o valor | RNF-07(e) |
| teste_qa_saida_padrao_sem_espaco_falha_sem_repetir | Saida padrao sem espaco falha uma vez, sem repetir a tentativa | |
| teste_qa_sync_com_falha_de_item_nao_deixa_area_e_devolve_os_sinais | Sync com falha de item nao deixa area temporaria e devolve o sinal esperado | RNF-31 |
| teste_qa_term_durante_a_listagem_do_receber_nao_deixa_area | `TERM` durante a listagem do receber nao deixa area temporaria | RNF-31 |


## `tests/integracao/qa_sync_blocos_b21_test.sh`

- **Alvo:** `bin/dbx` (`sync` nos dois sentidos, `upload` e `download` de pasta) em blocos de arquivos cortados por diretorio, com foco na exclusao, na origem vazia, no cursor e no corte por diretorio
- **Modulo:** `qa_sync_blocos` (filtro do mapa de modulos)
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `sync-em-blocos`)
- **Regras de origem:** F-101; RF-186..RF-197; TC-BLC-nn (secao 5.24 do escopo); log `docs/prompts/2026-10-31_1200_sync-em-blocos.md`; registro `docs/reviews/2026-10-31-1200-registro-sync-em-blocos.md`; DIV-377..DIV-384
- **Aceite do solicitante:** [entrada](../../.github/agents/memoria/entradas/2026-10-31-1200-aceite-testes-qa-sync-em-blocos.md) com sha256 `f5e8fc366fda4d77c41db5e1541d40060a273ad1532397f11466209502bbd6f8` (2026-10-31)
- **Dados e precondicoes:** duplo de `curl` proprio por roteiro, registros de chamadas em arquivos temporarios; arvores locais e remotas sinteticas por caso; sem rede; casos de modo 000 nao rodam como root
- **Comando:** `bash tests/run.sh tests/integracao/qa_sync_blocos_b21_test.sh`
- **Observacoes:** Escrita como adversario a partir da secao 5.24 do escopo; prioridade na exclusao (RF-190, RF-191, RF-41(a)): diretorio nao observado nunca perde arquivo.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_blc_exclusao_so_com_o_diretorio_lido_inteiro_nos_dois_lados | Em execucao integral, apaga os sobrantes de d1, d2, d3 e do topo e preserva os arquivos iguais. | RF-190 |
| teste_qa_blc_listagem_remota_falha_no_ciclo_2_nao_apaga_o_nao_observado | Falha de listagem remota no ciclo 2 sai diferente de zero e nenhum arquivo do diretorio que falhou nem dos ciclos seguintes e apagado. | RF-190; RF-193 |
| teste_qa_blc_segunda_pagina_que_falha_desliga_a_exclusao | Segunda pagina remota que falha sai diferente de zero e a pagina parcial nunca autoriza exclusao. | RF-190 |
| teste_qa_blc_leitura_local_parcial_no_ciclo_2_desliga_a_exclusao_dos_seguintes | Leitura local parcial no ciclo 2 sai diferente de zero e desliga a exclusao do ciclo da parcialidade e dos seguintes. | RF-41(a); RF-190 |
| teste_qa_blc_diretorio_so_no_destino_so_e_apagado_com_o_pai_observado | Diretorio so no destino e apagado quando o pai foi observado; com a listagem do pai falhando, o filho so do destino permanece. | RF-190 |
| teste_qa_blc_origem_vazia_recusa_14_sem_nenhuma_escrita_e_o_flag_libera | Origem vazia recusa com 14 sem escrita, mesmo com `--confirmar`; `--dry-run` anuncia a recusa sem recusar; o flag proprio libera e o sobrante e apagado. | RF-191 |
| teste_qa_blc_origem_so_de_pastas_vazias_com_bloco_1_continua_origem_vazia_de_arquivos | Origem so com pastas vazias e `--bloco 1` continua origem vazia de arquivos: 14 e nada apagado. | RF-191 |
| teste_qa_blc_enviar_apaga_no_remoto_so_o_observado_nos_dois_lados | `--enviar --espelhar` apaga no remoto so o observado nos dois lados (sobrantes de d1, d2, d3 e pasta so do destino com pai observado) e nunca os arquivos iguais. | RF-190 |
| teste_qa_blc_enviar_listagem_do_ciclo_falha_nao_apaga_do_nao_observado | No `--enviar`, falha de listagem do ciclo sai diferente de zero e nao apaga do diretorio que falhou nem dos ciclos seguintes. | RF-190(d); RF-193(b) |
| teste_qa_blc_o_diretorio_que_cruza_n_entra_inteiro_e_fecha_o_ciclo | Com diretorios [2,2,2,2] e N=5 sao dois ciclos; com [1,1,1] e N=3, um ciclo (`ciclos=` no `--json`). | RF-187 |
| teste_qa_blc_diretorio_maior_que_n_forma_ciclo_sozinho_e_nao_e_partido | Diretorio de 12 arquivos com N menor forma ciclo sozinho (`ciclos=2`) e nenhum diretorio e partido. | RF-187(c) |
| teste_qa_blc_subdiretorio_sem_arquivo_direto_e_unidade_propria_de_custo_zero | Subdiretorio sem arquivo direto e unidade propria de custo zero: p(3)+s(1) atinge N so no fim e forma um ciclo. | RF-187 |
| teste_qa_blc_o_conjunto_final_independe_do_tamanho_do_bloco | O conjunto final de arquivos e identico para varios tamanhos de bloco. | RF-187(d) |
| teste_qa_blc_cada_diretorio_remoto_e_listado_uma_vez_e_nunca_recursivo | Na varredura completa nenhum `list_folder` e recursivo e cada diretorio remoto e listado exatamente uma vez. | RF-188(b); RF-189(a) |
| teste_qa_blc_diretorio_remoto_inexistente_e_lista_vazia_e_o_ciclo_segue | `path/not_found` na listagem e lista vazia, nao falha, e o ciclo seguinte roda. | RF-189 |
| teste_qa_blc_pasta_excluida_nao_e_listada_no_remoto | Pasta excluida pelo filtro nao e listada no remoto e seus arquivos locais permanecem. | RF-189; filtros |
| teste_qa_blc_valor_invalido_sai_2_antes_de_rede_e_de_estado | `--bloco` e `DBX_BLOCO` invalidos saem com 2 nomeando a origem do valor, sem chamada de rede; a opcao vence a variavel e `--batch` e alias. | RF-186 |
| teste_qa_blc_cursor_so_e_gravado_ao_fim_integral | O cursor so e gravado em execucao que termina integral; execucao com falha nao grava. | RF-192 |
| teste_qa_blc_falha_no_ciclo_k_preserva_o_cursor_anterior_intacto | Falha no ciclo 2 deixa cursor e retrato anteriores intactos (impressao igual a anterior). | RF-192 |
| teste_qa_blc_enviar_nao_le_nem_cria_cursor | `--enviar` nao pede cursor e nao cria nem le cursor. | RF-192 |
| teste_qa_blc_colisao_de_caixa_no_diretorio_recusa_antes_de_enviar | Colisao de caixa no diretorio recusa e nenhum envio ocorre antes da recusa. | RF-194 |
| teste_qa_blc_dry_run_nao_escreve_nada_em_nenhum_lado | `--dry-run` nao baixa, nao apaga, nao grava estado e nao faz chamada de escrita remota. | RF-196 |
| teste_qa_blc_json_agrega_ciclos_e_traz_o_bloco_efetivo | `--json` agrega `ciclos=3`, `bloco=2`, `bloco_origem=opcao` e `recebidos=6` somando os tres ciclos. | RF-197 |
| teste_qa_blc_arquivo_local_ilegivel_no_ciclo_desliga_a_exclusao_dali_em_diante | Arquivo local ilegivel no ciclo desliga a exclusao dali em diante: codigo diferente de zero, sobrantes do ciclo e dos seguintes preservados e o arquivo ilegivel permanece. | RF-41(a); RF-190 |
| teste_qa_blc_filtro_sem_casamento_na_raiz_nao_recusa_por_origem_vazia | Filtro sem casamento na raiz nao recusa por origem vazia com `--bloco 1` nem com bloco grande; o plano apaga `sobra.log` nos dois casos. | RF-191; filtros |


## `tests/integracao/qa_trava_tmp_b2_test.sh`

- **Alvo:** `bin/dbx` (sync, `--dry-run`, verificar, download de pasta, unlink, diagnostico, upload), `lib/state.sh` (trava de concorrencia por par), `lib/tmp.sh` (area temporaria unica)
- **Modulo:** qa_trava_tmp
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `backlog-fase-2-trava-e-tmp`)
- **Regras de origem:** F-12, F-31; RF-69, RF-70, RF-71; DIV-38..49; DIV-51; RNF-35, RNF-36; protocolo-tdd Regra 6; log `docs/prompts/2026-10-19_1419_backlog-fase-2-trava-e-tmp.md`
- **Aceite do solicitante:** [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md), sha256 `2114eaa27547bf7dcf37aaa322865fbca9c2401315f350898ea7d562df6d3333`
- **Dados e precondicoes:** duplos proprios de `curl`, `ln` (mata o `dbx` com SIGKILL em cada fase da retomada) e `sleep`; processos `bin/dbx` simultaneos reais; `setsid` por execucao; `TMPDIR` privado por caso
- **Comando:** `bash tests/run.sh tests/integracao/qa_trava_tmp_b2_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_b2_01_dez_execucoes_simultaneas_do_mesmo_par_um_so_entra | Dez execucoes simultaneas do mesmo par origem/destino: exatamente uma entra | RF-69 |
| teste_qa_b2_02_dez_retomadores_simultaneos_da_mesma_orfa_um_so_entra | Dez retomadores simultaneos da mesma trava orfa: exatamente um a assume | RF-70 |
| teste_qa_b2_03_sigkill_em_cada_fase_da_retomada_nunca_rouba_nem_some | SIGKILL em cada fase da retomada de orfa nunca rouba nem faz sumir a trava | RF-70 |
| teste_qa_b2_04_sigkill_com_a_trava_detida_vira_orfa_retomada | Processo morto por SIGKILL com a trava detida deixa orfa que a execucao seguinte retoma | RF-70 |
| teste_qa_b2_05_pid_reaproveitado_ou_de_outro_usuario_conta_como_viva | PID reaproveitado ou de outro usuario e tratado como dono vivo, sem retomar | RF-70 |
| teste_qa_b2_06_outro_host_nunca_retomado_nem_esperando_e_reinicio_e_orfa | Trava de outro host nunca e retomada; trava do mesmo host apos reinicio e orfa | RF-70 |
| teste_qa_b2_07_trava_hostil_e_ilegivel_nunca_retomada_apagada_nem_ecoada | Trava hostil ou ilegivel nunca e retomada, apagada nem reproduzida na saida | protocolo-tdd Regra 6 |
| teste_qa_b2_08_ligacao_simbolica_ou_diretorio_no_lugar_da_trava_ou_da_r | Ligacao simbolica ou diretorio no lugar da trava ou do ponto `.r` e tratado como ilegivel e fica intacto | protocolo-tdd Regra 6 |
| teste_qa_b2_09_verificar_e_simulacao_deixam_o_estado_como_estava | `verificar` e a simulacao (`--dry-run`) deixam o estado exatamente como estava, sem criar trava | RF-69 |
| teste_qa_b2_10_estado_sem_escrita_ou_alheio_segue_sem_trava_so_sem_trava_que_decida | Estado sem permissao de escrita ou alheio segue sem trava, mas so quando nao ha trava viva que decida | RF-71 |
| teste_qa_b2_11_chave_sem_ordem_canonica_e_sem_caixa | A chave da trava nao depende da ordem de origem/destino nem da caixa do caminho remoto | RF-69 |
| teste_qa_b2_12_receber_em_destino_ainda_inexistente_tem_a_mesma_chave | Receber em destino ainda inexistente gera a mesma chave de trava que o destino ja existente | RF-69 |
| teste_qa_b2_13_download_de_pasta_trava_o_par | Download de pasta toma a trava do par | RF-69 |
| teste_qa_b2_14_esperar_limites_e_valores_nao_numericos | `--esperar` rejeita valores fora dos limites e valores nao numericos | RF-71 |
| teste_qa_b2_15_esperar_real_adquire_ao_liberar_e_esgota_no_prazo | `--esperar` adquire a trava quando liberada e esgota no prazo quando nao e | RF-71 |
| teste_qa_b2_16_sinal_na_espera_sai_14_sem_residuo_e_sem_tocar_a_trava_alheia | Sinal durante a espera sai com codigo 14, sem residuo e sem tocar a trava de outro dono | RF-71 |
| teste_qa_b2_17_lib_tmp_subshell_codigo_e_sinal_durante_a_limpeza | A area temporaria preserva o codigo de saida em subshell e sob sinal durante a limpeza | RNF-35 |
| teste_qa_b2_18_obs03_sinal_logo_apos_o_mktemp_nao_deixa_area | Sinal logo apos a criacao da area temporaria nao deixa a area para tras | RNF-35 |
| teste_qa_b2_19_unlink_nao_apaga_estado_de_sync_que_comecou_durante_ele | `unlink` nao apaga o estado de um `sync` que comecou durante a sua execucao | RF-69 |
| teste_qa_b2_20_mensagens_de_trava_sem_segredo_e_nome_hostil_sem_byte_cru | Mensagens de trava nao expoem segredo e nome hostil nao aparece com byte cru | protocolo-tdd Regra 6 |
| teste_qa_b2_21_mesma_grafia_remota_em_localidades_diferentes_se_exclui | A mesma grafia remota em localidades diferentes (C e UTF-8) disputa a mesma trava | RF-69 |
| teste_qa_b2_22_div51_download_para_socket_vivo_sai_0_e_fechado_sai_15 | Download para socket vivo sai com 0 e para socket fechado sai com 15 | DIV-51 |
| teste_qa_b2_23_unlink_para_quando_uma_orfa_e_retomada_durante_a_remocao | `unlink` para quando uma trava orfa e retomada por outro processo durante a remocao | RF-70 |


## `tests/integracao/qa_upload_para_pasta_b15_test.sh`

- **Alvo:** `bin/dbx upload` de arquivo para pasta remota existente (`commands/upload.sh`, `lib/cmd.sh`), com e sem raiz remota e barra final
- **Modulo:** `qa_upload_para_pasta`
- **Camada:** integracao
- **Autoria:** QA Expert (suite independente da demanda `upload-arquivo-para-pasta`)
- **Regras de origem:** RF-174; emenda de RF-60(g)(h); log `docs/prompts/2026-10-26_1300_upload-arquivo-para-pasta.md`
- **Aceite do solicitante:** [registro de aceite no log](../prompts/2026-10-26_1300_upload-arquivo-para-pasta.md) com sha256 `dabdb304830025c12209554ab6111c31b2d8765015bcc8919d1f871d5934a867`
- **Dados e precondicoes:** duplo de `curl` proprio (prefixo `qp_`) que responde `get_metadata` por caminho (tabela `metas`; ausente = 409 `not_found`) e registra rotas em `chamadas`, caminhos em `consultas` e o `Dropbox-API-Arg` enviado em `opcoes`; arquivos locais sinteticos
- **Comando:** `bash tests/run.sh tests/integracao/qa_upload_para_pasta_b15_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_arquivo_diferente_na_pasta_e_enviado | Arquivo de conteudo diferente do existente na pasta e enviado | |
| teste_qa_arquivo_identico_na_pasta_e_dispensado_sem_envio | Arquivo identico ao existente na pasta e dispensado sem envio | |
| teste_qa_barra_final_em_pasta_existente_nao_duplica_barra | Destino com barra final em pasta existente nao duplica a barra no caminho | |
| teste_qa_barra_final_sem_pasta_existir_nao_consulta_o_tipo | Destino com barra final dispensa a consulta de tipo do caminho | |
| teste_qa_confinamento_com_raiz_remota_prefixa_pasta_e_nome | Com raiz remota, o caminho final e a raiz mais pasta e nome | |
| teste_qa_confinamento_destino_barra_final_com_raiz_remota | Destino com barra final sob raiz remota fica confinado a ela | |
| teste_qa_confinamento_destino_que_escapa_da_raiz_nunca_grava_fora | Destino que escapa da raiz remota e recusado e nunca grava fora dela | protocolo-tdd Regra 6 |
| teste_qa_confinamento_nome_nao_escapa_com_raiz_remota | Nome de arquivo com `..` nao escapa da raiz remota | protocolo-tdd Regra 6 |
| teste_qa_destino_arquivo_diferente_mantem_comportamento_anterior_e_envia | Destino que e arquivo existente de conteudo diferente mantem o comportamento anterior e envia | |
| teste_qa_destino_arquivo_identico_continua_dispensado | Destino que e arquivo existente identico continua dispensado | |
| teste_qa_destino_inexistente_sem_barra_mantem_comportamento_anterior | Destino inexistente sem barra final mantem o comportamento anterior | |
| teste_qa_destino_raiz_envia_para_raiz_com_o_nome | Destino na raiz envia para a raiz com o nome do arquivo | |
| teste_qa_dry_run_com_barra_final_reporta_caminho_final_sem_escrita | `--dry-run` com barra final reporta o caminho final sem escrever | |
| teste_qa_dry_run_com_pasta_existente_reporta_caminho_final_sem_escrita | `--dry-run` com pasta existente reporta o caminho final sem escrever | |
| teste_qa_forcar_com_barra_final_nao_consulta | `--forcar` com barra final nao consulta o tipo do destino | |
| teste_qa_forcar_com_pasta_faz_exatamente_uma_consulta_de_tipo | `--forcar` com pasta faz exatamente uma consulta de tipo | |
| teste_qa_forcar_destino_arquivo_mantem_o_caminho | `--forcar` com destino que e arquivo mantem o caminho informado | |
| teste_qa_nome_com_aspas_fica_escapado_e_sob_a_pasta | Nome com aspas segue escapado no argumento da API e sob a pasta | |
| teste_qa_nome_com_espaco_e_unicode_vai_inteiro_para_a_pasta | Nome com espaco e unicode vai inteiro para a pasta | |
| teste_qa_nome_com_pontos_duplos_nao_e_componente_e_nao_escapa | Nome com pontos duplos no meio nao e componente de caminho e nao escapa | protocolo-tdd Regra 6 |
| teste_qa_pasta_existente_upload_por_sessao_finish_em_pasta_e_nome | Upload por sessao para pasta existente termina com `finish` em pasta e nome | |
| teste_qa_pasta_existente_upload_simples_envia_para_pasta_e_nome | Upload simples para pasta existente envia para pasta e nome | |
| teste_qa_rev_com_pasta_nao_consulta_e_usa_o_caminho_informado | Com `--rev` e pasta, nao consulta o tipo e usa o caminho informado | |
| teste_qa_stdin_com_barra_final_recusa_com_2_sem_escrita | `upload -` com destino de barra final recusa com codigo 2 sem escrever | |
| teste_qa_stdin_com_nome_no_destino_continua_funcionando | `upload -` com nome no destino continua funcionando | |
| teste_qa_stdin_para_pasta_existente_recusa_com_2_sem_escrita | `upload -` para pasta existente recusa com codigo 2 sem escrever | |


## `tests/integracao/recuperacao_test.sh`

- **Alvo:** `bin/dbx` (`revisoes`, `restaurar`, `lixeira` e aliases, incluindo expurgo permanente), `commands/revisoes.sh`, `commands/restaurar.sh`, `commands/lixeira.sh`
- **Modulo:** recuperacao
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-3-recuperacao`)
- **Regras de origem:** F-07, F-20; RF-72 a RF-78; TC-RVS, TC-RST, TC-RPA, TC-LIX, TC-EXP, TC-DOC-02; log `docs/prompts/2026-10-19_1828_backlog-fase-3-recuperacao.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` que responde por regra (endpoint e filtro do corpo) com registro de chamadas em `chamadas` (chamada sem regra responde 400 e marca `SEM_REGRA`); `setsid` para o TERM e terminal real por `script(1)` na confirmacao; diretorio de estado temporario; sem rede
- **Comando:** `bash tests/run.sh tests/integracao/recuperacao_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_doc02_readme_e_ajuda_citam_escopo_business_e_remedio | README e ajuda do comando citam o escopo necessario, o limite do plano Business e o remedio | TC-DOC-02 |
| teste_exp01_item_apagado_confirmado_e_expurgado | Item apagado, com o caminho digitado como confirmacao, e expurgado permanentemente | TC-EXP-01 |
| teste_exp02_item_vivo_e_recusado_sem_chamada_destrutiva | Item ainda vivo e recusado sem nenhuma chamada destrutiva | TC-EXP-02 |
| teste_exp03_inexistente_e_4 | Expurgo de item inexistente sai com codigo 4 | TC-EXP-03 |
| teste_exp04_sem_confirmacao_e_sem_terminal_e_2_sem_nenhuma_chamada | Sem confirmacao e sem terminal sai com codigo 2 sem nenhuma chamada | TC-EXP-04 |
| teste_exp05_com_terminal_o_operador_digita_o_caminho | Com terminal, a confirmacao exige que o operador digite o caminho do item | TC-EXP-05 |
| teste_exp06_yes_y_e_confirmar_nao_existem_aqui | Opcoes `--yes`, `-y` e `--confirmar` nao existem neste comando e sao recusadas | TC-EXP-06 |
| teste_exp07_dry_run_sem_expurgo_e_sem_pergunta | `--dry-run` nao expurga nem pergunta | TC-EXP-07 |
| teste_exp08_conta_pessoal_e_permissao_com_remedio | Conta pessoal ou permissao insuficiente falha com mensagem que indica o remedio | TC-EXP-08 |
| teste_exp09_escopo_ausente_e_autenticacao_com_remedio | Escopo ausente na credencial falha como autenticacao e indica o remedio | TC-EXP-09 |
| teste_exp10_fora_da_raiz_e_a_propria_raiz | Caminho fora da raiz configurada, ou a propria raiz, e recusado sem chamada | TC-EXP-10 |
| teste_exp11_excluir_com_pasta_posicional_e_2 | `excluir` com pasta posicional sai com codigo 2 | TC-EXP-11 |
| teste_exp12_aviso_de_irreversibilidade_em_stderr | O aviso de irreversibilidade do expurgo sai em stderr | TC-EXP-12 |
| teste_exp13_too_many_write_operations_e_repetido | Erro `too_many_write_operations` do servidor e repetido ate concluir | TC-EXP-13 |
| teste_exp14_sentinelas_ausentes_de_toda_saida | Valores sentinela de segredo nunca aparecem em nenhuma saida do expurgo | TC-EXP-14 |
| teste_exp_guarda_exige_path_lower_do_proprio_alvo | A guarda do expurgo exige que o `path_lower` retornado seja o do proprio alvo | |
| teste_exp_guarda_recusa_u0000_e_campo_duplicado | A guarda recusa resposta com `\u0000` e campo duplicado no JSON | |
| teste_exp_pasta_apagada_avisa_a_contagem | Expurgo de pasta apagada avisa a contagem de itens atingidos | |
| teste_lix01_so_apagados_com_restauravel | `lixeira` lista somente itens apagados e marca os restauraveis | TC-LIX-01 |
| teste_lix02_sem_argumento_usa_a_raiz_remota | `lixeira` sem argumento usa a raiz remota configurada | TC-LIX-02 |
| teste_lix03_recursivo_desce_um_nivel_por_vez | `lixeira --recursivo` desce um nivel por vez | TC-LIX-03 |
| teste_lix04_include_deleted_e_limit_explicito | A listagem envia `include_deleted` e `limit` explicito | TC-LIX-04 |
| teste_lix05_lixeira_vazia_sai_0_com_total_0 | Lixeira vazia sai com codigo 0 e total 0 | TC-LIX-05 |
| teste_lix06_fora_da_raiz_arquivo_e_inexistente | Argumento fora da raiz, arquivo ou inexistente e recusado com o codigo correspondente | TC-LIX-06 |
| teste_lix07_json_null_e_nenhuma_escrita | `--json` e `--null` produzem a saida estruturada e a lixeira nunca faz escrita | TC-LIX-07 |
| teste_lix_qa_b3_06_recursiva_com_ciclo_termina | Listagem recursiva sobre estrutura com ciclo termina | |
| teste_rpa01_tres_arquivos_em_dois_niveis | Restaurar pasta recupera tres arquivos distribuidos em dois niveis | TC-RPA-01 |
| teste_rpa02_sem_recursive_e_com_limit_em_toda_listagem | Toda listagem da restauracao de pasta vai sem `recursive` e com `limit` | TC-RPA-02 |
| teste_rpa03_item_vivo_nao_e_tocado | Item ainda vivo dentro da pasta nao e tocado na restauracao | TC-RPA-03 |
| teste_rpa04_falha_de_item_segue_e_sai_14 | Falha em um item nao interrompe os demais e o comando sai com codigo 14 | TC-RPA-04 |
| teste_rpa05_travessia_parcial_sai_14_com_o_que_faltou | Travessia parcial sai com codigo 14 e informa o que faltou | TC-RPA-05 |
| teste_rpa06_dry_run_lista_sem_restore | `--dry-run` lista o que seria restaurado sem chamar `restore` | TC-RPA-06 |
| teste_rpa07_reexecucao_restaura_so_o_que_falta | Reexecucao restaura somente o que ainda falta | TC-RPA-07 |
| teste_rpa08_rev_ou_antes_de_com_pasta_e_uso_invalido | `--rev` ou `--antes-de` combinado com pasta e uso invalido | TC-RPA-08 |
| teste_rpa09_item_fora_da_raiz_nunca_e_restaurado | Item fora da raiz configurada nunca e restaurado | TC-RPA-09 |
| teste_rpa10_term_no_meio_sai_14_com_resumo_parcial_e_tmpdir_limpo | TERM no meio da restauracao sai com 14, resumo parcial e area temporaria limpa | TC-RPA-10 |
| teste_rpa_div78_item_fora_da_pasta_pedida_e_falha_mesmo_dentro_da_raiz | Item retornado fora da pasta pedida e tratado como falha, mesmo dentro da raiz | DIV-78 |
| teste_rpa_qa_b3_06_descida_com_ciclo_termina_e_lista_cada_pasta_uma_vez | Descida com ciclo termina e lista cada pasta uma unica vez | |
| teste_rst01_rev_valido_restaura_e_mostra_como_desfazer | Revisao valida e restaurada e a saida mostra como desfazer | TC-RST-01 |
| teste_rst02_rev_malformado_e_uso_invalido_sem_rede | Revisao malformada e uso invalido, sem chamada de rede | TC-RST-02 |
| teste_rst03_rev_e_antes_de_juntos_sao_uso_invalido | `--rev` e `--antes-de` juntos sao uso invalido | TC-RST-03 |
| teste_rst04_arquivo_vivo_sem_selecao_e_uso_invalido | Arquivo vivo sem selecao de revisao e uso invalido | TC-RST-04 |
| teste_rst05_rev_de_outro_arquivo_e_2_sem_restore_atravessando_paginas | Revisao de outro arquivo, buscada atraves das paginas, sai com 2 sem chamar `restore` | TC-RST-05 |
| teste_rst06_antes_de_escolhe_a_mais_recente_ate_o_fim_do_dia_atravessando_pagina | `--antes-de` escolhe a revisao mais recente ate o fim do dia, atravessando paginas | TC-RST-06 |
| teste_rst07_antes_de_anterior_a_toda_revisao_e_4 | `--antes-de` anterior a toda revisao sai com codigo 4 | TC-RST-07 |
| teste_rst08_datas_invalidas_sao_uso_invalido_sem_rede | Datas invalidas em `--antes-de` sao uso invalido, sem rede | TC-RST-08 |
| teste_rst09_arquivo_apagado_sem_selecao_restaura_a_ultima | Arquivo apagado sem selecao restaura a ultima revisao | TC-RST-09 |
| teste_rst10_rev_igual_ao_vigente_e_ja_atual_sem_restore | Revisao igual a vigente informa que ja esta atual e nao chama `restore` | TC-RST-10 |
| teste_rst11_dry_run_so_le | `--dry-run` de `restaurar` apenas le, sem escrita | TC-RST-11 |
| teste_rst12_fora_da_raiz_e_13_sem_chamada | Caminho fora da raiz e recusado com codigo 13 sem chamada | TC-RST-12 |
| teste_rst13_erros_do_restore_pela_taxonomia | Erros de `restore` seguem a taxonomia de codigos de saida | TC-RST-13 |
| teste_rst14_json_e_null_coerentes_com_info | `--json` e `--null` de `restaurar` sao coerentes com os de `info` | TC-RST-14 |
| teste_rst_raiz_e_pasta_viva_sao_uso_invalido | Restaurar a raiz ou uma pasta viva e uso invalido | |
| teste_rvs01_lista_tres_revisoes_da_mais_recente_com_campos_de_info | `revisoes` lista tres revisoes da mais recente para a mais antiga, com os campos de `info` | TC-RVS-01 |
| teste_rvs02_limite_fora_da_faixa_e_uso_invalido_sem_rede | Limite fora da faixa permitida e uso invalido, sem rede | TC-RVS-02 |
| teste_rvs03_limite_explicito_no_corpo_padrao_dez | O limite explicito vai no corpo da chamada e o padrao e dez | TC-RVS-03 |
| teste_rvs04_por_id_envia_modo_id_e_omite_revisao_fora_da_raiz | Consulta por id envia o modo id e omite revisao cujo caminho esta fora da raiz | TC-RVS-04 |
| teste_rvs05_fora_da_raiz_e_caminho_recusado_sem_chamada | Caminho fora da raiz e recusado sem chamada | TC-RVS-05 |
| teste_rvs06_arquivo_apagado_lista_com_apagado_sim_e_data | Arquivo apagado lista revisoes com `apagado: sim` e a data | TC-RVS-06 |
| teste_rvs07_pasta_e_uso_invalido_com_orientacao_e_inexistente_e_4 | Pasta e uso invalido com orientacao; caminho inexistente sai com 4 | TC-RVS-07 |
| teste_rvs08_null_preserva_nome_com_quebra_e_so_leitura | `--null` preserva nome com quebra de linha e o comando so le | TC-RVS-08 |


## `tests/integracao/reter_test.sh`

- **Alvo:** `bin/dbx reter` (alias `retain`): `commands/reter.sh`, `lib/retencao.sh`, `lib/filtro.sh`; plano, lixeira e guarda por identidade
- **Modulo:** `reter_test`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-6-retencao`)
- **Regras de origem:** F-10; RF-93..100; TC-RTA; TC-RTS; TC-RTP; TC-RTC; TC-RTG; TC-RTX; TC-RTO; TC-CPL-11; TC-DOC-05; TC-TST-09; DIV-130..147; DIV-158..168; log `docs/prompts/2026-10-20_2010_backlog-fase-6-retencao.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` por regras (endpoint, filtro do corpo, codigo, arquivo; registra `chamadas`; cabecalho `Date`; `@PATH@`; sinal ao `dbx`; regra `uma` atomica), duplo de `sleep` que so registra a espera, duplos de `date`; listagens sinteticas em diretorio temporario; copias mutantes de `lib/retencao.sh` e `commands/reter.sh` (os casos `mutante` esperam reprovacao)
- **Comando:** `bash tests/run.sh tests/integracao/reter_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_rta01_forma_minima_e_aliases_dao_o_mesmo_plano | A forma minima e os aliases de `reter` produzem o mesmo plano | TC-RTA-01 |
| teste_rta02_pasta_ausente_dupla_ou_relativa_e_uso_invalido_sem_rede | Pasta ausente, duplicada ou relativa e uso invalido (2) e sai sem chamar a rede | TC-RTA-02 |
| teste_rta03_padrao_ausente_vazio_ou_repetido_e_uso_invalido | Padrao ausente, vazio ou repetido e uso invalido | TC-RTA-03 |
| teste_rta04_politica_ausente_dupla_ou_repetida_e_uso_invalido | Politica ausente, dupla ou repetida e uso invalido | TC-RTA-04 |
| teste_rta05_rta06_valores_fora_da_faixa_sem_rede_e_limites_aceitos | Valores fora da faixa de `--manter` e `--dias` sao recusados sem rede e os limites sao aceitos | TC-RTA-05; TC-RTA-06 |
| teste_rta07_padrao_malformado_e_2_citado_e_aceitos | Padrao malformado sai 2 citando o padrao; os bem formados sao aceitos | TC-RTA-07 |
| teste_rta08_opcoes_de_outros_comandos_sao_recusadas | Opcoes que pertencem a outros comandos sao recusadas em `reter` | TC-RTA-08 |
| teste_rta09_padrao_e_dado_nunca_codigo | Padrao com metacaracteres de shell e tratado como dado e nunca executado | TC-RTA-09 |
| teste_rta10_uso_vem_antes_do_confinamento_e_toda_recusa_e_sem_rede | O erro de uso e avaliado antes do confinamento e toda recusa ocorre sem rede | TC-RTA-10 |
| teste_rts01_corpo_da_listagem_e_um_nivel_so | A listagem pedida e de um nivel apenas (sem recursao) | TC-RTS-01 |
| teste_rts02_arquivos_de_subpasta_nunca_sao_candidatos | Arquivos de subpasta nunca entram como candidatos | TC-RTS-02 |
| teste_rts03_pasta_apagado_e_tag_desconhecida_sao_ignorados | Pasta, item apagado e `.tag` desconhecida sao ignorados | TC-RTS-03 |
| teste_rts04_tres_paginas_e_nenhum_delete_antes_da_ultima | Com tres paginas, nenhum `delete_v2` ocorre antes da ultima pagina ser lida | TC-RTS-04 |
| teste_rts05_falha_na_pagina_2_sai_pela_classe_sem_delete | Falha na pagina 2 sai pelo codigo da classe do erro sem nenhum delete | TC-RTS-05 |
| teste_rts06_reset_no_continue_sai_14_sem_delete | `reset` no `list_folder/continue` sai 14 sem delete | TC-RTS-06 |
| teste_rts07_cursor_repetido_e_pagina_vazia | Cursor repetido ou pagina vazia com `has_more` derruba a execucao sem delete | TC-RTS-07 |
| teste_rts07_teto_de_1000_paginas | Acima de 1000 paginas a listagem e abortada sem delete | TC-RTS-07 |
| teste_rts08_pagina_malformada_ou_com_chave_repetida_e_10 | Pagina malformada ou com chave repetida sai 10 | TC-RTS-08 |
| teste_rts09_listagem_incoerente_derruba_a_execucao_inteira | Um item incoerente na listagem derruba a execucao inteira, sem apagar os demais | TC-RTS-09 |
| teste_rts09_mutante_que_pula_o_item_incoerente_reprova | Mutante que apenas pula o item incoerente e reprovado pelo teste | TC-RTS-09 |
| teste_rts10_sem_caixa_e_licao_da_fase_4 | O casamento do padrao e sem diferenca de caixa, como na fase 4 | TC-RTS-10 |
| teste_rts11_pasta_inexistente_e_4_e_arquivo_e_2 | Pasta inexistente sai 4 e um arquivo no lugar da pasta sai 2 | TC-RTS-11 |
| teste_rts12_diretorio_de_estado_intocado_nos_tres_modos | O diretorio de estado nao e alterado em nenhum dos tres modos | TC-RTS-12 |
| teste_rtp01_rtx01_manter_2_de_5_apaga_3_do_mais_velho_ao_mais_novo | `--manter 2` com cinco itens apaga os tres mais velhos, do mais velho ao mais novo | TC-RTP-01; TC-RTX-01 |
| teste_rtp04_client_modified_e_size_nao_participam | `client_modified` e `size` nao participam da ordem de retencao | TC-RTP-04 |
| teste_rtp05_server_modified_invalido_em_um_candidato_e_10_sem_delete | `server_modified` invalido em um candidato sai 10 sem delete | TC-RTP-05 |
| teste_rtp07_rtp08_dias_com_o_relogio_real | `--dias` usa o relogio real e apaga so o que passou do limite | TC-RTP-07; TC-RTP-08 |
| teste_rtp11_zero_candidatos_sai_0_com_aviso | Sem candidatos sai 0 com aviso | TC-RTP-11 |
| teste_rtc01_rtc02_rtc03_sem_confirmar_e_com_dry_run_nada_e_apagado | Sem `--confirmar`, ou com `--dry-run`, nada e apagado | TC-RTC-01..03 |
| teste_rtc01_mutantes_da_confirmacao_reprovam | Mutantes que enfraquecem a exigencia de `--confirmar` sao reprovados | TC-RTC-01 |
| teste_rtc04_um_so_plano_nos_tres_modos | O plano e o mesmo no modo normal, simulado e confirmado | TC-RTC-04 |
| teste_rtc05_com_terminal_nao_pergunta | Mesmo com terminal, o comando nunca pergunta confirmacao | TC-RTC-05 |
| teste_rtc06_linhas_na_ordem_e_fora_do_padrao_so_contado | As linhas saem na ordem do plano e o que esta fora do padrao so e contado | TC-RTC-06 |
| teste_rtc07_padrao_amplo_avisa_nos_tres_modos | Padrao amplo demais gera aviso nos tres modos | TC-RTC-07 |
| teste_rtc08_nenhum_plano_gravado_em_disco | Nenhum plano e gravado em disco | TC-RTC-08 |
| teste_rtg01_fora_da_raiz_e_controle_sao_13_sem_chamada | Caminho fora da raiz ou com controle sai 13 sem chamada de rede | TC-RTG-01 |
| teste_rtg02_a_raiz_remota_e_a_raiz_da_conta_sao_alvo | A raiz remota e a raiz da conta sao alvos validos | TC-RTG-02 |
| teste_rtg03_mutante_sem_a_conferencia_da_listagem_ainda_e_barrado_pela_guarda | Mutante sem a conferencia da listagem ainda e barrado pela guarda por identidade | TC-RTG-03 |
| teste_rtg04_pasta_fora_do_ascii_com_dobra_diferente_falha_fechada | Pasta fora do ASCII cuja dobra de caixa difere falha fechada | TC-RTG-04 |
| teste_rtg05_name_diferente_do_path_lower_e_10 | `name` diferente do fim de `path_lower` sai 10 | TC-RTG-05 |
| teste_rtg06_rtg11_todo_delete_leva_path_lower_e_parent_rev_listados | Todo `delete_v2` leva o `path_lower` e o `parent_rev` listados | TC-RTG-06; TC-RTG-11 |
| teste_rtg06_mutante_sem_parent_rev_reprova | Mutante que omite `parent_rev` e reprovado | TC-RTG-06 |
| teste_rtg07_parent_rev_divergente_e_conflito_e_os_demais_seguem | `parent_rev` divergente e conflito do item e os demais seguem | TC-RTG-07 |
| teste_rtg08_estado_envenenado_nao_muda_o_plano_nem_os_deletes | Estado local adulterado nao altera plano nem deletes | TC-RTG-08 |
| teste_rtg09_mutante_que_zera_o_n_nunca_apaga_o_primeiro | Mutante que zera o contador nunca apaga o primeiro da ordem (o item mais novo) | TC-RTG-09 |
| teste_rtg10_resposta_2xx_incoerente_do_delete_para_antes_do_proximo | Resposta 2xx incoerente de um delete interrompe antes do proximo | TC-RTG-10 |
| teste_rtg12_auditoria_estatica_sem_rota_destrutiva_alheia | Auditoria do texto: nenhuma rota destrutiva alem de `delete_v2` e usada | TC-RTG-12 |
| teste_rtx02_permissao_no_segundo_segue_e_sai_14 | Permissao negada no segundo delete segue com os demais e sai 14 | TC-RTX-02 |
| teste_rtx03_autenticacao_taxa_e_rede_esgotados_param | Autenticacao, taxa e rede esgotadas param a execucao | TC-RTX-03 |
| teste_rtx04_rtx05_ja_ausente_e_retentativa | Item ja ausente conta como feito e a retentativa nao duplica o delete | TC-RTX-04; TC-RTX-05 |
| teste_rtx06_too_many_write_operations_e_retry_after | `too_many_write_operations` respeita o `Retry-After` antes de retomar | TC-RTX-06 |
| teste_rtx07_artefato_novo_durante_a_execucao_nunca_e_apagado | Artefato criado durante a execucao nunca e apagado | TC-RTX-07 |
| teste_rtx08_duas_execucoes_simultaneas | Duas execucoes simultaneas nao apagam o mesmo item duas vezes | TC-RTX-08 |
| teste_rtx09_sinal_entre_dois_deletes_sai_14_sem_proximo_delete | Sinal recebido entre dois deletes sai 14 sem o proximo delete | TC-RTX-09 |
| teste_rtx10_autenticacao_na_renovacao_antes_de_qualquer_delete | Falha de autenticacao na renovacao ocorre antes de qualquer delete | TC-RTX-10 |
| teste_rtx11_rtx12_sem_segredo_e_com_a_recuperacao | Nenhum segredo vaza na saida e a mensagem aponta a recuperacao pela lixeira | TC-RTX-11; TC-RTX-12 |
| teste_div134_relogio_divergente_sai_3_sem_delete | Relogio local divergente do servidor sai 3 sem delete | DIV-134 |
| teste_div134_date_ausente_ou_malformado_com_dias_e_10 | `Date` ausente ou malformado com `--dias` sai 10 | DIV-134 |
| teste_div134_mutante_sem_a_conferencia_do_relogio_reprova | Mutante sem a conferencia do relogio e reprovado | DIV-134 |
| teste_p04_mutante_sem_a_validacao_de_server_modified_reprova | Mutante sem a validacao de `server_modified` e reprovado | |
| teste_p04_mutante_sem_o_cursor_repetido_reprova | Mutante sem a deteccao de cursor repetido e reprovado | |
| teste_p02_mutantes_de_selecao_reprovam | Mutantes da regra de selecao de candidatos sao reprovados | |
| teste_rto01_rto05_texto_com_cabecalho_linhas_e_resumo | Saida em texto traz cabecalho, uma linha por item e resumo | TC-RTO-01; TC-RTO-05 |
| teste_rto02_json_com_a_versao_do_contrato | Saida `--json` traz a versao do contrato e os campos do plano | TC-RTO-02 |
| teste_rto03_rto04_null_intacto_e_texto_escapado | Com `--null` o nome sai intacto; em texto sai escapado | TC-RTO-03; TC-RTO-04 |
| teste_rto06_avisos_so_em_stderr | Avisos saem so em stderr, nunca em stdout | TC-RTO-06 |
| teste_cpl11_ajuda_e_autocompletar_coincidem | As opcoes da ajuda de `reter` coincidem com as do autocompletar | TC-CPL-11 |
| teste_doc05_ajuda_e_readme_trazem_as_frases | Ajuda e README trazem as frases exigidas sobre `reter` | TC-DOC-05 |
| teste_div158_path_lower_repetido_sai_10_sem_delete | `path_lower` repetido na listagem sai 10 sem delete, protegendo o item que fica | DIV-158 |
| teste_div158_mutantes_das_tres_barreiras | Mutantes das tres barreiras contra repeticao sao reprovados | DIV-158 |
| teste_div159_ponto_e_ponto_ponto_derrubam_a_listagem | Nome `.` ou `..` na listagem derruba a execucao antes de qualquer exclusao | DIV-159 |
| teste_div159_mutante_sem_a_conferencia_de_normalizacao_reprova | Mutante sem a conferencia de normalizacao e reprovado | DIV-159 |
| teste_div160_relogio_conferido_contra_a_ultima_pagina | O relogio e conferido contra o `Date` da ultima pagina | DIV-160 |
| teste_div160_mutante_que_le_so_a_primeira_pagina_reprova | Mutante que le o `Date` so da primeira pagina e reprovado | DIV-160 |
| teste_div161_chave_unicode_nas_barreiras_da_listagem | Chaves Unicode equivalentes sao tratadas como a mesma nas barreiras da listagem | DIV-161 |
| teste_div161_mutantes_reprovam | Mutantes das barreiras com chave Unicode sao reprovados | DIV-161 |
| teste_div164_marca_combinante_derruba_a_listagem | Marca combinante que torna nomes equivalentes derruba a listagem | DIV-164 |
| teste_div164_mutantes_reprovam | Mutantes da barreira de marca combinante sao reprovados | DIV-164 |
| teste_div167_id_e_rev_unicos_na_listagem | `id` e `rev` repetidos na listagem derrubam a execucao | DIV-167 |
| teste_div167_mutantes_a_guarda_segura_sozinha | Com as demais barreiras removidas, a guarda por identidade sozinha ainda segura o delete | DIV-167 |
| teste_div168_utf8_invalido_derruba_a_listagem | Nome com UTF-8 invalido derruba a listagem antes de qualquer exclusao | DIV-168 |
| teste_div168_mutante_sem_a_validacao_reprova | Mutante sem a validacao de UTF-8 e reprovado | DIV-168 |
| teste_marcas_de_mutacao_existem | As marcas usadas pelos mutantes existem no fonte (evita mutante que nao muta nada) | |
| teste_tst09_mapa_de_modulos_tem_as_entradas | O mapa de modulos traz as entradas dos testes de retencao | TC-TST-09 |


## `tests/integracao/retomada_download_test.sh`

- **Alvo:** `bin/dbx download` retomado entre execucoes (`Range`), `--no-resume`, `diagnostico` e `unlink`; `commands/download.sh`, `lib/cmd.sh`, `lib/state.sh`
- **Modulo:** retomada_download
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-7a-retomada`)
- **Regras de origem:** F-03; RF-102, RF-104 a RF-108; TC-RMD-01..15, TC-RMO-01, 02, 04, 05, TC-RMC-01, 06, TC-RML-05..07, TC-RMS-06, TC-DBG-13..15; DIV-176 a DIV-178, DIV-183, DIV-185, DIV-294; log `docs/prompts/2026-10-20_2315_backlog-fase-7a-retomada.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` que segue o contrato medido do cliente real para `continue-at` (anexa ao destino, status 33 sem escrita em 200 ou 206 de outro inicio, 416 com status 0); arquivos `.part` e registros de retomada sinteticos; mutantes aplicados por copia do codigo; sem rede
- **Comando:** `bash tests/run.sh tests/integracao/retomada_download_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_c2_fifo_no_estado_nao_pendura_diagnostico_nem_unlink | FIFO no lugar de um registro de estado nao pendura `diagnostico` nem `unlink` | |
| teste_c2_mutante_que_descarta_sem_a_barreira_deixa_o_orfao | Mutante que descarta o registro sem a barreira do `.part` deixa o `.part` orfao e e reprovado | |
| teste_c2_mutante_sem_a_conferencia_de_arquivo_regular_pendura | Mutante sem a conferencia de arquivo regular pendura no FIFO e e reprovado | |
| teste_c2_registro_de_outro_remoto_descartado_leva_o_part_pela_barreira | Registro de outro remoto e descartado e leva o `.part` junto pela barreira de inode | |
| teste_prg_download_retomado_comeca_no_percentual_do_part | Download retomado comeca o progresso no percentual ja contido no `.part` | DIV-294 |
| teste_rmc01_dois_downloads_simultaneos_um_retoma | Dois downloads simultaneos do mesmo destino: so um retoma o `.part` | TC-RMC-01 |
| teste_rmd01_rmd02_interrompido_e_retomado_por_range_com_rev_fixa | Download interrompido e retomado por `Range` com a revisao fixada, resultando em arquivo identico | TC-RMD-01, TC-RMD-02 |
| teste_rmd03_rmd04_rev_mudou_apaga_o_part_pela_barreira_e_baixa_a_nova | Se a revisao remota mudou, o `.part` e apagado pela barreira e a nova versao e baixada do inicio | TC-RMD-03, TC-RMD-04 |
| teste_rmd05_mutante_sem_a_barreira_de_inode_anexa_ao_arquivo_do_usuario | Mutante sem a barreira de inode anexaria ao arquivo do usuario e e reprovado | TC-RMD-05 |
| teste_rmd05_rmd06_part_trocado_por_ligacao_ou_outro_inode_nao_e_tocado | `.part` trocado por ligacao ou por outro inode nao e tocado | TC-RMD-05, TC-RMD-06 |
| teste_rmd07_200_a_um_pedido_de_faixa_nunca_e_anexado | Resposta 200 a um pedido de faixa nunca e anexada ao `.part` | TC-RMD-07 |
| teste_rmd08_206_de_outro_inicio_outro_total_ou_outra_rev_recomeca | 206 com outro inicio, outro total ou outra revisao faz recomecar do zero | TC-RMD-08 |
| teste_rmd08_mutante_que_nao_confere_o_content_range_aceita_o_total_errado | Mutante que nao confere o `Content-Range` aceitaria o total errado e e reprovado | TC-RMD-08 |
| teste_rmd09_416_com_o_part_completo_confere_e_troca_sem_corpo | 416 com o `.part` ja completo confere o hash e publica o arquivo sem corpo de resposta | TC-RMD-09 |
| teste_rmd10_hash_divergente_recomeca_uma_vez_e_de_novo_sai_11_sem_trocar | Hash divergente recomeca uma vez e, divergindo de novo, sai com 11 sem trocar o arquivo | TC-RMD-10 |
| teste_rmd10_mutante_que_troca_antes_do_hash_reprova | Mutante que publica o arquivo antes de conferir o hash e reprovado | TC-RMD-10 |
| teste_rmd11_arquivo_do_usuario_com_nome_parecido_fica_intacto | Arquivo do usuario com nome parecido com o de um `.part` fica intacto | TC-RMD-11 |
| teste_rmd12_alvo_novo_tem_o_modo_do_umask | O arquivo novo publicado tem o modo determinado pelo umask do usuario | TC-RMD-12 |
| teste_rmd13_part_maior_que_o_esperado_nao_e_usado | `.part` maior que o tamanho esperado nao e usado na retomada | TC-RMD-13 |
| teste_rmd14_mutante_sem_a_conferencia_pelo_descritor_anexa_ao_trocado | Mutante sem a conferencia pelo descritor anexaria ao arquivo trocado e e reprovado | TC-RMD-14 |
| teste_rmd14_nome_trocado_entre_a_conferencia_e_a_abertura_nada_anexa | Nome trocado entre a conferencia e a abertura do `.part`: nada e anexado | TC-RMD-14 |
| teste_rmd15_sinal_depois_do_registro_deixa_o_part_e_antes_remove | Sinal apos gravar o registro deixa o `.part` para a retomada; antes do registro, remove-o | TC-RMD-15 |
| teste_rml05_unlink_apaga_o_part_que_passa_e_lista_o_que_nao_passa | `unlink` apaga o `.part` que passa na barreira e lista o que nao passa | TC-RML-05 |
| teste_rml05_unlink_com_trava_de_registro_viva_recusa_sem_apagar | `unlink` com trava de registro viva recusa sem apagar nada | TC-RML-05 |
| teste_rml06_rml07_rmc06_diagnostico_lista_so_le_e_nao_cria | `diagnostico` lista os registros de retomada, apenas le e nao cria nada | TC-RML-06, TC-RML-07, TC-RMC-06 |
| teste_rmo01_rmo02_rmo04_fora_do_alcance_e_recusas_antes_do_part | Casos fora do alcance da retomada e recusas ocorrem antes de qualquer `.part` ser criado | TC-RMO-01, TC-RMO-02, TC-RMO-04 |
| teste_rmo05_sem_retomada_recebe_como_antes_e_nao_toca_o_registro | `--no-resume` recebe o arquivo como antes e nao toca o registro de retomada | TC-RMO-05 |
| teste_rms06_remoto_que_sumiu_limpa_registro_e_part_e_sai_4 | Remoto que sumiu limpa registro e `.part` e sai com codigo 4 | TC-RMS-06 |
| teste_tc_dbg_13_retomada_do_part_traz_a_faixa_e_part_bytes_no_plano_e_na_linha_http | Com `--debug`, a retomada mostra a faixa e `part_bytes` no plano e na linha HTTP | TC-DBG-13 |
| teste_tc_dbg_13_rev_mudou_descarta_com_motivo_hash_remoto_mudou | Com `--debug`, revisao mudada descarta o `.part` com o motivo `hash_remoto_mudou` | TC-DBG-13 |
| teste_tc_dbg_14_servidor_que_ignora_a_faixa_reinicia_com_motivo | Com `--debug`, servidor que ignora a faixa faz reiniciar com o motivo indicado | TC-DBG-14 |
| teste_tc_dbg_15_hash_divergente_aparece_antes_do_erro_11 | Com `--debug`, o hash divergente aparece na saida antes do erro com codigo 11 | TC-DBG-15 |


## `tests/integracao/retomada_upload_test.sh`

- **Alvo:** `bin/dbx upload` retomado entre execucoes (`commands/upload.sh`, `lib/transfer.sh`, `lib/state.sh`, registro `retomada-*`)
- **Modulo:** retomada_upload
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-7a-retomada`)
- **Regras de origem:** F-03; RF-101..RF-109; DIV-171..DIV-190; TC-RMU-01..16; TC-RME-02, 12, 14; TC-RMO-01..03, 05..11; TC-RMC-01, 04, 05; TC-RMS-01..06; TC-DBG-08..12, 24 (casos de debug); log `docs/prompts/2026-10-20_2315_backlog-fase-7a-retomada.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de `curl` que e servidor de sessao com estado (sessoes em `sess/`, SHA-256 por parte, `content_hash` calculado sobre as partes recebidas), roteiro de acoes por chamada (`SINAL:NOME`, `KILL`, `ACEITA_E_KILL`, `NOT_FOUND`, `CLOSED`, `TOO_LARGE`, `OFFSET:n`, `HASH_ERRADO`, `CRESCE`), arquivo de origem de 150 MiB mais 3 bytes em partes de 4 MiB, sentinelas sinteticas, `XDG_STATE_HOME` temporario; sem rede
- **Comando:** `bash tests/run.sh tests/integracao/retomada_upload_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_rmc01_dois_uploads_simultaneos_um_retoma_o_outro_vai_do_zero | Dois uploads simultaneos do mesmo par: um retoma pelo registro e o outro vai do zero, sem corromper. | TC-RMC-01 |
| teste_rmc01_mutante_sem_trava_de_registro_deixa_os_dois_lerem | Mutante sem a trava de registro deixa os dois processos lerem o mesmo registro e e reprovado pelo teste. | TC-RMC-01 |
| teste_rmc04_sync_e_upload_do_mesmo_par_nao_se_esperam | Sync e upload do mesmo par nao se esperam mutuamente nem se bloqueiam. | TC-RMC-04 |
| teste_rmc05_verificar_e_dry_run_deixam_o_estado_byte_a_byte | `verificar` e `--dry-run` deixam o diretorio de estado identico byte a byte. | TC-RMC-05 |
| teste_rme02_rmo09_sentinelas_e_session_id_fora_da_saida_e_do_registro | Sentinelas de segredo e session_id nao aparecem na saida nem no texto do registro. | TC-RME-02; TC-RMO-09 |
| teste_rme12_diretorio_de_estado_sem_escrita_segue_sem_retomada | Diretorio de estado sem escrita nao impede o upload: segue sem retomada. | TC-RME-12 |
| teste_rme14_registro_apagado_a_mao_so_muda_o_custo | Registro apagado a mao muda so o custo (envio do zero), nao o resultado. | TC-RME-14 |
| teste_rme_registro_de_outra_conta_e_descartado_e_o_mutante_que_o_aceita_reprova | Registro de outra conta e descartado; o mutante que o aceita e reprovado. | |
| teste_rme_registro_invalido_descarta_com_um_aviso_e_conclui_igual | Registro invalido e descartado com um unico aviso e o upload conclui com o mesmo resultado. | |
| teste_rmo01_rmo02_fora_do_alcance_nao_cria_nem_le_registro | Envio fora do alcance da retomada (pequeno ou simples) nao cria nem le registro. | TC-RMO-01; TC-RMO-02 |
| teste_rmo03_dispensa_por_content_hash_igual_remove_o_registro_sem_sessao | Arquivo dispensado por `content_hash` igual remove o registro sem abrir sessao. | TC-RMO-03 |
| teste_rmo03_rev_decide_antes_e_o_finish_leva_o_rev_desta_execucao | O rev e decidido antes do envio e o finish leva o rev desta execucao. | TC-RMO-03 |
| teste_rmo05_rmo06_sem_retomada_e_no_resume_nao_leem_nem_tocam_o_registro | `--sem-retomada` e `--no-resume` nao leem nem tocam o registro. | TC-RMO-05; TC-RMO-06 |
| teste_rmo07_opcao_em_outro_comando_e_uso_invalido | A opcao de retomada em outro comando e uso invalido. | TC-RMO-07 |
| teste_rmo08_campos_em_texto_json_e_null_e_resto_da_saida_igual | Os campos de retomada aparecem em texto, `--json` e `--null` e o resto da saida e igual. | TC-RMO-08 |
| teste_rmo10_ajuda_e_autocompletar_trazem_a_opcao_e_as_frases | Ajuda e autocompletar trazem a opcao e as frases da retomada. | TC-RMO-10 |
| teste_rmo11_codigos_iguais_com_e_sem_registro_previo | Os codigos de saida sao os mesmos com e sem registro previo. | TC-RMO-11 |
| teste_rms01_a_03_int_term_hup_entre_partes_deixam_registro_e_soltam_a_trava | INT, TERM e HUP entre partes deixam o registro e soltam a trava. | TC-RMS-01..03 |
| teste_rms04_kill_9_e_a_seguinte_conclui_igual_retomando_a_trava_orfa | `kill -9` deixa trava orfa e a execucao seguinte a retoma e conclui igual. | TC-RMS-04 |
| teste_rms05_kill_9_depois_do_finish_publicado_a_seguinte_dispensa | `kill -9` depois do finish publicado: a seguinte dispensa o envio por hash igual. | TC-RMS-05 |
| teste_rms06_falha_definitiva_e_sucesso_nao_deixam_registro | Falha definitiva e sucesso nao deixam registro de retomada. | TC-RMS-06 |
| teste_rmu01_rmu02_interrompido_na_parte_4_retoma_do_confirmado_sem_reenviar | Upload interrompido na parte 4 retoma do deslocamento confirmado sem reenviar as partes aceitas. | TC-RMU-01; TC-RMU-02 |
| teste_rmu03_falha_ao_gravar_o_registro_segue_sem_retomada | Falha ao gravar o registro nao interrompe o envio: segue sem retomada. | TC-RMU-03 |
| teste_rmu04_ctime_diferente_com_mtime_restaurado_recomeca_do_zero | ctime diferente com mtime restaurado: o envio recomeca do zero. | TC-RMU-04 |
| teste_rmu05_mutante_que_retoma_so_pela_identidade_reprova | Mutante que retoma so pela identidade do arquivo (sem conferir o prefixo) e reprovado. | TC-RMU-05 |
| teste_rmu05_prefixo_alterado_com_stat_forjado_reprova_antes_do_primeiro_append | Prefixo alterado com stat forjado e reprovado antes do primeiro `append_v2`. | TC-RMU-05 |
| teste_rmu06_rmu08_correct_offset_fora_do_aceito_descarta_e_recomeca_do_zero | `correct_offset` fora do aceito descarta o registro e recomeca do zero. | TC-RMU-06; TC-RMU-08 |
| teste_rmu07_mutante_que_aceita_o_avanco_sem_conferir_a_parte_reprova | Mutante que aceita o avanco do servidor sem conferir a parte em voo e reprovado. | TC-RMU-07 |
| teste_rmu07_parte_em_voo_relida_diferente_recomeca_do_zero | Parte em voo relida com SHA diferente recomeca do zero. | TC-RMU-07 |
| teste_rmu07_servidor_no_confirmado_mais_a_parte_em_voo_com_sha_igual_segue | Servidor no confirmado mais a parte em voo com SHA igual: a retomada segue. | TC-RMU-07 |
| teste_rmu08_confirmado_mais_4_mib_sem_parte_em_voo_gravada_recomeca | Servidor a confirmado mais 4 MiB sem parte em voo gravada: recomeca. | TC-RMU-08 |
| teste_rmu09_not_found_no_primeiro_append_recomeca_uma_vez_sem_codigo_4 | `not_found` no primeiro append recomeca uma unica vez, sem sair com codigo 4. | TC-RMU-09 |
| teste_rmu09_segundo_not_found_na_sessao_nova_tem_a_classe_de_hoje | Segundo `not_found` na sessao nova tem a classe de erro de hoje. | TC-RMU-09 |
| teste_rmu10_closed_no_append_e_lookup_failed_no_finish_recomecam | `closed` no append e `lookup_failed` no finish recomecam o envio. | TC-RMU-10 |
| teste_rmu11_too_large_e_definitivo_com_codigo_10 | `too_large` e definitivo e sai com codigo 10. | TC-RMU-11 |
| teste_rmu12_finish_leva_o_modo_desta_execucao | O finish leva o modo de escrita desta execucao. | TC-RMU-12 |
| teste_rmu13_hash_do_finish_divergente_sai_11_sem_reenvio_nem_exclusao | Hash do finish divergente sai com 11, sem reenvio nem exclusao. | TC-RMU-13 |
| teste_rmu14_arquivo_que_cresce_durante_o_envio_retomado_aborta_e_remove_o_registro | Arquivo que cresce durante o envio retomado aborta e remove o registro. | TC-RMU-14 |
| teste_rmu15_na_retomada_o_arquivo_e_lido_uma_vez | Na retomada o arquivo e lido uma unica vez. | TC-RMU-15 |
| teste_tc_dbg_08_09_24_upload_em_sessao_real_tem_modalidade_blocos_e_nao_vaza_a_sessao | Upload em sessao real emite modalidade e blocos no debug e nunca o id da sessao. | TC-DBG-08; TC-DBG-09; TC-DBG-24 |
| teste_tc_dbg_10_retomada_encontrada_traz_o_deslocamento_e_nao_o_id_da_sessao | Retomada encontrada emite o deslocamento no debug e nao o id da sessao. | TC-DBG-10 |
| teste_tc_dbg_11_sessao_recusada_descarta_a_retomada_com_motivo_do_vocabulario | Sessao recusada descarta a retomada com motivo do vocabulario no debug. | TC-DBG-11 |
| teste_tc_dbg_12_sem_retomada_traz_o_motivo_sem_retomada | Upload sem retomada emite o motivo `sem-retomada` no debug. | TC-DBG-12 |


## `tests/integracao/sync_blocos_test.sh`

- **Alvo:** `bin/dbx sync` nos dois sentidos e `download` de pasta em ciclos cortados por diretorio (`commands/sync.sh`, `lib/sync.sh`, `lib/lote.sh`, `lib/state.sh`): exclusao, origem vazia, colisao de caixa, `--dry-run`, falhas, cursor e retrato, `--paralelo` e `--debug`
- **Modulo:** `sync_blocos` (filtro do mapa de modulos)
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `sync-em-blocos`)
- **Regras de origem:** F-101; RF-186..RF-197; TC-BLC-nn (secao 5.24 do escopo); log `docs/prompts/2026-10-31_1200_sync-em-blocos.md`; registro `docs/reviews/2026-10-31-1200-registro-sync-em-blocos.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` que responde a listagem por diretorio (`$base/ls/<caminho>`), registra chamadas e corpos de requisicao; credencial, raiz local e estado temporarios por caso; dado sintetico; sem rede; os casos de modo 000 nao rodam como root
- **Comando:** `bash tests/run.sh tests/integracao/sync_blocos_test.sh`
- **Observacoes:** Etapa 2 de F-101. O duplo foi alterado em `cursor_test.sh` e nas suites `qa_*` afetadas para responder `list_folder` nao recursivo e `get_latest_cursor`.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_blc_enviar_forma_ciclos_por_diretorio_e_consulta_so_nao_recursivo | `sync --enviar --bloco 2` forma dois ciclos por diretorio, envia os cinco arquivos sem omissao nem duplicacao, mostra o progresso por ciclo, nao faz listagem recursiva e consulta o destino so nos diretorios do ciclo. | RF-187(d); RF-189(a) |
| teste_blc_uma_arvore_que_cabe_em_um_ciclo_nao_muda_o_resultado | Arvore que cabe em um ciclo da o mesmo resultado de antes e a saida nao traz o campo `ciclos=` fora do `--json`. | RF-187 |
| teste_blc_receber_percorre_os_diretorios_remotos_nao_recursivamente | `sync --receber --bloco 2 --sem-cursor` recebe os quatro arquivos em dois ciclos, percorre os diretorios sem listagem recursiva e grava o arquivo do ciclo 2. | RF-187; RF-189(a) |
| teste_blc_download_de_pasta_usa_ciclos | `download` de pasta com `--bloco 2` e `--excluir` recebe os arquivos pela descida por diretorio (listagem nao recursiva, nenhuma recursiva). | RF-188; RF-189(a) |
| teste_blc_espelhar_apaga_so_em_diretorio_lido_inteiro_e_o_so_do_destino_depois_do_pai | `sync --enviar --espelhar --confirmar` em ciclos apaga o arquivo sobrante de diretorio lido inteiro e o conteudo do diretorio so do destino (2 exclusoes), emitindo `delete_v2`. | RF-190 |
| teste_blc_travessia_parcial_desliga_a_exclusao_na_execucao_inteira | Diretorio local ilegivel (modo 000) torna a travessia parcial: codigo diferente de zero, `exclusao_desabilitada` informado e nenhuma exclusao remota em ciclo algum (nao roda como root). | RF-41(a); RF-190 |
| teste_blc_origem_vazia_com_algo_a_apagar_e_recusa_14_sem_escrita | Origem sem arquivos com algo a apagar no destino (inclusive em diretorio so do destino) recusa com codigo 14 e nenhuma escrita. | RF-191 |
| teste_blc_colisao_de_caixa_no_diretorio_do_ciclo_recusa_antes_de_escrever | Dois arquivos que diferem so na caixa no mesmo diretorio recusam com `colisao de caixa` antes de qualquer escrita. | RF-194 |
| teste_blc_dry_run_percorre_os_ciclos_sem_escrever | `--dry-run` percorre todos os ciclos, mostra o plano do primeiro e do ultimo ciclo e nao escreve nada. | RF-196 |
| teste_blc_falha_de_arquivo_segue_e_falha_de_enumeracao_para | Falha de arquivo (500) segue e os dois ciclos sao tentados, com codigo diferente de zero; falha de enumeracao no ciclo 2 para a execucao com `ciclos_concluidos=1` e `ciclo_falho=2`. | RF-193 |
| teste_blc_download_de_arquivo_ignora_a_variavel_invalida_e_o_de_pasta_recusa_2_sem_escrita | `download` de arquivo unico ignora `DBX_BLOCO` invalida e baixa; o de pasta recusa com 2 nomeando a variavel assim que o alvo se revela pasta. | RF-186(e) |
| teste_blc_primeira_execucao_em_ciclos_grava_cursor_e_retrato_e_a_segunda_usa_o_delta | Primeira execucao `--receber` sem cursor roda em ciclos, grava cursor e retrato, so a chamada do cursor e recursiva e `get_latest_cursor` e pedido antes da primeira listagem de diretorio. | RF-192; RF-189(a) |
| teste_blc_retrato_dos_ciclos_e_o_da_varredura_recursiva_da_mesma_arvore | O retrato gravado pelos ciclos contem exatamente os mesmos caminhos da arvore remota esperada, sem repeticao nem omissao (esperado derivado da arvore). | TC-BLC-18 |
| teste_blc_dry_run_nao_grava_cursor_nem_retrato | `--dry-run` percorre os ciclos, mostra o plano e nao grava cursor nem retrato nem pede `get_latest_cursor`. | RF-112; RF-196 |
| teste_blc_falha_no_ciclo_k_nao_grava | Falha na enumeracao do ciclo 2 sai diferente de zero com `ciclo_falho=2` e nao grava cursor nem retrato. | RF-192 |
| teste_blc_leitura_parcial_nao_grava | Travessia local parcial (diretorio modo 000) sai diferente de zero e nao grava cursor nem retrato (nao roda como root). | RF-192; RF-41(a) |
| teste_blc_varredura_completa_forcada_roda_em_ciclos_e_regrava | `--varredura-completa` apos execucao com cursor roda em ciclos, pede novo cursor e regrava cursor e retrato. | RF-192 |
| teste_blc_receber_lista_cada_diretorio_remoto_exatamente_uma_vez | `--receber --sem-cursor` em dois ciclos lista cada diretorio remoto (`/r`, `/r/a`, `/r/b`) exatamente uma vez. | RF-188(b); RF-189 |
| teste_blc_receber_diretorio_maior_que_n_forma_ciclo_sozinho | Diretorio com mais de N arquivos forma ciclo sozinho no receber em fluxo: dois ciclos, quatro recebidos e cada diretorio listado uma vez. | RF-187(c) |
| teste_blc_receber_espelhar_apaga_ramo_local_que_so_existe_no_destino | `--receber --espelhar --confirmar` recebe os quatro arquivos e apaga o ramo local so do destino e o arquivo extra de diretorio lido inteiro (2 exclusoes), preservando a origem. | RF-190 |
| teste_blc_debug_traz_a_linha_bloco_no_resumo | `--debug` traz no resumo as linhas `bloco=2` e `ciclos=2`. | RF-197 |
| teste_blc_paralelo_2_fecha_o_ciclo_antes_do_proximo_e_da_o_mesmo_resultado | `--paralelo 2` da o mesmo resultado de N=1 e os tres downloads do ciclo 1 terminam antes da leitura de `/r/b` (barreira no fim do ciclo). | RF-195 |
| teste_blc_falha_sistemica_de_transferencia_para_e_a_de_arquivo_segue | Falha sistemica (403) em transferencia para a execucao (`ciclo_falho=1`, `falhas=1`, `ciclos_nao_tentados=1`, ciclo 2 nem lido, nada gravado); falha de arquivo (500) so segue. | RF-193; DIV-380 |


## `tests/integracao/sync_test.sh`

- **Alvo:** `bin/dbx sync` direcional (`commands/sync.sh`, `lib/sync.sh`, `lib/walk.sh`, `lib/transfer.sh`, `lib/state.sh`)
- **Modulo:** `commands/sync.sh`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD; sem log de prompt, commit de criacao `f8b9ed0` `feat(sync): sincronizacao direcional com a origem como autoridade`)
- **Regras de origem:** DP-27; DP-28; RF-37..RF-53; RF-54; RF-55(e); RF-57; RF-59; RF-64; RF-137; RNF-29; RNF-31; RSK-35; TC-FLH-01..04; TC-SIG-01..03; DIV-28 (ver cabecalho do arquivo)
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** arvores locais temporarias, listagem remota e metadados fornecidos pelo duplo de `curl` do arquivo (com `tests/support/lote_duplo.sh`), credencial sintetica; casos de sinal iniciam processo proprio
- **Comando:** `bash tests/run.sh tests/integracao/sync_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_origem_e_destino_sao_obrigatorios | Sem --origem ou --destino o sync sai com uso invalido | RF-53; DP-28 |
| teste_sentido_e_obrigatorio_e_mutuamente_exclusivo | O sentido (--enviar ou --receber) e obrigatorio e os dois juntos sao recusados | RF-53; DP-28 |
| teste_o_tipo_de_cada_lado_nunca_e_inferido_do_caminho | O tipo de cada lado vem do sentido, nunca do formato do caminho | DP-28 |
| teste_fluxo_e_recusado_nos_dois_lados | O traco de entrada padrao e recusado como origem e como destino | RF-53 |
| teste_carimbo_de_tempo_nao_participa_de_decisao | A diferenca de carimbo de tempo nao decide transferencia | DP-27 |
| teste_transfere_o_que_so_existe_na_origem_e_omite_identico | Transfere o que so existe na origem e omite o identico | RF-37 |
| teste_conteudo_divergente_transfere_com_a_origem_prevalecendo | Conteudo divergente e transferido com a origem como autoridade | RF-37; DP-27 |
| teste_resumo_remoto_malformado_nunca_e_lido_como_identico | Resumo remoto malformado nunca e tratado como identico | RF-37 |
| teste_sem_espelhar_nenhuma_exclusao_e_emitida | Sem --espelhar nenhuma exclusao e emitida | RF-40 |
| teste_travessia_parcial_desabilita_exclusao_na_execucao_inteira | Travessia parcial desabilita a exclusao em toda a execucao | RF-47 |
| teste_vinculo_simbolico_tambem_desabilita_exclusao | Vinculo simbolico na origem tambem desabilita a exclusao | RF-47 |
| teste_origem_vazia_com_memoria_povoada_recusa_integralmente | Origem vazia com memoria povoada recusa a execucao integralmente | RF-41 |
| teste_primeira_execucao_com_espelhamento_exige_reconhecimento | A primeira execucao com --espelhar exige reconhecimento explicito | RF-48 |
| teste_exclusoes_sao_anunciadas_antes_de_executadas | As exclusoes sao anunciadas antes de executadas | RF-40 |
| teste_simulacao_imprime_o_plano_e_nao_escreve | A simulacao imprime o plano sem escrever nada | RF-44 |
| teste_segunda_execucao_sem_alteracao_nao_emite_escrita | Segunda execucao sem alteracao nao emite nenhuma escrita | RF-38 |
| teste_apagar_a_memoria_nao_muda_o_conjunto_de_operacoes | Apagar a memoria nao muda o conjunto de operacoes de transferencia | DP-27 |
| teste_recebimento_grava_no_local_e_cria_as_pastas_intermediarias | O recebimento grava no local e cria as pastas intermediarias | RF-50 |
| teste_recebimento_cria_diretorio_de_destino_caso_nao_exista | O recebimento cria o diretorio de destino quando nao existe | RF-50 |
| teste_sync_com_progresso_emite_em_stderr_e_preserva_stdout | Com --progresso o andamento vai ao stderr e o stdout permanece igual | RF-37 |
| teste_sync_com_progresso_lista_arquivos_e_resultados_da_analise | --progresso lista os arquivos e os resultados da analise | RF-37 |
| teste_sync_com_progresso_exibe_andamento_da_consulta_remota | --progresso exibe o andamento da consulta remota | RF-37 |
| teste_sync_com_progresso_exibe_andamento_da_analise_local | --progresso exibe o andamento da analise local | RF-37 |
| teste_caixa_diferente_e_o_mesmo_arquivo_e_espelhar_nao_apaga_o_enviado | Caminhos que diferem so na caixa sao o mesmo arquivo e o --espelhar nao apaga o enviado | RF-54; DP-31 |
| teste_caixa_diferente_com_conteudo_identico_e_omitido | Arquivo com caixa diferente e conteudo identico e omitido | RF-54 |
| teste_colisao_de_caixa_local_e_recusada_antes_de_qualquer_escrita | Colisao de caixa na origem local e recusada antes de qualquer escrita | RF-54 |
| teste_colisao_de_caixa_no_destino_local_recusa_o_recebimento | Colisao de caixa no destino local recusa o recebimento | RF-54 |
| teste_recebimento_com_caixa_diferente_grava_no_arquivo_local_existente | Recebimento com caixa diferente grava sobre o arquivo local existente | RF-54 |
| teste_recebimento_com_hash_divergente_preserva_o_arquivo_local | Recebimento com hash divergente preserva o arquivo local | RF-55(e) |
| teste_recebimento_com_hash_conferido_substitui_sem_temporario | Recebimento com hash conferido substitui o arquivo sem deixar temporario | RF-55(e) |
| teste_recebimento_segue_o_umask_do_usuario | O arquivo recebido segue o umask do usuario | RNF-29 |
| teste_envio_define_client_modified | O envio define client_modified a partir do arquivo local | RF-57 |
| teste_envio_sobre_arquivo_existente_carrega_o_rev_da_listagem | Envio sobre arquivo existente carrega o rev da listagem | RF-49 |
| teste_conflito_de_rev_nao_sobrescreve_e_conta_como_falha | Conflito de rev nao sobrescreve e conta como falha do item | RF-49 |
| teste_envio_acima_do_teto_vai_por_sessao_com_rev | Envio acima do teto vai por sessao de upload com o rev | RF-57; RF-49 |
| teste_envio_do_sync_mantem_mute_verdadeiro | O envio do sync mantem mute verdadeiro | RF-57 |
| teste_temporario_de_recebimento_nao_e_enviado_nem_entra_no_plano | O temporario de recebimento nao e enviado nem entra no plano | RF-55 |
| teste_temporario_de_recebimento_nao_entra_na_exclusao_local | O temporario de recebimento nao entra na exclusao local | RF-55 |
| teste_recebimento_sobre_arquivo_somente_leitura_falha_o_item_e_segue | Recebimento sobre arquivo somente leitura falha o item e segue para os demais | RF-55 |
| teste_falha_de_envio_gera_uma_linha_por_item_e_stdout_inalterado | Falha de envio gera uma linha por item no stderr e o stdout fica inalterado | RF-59; TC-FLH-01 |
| teste_falha_de_recebimento_e_de_exclusao_tambem_geram_linha | Falha de recebimento e de exclusao tambem geram a linha por item | RF-59; TC-FLH-02 |
| teste_json_ganha_a_lista_de_falhas_com_caminho_e_classe | A saida --json traz a lista de falhas com caminho e classe | RF-59; TC-FLH-03 |
| teste_linha_de_falha_nunca_carrega_token_nem_corpo_bruto | A linha de falha nunca contem token nem corpo bruto da resposta | RF-59; TC-FLH-04 |
| teste_linha_de_falha_mascara_token_e_refresh_token_pelo_valor | A linha de falha mascara token e refresh token pelo valor | RF-59 |
| teste_caminho_com_quebra_de_linha_nao_forja_linha_de_falha | Caminho com quebra de linha nao forja uma linha de falha falsa | RF-59 |
| teste_int_durante_o_envio_nao_deixa_area_do_sync | SIGINT durante o envio nao deixa area temporaria dbx-sync | RNF-31; TC-SIG-01 |
| teste_term_durante_o_recebimento_nao_deixa_area_do_sync | SIGTERM durante o recebimento nao deixa area temporaria dbx-sync | RNF-31; TC-SIG-02 |
| teste_hup_durante_a_listagem_remota_nao_deixa_area_do_sync | SIGHUP durante a listagem remota nao deixa area temporaria dbx-sync | RNF-31; TC-SIG-03 |
| teste_travessia_completa_grava_so_os_arquivos_visitados | Travessia completa grava na memoria so os arquivos visitados | RF-38 |
| teste_travessia_parcial_preserva_a_memoria_do_ramo_nao_visitado | Travessia parcial preserva a memoria do ramo nao visitado | RF-38 |
| teste_reescrita_no_mesmo_segundo_com_remoto_antigo_e_enviada | Arquivo reescrito no mesmo segundo com remoto antigo e enviado | RF-38 |
| teste_sem_identidade_de_conta_o_sync_segue_sem_memoria | Sem identidade de conta o sync segue sem usar memoria | RF-52(a) |
| teste_sem_identidade_de_conta_espelhar_pede_reconhecimento_e_a_ajuda_avisa | Sem identidade de conta o --espelhar pede reconhecimento e a ajuda avisa | RF-48; RF-52(a) |
| teste_sem_conta_origem_vazia_com_algo_a_apagar_e_recusada_mesmo_com_confirmar | Sem conta, origem vazia com algo a apagar e recusada mesmo com --confirmar | RF-41; DIV-28 |
| teste_sem_conta_origem_povoada_transfere_e_nao_apaga | Sem conta, origem povoada transfere e nao apaga | RF-41; DIV-28 |
| teste_sem_conta_receber_espelhar_nao_apaga_local | Sem conta, --receber --espelhar nao apaga no local | RF-41; DIV-28 |
| teste_memoria_descartada_desabilita_a_exclusao_e_a_seguinte_volta_ao_normal | Memoria descartada desabilita a exclusao e a execucao seguinte volta ao normal | RF-38; RF-41 |
| teste_enumeracao_remota_que_falha_sai_com_o_codigo_da_classe | Falha na enumeracao remota sai com o codigo da classe do erro | RF-52 |
| teste_sync_com_segredo_vazio_recusa_antes_da_rede_na_classe_de_rf03 | Segredo vazio recusa antes da rede na classe de erro de RF-03 | RF-03 |
| teste_origem_vazia_com_algo_a_apagar_e_recusada_em_toda_combinacao | Origem vazia com algo a apagar e recusada em toda combinacao de opcoes | RF-41(b) |
| teste_origem_vazia_com_algo_a_apagar_traz_o_motivo_mesmo_com_confirmar | A recusa por origem vazia traz o motivo mesmo com --confirmar | RF-41(b) |
| teste_permitir_origem_vazia_libera_a_exclusao_nos_dois_sentidos | --permitir-origem-vazia libera a exclusao nos dois sentidos | RF-41(b) |
| teste_simulacao_com_origem_vazia_anuncia_a_recusa_e_nao_lista_exclusao | A simulacao com origem vazia anuncia a recusa e nao lista exclusao | RF-41(b) |
| teste_simulacao_com_permitir_origem_vazia_lista_as_exclusoes | A simulacao com --permitir-origem-vazia lista as exclusoes | RF-41(b) |
| teste_origem_vazia_com_destino_vazio_nao_e_recusada | Origem vazia com destino vazio nao e recusada | RF-41(b) |
| teste_travessia_parcial_nao_regrava_a_memoria | Travessia parcial nao regrava a memoria | RF-38 |
| teste_raiz_relativa_e_absoluta_usam_a_mesma_memoria | Raiz relativa e absoluta usam a mesma memoria | RF-38 |
| teste_diretorio_de_estado_alheio_avisa_e_nao_muda_o_resultado | Diretorio de estado alheio avisa e nao muda o resultado | RNF-02 |
| teste_sync_usa_a_memoria_sem_sqlite_nem_python_e_preserva_o_legado | O sync usa a memoria sem SQLite nem Python e preserva o legado | RF-62(c) |
| teste_cada_alias_do_sync_produz_o_mesmo_plano_que_o_nome_em_portugues | Cada alias em ingles produz o mesmo plano do nome em portugues | RF-64 |
| teste_aliases_do_sync_todos_em_ingles_e_misturados_dao_o_mesmo_plano | Aliases todos em ingles ou misturados dao o mesmo plano | RF-64 |
| teste_yes_reconhece_a_primeira_execucao_espelhada_como_confirmar | --yes reconhece a primeira execucao espelhada como --confirmar | RF-64; RF-48 |
| teste_aliases_do_sync_herdam_as_recusas | Os aliases herdam as recusas dos nomes em portugues | RF-64 |
| teste_opcao_com_valor_repetida_por_alias_vale_o_ultimo | Opcao com valor repetida por alias vale a ultima ocorrencia | RF-64 |
| teste_ajuda_do_sync_lista_os_dois_nomes_de_cada_opcao | A ajuda do sync lista os dois nomes de cada opcao | RF-64 |
| teste_receber_espelhado_com_origem_vazia_recusa_pelo_plano_em_toda_memoria | --receber --espelhar com origem vazia recusa pelo plano com qualquer estado de memoria | RF-41(b) |
| teste_receber_espelhado_com_origem_vazia_simula_e_libera_como_o_enviar | No --receber a simulacao e a liberacao com origem vazia seguem o mesmo comportamento do --enviar | RF-41(b) |
| teste_origem_vazia_sem_espelhar_e_operacao_vazia_com_saida_zero | Origem vazia sem --espelhar e operacao vazia com saida 0 | RF-41 |
| teste_raiz_local_inexistente_continua_recusada | Raiz local inexistente continua recusada | RF-50 |
| teste_caixa_fora_do_ascii_e_um_caminho_mesmo_com_lc_all_c | Caminhos que diferem so em caixa fora do ASCII sao o mesmo caminho mesmo com LC_ALL=C | RF-54 |
| teste_caixa_fora_do_ascii_com_conteudo_igual_e_omitida_com_lc_all_c | Arquivo com caixa fora do ASCII e conteudo igual e omitido com LC_ALL=C | RF-54 |
| teste_comparacao_sem_caixa_nao_muda_medida_em_bytes | A comparacao sem caixa nao altera a medida de tamanho em bytes | RF-54 |
| teste_localidade_ausente_avisa_uma_vez_e_compara_so_no_ascii | Localidade ausente avisa uma unica vez e compara a caixa so no ASCII | RF-54 |
| teste_localidade_ausente_nao_muda_saida_nem_codigo_no_ascii | Localidade ausente nao muda saida nem codigo para nomes ASCII | RF-54 |
| teste_aviso_de_localidade_e_so_do_sync | O aviso de localidade ausente e emitido apenas pelo sync | RF-54 |


## `tests/integracao/testar_test.sh`

- **Alvo:** `bin/dbx testar` (alias `check`) e a sonda de disponibilidade (`commands/testar.sh`, `lib/disponibilidade.sh`)
- **Modulo:** `commands/testar.sh`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `teste-de-disponibilidade`)
- **Regras de origem:** RF-148; RF-149; RF-150; RF-154; TC-DSP-01..25; TC-DSP-55; TC-DSP-57; TC-DSP-58; DIV-326; log `docs/prompts/2026-10-23_0900_teste-de-disponibilidade.md`; protocolo-tdd Regra 6
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` de `tests/support/disponibilidade.sh` que honra o contrato de `lib/http` e grava as opcoes lidas; credencial e senha sentinela sinteticas; terminal interativo por `script(1)`
- **Comando:** `bash tests/run.sh tests/integracao/testar_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_dsp01_tudo_disponivel_quatro_linhas_ok_e_alias_check | Com tudo disponivel testar imprime quatro linhas ok e o alias check equivale | TC-DSP-01; TC-DSP-02 |
| teste_dsp03_sem_credencial_e_sem_rede_primeira_falha_e_a_internet | Sem credencial e sem rede a primeira falha reportada e a de internet | TC-DSP-03; TC-DSP-22 |
| teste_div326_sonda_inacessivel_com_dropbox_respondendo_e_aviso | Sonda sem resposta com o Dropbox respondendo gera aviso, nao falha | DIV-326 |
| teste_dsp04_campo_faltando_e_nomeado_sem_valor_e_sai_3 | Campo faltando na credencial e nomeado sem exibir valor e sai com 3 | TC-DSP-04 |
| teste_dsp05_invalid_grant_sai_5 | Resposta invalid_grant na renovacao sai com 5 | TC-DSP-05 |
| teste_dsp06_perfil_explicito_aponta_o_arquivo_e_o_remedio | Com perfil explicito a mensagem aponta o arquivo e o remedio | TC-DSP-06 |
| teste_dsp07_json_traz_os_mesmos_campos_e_so_json | --json traz os mesmos campos e apenas JSON no stdout | TC-DSP-07 |
| teste_dsp08_so_sonda_dois_hosts_sem_token_e_uma_renovacao_e_nada_em_disco | A execucao sonda dois hosts sem token, faz uma renovacao e nada e gravado em disco | TC-DSP-08; TC-DSP-09; TC-DSP-11 |
| teste_dsp12_duas_falhas_o_codigo_e_o_da_primeira_e_5xx_nao_dispara_nova_sonda | Com duas falhas o codigo e o da primeira e 5xx nao dispara nova sonda | TC-DSP-12; TC-DSP-24 |
| teste_dsp23_sonda_responde_e_dropbox_nao_e_rede_9_servico | Sonda responde e Dropbox nao: a falha e de servico (codigo 9), nao de rede | TC-DSP-23 |
| teste_dsp25_429_e_limite_taxa_nao_indisponibilidade | Resposta 429 e limite de taxa, nao indisponibilidade | TC-DSP-25 |
| teste_dsp13_url_padrao_e_configurada_e_qualquer_status_responde | A URL da sonda padrao ou configurada vale e qualquer status HTTP conta como resposta | TC-DSP-13; TC-DSP-14; TC-DSP-17; TC-DSP-19 |
| teste_dsp15_sonda_vazia_desliga_e_http_e_recusada_no_testar | Sonda vazia a desliga e URL http e recusada no testar | TC-DSP-15; TC-DSP-16 |
| teste_dsp55_nenhum_sentinela_na_saida_nem_na_requisicao | Nenhum valor sentinela de segredo aparece na saida nem na requisicao da sonda | TC-DSP-55; TC-DSP-57 |
| teste_dsp58_sem_terminal_nao_pergunta_e_nao_le_stdin | Sem terminal nao pergunta e nao le nenhum byte da entrada padrao | TC-DSP-10; TC-DSP-58 |
| teste_dsp10_terminal_credencial_ausente_pergunta_e_recusa_mantem_3 | Em terminal com credencial ausente pergunta e, recusada a oferta, mantem o codigo 3 | TC-DSP-10 |
| teste_dsp10_terminal_fim_de_entrada_vale_recusa | Em terminal, fim de entrada na pergunta vale recusa | TC-DSP-10 |
| teste_dsp10_terminal_credencial_incompleta_pergunta_invalida | Em terminal, credencial incompleta tambem pergunta e a resposta invalida e tratada | TC-DSP-10 |
| teste_dsp10_aceite_inicia_o_config_e_o_cancelamento_mantem_o_codigo_da_falha | Aceitar inicia o config e cancelar mantem o codigo da falha original | TC-DSP-10 |
| teste_dsp10_aceite_com_config_bem_sucedido_refaz_as_checagens_e_sai_0 | Aceite com config bem sucedido refaz as checagens e sai com 0 | TC-DSP-10 |
| teste_dsp10_dumb_e_dbx_teste_config_nao_fecham_o_portao | Terminal dumb e DBX_TESTE_CONFIG nao fecham o portao de pergunta | TC-DSP-10 |
| teste_dsp26_permissao_larga_nao_recebe_oferta | Credencial com permissao larga nao recebe oferta de config | TC-DSP-26 |
| teste_dsp26b_remedio_da_recusa_acompanha_o_motivo | O remedio da recusa acompanha o motivo da falha | TC-DSP-26 |
| teste_dsp03b_credencial_nao_executada_nomeia_a_falta_de_internet | Credencial nao executada por falta de internet nomeia essa falta | TC-DSP-03 |
| teste_dsp03c_credencial_nao_executada_nomeia_dropbox_inacessivel | Credencial nao executada por Dropbox inacessivel nomeia essa causa | TC-DSP-03 |
| teste_dsp55c_debug_da_sonda_nao_vaza_userinfo | O --debug da sonda nao vaza userinfo da URL | TC-DSP-55 |
| teste_dsp55d_debug_da_sonda_nao_polui_stdout | O --debug da sonda nao escreve no stdout | TC-DSP-55 |
| teste_dsp55e_debug_da_sonda_nao_vaza_senha_com_delimitador | O --debug da sonda nao vaza senha que contem delimitador | TC-DSP-55 |
| teste_dsp55b_debug_da_sonda_traz_status_sem_segredo_nem_parametro | O --debug da sonda traz status e requisicao mascarada sem segredo nem parametro | TC-DSP-55; RF-149 |


## `tests/integracao/trava_test.sh`

- **Alvo:** `bin/dbx` (sync, verificar, unlink, diagnostico, upload, download, list, info, space, delete, help) com `lib/state.sh` e `lib/tmp.sh`: trava de concorrencia por par e area temporaria unica; auditoria de que a trava so e criada por `lib/state`
- **Modulo:** `lib/state.sh`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-2-trava-e-tmp`)
- **Regras de origem:** RF-69, RF-70, RF-71, RNF-35; TC-TRV, TC-ESR, TC-DIA-11..14, TC-TMP-02, 05, 06; DIV-50, DIV-51; F-12, F-31; log `docs/prompts/2026-10-19_1419_backlog-fase-2-trava-e-tmp.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` que registra cada URL e se havia trava no diretorio de estado naquele instante (coluna T/N) e segura a primeira listagem ate o caso soltar; processos concorrentes reais; estado e area temporaria por caso; duplos de `ln`/`sleep` e socket local quando o caso exige
- **Comando:** `bash tests/run.sh tests/integracao/trava_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_c2_div50_repeticoes_esgotadas_recusam_7_e_nao_seguem_sem_trava | Esgotadas as repeticoes de aquisicao a execucao sai com codigo 7 e nao segue sem trava | DIV-50 |
| teste_c2_div51_download_para_socket_vivo_sai_0_com_o_conteudo | Download para socket vivo termina com codigo 0 entregando o conteudo | DIV-51 |
| teste_c2_qa_b2_02_unlink_reconfere_as_travas_antes_de_apagar | `unlink` reconfere as travas imediatamente antes de apagar o estado | |
| teste_c2_trv37_a_chave_e_da_credencial_e_nao_revela_o_token | A chave da trava deriva da credencial e nunca revela o token | TC-TRV-37 |
| teste_c2_trv38_estado_alheio_segue_sem_trava_com_aviso | Estado que pertence a outro usuario segue sem trava e com aviso | TC-TRV-38 |
| teste_c2_trv39_estado_sem_escrita_segue_e_com_trava_viva_recusa_7 | Estado sem escrita segue sem trava, mas com trava viva de outro processo recusa com codigo 7 | TC-TRV-39 |
| teste_c2_trv40_download_de_pasta_trava_o_par | Download de pasta adquire a trava do par | TC-TRV-40 |
| teste_c3_qa_b2_09_orfa_conhecida_retomada_no_meio_do_unlink_para_com_7 | Trava orfa conhecida, retomada no meio do `unlink`, faz a execucao parar com codigo 7 | |
| teste_dia11_sem_travas_ok_e_estado_ausente_nao_e_criado | Diagnostico sem travas informa ok e nao cria o diretorio de estado ausente | TC-DIA-11 |
| teste_dia12_dia13_dia14_cada_estado_uma_linha_com_remedio_sem_alterar_nada | Diagnostico descreve cada estado de trava em uma linha com o remedio, sem alterar nada | TC-DIA-12; TC-DIA-13; TC-DIA-14 |
| teste_esr01_valores_validos_e_invalidos | A opcao de espera aceita valores validos e recusa invalidos | TC-ESR-01 |
| teste_esr02_esr04_zero_recusa_na_hora_e_espera_esgotada_diz_o_tempo | Espera zero recusa imediatamente e a espera esgotada informa o tempo aguardado | TC-ESR-02; TC-ESR-04 |
| teste_esr03_espera_e_adquire_quando_a_trava_e_liberada | Com espera, a execucao adquire a trava assim que a outra a libera | TC-ESR-03 |
| teste_esr05_alias_e_repeticao_ultimo_vence | Os nomes da opcao de espera sao equivalentes e, repetida, vale a ultima | TC-ESR-05 |
| teste_esr06_orfa_retomada_na_primeira_sondagem_e_outro_host_nunca | Trava orfa do mesmo host e retomada na primeira sondagem e a de outro host nunca e retomada | TC-ESR-06 |
| teste_esr07_sinal_durante_a_espera_sai_com_14_sem_residuo | Sinal durante a espera sai com codigo 14 sem residuo | TC-ESR-07 |
| teste_esr08_demais_comandos_recusam_esperar_e_a_ajuda_traz_a_opcao | Comandos sem trava recusam a opcao de espera e a ajuda a documenta | TC-ESR-08 |
| teste_tmp06_saida_em_socket_que_fecha_cedo_e_consumidor_encerrou | Saida para socket que fecha cedo e tratada como consumidor encerrado | TC-TMP-06 |
| teste_trv01_mesmo_par_se_exclui_em_qualquer_sentido_e_pares_diferentes_rodam_juntos | O mesmo par se exclui em qualquer sentido e pares diferentes rodam em paralelo | TC-TRV-01 |
| teste_trv02_trv06_ocupada_recusa_na_hora_sem_sleep_sem_api_e_sem_segredo | Trava ocupada recusa na hora, sem espera, sem chamada de API e sem expor segredo | TC-TRV-02; TC-TRV-06 |
| teste_trv03_toda_chamada_sai_com_a_trava_e_recusas_de_uso_nao_adquirem | Toda chamada de API ocorre com a trava detida e recusas de uso nao a adquirem | TC-TRV-03 |
| teste_trv04_liberada_em_termino_normal_falha_e_recusa_por_guarda | A trava e liberada em termino normal, falha e recusa por guarda | TC-TRV-04 |
| teste_trv05_tmp02_tmp05_sinal_em_cada_fase_sem_residuo_e_sem_trava | Sinal em cada fase do sync nao deixa residuo nem trava | TC-TRV-05; TC-TMP-02; TC-TMP-05 |
| teste_trv08_comandos_avulsos_nao_travam | Comandos avulsos (list, info, space, delete) nao adquirem trava | TC-TRV-08 |
| teste_trv09_orfa_do_mesmo_host_e_retomada_com_aviso_e_codigo_normal | Trava orfa do mesmo host e retomada com aviso e a execucao termina com codigo normal | TC-TRV-09 |
| teste_trv18_verificar_e_simulacao_deixam_o_estado_byte_a_byte | Verificar e `--dry-run` deixam o diretorio de estado identico byte a byte | TC-TRV-18 |
| teste_trv19_unlink_com_trava_viva_recusa_7_e_nao_apaga_nada | `unlink` com trava viva recusa com codigo 7 e nao apaga nada | TC-TRV-19 |
| teste_trv20_unlink_mantem_travas_nao_vivas_com_um_aviso_por_trava | `unlink` mantem travas nao vivas e emite um aviso por trava | TC-TRV-20 |
| teste_trv31_ordem_trava_leitura_gravacao_liberacao | A ordem observada e trava, leitura de estado, gravacao e liberacao | TC-TRV-31 |
| teste_trv35_estado_em_nfs_avisa_e_nao_bloqueia | Estado em sistema de arquivos de rede avisa e nao bloqueia a execucao | TC-TRV-35 |
| teste_trv36_a_trava_e_escrita_so_de_lib_state | A criacao de trava existe apenas em `lib/state` (auditoria de `lib/*.sh`, `commands/*.sh` e `bin/dbx`) | TC-TRV-36 |


## `tests/integracao/upload_pasta_test.sh`

- **Alvo:** `bin/dbx` (`upload` de arquivo para destino que e pasta) com `commands/upload.sh`: grava em `<pasta>/<nome>` sem falhar com `path/conflict/folder`
- **Modulo:** `commands/upload.sh`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `upload-arquivo-para-pasta`)
- **Regras de origem:** RF-174; log `docs/prompts/2026-10-26_1300_upload-arquivo-para-pasta.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** credencial e duplo de `curl` que responde `get_metadata` por caminho (tabela `metas`, caminho ausente responde 409 `not_found`) e registra consultas, rotas e cabecalhos; arquivo local temporario por caso
- **Comando:** `bash tests/run.sh tests/integracao/upload_pasta_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_arquivo_identico_na_pasta_e_dispensado | Arquivo identico ao ja existente em `<pasta>/<nome>` e dispensado sem novo envio | |
| teste_barra_final_grava_em_pasta_sem_consulta_extra | Destino terminado em barra grava em `<pasta>/<nome>` sem consulta extra de metadados | |
| teste_barra_sozinha_grava_na_raiz | Destino `/` grava o arquivo pelo nome na raiz | |
| teste_destino_inexistente_sem_barra_mantem_o_caminho_informado | Destino inexistente sem barra final e mantido como o caminho do arquivo informado | |
| teste_destino_que_e_arquivo_mantem_o_caminho_informado | Destino que ja e arquivo mantem o caminho informado (sobrescreve conforme as regras existentes) | |
| teste_dry_run_com_barra_final_reporta_caminho_final_sem_escrita | `--dry-run` com barra final reporta o caminho final sem escrever | |
| teste_dry_run_com_pasta_existente_reporta_caminho_final_sem_chamada_extra | `--dry-run` com pasta existente reporta o caminho final sem chamada de escrita | |
| teste_entrada_padrao_com_barra_final_recusa_antes_da_rede | Envio da entrada padrao com destino de barra final e recusado antes de qualquer chamada de rede | |
| teste_entrada_padrao_com_pasta_existente_recusa_sem_escrita | Envio da entrada padrao para pasta existente e recusado sem escrita | |
| teste_forcar_com_pasta_resolve_com_consulta_so_de_tipo | Com `--forcar` e destino pasta a resolucao consulta apenas o tipo do destino | |
| teste_nome_com_caracteres_especiais_fica_dentro_da_pasta_e_da_raiz | Nome com caracteres especiais fica dentro da pasta e da raiz remota configurada | |
| teste_pasta_existente_grava_em_pasta_e_nome_por_requisicao_unica | Pasta existente recebe o arquivo pequeno em `<pasta>/<nome>` por requisicao unica | |
| teste_pasta_existente_grava_em_pasta_e_nome_por_sessao | Pasta existente recebe o arquivo grande em `<pasta>/<nome>` por sessao de envio | |


## `tests/integracao/verificar_test.sh`

- **Alvo:** `bin/dbx verificar` (alias `verify`) (`commands/verificar.sh`, `lib/walk.sh`, `lib/sync.sh`)
- **Modulo:** `commands/verificar.sh`
- **Camada:** integracao
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-1-consulta-diagnostico`)
- **Regras de origem:** RF-65; TC-VER-01..09; log `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md`; protocolo-tdd Regra 6
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** arvores locais temporarias, listagem remota pelo duplo de `curl` do arquivo, credencial sintetica, memoria de estado corrompida ou de outra conta nos casos TC-VER-04
- **Comando:** `bash tests/run.sh tests/integracao/verificar_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_ver01_arvores_iguais_saem_com_zero_e_nao_escrevem | Arvores iguais saem com 0 e nada e escrito | TC-VER-01 |
| teste_ver01_arvores_ambas_vazias_saem_com_zero | Duas arvores vazias saem com 0 | TC-VER-01 |
| teste_ver02_quatro_estados_e_codigo_onze_no_enviar | No --enviar classifica os quatro estados e sai com 11 quando ha divergencia | TC-VER-02 |
| teste_ver02_no_receber_os_papeis_se_invertem | No --receber os papeis de origem e destino se invertem nos estados | TC-VER-02 |
| teste_ver09_origem_vazia_nao_e_recusada_e_lista_tudo_como_so_destino | Origem vazia nao e recusada e tudo aparece como so no destino | TC-VER-09 |
| teste_ver03_so_le_e_nao_toca_estado_nem_temporarios | verificar so le e nao toca estado nem temporarios | TC-VER-03 |
| teste_ver03_receber_nao_cria_a_raiz_local_ausente | No --receber nao cria a raiz local ausente | TC-VER-03 |
| teste_ver04_memoria_corrompida_ou_de_outra_conta_nao_muda_o_resultado | Memoria corrompida ou de outra conta nao muda o resultado | TC-VER-04 |
| teste_ver05_caminho_remoto_hostil_e_recusado_antes_da_api_e_do_disco | Caminho remoto hostil e recusado antes de qualquer chamada a API ou acesso a disco | TC-VER-05 |
| teste_ver05_vinculo_simbolico_para_fora_nao_e_seguido_e_a_travessia_e_parcial | Vinculo simbolico para fora nao e seguido e a travessia e marcada parcial | TC-VER-05 |
| teste_ver05_colisao_de_caixa_local_e_recusada_antes_de_qualquer_acesso_remoto | Colisao de caixa local e recusada antes de qualquer acesso remoto | TC-VER-05 |
| teste_ver05_caixa_e_acento_sao_o_mesmo_caminho | Caixa e acento diferentes denotam o mesmo caminho | TC-VER-05 |
| teste_ver06_json_traz_a_versao_de_contrato_e_null_preserva_quebra_de_linha | --json traz a versao de contrato e --null preserva quebra de linha em nomes | TC-VER-06 |
| teste_ver07_erro_de_execucao_prevalece_sobre_a_divergencia | Erro de execucao prevalece sobre o codigo de divergencia | TC-VER-07 |
| teste_ver08_opcoes_do_sync_que_nao_se_aplicam_sao_recusadas | Opcoes do sync que nao se aplicam a verificar sao recusadas | TC-VER-08 |
| teste_ver08_aliases_produzem_o_mesmo_resultado | Os aliases produzem o mesmo resultado dos nomes em portugues | TC-VER-08 |
| teste_ver08_simulacao_e_aceita_e_sem_efeito | --dry-run e aceito e nao tem efeito | TC-VER-08 |


## `tests/unit/atributos_portavel_test.sh`

- **Alvo:** `lib/atributos.sh` (`dbx_atributo`), `lib/http.sh` e `lib/transfer.sh` na leitura de atributos de arquivo com `stat` GNU ou BSD
- **Modulo:** `atributos_portavel` (linha ausente do mapa de modulos; id derivado do nome do arquivo)
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `suporte-freebsd`)
- **Regras de origem:** RF-167; TC-FBSD-02; TC-FBSD-11; TC-FBSD-19 (parte `stat`); log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de `stat` do FreeBSD em `tests/duplos/freebsd/bin/stat` (rejeita `-c`, aceita `-f`) no `PATH`; arquivos temporarios por caso
- **Comando:** `bash tests/run.sh tests/unit/atributos_portavel_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_atributo_de_tipo_do_sistema_de_arquivos_e_nao_verificado_no_bsd | No `stat` BSD, o tipo do sistema de arquivos e reportado como nao verificado | TC-FBSD-19 |
| teste_atributo_falha_sem_assumir_valor_quando_o_arquivo_nao_existe | Arquivo inexistente faz o auxiliar falhar sem assumir valor | |
| teste_atributo_le_do_mesmo_modo_com_stat_gnu | Com `stat` GNU o auxiliar le o mesmo modo que com o BSD | |
| teste_atributo_le_modo_dono_tamanho_e_mtime_com_stat_bsd | Com `stat` BSD o auxiliar le modo, dono, tamanho e mtime | RF-167 |
| teste_duplo_de_stat_rejeita_c_e_aceita_f | O duble de `stat` rejeita `-c` e aceita `-f`, como o FreeBSD | |
| teste_forma_aprendida_por_sonda_unica_uma_leitura_uma_chamada | A forma do `stat` e aprendida por uma unica sonda e cada leitura faz uma chamada | |
| teste_identidade_do_arquivo_vem_preenchida_e_estavel_com_stat_bsd | A identidade do arquivo vem preenchida e estavel com `stat` BSD | TC-FBSD-11 |
| teste_listagem_de_retomada_calcula_a_idade_pelo_mtime_com_stat_bsd | A listagem de retomada calcula a idade pelo mtime com `stat` BSD | TC-FBSD-11 |
| teste_modo_mantem_suid_e_sticky_e_coincide_nas_duas_formas | O modo mantem suid e sticky e coincide nas duas formas de `stat` | |
| teste_nenhum_stat_com_formato_fora_do_auxiliar | Nenhum `stat` com formato (`-c`/`-f`) e chamado fora do auxiliar | TC-FBSD-02 |
| teste_recebimento_preserva_o_modo_do_alvo_com_stat_bsd | O recebimento preserva o modo do alvo com `stat` BSD | |


## `tests/unit/auth_test.sh`

- **Alvo:** `lib/auth.sh` (troca de codigo e renovacao de token de curta duracao, revogacao, esquecimento de credencial)
- **Modulo:** auth_test
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `feat(auth): renovacao de token sem escrita do segredo em disco`)
- **Regras de origem:** Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` no caminho de busca; refresh token e segredos sinteticos; `assert_segredo_ausente` para provar ausencia sem imprimir a agulha; sem rede
- **Comando:** `bash tests/run.sh tests/unit/auth_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_auditoria_de_multiplexacao_discrimina_selecao_de_registro | A auditoria de multiplexacao distingue a selecao de registro legitima de seletor indevido | |
| teste_auditoria_fora_de_config_reprova_seletor_em_cada_camada | A auditoria reprova seletor de conta ou perfil fora de `config` em cada camada do codigo | |
| teste_canal_de_corpo_do_transporte_nao_retem_o_token_apos_renovar | Apos renovar, o canal de corpo do transporte nao retem o token | |
| teste_canal_de_corpo_nao_retem_segredo_quando_o_servico_ecoa_a_requisicao | O canal de corpo nao retem segredo mesmo quando o servico ecoa a requisicao | |
| teste_chave_fora_do_alfabeto_de_url_nao_entra_na_url | Chave com caracteres fora do alfabeto de URL nao entra na URL | |
| teste_codigo_vencido_nao_e_diagnosticado_como_credencial_revogada | Codigo de autorizacao vencido nao e diagnosticado como credencial revogada | |
| teste_concessao_invalida_e_terminal_e_nao_e_retentada | Concessao invalida e erro terminal e nao e retentada | |
| teste_esquecer_apaga_o_token_da_memoria | `esquecer` apaga o token da memoria do processo | |
| teste_esquecer_vinculo_apaga_o_que_a_troca_publicou | Esquecer o vinculo apaga tudo o que a troca de codigo publicou | |
| teste_falha_de_renovacao_nao_vaza_o_refresh_token_no_motivo | O motivo de falha da renovacao nao contem o refresh token | |
| teste_limpeza_do_transporte_nao_apaga_a_resposta_que_o_chamador_precisa | A limpeza do transporte preserva a resposta de que o chamador ainda precisa | |
| teste_nao_grava_estado_em_disco_ao_renovar | Renovar o token nao grava nenhum estado em disco | |
| teste_nao_invoca_o_cliente_de_rede_diretamente | `lib/auth.sh` nao invoca o cliente de rede diretamente, so pelo ponto unico de `lib/http.sh` | |
| teste_nao_recebe_identificador_de_conta_ou_perfil | A biblioteca nao recebe identificador de conta ou perfil como parametro | |
| teste_nenhum_formulario_de_token_sai_sem_client_secret | Nenhum formulario de token e emitido sem o segredo do cliente | |
| teste_pkce_nao_e_implementado | Nao ha `code_verifier` nem `code_challenge` (PKCE nao e implementado) | |
| teste_refresh_token_chega_pela_entrada_padrao | O refresh token chega ao cliente de rede pela entrada padrao | |
| teste_refresh_token_nao_vaza_nos_canais_publicos_apos_renovar | Apos renovar, o refresh token nao aparece em nenhum canal publico da biblioteca | |
| teste_refresh_token_nunca_aparece_na_linha_de_comando | O refresh token nunca aparece na linha de comando do cliente de rede | |
| teste_refresh_token_nunca_e_escrito_em_arquivo_de_corpo | O refresh token nunca e escrito em arquivo de corpo | |
| teste_renovacao_bem_sucedida_seguida_de_401_nao_entra_em_laco | Renovacao bem-sucedida seguida de 401 nao entra em laco de renovacoes | |
| teste_renovacao_expoe_os_escopos_concedidos | A renovacao expoe os escopos concedidos pelo servico | |
| teste_renovacao_falha_sem_credencial_carregada | Renovar sem credencial carregada falha com erro claro | |
| teste_renovacao_no_meio_do_caminho_nao_repete_indefinidamente | Renovacao no meio de uma sequencia de chamadas nao se repete indefinidamente | |
| teste_renovacao_obtem_token_de_curta_duracao | A renovacao obtem um access token de curta duracao | |
| teste_renovacao_sem_campo_de_escopo_declara_nao_informados | Resposta de renovacao sem campo de escopo declara os escopos como nao informados | |
| teste_renovacao_sem_segredo_e_recusada_antes_da_rede | Renovar sem o segredo e recusado antes de qualquer chamada de rede | |
| teste_requisicao_usa_o_token_curto_e_nao_o_refresh | As requisicoes usam o token curto e nunca o refresh token | |
| teste_resposta_sem_refresh_token_nomeia_a_causa_em_vez_do_sintoma | Resposta da troca sem refresh token nomeia a causa em vez do sintoma | |
| teste_resposta_sem_token_e_recusada | Resposta sem access token e recusada como erro | |
| teste_revogacao_nao_expoe_credencial_na_linha_de_comando | A revogacao nao expoe credencial na linha de comando | |
| teste_revogacao_vai_ao_endpoint_previsto | A revogacao chama o endpoint previsto de revogacao de token | |
| teste_segredo_e_codigo_nao_aparecem_na_linha_de_comando_da_troca | Segredo e codigo de autorizacao nao aparecem na linha de comando da troca | |
| teste_status_seguem_a_taxonomia_de_erro | Os status HTTP de erro da autenticacao seguem a taxonomia de codigos de saida | |
| teste_token_expirado_dispara_nova_renovacao | Token expirado dispara uma nova renovacao | |
| teste_token_expirado_no_meio_do_caminho_renova_uma_vez_e_repete | Token expirado no meio de uma chamada renova uma vez e repete a chamada | |
| teste_token_valido_e_reaproveitado_sem_nova_renovacao | Token ainda valido e reaproveitado sem nova renovacao | |
| teste_troca_de_codigo_publica_refresh_token_e_conta | A troca de codigo publica o refresh token e a conta obtida | |
| teste_troca_de_codigo_sem_segredo_e_recusada_antes_da_rede | A troca de codigo sem o segredo do cliente e recusada antes da rede | |
| teste_troca_nao_deixa_o_refresh_token_nos_canais_do_transporte | A troca de codigo nao deixa o refresh token nos canais do transporte | |
| teste_url_de_autorizacao_pede_acesso_offline | A URL de autorizacao pede acesso offline (refresh token) | |
| teste_validade_respeita_margem_antes_do_vencimento | A validade do token considera uma margem de seguranca antes do vencimento | |


## `tests/unit/cabecalho_test.sh`

- **Alvo:** `lib/http.sh` (recusa de valor de cabecalho HTTP com CR, LF ou byte de controle antes de chegar ao cliente)
- **Modulo:** `cabecalho`
- **Camada:** unitario
- **Autoria:** Senior Developer (commit de criacao e0cee97 `test: casos adversariais da recusa de cabecalho, escritos pelo QA`, sem log de prompt)
- **Regras de origem:** Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de cliente HTTP que registra se foi invocado; valores de cabecalho adversariais (CR, LF, bytes de controle, UTF-8 sobrelongo) montados no caso; nome de arquivo real com CR em area temporaria
- **Comando:** `bash tests/run.sh tests/unit/cabecalho_test.sh`
- **Observacoes:** o cabecalho do arquivo declara que os casos foram escritos pelo QA a pedido do Senior Developer, mas a autoria pelo historico git e do Senior Developer e nao ha registro de aceite do solicitante; o Tech Lead deve decidir a autoria.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_a_garantia_nao_depende_do_comportamento_do_cliente | A recusa ocorre em nossa biblioteca, sem depender de o cliente HTTP descartar o valor | |
| teste_aceita_nome_de_arquivo_legitimo | Nome de arquivo legitimo e aceito como valor de cabecalho | |
| teste_aceita_sequencia_percentual_literal | Sequencia percentual literal (por exemplo `%0d`) e aceita, por nao ser CR real | |
| teste_aceita_valor_no_teto | Valor com exatamente o tamanho do teto e aceito | |
| teste_emissao_aceita_valor_legitimo_e_invoca_o_cliente | Valor legitimo e emitido e o cliente HTTP e invocado | |
| teste_emissao_recusa_antes_de_invocar_o_cliente | Valor invalido e recusado antes de invocar o cliente HTTP | |
| teste_motivo_da_recusa_nao_ecoa_o_valor_recusado | A mensagem de recusa nao repete o valor recusado | |
| teste_nome_de_arquivo_real_com_cr_nao_produz_cabecalho_inseguro | Arquivo real com CR no nome nao produz cabecalho inseguro | |
| teste_nome_de_arquivo_real_legitimo_atravessa_o_caminho_completo | Arquivo real com nome legitimo atravessa o caminho completo ate o cliente | |
| teste_recusa_byte_de_controle_isolado_sem_texto_ao_redor | Byte de controle isolado, sem texto ao redor, e recusado | |
| teste_recusa_cr_lf_e_crlf_em_qualquer_posicao | CR, LF e CRLF sao recusados em qualquer posicao do valor | |
| teste_recusa_cr_produzido_por_escape_unicode_do_analisador | CR produzido por escape unicode do analisador JSON e recusado | |
| teste_recusa_terminador_repetido_e_corpo_forjado | Terminador repetido e corpo de requisicao forjado no valor sao recusados | |
| teste_recusa_todo_byte_de_controle | Todo byte de controle e recusado | |
| teste_recusa_utf8_sobrelongo_de_cr_e_de_lf | Codificacao UTF-8 sobrelonga de CR e de LF e recusada | |
| teste_recusa_valor_acima_do_teto | Valor acima do teto de tamanho e recusado | |
| teste_teto_de_cabecalho_existe_e_e_conservador | O teto de tamanho de cabecalho existe e e conservador | |


## `tests/unit/chmod_portavel_test.sh`

- **Alvo:** chamadas de `chmod` de `lib/auth.sh`, `lib/state.sh` e `lib/http.sh` (gravacao da credencial, diretorio de estado, modo do alvo no recebimento), exercitadas com o duble de `chmod` do FreeBSD em `tests/duplos/freebsd/bin/chmod`
- **Modulo:** chmod_portavel
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `suporte-freebsd`)
- **Regras de origem:** RF-166; TC-FBSD-01; TC-FBSD-19 (parte chmod); log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** areas temporarias por caso; duble de `chmod` do FreeBSD no `PATH` (trata o primeiro argumento nao-opcao como modo); credencial sintetica
- **Comando:** `bash tests/run.sh tests/unit/chmod_portavel_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_duplo_de_chmod_trata_dois_hifens_depois_do_modo_como_operando | O duble reproduz o FreeBSD: `chmod 600 -- arquivo` falha por tratar `--` como arquivo | TC-FBSD-01 |
| teste_duplo_de_chmod_aceita_dois_hifens_antes_do_modo | O duble aceita a forma portavel `chmod -- 600 arquivo` e aplica o modo | TC-FBSD-01 |
| teste_gravacao_da_credencial_conclui_com_chmod_bsd | Com o duble no `PATH`, a gravacao da credencial conclui e deixa o arquivo com modo restrito | TC-FBSD-19 |
| teste_preparo_do_diretorio_de_estado_conclui_com_chmod_bsd | Com o duble no `PATH`, o preparo do diretorio de estado conclui com o modo esperado | TC-FBSD-19 |
| teste_recebimento_aplica_o_modo_do_alvo_com_chmod_bsd | Receber sobre um alvo existente replica o modo do alvo no arquivo novo, mesmo com o chmod BSD | TC-FBSD-19 |
| teste_nenhum_chmod_do_produto_poe_dois_hifens_depois_do_modo | Auditoria de texto: nenhum `chmod` em lib, commands ou bin usa `--` depois do modo | RF-166 |


## `tests/unit/cli_test.sh`

- **Alvo:** `lib/cli.sh`: interpretacao de opcoes globais, despacho por tabela fechada de comandos e requisito de ambiente de cada comando
- **Modulo:** `lib/cli.sh`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD; commit de criacao `b2179b4`, "feat(comandos): entrada fina com despacho por tabela literal")
- **Regras de origem:** Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** Nao aplicavel: casos carregam `lib/cli.sh` em processo proprio e leem apenas `bin/dbx` e `commands/*.sh` do repositorio
- **Comando:** `bash tests/run.sh tests/unit/cli_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_ajuda_e_versao_nao_exigem_ambiente | Ajuda e versao nao exigem preflight nem credencial | |
| teste_ajuda_e_versao_sao_comandos_e_nao_opcoes_pendentes | Ajuda e versao sao tratadas como comandos, nao como opcoes pendentes de outro comando | |
| teste_ausencia_de_comando_e_uso_invalido | Chamada sem comando e uso invalido (codigo 2) | |
| teste_comando_conhecido_e_aceito | Comando presente na tabela de despacho e aceito | |
| teste_comando_desconhecido_e_recusado | Comando fora da tabela e recusado como uso invalido | |
| teste_nome_de_comando_nunca_compoe_caminho_de_arquivo | O nome digitado nunca e usado para compor o caminho do arquivo carregado | |
| teste_nome_sem_arquivo_nao_resolve_para_caminho | Nome sem arquivo de comando correspondente nao resolve para nenhum caminho | |
| teste_opcao_debug_reconhecida_globalmente | `--debug` e reconhecida como opcao global | |
| teste_opcao_global_desconhecida_e_recusada | Opcao global desconhecida antes do comando e recusada | |
| teste_opcoes_apos_o_comando_pertencem_ao_comando | Opcoes depois do comando pertencem ao comando e nao sao consumidas como globais | |
| teste_opcoes_de_progresso_reconhecidas_globalmente | Opcoes de progresso sao reconhecidas como globais | |
| teste_opcoes_globais_antes_do_comando | Opcoes globais antes do comando sao interpretadas e o comando e identificado corretamente | |
| teste_requisito_declarado_pertence_ao_vocabulario_fechado | O requisito de ambiente declarado por cada comando pertence ao vocabulario fechado | |
| teste_separador_de_fim_de_opcoes_e_respeitado | O separador `--` encerra a leitura de opcoes globais | |
| teste_tabela_de_despacho_e_os_arquivos_de_comando_se_correspondem | A tabela de despacho e os arquivos de `commands/` correspondem um a um | |
| teste_todo_comando_declara_seu_requisito_de_ambiente | Todo comando da tabela declara o seu requisito de ambiente | |
| teste_travessia_no_nome_do_comando_e_recusada | Nome de comando com travessia de diretorio e recusado | |
| teste_validar_paralelo_aceita_so_um_algarismo_de_1_a_8 | A validacao do paralelismo aceita apenas um algarismo de 1 a 8 | |


## `tests/unit/cmd_test.sh`

- **Alvo:** `lib/cmd.sh`: servicos comuns dos comandos (`dbx_cmd_falhar`, `dbx_cmd_iniciar_saida`, `dbx_cmd_bytes_legiveis`, `dbx_cmd_content_hash_do_resultado`, `dbx_cmd_receber_arquivo`, confinamento do caminho remoto, checagem e calculo de espaco)
- **Modulo:** `lib/cmd.sh`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `cache-unico-p3`)
- **Regras de origem:** RNF-32(d); log `docs/prompts/2026-10-18_2243_cache-unico-p3.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` escrito sem expansao; canais de `lib/cli`, `lib/auth` e `lib/http` ajustados por caso; diretorios temporarios por caso
- **Comando:** `bash tests/run.sh tests/unit/cmd_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_bytes_legiveis_por_unidade_binaria | Valores em bytes viram texto legivel em unidade binaria (KiB, MiB, GiB) | |
| teste_caminho_remoto_com_controle_recusa_sem_reproduzir_o_byte | Caminho remoto com caractere de controle e recusado sem reproduzir o byte na mensagem | |
| teste_caminho_remoto_com_raiz_da_conta_nao_muda_nada | Com a raiz da conta o caminho remoto nao e alterado | |
| teste_caminho_remoto_com_raiz_explicita_ignora_a_da_credencial | Raiz explicita informada prevalece sobre a raiz da credencial | |
| teste_caminho_remoto_com_raiz_malformada_falha_fechado_como_configuracao | Raiz malformada falha fechada como erro de configuracao | |
| teste_caminho_remoto_dentro_da_raiz_da_credencial_e_aceito_sem_emitir | Caminho dentro da raiz da credencial e aceito e nada e emitido na saida | |
| teste_caminho_remoto_fora_da_raiz_recusa_com_13_e_nomeia_a_raiz | Caminho fora da raiz recusa com codigo 13 e a mensagem nomeia a raiz | |
| teste_checar_espaco_com_consulta_falha_avisa_uma_vez_e_segue | Falha na consulta de espaco avisa uma unica vez e o envio segue | |
| teste_checar_espaco_recusa_so_quando_o_total_excede_a_folga | A checagem recusa apenas quando o total a enviar excede a folga disponivel | |
| teste_checar_espaco_sem_nada_a_enviar_ou_pulado_nao_consulta | Sem itens a enviar (ou todos pulados) a checagem nao consulta o espaco | |
| teste_content_hash_do_resultado_le_o_cabecalho_ou_fica_vazio | O `content_hash` do resultado vem do cabecalho e fica vazio quando ausente | |
| teste_espaco_de_equipe_e_a_menor_das_folgas | Em conta de equipe o espaco livre e a menor das folgas | |
| teste_espaco_individual_e_alocado_menos_usado | Em conta individual o espaco livre e o alocado menos o usado | |
| teste_espaco_sem_alocacao_interpretavel_fica_desconhecido | Sem alocacao interpretavel o espaco fica desconhecido | |
| teste_falhar_devolve_o_codigo_da_classe_e_escreve_so_no_stderr | `dbx_cmd_falhar` devolve o codigo da classe e escreve somente no stderr | |
| teste_falhar_redige_segredo_no_diagnostico | `dbx_cmd_falhar` redige segredos no diagnostico | |
| teste_iniciar_saida_aplica_os_modos_globais | `dbx_cmd_iniciar_saida` aplica os modos globais de saida | |
| teste_ler_corpo_silencioso_le_campo_aninhado_por_segmentos | A leitura silenciosa do corpo resolve campo aninhado por segmentos | |
| teste_ler_corpo_silencioso_nomeia_classe_e_motivo_na_falha | Na falha a leitura silenciosa nomeia a classe e o motivo | |
| teste_ler_corpo_silencioso_publica_campos_sem_emitir_nada | A leitura silenciosa publica os campos nos canais sem emitir saida | |
| teste_receber_arquivo_com_resumo_divergente_preserva_o_alvo | Recebimento com resumo divergente falha e preserva o alvo existente | |
| teste_receber_arquivo_confere_e_substitui_sem_temporario | Recebimento valido confere o resumo, substitui o alvo e nao deixa temporario | |
| teste_receber_arquivo_nao_substitui_alvo_somente_leitura | Recebimento nao substitui alvo somente leitura | |


## `tests/unit/compartilhamento_test.sh`

- **Alvo:** `lib/compartilhamento.sh` (visibilidade, `--expira`, URL, senha, corpo), leitura sem eco de `lib/cli.sh` e tags e chave sensivel novas de `lib/errors.sh`
- **Modulo:** `compartilhamento_test`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-5-compartilhamento`)
- **Regras de origem:** RF-85..RF-89; RF-90(a); DIV-104..DIV-120; DIV-111; DIV-117; TC-SHE-01; TC-SNH-11; log `docs/prompts/2026-10-20_1110_backlog-fase-5-compartilhamento.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** Nao aplicavel: lib pura, sem rede nem estado; entradas sinteticas em memoria (a senha de teste e valor fabricado)
- **Comando:** `bash tests/run.sh tests/unit/compartilhamento_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_cli_ler_oculto_preenche_a_variavel_do_chamador_e_pergunta_em_stderr | A leitura sem eco preenche a variavel do chamador e faz a pergunta em stderr | DIV-117 |
| teste_cmp02_03_corpo_publico_e_equipe_usam_audience_sem_campo_depreciado | Visibilidade publica e de equipe usam `audience` no corpo, sem o campo depreciado | TC-CMP-02, TC-CMP-03 |
| teste_cmp05_expira_datas_e_duracoes_validas_viram_expires_normalizado | Datas e duracoes validas de `--expira` viram `expires` normalizado | TC-CMP-05 |
| teste_cmp06_expira_invalidas_sao_uso_invalido | Valores invalidos de `--expira` sao recusados como uso invalido | TC-CMP-06 |
| teste_cmp07_expira_no_passado_ou_a_menos_de_60s_e_recusada | `--expira` no passado ou a menos de 60 segundos e recusada | TC-CMP-07 |
| teste_lex03_mesmo_caminho_dobra_so_ascii | A comparacao de caminho dobra a caixa so para ASCII | TC-LEX-03 |
| teste_lex10_exposicao_ampliada_e_detectada | Ampliacao de exposicao do link e detectada | TC-LEX-10 |
| teste_lst04_05_rvg12_confinamento_por_componente_e_dobra_so_ascii | Confinamento e por componente de caminho e a dobra de caixa e so ASCII | TC-LST-04, TC-LST-05, TC-RVG-12 |
| teste_rvg06_07_urls_invalidas_e_link_temporario_sao_recusados | URLs invalidas e URL de link temporario sao recusadas onde nao cabem | TC-RVG-06, TC-RVG-07 |
| teste_rvg06_urls_validas_sao_aceitas | URLs de link compartilhado validas sao aceitas | TC-RVG-06 |
| teste_she01_cada_tag_nova_cai_na_classe_da_tabela_com_e_sem_qualificador | Cada tag nova de erro cai na classe da tabela, com e sem qualificador | TC-SHE-01; RF-90(a) |
| teste_snh05_06_senha_vazia_controle_longa_ou_utf8_invalido_sao_recusadas_sem_citar | Senha vazia, com controle, longa demais ou UTF-8 invalido e recusada sem citar o valor | TC-SNH-05, TC-SNH-06 |
| teste_snh11_link_password_e_mascarado_pela_redacao | O campo `link_password` e mascarado pela redacao de erros | TC-SNH-11; DIV-111 |
| teste_snh14_corpo_com_senha_e_json_valido_com_o_valor_identico | Corpo com senha e JSON valido e carrega o valor identico | TC-SNH-14 |
| teste_snh14_senha_com_aspa_barra_espaco_e_acento_e_aceita | Senha com aspa, barra, espaco e acento e aceita | TC-SNH-14 |
| teste_visibilidade_esperada_e_a_resolvida_da_api | A visibilidade esperada e comparada com a resolvida devolvida pela API | |


## `tests/unit/config_test.sh`

- **Alvo:** `lib/config.sh` (leitura e escrita atomica do arquivo de credencial, caminhos XDG, permissoes, remocao)
- **Modulo:** `config`
- **Camada:** unitario
- **Autoria:** Senior Developer (commit de criacao ebec9ae `test: preflight, config e composicao dos caminhos gemeos`, sem log de prompt)
- **Regras de origem:** PRJ-DEC-07; DP-05; DP-11; RNF-04
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** diretorios temporarios por caso, `XDG_CONFIG_HOME` e `XDG_STATE_HOME` ajustados pelo caso, processos filhos por `bash -c`; credenciais sinteticas e valores sentinela de segredo
- **Comando:** `bash tests/run.sh tests/unit/config_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_a_auditoria_de_saida_unica_detecta_caminho_novo | A auditoria de saida unica detecta um novo caminho de saida inserido numa copia mutante | |
| teste_app_key_vazia_e_credencial_incompleta | Chave de aplicativo vazia torna a credencial incompleta | |
| teste_arquivo_inexistente_e_erro_de_configuracao | Arquivo de credencial inexistente e erro de configuracao | |
| teste_arquivo_truncado_e_recusado | Arquivo de credencial truncado e recusado | |
| teste_auditoria_de_perfil_em_config_reprova_as_mutacoes | A auditoria de identificador de perfil em `lib/config.sh` reprova as copias mutantes | DP-05 |
| teste_caminho_de_estado_recusa_base_relativa | O caminho de estado recusa base relativa | |
| teste_caminho_de_estado_usa_xdg_state_e_nao_o_de_configuracao | O caminho de estado usa `XDG_STATE_HOME` e nao o de configuracao | |
| teste_caminho_segue_xdg_config_home | O caminho da credencial segue `XDG_CONFIG_HOME` | RNF-04 |
| teste_carregar_usa_contexto_proprio_e_nao_destroi_documento_em_curso | `carregar` usa contexto proprio e nao destroi um documento JSON em curso | |
| teste_conteudo_malformado_de_edicao_manual_e_recusado | Conteudo malformado por edicao manual e recusado | |
| teste_diretorio_acessivel_a_terceiros_e_recusado | Diretorio de credencial acessivel a terceiros e recusado | |
| teste_falha_de_gravacao_preserva_o_arquivo_anterior | Falha de gravacao preserva o arquivo anterior | |
| teste_falha_de_gravacao_registra_detalhe_operacional | Falha de gravacao registra o detalhe operacional sem segredo | |
| teste_falha_de_leitura_nao_deixa_credencial_residual | Falha de leitura nao deixa credencial residual em variaveis | |
| teste_fallback_e_config_no_diretorio_do_usuario | Sem `XDG_CONFIG_HOME`, o fallback e `.config` no diretorio do usuario | RNF-04 |
| teste_formato_do_arquivo_e_coberto_pela_redacao | O formato do arquivo de credencial e coberto pela redacao de segredos | |
| teste_gravacao_cria_arquivo_com_permissao_restrita | A gravacao cria o arquivo com permissao restrita ao dono | |
| teste_gravacao_cria_diretorio_pai_ausente | A gravacao cria o diretorio pai ausente | |
| teste_gravacao_e_atomica_e_nao_deixa_residuo | A gravacao e atomica e nao deixa residuo | |
| teste_ida_e_volta_preserva_os_campos | Gravar e carregar preserva todos os campos | |
| teste_interrupcao_nao_deixa_orfao_com_segredo | Interrupcao durante a gravacao nao deixa temporario orfao com segredo | |
| teste_modo_de_remocao_fora_do_vocabulario_e_recusado | Modo de remocao fora do vocabulario previsto e recusado | |
| teste_nenhum_modo_de_falha_deixa_o_refresh_token_num_canal_global | Nenhum modo de falha deixa o refresh token em canal global | |
| teste_nenhuma_falha_ecoa_o_segredo | Nenhuma falha ecoa o segredo | |
| teste_nenhuma_funcao_recebe_identificador_de_perfil | Nenhuma funcao de `lib/config.sh` recebe identificador de perfil | DP-05 |
| teste_nenhuma_variavel_de_ambiente_sobrescreve_a_credencial | Nenhuma variavel de ambiente sobrescreve a credencial lida do arquivo | |
| teste_o_bloco_de_analise_tem_saida_unica | O bloco de analise tem saida unica | |
| teste_orfao_com_identificador_de_processo_vivo_e_removido_por_idade | Temporario orfao cujo identificador de processo foi reaproveitado e removido por idade | |
| teste_permissao_frouxa_e_recusada | Arquivo com permissao frouxa e recusado | |
| teste_permissao_mais_restritiva_que_0600_e_aceita | Permissao mais restritiva que 0600 e aceita | |
| teste_permissao_sem_leitura_para_o_dono_e_recusada | Permissao sem leitura para o dono e recusada | |
| teste_raiz_remota_com_caractere_adversarial_sobrevive | Raiz remota com caractere adversarial sobrevive ao ciclo de gravacao e leitura | |
| teste_refresh_token_vazio_e_credencial_incompleta | Refresh token vazio torna a credencial incompleta | |
| teste_remocao_de_aplicativo_preserva_a_chave_e_invalida_o_vinculo | Remocao do aplicativo preserva a chave e invalida o vinculo | |
| teste_remocao_de_aplicativo_sem_credencial_carregada_e_recusada | Remocao do aplicativo sem credencial carregada e recusada | |
| teste_remocao_integral_apaga_o_arquivo | Remocao integral apaga o arquivo | |
| teste_remocao_integral_leva_junto_temporario_orfao | Remocao integral leva junto o temporario orfao | |
| teste_segredo_com_caractere_adversarial_sobrevive | Segredo com caractere adversarial sobrevive ao ciclo de gravacao e leitura | |
| teste_segredo_opcional_nao_torna_a_credencial_incompleta | Segredo opcional ausente nao torna a credencial incompleta | |
| teste_varredura_nao_remove_temporario_de_processo_vivo | A varredura nao remove temporario de processo vivo | |
| teste_xdg_relativo_e_recusado | `XDG_CONFIG_HOME` relativo e recusado | |


## `tests/unit/cursor_estado_test.sh`

- **Alvo:** registro `cursor-*` do estado em `lib/state.sh` (cursor de listagem do `sync --receber`)
- **Modulo:** `lib/state.sh`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-7b-cursor`)
- **Regras de origem:** F-14; RF-111; RF-113(d); RF-117(e)(f); parecer do DBA C1, C2, C4, C8, C10, C11; log `docs/prompts/2026-10-21_0713_backlog-fase-7b-cursor.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** diretorio de estado temporario por caso, credencial e identidade sinteticas, registros escritos diretamente pelo teste; relogio controlado nos casos de vencimento
- **Comando:** `bash tests/run.sh tests/unit/cursor_estado_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_contexto_exige_cred_e_account_id | O contexto do cursor exige credencial e account_id; sem eles nao ha cursor | RF-111 |
| teste_chave_por_conta_raizes_e_assinatura_com_nul | A chave do registro distingue conta, raizes e assinatura de filtros e nao colide por separador | RF-111 |
| teste_gravacao_e_carga_entregam_o_retrato_depois_do_rodape | Gravar e carregar devolve o retrato remoto somente depois de conferir o rodape | RF-113(d) |
| teste_gravacao_recusa_cursor_fora_da_regex_e_teto | A gravacao recusa cursor fora da regex e acima do teto de tamanho | RF-111 |
| teste_registro_corrompido_e_descartado_e_apagado_so_fora_da_simulacao | Registro corrompido e descartado e so apagado fora da simulacao | RF-117(e) |
| teste_rodape_e_conferido_antes_do_uso_mutante | O rodape SHA-256 e conferido antes do uso (mutante: sem conferencia o teste falha) | C1 |
| teste_cabecalho_divergente_e_descartado | Cabecalho divergente da identidade esperada e descartado | RF-117(f) |
| teste_funcao_de_entrada_que_recusa_descarta | Funcao de entrada que recusa o contexto descarta o registro | C2 |
| teste_intocavel_nao_e_lido_nem_apagado | Registro que nao e arquivo regular do usuario nao e lido nem apagado | C4 |
| teste_vencido_sete_dias_cem_incrementais_e_relogio | Registro vencido por 7 dias, por 100 incrementais ou por relogio invertido e descartado | RF-113 |
| teste_listagem_le_so_o_cabecalho_e_nao_cria_nada | A listagem le apenas o cabecalho e nao cria nada | C8 |
| teste_poda_oito_dias_e_teto_cem_so_cursor | A poda remove cursores com mais de 8 dias e acima do teto de 100, e so cursores | C10 |
| teste_qa_b7b_01_raiz_remota_vazia_e_chave_valida | Raiz remota vazia gera chave valida | C11 |


## `tests/unit/debug_test.sh`

- **Alvo:** `lib/debug.sh`, ponto unico de emissao das linhas `debug:` em stderr
- **Modulo:** `debug_test`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `debug-transferencias`)
- **Regras de origem:** RF-156; RF-163(d); RF-164(b); TC-DBG-22; TC-DBG-27; TC-DBG-30; log `docs/prompts/2026-10-24_0330_debug-transferencias.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** Nao aplicavel: carrega a lib e captura o stderr da funcao; sem rede nem estado
- **Comando:** `bash tests/run.sh tests/unit/debug_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_aspas_e_barra_sao_escapadas | Aspas e barra invertida no valor saem escapadas na linha | TC-DBG-22 |
| teste_caractere_de_controle_vira_interrogacao_em_uma_so_linha | Caractere de controle vira `?` e a linha continua unica | TC-DBG-22 |
| teste_falha_de_escrita_em_stderr_nao_muda_o_resultado | Falha ao escrever em stderr nao altera o resultado da operacao | RF-164(b) |
| teste_linha_tem_prefixo_categoria_e_pares_em_ordem | A linha tem prefixo `debug:`, categoria e pares chave=valor na ordem dada | RF-156 |
| teste_nada_vai_ao_stdout | Nenhuma linha de debug vai ao stdout | RF-163(d) |
| teste_posicional_entra_sem_chave | Argumento posicional entra na linha sem chave | |
| teste_sem_debug_nada_e_escrito | Sem `--debug` nada e escrito | RF-156 |
| teste_valor_com_espaco_vai_entre_aspas | Valor com espaco sai entre aspas | |
| teste_valor_passa_pela_redacao | O valor passa pela redacao de segredos antes de sair | TC-DBG-27 |
| teste_valor_vazio_vai_entre_aspas | Valor vazio sai como aspas vazias | |


## `tests/unit/descritor_portavel_test.sh`

- **Alvo:** `lib/atributos.sh` (`dbx_atributo_fd`) e os chamadores em `lib/state.sh`, `lib/transfer.sh`, `lib/hash.sh`: conferencia de arquivo aberto pelo proprio descritor, sem `/dev/fd/<n>`, em GNU `stat` e BSD `stat`
- **Modulo:** `lib/atributos.sh`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `suporte-freebsd`)
- **Regras de origem:** RF-171(a); TC-FBSD-20; DIV-352; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplos de `stat` GNU e BSD no `PATH` (o duplo BSD devolve, para `/dev/fd/<n>`, um no proprio do fdescfs com dev/ino fixos); arquivos temporarios por caso
- **Comando:** `bash tests/run.sh tests/unit/descritor_portavel_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_atributo_fd_le_do_proprio_descritor_com_stat_bsd | `dbx_atributo_fd` le os atributos do proprio descritor usando `stat` BSD | |
| teste_atributo_fd_le_do_proprio_descritor_com_stat_gnu | `dbx_atributo_fd` le os atributos do proprio descritor usando `stat` GNU | |
| teste_auditoria_distingue_codigo_de_comentario | A auditoria de `/dev/fd` ignora comentarios e so acusa codigo | |
| teste_barreira_do_part_aceita_o_legitimo_com_stat_bsd | A barreira do `.part` aceita o arquivo legitimo com `stat` BSD | |
| teste_barreira_do_part_recusa_tamanho_acima_do_esperado | A barreira do `.part` recusa arquivo com tamanho acima do esperado | |
| teste_barreira_do_part_recusa_troca_do_arquivo_entre_a_abertura_e_o_uso | A barreira do `.part` recusa arquivo trocado entre a abertura e o uso | |
| teste_cursor_grava_e_carrega_com_stat_bsd | Gravar e carregar o registro de cursor funciona com `stat` BSD | |
| teste_duplo_devolve_no_do_fdescfs_para_dev_fd | O duplo de `stat` BSD devolve o no do fdescfs para `/dev/fd`, provando que quem ainda o usa falha | |
| teste_duplo_le_a_entrada_padrao_quando_f_nao_tem_operando | O duplo de `stat` BSD le a entrada padrao quando `-f` vem sem operando | |
| teste_leitor_limitado_e_trava_leem_com_stat_bsd | O leitor limitado e a trava leem o descritor corretamente com `stat` BSD | |
| teste_nenhum_caminho_do_produto_depende_de_dev_fd_variavel | Nenhum codigo do produto usa `/dev/fd/<n>` com descritor variavel | |


## `tests/unit/disponibilidade_test.sh`

- **Alvo:** `lib/disponibilidade.sh` e `dbx_http_sondar` em `lib/http.sh` (sonda de disponibilidade, reserva compartilhada entre processos, classificacao de causa)
- **Modulo:** disponibilidade_test
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `teste-de-disponibilidade`)
- **Regras de origem:** RF-149, RF-150, RF-152(a); TC-DSP-13..21, 22..25, 27; DIV-331; log `docs/prompts/2026-10-23_0900_teste-de-disponibilidade.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` no caminho de busca; diretorio compartilhado temporario para a marca da sonda; sem rede
- **Comando:** `bash tests/run.sh tests/unit/disponibilidade_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_aviso_de_sonda_invalida_do_auxiliar_sai_pelo_principal | O aviso de sonda invalida emitido no auxiliar chega ao stderr do processo principal | |
| teste_aviso_nao_e_consumido_com_stderr_descartado | O aviso pendente nao e consumido quando o stderr esta descartado | |
| teste_causa_enriquece_o_resumo_de_erro_sem_perder_o_original | A causa da indisponibilidade enriquece o resumo do erro sem perder a mensagem original | |
| teste_classificar_tabela_unica_de_classes_e_codigos | A classificacao usa uma tabela unica de classes de causa e codigos de saida | RF-150 |
| teste_diretorio_compartilhado_ausente_sonda_localmente | Sem diretorio compartilhado, a sonda roda localmente no proprio processo | RF-152(a) |
| teste_mensagens_sem_segredo_url_com_parametro_nem_corpo | As mensagens nao contem segredo, URL com parametro nem corpo de resposta | |
| teste_motivo_da_autenticacao_preserva_o_original | O motivo de falha de autenticacao preserva o texto original ao receber a causa | |
| teste_perdedor_da_reserva_espera_e_recebe_a_causa_do_vencedor | O processo que perde a reserva espera e recebe a causa do vencedor | RF-152(a) |
| teste_perdedor_sem_resultado_no_prazo_da_causa_indeterminada | Perdedor que nao recebe resultado no prazo trata a causa como indeterminada | RF-152(a) |
| teste_portao_fechado_sem_terminal_e_com_as_chaves | O portao de interatividade fica fechado sem terminal e conforme as chaves de configuracao | |
| teste_reserva_orfa_nao_espera_o_prazo | Reserva orfa (dono morto) nao faz esperar o prazo completo | RF-152(a) |
| teste_resultado_fora_do_vocabulario_vira_indeterminada | Resultado fora do vocabulario conhecido vira causa indeterminada | |
| teste_sonda_invalida_avisa_uma_vez_sem_o_valor | Sonda configurada de forma invalida avisa uma unica vez, sem exibir o valor | |
| teste_sonda_uma_por_execucao | A sonda e feita uma unica vez por execucao (memoizada) | RF-149 |
| teste_sonda_uma_por_execucao_entre_processos_com_marca_compartilhada | Entre processos que compartilham a marca, so uma sonda e feita | RF-152(a) |
| teste_sonda_url_padrao_vazia_e_invalida | URL padrao da sonda, vazia ou invalida, e tratada conforme o contrato | |
| teste_sondar_qualquer_status_http_responde | Qualquer status HTTP recebido conta como servico respondendo | RF-149 |
| teste_sondar_requisicao_minima_sem_segredo_nem_repeticao | A sonda faz uma requisicao minima, sem segredo e sem retentativa | RF-149 |
| teste_sondar_sem_resposta_nao_responde_e_codigo_zero | Sem resposta, a sonda indica que nao respondeu e retorna codigo zero | RF-149 |


## `tests/unit/errors_test.sh`

- **Alvo:** `lib/errors.sh` (taxonomia de erro, codigos de saida, politica de retentativa, redacao de segredos, idempotencia)
- **Modulo:** `errors`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD; commit `a03d2c0` "first commit", sem log de prompt)
- **Regras de origem:** RF-29; RF-35 (contrato congelado dos codigos); RNF-08; DIV-58 (tags da recuperacao); `docs/testes/mapa-modulos.md` (Regra 1: `errors` e carregado por toda a suite)
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** Nao aplicavel: lib pura; segredos sinteticos e processos `bash -c` filhos para os casos de ambiente
- **Comando:** `bash tests/run.sh tests/unit/errors_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_400_nunca_sofre_retentativa | HTTP 400 nunca recebe retentativa | |
| teste_401_renova_token_uma_unica_vez | HTTP 401 pede renovacao do token uma unica vez | |
| teste_408_e_retentavel | HTTP 408 e retentavel | |
| teste_409_nao_sofre_retentativa_exceto_cursor_invalidado | HTTP 409 nao e retentado, exceto o caso de cursor invalidado | |
| teste_429_respeita_retry_after | HTTP 429 respeita o `Retry-After` informado | |
| teste_5xx_classifica_como_erro_remoto | Respostas 5xx sao classificadas como erro remoto | |
| teste_5xx_segue_a_idempotencia_como_a_falha_de_transporte | 5xx segue a regra de idempotencia da operacao, como a falha de transporte | |
| teste_arquivo_de_teste_com_filtro_sem_correspondencia_reprova | O runner reprova quando o filtro de arquivo nao casa nenhum teste | protocolo-tdd Regra 9 |
| teste_aspa_escapada_em_senha_com_pontuacao | Aspa escapada dentro de senha com pontuacao e mascarada por inteiro | |
| teste_aspa_escapada_no_valor_nao_encerra_o_mascaramento | Aspa escapada no valor nao encerra o mascaramento antes do fim | |
| teste_ausencia_de_resposta_http_e_falha_de_rede | Ausencia de resposta HTTP e classificada como falha de rede | |
| teste_byte_de_controle_em_chave_sensivel_nao_contorna_a_redacao | Byte de controle dentro do nome de chave sensivel nao contorna a redacao | |
| teste_byte_de_controle_nao_e_apagado_silenciosamente | Byte de controle no texto nao e apagado em silencio | |
| teste_cabecalho_sensivel_preserva_o_nome_e_o_restante_da_linha | Cabecalho sensivel mascara so o valor e preserva o nome e o resto da linha | |
| teste_chave_code_isolada_continua_sendo_redigida | A chave `code` isolada continua sendo redigida | |
| teste_chaves_que_apenas_terminam_em_code_nao_sao_redigidas | Chaves que apenas terminam em `code` nao sao redigidas | |
| teste_classe_desconhecida_e_recusada | Classe de erro desconhecida e recusada | |
| teste_classificacao_e_politica_nao_criam_subshell_por_dentro | Classificacao e politica nao criam subshell internamente | |
| teste_classificacao_exige_codigo_http_numerico | A classificacao exige codigo HTTP numerico | |
| teste_classificacao_por_codigo_http_sem_resumo | O codigo HTTP sozinho, sem resumo, classifica o erro | |
| teste_classificacao_publica_a_classe_sem_subshell | A classificacao publica a classe sem recorrer a subshell | |
| teste_codigos_de_saida_nao_colidem_entre_classes | Classes distintas nunca compartilham o mesmo codigo de saida | RF-35 |
| teste_codigos_ficam_fora_da_faixa_reservada_pelo_shell | Os codigos de saida ficam fora da faixa reservada pelo shell | |
| teste_custo_da_redacao_com_corpo_denso_e_limitado | A redacao de corpo denso termina em tempo limitado | |
| teste_custo_da_redacao_cresce_proporcionalmente_a_entrada | O custo da redacao cresce de forma proporcional a entrada | |
| teste_deslocamento_incorreto_pede_retomada_e_nao_reinicio | Deslocamento incorreto da sessao pede retomada, nao reinicio | |
| teste_detalhe_com_multiplas_linhas_nao_e_truncado | Detalhe de erro com varias linhas nao e truncado | |
| teste_div58_in_progress_e_repetido_mesmo_em_escrita | A tag `in_progress` e repetida mesmo em operacao de escrita | DIV-58 |
| teste_div58_tags_da_recuperacao_mapeadas_a_classes_existentes | Tags da recuperacao sao mapeadas a classes que ja existem | DIV-58 |
| teste_entrada_acima_do_teto_de_analise_e_truncada_com_redacao | Entrada acima do teto de analise e truncada, ainda com redacao | |
| teste_erro_do_servidor_ignora_o_resumo | Erro do servidor e classificado sem depender do resumo | |
| teste_esquema_de_autenticacao_exige_espaco_antes_da_credencial | O esquema de autenticacao so casa com espaco antes da credencial | |
| teste_falha_de_transporte_depende_da_idempotencia_da_operacao | Falha de transporte so e retentada se a operacao e idempotente | |
| teste_falha_de_transporte_em_operacao_nao_idempotente_e_indeterminada | Falha de transporte em operacao nao idempotente e classificada como indeterminada | |
| teste_fidelidade_byte_a_byte_para_entrada_aceita | Entrada aceita sem segredo sai identica byte a byte | |
| teste_idempotencia_nao_altera_as_demais_classes | A idempotencia nao altera a politica das demais classes | |
| teste_idempotencia_omitida_assume_o_lado_seguro | Idempotencia omitida assume o lado seguro (nao idempotente) | |
| teste_mensagem_de_classe_invalida_e_recusada | Pedir mensagem de uma classe invalida e recusado | |
| teste_mensagem_de_configuracao_nao_presume_credencial | A mensagem de configuracao nao presume problema de credencial | |
| teste_mensagem_e_acionavel_e_inclui_o_detalhe | A mensagem de erro e acionavel e inclui o detalhe | |
| teste_mensagem_nao_vaza_segredo_conhecido | A mensagem de erro nao contem segredo conhecido | protocolo-tdd Regra 6 |
| teste_nao_depende_de_jq_nem_de_lib_json | A lib funciona sem `jq` e sem `lib/json.sh` | |
| teste_nenhuma_classe_retentavel_devolve_politica_nenhuma | Classe nao retentavel devolve politica nenhuma | |
| teste_politica_concorda_com_a_classificacao_em_erro_remoto | A politica concorda com a classificacao para erro remoto | |
| teste_politica_concorda_com_a_classificacao_em_limite_de_taxa | A politica concorda com a classificacao para limite de taxa | |
| teste_politica_publica_o_valor_sem_subshell | A politica publica o valor sem subshell | |
| teste_politicas_pertencem_ao_conjunto_congelado | Toda politica devolvida pertence ao conjunto congelado | RF-35 |
| teste_prefixo_e_nao_igualdade | A tag casa por prefixo, nao por igualdade | |
| teste_prefixo_respeita_a_fronteira_do_componente | O prefixo respeita a fronteira do componente da tag | |
| teste_qualificador_nao_e_confundido_com_tag | Qualificador de tag nao e confundido com tag | |
| teste_qualificadores_de_uniao_sao_removidos_antes_do_casamento | Qualificadores de uniao sao removidos antes do casamento da tag | |
| teste_qualificadores_encadeados_sao_removidos | Qualificadores encadeados sao todos removidos | |
| teste_redacao_de_cabecalho_authorization | Cabecalho `Authorization` e mascarado | protocolo-tdd Regra 6 |
| teste_redacao_de_chave_com_hifen | Chave sensivel com hifen no nome e mascarada | |
| teste_redacao_de_cookie | Cookie e mascarado | protocolo-tdd Regra 6 |
| teste_redacao_de_credencial_em_linha_de_comando_curl | Credencial em linha de comando do `curl` e mascarada | protocolo-tdd Regra 6 |
| teste_redacao_de_entrada_muito_grande_e_limitada | Redacao de entrada muito grande e limitada em tamanho | |
| teste_redacao_de_refresh_token_em_json | `refresh_token` em JSON e mascarado | protocolo-tdd Regra 6 |
| teste_redacao_de_token_em_json | Token em JSON e mascarado | protocolo-tdd Regra 6 |
| teste_redacao_de_token_entre_aspas_em_prosa | Token entre aspas dentro de prosa e mascarado | |
| teste_redacao_de_token_no_formato_sl_u_consome_o_corpo_inteiro | Token no formato `sl.u` e mascarado por inteiro | |
| teste_redacao_de_valor_em_arranjo | Valor sensivel dentro de arranjo JSON e mascarado | |
| teste_redacao_de_valor_json_sem_aspas | Valor sensivel JSON sem aspas e mascarado | |
| teste_redacao_em_corpo_urlencoded | Segredo em corpo `urlencoded` e mascarado | |
| teste_redacao_em_querystring | Segredo em querystring e mascarado | |
| teste_redacao_ignora_caixa_do_prefixo_de_token | O prefixo de token e reconhecido sem distinguir caixa | |
| teste_redacao_preserva_estrutura_do_texto | A redacao preserva a estrutura do texto ao redor | |
| teste_redacao_preserva_texto_sem_segredo | Texto sem segredo passa pela redacao inalterado | |
| teste_remocao_de_qualificador_nao_afrouxa_a_fronteira_de_componente | Remover qualificador nao afrouxa a fronteira de componente da tag | |
| teste_resumo_com_espacos_e_quebras_de_linha_nao_quebra_a_classificacao | Resumo com espacos e quebras de linha nao quebra a classificacao | |
| teste_saida_permanece_limitada_apos_a_redacao | A saida continua limitada em tamanho depois da redacao | |
| teste_segredo_em_linha_posterior_tambem_e_redigido | Segredo em linha posterior a primeira tambem e mascarado | |
| teste_tabela_de_codigos_de_saida_e_congelada | A tabela de classes e codigos de saida e congelada em valores literais | RF-35 |
| teste_tag_other_e_o_desconhecido_declarado_da_uniao | A tag `other` e o desconhecido declarado da uniao de tags | |
| teste_tags_de_autenticacao_e_escopo | Tags de autenticacao e de escopo caem nas classes corretas | |
| teste_tags_de_caminho_malformado_sao_uso_invalido | Tags de caminho malformado sao classificadas como uso invalido | |
| teste_tags_relevantes_documentadas_no_system_design | As tags relevantes documentadas no System Design estao mapeadas | |
| teste_teto_de_redacao_nao_e_afrouxavel_pelo_ambiente | O teto de redacao nao pode ser afrouxado por variavel de ambiente | |
| teste_toda_classe_tem_codigo_e_mensagem | Toda classe de erro tem codigo de saida e mensagem | |
| teste_truncagem_nao_deixa_segredo_escapar | A truncagem da entrada nao deixa segredo parcial escapar | |
| teste_valor_invalido_de_idempotencia_e_recusado | Valor invalido de idempotencia e recusado | |
| teste_valor_sem_delimitador_de_fechamento_e_mascarado_ate_o_fim | Valor sem delimitador de fechamento e mascarado ate o fim da entrada | |


## `tests/unit/filtro_test.sh`

- **Alvo:** `lib/filtro.sh`: casamento de padroes estilo gitignore sem diferenca de caixa, validacao de padroes, filtros de data e de tamanho
- **Modulo:** `filtro_test`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-4-filtros-e-banda`)
- **Regras de origem:** RF-79; RF-80(a); RF-81; TC-FLT; TC-FES-01; TC-FES-03; TC-FDT; DIV-94; DIV-103; log `docs/prompts/2026-10-19_2141_backlog-fase-4-filtros-e-banda.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** `lib/errors.sh` e `lib/filtro.sh` carregados em processo; sem rede, disco nem estado; processos proprios sob `LC_ALL=C`, `TZ` e localidade ausente; `$DBX_TESTES_TMP` para a sentinela de TC-FLT-16
- **Comando:** `bash tests/run.sh tests/unit/filtro_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_flt01_padrao_sem_barra_casa_o_nome_em_qualquer_nivel | Padrao sem barra casa o nome em qualquer nivel da arvore | TC-FLT-01 |
| teste_flt02_estrela_nao_cruza_barra_e_casa_nome_com_ponto | `*` nao atravessa barra e casa nomes com ponto | TC-FLT-02 |
| teste_flt03_interrogacao_casa_um_caractere | `?` casa exatamente um caractere | TC-FLT-03 |
| teste_flt04_conjuntos_faixas_e_negacao_nunca_casam_barra | Conjuntos, faixas e negacao de conjunto nunca casam a barra | TC-FLT-04 |
| teste_flt05_duas_estrelas_no_inicio_no_fim_no_meio_e_em_outra_posicao | `**` no inicio, no fim, no meio e em outra posicao tem a semantica prevista | TC-FLT-05 |
| teste_flt06_barra_no_inicio_ou_no_meio_ancora_na_raiz | Barra no inicio ou no meio ancora o padrao na raiz | TC-FLT-06 |
| teste_flt07_barra_final_casa_so_pasta_e_tudo_abaixo_dela | Barra final casa so pasta e tudo abaixo dela | TC-FLT-07 |
| teste_flt08_barra_invertida_torna_literal_o_caractere_seguinte | Barra invertida torna literal o caractere seguinte | TC-FLT-08 |
| teste_flt09_sem_caixa_no_ascii_e_faixa_depois_da_dobra | O casamento ignora a caixa em ASCII, inclusive em faixas | TC-FLT-09 |
| teste_flt10_sem_caixa_unicode_sob_lc_all_c_sem_vazar_a_localidade | Dobra de caixa Unicode funciona sob `LC_ALL=C` sem deixar a localidade alterada | TC-FLT-10 |
| teste_flt11_localidade_ausente_vale_so_o_ascii_e_interrogacao_e_um_byte | Sem localidade UTF-8 vale so o ASCII e `?` casa um byte | TC-FLT-11 |
| teste_flt12_nfc_e_nfd_sao_distintos | Formas NFC e NFD do mesmo texto sao tratadas como nomes distintos (limitacao declarada) | TC-FLT-12 |
| teste_flt_nome_que_nao_e_utf8_valido_ainda_casa_por_bytes | Nome com byte invalido em UTF-8 ainda casa, por bytes | |
| teste_qa_b4_01_queda_para_bytes_usa_a_mesma_dobra_do_padrao | A queda para bytes usa a mesma dobra de caixa aplicada ao padrao | QA-B4-01 |
| teste_div103_incluir_impreciso_em_bytes_nunca_casa_a_mais | Em bytes, padrao de inclusao impreciso nunca inclui a mais | DIV-103 |
| teste_qa_b4_01_interrogacao_e_conjunto_negado_casam_um_caractere_inteiro_em_bytes | Em bytes, `?` e conjunto negado casam um caractere acentuado inteiro | QA-B4-01 |
| teste_flt13_malformados_sao_uso_invalido | Padroes malformados sao erro de uso | TC-FLT-13 |
| teste_flt14_mensagem_nomeia_a_opcao_e_cita_o_padrao_sem_byte_cru | A mensagem de erro nomeia a opcao e cita o padrao sem byte de controle cru | TC-FLT-14 |
| teste_flt15_limites_de_quantidade_e_de_tamanho | Limites de quantidade e de tamanho de padroes sao aplicados | TC-FLT-15 |
| teste_flt16_padrao_e_dado_nunca_codigo | Padrao com `$(...)`, crase e `$HOME` e dado, nunca executado | TC-FLT-16 |
| teste_flt17_cerquilha_literal_e_espaco_final_preservado | `#` inicial e literal e espaco final do padrao e preservado | TC-FLT-17 |
| teste_fes01_exclusao_vence_inclusao_nas_duas_ordens | Exclusao vence inclusao independentemente da ordem declarada | TC-FES-01 |
| teste_fes02_com_incluir_so_o_que_casa_entra_em_qualquer_profundidade | Com inclusao declarada, so entra o que casa, em qualquer profundidade | TC-FES-02 |
| teste_fes03_pasta_casada_por_incluir_inclui_o_conteudo | Pasta casada por inclusao inclui o conteudo | TC-FES-03 |
| teste_fes_pasta_excluida_e_o_item_contado_pelo_conteudo | Pasta excluida e contada pelo seu conteudo | |
| teste_fes18_padrao_sem_casamento_e_listado_para_o_aviso | Padrao que nao casou nada e listado para o aviso | TC-FES-18 |
| teste_flt_sem_filtro_tudo_esta_no_escopo | Sem filtro configurado, tudo esta no escopo | |
| teste_fdt01_datas_validas_e_invalidas | Datas validas sao aceitas e as invalidas recusadas | TC-FDT-01 |
| teste_fdt02_fdt07_limites_inclusivos | Os limites da faixa de data sao inclusivos | TC-FDT-02; TC-FDT-07 |
| teste_fdt03_fdt07_faixa_invertida_e_uso_invalido | Faixa de data invertida e erro de uso | TC-FDT-03; TC-FDT-07 |
| teste_fdt04_epoca_vira_utc_sem_utilitario_e_sem_depender_do_fuso | A conversao de data para epoca e em UTC, sem utilitario externo e sem depender do fuso | TC-FDT-04 |
| teste_fdt06_tamanhos_validos_e_invalidos | Tamanhos validos sao aceitos e os invalidos recusados | TC-FDT-06 |
| teste_fdt_sem_carimbo_conhecido_o_arquivo_fica_fora_da_faixa_de_data | Arquivo sem carimbo conhecido (ausente ou malformado) fica fora da faixa de data | |
| teste_lib_filtro_e_pura_sem_rede_disco_estado_nem_eval | Auditoria: `lib/filtro.sh` nao usa rede, disco, estado nem `eval` | DIV-94 |


## `tests/unit/harness_test.sh`

- **Alvo:** `tests/support/harness.sh` e `tests/run.sh`: assercoes e executor do arcabouco de teste
- **Modulo:** `harness_test`
- **Camada:** unitario
- **Autoria:** Senior Developer (commit `64e6139`, `test: fixa todas as assercoes do arcabouco nos dois sentidos`; sem log de prompt)
- **Regras de origem:** Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste (commit `64e6139`); protocolo-tdd Regra 9 (parada no primeiro erro)
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** diretorio temporario com copia de `tests/run.sh` e do harness e arquivos `a_test.sh` e `b_test.sh` fabricados; segredos sinteticos; variavel `MARCA_DIR`
- **Comando:** `bash tests/run.sh tests/unit/harness_test.sh`
- **Observacoes:** `teste_a_reprova`, `teste_b_nao_pode_rodar` e `teste_c_nao_pode_rodar` sao funcoes fabricadas dentro de heredocs dos casos de parada no primeiro erro (fixtures); o descobridor as lista como casos e por isso constam na tabela. Idem `teste_deixa_lixo` e `teste_ve_o_lixo_do_anterior`, fabricadas no caso da area temporaria por arquivo (demanda `investigar-retomada-download`).

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_a_reprova | Caso fabricado no arquivo `a_test.sh` do cenario de parada: reprova de proposito (fixture, nao roda na suite real) | protocolo-tdd Regra 9 |
| teste_arcabouco_para_no_primeiro_caso_com_reprovacao | O arcabouco nao executa o caso seguinte depois do primeiro caso reprovado | protocolo-tdd Regra 9 |
| teste_assercao_contem_reprova_quando_o_trecho_falta | `assert_contem` reprova quando o trecho esperado falta | |
| teste_assercao_de_arquivo_ausente_reprova_quando_o_arquivo_existe | A assercao de arquivo ausente reprova quando o arquivo existe | |
| teste_assercao_de_arquivo_existe_reprova_quando_o_arquivo_falta | A assercao de arquivo existente reprova quando o arquivo falta | |
| teste_assercao_de_segredo_aprova_quando_ausente | A assercao de segredo aprova quando o segredo esta ausente do texto | |
| teste_assercao_de_segredo_recusa_agulha_vazia | A assercao de segredo recusa agulha vazia | |
| teste_assercao_de_segredo_reprova_quando_presente | A assercao de segredo reprova quando o segredo esta presente | |
| teste_assercao_de_status_reprova_quando_o_codigo_difere | A assercao de status reprova quando o codigo de saida difere do esperado | |
| teste_assercao_diferente_reprova_quando_os_valores_sao_iguais | `assert_diferente` reprova quando os valores sao iguais | |
| teste_assercao_igual_reprova_quando_os_valores_diferem | `assert_igual` reprova quando os valores diferem | |
| teste_assercao_nao_contem_reprova_quando_o_trecho_esta_presente | `assert_nao_contem` reprova quando o trecho esta presente | |
| teste_b_nao_pode_rodar | Caso fabricado que grava uma marca se rodar; a prova e a marca nao existir apos a reprova do caso anterior | protocolo-tdd Regra 9 |
| teste_c_nao_pode_rodar | Caso fabricado no `b_test.sh` que grava uma marca se rodar; a prova e a marca nao existir apos a reprova do arquivo anterior | protocolo-tdd Regra 9 |
| teste_cada_arquivo_tem_area_propria_removida_ao_terminar | O executor da a cada arquivo de teste uma area temporaria propria e a remove ao fim dele: o que um arquivo deixa nao chega ao seguinte (causa da falha do `retomada_download` na suite completa: area unica acumulava 9,4 GB num /tmp tmpfs de 9,8 GB) | log `docs/prompts/2026-10-31_1900_investigar-retomada-download.md` |
| teste_deixa_lixo | Caso fabricado no `x_test.sh` do cenario da area por arquivo: grava 1 MiB na sua area e anota o caminho (fixture, nao roda na suite real) | log `docs/prompts/2026-10-31_1900_investigar-retomada-download.md` |
| teste_diario_nao_recebe_segredo_sem_forma_reconhecivel | O diario de reprovacoes em disco nao recebe segredo mesmo sem forma reconhecivel | |
| teste_diario_preserva_o_diagnostico_do_caso | O diario preserva o diagnostico do caso reprovado | |
| teste_executor_para_no_primeiro_arquivo_com_reprovacao | O executor nao roda o arquivo seguinte depois do primeiro arquivo reprovado | protocolo-tdd Regra 9 |
| teste_falha_de_segredo_informa_posicao_e_comprimento | A falha da assercao de segredo informa posicao e comprimento, nao o valor | |
| teste_falha_de_segredo_mascara_todas_as_ocorrencias | A falha mascara todas as ocorrencias do segredo no diagnostico | |
| teste_falha_de_segredo_nunca_imprime_o_segredo | A falha da assercao de segredo nunca imprime o segredo | |
| teste_falha_de_segredo_preserva_o_restante_do_diagnostico | A falha mascara so o segredo e preserva o resto do diagnostico | |
| teste_filtro_sem_correspondencia_continua_reprovando | Filtro sem arquivo correspondente continua reprovando a execucao | protocolo-tdd Regra 9 |
| teste_nenhum_arquivo_de_teste_redefine_uma_funcao_propria | Auditoria: nenhum arquivo de teste redefine funcao do arcabouco | |
| teste_primitiva_de_falha_encerra_o_caso_com_status_um | A primitiva de falha encerra o caso com status 1 | |
| teste_segredo_com_metacaractere_de_glob_e_tratado_literalmente | Segredo com metacaractere de glob e comparado literalmente | |
| teste_ve_o_lixo_do_anterior | Caso fabricado no `y_test.sh`: marca se o arquivo do caso anterior sobreviveu ou se recebeu a mesma area (fixture) | log `docs/prompts/2026-10-31_1900_investigar-retomada-download.md` |


## `tests/unit/hash_test.sh`

- **Alvo:** `lib/hash.sh`: `content_hash` da Dropbox (blocos de 4 MiB), API incremental, comparacao e identidade do arquivo
- **Modulo:** `hash`
- **Camada:** unitario
- **Autoria:** Senior Developer (commit `a03d2c0`, `first commit`; sem log de prompt)
- **Regras de origem:** RF-33; RF-34; `docs/registros/vetores-content-hash.md` (vetores derivados de oraculo independente em Python); log de prompt: Nao aplicavel: anterior a trilha do protocolo
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** arquivos temporarios gerados na suite (vazio, 1 byte, 4 MiB exatos, multiplos blocos); vetores esperados fixos no arquivo; `lib/errors.sh` carregado; area temporaria da suite
- **Comando:** `bash tests/run.sh tests/unit/hash_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_acumular_bloco_recusa_arquivo_ilegivel | A acumulacao de bloco recusa arquivo ilegivel | |
| teste_acumular_encerrar_exige_area_de_trabalho_gravavel | Encerrar a acumulacao exige area de trabalho gravavel | |
| teste_api_incremental_nao_concatena_resumos_em_hexadecimal | A API incremental nao concatena resumos em hexadecimal (usa os bytes) | RF-33 |
| teste_api_incremental_reproduz_o_calculo_de_uma_passada | A API incremental reproduz o calculo de uma passada | RF-33 |
| teste_argumento_ausente_falha_com_status_de_uso | Chamada sem argumento falha com o status de uso | |
| teste_arquivo_com_multiplos_blocos_e_resto | Arquivo com varios blocos e resto tem o hash esperado | RF-33 |
| teste_arquivo_com_um_byte_a_menos_que_um_bloco | Arquivo de um bloco menos um byte tem o hash esperado | RF-33 |
| teste_arquivo_de_bloco_exato | Arquivo de exatamente um bloco tem o hash esperado | RF-33 |
| teste_arquivo_de_bloco_mais_um_byte | Arquivo de um bloco mais um byte tem o hash esperado | RF-33 |
| teste_arquivo_de_um_byte | Arquivo de um byte tem o hash esperado | RF-33 |
| teste_arquivo_grande_nao_e_carregado_em_memoria | Arquivo grande e processado em fluxo, sem carga integral em memoria | |
| teste_arquivo_inexistente_falha_com_status_dedicado | Arquivo inexistente falha com status dedicado | |
| teste_arquivo_vazio | Arquivo vazio tem o hash esperado | RF-33 |
| teste_backend_invalido_vindo_do_ambiente_e_recusado | Backend de hash invalido vindo do ambiente e recusado | |
| teste_backend_valido_vindo_do_ambiente_e_aceito | Backend de hash valido vindo do ambiente e aceito | |
| teste_bytes_nulos_nao_truncam_o_conteudo | Bytes nulos no conteudo nao truncam o calculo | |
| teste_calculo_de_uma_passada_passa_pela_api_incremental | O calculo de uma passada e implementado sobre a API incremental | |
| teste_comparacao_ignora_caixa_mas_nao_valores_diferentes | A comparacao ignora a caixa das letras hexadecimais mas distingue valores diferentes | RF-34 |
| teste_comparacao_recusa_valor_malformado | A comparacao recusa valor malformado | RF-34 |
| teste_contagem_confere_com_o_tamanho_real_do_arquivo | O total de bytes lidos confere com o tamanho real do arquivo | |
| teste_conversao_de_escapes_e_linear_na_quantidade_de_blocos | A conversao de escapes cresce de forma linear com a quantidade de blocos | |
| teste_diretorio_nao_e_aceito_como_origem | Diretorio nao e aceito como origem | |
| teste_expoe_o_total_de_bytes_lidos | O calculo expoe o total de bytes lidos de arquivo | |
| teste_expoe_o_total_de_bytes_lidos_a_partir_de_fluxo | O calculo expoe o total de bytes lidos a partir de fluxo | |
| teste_falha_da_area_temporaria_e_erro_de_configuracao | Falha da area temporaria e erro de configuracao | |
| teste_falha_do_leitor_nao_produz_hash_com_status_zero | Falha do leitor nunca produz hash com status 0 | |
| teste_fluxo_a_partir_de_cano_sem_arquivo_intermediario | Hash a partir de cano e feito sem arquivo intermediario | |
| teste_fluxo_e_arquivo_produzem_o_mesmo_valor | Fluxo e arquivo com o mesmo conteudo produzem o mesmo hash | |
| teste_fluxo_vazio | Fluxo vazio tem o hash esperado | RF-33 |
| teste_identidade_de_caminho_inexistente_falha_sem_publicar | Identidade de caminho inexistente falha sem publicar valor | |
| teste_identidade_mora_no_dominio_e_nao_em_quem_a_consome | A identidade do arquivo e calculada em `lib/hash.sh`, nao em quem a consome | |
| teste_identidade_traz_mtime_e_ctime_com_nanossegundos_dispositivo_inode_e_tamanho | A identidade traz mtime e ctime em nanossegundos, dispositivo, inode e tamanho | |
| teste_nao_concatena_resumos_em_hexadecimal_com_bloco_mais_um | Com bloco mais um byte, os resumos de bloco nao sao concatenados em hexadecimal | RF-33 |
| teste_nao_concatena_resumos_em_hexadecimal_com_dois_blocos | Com dois blocos, os resumos de bloco nao sao concatenados em hexadecimal | RF-33 |
| teste_nao_deixa_residuo_temporario | O calculo nao deixa residuo temporario | |
| teste_nome_de_arquivo_com_espacos_e_caracteres_especiais | Nome de arquivo com espacos e caracteres especiais e processado | |
| teste_nome_de_arquivo_com_quebra_de_linha | Nome de arquivo com quebra de linha e processado | |
| teste_origem_pode_ser_um_cano_e_nao_apenas_arquivo_comum | A origem pode ser um cano, nao apenas arquivo comum | |
| teste_reescrita_no_mesmo_segundo_com_mesmo_tamanho_muda_a_identidade | Reescrita no mesmo segundo e com mesmo tamanho muda a identidade | |
| teste_saida_tem_64_caracteres_hexadecimais_minusculos | A saida tem 64 caracteres hexadecimais minusculos | RF-33 |
| teste_status_do_componente_seguem_a_taxonomia_de_erro | Os status do componente seguem a taxonomia de erros | |
| teste_tamanho_de_bloco_e_4_mib | O tamanho de bloco e 4 MiB | RF-33 |
| teste_um_unico_bloco_nao_e_o_sha256_do_proprio_conteudo | Com um unico bloco, o hash nao e o SHA-256 do proprio conteudo (ha segundo nivel de hash) | RF-33 |
| teste_valida_formato_de_content_hash | A validacao reconhece o formato de `content_hash` (64 hexadecimais) | RF-34 |


## `tests/unit/hash_vetor_oficial_test.sh`

- **Alvo:** `lib/hash.sh` (`content_hash` da Dropbox) contra o arquivo de exemplo oficial da Dropbox
- **Modulo:** hash_vetor_oficial
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `first commit`)
- **Regras de origem:** RF-34 (criterio de aceite: vetor oficial da Dropbox); Nao aplicavel como log de prompt: anterior a trilha do protocolo
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** copia local do arquivo oficial apontada por `DBX_TESTE_ARQUIVO_OFICIAL`, ou baixada se `DBX_TESTES_REDE=1`; o SHA-256 do arquivo e conferido antes da comparacao; sem nenhuma das duas condicoes o teste e PULADO
- **Comando:** `bash tests/run.sh tests/unit/hash_vetor_oficial_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_vetor_oficial_de_content_hash | O `content_hash` do arquivo oficial publicado pela Dropbox e igual ao valor oficial | RF-34 |
| teste_vetor_oficial_por_fluxo | O `content_hash` calculado por fluxo (entrada lida em partes) do arquivo oficial e igual ao valor oficial | RF-34 |


## `tests/unit/http_fd_curl_real_test.sh`

- **Alvo:** `lib/http.sh`: destino `fd:n` e saida padrao do download, com o `curl` real do sistema (URL `file://`)
- **Modulo:** `http_fd_curl_real`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `suporte-freebsd`)
- **Regras de origem:** RF-171; RF-166..172; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** `curl` real resolvido antes de qualquer duble no `PATH`; origens `file://` em diretorio temporario; sem rede; `.part` vazio ou com prefixo criado no caso
- **Comando:** `bash tests/run.sh tests/unit/http_fd_curl_real_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_fd_part_vazio_recebe_os_bytes_da_origem | O download por descritor num `.part` vazio recebe os bytes da origem (e nao o arquivo de erros) | RF-171 |
| teste_fd_part_com_prefixo_preserva_e_anexa_o_resto | Com `.part` ja com prefixo, o prefixo e preservado e o resto e anexado | RF-171 |
| teste_fd_url_inexistente_falha_sem_mensagem_no_part | URL inexistente falha sem escrever mensagem de erro no `.part` | RF-171 |
| teste_saida_padrao_recebe_os_bytes_da_origem | Download para a saida padrao recebe os bytes da origem | RF-171 |


## `tests/unit/http_test.sh`

- **Alvo:** `lib/http.sh` (ponto unico de saida de rede: paginacao, retentativa, recuo, `Retry-After`, classificacao de erro, canal do segredo)
- **Modulo:** http
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `feat(http): cliente com paginacao, retentativa e contexto isolado`)
- **Regras de origem:** RNF-14 (a suite padrao nao usa rede); Nao aplicavel como log de prompt: anterior a trilha do protocolo; comportamento inferido do codigo do teste
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `curl` injetado no caminho de busca que fabrica apenas os bytes da resposta; segredos sinteticos; `sleep` substituido para nao esperar tempo real; sem rede
- **Comando:** `bash tests/run.sh tests/unit/http_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_429_com_retry_after_de_5_espera_ao_menos_5_segundos | Resposta 429 com `Retry-After` de 5 espera ao menos 5 segundos antes de repetir | |
| teste_ambos_os_caminhos_registram_o_identificador_de_correlacao | Os caminhos de sucesso e de erro registram o identificador de correlacao da resposta | |
| teste_area_temporaria_da_requisicao_nasce_restrita | A area temporaria da requisicao e criada com permissao restrita ao dono | |
| teste_chamada_de_colecao_sem_limite_e_recusada | Chamada de colecao sem limite explicito e recusada | |
| teste_codigo_de_saida_da_requisicao_segue_a_taxonomia | O codigo de saida da requisicao segue a taxonomia de erros do projeto | |
| teste_conducao_da_requisicao_nao_captura_a_taxonomia_por_subshell | A conducao da requisicao nao captura o codigo da taxonomia por subshell, preservando o status | |
| teste_contrato_conexao_recusada_ainda_produz_codigo_zerado | Contrato: conexao recusada produz codigo HTTP zerado e e tratada como falha de rede | |
| teste_contrato_corpo_ilegivel_produz_status_de_defeito_nosso | Contrato: corpo ilegivel produz status de defeito nosso e nao de rede | |
| teste_contrato_opcoes_de_formulario_sao_aceitas_pelo_cliente_real | Contrato: as opcoes de formulario geradas sao aceitas pelo `curl` real | |
| teste_contrato_opcoes_de_token_sao_aceitas_pelo_cliente_real | Contrato: as opcoes de token geradas sao aceitas pelo `curl` real | |
| teste_contrato_opcoes_malformadas_produzem_status_de_defeito_nosso | Contrato: opcoes malformadas produzem status de defeito nosso | |
| teste_corpo_acima_do_teto_reduz_o_limite_e_repete | Corpo acima do teto reduz o limite da pagina e repete a chamada | |
| teste_corpo_de_erro_nao_destroi_listagem_em_curso | Corpo de erro nao destroi a listagem ja acumulada em curso | |
| teste_defeito_do_cliente_nao_e_classificado_como_falha_de_rede | Defeito do cliente `curl` nao e classificado como falha de rede | |
| teste_e_o_unico_ponto_de_saida_de_rede | `lib/http.sh` e o unico ponto de saida de rede do codigo | |
| teste_erro_definitivo_nao_repete | Erro definitivo (4xx nao transitorio) nao e repetido | |
| teste_falha_de_rede_continua_sendo_classificada_como_rede | Falha de rede segue classificada como rede apos a separacao de defeitos do cliente | |
| teste_falha_de_transporte_e_classificada_como_rede | Falha de transporte (status do `curl`) e classificada como rede | |
| teste_interpretacao_de_erro_nao_json_preserva_mensagem_textual | Erro cujo corpo nao e JSON preserva a mensagem textual | |
| teste_limite_acima_do_maximo_e_recusado | Limite de pagina acima do maximo permitido e recusado | |
| teste_mensagem_do_cliente_e_publicada_e_nao_descartada | A mensagem do cliente `curl` e publicada e nao descartada | |
| teste_mensagem_do_cliente_e_redigida_antes_de_publicar | A mensagem do cliente e redigida (segredos mascarados) antes de ser publicada | |
| teste_nao_deixa_residuo_temporario | A requisicao nao deixa nenhum residuo temporario | |
| teste_nao_introduz_estado_local_persistente | A biblioteca nao introduz estado local persistente | |
| teste_nenhum_gancho_de_limpeza_fica_armado_apos_requisicao | Nenhum gancho de limpeza (`trap`) permanece armado apos a requisicao | |
| teste_nome_de_contexto_e_literal | O nome do contexto isolado e literal e nao derivado de entrada | |
| teste_numero_de_tentativas_e_configuravel | O numero de tentativas e configuravel por ambiente | |
| teste_opcoes_carregam_timeouts_padrao_em_todos_os_modos | As opcoes carregam os timeouts padrao em todos os modos de chamada | |
| teste_opcoes_de_bearer_incluem_content_type_json | As opcoes de bearer incluem o `Content-Type` JSON | |
| teste_operacao_idempotente_sem_resposta_repete_com_recuo | Operacao idempotente sem resposta e repetida com recuo | |
| teste_operacao_nao_idempotente_sem_resposta_nao_repete | Operacao nao idempotente sem resposta nao e repetida | |
| teste_padrao_e_de_cinco_tentativas_contando_a_primeira | O padrao e de cinco tentativas, contando a primeira | |
| teste_politica_vem_de_lib_errors_e_nao_de_decisao_propria | A politica de retentativa vem de `lib/errors.sh` e nao de decisao propria da biblioteca | |
| teste_recuo_respeita_o_teto_por_espera | O recuo entre tentativas respeita o teto por espera | |
| teste_recuo_tem_base_de_um_segundo_com_variacao | O recuo parte de uma base de um segundo com variacao aleatoria | |
| teste_reducao_de_limite_tem_piso_e_desiste | A reducao do limite de pagina tem piso e desiste ao atingi-lo | |
| teste_reemissao_diagnostica_nao_deixa_area_temporaria | A reemissao diagnostica da requisicao nao deixa area temporaria | |
| teste_requisicao_com_e_sem_corpo_sao_tratadas_igualmente | Requisicoes com e sem corpo sao tratadas com a mesma conducao | |
| teste_resposta_de_erro_expoe_resumo_ja_extraido | A resposta de erro expoe o resumo ja extraido do corpo | |
| teste_resposta_de_sucesso_expoe_codigo_e_corpo | A resposta de sucesso expoe codigo HTTP e corpo | |
| teste_retry_after_acima_do_teto_e_limitado_a_300_segundos | `Retry-After` acima do teto e limitado a 300 segundos | |
| teste_retry_after_depois_do_identificador_de_correlacao_ainda_e_lido | `Retry-After` posterior ao identificador de correlacao nos cabecalhos ainda e lido | |
| teste_retry_after_invalido_ou_em_data_cai_no_recuo | `Retry-After` invalido ou em formato de data cai no recuo padrao | |
| teste_retry_after_zero_e_valido_e_nao_espera | `Retry-After` igual a zero e valido e nao espera | |
| teste_segredo_chega_ao_cliente_por_canal_fora_de_argv | O segredo chega ao cliente por canal fora de `argv` | |
| teste_segredo_nunca_aparece_na_linha_de_comando | O segredo nunca aparece na linha de comando do cliente | |
| teste_servidor_mudo_em_operacao_idempotente_e_repetido | Servidor mudo em operacao idempotente leva a nova tentativa | |
| teste_servidor_mudo_termina_como_falha_transitoria_de_rede | Servidor mudo esgota as tentativas e termina como falha transitoria de rede | |
| teste_status_seguem_a_taxonomia_de_erro | Os status HTTP de erro seguem a taxonomia de codigos de saida | |
| teste_timeouts_sao_ajustaveis_por_ambiente | Os timeouts sao ajustaveis por variavel de ambiente | |
| teste_umask_do_processo_e_preservado_apos_chamada_http | O umask do processo e preservado apos uma chamada HTTP | |
| teste_validacao_de_ambiente_e_publica_e_aceita_o_padrao | A validacao do ambiente e publica e aceita os valores padrao | |
| teste_variavel_de_ambiente_invalida_e_recusada_antes_da_rede | Variavel de ambiente invalida e recusada antes de qualquer chamada de rede | |


## `tests/unit/identidade_gnustat_test.sh`

- **Alvo:** `lib/hash.sh` (identidade forte do arquivo lida com `stat -c`) sob o GNU coreutils
- **Modulo:** `identidade_gnustat`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-0-pendencias`)
- **Regras de origem:** RSK-43; log `docs/prompts/2026-10-19_1023_backlog-fase-0-pendencias.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `stat` no `PATH` que faz `exec` no `gnustat` (`/usr/bin/gnustat`); sem `gnustat` cada caso e pulado com motivo explicito; arquivos temporarios por caso
- **Comando:** `bash tests/run.sh tests/unit/identidade_gnustat_test.sh`
- **Observacoes:** caso pulado por ausencia do `gnustat` nao prova nada naquela maquina; o registro da suite mostra o pulo

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_gnu_formato_da_identidade_e_identico_ao_do_stat_de_referencia | Sob o GNU `stat`, a identidade tem o mesmo formato da obtida com o `stat` de referencia | RSK-43 |
| teste_gnu_identidade_de_arquivo_vazio_nao_e_registravel | A identidade de arquivo vazio nao e registravel no cache | RSK-43 |
| teste_gnu_identidade_e_aceita_pela_validacao_do_cache | A identidade gerada passa pela validacao do registro de cache | RSK-43 |
| teste_gnu_identidade_inalterada_se_nada_muda | Sem alteracao do arquivo, a identidade se mantem igual | RSK-43 |
| teste_gnu_mtime_restaurado_nao_esconde_a_reescrita | Restaurar o `mtime` apos reescrever o arquivo nao esconde a mudanca | RSK-43 |
| teste_gnu_regra_de_dois_segundos_do_registro | A regra de 2 segundos do registro recusa identidade recente demais | RSK-43 |
| teste_gnu_troca_de_inode_muda_a_identidade | Trocar o inode do arquivo muda a identidade | RSK-43 |


## `tests/unit/json_test.sh`

- **Alvo:** `lib/json.sh` (interpretador JSON proprio, sem `jq`)
- **Modulo:** json
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `feat(json): interpretador JSON proprio sem dependencia externa`; sem log de prompt)
- **Regras de origem:** RNF-11; DIV-04 (citados no cabecalho do teste); sem log de prompt (commit de criacao `edfd8ad`, anterior a trilha do protocolo)
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** documentos JSON sinteticos em variaveis e subshells do harness, massa adversarial gerada em memoria, sem rede nem arquivos permanentes
- **Comando:** `bash tests/run.sh tests/unit/json_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_acao_de_trap_nunca_referencia_variavel_local | Nenhuma acao de `trap` da lib referencia variavel local. | |
| teste_analise_em_subshell_sobre_estado_alheio_e_recusada | Analise feita em subshell sobre estado de outro contexto e recusada. | |
| teste_analise_seguinte_nao_herda_nos_da_anterior | Uma analise nao herda nos da analise anterior. | |
| teste_aninhamento_e_arranjo | Objetos aninhados e arranjos sao percorridos por caminho e indice. | |
| teste_aninhamento_profundo_valido | Aninhamento profundo dentro do teto e aceito. | |
| teste_apos_falha_nao_ha_resultado_residual | Apos analise com falha nao resta resultado residual consultavel. | |
| teste_arranjo_de_arranjo | Arranjo dentro de arranjo e consultavel por indices encadeados. | |
| teste_barra_invertida_antes_de_aspa_final | Barra invertida antes da aspa final de uma cadeia nao a fecha indevidamente. | |
| teste_caminho_inexistente_falha_sem_inventar_valor | Caminho inexistente falha sem devolver valor inventado. | |
| teste_caractere_de_controle_cru_e_recusado | Caractere de controle cru dentro de cadeia e recusado. | |
| teste_chave_contendo_separador_e_enderecavel_por_si | Chave que contem o separador de caminho e enderecavel por si. | |
| teste_chave_duplicada_nao_deixa_filha_fantasma | Chave duplicada nao deixa campo filho fantasma da ocorrencia anterior. | |
| teste_chave_duplicada_vence_a_ultima | Com chave duplicada, vence o ultimo valor. | |
| teste_chave_terminada_em_quebra_de_linha_nao_entrega_outro_campo | Chave terminada em quebra de linha nao entrega o valor de outro campo. | |
| teste_chave_vazia_e_aceita_e_enderecavel | Chave vazia e aceita e enderecavel. | |
| teste_codificador_escapa_a_barra_invertida_antes_das_demais | O codificador escapa a barra invertida antes das demais sequencias. | |
| teste_codificador_escapa_cada_forma_exigida | O codificador escapa aspa, barra, e as formas de controle exigidas. | |
| teste_codificador_escapa_controle_como_sequencia_unicode | Caractere de controle e codificado como sequencia unicode. | |
| teste_codificador_nao_altera_texto_sem_escape | Texto que nao precisa de escape sai inalterado do codificador. | |
| teste_consulta_apos_analise_perdida_nao_responde_pelo_documento_novo | Consulta apos analise perdida nao responde com dados do documento novo. | |
| teste_contador_e_enumeracao_concordam_com_chave_duplicada | Contagem e enumeracao de chaves concordam quando ha chave duplicada. | |
| teste_contexto_devolve_o_anterior_para_restauracao | Trocar de contexto devolve o anterior para restauracao. | |
| teste_contexto_nomeado_nao_vira_porta_para_analise_em_subshell | Contexto nomeado nao serve de porta para analise em subshell. | |
| teste_contextos_nao_enxergam_os_campos_um_do_outro | Contextos distintos nao enxergam os campos um do outro. | |
| teste_corpo_de_erro_nao_destroi_listagem_em_curso | Corpo de erro analisado em outro contexto nao destroi a listagem em curso. | |
| teste_custo_com_corpus_adversarial | Corpus adversarial e analisado em tempo limitado (sem custo explosivo). | |
| teste_delimitadores_dentro_de_cadeia_nao_estruturam | Delimitadores dentro de cadeias nao alteram a estrutura do documento. | |
| teste_descartar_libera_o_contexto | Descartar um contexto o libera. | |
| teste_descartar_recusa_nome_invalido | Descartar com nome de contexto invalido e recusado. | |
| teste_diagnostico_acompanha_o_contexto_corrente | O diagnostico de falha acompanha o contexto corrente. | |
| teste_entrada_gigante_e_recusada_pelo_teto | Entrada acima do teto de tamanho e recusada. | |
| teste_entrada_malformada_e_recusada | Entrada malformada e recusada com falha classificada. | |
| teste_enumeracao_por_indice_devolve_o_nome_exato | Enumeracao por indice devolve o nome exato da chave. | |
| teste_enumeracao_terminada_por_nulo_nao_e_ambigua | Enumeracao terminada por nulo nao e ambigua com nomes que contem separadores. | |
| teste_escape_unicode | Sequencia `\u` e decodificada para o caractere correto. | |
| teste_escape_unicode_com_par_surrogate | Par surrogate em `\u` e decodificado para um unico caractere. | |
| teste_escapes_simples | Escapes simples (aspa, barra, quebra de linha, tabulacao) sao decodificados. | |
| teste_espacamento_e_ordem_nao_afetam | Espacamento e ordem dos campos nao afetam o resultado. | |
| teste_faixa_de_nos_e_fechada_mesmo_quando_a_analise_falha | A faixa de nos e fechada (nao vaza) mesmo quando a analise falha. | |
| teste_falha_e_classificada_e_nao_silenciosa | Falha de analise e classificada e nunca silenciosa. | |
| teste_falha_no_meio_de_listagem_paginada_nao_acumula | Falha no meio de listagem paginada nao acumula resultado parcial. | |
| teste_massa_adversarial_nao_e_construida_por_substituicao_de_comando | A massa adversarial de teste nao e construida por substituicao de comando (que perderia bytes). | |
| teste_nao_usa_jq_nem_sed_por_campo | A lib nao usa `jq` nem `sed` por campo. | RNF-11; DIV-04 |
| teste_nenhum_desfecho_de_analise_vaza_nos | Nenhum desfecho de analise (sucesso ou falha) vaza nos. | |
| teste_nenhuma_captura_pode_carregar_byte_externo | Nenhuma captura de saida carrega byte externo nao confiavel. | |
| teste_nome_de_contexto_restrito_a_minusculas_e_sublinhado | Nome de contexto so aceita minusculas e sublinhado. | |
| teste_nome_invalido_nao_troca_o_contexto_corrente | Nome de contexto invalido nao troca o contexto corrente. | |
| teste_objeto_e_arranjo_vazios_e_cadeia_vazia | Objeto vazio, arranjo vazio e cadeia vazia sao aceitos. | |
| teste_objeto_simples | Objeto simples e lido por chave. | |
| teste_profundidade_excessiva_e_recusada | Profundidade acima do teto e recusada. | |
| teste_qa_b3_04_escape_u0000_e_malformado_em_todo_documento | O escape `\u0000` e tratado como malformado em qualquer posicao do documento. | |
| teste_qa_b3_05_chave_duplicada_e_contada_sem_mudar_a_analise | Chave duplicada e contada sem alterar o resultado da analise. | |
| teste_quebra_de_linha_no_valor_e_preservada_byte_a_byte | Quebra de linha dentro de valor e preservada byte a byte. | |
| teste_reanalise_no_mesmo_contexto_libera_os_nos_anteriores | Reanalise no mesmo contexto libera os nos anteriores. | |
| teste_sentinela_de_documento_em_chave_nao_sequestra_a_raiz | Chave igual ao marcador interno de documento nao sequestra a raiz. | |
| teste_separador_em_chave_nas_duas_ordens | Chaves com separador funcionam nas duas ordens de declaracao. | |
| teste_separador_em_chave_por_escape_unicode_nao_desloca_campo | Separador escrito como escape unicode na chave nao desloca o campo. | |
| teste_teto_de_entrada_e_aplicado | O teto de entrada e aplicado ao tamanho do documento. | |
| teste_teto_de_profundidade_declarado_e_o_efetivo | O teto de profundidade declarado e o efetivamente aplicado. | |
| teste_tipos_escalares | Escalares (cadeia, numero, booleano, nulo) sao lidos com o tipo correto. | |
| teste_utf8_multibyte_direto | UTF-8 multibyte direto e preservado. | |
| teste_valor_contendo_delimitadores_de_erro_da_dropbox | Valor que contem os delimitadores dos erros da Dropbox e lido sem quebrar o parser. | |


## `tests/unit/leitura_exata_portavel_test.sh`

- **Alvo:** `lib/atributos.sh` (`dbx_ler_exato`, sobre `dd`), `lib/hash.sh` e `lib/transfer.sh` na leitura em partes do mesmo descritor
- **Modulo:** `leitura_exata_portavel` (linha ausente do mapa de modulos; id derivado do nome do arquivo)
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `suporte-freebsd`)
- **Regras de origem:** RF-173; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duble de `head` do FreeBSD em `tests/duplos/freebsd/bin/head` (consome N+4096 bytes, como o `head -c` do FreeBSD); massa e entrada padrao em area temporaria; cano com leituras curtas
- **Comando:** `bash tests/run.sh tests/unit/leitura_exata_portavel_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_content_hash_de_arquivo_maior_que_um_bloco_nao_depende_do_head | O resumo de conteudo de arquivo maior que um bloco nao depende do `head` | RF-173 |
| teste_duplo_de_head_le_alem_de_n_do_descritor | O duble de `head` reproduz o defeito do FreeBSD e le alem de N do descritor | |
| teste_ler_exato_le_de_cano_com_leituras_curtas | `dbx_ler_exato` completa N bytes lendo de cano com leituras curtas | RF-173 |
| teste_ler_exato_nao_passa_de_n_e_continua_do_ponto_certo | `dbx_ler_exato` nao passa de N e a leitura seguinte continua do ponto certo | RF-173 |
| teste_ler_exato_recusa_uso_invalido | `dbx_ler_exato` recusa uso invalido (N nao numerico ou ausente) | |
| teste_reposicionamento_da_retomada_posiciona_no_deslocamento_exato | O reposicionamento da retomada posiciona o descritor no deslocamento exato | RF-173 |
| teste_upload_por_sessao_le_todos_os_bytes_em_partes_exatas | O upload por sessao le todos os bytes, em partes exatas, sem perda | RF-173 |


## `tests/unit/output_test.sh`

- **Alvo:** `lib/output.sh`: modelo de resultado unico com duas apresentacoes (texto e estruturada), terminador nulo, restricao de linha e mascaramento de segredos
- **Modulo:** `output`
- **Camada:** unitario
- **Autoria:** Senior Developer (commit `74b3567`, `feat(output): apresentacao dupla com terminador selecionavel`; sem log de prompt)
- **Regras de origem:** RF-28; RF-35; RNF-19; RNF-22; log de prompt: Nao aplicavel: anterior a trilha do protocolo
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** `lib/errors.sh` e `lib/output.sh` carregados; scripts entregues a `bash -c`; segredos sinteticos em memoria; nenhum arquivo em disco
- **Comando:** `bash tests/run.sh tests/unit/output_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_versao_do_contrato_e_declarada_e_congelada | A versao do contrato de saida e declarada e permanece congelada | RF-35 |
| teste_apresentacoes_derivam_do_mesmo_modelo | Texto e saida estruturada derivam do mesmo modelo de resultado | RF-28 |
| teste_saida_estruturada_nao_tem_texto_decorativo | A saida estruturada nao traz texto decorativo | RF-28 |
| teste_sem_terminal_assume_apresentacao_estruturada | Sem terminal, a apresentacao assumida e a estruturada | RNF-19 |
| teste_sinalizador_explicito_prevalece_nos_dois_sentidos | Sinalizador explicito vence a deteccao de terminal nos dois sentidos | RNF-19 |
| teste_modo_invalido_e_recusado | Modo de apresentacao invalido e recusado | |
| teste_modo_nulo_usa_terminador_nulo | O modo nulo usa o byte nulo como terminador | |
| teste_nome_com_quebra_de_linha_sobrevive_no_modo_nulo | Nome com quebra de linha sai intacto no modo nulo | |
| teste_nome_com_espaco_e_controle_no_modo_nulo | Nome com espaco e controle sai intacto no modo nulo | |
| teste_modo_nulo_e_ortogonal_a_deteccao_de_terminal | O modo nulo independe da deteccao de terminal | |
| teste_terminador_invalido_e_recusado | Terminador invalido e recusado | |
| teste_identificador_de_requisicao_fica_em_linha_propria | O identificador de requisicao sai em linha propria | |
| teste_diagnostico_nunca_concatena_na_linha_do_cabecalho | O diagnostico nunca e concatenado na linha do cabecalho | RNF-22 |
| teste_restricao_de_linha_vale_tambem_no_modo_nulo | A restricao de linha vale tambem no modo nulo | RNF-22 |
| teste_identificador_sobrevive_no_modo_nulo | O identificador de requisicao sobrevive no modo nulo | |
| teste_redacao_e_aplicada_ao_alimentar_o_modelo | A redacao de segredos e aplicada ao alimentar o modelo | |
| teste_diagnostico_nao_vai_para_a_saida_padrao | O diagnostico nao vai para a saida padrao | |
| teste_iniciar_descarta_o_resultado_anterior | Iniciar um novo resultado descarta o anterior | |
| teste_nao_escreve_em_disco | A biblioteca nao escreve em disco | |
| teste_valor_com_quebra_de_linha_e_recusado_em_modo_linha | Valor com quebra de linha e recusado em modo linha | RNF-22 |
| teste_recusa_em_modo_linha_nao_emite_saida_parcial | A recusa em modo linha nao emite saida parcial | RNF-22 |
| teste_mesmo_valor_e_aceito_em_modo_nulo | O mesmo valor com quebra de linha e aceito em modo nulo | RNF-22 |
| teste_tabulacao_e_retorno_de_carro_tambem_sao_recusados_em_modo_linha | Tabulacao e retorno de carro tambem sao recusados em modo linha | RNF-22 |
| teste_diagnostico_sai_na_saida_de_erro_e_nao_na_padrao | O diagnostico sai na saida de erro e nao na padrao | |
| teste_chave_invalida_e_recusada | Chave de campo invalida e recusada | |
| teste_todo_cabecalho_isolado_aqui_e_redigido_pela_taxonomia | Todo cabecalho de resposta isolado aqui e redigido pela taxonomia | |
| teste_assert_status_nao_descarta_estado_da_funcao_observada | A assercao de status preserva o estado da funcao observada | |
| teste_diagnostico_mascara_os_segredos_em_memoria_pelo_valor | O diagnostico mascara pelo valor os segredos mantidos em memoria | |
| teste_mascara_pelo_valor_cobre_a_chave_do_aplicativo | O mascaramento pelo valor cobre a chave do aplicativo | |
| teste_diagnostico_redige_token_sl_u_fora_da_memoria_pela_forma | O diagnostico redige pela forma um token `sl.u` que nao esta em memoria | |
| teste_diagnostico_mascara_pelo_valor_antes_da_redacao_por_forma | O mascaramento pelo valor ocorre antes da redacao por forma | |


## `tests/unit/path_test.sh`

- **Alvo:** `lib/path.sh`: normalizacao, confinamento a raiz (remoto sem distincao de caixa, local com distincao), recusa de travessia, vinculos simbolicos, chave canonica e conversao para o formato da API
- **Modulo:** `lib/path.sh`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD; commit de criacao `a03d2c0`, "first commit")
- **Regras de origem:** Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** diretorios temporarios e vinculos simbolicos criados por caso; localidades variadas nos casos de caixa
- **Comando:** `bash tests/run.sh tests/unit/path_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_arg_caixa_fora_do_ascii_nunca_escapa_em_nenhuma_localidade | A comparacao de caixa de caractere fora do ASCII nunca deixa escapar do confinamento em nenhuma localidade | |
| teste_arg_caminho_relativo_nao_e_ancorado_na_raiz | Argumento relativo nao e ancorado na raiz | |
| teste_arg_caractere_de_controle_e_recusado_com_qualquer_raiz | Argumento com caractere de controle e recusado com qualquer raiz | |
| teste_arg_comparacao_ignora_caixa | A comparacao do argumento com a raiz ignora a caixa | |
| teste_arg_dentro_da_raiz_e_aceito_por_componente | Argumento dentro da raiz e aceito com comparacao por componente | |
| teste_arg_ponto_e_ponto_ponto_normalizados_antes_de_comparar | `.` e `..` sao normalizados antes da comparacao com a raiz | |
| teste_arg_prefixo_semelhante_e_recusado | Prefixo textual semelhante a raiz, mas de outra pasta, e recusado | |
| teste_arg_publica_no_canal_sem_perder_resultado | O argumento aceito e publicado no canal e o resultado nao se perde | |
| teste_arg_raiz_com_controle_e_configuracao_mesmo_usada_como_caminho | Raiz com caractere de controle e erro de configuracao mesmo quando usada como caminho | |
| teste_arg_raiz_da_conta_nao_muda_nada | Com a raiz da conta o argumento nao muda | |
| teste_arg_raiz_malformada_falha_fechado | Raiz malformada falha fechada | |
| teste_caminho_dentro_da_raiz_e_aceito | Caminho remoto dentro da raiz e aceito | |
| teste_caminho_local_dentro_da_raiz_e_aceito | Caminho local dentro da raiz e aceito | |
| teste_caminho_relativo_e_ancorado_na_raiz | Caminho relativo e ancorado na raiz | |
| teste_caminho_relativo_ou_vazio_e_uso_invalido | Caminho relativo ou vazio onde se exige absoluto e uso invalido | |
| teste_chave_canonica_nao_imprime_e_recusa_vazio | A chave canonica nao imprime na saida e recusa entrada vazia | |
| teste_chave_canonica_nao_usa_substituicao_de_comando_com_readlink | A chave canonica nao usa substituicao de comando com `readlink` (auditoria de `lib/*.sh`) | |
| teste_codigo_de_recusa_corresponde_a_taxonomia_de_erro | O codigo de recusa corresponde a taxonomia de erros do projeto | |
| teste_confinamento_ignora_caixa_como_a_dropbox | O confinamento remoto ignora a caixa, como a Dropbox | |
| teste_confinamento_local_e_sensivel_a_caixa | O confinamento local distingue a caixa | |
| teste_confinamento_preserva_nomes_adversariais | O confinamento preserva nomes adversariais (espacos, quebras de linha, metacaracteres) | |
| teste_conversao_para_o_formato_da_api | A conversao para o formato da API produz o caminho esperado (barra inicial, raiz vazia) | |
| teste_destino_local_ainda_inexistente_e_aceito_dentro_da_raiz | Destino local ainda inexistente e aceito se ficar dentro da raiz | |
| teste_destino_local_inexistente_com_travessia_e_recusado | Destino local inexistente com travessia para fora e recusado | |
| teste_deteccao_de_caminho_inseguro_para_saida_de_uma_linha | Caminho que quebraria a saida de uma linha e detectado como inseguro | |
| teste_irmao_com_prefixo_comum_e_recusado | Pasta irma remota com prefixo comum a raiz e recusada | |
| teste_irmao_local_com_prefixo_comum_e_recusado | Pasta irma local com prefixo comum a raiz e recusada | |
| teste_link_simbolico_folha_para_fora_da_raiz_e_recusado | Vinculo simbolico na folha apontando para fora da raiz e recusado | |
| teste_link_simbolico_interno_a_raiz_e_aceito | Vinculo simbolico que aponta para dentro da raiz e aceito | |
| teste_link_simbolico_para_fora_da_raiz_e_recusado | Vinculo simbolico em componente intermediario apontando para fora da raiz e recusado | |
| teste_multiplas_quebras_terminais_sao_preservadas | Varias quebras de linha no fim do nome sao preservadas | |
| teste_nome_com_ponto_ponto_embutido_nao_e_travessia | Nome com `..` embutido (por exemplo `a..b`) nao e tratado como travessia | |
| teste_nome_com_quebra_de_linha_e_preservado | Nome com quebra de linha e preservado sem alteracao | |
| teste_nome_local_com_espacos_e_quebra_de_linha | Nome local com espacos e quebra de linha e aceito e preservado | |
| teste_nomes_com_caracteres_especiais_sao_preservados | Nomes com caracteres especiais sao preservados | |
| teste_normaliza_componentes_ponto | Componentes `.` sao removidos na normalizacao | |
| teste_normaliza_separadores_redundantes | Barras redundantes sao colapsadas na normalizacao | |
| teste_opcao_de_raiz_total_nao_afeta_raiz_restrita | A opcao de raiz total nao afeta o confinamento de uma raiz restrita | |
| teste_quebra_de_linha_terminal_sobrevive_na_normalizacao_remota | Quebra de linha terminal sobrevive a normalizacao remota | |
| teste_quebra_de_linha_terminal_sobrevive_no_confinamento_remoto | Quebra de linha terminal sobrevive ao confinamento remoto | |
| teste_quebra_terminal_local_nao_entrega_arquivo_errado | Quebra terminal em nome local nao resolve para outro arquivo | |
| teste_raiz_barra_com_opcao_explicita_opera_sem_confinamento | Raiz `/` com a opcao explicita de raiz total opera sem confinamento | |
| teste_raiz_barra_explicita_ainda_barra_travessia_acima_da_raiz | Raiz `/` explicita ainda barra travessia acima da raiz | |
| teste_raiz_barra_sem_opcao_explicita_falha_fechado | Raiz `/` sem a opcao explicita falha fechada | |
| teste_raiz_com_quebra_de_linha_final_nao_alcanca_a_raiz_vizinha | Raiz terminada em quebra de linha nao alcanca a raiz vizinha de mesmo nome | |
| teste_raiz_com_quebra_de_linha_nao_captura_caminho_da_raiz_vizinha | Raiz com quebra de linha nao captura caminho da raiz vizinha | |
| teste_raiz_e_preservada | A raiz e preservada na normalizacao | |
| teste_raiz_local_barra_tambem_exige_opcao_explicita | Raiz local `/` tambem exige a opcao explicita | |
| teste_raiz_local_inexistente_falha_fechado | Raiz local inexistente falha fechada | |
| teste_raiz_malformada_falha_fechado | Raiz remota malformada falha fechada | |
| teste_relativo_absoluto_e_ligacao_simbolica_tem_a_mesma_chave_canonica | Caminho relativo, absoluto e por ligacao simbolica do mesmo arquivo tem a mesma chave canonica | |
| teste_resolve_ponto_ponto_lexicalmente | `..` e resolvido de forma lexica | |
| teste_resultado_e_limpo_quando_a_raiz_total_nao_e_autorizada | Quando a raiz total nao e autorizada o canal de resultado fica limpo | |
| teste_resultado_e_limpo_quando_o_caminho_e_recusado | Quando o caminho e recusado o canal de resultado fica limpo | |
| teste_travessia_acima_da_raiz_e_recusada | Travessia acima da raiz remota e recusada | |
| teste_travessia_local_por_ponto_ponto_e_recusada | Travessia local por `..` para fora da raiz e recusada | |
| teste_travessia_para_fora_da_raiz_e_recusada | Travessia para fora da raiz por `..` no meio do caminho e recusada | |
| teste_valor_invalido_da_opcao_de_raiz_total_e_recusado | Valor invalido da opcao de raiz total e recusado | |


## `tests/unit/perfis_cli_test.sh`

- **Alvo:** `lib/cli.sh`, opcao global `--perfil` e variavel de perfil
- **Modulo:** `lib/cli.sh`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-8-perfis`)
- **Regras de origem:** F-18; RF-120; RF-121(g); DIV-241; TC-PFS-01..08; TC-PFN-09; TC-PFN-10; log `docs/prompts/2026-10-21_1735_backlog-fase-8-perfis.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** Nao aplicavel: funcoes de `lib/cli.sh` carregadas por source, sem rede nem arquivos
- **Comando:** `bash tests/run.sh tests/unit/perfis_cli_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_pfs05_perfil_e_profile_equivalem_antes_do_subcomando | --perfil e --profile antes do subcomando produzem o mesmo resultado | TC-PFS-05 |
| teste_pfs06_sem_valor_sai_2 | --perfil sem valor sai com 2 | TC-PFS-06 |
| teste_pfs07_repeticao_sai_2_mesmo_igual | Opcao repetida sai com 2 mesmo quando os valores sao iguais | TC-PFS-07 |
| teste_pfs08_depois_do_subcomando_so_em_config_e_unlink | Depois do subcomando --perfil so e aceito em config e unlink | TC-PFS-08 |
| teste_pfs_depois_do_subcomando_repeticao_e_valor_de_raiz | Depois do subcomando, repeticao e valor que parece raiz sao tratados corretamente | TC-PFS-08 |
| teste_pfn10_nome_invalido_em_qualquer_comando_sai_2 | Nome de perfil invalido em qualquer comando sai com 2 | TC-PFN-10 |
| teste_pfn10_help_e_version_curto_circuitam_na_ordem_da_analise | help e version curto-circuitam na ordem da analise de argumentos, antes do nome invalido | TC-PFN-10 |
| teste_pfs_aplicar_opcao_vence_variavel_e_vazio_e_nao_definida | A opcao vence a variavel; variavel vazia e nao definida equivalem a sem selecao | TC-PFS-01; TC-PFS-03 |
| teste_pfn09_variavel_invalida_so_e_validada_quando_usada | Variavel de perfil invalida so e validada quando efetivamente usada | TC-PFN-09 |


## `tests/unit/perfis_config_test.sh`

- **Alvo:** `lib/config.sh`: perfis nomeados de credencial (nome, selecao, resolucao, permissoes, gravacao, remocao, identidade e listagem)
- **Modulo:** `perfis_config`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-8-perfis`)
- **Regras de origem:** F-18; RF-120..122; RF-125; RF-126; RNF-37; TC-PFN; TC-PFC; TC-PFS; TC-PFG; TC-PFU; TC-PFL; log `docs/prompts/2026-10-21_1735_backlog-fase-8-perfis.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** `lib/errors.sh`, `lib/json.sh` e `lib/config.sh` carregados; diretorio de configuracao temporario com credenciais sinteticas e permissoes e ligacoes simbolicas montadas no caso
- **Comando:** `bash tests/run.sh tests/unit/perfis_config_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_pfn01_nomes_validos_de_1_e_32_caracteres | Nomes de perfil de 1 a 32 caracteres validos sao aceitos | TC-PFN-01 |
| teste_pfn02_trinta_e_tres_caracteres_recusado_com_2 | Nome com 33 caracteres e recusado com saida 2 | TC-PFN-02 |
| teste_pfn03_a_pfn06_nomes_invalidos_recusados_com_2 | Nomes invalidos (vazio, caracteres proibidos, reservados) sao recusados com 2 | TC-PFN-03..06 |
| teste_pfn_validacao_nao_toca_disco | A validacao do nome nao acessa o disco | |
| teste_pfn09_valor_invalido_do_ambiente_nao_e_ecoado | Valor invalido vindo do ambiente nao e ecoado na mensagem | TC-PFN-09 |
| teste_pfn_nome_da_opcao_invalido_e_citado_truncado | Nome invalido vindo da opcao e citado na mensagem de forma truncada | |
| teste_pfs_ambiente_vazio_equivale_a_nao_definida | Variavel de ambiente de perfil vazia equivale a nao definida | |
| teste_pfs_ambiente_seleciona_com_origem_ambiente | A variavel de ambiente seleciona o perfil com origem `ambiente` | |
| teste_pfs_opcao_vence_a_variavel | A opcao de perfil vence a variavel de ambiente | |
| teste_pfc01_padrao_resolve_credencial_json_como_hoje | O perfil padrao resolve `credencial.json`, como antes dos perfis | TC-PFC-01 |
| teste_pfc02_outro_nome_resolve_perfis_nome_json | Outro nome resolve `perfis/nome.json` | TC-PFC-02 |
| teste_pfc_composicao_so_com_nome_validado | O caminho do perfil so e composto com nome ja validado | |
| teste_pfc03_perfil_ausente_nao_recua_para_o_padrao | Perfil inexistente nao recua para a credencial padrao | TC-PFC-03 |
| teste_pfc_perfil_carrega_do_seu_arquivo | O perfil carrega a credencial do seu proprio arquivo | |
| teste_pfc04_arquivo_do_perfil_0644_recusado | Arquivo de perfil com modo 0644 e recusado | TC-PFC-04 |
| teste_pfc05_perfis_0755_recusado | Diretorio `perfis` com modo 0755 e recusado | TC-PFC-05 |
| teste_pfc06_dbx_0755_recusado_para_perfil | Diretorio `dbx` com modo 0755 e recusado para perfil | TC-PFC-06 |
| teste_pfc07_perfis_ligacao_simbolica_recusado_sem_ler | `perfis` como ligacao simbolica e recusado sem ler o destino | TC-PFC-07 |
| teste_pfc08_arquivo_do_perfil_ligacao_simbolica_inclusive_pendente | Arquivo de perfil como ligacao simbolica, inclusive pendente, e recusado | TC-PFC-08 |
| teste_pfc13_dbx_ligacao_simbolica_recusada_para_perfil | Diretorio `dbx` como ligacao simbolica e recusado para perfil | TC-PFC-13 |
| teste_pfc_padrao_reservado_nunca_le_perfis_padrao_json | O nome reservado `padrao` nunca le `perfis/padrao.json` | |
| teste_pfg01_gravar_cria_perfis_0700_e_arquivo_0600 | Gravar cria `perfis` com 0700 e o arquivo do perfil com 0600 | TC-PFG-01 |
| teste_pfg04_destino_inseguro_recusado_antes_de_gravar | Destino inseguro e recusado antes de qualquer gravacao | TC-PFG-04 |
| teste_pfg05_destino_ligacao_simbolica_pendente_recusado | Destino que e ligacao simbolica pendente e recusado | TC-PFG-05 |
| teste_pfg_verificar_destino_do_padrao_nao_recusa_nada_novo | A verificacao de destino do perfil padrao nao recusa nada que antes aceitava | |
| teste_pfc11_gravar_e_remover_varrem_orfaos_em_perfis | Gravar e remover varrem temporarios orfaos em `perfis` | TC-PFC-11 |
| teste_pfu11_remover_perfil_remove_perfis_vazio | Remover o ultimo perfil remove o diretorio `perfis` vazio | TC-PFU-11 |
| teste_pfu_remover_nao_segue_perfis_ligacao_simbolica | A remocao nao segue `perfis` quando e ligacao simbolica | |
| teste_pfu06_manter_aplicativo_regrava_o_perfil | Manter o aplicativo regrava o perfil | TC-PFU-06 |
| teste_pfu08_identidade_de_perfil_e_igual_para_a_mesma_credencial | A identidade do perfil e igual para a mesma credencial | TC-PFU-08 |
| teste_pfc12_identidade_de_perfil_ilegivel_falha_sem_identidade | Perfil ilegivel falha sem produzir identidade | TC-PFC-12 |
| teste_pfl_listar_padrao_primeiro_e_ordem_de_bytes | A listagem traz o padrao primeiro e o restante em ordem de bytes | |
| teste_pfl03_padrao_so_aparece_se_existir | O perfil padrao so aparece na listagem se existir | TC-PFL-03 |
| teste_pfl05_vocabulario_do_veredito | O veredito de cada perfil usa so o vocabulario definido | TC-PFL-05 |
| teste_pfl08_entradas_anomalas_nao_viram_registro | Entradas anomalas em `perfis` nao viram registro na listagem | TC-PFL-08 |
| teste_pfl_listar_nao_cria_diretorios | Listar nao cria diretorios | |
| teste_pfl_carregar_outro_perfil_revalida_o_nome_antes_do_disco | Carregar outro perfil revalida o nome antes de acessar o disco | |
| teste_pfl_carregar_confere_a_cadeia_pelo_caminho_e_nao_pelo_rotulo | Carregar confere a cadeia de diretorios pelo caminho real, nao pelo rotulo do perfil | |


## `tests/unit/plataforma_freebsd_test.sh`

- **Alvo:** `lib/state.sh` (`dbx_state_host_id`): identificador do host sem `/proc`, como no FreeBSD
- **Modulo:** `lib/state.sh`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `suporte-freebsd`)
- **Regras de origem:** RF-171(b); TC-FBSD-21; DIV-353 (opcao A); log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** programa filho que carrega `lib/state` sem `/proc` utilizavel (capacidade ausente simulada); sem container
- **Comando:** `bash tests/run.sh tests/unit/plataforma_freebsd_test.sh`
- **Observacoes:** os casos de `dbx_preflight_descritores` (TC-FBSD-20) foram removidos; a prova do descritor esta em `tests/unit/descritor_portavel_test.sh`.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_host_id_sem_proc_publica_boot_e_ns_como_x | Sem `/proc` o identificador do host publica boot e namespace como `x` em vez de falhar | TC-FBSD-21 |


## `tests/unit/poda_portavel_test.sh`

- **Alvo:** `lib/state.sh` (`_dbx_state_retomada_podar` e poda equivalente de `cursor-*`): poda por teto sem `find -printf`
- **Modulo:** `lib/state.sh`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `suporte-freebsd`)
- **Regras de origem:** RF-168; TC-FBSD-03; TC-FBSD-19 (parte `find`); log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** duplo de `find` do FreeBSD (`tests/duplos/freebsd/bin/find`) no `PATH`, que rejeita `-printf`; registros sinteticos criados por `_popular` em diretorio temporario
- **Comando:** `bash tests/run.sh tests/unit/poda_portavel_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_duplo_de_find_rejeita_printf_e_delega_o_resto | O duplo de `find` rejeita `-printf` e delega as demais expressoes ao `find` real | |
| teste_nenhum_find_com_printf_em_codigo_de_runtime | Nenhum codigo de runtime usa `find -printf` (auditoria) | |
| teste_poda_nao_toca_outros_prefixos_nem_abaixo_do_teto | A poda nao toca registros de outros prefixos nem age abaixo do teto | |
| teste_poda_por_teto_de_cursor_com_find_bsd_mantem_o_teto_e_o_atual | A poda de `cursor-*` com `find` BSD mantem o teto e o registro atual | |
| teste_poda_por_teto_de_retomada_com_find_bsd_mantem_o_teto_e_o_atual | A poda de `retomada-*` com `find` BSD mantem o teto e o registro atual, removendo os mais antigos | |


## `tests/unit/preflight_test.sh`

- **Alvo:** `lib/preflight.sh`: verificacao de ambiente (utilitarios, versao do bash, permissao da credencial, area temporaria, XDG), auditorias de `lib/*.sh` e coerencia com o README e o instalador
- **Modulo:** `lib/preflight.sh`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD; commit de criacao `ebec9ae`, "test: preflight, config e composicao dos caminhos gemeos")
- **Regras de origem:** Nao aplicavel: anterior a trilha do protocolo; comportamento inferido do codigo do teste
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** `PATH` restrito com duplos que omitem cada utilitario; credencial, diretorio temporario e variaveis XDG por caso; leitura de `lib/*.sh`, `README.md` e `install.sh` nas auditorias
- **Comando:** `bash tests/run.sh tests/unit/preflight_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_ambiente_saudavel_e_aprovado | Ambiente com todos os requisitos e aprovado | |
| teste_area_temporaria_inexistente_e_recusada | Area temporaria inexistente e recusada | |
| teste_area_temporaria_somente_leitura_e_recusada | Area temporaria somente leitura e recusada | |
| teste_auditoria_de_comandos_enxerga_utilitario_fora_de_qualquer_lista | A auditoria de comandos externos enxerga utilitario usado fora de qualquer lista | |
| teste_auditoria_de_comandos_ignora_o_que_nao_e_comando | A auditoria ignora palavras que nao sao comandos (textos, comentarios) | |
| teste_auditoria_de_comandos_nao_fica_cega_depois_de_vetor_de_uma_linha | A auditoria nao fica cega depois de um vetor declarado em uma linha | |
| teste_biblioteca_carrega_sem_utilitario_externo_algum | A biblioteca carrega sem exigir nenhum utilitario externo | |
| teste_canal_de_hash_do_envio_por_sessao_tem_nome_unico | O canal de hash do envio por sessao tem nome unico | |
| teste_credencial_ausente_nao_reprova_o_preflight | Credencial ausente nao reprova o preflight | |
| teste_curl_ausente_e_recusado_nomeando_o_utilitario | `curl` ausente e recusado e o utilitario e nomeado | |
| teste_deteccao_de_plataforma_so_no_ponto_unico | A deteccao de plataforma existe apenas no ponto unico previsto | |
| teste_diagnostico_do_preflight_nao_ecoa_conteudo_da_credencial | O diagnostico do preflight nunca ecoa o conteudo da credencial | |
| teste_extracao_enxerga_comando_apos_cada_palavra_que_abre | A extracao de comandos enxerga o comando depois de cada palavra que abre comando | |
| teste_inspecao_sem_parada_inclui_o_resumo_sha256 | A inspecao sem parada inclui o utilitario de resumo SHA-256 | |
| teste_inspecao_sem_parada_nomeia_cada_ausente | A inspecao sem parada nomeia cada utilitario ausente | |
| teste_instalador_nao_detecta_nem_recomenda_sqlite3 | O instalador nao detecta nem recomenda `sqlite3` | |
| teste_jq_nao_e_exigido | `jq` nao e exigido | |
| teste_lib_db_e_suas_chamadas_nao_existem_mais | `lib/db` e suas chamadas nao existem mais | |
| teste_lista_de_utilitarios_do_readme_e_a_do_preflight | A lista de utilitarios do README coincide com a do preflight | |
| teste_nenhum_codigo_do_produto_invoca_sqlite3_nem_python3 | Nenhum codigo do produto invoca `sqlite3` nem `python3` | |
| teste_nivel_ambiente_nao_recusa_por_permissao_de_credencial | No nivel ambiente a permissao da credencial nao reprova | |
| teste_nivel_credencial_continua_recusando_permissao_larga | No nivel credencial permissao larga continua sendo recusada | |
| teste_nivel_fora_do_vocabulario_e_recusado | Nivel de verificacao fora do vocabulario e recusado | |
| teste_omissao_de_nivel_assume_o_mais_estrito | Sem nivel informado vale o mais estrito | |
| teste_palavras_que_abrem_comando_vem_da_gramatica_do_shell | As palavras que abrem comando seguem a gramatica do shell | |
| teste_permissao_da_credencial_e_verificada_no_preflight | A permissao do arquivo de credencial e verificada pelo preflight | |
| teste_piso_declarado_e_o_verificado | O piso de versao do bash declarado e o verificado | |
| teste_preflight_exige_os_utilitarios_do_diagnostico_do_config | O preflight exige os utilitarios usados pelo diagnostico do `config` | |
| teste_preflight_nao_lista_nem_sonda_sqlite3_e_python3 | O preflight nao lista nem sonda `sqlite3` e `python3` | |
| teste_status_segue_a_taxonomia_de_erro | O status de saida do preflight segue a taxonomia de erros | |
| teste_todo_comando_externo_de_lib_e_exigido_pelo_preflight | Todo comando externo usado em `lib/*.sh` e exigido pelo preflight | |
| teste_todo_utilitario_ausente_reprova_e_e_nomeado | Todo utilitario exigido que falte reprova e e nomeado | |
| teste_utilitario_de_resumo_ausente_e_recusado | Ausencia de qualquer utilitario de resumo SHA-256 e recusada | |
| teste_versao_de_bash_abaixo_do_piso_e_recusada | Versao do bash abaixo do piso e recusada | |
| teste_xdg_invalido_e_recusado | Variavel XDG invalida (relativa ou inutilizavel) e recusada | |


## `tests/unit/progress_test.sh`

- **Alvo:** `lib/progress.sh` (formatacao de bytes, barra, etapa e transferencia de progresso em stderr)
- **Modulo:** progress
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `progresso-operacoes`)
- **Regras de origem:** log `docs/prompts/2026-10-08_1015_progresso-operacoes.md` (parametros de progresso para operacoes)
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** funcoes de `lib/progress.sh` carregadas em subshell do harness, canais stdout e stderr capturados; sem rede
- **Comando:** `bash tests/run.sh tests/unit/progress_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_barra_gerar_percentual_zero_e_cem | A barra gerada em 0% e 100% fica toda vazia e toda cheia. | |
| teste_barra_gerar_valores_intermediarios_e_limites | A barra gerada para valores intermediarios e limites tem o preenchimento proporcional. | |
| teste_barra_grafica_emite_em_stderr_e_preserva_stdout | A barra grafica sai em stderr e stdout permanece intacto. | |
| teste_etapa_barra_exibe_progresso_do_arquivo_atual_e_percentual_global | A etapa com barra mostra o progresso do arquivo atual e o percentual global. | |
| teste_etapa_com_progresso_fracionario_exibe_decimais | Etapa com progresso fracionario exibe casas decimais. | |
| teste_etapa_formata_e_emite_em_stderr | A etapa e formatada e emitida em stderr. | |
| teste_etapa_inclui_barra_grafica_em_stderr | A linha de etapa inclui a barra grafica em stderr. | |
| teste_formatacao_de_bytes | Bytes sao formatados na unidade legivel correta (B, KiB, MiB, GiB). | |
| teste_progresso_ativado_por_flag_explicita | A flag explicita de progresso o ativa. | |
| teste_progresso_desativado_por_flag_negativa | A flag negativa de progresso o desativa. | |
| teste_progresso_desativado_por_padrao_sem_terminal | Sem terminal e sem flag, o progresso fica desativado por padrao. | |
| teste_progresso_emite_em_stderr_e_preserva_stdout | O progresso emite em stderr e preserva stdout. | |
| teste_progresso_silenciado_nao_emite_em_nenhum_descritor | Progresso silenciado nao emite em nenhum descritor. | |
| teste_transferencia_e_barra_com_progresso_fracionario | A transferencia com barra aceita progresso fracionario. | |
| teste_transferencia_formata_com_percentual_em_stderr | A linha de transferencia mostra o percentual em stderr. | |
| teste_transferencia_inclui_barra_grafica_em_stderr | A linha de transferencia inclui a barra grafica em stderr. | |


## `tests/unit/progresso_linha_test.sh`

- **Alvo:** `lib/progress.sh`: progresso por arquivo (`dbx_progress_arquivo_*`), linha com percentual, terminal simulado, observador do `.part` e canal de status
- **Modulo:** `progresso_linha`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `progresso-por-arquivo`)
- **Regras de origem:** F-49; RF-140..147; TC-PRG-01; TC-PRG-03; TC-PRG-04; TC-PRG-10..13; TC-PRG-15; TC-PRG-27; TC-PRG-29..32; log `docs/prompts/2026-10-22_1600_progresso-por-arquivo.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** `lib/errors.sh` e `lib/progress.sh` carregados; terminal simulado por `DBX_PROGRESS_TERMINAL`; `.part` temporario para o observador; escrita concorrente no canal de status
- **Comando:** `bash tests/run.sh tests/unit/progresso_linha_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_linha_tem_formato_posicao_barra_percentual_e_bytes | A linha traz posicao, barra, percentual e bytes no formato definido | |
| teste_percentual_arredonda_para_baixo_e_nunca_cem_antes_de_concluir | O percentual arredonda para baixo e so chega a 100 ao concluir | |
| teste_arquivo_de_zero_bytes_vai_de_zero_a_cem | Arquivo de zero bytes vai de 0 a 100 | |
| teste_percentual_nunca_diminui | O percentual nunca diminui entre atualizacoes | |
| teste_retomada_inicia_no_confirmado | Na retomada o progresso comeca no ponto ja confirmado | |
| teste_total_desconhecido_mostra_so_bytes_feitos | Com total desconhecido a linha mostra so os bytes ja feitos | |
| teste_sem_terminal_cada_atualizacao_e_uma_linha_nova_sem_controle | Sem terminal cada atualizacao e uma linha nova, sem caracteres de controle | |
| teste_com_terminal_a_mesma_linha_e_atualizada_e_quebra_so_ao_concluir | Com terminal a mesma linha e reescrita e so quebra ao concluir | |
| teste_falha_deixa_ultimo_percentual_com_sufixo_falhou | Falha deixa o ultimo percentual com o sufixo de falha | |
| teste_falha_no_terminal_termina_a_linha | Falha em terminal termina a linha em curso | |
| teste_sinal_termina_a_linha_em_curso_uma_vez | Sinal recebido termina a linha em curso uma unica vez | |
| teste_caractere_de_controle_no_nome_vira_interrogacao | Caractere de controle no nome vira interrogacao na linha | |
| teste_nome_longo_e_truncado_pelo_meio_preservando_extensao_no_terminal | Em terminal, nome longo e truncado pelo meio preservando a extensao | |
| teste_sem_terminal_nome_longo_nao_e_truncado | Sem terminal o nome longo nao e truncado | |
| teste_progresso_inativo_nao_emite_nem_inicia_observador | Com progresso inativo nada e emitido e nenhum observador e iniciado | |
| teste_observador_acompanha_o_part_e_nao_deixa_orfao | O observador acompanha o `.part` e nao deixa processo orfao | |
| teste_arquivo_abaixo_de_1_mib_nao_tem_observador | Arquivo abaixo de 1 MiB nao tem observador | |
| teste_canal_escrita_concorrente_nunca_deixa_status_invalido | Escrita concorrente no canal de status nunca deixa um status invalido | |


## `tests/unit/qa_rede_p2_test.sh`

- **Alvo:** `lib/http.sh` (timeouts, retentativas, `Retry-After`), `lib/transfer.sh` (retomada em partes, `correct_offset`) e o executor de testes `tests/run.sh` com `tests/support/harness.sh`
- **Modulo:** `qa_rede`
- **Camada:** unitario
- **Autoria:** QA Expert (suite independente da demanda `robustez-de-rede-p2`)
- **Regras de origem:** RNF-07; RNF-30; RF-09; RF-58; RNF-32(a); log `docs/prompts/2026-10-18_2045_robustez-de-rede-p2.md`; protocolo-tdd Regra 9 (parada no primeiro erro, para os casos do executor)
- **Aceite do solicitante:** [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-18-2045-aceite-testes-qa-p2.md), com sha256 `27b0987121c7a7396ba4e2f9293a81ad5736a059ac863dc758a1692107d62c53`
- **Dados e precondicoes:** duble de `curl` e de `sleep` proprios com respostas roteirizadas por chamada (status, cabecalhos e corpo distintos a cada tentativa); copia de `tests/run.sh` e do harness e arquivos de teste fabricados em area temporaria para os casos do executor
- **Comando:** `bash tests/run.sh tests/unit/qa_rede_p2_test.sh`
- **Observacoes:** o `--listar` extrai o nome do primeiro texto entre aspas das funcoes de uma linha; por isso alguns casos aparecem com o texto citado em vez do nome da funcao, e `fabricada` aparece duas vezes (duas funcoes). Sao arquivos de apoio fabricados pelos casos do executor (`teste_b`, `teste_m1`, `teste_m2`, `teste_u1` a `teste_u3`, `teste_f1`), nao testes independentes.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_b | (teste_b) Caso de apoio do executor: grava a marca de que o arquivo seguinte rodou, que o executor nao deve deixar acontecer | RNF-32(a) |
| teste_m2 | (teste_m2) Caso de apoio do executor: grava a marca de que o caso seguinte rodou apos uma falha | RNF-32(a) |
| teste_m1 | (teste_m1) Caso de apoio do executor: falha fabricada para provar que o caso seguinte nao roda | RNF-32(a) |
| teste_u3 | (teste_u3) Caso de apoio do executor: falha fabricada apos caso pulado e aprovado | RNF-32(a) |
| teste_u2 | (teste_u2) Caso de apoio do executor: caso pulado de proposito, contado como pulado e nao como aprovado | RNF-32(a) |
| teste_f1 | Caso de apoio do executor: caso aprovado cujo filtro sem correspondencia deve reprovar o arquivo | RNF-32(a) |
| teste_qa_ajuste_com_espaco_sinal_ou_dez_digitos_e_recusado_antes_da_rede | Ajuste de rede com espaco, sinal ou dez digitos e recusado antes de qualquer chamada | RNF-07 |
| teste_qa_entrada_padrao_em_cano_nao_retoma_mesmo_com_offset_zero | Entrada padrao em cano nao e retomada, mesmo com offset zero devolvido | RF-58 |
| teste_qa_executor_nao_mascara_integridade_atras_de_bail_out | O executor nao mascara falha de integridade escondida atras de um `Bail out!` | RNF-32(a) |
| teste_qa_executor_para_em_arquivo_que_morre_sem_agregado | O executor para no arquivo que morre sem emitir agregado e nao roda o seguinte | RNF-32(a) |
| teste_qa_filtro_de_caso_sem_correspondencia_reprova_o_arquivo | Filtro de caso sem correspondencia reprova o arquivo em vez de aprovar sem executar | RNF-32(a) |
| teste_qa_offset_igual_ao_enviado_reenvia_so_a_parte_recusada | `correct_offset` igual ao enviado reenvia so a parte recusada | RF-58 |
| teste_qa_offset_igual_ao_tamanho_do_arquivo_e_recusado | `correct_offset` igual ao tamanho do arquivo e recusado | RF-58 |
| teste_qa_offset_um_byte_acima_do_enviado_e_recusado | `correct_offset` um byte acima do enviado e recusado | RF-58 |
| teste_qa_origem_que_cresce_na_ultima_parte_sem_retomada_e_recusada | Origem que cresce na ultima parte, sem retomada, e recusada | RF-58 |
| teste_qa_origem_que_encolhe_antes_da_retomada_e_recusada | Origem que encolhe antes da retomada e recusada | RF-58 |
| teste_qa_origem_que_encolhe_sem_retomada_e_recusada | Origem que encolhe sem retomada e recusada | RF-58 |
| teste_qa_parte_esgotada_com_tentativas_igual_a_1_nao_repete | Com tentativas igual a 1, parte esgotada nao e repetida | RNF-07 |
| teste_qa_retomadas_em_partes_distintas_contam_por_parte | Retomadas em partes distintas sao contadas por parte | RF-58 |
| teste_qa_retry_after_301_e_limitado_a_300 | `Retry-After` de 301 segundos e limitado a 300 | RNF-30 |
| teste_qa_retry_after_ausente_em_429_cai_no_recuo_de_base_um_segundo | 429 sem `Retry-After` cai no recuo de base de um segundo | RNF-30 |
| teste_qa_retry_after_com_espacos_e_zero_a_esquerda_vale_em_decimal | `Retry-After` com espacos e zero a esquerda vale em decimal | RNF-30 |
| teste_qa_retry_after_de_uma_tentativa_nao_vaza_para_a_seguinte | `Retry-After` de uma tentativa nao vaza para a seguinte | RNF-30 |
| teste_qa_retry_after_em_falha_de_transporte_seguinte_nao_e_reaproveitado | `Retry-After` anterior nao e reaproveitado numa falha de transporte seguinte | RNF-30 |
| teste_qa_retry_after_negativo_ou_com_digitos_separados_nao_vale | `Retry-After` negativo ou com digitos separados e ignorado | RNF-30 |
| teste_qa_retry_after_no_limite_exato_de_300_vale_300 | `Retry-After` de exatamente 300 segundos vale 300 | RNF-30 |
| teste_qa_retry_after_repetido_vale_um_dos_valores_e_nunca_a_juncao | `Retry-After` repetido vale um dos valores e nunca a juncao deles | RNF-30 |
| teste_qa_servidor_que_alterna_offsets_na_mesma_parte_esgota_as_tentativas | Servidor que alterna offsets na mesma parte esgota as tentativas | RF-58 |
| teste_qa_servidor_que_sempre_volta_ao_inicio_na_mesma_parte_esgota_as_tentativas | Servidor que sempre volta ao inicio na mesma parte esgota as tentativas | RF-58 |
| teste_qa_tentativas_igual_a_1_com_429_nao_espera_nem_repete | Com tentativas igual a 1 e 429, nao espera nem repete | RNF-07 |
| teste_qa_ultimo_caso_reprovado_nao_emite_bail_out_e_reprova | Ultimo caso reprovado nao emite `Bail out!` e o arquivo reprova | RNF-32(a) |
| teste_u1 | Caso de apoio do executor: caso aprovado, antes de um pulado e de uma falha | RNF-32(a) |

## `tests/unit/qa_state_p3_test.sh`

- **Alvo:** `lib/state.sh` (estado hostil, anti-corrida na fronteira de dois segundos), `lib/errors.sh` e `lib/http.sh` (regressao da P3.4 por tabela de referencia) e recusa de segredo na biblioteca
- **Modulo:** `lib/state.sh`
- **Camada:** unitario
- **Autoria:** QA Expert (suite independente da demanda `cache-unico-p3`)
- **Regras de origem:** RNF-25, RF-42, RF-61(a), RF-61(d), RF-63(a); log `docs/prompts/2026-10-18_2243_cache-unico-p3.md`; [entrada](../../.github/agents/memoria/entradas/2026-10-18-2243-aceite-testes-qa-p3.md)
- **Aceite do solicitante:** [entrada](../../.github/agents/memoria/entradas/2026-10-18-2243-aceite-testes-qa-p3.md), sha256 `abc531546531dec8209094ec3f0154af27fe4f27de83161c507dd1dbc496aa12`
- **Dados e precondicoes:** massa propria do QA; `XDG_STATE_HOME` proprio por caso; tabela de referencia colhida do HEAD `007f3ec` (830 combinacoes) para a regressao de classe, politica e codigo
- **Comando:** `bash tests/run.sh tests/unit/qa_state_p3_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_qa_auth_sem_segredo_recusa_antes_da_rede_na_classe_de_rf03 | Autenticacao sem segredo e recusada antes de qualquer chamada de rede, na classe prevista em RF-03 | RF-63(a) |
| teste_qa_p34_classe_politica_e_codigo_iguais_a_referencia | Classe, politica e codigo de erro de todas as combinacoes coincidem com a tabela de referencia do HEAD anterior | P3.4 |
| teste_qa_state_anti_corrida_na_fronteira_de_dois_segundos | Na fronteira de dois segundos a regra anti-corrida do cache de hash se aplica corretamente | RF-61(d) |
| teste_qa_state_caminho_com_tab_e_quebra_de_linha_volta_intacto | Caminho com tabulacao e quebra de linha gravado no estado volta intacto na leitura | |
| teste_qa_state_diretorio_alheio_gravavel_devolve_permissao | Diretorio de estado de outro usuario e gravavel devolve erro de permissao | RNF-25 |
| teste_qa_state_nul_no_meio_do_registro_nao_cria_entrada_espuria | NUL no meio de um registro nao cria entrada espuria | |
| teste_qa_state_registro_como_ligacao_simbolica_nao_e_escrito_atraves | Registro que e ligacao simbolica nao e escrito atraves do vinculo | RF-42 |
| teste_qa_state_registro_de_outro_namespace_e_rejeitado | Registro de outro namespace e rejeitado | RF-61(a) |


## `tests/unit/regex_portavel_test.sh`

- **Alvo:** expressoes regulares de `lib/state.sh` (registro de retomada e cursor) e a regra de portabilidade com RE_DUP_MAX do FreeBSD
- **Modulo:** `lib/state.sh`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `suporte-freebsd`)
- **Regras de origem:** RF-166; TC-FBSD-19 (parte regex); log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** Nao aplicavel: audita o texto de `lib/*.sh` e usa valores de borda sinteticos (256 e 257 caracteres, 8192 e 256); sem dubles
- **Comando:** `bash tests/run.sh tests/unit/regex_portavel_test.sh`
- **Observacoes:** o glibc aceita repeticao ate 32767; o teste audita o texto para pegar o que so falharia no FreeBSD (limite 255)

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_nenhuma_repeticao_de_regex_passa_de_255 | Nenhuma repeticao de regex em lib/*.sh tem limite acima de 255 | RF-166 |
| teste_session_id_do_registro_de_retomada_aceita_256_e_recusa_257_e_vazio | O session_id do registro de retomada aceita 256 caracteres e recusa 257 e vazio | TC-FBSD-19 |
| teste_cursor_e_assinatura_do_cabecalho_respeitam_8192_e_256 | O cursor respeita o limite de 8192 e a assinatura do cabecalho o de 256 | TC-FBSD-19 |


## `tests/unit/resumo_freebsd_test.sh`

- **Alvo:** resumo SHA-256 por capacidade (`lib/hash.sh`), `lib/preflight.sh` e `lib/tmp.sh` sob os utilitarios da base do FreeBSD
- **Modulo:** `resumo_freebsd`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `suporte-freebsd`)
- **Regras de origem:** RF-168; RF-169; TC-FBSD-04, TC-FBSD-05, TC-FBSD-06, TC-FBSD-07, TC-FBSD-10; log `docs/prompts/2026-10-24_1153_suporte-freebsd.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** `PATH` restrito (diretorio de vinculos so com o necessario) e bash filho com `env -i`, de modo que o utilitario ausente de fato nao exista; dubles de `sha256`, `openssl`, `wc` e `mktemp` da base do FreeBSD; vetores literais de `hash_test.sh`
- **Comando:** `bash tests/run.sh tests/unit/resumo_freebsd_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_sem_nenhum_utilitario_de_resumo_o_preflight_recusa_com_codigo_3_nomeando_o_resumo | Sem `sha256sum`, `shasum`, `sha256` e `openssl`, o preflight recusa com codigo 3 e nomeia o resumo | TC-FBSD-10 |
| teste_so_openssl_confere_o_content_hash_no_formato_do_openssl_1 | Apenas com `openssl` no formato 1.x, o `content_hash` confere com o vetor oficial | TC-FBSD-05 |
| teste_so_openssl_confere_o_content_hash_no_formato_do_openssl_3 | Apenas com `openssl` no formato 3.x, o `content_hash` confere com o vetor oficial | TC-FBSD-05 |
| teste_so_sha256_da_base_confere_o_content_hash_e_passa_no_preflight | Apenas com o `sha256` da base do FreeBSD, o `content_hash` confere e o preflight passa | TC-FBSD-04 |
| teste_tamanho_de_bloco_e_inteiro_limpo_com_wc_de_largura_8 | O tamanho de bloco e inteiro limpo mesmo com `wc` que completa a largura com espacos | TC-FBSD-06 |
| teste_tmp_cria_area_e_arquivo_com_mktemp_sem_opcao_longa_e_exige_seis_x | `lib/tmp.sh` cria area e arquivo com `mktemp` sem opcao longa, com seis `X` no modelo | TC-FBSD-07 |


## `tests/unit/retencao_test.sh`

- **Alvo:** `lib/retencao.sh` (politica pura de `--manter` e `--dias`, carimbo, guardas) e casamento de nome avulso de `lib/filtro.sh`
- **Modulo:** `retencao_test`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-6-retencao`)
- **Regras de origem:** F-10; RF-93(e)(f)(g)(h)(j); RF-95; RF-97(b); TC-RTA-05..07; TC-RTP-01..12; TC-RTG-03..05; TC-RTG-09; log `docs/prompts/2026-10-20_2010_backlog-fase-6-retencao.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** lib pura (sem rede, disco, estado nem relogio; o "agora" e argumento, duble do relogio fixado); copias mutantes de `lib/retencao.sh` com uma linha removida; processo isolado com `lib/http` para o cabecalho `Date`; `LC_ALL=C` e localidade ausente nos casos de caixa
- **Comando:** `bash tests/run.sh tests/unit/retencao_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_div134_data_http_vira_segundos_desde_1970 | O cabecalho `Date` HTTP vira segundos desde 1970 | DIV-134 |
| teste_div134_lib_http_expoe_o_cabecalho_date | `lib/http.sh` expoe o cabecalho `Date` da resposta | DIV-134 |
| teste_div158_guarda_recusa_caminho_igual_ao_de_quem_fica | A guarda recusa excluir caminho igual ao de um item que fica | DIV-158 |
| teste_div158_mutantes_da_lib_reprovam | Copias da lib sem a guarda da DIV-158 reprovam o caso | DIV-158 |
| teste_div158_plano_recusa_caminho_repetido | O plano recusa listagem com caminho repetido | DIV-158 |
| teste_div161_chave_unicode_de_rf54 | A chave de comparacao unicode segue a regra de RF-54 | DIV-161; RF-54 |
| teste_div161_div162_mutantes_da_lib_reprovam | Copias da lib sem a chave unicode reprovam o caso | DIV-161, DIV-162 |
| teste_div161_plano_recusa_duplicata_em_caixa_nao_ascii | O plano recusa duplicata que so difere em caixa nao ASCII | DIV-161 |
| teste_div161_sem_localidade_fora_do_ascii_falha_fechada | Sem localidade apropriada, nome fora de ASCII falha fechado | DIV-161 |
| teste_div164_div165_guarda_e_mutantes | A guarda de marca combinante existe e as copias mutantes reprovam | DIV-164, DIV-165 |
| teste_div164_marca_combinante_por_bytes | Marca combinante e detectada por bytes, nao por localidade | DIV-164 |
| teste_div167_guarda_por_rev_e_id_e_mutante | A guarda por `rev` e `id` existe e a copia mutante reprova | DIV-167 |
| teste_div168_utf8_valido_por_bytes | A validade de UTF-8 do nome e verificada por bytes | DIV-168 |
| teste_rta05_manter_aceita_1_a_999999_e_recusa_o_resto | `--manter` aceita de 1 a 999999 e recusa o resto | TC-RTA-05 |
| teste_rta06_dias_aceita_1_a_36500_e_recusa_o_resto | `--dias` aceita de 1 a 36500 e recusa o resto | TC-RTA-06 |
| teste_rta07_casa_o_nome_inteiro_sem_caixa_e_sem_normalizacao | O padrao casa o nome inteiro, sem distinguir caixa e sem normalizacao | TC-RTA-07 |
| teste_rta07_nome_avulso_nao_mexe_nos_filtros_de_caminho | O casamento de nome avulso nao altera os filtros de caminho | TC-RTA-07 |
| teste_rta07_padrao_com_barra_ou_malformado_e_recusado_citado | Padrao com barra ou malformado e recusado e citado na mensagem | TC-RTA-07 |
| teste_rta09_padrao_e_dado_nunca_codigo | O padrao do usuario e tratado como dado, nunca executado como codigo | TC-RTA-09; protocolo-tdd Regra 6 |
| teste_rtc07_padrao_amplo_e_o_sem_caractere_literal | Padrao amplo e definido como o que nao tem caractere literal | TC-RTC-07 |
| teste_rtg03_guarda_recusa_item_incoerente | A guarda recusa item de listagem incoerente | TC-RTG-03 |
| teste_rtg04_fora_do_ascii_a_pasta_falha_fechada | Pasta com nome fora de ASCII falha fechada | TC-RTG-04 |
| teste_rtg05_name_tem_de_ser_o_ultimo_componente_pela_chave | O `name` do item tem de ser o ultimo componente do caminho pela chave | TC-RTG-05 |
| teste_rtg09_mutante_sem_a_guarda_do_primeiro_reprova | Copia da lib sem a guarda do primeiro da ordem reprova | TC-RTG-09 |
| teste_rtg12_lib_retencao_nao_cita_rota_destrutiva_nem_rede | `lib/retencao.sh` nao cita rota destrutiva nem usa rede | TC-RTG-12 |
| teste_rtp01_manter_dois_dos_cinco_mais_novos | Com `--manter 2` em cinco itens, ficam os dois mais novos | TC-RTP-01 |
| teste_rtp02_ordem_de_entrada_nao_muda_o_plano | A ordem da listagem de entrada nao muda o plano | TC-RTP-02 |
| teste_rtp03_empate_fica_antes_o_maior_nome_sem_caixa | Em empate de data, fica o de maior nome sem distinguir caixa | TC-RTP-03 |
| teste_rtp05_carimbo_invalido_derruba_o_plano | Carimbo invalido em um item derruba o plano inteiro | TC-RTP-05 |
| teste_rtp05_carimbo_valido_so_na_forma_exata_e_com_data_existente | Carimbo so e valido na forma exata e com data existente | TC-RTP-05 |
| teste_rtp06_manter_maior_ou_igual_aos_candidatos_nada_sai | Com `--manter` maior ou igual ao numero de candidatos nada e excluido | TC-RTP-06 |
| teste_rtp07_dias_corte_inclusivo_ao_segundo | O corte de `--dias` e inclusivo ao segundo, com relogio fixado | TC-RTP-07 |
| teste_rtp08_dias_com_todos_velhos_mantem_o_mais_novo | Com todos os itens velhos, `--dias` ainda mantem o mais novo | TC-RTP-08 |
| teste_rtp09_dias_com_todos_dentro_e_futuro_fica | Itens dentro do prazo ou no futuro ficam | TC-RTP-09 |
| teste_rtp10_um_so_candidato_nunca_sai | Um unico candidato nunca e excluido | TC-RTP-10 |
| teste_rtp11_zero_candidatos_plano_vazio | Zero candidatos gera plano vazio | TC-RTP-11 |
| teste_rtp12_mutante_sem_o_minimo_reprova | Copia da lib sem o minimo de um item mantido reprova | TC-RTP-12 |
| teste_rtp12_propriedade_sobre_listagens_geradas | Em listagens geradas, a politica sempre mantem ao menos um item e respeita a regra | TC-RTP-12 |

## `tests/unit/retomada_estado_test.sh`

- **Alvo:** registro de retomada (`retomada-*`), travas de registro, poda e barreira do `.part` em `lib/state.sh`
- **Modulo:** `lib/state.sh`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-7a-retomada`)
- **Regras de origem:** F-03; RF-61 (emenda C3); RF-101; RF-105; RF-107; TC-RME-01, 03..11, 13; TC-UPC-13; TC-RMC-02; TC-RMC-03; TC-RML-01..04; parecer do DBA C1 a C6; log `docs/prompts/2026-10-20_2315_backlog-fase-7a-retomada.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** diretorio de estado temporario por caso, registros, arquivos `.part`, FIFOs e ligacoes simbolicas criados pelo proprio teste, processos auxiliares para trava viva
- **Comando:** `bash tests/run.sh tests/unit/retomada_estado_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_rme01_registro_nasce_0600_em_0700_com_campos_nul_na_ordem_e_local_por_ultimo | O registro nasce 0600 em diretorio 0700 com campos separados por NUL na ordem e o local por ultimo | TC-RME-01 |
| teste_rme01_registro_de_download_tem_treze_campos | O registro de download tem treze campos | TC-RME-01 |
| teste_rme01_gravacao_recusa_campo_invalido_sem_criar_registro | A gravacao recusa campo invalido sem criar registro | TC-RME-01 |
| teste_rme03_chave_separa_destino_sentido_conta_e_nao_colide_por_quebra_de_linha | A chave separa destino, sentido e conta e nao colide por quebra de linha | TC-RME-03 |
| teste_rme13_registro_valido_carrega_sem_relogio_decidir | Registro valido carrega sem o relogio decidir a validade | TC-RME-13 |
| teste_rme04_a_rme06_vazio_truncado_e_lixo_nul_sao_descartados | Registro vazio, truncado ou com lixo NUL e descartado | TC-RME-04..06 |
| teste_rme07_magia_errada_e_versao_2_sao_descartadas | Numero magico errado e versao 2 sao descartados | TC-RME-07 |
| teste_rme08_contagem_e_campos_fora_da_regex_sao_descartados | Contagem de campos errada ou campo fora da regex e descartado | TC-RME-08 |
| teste_rme09_registro_acima_de_16_kib_e_descartado | Registro acima de 16 KiB e descartado | TC-RME-09 |
| teste_rme10_conta_sentido_host_remoto_e_local_divergentes_descartam | Conta, sentido, host, remoto ou local divergentes descartam o registro | TC-RME-10 |
| teste_rme11_ligacao_simbolica_e_diretorio_no_lugar_nao_sao_lidos_nem_apagados | Ligacao simbolica ou diretorio no lugar do registro nao e lido nem apagado | TC-RME-11 |
| teste_rme11_registro_de_outro_dono_nao_e_lido_nem_apagado | Registro de outro dono nao e lido nem apagado | TC-RME-11 |
| teste_rme12_diretorio_de_estado_alheio_ou_sem_escrita_fica_inutilizavel | Diretorio de estado alheio ou sem escrita fica inutilizavel sem erro fatal | TC-RME-12 |
| teste_upc13_upload_acima_do_limite_sem_nul_ou_com_campo_invalido_e_cache_ausente | Registro de upload acima do limite, sem NUL ou com campo invalido equivale a cache ausente | TC-UPC-13 |
| teste_barreira_so_aceita_o_part_registrado | A barreira de identidade so aceita o .part registrado (dono, regular, dispositivo, inode, nome, diretorio) | RF-107 |
| teste_rmc02_trava_de_registro_tem_comando_retomada_e_o_mesmo_resumo | A trava de registro carrega o comando retomada e o mesmo resumo da trava de par | TC-RMC-02 |
| teste_rmc02_trava_de_par_e_de_registro_convivem_no_mesmo_processo | Trava de par e de registro convivem no mesmo processo | TC-RMC-02 |
| teste_rmc03_ocupada_outro_host_e_ilegivel_recusam_sem_apagar_e_orfa_e_retomada | Trava ocupada, de outro host ou ilegivel recusa sem apagar; trava orfa e retomada | TC-RMC-03 |
| teste_rml01_poda_tira_so_retomada_com_mais_de_8_dias_e_sem_trava_viva | A poda remove so registros de retomada com mais de 8 dias e sem trava viva | TC-RML-01 |
| teste_rml02_teto_de_1000_registros_tira_os_mais_antigos | O teto de 1000 registros remove os mais antigos | TC-RML-02 |
| teste_rml03_part_de_registro_podado_so_sai_pela_barreira | O .part de registro podado so e apagado pela barreira de identidade | TC-RML-03 |
| teste_rml04_temporario_retomada_velho_sai_e_o_recente_fica | Temporario de retomada velho sai e o recente fica | TC-RML-04 |
| teste_rml06_listagem_so_le_e_classifica_pendente_ilegivel_e_orfa | A listagem so le e classifica registros em pendente, ilegivel e orfa | TC-RML-06 |
| teste_c2_fifo_no_lugar_do_registro_nao_bloqueia_leitor_listagem_nem_travas | FIFO no lugar do registro nao bloqueia leitor, listagem nem travas | C2 |
| teste_c2_poda_ignora_entrada_nao_regular | A poda ignora entradas que nao sao arquivo regular | C2 |
| teste_c2_descarte_por_cabecalho_leva_o_part_pela_barreira | Descarte por cabecalho leva o .part pela barreira de identidade | C2 |


## `tests/unit/state_test.sh`

- **Alvo:** `lib/state.sh` (cache unico de `content_hash`: carga, gravacao atomica, namespaces `memoria-*` do sync e `upload-*` do upload, identidade forte, poda e diretorio de estado)
- **Modulo:** state
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `cache-unico-p3`)
- **Regras de origem:** RNF-32(d); RNF-33; log `docs/prompts/2026-10-18_2243_cache-unico-p3.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** `XDG_STATE_HOME` proprio e temporario por caso, rodando em subshell do harness (nada vaza entre casos); arquivos de cache sinteticos, inclusive corrompidos e hostis; sem rede
- **Comando:** `bash tests/run.sh tests/unit/state_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_caminho_sem_resumo_admissivel_continua_registrado_como_presente | Caminho sem resumo admissivel continua registrado como presente na memoria do sync. | |
| teste_diretorio_de_estado_nasce_0700_e_arquivos_0600 | O diretorio de estado nasce 0700 e os arquivos 0600. | |
| teste_diretorio_de_outro_dono_e_recusado_como_permissao_sem_escrita | Diretorio de estado de outro dono e recusado como permissao sem escrita. | |
| teste_diretorio_existente_do_usuario_e_corrigido_para_0700 | Diretorio existente do usuario com modo frouxo e corrigido para 0700. | |
| teste_gravacao_completa_guarda_so_as_entradas_visitadas | Gravacao completa guarda so as entradas visitadas na execucao. | |
| teste_gravacao_parcial_preserva_as_entradas_nao_visitadas | Gravacao parcial preserva as entradas nao visitadas. | |
| teste_gravacao_renova_o_carimbo_de_uso | Gravar renova o carimbo de uso do arquivo de cache. | |
| teste_memoria_do_sync_corrompida_ou_hostil_e_descartada | Memoria do sync corrompida ou hostil e descartada sem falhar. | |
| teste_memoria_existente_e_ilegivel_conta_como_descartada | Memoria existente mas ilegivel conta como descartada. | |
| teste_namespaces_do_upload_e_do_sync_nao_se_tocam | Os namespaces `upload-*` e `memoria-*` nao se tocam. | |
| teste_nome_do_arquivo_de_cache_nao_carrega_texto_do_caminho | O nome do arquivo de cache nao carrega texto do caminho original. | |
| teste_poda_acima_do_teto_remove_os_nao_usados_ha_mais_de_90_dias | Acima do teto de arquivos, a poda remove os nao usados ha mais de 90 dias. | |
| teste_poda_no_teto_nao_remove_nada | No teto exato de arquivos, a poda nao remove nada. | |
| teste_reescrita_do_registro_e_atomica_por_renomeacao | A reescrita do registro e atomica por renomeacao. | |
| teste_registro_de_upload_corrompido_e_descartado_sem_falhar | Registro de upload corrompido e descartado sem falhar. | |
| teste_registro_hostil_que_e_diretorio_nao_recebe_a_gravacao | Registro hostil que e um diretorio nao recebe a gravacao. | |
| teste_sync_nao_registra_stat_divergente_nem_mtime_recente | O sync nao registra arquivo com stat divergente nem mtime recente. | |
| teste_sync_reaproveita_so_com_identidade_identica | O sync reaproveita o hash so quando a identidade do arquivo e identica. | |
| teste_temporarios_orfaos_antigos_saem_e_os_recentes_ficam | Temporarios orfaos antigos sao removidos e os recentes ficam. | |
| teste_upload_grava_e_reaproveita_com_identidade_identica | O upload grava e reaproveita o hash com identidade identica. | |
| teste_upload_nao_grava_arquivo_modificado_ha_menos_de_dois_segundos | O upload nao grava arquivo modificado ha menos de dois segundos. | |
| teste_upload_nao_grava_quando_o_stat_muda_durante_o_calculo | O upload nao grava quando o stat muda durante o calculo do hash. | |
| teste_upload_nao_reaproveita_quando_qualquer_campo_da_identidade_difere | O upload nao reaproveita quando qualquer campo da identidade difere. | |
| teste_upload_sem_cache_para_arquivo_vazio_e_para_fila_nomeada | O upload nao usa cache para arquivo vazio nem para fila nomeada (stdin). | |


## `tests/unit/state_trava_raiz_test.sh`

- **Alvo:** `lib/state.sh`: trava por raiz local canonica entre processos
- **Modulo:** `state_trava_raiz`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-8-perfis`)
- **Regras de origem:** F-18; RF-132; DIV-250; TC-PFT-01..03; TC-PFT-06..08; log `docs/prompts/2026-10-21_1735_backlog-fase-8-perfis.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** processos `bash` proprios com `lib/errors`, `json`, `config` e `state`; raizes e diretorio de estado temporarios; disputantes reais da trava
- **Comando:** `bash tests/run.sh tests/unit/state_trava_raiz_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_pft01_segunda_aquisicao_da_mesma_raiz_recusa_com_conflito | A segunda aquisicao da trava da mesma raiz e recusada com conflito | TC-PFT-01 |
| teste_pft02_grafias_diferentes_da_mesma_pasta_resolvem_a_mesma_trava | Grafias diferentes da mesma pasta resolvem a mesma trava | TC-PFT-02 |
| teste_pft_raizes_diferentes_tem_travas_diferentes_e_aninhadas_nao_sao_cobertas | Raizes diferentes tem travas diferentes e raizes aninhadas nao se cobrem | |
| teste_pft03_espera_cobre_a_trava_e_conclui_quando_a_primeira_termina | A espera cobre a trava e conclui quando a primeira execucao termina | TC-PFT-03 |
| teste_pft06_trava_orfa_de_processo_morto_e_retomada | Trava orfa de processo morto e retomada | TC-PFT-06 |
| teste_pft07_a_trava_nao_carrega_credencial_conta_nem_perfil | A trava nao carrega credencial, conta nem perfil | TC-PFT-07 |
| teste_pft08_par_depois_raiz_libera_na_ordem_inversa_e_falha_da_segunda_libera_a_primeira | O par de travas e liberado na ordem inversa e a falha da segunda libera a primeira | TC-PFT-08 |
| teste_pft_liberacao_so_apaga_a_propria_e_limpa_o_diretorio_criado | A liberacao so apaga a propria trava e limpa o diretorio que criou | |
| teste_pft_raiz_inexistente_nao_tem_identidade | Raiz inexistente nao tem identidade de trava | |


## `tests/unit/state_trava_test.sh`

- **Alvo:** `lib/state.sh` (trava de concorrencia por par, retomada de trava orfa, listagem), com apoio de `lib/tmp.sh` e `lib/hash.sh`
- **Modulo:** state_trava
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-2-trava-e-tmp`)
- **Regras de origem:** RF-69; parecer do DBA de 2026-10-19; TC-TRV-12..15, 17, 21..30, 32..34 e a parte de biblioteca de TC-TRV-01, 09..11, 18; DIV-53; log `docs/prompts/2026-10-19_1419_backlog-fase-2-trava-e-tmp.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** processos `bash` proprios como disputantes reais, liberados por barreira de arquivo; diretorios de estado e `TMPDIR` temporarios; duplo de `ln` onde o caso exige; sem rede
- **Comando:** `bash tests/run.sh tests/unit/state_trava_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_aquisicao_cria_0600_em_0700_com_linha_unica_e_liberacao_remove | A aquisicao cria a trava com modo 0600 em diretorio 0700, com linha unica, e a liberacao a remove | |
| teste_boot_diferente_no_mesmo_host_e_orfa_mesmo_com_pid_vivo | Boot diferente no mesmo host torna a trava orfa, mesmo que o PID esteja vivo | |
| teste_c2_erro_de_uso_da_aquisicao_e_uso | Chamada de aquisicao com argumentos invalidos retorna erro de uso | |
| teste_c2_estado_sem_escrita_sem_trava_segue_e_com_viva_recusa | Estado sem escrita sem trava segue; com trava viva recusa | |
| teste_c2_mesma_grafia_mesma_chave_em_c_e_em_c_utf8 | A mesma grafia gera a mesma chave nas localidades C e C.UTF-8 | |
| teste_c2_pai_sem_escrita_e_estado_alheio_sao_permissao | Diretorio pai sem escrita ou estado de outro usuario resulta em erro de permissao | |
| teste_c2_qualquer_byte_depois_da_quebra_final_e_ilegivel | Qualquer byte apos a quebra de linha final torna a trava ilegivel | |
| teste_chave_e_sem_ordem_sem_caixa_no_remoto_e_por_par | A chave e independente da ordem e da caixa do remoto, e distinta por par | |
| teste_diretorio_criado_pela_trava_sai_vazio_e_o_preexistente_fica | O diretorio criado pela trava sai vazio ao liberar e o preexistente permanece | |
| teste_div53_quem_apaga_a_orfa_avisa_mesmo_perdendo_o_ln | Quem apaga a trava orfa avisa mesmo quando perde a disputa do `ln` | DIV-53 |
| teste_dois_e_vinte_retomadores_da_mesma_orfa_exatamente_um_vence | Dois e vinte retomadores da mesma orfa: exatamente um vence | |
| teste_host_id_tem_nome_boot_e_namespace_no_alfabeto | O identificador do host tem nome, boot e namespace no alfabeto permitido | |
| teste_identidade_que_muda_antes_da_releitura_solta_a_r_e_nao_apaga_a_nova | Se a identidade muda antes da releitura, solta o `.r` e nao apaga a trava nova | |
| teste_kill_9_entre_a_gravacao_e_a_liberacao_deixa_memoria_integra_e_trava_retomavel | SIGKILL entre a gravacao e a liberacao deixa a memoria do processo integra e a trava retomavel | |
| teste_leitor_concorrente_nunca_ve_trava_vazia_ou_parcial | Leitor concorrente nunca ve a trava vazia ou parcialmente escrita | |
| teste_liberacao_nunca_apaga_trava_de_outro_dono | A liberacao nunca apaga a trava de outro dono | |
| teste_listagem_classifica_e_nao_cria_o_diretorio | A listagem classifica as travas e nao cria o diretorio quando ausente | |
| teste_matriz_hostil_e_ilegivel_nunca_apagada_nem_retomada_nem_ecoada | Matriz de travas hostis ou ilegiveis: nunca apagadas, retomadas nem ecoadas na saida | protocolo-tdd Regra 6 |
| teste_namespace_ou_nome_diferente_e_outro_host_nunca_retomado | Namespace ou nome de host diferente e outro host, e a trava nunca e retomada | |
| teste_orfa_do_mesmo_host_e_retomada_com_aviso | Trava orfa do mesmo host e retomada com aviso | |
| teste_poda_e_limpeza_nunca_tocam_trava | A poda e a limpeza do estado nunca tocam as travas | |
| teste_ponto_r_orfa_nao_e_retomada_e_recusa | Ponto `.r` orfa nao e retomado e a aquisicao recusa | |
| teste_sucesso_e_o_inode_e_nao_o_codigo_do_ln | O sucesso da aquisicao e decidido pelo inode da trava e nao pelo codigo de saida do `ln` | |
| teste_temporario_de_trava_antigo_e_varrido_e_o_novo_fica | Temporario de trava antigo e varrido e o recente permanece | |
| teste_termino_do_processo_libera_a_trava | O termino do processo libera a trava que ele detinha | |
| teste_trava_com_dono_alheio_ligacao_ou_diretorio_e_ilegivel_e_intacta | Trava de dono alheio, ligacao simbolica ou diretorio e ilegivel e fica intacta | protocolo-tdd Regra 6 |
| teste_trava_viva_recusa_com_7_e_mensagem_sem_segredo | Trava viva recusa a aquisicao com codigo 7 e mensagem sem segredo | |
| teste_vinte_processos_disputam_e_exatamente_um_vence | Vinte processos disputam a trava e exatamente um vence | |

## `tests/unit/sync_blocos_test.sh`

- **Alvo:** `lib/cli.sh` (`dbx_cli_validar_bloco`), `lib/cmd.sh` (`dbx_cmd_bloco`), `lib/sync.sh` (`dbx_sync_blocos_planejar`, `dbx_sync_listar_diretorio`): validacao de `--bloco`/`DBX_BLOCO`, planejador de ciclos e listagem remota de um diretorio
- **Modulo:** `sync_blocos` (filtro do mapa de modulos)
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `sync-em-blocos`)
- **Regras de origem:** F-101; RF-186..RF-197; TC-BLC-nn (secao 5.24 do escopo); log `docs/prompts/2026-10-31_1200_sync-em-blocos.md`; registro `docs/reviews/2026-10-31-1200-registro-sync-em-blocos.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** libs de `lib/` carregadas; a camada de autenticacao e substituida por funcoes locais que devolvem paginas sinteticas; vetores sinteticos de nomes e contagens; sem rede
- **Comando:** `bash tests/run.sh tests/unit/sync_blocos_test.sh`
- **Observacoes:** Etapa 1 de F-101 (RF-186, RF-187, RF-189); o planejador e puro.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_validar_bloco_aceita_a_faixa_1_a_1000000 | `dbx_cli_validar_bloco` aceita 1, 7, 50000, 999999 e 1000000, devolve 0 e publica o valor em `DBX_CLI_BLOCO`. | RF-186 |
| teste_validar_bloco_recusa_fora_da_faixa_e_formato_invalido | Valores 0, 1000001, 9999999, negativos, com sinal, com zero a esquerda, vazio, com espaco, texto, decimal, expoente e com quebra de linha saem com erro de uso, nada e publicado e o motivo nomeia `--bloco`; na variavel o motivo nomeia `variavel de ambiente DBX_BLOCO`. | RF-186 |
| teste_bloco_padrao_sem_opcao_nem_variavel | Sem opcao nem variavel, `dbx_cmd_bloco` resolve o padrao 50000 com origem `padrao`. | RF-186 |
| teste_bloco_variavel_valida_vale_e_invalida_recusa | `DBX_BLOCO=100` vale com origem `ambiente`; `DBX_BLOCO=abc` e `DBX_BLOCO` vazia recusam com erro de uso e o motivo nomeia a variavel. | RF-186 |
| teste_bloco_opcao_vence_e_a_variavel_nao_e_lida | Com `--bloco 100` valido e `DBX_BLOCO=abc` invalida, a opcao vence (origem `opcao`) e a variavel nao e lida; `--batch 0` recusa e o motivo nomeia a opcao como digitada. | RF-186 (precedencia e alias) |
| teste_planejador_arvore_que_cabe_forma_um_ciclo | Com N=100 e diretorios de 10, 20 e 30 arquivos, o planejador forma um unico ciclo (`0-3`). | RF-187 |
| teste_planejador_diretorio_que_cruza_n_entra_inteiro_e_fecha | Com N=10 e diretorios de 6, 6 e 1, o segundo cruza N (12), entra inteiro no ciclo e o fecha; o terceiro abre outro (`0-2 2-3`). | RF-187 |
| teste_planejador_total_exato_em_n_fecha_o_ciclo | Com N=10 e diretorios de 6, 4 e 1, atingir exatamente N fecha o ciclo (`0-2 2-3`). | RF-187 |
| teste_planejador_diretorio_maior_que_n_fica_sozinho | Com N=10 e diretorios de 3, 50 e 1, o diretorio maior que N forma ciclo proprio e o anterior fecha antes dele (`0-1 1-2 2-3`). | RF-187(c) |
| teste_planejador_diretorio_vazio_conta_zero_e_e_unidade | Diretorios com zero arquivos contam zero, sao unidades do ciclo e nao fecham ciclo (`0-4`). | RF-187 |
| teste_planejador_cada_diretorio_em_exatamente_um_ciclo | Em 40 diretorios com contagens variadas e N=17, a uniao dos ciclos cobre cada diretorio exatamente uma vez, sem omissao, duplicacao ou troca de ordem. | RF-187(d) |
| teste_planejador_lista_vazia_e_entrada_invalida | Lista vazia planeja sem ciclos; contagem nao numerica e vetores de tamanhos diferentes saem com erro de uso. | RF-187 |
| teste_listar_diretorio_pede_nao_recursivo_e_alimenta_a_tabela | `dbx_sync_listar_diretorio` pede `list_folder` com `"recursive":false` e coloca o arquivo (tipo f) e a subpasta (tipo d) na tabela remota. | RF-189(a) |
| teste_listar_diretorio_acumula_entre_chamadas_e_segue_continue | Segue a paginacao por `list_folder/continue` e a tabela acumula as entradas de dois diretorios listados em chamadas sucessivas, sem zerar. | RF-189 |
| teste_listar_diretorio_inexistente_e_vazio_legitimo | Resposta `path/not_found/` na listagem e lista vazia legitima: devolve 0 e a tabela fica vazia. | RF-189 |
| teste_listar_diretorio_falha_remota_sinaliza_parcialidade | Falha remota (`too_many_requests`) devolve o codigo da classe de erro e o motivo cita a enumeracao remota. | RF-189; RF-190 |
| teste_listar_diretorio_falha_na_segunda_pagina_e_parcial | Falha na segunda pagina da listagem devolve codigo diferente de zero (enumeracao parcial). | RF-190 |
| teste_listar_diretorio_cursor_repetido_e_erro_remoto_parcial | Paginas que repetem o mesmo cursor (laco) saem com o codigo de `erro_remoto`. | RF-189 |
| teste_listar_diretorio_recusa_uso_incorreto | Chamada sem o diretorio devolve erro de uso. | RF-189 |


## `tests/unit/sync_plano_test.sh`

- **Alvo:** `lib/sync.sh` (`dbx_sync_comparar`, traducao do plano para os quatro estados do `verificar`)
- **Modulo:** sync_plano
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-1-consulta-diagnostico`)
- **Regras de origem:** RF-65(c)(d); log `docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** vetores e mapas associativos sinteticos passados por nome a `lib/sync`; sem rede nem arquivos
- **Comando:** `bash tests/run.sh tests/unit/sync_plano_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_comparar_arquivo_contra_pasta_e_diferente_por_tipo | Arquivo de um lado e pasta do outro resultam em estado diferente com motivo `tipo`. | |
| teste_comparar_casa_os_lados_sem_caixa_e_mantem_a_grafia_da_origem | A comparacao casa os lados sem distinguir caixa e mantem a grafia da origem. | |
| teste_comparar_exige_quatro_argumentos | A funcao exige quatro argumentos e falha sem eles. | |
| teste_comparar_lados_vazios_nao_publica_nada | Com os dois lados vazios nada e publicado. | |
| teste_comparar_publica_os_quatro_estados_na_ordem_da_chave | Publica os quatro estados na ordem estavel da chave. | |
| teste_comparar_resumo_malformado_nunca_e_igual | Resumo malformado nunca resulta em estado igual. | |


## `tests/unit/sync_tabela_test.sh`

- **Alvo:** `lib/sync.sh` (tabela remota: retrato carregado, delta aplicado, confinamento e agrupamento das confirmacoes de exclusao)
- **Modulo:** sync_tabela
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-7b-cursor`)
- **Regras de origem:** F-14; DIV-g; RF-112; RF-114; RF-115; parecer do DBA (secao 5; C3, C4, C5); log `docs/prompts/2026-10-21_0713_backlog-fase-7b-cursor.md`
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** vetores e canais sinteticos lidos por nome por `lib/sync`; unica fronteira dublada e a rede (`dbx_auth_requisitar`), redefinida por caso na confirmacao; sem rede
- **Comando:** `bash tests/run.sh tests/unit/sync_tabela_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_confirmacao_agrupa_por_raiz_apagada_e_respeita_o_teto | A confirmacao de exclusao agrupa por raiz apagada e respeita o teto de confirmacoes. | |
| teste_delta_incoerente_e_recusado_e_a_varredura_so_marca | Delta incoerente e recusado e a varredura completa so marca, sem apagar. | |
| teste_emitir_aplica_o_escopo_depois_e_conta_como_antes | A emissao aplica o escopo depois de montar a tabela e as contagens valem como antes. | |
| teste_ids_unicos_detecta_movimento_sem_deleted | Ids unicos permitem detectar movimento mesmo sem entrada deleted. | |
| teste_qa_b7b_01_raiz_vazia_da_api_confina_e_ignora_nada | Raiz vazia da API confina os caminhos e nao ignora entrada alguma. | |
| teste_qa_b7b_02_entrada_da_propria_raiz_e_ignorada_sem_bloquear_o_retrato | Entrada da propria raiz e ignorada sem bloquear o retrato. | |
| teste_qa_b7b_03_delta_confina_tambem_o_path_lower | O delta confina tambem o `path_lower`. | |
| teste_raiz_apagada_e_recriada_nao_cobre_ninguem | Raiz apagada e recriada nao cobre nenhum item como apagado. | |
| teste_receita_do_servico_deleted_file_e_folder | A receita do servico trata deleted de arquivo e de pasta como documentado. | |
| teste_retrato_confina_cada_caminho_e_recusa_repetido | O retrato confina cada caminho e recusa caminho repetido. | |
| teste_so_not_found_confirma | Somente a resposta not_found confirma a exclusao. | |
| teste_tabela_datada_so_com_filtro_de_data | A tabela datada so e montada quando ha filtro de data. | |


## `tests/unit/tmp_test.sh`

- **Alvo:** `lib/tmp.sh` (registro unico de areas temporarias e acoes de liberacao com tratadores de sinal) e auditoria de `mktemp` e `trap` em `lib/`, `commands/` e `bin/dbx`
- **Modulo:** `lib/tmp.sh`
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `backlog-fase-2-trava-e-tmp`)
- **Regras de origem:** RNF-35; RNF-36; TC-TMP-01..09; TC-CNF-01; F-12; F-31; log `docs/prompts/2026-10-19_1419_backlog-fase-2-trava-e-tmp.md`; mapa de modulos Regra 1
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** processo proprio (`bash -c`) por caso de sinal, `TMPDIR` privado por caso; a auditoria varre o texto de `lib/*.sh`, `commands/*.sh` e `bin/dbx`
- **Comando:** `bash tests/run.sh tests/unit/tmp_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_area_nasce_0700_com_nome_do_projeto_e_sai_no_termino_normal | A area temporaria nasce 0700 com o nome do projeto e e removida no termino normal | TC-TMP-02 |
| teste_termino_normal_preserva_o_codigo_de_saida | O termino normal preserva o codigo de saida do processo | TC-TMP-02 |
| teste_rotulo_fora_do_alfabeto_e_recusado_sem_criar_nada | Rotulo fora do alfabeto permitido e recusado sem criar nada | TC-TMP-03 |
| teste_arquivo_em_diretorio_dado_e_esquecido_depois_do_mv | Arquivo registrado e esquecido depois de movido (mv) e nao e mais removido | TC-TMP-04 |
| teste_remover_apaga_e_tira_do_registro | Remover apaga o item e o tira do registro | TC-TMP-04 |
| teste_sinais_removem_a_area_executam_as_acoes_e_saem_com_14 | Sinais removem a area, executam as acoes de liberacao e saem com 14 | TC-TMP-05 |
| teste_termino_normal_executa_as_acoes_em_ordem_inversa | O termino normal executa as acoes em ordem inversa ao registro | TC-TMP-06 |
| teste_gancho_antes_roda_antes_das_acoes_no_termino_normal | O gancho antes roda antes das acoes no termino normal | TC-TMP-06 |
| teste_gancho_antes_roda_antes_das_acoes_no_sinal | O gancho antes roda antes das acoes ao receber sinal | TC-TMP-06 |
| teste_gancho_sozinho_mantem_o_codigo_do_proprio_sinal | Um gancho sozinho mantem o codigo de saida do proprio sinal | TC-TMP-06 |
| teste_segundo_gancho_no_mesmo_processo_e_recusado | Segundo gancho no mesmo processo e recusado | TC-TMP-07 |
| teste_gancho_antes_recusa_texto_que_nao_e_funcao | O gancho antes recusa texto que nao e funcao | TC-TMP-07 |
| teste_acao_cancelada_nao_executa | Acao cancelada nao e executada | TC-TMP-08 |
| teste_acao_que_nao_e_funcao_e_recusada | Acao que nao e funcao e recusada | TC-TMP-08 |
| teste_sinal_seguido_de_exit_nao_repete_as_acoes | Sinal seguido de exit nao repete as acoes de liberacao | TC-TMP-05 |
| teste_sinal_durante_a_liberacao_nao_interrompe_a_liberacao | Sinal durante a liberacao nao a interrompe | TC-TMP-05 |
| teste_subshell_limpa_so_o_que_registrou | Subshell limpa apenas o que ele mesmo registrou | TC-TMP-09 |
| teste_sinal_logo_depois_do_mktemp_nao_deixa_a_area | Sinal logo depois do mktemp nao deixa a area temporaria | TC-TMP-05 |
| teste_nenhum_mktemp_nem_trap_fora_de_lib_tmp | Nenhum mktemp nem trap existe fora de lib/tmp.sh em lib, commands e bin/dbx | TC-TMP-01 |
| teste_auditoria_reprova_a_forma_reintroduzida | A auditoria reprova a forma antiga reintroduzida (mutacao sintetica) | TC-TMP-01 |
| teste_sync_e_verificar_usam_o_mesmo_ciclo_sem_codigo_gemeo | commands/sync.sh e commands/verificar.sh usam o mesmo ciclo comum, sem area, remocao ou tratador proprio | TC-CNF-01 |

## `tests/unit/transfer_test.sh`

- **Alvo:** `lib/transfer.sh` (sessao de envio em partes sequencial com retentativa e retomada na mesma execucao)
- **Modulo:** transfer
- **Camada:** unitario
- **Autoria:** Senior Developer (TDD da demanda `feat(transfer): envio em partes por sessao sequencial com retentativa`; sem log de prompt)
- **Regras de origem:** RF-08; RF-09; RF-31 (citados no cabecalho do teste); sem log de prompt (commit de criacao `ca64c8d`)
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** substituto do cliente HTTP que registra por chamada a URL, o alvo, o tamanho do corpo, o argumento do cabecalho, a ocupacao em disco e as permissoes no momento da chamada; arquivos de origem temporarios em multiplos de 4 MiB e nao multiplos; sem rede
- **Comando:** `bash tests/run.sh tests/unit/transfer_test.sh`
- **Observacoes:** verifica a sequencia observada pelo cliente, pois defeito de ordem ou deslocamento produz arquivo remoto bem formado e errado sem alterar o status de saida.

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_a_sessao_devolve_a_umask_que_recebeu | Ao terminar, a sessao devolve a umask que recebeu. | |
| teste_a_umask_e_devolvida_tambem_quando_a_area_temporaria_falha | A umask e devolvida tambem quando a criacao da area temporaria falha. | |
| teste_area_e_bloco_nascem_com_permissao_restrita | Area temporaria e bloco nascem com permissao restrita. | |
| teste_arquivo_que_muda_de_tamanho_durante_o_envio_e_recusado | Arquivo que muda de tamanho durante o envio e recusado. | |
| teste_cada_retomada_consome_uma_tentativa | Cada retomada de parte consome uma tentativa do limite. | |
| teste_commit_ausente_e_uso_invalido | Chamada sem o commit e uso invalido. | |
| teste_content_hash_coincidente_declara_integridade_conferida | `content_hash` do finish igual ao local declara a integridade conferida. | |
| teste_content_hash_do_finish_divergente_do_local_e_integridade | `content_hash` do finish diferente do local e erro de integridade. | |
| teste_deslocamento_acima_do_ja_enviado_e_recusado_sem_finish | Deslocamento informado acima do ja enviado e recusado sem chamar o finish. | |
| teste_deslocamento_hostil_e_recusado_sem_finish_e_sem_residuo | Deslocamento hostil e recusado sem finish e sem residuo temporario. | |
| teste_entrada_padrao_nao_retoma | Entrada padrao (stdin) nao retoma por deslocamento. | |
| teste_entrada_vazia_produz_arquivo_vazio_com_resumo_do_conteudo_vazio | Entrada vazia produz arquivo vazio com o resumo do conteudo vazio. | |
| teste_falha_de_leitura_no_meio_nao_publica_nada_e_nao_deixa_residuo | Falha de leitura no meio nao publica nada e nao deixa residuo. | |
| teste_falha_transitoria_reenvia_apenas_a_parte_afetada | Falha transitoria reenvia apenas a parte afetada. | |
| teste_fluxo_multiplo_exato_de_partes_emite_a_sequencia_correta | Fluxo de tamanho multiplo exato de partes emite a sequencia start, appends e finish correta. | RF-08 |
| teste_fluxo_nao_multiplo_de_partes_fecha_com_o_resto_no_finish | Fluxo nao multiplo de partes fecha com o resto enviado no finish. | RF-08 |
| teste_incorrect_offset_coerente_conta_como_parte_ja_aceita | `incorrect_offset` coerente conta como parte ja aceita pelo servico. | |
| teste_incorrect_offset_em_arquivo_regular_retoma_do_deslocamento_informado | `incorrect_offset` em arquivo regular retoma do deslocamento informado. | |
| teste_incorrect_offset_incoerente_aborta_com_diagnostico_util | `incorrect_offset` incoerente aborta com diagnostico util. | |
| teste_interrupcao_com_o_tratador_armado_nao_publica_nada_e_esvazia_o_tmpdir | Interrupcao com o tratador armado nao publica nada e esvazia o diretorio temporario. | |
| teste_limiar_de_roteamento_e_o_teto_por_requisicao | O limiar de roteamento para sessao e o teto por requisicao. | RF-09 |
| teste_nenhum_residuo_temporario_apos_sucesso | Apos sucesso nenhum residuo temporario permanece. | |
| teste_nenhuma_requisicao_isolada_acima_do_teto_por_requisicao | Nenhuma requisicao isolada passa do teto por requisicao. | RF-09 |
| teste_ocupacao_maxima_e_de_um_bloco_e_nao_cresce_com_o_numero_de_partes | A ocupacao maxima em disco e de um bloco e nao cresce com o numero de partes. | RF-31 |
| teste_origem_que_nao_e_arquivo_regular_nao_retoma | Origem que nao e arquivo regular nao retoma. | |
| teste_parte_que_falha_em_todas_as_tentativas_aborta_sem_finish | Parte que falha em todas as tentativas aborta sem chamar o finish. | |
| teste_retomada_nao_escreve_estado_persistente | A retomada na mesma execucao nao escreve estado persistente. | |
| teste_roteamento_recusa_tamanho_que_nao_e_numero | O roteamento recusa tamanho que nao e numero. | |
| teste_sem_resumo_no_finish_a_integridade_nao_e_afirmada | Sem resumo no finish a integridade nao e afirmada. | |
| teste_sessao_invalidada_pelo_servico_aborta_com_diagnostico_proprio | Sessao invalidada pelo servico aborta com diagnostico proprio. | |
| teste_simulacao_nao_alcanca_a_sessao_e_falha_fechado | Simulacao (`--dry-run`) nao alcanca a sessao e falha fechado. | |
| teste_tag_que_apenas_contem_incorrect_offset_nao_entra_no_ramo_de_deslocamento | Tag que apenas contem o texto `incorrect_offset` nao entra no ramo de deslocamento. | |
| teste_tamanho_de_arquivo_ausente_ou_ilegivel_e_uso_invalido | Tamanho de arquivo ausente ou ilegivel e uso invalido. | |
| teste_tamanho_de_arquivo_vem_do_proprio_arquivo | O tamanho considerado vem do proprio arquivo e nao de argumento. | |
| teste_tamanho_de_parte_e_de_4_mib | O tamanho de cada parte e de 4 MiB. | RF-09 |
| teste_voltar_e_reaceitar_o_mesmo_trecho_nao_renova_as_tentativas | Voltar e reaceitar o mesmo trecho nao renova as tentativas. | |


## `tests/unit/walk_test.sh`

- **Alvo:** `lib/walk.sh`: travessia da arvore local por descida
- **Modulo:** `walk`
- **Camada:** unitario
- **Autoria:** Senior Developer (commit `f8b9ed0`, `feat(sync): sincronizacao direcional com a origem como autoridade`; sem log de prompt)
- **Regras de origem:** RNF-28; RF-41a; log de prompt: Nao aplicavel: anterior a trilha do protocolo
- **Aceite do solicitante:** Nao aplicavel: teste do Senior Developer
- **Dados e precondicoes:** `lib/errors.sh`, `lib/walk.sh` e `lib/hash.sh` carregados; arvores temporarias com nomes especiais, ligacoes simbolicas e diretorios sem permissao montados no caso
- **Comando:** `bash tests/run.sh tests/unit/walk_test.sh`

| Caso | O que verifica | Regra especifica |
|---|---|---|
| teste_percorre_a_arvore_inteira_com_caminhos_relativos | A travessia percorre a arvore inteira com caminhos relativos | |
| teste_arquivo_oculto_e_transferivel_como_qualquer_outro | Arquivo oculto e tratado como qualquer outro | |
| teste_nome_com_quebra_de_linha_sobrevive_a_travessia | Nome com quebra de linha sobrevive a travessia | |
| teste_diretorio_vazio_nao_produz_registro_literal | Diretorio vazio nao produz registro literal | |
| teste_ligacao_simbolica_nao_e_seguida_e_marca_a_travessia | Ligacao simbolica nao e seguida e marca a travessia como parcial | |
| teste_subdiretorio_ilegivel_em_profundidade_um_marca_parcial | Subdiretorio ilegivel na profundidade um marca a travessia como parcial | |
| teste_subdiretorio_ilegivel_em_profundidade_n_marca_parcial | Subdiretorio ilegivel em profundidade maior marca a travessia como parcial | |
| teste_raiz_inexistente_ou_ilegivel_e_recusada | Raiz inexistente ou ilegivel e recusada | |
| teste_entrada_que_nao_e_arquivo_comum_marca_parcial | Entrada que nao e arquivo comum marca a travessia como parcial | |
| teste_travessia_nao_altera_o_diretorio_corrente_do_chamador | A travessia nao altera o diretorio corrente do chamador | |
| teste_nenhum_ponto_da_travessia_reconstroi_caminho_absoluto | Auditoria: nenhum ponto da travessia reconstroi caminho absoluto (a descida usa `cd -P`) | RNF-28 |
| teste_registro_da_travessia_traz_a_identidade_forte | O registro da travessia traz a identidade forte do arquivo | |
| teste_identidade_publicada_coincide_com_a_da_travessia | A identidade publicada coincide com a calculada na travessia | |


