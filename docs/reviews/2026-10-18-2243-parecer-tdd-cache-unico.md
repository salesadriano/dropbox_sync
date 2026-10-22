# Parecer de Evidências de Testes (TDD) — Cache único, skip do upload e segredo (fase 3)

## Identificação

- Projeto ou produto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Agent responsável pela alteração: Senior Developer (delegação do Tech Lead, regra 44)
- Agent responsável pela verificação: Senior Developer (gate local, regra 14); validação independente a cargo do QA Expert
- Data da verificação: 2026-10-18
- Ciclo de verificação: 4 (ciclo 1 em 2026-10-18; ciclos 2 a 4 em 2026-10-19 — seções "Ciclo 2", "Ciclo 3" e "Ciclo 4")
- Tipo de alteração: Implementação nova (cache do upload, skip pelo hash remoto, chave canônica, identidade forte) + Refatoração (P3.4) + Remoção de componente (`lib/db`)
- Execução dos gates: local, sem pipeline (suíte completa roda no push para a PR e na pipeline, Regra 8)
- Porte da demanda: **G** (confirmado: remove componente de persistência, muda o contrato de estado local e a autenticação)
- Modo do parecer: Completo
- Branch / worktree: `feature/cache-unico-p3` em `/home/sales/dropbox_api.worktrees/feature-cache-unico-p3`, base `007f3ec`
- Log de prompt: [2026-10-18_2243_cache-unico-p3.md](../prompts/2026-10-18_2243_cache-unico-p3.md)
- Memória transposta (por id, regra 43): `2026-10-18-2243-cache-unico-e-segredo`, `2026-10-18-2243-cache-do-upload` (DIV-26 a DIV-29), `2026-10-18-1745-skip-upload-condicionado`, `2026-10-18-1745-selecao-inclui-auditorias-lib`
- Insumos: [parecer do DBA](2026-10-18-2243-parecer-dba-cache-unico.md); critérios em [escopo-requisitos-e-criterios-de-aceite.md](../requisitos/escopo-requisitos-e-criterios-de-aceite.md) v1.5

## Escopo verificado

- Comando usado para levantar o diff: `git status --short`, `git diff --stat`, `git diff`
- Base de comparação: `HEAD` = `007f3ec` (não há commit da demanda; diff só na árvore de trabalho)

| Arquivo | Tipo de alteração | Camada / módulo | Coberto por teste |
|---|---|---|---|
| `lib/state.sh` | Alterado (reescrito) | adaptador `lib/state` | Sim (`state`, `sync`, `comandos`) |
| `lib/hash.sh` | Alterado (`dbx_hash_identidade`, definição única da identidade forte) | domínio `lib/hash` | Sim (`hash`, `walk`, `state`, `sync`, `comandos`) |
| `lib/walk.sh` | Alterado (registro com a identidade, uma leitura de `stat`) | `lib/walk` | Sim (`walk`, `sync`) |
| `lib/path.sh` | Alterado (`dbx_path_local_canonico`) | domínio `lib/path` | Sim (`path`, `comandos`, `sync`) |
| `lib/auth.sh` | Alterado (RF-63) | adaptador `lib/auth` | Sim (`auth`) |
| `lib/errors.sh` | Alterado (P3.4: publicação por variável) | domínio `lib/errors` | Sim (`errors`, `http`, suíte inteira) |
| `lib/http.sh` | Alterado (P3.4) | adaptador `lib/http` | Sim (`http`, suíte inteira) |
| `lib/db.sh` | **Removido** | — | Sim (auditoria `preflight`: TC-LEG-01) |
| `commands/upload.sh` | Alterado (RF-60, RF-61, RF-62) | comando | Sim (`comandos`) |
| `commands/sync.sh` | Alterado (RF-38, RF-52(a), RF-62(c), sem `lib/db`) | comando | Sim (`sync`, `comandos`) |
| `bin/dbx` | Alterado (ajuda do `sync`, TC-CONTA-04) | entrypoint | Sim (`sync`) |
| `install.sh` | Alterado (sem `sqlite3`) | instalador | Sim (`preflight`: TC-LEG-03) |
| `README.md` | Alterado (cache único, legado `dbx.db*`, aviso RF-52(a)) | documentação de produto | Sim (`sync`: TC-CONTA-04) |
| `tests/unit/state_test.sh` | **Novo** (23 casos) | teste unitário direto | — |
| `tests/unit/cmd_test.sh` | **Novo** (8 casos) | teste unitário direto | — |
| `tests/unit/db_test.sh` | **Removido** (4 casos) | — | — |
| `tests/unit/{hash,walk,path,auth,errors,http,preflight}_test.sh` | Alterados (+4, +2, +3, +4, +3, +2, +5) | testes | — |
| `tests/integracao/comandos_test.sh` | Alterado (+21 novos, 1 reescrito; 91 → 111) | integração | — |
| `tests/integracao/sync_test.sh` | Alterado (+8) | integração | — |
| `tests/integracao/composicao_test.sh` | Alterado (exceção justificada de canal) | auditoria | — |
| `docs/testes/mapa-modulos.md` | Alterado (remoção do `lib/db`, testes novos) | mapa (dono: QA) | — |

- Comportamento alterado e não verificado, com motivo: nenhum. Os arquivos `docs/arquitetura/system-design.md` e `docs/requisitos/*` aparecem no diff mas são do Business Analyst, editados em paralelo nesta rodada; não são deste gate.

## Critérios e seams acordadas

