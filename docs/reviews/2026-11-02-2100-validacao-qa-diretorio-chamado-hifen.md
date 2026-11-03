# Validacao independente do QA: diretorio-chamado-hifen (porte M)

Data: 2026-11-02 | Papel: QA Expert | Escopo: `lib/walk.sh` (todo `cd` de nome relativo passou a `cd -- "./$nome"`), `tests/unit/walk_test.sh`, `tests/integracao/sync_test.sh`, requisito `DIV-393`. Log: `docs/prompts/2026-11-02_2100_diretorio-chamado-hifen.md`.

## Veredito: APROVADO (sem achado bloqueante nem maior; 2 menores informativos)

## Suite independente
`tests/integracao/qa_diretorio_hifen_test.sh` (8 casos; `bash tests/run.sh qa_diretorio_hifen_test.sh` -> 8 aprovados, 0 reprovados). sha256 `014c29de61287029d44fbc01d8ba53944ddde11c4943df1b309dfd65ebe38833` (arquivo novo, marcado com `git add -N` para o detector e o inventario).

Metodo: `sync --enviar --dry-run` contra duplo de `curl`, com arvores de nomes `-`, `--` e `-x`. A conferencia e por **contagem exata** do plano (`transferir=`, `apagar=`, ordenado com `LC_ALL=C`): cada arquivo aparece uma vez, nenhum irmao e repetido ou perdido, nenhum caminho absoluto do `cd` vira item, e o stderr nao tem "syntax" nem "arithmetic". Casos: pasta `-` na raiz; `-` como primeiro irmao; `-` como ultimo irmao (`!`, `+`, `-`); aninhada (`a/-/b`, `a/-/-`, irmao `a/irmao`); `-` so do destino sob `--espelhar` (listagem remota `/r/-/x.txt`: exclusao planejada uma vez); arquivo (nao pasta) `-`; pastas `--`, `-x` e `-` juntas; `sl/-` e `sl/SL` sob `--espelhar` (o irmao nao e lido como `-`).

## Vermelho contra a base
Copia de `bin lib commands` com `lib/walk.sh` de `origin/develop` (apontada por `DBX_QA_EXEC`), cada caso isolado (o runner para no primeiro erro, entao rodei um a um pelo filtro do arquivo): **6 de 8 reprovam sem a correcao** (raiz, primeiro, ultimo, aninhada, `--`/`-x`/`-`, enumeracao de diretorios) e todos aprovam com ela. Os 2 que passam nos dois lados: `arquivo_chamado_hifen_nao_e_pasta` (arquivo nao e descido por `cd`) e `pasta_hifen_so_do_destino_sob_espelhar` (a pasta `-` so existe no remoto; nao ha `cd` local nela). Ficam como guardas de regressao.

## Achados
- Menor (informativo): o ramo so do destino (`dbx_walk_ciclo` / `_dbx_walk_ciclo_dir`) so se exerce com `-` quando a pasta tambem existe localmente; o caso so-do-destino prova que o plano de exclusao sob `-` sai correto, mas nao e vermelho sem a correcao. Os 6 casos vermelhos cobrem a descida local; o `cd` corrigido nas linhas de `_dbx_walk_ciclo_dir` nao teve caso proprio que o isole (limitacao registrada; recomenda-se, se o solicitante quiser, um caso com ciclo de vinculo simbolico sob pasta `-`).
- Menor: o duplo de `curl` e proprio da suite (nao reutiliza o do `sync_test`), por independencia; o custo e duplicacao de ~35 linhas.
- Nao aplicavel: Cypress/E2E (CLI shell); sem gatilho de formulario nem de seguranca de acesso.

## Checagens do diff
- Todas as 6 ocorrencias de `cd -- "$x"` em `lib/walk.sh` receberam `./`; o comentario explica a causa (`cd -- -` = OLDPWD com eco no stdout) e que `./nome` tambem dispensa CDPATH (DIV-392).
- Os testes do Tech Lead (`walk_test`, `sync_test`) aprovam; o caso de `sync_test` ja cobre `sl/SL` + `sl/-`.

## Execucao seletiva (modulos: `walk`, `commands/sync.sh`, `qa_diretorio_hifen`, `qa_cdpath`)
- `walk_test.sh`: 15 aprovados, 0 reprovados; `sync_test.sh`: 100 aprovados, 0 reprovados; `qa_diretorio_hifen_test.sh`: 8/0; `qa_cdpath_test.sh`: 8/0. `shellcheck -x -s bash` na suite nova: sem aviso.

## Inventario
`docs/testes/inventario-de-testes.md` atualizado (resumo, secoes de `walk_test`, `sync_test` e da suite nova); `sh scripts/inventario-de-testes.sh --check` -> 116 arquivos, 2908 casos, 0 divergencias.

## Recomendacao ao Tech Lead
Aprovar a correcao; levar `qa_diretorio_hifen_test.sh` ao aceite do solicitante (regra 12); o mapa de modulos (`docs/testes/mapa-modulos.md`) nao lista as suites `qa_*` (nem a do cdpath), por isso nao foi alterado.
