# Registro de Entrega — Cache Local SQLite de Metadados e Hash para Upload e Sync

> Registro de entrega formal da demanda (Porte M) conforme regra 41 do protocolo comum.

## Identificacao da demanda

| Campo | Valor |
|---|---|
| Demanda | Manutenção de banco SQLite local para metadados/hash, dispensando upload/sync de arquivos locais inalterados e suporte a `--forcar` |
| Data / Hora | 2026-10-08 14:25 |
| Dominio | Armazenamento Local / SQLite / Metadados / Otimização de Transferência / CLI |
| Porte | **M (padrao)** — novo componente de persistência SQLite (`lib/db.sh`), novos testes unitários/integração e otimização de `upload` e `sync` |
| Instancia | `myPCWin/Adriano Sales Santos` |
| Branch de trabalho | `feature/banco-sqlite-metadados` |
| Branch principal | `develop` |
| Log de prompt | [2026-10-08_1425_banco-sqlite-metadados-cache.md](../prompts/2026-10-08_1425_banco-sqlite-metadados-cache.md) |

---

## Contexto e Objetivo

Nas operações de transferência de arquivos (`upload` e `sync --enviar`), arquivos locais de grande porte ou coleções volumosas exigiam releitura contínua e recálculo intensivo de `content_hash` ou transferências desnecessárias para destinos remotos onde o arquivo já se encontrava idêntico.

Os objetivos desta demanda foram:
1. Implementar um componente de banco relacional SQLite local (`~/.local/state/dbx/dbx.db`) encapsulado em `lib/db.sh` para persistir metadados locais (`tamanho`, `mtime`, `content_hash`) e histórico de operações bem-sucedidas (`upload`, `sync`).
2. Adaptar o motor do SQLite com suporte nativo híbrido: uso do CLI `sqlite3` ou fallback transparente para `python3` com biblioteca padrão `sqlite3` (garantindo compatibilidade quando o pacote `sqlite3` CLI não estiver instalado).
3. No comando `upload`: verificar se o arquivo local permanece inalterado para o destino remoto desde a última operação bem-sucedida. Se inalterado, dispensar o envio (emitindo `status=dispensado` e `motivo=inalterado`, com código de saída 0), permitindo forçar o re-upload via sinalizador `--forcar` / `--force`.
4. No comando `sync --enviar`: consultar o banco SQLite durante o resumo local para reaproveitar instantaneamente o `content_hash` de arquivos locais inalterados sem releitura de disco, e salvar metadados e operações bem-sucedidas.
5. Melhorar o diagnóstico de erro no comando `download` quando o caminho não existe (`not_found`), alertando o operador caso se trate de uma pasta que deve ser sincronizada com `sync --receber`.

---

## Escopo Tecnico e Arquivos Modificados

| Arquivo | Natureza | Descricao |
|---|---|---|
| `lib/db.sh` | Novo | Adaptador SQLite resiliente com DDL das tabelas `metadados_arquivos` e `operacoes_arquivos`, motor híbrido `sqlite3`/`python3`, suporte a WAL mode, índices e funções públicas para consulta e registro |
| `tests/unit/db_test.sh` | Novo | Suíte unitária (4 testes) cobrindo inicialização DDL, ciclo de metadados, operações e detecção de arquivos inalterados/alterados |
| `commands/upload.sh` | Modificado | Adicionado suporte a `--forcar` / `--force`, verificação prévia no banco SQLite com dispensa de envio (`status=dispensado`, `motivo=inalterado`) e gravação pós-envio |
| `commands/sync.sh` | Modificado | Integração com SQLite no resumo local (`_dbx_cmd_sync_resumo_local`) e registro de operações bem-sucedidas |
| `commands/download.sh` | Modificado | Diagnóstico específico para erro `not_found`, orientando o operador sobre caminho inexistente e uso de `sync --receber` para diretórios |
| `tests/integracao/comandos_test.sh` | Modificado | Novo teste de integração `teste_upload_dispensa_arquivo_inalterado_e_forca_com_sinalizador` e isolamento de entrada padrão em `_rodar` |
| `docs/prompts/2026-10-08_1425_banco-sqlite-metadados-cache.md` | Novo | Registro completo do prompt e contexto da demanda |
| `docs/reviews/2026-10-08-1425-registro-banco-sqlite-metadados.md` | Novo | Este registro de entrega e conformidade |

---

## Validacao e Evidencias

- **Suíte de Testes:** 581 aprovados (20 arquivos TAP), 0 reprovados, 2 pulados.
- **ShellCheck:** 0 apontamentos em todos os arquivos adicionados e modificados.
- **Auditoria de Comandos e Alfabeto:** Conformidade estrita com `preflight_test.sh` e `json_test.sh` (sem comandos externos não declarados, sem captura proibida de bytes externos).
- **Fallback SQLite:** Validado e aprovado em ambiente sem `sqlite3` CLI utilizando motor transparente em `python3`.
- **Memória e Skills:** Validadores `memoria-index.sh --check` e scripts de governança executados.
