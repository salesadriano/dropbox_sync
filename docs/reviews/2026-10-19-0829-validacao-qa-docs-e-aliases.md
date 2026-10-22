# Validação do QA Expert — Aliases, origem vazia pelo plano, localidade e documentação (fase 4)

## Identificação

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Agent: QA Expert, por delegação do Tech Lead (regra 44)
- Data: 2026-10-19
- Ciclo do QA: 1
- Porte: **G**. Validação independente sobre os itens afetados, com suíte própria e mutantes.
- Branch e worktree: `feature/docs-e-aliases-p4` em `/home/sales/dropbox_api.worktrees/feature-docs-e-aliases-p4`, base `6b00bcd`, sem commit da demanda
- Log de prompt: [2026-10-19_0829_docs-e-aliases-p4.md](../prompts/2026-10-19_0829_docs-e-aliases-p4.md)
- Memória do papel: `sh scripts/memoria-index.sh --agente qa-expert`; extrato transposto `2026-10-19-0829-aliases-poda-e-comentarios`
- Critérios: [escopo-requisitos-e-criterios-de-aceite.md](../requisitos/escopo-requisitos-e-criterios-de-aceite.md) v1.6, com RF-64 (TC-ALI-01..03), RF-41(b) com O-1 e DIV-30 (TC-DEL-13), RF-54(e)(f)(g) (TC-CX-04/05) e RNF-34 (TC-DOC-01)

## Precondições de entrada

| Precondição | Situação |
|---|---|
| Parecer de evidências de testes (TDD) | [Aprovado](2026-10-19-0829-parecer-tdd-docs-e-aliases.md), ciclo 1, com 2 achados menores |
| Parecer de conformidade | [Aprovado](2026-10-19-0829-parecer-conformidade-docs-e-aliases.md) |
| `alteracoes-externas.sh --detectar` antes de começar | Saída 0, sem alteração externa |
| Fluxo frontend ou Cypress | Não se aplica: a CLI não tem interface gráfica |

## Escopo validado

Diff de produto: `bin/dbx`, `commands/sync.sh`, `commands/unlink.sh`, `commands/config.sh`, `lib/sync.sh`, `lib/preflight.sh`, `lib/output.sh`, `lib/http.sh`, `lib/transfer.sh` e `README.md`. Também entram `docs/arquitetura/system-design.md` e a poda de 31 diretórios de skill em `.github/skills/`.

### Auditoria por ponto de risco

| # | Ponto | Verificação do QA | Resultado |
|---|---|---|---|
| 1 | **Aliases** | Os 11 pares estão no mesmo ramo do `case` (`commands/*.sh`). O QA comparou o estado final da execução real (código, stdout, URLs chamadas, árvore local, credencial e memória) entre português, inglês e misto, nos dois sentidos. A repetição foi testada em 7 combinações de sentido e com opções sem valor repetidas. As formas `--source=x` e `--origem=x` recebem a mesma recusa. Prefixos e outra caixa são recusados como uso inválido sem chamada de rede: `--pu`, `--pul`, `--pus`, `--sour`, `--sourc`, `--de`, `--des`, `--mirr`, `--ye`, `--allow-empty`, `--allow-empty-sourc`, `--PUSH`, `--Pull` e `--YES`. Alias de um comando é recusado nos outros. Opção com valor sem o valor recebe a mesma recusa pelos dois nomes. A ajuda põe os dois nomes na mesma linha e o README documenta os 11 pares | Conforme |
| 2 | **Guarda (O-1, DIV-30)** | Os casos `qa_exclusao_*` (11) e `qa_guarda_*` (4) da fase 3 rodaram **sem alteração** do arquivo e passaram 15 de 15. Sem `--espelhar`, origem vazia sai com 0, não faz escrita remota nem download e não toca o destino local (comparado por `stat`). Com `--push` e `--pull`, `--mirror --yes` sem memória recusa pelo plano (`recusada=origem vazia`, código 14). Raiz local ausente ou que é arquivo continua recusada sem `--espelhar` | Conforme |
| 3 | **Localidade** | Testada com `LC_ALL=C` no ambiente, com `LANG=C.UTF-8` sem `LC_ALL`, com localidade inexistente (`DBX_SYNC_LOCALIDADE`), com valores fora do alfabeto e com `C` puro. Em processo isolado, `LC_ALL` volta ao valor anterior, inclusive ausente; `${#x}`, o fatiamento e o escape de `lib/json` são iguais antes e depois da comparação. A configuração enviada ao `curl` para um nome multibyte tem os mesmos bytes com e sem a conversão fora do ASCII | Conforme |
| 4 | **Comentários** | `lib/http.sh` e `lib/transfer.sh` foram comparados com o `HEAD` depois de tirar comentários de linha inteira e linhas em branco (`scratchpad/qa-cmp/sem_comentarios.sh`). O `diff` sai 0 nos dois e nenhum dos arquivos tem heredoc. Todas as linhas `+`/`-` do `git diff -U0` são comentário ou branco | Conforme: só comentários |
| 5 | **Documentação (RNF-34)** | A lista de utilitários do README é igual à do preflight (`tail` e `df` incluídos), mais a família SHA-256 com `openssl`. Não há "sem estado local persistente" nem "sqlite" vigente: a única menção em `README.md:22` é a nota de legado. **Duas contradições permanecem: QA-P4-01 e QA-P4-02** | **Não conforme** |
| 6 | **Poda do pacote** | `validate-skill-links.sh` sai 0, `verificar-instrucoes-do-projeto.sh` sai 0 (48 regras, `develop`, 4 caminhos), o hook `guarda-de-comandos.sh` com `ls` sai 0 e o `resumo-de-estado.sh` sai 0. Uma varredura de `skills/<nome>` das 31 skills removidas em `.github/`, `CLAUDE.md` e `.claude/` só encontrou citações em `.github/agents/memoria/historico/`, que são registros históricos imutáveis e não links vivos | Conforme |

