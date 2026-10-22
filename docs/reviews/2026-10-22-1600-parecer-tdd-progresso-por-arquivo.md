# Parecer de Evidencias de Testes (TDD) — Fase 10, progresso por arquivo (F-49)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: secao 5.19 (RF-140 a RF-147, TC-PRG-01 a 36, DIV-282 a DIV-303); porte **G**
- Agent: Senior Developer, revisao independente do gate (nao implementou; nao alterou codigo nem testes do worktree)
- Data: 2026-10-22
- Branch / base: `feature/progresso-por-arquivo` sobre `develop` @ `a39a89e`; nada commitado
- Log de prompt: [2026-10-22_1600_progresso-por-arquivo.md](../prompts/2026-10-22_1600_progresso-por-arquivo.md)
- Fontes: `git diff`, leitura integral de `tests/unit/progresso_linha_test.sh` e `tests/integracao/progresso_arquivo_test.sh`, 4 mutacoes em copia descartavel. Reexecutei `bash tests/run.sh progresso < /dev/null` (copia sem mutacao efetiva antes de cada mutante): 2 arquivos, 36 aprovados (17 + 19), 0 reprovados, confirmando a contagem declarada. Demais contagens (progress_test 16, comandos 119, sync 85, paralelo 14, lote 32, tmp 16, qa_ 490) sao do log; nao reexecutadas por mim. Suite completa: nao e deste gate (Regra 8).

## 1. Escopo e modulos

| Arquivo | Testes que cobrem |
|---|---|
| `lib/progress.sh` (linha, observador, bloco) | `progresso_linha` 17, `progress_test` 16, `progresso_arquivo` (bloco) |
| `lib/transfer.sh` (avanco por parte, retomada) | `progresso_arquivo` upload em sessao; `upload`, `retomada_upload` (log) |
| `lib/cmd.sh` (observador do `.part`, retomada de download) | so por reflexo: nenhum teste exercita o observador pelo `bin/dbx` (achados 3 e 5) |
| `commands/download.sh`, `commands/upload.sh` | `progresso_arquivo`, `comandos` |
| `commands/sync.sh` (bloco N>1, canal de status) | `progresso_arquivo` (5 casos paralelos), `paralelo`, `sync_test` |
| `lib/http.sh` (sem `progress-bar`) | `comandos` (2 assercoes alteradas) |

O projeto nao tem mapa de modulos alem dos nomes de `tests/run.sh`; a selecao foi do Tech Lead (limitacao herdada, mesma dos pareceres vizinhos).

Gatilhos da Regra 6: upload/download de arquivo, nome de arquivo de entrada de usuario que chega ao terminal (injecao de controle), segredo em log (RNF-03). Cenarios negativos presentes: caractere de controle no nome (TC-PRG-29), progresso inativo sem efeito (RF-145(c)). **Ausente: sentinela de segredo (TC-PRG-28).**

## 2. Vermelho

| Fatia | Red | Avaliacao |
|---|---|---|
| `progresso_linha` | so o primeiro caso ("command not found") | 16 dos 17 sem red registrado |
| integracao etapa 1 | primeiro caso reprovou; 11 nao executados; testes escritos depois do codigo | desvio declarado do Passo 2 |
| integracao etapa 2 | `int_com_n3...` ok=3 nao_ok=1 | unico red real da etapa |

Red comprovado por mutacao (abaixo) so para parte dos comportamentos.

## 3. Mutacoes (copia em scratchpad, removida ao fim; `bash tests/run.sh progresso`)

| # | Mutacao | Resultado |
|---|---|---|
| M1 | `commands/download.sh`: remover `dbx_progress_arquivo_falhar` na falha do recebimento | **SOBREVIVEU** (36/36 verdes). Nenhum teste faz o download falhar com progresso ativo; RF-146/TC-PRG-31 so e provado para upload e sync |
| M2 | `lib/transfer.sh`: remover o `dbx_progress_arquivo_avancar` por parte no laco de sessao | MORTA por `progresso_arquivo` (upload em sessao, ao menos 4 linhas); 34 aprovados, 1 reprovado, parou no primeiro erro |
| M3 | `lib/progress.sh`: `dbx_progress_arquivo_falhar` passa a marcar concluido (forja 100%) | MORTA por `progresso_linha` (falha deixa ultimo percentual / nunca 100%) |
| M4 | `lib/cmd.sh`: remover `dbx_progress_arquivo_avancar "$inicio"` do recebimento retomavel (DIV-294, nunca 0% na retomada) | **SOBREVIVEU** (36/36 verdes). So a funcao pura `iniciar ... feitos` e testada; a ligacao no download retomavel nao |

