# Teste da trava: pid de outro usuario tomado como morto

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | Destravar a release v2.4.1 ("merge as PRs"): a suite completa de `develop` @ `8988ddc` reprovou em `state_trava_test.sh` |
| Porte | P - 4 linhas so de teste; sem contrato, schema, auth, segredo, dado sensivel, fronteira, pipeline nem dependencia; sem mudanca de comportamento do produto |
| Log de prompt | `docs/prompts/2026-11-12_1046_teste-trava-pid-alheio.md` |
| Issues | nenhuma |
| Branch / base | `chore/teste-trava-pid-alheio` sobre `origin/develop` @ `8988ddc` |
| Agents | Tech Lead (implementou e validou) |
| Data | 2026-11-12 |

## 2. Causa ou decisao

`matriz_hostil_e_ilegivel_nunca_apagada_nem_retomada_nem_ecoada` usa o pid 12 como "valido e morto" e so o pulava quando `kill -0` respondia. Nesta maquina o pid 12 e uma thread do `Interop` do WSL (uid 0): `kill -0` da EPERM, o teste o plantava como morto, e o produto (`lib/state.sh:774`, vivo por `kill -0` ou `/proc/<pid>`) o via vivo e recusava (`estado=7`), como deve. Correcao unica e evidente: o teste usa a mesma regra de vivo do produto. Analise comparativa dispensada (P).

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `tests/unit/state_trava_test.sh` | Alterado | +3/-1 |

Total de linhas de codigo (producao e teste, sem documentacao): **4**.

## 4. Testes rodados

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `tests/unit/state_trava_test.sh` | o proprio arquivo | `bash tests/run.sh state_trava_test.sh` | 28 | 28 | 0 | - |

- Red observado: suite completa de `develop` @ `8988ddc`, duas vezes (2026-11-12T15:43:36Z e 15:45:49Z): `not ok 18 - matriz_hostil_e_ilegivel_nunca_apagada_nem_retomada_nem_ecoada`, `# FALHA: pid 12 valido e morto: retomada`, `trecho ausente: [estado=0]`, texto `estado=7 ... trava ocupada: o sync pid 12`.
- Parada no primeiro erro (Regra 9): `tests/run.sh` com `Bail out!`, conferido na falha acima; execucao final sem interrupcao.
- Barreiras estaticas: `sh scripts/lint.sh tests/unit/state_trava_test.sh` saida 0; `bash scripts/verificar-remocao-de-casos.sh`: `nenhuma reducao nao declarada.`
- Testes de seguranca e acesso (Regra 6): Nao aplicavel: so teste, sem rota, sessao, dado sensivel ou entrada de usuario.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: CLI sem formulario.
- Suite completa local no push para a PR (Regra 8): `sh scripts/suite-completa.sh -- bash tests/run.sh`, verde para `11b27f3`: 130 arquivos, 3074 aprovados, 0 reprovados, 3 pulados (2798s); apos o merge, verde para `ebdfee2` (3001s).

## 5. Gates

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9 e 11; `Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados` | nenhum; o caso nao fica inerte: o pid 9999999 continua plantado e retomado | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + shell; `Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados` | nenhum | Aprovado |

- Ciclo: 1
- `sh scripts/alteracoes-externas.sh --detectar`: exit 0 antes da edicao e do commit.

## 6. QA

- `QA: amostragem - nao validada` (fora da amostra 1 em 5).
- Inventario de testes (regra 51): Nao aplicavel: nome e contagem de casos inalterados; `sh scripts/inventario-de-testes.sh --check`: `arquivos: 130 | casos: 3089 | divergencias: 0`.
- Veredito do QA: Nao aplicavel: fora da amostra, 2026-11-12.

## 7. Riscos e rollback

- Riscos residuais: a linha legada (`support/bash-4.2`) tem o mesmo caso; a v2.4.1-bash42 ja saiu com a suite verde em outra janela de pids, e a correcao vai para la na proxima demanda da linha.
- Impacto: Nenhum: so teste.
- Rollback: `git revert <sha>` basta.

## 8. Links e aceites

- Entradas de memoria: Nenhuma: sem decisao duravel.
- Documentacao sincronizada: Nenhuma.
- Commit(s): `11b27f3` - test(state): pid de outro usuario conta como vivo no teste da trava
- PR: #114, mesclada em `ebdfee2`.
- Tech Lead: **Aprovado**, 2026-11-12.
- Solicitante: Nao aplicavel: sem arquivo do QA.
