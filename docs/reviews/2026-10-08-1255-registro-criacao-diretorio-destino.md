# Registro de Entrega — Criacao Automatica de Diretorios de Destino Inexistentes

> Registro de entrega formal da demanda (Porte M) conforme regra 41 do protocolo comum.

## Identificacao da demanda

| Campo | Valor |
|---|---|
| Demanda | Criacao automatica de diretorios locais de destino inexistentes em `sync --receber` e `download` |
| Data / Hora | 2026-10-08 12:55 |
| Dominio | CLI / Transferencia / Sincronizacao / Sistema de Arquivos |
| Porte | **M (padrao)** — alteracao de comportamento operacional em comandos publicos e novos testes de integracao |
| Instancia | `myPCWin/Adriano Sales Santos` |
| Branch de trabalho | `feature/criacao-diretorio-destino` |
| Branch principal | `develop` |
| Log de prompt | [2026-10-08_1255_criacao-diretorio-destino.md](../prompts/2026-10-08_1255_criacao-diretorio-destino.md) |

---

## Contexto e Objetivo

Ao executar operações de recebimento ou download com destino para novos diretórios locais ainda não criados:
1. O comando `dbx sync --receber --origem <remoto> --destino <novo_dir>` falhava anteriormente com `raiz local inexistente ou nao e diretorio`, forçando o operador a executar `mkdir -p` manualmente antes de sincronizar.
2. O comando `dbx download <remoto> <caminho>` falhava caso o caminho especificasse um subdiretório inexistente.

O objetivo desta demanda é garantir que o utilitário crie os diretórios de destino automaticamente (`mkdir -p`), mantendo a integridade do modo `--dry-run` (que não deve criar diretórios em disco e deve simular o destino inexistente como vazio).

---

## Escopo Tecnico e Arquivos Modificados

| Arquivo | Natureza | Descricao |
|---|---|---|
| `commands/sync.sh` | Modificado | Criação automática da raiz de destino local inexistente no sentido `receber` (se não for simulação); em simulação, trata destino inexistente como lista vazia sem tocar o disco |
| `commands/download.sh` | Modificado | Criação automática de diretórios de destino e subdiretórios intermediários inexistentes antes do recebimento |
| `tests/integracao/sync_test.sh` | Modificado | Novo teste de integração `teste_recebimento_cria_diretorio_de_destino_caso_nao_exista` |
| `tests/integracao/comandos_test.sh` | Modificado | Novo teste de integração `teste_download_cria_diretorio_de_destino_caso_nao_exista` |
| `docs/prompts/2026-10-08_1255_criacao-diretorio-destino.md` | Novo | Registro completo do prompt da demanda |
| `docs/reviews/2026-10-08-1255-registro-criacao-diretorio-destino.md` | Novo | Este registro de entrega e conformidade |

---

## Validacao e Evidencias

- **Suíte de Testes:** 576 aprovados (19 arquivos TAP), 0 reprovados, 2 pulados.
- **ShellCheck:** 0 apontamentos em todos os arquivos modificados.
- **Guarda de Remoção de Casos:** 576 -> 578 verificados, nenhuma redução não declarada.
- **Memória e Skills:** Validadores `memoria-index.sh --check` e `validate-skill-links.sh` aprovados.