Rotulo de falsa seguranca: M2 e M3 morrem porque ha teste com asserção sobre o resultado observavel. M1 e M4 sobrevivem porque o caminho nem e executado pelos testes.

## 4. Piramide e proibicoes

CLI Bash sem banco, UI ou backend proprio; o "backend" e a API Dropbox, simulada por duplo de `curl` (fronteira externa, permitido). Sem Cypress/Testcontainers aplicaveis.

| Camada | Casos novos | Parcela |
|---|---|---|
| Unitario (funcoes `dbx_progress_arquivo_*`) | 17 | 47% |
| Integracao (`bin/dbx` + duplo de `curl`) | 19 | 53% |
| E2E contra conta real | nenhum | n/a |

Desvio do 70/20/10 justificado pela natureza do projeto (orquestracao de processos e saida em stderr); nao e achado. As asserções de linha usam literais independentes (ex.: `[3/10] enviando: fotos/a.jpg [████░░░░░░] 40% 4 MiB / 10 MiB`), sem tautologia. AAA e seam publica respeitados.

## 5. Cobertura por TC-PRG (por tag e por leitura)

| Situacao | TC |
|---|---|
| Coberto | 01, 02, 03 (via linha 40%), 04, 06, 08, 10 (so unit), 11, 12, 13, 14, 15, 16/17/19 (paralelo, sem tag), 20 (stdout/estado/cache; sem N=1 vs N=4 x com/sem progresso nos 4 cruzamentos), 21, 22, 23, 25, 29, 30 (parcial), 31, 32, 34 |
| **Sem teste encontrado** | 05 (0% antes da 1a requisicao), 07 (erro em `append_v2` parte 2, maximo = parte 1), 09 (lote com `finish_batch_v2` parcial), 18 (so o principal escreve em fd 2), 24 (upload/download de pasta), 26, 27 (integracao: nenhum observador/canal; so o unit), 28 (sentinela RNF-03), 33 (falha com `--paralelo 4` e codigo igual ao N=1), 35 (stderr identico a `a39a89e`), 36 (help/README) |

## 6. Testes existentes alterados

- `tests/unit/progress_test.sh`, 8 asserções: `assert_contem '(N%)'` virou `assert_nao_contem '(N%)'`, coerente com RF-147(b). Porem ficaram **so negativas**: uma `dbx_progress_etapa` que imprimisse lixo passaria. Falta uma asserção positiva do novo formato `[i/N] acao: item [barra]` nesses casos. Menor.
- `tests/integracao/comandos_test.sh`, 2 asserções: `progress-bar` agora ausente (DIV-293). Coerente e verificada contra a mudanca em `lib/http.sh`. Sem objecao.

## 7. Parada no primeiro erro e execucao seletiva (Regras 8 e 9)

Confirmado nas minhas execucoes: `tests/run.sh` interrompe no primeiro arquivo com erro e relata `interrompida em ... (primeiro erro; N arquivo(s) nao executado(s))` com resultado REPROVADA (vistas em M2 e M3); nenhum erro mascarado. Selecao seletiva dos modulos atingidos registrada no log pelo Tech Lead. Suite completa local e pipeline: pendentes (push que abre a PR para `master`), fora deste parecer.

## 8. Achados

