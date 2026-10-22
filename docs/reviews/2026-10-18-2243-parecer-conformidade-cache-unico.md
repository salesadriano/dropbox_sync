# Parecer de Conformidade Arquitetural e de Boas Práticas — Cache único, skip do upload e segredo (fase 3)

## Identificação

- Projeto ou produto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Agent responsável pela alteração: Senior Developer (delegação do Tech Lead)
- Agent responsável pela verificação: Senior Developer (gate local, regra 16)
- Data da verificação: 2026-10-18 (sessão concluída em 2026-10-19)
- Ciclo de verificação: 4 (ciclo 1 em 2026-10-18, com um bloqueante corrigido antes da emissão; ciclos 2 a 4 em 2026-10-19 — seção "Achados do ciclo anterior")
- Tipo de alteração: Implementação nova + Refatoração + Remoção de componente
- Execução: local, sem pipeline
- Porte da demanda: **G**
- Modo do parecer: Completo
- Gate de testes: [parecer de evidências](2026-10-18-2243-parecer-tdd-cache-unico.md) — Aprovado
- Log de prompt: [2026-10-18_2243_cache-unico-p3.md](../prompts/2026-10-18_2243_cache-unico-p3.md)

## Escopo verificado

- Comando usado para levantar o diff: `git status --short`, `git diff --stat`, `git diff -- lib commands bin install.sh README.md tests`
- Base de comparação: `HEAD` = `007f3ec`; diff de produção: 12 arquivos (`lib/`, `commands/`, `bin/dbx`, `install.sh`), mais `README.md` e testes

| Arquivo | Tipo de alteração | Camada / módulo | Verificado |
|---|---|---|---|
| `lib/state.sh` | Alterado (reescrito, formato v2) | Adaptador | Sim |
| `lib/hash.sh` | Alterado (`dbx_hash_identidade`) | Domínio | Sim |
| `lib/walk.sh` | Alterado (registro com identidade; carrega `lib/hash`) | Orquestração (System Design) / adaptador (cabeçalho do arquivo) | Sim |
| `lib/path.sh` | Alterado (`dbx_path_local_canonico`) | Domínio | Sim |
| `lib/auth.sh` | Alterado (RF-63) | Adaptador | Sim |
| `lib/errors.sh` | Alterado (P3.4) | Domínio | Sim |
| `lib/http.sh` | Alterado (P3.4) | Adaptador | Sim |
| `lib/db.sh` | Removido | Adaptador | Sim |
| `commands/upload.sh` | Alterado | Caso de uso | Sim |
| `commands/sync.sh` | Alterado | Caso de uso | Sim |
| `bin/dbx` | Alterado (ajuda do `sync`) | Entrada | Sim |
| `install.sh` | Alterado | Instalador | Sim |
| `README.md` | Alterado | Documentação de produto | Sim |
| `tests/**` (13 arquivos), `docs/testes/mapa-modulos.md` | Novos/alterados/removido | Testes e mapa | Sim (lint e auditorias) |

- Arquivos alterados e não verificados, com motivo: `docs/arquitetura/system-design.md` e `docs/requisitos/*` — do Business Analyst, editados em paralelo; foram lidos só para conferir coerência (seção "Consistência").

## Stack detectada e skills aplicadas

- Stack detectada: Shell script (`bash` 4.4+ em `lib/`, `commands/`, `bin/`; POSIX `sh` em `scripts/`) + `cURL`
- Evidência da detecção: entrada `2026-10-07-1256-stack` da memória; shebangs `#!/usr/bin/env bash`

| Skill aplicada | Motivo da seleção | Regras consultadas |
|---|---|---|
| `clean-architecture` | obrigatória em qualquer stack | `dep-inward-only`, `dep-acyclic-dependencies`, `adapt-gateway-abstraction`, `adapt-controller-thin`, `comp-common-closure` |
| `shellcheck-configuration` | skill de stack (shell) | dialeto pelo shebang; supressão só na linha e com motivo; execução local no diff |
| `security-best-practices` | o diff toca segredo (RF-63), permissão de diretório e estado em disco com caminhos absolutos | segredo fora de argv/log; menor privilégio em arquivo; entrada externa em caminho de escrita |

