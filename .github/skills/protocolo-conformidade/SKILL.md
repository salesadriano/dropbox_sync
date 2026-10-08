---
name: protocolo-conformidade
description: "Protocolo obrigatorio de verificacao local de conformidade arquitetural e de boas praticas. Deve ser acionado sempre que a tarefa envolver nova implementacao, refatoracao, correcao ou ajuste de codigo, APOS a implementacao e ANTES do handoff para QA. Le o diff local com git, deduz a stack, aplica clean-architecture e as skills de boas praticas correspondentes, e emite um parecer com achados classificados por severidade. Achados bloqueantes reprovam a entrega e sao devolvidos ao agent originador para correcao, sem depender de pipeline, CI, workflow ou qualquer execucao remota."
---

# Protocolo de Conformidade Arquitetural e de Boas Praticas

## Security Handoff

Esta skill nao substitui hardening de seguranca.

- Se o diff tocar autenticacao, autorizacao, segredos, dados sensiveis, sessao/cookies, CSP/CORS ou exposicao de API, aplicar tambem `security-best-practices` e `api-security-best-practices` e registrar o resultado como achado desta verificacao.
- Nunca incluir segredos, tokens, credenciais, connection strings ou chaves privadas no parecer, nos trechos citados ou nas evidencias.
- Ao citar codigo no parecer, mascarar qualquer valor sensivel encontrado no diff e registrar o achado como bloqueante.

## Scope Boundary

Esta skill verifica **aderencia do codigo entregue** a arquitetura e as boas praticas do catalogo.

- [`protocolo-tdd`](../protocolo-tdd/SKILL.md) e o gate de **testes** e permanece obrigatorio e independente. Esta skill nao valida cobertura nem piramide de testes; ela verifica se o codigo entregue respeita camadas, fronteiras e as regras da stack.
- [`review-documentation`](../review-documentation/SKILL.md) registra a entrega. Esta skill produz o parecer tecnico que alimenta esse registro, mas nao o substitui.
- [`clean-architecture`](../clean-architecture/SKILL.md) e as skills de stack sao as **fontes das regras**. Esta skill e o **procedimento** que as aplica sobre um diff concreto.
- A validacao funcional continua sendo do QA Expert. Esta skill nao valida comportamento, apenas conformidade estrutural e de praticas.

## Regra de acionamento obrigatorio

Esta skill deve ser usada obrigatoriamente sempre que a tarefa envolver:

- implementacao de codigo novo;
- refatoracao de codigo existente;
- correcao de defeito ou bug;
- ajuste pontual de codigo, por menor que seja.

A obrigatoriedade vale mesmo quando o solicitante nao mencionar arquitetura, revisao ou boas praticas. O agent que produziu a alteracao executa esta verificacao **antes** de declarar a implementacao concluida e **antes** de qualquer handoff.

## Execucao estritamente local

Gate local, nos termos da regra 16 do `AGENTS.md`: roda no ambiente do agent sobre o diff local, inclusive nao commitado, e nao pode ser adiado para o CI. Linter, type checker ou formatter ausentes sao registrados como limitacao no parecer e a analise segue pela leitura do diff; ausencia de ferramenta nunca dispensa a verificacao.

## Procedimento

### Passo 1 - Delimitar o escopo real da alteracao

Levantar exatamente o que mudou, sem depender de memoria da conversa:

```bash
git status --short
git diff --stat
git diff --name-only            # nao commitado
git diff --cached --name-only   # em stage
git diff                        # conteudo completo para leitura
```

Quando a alteracao ja estiver commitada localmente, comparar com a base da branch:

```bash
git diff --name-only <base>...HEAD
git diff <base>...HEAD
```

Registrar a lista final de arquivos avaliados. Arquivo alterado que nao entrou na lista nao foi verificado, e isso deve constar como limitacao do parecer.

### Passo 2 - Deduzir a stack e selecionar as skills aplicaveis

Usar a tabela de deteccao de stack de `../../agents/AGENTS.md` e as regras de prioridade de [`SKILL_HIERARCHY.md`](../SKILL_HIERARCHY.md).

Regras de selecao:

1. `clean-architecture` aplica-se **sempre**, em qualquer stack, como fonte das regras de dependencia, fronteira e coesao.
2. Adicionar a skill de stack mais especifica para os arquivos alterados (uma por ecossistema, nunca duas concorrentes).
3. Adicionar `supabase-postgres-best-practices` quando o diff tocar schema, migration, indice, policy RLS, funcao de banco ou SQL.
4. Adicionar `security-best-practices` e `api-security-best-practices` quando o diff tocar autenticacao, autorizacao, segredos, dados sensiveis, sessao, CORS/CSP ou exposicao de endpoint.
5. Adicionar `dotnet-clean-architecture` quando a stack for .NET/C#.
6. Ler apenas o `SKILL.md` de cada skill selecionada e, dentro dela, apenas a regra especifica necessaria (item 37 do `AGENTS.md`). Nunca carregar diretorio inteiro.

Registrar no parecer quais skills foram aplicadas e por que.

### Passo 3 - Verificar conformidade arquitetural

Aplicar sobre o diff, com base em `clean-architecture`:

