# Sync em ciclos: orfaos apagados so ao fim da execucao

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "ajuste o processo para só apagar os orfãos quando o processo concluir" (com a saida `--debug` do `sync --enviar --espelhar --confirmar`, `DBX_BLOCO=1000`) |
| Porte | M: muda o comportamento destrutivo do `--espelhar` e toca a fronteira com nome vindo do destino (Regra 6) |
| Log de prompt | `docs/prompts/2026-11-11_2210_sync-orfaos-no-fim.md` |
| Issues | nenhuma |
| Branch / base | `feature/sync-orfaos-no-fim` sobre `origin/develop` @ `03b225f` |
| Agents | Tech Lead, Senior Developer, QA Expert |
| Data | 2026-11-11 |

## 2. Causa ou decisao

- **Causa do relato:** o diagnostico do solicitante (Prompts 2 a 5 do log) mostrou que os itens marcados `a apagar` eram orfaos reais. A pasta `ACRELÂNDIA/2ANA_03042024` foi movida na origem para `ACRELÂNDIA/FNDE/REFOR_ESC_RITA_BOCALOM/2ANA_03042024`. A exclusao por ciclo apagava a copia antiga (`2ANA...`) num ciclo anterior ao envio da nova (`FNDE/...`). No intervalo, o conteudo nao existia no destino. Isso explica tambem a ressalva da demanda `sync-ciclos-exclusao-indevida`.
- **Decisao do solicitante:** nenhuma exclusao de orfao dentro do ciclo. Os orfaos saem depois do ultimo ciclo, so com todos concluidos sem falha, e cada candidata e reconferida contra a origem completa. Entrada `2026-11-11-2210-orfaos-no-fim`.
- **Implementacao (`commands/sync.sh`):**
  - `_dbx_cmd_sync_orfaos_acumular` guarda as candidatas e as chaves da origem de cada ciclo em `$area` (temporario da execucao).
  - `_dbx_cmd_sync_orfaos_apagar` roda depois do ultimo ciclo e antes de `_dbx_cmd_sync_pastas_orfas_apagar`. Ela usa a mesma trava das pastas (`pastas_bloqueio`, ciclo falho, travessia parcial), reconfere cada candidata contra a origem, aplica de novo os filtros e envia as exclusoes por `delete_batch` com a rev lida na execucao.
  - Em `--dry-run`, as candidatas sao anunciadas como `apagaria=` no fim.
- **Robustez:** toda dobra de caixa de chave de diretorio (`commands/sync.sh`, `lib/sync.sh`, `lib/walk.sh`) passa por `dbx_filtro_chave`. Antes, `${x,,}` usava a localidade do processo. Nao e a causa do relato, porque o solicitante usa `C.UTF-8`.
- **Mantido:** a exclusao antecipada do arquivo no lugar de uma pasta (F-103) continua dentro do ciclo, porque e pre-condicao para criar a pasta.

## 3. Arquivos

| Arquivo | Alteracao |
|---|---|
| `commands/sync.sh` | acumulacao e exclusao final dos orfaos, trava comum, dobra unica, `unset` seguro (QA-ORF-01, inclusive em `_dbx_cmd_sync_ciclo_remoto_formar`, anterior a demanda) |
| `lib/sync.sh`, `lib/walk.sh` | dobra de caixa por `dbx_filtro_chave` |
| `tests/integracao/sync_orfaos_no_fim_test.sh` | novo, 10 casos (Senior Developer, TDD) |
| `tests/integracao/qa_sync_orfaos_no_fim_test.sh` | novo, 12 casos (QA) |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | `RF-190(h)`, emenda em `RF-216`, `RF-217(e)` |
| `docs/testes/inventario-de-testes.md`, `docs/testes/mapa-modulos.md` | dois arquivos novos |
| `.github/agents/memoria/entradas/` | decisao `2026-11-11-2210-orfaos-no-fim` e aceite `2026-11-11-2210-aceite-testes-qa-sync-orfaos-no-fim` |

## 4. Testes rodados

