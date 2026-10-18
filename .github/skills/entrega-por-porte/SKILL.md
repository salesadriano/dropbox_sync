---
name: entrega-por-porte
description: >
  Faz o porte P existir de verdade e encurta o registro de entrega em P e M: criterios objetivos de
  P (ate 50 linhas de codigo, sem contrato, schema, auth, segredo, dado sensivel, fronteira,
  pipeline ou dependencia), o proprio Tech Lead implementa, os dois gates fecham num parecer
  combinado, QA por amostragem (1 em N, padrao 5), e um unico arquivo em docs/reviews/ pelo template
  registro-de-entrega-curto-template.md. Use ao classificar o porte e ao escolher o formato do
  registro; prefira `review-documentation` para o registro completo de porte G e `protocolo-tdd` e
  `protocolo-conformidade` para o conteudo de cada gate.
---

# Entrega por porte: P de verdade e registro curto

## Security Handoff

O porte P e definido pelo que o diff **nao** toca. Autenticacao, autorizacao, segredo, dado sensivel, contrato publico e fronteira arquitetural tiram a demanda de P por criterio, nao por juizo; e nesse caso os cenarios negativos da Regra 6 de `protocolo-tdd` continuam obrigatorios e nunca se compactam. Em qualquer porte, aplicar `security-best-practices` e `api-security-best-practices` quando o diff tocar esses pontos, e nunca gravar segredo, token ou dado pessoal no registro de entrega.

## Scope Boundary

- A regra 40 e a secao *Protocolo por porte* do `AGENTS.md` definem P, M e G; esta skill da a P criterios objetivos e um fluxo proprio, e a P e M um registro curto. Nao muda G.
- [`review-documentation`](../review-documentation/SKILL.md) e a skill do registro de entrega; o template curto desta skill e a forma que ela assume em P e M. Em G continuam os arquivos proprios.
- [`protocolo-tdd`](../protocolo-tdd/SKILL.md) e [`protocolo-conformidade`](../protocolo-conformidade/SKILL.md) continuam sendo os dois gates, com o seu conteudo; aqui muda so **onde** o parecer e escrito (uma secao do registro curto) e **quem** valida depois (QA por amostragem em P).
- [`prompt-logger`](../prompt-logger/SKILL.md) registra o porte na entrada; esta skill diz como decidi-lo.

## Origem

Praticas adotadas num projeto governado por este pacote em 14/10/2026 (itens 5 e 7 de onze mods de governanca) e trazidas ao modelo em 15/10/2026 (entrada `2026-10-15-0914-skills-a-partir-dos-mods-de-governanca`). Diagnostico medido la: uma correcao de 6 linhas levou 58 minutos e cerca de 180 mil tokens, e cada demanda produzia de 4 a 6 arquivos em `docs/reviews/`; o custo fixo do protocolo dominava o custo do codigo, e o porte P da regra 40 nunca era aplicado.

## Fluxo P

Detalhe, com os criterios e a contagem da amostragem, em [references/fluxo-p.md](references/fluxo-p.md). Em resumo:

- **Criterios, todos obrigatorios:** diff de ate **50 linhas de codigo** (adicoes e remocoes em arquivos de producao e de teste, sem documentacao); **nao toca** contrato publico, schema ou migration, autenticacao ou autorizacao, segredo, dado sensivel, fronteira arquitetural, pipeline, arquivo de congelamento de versoes nem dependencia; e **nao e defeito de alta criticidade**. Falhou um criterio, e M. Sobe para M ao primeiro sinal, em qualquer ponto, sem justificativa; descer continua exigindo justificativa no log de prompt (regra 40).
- **Quem executa:** o proprio Tech Lead, sem delegar ao Senior Developer, sob `protocolo-tdd` e `protocolo-conformidade`. Os dois gates fecham num **parecer combinado**, que e a secao *Gates* do registro curto.
- **Testes:** so os dos itens afetados, por arquivo de teste (Regra 8), com parada no primeiro erro (Regra 9). Nao se compacta: Regra 6 (seguranca e acesso) quando o diff tocar rota, guard ou sessao (o que, pelos criterios, em geral ja tira a demanda de P) e Regra 9.
- **QA por amostragem:** o QA Expert valida **1 em cada N** registros P (padrao N = 5), contados pelo Tech Lead desde a ultima validacao em P, ou quando o Tech Lead pedir fora da contagem por risco. Validacao por evidencia: audita o parecer combinado, reexecuta os testes dos itens afetados, acrescenta cenarios de risco; sem mutantes nem arquivo `qa-*`. O registro declara `QA: amostragem <n> de <N> - validada em <data> | nao validada`.
- **Tres abordagens:** dispensadas; uma linha com a causa raiz e por que a solucao e unica. `documentation-writer` e `commit-writer` opcionais (regras 4 e 5). Aprovacao do Tech Lead em uma linha no registro.

## Registro curto (P e M)

Template: [`registro-de-entrega-curto-template.md`](../../agents/templates/registro-de-entrega-curto-template.md). Um unico arquivo em `docs/reviews/`, `YYYY-MM-DD-HHMM-<slug>.md`, com **oito secoes fixas**, nesta ordem: pedido e porte; causa ou decisao; arquivos; testes rodados; gates; QA; riscos e rollback; links e aceites. Ele e o registro de entrega da regra 41 **e** carrega, como secoes, o parecer de testes, o parecer de conformidade e a validacao do QA. Em P e M nao se cria arquivo separado para nenhum dos tres.

Regras de preenchimento:

- contagens de testes sao **literais** copiadas da saida do runner (total, aprovados, falhos, duracao), nunca arredondadas; `documentation-writer` transcreve sem resumir;
- secao sem conteudo recebe `Nao aplicavel: <motivo>`, nunca placeholder;
- reprovacao de gate ou do QA **atualiza o mesmo arquivo** (as secoes *Gates* e *QA* ganham a linha do ciclo); nunca se abre outro;
- memoria, commit e PR apontam para o arquivo por link e nao repetem o que esta nele.

Em M, a validacao do QA e independente sobre os itens afetados e entra como secao, com os arquivos `qa-*` e o sha256 de cada um para o aceite do solicitante. A aprovacao final e a revisao consolidada do Tech Lead em M continuam nos templates proprios do protocolo (`Protocolo por porte`), o que deixa M com ate tres arquivos.

**G nao muda:** `evidencia-testes-template.md`, `parecer-conformidade-template.md`, validacao do QA, revisao consolidada e aprovacao final em arquivos proprios. Registros existentes nunca sao reescritos no formato novo.

## Relacao com o protocolo

Desde 15/10/2026 (decisao de Sales, entrada `2026-10-15-1050-regras-do-pacote-absorvem-os-mods`), o fluxo P e o registro curto sao norma do pacote: regra 40 (criterios de P) e secao *Protocolo por porte* do `AGENTS.md` (*Fluxo P*: o Tech Lead implementa, parecer combinado, QA por amostragem; registro curto em P e M). Esta skill e a referencia operacional; o projeto registra na entrada de adocao o N da amostragem, o limite de linhas se for outro e os caminhos que tiram a demanda de P.

## Adocao num projeto

A skill e o template sao transversais e vao com todo projeto gerado; registrar numa entrada `tipo: decisao`, `escopo: projeto`, `agentes: tech-lead, senior-developer, qa-expert`: o N da amostragem, o limite de linhas se for outro, a lista de caminhos que tiram a demanda de P (pipeline, congelamento, matriz de autorizacao e equivalentes do projeto) e a data a partir da qual os registros de P e M usam o template curto.