| # | Critério de aceite | Seam sob teste | Origem do acordo | Camada do teste | Coberto |
|---|---|---|---|---|---|
| 1 | TC-SKP-01 — hash remoto igual dispensa, sem chamada de envio, saída `status=dispensado` | `bin/dbx upload` + duplo de `curl` | RF-60(a) | Integração | Sim |
| 2 | TC-SKP-02 — hash diferente envia no modo pedido | idem | RF-60(b) | Integração | Sim |
| 3 | TC-SKP-03 — `--modo overwrite` com a mesma regra | idem | RF-60(c) | Integração | Sim |
| 4 | TC-SKP-04 — remoto ausente envia sem calcular o resumo local | idem (stderr de progresso) | RF-60(d), RF-61(f) | Integração | Sim |
| 5 | TC-SKP-05 — falha do `get_metadata` envia; remoto pasta tenta o envio | idem | RF-60(d), (e) | Integração | Sim |
| 6 | TC-SKP-06/07 — cache válido com remoto alterado/apagado envia; decisão idêntica com e sem cache | idem | RF-60(f) | Integração | Sim |
| 7 | TC-SKP-08 — `--forcar` e `-` sem consulta de comparação | idem | RF-60(g), (h) | Integração | Sim |
| 8 | TC-SKP-09 — `--rev` envia em `update` sem consulta | idem | RF-60(i), DIV-27 | Integração | Sim |
| 9 | TC-UPC-01 — namespace `upload-*`, sem `memoria-*`, RF-48 preservado | `lib/state` + `bin/dbx` | RF-61(a) | Unitário + Integração | Sim |
| 10 | TC-UPC-02/03 — reescrita no mesmo segundo e tamanho, `mtime` restaurado, envia | `lib/hash` (identidade) + `bin/dbx upload` | RF-61(b) | Unitário + Integração | Sim |
| 11 | TC-UPC-04 — `stat` divergente antes/depois não grava | `lib/state`; duplo que altera a origem durante o envio | RF-61(c) | Unitário + Integração | Sim |
| 12 | TC-UPC-05 — `mtime` a menos de 2 s não grava | `lib/state` + `bin/dbx` | RF-61(d) | Unitário + Integração | Sim |
| 13 | TC-UPC-06 — sem cache para `-`, FIFO e arquivo vazio | `lib/state` + `bin/dbx` | RF-61(e) | Unitário + Integração | Sim |
| 14 | TC-UPC-08 — falha de gravação não muda o código de saída | `bin/dbx upload` com estado alheio | RF-61(g) | Integração | Sim |
| 15 | TC-UPC-09 / TC-CONTA-03 — upload não emite `get_current_account` | duplo (argv) | RF-61(h), RF-52(b) | Integração | Sim |
| 16 | TC-UPC-10 — poda: 10.001 com 5 velhos remove 5; 10.000 não remove; acerto renova o carimbo | `lib/state` + `bin/dbx` | RF-61(i) | Unitário + Integração | Sim |
| 17 | TC-UPC-11/12 — envio por sessão grava o hash de `DBX_TRANSFER_CONTENT_HASH`; sem `DBX_TRANSFER_HASH` | `bin/dbx upload` (arquivo esparso > 150 MiB) + auditoria | RF-61(j), F-29 | Integração + Auditoria | Sim |
| 18 | TC-CAN-01 — relativo, absoluto e ligação no mesmo `upload-*` | `lib/path` + `bin/dbx` | RF-62(a) | Unitário + Integração | Sim |
| 19 | TC-CAN-02 — nome do cache sem texto do caminho | `lib/state` | RF-62(b) | Unitário | Sim |
| 20 | TC-CAN-03 — `sync --origem ./x` e `/abs/x` com a mesma memória e o mesmo "par visto" | `bin/dbx sync` | RF-62(c) | Integração | Sim |
| 21 | TC-CAN-04 — canonização sem `$(readlink)` em `lib/` | auditoria | RF-62(d), RNF-24 | Auditoria | Sim |
| 22 | TC-SCR-01 — renovação e troca sem segredo recusadas antes da rede | `lib/auth` + duplo | RF-63(a) | Unitário | Sim |
| 23 | TC-SCR-02 — auditoria de formulário de token com mutação | auditoria sobre `lib/*.sh` | RF-63(b), RSK-27 | Auditoria | Sim |
| 24 | TC-SCR-03 — segredo fora de argv e de log; PKCE ausente | `lib/auth` (casos existentes) + auditoria | RF-63(c), (d) | Unitário | Sim |
| 25 | TC-LEG-01..04 — sem `dbx_db_`; `dbx.db*` intacto; `install.sh` sem `sqlite3`; `unlink` remove os quatro tipos | auditoria + `bin/dbx` | RNF-33, RF-51(f) | Auditoria + Integração | Sim |
| 26 | TC-DEP-01..03 — sem `sqlite3`/`python3` (mutação), preflight sem sondagem, cache funciona com sentinelas no `PATH` | auditoria + `bin/dbx` | RNF-02 | Auditoria + Integração | Sim |
| 27 | TC-EST-01..04 — diretório 0700, arquivos 0600, correção de 0755, alheio recusado como `permissao`, órfãos > 1 dia | `lib/state` + `bin/dbx` | RNF-25, DIV-29 | Unitário + Integração | Sim |
| 28 | RNF-26 — após `upload` e `sync` só `memoria-*` e `upload-*` | `bin/dbx` | RNF-26 | Integração | Sim |
| 29 | TC-MEM-04/05 — travessia completa grava só visitados; parcial preserva o não visitado | `lib/state` + `bin/dbx sync` | RF-38(b) | Unitário + Integração | Sim |
| 30 | TC-MEM-06 — reescrita no mesmo segundo é enviada pelo `sync` | `bin/dbx sync` | RF-38(e), DIV-26 | Integração | Sim |
| 31 | TC-CONTA-02 — sem conta, nenhum `memoria-*` nem `sem-identidade` | `bin/dbx sync` | RF-52(a) | Integração | Sim |
| 32 | TC-CONTA-04 — sem conta, `--espelhar` pede reconhecimento; ajuda e README avisam | `bin/dbx sync`, `dbx help sync`, `README.md` | RF-52(a), DIV-28 | Integração | Sim |
| 33 | RF-42 — corrupção (versão, tipo, chave, truncado, campo não numérico, NUL extra, hash inválido) descarta sem falhar | `lib/state` | RF-42 | Unitário | Sim |
| 34 | TC-TST-05/06 — testes diretos de `lib/state` e `lib/cmd`; remoção do `db_test` | `state_test`, `cmd_test` | RNF-32(d) | Unitário | Sim |
| 35 | P3.4 — sem subshell evitável por requisição, comportamento igual | auditoria do corpo de `_dbx_http_conduzir` + classificação por variável | Delegação do Tech Lead | Unitário + Auditoria | Sim |

- Seams propostas e descartadas, com motivo: injeção de relógio no `lib/state` (para testar a janela anti-corrida sem arquivo real) — descartada: a regra é exercitada com `touch -d` em arquivos reais, sem gancho de teste no produto.

## Análise de 3 abordagens (porte G, itens 2, 3 e 4)

### Item 2 — cache do upload em `lib/state`

| Abordagem | Vantagens | Desvantagens | Impacto arquitetural | Decisão |
|---|---|---|---|---|
| **A. Um `upload-<resumo>` por origem canônica**, registro único NUL, identidade de `lib/hash`, poda pelo `mtime` do próprio arquivo | Custo constante (< 5 ms); concorrência só entre uploads da mesma origem, que gravam o mesmo valor; poda trivial; recomendação U2 do DBA | Um arquivo por origem (exige poda) | Reusa a gravação atômica única do `lib/state`; nenhum componente novo | **Escolhida** |
| B. Um arquivo por conta com todos os uploads (U1) | Um só arquivo | Leitura e regravação O(n) por upload (~210 ms com 10 mil); o último upload concorrente apaga entradas do outro | Mesma do A | Descartada |
| C. Reaproveitar `memoria-*` do `sync` com tripla fictícia | Sem namespace novo | Cria "par visto" e dispensa o reconhecimento de RF-48; ciclo de gravação do `sync` apaga o do upload | Viola RF-61(a) | Descartada |

### Item 3 — skip do upload (RF-60)

