# Gitflow Policies

These rules must be followed to ensure repository health and history cleanliness.

## 1. Upstream Synchronization
**Rule**: You MUST fetch from upstream and create the new branch from the remote source (`origin/<source>`), never from a possibly stale local branch. The source is the declared main branch unless the requester explicitly names another one. Before raising a PR, bring the latest source into the branch (rebase or merge).
-   **Why**: To avoid merge conflicts and ensure you are working on the latest code.
-   **Command**: each demand gets its own worktree; see [worktree-e-sincronizacao.md](worktree-e-sincronizacao.md), section 4.

## 2. Remote-Deleted Branches
**Rule**: A local branch whose remote branch was deleted MUST be deleted locally too, together with its worktree, at the start of every demand and after every merge.
-   **Safety**: Removal is automatic only when all local work was already on the remote. Unpushed commits or uncommitted changes keep the branch and the worktree, which are listed to the requester and removed only after explicit confirmation. The main branch is never removed by this sync.
-   **Command**: see [worktree-e-sincronizacao.md](worktree-e-sincronizacao.md), section 2.

## 3. Open Pull Requests Before a New Demand
**Rule**: After syncing and before creating the demand's worktree, check the repository's open PRs against the demand's expected scope (files, modules and their direct dependents, shared contracts). For each PR with impact, tell the requester which merge is needed and why: merge before starting, start from the PR branch (explicit request only), or proceed without dependency.
-   **Safety**: The agent never merges, approves or changes a PR on its own; the requester decides and the decision is recorded in the prompt log.
-   **Command**: see [worktree-e-sincronizacao.md](worktree-e-sincronizacao.md), section 3.

## 4. Main Branch Evaluation Before Every Push
**Rule**: Before every push of a demand branch, fetch the main branch and evaluate it. If it moved ahead, integrate it into the demand's worktree, resolve the conflicts there, re-run the local gates over the integrated diff and push only when the branch contains `origin/<main>`.
-   **Why**: Conflicts that would surface at merge time are cheaper to resolve in the demand's worktree, with the gates still running, than on the integration branch.
-   **Scope**: Covers textual conflicts and unmarked ones: files changed on both sides without overlapping lines, shared contracts changed on main (API, schema and migrations, configuration, dependencies and lockfiles, pipeline, protocol) and memory decisions that change the demand's premise.
-   **Safety**: `--force` is never used on a shared branch, and conflicts are never resolved on the main branch. A `non-fast-forward` rejection reopens the cycle.
-   **Command**: see [coordenacao-multi-instancia.md](coordenacao-multi-instancia.md), section 4.

## 5. Coordination Between Tech Lead Instances
**Rule**: When several Tech Lead instances work on the same project from different machines, the main branch history is the only coordination channel (memory entries, prompt logs and delivery records arriving through merged PRs). Read the channel at the start of every demand, publish a `tipo: reserva` entry for the demand's expected scope in the branch's first commit with a draft PR, and close it in the commit that closes the demand.
-   **Safety**: Decisions are settled by merge precedence; no instance edits another's entry, branch, worktree or PR, pushes directly to main or rewrites its history.
-   **Command**: see [coordenacao-multi-instancia.md](coordenacao-multi-instancia.md), sections 1 to 3 and 5.

## 6. Pull Requests (PRs)
-   **Target**: The PR targets the demand's source branch (the declared main branch by default). Additional Gitflow targets (e.g., back-merging `hotfix/*` into `develop`) only when explicitly requested.
-   **Review**: Code must be reviewed by at least one other developer.
-   **CI/CD**: All automated tests must pass before merging.

## 7. Commit Messages
-   Follow the Conventional Commits specification.
-   Format: `<type>(<scope>): <subject>`
