---
name: accessibility-review
description: Run a WCAG 2.2 AA accessibility audit on a design or page. Trigger with "audit accessibility", "check a11y", "is this accessible?", or when reviewing a design or implemented page for color contrast, keyboard navigation, touch target size, or screen reader behavior before handoff. Prefer this skill for review-only assessment, not for implementation-heavy remediation.
argument-hint: "<Figma URL, URL, or description>"
---

# /accessibility-review

Audit a design or page for WCAG 2.2 AA accessibility compliance.

## When To Prefer Another Skill

- Use `accessibility` when the main task is to fix web accessibility issues in existing UI.
- Use `accessibility-compliance` when the main task is to implement accessible patterns, ARIA interactions, or mobile accessibility support.
- Use this skill when the expected output is an audit, finding list, compliance assessment, or pre-handoff review without remediation work in the same step.

## Usage

```
/accessibility-review $ARGUMENTS
```

Audit for accessibility: @$1

## WCAG 2.2 AA Quick Reference

### Perceivable
- **1.1.1** Non-text content has alt text
- **1.3.1** Info and structure conveyed semantically
- **1.4.3** Contrast ratio >= 4.5:1 (normal text), >= 3:1 (large text)
- **1.4.11** Non-text contrast >= 3:1 (UI components, graphics)

### Operable
- **2.1.1** All functionality available via keyboard
- **2.4.3** Logical focus order
- **2.4.7** Visible focus indicator
- **2.4.11** *(new in 2.2)* Focus not fully obscured by sticky headers or overlays
- **2.5.3** Label in name — accessible name contains visible label text
- **2.5.7** *(new in 2.2)* Dragging movements have single-pointer alternatives
- **2.5.8** *(new in 2.2)* Touch/pointer target minimum 24×24 CSS pixels (AA); 44×44 recommended

### Understandable
- **3.2.1** Predictable on focus (no unexpected changes)
- **3.2.6** *(new in 2.2)* Consistent help mechanism placement across pages
- **3.3.1** Error identification (describe the error)
- **3.3.2** Labels or instructions for inputs
- **3.3.7** *(new in 2.2)* Redundant entry — don't ask users to re-enter info already provided
- **3.3.8** *(new in 2.2)* Accessible authentication — no cognitive function test required to log in

### Robust
- **4.1.2** Name, role, value for all UI components

## Common Issues

1. Insufficient color contrast
2. Missing form labels
3. No keyboard access to interactive elements
4. Missing alt text on meaningful images
5. Focus traps in modals
6. Missing ARIA landmarks
7. Auto-playing media without controls
8. Time limits without extension options

## Testing Approach

1. Automated scan (catches ~30% of issues)
2. Keyboard-only navigation
3. Screen reader testing (VoiceOver, NVDA)
4. Color contrast verification
5. Zoom to 200% — does layout break?

## Output

```markdown
## Accessibility Audit: [Design/Page Name]
**Standard:** WCAG 2.2 AA | **Date:** [Date]

### Summary
**Issues found:** [X] | **Critical:** [X] | **Major:** [X] | **Minor:** [X]

### Findings

#### Perceivable
| # | Issue | WCAG Criterion | Severity | Recommendation |
|---|-------|---------------|----------|----------------|
| 1 | [Issue] | [1.4.3 Contrast] | 🔴 Critical | [Fix] |

#### Operable
| # | Issue | WCAG Criterion | Severity | Recommendation |
|---|-------|---------------|----------|----------------|
| 1 | [Issue] | [2.1.1 Keyboard] | 🟡 Major | [Fix] |

#### Understandable
| # | Issue | WCAG Criterion | Severity | Recommendation |
|---|-------|---------------|----------|----------------|
| 1 | [Issue] | [3.3.2 Labels] | 🟢 Minor | [Fix] |

#### Robust
| # | Issue | WCAG Criterion | Severity | Recommendation |
|---|-------|---------------|----------|----------------|
| 1 | [Issue] | [4.1.2 Name, Role, Value] | 🟡 Major | [Fix] |

### Color Contrast Check
| Element | Foreground | Background | Ratio | Required | Pass? |
|---------|-----------|------------|-------|----------|-------|
| [Body text] | [color] | [color] | [X]:1 | 4.5:1 | ✅/❌ |

### Keyboard Navigation
| Element | Tab Order | Enter/Space | Escape | Arrow Keys |
|---------|-----------|-------------|--------|------------|
| [Element] | [Order] | [Behavior] | [Behavior] | [Behavior] |

### Screen Reader
| Element | Announced As | Issue |
|---------|-------------|-------|
| [Element] | [What SR says] | [Problem if any] |

### Priority Fixes
1. **[Critical fix]** — Affects [who] and blocks [what]
2. **[Major fix]** — Improves [what] for [who]
3. **[Minor fix]** — Nice to have
```

## If Connectors Available

If **~~design tool** is connected:
- Inspect color values, font sizes, and touch targets directly from Figma
- Check component ARIA roles and keyboard behavior in the design spec

If **~~project tracker** is connected:
- Create tickets for each accessibility finding with severity and WCAG criterion
- Link findings to existing accessibility remediation epics

## Tips

1. **Start with contrast and keyboard** — These catch the most common and impactful issues.
2. **Test with real assistive technology** — My audit is a great start, but manual testing with VoiceOver/NVDA catches things I can't.
3. **Prioritize by impact** — Fix issues that block users first, polish later.

## References

- [Accessibility Review Checklist](references/checklist.md) — WCAG AA critical checks, interactive component patterns, testing tools, severity classification
