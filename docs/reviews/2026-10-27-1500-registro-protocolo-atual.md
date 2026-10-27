# Aplicar o protocolo atual (plugin ai-team 1.0.9)

## Identificacao

| Campo | Valor |
|---|---|
| Pedido | "aplique o protocolo atual", depois do `/reload-plugins` (ai-team 1.0.8 -> 1.0.9) |
| Porte | G - regra transversal do pacote (protocolo de 48 para 51 regras, templates operacionais) e adocao da regra 51 sobre 107 arquivos e 2757 casos; `sh scripts/porte.sh` mede G (template operacional, scripts do protocolo, 580 linhas) |
| Log de prompt | `docs/prompts/2026-10-27_1500_protocolo-atual.md` |
| Branch / base | `chore/protocolo-atual` sobre `origin/develop` |
| Agents | Tech Lead (sincronizacao, ajuste do script, montagem e conferencia); 8 QA Expert em paralelo (inventario por grupos) |
| Data | 2026-10-27 |

## Decisao

- **Protocolo:** `.github/agents/AGENTS.md` e `.github/agents/templates/` copiados do pacote (regras 49 duas camadas de execucao, 50 issues vinculadas, 51 inventario de testes; templates novos de inventario e de briefing de subagent). Caminhos `../skills/<nome>/...` convertidos para `ai-team:<nome>`, porque as skills vem do plugin (mesmo criterio da PR #62).
- **Scripts:** do pacote, `alteracoes-externas.sh` e `memoria-index.sh` (versoes novas), `memoria-extrato.sh`, `porte.sh` e `inventario-de-testes.sh`. Mantidos do projeto: `suite-completa.sh` (copia completa; a do pacote e um envelope para `.github/skills/`) e `suite-completa.cmd`. Novos do projeto: `porte-caminhos.txt` (gatilhos M/G deste repositorio) e `inventario-de-testes.txt` (padrao do harness `tests/*_test.sh`, `^teste_...()`).
- **Ajuste do script (decisao do solicitante "Ajustar aqui e propor"):** `inventario-de-testes.sh` passa a reconhecer o caso declarado como funcao shell (`nome() {`), com precedencia sobre as aspas da linha (caso de uma linha so com string no corpo). Proposto ao pacote em salesadriano/ai_team#60.
- **Inventario (decisao do solicitante "Tudo agora"):** `docs/testes/inventario-de-testes.md` com os 107 arquivos e os 2757 casos: dados de apoio por arquivo gerados do historico (commit de criacao, log de prompt, sha256, aceite), 8 QAs por grupos de ~345 casos, montagem e resumo pelo Tech Lead.
- **Aceites:** cinco suites `qa_*` alteradas apos o aceite sem nova aprovacao (achado maior da regra 51) foram reaprovadas pelo solicitante: entrada `2026-10-27-1500-aceite-reaprovacao-inventario`.
- **`CLAUDE.md`:** 51 regras, comandos de `porte.sh`, `inventario-de-testes.sh` e `memoria-extrato.sh`, e o passo do inventario no ciclo do QA.

## Evidencias

- `sh scripts/inventario-de-testes.sh --check`: `arquivos: 107 | casos: 2757 | divergencias: 0`.
- Descoberta conferida por outro caminho: `--listar` = 2757 linhas = `grep -c '^teste_...()'` sobre `tests/unit/*_test.sh tests/integracao/*_test.sh`.
- `sh scripts/verificar-instrucoes-do-projeto.sh`: sem drift (51 regras, branch `develop`, caminhos citados existem).
- `shellcheck` dos cinco scripts sincronizados: limpo. `sh scripts/memoria-index.sh --check`: 44 entradas validas.
- Nenhum teste do produto audita `AGENTS.md`, `CLAUDE.md` ou os scripts tocados (`grep` em `tests/`). Suite completa: reprovou so em `qa_retomada_b7a::qa_d15`, o problema conhecido da retomada do download sob carga (notas da v2.1.0; falha que o solicitante decidiu ignorar); esta demanda nao altera codigo do produto.

## Gates

| Gate | Achados | Veredito |
|---|---|---|
| `protocolo-tdd` | O ajuste do script nao ganhou teste automatizado no projeto (o pacote tem os testes bats do script); a conferencia e a contagem cruzada acima. Sem codigo de produto alterado. | Aprovado com ressalva |
| `protocolo-conformidade` | Copias fieis do pacote, salvo os desvios declarados (caminhos de skill, ajuste do script proposto ao pacote, `suite-completa.sh` do projeto). | Aprovado |

## QA

- Inventario elaborado pelo QA Expert (regra 51, adocao), conferido por `--check` sem divergencia.
- Pendencias registradas pelos QAs, para as proximas demandas (sem bloqueio da adocao):
  - **"O que verifica"** foi escrito sobretudo a partir do nome do caso e do cabecalho do arquivo; ids por caso (`TC-...`) foram derivados do prefixo do nome e nao foram conferidos um a um contra a especificacao. Revisao por amostragem nas proximas validacoes do QA.
  - **Mapa de modulos** (`docs/testes/mapa-modulos.md`) sem linha propria para os testes das demandas recentes (FreeBSD, upload para pasta, paralelismo); os blocos usam o identificador derivado do arquivo e o comando por caminho.
  - **Aceite registrado so no log de prompt** em algumas suites recentes (b10, b15, b18, b19, b20, b3, p3): o log registra a decisao literal do solicitante e vale como referencia; as proximas aprovacoes passam a gerar entrada `tipo: aceite`.
  - `tests/unit/cabecalho_test.sh` foi escrito pelo QA (assunto do commit), mas nao e `qa_*` e nunca teve aceite por sha256: registrado como Senior Developer, com nota no bloco.

## Riscos e rollback

- Risco: o ajuste local do script diverge do pacote ate a #60 ser aceita; a proxima sincronizacao precisa preserva-lo.
- Rollback: `git revert` do commit da demanda.

## Aceites

- Solicitante: escopo "Tudo agora", script "Ajustar aqui e propor" e reaprovacao das cinco suites (AskUserQuestion, 2026-10-27; log de prompt e entrada de aceite).
- Tech Lead: **Aprovado com ressalvas** (as pendencias da secao QA), 2026-10-27.
