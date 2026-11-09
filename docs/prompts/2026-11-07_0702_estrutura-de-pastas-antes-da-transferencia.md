# Estrutura de pastas criada antes da transferencia dos arquivos

**Branch:** `feature/estrutura-de-pastas-antes-da-transferencia` (sobre `origin/develop` @ `e3628a6`), worktree `../dropbox_api.worktrees/feature-estrutura-de-pastas-antes-da-transferencia`.
**Instancia:** `myPCWin/Desenvolvedor Hydros`.
**Porte:** G (Tech Lead). `sh scripts/porte.sh` na entrada, arvore sem diff: `base: origin/develop @ e3628a6 | arquivos: 0 | linhas de codigo: 0 (limite 50) | porte: P` — so mede o diff, ainda vazio. Sobe para G porque a demanda revoga o limite declarado "SO ARQUIVOS" de `lib/sync` (System Design), acrescenta endpoint novo da integracao externa (criacao de pasta remota, `create_folder_v2`/`create_folder_batch`) e muda o comportamento publico de `sync`, `upload` e `download` de pasta.
**PRs abertas na entrada:** nenhuma.
**Issues:** nenhuma.

## Prompt 1 — 2026-11-07

> nos processos crie toda a estrutura de pastas antes de iniciar a transferencia dos arquivos, tanto no destino local quanto no remoto

**Intencao principal:** nos processos de transferencia de pasta (`sync --enviar`, `sync --receber`, `upload` de pasta e `download` de pasta), criar no destino toda a arvore de diretorios antes do primeiro arquivo transferido: `mkdir` no destino local, criacao de pasta pela API no destino remoto.

**Inferencias adotadas:**
- Hoje o destino local recebe `mkdir -p` do diretorio pai arquivo a arquivo e o remoto ganha as pastas implicitamente no upload; diretorio vazio nao e criado (limite declarado em `lib/sync.sh`). As decisoes abertas (pastas vazias, ciclos do `--receber`, espelhamento, linhas) foram levadas ao solicitante em lote (regra 12).

## Respostas do solicitante ao lote de perguntas (regra 12) — 2026-11-07

Perguntas por AskUserQuestion; respostas literais das opcoes escolhidas:

- **Pastas vazias da origem devem ser criadas no destino?** "Sim, toda a árvore (Recomendado)" — toda pasta da origem que passa no filtro e criada no destino, inclusive as vazias; revoga o limite "so arquivos" do `sync`. Pastas excluidas por filtro ficam fora.
- **`sync --receber` e `download` de pasta, em ciclos:** "Por ciclo" — antes das transferencias de cada ciclo, criar todas as pastas daquele ciclo.
- **Com `--espelhar`, apagar pastas do destino que nao existem mais na origem?** "Sim, apagar pastas órfãs".
- **Linhas:** "develop e support/bash-4.2 (Recomendado)" — uma PR por linha.

**Inferencias do Tech Lead sobre as respostas:**
- No `--enviar` e no `upload` de pasta a travessia local ja e anterior ao ciclo 1: a estrutura remota inteira e criada antes do primeiro arquivo; "por ciclo" vale para o sentido remoto para local, onde a arvore so e conhecida ciclo a ciclo.
- A exclusao de pasta orfa e destrutiva: nasce com as guardas do espelhamento existentes (origem vazia, travessia parcial, `--confirmar`, filtro protege o destino) e nao pode apagar conteudo que a execucao nao viu (guarda sobre o observavel, nao sobre a memoria). Especificacao pelo Business Analyst.

## Resposta do solicitante a DIV-401 — 2026-11-07

Pergunta por AskUserQuestion (arquivo no destino com o nome de uma pasta da origem, sob `--espelhar`); opcao escolhida, literal: "Apagar antes de criar".

**Inferencias adotadas:** contra a recomendacao do BA (manter `DIV-394`). O Tech Lead escreveu as guardas da exclusao antecipada em `RF-214(c)` (observado nesta execucao, nao filtrado, origem vazia e leitura parcial ja resolvidas, `--confirmar`, `delete_v2` com `parent_rev`, local so arquivo ou ligacao) e o recuo para falha de item em `RF-214(d)`. As recomendacoes do BA em `DIV-397`, `DIV-399`, `DIV-400`, `DIV-402` a `DIV-405` foram aceitas pelo Tech Lead; `DIV-398` conferida pelo Tech Lead via Context7.

## Resposta ao lote 3 (2026-11-07) — reaprovacao de suites do QA (regra 12)

Pergunta: reaprovar as tres suites do QA alteradas so no duble de curl (ramo `create_folder_batch`), sem alteracao de assert ou caso?
Resposta do solicitante: "Reaprovar as três (Recomendado)".

## Resposta ao lote 4 (2026-11-08) — conflito RF-136 x RF-214/RF-216 (delete_v2)

Pergunta: manter `delete_v2` nas duas exclusoes novas (excecao ao RF-136) ou passar pelo `delete_batch`?
Resposta do solicitante: "Exceção para delete_v2 (Recomendado)".
Efeito: RF-136(f); auditorias `lot11` (lote_test) e `qdb09` (qa_desempenho_b9, suite do QA — reaprovacao com sha256) passam a admitir `delete_v2` so nas duas funcoes nomeadas.

## Resposta ao lote 5 (2026-11-08) — reaprovacao da qdb09 (regra 12)

Pergunta: reaprovar tests/integracao/qa_desempenho_b9_test.sh com a auditoria qdb09 restrita as duas funcoes de RF-136(f)?
Resposta do solicitante: "Reaprovar (Recomendado)".

## Prompt (2026-11-08) — merge da linha develop

```
merge PR #103
```

- Acao: a PR #103 foi mesclada na `develop` (merge commit `6ea9e33`) e o worktree da demanda foi removido por `limpar-worktrees.sh --executar`.

## Prompt (2026-11-08) — linha support/bash-4.2

```
sim, comece a linha support/bash-4.2
```

- Intencao: aplicar a F-103 na linha legada (RF-219(b), uma PR por linha, RF-207).
- Branch: `feature/estrutura-de-pastas-antes-da-transferencia-bash42`, a partir de `origin/support/bash-4.2` (`c539bbd`), com cherry-pick de `ba74974`.
- Conflito: cabecalho de `docs/testes/inventario-de-testes.md`, resolvido com a contagem desta linha: 128 arquivos, 3068 casos, 0 divergencias.
- Porte previsto (gate de conformidade, foco 5):
  - `local -n` em `commands/sync.sh`;
  - expansoes de arranjo possivelmente vazio sem `${v[@]+...}` sob `set -u` (`lib/lote.sh`, `commands/sync.sh`);
  - nova medicao do lint frente ao teto de 14336 MB.
