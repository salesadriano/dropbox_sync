# Parecer de Conformidade Arquitetural e de Boas Praticas — Fase 9, desempenho (F-09, F-08, F-34)

## Identificacao

- Projeto ou produto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Agent responsavel pela alteracao: Senior Developer (F-09, F-08, bancada) com ajustes do Tech Lead e do QA nos duplos
- Agent responsavel pela verificacao: Senior Developer (revisao, sem alterar codigo nem testes)
- Data da verificacao: 2026-10-22
- Ciclo de verificacao: 1
- Tipo de alteracao: Implementacao nova
- Execucao: local, sem pipeline
- Porte da demanda: G
- Modo do parecer: Completo
- Log de prompt: [2026-10-21_2300_backlog-fase-9-desempenho.md](../prompts/2026-10-21_2300_backlog-fase-9-desempenho.md)

## Escopo verificado

- Comando usado para levantar o diff: `git status --short`, `git diff --stat`, `git diff <arquivo>` e leitura integral dos arquivos novos, em `/home/sales/dropbox_api.worktrees/feature-desempenho-b9` (nada commitado)
- Base de comparacao: `develop` @ `334394e`

| Arquivo | Tipo | Camada / modulo | Verificado |
|---|---|---|---|
| `lib/lote.sh` (392 linhas) | Novo | adaptador (`delete_batch`, `finish_batch_v2`) | Sim, integral |
| `lib/transfer.sh` | Alterado (+112) | adaptador (conferencia de resumo, `start` de pequeno) | Sim |
| `lib/cli.sh` | Alterado (+28) | validacao de opcao (`dbx_cli_validar_paralelo`) | Sim |
| `lib/http.sh` | Alterado (+7) | adaptador HTTP (contador de 429) | Sim |
| `commands/sync.sh` | Alterado (+558/-28) | comando (orquestracao) | Sim |
| `commands/upload.sh` | Alterado (+4) | comando | Sim |
| `commands/diagnostico.sh` | Alterado (+11) | comando | Sim |
| `bin/dbx`, `completions/dbx.bash` | Alterado | ponto de entrada, ajuda, completion | Sim |
| `scripts/bancada.sh` (256 linhas) | Novo | ferramenta de medicao | Sim (cabecalho, shim, redacao, encerramento) |
| `commands/reter.sh` | Sem diferenca com `develop` (`git diff --quiet develop` sai 0) | comando | Sim (DIV-269 confirmada) |
| `tests/**`, `scripts/tests/bancada.bats`, `docs/**` | Alterado/Novo | testes e documentacao | Fora do escopo deste gate (ver parecer de TDD); docs nao avaliadas |

- Arquivos alterados e nao verificados: nenhum de codigo de producao. Limitacao: de `commands/sync.sh` li o diff; o corpo do planejamento (guardas de origem vazia e `--confirmar`) nao mudou e foi conferido so pela ordem de chamada.

## Stack detectada e skills aplicadas

- Stack detectada: Shell (Bash 4.4+) com `shellcheck` e `bats`
- Evidencia da deteccao: extensao `.sh` predominante, `bin/dbx` com `#!/usr/bin/env bash`, `scripts/lint.sh`, `tests/run.sh`

| Skill aplicada | Motivo da selecao | Regras consultadas |
|---|---|---|
| `clean-architecture` | obrigatoria em qualquer stack | `dep-inward-only`, `dep-interface-ownership`, `usecase-orchestrates-not-implements`, `adapt-gateway-abstraction`, `usecase-explicit-dependencies` |
| `security-best-practices` | o diff toca exclusao remota, segredos em log da bancada e processos filhos | segredo em log, validacao de entrada, falha segura |

- Skills consideradas e descartadas: `api-security-best-practices` (o projeto consome a API Dropbox, nao expoe endpoint).

## Verificacao arquitetural

Camadas do projeto: `bin/dbx` e `commands/*.sh` (orquestracao/casos de uso) sobre `lib/*.sh` (adaptadores e regras puras). Nao ha dominio com entidades.