| # | Sev. | Local | Achado | Regra | Correcao |
|---|---|---|---|---|---|
| 1 | Maior | `commands/download.sh` (falha do recebimento); `tests/integracao/progresso_arquivo_test.sh` | M1 sobreviveu: sem teste de download que falha com progresso ativo (RF-146, TC-PRG-31 no download) | Passo 6 (comportamento alterado sem teste), mutacao | Caso: `--progresso download` com `download_erro=404`; esperar ` falhou`, ausencia de `100%` e estado diferente de 0 |
| 2 | Maior | `lib/cmd.sh` (`dbx_progress_arquivo_avancar "$inicio"` em `dbx_cmd_receber_retomavel`); mesmo teste | M4 sobreviveu: a retomada do download comecando no confirmado (DIV-294) so e provada em funcao pura | Passo 6 | Caso de integracao com `.part` preexistente > 150 MiB (ou a semente de limiar do projeto) e asserção de que a primeira linha nao e `0%` |
| 3 | Maior | `tests/integracao/progresso_arquivo_test.sh` | TC-PRG-05, 07, 09, 18, 24, 26, 28, 33, 35, 36 sem teste. Destaque para 28 (segredo em stderr, gatilho da Regra 6), 07/09/33 (falha parcial) e 35 (regressao do stderr sem progresso) | Regra 6; Passo 6 | Escrever os casos (QA pode detalhar, mas o gate local do Senior exige o minimo: 28, 07, 09, 33); 35 por comparacao com a saida da base em worktree temporario |
| 4 | Maior | `tests/integracao/progresso_arquivo_test.sh:265` e `lib/cmd.sh` | O observador do `.part` e o "100% so apos `content_hash` conferido" (TC-PRG-10) nao sao exercidos pelo `bin/dbx`: os downloads de integracao tem 15 B (< 1 MiB, sem observador). Fiacao em `dbx_cmd_receber_arquivo` e `dbx_cmd_receber_retomavel` sem prova | Passo 6 | Caso com `.part` crescente > 1 MiB no duplo: percentuais intermediarios crescentes, `100%` apos a conferencia, nenhum processo orfao (TC-PRG-30 de ponta a ponta) |
| 5 | Maior | log; testes de ambas as etapas | Red registrado apenas para 3 casos; 11 de 12 casos da etapa 1 escritos depois do codigo; so M2 e M3 provam red por mutacao. Desvio declarado, nao oculto | Regra 1, Passo 2 | Feitos 1 a 4, a mutacao passa a provar o red; registrar no log |
| 6 | Menor | `tests/unit/progress_test.sh` (8 asserções) | Troca para asserção so negativa (secao 6) | tdd-test-design | Acrescentar asserção positiva do novo formato |
| 7 | Menor | `tests/unit/progresso_linha_test.sh` `teste_observador_acompanha_o_part...` | `sleep 0.8` com amostragem de 0,25 s: dependente de tempo sob carga | Passo 4 (anti-flaky) | Esperar condicao (laco ate a linha `50%` aparecer, com teto) em vez de sleep fixo |
| 8 | Menor | `tests/integracao/progresso_arquivo_test.sh` (cabecalho, `upload_em_sessao`) | Cabecalho lista TCs que o arquivo nao tem (02, 06...) mas omite tags de 16/17/19/20; `-ge 4` linhas nao verifica monotonicidade do percentual | rastreabilidade | Etiquetar os casos por TC e asserir percentual nao decrescente |

Contagem: 0 bloqueantes, **5 maiores** (acima do limite de 3), 3 menores. Nenhum reincidente (primeira rodada).

## 9. Veredito

**Reprovado.**

- Sem bloqueante, mas 5 achados maiores superam o limite de 3 do Passo 6. Dois deles tem prova direta por mutacao sobrevivente (M1, M4) e um e gatilho da Regra 6 sem cenario (TC-PRG-28).
- Pontos fortes: formato e regras puras da linha bem cobertos por literais independentes; M2 e M3 mortas; stdout/estado/cache comparados entre N=1, N=3 e com/sem progresso; parada no primeiro erro confirmada.
- Retorno ao Senior Developer: corrigir achados 1 a 4 (e 5 por consequencia), reexecutar a selecao e reenviar as mutacoes M1 e M4 como prova de red. Achados 6 a 8 sao recomendacao.

## Ciclo 2 (reavaliacao apos tres ciclos de correcao do developer)

Execucao minha, em copia descartavel (com `GIT_DIR` apontando ao repositorio para o caso TC-PRG-35, que usa `git archive a39a89e`), um teste por vez, copia removida ao fim:

