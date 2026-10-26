# Parecer de conformidade — suporte a FreeBSD

| Campo | Valor |
|---|---|
| Demanda | `suporte-freebsd` (porte G) |
| Registro de entrega | [2026-10-24-1153-registro-suporte-freebsd.md](2026-10-24-1153-registro-suporte-freebsd.md) |
| Diff avaliado | `origin/develop...HEAD` em `lib`, `commands`, `bin`, `install.sh`, `uninstall.sh`, `README.md`, `tests` |
| Revisor | agent de revisao independente (nao participou da implementacao), sob `ai-team:protocolo-conformidade` |
| Skills | `clean-architecture`, `shellcheck-configuration`, `bats-testing-patterns` |

## Ciclo 1 (branch @ `ff2b851`) — Aprovado com ressalvas

| # | Severidade | Local | Achado | Status no ciclo 2 |
|---|---|---|---|---|
| 1 | Importante | `lib/preflight.sh` `dbx_preflight_descritores` | So `[[ -f /dev/fd/N ]]`: um bash com emulacao de `/dev/fd` aprovava host sem `fdescfs`, enquanto o produto le `/dev/fd/N` pelo `stat -L` externo (falha fechada depois, com mensagem enganosa) | Corrigido: exige tambem `stat -L` externo com o mesmo `dev:ino` do arquivo aberto |
| 2 | Menor | `lib/atributos.sh` (`%Lp`) e chamadores de modo | O BSD descartava suid/sgid/sticky; regra de modo nao identica nos dois sistemas; duble mascarava | Corrigido: `%Mp%Lp` normalizado (ver N1) |
| 3 | Menor | `lib/atributos.sh` | Forma do `stat` inferida pela falha no alvo; arquivo ausente no GNU disparava `stat -f` a toa | Corrigido: sonda unica sobre o proprio modulo |
| 4 | Menor | testes | RF-167(d) sem teste de contagem de chamadas | Corrigido: `forma_aprendida_por_sonda_unica_uma_leitura_uma_chamada` |
| 5 | Menor | `lib/atributos.sh` identidade BSD | Nanossegundos fixados em zero; `%.9Fm` talvez disponivel | Justificado: conferencia no roteiro do FreeBSD real (secao 7) |
| 6 | Menor | `lib/progress.sh`, `lib/walk.sh`, `lib/sync.sh`, `commands/diagnostico.sh`, `tests/support/freebsd.sh` | Comentarios desatualizados; `progress.sh` sem `cd -P` | Corrigido |
| 7 | Menor | `lib/config.sh`, `lib/state.sh`, `lib/cmd.sh`, `lib/transfer.sh`, `lib/walk.sh` | `atributos.sh` carregado so de forma transitiva por `lib/hash.sh` | Justificado: observacao aceita pelo Tech Lead (modulo sem dependencias, carregado antes de qualquer uso) |
| 8 | Menor | `tests/unit/preflight_test.sh` | Guarda de deteccao nao cobria `BASH_VERSINFO[5]` | Corrigido, com mutacao propria |

Verificado no ciclo 1: nenhum chamador migrado passou de "recusa" para "aceita" (credencial, barreira de inode do `.part`, trava, cursor, `host_id`); poda com `-ot` filtra nao regulares e ligacoes simbolicas; nenhum `stat -c/-f`, `chmod <modo> --`, `-printf` (fora de `bin/dbx:35`) nem `uname/OSTYPE/MACHTYPE` no runtime; lint limpo.

## Ciclo 2 (branch @ `de4b66f`) — Aprovado com ressalvas

