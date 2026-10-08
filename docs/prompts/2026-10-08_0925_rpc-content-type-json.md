---
date: 2026-10-08
hora: "0925"
domain: http / api dropbox v2
porte: P
status: concluido
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-08-0925-registro-rpc-content-type-json.md"
---

# rpc-content-type-json

## Prompt 1 — 2026-10-08 0912

> check sales@myPCWin:~/dropbox_api$ ./bin/dbx list
> erro: listagem recusada: codigo 400

**Intenção:** Diagnosticar e corrigir a falha de execução de `./bin/dbx list` (e demais comandos RPC como `./bin/dbx space`) que retornam `erro: listagem recusada: codigo 400` mesmo após autenticação bem-sucedida via OAuth2 offline.

**Causa Raiz Identificada:**
1. Em `lib/http.sh:186` (`_dbx_http_opcoes`), no modo padrão (`bearer`), as opções geradas para `curl` incluem apenas o cabeçalho `Authorization: Bearer ...`, omitindo `Content-Type: application/json`.
2. Ao enviar o corpo JSON via `--data-binary "@$area/requisicao"`, o `curl` adota `Content-Type: application/x-www-form-urlencoded` por padrão na ausência de especificação explícita. A API v2 do Dropbox rejeita chamadas RPC em endpoints `api.dropboxapi.com/2/*` com HTTP 400 Bad Request se o cabeçalho não for `application/json`.
3. Adicionalmente, quando o Dropbox responde a esse erro em formato de texto simples (não-JSON), `_dbx_http_interpretar_erro` não capturava a mensagem de erro do corpo da resposta, deixando `DBX_HTTP_RESUMO_DE_ERRO` vazio e exibindo genericamente apenas `codigo 400`.

**Inferências e Decisões do Solicitante:**
- **Escopo:** Pontual (Porte P).
- **Correção em `lib/http.sh`:**
  - Adicionar `header = "Content-Type: application/json"` no ramo padrão/bearer de `_dbx_http_opcoes()`.
  - Melhorar `_dbx_http_interpretar_erro()` para preservar a primeira linha de texto do corpo de resposta não-JSON (sanitizada e truncada) como `DBX_HTTP_RESUMO_DE_ERRO`.
- **Testes automatizados:**
  - Adicionar caso de teste unitário verificando que chamadas RPC no modo `bearer` configuram o cabeçalho `Content-Type: application/json`.
  - Adicionar caso de teste unitário verificando interpretação de corpo de erro textual não-JSON.
