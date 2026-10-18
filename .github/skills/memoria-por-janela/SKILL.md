---
name: memoria-por-janela
description: >
  Reduz o que cada agent carrega da memoria no bootstrap: o Tech Lead le o indice por janela de
  tempo (`scripts/memoria-index.sh --desde <data>`) e consulta o resto sob demanda; `agentes: todos`
  fica restrito a decisao de pacote, para que a fatia por papel nao cresca com entrada que nenhum
  papel pediu. Use para dimensionar o bootstrap, escolher a janela e declarar `agentes:` numa
  entrada; prefira `prompt-logger` para o log de prompt e `review-documentation` para o registro de
  entrega, que nao sao memoria.
---

# Memoria por janela e por papel

## Security Handoff

Esta skill so le e filtra entradas de memoria ja versionadas. Nada do que ela produz (indice, extrato por papel) pode receber segredo, credencial, token, cookie, chave ou dado pessoal desnecessario; a entrada de memoria e sanitizada ao ser gravada (regra 7 do `AGENTS.md`), nunca ao ser lida. Em demanda que toque autenticacao, autorizacao, segredos ou exposicao de API, aplicar tambem `security-best-practices` e `api-security-best-practices`.

## Scope Boundary

- A memoria e uma entrada por arquivo em `memoria/entradas/`, com o frontmatter do `entradas/README.md`; esta skill nao muda o formato, muda **quanto** dela e carregado por padrao.
- [`prompt-logger`](../prompt-logger/SKILL.md) e [`review-documentation`](../review-documentation/SKILL.md) produzem o log de prompt e o registro de entrega, que a memoria referencia por `ref:` e nunca copia.
- [`instrucoes-do-projeto`](../instrucoes-do-projeto/SKILL.md) cuida do arquivo de instrucoes da ferramenta de IA, que tambem e carregado em toda sessao e tambem precisa ser enxuto; os dois cortes se somam.
- A transposicao de memoria entre papeis (regra 43) continua sendo do Tech Lead; o filtro por papel e o mecanismo, nao a autorizacao.

## Origem

Praticas adotadas num projeto governado por este pacote em 14/10/2026 (itens 2 e 3 de onze mods de governanca) e trazidas ao modelo em 15/10/2026 (entrada `2026-10-15-0914-skills-a-partir-dos-mods-de-governanca`). La, o bootstrap do Tech Lead carregava uma memoria de projeto de 1,28 MB e um indice de 420 KB a cada sessao, e 100 entradas com `agentes: todos` entravam no bootstrap de todo papel.

## O que o script do pacote faz

`scripts/memoria-index.sh` (POSIX `sh`, testes em `scripts/tests/memoria-index.bats`) ganhou tres comportamentos nesta skill:

| Opcao | Efeito |
|---|---|
| `--desde <YYYY-MM-DD>` | so entradas cuja data no **nome do arquivo** (a hora real da gravacao, que e o que ordena o indice) e maior ou igual a data. Valor obrigatorio; forma ou calendario invalidos saem com 2. Combina com `--agente`, `--tipo`, `--escopo`, `--corpo`. |
| `--todas` | atalho de `--status todas`: inclui `substituida` e `encerrada`, que o indice omite por padrao. |
| `--check` com `AVISO` | para `agentes: todos` fora de `tipo: decisao` + `escopo: pacote`, imprime `AVISO <arquivo>: 'agentes: todos' fora de tipo decisao + escopo pacote; nomeie os papeis` e **nao reprova** (exit 0): entradas antigas nao sao reescritas. A entrada `branch-principal`, que leva `todos` por exigencia da regra 46, e isenta. |

```sh
sh scripts/memoria-index.sh --desde "$(date -d '90 days ago' +%F 2>/dev/null || date -v-90d +%F)"
sh scripts/memoria-index.sh --agente qa-expert --desde 2026-07-01 --corpo
sh scripts/memoria-index.sh --todas --tipo reserva
sh scripts/memoria-index.sh --check
```

## Regras

1. **Bootstrap do Tech Lead por janela** (regra 1). Por padrao, o Tech Lead carrega as memorias estaveis que o projeto declarar (no modelo, `MEMORIA-COMPARTILHADA.md`) e o indice dos ultimos **90 dias**: `sh scripts/memoria-index.sh --desde <hoje menos 90 dias>`. A memoria de projeto extensa e as entradas anteriores a janela sao consultadas por `grep` e pelo indice sem `--desde`, **sob demanda**: quando a demanda toca um assunto cuja decisao pode ser mais antiga, o Tech Lead procura antes de decidir. As tabelas congeladas e as entradas antigas continuam valendo integralmente; muda so o que e carregado por padrao.
2. **A janela e do projeto, e e medida.** 90 dias e o padrao; o projeto que tiver memoria curta ou muito longa registra outra janela em entrada `tipo: decisao`, `escopo: projeto`. Ao adotar, medir `wc -c` do indice inteiro e do indice com `--desde` e registrar os dois no registro de entrega: se a janela nao cortar nada (entradas mais novas que a janela), o ganho e so o das memorias extensas que deixam de ser lidas, e o registro diz isso.
3. **`agentes: todos` so em decisao de pacote** (regra 7; a entrada `branch-principal` e a excecao da regra 46). Toda outra entrada (decisao de projeto, aceite, reserva, bloqueio, backlog, stack, contexto) nomeia os papeis a quem interessa: quem executa e quem valida, no minimo. `todos` fora desse caso entra no bootstrap de todo agent sem que nenhum o tenha pedido; o `--check` avisa.
4. **O que de fato corta o bootstrap dos demais agents** e a reescrita das entradas futuras com papeis nomeados e a janela do Tech Lead ao transpor; o aviso impede que o `todos` continue a crescer. Entradas antigas com `todos` podem ser ajustadas em massa, por script e so na linha `agentes:`, quando ja estiverem `encerrada` ou `substituida`; entrada `ativa` de outra sessao nao e editada (README das entradas).
5. **Reserva, aceite e bloqueio nomeiam `tech-lead`** e os papeis da demanda. Reserva encerrada com `todos` e o caso mais comum de ruido: ela ja sai do indice padrao por status, mas entra em `--todas` de todo papel.

## Relacao com o protocolo

Desde 15/10/2026 (decisao de Sales, entrada `2026-10-15-1050-regras-do-pacote-absorvem-os-mods`), a leitura por janela e a restricao de `todos` sao norma do pacote: regra 1 (bootstrap do Tech Lead pelos ultimos 90 dias, restante sob demanda) e regra 7 (`todos` so em decisao de pacote e na entrada `branch-principal`) do `AGENTS.md`. Esta skill e o mecanismo e a referencia de dimensionamento; o indice completo continua disponivel sem `--desde`.

## Testes

```sh
npx --yes bats@1.13.0 --abort --print-output-on-failure scripts/tests/memoria-index.bats
```

`--abort` para no primeiro teste falho (Regra 9 de `protocolo-tdd`; mecanica por ferramenta na referencia `interrupcao-no-primeiro-erro` de [`protocolo-tdd`](../protocolo-tdd/SKILL.md)). O script e POSIX `sh`; `shellcheck -s sh scripts/memoria-index.sh` e item do gate de conformidade.

## Adocao num projeto

Levar o `scripts/memoria-index.sh` e o Bats atualizados do modelo (o projeto gerado ja os tem em `scripts/`). Registrar a janela escolhida e a medicao do indice numa entrada `tipo: decisao`, `escopo: projeto`, `agentes: tech-lead`.
