# Parecer de conformidade arquitetural e de boas praticas — estrutura de pastas antes da transferencia (F-103)

Extraido do registro [2026-11-07-estrutura-de-pastas-registro.md](2026-11-07-estrutura-de-pastas-registro.md). O registro original traz parecer de conformidade apenas para a tarefa 1. A lacuna das tarefas 2 a 8b foi preenchida na revisao do ciclo 2 (secao "Revisao do diff completo (ciclo 2)"), feita por revisor sem participacao na implementacao.

## Identificacao

- Projeto ou produto: dropbox_api (CLI em shell)
- Agent responsavel pela alteracao: Senior Developer (conforme o registro)
- Agent responsavel pela verificacao: Tech Lead (registro original, tarefa 1)
- Data da verificacao: 2026-11-07
- Ciclo de verificacao: 1
- Tipo de alteracao: Implementacao nova
- Execucao: local, sem pipeline
- Porte da demanda: G
- Modo do parecer: Completo

## Escopo verificado

- Comando usado para levantar o diff: nao consta no registro original (o parecer diz "aplicado integralmente sobre o diff"; o comando nao foi registrado).
- Base de comparacao: `origin/develop` @ e3628a6.

| Arquivo | Tipo de alteracao | Camada / modulo | Verificado |
|---|---|---|---|
| `lib/lote.sh` (`dbx_lote_criar_pastas`, contrato no cabecalho) | Alterado | Adaptador (camada de adaptadores) | Sim |
| `tests/integracao/estrutura_pastas_lote_test.sh` | Novo | Testes de integracao, seam = funcao publica com `lib/auth` e `lib/http` reais e duble de `curl` | Sim |
| Tarefas 2 a 8b: `commands/sync.sh`, `lib/sync.sh`, `bin/dbx`, `README.md` | Alterado | Orquestracao do `sync` e ajuda | Sim, ciclo 2 (ver revisao abaixo) |
| `tests/integracao/estrutura_pastas_*_test.sh` | Novo | Testes | Por amostragem (ciclo 2) |

- Arquivos alterados e nao verificados: nenhum do codigo de producao. Testes por amostragem; docs e `scripts/lint.sh` fora do foco do ciclo 2.

## Stack detectada e skills aplicadas

- Stack detectada: shell (bash 4.4 ou superior, padroes do repositorio). A linha `support/bash-4.2` ainda nao foi verificada (ver pendencias do registro).
- Evidencia da deteccao: nao consta no registro original.

| Skill aplicada | Motivo da selecao | Regras consultadas |
|---|---|---|
| `clean-architecture` | obrigatoria em qualquer stack | checklist aplicado sobre o diff da tarefa 1 (regras individuais nao registradas) |
| padroes do repositorio (shell/bash 4.4+) | stack do projeto | nao consta a lista de regras |

- Skills consideradas e descartadas, com motivo: `security-best-practices` e `api-security-best-practices` nao foram acionadas na tarefa 1 (registro: "Regra 6: nao aplicavel, nenhum endpoint exposto, autenticacao ou entrada de usuario nova; o token do teste e sintetico"). Ver a secao de seguranca abaixo para as tarefas 4 e 5.

## Verificacao arquitetural

Checklist `clean-architecture` aplicado integralmente sobre o diff da tarefa 1, segundo o registro. Por regra, o registro original nao traz a evidencia item a item; o resultado consolidado e abaixo.

| Verificacao | Regra | Resultado | Evidencia |
|---|---|---|---|
| Direcao de dependencia | `dep-inward-only` | Conforme (tarefa 1, consolidado) | Adaptador depende so de `lib/auth`, `lib/http` e `lib/json`, sem dependencia nova |
| Propriedade da interface | `dep-interface-ownership` | Conforme (tarefa 1, consolidado) | Nao consta item a item |
| Pureza de dominio | `frame-domain-purity` | Nao aplicavel (adaptador) | Tarefa 1 |
| Dados na fronteira | `dep-data-crossing-boundaries` | Conforme (tarefa 1, consolidado) | Nao consta item a item |
| Ciclos de dependencia | `dep-acyclic-dependencies` | Conforme (tarefa 1, consolidado) | Nao consta item a item |
| Modelo rico | `entity-rich-not-anemic` | Nao aplicavel | Sem entidade nova na tarefa 1 |
| Invariantes na entidade | `entity-encapsulate-invariants` | Nao aplicavel | Sem entidade nova na tarefa 1 |
| Entidade sem persistencia | `entity-no-persistence-awareness` | Conforme (tarefa 1, consolidado) | Sem estado entre execucoes |
| Caso de uso orquestra | `usecase-orchestrates-not-implements` | Nao consta | Nao consta item a item |
| Sem logica de apresentacao no caso de uso | `usecase-no-presentation-logic` | Nao consta | Nao consta item a item |
| Dependencias explicitas | `usecase-explicit-dependencies` | Conforme (tarefa 1, consolidado) | Nao consta item a item |
| Fronteira transacional | `usecase-transaction-boundary` | Nao consta | Nao consta item a item |
| Controller fino | `adapt-controller-thin` | Nao consta | Nao consta item a item |
| Sistema externo isolado | `adapt-gateway-abstraction` | Conforme (tarefa 1, consolidado) | Chamadas de API por `lib/http` e `lib/lote` |
| Coesao e estrutura do dominio | `comp-common-closure`, `comp-screaming-architecture` | Nao consta | Nao consta item a item |