- Skills consideradas e descartadas: `supabase-postgres-best-practices` (sem banco; o SQLite sai), `api-security-best-practices` (nenhum endpoint exposto pelo produto).

## Verificação arquitetural

| Verificação | Regra | Resultado | Evidência |
|---|---|---|---|
| Direção de dependência | `dep-inward-only` | Conforme (após correção do achado 1) | A identidade do arquivo mora em `lib/hash` (domínio); `lib/walk` e `lib/state` dependem dele. A primeira versão definia a identidade em `lib/walk` e `lib/state` (adaptador) carregava `lib/walk` — contra "a dependência é unidirecional, do topo para a base" do System Design. Guarda: `hash_test` `identidade_mora_no_dominio…` (morta pelo mutante M21) |
| Propriedade da interface | `dep-interface-ownership` | Conforme | `lib/state` expõe a API que os comandos usam (`dbx_state_upload_*`, `dbx_state_registrar`…); os comandos não conhecem o formato do arquivo |
| Pureza de domínio | `frame-domain-purity` | Conforme | `lib/hash` passa a usar `stat` (utilitário de sistema, como já usava `sha256sum`); nenhum adaptador entrou no domínio. `lib/errors` continua sem `lib/json` nem adaptador |
| Dados na fronteira | `dep-data-crossing-boundaries` | Conforme | Identidade trafega como cadeia simples; canais publicados por variável (`DBX_HASH_IDENTIDADE`, `DBX_STATE_HASH`, `DBX_ERRORS_CLASSE`) |
| Ciclos de dependência | `dep-acyclic-dependencies` | Conforme | `walk → hash → errors`; `state → hash → errors`; `commands → state, path, hash`; sem ciclo |
| Modelo rico | `entity-rich-not-anemic` | Conforme | A regra de admissão (`dbx_state_registravel`: leituras iguais, tamanho > 0, anti-corrida) mora em `lib/state`, não nos comandos |
| Invariantes na entidade | `entity-encapsulate-invariants` | Conforme | Formato, versão, cabeçalho e validação de campo são de `lib/state`; corrupção descarta (RF-42) |
| Entidade sem persistência | `entity-no-persistence-awareness` | Não aplicável | Sem entidade de domínio persistida |
| Caso de uso orquestra | `usecase-orchestrates-not-implements` | Conforme com ressalva | `commands/upload` orquestra consulta, cache e envio; a leitura silenciosa do `get_metadata` (`_dbx_cmd_upload_hash_remoto`) ficou no comando (achado 2) |
| Sem lógica de apresentação no caso de uso | `usecase-no-presentation-logic` | Conforme | Saída por `lib/output`; o aviso de diretório alheio no `sync` usa `dbx_output_diagnostico` (canal com redação) |
| Dependências explícitas | `usecase-explicit-dependencies` | Conforme | Cada comando carrega o que usa (`lib/state` no upload; `lib/walk`/`lib/state` no sync) |
| Fronteira transacional | `usecase-transaction-boundary` | Conforme | Uma gravação atômica por `upload`; uma por `sync`, no fim |
| Controller fino | `adapt-controller-thin` | Conforme | `bin/dbx` só ganhou texto de ajuda |
| Sistema externo isolado | `adapt-gateway-abstraction` | Conforme | `get_metadata` passa por `dbx_auth_requisitar` → `lib/http`; nenhum `curl` direto (auditoria de `cli`/`composicao` verde) |
| Coesão e estrutura | `comp-common-closure`, `comp-screaming-architecture` | Conforme | Cache único num só módulo; gravação atômica única (`_dbx_state_gravar_arquivo`) para os dois namespaces; `lib/db` removido sem resíduo |

## Verificação da skill de stack

