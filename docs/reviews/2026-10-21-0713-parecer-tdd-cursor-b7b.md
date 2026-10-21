# Parecer de Evidencias de Testes (TDD) — Cursor de listagem no `sync --receber`, F-14 (fase 7b)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: cursor de listagem (`list_folder/continue`) com instantâneo remoto persistido no `sync --receber`, F-14 (RF-110 a RF-119, escopo v1.23, seção 5.16); porte **G**
- Agent responsavel pela alteracao e pela verificacao: Senior Developer (gate local, regra 14); validacao independente a cargo do QA Expert
- Data: 2026-10-21 (ciclo 1 e ciclo 2)
- Ciclos: 2 (ciclo 1 inicial; ciclo 2 apos QA-B7B-01, QA-B7B-02, QA-B7B-03 e O1)
- Branch / base: `feature/cursor-b7b` sobre `develop` @ `a6b5376`, sem commit
- Log de prompt: [2026-10-21_0713_backlog-fase-7b-cursor.md](../prompts/2026-10-21_0713_backlog-fase-7b-cursor.md)
- Registro de entrega: [2026-10-21-0713-registro-cursor-b7b.md](2026-10-21-0713-registro-cursor-b7b.md)
- Parecer de conformidade: [2026-10-21-0713-parecer-conformidade-cursor-b7b.md](2026-10-21-0713-parecer-conformidade-cursor-b7b.md)
- Validacao do QA: [2026-10-21-0713-validacao-qa-cursor-b7b.md](2026-10-21-0713-validacao-qa-cursor-b7b.md)
- Transcricao fiel do parecer do Senior Developer (secoes de TDD). As secoes comuns aos dois gates aparecem nos dois arquivos.

## Transcricao

Worktree: `/home/sales/dropbox_api.worktrees/feature-cursor-b7b` (base `a6b5376`, sem commit).
Requisitos: escopo v1.23, seção 5.16 (RF-110 a RF-119); decisões: memória `2026-10-21-0713-cursor`; parecer do DBA (C1 a C11); RSK-77 a RSK-84.

### 1. Escopo do diff

