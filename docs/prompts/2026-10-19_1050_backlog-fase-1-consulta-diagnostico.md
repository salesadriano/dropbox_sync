---
date: 2026-10-19
hora: "1050"
domain: cli / consulta / diagnostico
porte: M
status: em-andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-19-1050-registro-consulta-diagnostico-b1.md"
---

# backlog-fase-1-consulta-diagnostico

## Prompt 1 — 2026-10-19 (após o merge da PR #39)

> gh pr merge 39 --merge

**Intenção:** o solicitante mesclou a PR #39 (fase 0 do backlog, `6eeb691`), o que retoma a instrução "analise e implemente os itens no backlog". Esta é a fase 1 do plano (`2026-10-19-1023-plano-do-backlog`): consulta e diagnóstico (F-11, F-22, F-21, F-19).

**Inferências e decisões do solicitante:**
- **Limpeza pós-merge** feita; detector limpo.
- **Nomes:** `dbx verificar` (alias `verify`) compara local × remoto por `content_hash` sem transferir nada (F-11); `dbx diagnostico` (alias `doctor`) checa dependências, credencial, conectividade e escopos (F-22).
- **F-21:** consulta `get_space_usage` antes do `upload` e do `sync --enviar`. Se o total a enviar exceder o espaço livre, a execução é **recusada sem escrever nada**, com código e motivo; `--forcar` pula a checagem; em simulação, o plano apenas avisa.
- **F-19:** `completions/dbx.bash` versionado; o `install.sh` o copia para `~/.local/share/bash-completion/completions/dbx`, sem sudo; `dbx completar bash` imprime o script.
- **Porte M:** comandos novos são contrato público da CLI; sem estado persistente novo nem mudança de arquitetura. Branch `feature/consulta-diagnostico-b1`, a partir de `develop` (`6eeb691`); nenhum PR aberto.