- Reaproveitamento: `_dbx_lote_ler_marca`, `_dbx_lote_resumo_http`, `_dbx_lote_dormir` e as constantes de recuo e teto da DIV-262, sem duplicar (tarefa 1, consolidado).
- Constante unica de fatia; sem estado entre execucoes; motivo de erro so com texto do dbx e o caminho (corpo bruto nunca entra) (tarefa 1).

## Verificacao da skill de stack

| Regra verificada | Skill | Resultado | Evidencia |
|---|---|---|---|
| Padroes de shell do repositorio (bash 4.4+) | padroes do repositorio | Conforme (tarefa 1, consolidado) | `shellcheck -x lib/lote.sh tests/integracao/estrutura_pastas_lote_test.sh` limpo |

## Verificacao de seguranca acionada

- O diff toca autenticacao, autorizacao, segredos, dados sensiveis, sessao/cookies, CSP/CORS ou exposicao de API? Tarefa 1: Nao (registro). Tarefas 2 a 8b: nao consta no registro original. As tarefas 4 e 5 criam `delete_v2` e `create_folder_batch`, que sao escrita remota destrutiva; o registro nao documenta verificacao de seguranca para elas.
- Se sim, skills aplicadas: nao consta.

| Item | Resultado | Evidencia |
|---|---|---|
| Ausencia de segredo no diff | Conforme (tarefa 1, consolidado) | Token do teste sintetico (registro original) |
| Validacao de entrada nas novas fronteiras | Nao consta | Nao consta |
| Autorizacao verificada nos novos acessos | Nao consta | Escopo OAuth `files.content.write`, ja exigido (System Design) |
| Isolamento por tenant quando aplicavel | Nao aplicavel | Projeto CLI de conta unica por perfil |

## Consistencia com o projeto

| Item | Resultado | Observacoes |
|---|---|---|
| Segue padrao ja adotado em modulos equivalentes | Conforme (tarefa 1) | Reaproveita o padrao de `lib/lote.sh` (`dbx_lote_excluir`) |
| Nao reimplementa componente existente | Conforme (tarefa 1) | Ver reaproveitamento acima |
| Coerente com System Design / ARD | Conforme (tarefa 1, consolidado) | Secao "Estrutura de pastas antes da transferencia" do System Design (v1.21) |
| Coerente com decisoes nas memorias do pacote | Nao consta | Entrada de memoria da demanda referida no requisito, sem ref neste parecer |
| Vocabulario de dominio preservado | Nao consta | Nao consta |

## Ferramentas locais executadas

| Ferramenta | Comando | Resultado | Disponivel no projeto |
|---|---|---|---|
| Linter | `shellcheck -x lib/lote.sh tests/integracao/estrutura_pastas_lote_test.sh` | Limpo (tarefa 1) | Sim |
| Linter (projeto) | `sh scripts/lint.sh` | Saida 0 na tarefa 6d; interrupcao intermitente em `commands/download.sh` pelo teto de memoria, rodadas isoladas em 0 | Sim |
| Type checker | nao aplicavel (shell) | nao aplicavel | Nao |
| Analise de ciclos | nao consta | nao consta | Nao consta |

- Limitacoes por ausencia de ferramenta: nao consta analise de ciclos de dependencia para shell.

## Revisao do diff completo (ciclo 2)

Revisor: Senior Developer sem participacao na implementacao. Comando: `git diff develop -- lib/lote.sh lib/sync.sh bin/dbx README.md` e `git diff develop -- commands/sync.sh` (cerca de 900 linhas novas). Skills: `clean-architecture` e padroes de shell do repositorio. Nao rodei suite nem lint (o Tech Lead ja rodou). Numeros de linha de `commands/sync.sh` e `lib/lote.sh` sao os do worktree.

