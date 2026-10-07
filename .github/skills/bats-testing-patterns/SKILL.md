---
name: bats-testing-patterns
description: "Bats (Bash Automated Testing System) mechanics for testing shell scripts: test structure, run/status/output assertions, setup/teardown, fixtures, PATH stubs at system boundaries, and running the same script under sh, dash and bash. Use when writing or reviewing tests for shell scripts (`*.sh`, `*.bats`). Prefer shellcheck-configuration for static analysis and linting, protocolo-tdd for the mandatory delivery protocol, and tdd-test-design for deciding what each test asserts. Trigger terms: bats, .bats, @test, run, BATS_TEST_DIRNAME, BATS_TEST_TMPDIR, setup_file, shell script test."
metadata:
  tags: shell, sh, posix, bash, bats, testing, tdd
  source: wshobson/agents
---

# Bats Testing Patterns

## Security Handoff

This skill does not replace security hardening.

- If the script under test handles secrets, receives external input (arguments, environment, file contents) and passes it to commands, `eval`, file paths or URLs, or downloads and executes content, also apply `security-best-practices` and `api-security-best-practices`, and prove the negative cases required by Rule 6 of `protocolo-tdd`.
- Never include secrets, tokens, credentials, or private keys in examples, fixtures, stubs, diagrams, logs, TAP output, or generated artifacts. Stubs for `curl`, `gh`, cloud CLIs or `ssh` return fake, obviously non-real values.

## Scope Boundary

Use this skill to write or review tests that prove the behavior of shell scripts.

- [`shellcheck-configuration`](../shellcheck-configuration/SKILL.md) covers static analysis. It is complementary, not an alternative: lint does not prove behavior, and tests do not replace lint.
- [`protocolo-tdd`](../protocolo-tdd/SKILL.md) is the mandatory delivery protocol (red-green-refactor, evidence verdict, local gate). This skill provides only the Bats tool mechanics; on conflict, `protocolo-tdd` prevails.
- [`tdd-test-design`](../tdd-test-design/SKILL.md) decides what each test asserts and at which seam.
- [`testing-strategy`](../testing-strategy/SKILL.md) is for planning coverage without changing code.

## Package precedence

These package rules override the upstream content where they conflict:

1. **The script under test keeps its own dialect.** Bats runs `.bats` files under bash, so `[[ ]]`, `${lines[@]}` and `local` are fine inside test files and helpers. The script under test is executed in the dialect of its shebang: a `#!/usr/bin/env sh` script runs as `run sh "$SCRIPT"`, never sourced into the Bats process and never run with `bash`, which would hide bashisms. When `dash` is available, also run it with `dash` (Debian and Ubuntu `sh` is already dash).
2. **Stubs only at system boundaries.** Replace network, clock and external CLIs (`curl`, `gh`, `docker`, `ssh`) with PATH stubs. Never stub the project's own scripts or the standard utilities the script relies on (`find`, `awk`, `sed`, `grep`): run them for real against a fixture tree in a temporary directory. The upstream advice "mock external dependencies" is narrowed to this, following `tdd-test-design`.
3. **Tests never write to the real repository.** Pass the target root as an argument, or copy the fixture tree into `$BATS_TEST_TMPDIR` (bats-core 1.4+, created and removed by Bats per test). Do not overwrite `$TMPDIR`, which `mktemp` itself uses.
4. **The gate is local.** Tests run on the agent's machine, by the agent that changed the script, before any handoff, as required by `protocolo-tdd`. The CI examples below are an optional complement and never replace the local run.
5. **Missing Bats is a limitation, not a waiver.** Record it in the evidence verdict and install it (`apt-get install bats`, `brew install bats-core`) or run a vendored `bats-core`; the test is still required.

## When to Use This Skill

- Writing unit tests for shell scripts
- Implementing test-driven development (TDD) for scripts
- Testing edge cases and error conditions
- Validating behavior across different shell environments (sh, dash, bash)
- Building maintainable test suites and fixtures for scripts

## Detailed patterns and worked examples

Detailed pattern documentation lives in `references/details.md`. Read only the section you need.

## Testing a POSIX sh Script