## Suíte independente

Arquivo: `tests/integracao/qa_docs_aliases_p4_test.sh`, com 16 casos, `shellcheck` limpo e cenário, duplo de `curl` e massa próprios. Cada caso monta o próprio cenário, e a primeira execução de um caso semeia as seguintes. A fotografia e a restauração da árvore fazem só o nome da opção variar entre execuções. A limpeza é a da área do executor.

| # | Caso | Critério | Resultado |
|---|---|---|---|
| 1 | `teste_qa_p4_alias_ajuda_e_readme_documentam_os_onze_pares` | RF-64(c) | ok |
| 2 | `teste_qa_p4_alias_config_recusas_e_ultimo_valor_iguais_ao_portugues` | TC-ALI-03, RF-64(e) | ok |
| 3 | `teste_qa_p4_alias_formas_nao_aceitas_recusam_como_o_portugues_sem_rede` | RF-64(b)(f) | ok |
| 4 | `teste_qa_p4_alias_repeticao_pelos_dois_nomes_segue_a_regra_do_portugues` | RF-64(e), DIV-31 | ok |
| 5 | `teste_qa_p4_alias_sync_execucao_real_em_ingles_misto_e_portugues_deixa_o_mesmo_estado` | TC-ALI-01, RF-64(b)(d) | ok |
| 6 | `teste_qa_p4_alias_unlink_ingles_misto_e_repetido_deixam_o_estado_do_portugues` | TC-ALI-02 | ok |
| 7 | `teste_qa_p4_doc_readme_lista_os_utilitarios_do_preflight_e_nao_tem_frase_revogada` | TC-DOC-01, RNF-34 | **not ok** (QA-P4-01) |
| 8 | `teste_qa_p4_doc_system_design_marca_a_decisao_revogada_na_propria_linha` | RNF-34(f) | **not ok** (QA-P4-02) |
| 9 | `teste_qa_p4_guarda_pull_mirror_yes_sem_memoria_recusa_pelo_plano_e_so_allow_libera` | TC-DEL-13, RF-64(b) | ok |
| 10 | `teste_qa_p4_guarda_raiz_ausente_ou_arquivo_segue_recusada_sem_espelhar` | RF-41(b), DIV-30 | ok |
| 11 | `teste_qa_p4_guarda_sem_espelhar_origem_vazia_nao_escreve_nada_e_sai_zero` | DIV-30 | ok |
| 12 | `teste_qa_p4_localidade_ausente_aviso_unico_fora_do_stdout_sem_segredo` | TC-CX-05, RF-54(f)(g), RNF-03 | ok |
| 13 | `teste_qa_p4_localidade_fixacao_nao_vaza_para_o_processo_sob_c_e_sob_utf8` | RF-54(e), DIV-32 | ok |
| 14 | `teste_qa_p4_localidade_nao_muda_bytes_enviados_a_rede` | RF-54(e) | ok |
| 15 | `teste_qa_p4_localidade_receber_espelhado_com_lc_all_c_nao_duplica_nem_apaga` | TC-CX-04 (sentido `--pull`) | ok |
| 16 | `teste_qa_p4_localidade_valor_fora_do_alfabeto_cai_no_padrao_e_c_puro_avisa` | RF-54(e)(f); recomendação do parecer TDD | ok |

