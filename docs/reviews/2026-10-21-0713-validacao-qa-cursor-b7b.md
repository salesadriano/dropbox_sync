# Validacao independente do QA — Cursor de listagem no `sync --receber`, F-14 (fase 7b)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: F-14, cursor de listagem entre execuções no `sync --receber`; porte **G** (validação independente e adversarial, regra 40)
- Agent: QA Expert; datas: 2026-10-21 (ciclo 1 e ciclo 2); ciclos: 2
- Branch / base: `feature/cursor-b7b` sobre `develop` @ `a6b5376`, com o diff não commitado
- Registro de entrega: [2026-10-21-0713-registro-cursor-b7b.md](2026-10-21-0713-registro-cursor-b7b.md)
- Pareceres do desenvolvedor: [TDD](2026-10-21-0713-parecer-tdd-cursor-b7b.md) e [conformidade](2026-10-21-0713-parecer-conformidade-cursor-b7b.md)
- Fontes do QA: escopo v1.23, seção 5.16 (RF-110 a RF-119); memória `2026-10-21-0713-cursor`; RSK-77 a RSK-84; parecer do DBA; pareceres do desenvolvedor.

## Suíte do QA

`tests/integracao/qa_cursor_b7b_test.sh`, dublê de `curl` próprio, pelo `bin/dbx` real, sem rede real. Qualquer mudança na suíte volta para a aprovação do solicitante (regra 12).

| Versão | sha256 | Casos | Mudança |
|---|---|---|---|
| Ciclo 1 | `f16a365be9b1dd1d08d3ab4e4e1b25d5e1d125dcde37387fc29051278089b254` | 41 | Suíte inicial: exclusão (A), equivalência (B), invalidação (C), gravação (D), sinais (E), opções e sigilo (F), F-40 (G) |
| Ciclo 2 | `8c40c6f0f77ea0dd9e147e4ba6e21898366e7e131f5b51043e021ce05235e4b6` | 49 | Oito casos novos do grupo H (raiz `/`, entrada da própria pasta, confinamento do delta, raiz na CLI, Unicode sob `LC_ALL=C`, registros separados por raiz) |

**Aprovação do solicitante (regra 12):** em 2026-10-21 ("Aprovo"), para a versão de 49 casos, sha256 `8c40c6f0f77ea0dd9e147e4ba6e21898366e7e131f5b51043e021ce05235e4b6`.

## Ciclo 1 — REPROVADO

Veredito: **reprovado**. Dois achados bloqueantes de funcionalidade (P1) e um P3. Nenhum achado de segurança de dado.

As barreiras de segurança do P0 resistiram a todos os ataques: nenhum cenário produziu exclusão local a partir do registro sem `path/not_found` do servidor na mesma execução; nenhum plano incremental divergiu do da varredura completa; toda invalidação voltou à completa com código 0; o cursor não saiu do processo. Mas o recurso, como implementado, nunca entrava em ação contra a API real: a raiz `/` nunca recebia registro, e uma pasta que não fosse a raiz também não, porque o `list_folder` recursivo devolve a entrada da própria pasta e ela tornava a tabela "não persistível". Os 45 casos do desenvolvedor não pegaram isso porque o duplo deles nunca devolvia essa entrada e sempre usava `/r`.

### QA-B7B-01 — P1 — raiz `/` nunca grava o registro

- **Reprodução:** `dbx sync --receber --origem / --destino L` duas vezes. O diretório de estado só tem `memoria-*`, e a segunda execução faz `list_folder` recursivo (nunca `continue`).
- **Causa:** `dbx_state_cursor_contexto` exigia o quarto argumento não vazio, e a raiz da API para `/` é `""`. O contexto falhava, a preparação devolvia 0 sem registro, e toda execução saía `varredura=completa`, `cursor_motivo=sem-registro`, para sempre. O motivo também enganava (DIV-222 não previa isso).
- **Esperado:** RF-110(a)(c) e RF-111(g). A raiz `/` é chave válida.
- **Caso:** `teste_qa_z01_raiz_remota_barra_usa_o_cursor` (falhou no ciclo 1).

### QA-B7B-02 — P1 — entrada da própria pasta bloqueava a persistência

- **Reprodução:** duplo com a entrada `{".tag":"folder","path_lower":"/r","path_display":"/r"}` na listagem de `/r`: execução 0, nenhum `cursor-*`.
- **Causa:** o `list_folder` recursivo de `/X` devolve a própria pasta `/x` como entrada (exemplo da documentação no Context7: listar `/Homework/math` traz `{"tag":"folder","path_lower":"/homework/math"}`). `_dbx_sync_entrada` passava essa entrada por `_dbx_sync_relativo_seguro`, que reprova porque o relativo é vazio. Na completa, isso marcava a tabela como não persistível. Num delta, descartaria o incremental.
- **Esperado:** RF-110, RF-111(g). A entrada da raiz é reconhecida pela estrutura e ignorada.
- **Caso:** `teste_qa_z02_listagem_com_a_propria_pasta_grava_o_registro` (falhou no ciclo 1).

