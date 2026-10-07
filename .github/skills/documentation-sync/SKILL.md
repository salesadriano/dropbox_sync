---
name: documentation-sync
description: "Use after implementations, bug fixes, refactors, contract changes, test updates, infrastructure changes, or documentation-impacting deliveries. Performs repository-wide documentation impact analysis and updates only the documents, architecture records, QA artifacts, and operational guides that materially changed. In governed repositories, use it to keep mandatory templates and records synchronized without replacing the formal approval flow."
---

# Documentation Sync

Skill para revisar impacto documental apos entregas tecnicas, mantendo codigo, arquitetura, QA, requisitos e guias operacionais coerentes com o estado real do repositorio.

## Security Handoff

Esta skill nao substitui hardening de seguranca.

- Se o trabalho tocar autenticacao, autorizacao, segredos, dados sensiveis, sessao/cookies, CSP/CORS ou exposicao de API, aplicar tambem `security-best-practices` e `api-security-best-practices`.
- Nunca incluir segredos, tokens, credenciais ou chaves privadas em exemplos, fixtures, diagramas, logs ou artefatos gerados.

## Quando ativar

Ative esta skill apos qualquer mudanca relevante, como:
- implementacao de feature;
- bug fix;
- refatoracao com impacto estrutural ou funcional;
- alteracao de API, eventos, contratos, jobs, integracoes ou persistencia;
- ajuste de testes, setup, deploy, CI, infraestrutura ou operacao;
- mudanca em requisitos, escopo, fluxos, evidencias de QA ou artefatos de fechamento.

## Objetivo operacional

Depois de uma entrega tecnica, a skill deve:
1. levantar o impacto tecnico real da mudanca;
2. revisar a documentacao geral e a documentacao do dominio afetado;
3. atualizar somente os documentos realmente impactados, evitando mudancas cosmeticas;
4. registrar explicitamente quando nenhuma atualizacao documental for necessaria;
5. preservar rastreabilidade entre implementacao, arquitetura, QA e fechamento da entrega.

## Nao confundir com `review-documentation`

Use esta skill para manter documentacao viva e artefatos existentes coerentes com o estado atual do repositorio.

Nao use esta skill como substituto do registro tecnico formal da entrega. Quando a demanda pedir um review, changelog tecnico, journal de entrega ou registro retroativo da mudanca, complemente com `../review-documentation/`.

Regra pratica:
- `documentation-sync` atualiza o que ja existe e ficou potencialmente desatualizado;
- `review-documentation` cria ou completa o registro formal da mudanca executada.

## Fontes obrigatorias de revisao

### 1. Baseline geral do repositorio
Revisar sempre, pelo menos por impacto indireto:
- `README.md` ou documento equivalente de onboarding;
- documentacao principal em `docs/` ou pasta equivalente;
- artefatos de arquitetura como System Design, ADR, ARD ou diagramas principais, quando existirem;
- artefatos de requisitos como PRD, user stories, declaracao de escopo ou casos de uso, quando existirem;
- artefatos de QA, matriz de testes, rastreabilidade e evidencias, quando existirem;
- pasta de review, changelog tecnico ou registro formal de entrega adotado pelo projeto, quando existir.

### 2. Baseline por dominio afetado
Revisar quando a mudanca tocar o dominio correspondente:
- documentacao de API, contratos, eventos ou integracoes;
- documentacao de dados, migracoes, capacidade ou operacao;
- documentacao de UX, Design System ou fluxos de interface;
- documentacao de deploy, ambiente, observabilidade, operacao e runbooks;
- artefatos de fechamento formal ou revisao consolidada, quando a entrega fizer parte desse fluxo.

## Regra principal de atualizacao

Nao atualizar documentacao por reflexo ou cosmetica. Atualize somente quando a entrega alterar pelo menos um dos pontos abaixo:
- comportamento funcional;
- contrato de API ou integracao;
- regra de negocio;
- fluxo operacional;
- arquitetura, componentes ou dependencias;
- setup, deploy ou operacao;
- estrategia de teste, evidencia de QA ou rastreabilidade;
- requisitos formais, historias, casos de uso, PRD, ARD ou System Design;
- artefatos de revisao ou fechamento da entrega.

Se nada disso mudou, registre explicitamente que a revisao documental foi executada e que nao houve impacto material.

## Workflow obrigatorio