Contagem literal do arquivo, rodado por prefixo para diagnóstico: `qa_p4_alias` deu `ok=6 nao_ok=0`, `qa_p4_guarda` deu `ok=3 nao_ok=0` e `qa_p4_localidade` deu `ok=5 nao_ok=0`. `qa_p4_doc_readme` e `qa_p4_doc_system` deram `ok=0 nao_ok=1` cada. Total: **14 aprovados e 2 reprovados**.

O mapa [docs/testes/mapa-modulos.md](../testes/mapa-modulos.md) foi atualizado. A Regra 2 ganhou a linha `qa_docs_aliases` e o filtro `qa_` agora seleciona seis arquivos. `commands/config.sh`, `commands/unlink.sh` e `commands/sync.sh` passam a incluir `qa_docs_aliases`, e `commands/sync.sh` também passa a listar `qa_cache_unico`.

## Mutantes manuais

Cópias em `/tmp/claude-1000/-home-sales-dropbox-api/79c5663b-427b-43f7-afa1-0bdb22ddd6bf/scratchpad/qa-mut-p4/`. Cada mutante parte de uma base limpa (`mutar.sh`), confirma que o arquivo mudou e roda só os casos do QA do filtro indicado.

| Id | Mutação | Caso que matou | Resultado |
|---|---|---|---|
| M1 | `lib/sync.sh`: `{ LC_ALL=$DBX_SYNC_LOCALIDADE; }` sem `local` (a fixação vaza para o processo) | `qa_p4_localidade_fixacao_*` | Morto |
| M2 | `lib/sync.sh`: remove a validação por alfabeto de `DBX_SYNC_LOCALIDADE` | `qa_p4_localidade_valor_*` | Morto |
| M3 | `commands/sync.sh`: `--pull` em ramo próprio, sem a regra do segundo sentido | `qa_p4_alias_repeticao_*` (`--pull --pull`) | Morto |
| M4 | `commands/unlink.sh`: `--keep-app` aceito sem efeito | `qa_p4_alias_unlink_*` | Morto |
| M5 | `commands/sync.sh`: recusa de origem vazia condicionada à memória (`${#DBX_STATE_ENTRADA[@]} -gt 0`) | `qa_p4_guarda_pull_*`, trecho `--push` | Morto. Na primeira versão o caso só cobria `--pull` e o mutante **sobreviveu**: lá o destino povoado entra na memória durante o resumo, a mesma equivalência registrada pelo Senior Developer. O QA acrescentou o trecho `--push` sem memória, e nele o mutante sai com 0 e apaga o remoto |
| M6 | `commands/sync.sh`: aviso de localidade emitido duas vezes | `qa_p4_localidade_ausente_*` | Morto |
| M7 | `commands/sync.sh`: aviso emitido sempre (`\|\| true`) | `qa_p4_localidade_valor_*` | Morto |
| M6a | aviso sem `>&2` | — | **Equivalente**: `dbx_output_render_diagnostico` já escreve em stderr (`lib/output.sh:262-265`). Foi substituído por M6 |

Resultado: **7 de 7 mutantes não equivalentes mortos** e 1 equivalente descartado.

## Execução (diff em várias `lib/`: suíte inteira, parando no primeiro erro)

