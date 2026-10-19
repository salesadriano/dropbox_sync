# Robustez de rede P2: limites de rede por ambiente, retomada de envio, saida de falhas e parada da suite

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | Fase 2 da analise externa de melhorias: robustez de rede (politica de erro e retentativa, contrato de saida e configuracao por ambiente). Origem: [analise de melhorias](../sources/2026-10-18-analise-melhorias.md), item P2. |
| Porte | M. Toca politica de erro e retentativa (RNF-07, RF-09), contrato de saida do `download` e do `sync` (RF-59, RF-32(b)) e configuracao por variavel de ambiente (RNF-30). Sem mudanca de arquitetura, sem schema, sem dependencia nova. |
| Log de prompt | [docs/prompts/2026-10-18_2045_robustez-de-rede-p2.md](../prompts/2026-10-18_2045_robustez-de-rede-p2.md) |
| Branch / base | `feature/robustez-de-rede-p2` sobre `develop` @ `38b6148` |
| Agents | Business Analyst (requisitos RNF-30, RF-58, RF-59, RNF-31, RNF-32, F-33, DP-33, RSK-40 e RSK-41; emendas em RF-09, RNF-07 e RF-32(b)); Senior Developer (implementacao, ciclos 1 a 4, sob `protocolo-tdd` e `protocolo-conformidade`); QA Expert (validacao independente, ciclos 1 a 3); Tech Lead (verificacao, conferencia de testes e fechamento). Instancia: `myPCWin/Adriano Sales Santos`. |
| Data | 2026-10-18 |

## 2. Causa ou decisao

Solucao por item, com a abordagem escolhida. Os itens 2 e 3 tiveram tres abordagens comparadas; os demais tinham solucao unica ou evidente.

- **Item 2, retentativas e espera (RNF-07, RF-09).** Escolhida: ajustes lidos e validados a cada requisicao (`dbx_http_validar_ambiente`, publica `DBX_HTTP_EFETIVO`), `Retry-After` lido na mesma passada de cabecalhos, espera pelo `sleep` do sistema chamado por nome. Descartadas: leitura na carga do modulo (valor invalido sem diagnostico limpo) e funcao de espera injetavel (cria superficie de configuracao que a suite exercitaria no lugar do caminho real).
- **Item 3, retomada dentro da execucao (RF-58).** Escolhida: reabrir a origem em novo descritor e descartar `N` bytes em fatias, com resumo pelo arquivo inteiro so quando houve retomada. Descartadas: `dd skip=` e `tail -c +N` (dependencia nova, e `tail` em cano perde o status) e reinicio do zero (viola RF-58(a)).
- **Item 1, RNF-30.** Timeouts e limite de velocidade no arquivo de opcoes `-K -`, que e o unico ponto de opcoes de todos os modos; passar por argv mudaria o contrato do duplo.
- **Item 4, RF-59.** Linha `falha` montada so com canais saneados (classe e prefixo de `error_summary` vindo de JSON); a saida bruta das operacoes continua descartada.
- **Item 5, F-28 (RF-32(b)).** Causa: o canal de fluxo roda o cliente dentro de `codigo=$( ... -o "$destino" ... )`, onde `/dev/stdout` e o cano da captura; o conteudo sai colado ao codigo e a falha vira rede (9). Correcao: `lib/http` duplica o stdout (`exec {fd}>&1`), `download` aceita `-` e emite o registro no stderr em fluxo; truncamento por `>>` recusado.
- **Item 6, RNF-31.** Canal `DBX_HTTP_TRATADOR_EXTERNO` e `dbx_http_sinais_devolver` em `lib/http`, dono da area que os tratadores internos ja limpavam. Sem `lib/tmp` (backlog).
- **Item 7, RNF-32.** Parada por arquivo (`tests/run.sh`) e por caso (`tests/support/harness.sh`, `Bail out!` do TAP 13). Sem opcao de rodar tudo, porque a Regra 9 exige a parada.

