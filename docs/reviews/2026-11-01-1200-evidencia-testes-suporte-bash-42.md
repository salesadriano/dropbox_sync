# Parecer de Evidencias de Testes: suporte-bash-42, PARTE A (linha principal)

## Identificacao

- Projeto ou produto: dropbox_sync (`dbx`)
- Agent responsavel pela alteracao: Senior Developer
- Agent responsavel pela verificacao: Senior Developer (gate local; validacao independente e do QA Expert)
- Data da verificacao: 2026-11-01
- Ciclo de verificacao: 1
- Tipo de alteracao: Implementacao nova
- Execucao dos gates: local, sem pipeline (a suite completa roda antes do envio da PR para `master` e na pipeline, Regra 8)
- Porte da demanda: G
- Modo do parecer: Completo (secoes sem conteudo marcadas `Nao aplicavel`)

## Escopo verificado

- Levantamento: `git status --short` e `git diff` no worktree `feature/suporte-bash-42` sobre `origin/develop` @ ace646d.

| Arquivo | Tipo | Modulo | Coberto por teste |
|---|---|---|---|
| install.sh | Alterado | `install.sh` | Sim (`instalador_linha_test`) |
| lib/preflight.sh | Alterado | `lib/preflight.sh` | Sim (`preflight_test`) |
| commands/diagnostico.sh | Alterado | `commands/diagnostico.sh` | Parcial: texto do remedio por auditoria (`preflight_test`); o ramo so executa em bash < 4.4 |
| scripts/empacotar.sh | Alterado | `scripts/` | Sim (`instalador_linha_test`, `gh` falso) |
| scripts/suite-bash42.sh | Novo | `scripts/` | Sim (docker ausente e docker falso) |
| README.md | Alterado | documentacao | Nao aplicavel |
| tests/unit/instalador_linha_test.sh | Novo | teste | n/a |
| tests/unit/preflight_test.sh | Alterado (2 casos novos, nenhum removido) | teste | n/a |
| docs/testes/inventario-de-testes.md | Alterado | documentacao | `inventario-de-testes.sh --check` |

- Nao verificado: o ramo de bash < 4.4 de `commands/diagnostico.sh` em execucao real (`BASH_VERSINFO` e somente leitura); a prova no 4.2 real da suite e o RF-206 na legada (parte B). Fora desta parte: auditoria estatica de recursos proibidos (RF-200).

## Criterios e seams acordadas

Seams: funcoes de `install.sh` carregadas por `.` (`DBX_INSTALL_SO_FUNCOES=1`); download isolado em `baixar_fonte` (apontada por `FUNCAO_BAIXAR`); `scripts/empacotar.sh` e `scripts/suite-bash42.sh` por execucao com duplos de `gh` e `docker`. Origem: System Design, secao "Desenho / A".

| # | Criterio | Camada | Coberto |
|---|---|---|---|
| 1 | RF-201a escolha 3.2, 4.1 (recusa), 4.2, 4.3 (legada), 4.4, 5.2 (principal); TC-B42-09/10/11 | Unitario | Sim |
| 2 | RF-201b/d piso lido da fonte, sem uname/OSTYPE; TC-B42-12 | Unitario | Sim |
| 3 | RF-202a/b/d fonte local incompativel cai no remoto, sem rede falha com comando manual, compativel nao baixa; TC-B42-13/14/16 | Unitario | Sim |
| 4 | RF-202c, DIV-385 A: `--canal` incompativel recusado antes de escrever; TC-B42-15 | Unitario | Sim |
| 5 | RF-203a/c, DIV-389: aviso destacado de troca; TC-B42-17/19 (TC-B42-18, credencial intacta, nao e testado: o instalador nunca toca `~/.config/dbx`) | Unitario | Parcial |
| 6 | RF-204 mensagem de reinstalacao; TC-B42-20 | Unitario | Sim (texto) |
| 7 | RF-205 `--target` e `--latest=false`; TC-B42-22 | Unitario | Sim |
| 8 | RF-206a/c script do CentOS 7 com digest | Unitario | Sim |

- Seam descartada: executar `install.sh` real com `--prefix` completo em teste (exige rede); o fluxo real foi provado no container (abaixo).

## Evidencia do ciclo red-green-refactor

