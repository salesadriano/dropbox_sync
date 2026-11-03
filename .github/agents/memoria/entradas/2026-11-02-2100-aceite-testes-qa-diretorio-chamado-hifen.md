---
id: 2026-11-02-2100-aceite-testes-qa-diretorio-chamado-hifen
tipo: aceite
escopo: projeto
titulo: Solicitante aceita a suite do QA que prova a travessia imune a pasta chamada hifen
data: 2026-11-02
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-11-02-2100-registro-diretorio-chamado-hifen.md
---

Aceite do solicitante pela regra 12 (prompt 4, 2026-11-02, "accept the sha"), na demanda `diretorio-chamado-hifen` (defeito em producao na 2.3.1), valendo para as duas linhas (`develop` e `support/bash-4.2`):

- `tests/integracao/qa_diretorio_hifen_test.sh` (8 casos: pasta `-` na raiz, como primeiro e como ultimo irmao, aninhada `a/-/b`, pastas `--`/`-x`/`-` juntas, enumeracao `sl/-` com `sl/SL`, arquivo chamado `-`, pasta `-` so do destino sob `--espelhar`; reprova 6 de 8 sem a correcao): sha256 `014c29de61287029d44fbc01d8ba53944ddde11c4943df1b309dfd65ebe38833`.

Na mesma demanda o solicitante decidiu (prompt 3) levar a correcao tambem a linha legada.