| Regra verificada | Skill | Resultado | Evidência |
|---|---|---|---|
| Lint local no diff | `shellcheck-configuration` | Conforme | `shellcheck lib/*.sh commands/*.sh bin/dbx scripts/*.sh` (comando oficial) → código 0; `shellcheck -x` nos 13 testes alterados → 0 |
| Supressão só na linha, com motivo | `shellcheck-configuration` | Conforme | 7 novas: SC2034 em `lib/auth.sh` (vetor passado por nome), em `lib/hash.sh` (2 canais públicos) e em `commands/sync.sh` (`tamanhos` por nameref); SC2174 em `lib/state.sh` (`mkdir -p -m` deliberado: só o último componente é do módulo); SC2153 em `commands/sync.sh` (canal de `lib/path`); SC2206 em `tests/unit/state_test.sh` (glob intencional) |
| Dialeto | `shellcheck-configuration` | Conforme | Nenhum script `sh` de `scripts/` foi tocado |
| Captura de byte externo em `lib/` (RNF-24) | projeto | Conforme | Capturas novas só de `stat`, `mktemp`, `printf`, `cd`: alfabeto fechado (auditoria de `json_test` verde) |
| Utilitário externo novo em `lib/` | projeto (`preflight`) | Conforme | `stat`, `find`, `chmod`, `mkdir`, `mktemp`, `mv`, `rm` já constam de `DBX_PREFLIGHT_UTILITARIOS`; `touch` evitado (o carimbo de uso é renovado pela regravação) |
| Tratamento de erro e propagação | projeto | Conforme | Falha de cache nunca muda resultado (RF-61(g)); diretório alheio devolve o código da classe `permissao`; `dbx_errors_*` mantêm o contrato de saída padrão |
| Massa de teste sem `$(printf)`; contagem por `_harness_contar` | projeto | Conforme (após 2 interrupções registradas no parecer de testes) | `json_test`, `composicao_test` verdes |

## Verificação de segurança acionada

- O diff toca autenticação, segredos, dados sensíveis?: Sim (RF-63; estado com caminhos absolutos; permissão do diretório de estado)
- Skills aplicadas: `security-best-practices`

| Item | Resultado | Evidência |
|---|---|---|
| Ausência de segredo no diff | Conforme | Só valores sintéticos de teste (`ak`, `as`, `rt`, `sl.t`); nenhum segredo real |
| Validação de entrada nas novas fronteiras | Conforme | Chave canônica nunca vira texto de nome de arquivo (resumo); registro do cache validado campo a campo; `get_metadata` só aceita `.tag == file` e `content_hash` bem formado |
| Autorização verificada nos novos acessos | Conforme | Diretório de estado só é lido ou escrito quando pertence ao usuário (`-O`, seguindo ligação); de outro dono, nada é lido nem escrito |
| Menor privilégio em disco | Conforme | Diretório 0700 (criado ou corrigido), arquivos 0600 (`mktemp`), temporários órfãos > 1 dia removidos |
| Segredo obrigatório e fora de argv/log | Conforme | Recusa antes da rede; `client_secret` só no corpo, pela entrada padrão do cliente; motivo de recusa sem valor |
| Isolamento por conta | Conforme | Memória do `sync` só com conta identificada (RF-52(a)); cache do `upload` sem conta por decisão (RF-52(b)), protegido pela comparação com o hash remoto |

## Consistência com o projeto

| Item | Resultado | Observações |
|---|---|---|
| Segue padrão já adotado em módulos equivalentes | Conforme | Gravação atômica igual à de `lib/config`; canais publicados por variável como em `lib/hash`/`lib/path`; registros terminados em NUL como em `lib/walk` |
| Não reimplementa componente existente | Conforme com ressalva | Reaproveita `_dbx_path_resolver_fisico`, `dbx_hash_publicar_arquivo`, `dbx_hash_iguais`, `dbx_output_diagnostico`. Ressalva: leitura silenciosa de JSON em `commands/upload.sh` paralela a `_dbx_cmd_analisar_corpo` (achado 2) |
| Coerente com System Design / ARD | Conforme | Seção v1.5 do System Design (dois namespaces, `upload-*` por origem canônica sem conta, 0700, poda 10.000/90 dias, `lib/db` removido, PKCE fora). Divergência menor: o System Design descreve `memoria-*` com "hash, tamanho, `mtime`, caminho" (linha "Natureza do dado"); a v2 grava hash, identidade forte e caminho, como manda RF-38(e) — atualização documental com o Business Analyst |
| Coerente com decisões nas memórias | Conforme | `2026-10-18-2243-cache-unico-e-segredo`, `2026-10-18-2243-cache-do-upload` (DIV-26 a DIV-29), `2026-10-18-1745-skip-upload-condicionado` |
| Vocabulário de domínio preservado | Conforme | `memoria`, `registrar`, `consultar`, `gravar`, `identidade`, `chave canonica` |

