# Releases 2.4.0 e 2.4.0-bash42: estrutura de pastas antes da transferencia

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "faça a release com a F-103 nas duas linhas" |
| Porte | M, pelo gatilho `install.sh`. Muda so o numero de versao e as notas, sem comportamento alem da demanda ja registrada |
| Log de prompt | `docs/prompts/2026-11-08_1939_release-v240.md` |
| Issues | nenhuma |
| Branch / base | `chore/release-v240` sobre `origin/develop` @ `6ea9e33`; `chore/release-v240-bash42` sobre `origin/support/bash-4.2` @ `92c7820` |
| Agents | Tech Lead |
| Data | 2026-11-08 |

## 2. Causa ou decisao

- O conteudo da versao e as evidencias nao se repetem aqui: estao em `F-103`, no registro `docs/reviews/2026-11-07-estrutura-de-pastas-registro.md` e nas PRs #103 e #104.
- O numero `2.4.0` / `2.4.0-bash42` foi escolhido pelo solicitante. E minor porque a funcionalidade e nova e muda o comportamento do `--espelhar`, que passa a apagar pastas orfas e o arquivo no lugar de uma pasta.
- So o numero muda, em `lib/cli.sh`, `install.sh` e README, mais as notas em `docs/releases/`.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/cli.sh`, `install.sh`, `README.md` | versao 2.4.0 / 2.4.0-bash42 | +/-1, +/-1, +/-3 |
| `docs/releases/v2.4.0.md` (principal), `docs/releases/v2.4.0-bash42.md` (legada) | Novos: notas | doc |

## 4. Testes rodados

- Suite completa local de cada linha sobre o commit da release; a da legada roda no bash 4.2 real. O resultado esta na secao 8 e no corpo das PRs.
- `bash scripts/empacotar.sh`, sem publicar, em cada linha: pacote gerado e `dbx --version` do pacote conferido.

## 5. Gates

| Gate | Achados | Veredito |
|---|---|---|
| `protocolo-tdd` | nenhum: so numero de versao e notas | Aprovado |
| `protocolo-conformidade` | nenhum | Aprovado |

## 6. QA

Nao se aplica validacao nova. A F-103 ja foi validada pelo QA no registro da demanda, e a release so muda versao e notas.

## 7. Riscos e rollback

- As notas trazem a mudanca de comportamento do `--espelhar` e recomendam um `--dry-run` antes de atualizar.
- Rollback: `git revert` do commit de release e exclusao da release e da tag no GitHub.

## 8. Links e aceites

| Item | Valor |
|---|---|
| PR #105 `chore/release-v240` -> `develop` | mesclada em `684045b` |
| PR #106 `chore/release-v240-bash42` -> `support/bash-4.2` | mesclada em `88883bd` |
| PR #107 `develop` -> `master` | mesclada em `d99463b` |
| Release `v2.4.0` (Latest) | tag em `d99463b`; `dropbox_sync-2.4.0-linux.tar.gz` e `.sha256`; `dbx --version` do pacote: `2.4.0` |
| Release `v2.4.0-bash42` (sem Latest) | tag em `88883bd`; `dropbox_sync-2.4.0-bash42-linux.tar.gz` e `.sha256`; `dbx --version` do pacote: `2.4.0-bash42` |
| Suite completa, principal | verde para `386e1d1` e para `684045b`: 3040 aprovados, 0 reprovados, 4 pulados |
| Suite completa, legada (bash 4.2.46) | verde para `e585e4b`: 2969 aprovados, 0 reprovados, 87 pulados por ambiente |
| Aceite | merges das PRs #105, #106 e #107 pelo solicitante |
| Limpeza | worktrees e branches `chore/release-v240*` removidos com `limpar-worktrees.sh` |