| # | Severidade | Local | Achado | Status |
|---|---|---|---|---|
| N1 | Menor | `lib/atributos.sh`, duble `stat` | O `%Lp` do FreeBSD sai sem zeros a esquerda: 4044 viraria 444 (efeito no modo preservado do alvo) | Corrigido: `%Mp%03Lp`; duble imita o BSD real; caso 4044 no teste; conferencia no roteiro |
| N2 | Menor | `lib/preflight.sh` | Segunda leitura da sonda sem `-L`: com `lib/` instalado por ligacao simbolica o preflight recusaria sempre | Corrigido: `dbx_atributo -L dev_ino` |
| N3 | Observacao | `lib/atributos.sh` | Forma aprendida dentro de `$(...)` nao volta ao pai: uma sonda a mais por subshell | Aceito: custo, nao erro |

Verificado no ciclo 2: com a sonda falhando, todo chamador falha fechado e nao ha aprendizado errado; o `stat` filho herda o descritor aberto pelo `exec`.

## Escopo posterior ao ciclo 2

Commits feitos apos `de4b66f`, avaliados no ciclo 3:

| Commit | Tema | Requisito |
|---|---|---|
| `2d7ca4a`, `b797ae8` | Conferencia dos arquivos abertos pelo proprio descritor, sem `/dev/fd` (DIV-352 superada) | RF-171(a), RF-172(a) |
| `cae6e36` | `qa_b2_01` aceita as duas travas do sync vencedor (teste da fase 2) | RF-132 |
| `548b2f1`, `f614b02` | Leitura exata de N bytes do descritor, `dbx_ler_exato` com `dd` | RF-173(a) a (d) |
| `5714175` | Download por descritor com `--no-show-error` no lugar de `--stderr` | RF-171(a) emendado |
| `dd55b20` | Nenhuma repeticao de regex acima de 255 (RE_DUP_MAX do FreeBSD) | RF-173(e) |

Os achados do ciclo 2 seguem validos.

### Ciclo 3 (Tech Lead, 2026-10-26)

Leitura do diff de cada commit acima, contra `clean-architecture` e as regras de shell do projeto (ponto unico por capacidade, sem deteccao de plataforma fora de `dbx_preflight_plataforma`, capturas no alfabeto do `json_test`, `stat -c/-f` so em `lib/atributos.sh`, shellcheck por arquivo).

| Commit | Achados | Veredito |
|---|---|---|
| `b797ae8` | Nenhum bloqueante. Atributos de descritor num ponto unico (`dbx_atributo_fd`, `dbx_fd_regular_proprio`); a reabertura por `/dev/fd` vira abertura pelo caminho com conferencia do `dev:ino`. **Defeito latente** no ramo `fd:` de `lib/http.sh` (`--stderr` reabre o stderr), invisivel ao curl duble: achado no FreeBSD real e corrigido em `5714175` | Aprovado (defeito corrigido no ciclo) |
| `cae6e36` | Nenhum. Teste do QA corrigido com o comportamento de RF-132, reaprovado pelo solicitante | Aprovado |
| `f614b02` | Nenhum. `dbx_ler_exato` e o ponto unico de leitura exata; os 4 leitores em partes passam por ele; leitura unica de `lib/state.sh` fica com `head -c` (RF-173(d)) | Aprovado |
| `5714175` | Nenhum. Motivo legivel para falha do cliente sem mensagem; limite do arquivo reaberto continua declarado | Aprovado |
| `dd55b20` | Nenhum. Comprimento testado a parte nos pontos de uso; contrato de tamanho inalterado; auditoria impede regressao | Aprovado |

Ressalva de processo: o ramo `fd:` foi aprovado na T5 so com curl duble. Daqui em diante, mudanca na invocacao do curl leva teste com o curl real (`tests/unit/http_fd_curl_real_test.sh`, `qa_download_curl_real_b16`).

Achado da validacao no FreeBSD real (fora deste parecer, para o registro de entrega): a leitura por `head -c` deixava o descritor alem de N bytes; a correcao esta em `dbx_ler_exato`.

## Veredito final

**Aprovado com ressalvas** no ciclo 2 (sem bloqueante; ressalvas 5, 7 e N3 justificadas; demais corrigidas). **Ciclo 3 (commits posteriores a `de4b66f`): Aprovado**, sem bloqueante, com a ressalva de processo acima.