## Ferramentas locais executadas

| Ferramenta | Comando | Resultado | Disponível no projeto |
|---|---|---|---|
| Linter | `shellcheck lib/*.sh commands/*.sh bin/dbx scripts/*.sh` (0.10.0) | 0 achados | Sim |
| Linter (testes alterados) | `shellcheck -x` nos 13 arquivos de teste alterados | 0 achados | Sim |
| Type checker | — | Não aplicável | Não |
| Análise de ciclos | auditoria `hash_test` `identidade_mora_no_dominio…` e leitura das cargas `. "$dir/x.sh"` | Sem ciclo | Parcial (manual) |
| Auditorias do projeto | `json`, `http`, `preflight`, `composicao`, `cli` (seleção inteira, 24 arquivos) | 838 aprovados, 0 falhos | Sim |
| Guarda de remoção de casos | `bash scripts/verificar-remocao-de-casos.sh develop` | Acusa `tests/unit/db_test.sh 4 -> 0` não declarada (esperado antes do commit) | Sim |

- Limitações por ausência de ferramenta: não há verificador automático de direção de camada; a guarda específica criada nesta fase cobre o caso desta demanda.

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correção esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 | `lib/state.sh` (carga de `lib/walk.sh`), `lib/walk.sh` (definição da identidade) | `lib/state` (adaptador) passou a depender de `lib/walk` (orquestração) para obter a definição de identidade: dependência contra a direção das camadas do System Design | `clean-architecture / dep-inward-only` | Definição única em `lib/hash` (domínio); `lib/walk` e `lib/state` dependem dele; guarda de regressão | Bloqueante | **Corrigido** neste ciclo, antes da emissão: `dbx_hash_identidade` em `lib/hash.sh`; `lib/state.sh` não carrega mais `lib/walk.sh`; guarda `identidade_mora_no_dominio…` (mutante M21 morto); seleção inteira reexecutada, verde |
| 2 | `commands/upload.sh` (`_dbx_cmd_upload_hash_remoto`) | Leitura silenciosa de campo de JSON (contexto, análise, descarte) escrita no comando, paralela a `_dbx_cmd_analisar_corpo` de `lib/cmd`, que emite diagnóstico na falha e por isso não servia para "falha leva ao envio" | `clean-architecture / comp-common-closure`; família de gêmeos do projeto (`lib/cmd`) | Extrair para `lib/cmd` uma variante silenciosa de leitura de corpo quando surgir o segundo uso | Menor | Aberto (recomendação) |
| 3 | `bin/dbx` (ajuda do `sync`) | A ajuda anunciava `--reconhecer-primeira-execucao`, sinalizador que o código não aceita (o real é `--confirmar`); corrigido junto com o aviso de RF-52(a), porque o aviso precisa nomear o sinalizador certo | Consistência com o projeto | — | Menor | Corrigido |
| 4 | `README.md` | O README anunciava o cache SQLite, `sqlite3` e o recuo para `python3`; reescrito para o cache único, o legado `dbx.db*` e o aviso de RF-52(a) | RNF-33(c) | — | Menor | Corrigido |

- Total de bloqueantes: 0 em aberto (1 encontrado e corrigido no ciclo)
- Total de maiores: 0
- Total de menores: 3 (1 em aberto, como recomendação)

## Achados do ciclo anterior

