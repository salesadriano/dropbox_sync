---
id: 2026-10-18-1745-selecao-inclui-auditorias-lib
tipo: decisao
escopo: projeto
titulo: Todo diff em lib/*.sh seleciona os quatro testes que auditam lib/ inteiro
data: 2026-10-18
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert
status: ativa
regra: protocolo-tdd Regra 8
ref: docs/reviews/2026-10-18-1745-registro-integridade-de-dados-p1.md
---

`json_test`, `http_test`, `preflight_test` e `composicao_test` auditam estaticamente todo o `lib/*.sh` (RNF-24, RSK-27, preflight). Por isso entram na execução seletiva de qualquer diff que toque `lib/`, e não só quando o módulo testado for carregado. Na fase P1 essa lacuna deixou passar três capturas proibidas até a suíte completa local reprovar o commit `d4ef8a1`.
