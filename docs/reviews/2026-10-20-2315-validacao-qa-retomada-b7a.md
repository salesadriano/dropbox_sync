# Validacao independente do QA — Retomada entre execucoes, F-03 (fase 7a)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: F-03, retomada de `upload` e `download` entre execucoes; porte **G** (validacao independente e adversarial, regra 40)
- Agent: QA Expert; data: 2026-10-20 (ciclo 1) e 2026-10-21 (ciclo 2); ciclos: 2
- Branch / base: `feature/retomada-b7a` sobre `develop` @ `3c9a702`, com o diff nao commitado
- Registro de entrega: [2026-10-20-2315-registro-retomada-b7a.md](2026-10-20-2315-registro-retomada-b7a.md)
- Pareceres do desenvolvedor: [TDD](2026-10-20-2315-parecer-tdd-retomada-b7a.md) e [conformidade](2026-10-20-2315-parecer-conformidade-retomada-b7a.md)
- Fontes do QA: escopo v1.21, secao 5.15 (RF-101 a RF-109); memoria `2026-10-20-2315-retomada`; RSK-69 a RSK-76; parecer do DBA; pareceres do developer.

## Suite do QA

`tests/integracao/qa_retomada_b7a_test.sh`, duble de `curl` proprio para upload e download, sem rede real. Qualquer mudanca na suite volta para a aprovacao do solicitante (regra 12).

| Versao | sha256 (prefixo) | Casos | Mudanca |
|---|---|---|---|
| Ciclo 1 | `d90cfd7e...` | 34 | Suite inicial: upload (C1, DIV-172), `correct_offset`, estado invalido, trava, sigilo, simulacao e sinal, barreira do `.part`, resposta e conferencia, diagnostico |
| Ciclo 2 | `445ba4fc6cf83dc85972e12e93ace6b6ec67d0d9a2ead5a594b600abbd263a34` | 41 | Sete casos novos (`qa_l04`, `qa_l05`, `qa_l06`, `qa_u19`, `qa_d14`, `qa_d15`, `qa_d16`); ajuste de RNF-24 em `qa_u10` e `qa_l03` (`printf -v` no lugar de substituicao de comando) |

**Aprovacao do solicitante (regra 12):** em 2026-10-21 ("Aprovo"), para a versao final, sha256 `445ba4fc6cf83dc85972e12e93ace6b6ec67d0d9a2ead5a594b600abbd263a34`, 41 casos.

## Ciclo 1 — REPROVADO

Veredito: **reprovado**. Ha um P1 (QA-B7A-01) e um P2 (QA-B7A-02). Nenhum P0 foi violado: os P0 de integridade se sustentaram em todos os ataques.

- **Upload:** prefixo, parte em voo, `correct_offset` e `content_hash` final.
- **Download:** `206` coerente, `rev:` fixo e hash do `.part` inteiro antes do `mv`.
- **Barreira de identidade:** nos dois sentidos.

O que reprova e robustez, nao integridade:
- uma FIFO chamada `retomada-*` pendura o `diagnostico` e o `unlink`, e o `unlink` pendura depois de revogar o token e apagar a credencial;
- um registro legivel descartado deixa um `.part` grande e invisivel.

### QA-B7A-01 — P1 — FIFO `retomada-*` pendura `diagnostico` e `unlink --confirmar`

- **Reproducao:**
  ```
  mkfifo "$XDG_STATE_HOME/dbx/retomada-0123456789abcdef0123456789abcdef"
  dbx diagnostico        # ou: dbx unlink --confirmar
  ```
  - **Obtido:** os dois penduram (status 124 sob `timeout`). No `unlink`, o duplo registrou o `oauth2/token` e o `auth/token/revoke`. A credencial ja tinha sido apagada (`config/dbx` vazio). Nao houve saida nem relatorio.
  - **Esperado:** RF-107(d): o `diagnostico` so le, emite uma linha `retomada` (`ilegivel`, `aviso`) e nunca falha nem pendura. RF-107(c) e RF-51(f): o `unlink` conclui e remove o estado. P2 da secao 5.15: o estado nunca e causa de falha.