### Passo 1. Levantar o impacto tecnico real
Inspecione:
- arquivos alterados;
- contratos, interfaces ou integracoes afetadas;
- modelos, migracoes, eventos ou persistencia;
- testes criados ou alterados;
- mudancas de ambiente, deploy, operacao e dependencias.

### Passo 2. Mapear impacto documental
Para cada mudanca tecnica, pergunte objetivamente:
- isso altera o que o sistema faz?
- isso altera como o sistema e operado?
- isso altera como o sistema e testado?
- isso altera o que a documentacao afirma hoje?
- isso cria, remove ou modifica uma capacidade que precisa aparecer em requisitos, arquitetura, QA ou fechamento?

### Passo 2.1. Garantir diretorios de documentacao
Antes de escrever novos artefatos documentais, confirme que os diretorios de destino existem (por exemplo `docs/` ou pasta equivalente definida pelo projeto).
Se algum diretorio necessario nao existir, crie com `create_directory` antes de gerar ou atualizar os arquivos. Esta verificacao deve ser feita uma unica vez por ciclo de atualizacao.

### Passo 3. Revisar documentacao em camadas
Revise na ordem:
1. setup, visao geral e onboarding;
2. requisitos, escopo, historias e casos de uso;
3. arquitetura, System Design, ARD, ADR e diagramas;
4. QA, matriz de testes, rastreabilidade e evidencias;
5. registro tecnico (review/changelog) ou artefato equivalente.

### Passo 4. Atualizar apenas o necessario

#### Requisitos e escopo
Atualize quando houver nova capacidade, mudanca de comportamento, nova restricao, divergencia tratada ou mudanca de aceite.

#### Arquitetura e design
Atualize quando houver mudanca em componentes, integracoes, capacidade, topologia, Design System, contratos arquiteturais ou operacionais.

#### QA e rastreabilidade
Atualize quando houver nova cobertura, nova lacuna, mudanca de estrategia de validacao, nova evidencia ou mudanca nas dependencias de aceite.

#### Operacao e infraestrutura
Atualize quando houver mudanca em ambiente, deploy, observabilidade, jobs, processos assicronos, integracoes externas ou procedimento operacional.

#### Fechamento formal
Atualize quando a entrega exigir registro em review tecnico, revisao consolidada, aprovacao final ou artefato equivalente adotado no projeto.

### Passo 5. Registrar conclusao documental
Ao final da revisao, a skill deve sempre produzir um destes resultados:
- documentos atualizados e coerentes com a entrega; ou
- declaracao objetiva de que a revisao documental foi executada e nao houve impacto material.

## Regras de qualidade

- A documentacao deve refletir o estado real do repositorio, nao o roadmap desejado.
- Nao invente cobertura de teste, evidencia, smoke, homologacao ou deploy que nao foi executado.
- Diferencie claramente evidencia existente, lacuna conhecida e proximo passo recomendado.
- Quando houver mudanca funcional, avalie primeiro impacto em requisitos, arquitetura, QA e operacao antes de ajustar documentos de visao geral.
- Se houver conflito entre documentacao antiga e implementacao nova, corrija a documentacao em vez de mascarar a divergencia.

## Checklist minimo

- [ ] Alteracoes tecnicas mapeadas
- [ ] Diretorios de documentacao necessarios existentes (ou criados antes da escrita)
- [ ] Impacto em setup e operacao avaliado
- [ ] Impacto em requisitos e arquitetura avaliado
- [ ] Impacto em QA, evidencias e rastreabilidade avaliado
- [ ] Registro tecnico (review/changelog) ou artefato equivalente atualizado quando aplicavel
- [ ] Declarado explicitamente se nao houve impacto documental material

## Arquivo de apoio

Use o checklist em `assets/template/documentation-impact-checklist.md` para conduzir a revisao antes de encerrar a tarefa.

## Saida esperada

Ao terminar, a entrega deve deixar o repositorio com:
- implementacao e evidencias coerentes;
- documentacao revisada e atualizada quando necessario;
- requisitos, arquitetura, QA e operacao alinhados a mudanca;
- rastreabilidade clara entre alteracao tecnica, impacto funcional e evidencia disponivel.

## References

- [Sync Strategy Quick Reference](references/sync-strategy.md) — decision tree for what to update, layer map, staleness detection, anti-patterns, atomic PR checklist