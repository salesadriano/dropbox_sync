---
date: 2026-10-08
hora: "0735"
domain: cli / documentacao operacional
porte: P
status: concluido
instancia: myNote/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-08-0735-registro-ajuda-upload-pipefail.md"
---

# ajuda-upload-pipefail

## Prompt 1 — 2026-10-08 0727

> merge feito prossiga

**Intenção:** Prosseguir com a esteira do projeto após o merge do PR #15 em `develop`. Conforme o backlog consolidado e o painel de pendências de requisitos (`DIV-18`, `RSK-36`, `DP-29`), implementar no ponto de entrada (`bin/dbx`) o suporte a texto de ajuda contextual para comandos (com ênfase no subcomando `upload`) e a recomendação operacional de `set -o pipefail` quando a origem for `-` (entrada padrão), protegendo operadores contra publicação parcial decorrente de encerramento anormal do processo produtor em canos anônimos.

**Inferências e Decisões do Solicitante:**
- **Escopo:** Pontual (Porte P).
- **Atendimento de RSK-36 / DIV-18 / DP-29:** A recomendação antes restrita a comentários em `lib/transfer.sh` e `commands/upload.sh` é formalmente levada ao texto de ajuda de `bin/dbx` e validada por testes automatizados.
- **Atualização documental:** Refletir a resolução da pendência de documentação em `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md`, `docs/requisitos/riscos-restricoes-e-licenciamento.md` e `docs/requisitos/decisoes-pendentes.md`.
