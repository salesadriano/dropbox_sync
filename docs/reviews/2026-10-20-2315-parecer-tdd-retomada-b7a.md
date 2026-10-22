# Parecer de Evidencias de Testes (TDD) — Retomada entre execucoes, F-03 (fase 7a)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: retomada de `upload` e `download` de arquivo acima de 150 MiB entre execucoes (F-03, RF-101 a RF-109); porte **G**
- Agent responsavel pela alteracao e pela verificacao: Senior Developer (gate local, regra 14); validacao independente a cargo do QA Expert
- Data: 2026-10-20 (ciclo 1); 2026-10-21 (ciclo 2)
- Ciclos: 2 (ciclo 1 inicial; ciclo 2 apos QA-B7A-01 e QA-B7A-02)
- Branch / base: `feature/retomada-b7a` sobre `develop` @ `3c9a702`, sem commit
- Log de prompt: [2026-10-20_2315_backlog-fase-7a-retomada.md](../prompts/2026-10-20_2315_backlog-fase-7a-retomada.md)
- Registro de entrega: [2026-10-20-2315-registro-retomada-b7a.md](2026-10-20-2315-registro-retomada-b7a.md)
- Parecer de conformidade: [2026-10-20-2315-parecer-conformidade-retomada-b7a.md](2026-10-20-2315-parecer-conformidade-retomada-b7a.md)
- Validacao do QA: [2026-10-20-2315-validacao-qa-retomada-b7a.md](2026-10-20-2315-validacao-qa-retomada-b7a.md)
- Transcricao fiel do parecer do Senior Developer por gate (secoes de TDD). As secoes comuns aos dois gates aparecem nos dois arquivos.

## Transcricao

Worktree: `/home/sales/dropbox_api.worktrees/feature-retomada-b7a` (base `3c9a702`, sem commit).
Requisitos: escopo v1.21, secao 5.15 (RF-101 a RF-109); decisoes: memoria `2026-10-20-2315-retomada`; parecer do DBA (C1 a C6); RSK-69 a RSK-74.

### 1. Escopo do diff

| Arquivo | Mudanca |
|---|---|
| `lib/state.sh` | leitor NUL limitado (16 KiB, por descritor) aplicado a `upload-*` (C3) e `retomada-*`; namespace `retomada-*` (contexto, chave SHA-256 com NUL, carga com descarte, gravacao atomica, poda, barreira do `.part`, listagem); trava de registro (`comando retomada`, alem da de par); varredura de `.retomada.*` |
| `lib/transfer.sh` | laco de sessao reescrito em `_dbx_transfer_conduzir`/`_dbx_transfer_percurso`: gravacao antecipada do registro, carga com identidade + `prefixo_hash` relido para o acumulador, primeiro `append_v2` retomado restrito, recomeco unico (expirada/fechada/deslocamento), `too_large` -> 10, limpeza do registro por desfecho |
| `lib/cmd.sh` | `dbx_cmd_retomada_preparar/limpar`, `dbx_cmd_receber_retomavel` (`.part`, barreira pelo descritor, `rev:<rev>`, faixa, conferencia, `mv`), `dbx_cmd_avisar` |
| `lib/http.sh`, `lib/auth.sh` | pedido de faixa (`continue-at`), status 33 -> `DBX_HTTP_FAIXA_IGNORADA`, `Content-Range` publicado |
| `lib/hash.sh` | `DBX_HASH_ULTIMO_BLOCO` (SHA-256 da parte em voo sem reler) |
| `commands/upload.sh`, `commands/download.sh` | `--sem-retomada`/`--no-resume`, ordem C5, campos `retomada`/`retomado_de` so no caminho retomavel, `get_metadata` antes do download de arquivo |
| `commands/unlink.sh`, `commands/diagnostico.sh` | `.part` pela barreira e lista dos que ficam; checagem `retomada` |
| `bin/dbx`, `completions/dbx.bash`, `README.md`, `docs/testes/mapa-modulos.md`, `docs/arquitetura/system-design.md` (v1.15) | documentacao |

### 2. Testes novos (nenhum teste aprovado alterado)

| Arquivo | Casos | Cobre |
|---|---|---|
| `tests/unit/retomada_estado_test.sh` | 23 (1 pulado sem root) | TC-RME-01, 03..11, 12, 13; TC-UPC-13; TC-RMC-02, 03; TC-RML-01..04, 06; barreira |
| `tests/integracao/retomada_upload_test.sh` | 39 | TC-RMU-01..16, TC-RME-02, 12, 14, TC-RMO-01..03, 05..11, TC-RMC-01, 04, 05, TC-RMS-01..06 |
| `tests/integracao/retomada_download_test.sh` | 23 | TC-RMD-01..15, TC-RMO-01, 02, 04, 05, TC-RMC-01, 06, TC-RML-05..07, TC-RMS-06 |

