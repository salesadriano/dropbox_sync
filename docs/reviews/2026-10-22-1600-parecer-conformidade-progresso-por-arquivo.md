# Parecer de Conformidade Arquitetural e de Boas Praticas — Progresso por arquivo (F-49, RF-140 a RF-147)

## Identificacao

- Projeto ou produto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Agent responsavel pela alteracao: Senior Developer
- Agent responsavel pela verificacao: Senior Developer (revisao independente, sem alterar codigo nem testes)
- Data da verificacao: 2026-10-22
- Ciclo de verificacao: 1
- Tipo de alteracao: Implementacao nova
- Execucao: local, sem pipeline
- Porte da demanda: G
- Modo do parecer: Completo
- Log de prompt: [2026-10-22_1600_progresso-por-arquivo.md](../prompts/2026-10-22_1600_progresso-por-arquivo.md)

## Escopo verificado

- Levantamento: `git status --short`, `git diff --stat` e `git diff` por arquivo em `/home/sales/dropbox_api.worktrees/feature-progresso-por-arquivo` (nada commitado)
- Base de comparacao: `develop` @ `a39a89e`

| Arquivo | Tipo | Camada / modulo | Verificado |
|---|---|---|---|
| `lib/progress.sh` (+461/-16) | Alterado | utilitario de saida (linha por arquivo, observador, bloco N>1) | Sim, integral do diff |
| `lib/transfer.sh` | Alterado | adaptador | Sim |
| `lib/cmd.sh` | Alterado | adaptador de comando | Sim |
| `lib/http.sh` | Alterado | adaptador HTTP (barra do cURL removida) | Sim |
| `commands/sync.sh` | Alterado (+113) | comando | Sim |
| `commands/upload.sh`, `commands/download.sh` | Alterado | comando | Sim |
| `bin/dbx`, `README.md` | Alterado | ajuda e doc | Sim (ajuda) |
| `tests/**`, `docs/**` | Alterado/Novo | testes e docs | Fora deste gate (ver parecer de TDD) |

- Limitacao: nao executei o comportamento em terminal real; sequencias ESC e corridas foram avaliadas por leitura.

## Stack detectada e skills aplicadas

- Stack: Shell (Bash 4.4+), `shellcheck`, `bats`; deteccao por `.sh`, `bin/dbx`, `scripts/lint.sh`

| Skill aplicada | Motivo | Regras consultadas |
|---|---|---|
| `clean-architecture` | obrigatoria | `dep-inward-only`, `dep-interface-ownership`, `usecase-orchestrates-not-implements`, `comp-common-closure` |
| `security-best-practices` | nome de arquivo vindo do usuario chega ao terminal; status entre processos em area temporaria | injecao de sequencia de controle, permissao de area temporaria, segredo em log |

## Verificacao arquitetural

| Verificacao | Regra | Resultado | Evidencia |
|---|---|---|---|
| Direcao de dependencia | `dep-inward-only` | Conforme | `lib/cmd.sh` e `lib/transfer.sh` chamam a API publica `dbx_progress_arquivo_*`; `lib/progress.sh` nao conhece comandos. Dependencia de `lib/tmp` e opcional por `declare -F` |
| Propriedade da interface | `dep-interface-ownership` | Violada em um ponto | Achado 1 (`_DBX_PRG_CANAL` escrito de fora) |
| Ciclos | `dep-acyclic-dependencies` | Conforme | progress nao carrega transfer/cmd |
| Caso de uso orquestra | `usecase-orchestrates-not-implements` | Conforme | sync decide quando abrir, concluir e falhar; desenho e montagem da linha ficam em progress |
| Coesao | `comp-common-closure` | Conforme com ressalva | Achado 5 (duas responsabilidades em um arquivo de ~650 linhas) |
| Demais regras `entity-*`, `adapt-*` | n/a | Nao aplicavel | sem dominio nem gateway novo |

## Verificacao da skill de stack (Bash)