| Comando | Resultado literal |
|---|---|
| `bash tests/run.sh < /dev/null` | `arquivos executados : 24`, `casos aprovados : 793`, `casos reprovados : 1`, `casos pulados : 2`, `interrompida em : qa_docs_aliases_p4_test.sh (primeiro erro; 3 arquivo(s) nao executado(s))`, `resultado : REPROVADA` |
| `bash tests/run.sh qa_integridade` | `casos aprovados : 27`, `casos reprovados : 0`, `APROVADA` |
| `bash tests/run.sh qa_robustez` | `casos aprovados : 20`, `casos reprovados : 0`, `APROVADA` |
| `bash tests/run.sh sync_test` | `casos aprovados : 85`, `casos reprovados : 0`, `APROVADA` |
| P3 sem alteração: `qa_cache_unico_p3_test.sh qa_exclusao` e `… qa_guarda` | `ok=11 nao_ok=0` e `ok=4 nao_ok=0` |
| `bash scripts/verificar-remocao-de-casos.sh` | `906 -> 931 caso(s)`, `nenhuma reducao nao declarada` |
| `shellcheck` nos 9 arquivos de produto alterados e no arquivo do QA | Saída 0, sem apontamento |

A interrupção vem do caso 7 do QA, que reprova pelo defeito QA-P4-01. Nenhum caso do Senior Developer nem de fase anterior reprovou. Os 3 arquivos que não rodaram por causa da interrupção foram executados um a um, todos verdes. Uma primeira execução tinha parado em `composicao_test.sh`: o arquivo do QA contava com `grep -c` fora de `_harness_contar` (auditoria do próprio harness). O QA corrigiu o próprio arquivo e reexecutou do início.

## Resultado da validação

- Itens funcionais (RF-64, RF-41(b) com O-1 e DIV-30, RF-54(e)(f)(g)): **aprovados**, sem regressão.
- Comentários de `lib/http.sh` e `lib/transfer.sh`: só comentários, confirmado.
- Poda do pacote: sem link vivo, e os scripts e hooks saem 0.
- **RNF-34 (TC-DOC-01): reprovado** por QA-P4-01 e QA-P4-02.

## Falhas documentadas

| Id | Arquivo:linha | Achado | Critério | Correção esperada | Severidade |
|---|---|---|---|---|---|
| QA-P4-01 | `lib/config.sh:6-8` e `lib/auth.sh:61-63` | `lib/config.sh` diz "ESTA E A UNICA ESCRITA PERSISTENTE DE TODO O PROJETO (PRJ-DEC-07). Nao ha cache, indice, cursor…". `lib/auth.sh` diz que o token em memória "mantem a unica escrita persistente do projeto sendo o arquivo de credencial". As duas frases contradizem RF-38, RF-61 e RNF-26, pois a memória do `sync` e o cache do `upload` gravam em `lib/state`. A lista fechada de buscas do TC-DOC-01 não pega essas frases, mas o caput do RNF-34 proíbe cabeçalho de `lib/*.sh` que afirme o contrário do código | RNF-34 (caput) | Reescrever os dois trechos com o porquê atual. Exemplo: "`lib/config` é a única escrita da credencial; o estado persistente restante passa só por `lib/state`" | **Maior** (documentação; sem efeito funcional) |
| QA-P4-02 | `docs/arquitetura/system-design.md:486` | A linha "Ausencia deliberada de estado local persistente *(v0.3)*" da tabela de decisões continua sem marca de revogação na própria linha. RNF-34(f) pede essa marca explicitamente, e o diff do System Design só acrescentou linhas | RNF-34(f) | Marcar a linha como revogada ou superada (v1.5, `lib/state`), sem apagar o histórico | **Menor** (pode ser do `documentation-writer`) |

### Observações sem reprovação (risco residual, para o Tech Lead)

- **O-QA-1, comportamento anterior à fase.** No `--pull`, raiz remota inexistente (`path/not_found`) é tratada como origem vazia (`lib/sync.sh:198`). Com `--mirror --yes` a recusa é a de origem vazia (testado, código 14). Com `--allow-empty-source`, porém, um erro de digitação no caminho remoto espelha o vazio e apaga o destino local. Isso está de acordo com RF-41(b) e RF-53(e), porque o operador declarou a origem vazia, mas a mensagem não distingue "vazia" de "inexistente". Fica como sugestão ao BA e não como defeito. O caso P3 `qa_guarda_origem_vazia_no_receber_e_raiz_remota_inexistente` testa, na verdade, um `internal_error`: o duplo da P3 troca o corpo quando há `listagem_codigo`. O nome do caso promete mais do que ele prova.
- **O-QA-2.** O achado 2 do parecer TDD (memória ausente sem `--confirmar` cai em RF-48 antes do plano) continua sendo decisão do Tech Lead. O caso 9 do QA usa `--yes` e prova a recusa pelo plano sem memória nos dois sentidos.
- **O-QA-3.** A memória histórica (`.github/agents/memoria/historico/`) cita caminhos de skills removidas. São registros imutáveis e não links, mas uma futura validação de links que inclua `historico/` vai acusá-las.

