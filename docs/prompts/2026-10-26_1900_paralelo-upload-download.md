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

**Etapa 2a (upload em partes simultaneas), commit `71a61d2`; merge da develop com o FreeBSD (#63) e a limpeza do plugin (#62) feito na branch, conflitos resolvidos (registro v2 sem repeticao de regex acima de 255).** Esclarecimento do Tech Lead sobre a `DIV-365` (A): a pausa compartilhada por 429 e implementada assim: o auxiliar espera o proprio `Retry-After` dentro de `lib/http` e o principal para de despachar partes novas ate as em voo terminarem; nao ha propagacao do maior `Retry-After` entre auxiliares em tempo real. O efeito pedido (nenhuma parte nova durante a pausa) se mantem.

**Etapa 2a, QA:** `qa_paralelo_upload_b19_test.sh` (35 casos; mutacoes de N+1 em voo e parte em voo confirmada pegas); achado QA-B19-01 (Maior: intervalos do registro v2 fora de ordem ou sobrepostos aceitos) corrigido no ciclo 2 (`_dbx_state_intervalos_validos`), classe da falha de parte igual a do sequencial, sem janela de residuo alem do SIGKILL apos 5 s. **Decisao do solicitante (AskUserQuestion, 2026-10-26):** "Aprovo (Recomendado)" para `qa_paralelo_upload_b19_test.sh`, sha256 `96fe8d653118cbe6f0c57aeee13f4ee80f9a795ec83d6edc527a68ad5ee06561`.

**Etapa 2b (download em faixas), decisoes do Tech Lead:** escrita em ordem no fim do `.part` pelo descritor no lugar do `dd seek=` (refinamento da `DIV-369`, registrado na especificacao); falha definitiva de uma faixa segue a regra do download sequencial para a mesma classe (`RF-106(a)`): preserva `.part` e registro em `rede|limite_taxa|nao_concluida`, o resto como hoje.

**Etapa 2b, QA (ciclo 1):** `qa_paralelo_download_b20_test.sh` (27 casos, 26 verdes; mutacoes pegas). Achado QA-B20-01 (Maior): a pausa por 429 nao valia durante o `Retry-After` (o coordenador despachava faixas novas enquanto um auxiliar esperava); a mesma aproximacao existia no upload paralelo. Devolvido ao developer: o auxiliar sinaliza o coordenador antes de esperar, nos dois sentidos; o esclarecimento anterior da `DIV-365` deixa de valer. Decisao do Tech Lead: `Content-Range` errado ou `rev` divergente numa faixa seguem como `faixa ignorada` e recomeco sequencial (`RF-104(d)`), sem publicar bytes adulterados; mantido.

**Etapa 2b, ciclo 2:** QA-B20-01 corrigido nos dois sentidos: o auxiliar que recebe 429 cria a marca `DBX_HTTP_MARCA_PAUSA` antes de esperar (`lib/http.sh`), e o coordenador nao despacha enquanto houver marca (`lib/download_paralelo.sh`, `lib/transfer_paralelo.sh`); substitui o esclarecimento anterior da `DIV-365`. **Decisao do solicitante (AskUserQuestion, 2026-10-26):** "Aprovo (Recomendado)" para `qa_paralelo_download_b20_test.sh`, 27 casos, sha256 `efbdda6334fa9111bdc0fd28d26dcd0b77653ca81a3b31cba2f3cc0891f84f0e`.

**Ciclo 3 (intermitentes), 2026-10-27:** a suite completa reprovou na auditoria `composicao` (contagens fora de `_harness_contar` em testes novos e na b19), corrigido. Tres execucoes isoladas da b19 mostraram duas intermitencias: residuo `dbx-http.*` apos SIGTERM (auxiliar morto por SIGKILL sem limpar) e parte da primeira leva com `ini` apos o 429. Produto: cada auxiliar roda com TMPDIR dentro da area do coordenador; a marca de pausa e criada logo ao contar o 429; o coordenador rele as marcas antes de cada lancamento. Testes do QA: o duble so responde 429 depois do `ini` da primeira leva (corrida de medicao, nao do produto); b19 e b20 verdes 5x cada; mutacao sem marca reprova a b20 (`ini 67108864`, faixa 4). **Decisao do solicitante (AskUserQuestion, 2026-10-27):** "Reaprovo (Recomendado)" para `qa_paralelo_upload_b19` (sha256 `e1dc693fe4e65bb82d5d278bbe64e51c12459b0726dfce32bdeb9e6ab7bd5526`) e `qa_paralelo_download_b20` (sha256 `86fc839a8d914d1c44b834f726e995fd63560ac79490dd116876c1d85d668d3e`).

**Suite completa (2026-10-27):** duas execucoes reprovaram em `qa_retomada_b7a::qa_d16_descarte_por_cabecalho_so_apaga_pela_barreira_e_so_do_proprio_alvo` (download com `content_hash` divergente, saida 11) e uma sequencia `qa_` reprovou em `qa_compartilhamento_b5::qa_s05_sinal_durante_a_chamada_limpa_tudo`; todos passam isolados (b7a 6/6) e na sequencia curta; maquina com carga externa (outro projeto: `tsc`, Docker, vite; carga media 3 a 5) e um laco esquecido de subagent (encerrado). Causa nao isolada. **Decisao do solicitante (2026-10-27):** "ignore esse erro".

## Prompt 2 — 2026-10-27

> (colagem: `dbx --debug upload -p --modo overwrite --paralelo 4 "/mnt/e/nossoerp bkp/nossoerp.bak.zip" "/ASJ/ASJEP/backup/nossoerp bkp/"` no FreeBSD 15.1 do solicitante, branch `feature/paralelo-upload-download`; sem segredo) `upload paralelo=4 partes=25 parte_tamanho=16777216`; 25 `append_v2` de 16 MiB concluidos fora de ordem (3, 1, 4, 0, 2, ...), a parte 16 com `curl=28` (tempo esgotado) e sucesso na tentativa 2; ultima parte (24) com `close=true` e 11815282 bytes; `finish` 200; `bytes_enviados: 414468466`, `integridade: conferida`, `size: 414468466`; destino com `/` final resolvido para `<pasta>/nossoerp.bak.zip` (RF-174).

**Leitura do Tech Lead:** upload em partes simultaneas validado no FreeBSD real (RF-177..179): sessao concorrente, ate 4 partes em voo, retentativa de parte isolada, content_hash conferido. Pendente: download com `--paralelo 4`.

## Prompt 3 — 2026-10-27

> (colagem: `dbx --debug download -p --paralelo 4 ".../nossoerp.bak.zip" /tmp/test/n2.zip` no FreeBSD; sem segredo) `download paralelo=4 partes=25 parte_tamanho=16777216`; as 25 faixas 206 chegam fora de ordem; o progresso para em 99% e o comando nao termina (Ctrl+C, saida 14); a reexecucao encontra o `.part` completo (`part_bytes=414468466`), recebe 416, `hash=ok`, `integridade: conferida`, `retomada: sim`, saida 0.

**Leitura do Tech Lead:** defeito da etapa 2b, em qualquer plataforma: com `-p`, o observador de progresso do `.part` roda em segundo plano no principal e o `wait` sem argumento do coordenador (`lib/download_paralelo.sh`) esperava por ele: o download pendurava depois da ultima faixa. Os testes nao usavam `-p`. Correcao: esperar so os PIDs dos auxiliares (download e, por precaucao, upload). Red: `paralelo_download_test::progresso_ativo_nao_pendura_o_fim_das_faixas` pendurou (124) antes e passou depois; filtro `paralelo` 121 aprovados (inclui b18, b19, b20 sem alteracao), `composicao` e `json` verdes. Retomada do download com `.part` completo (416) validada no FreeBSD real.
