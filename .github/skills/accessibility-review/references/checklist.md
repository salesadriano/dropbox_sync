# Accessibility Review Checklist

## Critical — Fix Before Launch (WCAG AA)

### Perceivable
- [ ] All images have meaningful `alt` text (or `alt=""` for decorative)
- [ ] Text contrast ratio ≥ 4.5:1 for normal text, ≥ 3:1 for large text (18px+/14px bold+)
- [ ] UI components and graphical objects contrast ratio ≥ 3:1
- [ ] No information conveyed by color alone
- [ ] Videos have captions; audio has transcripts
- [ ] Content does not depend on sensory characteristics (shape, color, position only)

### Operable
- [ ] All interactive elements reachable and operable via keyboard
- [ ] No keyboard traps — focus can always be moved away
- [ ] Visible focus indicator on all interactive elements
- [ ] Skip navigation link available (or landmarks used)
- [ ] No content flashes more than 3 times per second
- [ ] Sufficient time provided for timed interactions (or user can extend)

### Understandable
- [ ] `<html lang="xx">` set to correct language
- [ ] Error messages clearly identify which field has an error and how to fix it
- [ ] Form labels associated with their inputs (`for`/`id` or wrapping label)
- [ ] Consistent navigation across pages
- [ ] No unexpected context changes on focus or input

### Robust
- [ ] Valid, well-formed HTML (no duplicate IDs, no unclosed tags)
- [ ] ARIA roles, states, and properties used correctly
- [ ] Name, role, value available for all UI components
- [ ] Status messages announced without keyboard focus (aria-live)

---

## Interactive Component Patterns

### Buttons vs Links
```html
<!-- ✅ Button: triggers action -->
<button type="button" onclick="openModal()">Open</button>

<!-- ✅ Link: navigates to URL -->
<a href="/dashboard">Dashboard</a>

<!-- ❌ Never: div or span as clickable without role -->
<div onclick="openModal()">Open</div>

<!-- ✅ If you must: add role and keyboard support -->
<div role="button" tabindex="0" onclick="openModal()"
     onkeydown="if(event.key==='Enter') openModal()">Open</div>
```

### Modal Dialog
```html
<div role="dialog" aria-modal="true" aria-labelledby="dialog-title">
  <h2 id="dialog-title">Confirm Delete</h2>
  <!-- ✅ Trap focus within modal -->
  <!-- ✅ Return focus to trigger on close -->
  <!-- ✅ Close on Escape key -->
</div>
```

### Form Field
```html
<!-- ✅ Explicit label association -->
<label for="email">Email address</label>
<input id="email" type="email" aria-describedby="email-hint email-error"
       aria-required="true" aria-invalid="true">
<span id="email-hint">We'll never share your email.</span>
<span id="email-error" role="alert">Please enter a valid email address.</span>
```

---

## Testing Tools

| Tool | Use |
|------|-----|
| axe DevTools | Automated WCAG scan — catches ~40% of issues |
| Lighthouse | Quick audit in Chrome DevTools |
| NVDA + Firefox | Windows screen reader testing |
| VoiceOver + Safari | macOS/iOS screen reader testing |
| Keyboard only | Tab through entire flow — most impactful manual test |
| Color contrast analyzer | Desktop tool for precise contrast measurement |

---

## Severity Classification

| Level | Description | Timeline |
|-------|-------------|----------|
| **Critical** | Completely blocks users with disability | Fix immediately |
| **High** | Significantly impairs but workaround exists | Fix in current sprint |
| **Medium** | Causes confusion or extra effort | Fix in next sprint |
| **Low** | Minor inconvenience | Fix in backlog |