Detalhes e trade-offs: [padroes-rede-p2](../../.github/agents/memoria/entradas/2026-10-18-2045-padroes-rede-p2.md) e [detalhes-tecnicos-rede-p2](../../.github/agents/memoria/entradas/2026-10-18-2045-detalhes-tecnicos-rede-p2.md). Requisitos: [escopo, requisitos e criterios de aceite](../requisitos/escopo-requisitos-e-criterios-de-aceite.md), [decisoes pendentes](../requisitos/decisoes-pendentes.md), [funcionalidades candidatas](../requisitos/funcionalidades-candidatas.md), [riscos](../requisitos/riscos-restricoes-e-licenciamento.md) e [System Design](../arquitetura/system-design.md). Mapa de modulos: [mapa-modulos](../testes/mapa-modulos.md).

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| [bin/dbx](../../bin/dbx) | Alterado | +15/-0 |
| [commands/download.sh](../../commands/download.sh) | Alterado | +41/-2 |
| [commands/sync.sh](../../commands/sync.sh) | Alterado | +168/-17 |
| [lib/cmd.sh](../../lib/cmd.sh) | Alterado | +7/-7 |
| [lib/errors.sh](../../lib/errors.sh) | Alterado | +9/-1 |
| [lib/http.sh](../../lib/http.sh) | Alterado | +219/-13 |
| [lib/output.sh](../../lib/output.sh) | Alterado | +27/-1 |
| [lib/transfer.sh](../../lib/transfer.sh) | Alterado | +205/-29 |
| [tests/run.sh](../../tests/run.sh) | Alterado | +24/-0 |
| [tests/support/harness.sh](../../tests/support/harness.sh) | Alterado | +9/-0 |
| [tests/integracao/comandos_test.sh](../../tests/integracao/comandos_test.sh) | Alterado | +116/-0 |
| [tests/integracao/sync_test.sh](../../tests/integracao/sync_test.sh) | Alterado | +209/-0 |
| [tests/unit/errors_test.sh](../../tests/unit/errors_test.sh) | Alterado | +12/-0 |
| [tests/unit/harness_test.sh](../../tests/unit/harness_test.sh) | Alterado | +75/-0 |
| [tests/unit/hash_test.sh](../../tests/unit/hash_test.sh) | Alterado | +11/-5 |
| [tests/unit/http_test.sh](../../tests/unit/http_test.sh) | Alterado | +241/-0 |
| [tests/unit/output_test.sh](../../tests/unit/output_test.sh) | Alterado | +46/-0 |
| [tests/unit/transfer_test.sh](../../tests/unit/transfer_test.sh) | Alterado | +228/-0 |
| [tests/unit/qa_rede_p2_test.sh](../../tests/unit/qa_rede_p2_test.sh) | Novo (QA) | +576/-0 |
| [tests/integracao/qa_robustez_rede_p2_test.sh](../../tests/integracao/qa_robustez_rede_p2_test.sh) | Novo (QA) | +518/-0 |
| [README.md](../../README.md) | Alterado (secao de variaveis de rede) | +20/-0 |
| [docs/README.md](../README.md) | Alterado | +1/-0 |
| [docs/arquitetura/system-design.md](../arquitetura/system-design.md) | Alterado (BA e Tech Lead) | +12/-3 |
| [docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md](../requisitos/escopo-requisitos-e-criterios-de-aceite.md) | Alterado (BA) | +19/-6 |
| [docs/requisitos/decisoes-pendentes.md](../requisitos/decisoes-pendentes.md) | Alterado (BA) | +16/-0 |
| [docs/requisitos/funcionalidades-candidatas.md](../requisitos/funcionalidades-candidatas.md) | Alterado (BA) | +7/-4 |
| [docs/requisitos/riscos-restricoes-e-licenciamento.md](../requisitos/riscos-restricoes-e-licenciamento.md) | Alterado (BA) | +3/-1 |
| [docs/testes/mapa-modulos.md](../testes/mapa-modulos.md) | Novo (QA) | +114/-0 |
| [docs/prompts/2026-10-18_2045_robustez-de-rede-p2.md](../prompts/2026-10-18_2045_robustez-de-rede-p2.md) | Novo (log de prompt) | +31/-0 |
| `.github/agents/memoria/entradas/2026-10-18-2045-*.md` (3 entradas) | Novo (memoria) | +57/-0 |

