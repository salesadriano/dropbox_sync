# Evidencia de testes — suporte a FreeBSD

| Campo | Valor |
|---|---|
| Demanda | `suporte-freebsd` (porte G) |
| Registro de entrega | [2026-10-24-1153-registro-suporte-freebsd.md](2026-10-24-1153-registro-suporte-freebsd.md) |
| Gate | `ai-team:protocolo-tdd` (regras 1 a 9) |
| Atualizado | 2026-10-26 (ciclo final: T5, RF-173, RF-171(a) emendado, RF-173(e)) |

## Estrategia

A suite roda em Linux. Os dubles em `tests/duplos/freebsd/bin/` (`chmod`, `stat`, `find`, `sha256`, `head`, `mktemp`, entre outros) imitam a interface dos utilitarios do FreeBSD e rejeitam o que o GNU aceita; `tests/support/freebsd.sh` os poe a frente do `PATH`. A base do FreeBSD sem `sha256sum`/`shasum` e simulada por `PATH` restrito.

O que o duble nao reproduz fica para o roteiro `docs/testes/roteiro-freebsd.md` (TC-FBSD-24), executado pelo solicitante (`DIV-355`). Duas lacunas dos duplos foram achadas no FreeBSD real e corrigidas nesta demanda: o `head -c` que le alem de N (defeito a) e o `--stderr` do curl, que so o curl real reproduz (defeito b). Para o `head`, o duble passou a reproduzir o consumo excedente; para o `--stderr`, o teste usa o curl real (`http_fd_curl_real`, `qa_download_curl_real_b16`).

## Red antes do green

Medido pelo Tech Lead em copia `git archive` do commit anterior a cada tarefa, com os testes novos copiados e, quando o runner parava no primeiro erro, desligando so na copia o caso ja visto.

### Ciclos 1 e 2 (T1 a T4 e conformidade)

| Arquivo de teste | Caso | Falha vista no codigo anterior |
|---|---|---|
| `tests/unit/chmod_portavel_test.sh` | `gravacao_da_credencial_conclui_com_chmod_bsd` | status 3, `chmod: --: No such file or directory` |
| idem | `nenhum_chmod_do_produto_poe_dois_hifens_depois_do_modo` | as 4 linhas acusadas |
| idem | `preparo_do_diretorio_de_estado_conclui_com_chmod_bsd` | status 1 |
| idem | `recebimento_aplica_o_modo_do_alvo_com_chmod_bsd` | erro `chmod: --` engolido pelo produto |
| `tests/unit/atributos_portavel_test.sh` | `identidade_do_arquivo_vem_preenchida_e_estavel_com_stat_bsd` | status 4 |
| idem | `listagem_de_retomada_calcula_a_idade_pelo_mtime_com_stat_bsd` | idade 0 em vez de 9 |
| idem | `recebimento_preserva_o_modo_do_alvo_com_stat_bsd` | 644 em vez de 640 |
| idem | `modo_mantem_suid_e_sticky_e_coincide_nas_duas_formas` | 600 em vez de 4600; depois 444 em vez de 4044 |
| idem | `forma_aprendida_por_sonda_unica_uma_leitura_uma_chamada` | `stat -f` disparado para arquivo ausente |
| `tests/integracao/diagnostico_test.sh` | `fbsd15_estado_0700_com_stat_bsd_nao_reporta_permissao_falsa` | "pertence a outro usuario" |
| `tests/unit/poda_portavel_test.sh` | auditoria de `-printf`, poda de retomada e de cursor | 2 linhas acusadas; 1005 em vez de 1000; 105 em vez de 100 |
| `tests/unit/resumo_freebsd_test.sh` | so `sha256`; `mktemp` com 3 X | resumo vazio; status 0 em vez de 2 |
| `tests/unit/plataforma_freebsd_test.sh` | recusa sem `/dev/fd`; descritor com outro inode | status 0 em vez de 3 |
| `tests/integracao/instalador_diagnostico_freebsd_test.sh` | sugestao `pkg`; mensagem neutra; backend do resumo; "nao verificado" | `apt` sugerido; trechos ausentes |

Ja passavam (regressao): so `openssl` nos dois formatos, `wc` com largura 8, `install.sh --prefix` com os dubles, preflight sem nenhum resumo.

### Ciclo final (T5 e RF-173)

| Commit | Arquivo de teste | Caso | Situacao do red |
|---|---|---|---|
| `b797ae8` (T5, DIV-352) | arquivo de teste a conferir com `git show --stat b797ae8` | conferencia pelo descritor no lugar da recusa sem `fdescfs` | Red nao consta em parecer desta demanda |
| `f614b02` (RF-173) | `tests/integracao/qa_leitura_exata_b14_test.sh` | leitura exata sob o duble do `head` que consome alem de N | Red medido no FreeBSD do solicitante (Prompt 6, defeito a); parecer de `protocolo-tdd` a anexar |
| `5714175` (RF-171(a)) | `tests/unit/http_fd_curl_real_test.sh` | `.part` com conteudo pelo descritor, com curl real | Red medido com curl real 8.18 no Linux (Prompt 11: `.part` com 0 bytes); parecer a anexar |
| `dd55b20` (RF-173(e)) | auditoria `regex_portavel` e `tests/integracao/qa_regex_portavel_b17_test.sh` | regex com repeticao acima de 255 | Red medido no FreeBSD do solicitante (Prompt 13); parecer a anexar |

