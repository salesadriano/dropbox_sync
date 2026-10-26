# Paralelismo no upload e no download

**Branch:** `feature/paralelo-upload-download` (de `origin/develop` @ `6df321e`)
**Porte:** G. `scripts/porte.sh` nao existe no projeto. Estende `RF-133` (contrato da CLI `--paralelo`/`DBX_PARALELO`) a dois comandos e cria transferencia de um arquivo em partes simultaneas: sessao concorrente no upload, faixas `Range` no download, retomada e conferencia de integridade com partes fora de ordem (formato do estado de retomada).

## Prompt 1 — 2026-10-26

> dowload e upload devem suportar --paralel támbem

**Intencao:** `dbx upload` e `dbx download` aceitam `--paralelo N` (alias `--parallel`), hoje so do `sync` (`RF-133(e)` recusa em outros comandos com `2`; o upload e o download de pasta nunca usam paralelismo, decisao da fase 9).

**Decisoes do solicitante (AskUserQuestion, 2026-10-26):**
- Escopo: "Pastas e arquivo grande" (contra a recomendacao "So pastas"): pasta com varios arquivos simultaneos, pelo mecanismo do `sync`; e arquivo grande em partes simultaneas (sessao concorrente no upload, faixas `Range` no download).
- Variavel: "Sim, igual ao sync (Recomendado)": `DBX_PARALELO` vale para upload e download; a opcao vence a variavel.

**Plano do Tech Lead:** duas etapas na mesma demanda, com entregas separadas: (1) pastas, pelo mecanismo ja validado do `sync`; (2) arquivo grande em partes simultaneas, depois da especificacao do BA com as divergencias levadas ao solicitante.

**Decisoes do solicitante (AskUserQuestion, 2026-10-26):** "Aceito todas (Recomendado)" para `DIV-358` a `DIV-376` (secao 5.23, RF-175..185; a `DIV-367` condicionada ao teste de contrato); "Pode testar (Recomendado)": teste de contrato da sessao concorrente contra a conta real, com arquivo de 40 MiB em `/dbx-teste-contrato/`, conferencia do `content_hash` e remocao do arquivo e da pasta ao fim (`RSK-98`).

**Teste de contrato (`RSK-98`), 2026-10-26, conta real do solicitante, script `scratchpad/contrato-concorrente.sh` (sem token nem `session_id` na saida):** `upload_session/start` com `session_type: concurrent` 200 (`session_id` de 69 caracteres, alfabeto `[A-Za-z0-9:_-]`); tres `append_v2` de 16 MiB SIMULTANEOS e FORA DE ORDEM (a ultima parte, com `close=true`, primeiro) todos 200; REENVIO da parte ja aceita (mesmo deslocamento e bytes) 200; `finish` com `offset` = total 200; `size` 41955385 = local; `content_hash` igual ao local; `/dbx-teste-contrato` apagada (200). Confirma a opcao A da `DIV-367` (parte em voo reenviada na retomada) e o contrato de `RF-178`.

**Etapa 1 (pastas):** QA independente `tests/integracao/qa_paralelo_pastas_b18_test.sh`, 10 casos, mutacoes M1/M2 pegas; achado menor corrigido pelo Tech Lead (`commands/diagnostico.sh:408`, aviso citava so o sync). **Decisao do solicitante (AskUserQuestion, 2026-10-26):** "Aprovo (Recomendado)" para `qa_paralelo_pastas_b18_test.sh`, sha256 `94f2b18c884f014b162632451ac28c2c1f0a2b372be37bcadf3d7e4e02071c44`.