Total de linhas de codigo (producao e teste, sem documentacao): **2831** (`git diff --numstat 38b6148` sobre `bin`, `commands`, `lib` e `tests`, mais os dois arquivos do QA novos: +2756/-75).

## 4. Testes rodados

Selecao: `lib/errors.sh` no diff seleciona toda a suite pelo mapa de modulos. Comando do ciclo 3 do QA: `bash tests/run.sh` (sem filtro), 23 arquivos executados. Contagem por arquivo a partir do log da execucao; a duracao por arquivo nao consta do log e fica como `n/d`.

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `auth_test` | Selecao total pelo mapa (`lib/errors.sh`) | `bash tests/run.sh` | 35 | 35 | 0 | n/d |
| `cabecalho_test` | Selecao total pelo mapa | `bash tests/run.sh` | 17 | 17 | 0 | n/d |
| `cli_test` | Selecao total pelo mapa | `bash tests/run.sh` | 17 | 17 | 0 | n/d |
| `comandos_test` | `lib/cmd.sh`, `commands/download.sh`, `bin/dbx` | `bash tests/run.sh` | 91 | 91 | 0 | n/d |
| `composicao_test` | Selecao total pelo mapa | `bash tests/run.sh` | 24 | 24 | 0 | n/d |
| `config_test` | Selecao total pelo mapa | `bash tests/run.sh` | 40 | 40 | 0 | n/d |
| `db_test` | Selecao total pelo mapa | `bash tests/run.sh` | 4 | 4 | 0 | n/d |
| `errors_test` | `lib/errors.sh` | `bash tests/run.sh` | 77 | 77 | 0 | n/d |
| `harness_test` | `tests/run.sh`, `tests/support/harness.sh` | `bash tests/run.sh` | 22 | 22 | 0 | n/d |
| `hash_test` | Selecao total pelo mapa (reescrito no ciclo 1) | `bash tests/run.sh` | 40 | 40 | 0 | n/d |
| `hash_vetor_oficial_test` | Selecao total pelo mapa; 2 casos pulados (SKIP, arquivo oficial indisponivel sem `DBX_TESTES_REDE=1`) | `bash tests/run.sh` | 2 | 0 | 0 | n/d |
| `http_test` | `lib/http.sh` | `bash tests/run.sh` | 51 | 51 | 0 | n/d |
| `json_test` | Auditoria estatica de todo `lib/*.sh` (RNF-24) | `bash tests/run.sh` | 60 | 60 | 0 | n/d |
| `output_test` | `lib/output.sh` | `bash tests/run.sh` | 30 | 30 | 0 | n/d |
| `path_test` | Selecao total pelo mapa | `bash tests/run.sh` | 44 | 44 | 0 | n/d |
| `preflight_test` | Auditoria de comandos de `lib/*.sh` | `bash tests/run.sh` | 25 | 25 | 0 | n/d |
| `progress_test` | Selecao total pelo mapa | `bash tests/run.sh` | 16 | 16 | 0 | n/d |
| `qa_integridade_p1_test` | Validacao independente da fase P1 (regressao) | `bash tests/run.sh` | 27 | 27 | 0 | n/d |
| `qa_rede_p2_test` | Validacao independente da fase P2 (25 casos) | `bash tests/run.sh` | 25 | 25 | 0 | n/d |
| `qa_robustez_rede_p2_test` | Validacao independente da fase P2 (20 casos) | `bash tests/run.sh` | 20 | 20 | 0 | n/d |
| `sync_test` | `commands/sync.sh`, `lib/transfer.sh`, `lib/cmd.sh` | `bash tests/run.sh` | 48 | 48 | 0 | n/d |
| `transfer_test` | `lib/transfer.sh` | `bash tests/run.sh` | 36 | 36 | 0 | n/d |
| `walk_test` | Selecao total pelo mapa | `bash tests/run.sh` | 11 | 11 | 0 | n/d |

Resultado da execucao: 23 arquivos, **760 aprovados, 0 reprovados, 2 pulados**, `resultado: APROVADA` (log `qa-ciclo3-selecao.log`, no scratchpad da sessao; a soma de Total e 762, com os 2 pulados).

