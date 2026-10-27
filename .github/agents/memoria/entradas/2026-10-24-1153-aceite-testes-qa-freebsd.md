---
id: 2026-10-24-1153-aceite-testes-qa-freebsd
tipo: aceite
escopo: projeto
titulo: Solicitante aprova a suite do QA do suporte a FreeBSD e reaprova a da fase 4
data: 2026-10-24
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-10-24-1153-registro-suporte-freebsd.md
---

O solicitante aprovou explicitamente (AskUserQuestion, 2026-10-24):
- `tests/integracao/qa_freebsd_b13_test.sh` (novo, 5 casos, sha256 `fb7e9191…ca7488`);
- `tests/integracao/qa_docs_aliases_p4_test.sh` (reaprovacao; o filtro dos utilitarios de resumo passou a incluir `sha256`, DIV-354; sha256 `17192612…708467`).

Reaprovacao (AskUserQuestion, 2026-10-25): `tests/integracao/qa_freebsd_b13_test.sh` com 10 casos (o caso da recusa sem fdescfs saiu pela decisao "Conferir pelo descritor"; entraram 6 casos do comportamento novo), sha256 `20420830…711d006b`.

Reaprovacao (AskUserQuestion, 2026-10-25): `tests/integracao/qa_trava_tmp_b2_test.sh` (suite da fase 2), caso `qa_b2_01` corrigido para aceitar as 2 travas (par e raiz, RF-132) quando a vencedora e um `sync`; defeito do teste anterior a demanda; sha256 `2114eaa2…df6d3333`.

Aprovacao (AskUserQuestion, 2026-10-26): `tests/integracao/qa_leitura_exata_b14_test.sh` (novo, 10 casos, RF-173, TC-FBSD-25..27; leitura exata sob o duble do `head` do FreeBSD), sha256 `c7de4ca5…76c920b8`.

Reaprovacao (AskUserQuestion, 2026-10-26): `tests/integracao/qa_consulta_diagnostico_b1_test.sh` (sha256 `9a0dab8d…e661920a`) e `tests/integracao/qa_debug_transferencias_b12_test.sh` (sha256 `fa2d971d…e2fca987`); unica mudanca: `dd` na lista de utilitarios do PATH reduzido, exigido pelo preflight (RF-173(c)).

Aprovacao (AskUserQuestion, 2026-10-26): `tests/integracao/qa_download_curl_real_b16_test.sh` (novo, 7 casos, curl real contra servidor HTTP local; RF-171(a) emendado, destino `fd:` sem `--stderr`), sha256 `d0c1dd49…5af129`.

Aprovacao (AskUserQuestion, 2026-10-26): `tests/integracao/qa_regex_portavel_b17_test.sh` (novo, 19 casos, RF-173(e), TC-FBSD-28; repeticao de regex ate 255), sha256 `1406718c…138a015d8`.