| # | Fatia | Red observado | Implementacao minima |
|---|---|---|---|
| 1 | Seam e escolha de linha (13 casos) | `install.sh` sem seam: "Opcao nao reconhecida: <raiz>", depois status 0 em lugar de 1 no caso do bash 4.1 | `escolher_linha`, `piso_da_fonte`, `baixar_fonte`, `avisar_troca_de_linha`, `DBX_INSTALL_SO_FUNCOES` |
| 2 | Mensagem de reinstalacao (2 casos) | `dbx_preflight_mensagem_bash_antigo: command not found` | funcao em `lib/preflight.sh`; `diagnostico` a usa |
| 3 | Release (2 casos) | "a tag nasce no HEAD, nao no ramo padrao": argumentos de `gh release create` sem `--target` | `--target "$(git rev-parse HEAD)"` e `--latest=false` por sufixo |
| 4 | suite-bash42 (2 casos) | **Red nao observado isoladamente**: teste e script escritos no mesmo passo (o script nao existia antes) | `scripts/suite-bash42.sh` |

- Refactors sem mudanca de comportamento: a mensagem do preflight passou de `$(funcao)` a variavel global (auditoria `nenhuma_captura_pode_carregar_byte_externo`, `json_test`); o duplo de download virou um so (auditoria `nenhum_arquivo_de_teste_redefine_uma_funcao_propria`, `harness_test`).

## Execucao seletiva por modulo, local (Regra 8)

- Mapa: `docs/testes/mapa-modulos.md`; separacao automatica (modulo = arquivo). Arquivos sem enquadramento: nenhum. Suite completa durante a demanda: Nao.
- Atingidos: `install.sh`, `lib/preflight.sh`, `commands/diagnostico.sh`. Dependentes pelo mapa: `cli`, `composicao`, `tmp_test` (diff em `commands/`), auditores de `install.sh` e README (`qa_cache_unico`, `qa_docs_aliases`, `qa_consulta`), mais `json` e `harness` (auditorias estaticas).

| Filtro `bash tests/run.sh` | Motivo | Total | Aprovados | Falhos |
|---|---|---|---|---|
| instalador_linha | teste novo | 17 | 17 | 0 |
| instalador (inclui `instalador_diagnostico_freebsd`) | direto | 24 | 24 | 0 |
| preflight | direto | 37 | 37 | 0 |
| diagnostico | direto | 47 | 47 | 0 |
| qa_consulta | executa install.sh | 21 | 21 | 0 |
| qa_docs_aliases | audita install.sh e README | 16 | 16 | 0 |
| qa_cache_unico | audita install.sh e README | 33 | 33 | 0 |
| cli_test (cli, composicao, tmp) | diff em `commands/` | 33 | 33 | 0 |
| json | auditoria estatica | 62 | 62 | 0 |
| harness | auditoria estatica | 23 | 23 | 0 |

Outros gates: `sh scripts/lint.sh scripts/empacotar.sh scripts/suite-bash42.sh lib/preflight.sh commands/diagnostico.sh` saida 0 (a execucao sem argumentos terminou com codigo 0, com um aviso `info` preexistente em `lib/cmd.sh:1600`); `shellcheck -x` em `install.sh` e nos dois testes: 0 achados; `sh scripts/inventario-de-testes.sh --check`: `arquivos: 112 | casos: 2852 | divergencias: 0`; `scripts/verificar-remocao-de-casos.sh`: 2833 -> 2835, nenhuma reducao.

## Suite completa antes do envio da PR e na pipeline

Ainda nao houve envio para a PR; nao executada nesta etapa. Pipeline: nao executada.

## Execucao por camada

- Comando oficial: `bash tests/run.sh` (suite completa por `sh scripts/suite-completa.sh -- bash tests/run.sh`). Prova em bash 4.2: `sh scripts/suite-bash42.sh`.
- Parada no primeiro erro: conferida; o runner interrompeu e propagou o codigo em duas falhas reais, ambas corrigidas (`json_test`, `harness_test`).
- Banco real e E2E: Nao aplicavel: projeto CLI em bash, sem banco nem frontend.

| Camada | Total | Aprovados | Falhos | Nao executados |
|---|---|---|---|---|
| Unitario (instalador_linha 17, preflight 37, json 62, harness 23) | 139 | 139 | 0 | 0 |
| Integracao (diagnostico 47, qa_consulta 21, qa_docs_aliases 16, qa_cache_unico 33, cli_test 33) | 150 | 150 | 0 | 0 |

