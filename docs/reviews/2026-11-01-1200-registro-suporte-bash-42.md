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

## 8. PARTE B - linha legada `support/bash-4.2` (versao `2.3.0-bash42`)

| Campo | Valor |
|---|---|
| Branch | `feature/porte-bash-42` (de `26f2452`) -> PR para `support/bash-4.2` |
| Agents | Tech Lead; Senior Developer (B1, B2, B3a, B3b, B4, B5 x3, QA-B42-01); QA Expert (2 ciclos) |
| Parecer de conformidade | `docs/reviews/2026-11-01-1200-parecer-conformidade-porte-bash-42.md` |
| Validacao do QA | `docs/reviews/2026-11-01-1200-validacao-qa-porte-bash-42.md` (ciclo 1 reprovado por `QA-B42-01`; ciclo 2 aprovado com ressalvas) |
| Aceite do solicitante | `.github/agents/memoria/entradas/2026-11-02-1200-aceite-testes-qa-porte-bash-42.md` (21 suites `qa_*` por sha256) |
| Requisitos | v1.35: `RF-54(f2)`, `DIV-391` |

### 8.1 Decisoes

- Solicitante (2026-11-02): suites do QA aceitas; retorno da correcao `QA-B42-01` a linha principal em demanda propria, depois da PARTE B, na release 2.3.0.
- Tech Lead: auxiliar unico `lib/ref.sh` (eval so do nome validado); espera por sondagem `kill -0` que retorna quando qualquer PID nao esta vivo; protecao mecanica de toda expansao de vetor; falha fechada sem localidade (`DIV-391`); pulos de localidade so onde o caso exige a dobra Unicode para resultado positivo, nunca onde prova ausencia de efeito destrutivo.

### 8.2 Arquivos

| Grupo | Alteracao |
|---|---|
| Piso e versao | `lib/preflight.sh` (piso 4.2), `lib/cli.sh` e `install.sh` (`2.3.0-bash42`), `scripts/suite-completa.cmd` (`sh scripts/suite-bash42.sh`) |
| Recursos 4.3+/4.4 | `lib/ref.sh` (novo) e 28 namerefs; `dbx_par_aguardar_algum` e 4 `wait -n`; 2 `${x@a}`; 114 expansoes de vetor protegidas; 4 vetores globais com valores separados |
| Defeitos do 4.2 / CentOS 7 achados pela suite | eco do terminal apos sinal (`lib/cli.sh`, `lib/tmp.sh`); acumulador quadratico (`lib/hash.sh`); corpo ilegivel com curl 7.29 (`lib/http.sh`) |
| Seguranca de dados | `QA-B42-01`: `lib/filtro.sh` (modo bytes e padrao nao ASCII sem localidade), `lib/sync.sh` `dbx_sync_reter_nao_ascii`, `commands/sync.sh` |
| Testes | `tests/run.sh` (calco de `setsid -w`); `tests/unit/ref_test.sh` (novo, 8); `tests/unit/bash42_auditoria_test.sh` (novo, 7); `tests/integracao/qa_exclusao_sem_localidade_b42_test.sh` (novo, QA, 6); casos novos em `sync_test.sh`, `filtro_test.sh`, `http_test.sh`; construcoes 4.4 trocadas (`mapfile -d`, `@Q`, `EPOCHSECONDS`, subscrito negativo); terminal com fifo e `stty sane`; troca de inode por create+mv; `qa_instalador_linha_b22` simula a arvore da linha principal |
| Inventario | `docs/testes/inventario-de-testes.md`: 116 arquivos, 2899 casos, 0 divergencias |

### 8.3 Testes e gates

- Mapa por arquivo no CentOS 7 (bash 4.2.46, curl 7.29, util-linux 2.23, coreutils 8.22, sem `C.UTF-8`): 30 -> 24 -> 4 -> 0 arquivos reprovados; host (bash 5.3): 116 arquivos verdes.
- Lint: sem achado (`LINT_MEMORIA_MB=15360`). `verificar-remocao-de-casos.sh`: sem reducao.
- Gates: conformidade aprovado; QA aprovado com ressalvas no ciclo 2.
- Suite completa oficial (`sh scripts/suite-completa.sh`, no CentOS 7): sobre o commit da PARTE B, resultado no corpo da PR.

### 8.4 Riscos, limites e rollback

- Comparacao sem caixa so no ASCII sem `C.UTF-8` (bash 4.2 nao dobra fora do ASCII nem com `en_US.UTF-8`); com `--espelhar`, caminho nao ASCII nao e apagado e ha aviso (`RF-54(f2)`).
- Acompanhamentos: retorno do `QA-B42-01` a principal (demanda propria); `QA-B42-03`; teto de memoria do lint em `commands/download.sh`.
- Rollback: apagar a release `v2.3.0-bash42`; o branch de suporte fica sem efeito para bash >= 4.4.