| Arquivo | Mudanca |
|---|---|
| `lib/state.sh` | Namespace `cursor-<resumo32>` (NUL v1, magia `dbx-cursor`, cabeçalho de 12 campos, corpo n × 2, rodapé `fim` + SHA-256): `dbx_state_cursor_contexto` (chave SHA-256 com NUL de `cursor`, `cred-`, local canônico, remoto dobrado ASCII, assinatura; `account_id` no cabeçalho); `dbx_state_cursor_carregar` (leitor em fluxo: só arquivo regular do usuário, um descritor, campo ≤ 8 KiB, ≤ 1.000.000 entradas e 512 MiB, regex por campo, função de entrada do chamador, rodapé conferido sobre o mesmo inode via `/dev/fd`; descarte apaga só com `apagar=sim`); `dbx_state_cursor_gravar` (atômica pela `_dbx_state_gravar_arquivo`, com gancho opcional de rodapé); `dbx_state_cursor_remover`; `dbx_state_cursor_vencido` (7 dias, 100 incrementais, relógio -5 min); poda (8 dias, teto 100, uma vez por execução, só `cursor-*`, nunca o corrente); `dbx_state_cursor_listar` (só cabeçalho). `.cursor.*` entra na varredura de 24 h. `DBX_STATE_VERSAO` inalterada. |
| `lib/sync.sh` | Tabela remota sem filtro (DIV-g): `dbx_sync_listar_completo` (`list_folder` com `limit`; `continue` só com cursor, DIV-214 B; guarda de cursor repetido e teto de 20.000 páginas, DIV-h); `dbx_sync_listar_delta` (incremental; 401/403 fatal; 409/4xx/5xx/429/rede/malformado/incoerente/laço → recuo); receita do serviço (`file`, `folder`, `deleted`); coerência do delta (`id`, `rev`, confinamento, sem `.`/`..`/controle, `id` único); `dbx_sync_retrato_entrada` (confinamento e `path_lower` repetido); `dbx_sync_tabela_emitir` (escopo filtrado DEPOIS, mesmas contagens); `dbx_sync_confirmar_exclusoes` (só `path/not_found` confirma; agrupado por raiz apagada; > 50 → completa); `dbx_sync_tabela_datada`; `dbx_sync_tabela_corpo`. `dbx_sync_enumerar_remoto` virou a composição listar + emitir (`verificar` e `--enviar` com resultado inalterado). |
| `commands/sync.sh` | Opções `--sem-cursor`/`--no-cursor` e `--varredura-completa`/`--full-scan` (2 com `--enviar` ou juntas, ou fora do `--receber`, antes de qualquer estado); `_dbx_cmd_sync_cursor_preparar` (elegibilidade: `cred-`, `account_id`, local canônico, trava do par); laço de até 2 rodadas (incremental → confirmação → completa na mesma execução); confirmação antes do plano, também sem `--espelhar` e na simulação; campos `varredura`, `cursor_motivo`, `cursor_mudancas`, `cursor_confirmadas` só no `--receber` do próprio `sync`; gravação após a `memoria-*`, só com código final 0; download `not_found`/`conflito` de item incremental apaga o registro. |
| `commands/download.sh` | `local DBX_CMD_SYNC_CHAMADOR=download` nas duas delegações: o `sync` interno do download de pasta nunca usa o cursor nem emite os campos (DIV-205). |
| `commands/diagnostico.sh` | Checagem `cursor` (DIV-220): uma linha por registro, só cabeçalho, `valido`/`vencido` (ok) ou `ilegivel` (aviso); sem registros, nenhuma linha. Remédio corrigido (O1). |
| `bin/dbx`, `completions/dbx.bash` | Ajuda do `sync` com as opções nos dois nomes e as três frases de RF-118(e); autocompletar só no `sync`. |
| `README.md`, `docs/arquitetura/system-design.md` (v1.16), `docs/testes/mapa-modulos.md` | documentação |
| Testes novos | `tests/integracao/cursor_test.sh` (48 casos); `tests/unit/cursor_estado_test.sh` (13); `tests/unit/sync_tabela_test.sh` (12). Nenhum teste aprovado alterado. |

### 2. Verificacao de contratos (DIV-219) — Context7 `/websites/dropboxapi_dropbox-api`

| Ponto | Resultado | Uso |
|---|---|---|
| `DeletedMetadata` no `list_folder`/`continue` | Confirmado: só `name`, `path_lower`, `path_display` (ambos nulos se não montado); sem `id`/`rev` | Classificação da contradição pelo `id` do retrato; `path_lower` nulo no delta → varredura completa |
| Receita de aplicação | Confirmada: `file` substitui e remove filhos; `folder` substitui e mantém filhos; `deleted` remove subárvore, desconhecido é ignorado | `_dbx_sync_entrada` |
| `include_deleted` | Documentado só no `list_folder` (padrão falso). **Não confirmado** se o `continue` com `include_deleted` falso sempre relata exclusões | Em dúvida: só mantém arquivo local extra até a periódica (direção segura) → RSK-78 |
| Validade do cursor | "long-lived, but may expire if unused for an extended time"; expirado → `409 reset`; raiz apagada → `409 path`; sem prazo | Só o servidor decide; relógio só força varredura a mais |
| `reset` | Confirmado `ListFolderContinueError.reset` (409) | Recuo para completa, motivo `reset`, nunca 14 |
| `get_metadata` de item apagado | Confirmado: sem `include_deleted`, `LookupError.not_found` (`path/not_found`) | Único resultado que confirma |
| Mudança só de caixa | Confirmado: "Changes to only the casing of paths won't be returned by list_folder/continue" | DIV-227 (grafia antiga até a periódica) |
| Cursor da última página cobrindo mudanças durante a varredura | Não documentado de forma explícita | Coberto pela receita (entradas aplicadas na ordem) e pela periódica; RSK-78 |
| Entrada da própria pasta listada em `list_folder` recursivo | Exemplo da documentação: listar `/Homework/math` devolve `{"tag":"folder","path_lower":"/homework/math"}` | Descoberto pelo QA (QA-B7B-02). Corrigido no ciclo 2; o duplo passou a devolvê-la |