### QA-B7B-03 — P3 — `path_lower` do delta sem confinamento

- **Reprodução:** delta C1→C2 com uma entrada `file` cujo `path_lower` é `/r/../ok.txt` ou `/outra/ok.txt` e cujo `path_display` é `/r/ok.txt`: `varredura=incremental`.
- **Causa:** `_dbx_sync_entrada` só exigia que `path_lower` começasse por `/` e confinava apenas `path_display`.
- **Esperado:** RF-112(e) e RF-115(h). Não apaga nada, mas a chave estranha entra no retrato, e a execução seguinte descarta o registro, o que custa uma varredura.
- **Caso:** `teste_qa_z03_delta_com_path_lower_fora_da_raiz_e_incoerente` (falhou no ciclo 1).

### Observação O1 — remédio do `diagnostico`

O remédio para `cursor-*` ilegível dizia "a próxima execução do sync --receber faz a varredura completa e o substitui". Isso é falso para FIFO, ligação e diretório, que nunca são substituídos (código 3 do leitor). Corrigido no ciclo 2.

### Observação O2 — defeito anterior à 7b

Observado na primeira versão de `b01`: com o duplo sem `Dropbox-API-Result`, o `sync` aceitou um conteúdo cujo resumo divergia do `content_hash` da listagem e saiu 0. O comportamento foi reproduzido na base `a6b5376`, confirmado pelo SD e entregue como **F-43**, com risco **RSK-84**. Não entra na 7b.

### Observação O3 — risco aceito RSK-77 confirmado em comportamento

Um delta que omite mudança mantém arquivo local extra ou omite transferência até a periódica, e nunca apaga.

### Observação O4 — teto de 20.000 páginas não exercitado

Custo. O laço é coberto por cursor repetido, `has_more` sem cursor e cursor fora da regex.

### Observação O5 — memória descartada com `--espelhar`

Com memória descartada e `--espelhar`, a execução sai 14 (RF-41(f), comportamento anterior) e o registro não avança. Coerente com RF-111(g).

## Ciclo 2 — APROVADO

Veredito: **aprovado**, 49/49. QA-B7B-01, QA-B7B-02, QA-B7B-03 e O1 estão corrigidos. Os casos `z01` a `z03` passaram a verde sem editar o arquivo. Os oito casos novos do grupo H não acharam defeito.

### Reataque (grupo H, 8 casos novos, todos verdes)

- **h01, raiz `/`:** o registro é gravado com o remoto `""` no cabeçalho; num `deleted` de item que ainda existe, a contradição leva à completa e o item não é apagado; uma confirmação válida apaga com `--espelhar`; o `get_metadata` vai pelo caminho certo, `/d/x.txt`, nunca com `//`.
- **h02, entrada da raiz na completa:** cobre a entrada repetida com outro `id`, o `path_display` hostil (`/r/../fora`), a caixa `/R` e um arquivo no caminho da raiz. Nos três primeiros, a pasta é ignorada, nunca entra no retrato e nunca vira item local, e o registro é gravado. O arquivo no caminho da raiz deixa o retrato não gravável.
- **h03, entrada da raiz no delta:** pasta com outro `id`, repetida ou com outra caixa: o delta continua incremental, sem efeito. `deleted` da raiz ou arquivo no caminho da raiz: varredura completa. Em todos: nada apagado e nenhuma confirmação.
- **h04, confinamento do delta:** 11 formas, todas levando à completa com código 0, sem nada escrito ou apagado, e o retrato regravado sem chave fora de `/r/`: `..` e `.`; caminho absoluto fora da raiz; pasta irmã com prefixo (`/rx`); barra final (`/r/`) e barra dupla; `\n`, `\u0000` e `\u0001`; caminho relativo; `path_display` fora da raiz com `path_lower` dentro.
- **h05, `deleted` com grafia diferente** (`/R/A.TXT`, `/r/../r/a.txt`, `/outra/a.txt`): o arquivo continua no mapa e nada é apagado. O `deleted` só remove uma chave exata e nunca é confirmação.
- **h06, raiz na CLI como `/r/`, `/R` ou `//r`:** código 0, nada apagado e nada a transferir. Com `/R`, o cabeçalho diverge, o registro é descartado e refeito: só custo.
- **h07, raiz Unicode `/Ünï` com `LC_ALL=C` (DIV-235):** duas execuções com `--espelhar`, nada apagado.
- **h08, registros da raiz `/` e da subpasta `/r`:** são separados, um por par, e nenhum usa o cursor do outro.

### Mutantes do ciclo 2 (cópia em `qa7b-mut2`): 3 aplicados, 3 mortos

