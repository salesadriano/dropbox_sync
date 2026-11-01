# Area temporaria por arquivo de teste: causa da falha do retomada_download na suite completa

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "investigue a falha do retomada_download na suite completa" |
| Porte | P - `sh scripts/porte.sh`: 46 linhas de codigo (limite 50), nenhum gatilho de M ou G; sem contrato, schema, auth, segredo, dado sensivel, fronteira, pipeline ou dependencia; nenhuma linha de producao muda comportamento (so `lib/walk.sh:51`, `|| return` num `cd`); defeito de infraestrutura de teste, nao de producao |
| Log de prompt | `docs/prompts/2026-10-31_1900_investigar-retomada-download.md` |
| Issues | nenhuma |
| Branch / base | `chore/investigar-retomada-download` sobre `origin/develop` @ `bbc8504` |
| Agents | Tech Lead (investigacao e implementacao, Fluxo P); QA Expert (validacao, ver secao 6) |
| Data | 2026-10-31 |

## 2. Causa ou decisao

**Causa (medida):** `tests/run.sh` criava UMA area temporaria (`DBX_TESTES_TMP`) para a execucao inteira e so a removia no fim. O que cada arquivo de teste deixava nela se acumulava. Numa suite completa monitorada (amostra de `df /tmp` a cada 10 s) a area chegou a 9,4 GB num `/tmp` `tmpfs` de 9,8 GB, com 523 MB livres quando `retomada_download_test.sh` (arquivo 104 de 111) comecou. Os maiores acumuladores: `paralelo_upload_test.sh` (~4,2 GB) e `paralelo_download_test.sh` (~1,4 GB), da demanda de paralelismo de 2026-10-26. O caso grava varios arquivos reais de 150 MiB (`.part`, recebimento atomico, resposta do duble); com o disco cheio a escrita sai truncada e o produto, corretamente, recusa o conteudo pelo `content_hash` (saida `11`, destino preservado). Isolado o arquivo comeca com `/tmp` vazio, por isso passava (6 de 6). E o mesmo problema conhecido das notas da v2.1.0 ("retomada do download sob carga", visto entao em `qa_retomada_b7a`, o primeiro arquivo grande depois do acumulo naquela ordem): nao era carga, era espaco.

**Decisao (abordagem A de tres):** cada arquivo de teste roda com a sua propria area (`$DBX_TESTES_TMP/arquivo.N`), removida assim que ele termina; o agregado (`resumo.N`) fica na area da execucao. Descartadas: (B) corrigir a limpeza de cada arquivo que vaza (pontual, deixa a classe aberta para o proximo teste e mexe em suites `qa_*` aceitas); (C) apontar `TMPDIR` para disco (esconde o vazamento, depende do ambiente). A e a barreira estrutural: nenhum arquivo de teste consegue mais afetar o seguinte pelo espaco da area.

