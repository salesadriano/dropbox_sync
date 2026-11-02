# Releases 2.3.1 e 2.3.1-bash42: lint completo e sonda de localidade unica nos testes

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "make and publish release and update install script"; decisoes do solicitante: patch v2.3.1 com os acompanhamentos pendentes e atualizacao do `dbx` desta maquina |
| Porte | M - gatilhos de `scripts/porte.sh` (`commands/download.sh`, `install.sh`, `scripts/lint.sh`); sem mudanca de comportamento do produto |
| Log de prompt | `docs/prompts/2026-11-02_1930_release-v231.md` |
| Issues | nenhuma |
| Branch / base | `chore/release-v231` sobre `origin/develop` @ `4418058`; `chore/release-v231-bash42` sobre `origin/support/bash-4.2` @ `782d710` |
| Agents | Tech Lead (implementacao e gates), QA Expert (validacao independente) |
| Data | 2026-11-02 |

## 2. Causa ou decisao

- Lint: `commands/download.sh` carrega `commands/sync.sh` em dois pontos; com `external-sources=true`, o `shellcheck` analisava a cadeia duas vezes e era morto pelo teto de 12 GB do `scripts/lint.sh` (o arquivo nunca era verificado). A segunda carga passa a `source=/dev/null`; a primeira segue cobrindo os simbolos.
- `QA-B42-03`: a sonda `_localidade_disponivel` estava copiada em 9 arquivos de teste na linha legada (1 na principal); divergencia entre copias reabriria o `QA-B42-01`. Passa a `tests/support/localidade.sh`. `progresso_linha_test.sh` mantem a sua sonda, que confere outra coisa (contagem de caractere, nao dobra de caixa).
- Registro da v2.2.0: "PR: a abrir" -> PRs #72 e #73.
- Versao 2.3.1 / 2.3.1-bash42 em `lib/cli.sh`, `install.sh` e README; notas em `docs/releases/`. As notas registram tambem a correcao de `CDPATH` (DIV-392), que saiu na v2.3.0 sem constar nas notas dela.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `commands/download.sh` | diretiva `source=/dev/null` na segunda carga de `sync.sh` | +1/-1 |
| `scripts/lint.sh` | comentario do paralelismo | +1/-1 |
| `tests/support/localidade.sh` | Novo: sonda unica | novo |
| `tests/integracao/diagnostico_test.sh` (as duas linhas) e, na legada, `filtros_test`, `reter_test`, `sync_test`, `filtro_test`, `retencao_test`, `qa_debug_transferencias_b12`, `qa_filtros_banda_b4`, `qa_retencao_b6` | copia da sonda trocada pela carga do apoio | -5 a -9 cada |
| `lib/cli.sh`, `install.sh`, `README.md` | versao 2.3.1 / 2.3.1-bash42 | +/-1 cada |
| `docs/releases/v2.3.1.md`, `docs/releases/v2.3.1-bash42.md` | Novos: notas | doc |
| `docs/reviews/2026-10-31-2330-registro-release-v220.md` | PRs #72 e #73 | doc |

## 4. Testes rodados

| Arquivo de teste | Ambiente | Resultado |
|---|---|---|
| os 9 arquivos alterados da linha legada | host (bash 5.3) | todos aprovados, 0 falhos (diagnostico 17, filtros 33, b12 27/1 pulado, b4 21, b6 60, reter 84, sync 99, filtro 35, retencao 38) |
| `qa_filtros_banda_b4_test.sh` | CentOS 7 (`suite-bash42.sh`) | 17 aprovados, 4 pulados pela sonda compartilhada (esperado), 0 falhos |
| `diagnostico_test.sh` | host, linha principal | 17 aprovados, 0 falhos |
| `sh scripts/lint.sh commands/download.sh` | host | exit 0, sem achados (antes: interrompido pelo teto) |
| `sh scripts/lint.sh` nos arquivos alterados | host, as duas linhas | exit 0 |
| `verificar-remocao-de-casos.sh`, `inventario-de-testes.sh --check` | legada | sem reducao; 117 arquivos, 2909 casos, 0 divergencias |

- Achado anterior, fora do escopo: `SC2269` (info) em `qa_retencao_b6_test.sh:546`, ja presente na base.
- Suite completa local: resultado no corpo das PRs.

## 5. Gates

| Gate | Achados | Veredito |
|---|---|---|
| `protocolo-tdd` | refatoracao de teste sem mudanca de comportamento; nenhum caso removido | Aprovado |
| `protocolo-conformidade` | nenhum; apoio de teste no lugar dos demais (`tests/support/`) | Aprovado |

## 6. QA

Validacao independente em `docs/reviews/2026-11-02-1930-validacao-qa-release-v231.md`: **Aprovado**, sem achado bloqueante ou maior; menores aceitos: M-1 (a sonda de `diagnostico_test` usava `$BASH_ABSOLUTO`, equivalente a `${BASH:-bash}` sob o runner) e M-2 (simbolo definido so na segunda carga de `sync.sh` nao seria visto; hoje e o mesmo arquivo). Tres suites do QA da linha legada reaceitas pelo solicitante (`2026-11-02-1930-aceite-testes-qa-release-v231`).

## 7. Riscos e rollback

- Sem efeito no produto: so a diretiva do `shellcheck`, testes e versao.
- Rollback: apagar as releases `v2.3.1` e `v2.3.1-bash42`; `git revert` dos merges.
