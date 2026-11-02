---
id: 2026-11-02-1115-aceite-testes-qa-ignorar-cdpath
tipo: aceite
escopo: projeto
titulo: Solicitante aceita a suite do QA que prova o sync e a travessia imunes a CDPATH hostil
data: 2026-11-02
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-11-02-1115-registro-ignorar-cdpath.md
---

Aceite do solicitante pela regra 12 (AskUserQuestion, 2026-11-02, "Accept (Recommended)"), na demanda `ignorar-cdpath` (defeito em producao), valendo para as duas linhas:

- `tests/integracao/qa_cdpath_test.sh` (8 casos: `upload` de pasta e paralelo, `download` de pasta, `verificar` nos dois sentidos, `sync` nos dois sentidos com `--espelhar --confirmar`, em blocos e paralelo, cada um contra `CDPATH` hostil e comparado a linha de base, inclusive arvores e isca por `cksum`): sha256 `57be5d41d9c76c6a76561d6b75d08b2e28deb8abab75814d2a3419424fb1326d` (uma linha trocada pelo Tech Lead, `$(printf ...)` por `$'...'`, exigencia da auditoria do `json_test`).

Na mesma rodada o solicitante decidiu corrigir na release tambem `BASH_ENV`/`ENV` e `SHELLOPTS`/`BASHOPTS` exportados (`DIV-392`).
