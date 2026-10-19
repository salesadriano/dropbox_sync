# Análise do projeto `dropbox_sync` — melhorias priorizadas

## Visão geral

| Item | Situação |
|---|---|
| Código | ~8,8 mil linhas de Bash (`lib/` 17 módulos, `commands/` 9, `bin/dbx`) |
| Testes | `bash tests/run.sh` → **608 aprovados, 0 reprovados, 2 pulados** |
| Lint | `shellcheck` limpo (exit 0), com 94 `disable=SC…` — a maioria é SC2034 de "canais públicos" globais |
| Pontos fortes | Segredo nunca vai para `argv` (`curl -K -`), proteção contra injeção de cabeçalho, taxonomia de erros centralizada, integridade via `content_hash`, salvaguardas do `--espelhar` (dry-run, `--confirmar`, travessia parcial) |
| Ambiente analisado | `sqlite3` **ausente** → `lib/db.sh` está usando o fallback `python3` |

O projeto é sólido em segurança de credenciais. Os riscos reais estão em **integridade de dados no `sync`/`download`**, **robustez de rede** e **desempenho**.

---

## 🔴 P1 — Defeitos com risco de perda ou corrupção de dados

### 1. Sincronização ignora diferença de maiúsculas/minúsculas (Dropbox não diferencia)
[lib/sync.sh:64-76](../../lib/sync.sh#L64-L76) e [dbx_sync_planejar](../../lib/sync.sh#L186-L216)

- As chaves dos mapas usam `path_display` e o caminho local **com a grafia original**.
- Local `Docs/Foto.JPG` × remoto `docs/foto.jpg` → é **o mesmo arquivo** no Dropbox, mas o plano diz "transferir" + "apagar".
- Com `--enviar --espelhar`: o upload sobrescreve o arquivo e em seguida o `delete_v2` **apaga o arquivo recém-enviado**.
- **Correção:** usar `path_lower` como chave e comparar o relativo local em minúsculas; detectar colisões locais (`a.txt` e `A.txt`) e recusar.

### 2. `sync --enviar` (e `upload <diretório>`) falha para arquivos > 150 MiB
[_dbx_cmd_sync_enviar](../../commands/sync.sh#L483-L489)

- Usa sempre `files/upload` (requisição única); não passa pelo `dbx_transfer_sessao`.
- Também **não envia `client_modified`** e usa `overwrite` sem `rev` — exatamente a "família de gêmeos" que o cabeçalho de [upload.sh](../../commands/upload.sh#L15-L22) tenta evitar.
- **Correção:** reutilizar `_dbx_upload_objeto_de_publicacao` + roteamento por tamanho num único helper compartilhado.

### 3. Recebimento grava direto no arquivo final
[_dbx_cmd_sync_receber](../../commands/sync.sh#L491-L499) e [download.sh:135](../../commands/download.sh#L135-L136)

- Queda de rede no meio = arquivo local bom **truncado/corrompido**.
- No `sync` não há verificação de `content_hash` (no `download` há, mas só depois de sobrescrever).
- **Correção:** baixar para `alvo.dbx-part` no mesmo diretório → conferir hash → `mv` atômico. Aplicar `mtime` do servidor e registrar no cache.

### 4. `download` pode apagar arquivo do usuário
[download.sh:146](../../commands/download.sh#L146)

- No ramo `not_file`, faz `rm -f -- "$alvo"`. `dbx download /Pasta ./relatorio.txt` com `relatorio.txt` existente → **arquivo local removido** para virar diretório.
- **Correção:** recusar se `$alvo` já existir como arquivo regular.

### 5. `umask 077` vaza para o processo inteiro
[lib/http.sh:368](../../lib/http.sh#L368)

- Testado: `f(){ umask 077; }; f; umask` → `0077`. Após a 1ª chamada HTTP, todo arquivo baixado sai `0600` e todo diretório criado sai `0700`.
- `lib/config.sh` e `lib/transfer.sh` salvam/restauram; `lib/http.sh` não. `transfer` "restaura" para um valor que já está contaminado.
- **Correção:** aplicar o umask só na criação (`(umask 077; mktemp -d ...)`) ou salvar/restaurar.

### 6. `trap ... RETURN` permanece armado após o retorno
[lib/http.sh:397](../../lib/http.sh#L397)

- Testado: o trap dispara de novo no retorno da função **chamadora**. Na reemissão diagnóstica (chamada recursiva, linha 561) a variável global é sobrescrita e a área temporária externa **vaza**.
- **Correção imediata:** `trap 'rm -rf -- "$DBX_HTTP_AREA_TEMP"; trap - RETURN' RETURN`. **Estrutural:** o `lib/tmp` já previsto no backlog (um trap `EXIT` único com lista de áreas registradas).

---

## 🟠 P2 — Robustez de rede

| # | Problema | Onde | Sugestão |
|---|---|---|---|
| 7 | **Sem timeout** — `curl` pode travar indefinidamente | [_dbx_http_executar](../../lib/http.sh#L409-L429) | `connect-timeout = 15`, `speed-limit`/`speed-time` (ex.: 1 KB/s por 60 s) em `_dbx_http_opcoes`; configurável por env |
| 8 | Política `respeitar_retry_after` **não lê** o cabeçalho `Retry-After` | [_dbx_http_esperar](../../lib/http.sh#L112-L118) | Extrair em `_dbx_http_correlacao_de` e usar como espera (com teto) |
| 9 | 3 tentativas com base 250 ms (~1,75 s no total) — pouco para 429/503 da Dropbox | [http.sh:54,61](../../lib/http.sh#L54-L61) | 5 tentativas, base 1 s, teto 60 s |
| 10 | Upload por sessão não é retomável: falha na parte N reinicia do zero | [lib/transfer.sh](../../lib/transfer.sh#L556-L590) | Para arquivo regular (posicionável), reler a partir do `correct_offset` em vez de abortar |
| 11 | Falhas por arquivo no `sync` são silenciadas (`>/dev/null 2>&1`); só sai a contagem | [sync.sh:483-506](../../commands/sync.sh#L483-L506) | Emitir campo `falha <caminho>: <resumo>` na saída |

---

## 🟡 P3 — Desempenho

1. **Um processo `sqlite3`/`python3` por consulta** — [_dbx_db_executar_sql](../../lib/db.sh#L58-L93). No `sync`, cada arquivo idêntico dispara ≥1 `INSERT`; com Python (~40 ms cada), 10 mil arquivos ≈ 7 min só de cache. Agrupar tudo numa transação ao final (`BEGIN; …; COMMIT;`) em uma única invocação.
2. **Dois caches sobrepostos**: `lib/state.sh` (arquivo NUL-delimitado) e `lib/db.sh` (SQLite) guardam o mesmo `hash × tamanho × mtime`. Escolher um.
3. **Operações sequenciais**: considerar paralelismo limitado (`xargs -P`/jobs) para uploads/downloads pequenos e `delete_batch`/`upload_session/finish_batch` da API.
4. **Muitos subshells** por requisição (`$(dbx_errors_classificar …)`, `$(dbx_errors_codigo_saida …)` chamado duas vezes em [http.sh:571-572](../../lib/http.sh#L571-L572)). Publicar o resultado por variável, como o resto do projeto já faz.

---

## 🔵 P4 — Correção e consistência

- **Skip do `upload` só olha o lado local** ([upload.sh:238-252](../../commands/upload.sh#L238-L252)): se o arquivo remoto foi apagado/alterado, o envio é "dispensado" indevidamente — inclusive com `--modo overwrite`. Validar o `rev` remoto (`get_metadata`) ou desativar o skip em `overwrite`.
- **Chave do cache não é canônica**: `./a.txt`, `a.txt` e `/home/…/a.txt` viram registros distintos. Normalizar com `realpath`.
- **SQL montado por interpolação** em [lib/db.sh](../../lib/db.sh#L109-L164): só `'` é escapado e os números entram sem validação. Validar `^[0-9]+$` ou usar parâmetros (`python3` suporta `?`).
- **Fallback Python** escolhe `executescript` por heurística (`";" in sql`) e descarta stderr — erros de banco ficam invisíveis.
- **Troca de código sem `client_secret` não funciona** sem PKCE ([dbx_auth_trocar_codigo](../../lib/auth.sh#L358-L428)): o segredo é opcional no código, mas a Dropbox exige `code_verifier` nesse caso. Implementar PKCE (S256) ou tornar o segredo obrigatório.

---

## ⚪ P5 — Documentação e manutenção

- **Documentação contraditória**: [CLAUDE.md](../../CLAUDE.md#L12-L14) e [http.sh:25-27](../../lib/http.sh#L25-L27) dizem "sem estado local persistente / cURL única dependência", mas já existem `lib/db.sh` (SQLite em `~/.local/state`) e `lib/state.sh`, com `sqlite3`/`python3` como dependências opcionais. Atualizar e incluir no `preflight`.
- **Comentários narrativos muito longos** (ex.: [http.sh:377-396](../../lib/http.sh#L377-L396)): histórico de defeitos ("pela sexta vez", "medido…") deveria ficar em `docs/registros`/ADRs; no código, deixar só o *porquê* atual.
- **Peso do processo**: `.github/` tem 9 MB e `docs/` 1,4 MB para ~9 mil linhas de código. Avaliar se o protocolo de agentes cabe num pacote separado/submódulo.
- **Mistura de idiomas nas flags** (`--modo`/`--mode`, `--forcar`/`--force`) está ok, mas `sync` não oferece aliases em inglês (`--origem`, `--enviar`) — padronizar.
- **Testes faltantes** sugeridos: colisão de caixa no sync; sync com arquivo > limite; interrupção no meio de download (arquivo anterior preservado); umask após download; `Retry-After`.

---

## Ordem sugerida de execução

```mermaid
flowchart LR
  A["P1.5/P1.6 umask e trap (rápido)"] --> B["P1.4 rm em download"]
  B --> C["P1.3 download atômico + hash"]
  C --> D["P1.1 caixa no sync"]
  D --> E["P1.2 sync usa sessão/objeto único"]
  E --> F["P2 timeouts e Retry-After"]
  F --> G["P3 cache em lote / cache único"]
```