### 3. Parecer `protocolo-tdd` — **Aprovado com ressalvas (ciclo 1)**

**Evidencias (ciclo 1).**
- Red contra a base `a6b5376` (cópia por `git archive`, testes novos copiados, caso a caso): integração **43/45 vermelhos** (os 2 verdes na base são guardas de regressão: `cul02` simulação sem registro não cria, `cur13` sem trava sem cursor); unidade `cursor_estado` **12/12** e `sync_tabela` **9/9** vermelhos.
- Green no worktree, caso a caso e pela suíte: `cursor_test` 45/45, `cursor_estado_test` 12/12, `sync_tabela_test` 9/9.
- Mutantes, um ou mais por P0 (RF-111, 112, 113, 114, 116, 117(a), 110/DIV-205, C6, C10, DIV-214, DIV-h, C11): seção 5.
- Execução seletiva pelo mapa de módulos (seção 6).
- `bash scripts/verificar-remocao-de-casos.sh`: seção 6.
- RNF-24: dados de teste por `printf -v`; nenhuma função definida duas vezes por arquivo.

**Pirâmide.** 21 casos de unidade (`lib/state` e `lib/sync`) e 45 de integração ponta a ponta por `bin/dbx` com dublê de rede por regras (ciclo 1). Não há E2E de interface (CLI sem UI; Cypress e Testcontainers não se aplicam, sem banco nem navegador — o "banco" é o arquivo NUL, exercitado de verdade). A proporção pende para a integração porque os P0 são propriedades da composição (plano igual, nada apagado, código 0), que só a execução inteira prova; registrado.

**Ressalvas (não bloqueantes, para o Tech Lead).**
- **R1 (ordem do ciclo):** em `lib/state` (namespace `cursor-*`) e na refatoração de `lib/sync`, parte do código foi escrita antes dos casos que a cobrem; o vermelho foi comprovado depois, contra a base, para todos os casos novos (e nenhum caso verde na base cobre comportamento novo). Fica registrado como desvio de ordem do red-green. **Aceita pelo Tech Lead.**
- **R2:** `TC-CUL-04/05` (sinais em cada fase e `SIGKILL` na gravação) não tinha caso próprio no ciclo 1; a gravação é a mesma `_dbx_state_gravar_arquivo` coberta na 7a. Recomendado ao QA o caso de sinal no `continue` e nas confirmações. **Coberto pelo grupo E da suíte do QA** (TERM, INT e HUP no `continue` e na confirmação).
- **R3:** desempenho de 100 mil / 1 milhão de entradas não medido (carga do retrato em array associativo, `_dbx_sync_ids_unicos` O(n), remoção de subárvore O(n) por pasta apagada). Fica para a F-34 (RSK-72 análogo; RSK-79).

### 4. Parecer `protocolo-conformidade` — ver [parecer de conformidade](2026-10-21-0713-parecer-conformidade-cursor-b7b.md)

### 5. Mutantes (P0) — ciclo 1: 22 aplicados, 22 mortos

Cada mutante numa cópia do worktree, um caso alvo.