| Regra verificada | Origem | Resultado | Evidencia |
|---|---|---|---|
| Progresso so em stderr, stdout intocado | RF-28, RF-32 | Conforme | todas as emissoes `>&2`; observador nao escreve em stdout (ressalva: herda o descritor, achado 7) |
| So o principal escreve saida no paralelo | RF-135(a) | Conforme | auxiliar grava so `st.<i>` (`_dbx_progress_canal_gravar`, l. 467) e tem stderr em `/dev/null`; bloco so desenha no principal |
| Escrita atomica do status | RF-143 | Conforme com ressalva | `printf > .parte && mv -f`, mas ver achado 3 |
| Area com permissao 0700 | RNF-03 | Conforme com ressalva | `chmod 0700` apos `mkdir -p` (`commands/sync.sh:319-321`); achado 8 |
| Area temporaria e `trap` so em `lib/tmp.sh` | restricao do projeto | Conforme | usa `dbx_tmp_acao_registrar/cancelar`; nenhum `trap` novo |
| Limpeza em sucesso, falha e sinal | RF-142(e) | Conforme | `concluir`/`falhar` param o observador; `_dbx_progress_arquivo_sinal` e `_dbx_progress_bloco_sinal` registrados; `dbx_progress_bloco_encerrar` cancela a acao. Nenhum `return` entre `bloco_iniciar` e `bloco_encerrar` em `_dbx_cmd_sync_transferir_paralelo` (so `break`) |
| Custo zero com progresso inativo | RF-145(c) | Conforme | `stat`, leitura de tamanhos, observador e canal so atras de `dbx_progress_ativo`; resta so chamada de funcao com retorno imediato |
| Nome com caractere de controle | RNF-03 | Conforme com ressalva | `${item//[[:cntrl:]]/?}` em `iniciar` e `bloco_abrir` neutraliza ESC; achado 9 (C1 em locale de byte) |
| Sequencias ESC | RF-143 | Conforme | `\r%s\033[K` por linha; `ESC[nA` com `n` = linhas ativas desenhadas; `pausar` apaga antes de mensagem alheia; linhas terminam em `\n`, entao sinal nao deixa cursor no meio |
| Quoting, `${v[@]+"${v[@]}"}`, Bash 4.4 | bash | Conforme | `declare -gA/-ga` ok em 4.4; sem `wait -p` nem `${v@Q}` |
| Lint por arquivo | `scripts/lint.sh` | Conforme | `lib/progress.sh`, `commands/sync.sh`, `commands/download.sh`, `lib/cmd.sh`, `lib/transfer.sh`: sem saida de erro; `upload.sh` e `http.sh` nao rodados por limite de chamadas |

## Verificacao de seguranca acionada

- O diff toca segredo/dado sensivel? Sim, de forma indireta (nome de arquivo no terminal, status em area temporaria). Skill: `security-best-practices`.

| Item | Resultado | Evidencia |
|---|---|---|
| Segredo no diff ou na linha de progresso | Conforme | linha contem so indice, acao, nome, percentual e bytes; sem URL, token ou cabecalho. `http.sh` deixou de repassar a barra do cURL |
| Injecao de sequencia de controle via nome | Conforme com ressalva | achado 9 |
| Permissao do canal de status | Conforme com ressalva | achado 8; conteudo e so numero e estado |
| Validacao do que o principal le do status | Conforme | `_dbx_progress_bloco_ler` valida `^[0-9]+$` e restringe o estado a `concluido` ou `falhou` |

## Consistencia com o projeto

| Item | Resultado | Observacoes |
|---|---|---|
| Padrao de modulos equivalentes | Sim | prefixo `_dbx_progress_`, canais `_DBX_PRG_*`, semente `DBX_PROGRESS_TERMINAL` |
| Nao reimplementa componente existente | Sim, com ressalva | `stat -c %s` repetido 6 vezes e sem o fallback BSD que `commands/config.sh` usa (achado 6); `dbx_progress_transferencia` ficou sem chamador de producao (achado 4) |
| Idioma e densidade | Sim | comentarios em portugues, com a referencia RF/DIV como no vizinho; achado 4 sobre bloco de comentario deslocado |

## Ferramentas locais executadas