Duplos: `curl` (servidor de sessao com estado que calcula o `content_hash` sobre as partes recebidas; download que segue o contrato do cliente para `continue-at`, medido com curl 8.18 contra servidor local), `stat` (identidade forjada; troca do nome entre conferencia e abertura), `head` (bytes lidos da origem), `mktemp` (gravacao do registro que falha), `sleep`. Sinais e `kill -9` pelo duplo; concorrencia com processos reais; `TMPDIR`, `HOME` e estado privados por caso.

### 3. Red -> green (ciclo 1)

- **Red**: os tres arquivos novos copiados para a arvore da base `3c9a702` (`git archive`), cada caso rodado isolado: 79 RED, 1 SKIP (outro dono, sem root) e 5 que ja passam na base por serem invariantes de comportamento atual (`rmo01_rmo02` upload e download fora do alcance, `rmo07` opcao em outro comando, `rms06` falha definitiva sem registro, e `rme01_gravacao_recusa_campo_invalido`, que passa na base de forma vacua porque a funcao nao existe). Todos os casos P0 e todos os mutantes estao entre os RED (`red.log`).
- **Green**: 23/23 (1 pulado: outro dono exige root), 39/39, 23/23.

### 4. Mutantes nos P0 (ciclo 1; copias do produto, cada um reprova o caso que o protege)

| P0 | Mutacao | Caso |
|---|---|---|
| conferencia do prefixo (C1) | comparacao do `prefixo_hash` removida | `rmu05_mutante_que_retoma_so_pela_identidade_reprova` (sufixo anexado na sessao antiga, sai diferente de 0) |
| deslocamento (confirmado + parte em voo) | aceita o avanco sem conferir o SHA-256 da parte relida | `rmu07_mutante_que_aceita_o_avanco_sem_conferir_a_parte_reprova` (sai 11) |
| hash final / troca antes da conferencia | `mv` do `.part` antes do hash | `rmd10_mutante_que_troca_antes_do_hash_reprova` (alvo trocado); `rmu13` prova o 11 sem reenvio |
| 206 coerente | conferencia do `Content-Range` removida | `rmd08_mutante_que_nao_confere_o_content_range_aceita_o_total_errado` |
| barreira do `.part` | inode na barreira por nome e pelo descritor removidos; so o do descritor removido | `rmd05_mutante_sem_a_barreira_de_inode_anexa_ao_arquivo_do_usuario`; `rmd14_mutante_sem_a_conferencia_pelo_descritor_anexa_ao_trocado` |
| descarte do estado invalido | reconferencia da conta removida | `rme_registro_de_outra_conta_e_descartado_e_o_mutante_que_o_aceita_reprova` |
| trava por registro | falha da trava ignorada | `rmc01_mutante_sem_trava_de_registro_deixa_os_dois_lerem` |
| `session_id` fora da saida | (prova direta, sem mutante) sentinela ausente de stdout, stderr, `--json`, `--null`, `--debug` interrompido e retomado, e do `diagnostico` | `rme02_rmo09_sentinelas_e_session_id_fora_da_saida_e_do_registro` |

### 5. Selecao pelo mapa (Regra 8) e demais verificacoes (ciclo 1)

Filtros (`sel2.log`): json 42, http 53, preflight 35, composicao 28, tmp_test 16, cli 17, state 60, trava 82, transfer 36, auth 41, banda 34, comandos 119, confinamento_remoto 25, diagnostico 39, completar 17, hash_ 44 (+2 pulados, como na base), cmd_test 23, sync 91, espaco 13, verificar 17, filtros 58, reter_test 84, compartilhar 83, recuperacao 91, qa_ 350, retomada 84 (+1 pulado). Todos APROVADOS. A auditoria `json` (RNF-24: massa por `$(printf ...)`) reprovou na 1a rodada por 5 linhas dos testes novos; elas passaram a `printf -v`, e `json` e `composicao` foram rodados de novo: aprovados.

- `shellcheck lib/*.sh commands/*.sh bin/* scripts/*.sh`: 0 achados (depois de uma supressao SC2016 justificada no texto da ajuda); `shellcheck -x` nos 3 testes novos: 0 achados (depois da correcao de 1 aviso SC2034 e da supressao justificada de SC2031).
- `bash scripts/verificar-remocao-de-casos.sh`: 1739 -> 1739, nenhuma reducao (os arquivos novos ainda nao sao rastreados).
- Suite completa: nao rodada nesta etapa (instrucao).