| Abordagem | Vantagens | Desvantagens | Impacto arquitetural | Decisão |
|---|---|---|---|---|
| **A. `get_metadata` primeiro; hash local preguiçoso (cache → cálculo) só com remoto arquivo; dispensa só com hash igual** | Restabelece RSK-23; uma requisição a mais e nenhum cálculo quando o remoto não existe; falha da consulta leva ao envio | Uma requisição extra por upload | Decisão no comando; cache segue sem decidir | **Escolhida** |
| B. Sem skip (sempre enviar) | Mais simples, nenhum estado | Descumpre RF-60(a); reenvia arquivos grandes idênticos | — | Descartada |
| C. Decidir por `rev`/cache (sem comparar hash remoto) | Zero requisições extras | É exatamente o `RSK-37`: cache decide; `rev` exigiria estado remoto persistido e vínculo à conta | Viola RF-60(f) e RNF-26 | Descartada |

Decisão acessória: o hash gravado após envio por requisição única é o `content_hash` que o serviço devolve (bytes recebidos), protegido pela dupla leitura de `stat`; por sessão, `DBX_TRANSFER_CONTENT_HASH` (F-29). Sem `content_hash` na resposta, nada é gravado.

### Item 4 — memória do `sync` com identidade forte (RF-38, DIV-26)

| Abordagem | Vantagens | Desvantagens | Impacto arquitetural | Decisão |
|---|---|---|---|---|
| **A. Identidade lida pela travessia** (`lib/walk`, uma leitura de `stat` por arquivo no lugar das duas de antes, pela função única `dbx_hash_identidade` do domínio) e segunda leitura só quando há cálculo; marca de presença para caminhos sem resumo admissível | Menos processos por arquivo que antes; uma única definição de identidade para `sync` e `upload`; RF-41(b) preservado | Muda o segundo campo do registro da travessia (`mtime` → identidade) | `lib/walk` e `lib/state` passam a depender de `lib/hash` (domínio), na direção permitida. A primeira versão punha a definição em `lib/walk` e fazia `lib/state` carregá-lo — dependência contra a direção das camadas, achada e corrigida no gate de conformidade (achado 1 do [parecer de conformidade](2026-10-18-2243-parecer-conformidade-cache-unico.md)) | **Escolhida** |
| B. `stat` dedicado em `lib/state` por arquivo | Não toca `lib/walk` | +1 a +2 processos por arquivo (10 mil arquivos: +10 a +30 s) — o ganho de desempenho da fase seria parcialmente devolvido | Duas definições de identidade | Descartada |
| C. `stat`/`find -printf` em lote | Menos processos | Reconstrói caminho por texto (contraria a descida por nome de RNF-28) e complica nomes com quebra de linha | Fere `lib/walk` | Descartada |

Achado de projeto resolvido em A: com a janela anti-corrida, uma árvore de arquivos recém-criados deixaria a memória vazia e a recusa de RF-41(b) ("origem vazia com memória povoada") nunca dispararia. A memória passa a registrar o caminho com a marca `-` (sem resumo reaproveitável); o caso existente `origem_vazia_com_memoria_povoada_recusa_integralmente` e o novo `caminho_sem_resumo_admissivel_continua_registrado_como_presente` morrem com o mutante M9.

## Evidência do ciclo red-green-refactor

Red comprovado contra o `HEAD` (`007f3ec`, exportado por `git archive` para área temporária fora do worktree, com os testes novos copiados por cima). São **83 casos novos** (54 unitários e de auditoria, 29 de integração). Executados um a um contra o `HEAD`, 55 deles: **37 reprovam** e 18 passam. Dos 28 não executados um a um, 21 são do `state_test.sh`, que no `HEAD` não carrega a API nova (amostra de 2 reprovada; na primeira execução do arquivo, `…identidade: command not found`), e 7 do `cmd_test.sh`, que é caracterização. Dos 18 que passam no `HEAD`, 17 são guardas de regressão e 1 é caracterização (`cmd_test` `falhar_devolve…`); cada guarda foi morta por um mutante plausível do código novo, executado em cópia descartável (seção seguinte).

| # | Fatia vertical | Teste escrito antes? | Evidência do Red (falha observada) | Implementação mínima | Refactor aplicado |
|---|---|---|---|---|---|
| 1 | Identidade forte (definição em `lib/hash`, registro da travessia em `lib/walk`) | Sim | `walk_test` (2/2) e `hash_test` (3/3 funcionais) reprovam no HEAD: função de identidade inexistente | `DBX_HASH_FORMATO_IDENTIDADE`, `dbx_hash_identidade`, registro `tamanho⇥identidade⇥caminho` | Sim: uma leitura de `stat` por arquivo no lugar de duas; definição movida de `lib/walk` para `lib/hash` no gate de conformidade (guarda `identidade_mora_no_dominio…`, morta pelo mutante M21) |
| 2 | `lib/state`: namespaces, identidade, anti-corrida, poda, diretório, corrupção | Sim | `state_test`: função de identidade inexistente (o arquivo reprova inteiro no HEAD; amostra de 2 casos isolados reprovada) | Reescrita de `lib/state.sh` (v2) | Sim: gravação atômica única `_dbx_state_gravar_arquivo` para os dois namespaces |
| 3 | Chave canônica | Sim | `path_test`: `dbx_path_local_canonico: command not found` | `dbx_path_local_canonico` sobre `_dbx_path_resolver_fisico` | Não aplicável |
| 4 | Skip pelo hash remoto e cache do upload | Sim | `comandos_test`: `status=dispensado` ausente (SKP-01/03/07), `upload-*` ausente (UPC-01, CAN-01, UPC-11), `sqlite3` invocado (TC-DEP-03) | `_dbx_cmd_upload_hash_remoto`, `_dbx_cmd_upload_gravar_cache`, remoção do `lib/db` no upload | Sim: mensagens de progresso preservadas (caso existente `upload_com_progresso_analisa_arquivo`) |
| 5 | Memória do `sync` (visitados, identidade, sem conta, chave canônica) | Sim | `sync_test`: 6/7 reprovam no HEAD (`b.txt` permanece; `memoria-*` criado sem conta; raiz relativa pede reconhecimento) | `_dbx_cmd_sync_resumo_local` com identidade, carga/gravação só com conta, `dbx_state_gravar ... completa` | Sim: remoção do segundo nível SQLite |
| 6 | RF-41(b) com janela anti-corrida (marca de presença) | Não para o caso unitário novo (escrito depois); **o critério já tinha caso anterior** (`origem_vazia_com_memoria_povoada`) | Mutante M9 (sem a marca): os dois casos reprovam | Marca `-` em `dbx_state_registrar` e aceita na carga | Não aplicável |
| 7 | Segredo obrigatório | Sim | `auth_test`: renovação e troca sem segredo saem com `0` e chamam a rede; auditoria acusa `lib/auth.sh:197` | Recusa antes da rede; `client_secret` incondicional nos dois formulários | Não aplicável |
| 8 | P3.4 | Sim | `errors_test`: `DBX_ERRORS_CLASSE`/`POLITICA` não publicadas; `http_test`: captura `$(dbx_errors_classificar` em `_dbx_http_conduzir` | Publicação por variável; código de saída pela tabela `DBX_ERRORS_CODIGO` | Sim: nenhuma mudança de saída padrão das funções públicas |
| 9 | Remoção do `lib/db`, legado, instalador, dependências | Sim | `preflight_test`: `db.sh:68: command -v sqlite3`; `lib/db.sh` existe; `install.sh:90` recomenda `sqlite3`; `DBX_TRANSFER_HASH` em `commands/upload.sh` | Remoção de `lib/db.sh` e `db_test.sh`; `install.sh` sem detecção | Não aplicável |
| 10 | Testes diretos de `lib/cmd` | Sim (caracterização) | Antes do arquivo, `bash tests/run.sh cmd_test` reprova ("filtro sem correspondência", TC-TST-06) | Nenhuma (comportamento existente) | Não aplicável |
| 11 | Aviso no `sync` com diretório de estado alheio | Não (escrito depois do aviso) | No HEAD o caso reprova (`o operador e avisado`) | `dbx_output_diagnostico aviso` após `dbx_state_gravar` com `permissao` | Não aplicável |

