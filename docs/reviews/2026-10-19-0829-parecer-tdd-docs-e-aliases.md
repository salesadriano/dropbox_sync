# Parecer de Evidências de Testes (TDD) — Aliases, origem vazia pelo plano, localidade e documentação (fase 4)

## Identificação

- Projeto ou produto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Agent responsável pela alteração: Senior Developer (delegação do Tech Lead, regra 44); poda de comentários (item 4) por um fork do próprio Senior Developer
- Agent responsável pela verificação: Senior Developer (gate local, regra 14); validação independente a cargo do QA Expert
- Data da verificação: 2026-10-19
- Ciclo de verificação: 1
- Tipo de alteração: Implementação nova (RF-64, RF-54(f)(g)) + Correção (O-1/DIV-30) + Refatoração (comentários, O-6, SC2034) + Documentação com teste (RNF-34)
- Execução dos gates: local, sem pipeline (suíte completa roda no push para a PR e na pipeline, Regra 8)
- Porte da demanda: **G**
- Modo do parecer: Completo
- Branch / worktree: `feature/docs-e-aliases-p4` em `/home/sales/dropbox_api.worktrees/feature-docs-e-aliases-p4`, base `6b00bcd`
- Log de prompt: [2026-10-19_0829_docs-e-aliases-p4.md](../prompts/2026-10-19_0829_docs-e-aliases-p4.md)
- Memória transposta (por id, regra 43): `2026-10-19-0829-aliases-poda-e-comentarios`, `2026-10-18-1745-selecao-inclui-auditorias-lib`
- Critérios: [escopo-requisitos-e-criterios-de-aceite.md](../requisitos/escopo-requisitos-e-criterios-de-aceite.md) v1.6 — RF-64 (TC-ALI-01..03), RF-41(b)/O-1 (TC-DEL-13), RF-54(e)-(g) (TC-CX-04, TC-CX-05), RNF-34 (TC-DOC-01)
- Parecer de conformidade: [2026-10-19-0829-parecer-conformidade-docs-e-aliases.md](2026-10-19-0829-parecer-conformidade-docs-e-aliases.md)

## Escopo verificado

- Comando usado para levantar o diff: `git status --short`, `git diff --stat -- lib bin commands tests README.md`, `git diff`
- Base de comparação: `HEAD` = `6b00bcd` (sem commit da demanda)

| Arquivo | Tipo de alteração | Camada / módulo | Coberto por teste |
|---|---|---|---|
| `commands/sync.sh` | Alterado | `commands/sync` | Sim (`sync`, `qa_cache_unico`, `qa_robustez`, `cli`, `composicao`) |
| `commands/unlink.sh` | Alterado | `commands/unlink` | Sim (`comandos`) |
| `commands/config.sh` | Alterado | `commands/config` | Sim (`comandos`, `preflight`) |
| `bin/dbx` | Alterado (ajuda) | `bin/dbx` | Sim (`sync`, `comandos`) |
| `lib/sync.sh` | Alterado | `lib/sync` | Sim (`sync`; auditorias `json`, `http`, `preflight`, `composicao`) |
| `lib/preflight.sh` | Alterado | `lib/preflight` | Sim (`preflight`) |
| `lib/output.sh` | Alterado (comentário) | `lib/output` | Sim (`composicao` TC-DOC-01, `output`) |
| `lib/http.sh` | Alterado (só comentários) | `lib/http` | Sim (suíte inteira; `composicao` TC-DOC-01) |
| `lib/transfer.sh` | Alterado (só comentários) | `lib/transfer` | Sim (suíte inteira) |
| `README.md` | Alterado | documentação | Sim (`preflight`, `composicao`, `sync`, `qa_cache_unico`) |
| `tests/…` (5 arquivos) | Alterado | suíte | — |

- Comportamento alterado e não verificado, com motivo: nenhum.

## Critérios e seams acordadas

Seams: a CLI `bin/dbx` com o duplo de `curl` de cada arquivo de integração (seam já acordada no projeto), o texto versionado (README, cabeçalhos) para TC-DOC-01, e a função pública de `lib/sync` carregada em processo limpo para a medida em bytes.

