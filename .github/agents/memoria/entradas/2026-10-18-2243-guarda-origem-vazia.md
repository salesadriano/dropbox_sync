---
id: 2026-10-18-2243-guarda-origem-vazia
tipo: decisao
escopo: projeto
titulo: Guarda de origem vazia do sync --espelhar independe da memoria; nova opcao --permitir-origem-vazia
data: 2026-10-19
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst
status: ativa
ref: docs/reviews/2026-10-18-2243-validacao-qa-cache-unico.md
---

Decidido pelo solicitante depois do ciclo 2 do QA da fase 3 (QA-P3-05 a 07): no `sync --espelhar`, uma origem vazia com algo a apagar no destino é **sempre recusada**, sem nenhuma escrita, tenha ou não memória. Só passa com a opção explícita nova `--permitir-origem-vazia`; o `--confirmar` não basta. O RF-41(b) deixa de depender da linha de base.

Mantidos como defesa em profundidade, por decisão do Tech Lead:
- memória descartada desabilita exclusões na execução (RF-41(f));
- memória ilegível conta como descartada;
- a memória só é regravada depois de uma travessia completa.