| Verificacao | Pergunta objetiva | Regra de referencia |
|---|---|---|
| Direcao de dependencia | Alguma camada interna passou a depender de camada externa? | `dep-inward-only` |
| Propriedade da interface | A interface foi declarada junto do cliente, e nao do implementador? | `dep-interface-ownership` |
| Pureza de dominio | Entrou import de framework, ORM, HTTP ou driver em camada de dominio? | `dep-no-framework-imports`, `frame-domain-purity` |
| Dados na fronteira | Estrutura de framework atravessou fronteira em vez de tipo simples/DTO? | `dep-data-crossing-boundaries` |
| Ciclos | A alteracao criou dependencia ciclica entre modulos? | `dep-acyclic-dependencies` |
| Modelo rico | A regra de negocio ficou na entidade ou vazou para service/controller? | `entity-rich-not-anemic` |
| Invariantes | A entidade continua garantindo suas proprias invariantes? | `entity-encapsulate-invariants` |
| Persistencia na entidade | A entidade passou a conhecer como e persistida? | `entity-no-persistence-awareness` |
| Caso de uso | O caso de uso orquestra, sem implementar regra de negocio nem formatar apresentacao? | `usecase-orchestrates-not-implements`, `usecase-no-presentation-logic` |
| Dependencias explicitas | As dependencias entram por construtor/parametro, sem service locator ou singleton oculto? | `usecase-explicit-dependencies` |
| Transacao | A fronteira transacional continua no caso de uso? | `usecase-transaction-boundary` |
| Controller fino | O controller/endpoint/handler ficou fino? | `adapt-controller-thin` |
| Sistema externo | Integracao externa passou por gateway/anti-corruption layer? | `adapt-gateway-abstraction`, `adapt-anti-corruption-layer` |
| Coesao | Arquivos que mudam juntos ficaram juntos, e a estrutura ainda revela o dominio? | `comp-common-closure`, `comp-screaming-architecture` |

### Passo 4 - Verificar conformidade com a skill de stack

Para cada skill de stack selecionada no Passo 2, percorrer as regras aplicaveis aos arquivos alterados e verificar aderencia real, citando a regra pelo identificador quando a skill usar prefixos (`dep-`, `query-`, `sec-`, `arch-`, `rerender-`, etc.).

Cobrir, no minimo:

- padroes de estrutura e nomenclatura da stack;
- tratamento de erro e propagacao;
- validacao de entrada e contratos;
- acesso a dados, N+1, indices e transacoes quando houver persistencia;
- performance quando a skill da stack tratar o tema;
- praticas proibidas explicitamente pela skill (anti-patterns).

### Passo 5 - Verificar consistencia com o que ja existe no projeto

Alem das skills, comparar a alteracao com o proprio repositorio:

- o padrao adotado e o mesmo ja usado em modulos equivalentes?
- houve reimplementacao de componente/utilitario que ja existia?
- a alteracao contradiz decisao registrada no System Design, ARD ou nas memorias do pacote?
- a nomenclatura segue o vocabulario de dominio ja usado no codigo?

Divergencia encontrada aqui e achado, mesmo que o codigo esteja tecnicamente correto.

### Passo 6 - Classificar os achados

| Severidade | Criterio | Efeito |
|---|---|---|
| **Bloqueante** | Viola direcao de dependencia, pureza de dominio, fronteira transacional, regra de seguranca, ou pratica explicitamente proibida pela skill da stack. Tambem: segredo no codigo, dado sensivel exposto, quebra de contrato publico. | **Reprova.** Devolve ao agent originador. |
| **Maior** | Compromete manutenibilidade, coesao ou reuso sem quebrar a arquitetura. Regra recomendada da stack ignorada sem justificativa. Divergencia com padrao ja consolidado no projeto. | Reprova se houver mais de tres achados maiores, ou se um deles se repetir apos correcao. Caso contrario, vira ressalva com prazo. |
| **Menor** | Ajuste de estilo, nomenclatura, organizacao ou legibilidade sem impacto estrutural. | Nao reprova. Registrar como recomendacao. |

Toda decisao de severidade deve citar a regra que a sustenta. Achado sem regra de referencia nao pode ser bloqueante.

### Passo 7 - Emitir o parecer e decidir

Preencher `../../agents/templates/parecer-conformidade-template.md`.

Veredito possivel:

- **Aprovado**: nenhum achado bloqueante e no maximo tres achados maiores tratados como ressalva.
- **Aprovado com ressalvas**: sem bloqueante, com ressalvas registradas e owner definido.
- **Reprovado**: existe achado bloqueante, ou mais de tres maiores, ou reincidencia de achado ja apontado.

## Devolucao e ciclos de correcao

Seguem a regra 17 do `AGENTS.md`: devolucao acionavel (arquivo:linha, achado, regra violada com skill e identificador, correcao esperada, severidade) na secao `Devolucao ao agent` do template; reexecucao apos correcao com status de cada achado anterior; terceira reincidencia escala ao Tech Lead; justificativa tecnica so encerra achado com aceite do Tech Lead registrado em memoria, e nunca achado de seguranca.

## Modo compacto (porte P e M)

Conforme `Protocolo por porte` do `AGENTS.md`, em porte P e M o parecer e preenchido por excecao: identificacao, escopo do diff, stack e skills aplicadas, achados, veredito e, se houver, devolucao. As tabelas dos Passos 3, 4 e 5 sao substituidas pela linha `Checklist clean-architecture + <skill de stack> aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados`. O procedimento e o mesmo; muda apenas o que e transcrito. Em porte G, todas as secoes do template sao preenchidas.

## Saida

Parecer de conformidade em `../../agents/templates/parecer-conformidade-template.md`, no modo do porte, com veredito explicito. Em aprovacao, libera o handoff; em reprovacao, devolucao acionavel e handoff bloqueado. O parecer e referenciado pelo registro de entrega (regra 41), nunca copiado nele.

## Reference Files

Nao carregar o diretorio `references/` inteiro. Abrir apenas o arquivo necessario:

| Arquivo | Quando abrir |
|---|---|
| [references/comandos-locais.md](references/comandos-locais.md) | levantar o diff, rodar verificadores locais da stack e checar ciclos de dependencia sem pipeline |
| [references/exemplos-achados.md](references/exemplos-achados.md) | calibrar severidade e redigir o achado com regra de referencia e correcao esperada |