- Refatorações sem alteração de comportamento externo: P3.4 (`lib/errors.sh`, `lib/http.sh`); `lib/walk.sh` (duas leituras de `stat` viraram uma); identidade movida de `lib/walk` para `lib/hash` (seleção inteira reexecutada depois).

### Casos que passam no HEAD e o mutante que os mata

22 mutantes (M1 a M21 e M4b) aplicados por `sed` em cópia descartável do worktree, nunca no próprio worktree; **todos mortos**. M4 e M4b foram refeitos depois de a identidade mudar para `lib/hash`.

| Mutante | O que reintroduz | Casos que reprovaram |
|---|---|---|
| M1 | falha do `get_metadata` dispensa | `upload_com_remoto_ausente…`, `upload_com_falha_na_consulta…`, `upload_com_remoto_pasta…` |
| M2 | acerto de cache dispensa sem comparar com o remoto | `upload_nao_dispensa_pelo_cache…` |
| M3 | gravação sem a segunda leitura de `stat` | `upload_nao_grava_cache_quando_a_origem_muda…` |
| M4 / M4b | identidade só com `mtime` em segundos / sem inode e dispositivo | `upload_reescrita…`, `sync … reescrita…`, `hash … reescrita…`, `identidade_traz_mtime_e_ctime…`, `registro_da_travessia…` |
| M5 | sem anti-corrida de 2 s | `state … modificado_ha_menos_de_dois_segundos`, `sync_nao_registra…`, `upload_sem_cache_para…` |
| M6 | arquivo vazio cacheado | `state … arquivo_vazio…`, `upload_sem_cache_para…` |
| M7 | `--forcar`/`--rev` consultam | `upload_forcar_e_entrada_padrao…`, `upload_com_rev_envia…` |
| M8 | diretório alheio aceito | `diretorio_de_outro_dono…` |
| M9 | caminho sem resumo some da memória | `caminho_sem_resumo_admissivel…`, `origem_vazia_com_memoria_povoada…` |
| M10 / M11 | gravação ignora "travessia completa" / descarta o não visitado na parcial | `gravacao_completa…`, `travessia_completa…`, `gravacao_parcial…`, `travessia_parcial…` |
| M12 | código de saída fixo no lugar do da classe | `codigo_de_saida_da_requisicao…` |
| M13 | falha do cache muda o código de saída | `upload_falha_ao_gravar…` (após corrigir o caso, que era vácuo: a resposta do duplo não trazia `content_hash` e a gravação nem era tentada) |
| M14 | upload identifica a conta | `upload_nao_identifica_a_conta` |
| M15 | `unlink` deixa o estado | `unlink_remove_memorias…` |
| M16 | chave pelo caminho digitado | `upload_relativo_absoluto…` |
| M17 | canonização por `$(readlink -f)` | `chave_canonica_nao_usa…` |
| M18 | PKCE introduzido | `pkce_nao_e_implementado` |
| M19 | preflight sonda `sqlite3` | `preflight_nao_lista…` |
| M20 | comparação invertida | `upload_envia_quando…`, `upload_dispensa_quando…` |
| M21 | `lib/state` volta a carregar `lib/walk` | `identidade_mora_no_dominio_e_nao_em_quem_a_consome` |

## Execução seletiva por módulo, local (Regra 8)

- Mapa de módulos: [docs/testes/mapa-modulos.md](../testes/mapa-modulos.md)
- Separação em módulos definida?: Automática (o mapa; módulo = arquivo)
- Arquivos do diff sem enquadramento automático: nenhum. `tests/unit/state_test.sh` e `cmd_test.sh` são teste direto de módulos já mapeados (`lib/state`, `lib/cmd`).
- Módulos atingidos diretamente: `lib/state`, `lib/hash`, `lib/walk`, `lib/path`, `lib/auth`, `lib/errors`, `lib/http`, `lib/db` (removido), `commands/upload`, `commands/sync`, `bin/dbx`
- Dependentes diretos incluídos: Regra 1 do mapa (`json`, `http`, `preflight`, `composicao`), `cli` e `composicao` por `commands/*.sh`, e — **porque `lib/errors.sh` mudou** — todos os arquivos, conforme a delegação do Tech Lead ("Se `lib/errors.sh` mudar, rode tudo") e a linha `lib/errors.sh … toda a suíte` do mapa.
- Suíte completa executada durante a demanda, fora do push para a PR?: Não como "suíte completa oficial" (`sh scripts/suite-completa.sh` não foi rodado nem registrado). A seleção ditada pelo mapa para um diff em `lib/errors.sh` coincide com todos os arquivos de `tests/run.sh`.
- Estrutura ou dependência nova adicionada ao mapa: Sim, origem automática (lida do código): `lib/walk` carrega `lib/hash`; `lib/state` chama `lib/config`; `commands/upload` carrega `lib/state` e chama `lib/path`/`lib/hash` (identidade); `commands/sync` chama `lib/path` e `lib/hash`; testes diretos `state` e `cmd`; `qa_integridade` passa a ser selecionado por `lib/state.sh` e `lib/path.sh`; `lib/db.sh` e o teste `db` saem das linhas de `hash`, `config`, `qa_integridade`, `qa_robustez`, `upload` e `sync`; a lacuna "`lib/state` e `lib/cmd` sem teste direto" foi fechada.

| Módulo (filtro) | Motivo da seleção | Comando | Total | Aprovados | Falhos | Duração |
|---|---|---|---|---|---|---|
| todos os 24 arquivos | `lib/errors.sh` no diff (mapa: "toda a suíte") | `bash tests/run.sh < /dev/null` | 840 | 838 (+2 pulados) | 0 | 116 s |

Contagens literais por arquivo da execução final: `auth` 39, `cabecalho` 17, `cli` 17, `cmd` 8, `config` 40, `errors` 80, `harness` 22, `hash` 44, `hash_vetor_oficial` 0 (2 pulados: vetor oficial exige rede), `http` 53, `json` 60, `output` 30, `path` 47, `preflight` 30, `progress` 16, `qa_rede_p2` 25, `state` 23, `transfer` 36, `walk` 13, `comandos` 111, `composicao` 24, `qa_integridade_p1` 27, `qa_robustez_rede_p2` 20, `sync` 56.

