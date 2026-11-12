# Releases 2.4.1 e 2.4.1-bash42: memoria do sync por ciclo e orfaos apagados no fim

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

- O conteudo da versao e as evidencias nao se repetem aqui. Estao nos registros `docs/reviews/2026-11-11-1827-registro-sync-ciclos-exclusao-indevida.md` (PR #111) e `docs/reviews/2026-11-11-2210-registro-sync-orfaos-no-fim.md` (commit `9549710`).
- A release foi suspensa e retomada com a correcao `sync-orfaos-no-fim`, por decisao do solicitante ("Segurar e incluir"). Na principal, a correcao entra por merge na branch da release (regra 47) e vai na mesma PR para `develop`, para que a suite completa rode uma vez.
- O numero `2.4.1` / `2.4.1-bash42` foi escolhido pelo solicitante. E patch: correcao, sem funcionalidade nem contrato novos.
- No instalador, so `VERSAO_INSTALADOR` muda, por decisao do solicitante.
- Porte legado: cherry-pick de `4a0fd1e` e `268878e` sem ajuste de codigo, e de `9549710` com dois conflitos resolvidos sem nameref (RF-200): o mapa `cobertas` por escopo dinamico em `commands/sync.sh` e `dbx_ref_existe` em `lib/walk.sh`, ambos com a chave de `dbx_filtro_chave`. A mudanca nao usa construcao 4.3+, e `bash42_auditoria_test.sh` passou 7/0. O unico conflito foi no inventario de testes: manteve-se a linha do `sync_test.sh` da linha legada (97 casos), e a conferencia passa a 130 arquivos e 3080 casos.
- O sha256 da suite do QA na linha legada e o mesmo aceito (`cb8665e0...a624`).

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/cli.sh`, `install.sh`, `README.md` | versao 2.4.1 / 2.4.1-bash42 | +/-1, +/-1, +/-3 |
| `docs/releases/v2.4.1.md` (principal), `docs/releases/v2.4.1-bash42.md` (legada) | Novos: notas | doc |
| Linha legada: `commands/sync.sh`, `lib/state.sh`, `lib/sync.sh`, `lib/walk.sh`, os 4 testes novos e a documentacao das demandas | porte da PR #111 e de `9549710` | conforme `4a0fd1e`, `268878e` e `9549710` |
| Principal: correcao `9549710` | na mesma PR da release | conforme o registro da demanda |

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
| PR #112 `chore/release-v241` -> `develop` | mesclada em `8988ddc` |
| PR #113 `feature/sync-ciclos-exclusao-indevida-bash42` -> `support/bash-4.2` | mesclada em `66d7c6d` |
| PR #114 `chore/teste-trava-pid-alheio` -> `develop` | mesclada em `ebdfee2`; corrige o teste que reprovava a suite de `8988ddc` (registro `docs/reviews/2026-11-12-1046-registro-teste-trava-pid-alheio.md`) |
| PR #115 `develop` -> `master` | mesclada em `b83791c` |
| Release `v2.4.1` (Latest) | tag em `b83791c`; `dropbox_sync-2.4.1-linux.tar.gz` (sha256 `e2ac9cd6c555519bc709f78841396e0627b6f385ea675d97b1ec961635e1381d`) e `.sha256`; `dbx --version` do pacote: `2.4.1` |
| Release `v2.4.1-bash42` (sem Latest) | tag em `66d7c6d`; `dropbox_sync-2.4.1-bash42-linux.tar.gz` (sha256 `66ee74264145fe1c59de3fa10833e0f46e203f3fccca8c9d80c39607b2ac4a49`) e `.sha256`; `dbx --version` do pacote: `2.4.1-bash42` |
| Suite completa, principal | verde para `72469e9` (3740s); vermelha duas vezes para `8988ddc` (mesma arvore) em `state_trava_test.sh`, pid 12 de outro usuario tomado por morto; verde para `11b27f3` e para `ebdfee2`: 130 arquivos, 3074 aprovados, 0 reprovados, 3 pulados (3001s) |
| Suite completa, legada (bash 4.2.46) | verde para `c5e8137` (2994s) |
| Aceite | merges das PRs #112 a #115 pelo solicitante ("merge as PRs", "merge a PR") |
| Limpeza | worktrees mesclados removidos com `limpar-worktrees.sh` |
