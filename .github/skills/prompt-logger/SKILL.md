---
name: prompt-logger
description: >
  Registra cada prompt recebido em docs/prompts/, um arquivo por demanda, com o texto integral
  sanitizado, o porte atribuido, a intencao principal e as inferencias adotadas. Obrigatoria em toda
  solicitacao (AGENTS.md, regra 2). O log e a trilha de auditoria do que foi pedido; o que foi feito
  vive no registro de entrega, que o log referencia.
---

# Prompt Logger

## Security Handoff

Esta skill persiste conteudo de prompt em disco e, por isso, e uma superficie de tratamento de dados.

- Antes de gravar, remover ou mascarar segredos, credenciais, tokens, cookies, chaves, material copiado de ambientes protegidos e dados pessoais desnecessarios. Usar placeholders como `[TOKEN_REMOVIDO]`, `[SEGREDO_REMOVIDO]`, `[DADO_SENSIVEL_REDACTED]` e registrar que houve sanitizacao.
- `docs/prompts/` e versionado com o projeto (desbloqueado explicitamente no `.gitignore`). Tratar cada arquivo como conteudo publico: sanitizar antes de gravar, nunca depois.
- Se o prompt nao puder ser sanitizado com seguranca, nao gravar o log. Registrar a restricao na memoria de projeto e seguir com a execucao principal.
- Esta skill espelha a regra 2 de `../../agents/AGENTS.md`, que e a fonte autoritativa.

## O que o log e, e o que nao e

O log responde a uma unica pergunta: **o que foi pedido, e como foi entendido**. Ele nao registra plano de acao, entidades, contexto aplicado nem resultado esperado: isso e conteudo do registro de entrega (`review-documentation`, regra 41), que o log referencia por link quando existir.

## Um arquivo por demanda

- A primeira solicitacao de uma demanda cria o arquivo. Cada prompt seguinte **da mesma demanda** (refinamento, correcao, aprovacao, resposta a pergunta do agent) e anexado ao mesmo arquivo como um novo bloco numerado, com data e hora.
- Demanda nova abre arquivo novo. Criterio: muda o objetivo, o escopo ou o artefato principal.
- Prompts que sejam exclusivamente execucao de comando (`git`, `npm`, `docker`) sem interpretacao nao geram bloco.
- O texto do prompt e transcrito integralmente. Nunca resumir o prompt; resumir e a intencao.

Nome do arquivo:

```
docs/prompts/YYYY-MM-DD_HHMM_slug-da-intencao.md
```

`HHMM` e a hora real do primeiro prompt da demanda (nunca contador sequencial: sessoes paralelas escolheriam o mesmo numero). `slug` tem ate cinco palavras em kebab-case. Se o arquivo ja existir, ler antes de gravar: pode ser a mesma demanda em outra sessao; se for outra, acrescentar sufixo ao slug.

## Template

```markdown
---
date: YYYY-MM-DD
hora: HHMM
domain: <dominio>
porte: P | M | G
status: aberto | concluido
registro_de_entrega: <caminho do registro quando existir, senao "pendente">
---

# <slug-da-intencao>

## Prompt 1 — YYYY-MM-DD HH:MM

> <texto integral do prompt, sanitizado se necessario>

**Intencao:** <uma a tres frases: o que o solicitante quer, em termos de objetivo>

**Inferencias:** <apenas se houver ambiguidade; uma linha por inferencia, com a leitura adotada. Se nao houver, omitir a secao>

**Sanitizacao:** <apenas se houve; o que foi mascarado e por que. Se nao houve, omitir>

## Prompt 2 — YYYY-MM-DD HH:MM

> <texto integral>

**Intencao:** <...>
```

Ao concluir a demanda, atualizar `status` e `registro_de_entrega` no frontmatter. Reclassificacao de porte para baixo (regra 40) e registrada como uma linha `**Porte:** M -> P, motivo: ...` no bloco do prompt em que ocorreu.

## Regras de qualidade

- **Fidelidade**: o bloco `Prompt N` preserva o texto recebido; sanitizacao e a unica alteracao admitida, e e declarada.
- **Neutralidade**: inferencia feita e inferencia registrada. Nao omitir leituras adotadas sob ambiguidade.
- **Idioma**: o log segue o idioma do prompt.
- **Sem duplicacao**: nada que esteja no registro de entrega e repetido aqui. Diagrama Mermaid nao e exigido.
- **Automatico**: criar ou anexar sem pedir confirmacao ao solicitante.