## Suíte completa no push para a PR e na pipeline de main/master (Regra 8)

- Execução local no push para a PR: ainda não houve push para a PR (fora do escopo do Senior Developer nesta delegação).
- Branch de integração do projeto: `develop` declarada na memória `branch-principal`; a PR vai para `develop`.
- Workflow e job que rodam a suíte completa: não verificado nesta delegação (sem rede, sem alteração de pipeline).
- Estado no momento do parecer: Ainda não executada (PR não aberta).

## Execução por camada

- Comando oficial de execução isolada: `bash tests/run.sh` (oficial da suíte: `sh scripts/suite-completa.sh`)
- Tecnologia suporta execução em container?: Não há container no projeto (CLI em shell; dependência única `curl`). Limitação registrada, sem achado.
- Comando efetivamente executado: `bash tests/run.sh < /dev/null` e casos isolados por `bash tests/<arquivo> <caso>` com o ambiente do executor (para o red por caso e os mutantes)
- Divergência em relação ao comando oficial: nenhuma na execução final.
- Banco real da stack usado na integração: não aplicável — não há banco; o `lib/db` (SQLite) foi justamente removido. A persistência é arquivo local, exercitada em sistema de arquivos real.
- Ferramenta de E2E: não aplicável (sem interface web); a camada ponta a ponta é `bin/dbx` real contra duplo de `curl` (sem rede, RNF-14).

| Camada | Comando | Total | Aprovados | Falhos | Ignorados | Não executados por interrupção | Duração |
|---|---|---|---|---|---|---|---|
| Unitário (`tests/unit`, 19 arquivos) | `bash tests/run.sh` | 602 | 600 | 0 | 2 | 0 | não medida por camada |
| Integração (`tests/integracao`, 5 arquivos) | `bash tests/run.sh` | 238 | 238 | 0 | 0 | 0 | não medida por camada (execução única: 116 s) |
| E2E | — | — | — | — | — | — | Não aplicável: sem interface |

- Falhas em aberto: nenhuma.

## Interrupção no primeiro erro (Regra 9)

- Parada no primeiro teste falho: nativa do harness (`Bail out!`) e do executor (para no primeiro arquivo), sem opção de desligar (RNF-32(a)).
- Módulos e camadas em sequência, sem iniciar o seguinte após erro?: Sim
- Código de saída propagado até o fim?: Sim
- Job da pipeline: não verificado nesta delegação.
- Execução final concluída sem interrupção?: Sim

| # | Camada | Módulo | Teste | Arquivo:linha | Tipo de erro | Mensagem (sanitizada) | Comando | Não executados | Correção e reexecução do início |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Unitário | `json` | `massa_adversarial_nao_e_construida_por_substituicao_de_comando` | `tests/unit/state_test.sh:372` | Asserção | massa construída por `$(printf …)` | `bash tests/run.sh` | 13 arquivos | `printf -v`; reexecução do início |
| 2 | Integração | `composicao` | `canal_publico_alheio_com_dado_de_credencial_e_limpo_por_quem_o_encheu` | `lib/http.sh` (lê `DBX_ERRORS_CLASSE`/`POLITICA`) | Asserção | canal alheio sem limpeza | `bash tests/run.sh` | 3 arquivos | Exceção justificada (vocabulário fechado da taxonomia) em `composicao_test.sh`; reexecução do início |
| 3 | Integração | `comandos` | `upload_com_progresso_analisa_arquivo_e_emite_resultado` (caso existente) | `commands/upload.sh` | Asserção | mensagem "analisando arquivo local" ausente | `bash tests/run.sh comandos` | 34 casos | Mensagens de progresso preservadas; reexecução |
| 4 | Integração | `composicao` | `contagem_sobre_arquivo_passa_pelo_auxiliar` | `tests/unit/hash_test.sh:668` | Asserção | contagem com `grep -c` fora de `_harness_contar` | `bash tests/run.sh` | 3 arquivos | `_harness_contar`; reexecução do início |

## Distribuição da pirâmide

Conjunto entregue (83 casos novos): 54 unitários e de auditoria (state 23, cmd 8, preflight 5, auth 4, hash 4, path 3, errors 3, walk 2, http 2) e 29 de integração (comandos 21, sync 8) — 65/35/0. Removidos: 4 de `db_test.sh` e 1 de `comandos_test.sh` (reescrito).

| Camada | Alvo | Real entregue | Desvio justificado? | Justificativa |
|---|---|---|---|---|
| Unitário | 70% | 65% | Sim | Os critérios RF-60 e RF-52(a) são de comando (decisão com `get_metadata`, saída, código), e a única forma real de prová-los é `bin/dbx` contra o duplo de rede |
| Integração | 20% | 35% | Sim | Idem |
| E2E | 10% | 0% | Sim (não aplicável) | Projeto CLI sem interface; a camada ponta a ponta é a integração por `bin/dbx` |

## Verificação das proibições por camada

| Verificação | Camada | Resultado | Evidência |
|---|---|---|---|
| Teste unitário isolado de rede e banco | Unitário | Conforme | `state_test`, `hash_test`, `walk_test`, `path_test` usam só sistema de arquivos; `auth_test`/`cmd_test` usam duplo de `curl` no `PATH` |
| Teste pela interface pública | Unitário | Conforme | `dbx_state_*`, `dbx_hash_identidade`, `dbx_path_local_canonico`, `dbx_cmd_*`; o único acesso a interno é `DBX_STATE_ENTRADA`, canal público documentado |
| Padrão AAA e nome que descreve comportamento | Unitário | Conforme | Nomes como `poda_no_teto_nao_remove_nada` |
| Banco real via Testcontainers | Integração | Não aplicável | Sem banco no produto |
| Ausência de mock da camada de dados | Integração | Conforme | Estado gravado e lido em disco real (`XDG_STATE_HOME` por cenário) |
| Contrato HTTP verificado na fronteira real | Integração | Conforme (limitado) | Duplo de `curl` registra argv, opções e URLs; sem rede por RNF-14 |
| Fluxo principal contra frontend, backend e banco reais | E2E | Não aplicável | Sem interface |
| Ausência de `cy.intercept()` | E2E | Não aplicável | Sem interface |
| Jornada de negócio completa | E2E | Não aplicável | — |
| Cada critério com cenário correspondente | Integração | Conforme | Tabela de critérios acima |

## Governança de dados de teste

| Item | Resultado | Evidência |
|---|---|---|
| Dado originado de criação programática | Conforme | Cada caso cria arquivos, credencial sintética e duplo no próprio roteiro |
| Ausência de dado manual e de ID adivinhado | Conforme | Hashes calculados por `dbx_hash_conteudo_arquivo`; nomes de cache derivados pela API |
| Estado preservado entre cenários relacionados | Conforme | Jornadas encadeadas no mesmo caso (ex.: dispensa → remoto alterado → apagado → sem cache) |
| Teardown apenas ao final | Conforme | Área do executor removida ao fim (`DBX_TESTES_TMP`) |
| Dado sintético, sem segredo real | Conforme | `ak`/`as`/`rt`, `sl.t`, hashes fictícios |

