---
name: protocolo-tdd
description: Protocolo obrigatorio de engenharia de testes com TDD, integracao real via Testcontainers e E2E real com Cypress sem mocks de rede. Deve ser acionado obrigatoriamente sempre que a tarefa envolver desenvolvimento, refatoracao ou correcao de codigo.
---

# Protocolo de Engenharia de Testes (TDD)

## Security Handoff

Esta skill nao substitui hardening de seguranca.

- Se o trabalho tocar autenticacao, autorizacao, segredos, dados sensiveis, sessao/cookies, CSP/CORS ou exposicao de API, aplicar tambem `security-best-practices` e `api-security-best-practices`.
- Nunca incluir segredos, tokens, credenciais ou chaves privadas em exemplos, fixtures, diagramas, logs ou artefatos gerados.

## Objetivo

Padronizar a engenharia de testes com foco em confiabilidade real de ambiente, garantindo que desenvolvimento, QA e aprovacao final usem as mesmas regras operacionais de TDD, integracao e E2E.

## Regra de acionamento obrigatorio

Esta skill deve ser usada obrigatoriamente sempre que a tarefa envolver qualquer uma das situacoes abaixo:

- desenvolvimento de codigo novo
- refatoracao de codigo existente
- correcao de defeitos ou bugs em codigo

Essa obrigatoriedade vale mesmo quando a solicitacao do usuario nao mencionar testes explicitamente. Nesses casos, o protocolo TDD continua sendo a referencia operacional padrao para orientar implementacao, validacao e handoff.

## Quando usar

- Sempre que a tarefa envolver desenvolvimento, refatoracao ou correcao de codigo.
- Quando a entrega exigir TDD como estrategia obrigatoria de desenvolvimento.
- Quando for necessario validar integracao com banco real sem mocks na camada de dados.
- Quando houver fluxo E2E com Cypress e backend real, sem stubs de rede.
- Quando for necessario formalizar criterios de handoff bloqueantes para QA.

## Regras obrigatorias

### 1) Ciclo TDD Red-Green-Refactor

1. Red: escrever teste antes da implementacao, guiado pelos criterios BDD.
2. Green: implementar o minimo necessario para o teste passar.
3. Refactor: melhorar design e legibilidade sem alterar comportamento externo.

### 2) Piramide de testes 70/20/10

- 70% Unitario:
  - Foco em regras de negocio puras, isoladas de rede e banco.
  - Usar padrao AAA (Arrange, Act, Assert).
  - Tratar unidade como caixa-preta pela API publica.
- 20% Integracao:
  - Foco em contratos HTTP e persistencia real.
  - Proibido mockar camada de dados para validar repositorios/DAO.
  - Usar Testcontainers com PostgreSQL real para execucao de queries.
- 10% E2E:
  - Cypress contra frontend + backend + banco reais.
  - Proibido mockar/stubar backend no fluxo principal de E2E.
  - Proibido smoke test superficial; exigir jornadas de negocio completas.
  - Preferir multiplas assercoes por jornada para reduzir custo de setup.

### 3) Governanca de dados de teste

- Dados devem vir de seeder padrao ou de criacao programatica no roteiro.
- Nao depender de dado manual nem adivinhacao de IDs.
- Estado gerado no roteiro deve permanecer disponivel entre cenarios relacionados.
- Limpeza/teardown deve ocorrer apenas ao final do roteiro completo.

### 4) Resiliencia E2E e anti-flaky

- Frontend deve expor seletores `data-cy` ou `data-test` para elementos interativos.
- Nao usar seletor baseado em classe de estilo como estrategia principal.
- Falha flaky em ambiente integrado deve ser tratada como bloqueio ate correção da causa raiz.

### 5) DoD bloqueante para handoff ao QA

1. Evidencia de TDD aplicada e testes de unidade/integracao aprovados.
2. Evidencia de execucao isolada em container com comando oficial da arquitetura:
   - `docker compose run --rm <service> test`
3. Cobertura E2E dos criterios BDD Given/When/Then contra base real de homologacao.
4. Em frontend, System Design deve referenciar explicitamente o Design System validado.

## Checklist rapido de validacao

- TDD executado na ordem Red -> Green -> Refactor.
- Integracao com banco real via Testcontainers sem mocks de dados.
- E2E com Cypress sem `cy.intercept()` para fixture/stub do backend principal.
- Fluxos E2E cobrem sucesso, validacao, borda e exaustao quando critico.
- Dados de teste rastreaveis do seeder/roteiro e limpeza no final.
- Seletores estaveis via `data-cy`/`data-test`.
- Handoff ao QA contem evidencias e comando oficial de execucao.

## Saida esperada ao usar esta skill

- Plano de testes aderente a 70/20/10.
- Evidencias de execucao por camada.
- Registro explicito de proibicoes respeitadas (sem mocks de dados e sem stubs de rede no E2E principal).
- Criterios de aceite bloqueantes para QA claramente atendidos ou reportados como bloqueio.