| # | Critério de aceite | Seam sob teste | Origem do acordo | Camada do teste | Coberto |
|---|---|---|---|---|---|
| 1 | TC-ALI-01: cada par do `sync` dá o mesmo plano (7 pares) | `bin/dbx --json --dry-run sync` | Requisitos v1.6 | Integração | Sim — `teste_cada_alias_do_sync_produz_o_mesmo_plano_que_o_nome_em_portugues` |
| 2 | TC-ALI-01: todo em inglês e misto dão o mesmo plano (RF-64(d)) | idem | Requisitos v1.6 | Integração | Sim — `teste_aliases_do_sync_todos_em_ingles_e_misturados_dao_o_mesmo_plano` |
| 3 | TC-ALI-01: `--yes` reconhece a primeira execução espelhada | `bin/dbx sync` real | Requisitos v1.6 | Integração | Sim — `teste_yes_reconhece_a_primeira_execucao_espelhada_como_confirmar` |
| 4 | TC-ALI-01: `--push --pull`, `--enviar --push`, `--pull --receber` recusados pela regra do sentido; `--mirror --yes` com origem vazia → 14; `--allow-empty-source` libera | idem | Requisitos v1.6, DIV-31 | Integração | Sim — `teste_aliases_do_sync_herdam_as_recusas` |
| 5 | TC-ALI-01: `--origem a --source b` usa `b` (RF-64(e)) | idem | Requisitos v1.6 | Integração | Sim — `teste_opcao_com_valor_repetida_por_alias_vale_o_ultimo` |
| 6 | RF-64(c): `Uso:` do `sync` lista os dois nomes | `dbx help sync` | Requisitos v1.6 | Integração | Sim — `teste_ajuda_do_sync_lista_os_dois_nomes_de_cada_opcao` |
| 7 | TC-ALI-02: `unlink --yes` = `--confirmar`; `--keep-app` preserva app key e secret; sem `--yes` segue recusado | `bin/dbx unlink` | Requisitos v1.6 | Integração | Sim — 3 casos `teste_unlink_*` novos |
| 8 | TC-ALI-03: `config --root` = `--raiz` (efeito, recusa, último valor); `--replace` = `--substituir` | `bin/dbx config` | Requisitos v1.6 | Integração | Sim — `teste_config_root_*`, `teste_config_replace_*` |
| 9 | RF-64(c): `Uso:` de `unlink` e `config` lista os dois nomes | `dbx help` | Requisitos v1.6 | Integração | Sim — `teste_ajuda_de_unlink_e_config_lista_os_dois_nomes` |
| 10 | TC-DEL-13: `--receber --espelhar` com origem vazia, memória válida/descartada/ausente: plano com `recusada=origem vazia`, código 14, nada apagado, mensagem sem memória; `--confirmar` não dispensa | `bin/dbx sync` | Requisitos v1.6, O-1 | Integração | Sim — `teste_receber_espelhado_com_origem_vazia_recusa_pelo_plano_em_toda_memoria` |
| 11 | TC-DEL-13: simulação `recusaria`, código 0; `--permitir-origem-vazia` libera | idem | Requisitos v1.6 | Integração | Sim — `teste_receber_espelhado_com_origem_vazia_simula_e_libera_como_o_enviar` |
| 12 | DIV-30: sem `--espelhar`, origem vazia é operação vazia com saída 0, nos dois sentidos | idem | Decisão do Tech Lead (memória) | Integração | Sim — `teste_origem_vazia_sem_espelhar_e_operacao_vazia_com_saida_zero` |
| 13 | RF-41(b): raiz local inexistente continua recusada | idem | Requisitos v1.6 | Integração | Sim — `teste_raiz_local_inexistente_continua_recusada` |
| 14 | TC-CX-04: `É` local e `é` remoto são um caminho com `LC_ALL=C` no ambiente; `--espelhar` não apaga o recém-enviado; conteúdo igual é omitido | `bin/dbx sync` com `LC_ALL=C` | Requisitos v1.6, F-32 | Integração | Sim — `teste_caixa_fora_do_ascii_e_um_caminho_mesmo_com_lc_all_c`, `teste_caixa_fora_do_ascii_com_conteudo_igual_e_omitida_com_lc_all_c` |
| 15 | RF-54(e)/DIV-32: nenhuma medida em bytes muda; `lib/json` preserva nome multibyte | `_dbx_sync_chave` + `dbx_json_escapar_cadeia` em `env -i LC_ALL=C bash` | Requisitos v1.6 (o SD demonstra com caso) | Integração (processo isolado) | Sim — `teste_comparacao_sem_caixa_nao_muda_medida_em_bytes` |
| 16 | TC-CX-05: localidade ausente (simulada) avisa uma vez em stderr, nomeia causa e efeito, `É`/`é` distintos | `bin/dbx sync` com `DBX_SYNC_LOCALIDADE` inexistente | Requisitos v1.6 | Integração | Sim — `teste_localidade_ausente_avisa_uma_vez_e_compara_so_no_ascii` |
| 17 | RF-54(f): no ASCII, código e stdout iguais aos de uma execução sem aviso | idem | Requisitos v1.6 | Integração | Sim — `teste_localidade_ausente_nao_muda_saida_nem_codigo_no_ascii` |
| 18 | RF-54(g): aviso só no `sync` | `bin/dbx list` | Requisitos v1.6 (escopo confirmado pelo Tech Lead na delegação) | Integração | Sim — `teste_aviso_de_localidade_e_so_do_sync` |
| 19 | TC-DOC-01 (a)(b)(d)(e): busca textual sem contradição | texto de `lib/http.sh`, `lib/output.sh`, `README.md` | Requisitos v1.6 | Integração (auditoria de texto em `composicao`) | Sim — `teste_documentacao_nao_contradiz_o_estado_persistente_nem_as_dependencias` (`composicao`) |
| 20 | TC-DOC-01 (c): lista do README = lista do preflight (+ família SHA-256) | README × `DBX_PREFLIGHT_UTILITARIOS` | Requisitos v1.6 | Unitário | Sim — `teste_lista_de_utilitarios_do_readme_e_a_do_preflight` |
| 21 | TC-DOC-01 (c): preflight exige `df` e `tail` de `commands/config.sh` | idem | Requisitos v1.6 | Unitário | Sim — `teste_preflight_exige_os_utilitarios_do_diagnostico_do_config` |

