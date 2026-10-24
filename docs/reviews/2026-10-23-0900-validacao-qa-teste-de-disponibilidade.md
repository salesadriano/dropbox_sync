# Validacao independente do QA - teste de disponibilidade (F-50, RF-148..155), porte M, ciclo 1

- Worktree: `/home/sales/dropbox_api.worktrees/feature-teste-de-disponibilidade` (branch `feature/teste-de-disponibilidade`, base `develop` @ `877b708`, sem commit).
- Suite: `tests/integracao/qa_disponibilidade_b11_test.sh` (475 linhas, 33 casos), escrita antes de ler o registro de entrega. Reusa so o duplo de curl e o pty de `tests/support/disponibilidade.sh`.
- sha256: `ffe3ef0ea7f4cf69d96465d2960828b30597b9735ec88412ca2231e4a3db96ec`

## Veredito do ciclo 1: REPROVADO

Motivo unico: a auditoria RNF-24 (`bash tests/run.sh json`) esta vermelha por massa montada com `$(printf ...)` em teste do developer (QA-DSP-01). Nenhum defeito de comportamento foi encontrado na funcionalidade: a suite do QA passou integralmente (33/33). Reprovacao so do gate de testes; a correcao e trocar a massa nas duas linhas e rerodar.

## Execucoes

| Comando | Resultado |
|---|---|
| `bash tests/run.sh qa_disponibilidade_b11_test < /dev/null` | 33 casos, 33 aprovados, 0 reprovados, 0 pulados: APROVADA |
| `bash tests/run.sh json < /dev/null` | **REPROVADA**: 41 ok, 1 nao ok, parou no caso 42 (`massa_adversarial_nao_e_construida_por_substituicao_de_comando`), 20 nao executados. Linhas acusadas: `tests/integracao/testar_test.sh:363-364` (arquivo do developer; a suite do QA nao tem `$(printf ...)`) |
| `bash tests/run.sh harness < /dev/null` | 22 casos, 22 aprovados: APROVADA (nenhuma funcao redefinida no arquivo do QA nem em heredoc do duplo) |
| `sh scripts/lint.sh tests/integracao/qa_disponibilidade_b11_test.sh` | rc=0 |

## Casos (todos aprovados)

| Risco | Casos |
|---|---|
| Classificacao e codigos (testar) | sonda com 200/301/403/503 e internet nao falha (aviso, DIV-311); api 503 = 10; api 429 = 8; content 503 so falha `servico_conteudo`; Dropbox inacessivel com internet ok = 9 sem culpar a internet; sonda desligada = 9, zero requisicao, mensagem que nao distingue a causa |
| Classificacao (automatico) | sem internet = 9 e nomeia internet com 1 sonda; Dropbox inacessivel nao culpa a internet; renovacao 503 = 10 com no maximo 1 sonda; falha 503 no meio com terminal nao oferece config e mantem 10 |
| Oferta do config | sem terminal nunca le stdin (bytes de `upload -` intactos) e sai 3; invalid_grant sem terminal sai 5 sem pergunta; respostas '', n, N, y, yes, nao, 0, ' ' recusam sem gravar nada e sem chamar o oauth; recusa com credencial recusada mantem o arquivo byte a byte e sai 5; `--json` recusado deixa stdout vazio; `--dry-run`, permissao 644 e comandos de fora (diagnostico, perfis, completar) nao oferecem; `sim` e `S` aceitam e o comando original roda uma vez |
| Segredos | sentinelas de credencial, senha e token embutidos na URL da sonda ausentes de stdout e stderr em testar, `--debug testar`, `--debug space` e `--json --debug testar` nos caminhos ok, sonda caida e token caido; sonda e servico sem credencial nem `Authorization`; campo vazio nomeado sem valor; URL com aspas e quebra de linha nao injeta diretiva no curl |
| Canal | `--json`/`--null` com e sem `--debug` tem o mesmo stdout (ok e falha); automatico `--json --debug` igual; `--null` sem texto de diagnostico; nenhum temporario em TMPDIR em sucesso, falha e invalid_grant |
| Caminho feliz | `space` faz exatamente 2 requisicoes (renovacao + chamada), stderr vazio; igual com URL da sonda invalida |
| Sync paralelo | `sync --enviar --paralelo 4` com rede caida: 1 sonda; URL invalida: 1 aviso, sem o valor, sem requisicao a sonda, codigo 9; `testar` com URL invalida (`http://`, `ftp://`, `HTTPS://`, `https://`, sem esquema) sai 2 sem requisicao |

## Defeitos

| Id | Prioridade | Local | Cenario reproduzivel | Efeito |
|---|---|---|---|---|
| QA-DSP-01 | P1 (gate vermelho, nao e defeito do produto) | `tests/integracao/testar_test.sh:363-364` | `bash tests/run.sh json < /dev/null`: o caso 42 reprova porque o teste de aviso de URL monta a entrada de `assert_nao_contem` com `"$(printf '%s\n' "$DBX_ERRO" | grep 'sonda GET')"` (RNF-24) | A auditoria interrompe a execucao no 1o erro (Regra 9) e deixa 20 casos do `json` nao executados; a PR nao passa a suite completa. Correcao esperada: usar `$'...'`/`printf -v` ou capturar sem `printf` (ex.: `grep ... <<<"$DBX_ERRO"`). |

## Observacoes (nao sao defeitos; sem reprovacao)

- O remedio de `invalid_grant` sem terminal e a mensagem atual ("autorize de novo"), nao `dbx config --substituir`: esta de acordo com RF-152(a) ("mensagem e remedio de hoje"), mas RF-150(c) pede remedio acionavel; sugestao P2 ao BA, nao bloqueia.
- `help testar` diz "invalida sai com 2" e RF-149(b) fala em desligar com aviso; DIV-310 resolve por A no automatico e B no `testar`, entao o comportamento confere. Recomendo que RF-149(b) cite as duas metades.
- Recomendacoes ja registradas pelo developer (R3, R5a) nao foram reportadas como novas.
- Limite da validacao: o duplo de curl nao prova o comportamento do curl real frente a URL com `"`/quebra de linha; o caso confere so o arquivo de opcoes que o dbx gera.
- Aceite do solicitante para esta suite: pendente (sha256 acima).

## Ciclo 2

**Veredito: APROVADO.** QA-DSP-01 corrigido em `tests/integracao/testar_test.sh:399-400` (`grep 'sonda GET' <<<"$DBX_ERRO"`); reverificado pelo QA.

| Comando | Resultado |
|---|---|
| `bash tests/run.sh json < /dev/null` | 62 aprovados, 0 reprovados: APROVADA |
| `bash tests/run.sh harness < /dev/null` | 22 aprovados, 0 reprovados: APROVADA |
| `bash tests/run.sh qa_disponibilidade_b11_test < /dev/null` | 33 aprovados, 0 reprovados: APROVADA |
| `bash tests/run.sh testar_test < /dev/null` | 29 aprovados, 0 reprovados: APROVADA |
| lint de `testar_test.sh` | rc=0 |

sha256 da suite do QA (inalterada): `ffe3ef0ea7f4cf69d96465d2960828b30597b9735ec88412ca2231e4a3db96ec`.

QA-DSP-01: fechado. As observacoes P2 do ciclo 1 permanecem (remedio de `invalid_grant` sem terminal; RF-149(b) citar as duas metades; limite do duplo de curl). Aceite do solicitante: pendente.