- Red observado: ciclo 1 do developer, `http_test` 14 de 15 casos novos vermelhos contra o HEAD; `transfer_test` 6 de 8; `sync_test` 8 de 8; `comandos_test` 3 de 4 contra o HEAD, com o caso do `>>` provado por mutacao (T-01); `harness_test` 2 de 3; `hash_test` reescrito e vermelho com ruido no `/tmp`. Ciclos 2 a 4: casos novos com red comprovado nos pareceres; os casos de guarda estao identificados e nao servem de prova de red.
- Parada no primeiro erro (Regra 9): cumprida pelo RNF-32 (F-30 entregue nesta fase). `tests/run.sh` para no primeiro arquivo reprovado e `harness.sh` no primeiro caso (`Bail out!`). A execucao final nao foi interrompida.
- Barreiras estaticas: `shellcheck` dos arquivos alterados em `lib`, `commands`, `bin` e `tests`, saida 0 (modo bash, shellcheck 0.10.0); `shellcheck -x` dos dois arquivos do QA, saida 0.
- Testes de seguranca e acesso (Regra 6), um cenario por linha:
  - Sentinela de token e de corpo ausentes de stdout e stderr do `sync`.
  - `correct_offset` hostil (`abc`, `-1`, tamanho + 1, 20 digitos, `1.5`, `0x10`, quebra de linha, ausente): recusado sem `finish` e sem residuo.
  - Variavel de ambiente de rede invalida nas 7 variaveis: codigo 2, nenhuma chamada de rede, diagnostico com variavel e valor, inclusive no `bin/dbx` antes da renovacao do token.
  - Caminho com quebra de linha que imita `falha`: uma linha `falha`, nenhuma forjada.
  - Token `sl.u.` e refresh token sem forma reconhecivel ausentes de stdout, stderr e memoria do diagnostico (QA-P2-02 e QA-P2-04).
  - Download de 6 MiB com NUL byte a byte, com `-` e com `--json`, sem corrupcao (RF-32(b)).
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: o projeto e CLI em shell, sem formulario nem frontend.
- Suite completa local no push para a PR de `develop` (Regra 8), pelo comando oficial `sh scripts/suite-completa.sh` (`bash tests/run.sh`): em `22e0a6f`, **verde**, 23 arquivos, 760 aprovados, 0 reprovados, 2 pulados (`hash_vetor_oficial_test`, sem rede), 118 s; base do push que abriu a PR. O commit so de documentacao que preenche este registro reexecuta a suite antes do proprio push.

## 5. Gates

Parecer combinado dos dois gates locais, executados pelo Senior Developer. Veredito vigente: ciclo 4. Ciclos 1 a 4 em `Aprovado` nos dois gates.

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | Ciclo 4: nenhum achado de codigo. Desvio registrado: o caso `errors_test` `redacao_de_token_no_formato_sl_u_consome_o_corpo_inteiro` foi escrito depois da correcao de `lib/errors.sh`; a mesma regressao ja estava provada em vermelho pelo caso de forma do `output_test`. Ciclo 1 (resolvidos): T-01 (menor), caso do `>>` escrito depois da guarda, red provado por mutacao; T-02 (menor), TC-TST-04 coberto pelo QA; T-03 (observacao), sem mudanca. | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + `shellcheck-configuration` + `security-best-practices`; Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | Ciclo 4: C-07 (menor), `lib/errors` consome `sl.<a>.<b>...` ate o primeiro ponto sem termo; erra para o lado seguro (RNF-03). C-08 (menor), falha de escrita na saida padrao em arquivo usa `configuracao`, classe ja existente. Ciclo 3: C-05 (menor, `dep-inward-only`), `lib/output` le canais de `lib/auth` e `lib/config` por nome, sem carga nem ciclo; C-06 (menor), segredo com menos de 8 bytes nao e mascarado pelo valor. C-05 a C-08 aceitos pelo Tech Lead. Ciclo 1: C-01 a C-04 sem alteracao posterior; a correcao estrutural de C-01 (encadeamento de sinais em `lib/http`) segue no backlog (`lib/tmp`). | Aprovado |

