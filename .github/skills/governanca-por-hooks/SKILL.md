---
name: governanca-por-hooks
description: >
  Troca prosa de governanca por mecanismo do cliente de IA quando ele oferece hooks e permissoes
  versionaveis: um resumo de estado impresso no inicio da sessao (branch principal declarada,
  remoto, reservas ativas, PRs abertas, worktrees, alteracoes nao realizadas pelos agents), um
  guarda que bloqueia comandos proibidos antes de rodarem, e permissoes versionadas para comandos ja
  autorizados pelo solicitante. Use para configurar ou revisar hooks e permissoes do cliente de IA
  num projeto; prefira `instrucoes-do-projeto` para o texto do arquivo de instrucoes e
  `security-best-practices` para o endurecimento do que o guarda protege.
---

# Governanca por hooks, nao por prosa

## Security Handoff

Os scripts desta skill recebem entrada de fora (o JSON do hook, a saida de `gh`, o conteudo das entradas de memoria) e repassam texto a shell.

- Nenhum dos dois scripts executa, expande ou avalia o comando recebido: o guarda compara por `case` com o padrao entre aspas e nunca usa `eval`. Mudanca que introduza execucao do comando e achado bloqueante do gate de conformidade.
- Permissao versionada (`permissions.allow`) e **o harness deixar de perguntar** o que o solicitante ja decidiu por demanda; nao e autorizacao para o agent decidir. Nunca versionar permissao para comando que o protocolo proibe ao agent (merge por conta propria, `--force` em branch compartilhada, reversao de alteracao humana).
- Nunca versionar segredo, token, credencial ou chave em `settings.json`, nos scripts, nos exemplos ou nos Bats. Autenticacao do `gh` e do operador, fora do repositorio.
- Em projeto com autenticacao, autorizacao ou exposicao de API, aplicar tambem `security-best-practices` e `api-security-best-practices` ao decidir o que o guarda bloqueia.

## Scope Boundary

- [`instrucoes-do-projeto`](../instrucoes-do-projeto/SKILL.md) cuida do texto do arquivo de instrucoes; esta skill cuida do que **sai** dele porque passou a ser garantido por hook. O resumo de estado chama o verificador daquela skill em modo aviso.
- [`gitflow`](../gitflow/SKILL.md) e a regra 48 do `AGENTS.md` definem o detector de alteracoes externas (`scripts/alteracoes-externas.sh`); o guarda so o **invoca** antes do `git push` e o resumo so o **imprime**. Nenhum dos dois decide pelo solicitante.
- [`protocolo-tdd`](../protocolo-tdd/SKILL.md), Regra 8, e a fonte da regra "so os itens afetados, por arquivo de teste"; o guarda e um anteparo contra o esquecimento, nao a regra.

## Origem

Praticas adotadas num projeto governado por este pacote em 14/10/2026 (itens 4 e 9 de onze mods de governanca) e trazidas ao modelo em 15/10/2026 (entrada `2026-10-15-0914-skills-a-partir-dos-mods-de-governanca`). La, tres proibicoes do arquivo de instrucoes (comando que nao roda no host, suite inteira local, push com alteracao nao realizada pelos agents) viraram um hook, e dois comandos ja autorizados por demanda (`gh pr merge`, `gh run rerun`) deixaram de parar no classificador de permissoes.

## Principio

Regra que um hook garante nao precisa ser lida em toda sessao. O que o cliente de IA consegue executar antes ou depois de uma acao do agent (inicio de sessao, antes de um comando) sai da prosa e vira script versionado, com teste; o que o cliente nao consegue garantir continua em prosa. A marca no arquivo de instrucoes e uma linha: `garantido por hook: scripts/<script>.sh`.

## Os tres scripts

Todos em POSIX `sh`, em `scripts/` desta skill, com Bats em `scripts/tests/`. O projeto os copia para `scripts/` e `scripts/tests/` (e o que os exemplos de configuracao pressupoem) ou os chama no lugar.

### `resumo-de-estado.sh` (inicio de sessao)

Imprime fatos medidos no momento, uma fonte por linha, e **nunca falha a sessao** (exit sempre 0; fonte indisponivel vira `indisponivel (...)`):

