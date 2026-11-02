# Falha fechada sem a localidade e tokenizador JSON linear na linha principal (antes das releases 2.3.0 e 2.3.0-bash42)

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "check branchs and make release"; decisao do solicitante (2026-11-02): trazer antes a correcao `QA-B42-01` e o tokenizador linear para a principal e publicar as duas releases juntas |
| Porte | M - guarda destrutiva (`--espelhar` sem a localidade) e componente central (`lib/json.sh`); 107 linhas de produto |
| Log de prompt | `docs/prompts/2026-11-02_0840_release-v230.md` |
| Issues | nenhuma |
| Branch / base | `feature/falha-fechada-sem-localidade` sobre `origin/develop` @ `12a5086` |
| Agents | Senior Developer (retorno), QA Expert (validacao independente), Tech Lead (gates) |
| Data | 2026-11-02 |

## 2. Causa ou decisao

- Causa (`QA-B42-01`, `DIV-391`): sem a localidade `C.UTF-8`, `RF-54(f)` so avisava; o `--espelhar` apagava o recem-enviado (`Éa.txt`/`éa.txt`) e o filtro deixava no escopo nome que devia ficar fora. Achado e provado na linha legada (CentOS 7); a principal tem o mesmo defeito em qualquer host sem `C.UTF-8`.
- Desempenho: `${s//p/t}` do bash e quadratico na cadeia, e o tokenizador fazia 13 passadas no documento inteiro; trocas em pedacos de 4096 caracteres, com resultado identico.
- Solucao: a mesma da linha legada (`RF-54(f2)`), escrita no estilo da principal; analise comparativa feita na demanda `suporte-bash-42`.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/filtro.sh` | Alterado: `_dbx_filtro_em_caracteres`; modo bytes sem localidade em `_dbx_filtro_casa` | +40/-3 |
| `lib/sync.sh` | Alterado: `dbx_sync_reter_nao_ascii` | +24/-0 |
| `commands/sync.sh` | Alterado: retencao nos dois pontos de planejamento, aviso unico | +17/-1 |
| `lib/json.sh` | Alterado: tokenizador em pedacos | +26/-9 |
| `tests/integracao/qa_exclusao_sem_localidade_b42_test.sh` | Novo (suite do QA aceita na linha legada, sha256 `7654cd1a...d033`, sem mudanca) | novo |
| `tests/integracao/sync_test.sh`, `tests/unit/filtro_test.sh`, `tests/integracao/qa_docs_aliases_p4_test.sh`, `tests/unit/json_test.sh` | Alterados: casos de `RF-54(f2)` e 4 casos do QA na fronteira de 4096 | ver diff |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | v1.35, `RF-54(f2)`, `DIV-391` | doc |
| `docs/testes/inventario-de-testes.md` | 114 arquivos, 2887 casos, 0 divergencias | doc |

Total de linhas de codigo (producao e teste): **613** (+588/-25).

## 4. Testes rodados

| Arquivo de teste | Item afetado | Comando | Resultado |
|---|---|---|---|
| `filtro_test`, `filtros_test`, `qa_filtros_banda_b4` | `lib/filtro.sh` | `bash tests/run.sh <arquivo>` | 35, 33 e 21 aprovados, 0 falhos |
| `sync_test` (e `qa_sync_test`) | `lib/sync.sh`, `commands/sync.sh` | `bash tests/run.sh sync_test.sh` | 97 aprovados, 0 falhos |
| `qa_exclusao_sem_localidade_b42` | `RF-54(f2)` | `bash tests/run.sh qa_exclusao_sem_localidade_b42` | 6 aprovados, 0 falhos |
| `qa_docs_aliases_p4` | caso `[C]` | idem | 16 aprovados, 0 falhos |
| `json_test` | `lib/json.sh` | idem | 66 aprovados, 0 falhos |
| `sync_blocos_test`, `http_test`, `config_test` | consumidores de `lib/json.sh` | idem | 42, 73 e 79 aprovados, 0 falhos |

- Red observado: o QA reprovou `qa_b42_enviar_espelhar_remoto_nao_ascii_nao_e_apagado` contra `lib/filtro.sh`, `lib/sync.sh` e `commands/sync.sh` de `HEAD`; os casos de fronteira do json passam com o `lib/json.sh` de `HEAD` (equivalencia) e matam dois mutantes (pedaco de 4095, controle so no primeiro pedaco).
- Medicao: 1600 entradas (63877 bytes), 992 ms -> 158 ms.
- Deteccao de byte nao ASCII por faixa conferida sob `C`, `C.UTF-8` e `en_US.UTF-8`, no bash 5.3 e no 4.2.46.
- Barreiras estaticas: `shellcheck -x -s bash` sem aviso nos 4 arquivos de produto; `verificar-remocao-de-casos.sh` sem reducao.
- Seguranca: guarda destrutiva sem estado (nao depende de memoria do sync); nenhum segredo tocado.
- Suite completa local: resultado no corpo da PR.

## 5. Gates

| Gate | Achados | Veredito |
|---|---|---|
| `protocolo-tdd` | nenhum | Aprovado |
| `protocolo-conformidade` (`clean-architecture` + shell) | nenhum; a funcao de retencao e unica e chamada nos dois pontos de planejamento | Aprovado |

- Ciclo: 1. `sh scripts/alteracoes-externas.sh --detectar`: sem acusacao externa antes do commit.

## 6. QA

Validacao independente em `docs/reviews/2026-11-02-0840-validacao-qa-release-v230.md`: **Aprovado**, sem achado bloqueante ou maior. Casos novos do QA em `tests/unit/json_test.sh` (`qa_rel230_03_*`, sha256 do arquivo `183c16f2...db4e`), aceite do solicitante pedido na PR.

## 7. Riscos e rollback

- Sem `C.UTF-8`, caminho nao ASCII so no destino deixa de ser apagado pelo `--espelhar` (direcao segura, com aviso e contagem).
- Rollback: `git revert` do merge.

## 8. Proximos passos da demanda

Release: versao 2.3.0 e notas (`chore/release-v230`), PR `develop` -> `master`, publicacao de `v2.3.0` (Latest) e de `v2.3.0-bash42` (nao Latest) a partir de `support/bash-4.2`.

## 9. Merge do retorno e releases

- PR #76 (`feature/falha-fechada-sem-localidade` -> `develop`) mesclada em `0c80a1e` por pedido explicito do solicitante ("merge PR") antes do fim da suite completa oficial sobre `d2cc010`; o resultado dessa suite e registrado abaixo quando concluir.
- Linha principal: `chore/release-v230` (versao 2.3.0 em `lib/cli.sh` e `install.sh`, pacote no README, notas em `docs/releases/v2.3.0.md`) -> `develop` -> `master`; publicacao de `v2.3.0` (Latest) a partir da `master` com `bash scripts/empacotar.sh --publicar`.
- Linha legada: `chore/release-v230-bash42` (notas `docs/releases/v2.3.0-bash42.md`, pacote no README, reaceite das suites `qa_docs_aliases_p4` e `qa_exclusao_sem_localidade_b42`) -> `support/bash-4.2`; publicacao de `v2.3.0-bash42` (nao Latest) a partir de `support/bash-4.2`.
- Aceite dos 4 casos `qa_rel230_03_*` de `tests/unit/json_test.sh` (sha256 `183c16f2...db4e`): solicitante, 2026-11-02 (AskUserQuestion, "Accept (Recommended)"); entrada de memoria `2026-11-02-0840-aceite-testes-qa-release-v230`.
