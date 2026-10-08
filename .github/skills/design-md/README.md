# DESIGN.md Documentation Skill

## Purpose

Use this skill to synthesize a reusable `DESIGN.md` or equivalent design-system summary from the actual interface artifacts of any project.

## Example Prompt

```text
Analyze the current admin interface and generate a comprehensive DESIGN.md file documenting the design system.
```

## Skill Structure

This repository follows the **Agent Skills** open standard. Each skill is self-contained with its own logic, workflow, and reference materials.

```text
design-md/
├── SKILL.md           — Core instructions & workflow
├── examples/          — Sample DESIGN.md outputs
└── README.md          — This file
```

## How it Works

When activated, the agent follows a structured design analysis pipeline:

1. **Retrieval**: Reads repository-local design artifacts, screenshots, component docs, or exported visual references.
2. **Extraction**: Identifies design tokens including colors, typography, spacing, and component patterns.
3. **Translation**: Converts technical CSS, token, or component values into descriptive, natural design language.
4. **Synthesis**: Generates a comprehensive DESIGN.md following a semantic design system format.
5. **Alignment**: Keeps the output tied to the implemented product language instead of a vendor-specific tool.
