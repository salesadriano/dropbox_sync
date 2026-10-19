---
id: 2026-10-19-1243-confinamento-remoto
tipo: decisao
escopo: projeto
titulo: raiz_remota aplicada a todo comando; caminho remoto com controle recusado; raiz local adiada (F-38)
data: 2026-10-19
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst
status: ativa
ref: docs/prompts/2026-10-19_1243_backlog-fase-1b-confinamento-remoto.md
---

Decididos pelo solicitante em 2026-10-19 (fase 1b):
- **F-36:** todo caminho remoto de todo comando é confinado à `raiz_remota` da credencial; caminho fora dela é recusado antes de qualquer chamada à API (RNF-20(b)). Com a raiz `/`, nada muda.
- **F-37:** caminho remoto com quebra de linha ou outro caractere de controle é recusado.
- A raiz local configurável (RNF-20(c)) fica para o F-38 no backlog.

Decisões do Tech Lead:
- A recusa por caractere de controle usa `caminho_recusado`/13.
- A comparação de confinamento dobra a caixa só no ASCII e exige igualdade exata de bytes fora dele, independente da localidade (QA-B1B-01: `/RAİZ` escapava sob `C.UTF-8`). Ela falha fechada: pode recusar um caminho legítimo com acento em outra caixa, nunca aceita um de fora. A comparação do `sync` (RF-54) não muda.
- A raiz `/` remota não exige opt-in: é o padrão e o DP-04 define acesso à Dropbox inteira; o opt-in do RNF-20(e) vale só para o espaço local.
