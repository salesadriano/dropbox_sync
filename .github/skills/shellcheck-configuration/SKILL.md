---
name: shellcheck-configuration
description: "ShellCheck static analysis for shell scripts: choosing the dialect (sh vs bash), .shellcheckrc, inline directives, reading SC codes, POSIX portability checks, and running it locally on the diff. Use when writing, reviewing or linting shell scripts (`*.sh` or files with a sh/bash shebang). Prefer bats-testing-patterns to prove behavior with tests, protocolo-conformidade for the gate procedure and verdict, and security-best-practices for the security posture. Trigger terms: shellcheck, SC2086, SC3xxx, .shellcheckrc, lint shell, POSIX sh, bashism, dash."
metadata:
  tags: shell, sh, posix, bash, shellcheck, lint, static-analysis
  source: wshobson/agents
---

# ShellCheck Configuration and Static Analysis

## Security Handoff

This skill does not replace security hardening.

- If the script handles secrets, passes external input to commands, `eval`, `rm` or path construction, or downloads and executes content, also apply `security-best-practices` and `api-security-best-practices`. An unquoted expansion that lets external input reach command execution is a security finding, not a style warning.
- Never include secrets, tokens, credentials, or private keys in examples, fixtures, diagrams, logs, or generated artifacts.

## Scope Boundary

Use this skill to lint and review shell scripts statically.

- [`bats-testing-patterns`](../bats-testing-patterns/SKILL.md) proves behavior with tests. Lint does not prove behavior, and tests do not replace lint; changes to a script need both.
- [`protocolo-conformidade`](../protocolo-conformidade/SKILL.md) is the gate procedure that applies this skill to the diff and classifies findings by severity. This skill supplies the rules and the tool; the verdict belongs to the gate.
- [`best-practices`](../best-practices/SKILL.md) covers generic web code quality, not shell.

## Package precedence

These package rules override the upstream content where they conflict:

1. **The dialect follows the shebang.** The package scripts are POSIX sh (`#!/usr/bin/env sh`, `set -eu`), and ShellCheck detects the dialect from the shebang. Never set `shell=bash` for them, and never fix an SC3xxx warning by switching the shebang to bash: rewrite with POSIX constructs.
2. **POSIX checklist** for `sh` scripts: no `[[ ]]` (use `[ ]` or `case`), no arrays (use `set --` or delimited strings), no `local`, no `pipefail`, no `source` (use `.`), no `${var//a/b}`, no `{1..n}`, no `<( )`, no `==` inside `[ ]`, no `echo -e`/`echo -n` (use `printf`). Quote every expansion.
3. **The gate is local.** Run ShellCheck on the changed shell files during `protocolo-conformidade`, on the agent's machine, before any handoff. The CI examples in `references/details.md` are an optional complement and never replace the local run.
4. **Suppress with a reason.** `# shellcheck disable=SCxxxx` only on the specific line, with the reason in a comment right above it; the same justification goes into the conformity verdict. Never disable SC2086 (unquoted expansion) for a whole file.
5. **Missing ShellCheck is a limitation, not a waiver.** Record it in the verdict, run `sh -n` (and `dash -n` when available) for syntax, and review the diff manually against the POSIX checklist above.

## When to Use This Skill

- Analyzing new or changed shell scripts for issues
- Understanding ShellCheck error codes and warnings
- Configuring ShellCheck for specific project requirements
- Suppressing false positives with documented justification
- Checking script portability across sh, dash and bash

## Local Commands

```sh
shellcheck scripts/*.sh                              # dialect taken from each shebang
shellcheck -s sh -S style path/to/script             # force POSIX sh, include style checks
git diff --name-only -- '*.sh' | xargs -r shellcheck # only the changed scripts
sh -n path/to/script                                 # syntax only, always available
command -v dash >/dev/null 2>&1 && dash -n path/to/script
```

## Project Configuration

A `.shellcheckrc` is only needed when some scripts lack a shebang or source other files:

```
# Dialect for files without a shebang; scripts with a shebang keep their own.
shell=sh
# Follow files included with `.` and resolve their paths relative to the script.
external-sources=true
source-path=SCRIPTDIR
```

## Detailed patterns and worked examples

Detailed pattern documentation lives in `references/details.md`. Read only the section you need. For the exact meaning of a code, the authoritative source is `https://www.shellcheck.net/wiki/SCxxxx`; check it before citing a code in a verdict.

## Best Practices

1. **Lint every changed script locally** before handoff.
2. **Configure for the target shell** — don't analyze bash as sh, or sh as bash.
3. **Document exclusions** next to the directive and in the verdict.
4. **Fix violations** instead of disabling warnings.
5. **Consider optional checks** (`--enable=all`) with careful, justified exclusions.
6. **Keep ShellCheck current** for new checks.
7. **Integrate with editors** for real-time feedback during development.
