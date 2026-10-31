# Evidencia de testes - sync-em-blocos (etapas 3a e 3b)

## Etapa 3a
- Teste de download de pasta corrigido conforme RF-186(e): `blc_download_de_pasta_usa_ciclos` e `blc_download_de_arquivo_ignora_a_variavel_invalida_e_o_de_pasta_recusa_2_sem_escrita` em tests/integracao/sync_blocos_test.sh.
- Duble de cursor_test.sh: `_servidor`, `cul11`, `qa_b7b_01/02` ganharam `list_folder` nao recursivo e `get_latest_cursor` (varredura em ciclos pede o cursor da raiz antes do ciclo 1).

## Etapa 3b
Achado bloqueante (RF-189): enumeracao previa lia a arvore remota inteira e cada ciclo a lia de novo. Corrigido com coleta em fluxo (`_dbx_cmd_sync_ciclo_remoto_formar`, `_dbx_cmd_sync_ciclo_proximo`); `cul11` voltou a 1 e 1 (sem leitura duplicada).
Testes novos (sync_blocos_test.sh): cada diretorio listado exatamente uma vez; espelhar com ramo so do destino (RF-190); linha `bloco` no resumo de `--debug` (RF-194); `--paralelo 2` com barreira de ciclo e mesmo resultado (RF-195); falha sistemica 403 para a execucao e falha de arquivo (500) segue (RF-193).
Red: o teste de leitura unica e o `cul11` eram vermelhos pela leitura dobrada anterior (contagem 2). LIMITACAO: para os testes de RF-190, RF-194, RF-195 e RF-193 NAO foi obtido red isolado; neutralizar `_dbx_cmd_sync_parada_sistemica` nao reprovou o teste de RF-193 (a parada ja ocorre por outro caminho no duble). Pendente ao QA/Tech Lead.
Regra simplificada: ciclo remoto nao fecha "antes" de diretorio com mais de N arquivos (ja listado, entra inteiro no ciclo corrente).
Execucao: `bash tests/run.sh sync_`: 6 arquivos, 147 aprovados, 0 reprovados, 0 pulados (inclui sync_blocos). `cursor_test`, `download`, `paralelo` e `scripts/lint.sh`: NAO concluidos nesta etapa (tempo/limite de chamadas).

## Etapa 3c
- `harness_executar` estava no meio de sync_blocos_test.sh: 3 casos nunca rodavam (19 de 22). Movido para a ultima linha.
- Helper `_receber` passava `--dry-run`/`--debug`/`--sem-cursor` antes de `sync`; corrigido (globais antes, demais depois).
- Defeito real: `[[ $ciclo_falho -gt 0 ]] && break` estava fora do while de ciclos (falha sistemica nao parava; o ciclo 2 sobrescrevia `ciclo_falho`). Movido para dentro.
- Teste RF-193 reescrito. Red: com `_dbx_cmd_sync_parada_sistemica` neutralizada falha em `trecho ausente: [ciclo_falho=1]` (fecha a limitacao da 3b para RF-193).
- Composicao: linha 387 usa `_harness_contar` (composicao 28/0).
- Lint: alias `visto` removido (SC2178/SC2128 eram falso positivo do nome); `for fase` de uma volta removido; `dbx_sync_diretorios_remotos` removida, sem uso (verificar-remocao-de-casos 2757 -> 2757).
- Contagens: sync_blocos 41/0, composicao 28/0, sync_test 93/0.

## Etapa 3d
RF-187(c) no `--receber` em fluxo: diretorio remoto com mais de N arquivos forma ciclo sozinho (antes entrava no ciclo corrente). Implementado em `_dbx_cmd_sync_ciclo_remoto_formar` (commands/sync.sh): o diretorio ja listado e contado e seus registros da tabela ficam guardados (`pend_*`), a tabela e truncada e o ciclo fecha; o proximo ciclo restaura a tabela sem listar de novo. `remoto_fim` so vira `sim` sem pendencia. Diretorio > N com ciclo corrente vazio fica sozinho sem guardar.
Teste: `blc_receber_diretorio_maior_que_n_forma_ciclo_sozinho` (`--bloco 2`, raiz com 1 arquivo, /r/a com 3): dois ciclos, recebidos=4, cada diretorio listado uma vez.
- Red (antes da implementacao): `not ok 16 - blc_receber_diretorio_maior_que_n_forma_ciclo_sozinho` (um ciclo so).
- Green: `bash tests/run.sh sync_blocos`: 2 arquivos, 42 aprovados, 0 reprovados, 0 pulados, APROVADA (23 casos em sync_blocos).
- `bash tests/run.sh sync_test`: 2 arquivos, 93 aprovados, 0 reprovados, 0 pulados, APROVADA.
- Nao executados: lint e regressao ampla (a cargo do Tech Lead).

## Correcoes da conformidade

Refactor sem teste novo (comportamento externo inalterado): poda por filtro unificada em `_dbx_walk_podar_entrada` (achado 2) e `DBX_SYNC_DIR_PARCIAL` removida por ser escrita e nunca lida (achado menor 4; o sinal efetivo e o status de retorno, provado por testes existentes). Execucao seletiva: `tests/run.sh filtro` 92 aprovados/0 reprovados; `sync_blocos` 42/0; `sync_test` 93/0. `tests/run.sh walk` interrompe no primeiro erro: `nenhum_ponto_da_travessia_reconstroi_caminho_absoluto` (tests/unit/walk_test.sh:180) conta 3 `cd -P -- "$raiz"` (lib/walk.sh:200, 395, 513) contra 1 esperada; as tres entradas na raiz nao foram tocadas por esta correcao, logo a falha e anterior a ela e segue aberta para o Tech Lead; 7 casos do walk nao executados (nao contam como aprovados). (resolvida: ver paragrafo seguinte)

Entrada na raiz triplicada (falha de `nenhum_ponto_da_travessia_reconstroi_caminho_absoluto`, auditoria DP-26): `dbx_walk_diretorios` e `dbx_walk_ciclo`, desta demanda, repetiam `cd -P -- "$raiz"` cada um no seu subshell. Correcao: auxiliar unico `_dbx_walk_entrar_raiz` em lib/walk.sh (unico `cd -P -- "$raiz"`), chamado nos tres subshells com `|| exit 1`; teste inalterado, nenhum outro `cd` com raiz/prefixo/relativo. Execucao seletiva: `walk` 13 aprovados/0 reprovados/0 pulados; `sync_blocos` 42/0; `filtro` 92/0; `sync_test` APROVADA (0 reprovados, 0 pulados).


Auditorias estaticas (`auth_test`, `json_test`): `_blc_contagens` (lib/sync.sh:632) casava o padrao de identificador de conta; renomeada para `_blc_qtds` em todo o escopo. A massa de `tests/unit/sync_blocos_test.sh:208` usava `$(printf ... | sort | tr ...)`; reescrita com `mapfile` + laco, mesma afirmacao (a acusacao apontava `tests/integracao/sync_blocos_test.sh:186`, mas a unica ocorrencia do padrao estava no teste de unidade). Execucao seletiva: `auth_test` 42 aprovados/0 reprovados/0 pulados; `json_test` 62/0/0; `sync_blocos` 42/0/0.