- **Causa:** `dbx_state_retomada_listar` chamava `_dbx_state_ler_limitado` sobre cada `retomada-*` sem conferir antes que e arquivo regular. A abertura so-leitura de FIFO bloqueia ate aparecer um escritor. Os outros chamadores (carga, poda, `upload-*`) ja conferiam `-f`.
- **Correcao sugerida (conferida numa copia mutante, em que os 3 casos `qa_l*` passam):** acrescentar `[[ -f $arquivo ]] || return 1` depois de `[[ -e $arquivo ]] || return 2` em `_dbx_state_ler_limitado`.
- **Casos:** `teste_qa_l01_fifo_retomada_nao_pendura_diagnostico` e `teste_qa_l02_fifo_retomada_nao_pendura_unlink`. Os dois falharam no ciclo 1 (pendurou, 124).

### QA-B7A-02 — P2 — registro de download LEGIVEL descartado por cabecalho divergente deixa o `.part` orfao e invisivel

- **Reproducao:**
  1. `dbx download /Grande.iso grande.iso` e interrompido pela rede depois de 40 MiB. Ficam o registro e o `.part`.
  2. `dbx download /grande.ISO grande.iso`, o mesmo arquivo remoto com outra caixa, que a Dropbox nao distingue.
  - **Obtido:** sai 0 e o destino fica correto; o registro e descartado e apagado; o `.part` de 40 MiB fica no diretorio do alvo; sem registro, o `.part` nao aparece no `diagnostico` nem na listagem do `unlink`, e a poda nao o alcanca.
  - **Esperado:** quando o registro e legivel, o `.part` que ele descreve passa pela barreira de RF-104(e) antes de o registro sair. Alternativa: o registro fica e e listado. DIV-198 e RSK-75 aceitaram o residual so para o registro **ilegivel** podado.
- **Causa:** `dbx_state_retomada_carregar` descartava so o registro, e o ramo de cabecalho divergente nao oferecia o `.part` a barreira.
- **Caso:** `teste_qa_d13_registro_descartado_por_cabecalho_nao_deixa_part_invisivel`, que falhou no ciclo 1.

### Observacoes do ciclo 1 (sem severidade, nao bloqueiam)

- **OBS-1:** um `correct_offset` em cadeia JSON (`"16777216"`) igual a confirmado mais a parte em voo e aceito. O valor e o correto, e o SHA da parte confere. A RF-103(b) fala em "nao inteiro" como recusa; vale alinhar a redacao ou o leitor (DIV-203). Cadeia com valor errado (`"99"`), `null`, `1.6777216e7`, negativo e 20 digitos recomecam do zero (`qa_u06`).
- **OBS-2:** a barreira do `.part` e conferida duas vezes, pelo nome e pelo descritor. Num mutante sem as duas conferencias de inode, `qa_d02` e `qa_d04` reprovam. Num mutante sem a conferencia do SHA da parte em voo, `qa_u02` reprova.

### O que foi atacado e se sustentou (ciclo 1)

