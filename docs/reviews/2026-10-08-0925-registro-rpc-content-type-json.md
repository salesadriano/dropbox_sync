# Registro de Entrega — Cabecalho Content-Type: application/json em Chamadas RPC e Preservacao de Erro Textual

> Registro de entrega da demanda pontual (Porte P) conforme regra 41 do protocolo comum e a skill `review-documentation`.

## Identificacao da demanda

| Campo | Valor |
|---|---|
| Demanda | Correcao de HTTP 400 em chamadas RPC da API Dropbox v2 (`list`, `space`, etc.) e preservacao de erro textual |
| Data / Hora | 2026-10-08 09:25 |
| Dominio | HTTP / API Dropbox v2 / Diagnostico |
| Porte | **P (pontual)** — alteracao em `lib/http.sh`, testes unitarios e integrados |
| Instancia | `myPCWin/Adriano Sales Santos` |
| Branch de trabalho | `fix/rpc-content-type-json` |
| Branch principal | `develop` |
| Log de prompt | [2026-10-08_0925_rpc-content-type-json.md](../prompts/2026-10-08_0925_rpc-content-type-json.md) |

---

## Contexto e Causa Raiz

Ao autenticar com sucesso a aplicacao via `./bin/dbx config` (OAuth2 offline) e executar `./bin/dbx list`, a operacao falhava com:
```
erro: listagem recusada: codigo 400
```
Da mesma forma, `./bin/dbx space` falhava com `erro: chamada recusada: codigo 400`.

A investigacao identificou duas causas correlacionadas:
1. **Ausencia do cabecalho `Content-Type: application/json` nas chamadas RPC:**
   Em `lib/http.sh:186` (`_dbx_http_opcoes`), o ramo padrao (`_DBX_HTTP_MODO=bearer`) emitia apenas `header = "Authorization: Bearer <token>"`. Ao passar corpo JSON com `--data-binary "@$area/requisicao"`, o utilitario `curl` assumia por padrao `Content-Type: application/x-www-form-urlencoded`. Todos os endpoints RPC da API v2 do Dropbox (`https://api.dropboxapi.com/2/*`, como `files/list_folder`, `users/get_space_usage`, `files/delete_v2`, `files/get_metadata`) exigem estritamente `Content-Type: application/json`, rejeitando chamadas com HTTP 400 Bad Request.
2. **Ocultamento de mensagens de erro em texto plano:**
   Quando a API do Dropbox responde a erros de requisicao/cabecalho em texto plano (`Error in call to API function...`), `_dbx_http_interpretar_erro()` tentava analisar via `dbx_json_analisar`, que falhava por nao se tratar de JSON. Como resultado, `DBX_HTTP_RESUMO_DE_ERRO` permanecia vazio, e o usuario via apenas a mensagem generica `codigo 400` em vez da causa real.

---

## Modificacoes Realizadas

1. **Camada HTTP (`lib/http.sh`):**
   - Em `_dbx_http_opcoes()`: no caso padrao/bearer (`*)`), adicionada a emissao explicita de `header = "Content-Type: application/json"`.
   - Em `_dbx_http_interpretar_erro()`: adicionado tratamento alternativo caso o corpo da resposta nao seja JSON valido, capturando e sanitizando a primeira linha util (com limite de 120 caracteres) como `DBX_HTTP_RESUMO_DE_ERRO`.

2. **Testes Unitarios (`tests/unit/http_test.sh`):**
   - Adicionado `teste_opcoes_de_bearer_incluem_content_type_json`, verificando a emissao de `header = "Content-Type: application/json"`.
   - Adicionado `teste_interpretacao_de_erro_nao_json_preserva_mensagem_textual`, garantindo que respostas textuais de erro nao sejam descartadas.

3. **Testes de Integracao (`tests/integracao/comandos_test.sh`):**
   - Adicionado `teste_list_envia_content_type_json`, assegurando que o comando `dbx list` envie o cabecalho `Content-Type: application/json` nas opcoes passadas ao transporte.

---

## Evidencias de Validacao

- **TDD:**
  - Fase vermelha observada nos 2 novos testes unitarios (`http_test.sh`), comprovando a falha antes da correcao.
  - Fase verde confirmada apos implementacao em `lib/http.sh`.
- **Validacao contra a API Real do Dropbox:**
  - `./bin/dbx list` executado com exito na conta real do usuario, listando 22 pastas remotas com saida estruturada e saida 0.
  - `./bin/dbx space -H` executado com exito, exibindo uso (24 TiB) e cota (31 TiB) reais da conta com saida 0.
- **Suite de testes completa (`tests/run.sh`):**
  - 18 arquivos executados, 559 casos aprovados, 0 reprovados, 2 pulados.
- **Verificacao de contagem de casos (`scripts/verificar-remocao-de-casos.sh`):**
  - 558 -> 561 casos (+3 casos adicionados, nenhuma reducao).
- **Linter (`shellcheck`):**
  - Zero apontamentos em `lib/*.sh commands/*.sh bin/* scripts/*.sh`.
- **Deteccao de alteracoes externas (`scripts/alteracoes-externas.sh`):**
  - Executado e validado.

---

## Parecer do Tech Lead

- **Status:** Aprovado para integracao em `develop`.
- **Compatibilidade:** Retrocompativel e compativel com o contrato de transporte da API Dropbox v2.