- Seams propostas e descartadas, com motivo: `LOCPATH` para simular a ausência de `C.UTF-8` — medido nesta máquina, a localidade continua disponível com `LOCPATH=/nao/existe`; depender disso faria o teste depender da máquina, o que RF-54(f) proíbe.

## Análise de abordagens (item 3, F-32)

| # | Abordagem | Vantagens | Desvantagens | Decisão |
|---|---|---|---|---|
| A | `LC_CTYPE=C.UTF-8` exportado na entrada do `dbx` (redação original de RF-54(e)) | um ponto só | `LC_ALL` do operador tem precedência e anula (DIV-32); muda `${#x}` e fatiamento em todo o processo, inclusive `lib/json` e `lib/transfer` | Descartada |
| B | `LC_ALL` local à função de comparação, detecção por `locale -a` | escopo mínimo | `locale -a` é captura nova de byte externo em `lib/` (RNF-24) e utilitário novo no preflight; responde "existe", não "a conversão funciona" | Descartada |
| C | `LC_ALL` local à função de comparação (já existente) + detecção pela própria conversão (`É` → `é`) + nome da localidade em constante validada, sobrescrevível pelo ambiente só para a suíte | sem captura nem utilitário novo; mede o que importa; restaura no retorno (medido); simulação independente da máquina | uma variável de ambiente a mais (achado menor 1 do parecer de conformidade) | **Escolhida** |

`local -x` (sugerido na delegação) não foi usado: a função não abre processo filho, e `bash` reaplica a localidade na atribuição de `LC_ALL` mesmo sem exportação — medido com `env -i` e com `LC_ALL=C` (antes 2 bytes, `É`→`é` dentro, 2 bytes depois do retorno).

Itens 1, 2, 5: abordagem única e evidente — padrões a mais no `case` existente (mesmo estilo de `--progresso | --progress | -p`); remoção da guarda e condição só no plano, conforme O-1; correções de texto. Itens 4, 6, 7: refatoração sem mudança de comportamento.

