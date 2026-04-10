---
name: verification-light
description: Light verification protocol for teammates - build/test only. Enforces evidence-based verification with max 3 attempts. No completion claims without fresh evidence.
---

# Verification

## The Iron Law

No completion claims without fresh verification evidence. If you haven't run the command in this phase, you cannot claim it passes.

## Red Flags - STOP

- Using "should pass", "probably works", "seems fine"
- Expressing satisfaction before running commands
- Running commands without reading output
- Claiming success from a prior run (must be fresh in THIS phase)

## Evidence Pattern

Good: `[run tsc] -> "exit 0, 0 errors" -> [run build] -> "exit 0" -> [run test] -> "47/47 pass" -> "All verification passes"`
Bad: `"Tests should pass now"` / `"I fixed it so it works"`

---

## Verification Loop (max 3 attempts)

Run the verify commands from your brief or manifest config.

For each attempt:

1. Run each verification step separately and read full output.
   Typical steps (run in this order):
   - Lint (e.g., `npm run lint` or `npx eslint .`) - check for a `lint` script in `package.json` or for eslint config files (`.eslintrc*`, `eslint.config.*`). For non-JS projects, check equivalents (`cargo clippy` for Rust, `ruff` for Python). If no linter is configured, skip and report "Lint: skipped (no lint configuration detected)". Lint runs independently of the manifest's `verify` command - auto-detect and run even if the verify command doesn't include it.
   - Type check (e.g., `npx tsc --noEmit`) - read stderr, check exit code
   - Build (e.g., `npm run build`) - read output, check exit code
   - Test (e.g., `npm test`) - read output, count pass/fail, check exit code

2. After ALL steps pass: state the results with evidence
   (e.g., "tsc: exit 0, no errors. build: exit 0. tests: 47/47 pass.")

3. If ANY command fails:
   - Read the full error output
   - Diagnose the root cause
   - **Check the baseline**: if this test failure existed in the baseline (captured by preflight before any sessions ran), note it as pre-existing but do not count it as a new failure
   - Fix new issues only
   - Increment attempt counter and re-run ALL commands (not just the failing one)

4. After 3 failed attempts: describe the blocker, commit what works,
   and exit with a clear failure description.

### Verify All

Run ALL commands and re-run ALL commands if you fix something. Never re-run just one.

### Report

```
Verification Results:
  Build (lint, tsc, build, test): PASS
```

Or on failure:
```
Verification Results:
  Build (lint, tsc, build, test): FAIL - {error summary}
  Attempts: 3/3 exhausted
  Blocker: {description}
```
