# Registro de Entrega — Suporte a Arquivos e Pastas em Download e Upload

> Registro de entrega formal da demanda (Porte M) conforme regra 41 do protocolo comum.

## Identificação da demanda

| Campo | Valor |
|---|---|
| Demanda | Suporte a arquivos e pastas nos comandos `download` e `upload` |
| Data / Hora | 2026-10-08 15:25 |
| Domínio | CLI / Transferência / Sincronização / Pastas e Arquivos |
| Porte | **M (padrão)** — alteração de contrato operacional público dos comandos `upload` e `download` para suporte transparente a diretórios |
| Instância | `myPCWin/Adriano Sales Santos` |
| Branch de trabalho | `feature/suporte-pastas-upload-download` |
| Branch principal | `develop` |
| Log de prompt | [2026-10-08_1525_suporte-pastas-upload-download.md](../prompts/2026-10-08_1525_suporte-pastas-upload-download.md) |

---

## Contexto e Objetivo

Anteriormente:
1. O comando `dbx upload <origem> <destino>` aceitava somente arquivos regulares e streams (`-`). Diante de diretórios locais, falhava com `arquivo local inexistente ou ilegivel`.
2. O comando `dbx download <remoto> <destino>` aceitava somente arquivos individuais via endpoint `files/download`. Diante de pastas remotas, falhava com `path/not_file/` solicitando ao operador o uso de `sync --receber`.

Esta demanda expande os dois comandos para que trabalhem intuitivamente tanto com arquivos quanto com pastas:
- Em `upload`: detecta se a origem é um diretório local (`[[ -d $origem ]]`), normaliza o destino remoto (anexando o nome base quando o destino termina com barra `/` ou é a raiz `/`) e executa o envio recursivo de todos os arquivos e pastas da árvore, reutilizando o motor `sync --enviar` com integração a metadados SQLite e relatório de progresso.
- Em `download`: tenta receber o arquivo individual; caso o caminho remoto seja uma pasta (erro `not_file` do Dropbox ou raiz `/`), redireciona automaticamente para recebimento recursivo da pasta via `sync --receber`, preservando o nome da pasta remota no destino local e rejeitando com `uso_invalido` apenas se nenhum diretório de destino tiver sido especificado.

---

## Escopo Técnico e Arquivos Modificados

| Arquivo | Natureza | Descrição |
|---|---|---|
| `commands/upload.sh` | Modificado | Suporte a diretórios locais com validação, normalização de caminho remoto e delegação transparente para `sync --enviar` |
| `commands/download.sh` | Modificado | Suporte a pastas remotas (`not_file` e raiz `/`) com criação de diretórios e delegação transparente para `sync --receber` |
| `tests/integracao/comandos_test.sh` | Modificado | Novos testes de integração cobrindo upload recursivo de pasta, download recursivo de pasta e validação de pasta sem destino |
| `docs/prompts/2026-10-08_1525_suporte-pastas-upload-download.md` | Novo | Log de prompt da demanda |
| `docs/reviews/2026-10-08-1525-registro-suporte-pastas-upload-download.md` | Novo | Este registro formal de entrega |

---

## Validação e Evidências

- **Suíte de Testes:** 584 casos aprovados (20 arquivos TAP), 0 reprovados, 2 pulados.
- **Guarda de Redução de Testes:** 583 -> 586 casos medidos em `scripts/verificar-remocao-de-casos.sh` (nenhuma regressão).
- **ShellCheck:** 0 apontamentos em todos os arquivos modificados e no repositório.
- **Memória e Governança:** `ensure-docs.sh`, `memoria-index.sh --check` e `alteracoes-externas.sh` validados com sucesso.