## Evidência do ciclo red-green-refactor

Red executado contra o código do `HEAD` (testes escritos antes de qualquer alteração de produto, rodados por `DBX_TESTES_TMP=… bash <arquivo> <filtro>`):

| # | Fatia vertical | Teste escrito antes? | Evidência do Red (falha observada) | Implementação mínima | Refactor aplicado |
|---|---|---|---|---|---|
| 1 | Aliases do `sync` (critérios 1-6) | Sim | `--source: mesmo plano que --origem` esperado `0\|contrato=1…`, obtido `2\|` (opção não reconhecida); `herdam`: "trecho ausente: [mutuamente exclusiv]", texto "opcao nao reconhecida: --push"; `ajuda`: Uso sem `--source` | padrões `--source`, `--dest`, `--push`, `--pull`, `--mirror`, `--yes`, `--allow-empty-source` no `case` de `commands/sync.sh`; `Uso:` e opções em `bin/dbx` | mensagens de uso citam os aliases |
| 2 | Aliases de `unlink`/`config` (7-9) | Sim | `unlink --yes deve concluir` obtido 2 ("opcao nao reconhecida: --yes"); `unlink_sem_yes`: "[--confirmar]" ausente; `config_root` obtido `2\|`; `config_replace` obtido 2 em vez de 3; Uso sem `--yes` | padrões no `case` de `commands/unlink.sh` e `commands/config.sh`; ajuda | mensagens de recusa citam o alias |
| 3 | TC-DEL-13 e DIV-30 (10-12) | Sim | `valida/sem: o plano traz a recusa` — stdout vazio (recusa antes do plano); `receber sem --espelhar` esperado 0, obtido 14 com "a memoria registra caminhos" | remoção da guarda anterior ao plano em `commands/sync.sh`; `recusaria` só pela guarda do plano | comentários de RF-41(e)(f) atualizados |
| 4 | TC-CX-05 e RF-54(f) (16-17) | Sim | `um aviso so, no stderr` esperado 1, obtido 0; `o aviso sai`: trecho ausente | `DBX_SYNC_LOCALIDADE` + `dbx_sync_localidade_disponivel` em `lib/sync.sh`; aviso único em `commands/sync.sh` | — |
| 5 | TC-DOC-01 (19-21) | Sim | `lib/http nega a memoria de lib/state: 25:# RSK-23 — nao ha estado local persistente`; lista do README `cat chmod head mkdir rm sha256sum shasum tail wc` ≠ preflight; "commands/config.sh invoca df e o preflight nao o exige" | cabeçalho de `lib/http.sh`, `lib/output.sh:33`, README (introdução, recursos, requisitos, versão do cURL), `df`/`tail` no preflight | — |
| 6 | TC-CX-04, RF-54(e), RF-41(b) raiz inexistente, RF-54(g), simulação do DEL-13 (11, 13, 14, 15, 18) | Sim | **Verdes contra o `HEAD`**: o comportamento já existia (`_dbx_sync_chave` já fixava `LC_ALL` local; a guarda de simulação e a da raiz já valiam). Sem red possível; a força do teste é provada por mutação (abaixo) | — | — |

Mutantes aplicados em cópia descartável da árvore (`scratchpad/mut`), cada um sobre cópia limpa:

| Mutante | Casos | Resultado |
|---|---|---|
| M1 remove a fixação da localidade em `_dbx_sync_chave` | TC-CX-04 (2 casos) | Morto: `a_apagar=0` ausente; `identicos=1` ausente |
| M2 fixação exportada no processo inteiro | medida em bytes | Morto: esperado `7\|7\|7\|igual`, obtido `7\|6\|6\|igual` |
| M3 remove `--source` | alias por par | Morto |
| M4 `--yes` com efeito de `--mirror` | `--yes` reconhece | Morto: 14 em vez de 0 |
| M5 `--push` sem a regra de repetição | recusas herdadas | Morto: `--enviar --push` saiu 0 |
| M6 recusa condicionada à memória | TC-DEL-13 (receber) | **Equivalente no `--receber`** (o destino local povoado entra na memória durante o resumo); morto no `--enviar` por `teste_origem_vazia_com_algo_a_apagar_e_recusada_em_toda_combinacao` (enviar/ausente/--confirmar: 0 em vez de 14) |
| M10 guarda reintroduzida antes do plano | TC-DEL-13, DIV-30 | Morto nos dois |
| M7 aviso removido | TC-CX-05 | Morto |
| M8 `--keep-app` sem efeito | TC-ALI-02 | Morto |
| M9 remove `--root` | TC-ALI-03 | Morto |

