# Fase 2 do backlog (B2): trava de concorrencia por par (F-12) e lib/tmp para temporarios e sinais (F-31)

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | Fase 2 do plano do backlog: trava de concorrencia por par de `sync`/`verificar` (F-12, RF-69, RF-70, RF-71, RNF-35, RNF-36) e o restante do F-31, o `lib/tmp`, que tambem entrega o C-1 da fase 1 (fim do codigo gemeo de `sync` e `verificar`). |
| Porte | M. Toca contrato publico (`--esperar`/`--wait`, codigo 7 com mensagem propria, `ln` e `rmdir` no preflight), persistencia, concorrencia e tratamento de sinais. Sem gatilho de G: nenhuma integracao externa nova; a arquitetura so ganha o adaptador `lib/tmp`, sem dependencia alem de `lib/errors`. |
| Log de prompt | [docs/prompts/2026-10-19_1419_backlog-fase-2-trava-e-tmp.md](../prompts/2026-10-19_1419_backlog-fase-2-trava-e-tmp.md) |
| Branch / base | `feature/trava-e-tmp-b2` sobre `develop` @ `c8fc887` |
| Agents | Business Analyst (requisitos v1.12, System Design); DBA ([parecer da trava](2026-10-19-1419-parecer-dba-trava.md)); Senior Developer (implementacao, sob `protocolo-tdd` e `protocolo-conformidade`); QA Expert (validacao independente, 23 casos, 3 ciclos); Tech Lead (decisoes, fechamento). |
| Data | 2026-10-19 |

## 2. Causa ou decisao

Decisao do solicitante (F-12): uma trava por par (conta x origem x destino), pares diferentes em paralelo, comandos avulsos sem trava; trava ocupada recusa na hora dizendo pid e inicio, com `--esperar N` (alias `--wait`) para esperar; trava orfa do mesmo host e retomada com aviso, a de outro host nunca. Decisoes DIV-38 a DIV-53 na memoria [2026-10-19-1419-trava-de-concorrencia](../../.github/agents/memoria/entradas/2026-10-19-1419-trava-de-concorrencia.md). Principais:

- DIV-38: chave do par sem ordem. DIV-41: `lib/state` cria e remove a trava; `lib/tmp` so registra a liberacao. DIV-43: trava ocupada e `conflito`/7.
- DIV-47: parte "conta" da chave e o resumo local da credencial, nao o `account_id` (exigiria rede e quebraria RF-69(d) e RF-65(b)/(c)); custo aceito: duas credenciais da mesma conta no mesmo diretorio de estado nao se excluem.
- DIV-48 e DIV-50: so estado alheio ou sem escrita segue sem trava (com aviso); trava viva ja existente decide (7); repeticoes esgotadas recusam com 7.
- DIV-44 e DIV-45: o `unlink` recusa (7) com trava viva no mesmo host e mantem, avisando, as nao vivas.
- DIV-51: stdout em socket vivo funciona; 15 so se o consumidor de fato encerrou. DIV-52: `mkdir -p` do destino do `download` de pasta antes da trava, aceito. DIV-49: `download` de pasta trava (roda um `sync`).
- DIV-53: a receita do DBA para retomar orfa fica (apaga, depois `ln`); o aviso e dado por quem apaga a orfa, mesmo que perca o `ln`: exatamente um vencedor e um aviso por orfa removida.

Abordagens para a composicao de tratadores no `lib/tmp` (parecer do Senior Developer):

- **A, escolhida:** um tratador por sinal, armado uma vez por processo (`BASHPID`), percorrendo registro LIFO de acoes (nome de funcao, nunca texto) e areas, com secao critica que adia o sinal; composicao por construcao e fecha OBS-03 sem janela.
- **B, recusada:** encadear texto de `trap` (`eval` fragil, janela entre ler e rearmar).
- **C, recusada:** pilha salvar/restaurar por modulo (o desenho anterior, `DBX_HTTP_TRATADOR_EXTERNO`): nao compoe e deixa area com sinal fora das janelas.