## Resiliência E2E e tratamento de flaky

| Item | Resultado | Evidência |
|---|---|---|
| Seletores `data-cy`/`data-test` | Não aplicável | Sem interface |
| Ausência de seletor por classe de estilo | Não aplicável | Sem interface |

| Cenário | Execuções (resultado de cada uma) | Causa raiz identificada | Correção aplicada | Status |
|---|---|---|---|---|
| `reescrita_no_mesmo_segundo_com_mesmo_tamanho_muda_a_identidade` (hoje em `hash_test`) | 1ª: reprovou (identidades iguais); depois da correção, 10 execuções seguidas aprovadas | Duas escritas no mesmo tique do relógio grosso de carimbos do núcleo recebem o mesmo `ctime` (medido: `ctime` idêntico até o nanossegundo) | Espera por **condição** (`_esperar_tique_do_ctime`: sonda até o `ctime` avançar), sem tempo fixo; mesma espera nos casos equivalentes de `comandos` e `sync` e no duplo que altera a origem durante o envio | Corrigido |

- Houve `sleep` fixo, retry cego ou quarentena?: Não.

## Testes de segurança e acesso (Regra 6 do protocolo)

- Gatilhos considerados: autenticação | dado sensível | arquivo | entrada maliciosa | estado hostil
- Gatilhos tocados: segredo do aplicativo (RF-63); arquivos de estado com caminhos absolutos (dado sensível); permissão de diretório; ligação simbólica na chave canônica; estado corrompido ou hostil.

| # | Gatilho | Cenário negativo | Ator ou entrada usada | Resultado esperado | Camada | Contra componente real | Resultado |
|---|---|---|---|---|---|---|---|
| 1 | Segredo | Renovação sem `client_secret` | credencial sem segredo | código de uso, zero chamadas de rede, motivo sem valor | Unitário | Sim (`lib/auth`, duplo de `curl`) | Aprovado |
| 2 | Segredo | Troca de código sem segredo | `app_secret` vazio | idem, código de uso de uma vez não ecoado | Unitário | Sim | Aprovado |
| 3 | Segredo | Ramo "sem segredo" reintroduzido em forma não óbvia | 4 mutações (`+=` condicional, `${s:+…}`, omissão, `${s:-}`) | auditoria acusa as 4 e absolve a forma correta | Auditoria | Sim | Aprovado |
| 4 | Segredo | Segredo em argv/log | casos existentes `segredo_e_codigo_nao_aparecem…` | ausente | Unitário | Sim | Aprovado |
| 5 | Permissão | Diretório de estado de outro dono | `dbx` → `/usr` (root) | `permissao`, nada lido nem escrito, modo e `mtime` de `/usr` intactos, `VISTO=nao` | Unitário + Integração | Sim (sistema de arquivos real) | Aprovado |
| 6 | Permissão | Diretório existente 0755 do usuário | `chmod 755` | corrigido para 0700 na gravação | Unitário | Sim | Aprovado |
| 7 | Dado sensível | Diretório criado com `umask 022` | primeira gravação | 0700; arquivos 0600 | Unitário + Integração | Sim | Aprovado |
| 8 | Arquivo / estado hostil | Registro do upload corrompido | versão, tipo, chave, truncado, hash inválido, campo de texto, NUL extra | descartado, sem falha, reconstruído na gravação seguinte | Unitário | Sim | Aprovado |
| 9 | Arquivo / estado hostil | Memória do `sync` com registro hostil | hash fora do formato, identidade inválida, caminho `../` | só o bem formado entra; nenhum é usado para abrir arquivo | Unitário | Sim | Aprovado |
| 10 | Arquivo / estado hostil | Diretório no lugar do registro | `upload-<resumo>/` | gravação falha, nada movido para dentro, sem temporário | Unitário | Sim | Aprovado |
| 11 | Entrada maliciosa | Chave com quebra de linha e `../` | `/home/u/segredo\n../../nome.txt` | nome `upload-` + 32 hex, sem texto do caminho | Unitário | Sim | Aprovado |
| 12 | Ligação simbólica | Ligação no último componente e no meio, com `..` | `atalho.txt`, `pasta/../pasta/a.txt` | mesma chave física; sem `$(readlink)` | Unitário + Integração | Sim | Aprovado |
| 13 | Arquivo | Origem alterada durante o envio | duplo reescreve a origem (mesmo tamanho, `mtime` restaurado) | nenhum registro gravado | Integração | Sim | Aprovado |
| 14 | Dado sensível | Legado `dbx.db*` com caminhos absolutos | três arquivos sentinela | conteúdo e `mtime` intactos; `unlink` remove | Integração | Sim | Aprovado |

- Cenários do catálogo não implementados para gatilho tocado: nenhum.
- Resposta, log e evidência sem segredo: Sim (motivos de recusa nomeiam a falta, não valores; o aviso de diretório alheio passa por `dbx_output_diagnostico`, com redação).

## Validação de formulários em E2E (Regra 7 do protocolo)

Não aplicável: a alteração não toca interface com entrada de dados.

## DoD bloqueante para handoff ao QA

| # | Item | Resultado | Evidência |
|---|---|---|---|
| 1 | TDD aplicado, unidade e integração aprovados | Atendido | 37 reds isolados contra o HEAD e o `state_test` inteiro reprovando no HEAD; 22 mutantes mortos; 838 aprovados |
| 2 | Execução isolada com o comando oficial | Atendido | `bash tests/run.sh`; sem container por natureza do projeto |
| 3 | Cobertura E2E dos critérios | Não aplicável | Sem interface; critérios cobertos por `bin/dbx` |
| 4 | Cenários negativos de segurança | Atendido | 14 cenários acima |
| 5 | Cenários de formulário | Não aplicável | — |
| 6 | Execução seletiva aprovada | Atendido | 24 arquivos, 0 falhas (seleção = tudo, por `lib/errors.sh`) |
| 7 | Parada no primeiro erro e execução final sem interrupção | Atendido | 4 interrupções registradas, reexecutadas do início |

## Limitações do ambiente

| Recurso ausente | Impacto na verificação | Achado registrado |
|---|---|---|
| Testcontainers / banco | Nenhum: não há banco no produto | Não |
| Runner E2E web | Nenhum: não há interface | Não |
| GNU coreutils (ambiente com uutils 0.8.0) | `%y`/`%z` medidos aqui; `%.9Y` descartado por arredondar os nanossegundos no uutils. O formato textual é o mesmo no GNU, mas não foi executado nele | Não (registrado como risco RSK-43 para o QA) |
| Execução como root | Casos de permissão pulam como root (`pular`) | Não |

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correção esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 | `tests/unit/state_test.sh` (`caminho_sem_resumo_admissivel…`) e `tests/integracao/sync_test.sh` (`diretorio_de_estado_alheio…`) | Dois casos escritos depois do código que verificam; o critério do primeiro (RF-41(b)) já tinha caso anterior, e o segundo cobre um aviso acrescentado por desenho. Red demonstrado por mutante (M9) e contra o HEAD | `protocolo-tdd / Regra 1 - Ciclo TDD` | Nenhuma além do registro | Menor | Justificado |
| 2 | `tests/integracao/comandos_test.sh` (`upload_falha_ao_gravar…`) | O caso era vácuo na primeira versão (sem `content_hash` na resposta, a gravação não era tentada); o mutante M13 sobreviveu | `protocolo-tdd / Regra 6` | Resposta com `content_hash` | Menor | Corrigido |

