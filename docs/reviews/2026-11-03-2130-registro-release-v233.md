# Releases 2.3.3 e 2.3.3-bash42: arquivo no lugar da pasta e relatorio final por arquivo

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "gere a release 2.3.3" |
| Porte | M - gatilho `install.sh` (`sh scripts/porte.sh`: 3 arquivos, 4 linhas de codigo); sem mudanca de comportamento alem das demandas ja registradas |
| Log de prompt | `docs/prompts/2026-11-03_2130_release-v233.md` |
| Issues | nenhuma |
| Branch / base | `chore/release-v233` sobre `origin/develop` @ `86bdd92`; `chore/release-v233-bash42` sobre `origin/support/bash-4.2` @ `8636052` |
| Agents | Tech Lead |
| Data | 2026-11-03 |

## 2. Causa ou decisao

- Conteudo da versao e evidencias, nao repetidos aqui:
  - `DIV-394`: `docs/reviews/2026-11-03-1017-registro-arquivo-remoto-no-lugar-da-pasta.md` (PRs #86 e #87).
  - `RF-208`: `docs/reviews/2026-11-03-1203-registro-relatorio-com-tamanho-e-motivo.md` (PRs #88 e #89).
- Numero `2.3.3` / `2.3.3-bash42` dado pelo solicitante. O `RF-208` e aditivo: linhas novas antes dos contadores e pares novos no `--json`; nenhum par existente muda.
- So o numero em `lib/cli.sh`, `install.sh` e README, mais as notas em `docs/releases/`.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/cli.sh`, `install.sh`, `README.md` | versao 2.3.3 / 2.3.3-bash42 | +/-1, +/-1, +/-3 |
| `docs/releases/v2.3.3.md` (principal), `docs/releases/v2.3.3-bash42.md` (legada) | Novos: notas | doc |

## 4. Testes rodados

- Suite completa local de cada linha sobre o commit da release (a legada no bash 4.2 real): resultado na secao 8 e no corpo das PRs.
- `bash scripts/empacotar.sh` (sem publicar) em cada linha: pacote gerado e `dbx --version` do pacote conferido.

## 5. Gates

| Gate | Achados | Veredito |
|---|---|---|
| `protocolo-tdd` | nenhum: so numero de versao e notas | Aprovado |
| `protocolo-conformidade` | nenhum | Aprovado |

## 6. QA

Nao aplicavel a validacao nova: `DIV-394` e `RF-208` ja foram validados pelo QA nos registros das demandas; a release so muda versao e notas.

## 7. Riscos e rollback

- Rollback: `git revert` do commit de release e exclusao da release/tag no GitHub.

## 8. Links e aceites

- PRs, tags e releases: preenchidos no fechamento.