| Mutante | Requisito | Morto por |
|---|---|---|
| m01/m01b rodapé não conferido | RF-111, C4 | `cursor_estado: rodape_..._mutante`; `cursor_test: cur05_06` (sha_errado) |
| m02 retrato sem confinamento | RF-111(f), RF-50 | `cur05_06` (ponto_ponto) |
| m03 cabeçalho sem reconferência | C2 | `cursor_estado: cabecalho_divergente` |
| m04 delta ignora `deleted` | RF-112(d) | `cuv03` diferencial (apagado) |
| m05 pasta excluída não conta (filtro antes) | DIV-g, RF-80(i) | `sync_tabela: emitir` (sobreviveu na 1ª rodada; caso reforçado com pasta vazia) |
| m06 `reset` vira falha | RF-113(c) | `cuf01` |
| m07 sem varredura periódica | RF-113(d) | `cuf07_08` |
| m08 descarte do cursor apaga `memoria-*` | RF-113(e), C9 | `cuf03_04` (sobreviveu na 1ª rodada; caso reforçado: memória byte a byte quando a completa também falha) |
| m09/m09b sem confirmação | RF-114 | `cud03_04`, `cud05` |
| m10 qualquer 409 confirma | RF-114(b) | `sync_tabela: so_not_found_confirma` |
| m11 sem teto de 50 | RF-114(c) | `cud09_cuf10` |
| m12 confirma só com `--espelhar` | RF-114(f), DIV-218 | `cud01_02` |
| m13 mapa esvaziado vai à guarda | RF-116(c) | `cuf11` |
| m14 simulação apaga registro | RF-117(a) | `cud13_cul01` |
| m15 download de pasta usa o cursor | RF-110, DIV-205 | `cua02_03` (sobreviveu na 1ª rodada; reforçado) |
| m16 grava com item falho | RF-111(g), C6 | `cur10_cuv06` |
| m17 cursor em aviso | C10 | `cur08` |
| m18 `limit` no `continue` | DIV-214 | `cuv02_cul11` |
| m19 sem guarda de cursor repetido | DIV-h | `cuf06` |
| m20 poda alcança outro namespace | C11 | `cursor_estado: poda` |

**Ciclo 2: 10 aplicados, 10 mortos.**
- `-n $4` de volta: morto por `cursor_estado qa_b7b_01`, `qa_z01` e `cursor_test qa_b7b_01`.
- Sem reconhecer a própria pasta: morto por `sync_tabela qa_b7b_02`, `qa_z02` e `cursor_test qa_b7b_02`.
- Reconhecer a raiz sem conferir a tag: morto por `sync_tabela qa_b7b_02` (arquivo com o caminho da raiz).
- Sem confinar `path_lower`: morto por `sync_tabela qa_b7b_03` e `qa_z03`.
- Remédio antigo: morto por `qa_b7b_o1`.

### 6. Execucao seletiva e guarda de remocao

Pelo mapa de módulos (Regra 1 inclusa), última execução de cada filtro no ciclo 1, todas APROVADAS: `state` 60, `retomada` 132, `sync` 100, `verificar` 17, `diagnostico` 39, `filtros` 58, `comandos` 119, `trava` 82, `espaco` 13, `completar` 17, `cli` 17, `composicao` 28, `tmp_test` 16, `confinamento_remoto` 25, `banda` 34, `cursor` 57, `json` 62, `harness` 22, `http` 53, `preflight` 35, `identidade_gnustat` 7, `recuperacao` 91, `reter` 84, `qa_` 391.

Durante a demanda, as auditorias pegaram três defeitos do próprio SD, corrigidos: `qa_e09` (leitura da data remota fora da guarda → DIV-221), `composicao` (`grep -c` sobre arquivo no teste novo) e `json` (`$(printf ...)` como dado no teste novo, RNF-24; e duas capturas em `lib/state` que começavam por `head` e `type`, reescritas com `_dbx_hash_sha256_hex <(head ...)` e `declare -F`). Depois da última mudança em `lib/state`, rerodados `json`, `state`, `cursor`, `retomada`, `sync`, `trava` e os mutantes m01/m01b: verdes e mortos.