Distribuicao: sem E2E nem banco por natureza do projeto (CLI sem frontend); justificativa registrada.

### Prova em bash 4.2 real (CentOS 7, imagem `centos:7`)

- `sh scripts/suite-bash42.sh preflight`: REPROVADA, esperado na principal. Primeiro erro: `ambiente_saudavel_e_aprovado` (status 3 em vez de 0: o preflight da principal recusa o bash 4.2); 36 casos nao executados; 0,8 s.
- `docker run --rm -v <worktree>:/src:ro -w /src centos:7 bash install.sh --prefix /tmp/x`: `Linha legada (canal support/bash-4.2): bash 4.2 detectado.`, `[ok] Pre-requisitos validados`, `A fonte local exige bash 4.4 e o host tem 4.2; obtendo a linha legada`, tentou o remoto por cURL (sem `git` na imagem) e falhou com `curl: (22) ... 404 Not Found`, porque o ramo `support/bash-4.2` ainda nao existe; saiu com erro e a mensagem `Nada foi instalado. Comando manual: curl -fsSL https://raw.githubusercontent.com/salesadriano/dropbox_sync/support/bash-4.2/install.sh | bash -s -- --canal support/bash-4.2`. O `install.sh` executou inteiro no bash 4.2.46.

## Testes de seguranca e acesso

Gatilho tocado: download e escrita de arquivo (o instalador baixa fonte de URL derivada de `--canal`). Cenarios negativos cobertos: `--canal` incompativel recusado sem escrever no destino; fonte invalida (sem piso) recusada; sem rede, sem instalacao parcial. Nao coberto por teste: `--canal` com metacaracteres (a variavel vai entre aspas a `git clone --branch` e a URL, sem `eval`); sugerido ao QA.

## Validacao de formularios em E2E

Nao aplicavel: sem interface com entrada de dados.

## Achados

- Menor: red do caso `suite_bash42` nao observado isoladamente (acima).
- Menor: TC-B42-18 (credencial e estado intactos) so por inspecao: o instalador nao escreve fora de `DIR_BIN`, `DIR_SHARE` e `DIR_COMPLETAR`.
- DIV-390: nenhuma comparacao numerica de versao: `DBX_CLI_VERSAO` so e impressa (`bin/dbx:197`) e comparada como string (`empacotar.sh`, `dbx $VERSAO`); o instalador detecta a linha pelo sufixo `-bash42` por `sed` sobre o texto. Sem quebra.
- Corrigido pelo Tech Lead (verificacao do hand-back): no bash 4.2 o `bin/dbx` da principal morria em `lib/output.sh:207` (`local -n`) antes do preflight, e a mensagem do RF-204 nunca chegava. `bin/dbx` passa a carregar `lib/preflight.sh` e conferir o piso antes de qualquer outra biblioteca; caso novo `preflight_test::ponto_de_entrada_recusa_bash_antigo_antes_de_carregar_as_bibliotecas` (red sem a correcao, green com ela: 38/38). Prova no CentOS 7: `bash bin/dbx list /` -> `dbx: bash 4.2 abaixo do piso 4.4; reinstale pelo instalador, que escolhe a linha adequada: curl -fsSL https://raw.githubusercontent.com/salesadriano/dropbox_sync/master/install.sh | bash`, saida 3.
- Corrigido pelo Tech Lead: `scripts/suite-bash42.sh` rodava o conteiner como root, o que invalida os testes de permissao (0600, leitura negada); passa a `--user <uid>:<gid> -e HOME=/tmp`; caso `suite_bash42_monta_o_comando...` ajustado (17/17).
- Residuo da `develop` corrigido: `sh scripts/lint.sh` acusava SC2153 em `lib/cmd.sh` (`DBX_CLI_PARALELO`, `DBX_CLI_BLOCO`, definidas em `lib/cli.sh`); diretiva com o motivo em `dbx_cmd_paralelo` e `dbx_cmd_bloco`. Com isso o lint fica limpo com `LINT_MEMORIA_MB=15360`; com o teto padrao de 12288 MB o `commands/download.sh` e interrompido porque o `shellcheck` dele mede 13,2 GB de pico (`/usr/bin/time -v`, saida 0 sem achado): teto do ambiente, nao achado; acompanhamento fora desta demanda.

## Veredito

Aprovado com ressalvas (achados menores; suite completa local antes da PR e validacao independente do QA pendentes).
