# Registro de Entrega — Atualizacao do Ambiente de IA e Protocolos de Governanca (Upstream ai_team)

> Registro da demanda de atualizacao do ambiente de IA conforme regra 41 do protocolo comum e a skill `review-documentation`.

## Identificacao da demanda

| Campo | Valor |
|---|---|
| Demanda | Atualizacao do projeto com protocolos, skills, agents, mods, hooks e instrucoes vigentes |
| Data / Hora | 2026-10-18 17:10 |
| Dominio | Governanca / Pacote de Agents e Protocolos |
| Porte | **G (estrutural)** — atualizacao transversal de protocolo, personas, memoria, hooks e scripts |
| Instancia | `myNote/Adriano Sales Santos` |
| Modelo upstream | `git@github.com:salesadriano/ai_team.git` no commit `e3f1deb44a6d2fdb4b94dff51a83f26a88284f82` |
| Branch de trabalho | `feature/atualiza-ambiente-ia` |
| Branch principal | `develop` (conforme entrada de memoria `branch-principal`) |
| Log de prompt | [2026-10-18_1710_atualiza-ambiente-ia.md](../prompts/2026-10-18_1710_atualiza-ambiente-ia.md) |

---

## Contexto e Motivacao

O projeto `dropbox_sync` mantinha a adocao do modelo upstream `ai_team` no commit `ed927bb18678241c777346e7ad94ac0d0f2dd5c4` (de 2026-10-07). O modelo upstream evoluiu com incorporacoes de governanca operacional (mods de governanca transformados em skills do pacote), hooks nativos para clientes de IA (Claude Code), rotina de limpeza de worktrees, trava serializada no detector de alteracoes externas, novas opcoes no indexador de memoria e exigencia de execucao e registro local da suite completa antes do push para PR.

Esta demanda atualiza o ambiente do projeto para o HEAD do upstream (`e3f1deb44a6d2fdb4b94dff51a83f26a88284f82`), mantendo o projeto autossuficiente e preservando as particularidades da stack.

---

## Modificacoes e Adicoes Estruturais

### 1. Protocolo comum e regras (`.github/agents/AGENTS.md`)
- **Regra 40 (Portes e Fluxo P):** Criterios objetivos detalhados para portes P, M e G. Introducao do *Fluxo P*, permitindo implementacao direta pelo Tech Lead sob os dois gates unificados em parecer combinado no registro curto (`registro-de-entrega-curto-template.md`) e validacao do QA por amostragem (1 em N registros P, padrao N = 5).
- **Regra 46 (Sincronizacao e Limpeza de Worktrees):** Inclusao da rotina oficial de limpeza pos-merge via `sh scripts/limpar-worktrees.sh` (dry-run e `--executar`).
- **Regra 47 e 48 (Detector e Trava):** Serializacao da escrita da linha de base com arquivo de trava `O_EXCL`, aviso preventivo ao registrar arquivo identico ao HEAD e recusa formal de registrar diretorio diretamente.
- **Suite completa local antes do push:** Atualizacao da Regra 8 de `protocolo-tdd` e dos passos 10 e 11 do *Ciclo do developer*: antes de todo push que abre ou atualiza PR para `develop` ou `master`, a suite completa deve rodar localmente pelo comando oficial (`sh scripts/suite-completa.sh`) e ter contagens literais registradas no registro de entrega.

### 2. Personas dos agents (`.github/agents/`)
- `tech-lead.agent.md`: Incorporacao do Fluxo P, selecao de faixas de modelos para delegacoes (`faixa-do-modelo.sh`, `avaliar-troca-de-modelo.sh`), gestao de amostragem de QA em P, rotina pos-merge de limpeza de worktrees e cobranca da suite completa local no push.
- `senior-developer.agent.md`: Alinhamento do escopo para demandas M e G, suite completa local no push para PR, registro e confirmacao no worktree correto pelo detector.
- `qa-expert.agent.md`: Validacao por amostragem em P (sem mutantes nem `qa-*`), validacao independente em secao do registro curto em M, e gestao do comando oficial da suite completa.
- `documentation-writer.agent.md`: Suporte ao template de registro curto para portes P e M.

### 3. Templates oficiais (`.github/agents/templates/`)
- `registro-de-entrega-curto-template.md`: Template oficial unico para portes P e M, integrando gates de TDD e conformidade e validacao do QA em um unico arquivo.
- `evidencia-testes-template.md`: Inclusao do campo de suite completa local no push para PR.
- `templates/README.md`: Catalogo de templates atualizado.

