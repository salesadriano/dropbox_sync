---
name: design-md
description: Analyze existing interface artifacts and synthesize a reusable DESIGN.md or design-system summary for any project. Use when consolidating screenshots, HTML/CSS, tokens, Storybook, Figma exports, or implemented UI into a semantic design language. Do not use for marketing-only pages.
---

# DESIGN.md Synthesis Skill

You are an expert Design Systems Lead. Your goal is to analyze the design artifacts available in the repository or provided by the user and synthesize a semantic design system into a file named `DESIGN.md` or into the design-system document adopted by the project.

## Security Handoff

This skill does not replace security hardening.

- If work touches authentication, authorization, secrets, sensitive data, session/cookies, CSP/CORS, or API exposure, also apply `security-best-practices` and `api-security-best-practices`.
- Never include secrets, tokens, credentials, or private keys in examples, fixtures, diagrams, logs, or generated artifacts.

## Overview

This skill helps create design-system documentation that can serve as a source of truth for future UI implementation, design review, component work, or documentation sync in any project. The output should translate technical design details into consistent semantic language that can be reused by designers, developers, QA, and architecture records.

## Prerequisites

- At least one available design artifact, such as screenshots, rendered pages, Storybook stories, Figma exports, component docs, HTML/CSS, design tokens, or implemented UI.
- Access to repository files or provided assets that reflect the current interface language.

## The Goal

The `DESIGN.md` file should serve as a compact source of truth for the visual language of the project. It must help future contributors understand atmosphere, palette, typography, component rules, spacing, interaction patterns, and the rationale behind those choices without tying the documentation to a single tool or vendor.

## Retrieval and Networking

To analyze a project, retrieve the available design signals using the tools and assets already adopted by that project. Prefer repository-local sources first, then user-provided assets, then external design tools if they are explicitly part of the workflow.

Recommended retrieval order:

1. **Repository-local design sources**
   - component libraries and Storybook stories
   - CSS, Tailwind config, tokens, theme files, or design-tokens JSON
   - existing design-system documents, screenshots, and UI tests

2. **User-provided design assets**
   - screenshots
   - exported mockups
   - component specs
   - style guides

3. **External design tools when explicitly available**
   - Figma exports or documented URLs
   - vendor design tooling already used by the project
   - generated HTML or static previews

When multiple sources conflict, treat the implemented UI and the repository's current design tokens as the primary source of truth, and record meaningful divergences in the output.

## Analysis & Synthesis Instructions

### 1. Extract Project Identity
- Locate the product or module name.
- Identify the artifact scope being documented, such as app-wide system, admin module, dashboard family, or component library.

### 2. Define the Atmosphere
Evaluate the screenshot and HTML structure to capture the overall "vibe." Use evocative adjectives to describe the mood (e.g., "Airy," "Dense," "Minimalist," "Utilitarian").

### 3. Map the Color Palette
Identify the key colors in the system. For each color, provide:
- A descriptive, natural language name that conveys its character (e.g., "Deep Muted Teal-Navy")
- The specific hex code in parentheses for precision (e.g., "#294056")
- Its specific functional role (e.g., "Used for primary actions")

### 4. Translate Geometry & Shape
Convert technical `border-radius` and layout values into physical descriptions:
- Describe `rounded-full` as "Pill-shaped"
- Describe `rounded-lg` as "Subtly rounded corners"
- Describe `rounded-none` as "Sharp, squared-off edges"

### 5. Describe Depth & Elevation
Explain how the UI handles layers. Describe the presence and quality of shadows (e.g., "Flat," "Whisper-soft diffused shadows," or "Heavy, high-contrast drop shadows").

## Output Guidelines

- **Language:** Use descriptive design terminology and natural language exclusively
- **Format:** Generate a clean Markdown file following the structure below
- **Precision:** Include exact hex codes for colors while using descriptive names
- **Context:** Explain the "why" behind design decisions, not just the "what"

## Output Format (DESIGN.md Structure)

```markdown
# Design System: [Project Title]
**Scope:** [App, module, product area, or component library]

## 1. Visual Theme & Atmosphere
(Description of the mood, density, and aesthetic philosophy.)

## 2. Color Palette & Roles
(List colors by Descriptive Name + Hex Code + Functional Role.)

## 3. Typography Rules
(Description of font family, weight usage for headers vs. body, and letter-spacing character.)

## 4. Component Stylings
* **Buttons:** (Shape description, color assignment, behavior).
* **Cards/Containers:** (Corner roundness description, background color, shadow depth).
* **Inputs/Forms:** (Stroke style, background).

## 5. Layout Principles
(Description of whitespace strategy, margins, and grid alignment.)
```

## Usage Example

To use this skill in any project:

1. **Gather available design sources:**
   ```
   Read screenshots, Storybook stories, CSS/theme files, or component docs for the target product area
   ```

2. **Inspect one or more representative screens or components:**
   ```
   Review the implemented UI, tokens, and layout patterns that define the current interface language
   ```

3. **Analyze and synthesize:**
   - Extract all relevant design tokens from the screen
   - Translate technical values into descriptive language
   - Organize information according to the DESIGN.md structure

4. **Generate the file:**
   - Create `DESIGN.md` in the project directory
   - Follow the prescribed format exactly
   - Ensure all color codes are accurate
   - Use evocative, designer-friendly language

## Best Practices

- **Be Descriptive:** Avoid generic terms like "blue" or "rounded." Use "Ocean-deep Cerulean (#0077B6)" or "Gently curved edges"
- **Be Functional:** Always explain what each design element is used for
- **Be Consistent:** Use the same terminology throughout the document
- **Be Visual:** Help readers visualize the design through your descriptions
- **Be Precise:** Include exact values (hex codes, pixel values) in parentheses after natural language descriptions

## Tips for Success

1. **Start with the big picture:** Understand the overall aesthetic before diving into details
2. **Look for patterns:** Identify consistent spacing, sizing, and styling patterns
3. **Think semantically:** Name colors by their purpose, not just their appearance
4. **Consider hierarchy:** Document how visual weight and importance are communicated
5. **Reference the actual product language:** Use wording and examples that match the project's own interface vocabulary rather than a vendor-specific guide

## Common Pitfalls to Avoid

- ❌ Using technical jargon without translation (e.g., "rounded-xl" instead of "generously rounded corners")
- ❌ Omitting color codes or using only descriptive names
- ❌ Forgetting to explain functional roles of design elements
- ❌ Being too vague in atmosphere descriptions
- ❌ Ignoring subtle design details like shadows or spacing patterns