- Total de bloqueantes: 0
- Total de maiores: 0
- Total de menores: 2

## Veredito

- Resultado: **Aprovado**
- Justificativa objetiva: os 35 critérios da fase têm caso; 37 reprovam isolados no HEAD (mais o `state_test`, que não carrega no HEAD), 17 guardas foram mortas por mutante e 1 caso é caracterização; os cenários negativos da Regra 6 estão presentes e aprovados contra o sistema de arquivos real; a seleção do mapa (tudo, porque `lib/errors.sh` mudou) terminou sem interrupção com 838 aprovados, 0 falhos e 2 pulados (vetor oficial que exige rede).
- Ressalvas registradas, com owner e prazo: nenhuma deste gate. Riscos para o QA no relatório de handoff: formato de `stat` não executado em GNU coreutils (RSK-43).
- Handoff liberado?: Sim
- Gate de conformidade liberado para execução?: Sim
- Próximo passo do ciclo do developer: [parecer de conformidade](2026-10-18-2243-parecer-conformidade-cache-unico.md); em seguida registro de entrega (`documentation-writer`) e validação independente do QA. A remoção dos 4 casos de `tests/unit/db_test.sh` precisa do trailer `Remocao-de-casos: tests/unit/db_test.sh 4` no commit (o guarda `scripts/verificar-remocao-de-casos.sh` já acusa a redução como não declarada).

## Ciclo 2 — exclusão desabilitada sem identidade de conta (devolução do Tech Lead, 2026-10-19)

- Origem: risco apontado no relatório do ciclo 1 (sem conta não há memória, e sem memória a recusa de RF-41(b) não protege), classificado pelo Tech Lead como **bloqueante** (RF-41, P0). DIV-28 revista na memória `2026-10-18-2243-cache-do-upload`: sem identidade de conta, com `--espelhar`, a exclusão fica **desabilitada** naquela execução, com a semântica de RF-41(a), nos dois sentidos; envio e recebimento seguem; motivo no relatório e na saída estruturada; código de saída ≠ 0; `--confirmar` não reabilita.
- Arquivos: `commands/sync.sh`, `bin/dbx` (ajuda do `sync`), `README.md`, `tests/integracao/sync_test.sh` (+3 casos, 1 caso existente reforçado).

| # | Critério | Teste | Red contra o HEAD | Red contra o ciclo 1 | Resultado |
|---|---|---|---|---|---|
| C2-1 | Rotina com `--espelhar --confirmar`, origem vazia, conta não identificada: zero exclusões, saída ≠ 0, `exclusao_desabilitada=` na saída | `sem_conta_origem_vazia_com_confirmar_nao_apaga_nada` | Reprova (1 exclusão) | Reprova (1 exclusão) | Aprovado |
| C2-2 | Mesma rotina com a origem povoada: a transferência acontece, zero exclusões, saída ≠ 0 | `sem_conta_origem_povoada_transfere_e_nao_apaga` | Reprova | Reprova | Aprovado |
| C2-3 | Sentido `--receber --espelhar`: o recebimento acontece, o arquivo só local fica, saída ≠ 0 | `sem_conta_receber_espelhar_nao_apaga_local` | Reprova | Reprova (arquivo local apagado) | Aprovado |
| C2-4 | Ajuda do `sync` e README descrevem o comportamento novo | `sem_identidade_de_conta_espelhar_pede_reconhecimento_e_a_ajuda_avisa` (reforçado) | — | Reprova antes do texto novo | Aprovado |

- Mutantes: **M22** (`--confirmar` reabilita a exclusão sem conta) — os três casos C2 reprovam; **M23** (exclusão desabilitada só no sentido `enviar`) — C2-3 reprova. Ambos mortos.
- Execução seletiva pelo mapa (diff em `commands/sync.sh` e `bin/dbx`; `lib/` intocado): `sync` 59, `comandos` 111, `cli` 17, `composicao` 24, `qa_robustez` 20 — **231 aprovados, 0 falhos**, 44 s, sem interrupção. `shellcheck` oficial e do teste alterado: 0 achados.
- O reconhecimento de RF-48 continua valendo: sem `--confirmar`, a primeira execução com `--espelhar` segue recusada antes de qualquer escrita.
- Achados do ciclo 2: nenhum. Veredito do ciclo 2: **Aprovado**.

## Ciclo 3 — reprovação do QA (ciclo 1 do QA, [validação](2026-10-18-2243-validacao-qa-cache-unico.md))

Os arquivos `qa_*` não foram alterados; os casos vermelhos deles são o critério.

| Achado do QA | Correção | Testes (red) | Status |
|---|---|---|---|
| QA-P3-01 (bloqueante, segurança): memória que existe e é descartada na carga mantém `VISTO=sim` com base vazia; `--espelhar` sobre origem vazia apagava o destino | `lib/state.sh`: canal `DBX_STATE_DESCARTADA` (fica `sim` em todo ramo de descarte e só a carga válida o limpa). `commands/sync.sh`: com `--espelhar`, motivo `memoria descartada` em `exclusao_desabilitada`, exclusão desabilitada, `nao_concluida` no fim; a memória é regravada em v2 e a execução seguinte volta ao normal (decisão do Tech Lead, memória `2026-10-18-2243-cache-do-upload`) | `qa_exclusao_memoria_descartada_com_origem_vazia_nao_apaga` (v1 e truncada) e o caso novo `memoria_descartada_desabilita_a_exclusao_e_a_seguinte_volta_ao_normal` (reprova no HEAD: 1 exclusão) | Corrigido |
| QA-P3-02 (maior): sem segredo, código 2 na biblioteca e 10 sem motivo no `upload` | `lib/auth.sh`: recusa na classe `configuracao` (3), constante `DBX_AUTH_ERRO_CONFIGURACAO`; nova `dbx_auth_preparar` publica a classe da falha (`DBX_AUTH_CLASSE`); `upload` e `sync` a chamam antes da primeira chamada que falha em silêncio por desenho e recusam com classe e motivo. Comentário de `lib/config.sh` corrigido | `qa_segredo_ausente_recusa…`, `qa_auth_sem_segredo…`; casos novos `upload_com_segredo_vazio…` e `sync_com_segredo_vazio…` (reprovam no HEAD). **Mudança declarada:** `auth_test` `renovacao_sem_segredo…` e `troca_de_codigo_sem_segredo…` passam a afirmar 3 (afirmavam 2) | Corrigido |
| QA-P3-03 (maior, pré-existente): `$?` lido dentro de `if !` | Status capturado antes do teste | `qa_p34_falha_de_rede…`; caso novo `enumeracao_remota_que_falha_sai_com_o_codigo_da_classe` (403; reprova no HEAD com saída 0) | Corrigido |
| QA-P3-04 (menor): README com "cache SQLite" | Texto do `--progresso` corrigido | `qa_legado_install_readme…` | Corrigido |