- branch principal declarada (entrada `branch-principal` ativa; sem ela, a linha manda pedir a declaracao, regra 46);
- remoto `origin`, branch atual e sha;
- reservas de escopo ativas (entradas `tipo: reserva`, `status: ativa`): e a leitura do canal da regra 47, feita antes de planejar;
- PRs abertas, por `gh pr list`, quando `gh` responde;
- worktrees;
- alteracoes nao realizadas pelos agents: `scripts/alteracoes-externas.sh --detectar`, impresso como `nenhuma` ou `DIVERGENCIA (exit 3)` com a saida; so leitura, a decisao e do solicitante (regra 48);
- `--verificador "<comando>"`, opcional, em modo aviso: por exemplo o verificador de [`instrucoes-do-projeto`](../instrucoes-do-projeto/SKILL.md).

```sh
sh scripts/resumo-de-estado.sh --verificador "sh scripts/verificar-instrucoes-do-projeto.sh"
```

Diretorio de entradas por `--entradas` ou, por padrao, `.github/agents/memoria/entradas` e, se nao existir, `.claude/ai_team/memoria/entradas`. Raiz por `--raiz` ou, por padrao, o topo do git do diretorio do script. Sem `--verificador`, a linha `verificador: nao configurado` e impressa, para que a saida seja previsivel.

### `guarda-de-comandos.sh` (antes de cada comando de shell)

Le em stdin o JSON que o cliente envia ao hook (`tool_input.command`, `cwd`), por `node` ou `python3`; sem os dois, permite e avisa, porque um hook que falha por falta de interprete bloquearia todo comando. Bloqueia com exit 2 e o motivo em stderr, que o cliente devolve ao agent:

1. **Embutida:** `git push` quando `scripts/alteracoes-externas.sh --detectar` sai com 3 no repositorio do comando (regra 48). A saida do detector vai na mensagem, para que o agent a apresente ao solicitante.
3. **Embutida, por adocao** (so quando o repositorio tem `scripts/suite-completa.sh`): `gh pr create`, e `git push` quando a branch atual e a de integracao (a `branch-principal` declarada na memoria; sem ela, `main` ou `master`) ou tem PR aberta para ela (consultada por `gh pr list`, so se ha remoto e `gh` responde), exigem `scripts/suite-completa.sh --conferir` em 0: suite completa **verde, limpa e registrada para o HEAD** (Regra 8 de `protocolo-tdd`, desde 16/10/2026). Vermelha, de outro commit, suja ou ausente: bloqueio com o motivo do `--conferir`. Push de branch de trabalho sem PR para a integracao nao e afetado; sem `gh`, so o caso da branch de integracao e verificado; `git push origin HEAD:main` com HEAD destacado nao e reconhecido (limite declarado: o guarda nao le o refspec).
2. **Por arquivo de padroes** (`--padroes <arquivo>`, opcional): linhas `padrao<TAB>motivo`; comando que contem o padrao e bloqueado com o motivo, **salvo** quando roda em conteiner (`docker run`, `docker compose`, `docker-compose`, `docker exec`), isento por desenho, porque e por ali que a suite completa roda quando o solicitante a pede. Linha sem `<TAB>` bloqueia com motivo generico; arquivo de padroes ausente e silencioso (so a regra 1 vale), porque um aviso a cada comando seria ruido. Exemplo em [references/padroes-de-guarda.exemplo.txt](references/padroes-de-guarda.exemplo.txt); cada projeto escreve o seu em `scripts/guarda-de-comandos.txt`.

```sh
printf '{"tool_input":{"command":"git push"},"cwd":"%s"}' "$PWD" | sh scripts/guarda-de-comandos.sh --padroes scripts/guarda-de-comandos.txt
```

**Limites declarados:** o guarda casa por substring e nao sabe se um comando de teste traz arquivo de teste (a heuristica por stack da origem nao e agnostica e ficou de fora; o projeto pode acrescenta-la no seu arquivo de padroes com padroes mais especificos). E anteparo contra o esquecimento, nao barreira de seguranca: quem quiser contornar, contorna. A isencao por conteiner tambem casa por substring.

### `suite-completa.sh` (antes do push para a PR de integracao)

Roda o comando oficial da suite completa e registra o resultado para o commit atual, em `<git-dir>/agentes-suite-completa` (por worktree, fora do versionamento): `<sha> <limpo|sujo> <exit> <data> <segundos>`. E o que a regra 3 do guarda confere.