| Execucao | Resultado |
|---|---|
| `progresso_` sem mutacao | 48 aprovados (30 + 18), 0 reprovados |
| `retomada_download` sem mutacao | 28 aprovados, 0 reprovados |
| M1 (sem `dbx_progress_arquivo_falhar` em `commands/download.sh`) | **MORTA**: `# FALHA: RF-146: a linha termina em falhou` (`download_com_falha_do_servidor_termina_em_falhou_sem_cem`) |
| M4 (sem `dbx_progress_arquivo_avancar "$inicio"` em `lib/cmd.sh`) | **MORTA** em `retomada_download_test.sh`: `# FALHA: DIV-294: a primeira linha mostra o que o .part ja tem` (4 aprovados, 1 reprovado). Em `progresso_` fica verde, o que e esperado: o caso mora em `retomada_download` |
| M2 (sem avanco por parte em `lib/transfer.sh`) | MORTA: `# FALHA: TC-PRG-13: uma linha por parte` |
| M3 (`falhar` forja 100%) | MORTA: `# FALHA: TC-PRG-32 / RF-146(b)` |

Nota de metodo: numa primeira tentativa, sem `.git` na copia, o TC-PRG-35 reprovou por "nao foi possivel extrair a base" e mascarou M2 e M4; descartei essa rodada e refiz com `GIT_DIR`. O TC-PRG-35 depende do repositorio e do commit `a39a89e` existirem; isso e uma dependencia de ambiente do teste (ver achado 9).

### Status por achado

| # | Status | Verificacao |
|---|---|---|
| 1 | **Corrigido** | M1 morre no teste novo |
| 2 | **Corrigido** | M4 morre em `retomada_download`; o defeito real achado (primeira linha em 0% antes do avanco, `adiar` em `lib/progress.sh:339` e `commands/download.sh:305`) e resultado de teste que nao era caracterizacao |
| 3 | **Corrigido em parte, aceito como ressalva** | Existem agora casos para TC-PRG-07 (`:606-611`), 09 (`:623-625`), 28 (`:535-539`), 33 (`:552-555`), 35 (`:580`). Seguem sem caso proprio 05, 18, 24, 26 e 36. 05 (0% antes da primeira requisicao) e 18 (so o principal escreve em fd 2) sao as que tocam o contrato de RF-135/RF-141; 36 e documentacao; 24 e 26 sao cobertas por equivalencia (sync e igualdade de estado do caso paralelo) |
| 4 | **Corrigido** | Downloads de 8 MiB com `.part` crescente, 100% so no fim, hash divergente sem 100%, sem orfaos (declarado e confirmado verde em `progresso_`, 48/48); o observador e exercitado por `bin/dbx` |
| 5 | **Justificado** | Red literal agora registrado para os testes dos ciclos 2 e 3; casos de caracterizacao declarados como tal. A prova de red por mutacao fecha M1 a M4. Os casos da etapa 1 continuam sem red retroativo, desvio declarado e nao reincidente |
| 6 | **Corrigido (declarado)** | Menores 6, 7 e 8 feitos pelo developer; nao reverifiquei linha a linha, nenhum causou falha |
| 7, 8 | idem 6 | idem |
| 9 (novo, Menor) | Aberto | TC-PRG-35 usa `git archive a39a89e`: reprova fora de um clone com o commit (ex.: copia sem `.git`, CI com checkout raso). Correcao: pular com mensagem explicita quando o commit nao existir, ou fixar a base por fixture de saida (arquivo de referencia versionado) |

### Contagem e veredito

0 bloqueantes, 0 maiores abertos (3 fechado; as lacunas residuais de 05, 18, 24, 26 e 36 ficam como ressalva com owner Senior Developer/QA, prazo antes da PR), 1 menor novo. As quatro mutacoes sao mortas.

**Veredito: Aprovado com ressalvas.** Ressalvas: (a) casos proprios de TC-PRG-05 e 18 (QA pode detalhar), 24, 26 e 36 antes da PR; (b) achado 9; (c) suite completa local e pipeline, pendentes por Regra 8.
