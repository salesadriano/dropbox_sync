# Releases 2.3.4 e 2.3.4-bash42: trava legivel em localidade traduzida

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "gere a release 2.3.4" |
| Porte | M - gatilho `install.sh` (`sh scripts/porte.sh`: 3 arquivos, 4 linhas de codigo); sem mudanca de comportamento alem da demanda ja registrada |
| Log de prompt | `docs/prompts/2026-11-04_0006_release-v234.md` |
| Issues | nenhuma |
| Branch / base | `chore/release-v234` sobre `origin/develop` @ `bc190ec`; `chore/release-v234-bash42` sobre `origin/support/bash-4.2` @ `143809d` |
| Agents | Tech Lead |
| Data | 2026-11-04 |

## 2. Causa ou decisao

- Conteudo da versao e evidencias, nao repetidos aqui: `DIV-395`, `docs/reviews/2026-11-03-2001-registro-tipo-de-arquivo-sem-traducao.md` (PRs #93 e #94).
- Numero `2.3.4` / `2.3.4-bash42` dado pelo solicitante. A correcao nao muda nenhum par de saida.
- So o numero em `lib/cli.sh`, `install.sh` e README, mais as notas em `docs/releases/`.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/cli.sh`, `install.sh`, `README.md` | versao 2.3.4 / 2.3.4-bash42 | +/-1, +/-1, +/-3 |
| `docs/releases/v2.3.4.md` (principal), `docs/releases/v2.3.4-bash42.md` (legada) | Novos: notas | doc |

## 4. Testes rodados

- Suite completa local de cada linha sobre o commit da release (a legada no bash 4.2 real): resultado na secao 8 e no corpo das PRs.
- `bash scripts/empacotar.sh` (sem publicar) em cada linha: pacote gerado e `dbx --version` do pacote conferido.

## 5. Gates

| Gate | Achados | Veredito |
|---|---|---|
| `protocolo-tdd` | nenhum: so numero de versao e notas | Aprovado |
| `protocolo-conformidade` | nenhum | Aprovado |

## 6. QA

Nao aplicavel a validacao nova: `DIV-395` ja foi validado pelo QA no registro da demanda; a release so muda versao e notas.

## 7. Riscos e rollback

- Rollback: `git revert` do commit de release e exclusao da release/tag no GitHub.

## 8. Links e aceites

- PRs, tags e releases: preenchidos no fechamento.