Removidos os canais antigos (`DBX_HTTP_TRATADOR_EXTERNO`, `dbx_http_sinais_devolver` e os tratadores gemeos de `sync` e `verificar`); ciclo comum `dbx_cmd_ciclo_iniciar` em `lib/cmd`.

## 3. Arquivos

Levantado com `git diff --numstat` e `git status --short`; arquivos novos contados por `wc -l`.

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/tmp.sh` | Novo (registro LIFO, areas, secao critica, tratador unico) | +278/-0 |
| `lib/state.sh` | Alterado (trava por par, `.r`, leitura hostil, `host_id`, `dbx_state_trava_examinar`, gravacao atomica via `lib/tmp`) | +571/-7 |
| `lib/cmd.sh` | Alterado (`dbx_cmd_ciclo_iniciar`, aquisicao e `--esperar`) | +83/-29 |
| `lib/config.sh` | Alterado (`dbx_config_identidade`, temporario via `lib/tmp`) | +46/-20 |
| `lib/http.sh` | Alterado (remocao do canal de tratador externo, OBS-02, OBS-04) | +38/-54 |
| `lib/transfer.sh` | Alterado | +18/-43 |
| `lib/hash.sh` | Alterado | +10/-14 |
| `lib/cli.sh` | Alterado (`--esperar`/`--wait`) | +19/-0 |
| `lib/preflight.sh` | Alterado (`ln`, `rmdir`) | +4/-2 |
| `lib/walk.sh` | Alterado | +5/-2 |
| `commands/sync.sh` | Alterado | +34/-55 |
| `commands/verificar.sh` | Alterado | +32/-41 |
| `commands/unlink.sh` | Alterado (recusa e reconferencia das travas) | +116/-6 |
| `commands/diagnostico.sh` | Alterado (mostra a trava) | +50/-0 |
| `bin/dbx` | Alterado | +19/-5 |
| `completions/dbx.bash` | Alterado | +4/-4 |
| `tests/unit/tmp_test.sh` | Novo | +349/-0 |
| `tests/unit/state_trava_test.sh` | Novo | +725/-0 |
| `tests/integracao/trava_test.sh` | Novo | +887/-0 |
| `tests/integracao/qa_trava_tmp_b2_test.sh` | Novo (QA) | +1057/-0 |
| `tests/unit/preflight_test.sh` | Alterado (QA: reconhecedor da auditoria; `ln` e `rmdir` no PATH reduzido) | +60/-6 |
| `tests/integracao/diagnostico_test.sh` | Alterado (TC-DIA-01, 7 para 8 checagens; `rmdir`) | +4/-3 |
| `tests/integracao/qa_consulta_diagnostico_b1_test.sh` | Alterado (retrato sem `mtime` de diretorio; `rmdir`) | +6/-2 |
| `README.md` | Alterado | +8/-3 |
| `docs/arquitetura/system-design.md` | Alterado (BA) | +54/-5 |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | Alterado (BA) | +45/-12 |
| `docs/requisitos/funcionalidades-candidatas.md` | Alterado (BA) | +3/-3 |
| `docs/requisitos/riscos-restricoes-e-licenciamento.md` | Alterado (BA) | +5/-1 |
| `docs/requisitos/decisoes-pendentes.md` | Alterado (BA) | +2/-1 |
| `docs/testes/mapa-modulos.md` | Alterado | +28/-17 |
| `docs/reviews/2026-10-19-1419-parecer-dba-trava.md` | Novo (DBA) | documental |
| `.github/agents/memoria/entradas/2026-10-19-1419-trava-de-concorrencia.md` | Novo (decisao) | documental |
| `docs/prompts/2026-10-19_1419_backlog-fase-2-trava-e-tmp.md` | Novo (log de prompt) | documental |

Total de linhas de codigo (producao e teste, sem documentacao): **4708** (4415 adicionadas, 293 removidas), somando `lib/`, `commands/`, `bin/`, `completions/` e `tests/`.

## 4. Testes rodados

Mudanca ampla em `lib/` (13 modulos) e `commands/`: a selecao foi a suite inteira, com parada no primeiro erro (Regra 9), alem dos filtros por arquivo nos ciclos de correcao. Contagens literais dos pareceres do Senior Developer.

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| Suite inteira, ciclo 1 (40 arquivos, 2 pulados) | `lib/`, `commands/`, `bin/` | `bash tests/run.sh` | 1161 | 1159 | 0 | 9 min 06 s |
| `tmp_test.sh` (ciclo 2) | `lib/tmp.sh` | `bash tests/run.sh tmp_test` | 16 | 16 | 0 | nao informada |
| `state_trava_test.sh` (ciclo 3) | `lib/state.sh` | `bash tests/run.sh state_trava` | 28 | 28 | 0 | nao informada |
| `trava_test.sh` mais `state_trava_test.sh` (ciclo 3) | `lib/state.sh`, `commands/` | `bash tests/run.sh trava` | 59 | 59 | 0 | nao informada |
| `qa_trava_tmp_b2_test.sh` (ciclo 3) | `lib/state.sh`, `commands/unlink.sh` | `bash tests/run.sh qa_trava_tmp_b2` | 23 | 23 | 0 | nao informada |
| `preflight_test.sh` (ciclo 3) | `lib/preflight.sh` | `bash tests/run.sh preflight` | 35 | 35 | 0 | nao informada |
| `composicao_test.sh` (ciclo 3) | `commands/*.sh` | `bash tests/run.sh composicao` | 27 | 27 | 0 | nao informada |
| `json_test.sh` (ciclo 3) | auditoria de `lib/*.sh` | `bash tests/run.sh json` | 60 | 60 | 0 | nao informada |
| `cli_test.sh` (ciclo 3) | `lib/cli.sh` | `bash tests/run.sh cli` | 17 | 17 | 0 | nao informada |
| `diagnostico_test` (ciclo 3) | `commands/diagnostico.sh` | `bash tests/run.sh diagnostico` | 14 | 14 | 0 | nao informada |
| `qa_consulta_diagnostico_b1_test.sh` (ciclo 3) | `lib/preflight.sh` | `bash tests/run.sh qa_consulta_diagnostico_b1` | 21 | 21 | 0 | nao informada |

- Lacuna: a suite inteira so foi rodada no ciclo 1 (1159 aprovados, 0 reprovados, 2 pulados; base 37 arquivos, 1098, 5 min 23 s). Os ciclos 2 e 3 reexecutaram por filtro, sem duracao informada; a suite completa oficial, depois do ciclo 3, esta abaixo.
- Casos novos do developer: 61 no ciclo 1 (`tmp_test` 16, `state_trava_test` 22, `trava_test` 23). Suite do QA: 23 casos.
- Red observado: contra a base (`git archive HEAD` com os testes novos copiados caso a caso), 59 dos 61 casos vermelhos; 2 neutros por desenho (autoteste do detector da auditoria e "comandos avulsos nao travam"). `lib/tmp` com modulo ausente; `dbx_state_trava_adquirir` inexistente. Dois casos vacuos na base foram endurecidos (`termino_do_processo_libera_a_trava`, `trv04`). Ciclo 2: `c2_qualquer_byte_depois_da_quebra_final_e_ilegivel`, `c2_mesma_grafia_mesma_chave_em_c_e_em_c_utf8`, `c2_estado_sem_escrita...`, `c2_div51_download_para_socket_vivo_sai_0` e TC-TRV-39, todos vermelhos antes do conserto. Ciclo 3: `c3_qa_b2_09_orfa_conhecida_retomada_no_meio_do_unlink_para_com_7` saiu 0 contra o ciclo 2b; auditoria do preflight vermelha antes de `rmdir` entrar na lista.
- Parada no primeiro erro (Regra 9): atendida pelo runner (`Bail out!`). Interrupcoes corrigidas e reexecutadas do inicio: `config_test` (palavra `conta`), `harness_test` (funcao redefinida), `json_test` (massa por `$(printf`), `composicao` (canal alheio, contagem), `tmp_test` (auditoria lia literal), `diagnostico_test` (TC-DIA-01) e `qa_consulta_diagnostico_b1` (retrato com `mtime` de diretorio).
- Barreiras estaticas: `shellcheck` 0.10 limpo em `lib/*.sh commands/*.sh bin/* scripts/*.sh` e nos testes alterados, nos tres ciclos. Guarda `bash scripts/verificar-remocao-de-casos.sh`: nenhuma reducao.
- Testes de seguranca e acesso (Regra 6):
  - Sentinelas de segredo e de conta ausentes em stdout e stderr (trava ocupada, unlink recusado, diagnostico humano e estruturado); nome da trava por resumo, nunca a conta.
  - Matriz hostil de 15 conteudos de trava, mais diretorio, ligacao e dono alheio: ilegivel, intacta, sem byte cru; ciclo 2 acrescentou qualquer byte depois do `\n` final (NUL incluido).
  - `--esperar` validado so por digitos, 0 a 3600, antes de trava, rede ou escrita (TC-ESR-01).
  - Concorrencia real: 20 processos com barreira (1 vence, 19 recebem 7); 2 e 20 retomadores da mesma orfa (1 vence); leitor concorrente (0 leituras ilegiveis); `kill -9` entre o `mv` e a liberacao (memoria integra, trava retomada com aviso).
  - Sinais: `INT`/`TERM`/`HUP` em 6 fases (token, conta, listagem, espaco, envio, recebimento) e na espera: 14, sem `dbx-*` no `TMPDIR` e sem trava; OBS-03 por dobro de `mktemp` que se auto-sinaliza; `verificar` e `sync --dry-run` byte a byte apos cada sinal.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: projeto e CLI em shell, sem formulario.
- Suite completa local no push para a PR de `develop` (Regra 8), pelo comando oficial `sh scripts/suite-completa.sh` (`bash tests/run.sh`): **verde** em `8fb84b0`, 41 arquivos, 1197 aprovados, 0 reprovados, 2 pulados (vetor oficial sem rede), 584 s; `--conferir` com saida 0. Guarda de remocao de casos: 1209 -> 1209, sem reducao. O commit de documentacao que preenche este registro reexecuta a suite antes do proprio push.

## 5. Gates

Parecer combinado dos dois gates locais, executados pelo Senior Developer, nesta ordem. Pareceres completos no material do Senior Developer (ciclos 1, 2, 2b e 3).

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | Ciclo 1: ressalva, duas mudancas em teste aprovado (TC-DIA-01 de 7 para 8 checagens; `_qa_retrato` sem `mtime` de diretorio), consequencia de emendas aprovadas, para revisao do QA. Ciclo 2: ressalvas sobre `qa_b2_07`, `qa_b2_02` x `qa_b2_03` (corrida entre `rm` e `ln`, origem de DIV-53), `qa_b2_19` (corrida do proprio caso), `json_test`/`composicao_test` reprovando por `qa_trava_tmp_b2_test.sh` e auditoria do preflight cega. Ciclo 3: nenhum. | Ciclo 1 Aprovado; ciclo 2 Aprovado com ressalvas; ciclo 3 Aprovado |
| `protocolo-conformidade` | `clean-architecture` + `shellcheck-configuration`; `security-best-practices` (concorrencia, entrada de usuario, segredo); Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | Ciclo 1: ressalvas, DIV-47, DIV-48 e D-6 (download de pasta) a ratificar; System Design defasado (BA); mapa de modulos atualizado a pedido do Tech Lead. Ciclo 2: as ressalvas do TDD, mais DIV-50 e DIV-51 aplicados. Ciclo 3: nenhum; TC-TRV-36 passou a ignorar literais entre aspas, como a auditoria do `tmp_test`. | Ciclo 1 Aprovado com ressalvas; ciclo 2 Aprovado com ressalvas; ciclo 3 Aprovado |

- Ciclo: 3 (com ciclo 2b intermediario). Status dos achados do QA: QA-B2-01 a QA-B2-07 corrigidos no ciclo 2 (QA-B2-05 aceito como DIV-52, sem mudanca); QA-B2-08, 09 e 10 corrigidos no ciclo 3; QA-B2-11 corrigido pelo Tech Lead. Ressalvas do ciclo 1: DIV-47, 48 e 49 ratificados (memoria); System Design sincronizado pelo BA.
- `sh scripts/alteracoes-externas.sh --detectar`: exit 0 antes de cada passo e gate; dois artefatos do Senior Developer (`.r`, `.x`, gerados pela corrida contra a base) removidos e guardas acrescentadas nos testes.

## 6. QA

- Validacao independente do QA Expert em [tests/integracao/qa_trava_tmp_b2_test.sh](../../tests/integracao/qa_trava_tmp_b2_test.sh), 23 casos, sha256 `e875416efec7772235fc4fc092e31776a3ce73ea15f06307f6a1f5cbf34696b8`. Massa e duplo de `curl` proprios.
- Revisao de teste aprovado em fase anterior (regra 12): `tests/unit/preflight_test.sh` (mudanca na auditoria do preflight: reconhecedor de literal de vetor corrigido e `ln` e `rmdir` no PATH reduzido), sha256 `5ae77af7f99c64e87d5cc9dabbb385f7cf88bbc8929994cea28513882580ff84`. As duas alteracoes do developer em testes aprovados (TC-DIA-01 de 7 para 8 e o retrato sem `mtime` de diretorio, em `qa_consulta_diagnostico_b1_test.sh`) foram julgadas legitimas, pois seguem emendas aprovadas.
- Ciclo 1: **Reprovado**, 7 achados.
  - QA-B2-01: NUL depois da trava era aceito como legivel.
  - QA-B2-02: o `unlink` nao reconferia as travas antes de apagar.
  - QA-B2-03: a caixa da chave dependia da localidade.
  - QA-B2-04: socket vivo na saida padrao saia 15 (DIV-51).
  - QA-B2-05: `mkdir` do destino antes da trava (DIV-52, aceito).
  - QA-B2-06: estado sem escrita ignorava trava viva (DIV-50).
  - QA-B2-07: defeitos de teste.
- Ciclo 2: **Reprovado**, 3 achados.
  - QA-B2-08 (media): `rmdir` usado fora do preflight, exposto porque a auditoria do preflight estava cega depois de `x=()` desde antes desta fase.
  - QA-B2-09: o `unlink` comparava so nomes de trava, nao o conteudo.
  - QA-B2-10: `grep -c` sobre arquivo num teste do Senior Developer.
  - Decisao do ciclo: DIV-53, em que quem apaga a orfa da o aviso.
- Ciclo 3: **Aprovado**, com QA-B2-11 (baixa): o TC-TRV-36 tinha ficado mais fraco; o Tech Lead corrigiu. Duas janelas residuais do `unlink` declaradas: nenhuma apaga trava e, no pior caso, a memoria fica ausente (nunca decisao).
- Execucao do QA: `qa_trava_tmp_b2_test.sh` 23 aprovados, 0 falhos no ciclo 3; a contagem da suite inteira nao veio na delegacao.
- Veredito do QA: **Aprovado**, 2026-10-19 (ciclo 3).

## 7. Riscos e rollback

- Riscos residuais:
  - Duas credenciais distintas da mesma conta sobre o mesmo diretorio de estado nao se excluem (DIV-47). Owner Tech Lead, sem prazo.
  - Duas janelas residuais do `unlink` entre a ultima conferencia e um `rm`: nenhuma apaga trava; no pior caso a memoria fica ausente.
  - Sem `/proc`, EPERM em `kill -0` cai como morto (D-4); NFS e melhor esforco (RSK-49, ja no README).
  - Estado alheio ou sem escrita segue sem trava, com aviso (DIV-48/DIV-50).
  - `trava_test` usa `python3` so para o socket da OBS-04 e pula sem ele.
- Licoes:
  - A auditoria do preflight estava cega havia fases: o salto de "literal de vetor", iniciado em `segmentos=() resto=$campo`, so terminava numa linha com `)` e deixava de olhar o resto do arquivo; um rotulo de `case` novo o encerrou e expos `>/dev/null` e o `rmdir`. Ver a licao de selecao de auditorias (`2026-10-18-1745-selecao-inclui-auditorias-lib`). Regra a reter: toda auditoria nova precisa de autoteste que prove que ela ainda enxerga o arquivo inteiro.
  - O QA reprovou tres vezes por janelas de concorrencia no `unlink` (QA-B2-02, QA-B2-09 e as janelas residuais): conferir nomes nao basta; e preciso reler o conteudo imediatamente antes de cada `rm` e declarar a janela que sobra.
- Impacto: contrato. Novas flags `--esperar N` e `--wait N` em `sync` e `verificar` (e no `download` de pasta); trava ocupada sai 7 com mensagem propria; `unlink` recusa com 7 se houver execucao viva; `diagnostico` mostra a trava e passa a ter 8 checagens; `ln` e `rmdir` passam a ser utilitarios exigidos no preflight (README); sinal depois de envio concluido sai 14; stdout em socket vivo funciona. Sem schema nem dependencia nova. Removidos `DBX_HTTP_TRATADOR_EXTERNO`, `dbx_http_sinais_devolver`, `dbx_http_interrompido` e os tratadores gemeos.
- Rollback: `git revert 7222cf9` (e do commit de documentacao) basta; `8fb84b0` (plugin) e independente. Travas e temporarios sao transitorios; nao ha migracao de dado nem de credencial.

## 8. Links e aceites

- Entradas de memoria: `2026-10-19-1419-trava-de-concorrencia`.
- Documentacao sincronizada: [escopo-requisitos-e-criterios-de-aceite.md](../requisitos/escopo-requisitos-e-criterios-de-aceite.md), [funcionalidades-candidatas.md](../requisitos/funcionalidades-candidatas.md), [riscos-restricoes-e-licenciamento.md](../requisitos/riscos-restricoes-e-licenciamento.md), [decisoes-pendentes.md](../requisitos/decisoes-pendentes.md), [system-design.md](../arquitetura/system-design.md), [mapa-modulos.md](../testes/mapa-modulos.md), [parecer do DBA](2026-10-19-1419-parecer-dba-trava.md), `README.md`.
- Commit(s): `7222cf9` (fase 2), `8fb84b0` (`chore(claude)`: habilita o plugin `ai-team` em `.claude/settings.json`, alteracao externa acusada pela regra 48 e incluida por decisao do solicitante) e o commit de documentacao que preenche este registro.
- PR: [#42](https://github.com/salesadriano/dropbox_sync/pull/42) para `develop`, labels `review` e `enhancement`.
- Tech Lead: aceite com a suite completa local verde em `8fb84b0` e a validacao independente do QA aprovada no ciclo 3; QA-B2-11 corrigido pelo Tech Lead em `tests/integracao/trava_test.sh` (TC-TRV-36 volta a ver o nome da trava no texto cru, conferido por amostra com as tres formas).
- Solicitante: aceite dos `qa-*` por sha256 (regra 12): `tests/integracao/qa_trava_tmp_b2_test.sh` (23 casos, `e875416e...6b8`) e a mudanca na auditoria de `tests/unit/preflight_test.sh` (`5ae77af7...ff84`); e, em confirmacao separada, a inclusao de `rmdir` nas listas de PATH reduzido de `preflight_test`, `diagnostico_test` e `qa_consulta_diagnostico_b1_test`.