| Area | Casos | Resultado |
|---|---|---|
| Upload, arquivo local mudou (C1) | u01: sufixo alterado com `stat` forjado. u02: parte em voo alterada com `stat` forjado. u03: truncado. u04: outro inode com o mesmo conteudo. u05: ligacao fisica | ok |
| `correct_offset` (DIV-172 B) | u06: 10 valores, entre eles confirmado+2 partes, confirmado-1 parte, +voo-1, +voo+1, acima do total, 20 digitos, negativo, cadeia, `null` e notacao cientifica. Todos recomecam do zero. u07: `not_found` | ok |
| Estado invalido (P2, C3, C4) | u08: registro copiado para o nome de outra transferencia. u09: `\n` no local e na identidade, campo extra por NUL, outro host, aspas no `session_id`. u10: acima de 16 KiB e 64 MiB sem NUL. u11: `upload-*` de 32 MiB sem NUL. u12: registro FIFO, diretorio ou ligacao simbolica | ok |
| Trava (C2) | u13: trava de registro ilegivel. Segue sem retomada, registro, trava e sessao intocados | ok |
| Sigilo (C6) e modos | u14: `session_id` ausente em stdout e stderr com `--debug`, `--progresso`, `--json`, `--null` e `diagnostico`. Ausente tambem no argv e no ambiente do curl. u15: `umask 000` com registro 0600, diretorio 0700 e sem `.retomada.*` nem trava apos o sinal | ok |
| Simulacao, opcao, sinal, diretorio | u16: `--dry-run` e `--sem-retomada` deixam registro e diretorio identicos. u17: INT na execucao retomada avanca o confirmado, e a seguinte conclui com 1 sessao. u18: diretorio de estado e arquivo ou ligacao quebrada | ok |
| Barreira do `.part` | d01: FIFO e diretorio no lugar (nao pendura, nao apaga). d02: ligacao fisica para arquivo do usuario. d03: ligacao simbolica. d04: nome no padrao com `\n` e ESC, outro inode | ok |
| Resposta e conferencia | d05: `.part` adulterado no prefixo recomeca uma vez; divergencia persistente sai 11 com o destino intacto. d06: `206` com `rev` diferente. d07: tres quedas durante a faixa. d08: remoto trocado de mesmo tamanho | ok |
| Download, demais | d09: `--dry-run` e `--sem-retomada`, registro e `.part` intocados. d10: TERM durante a faixa (14, destino intacto). d11: diretorio de estado inutilizavel. d12: registro copiado para outro alvo nao anexa ao `.part` alheio | ok |
| Diagnostico | l03: caminhos com `\n` e ESC citados em texto e `--json`, sem `session_id` em nenhum modo | ok |

### Execucoes (ciclo 1)

- `bash tests/run.sh qa_retomada_b7a`: reprovada. O primeiro erro e `qa_d13`; o harness para no primeiro erro (RNF-32(a)).
- Execucao caso a caso, sem bail-out: **31 de 34 aprovados**. Falham `qa_d13`, `qa_l01` e `qa_l02`.
- Suites do developer, conferidas sem alteracao: `retomada_download` 23/23; `retomada_upload` 39/39; `retomada_estado` 22 aprovados e 1 pulado (root).
- Mutantes, em copias do produto: sem o SHA da parte em voo, `qa_u02` reprova; sem as conferencias de inode, `qa_d02` e `qa_d04` reprovam; com `-f` no leitor limitado, `qa_l01..03` passam, o que confirma a correcao de QA-B7A-01.
- `shellcheck tests/integracao/qa_retomada_b7a_test.sh`: limpo.
- `bash scripts/verificar-remocao-de-casos.sh`: 1739 -> 1739, nenhuma reducao nao declarada.

## Ciclo 2 — APROVADO

Veredito: **aprovado**. As duas correcoes se sustentaram no reataque. Nao ha achado novo com severidade; ficam so observacoes.

- **QA-B7A-01: fechado.** `_dbx_state_ler_limitado` e `_dbx_state_trava_ler` recusam o que nao e arquivo regular antes de abrir. Cobertura: `qa_l01`, `l02`, `l04`, `l05`, `l06`, `qa_u19` e `qa_d14`.
- **QA-B7A-02: fechado.** O registro de download legivel do MESMO alvo, descartado por cabecalho, leva o `.part` pela barreira. Cobertura: `qa_d13` e `qa_d16`.

### Correcao na suite do QA (RNF-24, pedido do coordenador)

Duas massas eram construidas por substituicao de comando, e a auditoria do `json_test` acusou as duas, uma de cada vez:
- `qa_u10`: `QA_C[5]+=$(printf '%17000s' '')` passou a `printf -v enchimento ...`.
- `qa_l03`: `"$(printf '%064d' 0)"` passou a `printf -v zeros ...`.

Depois disso, `bash tests/run.sh json` fica APROVADA (62/62).

### Casos novos no ciclo 2 (7; total 41)