| Mutante | Morto por |
|---|---|
| m4: sem confinamento do `path_lower` | h04, z03 |
| m5: a raiz é isenta para qualquer tag | h02, h03 |
| m6: a raiz casa por prefixo, não por igualdade | h02, h03, h04, h05, z02, z03 |

## Grupos anteriores

A a G e z01 a z03 estão todos verdes, sem edição, depois da troca do dublê do SD e das correções. Grupos: A, exclusão (10 casos); B, equivalência (5); C, invalidação (8); D, gravação (4); E, sinais (3: TERM, INT e HUP no `continue` e na confirmação; falha de transporte na confirmação); F, opções e sigilo (7); G, F-40 (1).

Destaques do grupo A: retrato forjado com rodapé recalculado, com `--espelhar --permitir-origem-vazia` (contradição, completa, nada apagado); `deleted` de item que existe, com o mesmo `id` e com outro `id`; respostas duvidosas na confirmação (outro 409, 200 `deleted`, 400, 404, `restricted_content`); simulação com 51 candidatas com estado byte a byte igual.

Destaques do grupo C: periódica (8 dias, 7 dias menos 1 h, 100 e 99 incrementais, relógio +10 min e +4 min); cabeçalho de outra conta, `account_id`, assinatura, remoto, local, versão e magia; 17 campos forjados com rodapé válido (contagem, campo de 8193 bytes, `..`, `//`, quebra de linha, controle, fora da raiz, relativo, `path_lower` repetido, `id`, `rev`, hash, cursor, 1.000.001 entradas, pasta com `rev`, tag desconhecida); ligação simbólica para registro válido (não seguida, alvo intacto); FIFO no `diagnostico` e no `unlink`.

Destaques do grupo F: `--no-cursor` não toca `cursor-*`; cursor ausente de `--debug --json --progresso`, `--null` com `reset`, contradição, `diagnostico` e `--json diagnostico`, argv, ambiente e resíduos da área temporária do cliente HTTP; registro 0600 e diretório 0700 com `umask 000`; poda de 8 dias não toca `memoria-*`, `retomada-*` e `upload-*`.

## Execuções

### Ciclo 1

| Execução | Resultado |
|---|---|
| `bash tests/run.sh qa_cursor_b7b` | 38 ok; para em `z01` (QA-B7B-01) e deixa `z02` e `z03` sem rodar pelo harness (saída 1, esperado) |
| `bash tests/run.sh cursor` | 95 ok: `cursor_estado` 12/12, `cursor_test` 45/45 e QA 38; para no mesmo `z01` |
| `bash tests/run.sh json` | 62/62 |
| `bash tests/run.sh harness` | 22/22 |
| `bash tests/run.sh composicao` | 28/28 |
| `shellcheck tests/integracao/qa_cursor_b7b_test.sh` | limpo |
| `bash scripts/verificar-remocao-de-casos.sh` | 1872 → 1872, nenhuma redução não declarada |

### Ciclo 2

| Execução | Resultado |
|---|---|
| `bash tests/run.sh qa_cursor_b7b` | 49/49 |
| `bash tests/run.sh cursor` | 110/110 (`cursor_estado` 13, `cursor_test` 48, QA 49) |
| `bash tests/run.sh json` | 62/62 |
| `bash tests/run.sh harness` | 22/22 |
| `bash tests/run.sh composicao` | 28/28 |
| `shellcheck` da suíte | limpo |
| `bash scripts/verificar-remocao-de-casos.sh` | nenhuma redução não declarada |

## Observação residual (sem reprovação)

O3 do ciclo 2: o `path_lower` do delta não é conferido como minúsculo. Uma entrada `file` com `path_lower` em caixa mista e confinado seria aceita com uma chave diferente da minúscula. O efeito possível é só manter um item a mais no mapa: o `deleted` remove apenas a chave exata, e o item a mais impede exclusão, nunca a causa. A API não envia isso, então fica só como observação.

## Achados consolidados

| ID | Ciclo | Severidade | Situação |
|---|---|---|---|
| QA-B7B-01 | 1 | P1 | Fechado no ciclo 2 |
| QA-B7B-02 | 1 | P1 | Fechado no ciclo 2 |
| QA-B7B-03 | 1 | P3 | Fechado no ciclo 2 |
| O1 | 1 | Observação | Fechado no ciclo 2 |
| O2 | 1 e 2 | Defeito anterior à 7b | F-43, RSK-84 |
| O3 | 1 | Risco aceito | RSK-77 |
| O3 (path_lower) | 2 | Observação | Sem efeito destrutivo |
| O4 | 1 | Observação | Teto de 20.000 páginas não exercitado (custo) |
| O5 | 1 | Observação | Coerente com RF-111(g) |

**Veredito do QA: APROVADO, 2026-10-21 (ciclo 2), 49/49, sem achado P0 ou P1 aberto.**