## Execucoes

| Comando | Resultado | Situacao |
|---|---|---|
| `bash tests/run.sh` no commit `f614b02` | 96 arquivos; 2568 aprovados; 0 reprovados; 4 pulados; 2795 s | Ultima execucao verde registrada |
| `bash tests/run.sh` no commit `7f8e402` (ciclo 2) | 92 arquivos; 2535 aprovados; 0 reprovados; 4 pulados | Historico |
| `sh scripts/suite-completa.sh` no commit final | pendente: suite do commit final | Tech Lead completa apos o registro |
| `sh scripts/lint.sh <arquivo>` em cada arquivo tocado | sem apontamento (ciclos 1 e 2) | Repetir nos arquivos das T5 e RF-173 |
| `bash scripts/verificar-remocao-de-casos.sh` | nenhuma reducao nao declarada (1 remocao declarada no commit da T1) | Repetir no commit final |

### Suites de QA

Sha256 abreviados conforme a [entrada de aceite](../../.github/agents/memoria/entradas/2026-10-24-1153-aceite-testes-qa-freebsd.md); sha256 completo a conferir com `sha256sum` no arquivo.

| Suite | Casos | Aprovacao | sha256 (abreviado) |
|---|---|---|---|
| `tests/integracao/qa_freebsd_b13_test.sh` | 10 | Reaprovado 2026-10-25 | `20420830…711d006b` |
| `tests/integracao/qa_docs_aliases_p4_test.sh` | - | Reaprovado 2026-10-24 | `17192612…708467` |
| `tests/integracao/qa_trava_tmp_b2_test.sh` | - | Reaprovado 2026-10-25 (`qa_b2_01` corrigido) | `2114eaa2…df6d3333` |
| `tests/integracao/qa_consulta_diagnostico_b1_test.sh` | - | Reaprovado 2026-10-26 | `9a0dab8d…e661920a` |
| `tests/integracao/qa_debug_transferencias_b12_test.sh` | - | Reaprovado 2026-10-26 | `fa2d971d…e2fca987` |
| `tests/integracao/qa_leitura_exata_b14_test.sh` | 10 | Aprovado 2026-10-26 | `c7de4ca5…76c920b8` |
| `tests/integracao/qa_download_curl_real_b16_test.sh` | 7 | Aprovado 2026-10-26 | `d0c1dd49…5af129` |
| `tests/integracao/qa_regex_portavel_b17_test.sh` | 19 | Aprovado 2026-10-26 | `1406718c…138a015d8` |

Historico: `qa_freebsd_b13_test.sh` tinha 5 casos e sha256 `fb7e9191…ca7488` antes da reaprovacao de 2026-10-25 (decisao "Conferir pelo descritor" removeu o caso da recusa sem `fdescfs` e acrescentou 6 casos). Os casos de `qa_freebsd_b13` e `qa_trava_tmp_b2` nao estao confirmados nesta redacao; conferir com `bash tests/integracao/<arquivo>`.

### Validacao no FreeBSD real (TC-FBSD-24)

Executada pelo solicitante no FreeBSD 15.1-RELEASE-p3 (UFS), nao em 13 ou 14. Detalhes e saidas sanitizadas no [log de prompt](../prompts/2026-10-24_1153_suporte-freebsd.md) (Prompts 2 a 17). Resumo: credencial 600 (Prompts 4 e 5); upload de 388 MiB conferido (Prompts 6 a 7, 14 a 16); download de pasta e `verificar` com 4 iguais (Prompts 9 e 10); download retomavel com `206` (Prompts 11 e 12); upload retomado do bloco 5 (Prompts 13 e 14); secao 7 do roteiro (Prompt 17).

## Veredito

**Aprovado com ressalvas**, com as seguintes pendencias:
- suite completa do commit final (`scripts/suite-completa.sh`): pendente;
- validacao no FreeBSD 13 e 14: pendente (executada apenas no 15.1);
- parecer de `protocolo-conformidade` para os commits pos-`de4b66f`: ciclo 3 aprovado (ver parecer de conformidade);
- red do ciclo final: `f614b02` (duble do `head`: upload "foram lidos 8392761" de 8400953; content_hash divergente), `5714175` (caso do `.part` com prefixo reprovou; mutacao do QA: `.part` com 0 de 6291457 bytes), `dd55b20` (auditoria acusou `lib/state.sh:1456`, `:1893`, `:1895`).

Instabilidades observadas e nao atribuidas ao diff: `state_trava_test::leitor_concorrente_nunca_ve_trava_vazia_ou_parcial` (RSK-DSP-01, preexistente). A falha de `qa_trava_tmp_b2::qa_b2_01` era defeito do teste (aceitava so uma trava), corrigido em `cae6e36` e reaprovado em 2026-10-25.
