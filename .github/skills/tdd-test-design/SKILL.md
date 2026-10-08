---
name: tdd-test-design
description: "Test design quality reference for the red-green loop: what a good test is, choosing and confirming the seams under test, mocking only at system boundaries, and the anti-patterns that produce tests worth deleting (implementation-coupled, tautological, horizontally sliced). Use while writing tests to decide WHAT to assert and WHERE to test. This skill does not replace protocolo-tdd, which remains the mandatory operational protocol (70/20/10 pyramid, Testcontainers, Cypress, DoD); use testing-strategy for conceptual coverage planning without implementation."
metadata:
  source: mattpocock/skills
---

# TDD Test Design

TDD is the red -> green loop. This skill is the reference that makes that loop produce tests worth keeping: what a good test is, where tests go, the anti-patterns, and the rules of the loop. Every section applies on every cycle: consult them before and during the loop, not after.

## Security Handoff

This skill does not replace security hardening.

- If work touches authentication, authorization, secrets, sensitive data, session/cookies, CSP/CORS, or API exposure, also apply `security-best-practices` and `api-security-best-practices`.
- Never include secrets, tokens, credentials, or private keys in tests, fixtures, factories, seeders, snapshots, logs, or generated artifacts. Test data must be synthetic.

## Scope Boundary

This skill is about test **design quality**, not about the delivery protocol.

- [`protocolo-tdd`](../protocolo-tdd/SKILL.md) is mandatory and remains authoritative for any development, refactor, or bug fix: it owns the 70/20/10 pyramid, real integration through Testcontainers, real E2E through Cypress without network stubs, test data governance, and the blocking DoD for QA handoff. When the two disagree, `protocolo-tdd` wins.
- [`testing-strategy`](../testing-strategy/SKILL.md) is for conceptual test planning and coverage design when no code is being written.
- Use this skill inside the red -> green cycle required by `protocolo-tdd`, to decide what each test asserts and at which seam.

Before exploring the codebase, read the project documentation and architecture records in the area you are touching so test names and interface vocabulary match the project's domain language.

## What a good test is

Tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't. A good test reads like a specification: "user can checkout with valid cart" tells you exactly what capability exists, and it survives refactors because it doesn't care about internal structure.

See [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking guidelines.

## Seams: where tests go

A **seam** is the public boundary you test at: the interface where you observe behavior without reaching inside. Tests live at seams, never against internals.

**Test only at pre-agreed seams.** Before writing any test, write down the seams under test and confirm them with the requester or with the System Design already approved for the demand. No test is written at an unconfirmed seam. You can't test everything, so agreeing the seams up front is how testing effort lands on the critical paths and complex logic instead of every edge case.

Ask: "What's the public interface, and which seams should we test?"

When the shape of that interface is itself in question (how deep the module is, where the seam belongs, what the interface should expose), consult [`clean-architecture`](../clean-architecture/SKILL.md) for boundary, port, and adapter vocabulary. It is a reference to consult, not a session to run.

## Anti-patterns

- **Implementation-coupled**: mocks internal collaborators, tests private methods, or verifies through a side channel (querying the database instead of using the interface). The tell: the test breaks when you refactor but behavior hasn't changed.
- **Tautological**: the assertion recomputes the expected value the way the code does (`expect(add(a, b)).toBe(a + b)`, a snapshot derived by hand the same way, a constant asserted equal to itself), so it passes by construction and can never disagree with the code. Expected values must come from an independent source of truth: a known-good literal, a worked example, the spec.
- **Horizontal slicing**: writing all tests first, then all implementation. Bulk tests verify _imagined_ behavior: you test the _shape_ of things rather than user-facing behavior, the tests go insensitive to real changes, and you commit to test structure before understanding the implementation. Work in **vertical slices** instead: one test -> one implementation -> repeat, each test a **tracer bullet** that responds to what the last cycle taught you.

## Rules of the loop

- **Red before green.** Write the failing test first, then only enough code to pass it. Don't anticipate future tests or add speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle.
- **Refactoring is not part of the red -> green cycle.** It belongs to the refactor step and to the review stage, and it must not change external behavior. The evidence of that refactor belongs in the delivery record required by [`review-documentation`](../review-documentation/SKILL.md).

## Note on the integration seam

This skill's "prefer a test DB" guidance in [mocking.md](mocking.md) is a general default. In this package the stronger rule applies: `protocolo-tdd` forbids mocking the data layer and requires a real database through Testcontainers for integration tests.