### 4. Skills transversais e de governanca (`.github/skills/`)
- Novas skills adicionadas a partir dos mods upstream:
  - `entrega-por-porte`: Regras e referencias para enquadramento de porte e conducao do Fluxo P.
  - `governanca-por-hooks`: Configuracao de hooks ativos de cliente de IA para automacao de guardas e contexto.
  - `instrucoes-do-projeto`: Manutencao de instrucoes do projeto (`CLAUDE.md`) enxutas e sem drift.
  - `memoria-por-janela`: Diretrizes de bootstrap enxuto da memoria operacional por janela temporal.
  - `selecao-de-modelo`: Racionalizacao de custos e desempenho via selecao de modelo por classe de tarefa e complexidade.
  - `superficie-de-contrato`: Conferencia de contagens e copias sincronizadas de contratos publicos.
  - `e2e-reexecucao-parcial`: Metodologia e utilitarios para diagnostico e reexecucao seletiva de suites E2E.
- Skills atualizadas: `gitflow`, `protocolo-tdd`, `protocolo-conformidade`, `review-documentation` e `SKILL_HIERARCHY.md`.

### 5. Scripts utilitarios e guardas (`scripts/`)
- `alteracoes-externas.sh`: Atualizado com trava `O_EXCL`, aviso para arquivo identico ao HEAD e rejeicao de diretorios.
- `limpar-worktrees.sh`: Novo utilitario para inspecao e higienizacao de worktrees mesclados.
- `memoria-index.sh`: Atualizado com suporte a `--desde <data>`, `--todas` e deteccao de `agentes: todos` fora de decisao de pacote.
- `suite-completa.sh` e `suite-completa.cmd`: Utilitario wrapper e definicao do comando oficial de testes do projeto (`bash tests/run.sh`).
- `guarda-de-comandos.txt`: Arquivo de padroes de bloqueio do guarda de comandos.
- `tabela-de-modelos.tsv`: Tabela local de modelos por faixa (economico/padrao/maximo).
- Utilitarios de governanca integrados: `verificar-instrucoes-do-projeto.sh`, `conferir-copias.sh`, `faixa-do-modelo.sh`, `avaliar-troca-de-modelo.sh`, `specs-nao-executadas.sh`.
- Baterias de testes Bats correspondentes em `scripts/tests/`.

### 6. Hooks de IA (`.claude/settings.json`)
- Ativados hooks nativos para o Claude Code:
  - `SessionStart`: Executa `resumo-de-estado.sh` para diagnosticar estado do repositorio no inicio de cada sessao.
  - `PreToolUse` (matcher Bash): Executa `guarda-de-comandos.sh` para interceptar comandos arriscados antes da execucao.

### 7. Instrucoes do projeto (`CLAUDE.md`)
- Atualizado com novos comandos, Fluxo P, hooks ativos, contexto de persistencia SQLite/estado e semantica de suite completa local.
- Validado por `scripts/verificar-instrucoes-do-projeto.sh` sem qualquer drift.

### 8. Memoria operacional
- Nova entrada ativa [2026-10-18-1715-adocao-modelo](../../.github/agents/memoria/entradas/2026-10-18-1715-adocao-modelo.md) registrando a adocao do commit `e3f1deb44a6d2fdb4b94dff51a83f26a88284f82`.
- Entrada anterior `2026-10-07-1256-adocao-modelo` marcada como `substituida`.
- Indice de memoria regenerado em `.github/agents/memoria/INDICE.md`.

---

## Verificacoes e Gates Executados

| Verificacao | Comando | Resultado |
|---|---|---|
| Validacao de links de skills | `sh scripts/validate-skill-links.sh` | **Aprovado** (`All local skill references are valid.`) |
| Validacao de memoria | `sh scripts/memoria-index.sh --check` | **Aprovado** (`entradas validas: 4`) |
| Inspecao de drift em instrucoes | `sh scripts/verificar-instrucoes-do-projeto.sh` | **Aprovado** (`✔ sem drift`) |
| Caminhos absolutos do modelo | `grep -rnF "/home/sales/ai_team" .github scripts .claude` | **Aprovado** (nenhuma ocorrencia, projeto 100% autossuficiente) |
| Linter estatico | `shellcheck lib/*.sh commands/*.sh bin/* scripts/*.sh` | **Aprovado** (zero erros/avisos) |
| Suite completa do projeto | `bash tests/run.sh` | **Aprovado** (608 aprovados, 0 reprovados, 2 pulados) |
| Deteccao de alteracoes externas | `sh scripts/alteracoes-externas.sh --detectar` | **Aprovado** |

---

## Conclusao

O ambiente do projeto `dropbox_sync` esta plenamente atualizado e sincronizado com o upstream `ai_team` no commit `e3f1deb44a6d2fdb4b94dff51a83f26a88284f82`, incorporando todas as evolucoes de protocolos, skills, personas, hooks e utilitarios, em perfeita conformidade com as regras de governanca.
