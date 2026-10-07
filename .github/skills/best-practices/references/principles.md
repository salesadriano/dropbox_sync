# Core Engineering Principles Quick Reference

## SOLID

| Principle | Rule | Violation Sign |
|-----------|------|----------------|
| **S** — Single Responsibility | One reason to change per class/module | God class with 500+ lines |
| **O** — Open/Closed | Open for extension, closed for modification | `if type == 'A'` chains everywhere |
| **L** — Liskov Substitution | Subclasses must be usable as their parent | Override that throws UnsupportedOperation |
| **I** — Interface Segregation | No client should depend on methods it doesn't use | Interface with 20 methods, clients use 2 |
| **D** — Dependency Inversion | Depend on abstractions, not concretions | `new EmailService()` deep inside business logic |

## DRY / WET / DAMP

```
DRY (Don't Repeat Yourself):
  Extract shared logic into a single authoritative source.
  ⚠ Don't over-apply — accidental duplication ≠ knowledge duplication.

WET (Write Everything Twice):
  Rule of three: allow up to 2 copies; refactor on the 3rd occurrence.

DAMP (Descriptive And Meaningful Phrases):
  In tests: prefer readable duplication over abstract helpers.
  Tests should be self-documenting — DRY can obscure intent.
```

## YAGNI / KISS

```
YAGNI (You Ain't Gonna Need It):
  Don't add functionality until it's needed.
  Speculative abstractions are liabilities — they have a maintenance cost now.

KISS (Keep It Simple, Stupid):
  The simplest solution that solves the problem is correct.
  Complexity budget: every abstraction must earn its keep.
```

## Fail Fast

```
Validate inputs at system boundaries.
Throw early when preconditions are violated — don't propagate invalid state.
// ✅
function divide(a: number, b: number): number {
  if (b === 0) throw new Error('Division by zero');
  return a / b;
}
```

## Command/Query Separation (CQS)

```
Commands: change state, return nothing (or only errors).
Queries: return data, change nothing.

// ❌ CQS violation — pops AND returns
const item = stack.pop();

// ✅ Separate concerns
stack.pop();          // command: changes state
const item = stack.peek(); // query: reads state
```

## Law of Demeter (Principle of Least Knowledge)

```
A module should only talk to its immediate friends.

// ❌ Train wreck — knows too much about internals
user.getAddress().getCity().getName()

// ✅ Delegate through the closest object
user.getCityName()
```

## Code Review Checklist

```
□ Does it do what the requirements say?
□ Is the logic clear without comments?
□ Are there edge cases not handled (null, empty, overflow)?
□ Are there security implications (injection, exposure)?
□ Is it testable? Are tests present?
□ Does it respect existing conventions and patterns?
□ Are dependencies appropriate (no unnecessary coupling)?
□ Will this be maintainable in 6 months?
```