`bash scripts/verificar-remocao-de-casos.sh` (ciclo 1): "1872 -> 1872 caso(s), nenhuma redução não declarada". `shellcheck`: limpo em `lib/`, `commands/`, `bin/`, `scripts/*.sh` e nos três testes novos (os únicos avisos são de arquivos não-shell pré-existentes em `scripts/`).

### 7. Divergencias da implementacao (DIV-221 em diante)

| DIV | Ponto | Implementado | Recomendacao do SD | Decisao do TL |
|---|---|---|---|---|
| **DIV-221** | RF-111(d)/C3 pedem `server_modified` sempre no retrato. O teste aprovado `qa_e09_server_modified_nunca_decide_transferencia` (QA-B4-E09) exige UM ponto de leitura da data remota em `lib/sync` | A data só é lida quando filtra o escopo; no retrato vira `-` fora disso. Incremental com filtro de data e retrato sem data → varredura completa (`descartado`). Teste aprovado não alterado | Aceitar; BA ajusta RF-111(d) | Aceita |
| **DIV-222** | RF-118(d) enumera 8 motivos; há casos fora deles | `descartado`: > 50 confirmações, mapa esvaziado (RF-116(c)), filtro de data sem data, delta incoerente/laço/4xx/outro 409. `sem-registro`: sem `cred-`, sem `account_id`, sem trava, sem raiz canônica | Aceitar | Aceita |
| **DIV-223** | C1/C4: hash do arquivo `^[0-9a-f]{64}$` | Arquivo sem `content_hash` (não baixável, p.ex. Google Docs) entra com `-` e o plano o trata como hoje. Sem isso, uma árvore com um arquivo assim nunca teria cursor | Aceitar | Aceita |
| **DIV-224** | Teto de páginas: TC-CUV-08 diz "delta acima do teto: 10"; TC-CUF-06 e o briefing dizem "abandona e faz a completa" | Delta acima do teto ou cursor repetido → completa (TC-CUF-06). Na varredura completa, guarda nova (DIV-h): cursor repetido ou > 20.000 páginas → `10`. Teto de 20.000 para não recusar árvore que a versão anterior listava | BA alinha TC-CUV-08 a TC-CUF-06 e registra o teto | Aceita |
| **DIV-225** | Varredura completa: `not_found` da raiz tratado como árvore vazia em QUALQUER página | Só na primeira página; `not_found` num `continue` da própria varredura é erro (antes viraria tabela parcial, e com `--espelhar`, exclusão) | Aceitar (mais seguro) | Aceita |
| **DIV-226** | TC-CUS-03 espera `11` para retrato com `rev`/`content_hash` falsos | No `sync`, resumo divergente no recebimento é falha por item (RF-59): linha `falha ...: integridade`, destino intacto, código `14`, igual ao `sync` sem cursor | BA ajusta TC-CUS-03 para `14` com classe `integridade` | Aceita |
| **DIV-227** | Mudança só de caixa não vem no `continue` (Context7) | Retrato fica com a grafia antiga até a periódica; plano igual pelo casamento sem caixa; só um arquivo local NOVO sob pasta renomeada só na caixa nasce com a grafia antiga | Registrar em RSK-77/78; sem mudança | Aceita |
| **DIV-228** | TC-CUO-08 "nenhum aviso contém `cursor`" | Lido literalmente: avisos dizem "registro de listagem", nunca o valor nem a palavra; campos de saída mantêm os nomes de RF-118(d) | Confirmar a leitura | Aceita |
| **DIV-229** | Varredura completa ignorava `deleted` e substituição arquivo/pasta durante a paginação | Aplica a receita do serviço também na completa (mesmo código do delta) | Aceitar (mudança só em borda; mais correta) | Aceita |
| **DIV-230** | RF-110(a), TC-CUA-01, TC-CUL-12, TC-CUO-01 ainda citam o `download` de pasta | Implementado por DIV-205: o download de pasta não usa o cursor, não mostra os campos e recusa as opções com `2` | BA propaga DIV-205 aos TCs | Aceita (BA propaga) |
| **DIV-231** | DIV-219, `include_deleted` no `continue` | Não confirmável no Context7; tratado como "em dúvida": exclusão não relatada só mantém arquivo local extra até a periódica | Registrar em RSK-78 | Aceita |
| **DIV-232** | RF-111(i) "uma linha de aviso" sem trava | Sem trava saem duas linhas: a da trava (já existente, `lib/cmd`) e "registro de listagem não usado nesta execução: sem a trava do par" | Aceitar ou remover a segunda | Aceita |
| **DIV-233** | DIV-214 B: F-40 só no caminho do `sync` | `verificar` e `--enviar` usam o mesmo enumerador (`dbx_sync_enumerar_remoto`), então também passam a mandar o `continue` sem `limit` e ganham a guarda de laço; `list` e `dbx_cmd_listar_nivel` seguem no backlog | Aceitar | Aceita como mudança de comportamento (PR) |
| **DIV-234** | RF-112(d) equivalência | Conjunto idêntico (testado em 10 cenários, com e sem filtro); a ORDEM das linhas `transferir`/`apagar` pode diferir | Confirmar que a equivalência é de conjunto | Aceita |
| **DIV-235** | Confinamento de `path_lower` e reconhecimento da própria pasta comparam com a raiz dobrada pela localidade do processo (`${raiz,,}`); o servidor dobra Unicode | Raiz com maiúscula fora do ASCII, sob `LC_ALL=C`, pode deixar de casar. Efeito: varredura completa ou retrato não gravável, nunca exclusão | Aceitar (direção segura); registrar junto da RF-54(f) | Aceita |

