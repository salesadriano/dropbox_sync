---
id: 2026-10-18-1745-skip-upload-condicionado
tipo: decisao
escopo: projeto
titulo: Skip do upload condicionado ao content_hash remoto (RSK-23)
data: 2026-10-18
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst
status: ativa
ref: docs/prompts/2026-10-18_1745_integridade-de-dados-p1.md
---

O upload só dispensa o envio quando o `content_hash` remoto, obtido por `get_metadata`, for igual ao do arquivo local. O cache local passa a ser apenas otimização do cálculo de hash e não decide mais sozinho. Isso restabelece o invariante do RSK-23. A implementação fica na fase 3 (`2026-10-18-1745-melhorias-em-fases`).