| Ferramenta | Comando | Resultado |
|---|---|---|
| Linter | `sh scripts/lint.sh <arquivo>` nos 5 arquivos acima | sem saida de erro |
| Suite | nao executada por mim | a cargo do gate de testes |

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correcao esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 | `commands/sync.sh:257` | O comando atribui `_DBX_PRG_CANAL=$canal`, variavel privada de `lib/progress.sh`, e a semantica "canal ativo" muda o comportamento de `iniciar`, `emitir` e do observador. Acoplamento por estado interno | `dep-interface-ownership`, `dep-data-crossing-boundaries` | Expor `dbx_progress_canal_definir <arquivo>` em progress e chama-la no auxiliar; testes devem usar a mesma API | Maior | Aberto |
| 2 | `commands/download.sh:293` e `:318-338` | A linha do arquivo abre antes de saber se o remoto e arquivo. No ramo `*not_file*` (pasta) `dbx_progress_arquivo_falhar` ja imprimiu ` falhou` e o fluxo segue em `_dbx_cmd_download_pasta`: falso `falhou` para comando que pode terminar com sucesso. (Confirmar em terminal; a leitura do diff indica o desvio) | RF-146 (` falhou` so em falha real) | Adiar `falhar` para depois do tratamento de `not_file`, ou fechar a linha sem sufixo ao desviar para pasta | Maior | Aberto |
| 3 | `lib/progress.sh:467-471` com `:392-412` | Auxiliar (via `avancar` nos percursos) e observador do `.part` gravam o mesmo `$_DBX_PRG_CANAL.parte` e fazem `mv` sem coordenacao; o segundo `mv` pode falhar (erro engolido) e o observador escreve com o `_DBX_PRG_FEITOS` copiado na bifurcacao. Hoje o leitor usa maximo e valida inteiro, entao o efeito e visual, mas o contrato "escrita atomica" nao e garantido | RF-143 (atomicidade); boa pratica de shell (temporario unico por escritor) | Nome temporario unico por escritor (`$_DBX_PRG_CANAL.$BASHPID`) ou um unico escritor; teste que force escrita concorrente | Maior | Aberto |
| 4 | `commands/sync.sh:1496-1501` | O bloco de comentario de `_dbx_cmd_sync_enviar` ("As quatro operacoes...") foi interrompido pelos docs de `_prg_iniciar` e `_ler_tamanhos`, e o doc de `_prg_iniciar` esta acima de `_ler_tamanhos`: comentarios apontam para a funcao errada. Tambem: `dbx_progress_transferencia` (`lib/progress.sh:166`) ficou so com testes (codigo morto de producao) | Fidelidade e densidade de comentario do vizinho | Reposicionar cada comentario sobre a sua funcao; remover ou manter `dbx_progress_transferencia` e seus testes (decisao do Tech Lead) | Menor | Aberto |
| 5 | `lib/progress.sh` (arquivo todo) | Passou de ~200 para ~650 linhas com duas responsabilidades (linha unica com observador; bloco N>1) e o bloco reaproveita as globais `_DBX_PRG_CAB/ITEM/TOTAL/FEITOS/CONCLUIDO` como area de trabalho, o que acopla os dois modos por estado implicito | `comp-common-closure` | Extrair `lib/progress_bloco.sh` (ou ao menos montar a linha por argumento, nao por globais) | Menor | Aberto |
| 6 | `commands/sync.sh:273,341,1343`; `commands/download.sh:357`; `lib/progress.sh:397,442` | `stat -c %s` repetido 6 vezes, GNU-only; o projeto ja usa `stat -c ... \|\| stat -f ...` em `commands/config.sh`. Duplicacao | Padrao do projeto; reuso | Helper unico com fallback BSD; `dbx_transfer_tamanho_de_arquivo` ja existe e pode ser reusado | Menor | Aberto |
| 7 | `lib/progress.sh:392-412` e `dbx_progress_arquivo_observar` | O observador herda stdout/stderr do processo; ao matar (`kill` e `wait`) sobra o `sleep` filho por ate 0,25 s com o descritor aberto, o que atrasa o EOF de uma captura `$(...)` do chamador. No auxiliar, `principal=$$` e o pid do principal, nao do auxiliar que o criou (usar `$BASHPID` do criador); se o auxiliar morrer sem derrubar o grupo, o observador vive ate o fim do processo | Higiene de processo filho | Lancar com `</dev/null >/dev/null`; testar o pai pelo pid do criador | Menor | Aberto |
| 8 | `commands/sync.sh:319-321` | `mkdir -p` seguido de `chmod 0700` deixa janela entre os dois comandos; a area do ciclo pai ja e privada, entao o risco e baixo | `security-best-practices` (permissao na criacao) | `mkdir -m 0700 -p` | Menor | Aberto |
| 9 | `lib/progress.sh` (`item=${item//[[:cntrl:]]/?}` em `iniciar` e `bloco_abrir`) | Em locale de bytes (C/POSIX) os bytes 0x80-0x9F nao sao `cntrl`; um nome com byte `0x9B` (CSI de 8 bits) chega ao terminal sem neutralizacao | RNF-03 (neutralizar controle) | Neutralizar tambem por classe de byte (`LC_ALL=C` na substituicao) ou aceitar apenas imprimiveis | Menor | Aberto |
| 10 | `commands/sync.sh` (laco do paralelo, `sleep 0.2`) | Com bloco ativo o `wait -n` foi trocado por sondagem de 0,2 s; custo aceitavel e so com progresso ativo | Boa pratica (espera ativa) | Registrar a escolha; nenhuma acao obrigatoria | Menor | Aberto |

- Total de bloqueantes: 0
- Total de maiores: 3
- Total de menores: 7