```sh
sh scripts/suite-completa.sh -- npx --yes bats@1.13.0 --abort --print-output-on-failure scripts/tests/   # roda e registra; exit = o do comando
sh scripts/suite-completa.sh                 # idem, com o comando gravado em scripts/suite-completa.cmd
sh scripts/suite-completa.sh --conferir      # 0 se ha registro verde e limpo para o HEAD; 3 se nao, com o motivo
sh scripts/suite-completa.sh --mostrar
```

`sujo` e alteracao em arquivo **rastreado** no momento da execucao (a suite nao testou o commit que vai ser enviado); arquivo novo nao rastreado nao conta e so gera aviso, porque nao vai no push. Commit novo invalida o registro. O comando e executado como recebido, sem `eval`; `scripts/suite-completa.cmd` e do projeto e roda por `sh -c`, como um script versionado. O registro e a evidencia que o registro de entrega transcreve (comando, contagens, duracao, sha).

## Permissoes versionadas

Comando que o solicitante **ja autoriza por demanda** e que o classificador de permissoes do cliente para toda vez (no projeto de origem, `gh pr merge` e `gh run rerun` depois de o solicitante mandar mergear ou reexecutar) entra em `permissions.allow` do arquivo de configuracao versionado do cliente. Tres condicoes, todas obrigatorias:

- a decisao continua do solicitante, por demanda, registrada no log de prompt; a permissao tira o prompt do harness, nao a decisao do protocolo (regra 46: o agent nunca mergeia por conta propria);
- o arquivo de instrucoes diz isso em uma linha, ao lado da marca do hook;
- a entrada de memoria que autoriza a permissao cita o literal do solicitante.

Permissao para comando que o protocolo proibe ao agent nao e versionada (ver *Security Handoff*).

## Por cliente de IA

O mecanismo e do cliente; o principio e o mesmo. Configuracao, sintaxe e o que fazer quando o cliente nao oferece hook em [references/clientes-de-ia.md](references/clientes-de-ia.md). Exemplo completo para o Claude Code em [references/settings-claude-code.exemplo.json](references/settings-claude-code.exemplo.json). A sintaxe de cada cliente e conferida na documentacao vigente dele (Context7, regra 30) na adocao e a cada atualizacao: identificadores de hook e de permissao mudam com o tempo.

## O que sai da prosa, e como

Para cada proibicao do arquivo de instrucoes que o guarda passa a bloquear, ou fato que o resumo passa a imprimir:

1. escrever o padrao (ou a linha do resumo) e o caso Bats que o prende;
2. exercitar o hook numa sessao real e registrar a saida literal no registro de entrega (o bloqueio e o resumo nao sao prensaveis por teste de repositorio);
3. trocar a prosa pela linha `garantido por hook: scripts/<script>.sh`; o que o hook **nao** cobre fica em prosa, e o registro diz qual parte ficou.

## Testes

```sh
npx --yes bats@1.13.0 --abort --print-output-on-failure .github/skills/governanca-por-hooks/scripts/tests/
```

`--abort` para no primeiro teste falho (Regra 9 de `protocolo-tdd`; mecanica por ferramenta na referencia `interrupcao-no-primeiro-erro` de [`protocolo-tdd`](../protocolo-tdd/SKILL.md)). `gh`, `docker` e o detector sao substituidos por stubs no `PATH` ou na raiz de teste (os casos da regra 3 usam o `suite-completa.sh` real copiado para a raiz de teste); o efeito do hook no cliente so se observa em sessao real e e registrado como tal. Os scripts sao POSIX `sh`; `shellcheck -s sh` e item do gate de conformidade.

## Adocao num projeto

Levar a pasta inteira da skill; copiar os tres scripts e os Bats para `scripts/` e `scripts/tests/` (a regra 3 do guarda so vale com `scripts/suite-completa.sh` presente); gravar o comando oficial da suite completa em `scripts/suite-completa.cmd`; escrever o arquivo de padroes do projeto; configurar o cliente conforme a referencia; registrar numa entrada `tipo: decisao`, `escopo: projeto` o que passou a ser garantido por hook, as permissoes versionadas com o literal do solicitante, e o que continua em prosa.