- Ciclo: 4 (vigente). Historico: ciclo 1 (implementacao inicial); ciclo 2 (decisoes do Tech Lead: limite de `correct_offset` em `0 <= N <= bytes ja confirmados`, documentacao de ajuda e README); ciclo 3 (correcao da reprovacao do QA 1: QA-P2-01 a 03 e OBS-01); ciclo 4 (correcao da reprovacao do QA 2: QA-P2-04 e 05). Status dos achados anteriores: corrigidos; divergencia 1 (nome do par `falha_caminho=`/`falha_classe=` apos `falhas=`) mantida sem mudanca de codigo, com decisao de nome a confirmar pelo Business Analyst.
- `sh scripts/alteracoes-externas.sh --detectar`: saida 0 antes de cada gate, ao fim de cada ciclo e antes da escrita deste registro. Nas etapas de registro, a saida 3 acusou apenas os arquivos do proprio agent, e foi zerada com `--registrar`.

## 6. QA

- Validacao independente do QA Expert sobre os itens afetados, em tres ciclos. Porte M, sobre o mapa de modulos (`docs/testes/mapa-modulos.md`), que ganhou as arestas por chamada de `lib/cmd`, `lib/transfer`, `commands/sync` e `bin/dbx` e a tabela da Regra 2 com os filtros `qa_*`.
- Arquivos do QA, com aceite do solicitante por sha256 (verificados nesta escrita):
  - `tests/unit/qa_rede_p2_test.sh`, 25 casos, sha256 `27b0987121c7a7396ba4e2f9293a81ad5736a059ac863dc758a1692107d62c53`
  - `tests/integracao/qa_robustez_rede_p2_test.sh`, 20 casos, sha256 `d38a10a4f105929a6fbfed12a66e350acd104a5afc8cb45e43f277bdebdf6ecd`
- Comando e contagem literais do ciclo 3: `bash tests/run.sh` (selecao do mapa, nao a suite oficial de push), 23 arquivos, 760 aprovados, 0 reprovados, 2 pulados, `APROVADA`; `shellcheck -x` dos dois arquivos, saida 0.
- Cenarios independentes: RNF-30 (recusa de ajuste invalido antes de qualquer chamada, inclusive da renovacao); RNF-07 (300, 301, 0, ausente, `010`, `5 0`, valor que nao vaza de uma tentativa para a seguinte); RF-58(a-d) (offset igual ao enviado, enviado + 1, igual ao tamanho, origem que encolhe ou cresce, cano); RF-59 (classes distintas na ordem, `--null`, tabulacao, ESC); RF-32(b) (6 MiB com NUL, `-` e `--json`); RNF-31 (HUP, INT e TERM em pontos novos); RNF-32(a-c).
- Achados:

| ID | Severidade | Achado | Status |
|---|---|---|---|
| QA-P2-01 | Maior | Contador de retomadas unico por sessao; cinco retomadas em partes distintas abortavam o envio (criterio RF-58(e) e RF-09) | Corrigido no ciclo 3 do developer (zera quando o deslocamento confirmado avanca) |
| QA-P2-02 | Maior (seguranca) | Token colado a prefixo do resumo (`x_sl.<token>`) saia em claro na linha `falha` (RF-59(c)) | Corrigido no ciclo 3 do developer, em duas camadas (alfabeto do resumo e mascaramento pelo valor) |
| QA-P2-03 | Menor | `Retry-After: 5 0` valia 50 s | Corrigido no ciclo 3 do developer (aparado so nas pontas) |
| QA-P2-04 | Maior (seguranca) | Token `sl.u.<corpo>` saia com o corpo em claro: a redacao por forma rodava antes do mascaramento pelo valor | Corrigido no ciclo 4 do developer (ordem valor -> forma; forma consome o corpo inteiro) |
| QA-P2-05 | Menor | Falha real de escrita na saida padrao em arquivo ou dispositivo cheio saia como `consumidor_encerrou` (15) | Corrigido no ciclo 4 do developer (15 so para cano ou FIFO) |
| OBS-01 | Observacao | Consumidor que fecha cedo sai com 9 (rede) | Corrigido no ciclo 3 do developer (cano vira 15, sem repeticao) |
| OBS-02 | Observacao | `TERM` durante `oauth2/token` deixa `dbx-http.*` em `TMPDIR`; preexistente a fase | Backlog (`lib/tmp` ou tratador global no `bin/dbx`) |
| OBS-03 | Observacao | Janela entre `mktemp` e o registro da area do sync | Backlog (`lib/tmp`) |
| OBS-04 | Observacao (nova no ciclo 3 do QA) | Stdout em socket que fecha cedo sai com codigo 3 e diagnostico impreciso; codigo diferente de 0 e sem repeticao | Backlog (`lib/tmp`) |