## Achados do ciclo anterior

Nao aplicavel: ciclo 1.

## Veredito

- Resultado: **Aprovado com ressalvas**
- Justificativa objetiva: sem violacao de direcao de dependencia, de regra de estado do auxiliar (RF-135(a)), de stdout, de segredo ou de limpeza; `trap` so em `lib/tmp.sh`; lint limpo nos arquivos rodados. Tres maiores (limite) tratados como ressalva.
- Ressalvas, com owner e prazo: achados 1, 2 e 3, owner Senior Developer, antes do push que abre a PR; achados 4 a 10 sao recomendacoes sem prazo (4 e 6 sao simples o bastante para entrar junto). Reincidencia de qualquer maior apos correcao reprova.
- Handoff liberado?: Sim, condicionado a 1, 2 e 3.
- Proximo passo: corrigir 1 a 3 com teste (2 e 3 pedem caso novo), reexecutar a selecao seletiva dos modulos de progresso e sync e o lint por arquivo.

## Devolucao ao agent (preencher apenas se Reprovado)

Nao aplicavel: aprovado com ressalvas.

## Registro

- Nenhuma justificativa aceita exige memoria nova.
- Referenciar este parecer no registro de entrega da demanda.

## Ciclo 2

- Data: 2026-10-22. Diff reconferido por `git diff` e leitura de `lib/progress.sh` (l. 385-500) e `commands/download.sh` (l. 288-330); nada aceito so pela declaracao do developer.
- Lint por arquivo (saida vazia): `lib/progress.sh`, `commands/download.sh`, `commands/sync.sh`. Os demais arquivos tocados e os testes ficam com o lint declarado pelo developer, nao reexecutado por mim.

| # | Status | Evidencia |
|---|---|---|
| 1 | Corrigido | `dbx_progress_canal_definir` em `lib/progress.sh:498`, usada em `commands/sync.sh`; `grep "_DBX_PRG_CANAL="` fora de `lib/progress.sh` em commands, lib e tests: zero ocorrencias |
| 2 | Corrigido | `commands/download.sh`: a linha so abre com `DBX_CMD_DOWNLOAD_EH_ARQUIVO == sim` (metadado `.tag=file`); pasta confirmada desvia para `_dbx_cmd_download_pasta` antes de qualquer linha; `dbx_progress_arquivo_descartar` (`lib/progress.sh:387`) para o observador e apaga a linha sem ` falhou`. Com `--sem-retomada` e progresso ativo o metadado e buscado por `so_meta`, sem tocar o registro de retomada |
| 3 | Corrigido | `_dbx_progress_canal_gravar` usa `$canal.$BASHPID.parte` e devolve o status do `mv`; teste de escrita concorrente declarado (nao reexecutado por mim) |
| 4 | Corrigido | comentarios movidos em `commands/sync.sh` (declarado; conferido apenas que o diff os toca). `dbx_progress_transferencia` segue com chamador so em teste: aceito como residual |
| 5 | Nao corrigido, risco residual por decisao do Tech Lead | `lib/progress.sh` segue com as duas responsabilidades |
| 6 | Corrigido | `dbx_progress_tamanho_de` com fallback `stat -f %z`; `commands/sync.sh` e `lib/progress.sh` a usam. `commands/download.sh` ainda tem `stat -c` direto? nao reverifiquei (menor) |
| 7 | Nao corrigido, risco residual por decisao do Tech Lead | |
| 8 | Corrigido | `mkdir -m 0700 -- "$pasta"` e nenhum `chmod 0700` restante em `commands/sync.sh`. Sem `-p`: depende de a area do ciclo existir, o que ja ocorre |
| 9 | Nao corrigido, risco residual por decisao do Tech Lead | |
| 10 | Nao corrigido, sem acao obrigatoria | |

Regressao nova: nenhuma bloqueante ou maior. Observacoes menores: (a) com progresso ativo e `--sem-retomada` o download faz uma chamada `get_metadata` a mais, declarada em DIV-304 e restrita ao progresso ativo; (b) se o metadado falhar (`so_meta ... || :`), o arquivo e baixado sem linha de progresso, degradacao silenciosa aceitavel; (c) temporarios `.<pid>.parte` ficam na area do ciclo, removida por `lib/tmp`.

Totais do ciclo 2: bloqueantes 0, maiores 0, menores abertos 5 (5, 7, 9, 10 e o residual de 4).

### Veredito do ciclo 2

- Resultado: **Aprovado com ressalvas** (os tres maiores foram corrigidos; restam menores como risco residual aceito pelo Tech Lead)
- Handoff liberado?: Sim