**Junto, residuo da demanda anterior:** `lib/walk.sh:51` (`_dbx_walk_entrar_raiz`) ficou sem `|| return` no `cd` (ShellCheck SC2164, aviso que entrou na `develop` com o PR #70 porque o lint daquela demanda rodou antes da ultima correcao). A auditoria DP-26 (`walk_test`) segue contando um unico `cd -P -- "$raiz"`.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `tests/run.sh` | Alterado: area temporaria por arquivo de teste | +10/-1 |
| `tests/unit/harness_test.sh` | Alterado: caso `cada_arquivo_tem_area_propria_removida_ao_terminar` (suite fabricada com dois arquivos) | +35/-0 |
| `lib/walk.sh` | Alterado: `cd ... \|\| return` (SC2164) | +1/-1 |
| `docs/testes/inventario-de-testes.md` | Alterado: linhas do caso novo e das duas funcoes fabricadas; resumo e conferencia | +9/-6 |
| `docs/prompts/2026-10-31_1900_investigar-retomada-download.md` | Novo | - |

## 4. Testes rodados

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `tests/unit/harness_test.sh` | `tests/run.sh` | `bash tests/run.sh harness_test` | 23 | 23 | 0 | - |
| `tests/unit/walk_test.sh` | `lib/walk.sh` | `bash tests/run.sh walk` | 13 | 13 | 0 | - |
| `tests/*/sync_blocos_test.sh` | `lib/walk.sh` (travessia por ciclo) | `bash tests/run.sh sync_blocos` | 67 | 67 | 0 | - |
| suite inteira, monitorada | `tests/run.sh` (todo arquivo passa por ele) | `bash tests/run.sh` | 2821 | 2817 | 0 | 48 min |

- Red observado: `harness_test` caso `cada_arquivo_tem_area_propria_removida_ao_terminar` reprovou antes da correcao com "o que um arquivo de teste deixa na sua area temporaria nao chega ao arquivo seguinte".
- Parada no primeiro erro (Regra 9): inalterada; os casos de parada do `harness_test` seguem verdes.
- Barreiras estaticas: `sh scripts/lint.sh` com 0 avisos (antes: 1, `lib/walk.sh:51`).
- Testes de seguranca e acesso (Regra 6): Nao aplicavel: o diff nao toca rota, credencial, dado sensivel nem entrada de usuario.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: sem interface.
- Suite completa: a execucao monitorada acima (111 arquivos, 2817 aprovados, 0 reprovados, 4 pulados, pico de `/tmp` 4,6 GB contra 9,4 GB antes) foi a primeira inteiramente verde desde a v2.1.0; a execucao oficial (`sh scripts/suite-completa.sh`) sobre o commit desta demanda e registrada abaixo antes do push.

## 5. Gates

| Gate | Skills aplicadas | Achados | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; checklist aplicado integralmente; itens nao aplicaveis listados na secao 4 | nenhum | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + `shellcheck-configuration`; checklist aplicado integralmente | nenhum: a mudanca fica no executor de testes (camada de teste), sem dependencia nova; `rm -rf --` com caminho montado pelo proprio executor sob a area da execucao | Aprovado |

- Ciclo: 1.
- `sh scripts/alteracoes-externas.sh --detectar`: exit 0 antes de cada gate.

## 6. QA

- Porte P: `QA: amostragem 2 de 5`; antecipada pelo Tech Lead (o executor de testes e o ponto por onde passa todo resultado da suite; defeito nele esconderia falhas). Resultado na linha do veredito.
- Inventario de testes (regra 51): 3 linhas novas em `tests/unit/harness_test.sh` (o caso e as duas funcoes fabricadas, como as existentes), resumo 25 -> 28; `sh scripts/inventario-de-testes.sh --check` -> `arquivos: 111 | casos: 2833 | divergencias: 0`.
- Veredito do QA (2026-10-31, amostragem por evidencia, sem `qa-*` nem mutantes formais; suite completa nao reexecutada, e do Tech Lead): **Aprovado**.
  - Auditado: `git diff origin/develop` em `tests/run.sh` (area `arquivo.N` criada com `mkdir --`, `rm -rf --` logo apos o arquivo; agregado `resumo.N` fica na area da execucao, passado por `DBX_HARNESS_RESUMO`), caso novo do `harness_test.sh` e inventario.
  - Reexecutado: `bash tests/run.sh harness_test` -> 1 arquivo, 23 aprovados, 0 reprovados, 0 pulados, APROVADA; `bash tests/run.sh walk` -> 1 arquivo, 13 aprovados, 0 reprovados, 0 pulados, APROVADA; `sh scripts/inventario-de-testes.sh --check` -> `arquivos: 111 | casos: 2833 | divergencias: 0`.
  - Riscos, por experimento em suite fabricada (rascunho fora de `tests/`, nada acrescentado ao repositorio): (a) arquivo que reprova: status 1, 2o arquivo nao rodou, `REPROVADA` no relatorio e a area do TMPDIR ficou vazia (area do arquivo removida); (b) arquivo que sai sem gravar o agregado: `# INTEGRIDADE: a_test.sh terminou sem gravar o agregado (status 0)`, status 1, sem sobra; (c) 4 arquivos que apagam a propria `DBX_TESTES_TMP`, fazem `cd` para dentro dela, trocam-na por link quebrado e reatribuem a variavel: 4 arquivos, 4 casos aprovados, status 0, executor integro, area da execucao intacta e sem sobra; (d) TMPDIR com espaco (`t u`): verde, arquivo com espaco no nome gravado, sem sobra; (e) `grep -rnE 'DBX_TESTES_TMP/\.\.|dirname "\$DBX_TESTES_TMP"' tests` -> sem ocorrencias, nenhum teste real usa o pai da area.
  - Dependencia entre arquivos: `grep -rn DBX_TESTES_TMP tests/support tests/unit tests/integracao` -> todos os usos sao `mktemp` ou nomes com `$$` na propria area, `TMPDIR`/`HOME` repassados a subprocessos do mesmo arquivo, e `fixtures.sh`, que gera `fixture-<nome>.bin` sob demanda se ausente (cache so por arquivo; custo de regerar, nao falha). Nenhum teste le artefato de outro arquivo. A suite completa verde do Tech Lead e indicio adicional.
  - Ressalva menor (nao reprova): o inventario conta 28 funcoes `teste_` em `harness_test.sh`, mas o arquivo executa 23 casos, porque as funcoes `teste_` fabricadas dentro de heredocs entram na contagem textual; convencao ja vigente, 3 linhas novas coerentes com ela. Risco residual: `fixture_criar` regera massa grande a cada arquivo que a usa (mais I/O, menos pico de disco).

## 7. Riscos e rollback

- Riscos residuais: os testes que vazam (paralelo_upload, paralelo_download e outros) continuam deixando arquivos na propria area, agora removida ao fim de cada arquivo; o pico passa a ser o do maior arquivo isolado (~4,6 GB medidos, abaixo do `tmpfs` de 9,8 GB). Corrigir a limpeza deles e melhoria, nao condicao.
- A nota "Problema conhecido" das notas da v2.1.0 descreve uma causa que nao era a real; a proxima release deve dizer que foi resolvido (infraestrutura de teste, sem efeito no produto).
- Impacto: Nenhum no produto (contrato, CLI, estado, dependencia inalterados); so o executor de testes.
- Rollback: `git revert` do commit basta.

## 8. Links e aceites

- Entradas de memoria: Nenhuma: sem decisao duravel alem do registro.
- Documentacao sincronizada: `docs/testes/inventario-de-testes.md`.
- Commit(s): o commit desta demanda (`chore(testes): ...`), unico da branch.
- PR: corpo da PR traz o resultado da suite completa oficial sobre o commit (registrada em `<git-dir>/agentes-suite-completa`), porque um commit posterior invalidaria o registro.
- Tech Lead: **Aprovado**, 2026-10-31 - condicionado a suite completa oficial verde sobre o commit; QA por amostragem antecipada aprovou.
- Solicitante: Nao aplicavel: sem arquivo do QA.