- Mutantes: ciclo 1, M1 a M6 mortos pelo QA (M1, M2, M3, M4 e M6 sobreviviam a suite do developer; M5 nao medido). Ciclo 2, m7, m9, m11, m12 e m13 mortos; m10 sobrevive por defesa em profundidade (equivalente no comportamento observavel). Ciclo 3, m14, m16 e m17 mortos; m15 sobrevive (equivalente apos a forma ampliada).
- Historico dos ciclos do QA:

| Ciclo | Data | Status | Resumo da devolucao | Responsavel |
|---|---|---|---|---|
| 1 | 2026-10-18 | Reprovado | QA-P2-01, QA-P2-02 (Maiores), QA-P2-03 (Menor) | QA Expert para Senior Developer |
| 2 | 2026-10-18 | Reprovado | QA-P2-04 (Maior), QA-P2-05 (Menor) | QA Expert para Senior Developer |
| 3 | 2026-10-18 | Aprovado | Correcoes confirmadas; OBS-04 para backlog | QA Expert para Tech Lead |

- Veredito do QA: **Aprovado**, 2026-10-18 (ciclo 3 de 3, sem escalonamento).

## 7. Riscos e rollback

- Riscos residuais (owner e prazo quando informados):
  - F-29, `commands/upload.sh` le `DBX_TRANSFER_HASH`, que nao existe; o canal e `DBX_TRANSFER_CONTENT_HASH`. Owner Senior Developer, fase 3.
  - F-32, comparacao sem caixa fora do ASCII em `lib/sync` depende de `C.UTF-8`. Owner Business Analyst, fase 5.
  - OBS-02, OBS-03 e OBS-04, detalhados na secao 6. Owner Senior Developer, backlog `lib/tmp`.
  - Lacunas do mapa de modulos: `lib/state.sh` e `lib/cmd.sh` sem teste direto; os `.bats` de `scripts/` nao rodam neste ambiente (bats ausente). Owner QA Expert, fase 3.
  - Nome do par `falha_caminho=`/`falha_classe=` emitido apos a contagem `falhas=` (divergencia 1 do ciclo 1 do developer). Decisao de nome a confirmar pelo Business Analyst. Owner e prazo: Nao informados nos insumos.
  - Limite de execucao como `root`: a recusa de alvo somente leitura nao ocorre (testes se pulam). Sem owner.
  - Limite de cliente reabrir o stdout: socket nao reabre; arquivo e truncado, tratado no `>>`. Declarado em `lib/http`. Sem owner.
  - Limite de SIGKILL e de `exit` fora da janela do tratador: um `.dbx-part` pode ficar no disco, mas o filtro do sync impede a publicacao. Sem owner.
- Impacto (contrato): `sync` envia com `rev` (`update`) para arquivo existente e `add` para arquivo novo, sem `autorename`; conflito vira falha do item e o sync sai com `nao_concluida`. `download` recusa alvo somente leitura (codigo 6, `permissao`) e destino que e diretorio ou pasta sobre arquivo (`conflito`). Novas variaveis de ambiente de rede (7), com valor invalido recusado com codigo 2. Parte esgotada em `append` sai `nao_concluida` (RF-09 emendado). `DBX_TRANSFER_ERRO_NAO_CONCLUIDA` removido; `DBX_HTTP_TENTATIVAS_MAXIMAS` deixou de ser `readonly`. Sem schema, sem migracao, sem dependencia nova (`lib/db.sh` e `lib/state.sh` nao alterados).
- Rollback: `git revert` de `22e0a6f` e do commit de documentacao que preenche este registro. Nao ha migracao de dado. Consumidores que leem a linha `falha_caminho=`, a classe `consumidor_encerrou` ou os codigos novos precisam ser avisados se o revert for feito.

## 8. Links e aceites

