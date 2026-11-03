# Releases 2.3.2 e 2.3.2-bash42: pasta chamada hifen nao quebra mais o sync

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "pushed both, merge the PRs and publish the release" |
| Porte | M - gatilho `install.sh` (`sh scripts/porte.sh`); sem mudanca de comportamento alem da correcao ja registrada |
| Log de prompt | `docs/prompts/2026-11-03_0010_release-v232.md` |
| Issues | nenhuma |
| Branch / base | `feature/diretorio-chamado-hifen` (sobre `origin/develop` @ `4f5be61`) e `feature/diretorio-chamado-hifen-bash42` (sobre `origin/support/bash-4.2` @ `bc4acdd`), release empilhada sobre a correcao |
| Agents | Tech Lead |
| Data | 2026-11-03 |

## 2. Causa ou decisao

- Correcao e evidencias: `docs/reviews/2026-11-02-2100-registro-diretorio-chamado-hifen.md` (nao repetidas aqui).
- Versao patch 2.3.2 / 2.3.2-bash42, como a v2.3.1: so o numero em `lib/cli.sh`, `install.sh` e README, mais as notas em `docs/releases/`.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/cli.sh`, `install.sh`, `README.md` | versao 2.3.2 / 2.3.2-bash42 | +/-1, +/-1, +/-3 |
| `docs/releases/v2.3.2.md`, `docs/releases/v2.3.2-bash42.md` | Novos: notas | doc |

## 4. Testes rodados

- Suite completa local de cada linha sobre o commit da release: resultado no corpo da PR e na secao 8.
- `bash scripts/empacotar.sh` (sem publicar) em cada linha: pacote gerado e `dbx --version` do pacote conferido.

## 5. Gates

| Gate | Achados | Veredito |
|---|---|---|
| `protocolo-tdd` | nenhum: so numero de versao e notas | Aprovado |
| `protocolo-conformidade` | nenhum | Aprovado |

## 6. QA

Nao aplicavel a validacao nova: a correcao ja foi validada pelo QA (registro da demanda `diretorio-chamado-hifen`); a release so muda versao e notas.

## 7. Riscos e rollback

- Rollback: `git revert` do commit de release e exclusao da release/tag no GitHub.

## 8. Links e aceites

- PRs, tags e releases: preenchidos no fechamento.