```bash
#!/usr/bin/env bats

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../scripts/generate.sh"
    ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$ROOT"
}

@test "creates the missing structure under the given root" {
    run sh "$SCRIPT" "$ROOT"
    [ "$status" -eq 0 ]
    [ -f "$ROOT/docs/README.md" ]
}

@test "never overwrites an existing file" {
    mkdir -p "$ROOT/docs"
    printf 'custom\n' > "$ROOT/docs/README.md"
    run sh "$SCRIPT" "$ROOT"
    [ "$status" -eq 0 ]
    [ "$(cat "$ROOT/docs/README.md")" = "custom" ]
}

@test "runs under dash" {
    command -v dash >/dev/null 2>&1 || skip "dash not installed"
    run dash "$SCRIPT" "$ROOT"
    [ "$status" -eq 0 ]
}
```

## Testing Error Conditions

```bash
#!/usr/bin/env bats

@test "fails with a missing file" {
    run sh "$SCRIPT" "/nonexistent/file.txt"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "fails with empty input" {
    run sh "$SCRIPT" ""
    [ "$status" -ne 0 ]
}

@test "fails with permission denied" {
    [ "$(id -u)" -ne 0 ] || skip "root ignores file permissions"
    touch "$BATS_TEST_TMPDIR/readonly.txt"
    chmod 000 "$BATS_TEST_TMPDIR/readonly.txt"
    run sh "$SCRIPT" "$BATS_TEST_TMPDIR/readonly.txt"
    [ "$status" -ne 0 ]
}

@test "prints usage on an invalid option" {
    run sh "$SCRIPT" --invalid-option
    [ "$status" -ne 0 ]
    [[ "$output" == *"Uso:"* || "$output" == *"Usage:"* ]]
}
```

### Testing with Optional Dependencies

```bash
#!/usr/bin/env bats

setup() {
    command -v jq >/dev/null 2>&1 || skip "jq is not installed"
    SCRIPT="$BATS_TEST_DIRNAME/../bin/script.sh"
}

@test "parses JSON" {
    run sh "$SCRIPT" '{"key": "value"}'
    [ "$status" -eq 0 ]
}
```

A skipped test is not evidence: if the dependency is required by the script, install it instead of skipping.

### Stubbing a Boundary Command

```bash
#!/usr/bin/env bats

setup() {
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    printf '#!/bin/sh\necho "{\\"status\\": \\"ok\\"}"\n' > "$STUBS/curl"
    chmod +x "$STUBS/curl"
    PATH="$STUBS:$PATH"
}

@test "reports success when the API answers ok" {
    run sh "$BATS_TEST_DIRNAME/../bin/check-api.sh"
    [ "$status" -eq 0 ]
}
```

## Test Helper Pattern

`load test_helper` looks for `test_helper.bash` next to the test file.

```bash
# tests/test_helper.bash
assert_file_equals() {
    local file="$1" expected="$2" actual
    [ -f "$file" ] || { echo "File does not exist: $file"; return 1; }
    actual=$(cat "$file")
    if [ "$actual" != "$expected" ]; then
        printf 'Expected: %s\nActual:   %s\n' "$expected" "$actual"
        return 1
    fi
}
```

## Running

```bash
bats --abort tests/                 # all .bats files, stop at the first failing test
bats --abort tests/generate.bats    # one file
bats --abort --tap tests/           # TAP output
bats --abort --jobs 4 tests/        # parallel, requires GNU parallel
```

`--abort` (bats-core 1.13+) is required in the local gate and in CI: `protocolo-tdd` Rule 9 demands that the run stops at the first error and reports it. Add `--print-output-on-failure` so the report carries the failing command's `$output`.

### Optional CI Complement

```yaml
name: Shell tests
on: [push, pull_request]
jobs:
  bats:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # Runner com versao fixada: --abort exige bats-core 1.13+, que o apt do Ubuntu nao garante
      - run: npx --yes bats@1.13.0 --version
      - run: npx --yes bats@1.13.0 --abort --print-output-on-failure tests/
      # Build, publicacao ou deploy so depois daqui (Regra 8 de protocolo-tdd)
```

## Best Practices

1. **Test one behavior per test** with a descriptive name.
2. **Run the script in its own dialect** (`run sh` for POSIX scripts), and under `dash` when available.
3. **Work only inside `$BATS_TEST_TMPDIR`**; never write to the real repository.
4. **Test both success and failure paths**, including usage errors and exit codes.
5. **Stub only system boundaries** through PATH; run real utilities against fixtures.
6. **Use fixtures for complex data** under `tests/fixtures/`.
7. **Keep tests fast** so the affected suite runs on every red-green cycle.
8. **Document unusual setup** in the test file.