- Entradas de memoria: [padroes-rede-p2](../../.github/agents/memoria/entradas/2026-10-18-2045-padroes-rede-p2.md), [detalhes-tecnicos-rede-p2](../../.github/agents/memoria/entradas/2026-10-18-2045-detalhes-tecnicos-rede-p2.md), [aceite-testes-qa-p2](../../.github/agents/memoria/entradas/2026-10-18-2045-aceite-testes-qa-p2.md).
- Documentacao sincronizada: [README.md](../../README.md) (secao de variaveis de rede), `bin/dbx` (ajuda), [docs/README.md](../README.md), [System Design](../arquitetura/system-design.md), [escopo, requisitos e criterios de aceite](../requisitos/escopo-requisitos-e-criterios-de-aceite.md), [decisoes pendentes](../requisitos/decisoes-pendentes.md), [funcionalidades candidatas](../requisitos/funcionalidades-candidatas.md), [riscos](../requisitos/riscos-restricoes-e-licenciamento.md), [mapa de modulos](../testes/mapa-modulos.md).
- Commit(s): `22e0a6f` (implementacao, mensagem pelo `commit-writer`, revisada pelo Tech Lead) e o commit de documentacao que preenche este registro.
- PR: [#36](https://github.com/salesadriano/dropbox_sync/pull/36) para `develop`, labels `review` e `enhancement`. Review request nativo nao aplicado: o unico colaborador e o proprio autor.
- Intervencao humana (regra 48): Nenhum arquivo de origem humana registrado nos insumos desta fase.
- Tech Lead: **Aprovado com ressalvas**, 2026-10-18. Ressalvas: F-29 e F-32, OBS-02 a OBS-04, lacunas do mapa de modulos (ver secao 7). A aprovacao final vale somente com a suite completa local verde registrada na secao 4.
- Solicitante: aceite dos `qa-*` registrado em [aceite-testes-qa-p2](../../.github/agents/memoria/entradas/2026-10-18-2045-aceite-testes-qa-p2.md) (25 + 20 casos, sha256 da secao 6).

## 9. Revisao consolidada e aprovacao (compacta)

- Identificacao: porte M; Tech Lead; 2026-10-18; branch `feature/robustez-de-rede-p2`.
- Artefatos consolidados, por referencia: este registro (secoes 5 e 6, com os gates e o QA); [prompt](../prompts/2026-10-18_2045_robustez-de-rede-p2.md); [fonte](../sources/2026-10-18-analise-melhorias.md); requisitos da secao 2 (RNF-30, RF-58, RF-59, RNF-31, RNF-32, F-33, DP-33, RSK-40 e RSK-41; emendas em RF-09, RNF-07 e RF-32(b)).
- Divergencias tratadas:
  - DIV-22 (`RNF-07` x `Retry-After`): encerrada. `Retry-After` implementado, com teto de 300 s e recuo de 1 s.
  - RF-58(b) literal (offset acima do enviado): corrigido no ciclo 2 do developer; `N` limitado a `0 <= N <= bytes ja confirmados`.
  - RF-09 (parte esgotada em `append`): emendado; sai `nao_concluida`, com a classe original no diagnostico.
  - RF-58(e) (tentativas por parte): QA-P2-01 corrigido; o limite continua por parte.
  - RF-59(b) x contrato de `falhas=`: resolvida. O Tech Lead decidiu manter `falhas` como contagem e acrescentar os pares `falha_caminho`/`falha_classe` ([detalhes-tecnicos-rede-p2](../../.github/agents/memoria/entradas/2026-10-18-2045-detalhes-tecnicos-rede-p2.md)), e o Business Analyst emendou o RF-59(b) e o TC-FLH.
- Pendencias: merge da PR #36 pelo solicitante (sem pipeline no repositorio).
- Decisao de fechamento: **Aprovado com ressalvas**, 2026-10-18. Ressalvas: F-29 (Senior Developer, fase 3); F-32 (Business Analyst, fase 5); OBS-02, OBS-03 e OBS-04 (Senior Developer, backlog `lib/tmp`); lacunas do mapa de modulos (QA Expert, fase 3). Validacao QA frontend: Nao aplicavel: sem frontend.
