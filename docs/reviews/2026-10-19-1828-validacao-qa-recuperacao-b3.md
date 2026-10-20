# Validacao independente do QA — Revisoes, restauracao e lixeira (fase 3)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: F-07 e F-20; porte **G** (validacao independente, regra 40)
- Agent: QA Expert; data 2026-10-19; ciclos: 3
- Branch / base: `feature/recuperacao-b3` sobre `develop` @ `ef1efb2`, sem commit
- Registro de entrega: [2026-10-19-1828-registro-recuperacao-b3.md](2026-10-19-1828-registro-recuperacao-b3.md)
- Pareceres do desenvolvedor: [TDD](2026-10-19-1828-parecer-tdd-recuperacao-b3.md) e [conformidade](2026-10-19-1828-parecer-conformidade-recuperacao-b3.md)
- Fonte deste documento: resumo do veredito do QA repassado pelo Tech Lead; o QA nao entregou arquivo proprio. Nao ha transcricao literal.

## Suite do QA

`tests/integracao/qa_recuperacao_b3_test.sh`, 30 casos. Aprovada pelo solicitante tres vezes, pela regra 12 (qualquer mudanca volta para reaprovacao):

| Versao | sha256 (prefixo) | Casos | Mudanca |
|---|---|---|---|
| Ciclo 1 | `c34c2120...` | 26 | Suite inicial |
| Ciclo 2 | `e77153d5...` | 30 | Massas de item apagado com `path_lower`; E08 e D03 endurecidos; E13, R09, R10 e L03 novos |
| Ciclo 2 (final) | `2044fa23...` | 30 | Correcao do padrao de contagem do R10, que nunca casava |

## Ciclo 1 — REPROVADO

| Id | Severidade | Achado | Desfecho |
|---|---|---|---|
| QA-B3-01 | alta | `rev` alheio ao arquivo saia 4, e nao 2 (DIV-59) | Corrigido no ciclo 2 (sai 2) |
| QA-B3-02 | media, seguranca | A guarda do expurgo lia so o `.tag`; um `DeletedMetadata` de outro caminho autorizava o `permanently_delete` | Corrigido no ciclo 2 (exige `path_lower` igual ao alvo) |
| QA-B3-03 | baixa | Upload com `in_progress` sai 10 | Aceito: o upload passa por `lib/transfer` e mantem 10; so comentario ajustado |
| Observacao | - | Na restauracao de pasta, item devolvido fora da pasta pedida | Virou a DIV-78 (falha, 14) |

Das 26 tentativas de ataque, so a QA-B3-02 alcancou o `permanently_delete`.

## Ciclo 2 — REPROVADO

| Id | Severidade | Achado | Desfecho |
|---|---|---|---|
| QA-B3-04 | media, seguranca | NUL `\u0000` em `path_lower` contornava a guarda, porque `lib/json` o descartava | Corrigido no ciclo 3 (`lib/json` recusa U+0000 como `malformado`) |
| QA-B3-05 | baixa | Chave duplicada, com a ultima vencendo | Corrigido no ciclo 3 (a guarda recusa com 10 qualquer documento com chave repetida) |
| QA-B3-06 | media | Descida sem fim quando a listagem traz a propria pasta | Corrigido no ciclo 3 (so descendente estrito e conjunto de visitados) |

## Ciclo 3 — APROVADO

Duas observacoes baixas, aceitas:

- O corpo HTTP e cortado no primeiro NUL cru; isso nao da poder extra a um servidor hostil.
- A fila da descida e quadratica (6,4 s com 4000 pastas); a fila por indice vai para a fase 9 (desempenho).

O QA avaliou que "a ultima chave vence" nos outros consumidores do `lib/json` nao e explotavel.

Resultado da suite do QA no ciclo 3: 30 aprovados, 0 reprovados (contagem do Senior Developer).

**Veredito do QA: APROVADO, 2026-10-19 (ciclo 3).**