| Caso | Ataque | Resultado |
|---|---|---|
| `qa_l04` | `diagnostico` com FIFO em `retomada-*`, `trava-*`, `upload-*` e `memoria-*`, ligacao simbolica para FIFO fora do estado e socket | conclui (codigo em 0..15), lista como ilegivel e nao toca em nada |
| `qa_l05` | `unlink --confirmar` no mesmo estado hostil | nao pendura; a FIFO fora do estado, alvo das ligacoes, fica |
| `qa_l06` | upload (com poda: registro FIFO com mtime de 10 dias) e download no mesmo estado hostil | concluem, conferidos; a poda nao apaga nao regular |
| `qa_u19` | trava do PROPRIO registro como FIFO ou ligacao para FIFO | segue sem retomada com aviso, trava e sessao intocadas |
| `qa_d14` | trava do registro de download como FIFO | segue sem retomada; o `.part` do registro nao e tocado |
| `qa_d15` | o mesmo alvo por outra grafia: pai por ligacao simbolica, `real/../real/` e `./real//` | mesmo alvo canonico: `retomada=sim`, sem `.part` nem registro sobrando |
| `qa_d16` | descarte por cabecalho em 4 formas: outro host; outra caixa no remoto; arquivo do usuario no lugar do `.part`; registro LEGIVEL de outro alvo plantado na chave | com outro host e outra caixa, o `.part` sai pela barreira; o arquivo do usuario e o `.part` de outro alvo ficam intactos |

**Mutante de conferencia:** sem o `-f` em `_dbx_state_trava_ler`, a FIFO volta a pendurar. `qa_l04` reprova com 124 no `diagnostico`; `qa_u19` reprova com 137 no `upload`.

### Observacoes do ciclo 2 (sem severidade, nao bloqueiam)

- **OBS-3 (TOCTOU):** entre `[[ -f ]]` e `exec {fd}<"$arquivo"` resta uma janela. Nessa janela, uma FIFO trocada por `rename` ainda pode bloquear a abertura. A sonda com 60 execucoes do `diagnostico` contra um laco de troca teve 0 penduradas. Exige escrita no diretorio 0700 do proprio usuario; risco residual, so de disponibilidade. Endurecimento possivel: abrir com `<>` (no Linux nao bloqueia em FIFO) ou com `timeout`; `<>` exige permissao de escrita no registro, entao a decisao fica com o Tech Lead. **Aceito pelo solicitante em 2026-10-21 como RSK-76.**
- **OBS-4:** a regra "mesmo alvo" do descarte compara o caminho local canonico byte a byte. Grafias diferentes do mesmo alvo canonizam igual e retomam (`qa_d15`). Um registro de outro alvo nunca apaga nada (`qa_d16`). Um registro plantado pelo proprio usuario, que nomeie um arquivo do diretorio do alvo com nome no padrao e o mesmo `dev|inode`, seria apagado. Vale por construcao da barreira (estado 0700 do usuario) e nao e caminho de ataque de terceiro. **Aceito como RSK-76.**

### Execucoes (ciclo 2)

| Verificacao | Resultado |
|---|---|
| `bash tests/run.sh qa_retomada_b7a` | APROVADA, 41/41 |
| `bash tests/run.sh retomada` (4 arquivos) | APROVADA, 132 ok e 1 pulado (root) |
| `bash tests/run.sh json` | APROVADA, 62/62 |
| `shellcheck tests/integracao/qa_retomada_b7a_test.sh` | limpo |
| `bash scripts/verificar-remocao-de-casos.sh` | 1739 -> 1739, nenhuma reducao |

- Nenhum codigo de implementacao nem teste do developer foi alterado pelo QA nesta etapa, exceto a correcao de RNF-24 na propria suite do QA.

## Achados consolidados

| ID | Ciclo | Severidade | Situacao |
|---|---|---|---|
| QA-B7A-01 | 1 | P1 | Fechado no ciclo 2 |
| QA-B7A-02 | 1 | P2 | Fechado no ciclo 2 |
| OBS-1 | 1 | Observacao | Aberto como redacao (DIV-203, BA) |
| OBS-2 | 1 | Observacao | Sem acao (dupla conferencia) |
| OBS-3 | 2 | Observacao (TOCTOU) | Aceito como RSK-76 |
| OBS-4 | 2 | Observacao (limite da barreira) | Aceito como RSK-76 |

**Veredito do QA: APROVADO, 2026-10-21 (ciclo 2), sem achado P0 ou P1 aberto.**