### 6. Achados (ciclo 1)

| ID | Severidade | Achado |
|---|---|---|
| TDD-01 | Menor | TC-RME-11 (registro e `.part` de outro dono) so roda como root; sem root fica `SKIP`, coberto pelos casos de ligacao simbolica, diretorio e outro inode (DIV-201). |
| TDD-02 | Menor | Contrato `Range`/`rev:` lido e medido contra curl, nao exercitado contra o servico real (RSK-70). |

**Veredito ciclo 1: aprovado** (sem bloqueante), com os achados acima e as DIVs da secao 7.

### 7. Divergencias (DIV-191 em diante), para decisao do Tech Lead

| DIV | Divergencia | Escolha feita |
|---|---|---|
| DIV-191 | RF-107(a) pede poda "em toda gravacao"; a gravacao e por parte de 4 MiB | poda (e varredura de `.retomada.*`) uma vez por execucao, na primeira gravacao |
| DIV-192 | RF-104(b) usa o `get_metadata` desta execucao, mas o download de arquivo de hoje nao o faz; sem ele nao se sabe o tamanho antes de criar o `.part` | todo download para arquivo (sem `--sem-retomada`) faz um `get_metadata`; falha, pasta ou ate 150 MiB caem no recebimento de hoje |
| DIV-193 | RF-104(d) "206 de total diferente: corpo nunca anexado"; o cliente (curl, medido) so recusa `200` e inicio diferente | o `dbx` confere `Content-Range` e `rev` depois; o `.part` com o corpo e apagado pela barreira e o recebimento recomeca do zero; nada do corpo e usado |
| DIV-194 | RF-104(d)(f) "o `.part` e truncado e recomeca do zero" | `.part` apagado pela barreira e recomeco pelo recebimento atomico de hoje sobre `rev:<rev>` (`.part` novo, sem registro); divergindo de novo, 11 |
| DIV-195 | RF-58 dentro da execucao (reposicao) desalinha partes e blocos; o `prefixo_hash` deixa de existir | a reposicao de RF-58 desliga a retomada entre execucoes naquela execucao (registro removido, aviso) |
| DIV-196 | `too_large` nao esta na taxonomia (saida `1`); RF-103(f)/RF-109 pedem `10` com e sem registro | `too_large` -> `erro_remoto` (10) em toda sessao, inclusive `sync --enviar` (antes 1) |
| DIV-197 | RF-107(d) "uma linha por registro"; TC aprovado do `diagnostico` exige `ok=8` sem estado | sem registros, nenhuma linha `retomada`; TC-RML-07 lido como resultado `ok` sem criar o diretorio |
| DIV-198 | TC-RML-03 "registro ilegivel: `.part` fica e aparece no diagnostico" | o `.part` fica, mas o registro podado sai e o `.part` nao e mais conhecido; `unlink` tambem nao lista parcial de registro ilegivel |
| DIV-199 | TC-RML-02 "1.001 registros: restam 1.000" ambiguo | a contagem inclui o registro recem-gravado (1.000 antigos + o novo -> sai o mais antigo) |
| DIV-200 | TC-RMD-13 "T maior: descarte pela barreira" x RF-104(e) "reprovado nao e tocado" | segue RF-104(e): o `.part` nao e tocado, registro removido, `.part` novo |
| DIV-201 | TC-RME-11/RMD-06 "de outro dono" nao e reproduzivel sem root | caso pulado sem root; cobertos ligacao simbolica, diretorio e outro inode |
| DIV-202 | Contrato do cliente declarado em `lib/http` nao tinha pedido de faixa; `files.stone` nao fala de `Range` (DIV-176) | contrato estendido: `continue-at` na configuracao; status 33 = faixa recusada sem escrita; `416` com status 0; sem reemissao diagnostica nesses dois |

## Ciclo 2 (QA-B7A-01 e QA-B7A-02; decisao do Tech Lead na memoria `2026-10-20-2315-retomada`)

### Correcoes (`lib/state.sh`)

