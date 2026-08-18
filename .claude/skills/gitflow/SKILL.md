---
name: gitflow
description: Use this skill when managing git branches, releases, or hotfixes according to the Gitflow workflow. It enforces naming conventions and synchronization policies.
metadata:
  short-description: Expert guidance on Gitflow branching and release management.
---

# Gitflow Expert

You are an expert in the Gitflow branching model adopted by this package. Your goal is to guide the user through the lifecycle of features, bug fixes, releases, hotfixes, and support lines while maintaining strict repository hygiene.

## Security Handoff

This skill does not replace security hardening.

- If work touches authentication, authorization, secrets, sensitive data, session/cookies, CSP/CORS, or API exposure, also apply `security-best-practices` and `api-security-best-practices`.
- Never include secrets, tokens, credentials, or private keys in examples, fixtures, diagrams, logs, or generated artifacts.

## Core Mandates

1.  **Sync First**: ALWAYS instruct the user to update their local source branch from upstream *before* creating a new branch.
2.  **Strict Naming**: Enforce the `feature/*`, `bugfix/*`, `release/*`, `hotfix/*`, and `support/*` naming conventions defined in the references.
3.  **Correct Targets**: Ensure PRs are targeted correctly (e.g., Hotfixes go to `master` AND `develop`).

## Branching Strategy

The project uses an extended Gitflow model.
-   **Branch Types & Lifecycles**: See [references/branching-model.md](references/branching-model.md).

## Developer Policies

-   **Upstream Sync & PR Rules**: See [references/policies.md](references/policies.md).

## Workflow

### 1. Starting Work
Before creating any branch, run:
```bash
git checkout <source_branch>
git pull origin <source_branch>
git checkout -b <new_branch_name>
```
*Ref: [references/policies.md](references/policies.md)*

### 2. Choosing a Branch Type
-   **New Feature** -> `feature/` (from `develop`)
-   **Non-critical Bug** -> `bugfix/` (from `develop`)
-   **Production Release** -> `release/` (from `develop`)
-   **Critical Production Fix** -> `hotfix/` (from `master`)
-   **Long-lived Support Line** -> `support/` (from `master` or supported production baseline)
*Ref: [references/branching-model.md](references/branching-model.md)*