Ciclo 2 (2026-10-19), devolução do Tech Lead: o risco de RF-41(b) sem conta identificada, apontado no relatório do ciclo 1 como divergência, foi classificado como bloqueante e entrou na fase (DIV-28 revista).

| # do ciclo anterior | Achado | Status atual | Evidência da correção |
|---|---|---|---|
| 1 | Direção de dependência `lib/state` → `lib/walk` | Corrigido (ciclo 1) | Guarda `identidade_mora_no_dominio…` verde |
| 2 | Leitura silenciosa de JSON em `commands/upload.sh` | Não corrigido (ressalva menor, owner e prazo mantidos) | — |
| 3, 4 | Ajuda com sinalizador inexistente; README com SQLite | Corrigidos (ciclo 1) | — |
| Divergência (relatório do ciclo 1) | Sem conta identificada, `--espelhar --confirmar` com origem vazia apagaria o destino | **Corrigido** | `commands/sync.sh`: a exclusão é desabilitada pelo mesmo mecanismo de RF-41(a) (`exclusao_desabilitada`, lista de exclusões esvaziada antes do plano), motivo `conta nao identificada` na saída, `nao_concluida` ao fim; vale nos dois sentidos; `--confirmar` não participa da condição. Ajuda e README atualizados |

Verificação do diff do ciclo 2 (`commands/sync.sh`, `bin/dbx`, `README.md`, `tests/integracao/sync_test.sh`):

| Item | Resultado | Evidência |
|---|---|---|
| Reuso do mecanismo existente, sem caminho paralelo | Conforme | Mesmo `exclusao_desabilitada` e mesmo esvaziamento de `DBX_SYNC_APAGAR` da travessia parcial; o motivo acumula quando há as duas causas |
| Direção de dependência e camadas | Conforme | Mudança só no caso de uso; `lib/` intocado |
| Saída e diagnóstico pelos canais do projeto | Conforme | `dbx_output_campo exclusao_desabilitada`; `dbx_cmd_falhar nao_concluida` |
| Segurança (falha segura) | Conforme | Sem memória, nenhuma exclusão é emitida, com ou sem `--confirmar`; RF-48 inalterado |
| Lint | Conforme | `shellcheck lib/*.sh commands/*.sh bin/dbx scripts/*.sh` → 0; `shellcheck -x tests/integracao/sync_test.sh` → 0 |

Achados novos no ciclo 2: nenhum.

Ciclo 3 (2026-10-19), reprovação do QA ([validação](2026-10-18-2243-validacao-qa-cache-unico.md)). Diff do ciclo: `lib/state.sh`, `lib/auth.sh`, `lib/config.sh` (comentário), `commands/sync.sh`, `commands/upload.sh`, `README.md`, testes `sync`, `comandos`, `auth` e o mapa.

| Item | Resultado | Evidência |
|---|---|---|
| QA-P3-01: reuso do mecanismo de RF-41(a) | Conforme | Mesmo `exclusao_desabilitada`; o motivo `memoria descartada` se soma aos outros; `lib/state` só publica o fato (`DBX_STATE_DESCARTADA`) e não decide nada, como manda o cabeçalho do módulo |
| QA-P3-02: direção de dependência | Conforme | A tradução de código para classe fica em `lib/auth` (`dbx_auth_preparar`), que já depende de `lib/errors`; a recusa e o diagnóstico ficam nos comandos. A primeira versão pôs o auxiliar em `lib/cmd`, e a auditoria de `composicao` acusou a leitura de `DBX_AUTH_MOTIVO` sem limpeza. Desfeito: `lib/cmd` voltou ao HEAD |
| QA-P3-02: gêmeos | Conforme, com registro | A recusa prévia aparece em dois comandos (`upload`, `sync`), com o conjunto declarado no comentário de `dbx_auth_preparar` e nos dois pontos de chamada; o mutante M27 mostra que os dois estão cobertos |
| QA-P3-03 | Conforme | Status capturado antes do teste (`|| estado_remoto=$?`), sem `set +e` nem negação |
| Contrato público | Conforme | Código de saída sem segredo passa de 2 para 3 por requisito (RF-63(a) → RF-03); mudança declarada nos casos do `auth_test` |
| Lint | Conforme | `shellcheck lib/*.sh commands/*.sh bin/dbx scripts/*.sh` → 0 (2 supressões novas SC2034 em canais públicos: `DBX_STATE_DESCARTADA`, `DBX_AUTH_CLASSE`) |

