# Releases 2.4.1 e 2.4.1-bash42: memoria do sync gravada por ciclo

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "make release and update install script" |
| Porte | M, pelos gatilhos `install.sh` (instalador) e porte de codigo para a linha legada |
| Log de prompt | `docs/prompts/2026-11-11_2158_release-v241.md` |
| Issues | nenhuma |
| Branch / base | `chore/release-v241` sobre `origin/develop` @ `03b225f`; `feature/sync-ciclos-exclusao-indevida-bash42` sobre `origin/support/bash-4.2` @ `88883bd` |
| Agents | Tech Lead |
| Data | 2026-11-11 |

## 2. Causa ou decisao

- O conteudo da versao e as evidencias nao se repetem aqui. Estao no registro `docs/reviews/2026-11-11-1827-registro-sync-ciclos-exclusao-indevida.md` e na PR #111.
- O numero `2.4.1` / `2.4.1-bash42` foi escolhido pelo solicitante. E patch: correcao, sem funcionalidade nem contrato novos.
- No instalador, so `VERSAO_INSTALADOR` muda, por decisao do solicitante.
- Porte legado: cherry-pick de `4a0fd1e` e `268878e` sem ajuste de codigo. A mudanca nao usa construcao 4.3+, e `bash42_auditoria_test.sh` passou 7/0. O unico conflito foi no inventario de testes: manteve-se a linha do `sync_test.sh` da linha legada (97 casos), e a conferencia passa a 130 arquivos e 3080 casos.
- O sha256 da suite do QA na linha legada e o mesmo aceito (`cb8665e0...a624`).

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/cli.sh`, `install.sh`, `README.md` | versao 2.4.1 / 2.4.1-bash42 | +/-1, +/-1, +/-3 |
| `docs/releases/v2.4.1.md` (principal), `docs/releases/v2.4.1-bash42.md` (legada) | Novos: notas | doc |
| Linha legada: `commands/sync.sh`, `lib/state.sh`, os 2 testes novos e a documentacao da demanda | porte da PR #111 | conforme `4a0fd1e` e `268878e` |

## 4. Testes rodados

- Linha legada, no bash 4.2.46 real (`sh scripts/suite-bash42.sh <arquivo>`), todos sem reprovacao:

  | Arquivo | Aprovados |
  |---|---|
  | `bash42_auditoria_test.sh` | 7 |
  | `sync_ciclos_memoria_test.sh` | 6 |
  | `qa_sync_ciclos_memoria_f101_test.sh` | 6 |
  | `sync_blocos_test.sh` | 42 |
  | `qa_sync_blocos_b21_test.sh` | 25 |
  | `state_test.sh` | 24 |
  | `cursor_test.sh` | 55 |
  | `json_test.sh` | 62 |
  | `harness_test.sh` | 23 |
  | `composicao_test.sh` | 28 |

- Na linha legada, `sh scripts/lint.sh commands/sync.sh lib/state.sh` sai sem achado, e `sh scripts/inventario-de-testes.sh --check` da 130 arquivos, 3080 casos e 0 divergencias.
- Suite completa local de cada linha sobre o commit da release: o resultado esta na secao 8.

## 5. Gates

| Gate | Achados | Veredito |
|---|---|---|
| `protocolo-tdd` | nenhum: numero de versao, notas e porte sem ajuste de codigo, coberto pelos testes portados | Aprovado |
| `protocolo-conformidade` | nenhum: diff legado identico ao da PR #111 nos arquivos de codigo | Aprovado |

## 6. QA

Nao se aplica validacao nova. A mudanca ja foi validada pelo QA na demanda `sync-ciclos-exclusao-indevida`, e a suite do QA roda sem alteracao no bash 4.2 real.

## 7. Riscos e rollback

- A causa do relato de origem segue aberta, como ressalva do Tech Lead no registro da demanda. As notas pedem a saida `-p` se o caso acontecer.
- Rollback: `git revert` do commit de release e exclusao da release e da tag no GitHub.

## 8. Links e aceites

| Item | Valor |
|---|---|
| PR `chore/release-v241` -> `develop` | pendente |
| PR `feature/sync-ciclos-exclusao-indevida-bash42` -> `support/bash-4.2` | pendente |
| PR `develop` -> `master` | pendente |
| Release `v2.4.1` (Latest) | pendente |
| Release `v2.4.1-bash42` (sem Latest) | pendente |
| Suite completa, principal | pendente |
| Suite completa, legada (bash 4.2.46) | pendente |