- Refatorações realizadas sem alteração de comportamento externo: comentários de `lib/http.sh` e `lib/transfer.sh` (diff de código vazio, ver parecer de conformidade); O-6 — `teste_sem_conta_origem_vazia_com_confirmar_nao_apaga_nada` renomeado para `teste_sem_conta_origem_vazia_com_algo_a_apagar_e_recusada_mesmo_com_confirmar`, com a mudança declarada no arquivo e as asserções intactas; SC2034 em `tests/unit/progress_test.sh:219` por diretiva com motivo.
- Mudanças declaradas em testes existentes: `teste_origem_vazia_com_memoria_povoada_recusa_integralmente` — o duplo passou a listar o `um.txt` enviado na primeira execução (a recusa agora depende de haver algo a apagar, O-1); `_sem` de `preflight_test.sh` ganhou `tail` e `df` no PATH reduzido (a lista do preflight cresceu).

## Execução seletiva por módulo, local (Regra 8)

- Mapa de módulos do projeto: [docs/testes/mapa-modulos.md](../testes/mapa-modulos.md)
- Separação em módulos definida?: Automática (módulo = arquivo, mapa do QA)
- Arquivos do diff sem enquadramento automático: Nenhum (o `README.md` está no mapa por `qa_cache_unico`; `docs/registros/` não é código)
- Módulos atingidos diretamente: `commands/sync`, `commands/unlink`, `commands/config`, `bin/dbx`, `lib/sync`, `lib/preflight`, `lib/output`, `lib/http`, `lib/transfer`
- Dependentes diretos incluídos: pela Regra 1 do mapa (todo diff em `lib/*.sh` seleciona `json`, `http`, `preflight`, `composicao`) e pela cadeia de `lib/http`/`lib/transfer`/`lib/output`, a seleção cobre praticamente todos os arquivos; com várias `lib/` alteradas, a delegação manda rodar a suíte inteira (`bash tests/run.sh`), registrada abaixo
- Suíte completa executada durante a demanda, fora do push para a PR?: Sim, por instrução explícita da delegação do Tech Lead para diff em várias `lib/` (não é a suíte do push para a PR)
- Estrutura ou dependência nova adicionada ao mapa nesta alteração?: Não (nenhum arquivo de teste novo; casos novos em arquivos existentes)

| Módulo | Motivo da seleção | Comando | Total | Aprovados | Falhos | Duração |
|---|---|---|---|---|---|---|
| Todos os 26 arquivos de `tests/unit` e `tests/integracao` | várias `lib/` no diff (Regra 1 do mapa e instrução da delegação) | `bash tests/run.sh < /dev/null` | 921 (919 + 2 pulados) | 919 | 0 | 168 s |

Linha de base no `HEAD` (antes de qualquer alteração): 894 aprovados, 0 falhos, 2 pulados. Os 25 casos novos: `sync` +16, `comandos` +6, `composicao` +1, `preflight` +2.

## Suíte completa no push para a PR e na pipeline de main/master (Regra 8)

- Execução local no push para a PR: ainda não houve push para a PR (commit e push são do Tech Lead/`commit-writer`)
- Branch de integração do projeto: `develop` é a principal declarada (entrada `branch-principal`); a pipeline de suíte completa é a do projeto para `master`
- Workflow e job que rodam a suíte completa: não alterados por esta demanda
- Estado no momento do parecer: Ainda não executada (PR não aberto)
- Execução referenciada: não aplicável

## Execução por camada

