# Aplicar o protocolo atual (plugin ai-team 1.0.9)

**Branch:** `chore/protocolo-atual` (de `origin/develop`)
**Porte:** G. `scripts/porte.sh` passa a existir nesta demanda. Regra transversal do pacote (sincroniza `AGENTS.md` de 48 para 51 regras, templates e scripts do protocolo) e adocao da regra 51 (inventario de testes) sobre 107 arquivos e 2757 casos.

## Prompt 1 — 2026-10-27

> aplique o protocolo atual

**Contexto:** o solicitante recarregou os plugins (`/reload-plugins`): ai-team 1.0.8 -> 1.0.9. Diferencas: regra 51 (inventario de testes, `docs/testes/inventario-de-testes.md`, conferido por `scripts/inventario-de-testes.sh --check`) nas personas, em `protocolo-tdd` e no Fluxo P. O protocolo do projeto estava em 48 regras; o do pacote tem 51 (49 duas camadas de execucao, 50 issues vinculadas, 51 inventario).

**Decisoes do solicitante (AskUserQuestion, 2026-10-27):**
- Escopo: "Tudo agora (Recomendado)": sincronizar `AGENTS.md`, templates e scripts e montar o inventario completo.
- Script: "Ajustar aqui e propor (Recomendado)": a copia do projeto de `scripts/inventario-de-testes.sh` reconhece o nome da funcao shell (`teste_<nome>() {`, harness proprio); issue no repositorio do pacote propondo o mesmo.

**Inferencias do Tech Lead:**
- Caminhos `../skills/<nome>/...` do `AGENTS.md` e dos templates viram `ai-team:<nome>` (as skills vem do plugin, como na PR #62).
- Mantidos do projeto: `scripts/suite-completa.sh` (copia completa; o do pacote e um envelope para `.github/skills/`) e `scripts/suite-completa.cmd`. Atualizados do pacote: `alteracoes-externas.sh`, `memoria-index.sh`; novos: `memoria-extrato.sh`, `porte.sh`, `inventario-de-testes.sh` (com o ajuste), `inventario-de-testes.txt` (padrao do harness).
- Inventario: dados de apoio por arquivo gerados do historico (commit de criacao, log de prompt, sha256, entrada de aceite); 8 grupos de ~345 casos para QAs em paralelo; o Tech Lead monta o documento e roda `--check`.

**Andamento (Tech Lead):** `AGENTS.md` (51 regras), templates e scripts sincronizados; caminhos `../skills/` convertidos para `ai-team:<nome>`; `CLAUDE.md` com 51 regras, comandos novos e o passo do inventario no ciclo; `scripts/porte-caminhos.txt` do projeto (o `porte.sh` mede esta demanda como G: template operacional e scripts do protocolo, 580 linhas). Issue no pacote: salesadriano/ai_team#60. Inventario: 8 QAs em paralelo por grupos.

**Inventario e aceites:** `docs/testes/inventario-de-testes.md` montado (8 grupos de QA; nomes de funcoes de uma linha corrigidos depois de ajustar a precedencia no script); `--check`: 107 arquivos, 2757 casos, 0 divergencias. Cinco suites `qa_*` sem aceite do sha256 atual. **Decisao do solicitante (AskUserQuestion, 2026-10-27):** "Reaprovo as 5 (Recomendado)": entrada `2026-10-27-1500-aceite-reaprovacao-inventario`.
