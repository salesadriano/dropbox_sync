---
name: testing-strategy
description: Design test strategies and test plans. Trigger with "how should we test", "test strategy for", "write tests for", "test plan", "what tests do we need", or when the user needs help with testing approaches, coverage, or test architecture.
---

# Testing Strategy

## Security Handoff

This skill does not replace security hardening.

- Never include secrets, tokens, credentials, connection strings, personal data, or private keys in the artifacts produced here. Sanitize any payload, log, or evidence copied from a real environment before persisting it.
- When the documented scope touches authentication, authorization, sensitive data, or API exposure, also apply `security-best-practices` and `api-security-best-practices`.

Design effective testing strategies balancing coverage, speed, and maintenance.

## Scope Boundary

This skill is for **conceptual planning** of test strategy and coverage, when no code is being written.

- The moment the task involves development, refactor, or bug fix, [`protocolo-tdd`](../protocolo-tdd/SKILL.md) becomes mandatory and authoritative: it owns the 70/20/10 pyramid, real integration through Testcontainers, real E2E through Cypress without network stubs, test data governance, and the blocking verdict for QA handoff. A plan produced here must fit that protocol, never replace or relax it.
- [`tdd-test-design`](../tdd-test-design/SKILL.md) is the reference for test quality inside the red -> green cycle: what to assert and at which seam.
- The generic pyramid below is a teaching model. When code is being delivered in this package, the binding proportions and the per-layer prohibitions are the ones in `protocolo-tdd`.

## Testing Pyramid

```
        /  E2E  \         Few, slow, high confidence
       / Integration \     Some, medium speed
      /    Unit Tests  \   Many, fast, focused
```

## Strategy by Component Type

- **API endpoints**: Unit tests for business logic, integration tests for HTTP layer, contract tests for consumers
- **Data pipelines**: Input validation, transformation correctness, idempotency tests
- **Frontend**: Component tests, interaction tests, visual regression, accessibility
- **Infrastructure**: Smoke tests, chaos engineering, load tests

## What to Cover

Focus on: business-critical paths, error handling, edge cases, security boundaries, data integrity.

Skip: trivial getters/setters, framework code, one-off scripts.

## Output

Produce a test plan with: what to test, test type for each area, coverage targets, and example test cases. Identify gaps in existing coverage.
