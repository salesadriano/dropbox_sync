# Design Tokens Quick Reference

## Color System Architecture

```css
/* Primitive tokens — the raw palette, never used directly in components */
:root {
  --color-slate-50: #f8fafc;
  --color-slate-100: #f1f5f9;
  --color-slate-900: #0f172a;
  --color-violet-500: #8b5cf6;
  --color-violet-600: #7c3aed;
}

/* Semantic tokens — map intent to primitives */
:root {
  /* Surfaces */
  --color-bg-base: var(--color-slate-50);
  --color-bg-elevated: #ffffff;
  --color-bg-overlay: var(--color-slate-100);

  /* Foreground */
  --color-text-primary: var(--color-slate-900);
  --color-text-secondary: #475569;  /* slate-600 */
  --color-text-muted: #94a3b8;      /* slate-400 */
  --color-text-inverse: #ffffff;

  /* Brand */
  --color-brand: var(--color-violet-500);
  --color-brand-hover: var(--color-violet-600);

  /* Semantic states */
  --color-destructive: #ef4444;     /* red-500 */
  --color-success: #22c55e;         /* green-500 */
  --color-warning: #f59e0b;         /* amber-500 */

  /* Border */
  --color-border-default: #e2e8f0;  /* slate-200 */
  --color-border-strong: #94a3b8;   /* slate-400 */
}
```

## Spacing Scale

```css
/* 4px base unit — consistent with 8-point grid */
:root {
  --space-1:  4px;
  --space-2:  8px;
  --space-3:  12px;
  --space-4:  16px;
  --space-5:  20px;
  --space-6:  24px;
  --space-8:  32px;
  --space-10: 40px;
  --space-12: 48px;
  --space-16: 64px;
  --space-20: 80px;
  --space-24: 96px;
}
```

## Typography Scale

```css
:root {
  /* Size */
  --text-xs:   0.75rem;   /* 12px */
  --text-sm:   0.875rem;  /* 14px */
  --text-base: 1rem;      /* 16px */
  --text-lg:   1.125rem;  /* 18px */
  --text-xl:   1.25rem;   /* 20px */
  --text-2xl:  1.5rem;    /* 24px */
  --text-3xl:  1.875rem;  /* 30px */
  --text-4xl:  2.25rem;   /* 36px */

  /* Weight */
  --font-normal: 400;
  --font-medium: 500;
  --font-semibold: 600;
  --font-bold: 700;

  /* Leading */
  --leading-tight:  1.25;
  --leading-snug:   1.375;
  --leading-normal: 1.5;
  --leading-relaxed: 1.625;
}
```

## Shadow Scale

```css
:root {
  --shadow-sm:  0 1px 2px 0 rgb(0 0 0 / 0.05);
  --shadow:     0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1);
  --shadow-md:  0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
  --shadow-lg:  0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);
  --shadow-xl:  0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1);
  --shadow-2xl: 0 25px 50px -12px rgb(0 0 0 / 0.25);
}
```

## Border Radius

```css
:root {
  --radius-sm:   0.125rem;  /* 2px  — subtle */
  --radius:      0.25rem;   /* 4px  — default */
  --radius-md:   0.375rem;  /* 6px  — cards */
  --radius-lg:   0.5rem;    /* 8px  — modals */
  --radius-xl:   0.75rem;   /* 12px — large cards */
  --radius-2xl:  1rem;      /* 16px — hero sections */
  --radius-full: 9999px;    /* pill — badges, avatars */
}
```

## Dark Mode Pattern

```css
/* System preference — no JS required */
@media (prefers-color-scheme: dark) {
  :root {
    --color-bg-base: #0f172a;
    --color-bg-elevated: #1e293b;
    --color-text-primary: #f1f5f9;
    --color-text-secondary: #94a3b8;
    --color-border-default: #334155;
  }
}

/* Manual toggle via [data-theme] attribute */
[data-theme="dark"] {
  --color-bg-base: #0f172a;
  /* ... */
}
```

## Contrast Checklist

```
Normal text (< 18px / < 14px bold):
  AA:  ≥ 4.5:1  ← minimum
  AAA: ≥ 7:1    ← preferred

Large text (≥ 18px / ≥ 14px bold):
  AA:  ≥ 3:1
  AAA: ≥ 4.5:1

UI components & graphical objects:
  AA:  ≥ 3:1
```