### (1) Camadas

Conforme. O adaptador de rede (`create_folder_batch` e `check`) fica em `lib/lote.sh`, com contrato por variaveis `DBX_LOTE_PASTAS*` no cabecalho. A orquestracao (quando criar, o que apagar, guardas, relatorio) fica em `commands/sync.sh`. Sem dependencia nova alem de cURL; `rmdir`, `mkdir`, `rm`, `find -P` sao utilitarios POSIX ja usados. `lib/lote.sh` nao conhece `commands/`.

### (2) Funcoes `_dbx_cmd_sync_pastas_*`, `_ocupante_*`, `_pasta_local_ocupada_remover`, `_pastas_delta_criar`

- Responsabilidade unica: boa na maioria (`_pastas_orfas_registrar`, `_remota_vazia`, `_apagar_local`, `_falhas_aplicar`). `_pastas_criar` (2397) acumula criar + reenvio + contabilizar; aceitavel. `_pastas_orfas_apagar` (3282) mistura decisao de simulacao e execucao; aceitavel.
- Duplicacao: ver achados 2 e 3 (alem do recuo do check, ja divida).
- `local`: todas as variaveis das funcoes novas estao `local`; as escritas dinamicas (`falhas`, `apagados`, `pastas_*`) sao do executor e declaradas nele. `_PASTA_MOTIVO` (3237) e `_DBX_SYNC_OCUPANTE_REV` (2465) sao globais de canal, sem `local`, por desenho.
- Quoting: sem achado. Uso consistente de `--`, `"${acumulado:?}"` e de chaves `k:` em arrays associativos.
- `set -u`: usa `${arr[@]+"${arr[@]}"}` quase sempre. Excecoes sinalizadas no item 5.
- Comentarios "Executor:": presentes em 12 das 16 funcoes. Ver achado 6.

### (3) Guardas destrutivas

| Ponto | Resultado | Evidencia |
|---|---|---|
| `delete_v2` do ocupante remoto | Conforme | `_ocupante_remoto_ler` (2466) lista o pai inteiro nesta execucao e so retorna 0 com `.tag == file` e `rev` nao vazio; `_ocupante_remoto_apagar` (2515) envia `parent_rev`; antes, `_exclusao_antecipada_permitida` (2454) exige `--espelhar`, exclusao habilitada, sem recusa de origem vazia, destino nao filtrado; o gatilho e `path/conflict/file` devolvido pelo servidor nesta execucao. Nunca `delete_batch` nem `permanently_delete`. |
| `delete_v2` da pasta orfa | Conforme, com risco residual (achado 5) | `_orfas_apagar_remota` (3238) so apaga apos `_orfas_remota_vazia` (3197) listar todas as paginas e achar zero entradas; erro ou listagem incerta = nao apaga; filhos antes do pai; so apos todos os ciclos e com ciclo sem falha, sem leitura parcial; a lista de candidatas vem da tabela do ciclo, listada por inteiro. Sem `parent_rev` (nao existe para pasta). |
| `rmdir` local | Conforme | `_orfas_apagar_local` (3258) percorre cada componente com `-L` (nao segue ligacao), exige `-d`, usa `rmdir --` nao recursivo, falha vira "mantida". |
| `rm` do ocupante local | Conforme na mecanica; ver achado 1 sobre a premissa no delta | `_pasta_local_ocupada_remover` (2601): guardas de `_exclusao_antecipada_permitida`, aceita so ligacao simbolica ou arquivo regular (nunca diretorio, FIFO ou dispositivo), `rm -f --` sem `-r`, confere que o caminho ficou livre, nunca toca o alvo da ligacao. |

### (4) Segredo

Conforme. Nenhuma mensagem, debug ou motivo inclui token, `Authorization` ou corpo bruto. Os motivos so carregam texto fixo do dbx e caminhos; `dbx_debug_linha pasta ...` so registra operacao, resultado e caminho relativo; a saida de `mkdir` (`erro=$(mkdir ...)`) e comparada e descartada, nunca impressa. `_dbx_lote_resumo_http` e anterior ao diff e nao foi reaberto. Nos testes, as unicas ocorrencias de `Authorization`/`Bearer` sao `assert_nao_contem` (negativas); tokens sinteticos.

### (5) Compatibilidade com `support/bash-4.2` (RF-200), apenas sinalizado