- Comando oficial de execução isolada: `bash tests/run.sh` (`scripts/suite-completa.cmd`)
- Tecnologia suporta execução em container?: Não (CLI em shell sem imagem no projeto; isolamento por `TMPDIR` privado do runner e `env -i` em cada caso de integração)
- Comando efetivamente executado: `bash tests/run.sh < /dev/null`
- Divergência em relação ao comando oficial: nenhuma
- Banco real da stack usado na integração: não aplicável (sem banco; a persistência é o arquivo de `lib/state`, exercitado de verdade em disco)
- Ferramenta de E2E: não aplicável (sem frontend; a integração exercita a CLI ponta a ponta com o duplo de `curl`, seam acordada do projeto)

| Camada | Comando | Total | Aprovados | Falhos | Ignorados | Não executados por interrupção | Duração |
|---|---|---|---|---|---|---|---|
| Unitário (`tests/unit`, 20 arquivos) | `bash tests/run.sh` | 613 | 611 | 0 | 2 (`hash_vetor_oficial`, vetor oficial ausente, pré-existente) | 0 | na execução única de 168 s |
| Integração (`tests/integracao`, 6 arquivos) | idem | 308 | 308 | 0 | 0 | 0 | idem |
| E2E | — | — | — | — | — | — | Não aplicável |

- Falhas em aberto: nenhuma. Estado testado: árvore de trabalho sobre `6b00bcd`, execução final iniciada após a última alteração de código e teste.

## Interrupção no primeiro erro (Regra 9)

- Parada no primeiro teste falho no runner de cada camada: `harness_executar` emite `Bail out!` no primeiro caso reprovado; `tests/run.sh` interrompe no primeiro arquivo com falha
- Módulos e camadas em sequência (unitário, depois integração), sem iniciar o seguinte após erro?: Sim
- Código de saída propagado até o fim?: Sim (`tests/run.sh` sai 1 na interrupção)
- Job da pipeline: não alterado por esta demanda
- Execução final concluída sem interrupção?: Sim

| # | Camada | Módulo | Teste | Arquivo:linha | Tipo de erro | Mensagem (sanitizada) | Comando | Não executados | Correção e reexecução do início |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Unitário | `lib/preflight` | `todo_utilitario_ausente_reprova_e_e_nomeado` | `tests/unit/preflight_test.sh:227` | Asserção | "RNF-02 exige nomear o utilitario ausente: wc" — obtido `3\|utilitario obrigatorio ausente: tail` | `bash tests/run.sh` | 3 casos do arquivo e 12 arquivos | `tail`/`df` movidos para o fim da lista do preflight e incluídos no PATH reduzido de `_sem`; suíte reexecutada do início |

## Distribuição da pirâmide

| Camada | Alvo | Real entregue (casos novos) | Desvio justificado? | Justificativa |
|---|---|---|---|---|
| Unitário | 70% | 2 de 25 (8%) | Sim | O contrato desta demanda é a linha de comando (aliases, ajuda, plano, aviso, código de saída); a seam acordada é `bin/dbx` com o duplo de `curl`, e testar o `case` de opções por dentro seria acoplar à implementação |
| Integração | 20% | 23 de 25 (92%) | Sim | idem (inclui o caso de texto de `composicao`, que mora na pasta de integração) |
| E2E | 10% | 0 | Sim | Sem frontend; a integração já é ponta a ponta da CLI |

## Verificação das proibições por camada

| Verificação | Camada | Resultado | Evidência |
|---|---|---|---|
| Teste unitário isolado de rede e banco | Unitário | Conforme | Os 2 casos leem o README e a constante do preflight |
| Teste pela interface pública | Unitário | Conforme | `DBX_PREFLIGHT_UTILITARIOS` é canal público; `_dbx_sync_chave` é usada pelo caso de medida em bytes porque é a única função que fixa a localidade (o critério pede a prova na comparação) |
| Padrão AAA e nome que descreve comportamento | Unitário | Conforme | — |
| Banco real via Testcontainers | Integração | Não aplicável | Sem banco |
| Ausência de mock da camada de dados | Integração | Conforme | Memória do `sync` real em `XDG_STATE_HOME` do cenário |
| Contrato HTTP verificado na fronteira real | Integração | Conforme (seam do projeto) | Duplo de `curl` registra cada URL; `_exclusoes`/`_escritas` afirmam o que saiu, não o relatório |
| Fluxo principal contra frontend, backend e banco reais | E2E | Não aplicável | Sem frontend |
| Ausência de `cy.intercept()` | E2E | Não aplicável | — |
| Jornada de negócio completa | E2E | Não aplicável | — |
| Cada critério BDD acordado com cenário | Integração | Conforme | Tabela de critérios: 21 de 21 |