Ciclo 4 (2026-10-19), reprovação do QA (ciclo 2 do QA), com a decisão do solicitante na memória `2026-10-18-2243-guarda-origem-vazia`. Diff do ciclo: `commands/sync.sh`, `lib/state.sh`, `bin/dbx` (ajuda), `README.md`, `tests/integracao/sync_test.sh`, `tests/unit/state_test.sh`.

| Item | Resultado | Evidência |
|---|---|---|
| Guarda de origem vazia independente da memória | Conforme | Decisão no caso de uso (`commands/sync.sh`), sobre dados que ele já tem (`vazia`, `DBX_SYNC_APAGAR`). `lib/state` segue sem decidir nada |
| Ordem plano → recusa → escrita (RF-41(d)) | Conforme | O plano sai com `recusada=origem vazia` e zero exclusões. A recusa vem logo depois de `dbx_output_render`, antes do bloco de escrita. Em simulação, `recusaria` e saída 0 (RF-44) |
| Sinalizador novo | Conforme | `--permitir-origem-vazia` é tratado no laço de opções, como os demais; está na ajuda e no README; `--confirmar` não entra na condição (mutante M29) |
| Gravação só após travessia completa | Conforme | Uma condição só (`parcial != sim`) na chamada de `dbx_state_gravar`; o 4º argumento passou a ser sempre `sim` |
| Memória ilegível | Conforme | Recorte em `lib/state`: só arquivo do usuário conta como descartado. Arquivo ou alvo alheio segue não lido e sem provar execução (segurança: não confiar em arquivo plantado) |
| Lint | Conforme | `shellcheck lib/*.sh commands/*.sh bin/dbx scripts/*.sh` → 0 |

Achados novos nos ciclos 3 e 4: nenhum. A ressalva menor do ciclo 1 (achado 2) segue aberta, e o QA a apontou como a razão de o motivo se perder no `upload` (O-5). Agora ela é contornada pela recusa prévia: o motivo chega ao operador sem passar pela leitura silenciosa.

## Veredito

- Resultado: **Aprovado com ressalvas**
- Justificativa objetiva: a construção respeita camadas, fronteiras e as regras de shell do projeto depois da correção da direção de dependência (achado 1, bloqueante corrigido e guardado por teste); lint limpo; auditorias do projeto verdes; segurança do segredo e do estado em disco conforme. A ressalva é o achado 2 (menor), sem impacto estrutural.
- Ressalvas registradas, com owner e prazo: achado 2 — owner Senior Developer, na próxima demanda que precise de leitura silenciosa de corpo (ou na fase 4, o que vier antes).
- Handoff liberado?: Sim
- Próximo passo do ciclo do developer: registro de entrega (`documentation-writer`), validação independente do QA, `commit-writer` com o trailer `Remocao-de-casos: tests/unit/db_test.sh 4`.

## Devolução ao agent

Não aplicável: parecer não reprovado.

## Registro

- Decisão durável para o Tech Lead avaliar como entrada de memória (`escopo: projeto`, `ref:` para este parecer): a identidade forte do arquivo mora em `lib/hash` (domínio) e é consumida por `lib/walk`, `lib/state` e pelos comandos; `lib/state` não depende de `lib/walk`.
- Divergências para o Tech Lead (regra 24), fora deste diff: ver relatório de handoff (o risco de RF-41(b) sem conta foi corrigido no ciclo 2; restam: `CLAUDE.md` ainda cita `lib/db.sh`; linha "Natureza do dado" do System Design).
- Referenciado pelo registro de entrega da demanda; referencia o [parecer de evidências de testes](2026-10-18-2243-parecer-tdd-cache-unico.md).
