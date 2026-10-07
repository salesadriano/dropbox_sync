---
name: gitflow
description: Use this skill when managing git branches, worktrees, releases, or hotfixes according to the Gitflow workflow. It enforces the declared main branch as default source, a check of open PRs that may impact a new demand (with the merges needed), one git worktree per demand, naming conventions, removal of local branches deleted on the remote, evaluation of the main branch before every push, and coordination between Tech Lead instances through the main branch history.
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

1.  **Declared Main Branch**: The project's main branch is declared explicitly by the requester on the first request and stored in memory (`branch-principal` entry). Never infer it from `origin/HEAD`, `init.defaultBranch` or the current checkout.
2.  **Source Branch**: Every new demand starts from the declared main branch, fetched from the remote, unless the requester explicitly names another source branch. The per-type Gitflow sources below apply only when they are the main branch or are explicitly named.
3.  **Worktree by Default**: Every demand gets its own branch and its own `git worktree` in a sibling directory (`../<repo>.worktrees/<type>-<slug>`). The main checkout stays on the main branch.
4.  **Sync First**: Before creating a worktree and again after the merge, sync with the remote: local branches (and their worktrees) deleted on the remote are removed when all local work was already pushed; otherwise they are preserved and listed for explicit confirmation.
5.  **Open PRs First**: After syncing and before creating the worktree, check open PRs against the demand's expected scope and tell the requester which merges are needed (merge first, start from the PR branch, or proceed). Never merge, approve or change a PR on your own.
6.  **Strict Naming**: Enforce the `feature/*`, `bugfix/*`, `release/*`, `hotfix/*`, and `support/*` naming conventions defined in the references.
7.  **Correct Targets**: PRs target the demand's source branch. Additional targets (e.g., back-merging a hotfix into `develop`) only when explicitly requested.
8.  **Evaluate Main Before Every Push**: Before every push of a demand branch, fetch and evaluate the main branch. If it moved ahead, integrate it into the demand's worktree, resolve textual conflicts and unmarked ones (shared contracts, memory decisions), re-run the local gates over the integrated diff, and only then push. Never resolve with `--force` on a shared branch, and never resolve conflicts on the main branch itself.
9.  **Coordinate Through Main's History**: When several Tech Lead instances work on the same project from different machines, the main branch history is the only coordination channel: read what arrived on it before planning, publish a scope reservation at the start of the demand, and settle conflicting decisions by merge precedence.

## Branching Strategy

The project uses an extended Gitflow model.
-   **Branch Types & Lifecycles**: See [references/branching-model.md](references/branching-model.md).

## Developer Policies

-   **Upstream Sync & PR Rules**: See [references/policies.md](references/policies.md).
-   **Worktree, Main Branch & Remote Sync (commands)**: See [references/worktree-e-sincronizacao.md](references/worktree-e-sincronizacao.md). Protocol source: rule 46 of `../../agents/AGENTS.md`.
-   **Multi-Instance Coordination & Pre-Push Evaluation (commands)**: See [references/coordenacao-multi-instancia.md](references/coordenacao-multi-instancia.md). Protocol source: rule 47 of `../../agents/AGENTS.md`.

## Workflow

### 1. Starting Work
1.  Read the active `branch-principal` memory entry; if there is none, ask the requester to declare the main branch and record it.
2.  Sync branches with the remote (removes local branches and worktrees deleted on the remote).
3.  Check open PRs that may impact the demand and indicate the needed merges to the requester; wait for the decision when a merge before starting is indicated.
4.  Create the demand's branch and worktree from `origin/<source>`, where `<source>` is the main branch unless another one was explicitly named:
```bash
git worktree add --no-track -b <new_branch_name> ../<repo>.worktrees/<type>-<slug> origin/<source>
```
*Ref: [references/worktree-e-sincronizacao.md](references/worktree-e-sincronizacao.md)*

### 2. Choosing a Branch Type
The type defines the branch name. The source is always the declared main branch unless another one is explicitly named; the Gitflow source in parentheses is the one to name explicitly when the flow requires it.
-   **New Feature** -> `feature/` (Gitflow: `develop`)
-   **Non-critical Bug** -> `bugfix/` (Gitflow: `develop`)
-   **Production Release** -> `release/` (Gitflow: `develop`)
-   **Critical Production Fix** -> `hotfix/` (Gitflow: `master`)
-   **Long-lived Support Line** -> `support/` (Gitflow: `master` or supported production baseline)
*Ref: [references/branching-model.md](references/branching-model.md)*

### 3. Pushing Work
Before every push, evaluate the main branch and integrate it when it moved ahead:
```bash
git fetch origin <main>
git merge-base --is-ancestor origin/<main> HEAD || git merge origin/<main>
```
Re-run the local gates over the integrated diff; push only when the branch contains `origin/<main>`.
*Ref: [references/coordenacao-multi-instancia.md](references/coordenacao-multi-instancia.md), section 4*

### 4. Finishing Work
After the PR is merged and the remote branch deleted, sync again from the main checkout: the demand's worktree and local branch are removed. The demand's scope reservation is closed in the same commit that closes the demand.
