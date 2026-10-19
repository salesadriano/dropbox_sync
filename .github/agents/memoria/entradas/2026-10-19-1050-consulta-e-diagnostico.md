---
id: 2026-10-19-1050-consulta-e-diagnostico
tipo: decisao
escopo: projeto
titulo: Comandos verificar e diagnostico, checagem de espaco que recusa e autocompletar bash
data: 2026-10-19
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst
status: ativa
ref: docs/prompts/2026-10-19_1050_backlog-fase-1-consulta-diagnostico.md
---

Decididos pelo solicitante em 2026-10-19 (fase 1 do backlog):
- **`dbx verificar` (alias `verify`, F-11):** compara local × remoto por `content_hash`, sem transferir nada.
- **`dbx diagnostico` (alias `doctor`, F-22):** checa dependências, credencial, conectividade e escopos.
- **F-21:** o `upload` e o `sync --enviar` consultam o espaço livre antes de enviar e recusam, sem escrever nada, quando o envio não cabe. O `--forcar` pula a checagem; em simulação, o plano apenas avisa.
- **F-19:** `completions/dbx.bash` instalado pelo `install.sh` em `~/.local/share/bash-completion/completions/dbx`; `dbx completar bash` imprime o script.

Divergências do BA decididas pelo Tech Lead:
- **DIV-33:** `--forcar` pula as checagens prévias: no `upload`, o hash e o espaço; no `sync`, só o espaço, e só com `--enviar` (`--forcar --receber` dá código 2). O RF-64 ganha `--forcar`/`--force` no `sync`.
- **DIV-34:** o `verificar` sai com 11 quando há divergência, com mensagem própria e sem a mensagem padrão de `integridade`; a taxonomia 0 a 15 está cheia (RF-35).
- **DIV-35:** escopos exigidos: `account_info.read`, `files.metadata.read`, `files.content.read` e `files.content.write`. O `lib/auth` expõe o `scope` da resposta de renovação; sem o campo, a checagem é aviso.
- **DIV-36:** encerrada; `tail` e `df` já estão no preflight desde a fase 4.
- **DIV-37:** o alias de `completar` é `completion`.