| Verificacao | Regra | Resultado | Evidencia |
|---|---|---|---|
| Direcao de dependencia | `dep-inward-only` | Conforme | `lib/lote.sh` nao referencia `commands/`; usa `lib/auth`, `lib/http`, `lib/json` e a global `DBX_CLI_SIMULACAO` (precedente em `lib/transfer.sh`). `commands/sync.sh` carrega `lib/lote.sh` (l. 130) |
| Propriedade da interface | `dep-interface-ownership` | Conforme | Canais publicos `DBX_LOTE_*` declarados por quem implementa e lidos por `commands/sync`; mesmo padrao de `DBX_TRANSFER_*` |
| Pureza de dominio | `frame-domain-purity` | Nao aplicavel | Sem dominio |
| Dados na fronteira | `dep-data-crossing-boundaries` | Conforme | Vetores paralelos de texto e inteiros; resultado dos auxiliares por arquivo de 4 ou 6 linhas validado por regex (`^[0-9]{1,9}$`, `^[0-9]{1,18}$`) |
| Ciclos | `dep-acyclic-dependencies` | Conforme | `lote -> auth/http/json`; `transfer` nao carrega `lote`; guarda `DBX_LOTE_CARREGADO` |
| Modelo rico / invariantes / persistencia na entidade | `entity-*` | Nao aplicavel | Sem entidades |
| Caso de uso orquestra | `usecase-orchestrates-not-implements` | Conforme | `sync` monta a lista e chama `dbx_lote_excluir` / `dbx_lote_concluir_envio`; fatia, recuo e conferencia por posicao ficam em `lib/lote.sh` |
| Sem apresentacao no caso de uso | `usecase-no-presentation-logic` | Conforme | Linha `falha <caminho>` sai por ponto unico (`_dbx_cmd_sync_falha_emitir`, l. 107), igual a N=1 |
| Dependencias explicitas | `usecase-explicit-dependencies` | Conforme com ressalva | Entrada de `lib/lote.sh` por globais publicas (padrao do projeto); `sync.sh` usa escopo dinamico (achado 2) |
| Fronteira transacional | `usecase-transaction-boundary` | Conforme | Sem estado entre execucoes (DIV-263); cache gravado so no principal, no fim (`dbx_state_gravar`, l. 1343) |
| Controller fino | `adapt-controller-thin` | Conforme | `bin/dbx` so ganhou ajuda e `--paralelo` no despacho |
| Sistema externo isolado | `adapt-gateway-abstraction` | Conforme | Rotas de lote so em `lib/lote.sh`; `delete_v2` saiu de `commands/sync.sh` |
| Coesao | `comp-common-closure` | Conforme | Lote de exclusao e de envio no mesmo adaptador; paralelismo no comando que o usa |

## Verificacao da skill de stack (Bash)

| Regra verificada | Origem | Resultado | Evidencia |
|---|---|---|---|
| So o processo principal grava estado (RF-135(a)) | RF-135 | Conforme | `_dbx_cmd_sync_aux_item` (l. 251) e `_dbx_cmd_sync_aux_iniciar` so escrevem `"$resultado.parte"` e fazem `mv`; `_dbx_cmd_sync_enviar`/`_receber` (l. 1445, 1459) nao chamam `dbx_state_*`; `dbx_state_cursor_remover` (l. 601) e `dbx_state_gravar` (l. 1343) ficam no principal; falha do plano incremental e tratada no descarregamento. Achado 3: a auditoria de teste nao cobre `aux_iniciar` e nao e transitiva |
| Guardas destrutivas antes do lote, sem estado | memoria `guarda-de-seguranca-sem-estado`, RF-80(d), RF-136(a) | Conforme | `_dbx_cmd_sync_protegido` (l. 1418) le so filtros da linha de comando; aplicada ao plano (l. 1008, `_dbx_cmd_sync_sem_protegidos`) e de novo item a item na montagem do lote (l. 1491); confirmacao, origem vazia e `--confirmar` ocorrem antes do plano (auditoria de ordem `confirma < plano < apaga_remoto/apaga_local`, `cursor_test.sh:1302`); `lib/lote.sh` declara que nao decide guarda (l. 14-17) |
| Lote confere por posicao; nao confirmado e falha | RF-136(c) | Conforme | `_dbx_lote_conferir`: so `success` vira `ok`; `n > total` falha a fatia; ausente ou tag desconhecida vira `falhou`; `in_progress` alem de 120 s falha sem repetir a exclusao |
| Nenhum `delete_v2` em laco no `--espelhar` | RF-136, DIV-269 | Conforme | `commands/sync.sh` so cita `delete_v2` em comentarios (l. 1303, 1480); `--enviar --espelhar` usa `_dbx_cmd_sync_apagar_remoto_em_lote` (l. 1306); `--receber --espelhar` segue `rm` local por item |
| `reter` fora do lote | DIV-269 | Conforme | `commands/reter.sh` identico a `develop`; mantem `delete_v2` por item (l. 10, 34, 531) |
| Simulacao nao escreve | RF-15, RF-134(e) | Conforme | `paralelo=1` em simulacao; `dbx_lote_excluir` retorna antes de qualquer fatia (`lib/lote.sh:284`); `_dbx_cmd_sync_lote_envio` e `dbx_transfer_iniciar_pequeno` recusam em simulacao |
| Escrita sem retentativa cega | RF-59 | Conforme | `dbx_auth_requisitar POST ... nao` no `delete_batch` e no `finish_batch_v2`; so o `check` (leitura) usa `sim` |
| Encerramento dos auxiliares por sinal | RF-134(c), `lib/tmp` | Conforme | `dbx_tmp_acao_registrar _dbx_cmd_sync_aux_encerrar` (TERM no grupo, espera 5 s, KILL), cancelada ao fim; `lib/tmp` e dono-por-`BASHPID`, entao o subshell nao roda as limpezas do pai |
| Quoting e expansao | bash | Conforme | Idioma `${v[@]+"${v[@]}"}` mantido; `printf %q` para byte de controle (`lib/cli.sh` ~l. 217) |
| Portabilidade Bash 4.4+ | bash | Conforme | Usa `wait -n` (4.3), `declare -gA/-ga`, `${!arr[@]}`; sem `mapfile -d`, `${var@Q}` ou `wait -p`; `sleep 0.05/0.1` aceito por GNU e BSD |
| Validacao de entrada nova | RF-133(b) | Conforme | `dbx_cli_validar_paralelo`: `^[1-8]$` ancorado (recusa `01`, vazio, sinal, espaco); valor exibido truncado a 64; validado antes de rede e estado |

