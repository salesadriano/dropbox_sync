# Trava valida deixa de sair como ilegivel numa localidade traduzida

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | Log de producao (Oracle Linux 7, root, 2.3.3-bash42): nova execucao recusada com `erro: trava ilegivel: /root/.local/state/dbx/trava-b5a4...` e o pedido de `rm` manual |
| Porte | M - defeito critico em producao (nenhum `sync` ou `verificar` do par roda enquanto a trava existir); `sh scripts/porte.sh`: 2 arquivos, 112 linhas de codigo, `porte: M` |
| Log de prompt | `docs/prompts/2026-11-03_2001_tipo-de-arquivo-sem-traducao.md` |
| Issues | nenhuma |
| Branch / base | `feature/tipo-de-arquivo-sem-traducao` sobre `origin/develop` @ `fc3ba8f`; a mesma correcao na linha legada em `feature/tipo-de-arquivo-sem-traducao-bash42` sobre `origin/support/bash-4.2` @ `ba0a110` (`lib/atributos.sh` difere so na expansao de `seguir`, preservada) |
| Agents | Tech Lead (diagnostico, implementacao e gates), QA Expert (validacao independente) |
| Data | 2026-11-03 |

## 2. Causa ou decisao

- Causa (medida em conteiner `oraclelinux:7`, bash 4.2.46, coreutils 8.22 com as traducoes): o tipo do arquivo vem de `stat -c %F`, cuja saida e traduzida pela localidade (`LANG=pt_BR.UTF-8` -> `arquivo comum`; `es_ES.UTF-8` -> `fichero regular`). `dbx_atributo_fd tipo` so reconhece `regular*`, entao `dbx_fd_regular_proprio` falha e `_dbx_state_trava_ler` devolve "ilegivel" para TODA trava ja existente: a viva deixa de dizer quem a detem e a orfa deixa de ser retomada (`RF-69`). O `local LC_ALL=C` de `_dbx_state_trava_ler` nao chega ao `stat`: variavel local sem `export` nao vai ao ambiente do filho. Reproducao com o codigo da `v2.3.3-bash42`: a mesma trava sai legivel com `LANG=en_US.UTF-8`, ilegivel com `LANG=pt_BR.UTF-8` e legivel com `LANG=pt_BR.UTF-8 LC_MESSAGES=C`.
- Por que os testes nao pegavam: as maquinas de teste nao tem as traducoes do coreutils; o `stat` responde em ingles em qualquer `LANG`.
- Decisao (`DIV-395`): todo `stat` de `lib/atributos.sh` roda com `LC_ALL=C` no ambiente do proprio comando. O modulo ja e o unico ponto com formato de `stat` (auditado por `teste_nenhum_stat_com_formato_fora_do_auxiliar`), entao a correcao cobre todo o produto. Os demais formatos sao numericos e saem iguais; a sonda de forma (`-c %a` / `-f %Lp`) tambem fica sob `C`. Alternativa descartada: trocar `%F` por `%f` (modo em hexadecimal) mudaria o contrato interno do campo `tipo` e nao teria equivalente direto no `%HT` do BSD.
- Contorno ate a atualizacao, dado ao solicitante: `LC_MESSAGES=C` no ambiente (ou `export LC_MESSAGES=C` no perfil do root), depois de confirmar que nenhum `sync` do par esta rodando.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/atributos.sh` | Alterado: `LC_ALL=C` nas 7 chamadas de `stat`; comentario do motivo | +11/-7 |
| `tests/unit/atributos_portavel_test.sh` | Alterado: duble de `stat` que traduz como o coreutils (precedencia `LC_ALL`, `LC_MESSAGES`, `LANG`) e 4 casos | +94/-0 |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | v1.40, `DIV-395` | doc |
| `docs/prompts/2026-11-03_2001_tipo-de-arquivo-sem-traducao.md` | Novo | doc |

## 4. Testes rodados

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos |
|---|---|---|---|---|---|
| `tests/unit/atributos_portavel_test.sh` | `lib/atributos.sh` | `bash tests/run.sh atributos_portavel_test.sh < /dev/null` | 15 | 15 | 0 |
| idem, linha legada no bash 4.2.46 real | idem | `sh scripts/suite-bash42.sh atributos_portavel_test.sh` | 15 | 15 | 0 |
| `state_test`, `qa_trava_tmp_b2_test`, `perfis_trava_raiz_test` | leitura e retomada da trava | `bash tests/run.sh <arquivo> < /dev/null` | 24, 23, 10 | todos | 0 |
| `diagnostico_test` | `diagnostico` le a trava e atributos | idem | 17 | 17 | 0 |
| `json_test`, `harness_test` | auditorias de `lib/` e do harness | idem | 66, 23 | todos | 0 |

- Red observado: sem a correcao em `lib/atributos.sh`, `teste_tipo_do_caminho_e_regular_com_stat_traduzido_e_lc_all_exportado` reprova com `esperado: [regular file]`, `obtido: [arquivo comum]` (o runner para ali, Regra 9).
- Prova no ambiente real: conteiner `oraclelinux:7` com as traducoes do coreutils, codigo desta branch legada: `stat -c %F` segue `arquivo comum` e a trava sai legivel com `LANG=pt_BR.UTF-8` e com `LC_ALL=pt_BR.UTF-8`.
- Barreiras estaticas: `sh scripts/lint.sh lib/atributos.sh tests/unit/atributos_portavel_test.sh` sem achado nas duas linhas (`SC2030`/`SC2031` justificados no cabecalho: a localidade muda so no subshell do caso).
- Testes de seguranca e acesso (Regra 6): a conferencia de dono e tipo do descritor (`RF-171`) volta a valer em qualquer localidade; nenhuma permissao afrouxada.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: CLI sem formulario.
- Linha legada, no bash 4.2.46 real (`sh scripts/suite-bash42.sh <arquivo>`): `atributos_portavel` 15/0, `state_test` 24/0, `qa_trava_tmp_b2` 21/0 (2 pulados), `perfis_trava_raiz` 10/0, `diagnostico_test` 16/0 (1 pulado); no host: `json_test` 62/0, `harness_test` 23/0.
- Suite completa local no push para a PR: secao 8.

## 5. Gates

| Gate | Skills aplicadas | Achados | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9 | nenhum: red antes do green, duble no limite do sistema (o utilitario externo), selecao pelos itens afetados mais as auditorias | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + boas praticas de shell | nenhum: correcao no unico auxiliar de atributos; sem contrato, flag, schema ou dependencia | Aprovado |

- Ciclo: 1

## 6. QA

- Pendente: validacao independente do QA Expert.

## 7. Riscos e rollback

- Riscos residuais: outros utilitarios externos cuja saida textual o produto interprete podem ter o mesmo risco de traducao; a auditoria do QA desta demanda cobre a varredura.
- Impacto: nenhum em contrato, CLI, schema ou dependencia.
- Rollback: `git revert` do commit basta.

## 8. Links e aceites

- Preenchidos no fechamento.