- **QA-B7A-01 (P1, uma FIFO pendura `diagnostico` e `unlink`):**
  - O leitor limitado (`_dbx_state_ler_limitado`) so abre arquivo regular: `[[ -f ]]` antes de abrir, alem da conferencia ja feita pelo descritor. Assim todo chamador fica coberto: listagem, carga, poda e `upload-*`.
  - O mesmo vale para `_dbx_state_trava_ler`: uma `trava-*` FIFO e "ilegivel", como o diretorio no lugar ja era. Sem isso ela tambem bloquearia o `diagnostico`, o `unlink` e o `sync`.
  - A poda ja usava `find -type f` e `-f`; agora isso esta coberto por teste.
- **QA-B7A-02 (P2, `.part` invisivel):**
  - Na carga, um registro legivel descartado pelo cabecalho, se for de download e do MESMO alvo desta execucao (mesmo caminho local, com outra parte divergente, como o remoto com outra caixa), leva o seu `.part` a barreira de identidade antes de sair (`_dbx_state_retomada_descartar_part`).
  - Um registro de OUTRO alvo (copiado ou plantado) nunca leva a apagar nada fora do alvo desta execucao. A primeira versao da correcao reprovou `qa_d12` por isso e foi restrita.
  - **DIV-198** passa a valer so para registro ilegivel.
- **Observacao do `correct_offset` em cadeia JSON:** mantida (DIV-203). A seguranca vem do SHA da parte em voo. O BA alinha a redacao da RF-103(b) ao leitor.

### Testes (red antes da correcao, green depois; nenhum teste aprovado ou do QA alterado)

| Caso | Antes | Depois |
|---|---|---|
| unit `c2_descarte_por_cabecalho_leva_o_part_pela_barreira` (mesmo alvo sai; outro inode fica; outro alvo fica) | not ok | ok |
| unit `c2_fifo_no_lugar_do_registro_nao_bloqueia_leitor_listagem_nem_travas` | nao executado (interrompido apos o primeiro not ok) | ok |
| unit `c2_poda_ignora_entrada_nao_regular` | nao executado (idem) | ok |
| integ `c2_registro_de_outro_remoto_descartado_leva_o_part_pela_barreira` | not ok | ok |
| integ `c2_fifo_no_estado_nao_pendura_diagnostico_nem_unlink` | not ok (pendurou, 124) | ok |

**Mutantes novos (cada um reprova o caso que o protege):**
- sem a conferencia de arquivo regular, o `diagnostico` pendura: `c2_mutante_sem_a_conferencia_de_arquivo_regular_pendura` (espera 124);
- sem a barreira no descarte, o `.part` orfao fica: `c2_mutante_que_descarta_sem_a_barreira_deixa_o_orfao`.

### Execucao (ciclo 2)

| Verificacao | Resultado |
|---|---|
| `bash tests/run.sh qa_retomada_b7a` | 34/34 (suite da epoca do ciclo 2 do dev) |
| `retomada` (o filtro casa tambem `qa_retomada_b7a`) | 125 ok, 1 pulado |
| `qa_` | 384/384 |
| `state`, `trava`, `diagnostico` | 60, 82, 39 |
| restante da selecao do mapa (http, preflight, composicao, tmp_test, cli, transfer, auth, banda, comandos, confinamento_remoto, completar, hash_, cmd_test, sync, espaco, verificar, filtros, reter_test, compartilhar, recuperacao) | tudo aprovado |
| `json` | 41/42: reprovado por um arquivo do QA (abaixo) |
| `shellcheck lib/*.sh commands/*.sh bin/* scripts/*.sh` e `-x` nos testes novos | 0 achados |
| `verificar-remocao-de-casos` | 1739 -> 1739, sem reducao |

**Pendencia no arquivo do QA, nao editado pelo developer (instrucao):** a auditoria RNF-24 do `json_test` (`massa_adversarial_nao_e_construida_por_substituicao_de_comando`) acusou `tests/integracao/qa_retomada_b7a_test.sh:435`, `QA_C[5]+=$(printf '%17000s' '')`. Correcao sugerida: `printf -v enchimento '%17000s' ''; QA_C[5]+=$enchimento`. **Resolvida pelo QA no ciclo 2 (caso `qa_u10`), com a mesma correcao, e tambem em `qa_l03`.** `bash tests/run.sh json` aprovada depois (62/62).

**Veredito ciclo 2: aprovado.** TDD sem achado novo.

## Achados consolidados

| ID | Ciclo | Severidade | Situacao |
|---|---|---|---|
| TDD-01 | 1 | Menor | Aberto (caso pulado sem root; DIV-201) |
| TDD-02 | 1 | Menor | Aberto (contrato real nao exercitado; RSK-70) |
| Pendencia do arquivo do QA (RNF-24) | 2 | Bloqueante na epoca | Resolvida pelo QA no ciclo 2 |
