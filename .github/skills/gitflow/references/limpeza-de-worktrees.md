# Limpeza de worktrees no fechamento

Mecanica do passo 5 (encerramento) de [worktree-e-sincronizacao.md](worktree-e-sincronizacao.md): depois do merge da PR, os worktrees de demanda ja mesclados saem por script, e o que nao pode sair fica listado com o motivo. Origem: pratica adotada num projeto governado por este pacote em 14 e 15/10/2026 (item 11 de onze mods de governanca), trazida ao modelo em 15/10/2026. La, `git worktree remove` falhava no meio por `node_modules` de root criados por conteiner e deixava o diretorio orfao com o registro ja apagado; o script apaga o `node_modules` **antes** do `remove`, e foi o primeiro `--executar` real que exercitou esse caminho (6 removidos, 0 falhas).

## O script

`scripts/limpar-worktrees.sh` (POSIX `sh`, testes em `scripts/tests/limpar-worktrees.bats`), executado de qualquer worktree do repositorio:

```sh
sh scripts/limpar-worktrees.sh                 # dry-run: lista; nao muda nada alem do FETCH_HEAD do fetch
sh scripts/limpar-worktrees.sh --executar      # remove o que o dry-run marcou como REMOVERIA
sh scripts/limpar-worktrees.sh --principal main --remoto origin --sem-gh --sem-docker
```

| Opcao | Efeito |
|---|---|
| `--dry-run` (padrao) | so lista; nao muda nada alem do `FETCH_HEAD` escrito pelo `git fetch` que prova a mescla; e o que se roda antes para conferir |
| `--executar` | remove o worktree, apaga a branch local (`branch -D`, porque a mescla ja foi provada) |
| `--raiz <dir>` | checkout principal; padrao: o primeiro worktree de `git worktree list` |
| `--principal <branch>` | branch principal; padrao: titulo da entrada `branch-principal` ativa (`.github/agents/memoria/entradas` ou `.claude/ai_team/memoria/entradas`; `--entradas <dir>` sobrescreve) |
| `--remoto <nome>` | padrao `origin` |
| `--sem-gh` | nao consulta PRs mescladas por squash no `gh` |
| `--sem-docker` | nao usa `docker run ... alpine rm -rf` para arquivos de root |

Um worktree de `<raiz>.worktrees/` so e removido quando **todas** valem: e worktree registrado no git; tem branch (HEAD nao destacado) que nao e a principal; nao esta travado (`git worktree lock`); `git status --porcelain` esta vazio fora de `node_modules/`; e a branch esta mesclada em `<remoto>/<principal>` (`merge-base --is-ancestor`) ou a sua PR consta como `MERGED` no `gh` (merge por squash) com o **mesmo** commit que o HEAD local (commit local posterior ao squash nao e descartado). Tudo o mais e `PENDENTE (<motivo>)` e nunca e tocado.

Saida: `REMOVERIA (...)` no dry-run, `REMOVIDO (...)`, `PENDENTE (...)`, `FALHOU (...)` e a linha `resumo:`. Exit 0; 1 quando `--executar` nao conseguiu remover algo que deveria; 2 em argumento invalido ou branch principal nao declarada.

## No fechamento da demanda

1. Com a PR mergeada e a branch remota apagada, rodar o dry-run e conferir a lista.
2. Rodar `--executar`. O worktree da propria demanda sai nessa execucao quando estiver limpo e mesclado; rodar de outro worktree ou do checkout principal.
3. `PENDENTE` por alteracao nao commitada, branch nao mesclada ou HEAD destacado **so sai com confirmacao explicita do solicitante, por item**, com `git worktree remove --force` e `git branch -D` a mao, como ja diz a secao 2 da referencia de worktree. Diretorio que nao e worktree registrado (orfao de um `remove` que falhou no meio) tambem e manual: apagar o diretorio (por `docker` se houver arquivo de root), `git worktree prune`, `git branch -d`.
4. A saida literal, datada, vai ao registro de entrega: o numero muda com o dia.

## Relacao com a sincronizacao da secao 2

A sincronizacao de [worktree-e-sincronizacao.md](worktree-e-sincronizacao.md), secao 2, remove branches locais cuja branch remota foi apagada; este script remove worktrees cuja branch foi mesclada na principal. Os dois se complementam: no encerramento, o script primeiro (prova a mescla e lida com arquivos de root), a sincronizacao depois (branches sem worktree). Nenhum dos dois toca a branch principal.
