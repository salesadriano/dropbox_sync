# Teste da trava na linha legada: pid de outro usuario tomado como morto

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "corrija o teste na linha legada agora" |
| Porte | P - 4 linhas so de teste; sem contrato, schema, auth, segredo, dado sensivel, fronteira, pipeline nem dependencia |
| Log de prompt | `docs/prompts/2026-11-12_1900_teste-trava-pid-alheio-bash42.md` |
| Issues | nenhuma |
| Branch / base | `chore/teste-trava-pid-alheio-bash42` sobre `origin/support/bash-4.2` @ `66d7c6d` |
| Agents | Tech Lead (implementou e validou) |
| Data | 2026-11-12 |

## 2. Causa ou decisao

A mesma da principal (PR #114, `11b27f3`): `matriz_hostil_e_ilegivel_nunca_apagada_nem_retomada_nem_ecoada` pulava o pid 12 so quando `kill -0` respondia; com o pid de outro usuario (EPERM) o teste o plantava como morto e o produto (`lib/state.sh`, vivo por `kill -0` ou `/proc/<pid>`) recusava. O teste passa a usar a regra do produto. Porte por cherry-pick, so do teste. Analise comparativa dispensada (P).

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `tests/unit/state_trava_test.sh` | Alterado | +3/-1 |

Total de linhas de codigo (producao e teste, sem documentacao): **4**.

## 4. Testes rodados

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `tests/unit/state_trava_test.sh` | o proprio arquivo, bash 4.2.46 real | `sh scripts/suite-bash42.sh state_trava_test.sh` | 28 | 28 | 0 | - |
| `tests/unit/state_trava_test.sh` | o proprio arquivo, bash do host (WSL) | `bash tests/run.sh state_trava_test.sh` | 28 | 28 | 0 | - |

- Red observado: no host, sem a correcao, `not ok 18 - matriz_hostil_e_ilegivel_nunca_apagada_nem_retomada_nem_ecoada`, `REPROVADA (1 arquivo(s) com falha)`.
- Parada no primeiro erro (Regra 9): `tests/run.sh` com `Bail out!`; execucao final sem interrupcao.
- Barreiras estaticas: `sh scripts/lint.sh tests/unit/state_trava_test.sh` saida 0; `bash scripts/verificar-remocao-de-casos.sh`: `nenhuma reducao nao declarada.`
- Testes de seguranca e acesso (Regra 6): Nao aplicavel: so teste.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: CLI sem formulario.
- Suite completa local no push para a PR (Regra 8): `sh scripts/suite-bash42.sh`, resultado no corpo da PR.

## 5. Gates

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9 e 11; `Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados` | nenhum; o pid 9999999 continua plantado e retomado | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + shell; `Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados` | nenhum | Aprovado |

- Ciclo: 1
- `sh scripts/alteracoes-externas.sh --detectar`: exit 0 antes da edicao e do commit.

## 6. QA

- `QA: amostragem - nao validada` (fora da amostra 1 em 5).
- Inventario de testes (regra 51): Nao aplicavel: nome e contagem inalterados; `sh scripts/inventario-de-testes.sh --check`: `arquivos: 132 | casos: 3102 | divergencias: 0`.
- Veredito do QA: Nao aplicavel: fora da amostra, 2026-11-12.

## 7. Riscos e rollback

- Riscos residuais: Nenhum identificado alem do escopo do diff.
- Impacto: Nenhum: so teste; sem release.
- Rollback: `git revert <sha>` basta.

## 8. Links e aceites

- Entradas de memoria: Nenhuma: sem decisao duravel.
- Documentacao sincronizada: Nenhuma.
- Commit(s): ver `git log -- tests/unit/state_trava_test.sh`.
- PR: para `support/bash-4.2`.
- Tech Lead: **Aprovado**, 2026-11-12.
- Solicitante: Nao aplicavel: sem arquivo do QA.
