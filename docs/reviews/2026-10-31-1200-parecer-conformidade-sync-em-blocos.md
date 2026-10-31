# Parecer de Conformidade Arquitetural e de Boas Praticas - sync-em-blocos

## Identificacao

- Projeto ou produto: dropbox_api (CLI `dbx`, Bash)
- Agent responsavel pela alteracao: senior-developer
- Agent responsavel pela verificacao: senior-developer (gate local, `ai-team:protocolo-conformidade`)
- Data da verificacao: 2026-10-31
- Ciclo de verificacao: 1
- Tipo de alteracao: Implementacao nova (F-101, `--bloco`/`--batch`, ciclos por diretorio)
- Execucao: local, sem pipeline
- Porte da demanda: G
- Modo do parecer: Completo

## Escopo verificado

- Comando usado para levantar o diff: `git status --short`, `git diff origin/develop --stat`, `git diff origin/develop -U0 -- <arquivo>` e leitura dos arquivos novos nao rastreados. Log: `docs/prompts/2026-10-31_1200_sync-em-blocos.md`.
- Base de comparacao: `origin/develop`.

| Arquivo | Tipo | Camada / modulo | Verificado |
|---|---|---|---|
| commands/sync.sh | Alterado (+671/-123) | commands/ (orquestracao do caso de uso) | Sim, integral nas funcoes novas e nos trechos de exclusao, cursor e simulacao |
| lib/walk.sh | Alterado (+269) | lib/ (adaptador de sistema de arquivos) | Sim, integral nas funcoes novas |
| lib/sync.sh | Alterado (+117) | lib/ (dominio de plano e adaptador de listagem remota) | Sim, integral nas funcoes novas |
| lib/cli.sh, lib/cmd.sh | Alterado | lib/ (validacao de opcao) | Sim |
| bin/dbx, completions/dbx.bash | Alterado | bin/ (ajuda e completion) | Sim, por amostragem |
| commands/upload.sh, download.sh, diagnostico.sh | Alterado | commands/ | Parcial (so o `--bloco` e a ajuda) |
| tests/integracao/{bloco_cli,sync_blocos}_test.sh, tests/unit/sync_blocos_test.sh, cursor_test.sh, qa_cursor_b7b_test.sh | Novo / Alterado | tests/ | Nao (gate de testes e do `protocolo-tdd`) |
| docs/** | Novo / Alterado | documentacao | Nao (fora do escopo deste gate) |
| README.md | Alterado | documentacao | Nao |

- Arquivos alterados e nao verificados, com motivo: testes e docs acima (escopo de outro gate); `upload.sh` e `download.sh` so no trecho do `--bloco`.

## Stack detectada e skills aplicadas

- Stack detectada: Bash (`#!/usr/bin/env bash`, `shopt`, arrays associativos, namerefs) com testes em shell.
- Evidencia da deteccao: extensao `.sh` predominante, `bin/dbx`, `lib/`, `commands/`, `tests/`.

| Skill aplicada | Motivo da selecao | Regras consultadas |
|---|---|---|
| `clean-architecture` | obrigatoria | `dep-inward-only`, `usecase-orchestrates-not-implements`, `adapt-controller-thin`, `adapt-gateway-abstraction`, `comp-common-closure` |
| `ai-team:shellcheck-configuration` (criterios) | codigo Bash | citacao de variaveis, `read -d ''`, diretivas `disable` justificadas |
| `security-best-practices` | diff toca exclusao de dados, nomes de arquivo e entrada de usuario (`DBX_BLOCO`) | validacao de entrada, ausencia de segredo |

- Skills consideradas e descartadas: `supabase-postgres-best-practices` (sem SQL); `api-security-best-practices` (sem endpoint exposto; a unica chamada nova e `get_latest_cursor`, consumida pelo cliente).

## Verificacao arquitetural

| Verificacao | Regra | Resultado | Evidencia |
|---|---|---|---|
| Direcao de dependencia | `dep-inward-only` | Nao conforme (menor) | lib/walk.sh:334 le `DBX_CMD_MARCA_RECEBIMENTO`, variavel de `commands/`/`lib/cmd`. Padrao ja existe em lib/sync.sh:267 (preexistente). Achado 5 |
| Propriedade da interface | `dep-interface-ownership` | Conforme | planejador `dbx_sync_blocos_planejar` (lib/sync.sh:633) recebe vetores por nome e N, sem conhecer o chamador |
| Pureza de dominio | `frame-domain-purity` | Conforme | `dbx_sync_blocos_planejar` e pura (sem rede nem disco) |
| Dados na fronteira | `dep-data-crossing-boundaries` | Conforme | registros `\0` com campos separados por TAB; nomes com TAB/quebra tratados por posicao (`${reg%%$'\t'*}`, contagem sem TAB antes do caminho) |
| Ciclos de dependencia | `dep-acyclic-dependencies` | Conforme | `commands/sync` usa `lib/walk`, `lib/sync`, `lib/cmd`; lib nao carrega commands |
| Modelo rico / invariantes / persistencia | `entity-*` | Nao aplicavel | sem entidades; Bash |
| Caso de uso orquestra | `usecase-orchestrates-not-implements` | Nao conforme (maior) | `dbx_cmd_sync_executar` com 999 linhas implementa o laco de ciclos, a formacao de ciclo remoto e a paginacao. Achados 1 e 3 |
| Sem logica de apresentacao | `usecase-no-presentation-logic` | Conforme com ressalva | mensagens de progresso misturadas no laco; padrao preexistente |
| Dependencias explicitas | `usecase-explicit-dependencies` | Nao conforme (maior) | helpers recebem estado por escopo dinamico do executor (`pend_*`, `ci_ini`, `chaves_dirs`, `dirs_v`...), documentado em comentario mas implicito. Achado 1 |
| Fronteira transacional | `usecase-transaction-boundary` | Conforme | cursor e memoria gravados uma vez, ao fim, sob a trava (commands/sync.sh:1633-1660) |
| Controller fino | `adapt-controller-thin` | Nao conforme (maior) | ver achado 1 |
| Sistema externo isolado | `adapt-gateway-abstraction` | Conforme | listagem e `get_latest_cursor` em lib/sync.sh; a formacao de ciclo remoto em commands/ (achado 3) fica em cima desse gateway |
| Coesao | `comp-common-closure` | Nao conforme (maior) | a formacao do ciclo remoto (commands/sync.sh:2186) muda junto com `lib/sync.sh` e esta em outro arquivo. Achado 3 |

## Verificacao da skill de stack

| Regra verificada | Skill | Resultado | Evidencia |
|---|---|---|---|
| Citacao de variaveis | shellcheck-configuration | Conforme | `"$raiz_local"`, `"$dirs_arq"`, `--` antes de nomes em `cd -- "$nome"` (lib/walk.sh:344) |
| Nomes com TAB/quebra de linha | shellcheck-configuration / security | Conforme no dado, menor no relato | registros `\0` (lib/walk.sh `_dbx_walk_dirs`, `_dbx_walk_ciclo_dir`); motivos de parcialidade vao por linhas em `>&3` e nome com quebra de linha fragmenta so o texto do motivo, nao a marca `DBX_WALK_PARCIAL`. Achado 6 |
| Ligacao simbolica e confinamento | security | Conforme | `-L` testado antes de descer e marcado parcial; descida por componente com `cd --` (lib/walk.sh:429-445) |
| Confinamento remoto | security | Conforme | `_dbx_cmd_sync_ramos_destino_remotos` (2328) so desce em filho de diretorio do ciclo e usa `dbx_sync_relativo` para rejeitar caminho fora da raiz |
| Validacao de `--bloco`/`DBX_BLOCO` | security | Conforme | regex `^[1-9][0-9]{0,6}$` mais teto (lib/cli.sh); valor citado truncado e escapado; recusa com 2 antes da rede |
| Diretivas `disable` | shellcheck-configuration | Conforme | cada `SC2034`/`SC2190` traz justificativa |
| Codigo morto | best-practices | Nao conforme (menor) | `DBX_SYNC_DIR_PARCIAL` (lib/sync.sh:534) documentado como "lido pelo laco de ciclos" e nao e lido por commands/sync.sh. Achado 4 |
| Formatacao | best-practices | Nao conforme (menor) | corpo do `while` (commands/sync.sh:1087-1731) sem recuo. Achado 7 |

## Verificacao de seguranca acionada

- O diff toca autenticacao, autorizacao, segredos, dados sensiveis, sessao/cookies, CSP/CORS ou exposicao de API?: Nao diretamente; toca guarda de exclusao, nomes de arquivo e entrada de usuario (`--bloco`, `DBX_BLOCO`).
- Skills aplicadas: `security-best-practices` (criterios acima).

| Item | Resultado | Evidencia |
|---|---|---|
| Ausencia de segredo no diff | Conforme | leitura do diff; cursor validado por regex e teto de 8192 (lib/sync.sh `dbx_sync_cursor_ultimo`) |
| Validacao de entrada nas novas fronteiras | Conforme | `dbx_cli_validar_bloco`; `dbx_sync_blocos_planejar` revalida N e contagens |
| Autorizacao nos novos acessos | Nao aplicavel | sem novo acesso alem de `list_folder` e `get_latest_cursor` sob a mesma conta |
| Isolamento por tenant | Nao aplicavel | CLI de uma conta |

### Seguranca de exclusao (foco do exame)

| Regra | Resultado | Evidencia |
|---|---|---|
| RF-190(a)(b): so apaga em diretorio lido por inteiro nos dois lados | Conforme | origem e destino lidos por ciclo; falha de pagina em `dbx_sync_listar_diretorio` devolve codigo e o ciclo para (commands/sync.sh:1172-1187) antes do plano; ramo so do destino lido inteiro pelo ciclo que o encontra (2328) |
| RF-190(c) e RF-41(a): parcial desliga exclusao na execucao inteira | Conforme com a emenda | `parcial` e acumulado entre ciclos (1107-1109) e zera `DBX_SYNC_APAGAR` (1383-1402); ciclos anteriores ja concluidos mantem seus efeitos por desenho (RF-190(d), RF-193(b), DIV-380), nao e achado |
| RF-191: sonda de origem vazia antes de qualquer exclusao | Conforme | `vazia_global` fixada antes do ciclo 1 (enviar: 2168; receber: 2283); `extras_arquivos` conta como "algo a apagar" (1322); recusa sai apos o plano e antes de escrita (1385) |
| Sem decisao destrutiva por estado persistido | Conforme | `_dbx_cmd_sync_sem_protegidos` e `_dbx_cmd_sync_protegido` (1735-1752) refazem a conta so pelos padroes da linha de comando; "memoria descartada" e "conta nao identificada" so desligam exclusao (direcao segura); retrato e cursor nunca afirmam "observado por inteiro" |
| RF-114: candidata de exclusao do incremental confirmada no servidor | Conforme | laco de duas rodadas (1203-1245) com retorno a varredura completa |

### Cursor (RF-192)

| Condicao | Resultado | Evidencia |
|---|---|---|
| Nunca em dry-run | Conforme | `DBX_CMD_SYNC_CURSOR_GRAVA='nao'` na simulacao (729) e `return 0` antes da gravacao (1638-1645) |
| Nunca em falha ou parcial | Conforme | condicao `ciclo_falho -eq 0 && falhas -eq 0 && parcial != 'sim'` (1653) |
| Cursor pedido antes do ciclo 1 | Conforme | `_dbx_cmd_sync_retrato_iniciar` antes da enumeracao (1070); o que mudar durante a varredura chega no proximo delta |
| Tudo ou nada | Conforme | `_dbx_cmd_sync_retrato_restaurar` so devolve o acumulado quando ha cursor (`return 1` sem ele) |

## Consistencia com o projeto

| Item | Resultado | Observacoes |
|---|---|---|
| Segue padrao ja adotado em modulos equivalentes | Conforme | `dbx_cmd_bloco`/`dbx_cli_validar_bloco` espelham `dbx_cmd_paralelo`; resolvedor do sync segue o de `--paralelo` |
| Nao reimplementa componente existente | Nao conforme (maior) | filtro de poda replicado tres vezes em lib/walk.sh (108, 306, 455). Achado 2 |
| Coerente com System Design / ARD | Conforme | `docs/reviews/2026-10-31-1200-system-design-sync-em-blocos.md`; DIV-377 a DIV-384 respeitadas |
| Coerente com decisoes nas memorias do pacote | Conforme | `guarda-de-seguranca-sem-estado` |
| Vocabulario de dominio preservado | Conforme | ciclo, bloco, retrato, cursor, observado por inteiro |

## Ferramentas locais executadas

| Ferramenta | Comando | Resultado | Disponivel no projeto |
|---|---|---|---|
| Linter (shellcheck) | nao executado | n/a | Sim |
| Type checker | n/a | n/a | Nao |
| Analise de ciclos | leitura dos `source`/chamadas entre lib e commands | sem ciclo novo | Nao (manual) |

- Limitacoes por ausencia de ferramenta: por ordem do Tech Lead, nem testes nem lint foram executados neste gate (regressao em curso). Os achados vem de leitura. O resultado do shellcheck e do `shfmt` fica a cargo da regressao e deve ser conferido contra os achados 4 e 7 antes do handoff.

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correcao esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 | commands/sync.sh:733-1731 | `dbx_cmd_sync_executar` tem 999 linhas e agora contem o laco de ciclos, o reset de estado por ciclo e a parada por falha. Os auxiliares (`_dbx_cmd_sync_diretorios_enumerar` 2129, `_dbx_cmd_sync_ciclo_remoto_formar` 2186, `_dbx_cmd_sync_ciclo_proximo` 2308, `_dbx_cmd_sync_parada_sistemica` 2290, `_dbx_cmd_sync_ramos_destino_remotos` 2328) leem e escrevem ~25 variaveis do executor por escopo dinamico | `clean-architecture`: `usecase-orchestrates-not-implements`, `usecase-explicit-dependencies`, `adapt-controller-thin` | Extrair o corpo de UM ciclo para `_dbx_cmd_sync_ciclo_executar` (entrada: indices e modo; saida: contadores num mapa `DBX_CMD_SYNC_CICLO_*`) e levar o planejamento, a formacao de ciclo e a fila para `lib/sync.sh`/`lib/walk.sh` com estado em variaveis `DBX_SYNC_*` documentadas, em vez de variaveis locais do executor | Maior | Aberto |
| 2 | lib/walk.sh:108, 306, 455 | O bloco de poda por filtro (pasta excluida, simbolico/nao-regular fora de qualquer padrao) esta replicado em `dbx_walk_local`, `_dbx_walk_dirs` e `_dbx_walk_ciclo_dir`; qualquer ajuste de regra de filtro (RF-80) precisa de tres edicoes e dois lados da travessia podem divergir | `best-practices` (DRY), `comp-common-closure` | Extrair `_dbx_walk_podar_entrada <relativo> <nome>` (status 0 = podada, imprime no fd 4) e chama-la nos tres pontos | Maior | Aberto |
| 3 | commands/sync.sh:2186-2287 e 2328-2361 | A formacao do ciclo remoto (paginacao por diretorio, fila, diretorio pendente `pend_*`) e a descida de ramos so do destino vivem em `commands/`, acopladas ao formato da tabela (`for k in 1 2 3 4 5 6; exibido=${exibido#*$'\t'}` em 2345) e a `DBX_SYNC_TAB*`, que sao detalhes de `lib/sync.sh` | `adapt-gateway-abstraction`, `comp-common-closure` | Mover as duas funcoes para `lib/sync.sh` (`dbx_sync_ciclo_remoto_formar`, `dbx_sync_ramos_destino_listar`) com a leitura do campo de caminho por helper da propria tabela, e deixar em `commands/` so a chamada | Maior | Aberto |
| 4 | lib/sync.sh:534 (e 561, 597) | `DBX_SYNC_DIR_PARCIAL` e anunciado como "lido pelo laco de ciclos" e nenhum codigo em `commands/` o le; a parcialidade efetiva vem so do status de retorno | `best-practices` (codigo morto) | Remover a variavel e as tres atribuicoes, ou consumi-la no laco com teste; corrigir o comentario | Menor | Aberto |
| 5 | lib/walk.sh:334 | `lib/walk` le `DBX_CMD_MARCA_RECEBIMENTO`, variavel do lado de `commands/`; camada interna depende de nome externo (ja ocorre em lib/sync.sh:267, preexistente) | `dep-inward-only` | Receber a marca por parametro ou por `DBX_WALK_MARCA_RECEBIMENTO` definida pelo chamador; corrigir tambem lib/sync.sh:267 se couber nesta demanda | Menor | Aberto |
| 6 | lib/walk.sh (`>&3` em `_dbx_walk_dirs` e `_dbx_walk_ciclo_dir`) | Motivos de parcialidade saem por linha; nome com quebra de linha parte o texto do motivo em duas linhas (so relato, a marca `DBX_WALK_PARCIAL` e a desabilitacao da exclusao nao sao afetadas) | `shellcheck-configuration` (nomes com delimitador) | Emitir o motivo com `printf '%q'` do nome ou em registro `\0` | Menor | Aberto |
| 7 | commands/sync.sh:1087-1731 | Corpo do laco `while _dbx_cmd_sync_ciclo_proximo` sem recuo (continua no nivel do corpo antigo), com `done` em 1650; atrapalha a leitura e quebra `shfmt` | `best-practices` (formatacao) | Rodar `shfmt -i 2 -w commands/sync.sh` depois de decidir o achado 1 (o recuo vai desaparecer da leitura ao extrair o ciclo) | Menor | Aberto |

- Total de bloqueantes: 0
- Total de maiores: 3
- Total de menores: 4

Observacoes (sem severidade): `_dbx_cmd_sync_retrato_*` usa estado global do modulo (`declare -gA`), aceitavel para script de processo unico; a decisao de manter o laco de ciclos em `commands/sync.sh` neste incremento e coerente com o porte, mas a divida dos achados 1 a 3 cresce a cada fase se nao for paga.

## Achados do ciclo anterior

Nao aplicavel: ciclo 1.

## Veredito

- Resultado: Aprovado com ressalvas
- Justificativa objetiva: nenhum bloqueante; as guardas de exclusao (RF-190, RF-41(a), RF-191, RF-114), o cursor (RF-192) e a validacao de entrada foram lidas e estao conformes; tres maiores (dentro do limite de tres), todos de coesao e tamanho, sem quebra de dependencia nem de regra de seguranca.
- Ressalvas registradas, com owner e prazo: achados 1 a 3, owner senior-developer; prazo sugerido: achado 2 antes do handoff ao QA (correcao local e pequena, protegida pela regressao); achados 1 e 3 como refatoracao propria na proxima demanda da fase, decisao do Tech Lead sobre adiar com registro. Achados 4 a 7: recomendacao, mesmo ciclo.
- Handoff liberado?: Sim, condicionado a regressao verde do Tech Lead e ao aceite do Tech Lead sobre o adiamento dos achados 1 e 3.
- Proximo passo do ciclo do developer: Tech Lead decide o achado 2 (agora) e 1 e 3 (agora ou fase seguinte); reexecutar este gate sobre o diff corrigido.

## Devolucao ao agent (preencher apenas se Reprovado)

Nao aplicavel: veredito Aprovado com ressalvas.

## Registro

- Sem decisao duravel nova. Se o Tech Lead adiar os achados 1 e 3, gravar entrada em `docs/memoria/entradas/` (`escopo: projeto`) com `ref:` para este parecer (regra 35).
- Referenciar este parecer no registro de entrega (`ai-team:review-documentation`).

## Correcoes

Aplicadas pelo Senior Developer sobre os achados abaixo; veredito e demais achados inalterados.

| Achado | Correcao | Evidencia |
|---|---|---|
| 2 (maior) | Extraido `_dbx_walk_podar_entrada <relativo> <nome>` em lib/walk.sh (status 0 = podada, imprime no fd 4); os tres pontos (`dbx_walk_local`, `_dbx_walk_dirs`, `_dbx_walk_ciclo_dir`) chamam `_dbx_walk_podar_entrada "$relativo" "$nome" && continue`. Sem mudanca de comportamento. | `bash tests/run.sh filtro`: 92 aprovados, 0 reprovados; `sync_blocos`: 42/0; `sync_test`: 93/0. Cobertura: `dbx_walk_local` pelos testes de filtro (RF-80); `_dbx_walk_dirs` e `_dbx_walk_ciclo_dir` pelos de sync_blocos (travessia por ciclo). |
| 4 (menor) | Parcialidade da listagem de diretorio ja e coberta pelo status de retorno: `dbx_sync_listar_diretorio` devolve codigo != 0 em falha, pagina repetida ou teto de paginas (lib/sync.sh `_dbx_sync_listar_paginas`); commands/sync.sh:1174-1187 e 2216-2220 o convertem em `dbx_cmd_falhar` e interrompem o ciclo (nada planejado nem apagado). `DBX_SYNC_DIR_PARCIAL` removida (variavel, atribuicoes, comentarios e as 5 asserções unitarias da variavel; os asserts de status permanecem). | Unit: `teste_listar_diretorio_falha_remota_sinaliza_parcialidade`, `..._falha_na_segunda_pagina_e_parcial`, `..._cursor_repetido_e_erro_remoto_parcial` (status != 0). Integracao: `teste_blc_falha_de_arquivo_segue_e_falha_de_enumeracao_para` e `teste_blc_falha_no_ciclo_k_nao_grava`. |
