# Evidencia de testes — suporte a FreeBSD

| Campo | Valor |
|---|---|
| Demanda | `suporte-freebsd` (porte G) |
| Registro de entrega | [2026-10-24-1153-registro-suporte-freebsd.md](2026-10-24-1153-registro-suporte-freebsd.md) |
| Gate | `ai-team:protocolo-tdd` (regras 1 a 9) |

## Estrategia

A suite roda em Linux. Os dubles em `tests/duplos/freebsd/bin/` (`chmod`, `stat`, `find`, `sha256`) imitam a interface dos utilitarios do FreeBSD e rejeitam o que o GNU aceita; `tests/support/freebsd.sh` os poe a frente do `PATH`. A base do FreeBSD sem `sha256sum`/`shasum` e simulada por `PATH` restrito. O que o duble nao reproduz (`/dev/fd` sem `fdescfs`, `/proc` ausente, formatos reais do `stat`) fica para o roteiro `docs/testes/roteiro-freebsd.md` (TC-FBSD-24), executado pelo solicitante (`DIV-355`).

## Red antes do green

Medido pelo Tech Lead em copia `git archive` do commit anterior a cada tarefa, com os testes novos copiados e, quando o runner parava no primeiro erro, desligando so na copia o caso ja visto.

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

## Execucoes

| Comando | Resultado |
|---|---|
| `bash tests/run.sh` (apos o ciclo 2 da conformidade) | 92 arquivos, 2535 aprovados, 0 reprovados, 4 pulados |
| `bash tests/run.sh qa_freebsd_b13` (QA) | `# resumo ok=5 nao_ok=0 pulados=0` |
| `sh scripts/lint.sh <arquivo>` em cada arquivo tocado | sem apontamento |
| `bash scripts/verificar-remocao-de-casos.sh` | nenhuma reducao nao declarada (1 remocao declarada no commit da T1) |

Instabilidades observadas e nao atribuidas ao diff: `state_trava_test::leitor_concorrente_nunca_ve_trava_vazia_ou_parcial` (RSK-DSP-01, preexistente) e `qa_trava_tmp_b2::qa_b2_01` (2 falhas na suite inteira; passou 4 vezes isolado, numa copia instrumentada e nas rodadas seguintes; causa nao confirmada).

## Veredito

**Aprovado com ressalvas**: a validacao no FreeBSD real (TC-FBSD-24) e a suite completa oficial do push estao pendentes.