## Devolução ao agent

Ao Senior Developer (QA-P4-01) e ao `documentation-writer` ou Senior Developer (QA-P4-02), conforme decisão do Tech Lead. Depois da correção, reexecutar `bash tests/run.sh qa_docs_aliases` e a suíte inteira a partir do início. Os casos 7 e 8 do QA são o critério de saída e não podem ser alterados para passar.

## Histórico de ciclos QA → Developer

| Ciclo | Data | Resultado | Achados |
|---|---|---|---|
| 1 | 2026-10-19 | Reprovado (só RNF-34) | QA-P4-01 (maior), QA-P4-02 (menor) |

## Critério de escalonamento

Mais de 3 ciclos de reprovação levam ao solicitante. Este é o ciclo 1.

## Divergências (regra 24)

Nenhuma divergência nova entre requisitos e código funcional. A lista "contradições remanescentes" do RNF-34 (a a f) estava incompleta: não trazia QA-P4-01. Recomenda-se ao BA acrescentar `unica escrita persistente` às buscas do TC-DOC-01.

## Aprovação do solicitante (regra 12)

A suíte `qa_docs_aliases_p4_test.sh` (16 casos) e os resultados acima ficam **submetidos ao aceite do solicitante**, pelo Tech Lead. O aceite deve ser registrado como `tipo: aceite`.

## Veredito

**Reprovado no ciclo 1, restrito à documentação (RNF-34).** Os aliases, a guarda de origem vazia pelo plano e a localidade da comparação estão aprovados, sem regressão e com 7 de 7 mutantes mortos. A entrega volta para corrigir QA-P4-01 e QA-P4-02, que são edições de comentário e de uma linha do System Design, seguidas da reexecução da suíte do início.

## Ciclo 2 do QA (2026-10-19) — revalidação sobre a correção de QA-P4-01 e QA-P4-02

### Status dos achados do ciclo 1

| Id | Status | Evidência |
|---|---|---|
| QA-P4-01 | **Corrigido** | `git diff -w -U0 -- lib/config.sh lib/auth.sh`: as linhas alteradas que não são comentário nem branco somam **0**. O texto novo diz que a credencial é o único arquivo com segredo e que `lib/state` guarda a memória de hash sem segredo, o que é coerente com RF-38 e RF-61. O caso 7 do QA passou |
| QA-P4-02 | **Corrigido** | `docs/arquitetura/system-design.md:486` traz "🔴 **REVOGADA (registro historico)**" na própria linha. O caso 8 do QA passou |

### Execução

| Comando | Resultado literal |
|---|---|
| `sh scripts/alteracoes-externas.sh --detectar` (antes) | Saída 0, sem alteração externa |
| `bash tests/run.sh < /dev/null` | `arquivos executados : 27`, `casos aprovados : 935`, `casos reprovados : 0`, `casos pulados : 2`, `resultado : APROVADA` |
| Casos `qa_p4_*` nessa execução | 16 `ok`, 0 `not ok` |

A suíte do QA ficou igual ao ciclo 1, sem caso alterado. O sha256 de `tests/integracao/qa_docs_aliases_p4_test.sh` continua `adf7f5c2b33b63ce7278e0f44e458dd3fde67c7f7ec7cd67d4ea09042a373fc1`. Os mutantes do ciclo 1 não foram refeitos, porque a correção só mexeu em comentário e documento.

### Histórico de ciclos (atualizado)

| Ciclo | Resultado | Achados |
|---|---|---|
| 1 | Reprovado (RNF-34) | QA-P4-01, QA-P4-02 |
| 2 | **Aprovado** | Nenhum novo; os dois anteriores foram corrigidos |

As observações O-QA-1 a O-QA-3 continuam como risco residual para o Tech Lead e não reprovam.

### Veredito do ciclo 2

**Aprovado.** RF-64, RF-41(b) com O-1 e DIV-30, RF-54(e)(f)(g) e RNF-34 estão atendidos, com a suíte inteira verde (935/0/2). A suíte do QA (16 casos) aguarda o aceite do solicitante (regra 12).
