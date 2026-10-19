---
id: 2026-10-19-1023-plano-do-backlog
tipo: decisao
escopo: projeto
titulo: Backlog implementado em dez fases sequenciais, PKCE fora
data: 2026-10-19
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst, dba
status: ativa
ref: docs/prompts/2026-10-19_1023_backlog-fase-0-pendencias.md
---

Por decisão do solicitante (2026-10-19), o backlog é implementado em fases sequenciais, cada uma com branch, gates, QA e PR próprios:
0. Pendências técnicas.
1. Consulta e diagnóstico (F-11, F-22, F-21, F-19).
2. Trava de concorrência (F-12) e `lib/tmp` (o restante do F-31: OBS-02, OBS-03, OBS-04).
3. Recuperação (F-07, F-20).
4. Filtros e banda (F-13, F-17).
5. Compartilhamento (F-15, F-16).
6. Retenção (F-10).
7. Cursor e retomada (F-14, F-03).
8. Perfis (F-18, reabre o DP-05).
9. Desempenho (F-34, F-08, F-09), com medição antes e depois.

O PKCE (F-35) continua fora. A trava vem antes de agendamento e paralelismo, e as fases destrutivas ou com estado novo são porte G.

Decisões do Tech Lead para a fase 0:
- O-QA-2 fica como está.
- O-QA-3 é documentado.
- O-7 mantém o comportamento seguro, com emenda ao RF-38(b).