- Mutantes do ciclo 3, todos mortos: **M24** (memória descartada não desabilita a exclusão) — o caso novo e o do QA reprovam; **M25** (a marca de descarte persiste na execução seguinte) — o caso novo reprova; **M26** (status lido de novo dentro de `if !`) — o caso de enumeração reprova; **M27** (sem a recusa prévia de token em `upload` e `sync`) — os dois casos novos e o do QA reprovam; **M28** (segredo ausente volta a `uso_invalido`) — os dois casos do `auth_test` reprovam.
- Execução: `lib/errors.sh` continua no diff, então rodei tudo, além de `bash tests/run.sh qa_cache` (23 aprovados) e `bash tests/run.sh qa_state` (8 aprovados). Resultado: `bash tests/run.sh` com **26 arquivos, 876 aprovados, 0 falhos, 2 pulados** (vetor oficial), em 118 s, sem interrupção. Contagens dos arquivos alterados: `sync` 62, `comandos` 112, `auth` 39. Uma interrupção durante o ciclo: `composicao` `canal_publico_alheio…` acusou a primeira versão do auxiliar em `lib/cmd`, que lia `DBX_AUTH_MOTIVO` sem limpá-lo; a classe passou a ser publicada pelo próprio `lib/auth` (`dbx_auth_preparar`), `lib/cmd` voltou ao HEAD, e a reexecução foi do início.
- `shellcheck` oficial: 0 achados.
- Achados do ciclo 3: nenhum novo. Veredito do ciclo 3: **Aprovado**.

## Ciclo 4 — reprovação do QA (ciclo 2 do QA): guarda de origem vazia sem memória

Base: decisão do solicitante na memória `2026-10-18-2243-guarda-origem-vazia` (RF-41(b) emendado) e o complemento do Tech Lead sobre a simulação (RF-44). Os arquivos `qa_*` não foram alterados.

| Item | Correção | Testes (red contra o HEAD) | Status |
|---|---|---|---|
| Guarda sem memória (QA-P3-05) | `commands/sync.sh`: com `--espelhar`, origem vazia (`--enviar`: raiz local sem arquivo; `--receber`: listagem remota vazia) e algo a apagar no destino → plano emitido com `recusada=origem vazia` e nenhuma exclusão listada, depois recusa `nao_concluida`, antes de qualquer escrita, dependa ou não da memória. Só `--permitir-origem-vazia` (opção nova) libera; `--confirmar` não. A guarda antiga, que dependia da memória, também passa a ceder só a essa opção. Ajuda do `sync` e README documentam | `origem_vazia_com_algo_a_apagar_e_recusada_em_toda_combinacao` (2 sentidos × memória válida, descartada, ilegível e ausente × com e sem `--confirmar`), `…traz_o_motivo_mesmo_com_confirmar`, `permitir_origem_vazia_libera_a_exclusao_nos_dois_sentidos` — reprovam no HEAD. `origem_vazia_com_destino_vazio_nao_e_recusada` passa no HEAD (guarda contra recusa indevida) | Corrigido |
| Simulação (complemento do Tech Lead) | Com `--dry-run`, o plano anuncia `recusaria=origem vazia`, não lista exclusão e sai com 0; com `--permitir-origem-vazia`, lista as exclusões | `simulacao_com_origem_vazia_anuncia_a_recusa…`, `simulacao_com_permitir_origem_vazia_lista…` — reprovam no HEAD | Corrigido |
| QA-P3-06 | A memória só é gravada depois de travessia **completa**; com travessia parcial nada é gravado | `travessia_parcial_nao_regrava_a_memoria` — reprova no HEAD e no ciclo 3 | Corrigido |
| QA-P3-07 | `lib/state.sh`: memória do usuário que existe e é ilegível (ou não é arquivo regular) conta como descartada (`VISTO=sim`, `DESCARTADA=sim`). Arquivo ou alvo de ligação de outro dono continua não lido e sem provar execução, como afirma `qa_state_registro_como_ligacao_simbolica…`, que reprovou na primeira versão desta correção e determinou o recorte | `memoria_existente_e_ilegivel_conta_como_descartada` (unitário) | Corrigido |

- **Mudança declarada:** `sem_conta_origem_vazia_com_confirmar_nao_apaga_nada` (ciclo 2) troca a afirmação de `exclusao_desabilitada` pela recusa da guarda de origem vazia. Zero exclusões e saída ≠ 0 continuam afirmadas.
- Critério do QA: `qa_exclusao_memoria_descartada_com_origem_vazia_segunda_execucao_nao_apaga`, `…com_travessia_parcial_nao_regrava_base_vazia` e `qa_exclusao_memoria_ilegivel_com_confirmar_nao_apaga` estão verdes. Também passa `qa_exclusao_origem_vazia_sem_conta_nos_dois_sentidos…`, que exige o motivo no plano: ele motivou a emissão do plano antes da recusa.
- Mutantes, todos mortos:
  - M29: `--confirmar` libera a origem vazia.
  - M30: a guarda volta a depender da memória. Morre no caso da matriz e no caso de duas execuções do QA.
  - M31: a travessia parcial volta a gravar.
  - M32: o arquivo ilegível volta a contar como ausente. Morre no caso unitário.
  - M33: a simulação lista exclusões.
  - M34: só o plano sai, sem a recusa.
- Os casos do QA que sobrevivem a M30, M31 e M32 sobrevivem porque estão protegidos por outra camada (RF-41(f), ou a guarda nova na execução seguinte). É a defesa em profundidade pedida no item 4. Os casos deste parecer matam os três mutantes.
- Execução: `bash tests/run.sh` deu **26 arquivos, 890 aprovados, 0 falhos e 2 pulados**, em 147 s, sem interrupção na execução final. Isso inclui `qa_cache` (29) e `qa_state` (8); `sync` deu 69 e `state` 24. Houve duas interrupções no ciclo, ambas reexecutadas do início:
  - `qa_state` acusou o recorte de arquivo alheio na memória ilegível;
  - `qa_cache` acusou o motivo ausente na recusa.
- `shellcheck` oficial: 0 achados.
- Achados novos do ciclo 4: nenhum. Veredito: **Aprovado**.

## Registro

- Decisões duráveis desta implementação para o Tech Lead avaliar como entrada de memória (`escopo: projeto`, `ref:` para este parecer): marca de presença `-` na memória do `sync` para preservar RF-41(b) sob a janela anti-corrida; identidade definida uma única vez em `lib/hash` (domínio); hash gravado após requisição única vem da resposta do serviço.
- Este parecer é referenciado pelo [parecer de conformidade](2026-10-18-2243-parecer-conformidade-cache-unico.md) e pelo registro de entrega da demanda.