## Governança de dados de teste

| Item | Resultado | Evidência |
|---|---|---|
| Dado originado de criação programática | Conforme | `_cenario`, `_par_semeado`, `_ambiente`, `_ambiente_vazio` |
| Ausência de dado manual e de ID adivinhado | Conforme | — |
| Estado preservado entre cenários relacionados | Conforme | Memória semeada pela primeira execução do próprio caso |
| Teardown apenas ao final | Conforme | `TMPDIR` privado do runner, removido no fim |
| Dado sintético, sem segredo real | Conforme | Credenciais `ak`/`as`/`rt` fabricadas |

## Resiliência E2E e tratamento de flaky

Não aplicável: sem E2E de interface; nenhuma instabilidade observada nas execuções.

## Testes de segurança e acesso (Regra 6 do protocolo)

- Gatilhos considerados: autenticação, autorização, dado sensível, entrada de usuário que chega a arquivo, arquivo
- Gatilhos tocados pela alteração: entrada de usuário/ambiente (`DBX_SYNC_LOCALIDADE`; aliases que levam à exclusão)

| # | Gatilho | Cenário negativo | Ator ou entrada usada | Resultado esperado | Camada | Contra backend/banco real | Resultado |
|---|---|---|---|---|---|---|---|
| 1 | Entrada que leva a exclusão | `--mirror --yes` com origem vazia e algo a apagar | aliases em inglês | código 14, zero escritas | Integração | Seam do projeto (duplo de `curl`, disco real) | Aprovado |
| 2 | Entrada que leva a exclusão | `--receber --espelhar --confirmar` com origem remota vazia, memória ausente/descartada | — | código 14, arquivo local intacto | Integração | idem | Aprovado |
| 3 | Entrada repetida/conflitante | `--enviar --push`, `--push --pull` | aliases | uso inválido (2), nada executado | Integração | idem | Aprovado |
| 4 | Entrada de ambiente | `DBX_SYNC_LOCALIDADE` inexistente | ambiente | sem recusa, aviso único, stdout e código inalterados | Integração | idem | Aprovado |

- Cenários do catálogo não implementados para gatilho tocado: valor de `DBX_SYNC_LOCALIDADE` fora do alfabeto (cai no padrão) não tem caso próprio — o efeito máximo é o mesmo do cenário 4; registrado como recomendação ao QA.
- Resposta, log e evidência verificados sem segredo?: Sim

## Validação de formulários em E2E (Regra 7 do protocolo)

Não aplicável: a alteração não toca interface com entrada de dados (CLI).

## DoD bloqueante para handoff ao QA

| # | Item | Resultado | Evidência |
|---|---|---|---|
| 1 | TDD aplicado, unidade e integração aprovados | Atendido | Red/green acima |
| 2 | Execução isolada com o comando oficial | Atendido | `bash tests/run.sh`, sem container (limitação da stack) |
| 3 | Cobertura dos critérios contra a seam real | Atendido | 21 de 21 |
| 4 | Cenários negativos executados | Atendido | Seção de segurança |
| 5 | Cenários de formulário | Não aplicável | CLI |
| 6 | Execução seletiva aprovada | Atendido | Suíte inteira verde |
| 7 | Parada no primeiro erro e execução final sem interrupção | Atendido | Seção Regra 9 |

## Limitações do ambiente

