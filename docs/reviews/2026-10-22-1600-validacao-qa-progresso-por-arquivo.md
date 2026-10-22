# Validacao independente do QA: fase 10, progresso por arquivo (F-49, RF-140 a RF-147)

Porte G. Papel: QA Expert. Suite nova: `tests/integracao/qa_progresso_arquivo_b10_test.sh`
(sha256 `fab96fad4e4aa1c67b3905c728b7004870031975618c030cba7987fc10ff5956`). Executavel real `bin/dbx`,
duplo de `curl` proprio (rotas de lote delegadas a `tests/support/lote_duplo.sh`, sem alteracao), sem rede e
sem conta real. Casos escritos pelo pedido e pela secao 5.19, sem reutilizar os testes do developer.

## Escopo

DIV-302 (cache igual entre N=1 e N=3), DIV-303 (amostragem sem terminal com N>1, arquivo de 1 MiB ou mais,
`.part` que cresce), stdout byte a byte (RF-145(a)), nome hostil (RF-144), falha do metadado (RF-146, DIV-304),
percentual que nunca diminui e 100% so ao concluir (RF-140(f)(g)).

## Casos (8) e resultado

| Caso | Requisito | Resultado |
|---|---|---|
| qpa01 `sync --receber` N=1 e N=3 com progresso e N=3 sem progresso: cache normalizado (cabecalho conta/origem/destino) igual | DIV-302, RF-139 | aprovado (limitacao: ver QA-B10-03) |
| qpa02 `sync --enviar` de 3 arquivos (mtime antigo): os 3 registros `hash nome` do cache iguais entre N=1 e N=3 | DIV-302 | aprovado |
| qpa03 N=3, 3 arquivos de 8 MiB, `.part` cresce 1 MiB/0,3 s, sem terminal: por arquivo >= 4 linhas, percentual nao decresce, no maximo 1 linha por decil, 100 uma unica vez e por ultimo, toda linha com o `[i/3]` do arquivo, sem `\r` nem ESC, nada resta no tmp | DIV-303, RF-143, RF-140(f)(g) | aprovado |
| qpa04 `upload -` (stdin) com `--json`: stdout identico byte a byte com e sem `--progresso` | RF-145(a) | aprovado |
| qpa05 `download` para arquivo com `--json`: stdout identico (caminho normalizado) e arquivo baixado identico | RF-145(a) | aprovado |
| qpa06 nome com ESC, BEL e quebra de linha: a linha de progresso (sem e com terminal) traz `?` no lugar, uma linha so, sem linha forjada | RF-144 | aprovado |
| qpa07 `get_metadata` recusado (400): codigo e stdout iguais ao sem progresso, nenhuma linha de arquivo, nenhum `falhou`, stderr igual salvo a mensagem `[download]` ja existente | RF-146, DIV-304 | aprovado |
| qpa08 download N=1 de 6 MiB com terminal: amostras nao decrescem, 100% uma unica vez e por ultimo, sem processo orfao | RF-140(f)(g) | aprovado |

## Comandos e contagens literais

| Comando | Resultado |
|---|---|
| `bash tests/run.sh qa_progresso_arquivo_b10 < /dev/null` | aprovados 8, reprovados 0, pulados 0 |
| `bash tests/run.sh progresso_ < /dev/null` (3 arquivos: `progress_test`, `progresso_arquivo_test`, `qa_progresso_arquivo_b10`, mais `progresso_linha`) | aprovados 61, reprovados 0, pulados 0 |
| `bash tests/run.sh qa_desempenho < /dev/null` | aprovados 15, reprovados 0, pulados 0 |
| `bash tests/run.sh harness < /dev/null` | aprovados 22, reprovados 0, pulados 0 |
| `bash tests/run.sh json < /dev/null` | aprovados 41, **reprovados 1** (caso 42, ver QA-B10-02); 20 casos nao executados pela parada no primeiro erro |
| `sh scripts/lint.sh tests/integracao/qa_progresso_arquivo_b10_test.sh` | sem avisos |
| `grep -c '[$](printf' tests/integracao/qa_progresso_arquivo_b10_test.sh` | 0 (a regra do caso 42 nao acusa a suite do QA) |

A suite do QA reprovou 4 vezes durante a escrita por defeito dos MEUS casos (hash invalido no duplo, lote de
pequenos sem o duplo de lote, `/` no nome, `[download]` esperado como erro); os 3 ajustes de premissa nao
afrouxaram asserção do produto. A 1a versao tinha `$(printf` em 17 linhas; troquei por here-string antes do sha.

## Achados

| ID | Severidade | Onde | Cenario | Descricao |
|---|---|---|---|---|
| QA-B10-01 | Menor (pre-existente, fora do diff) | `commands/sync.sh`, mensagens `[sync] analisando local (i/N): <nome>` e `[sync] analise [i/N]: <nome>` | qpa06 | Com `--progresso`, essas mensagens ecoam o nome do arquivo cru: ESC, BEL e quebra de linha chegam ao stderr (observado: `analise [1/1]: a<ESC>[31mBC` seguido de linha `FAKE [9-9] enviando: x.txt`). O RF-144 cobre so a linha de progresso do arquivo, que esta correta; o nome hostil forja uma linha parecida com a de progresso na etapa de analise. Recomendacao: aplicar a mesma troca de controles por `?` nessas mensagens; nao bloqueia esta demanda. |
| QA-B10-02 | Maior (processo, fora da minha suite) | `tests/unit/progresso_linha_test.sh:112,149`; `tests/integracao/progresso_arquivo_test.sh` (3 linhas com `$(printf`) | `tests/run.sh json` caso 42 | A auditoria `massa_adversarial_nao_e_construida_por_substituicao_de_comando` reprova com os arquivos do developer. Como a suite para no primeiro erro, a auditoria `json` nao fica verde e a pipeline vai quebrar. Devolver ao Senior Developer: trocar `$(printf ...)` por `printf -v`, `$'...'` ou here-string e reexecutar `json`. Nao editei os arquivos dele (pedido do Tech Lead). |
| QA-B10-03 | Menor (limitacao de cobertura) | `lib/state.sh:88` (anti-corrida de 2 s) | qpa01 | O arquivo recem-baixado nao entra na memoria do `sync --receber`; a igualdade de conteudo com registros (`hash nome`) so e provada no envio (qpa02). No recebimento a igualdade vale para o cabecalho da memoria. Aceito como risco residual baixo: o caminho que grava a memoria e o mesmo em N=1 e N>1. |

Nenhuma divergencia de comportamento do produto contra a secao 5.19 foi encontrada nos cenarios acima. DIV-302 e DIV-303
ficam provadas por teste. Nao cobri, por limite de orcamento de chamadas: INT com N=3 (ja coberto pelo developer em
`teste_int_com_n3_fecha_o_bloco_e_nao_deixa_orfaos`), arquivo de status ausente com progresso inativo (coberto pelo
developer, `teste_paralelo_canal_de_status_so_com_progresso_ativo...`), e o hash dos arquivos de teste reais do
`json` fora do caso 42 (nao executado).

## Veredito

**Aprovado com ressalvas.** Produto: sem defeito bloqueante nem maior; 8 de 8 casos do QA aprovados e as suites
vizinhas verdes. Ressalva Maior: QA-B10-02 (auditoria `json` vermelha por testes do developer) precisa ser
corrigida antes do push para a PR; QA-B10-01 e QA-B10-03 sao Menores, com recomendacao. A suite do QA aguarda
o aceite explicito do solicitante sobre o sha acima (regra 12/13), a registrar pelo Tech Lead.
