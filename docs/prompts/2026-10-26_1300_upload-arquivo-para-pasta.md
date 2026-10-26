# Upload de arquivo para pasta existente

**Branch:** `feature/upload-arquivo-para-pasta` (de `origin/develop`)
**Porte:** M. `scripts/porte.sh` nao existe no projeto. Muda o contrato do argumento `destino` do `dbx upload` (CLI), sem schema, credencial nem dependencia nova.

## Prompt 1 — 2026-10-26

> em bash bin/dbx --debug upload -p "/mnt/e/nossoerp bkp/nossoerp.bak.zip" "/ASJ/ASJEP/backup/nossoerp bkp" a origem é um arquivo e o destino é uma pasta, nesta casos a aplicação deve entender que o arquivo deve ser enviado para a pasta e não retornar erro

**Intencao:** com origem arquivo e destino que e pasta no Dropbox, o `upload` grava `<pasta>/<nome do arquivo>` em vez de falhar com `path/conflict/folder` no `finish`.

**Origem:** validacao no FreeBSD da demanda `suporte-freebsd` (log `2026-10-24_1153_suporte-freebsd.md`, prompts 7 e 8): a recusa so chegava depois de enviar 393 MiB, embora a pre-checagem `get_metadata` (RF-60) ja tivesse visto a pasta.

**Inferencias do Tech Lead (padroes adotados, sem pergunta):**
- Destino terminado em `/` vale como pasta mesmo sem existir (mesma regra do upload de pasta, `commands/upload.sh`).
- A deteccao de pasta existente reaproveita a consulta `get_metadata` do destino; com `--forcar`, que pula a pre-checagem, a consulta do tipo continua (uma chamada so leitura).
- `--dry-run` nao faz chamada de rede: resolve so pela `/` final.
- Entrada padrao (`-`) para pasta: recusa de uso antes de qualquer envio (nao ha nome de arquivo).
- O caminho final (`<pasta>/<nome>`) vale para a pre-checagem por `content_hash`, a chave da retomada, o `--rev` e o campo `caminho` da saida.

**Decisoes:** o Tech Lead aceitou a consulta so de tipo com `--forcar` e entrada padrao (emenda `RF-60(g)(h)`) e `--rev` sem consulta (com `/` final vale a regra da barra, `RF-174(f)`). **Aprovacao do solicitante (AskUserQuestion, 2026-10-26):** "Aprovo (Recomendado)" para `tests/integracao/qa_upload_para_pasta_b15_test.sh`, 26 casos, sha256 `dabdb304830025c12209554ab6111c31b2d8765015bcc8919d1f871d5934a867`.