## Verificacao de seguranca acionada

- O diff toca autenticacao, autorizacao, segredos, dados sensiveis, sessao/cookies, CSP/CORS ou exposicao de API?: Sim (exclusao remota destrutiva; segredos nos logs da bancada; processos filhos com acesso ao token)
- Skills aplicadas: `security-best-practices`

| Item | Resultado | Evidencia |
|---|---|---|
| Ausencia de segredo no diff | Conforme | Nenhum token, chave ou credencial literal; fixtures usam `ak/as/rt` sinteticos |
| Escrita de segredo em log (RNF-03) | Conforme com ressalva | Saida dos auxiliares vai a `/dev/null`; resumo da falha passa por `dbx_errors_redigir` e por `_dbx_cmd_sync_falha_emitir` (mascara por valor); `_dbx_lote_resumo_http` usa so o prefixo de tag do `error_summary` (corpo bruto nunca entra). Logs da bancada: redacao por `sed` (`bancada.sh:210-214`), lista de bloqueio. Achados 4 e 7 |
| Validacao de entrada nas novas fronteiras | Conforme | `--paralelo`/`DBX_PARALELO` ancorado; `--remoto` da bancada contra `^/dbx-bancada-[a-z0-9-]+$` antes de rede e antes de apagar; `parent_rev`, caminhos e `session_id` passam por `dbx_json_escapar_cadeia`; deslocamento validado por regex antes de entrar no JSON do `finish_batch_v2` |
| Autorizacao verificada nos novos acessos | Conforme | Mesma credencial e mesmo `dbx_auth_requisitar`; `bancada.sh medir` exige `--confirmo-conta-real` e o marcador `.bancada-marcador` para apagar |
| Isolamento por tenant | Nao aplicavel | CLI de usuario unico por perfil |

## Consistencia com o projeto

| Item | Resultado | Observacoes |
|---|---|---|
| Segue padrao ja adotado em modulos equivalentes | Sim | Espera substituivel (`_dbx_lote_dormir`), marcas `# MUTACAO:` como em `reter.sh`, `readonly` + guarda de carga como as demais libs |
| Nao reimplementa componente existente | Sim | Conferencia de resumo extraida para `dbx_transfer_conferir_resumo` e reusada pelo envio unitario e pelo lote (DIV-278) |
| Coerente com System Design / ARD | Sim | `system-design.md` atualizado na mesma demanda; limiar 1 MiB, fatia 250, recuo 1-10 s e teto 120 s conforme DIV-256/259/262 |
| Coerente com decisoes nas memorias do pacote | Sim | `guarda-de-seguranca-sem-estado` honrada; DIV-269 em `2026-10-21-2300-desempenho.md` |
| Vocabulario de dominio preservado | Sim | `espelhar`, `enviar`, `receber`, `falha <caminho>: <classe>` |

## Ferramentas locais executadas

| Ferramenta | Comando | Resultado | Disponivel no projeto |
|---|---|---|---|
| Linter | `sh scripts/lint.sh` | Nao reexecutado por mim; QA e Tech Lead registram exit 0 nos arquivos tocados | Sim |
| Type checker | n/a | n/a | Nao |
| Analise de ciclos | leitura de `source` | Sem ciclo | Nao (manual) |
| Reproducao seletiva | `bash tests/run.sh paralelo < /dev/null` | 14 aprovados, 0 reprovados, 0 pulados | Sim |

