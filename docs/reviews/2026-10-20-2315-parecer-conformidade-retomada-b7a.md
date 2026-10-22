# Parecer de Conformidade — Retomada entre execucoes, F-03 (fase 7a)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: retomada de `upload` e `download` de arquivo acima de 150 MiB entre execucoes (F-03, RF-101 a RF-109); porte **G**
- Agent responsavel pela alteracao e pela verificacao: Senior Developer (gate local, regra 14); validacao independente a cargo do QA Expert
- Data: 2026-10-20 (ciclo 1); 2026-10-21 (ciclo 2)
- Ciclos: 2
- Branch / base: `feature/retomada-b7a` sobre `develop` @ `3c9a702`, sem commit
- Log de prompt: [2026-10-20_2315_backlog-fase-7a-retomada.md](../prompts/2026-10-20_2315_backlog-fase-7a-retomada.md)
- Registro de entrega: [2026-10-20-2315-registro-retomada-b7a.md](2026-10-20-2315-registro-retomada-b7a.md)
- Tambem: [2026-10-20-2315-parecer-tdd-retomada-b7a.md](2026-10-20-2315-parecer-tdd-retomada-b7a.md)
- Validacao do QA: [2026-10-20-2315-validacao-qa-retomada-b7a.md](2026-10-20-2315-validacao-qa-retomada-b7a.md)

## Gate — protocolo-conformidade

**Parecer (ciclo 1): APROVADO para o handoff ao QA.** Ciclo 2: APROVADO.

### Verificacoes (ciclo 1)

| Regra | Verificacao |
|---|---|
| O estado so acelera (P1) | Integridade provada na execucao: prefixo relido antes do 1o `append_v2`; `correct_offset` so = confirmado ou confirmado + voo com SHA relido igual; `content_hash` do arquivo inteiro no `finish`; `.part` inteiro (pela barreira) contra `get_metadata` e `Dropbox-API-Result` antes do `mv`; registro removido so depois do `finish`/`mv` (C5) |
| Estado invalido nunca faz falhar (P2) | Leitor limitado (16 KiB, contagem, regex, `LC_ALL=C`, por descritor); qualquer anomalia descarta com uma linha e segue do zero; ligacao, alheio ou diretorio no lugar: nao lido, nao apagado, sem retomada; diretorio de estado inutilizavel: segue sem retomada (DIV-190); codigos iguais com e sem registro (`rmo11`) |
| `.part` so pela barreira | `dbx_state_retomada_part_barreira` (padrao, sem barra, nao ligacao, regular, dono, `dev\|inode`) em todo descarte (registro invalido, `rev` mudou, recomeco, poda, `unlink`, remoto sumiu); anexo so pelo descritor conferido e reaberto por `/dev/fd` |
| Segredos fora da saida (P3, C6) | `session_id` so no registro 0600 em dir 0700; `DBX_TRANSFER_LIDO` esvaziado apos o `start`; mensagens sem `session_id`; nada em `argv`/ambiente (o `continue-at` e numero, na configuracao do cliente) |
| Respostas inesperadas | `too_large` -> 10; `200`/`206` de outro inicio nunca anexados (status 33 do cliente); total ou `rev` incoerente descartam; codigos so 0..15, nenhum novo |
| Camadas | `lib/state` so persiste e valida, sem rede; `lib/transfer` decide quando gravar; `lib/cmd` orquestra o recebimento; comandos so ligam e emitem; `lib/http` continua o unico ponto de rede; `sync` nunca liga a retomada |
| Gemeos | barreira, leitor limitado e gravacao atomica em um lugar so (`lib/state`); limiar de 150 MiB so em `lib/transfer` (o download o carrega) |
| shellcheck / supressoes | 0 achados (depois de uma supressao SC2016 justificada no texto da ajuda), supressoes SC2034/SC2174 justificadas na linha |

### Achados (ciclo 1)

| ID | Severidade | Achado |
|---|---|---|
| CNF-01 | Menor | `download` de arquivo para destino em arquivo ganhou um `get_metadata` (leitura) antes do recebimento, inclusive ate 150 MiB (DIV-192). Saida e codigos de hoje preservados; selecao de regressao verde. |
| CNF-02 | Menor | Custo por parte: uma regravacao do registro e um SHA-256 da cadeia do prefixo (cresce com N partes; ~ms por parte ate dezenas de GB). Aceito por DIV-172/RSK-72. |
| CNF-03 | Info | O cliente anexa um `206` de total errado antes da conferencia; o `.part` e descartado antes de qualquer uso (DIV-193). |

**Veredito ciclo 1: aprovado** para o handoff ao QA. As divergencias DIV-191 a DIV-202 estao no parecer TDD, secao 7.

## Ciclo 2 (QA-B7A-01 e QA-B7A-02)

Correcoes em `lib/state.sh` e `lib/cmd.sh` conforme o parecer TDD, ciclo 2. Verificacao de conformidade:

- **Camadas:** a correcao do QA-B7A-01 ficou no leitor limitado e na trava de leitura de `lib/state`, sem rede e sem decisao de comando. A correcao do QA-B7A-02 usa a barreira de identidade ja existente; nenhum codigo novo de barreira foi criado.
- **Gemeos:** `_dbx_state_ler_limitado` e `_dbx_state_trava_ler` passam a conferir arquivo regular na mesma forma. A barreira do `.part` continua em um lugar so.
- **Segredos (C6):** nenhuma saida nova. A correcao nao escreve `session_id` em mensagem.
- **Codigos de saida:** sem codigo novo; `diagnostico` e `unlink` concluem com 0..15 na presenca de FIFO.
- **shellcheck:** 0 achados em `lib/*.sh commands/*.sh bin/* scripts/*.sh` e `-x` nos testes novos.

**Veredito ciclo 2: aprovado.** Sem achado novo.

## Divergencias com efeito de conformidade

- **DIV-192 (CNF-01):** `get_metadata` em todo download para arquivo. Custo registrado no RSK-72; medicao na fase 9 (F-34).
- **DIV-196:** `too_large` sai 10 em todas as sessoes, inclusive `sync --enviar`. Mudanca de comportamento, na PR.
- **DIV-185:** `unlink` apaga registros e `.part` que passam na barreira e lista os demais. Revisa a D1 do DBA.
- **DIV-203:** a redacao da RF-103(b) foi alinhada pelo BA ao leitor do `correct_offset` em cadeia JSON (escopo v1.22).

## Achados consolidados

| ID | Ciclo | Severidade | Situacao |
|---|---|---|---|
| CNF-01 | 1 | Menor | Aceito (DIV-192), com custo registrado |
| CNF-02 | 1 | Menor | Aceito (DIV-172, RSK-72) |
| CNF-03 | 1 | Info | Descarte antes de uso (DIV-193) |
