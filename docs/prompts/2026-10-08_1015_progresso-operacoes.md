---
date: 2026-10-08
hora: "1015"
domain: cli / progresso / ux
porte: M
status: concluido
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-08-1015-registro-progresso-operacoes.md"
---

# progresso-operacoes

## Prompt 1 — 2026-10-08 1011

> @tech-lead implements parameter to show progress of operations

**Intenção:** Implementar sinalizador de linha de comando (`--progresso` / `--progress` / `-p` e `--sem-progresso` / `--no-progress`) para exibição de progresso em tempo real das operações de transferência e sincronização (`upload`, `download`, `sync`).

**Inferências e Decisões do Solicitante:**
- **Porte M:** Toca contrato público de linha de comando (novas flags globais e locais, interação em tempo real com operador e testes automatizados).
- **Branch base:** Merge da branch anterior `fix/rpc-content-type-json` concluído em `develop`; nova branch criada como `feature/progresso-operacoes` a partir de `develop`.
- **Canal de emissão de progresso:** Toda emissão de progresso deve sair exclusivamente pelo descritor de erro padrão (`stderr` / `>&2`), garantindo isolamento absoluto de `stdout`, em conformidade estrita com `RF-28` (saída estruturada em JSON/chave-valor sem poluição) e `RF-32` (recebimento de conteúdo por stdout em pipes/fluxo sem corrupção).
- **Escopo operacional:**
  - `upload`: emissão de progresso em uploads de arquivo único e por blocos de sessão em partes (`lib/transfer.sh`).
  - `download`: emissão de progresso na recepção de arquivo remoto.
  - `sync`: indicação de progresso item a item durante a sincronização direcional (`[1/N] enviando ...`).
- **Detecção de terminal (RNF-19):** O sinalizador `--progresso` sobrepõe o comportamento padrão para permitir testes automatizados e forçar exibição quando desejado pelo operador; `--sem-progresso` desativa explicitamente.

## Prompt 2 — 2026-10-08 1050

> update README.md

**Intenção:** Atualizar a documentação do projeto no `README.md` refletindo os novos parâmetros de progresso (`--progresso` / `--progress` / `-p` e `--sem-progresso` / `--no-progress`), o isolamento de canais (progresso via `stderr`), exemplos práticos nos comandos `upload`, `download`, `sync`, o alinhamento das opções globais e a contagem atualizada da suíte de testes.

## Prompt 3 — 2026-10-08 1100

> fix
> sales@myPCWin:/mnt/h/Bkps$ ~/dropbox_api/bin/dbx download -p  /asj  .
> [download] iniciando recebimento: /asj -> .
> erro: recebimento recusado: path/not_file/

**Intenção:** Diagnosticar e tratar erro ao tentar baixar pasta remota (`/asj`) via comando `download` com destino `.` (diretório local). Tratamento adicionado em `commands/download.sh` resolvendo o destino quando for diretório e emitindo diagnóstico acionável ao operador instruindo o uso de `dbx sync --receber --origem ... --destino ...`.

## Prompt 4 e 5 — 2026-10-08 1147

> canecele os testes atuais e faça os teste para /PeOuro
> check status of tasks

**Intenção:** Cancelar operação sobre `/asj` e executar testes operacionais de informação, listagem e sincronização sobre a pasta `/PeOuro`. Sincronização e recebimento testados com sucesso com 3 arquivos transferidos e suíte completa de 574 testes verdes.