Divergências de origem anterior, decididas antes da implementação (DIV-204 a DIV-220), estão no registro, seção 2.4, e na memória `2026-10-21-0713-cursor`.

### 8. Ciclo 2 — correções do QA (QA-B7B-01, QA-B7B-02, QA-B7B-03 e O1)

Decisão do Tech Lead na memória `2026-10-21-0713-cursor`.

| Achado | Correção | Arquivo |
|---|---|---|
| **QA-B7B-01** (P1) raiz `/` (API `""`) nunca gravava | `dbx_state_cursor_contexto` aceita remoto vazio; `_dbx_state_cursor_cabecalho_formato` exige só o local não vazio. O campo vazio entra na chave e no cabeçalho, e a reconferência é byte a byte. O `diagnostico` mostra `/` | `lib/state.sh`, `commands/diagnostico.sh` |
| **QA-B7B-02** (P1) entrada da própria pasta listada bloqueava a persistência | `_dbx_sync_entrada` reconhece a raiz pela estrutura: raiz não vazia e `path_lower` igual à raiz sem caixa. `folder` é ignorada sem efeito, na completa e no delta. `deleted` ou `file` com esse caminho reprova o delta (completa: retrato não gravável). Qualquer outra entrada fora da raiz segue o confinamento | `lib/sync.sh` |
| **QA-B7B-03** (P3) `path_lower` do delta sem confinamento | `path_lower` vindo do serviço passa por `_dbx_sync_relativo_seguro`, como o `path_display`. Reprova o delta e marca o retrato da completa como não gravável | `lib/sync.sh` |
| **O1** remédio prometia "substitui" | Novo texto: "remova <arquivo> com rm; enquanto ele estiver ali, o sync --receber deste par faz a varredura completa" | `commands/diagnostico.sh` |
| **Lição dos dublês** | `_servidor` de `cursor_test.sh` passou a devolver a entrada da própria pasta `/r`, como a API real. Os 45 casos anteriores rodam com ela | `tests/integracao/cursor_test.sh` |

