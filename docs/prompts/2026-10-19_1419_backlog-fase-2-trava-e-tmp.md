---
date: 2026-10-19
hora: "1419"
domain: concorrencia / ciclo de vida do processo
porte: M
status: em-andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-19-1419-registro-trava-e-tmp-b2.md"
---

# backlog-fase-2-trava-e-tmp

## Prompt 1 — 2026-10-19 (após o merge da PR #41)

> gh pr merge 41 --merge

**Intenção:** o solicitante mesclou a PR #41 (fase 1b, `c8fc887`), o que retoma a instrução "analise e implemente os itens no backlog". Esta é a fase 2 do plano (`2026-10-19-1023-plano-do-backlog`), com três itens:
- F-12: trava de concorrência;
- `lib/tmp`: o restante do F-31 (OBS-02, OBS-03 e OBS-04);
- C-1 da fase 1: a área temporária do `verificar`, que é gêmea da do `sync`.

**Inferências e decisões do solicitante:**
- **Alcance da trava:** mesmo par de `sync`/`verificar` (conta × origem × destino). Pares diferentes rodam em paralelo; `upload`, `download` e `delete` avulsos não travam.
- **Trava ocupada:** recusa na hora, com código da taxonomia existente (os códigos 0 a 15 estão em uso; o BA propõe e o Tech Lead confirma), dizendo quem tem a trava (pid e início). A opção `--esperar N` (alias `--wait`) espera até N segundos.
- **Trava órfã:** a trava guarda pid, host e início. No mesmo host, se o pid não existe mais, ela é retomada com aviso. De outro host, nunca é retomada sozinha; o `dbx diagnostico` a mostra e diz como liberar.
- **Porte M:** a trava é estado transitório, não dado persistente, mas o RNF-26 precisa ser emendado para autorizar o arquivo de trava. Branch `feature/trava-e-tmp-b2`, a partir de `develop` (`c8fc887`); nenhum PR aberto.

## Prompt 2 — 2026-10-19 (aprovação da regra 12)

> Aprovo

**Intenção:** o solicitante aprova a suíte do QA da fase 2 (`tests/integracao/qa_trava_tmp_b2_test.sh`, 23 casos, ciclo 2, sha256 `e875416e…`) e a mudança na auditoria de comandos externos do `tests/unit/preflight_test.sh` (sha256 `5ae77af7…`). A auditoria agora fecha o bloco de vetor pelo saldo de parênteses e ganhou um caso novo. Qualquer mudança posterior nesses arquivos volta para reaprovação.

## Prompt 3 — 2026-10-19 (confirmação da regra 12)

> Aprovo

**Intenção:** o solicitante aprova a inclusão de `rmdir` nas listas de utilitários do PATH reduzido de três suítes já aprovadas: `preflight_test`, `diagnostico_test` e `qa_consulta_diagnostico_b1_test`. É a mesma manutenção de fixture feita para o `ln`, e o QA confirmou que não enfraquece nenhuma delas.
