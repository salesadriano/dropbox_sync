# Subdiretorio chamado `-` deixa de corromper e desviar a travessia local

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "check error" (`dbx --debug sync --enviar -p --origem /mnt/e/. --destino /Amac --espelhar --confirmar` na 2.3.1, erro aritmetico em `commands/sync.sh` linha 2192 durante "enumerando diretorios locais") |
| Porte | M - defeito critico em producao e guarda destrutiva (enumeracao da arvore errada sob `--espelhar`); `sh scripts/porte.sh`: 83 linhas de codigo, `porte: M` |
| Log de prompt | `docs/prompts/2026-11-02_2100_diretorio-chamado-hifen.md` |
| Issues | nenhuma |
| Branch / base | `feature/diretorio-chamado-hifen` sobre `origin/develop` @ `4f5be61` |
| Agents | Tech Lead (diagnostico, implementacao e gates), QA Expert (validacao independente) |
| Data | 2026-11-02 |

## 2. Causa ou decisao

- Causa (reproduzida em bash 5.3 e com o cenario do teste): `cd -- -` NAO trata `-` como nome, mesmo apos `--`. O bash o le como `OLDPWD`, volta ao diretorio anterior e imprime o destino no stdout. Na travessia (`lib/walk.sh`), um subdiretorio chamado `-` visitado logo depois do irmao `SL2801` leva o `cd` de volta a `.../sl2801/SL2801`; a linha impressa entra na lista `n<TAB>caminho\0` e o registro seguinte vira `"<caminho absoluto>\n0"`, o operando do erro aritmetico. Sem o erro, a descida seguiria na pasta errada (enumeracao incorreta sob `--espelhar`). A correcao de `CDPATH` (`DIV-392`) nao cobre este caso: o `-` e reinterpretado pelo proprio `cd`, sem variavel de ambiente.
- Decisao: todo `cd` de nome relativo da travessia passa a `cd -- "./$nome"` (cinco pontos em `lib/walk.sh`). `./nome` e a unica grafia que o bash nunca reinterpreta e preserva a descida por inode (`DP-26`). Alternativa descartada: tratar `-` como caso especial (`[[ $nome == - ]]`), que deixaria de fora qualquer outra grafia futura e espalharia a excecao pelos cinco pontos. `DIV-393` registrada e resolvida.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/walk.sh` | Alterado: `cd -- "./$nome"` e `cd -- "./$comp"` nos cinco `cd` de nome relativo; nota no cabecalho | +13/-6 |
| `tests/unit/walk_test.sh` | Alterado: `teste_diretorio_chamado_hifen_e_um_nome_e_nao_o_oldpwd`, `teste_enumeracao_de_diretorios_com_pasta_hifen_mantem_as_contagens_numericas` | +46/-0 |
| `tests/integracao/sync_test.sh` | Alterado: `teste_subdiretorio_chamado_hifen_nao_suja_nem_desvia_a_enumeracao` | +18/-0 |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | v1.37, `DIV-393` | doc |
| `docs/prompts/2026-11-02_2100_diretorio-chamado-hifen.md` | Novo | doc |

Total de linhas de codigo (producao e teste, sem documentacao): **83**.

## 4. Testes rodados

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `tests/unit/walk_test.sh` | `lib/walk.sh` | `bash tests/run.sh walk_test.sh < /dev/null` | 15 | 15 | 0 | nao exibida pelo runner |
| `tests/integracao/sync_test.sh` (o filtro tambem seleciona `qa_cdpath_sync`-afins: 2 arquivos) | `lib/walk.sh` via `commands/sync.sh` | `bash tests/run.sh sync_test.sh < /dev/null` | 100 | 100 | 0 | nao exibida pelo runner |

- Red observado: `teste_diretorio_chamado_hifen_e_um_nome_e_nao_o_oldpwd` reprovou antes da correcao (`Bail out!`, 13 casos nao executados); `teste_subdiretorio_chamado_hifen_nao_suja_nem_desvia_a_enumeracao` reprovou antes da correcao (`not ok 76`, 83 aprovados, 1 reprovado).
- Parada no primeiro erro (Regra 9): o runner interrompe no primeiro arquivo com falha (conferido no red); execucao final sem interrupcao.
- Barreiras estaticas: `shellcheck -x -s bash lib/walk.sh tests/unit/walk_test.sh` sem aviso.
- Testes de seguranca e acesso (Regra 6): a guarda destrutiva do `--espelhar` e o cenario do teste de integracao (origem lida pelo nome, irmao nao relido); nenhuma rota, sessao ou segredo tocado.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: CLI sem formulario.
- Suite completa local no push para a PR: ver secao 8 (preenchida no push).

## 5. Gates

| Gate | Skills aplicadas | Achados | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; checklist aplicado integralmente | nenhum: red antes do green nos tres casos novos, selecao pelos itens afetados, parada no primeiro erro | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + boas praticas de shell; checklist aplicado integralmente | nenhum: correcao confinada ao adaptador de travessia, sem contrato publico tocado, nenhum `cd` de nome relativo restante fora de `lib/walk.sh` (`grep` em `bin`, `lib`, `commands`) | Aprovado |

- Ciclo: 1
- `sh scripts/alteracoes-externas.sh --detectar`: exit 0 antes dos gates (so os arquivos desta demanda, todos registrados)

## 6. QA

- Validacao independente (QA Expert, ciclo 1): `docs/reviews/2026-11-02-2100-validacao-qa-diretorio-chamado-hifen.md`. Suite propria `tests/integracao/qa_diretorio_hifen_test.sh`, 8 casos (pasta `-` na raiz, como primeiro e ultimo irmao, aninhada `a/-/b`, pastas `--`/`-x`/`-` juntas, enumeracao `sl/-` com `sl/SL`, arquivo chamado `-`, pasta `-` so do destino sob `--espelhar`), com duble de `curl` proprio e plano conferido por contagem exata de `transferir=`/`apagar=`. sha256 `014c29de61287029d44fbc01d8ba53944ddde11c4943df1b309dfd65ebe38833` (conferido pelo Tech Lead).
- Vermelho da suite do QA: contra `lib/walk.sh` de `origin/develop` reprovam 6 de 8 (os dois que passam, arquivo `-` e pasta `-` so do destino, ficam como guarda de regressao); com a correcao, `bash tests/run.sh qa_diretorio_hifen_test.sh < /dev/null`: 8 aprovados, 0 reprovados, 0 pulados (reexecutado pelo Tech Lead: 8/8). `qa_cdpath_test.sh`: 8/8.
- Achados: nenhum bloqueante ou maior; 2 menores informativos (nenhum caso isola o `cd` de `_dbx_walk_ciclo_dir` sob ciclo de vinculo simbolico com pasta `-`; o ramo so do destino nao exercita `cd` local). Sem correcao exigida.
- Inventario de testes (regra 51): 3 linhas de casos em `walk_test.sh` e `sync_test.sh` e secao nova da suite do QA em `docs/testes/inventario-de-testes.md`; `sh scripts/inventario-de-testes.sh --check`: `arquivos: 116 | casos: 2908 | divergencias: 0`.
- Veredito do QA: Aprovado, 2026-11-02.

## 7. Riscos e rollback

- Riscos residuais: a linha legada `support/bash-4.2` (2.3.1-bash42) tem os mesmos cinco `cd` e o mesmo defeito; correcao pendente de decisao do solicitante (owner: Tech Lead).
- Impacto: Nenhum em contrato, CLI, schema ou dependencia; so o adaptador de travessia.
- Rollback: `git revert` do commit basta.

## 8. Links e aceites

- Entradas de memoria: a gravar no aceite da suite do QA (regra 12).
- Documentacao sincronizada: `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` (v1.37), `docs/testes/inventario-de-testes.md`.
- Commit(s): (no fechamento)
- PR: (no fechamento)
- Tech Lead: (no fechamento)
- Solicitante: aceite da suite `qa_diretorio_hifen_test.sh` por sha256 pendente.