- Limitacoes: suite completa a cargo do Tech Lead; `docs/**` nao avaliada; modo de arquivo dos logs da bancada nao verificado.

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correcao esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 | `commands/sync.sh:1008` e `:1491` | `_dbx_cmd_sync_protegido` esta aplicada em dois pontos (plano e montagem do lote). Correto e desejavel (defesa em profundidade), mas nenhum teste de caixa-preta mata a mutacao do segundo ponto, porque o primeiro ja filtra (ver parecer de TDD) | memoria `guarda-de-seguranca-sem-estado` (prova da guarda) | Teste direto da funcao e do ponto do lote com `DBX_SYNC_APAGAR` injetado, ou mutar os dois pontos juntos | Menor | Aberto |
| 2 | `commands/sync.sh:251-300`, `:415`, `:560-700` | Paralelismo e lote leem e escrevem ~12 variaveis `local` de `dbx_cmd_sync_executar` por escopo dinamico (`raiz_local`, `remoto`, `area`, `mapa_*`, `op_atual`, `enviados`, `falhas`). Documentado nos cabecalhos, mas acopla funcoes a nomes do chamador | `usecase-explicit-dependencies` | Aceitar se ja era padrao do arquivo (`op_atual`, `apagados` ja eram); ou agrupar em registro | Menor | Aberto |
| 3 | `tests/integracao/paralelo_test.sh:342-360` | A auditoria estatica de RF-135(a) cobre `aux_item`, `enviar` e `receber`, nao `_dbx_cmd_sync_aux_iniciar` (segundo lancamento em segundo plano, `sync.sh` ~l. 430); o "unico ponto de lancamento" conta so `aux_item "$pasta`. A busca por `dbx_state_` nao e transitiva (o que protege `lib/transfer` e `DBX_TRANSFER_RETOMADA_ATIVA='nao'` em execucao). O codigo esta conforme; falta prova | RF-135(a) | Incluir `aux_iniciar` na lista e contar os dois pontos de lancamento | Menor aqui (Maior no parecer de TDD) | Aberto |
| 4 | `lib/lote.sh:263` e montagem de motivo em `_dbx_lote_conferir` (~l. 175-190) | O motivo da falha embute `.tag` e `failure.*` lidos da resposta sem restringir ao alfabeto de tag, ao contrario de `_dbx_lote_resumo_http` (l. 75). Em `sync` o texto passa por `dbx_errors_redigir` e e cortado a 120 caracteres; resta byte de controle de servidor no terminal | RF-59(c), defesa em profundidade | Reaproveitar o filtro `marca%%[!a-z_/]*` nas tags citadas | Menor | Aberto |
| 5 | `lib/lote.sh:333` vs `:75` | Dois caminhos para o resumo seguro na mesma lib: exclusao usa `DBX_HTTP_RESUMO_DO_SERVICO` filtrado; envio usa `DBX_HTTP_RESUMO_DE_ERRO` | consistencia interna | Usar `_dbx_lote_resumo_http` nos dois ou comentar por que `RESUMO_DE_ERRO` ja e seguro | Menor | Aberto |
| 6 | `commands/sync.sh:309`, `:386`, `:445`, `:463` | `set -m` / `set +m` incondicionais; se o chamador ja tivesse monitor ligado, o `set +m` o desligaria. Hoje inofensivo (script nao interativo) | boas praticas Bash | Guardar `$-` e restaurar | Menor | Aberto |
| 7 | `scripts/bancada.sh:210-214` | Redacao dos logs por lista de formatos; o `dbx` nao emite credencial, entao e defesa em profundidade (QA-B9-01 ja ampliou a mascara) | RNF-03 | Aceitar; manter `qdb14`/`qdb15` | Menor | Justificado pelo QA |

- Total de bloqueantes: 0
- Total de maiores: 0
- Total de menores: 7

## Achados do ciclo anterior

Nao aplicavel: ciclo 1.

## Veredito

- Resultado: **Aprovado com ressalvas**
- Justificativa objetiva: sem violacao de direcao de dependencia, fronteira lib x commands, regra de estado do auxiliar, guarda destrutiva, segredo em log ou contrato; `delete_v2` ausente do `--espelhar` e `commands/reter.sh` identico a `develop`. Os achados sao de manutenibilidade e de lacuna de prova, todos Menor.
- Ressalvas registradas, com owner e prazo: achados 1 e 3 (provas), owner Senior Developer, antes do push que abre a PR; achados 2, 4, 5 e 6 sao recomendacoes sem prazo.
- Handoff liberado?: Sim
- Proximo passo do ciclo do developer: tratar 1 e 3 junto com as ressalvas do parecer de TDD; o QA ja validou (`docs/reviews/2026-10-21-2300-validacao-qa-desempenho-b9.md`).

## Devolucao ao agent (preencher apenas se Reprovado)

Nao aplicavel: aprovado com ressalvas.

## Registro

- Nenhuma justificativa aceita exige memoria nova; as decisoes duraveis ja estao em `.github/agents/memoria/entradas/2026-10-21-2300-desempenho.md`.
- Referenciar este parecer no registro de entrega da fase 9.
