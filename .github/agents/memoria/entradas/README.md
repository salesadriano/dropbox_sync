# Entradas de memoria

Uma entrada por arquivo, nunca uma linha em tabela compartilhada. E isso que permite sessoes paralelas gravarem memoria ao mesmo tempo sem conflito de merge: dois arquivos novos nunca conflitam; duas edicoes na mesma linha de uma tabela sempre conflitam.

## Nome do arquivo e id

```
YYYY-MM-DD-HHMM-<slug>.md
```

- `HHMM` e a hora real da gravacao; `slug` tem ate cinco palavras em kebab-case, sem acento.
- O `id` no frontmatter e igual ao nome do arquivo sem `.md`.
- Nunca usar contador sequencial (`001`, `DEC-nn`): duas sessoes escolheriam o mesmo numero.
- Se o arquivo ja existir, ler antes de gravar: e provavelmente a mesma decisao tomada por outra sessao. Se for outra, acrescentar um sufixo curto ao slug.

## Frontmatter obrigatorio

```markdown
---
id: 2026-09-12-0855-exemplo-de-entrada
tipo: decisao          # decisao | aceite | bloqueio | backlog | stack | contexto | reserva
escopo: projeto        # pacote (agents, skills, protocolo, templates) | projeto (demanda concreta)
titulo: Uma linha que diz a decisao
data: 2026-09-12
dono: Tech Lead
instancia:             # opcional: <host>/<usuario-git> da instancia que gravou (regra 47); obrigatorio quando houver mais de um Tech Lead no projeto
agentes: senior-developer, qa-expert   # papeis a quem a entrada e pertinente, ou 'todos'; o Tech Lead ve tudo sem precisar constar
status: ativa          # ativa | substituida | encerrada
substitui:             # opcional: id de outra entrada, ou DEC-STR-nn / PRJ-DEC-nn da tabela congelada
origem:                # opcional: delegacao (padrao) | chamada-direta, quando o agent foi acionado sem passar pelo Tech Lead | intervencao-humana, quando registra confirmacao ou autorizacao sobre alteracao nao feita pelos agents (regra 48)
regra:                 # opcional: AGENTS.md n, skill ou template que a decisao altera
ref:                   # opcional: link para registro de entrega, parecer ou historico
---

Corpo em uma a cinco linhas: a decisao e o impacto. Detalhe extenso vai para `../historico/`.
```

## Regras

- **Memoria por papel.** Cada entrada declara em `agentes:` os papeis a quem e pertinente (`tech-lead`, `senior-developer`, `qa-expert`, `ux-expert`, `dba`, `business-analyst`, `documentation-writer`, `commit-writer`) ou `todos`. No bootstrap, cada agent carrega apenas `sh scripts/memoria-index.sh --agente <seu-papel>`; o Tech Lead carrega toda a memoria (`--agente tech-lead` nao filtra). Quem grava a entrada decide os papeis; na duvida, declarar o papel que executa a decisao e o que a valida. Entrada sem `agentes:` reprova no `--check`.
- **Quem grava.** A entrada principal de toda solicitacao e o Tech Lead (regra 44), que garante `agentes:` com todos os papeis envolvidos. Em invocacao direta (admitida so para QA Expert, UX Expert e Business Analyst), o agent grava a entrada com `agentes:` completo e `origem: chamada-direta` e remete o resultado ao Tech Lead, que a revisa no bootstrap seguinte.
- **Transposicao pelo Tech Lead.** Quando um agent precisar de decisao que nao carrega, e o Tech Lead quem a envia, na delegacao ou no handoff, como extrato gerado por `sh scripts/memoria-index.sh --agente <papel> --corpo` (ou das entradas especificas). Se a pertinencia for duravel, o Tech Lead acrescenta o papel em `agentes:` da entrada; e a unica edicao de entrada alheia alem de `status`. O agent nao abre a memoria inteira por conta propria: pede ao Tech Lead o que falta.

- **Nunca editar entrada de outra sessao** para mudar a decisao: gravar uma entrada nova com `substitui:`. Editar a entrada original apenas para trocar `status: ativa` por `substituida` ou `encerrada`, e so depois que a nova ja estiver mergeada.
- **Entre instancias** (Tech Leads em maquinas diferentes, regra 47) vale a precedencia de merge: a decisao que chegou primeiro a branch principal e a vigente, e quem chega depois grava entrada nova com `substitui:` ou `tipo: bloqueio` com escalonamento ao solicitante. A entrada alheia so e tocada para marcar `substituida`, e depois que a nova estiver mergeada.
- `tipo: stack` e `tipo: contexto` sao unicos por projeto: antes de gravar, rodar `sh scripts/memoria-index.sh --tipo stack` e, se ja houver, nao gravar outra.
- `tipo: aceite` registra aprovacao ou reaprovacao explicita do solicitante (regra 12), com data e o que foi aprovado. Com `origem: intervencao-humana`, registra a confirmacao de que uma alteracao nao feita pelos agents foi intencional, ou a autorizacao para reverte-la (regra 48), listando no corpo os arquivos ou commits a que se refere.
- `tipo: backlog` e um item de trabalho; encerrar mudando `status`.
- `tipo: reserva` declara o escopo previsto de uma demanda em curso (regra 47), para que outra instancia do Tech Lead a enxergue antes do merge. Vai no primeiro commit da branch, com `instancia:`, `escopo: projeto` e o escopo previsto no corpo; e encerrada (`status: encerrada`) pela propria instancia no commit de fechamento da demanda. Reserva de outra instancia nunca e editada: colisao vai ao solicitante.
- As tabelas `DEC-STR-*` e `PRJ-DEC-*` em `../MEMORIA-COMPARTILHADA.md` e `../MEMORIA-PROJETO.md` estao **congeladas**: nao recebem linha nova. Decisao que as altera e uma entrada com `substitui: DEC-STR-nn`.
- O indice consolidado e gerado por `sh scripts/memoria-index.sh` (`--write` grava `../INDICE.md`, ignorado pelo git). Ninguem mantem indice a mao.
- `sh scripts/memoria-index.sh --check` valida todas as entradas; rodar antes do commit.

## Consolidacao periodica

Apenas o Tech Lead, em commit dedicado sem outras alteracoes, pode mover entradas `substituida` ou `encerrada` antigas para `../historico/` e apaga-las daqui. Entradas `ativa` nunca sao consolidadas.
