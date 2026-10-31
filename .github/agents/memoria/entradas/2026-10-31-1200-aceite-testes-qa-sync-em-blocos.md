---
id: 2026-10-31-1200-aceite-testes-qa-sync-em-blocos
tipo: aceite
escopo: projeto
titulo: Solicitante aceita a suite do QA do sync em blocos e reaprova duas suites do QA com duble estendido
data: 2026-10-31
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-10-31-1200-registro-sync-em-blocos.md
---

Aceite do solicitante pela regra 12 (AskUserQuestion, 2026-10-31, "Accept all 3 (Recommended)"), na demanda `sync-em-blocos`:

- `tests/integracao/qa_sync_blocos_b21_test.sh` (nova, 25 casos; exclusao por diretorio observado, parcial desliga exclusao, sonda de origem vazia, cursor so ao fim integral, uma leitura por diretorio; 5 mutantes na guarda de exclusao, todos mortos): sha256 `f5e8fc366fda4d77c41db5e1541d40060a273ad1532397f11466209502bbd6f8`
- `tests/integracao/qa_cursor_b7b_test.sh` (reaprovada; aceite anterior em `2026-10-21-0713-cursor`): sha256 `15045c18464902f61c70069c513a506cd3ac8f7fa2e3ed251a82e26af4ab5159`
- `tests/integracao/qa_regex_portavel_b17_test.sh` (reaprovada; aceite anterior em `2026-10-24-1153-aceite-testes-qa-freebsd`): sha256 `87de2391cc3bd773d8884e35510ea0ce0e0f67870b0abce7332b1ba5dc62bb9e`

As duas reaprovadas so ganharam linhas (82 no total, nenhuma removida): o duble de `curl` passou a responder `list_folder` nao recursivo e `get_latest_cursor` (RF-189, RF-192). Nenhuma afirmacao foi retirada ou alterada.
