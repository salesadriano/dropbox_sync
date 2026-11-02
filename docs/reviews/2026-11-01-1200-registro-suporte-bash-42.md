# Linha legada para bash 4.2 e instalador que escolhe a linha pelo bash do host

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "crie uma nova versão da aplicação com suporte a bash 4.2 a ajuste as scripts de atualização para identificar a versão do bash e realizar a instalacao da versao adequada" |
| Porte | G - reabre a DP-07 (piso de shell) e o RNF-01; regra transversal a `lib/` e `commands/` na linha legada; ambiente de validacao novo (CentOS 7) |
| Log de prompt | `docs/prompts/2026-11-01_1200_suporte-bash-42.md` |
| Issues | nenhuma |
| Entregas | PARTE A: `feature/suporte-bash-42` -> `develop` (este registro); PARTE B: porte da linha legada, PR propria para `support/bash-4.2` (secao propria a acrescentar) |
| Agents | Tech Lead; Business Analyst (requisitos); Senior Developer (PARTE A); QA Expert (validacao independente) |
| Data | 2026-11-01 |

## 2. Decisoes

- Solicitante (AskUserQuestion, 2026-11-01): linha legada separada (contra a recomendacao de base unica); versao 2.3.0; validacao do 4.2 pela suite completa em imagem CentOS 7; suite do QA aceita (sha256 abaixo); criacao de `support/bash-4.2` autorizada.
- Tech Lead: D1 a D8 do System Design; DIV-385 a DIV-390 decididas pelas recomendacoes do BA (requisitos v1.34).
- Requisitos: secao 5.25 (F-102, RF-198 a RF-207, RNF-40, TC-B42-01 a 24), DP-07 reaberta e resolvida, RSK-108 a RSK-112.

## 3. Artefatos da demanda

| Artefato | Caminho |
|---|---|
| System Design | `docs/reviews/2026-11-01-1200-system-design-suporte-bash-42.md` |
| Parecer de evidencias (protocolo-tdd) | `docs/reviews/2026-11-01-1200-evidencia-testes-suporte-bash-42.md` |
| Parecer de conformidade | `docs/reviews/2026-11-01-1200-parecer-conformidade-suporte-bash-42.md` |
| Validacao independente do QA | `docs/reviews/2026-11-01-1200-validacao-qa-suporte-bash-42.md` |
| Aceite da suite do QA | `.github/agents/memoria/entradas/2026-11-01-1200-aceite-testes-qa-suporte-bash-42.md` |

## 4. PARTE A - arquivos

| Arquivo | Alteracao |
|---|---|
| `install.sh` | Escolha da linha pelo `BASH_VERSINFO` (>= 4.4 principal, 4.2/4.3 legada, < 4.2 recusa); piso lido do `lib/preflight.sh` da fonte; execucao local incompativel baixa a linha certa; `--canal` validado e conferido antes de escrever; aviso de troca de linha; roda no bash 4.2 |
| `bin/dbx` | Piso de bash conferido antes de qualquer outra biblioteca (no 4.2 a principal morria em `lib/output.sh` antes do preflight) |
| `lib/preflight.sh`, `commands/diagnostico.sh` | Mensagem e remedio indicam a reinstalacao pelo `install.sh` (RF-204) |
| `lib/cmd.sh` | Diretivas SC2153 com motivo (residuo da `develop`) |
| `scripts/empacotar.sh` | `--target <sha de HEAD>`; versao `-bash42` publica e reedita com `--latest=false` |
| `scripts/suite-bash42.sh` | Novo: suite (ou filtro) no `centos:7` fixado por digest, com o usuario do host |
| `README.md` | Plataformas e linhas; atualizar = rodar o `install.sh` de novo |
| `tests/unit/instalador_linha_test.sh` | Novo (19 casos) |
| `tests/unit/preflight_test.sh` | +1 caso (ordem do piso no ponto de entrada) |
| `tests/integracao/qa_instalador_linha_b22_test.sh` | Novo, suite do QA (17 casos), sha256 `46ce2a6cb21eb1a2cedd6fb6ea8766e601ec7d04c82d48985d3e6fad91f0902b` |
| `docs/testes/inventario-de-testes.md` | 113 arquivos, 2872 casos, 0 divergencias |

## 5. Testes e gates

- Seletivos: `instalador_linha` 19/19, `qa_instalador_linha_b22` 17/17, `preflight` 38/38, `diagnostico`, `comandos`, `completar`, `cli`, `json` 62/62, `harness` 23/23, todos verdes.
- Bash 4.2 real (`centos:7`, 4.2.46): `install.sh` escolhe a legada, recusa `--canal master` sem escrever, falha sem a fonte remota com o comando manual; `bin/dbx list /` sai 3 com a mensagem de reinstalacao.
- Lint: sem achado com `LINT_MEMORIA_MB=15360`; com o teto padrao o `commands/download.sh` e interrompido por memoria (13,2 GB medidos; residuo da `develop`, acompanhamento fora desta demanda).
- `bash scripts/verificar-remocao-de-casos.sh`: nenhuma reducao.
- Gates: `protocolo-tdd` aprovado com ressalvas corrigidas (evidencia); `protocolo-conformidade` aprovado (ciclo 1, bloqueante e maior corrigidos); QA aprovado no ciclo 2 (achados menores do ciclo 1 corrigidos).
- Suite completa oficial: sobre o commit da PARTE A, resultado no corpo da PR.

## 6. Riscos e rollback

- RSK-108 a RSK-112 (requisitos). Ate o `support/bash-4.2` existir, o instalador num host 4.2/4.3 falha com o comando manual (sem instalacao parcial).
- Rollback da PARTE A: `git revert` do merge; o instalador volta a recusar abaixo de 4.4.

## 7. Links e aceites

- Entradas de memoria: `2026-11-01-1200-aceite-testes-qa-suporte-bash-42`.
- PR: a abrir (PARTE A -> `develop`).
- Tech Lead: **Aprovado** (PARTE A), 2026-11-01 - condicionado a suite completa oficial verde sobre o commit.
- Solicitante: suite do QA aceita, 2026-11-01.
