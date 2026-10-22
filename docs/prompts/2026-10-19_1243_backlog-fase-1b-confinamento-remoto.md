---
date: 2026-10-19
hora: "1243"
domain: seguranca / confinamento remoto
porte: M
status: em-andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-19-1243-registro-confinamento-remoto-b1b.md"
---

# backlog-fase-1b-confinamento-remoto

## Prompt 1 — 2026-10-19 (após o merge da PR #40)

> gh pr merge 40 --merge

**Intenção:** o solicitante mesclou a PR #40 (fase 1 do backlog, `c1c1f88`), o que retoma a instrução "analise e implemente os itens no backlog". Segue a fase 1b, que é extra e foi decidida pelo solicitante depois de um achado do QA da fase 1: F-36 e F-37.

**Inferências e decisões do solicitante:**
- **F-36:** a `raiz_remota` gravada na credencial passa a valer em todo comando. Um caminho remoto fora dela é recusado antes de qualquer chamada à API, como já define o RNF-20(b). Com a raiz padrão `/`, nada muda.
- **F-37:** um caminho remoto com quebra de linha (ou outro caractere de controle) é recusado.
- **RNF-20(c)** (raiz local configurável): o solicitante escolheu **só a remota agora**. A raiz local vira F-38 no backlog, com o RNF-20(c) marcado como não implementado.
- **Porte M:** defeito de segurança (confinamento) com alta criticidade, sem estado novo e sem mudança de arquitetura. Branch `bugfix/confinamento-remoto-b1b`, a partir de `develop` (`c1c1f88`); nenhum PR aberto.