| Recurso | Local | Observacao |
|---|---|---|
| `local -n` (nameref, bash 4.3) | `commands/sync.sh:3156` (`_pastas_cobertas_pela_origem`), novo neste diff | Substituir por variavel global de trabalho ou `eval` controlado. |
| `"${duplicadas[@]}"` e `"${pendentes[@]}"` sem guarda `+`, sob `set -u` | `lib/lote.sh:648` e `lib/lote.sh:639` | No 4.2 e no 4.3, vetor vazio com `set -u` e `unbound variable`; ocorre no caso comum (sem duplicadas). |
| `"${relativos[@]}"` no repasse | `commands/sync.sh:2419` | Nao vazio nesse ponto (status nao zero exige falha), mas fragil; usar `${relativos[@]+...}`. |
| `"${cheia[@]}"`, `"${velhos[@]}"`, `"${novos[@]}"`, `"${reenvio[@]}"` | `commands/sync.sh:2538-2580` | Mesmo padrao; `novos` pode ser vazio se o lote nao devolveu resultado. Idem. |
| `printf -v ... '%(%s)T'` | `commands/sync.sh:2349` | Pre-existente (nao e do diff). 4.2 aceita. |
| `wait -n` (4.3), `local -n` em `2002` | `commands/sync.sh:558`, `640`, `2002` | Pre-existentes, fora do diff; ja tratados em `bin/dbx:75`. |
| `${var@Q}`, `declare -n`, `mapfile -d` | Nenhum no diff | Verificado por grep. |
| `${var,,}`, `local -A`, `read -d ''`, `[[ -v ]]` ausente | Diff inteiro | Permitidos no 4.2. |

### (6) Comentarios e cabecalho de `lib/sync.sh`

O novo cabecalho "ARQUIVOS E ARVORE DE PASTAS" substitui corretamente o "SO ARQUIVOS". Ele diz "por `create_folder` na Dropbox", mas a implementacao usa `create_folder_batch` (e `check`): ver achado 7. O resto (pai antes de filho, pasta vazia, `--espelhar` apaga orfas depois dos arquivos, `deleted` de pasta no delta nao apaga) confere com o codigo. O `--ajuda` em `bin/dbx` e o README conferem com o relatorio (`pastas_criadas`, `pastas_apagadas`, `pastas_mantidas`, `pastas_falhas`).

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correcao esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 | `commands/sync.sh:2683-2755` (`_pastas_delta_criar`) com `2601` | No recebimento sem ciclos, a premissa "o remoto tem pasta neste caminho" vem da tabela (retrato gravado mais delta), e dela sai o `rm -f` do ocupante local. A guarda do disco e observada agora, mas a existencia da pasta remota nao foi listada nesta execucao. A regra do projeto diz que o destrutivo so age sobre o observado na execucao, nunca memoria, retrato ou cursor. O delta e lido agora, o retrato nao. Se o Tech Lead ler a regra literalmente, e bloqueante. | Regra destrutiva do projeto (so o observado); `usecase-orchestrates-not-implements` nao se aplica | Decidir com o Tech Lead: (a) no delta, nao apagar ocupante (so falha de item `arquivo no lugar da pasta`, como no RF-214(a)); ou (b) confirmar a pasta remota por `get_metadata` nesta execucao antes do `rm`. Registrar a decisao no registro de entrega. | Maior (condicional a leitura do Tech Lead) | Aberto |
| 2 | `commands/sync.sh:2623-2682` e `2683-2755` | Corpo de ~40 linhas duplicado entre `_pastas_receber_criar` e `_pastas_delta_criar`: heranca de falha de ancestral, remocao de ocupante, aviso, `mkdir` com classificacao de ENOSPC/EROFS, contadores. Uma correcao da guarda destrutiva precisa ser feita em dois lugares. | Duplicacao; `comp-common-closure`; regra de reuso do papel | Extrair `_dbx_cmd_sync_pasta_local_criar <rel>` (herdada, ocupante, mkdir) e deixar as duas funcoes so com a origem da lista. | Maior | Aberto |
| 3 | `commands/sync.sh:2466-2512` e `3197-3235` | Laco de paginacao de `list_folder`/`continue` com teto, repetido em `_ocupante_remoto_ler` e `_orfas_remota_vazia` (e semelhante ao da enumeracao de diretorios). As duas guardam `delete_v2`, entao divergencia futura e arriscada. | Duplicacao | Extrair `_dbx_cmd_sync_listar_pasta_nao_recursivo <caminho> <callback>` que as duas usem. | Maior | Aberto |
| 4 | `commands/sync.sh:2419` e `2538-2580`; `lib/lote.sh:639`, `648` | Expansao de vetor possivelmente vazio sem guarda sob `set -u`. Funciona no 4.4+, quebra no 4.2/4.3 no caso comum (`duplicadas` vazio). | `set -u` seguro; RF-200 | Usar `${v[@]+"${v[@]}"}`. Para a PR da linha legada. | Menor (sinalizado; o 4.4+ passa) | Aberto |
| 5 | `commands/sync.sh:3238-3257` | `delete_v2` de pasta e recursivo no Dropbox. Entre a releitura vazia e o delete ha janela em que outro cliente pode criar arquivo, que iria para a lixeira. Reversivel, janela curta, sem `parent_rev` possivel. | Guarda destrutiva | Aceitar e documentar no comentario e no System Design; sem codigo. | Menor | Aberto |
| 6 | `commands/sync.sh:2371`, `2850`, `2601`, `3238`, `3258`, `3154` | Comentarios "Executor:" ausentes ou incompletos: `_pastas_do_escopo`, `_pastas_campos`, `_pasta_local_ocupada_remover` (usa `apagados`), `_orfas_apagar_remota` (`remoto`), `_orfas_apagar_local` (`raiz_local`). `_pastas_criar` (2397) omite `pastas_criadas`, `falhas`, `apagados`. | Escopo dinamico documentado | Completar a lista de variaveis do executor em cada comentario. | Menor | Aberto |
| 7 | `lib/sync.sh:29` | Cabecalho diz `create_folder`; o codigo usa `create_folder_batch`. | Comentario coerente | Trocar por "`create_folder_batch`". | Menor | Aberto |
| 8 | `commands/sync.sh:3237`, `2465` | `_PASTA_MOTIVO` e global sem o prefixo `_DBX_` dos demais canais internos. | Nomenclatura | Renomear para `_DBX_SYNC_PASTA_MOTIVO`. | Menor | Aberto |
| 9 | `lib/lote.sh:526` e `_dbx_lote_excluir_fatia` | Recuo do `check` duplicado (divida registrada, achado de tarefa 1). | Duplicacao | Tarefa propria. | Menor | Aberto (divida) |
| 10 | `commands/sync.sh:2601-2621`, `2623-2682` | A guarda do `rm` local e do `mkdir` nao confere ligacao simbolica nos ancestrais do caminho (o `rmdir` confere). Na pratica a ordem pai-antes-de-filho trata o ancestral como ocupante, entao nao ha furo observado. | Defesa em profundidade | Opcional: reutilizar o laco de componentes de `_orfas_apagar_local`. | Menor | Aberto |

