---
id: 2026-11-01-1200-aceite-testes-qa-suporte-bash-42
tipo: aceite
escopo: projeto
titulo: Solicitante aceita a suite do QA do instalador que escolhe a linha pelo bash do host
data: 2026-11-01
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, qa-expert
status: ativa
regra: AGENTS.md 12
ref: docs/reviews/2026-11-01-1200-registro-suporte-bash-42.md
---

Aceite do solicitante pela regra 12 (AskUserQuestion, 2026-11-01, "Aceitar a suite (Recomendado)"), na demanda `suporte-bash-42`, PARTE A:

- `tests/integracao/qa_instalador_linha_b22_test.sh` (nova, 17 casos; `--canal` hostil recusado sem chamar git nem escrever, troca e rebaixamento de linha com credencial e estado preservados, fonte sem piso ou com piso acima do host recusada antes de escrever, limites de `escolher_linha`, publicacao da legada com `--latest=false` e `--target`; 6 mutantes, todos mortos): sha256 `46ce2a6cb21eb1a2cedd6fb6ea8766e601ec7d04c82d48985d3e6fad91f0902b`

Na mesma rodada o solicitante autorizou a criacao do branch de suporte `support/bash-4.2` depois do merge da PARTE A.