- **TDD (Senior Developer):** os casos da ordem de exclusao, da caixa fora do ASCII e do `--dry-run` reprovam sobre `origin/develop`.
- **Execucao atual** (`bash tests/run.sh <basename>`, um por vez, depois das correcoes do Tech Lead), todos com 0 reprovados:

  | Arquivo | Aprovados |
  |---|---|
  | `sync_orfaos_no_fim` (os dois arquivos) | 22 |
  | `sync_test.sh` | 106 |
  | `estrutura_pastas` | 108 |
  | `sync_blocos_test.sh` | 42 |
  | `qa_sync_blocos_b21_test.sh` | 25 |
  | `cursor_test.sh` | 55 |
  | `sync_ciclos_memoria_test.sh` | 6 |
  | `qa_sync_ciclos_memoria_f101_test.sh` | 6 |
  | `json_test.sh` | 66 |
  | `harness_test.sh` | 23 |
  | `composicao_test.sh` | 28 |

- **Lint e inventario:** `sh scripts/lint.sh commands/sync.sh lib/sync.sh lib/walk.sh` sai 0. `sh scripts/inventario-de-testes.sh --check` da 130 arquivos, 3089 casos e 0 divergencias.
- **Suite completa local no push para a PR:** ainda nao houve push para a PR.

## 5. Gates

| Gate | Achados | Veredito |
|---|---|---|
| `protocolo-tdd` | red registrado antes do green; piramide sem mudanca (integracao com duble de `curl`, padrao do projeto) | Aprovado |
| `protocolo-conformidade` | Tech Lead, na revisao: a exclusao final ignorava o bloqueio de ciclo posterior com exclusao desabilitada ou origem vazia recusada. Corrigido com a trava `pastas_bloqueio` | Aprovado apos correcao |

## 6. QA

- **Suite:** `tests/integracao/qa_sync_orfaos_no_fim_test.sh`, 12 casos. sha256 `d4a02858cc1663350b976b187ed35c01bac098cf5a1d2d70c6ad2f843c1c61eb`, aceita pelo solicitante.
- **Auditorias:** json 66/0, harness 23/0 e composicao 28/0. `auditar-casos.sh --so` sem bloqueante.
- **Achados:**
  - **QA-ORF-01 (bloqueante):** `unset "apagar_planejado[k:$chave]"` reavaliava o subscrito, e um nome `$(...)` vindo do destino executava comando. Corrigido pelo Tech Lead com `unset 'mapa[$var]'`. O mesmo padrao em `_dbx_cmd_sync_ciclo_remoto_formar` (`unset "DBX_SYNC_TAB[$pl]"`, com `path_lower` remoto), que existia antes da demanda, foi corrigido junto.
  - **QA-ORF-02 (menor):** o `--dry-run` nao aplicava a trava de exclusao desabilitada antes do `continue`. Corrigido.
- **Resultado:** 12/12 depois das correcoes.
- **Fora do escopo:** em `lib/json.sh` e `lib/tmp.sh` sobram `unset "mapa[$var]"` com chave interna (ids, nomes de contexto). Nao chegam de nome de arquivo e ficam como candidata de varredura.

## 7. Riscos e rollback

- **Risco:** o destino passa a ter, durante a execucao, as duas copias de uma pasta movida. O espaco usado sobe ate o fim; a guarda de espaco existente continua valendo.
- **Rollback:** `git revert` do commit da demanda.
- **Melhoria registrada:** reconhecer a pasta movida e move-la no servidor, em vez de reenviar e apagar. Candidata a funcionalidade, fora do escopo.

## 8. Links e aceites

| Item | Valor |
|---|---|
| Aceite da suite do QA | 2026-11-11, entrada `2026-11-11-2210-aceite-testes-qa-sync-orfaos-no-fim` |
| Tech Lead | Aprovado em 2026-11-11 |
| DBA | Nao aplicavel: sem formato persistido novo; candidatas so na area temporaria |
| PR | pendente |
| Release | entra na 2.4.1 / 2.4.1-bash42 (decisao do solicitante) |
