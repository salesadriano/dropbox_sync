---
date: 2026-10-08
hora: "1255"
domain: cli / transfer / sync / filesystem
porte: M
status: concluido
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-08-1255-registro-criacao-diretorio-destino.md"
---

# criacao-diretorio-destino

## Prompt 1 — 2026-10-08 1255

> @tech-lead os diretórios de destino devem ser criados, caso não existam

**Intenção:** Garantir que comandos que recebem ou baixam dados para caminhos locais (`sync --receber` e `download`) criem automaticamente os diretórios de destino caso eles ainda não existam no sistema de arquivos local (`mkdir -p`), evitando falhas desnecessárias de execução. Em modo de simulação (`--dry-run`), a execução não deve tocar o disco e deve tratar o destino ausente como vazio na previsão.

**Decisões e Diretrizes Técnicas:**
- **Porte M:** Altera o comportamento de contratos operacionais locais em `sync --receber` e `download`, mantendo determinismo, aderência a RNF-15 (dry-run sem efeitos colaterais) e semântica de erros.
- **`sync --receber`:**
  - Quando a raiz local (`$raiz_local` / `$destino`) não existir:
    - Se execução real (`simulacao != 'sim'`): cria o diretório via `mkdir -p -- "$raiz_local"`.
    - Se simulação (`simulacao == 'sim'`): não cria o diretório em disco, gerando lista local vazia para simular o recebimento integral de forma fiel.
  - Quando `sync --enviar`: a raiz local é a origem, portanto a exigência de pré-existência permanece inalterada (não é possível enviar a partir de diretório local inexistente).
- **`download`:**
  - Se `$destino` terminar com `/` (intenção explícita de diretório) ou for um caminho de arquivo cujo diretório pai não exista:
    - Cria os diretórios intermediários / pai via `mkdir -p`.
