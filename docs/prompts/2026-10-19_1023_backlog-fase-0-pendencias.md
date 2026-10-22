---
date: 2026-10-19
hora: "1023"
domain: backlog / manutencao
porte: M
status: em-andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-19-1023-registro-pendencias-backlog-p0.md"
---

# backlog-fase-0-pendencias

## Prompt 1 — 2026-10-19 1023

> analise e implemente os itens no backlog

**Intenção:** analisar o backlog de `docs/requisitos/funcionalidades-candidatas.md` e as ressalvas das quatro fases anteriores, e implementá-los.

**Inferências e decisões do solicitante:**
- **Inventário do Tech Lead:**
  - o F-06 (espelhamento) já existe como `sync --espelhar`;
  - em aberto: F-03, F-07 a F-22, F-34 e F-35, mais as ressalvas O-QA-2, O-QA-3, O-5, O-7 e RSK-43 e os status desatualizados do F-23 ao F-33.
- **Escolhas do solicitante:**
  - **sem estado:** consulta e diagnóstico (F-11, F-22, F-21, F-19), recuperação (F-07, F-20), compartilhamento (F-15, F-16), filtros e banda (F-13, F-17);
  - **com estado:** F-12, F-14 e F-03, F-10, F-18 (reabre o DP-05);
  - **adiados na fase 3:** entra o desempenho (F-34, F-08, F-09), com medição antes e depois; o **PKCE (F-35) continua fora**;
  - **pendências técnicas** como primeira fase.
- **Plano do Tech Lead, em fases sequenciais:**
  - **0:** pendências (esta fase, porte M);
  - **1:** consulta e diagnóstico;
  - **2:** trava de concorrência (antes de agendamento ou paralelismo);
  - **3:** recuperação;
  - **4:** filtros e banda;
  - **5:** compartilhamento (exige que o solicitante habilite o escopo `sharing.write` no App Console e reautorize);
  - **6:** retenção (G);
  - **7:** cursor e retomada (G);
  - **8:** perfis (G);
  - **9:** desempenho (G).
  Entrada de memória: `2026-10-19-1023-plano-do-backlog`.
- **Decisões do Tech Lead para a fase 0:**
  - O-QA-2 fica como está (o RF-48 reconhece a primeira execução antes do plano);
  - O-QA-3 é documentado (o `historico/` é imutável e cita skills removidas sem link);
  - O-7 mantém o comportamento seguro e o RF-38(b) é emendado;
  - O-5 é refatorado;
  - RSK-43 é testado com o GNU coreutils disponível como `gnustat`;
  - o BA atualiza os status do F-23 ao F-33;
  - o plano em fases anterior é encerrado.
- **Porte M** (manutenção e testes, sem contrato novo). Branch `chore/pendencias-backlog-p0`, a partir de `develop` (`73769c8`); nenhum PR aberto.