**Vermelho antes da correção** (todos no worktree com o código do ciclo 1):
- Unidade: `sync_tabela: qa_b7b_02` (própria pasta) e `qa_b7b_03` (`path_lower`); `cursor_estado: qa_b7b_01` (raiz vazia).
- Integração: `cursor_test: qa_b7b_01` (raiz `/`), `qa_b7b_02` (subpasta `/r/Sub` com `/r/sub`), `qa_b7b_o1` e `cua04`.
- Suíte do QA: `qa_z01`, `z02`, `z03`.
- `sync_tabela: qa_b7b_01` (confinamento com raiz vazia na tabela) já passava: é guarda, não correção.

**Verde depois:** todos os casos acima. Dois erros dos próprios testes novos foram corrigidos antes do verde: o `_apagado` fixo em `/r` no caso da raiz `/`, e a asserção do O1 restrita à linha `cursor=` (o `dbx config --substituir` de outra linha casava).

**O2 — investigado: anterior à 7b, não corrigido (vai ao backlog como F-43, risco RSK-84).** Reprodução sobre a cópia da base `a6b5376`: listagem com `content_hash` X, `files/download` com conteúdo de outro hash e sem `Dropbox-API-Result`. Resultado na base: `estado=0`, arquivo gravado. Causa, igual na base e na branch: `dbx_cmd_receber_arquivo` (`lib/cmd.sh`) confere só contra o `content_hash` do cabeçalho de resultado; sem cabeçalho, `DBX_CMD_INTEGRIDADE=nao_aplicavel` e aceita. `git diff --stat a6b5376 -- lib/cmd.sh lib/http.sh lib/transfer.sh` sai vazio: a 7b não tocou o recebimento. Risco: só se manifesta quando o servidor omite o cabeçalho. Sugestão ao backlog: o `sync` passar o hash da listagem como esperado ao recebimento (RF-55).

**Testes do ciclo 2 (contagem atual no momento do parecer do SD):** `cursor_test` 48, `cursor_estado_test` 13, `sync_tabela_test` 12.

**Mutantes do ciclo 2:** 10 aplicados, 10 mortos (seção 5).

**Execuções obrigatórias do ciclo 2 (dev), todas APROVADAS:**
- `qa_cursor_b7b` 41/41 (versão de 41 casos, z01..z03 verdes; sha256 `f16a365b...b254`, igual ao do QA, arquivo não editado).
- `cursor` 102, `json` 62, `harness` 22, `composicao` 28, `http` 53, `preflight` 35, `tmp_test` 16, `state` 60, `retomada` 132, `sync` 103, `verificar` 17, `diagnostico` 39, `filtros` 58, `comandos` 119, `trava` 82, `espaco` 13, `completar` 17, `cli` 17, `confinamento_remoto` 25, `banda` 34, `identidade_gnustat` 7, `recuperacao` 91, `reter` 84, `qa_` 432.
- `shellcheck`: limpo em `lib/`, `commands/`, `bin/` e nos três testes novos.
- `verificar-remocao-de-casos`: 1872 → 1872, nenhuma redução.

**Veredito do ciclo 2 (TDD):** o parecer do SD não registra veredito explícito para o ciclo 2. As correções têm vermelho antes e verde depois, e o SD não registrou achado novo. **Veredito do Tech Lead (2026-10-21): ciclo 2 aprovado.** As correções de QA-B7B-01..03 e O1 têm vermelho antes e verde depois, 10 mutantes barrados e seleção verde.

## Achados consolidados

| ID | Ciclo | Severidade | Situação |
|---|---|---|---|
| R1 | 1 | Ressalva | Aceita pelo Tech Lead (ordem do ciclo) |
| R2 | 1 | Ressalva | Coberta pelo grupo E do QA (sinais) |
| R3 | 1 | Ressalva | Aberta; F-34 (desempenho, RSK-79) |
| DIV-221 a DIV-235 | 1 e 2 | Divergências | Decididas pelo Tech Lead (seção 7) |
| QA-B7B-01, 02, 03, O1 | 2 | P1, P1, P3, observação | Corrigidos no ciclo 2 (seção 8) |
| O2 | 2 | Defeito anterior à 7b | F-43, RSK-84 |