| Recurso ausente | Impacto na verificação | Achado registrado |
|---|---|---|
| Container | Execução isolada por `TMPDIR` privado e `env -i` | Não (limitação da stack) |
| `bats` | `scripts/tests/*.bats` não rodam; nenhum `scripts/` alterado | Não |

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correção esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 | `tests/integracao/sync_test.sh` (TC-CX-04, RF-54(e), simulação de TC-DEL-13, raiz inexistente, RF-54(g)) | 6 casos novos passam contra o `HEAD`: o comportamento já existia; sem red possível | `protocolo-tdd / Regra 1 - Ciclo TDD` | Prova por mutação (M1, M2, M10) registrada; QA confirma | Menor | Justificado (mutantes mortos) |
| 2 | `tests/integracao/sync_test.sh` (TC-DEL-13, memória ausente) | Sem `--confirmar` e sem memória, quem recusa antes do plano é RF-48 (reconhecimento), não a origem vazia; o caso cobre memória ausente só com `--confirmar` | `protocolo-tdd / Regra 1` (critério literal de TC-DEL-13) | BA/Tech Lead confirmam que RF-48 antes do plano não conta como "recusa por origem vazia antes do plano" | Menor | Aberto, para decisão do Tech Lead |

- Total de bloqueantes: 0
- Total de maiores: 0
- Total de menores: 2

## Achados do ciclo anterior

Não aplicável: ciclo 1.

## Veredito

- Resultado: **Aprovado**
- Justificativa objetiva: todos os critérios de RF-64, TC-DEL-13, TC-CX-04/05 e TC-DOC-01 cobertos com red comprovado onde havia comportamento novo e mutação onde ele já existia; suíte inteira verde após a única interrupção, corrigida e reexecutada do início.
- Ressalvas registradas, com owner e prazo: achado 2 (Tech Lead, antes do commit).
- Handoff liberado?: Sim
- Gate de conformidade liberado para execução?: Sim (executado: [parecer](2026-10-19-0829-parecer-conformidade-docs-e-aliases.md))
- Próximo passo do ciclo do developer: registro de entrega (`documentation-writer`) e validação independente do QA Expert.

## Devolução ao agent

Não aplicável: aprovado.

## Registro

- Referenciado pelo registro de entrega da demanda e pelo parecer de conformidade.

---

## Ciclo 2 (2026-10-19) — devolução do QA, QA-P4-01

- Origem: [validação do QA](2026-10-19-0829-validacao-qa-docs-e-aliases.md), achado **QA-P4-01 (Maior)**, RNF-34: `lib/config.sh:6-8` ("única escrita persistente de todo o projeto… não há cache") e `lib/auth.sh:61-63` ("única escrita persistente do projeto") contradiziam RF-38/RF-61, já que `lib/state` também grava em disco.
- Critério: caso 7 do QA, `teste_qa_p4_doc_readme_lista_os_utilitarios_do_preflight_e_nao_tem_frase_revogada` (arquivo do QA não alterado).
- Red: `VERMELHO` — "lib/auth.sh nao contem [unica escrita persistente] (RNF-34): esperado [ausente], obtido [presente]".
- Correção (só comentário): a credencial passa a ser descrita como o único arquivo que guarda segredo, e `lib/state` como a memória de hash, sem segredo. `git diff -w` filtrado para linhas que não são comentário em `lib/config.sh lib/auth.sh`: 0 linhas.
- Varredura `grep -rniE "unica escrita|única escrita|nao ha cache|não há cache|sem estado local"` em `lib/ commands/ bin/ README.md install.sh`: nenhuma ocorrência restante.
- Green: o caso 7 ficou `VERDE`.
- Suíte inteira (`bash tests/run.sh < /dev/null`, 27 arquivos, já com o arquivo do QA): **935 aprovados, 0 reprovados, 2 pulados**, 186 s, saída 0, sem interrupção.

| # do ciclo anterior | Achado | Status atual | Evidência da correção |
|---|---|---|---|
| QA-P4-01 | Comentários de `lib/config.sh` e `lib/auth.sh` negam a memória de `lib/state` | Corrigido | Caso 7 do QA verde; suíte inteira verde |
| 1 (deste parecer) | Casos verdes contra o `HEAD`, provados por mutação | Justificado (inalterado) | — |
| 2 (deste parecer) | TC-DEL-13 com memória ausente só com `--confirmar` | Aberto, para decisão do Tech Lead | — |

- Veredito do ciclo 2: **Aprovado**. Handoff liberado ao QA para revalidação.