- Total de bloqueantes: 0
- Total de maiores: 3 (achados 1, 2, 3)
- Total de menores: 7 (achados 4 a 10)

## Achados do ciclo anterior

Achado 1 do ciclo 1 (recuo do check duplicado) segue aberto como divida (ciclo 2, achado 9).

## Veredito

- Resultado: Aprovado com ressalvas (ciclo 2, diff completo).
- Justificativa objetiva: nenhum bloqueante; tres maiores (limite de tres, todos tratados como ressalva). As quatro guardas destrutivas estao conformes na mecanica. Ressalva do achado 1: se o Tech Lead ou o solicitante lerem a regra "so o observado" de forma estrita para o recebimento por delta, o achado sobe a bloqueante e o veredito passa a Reprovado.
- Ressalvas com owner e prazo: achado 1 (decisao do Tech Lead antes do merge; correcao pelo Senior Developer); achados 2 e 3 (Senior Developer, tarefa de refatoracao antes da PR para `master`); achados 4 a 10 (Senior Developer; o 4 vai na PR da linha `support/bash-4.2`).
- Limitacao: nao rodei suite nem lint; testes verificados por amostragem; docs e `scripts/lint.sh` fora do foco.
- Handoff liberado?: pelo gate de conformidade, sim, condicionado a decisao do achado 1.

## Devolucao ao agent

Achados 1, 2 e 3 do ciclo 2 (secao Achados) voltam ao Senior Developer conforme a decisao do Tech Lead; os demais sao recomendacao.

## Registro

- Este parecer e referenciado pelo registro tecnico [2026-11-07-estrutura-de-pastas-registro.md](2026-11-07-estrutura-de-pastas-registro.md).
- Entrada de memoria com `ref:` para este parecer: nao consta no registro original.
