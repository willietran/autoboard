---
model: opus
qa-model: sonnet
explore-model: haiku
plan-review-model: sonnet
code-review-model: sonnet
verify: shellcheck bin/spawn-session.sh && bash tests/test-spawn-session.sh
retries: 1
tracking-provider: github
skip-permissions: false
qa-mode: build-only
max-parallel: 2
---

# Cross-Platform Compatibility — Task Manifest

**Design doc:** `docs/autoboard/cross-platform/design.md`

## Tech Stack

| Component | Technology |
|---|---|
| Shell adapter | Bash (POSIX-compatible) |
| Skills | Markdown (SKILL.md with YAML frontmatter) |
| Permission config | JSON (Claude Code), TOML (Codex) |
| Plugin discovery | Filesystem symlinks |
| Test framework | Bash (shell script tests) + shellcheck |

## Testing Strategy

- **TDD for shell adapter** — `spawn-session.sh` is the only code file; platform detection, argument building, and effort mapping are unit-testable via env var manipulation and argument capture
- **Exempt for skills** — Skills are markdown instructions for AI agents, not executable code. Changes are validated by reading and verifying structure.
- **Exempt for config/symlinks** — Static files verified by existence and format checks

## TDD Discipline

| Task | TDD? | Rationale |
|---|---|---|
| T1: spawn-session.sh platform adapter | RED → GREEN → REFACTOR | Core logic: platform detection, argument building, effort mapping — all unit-testable |
| T2: Codex skill symlinks | Exempt | Filesystem setup, no logic |
| T3: Codex permission defaults | Exempt | Static config file translation |
| T4: Update setup skill | Exempt | Markdown instructions |
| T5: Update session-spawn skill | Exempt | Markdown instructions |
| T6: Update task-manifest skill | Exempt | Markdown instructions |
| T7: Review qa-gate skill | Exempt | Markdown review, likely no-op |

---

## Session S1: Shell Platform Adapter

**Focus:** Refactor `spawn-session.sh` into a cross-platform session spawner with platform detection, Codex CLI invocation, effort control, and comprehensive tests.

**Depends on:** (none)

### Task 1: Refactor spawn-session.sh for Cross-Platform Support

- **Creates:** `tests/test-spawn-session.sh`
- **Modifies:** `bin/spawn-session.sh`
- **Depends on:** (none)
- **Requirements:**
  - Add `detect_platform()` function at the top of `spawn-session.sh`:
    - Check `AUTOBOARD_PLATFORM` env var first (validate against allowlist: `claude-code`, `codex`)
    - Then check `CLAUDECODE=1` for Claude Code
    - Then check `CODEX_CI` for Codex
    - If both `CLAUDECODE` and `CODEX_CI` are set, warn to stderr and default to `claude-code`
    - If none detected, exit with error listing expected env vars and the override mechanism
  - Add `--effort` CLI argument (accepts `low`, `medium`, `high`, `max`; validate against allowlist)
  - Rename `CLAUDE_PID` to `SESSION_PID` throughout the script (12 occurrences)
  - Build platform-specific argument arrays:
    - **Claude Code path:** preserve existing behavior exactly (`claude -p`, `--model`, `--plugin-dir`, `--output-format stream-json`, `--effort`, `--verbose`, permission flags)
    - **Codex path:** `codex exec` with prompt via positional arg, `--json`, `-c model="$MODEL_ID"`, `-c model_reasoning_effort="$EFFORT"` (map `max` to `xhigh`), `--ask-for-approval never`, `--sandbox workspace-write`
  - For Codex, do NOT pass `--plugin-dir` (Codex discovers skills from `.agents/skills/` in the repo)
  - For Codex, do NOT pass `--settings` (use `--sandbox` + `--ask-for-approval` instead)
  - When effort is `medium`, omit the effort flag entirely (both platforms default to medium)
  - Model alias mapping (`opus`/`sonnet`/`haiku` -> full IDs) remains Claude Code-only; Codex passes model IDs through directly
  - Process lifecycle management (perl setpgrp, PID files, signal traps, cleanup) works for both platforms — just swap the binary name (`claude` vs `codex`)
  - Add `--detect-platform` flag that calls `detect_platform()`, prints the result to stdout, and exits. This allows other scripts and the setup skill to reuse platform detection without reimplementing it.
  - Existing Claude Code behavior must be a zero-diff regression — identical argument construction as today when platform is `claude-code`
- **Explore:**
  - How `spawn-session.sh` currently builds argument arrays and handles permissions — for preserving exact behavior on Claude Code path
  - Whether `codex exec` accepts the prompt as a positional argument or via a flag — for correct Codex invocation
  - How Codex handles `--json` output alongside `--sandbox` flags — for ensuring no flag conflicts
- **TDD Phase:** `RED`, `GREEN`, `REFACTOR`
- **Commit:** `task 1: refactor spawn-session.sh for cross-platform support`
- **Test approach:** `unit`
- **Key test scenarios:**
  - Happy path: `CLAUDECODE=1` set -> detects `claude-code`, builds correct Claude Code args
  - Happy path: `CODEX_CI=1` set -> detects `codex`, builds correct Codex args
  - Happy path: `AUTOBOARD_PLATFORM=codex` overrides env vars -> uses Codex path
  - Error path: Neither env var set, no override -> exits with descriptive error
  - Error path: `AUTOBOARD_PLATFORM=invalid` -> exits listing valid values
  - Edge case: Both `CLAUDECODE=1` and `CODEX_CI=1` set -> warns, uses claude-code
  - Effort mapping: `--effort max` on Codex -> `-c model_reasoning_effort="xhigh"`
  - Effort mapping: `--effort medium` -> effort flag omitted entirely on both platforms
  - Effort mapping: `--effort invalid` -> exits with error
  - Model alias: `--model opus` on Claude Code -> `claude-opus-4-6`; on Codex -> passed through as `opus`
  - Permission flags: `--settings file.json` on Claude Code -> `--permission-mode dontAsk --settings file.json`; on Codex -> `--ask-for-approval never --sandbox workspace-write`
  - Detect-platform flag: `bin/spawn-session.sh --detect-platform` with `CLAUDECODE=1` -> prints `claude-code` and exits
  - Regression: Claude Code argument construction produces identical output to current script
- **Complexity Score:** 4
- **Suggested Session:** S1

---

## Session S2: Codex Infrastructure

**Focus:** Create the Codex-compatible discovery structure and permission defaults so Codex can find and run Autoboard skills with appropriate safety constraints.

**Depends on:** (none)

### Task 2: Create Codex Skill Discovery Symlinks

- **Creates:** `.agents/skills/audit`, `.agents/skills/brainstorm`, `.agents/skills/coherence-audit`, `.agents/skills/coherence-fixer`, `.agents/skills/completion`, `.agents/skills/diagnose`, `.agents/skills/failure`, `.agents/skills/knowledge`, `.agents/skills/merge`, `.agents/skills/qa-fixer`, `.agents/skills/qa-gate`, `.agents/skills/receiving-review`, `.agents/skills/run`, `.agents/skills/session-spawn`, `.agents/skills/session-workflow`, `.agents/skills/setup`, `.agents/skills/standards`, `.agents/skills/task-manifest`, `.agents/skills/tracking-github`, `.agents/skills/verification`
- **Modifies:** (none)
- **Depends on:** (none)
- **Requirements:**
  - Create `.agents/skills/` directory
  - Create one relative symlink per skill directory: `.agents/skills/<name>` -> `../../skills/<name>`
  - All 20 skill directories must be symlinked (audit, brainstorm, coherence-audit, coherence-fixer, completion, diagnose, failure, knowledge, merge, qa-fixer, qa-gate, receiving-review, run, session-spawn, session-workflow, setup, standards, task-manifest, tracking-github, verification)
  - Verify each symlink resolves to a directory containing `SKILL.md`
  - Add `.agents/` to git tracking (do NOT gitignore it)
- **Explore:**
  - Whether Codex expects skill directories or individual SKILL.md symlinks — for getting the symlink target level right
  - What the `.agents/` directory convention looks like in other Codex plugins — for following established patterns
- **TDD Phase:** Exempt
- **Commit:** `task 2: create codex skill discovery symlinks`
- **Test approach:** `unit`
- **Key test scenarios:**
  - Happy path: All 20 symlinks exist and resolve to directories containing SKILL.md
  - Edge case: Symlinks resolve correctly from a git worktree (not just the main repo)
- **Complexity Score:** 1
- **Suggested Session:** S2

### Task 3: Create Codex Permission Defaults

- **Creates:** `config/default-session-permissions.toml`
- **Modifies:** (none)
- **Depends on:** (none)
- **Requirements:**
  - Translate the safety intent of `config/default-session-permissions.json` into Codex's permission model
  - Use Codex's config.toml format with:
    - `sandbox_mode = "workspace-write"` — scopes file writes to worktree
    - `approval_policy = "never"` — headless mode, no interactive prompts
    - Shell execution rules matching the deny list: block `git push`, `git reset --hard`, `git checkout .`, `git restore .`, `git clean`, `sudo`, destructive `rm -rf`
  - Use Starlark `.rules` file format if Codex's execution policy requires it (check Codex docs)
  - Document the mapping from Claude Code JSON format to Codex TOML format in a comment header
  - Also translate the secret-reading deny rules from the JSON file (`Read(./.env)`, `Read(./.env.*)`, `Read(./secrets/**)`) into Codex's equivalent, or document why they're handled differently by Codex's sandbox model
  - This file is a reference/template — the orchestrator uses it when generating per-project Codex permissions
- **Explore:**
  - How `config/default-session-permissions.json` structures its allow/deny rules — for faithful translation
  - Codex's Starlark `.rules` file format and `prefix_rule()` syntax — for correct deny rules
  - Whether Codex's `sandbox_mode` and `approval_policy` are set in config.toml or via CLI flags — for choosing the right format
- **TDD Phase:** Exempt
- **Commit:** `task 3: create codex permission defaults`
- **Test approach:** `unit`
- **Key test scenarios:**
  - Happy path: TOML file parses correctly, all deny rules present
  - Edge case: Deny rules cover the same destructive commands as the JSON version
- **Complexity Score:** 2
- **Suggested Session:** S2

---

## Session S3: Skill Updates

**Focus:** Update the setup, session-spawn, and task-manifest skills to support platform detection and effort configuration.

**Depends on:** S1

### Task 4: Update Setup Skill for Platform Awareness

- **Creates:** (none)
- **Modifies:** `skills/setup/SKILL.md`
- **Depends on:** Task 1
- **Requirements:**
  - Add a platform detection step to the preflight section that calls `bin/spawn-session.sh` with a `--detect-platform` flag (or sources the function) — do NOT reimplement detection logic
  - Display detected platform in the execution plan output (e.g., "Platform: codex (auto-detected)")
  - Add `platform` to the list of recognized manifest frontmatter fields (alongside existing model, verify, etc.)
  - When platform is `codex`, adjust preflight messaging:
    - Skip `--plugin-dir` related checks
    - Note that Codex discovers skills from `.agents/skills/` in the repo
    - Verify `.agents/skills/` directory exists and contains symlinks
  - When platform is `claude-code`, preserve existing preflight behavior exactly
- **Explore:**
  - How `skills/setup/SKILL.md` currently runs preflight checks — for inserting platform detection at the right point
  - Whether `spawn-session.sh` can expose `detect_platform` as a callable function (via `source` or a dedicated flag) — for DRY reuse
- **TDD Phase:** Exempt
- **Commit:** `task 4: update setup skill for platform awareness`
- **Test approach:** `unit`
- **Key test scenarios:**
  - Happy path: Setup displays "Platform: claude-code (auto-detected)" when running in Claude Code
  - Happy path: Setup displays "Platform: codex (auto-detected)" when running in Codex
  - Edge case: Platform override via manifest `platform: codex` field
- **Complexity Score:** 2
- **Suggested Session:** S3

### Task 5: Update Session-Spawn Skill for Effort

- **Creates:** (none)
- **Modifies:** `skills/session-spawn/SKILL.md`
- **Depends on:** Task 1
- **Requirements:**
  - Read effort level from the sessions table in the manifest (new `Effort` column)
  - Pass `--effort <level>` to `bin/spawn-session.sh` when spawning each session
  - If effort is not specified in the manifest (backward compatibility), omit the `--effort` flag (defaults to `medium` on both platforms)
  - Include effort level in the session brief metadata so session agents know their effort configuration
  - Update the spawn command template to show the `--effort` flag
- **Explore:**
  - How `skills/session-spawn/SKILL.md` currently builds the spawn command — for inserting `--effort` at the right position
  - How the session brief is constructed — for including effort metadata
- **TDD Phase:** Exempt
- **Commit:** `task 5: update session-spawn skill for effort`
- **Test approach:** `unit`
- **Key test scenarios:**
  - Happy path: Session with `effort: high` -> spawn command includes `--effort high`
  - Happy path: Session with no effort specified -> spawn command omits `--effort` flag
  - Edge case: Backward compatibility with manifests that have no Effort column
- **Complexity Score:** 2
- **Suggested Session:** S3

### Task 6: Update Task-Manifest Skill for Effort Auto-Assignment

- **Creates:** (none)
- **Modifies:** `skills/task-manifest/SKILL.md`
- **Depends on:** (none)
- **Requirements:**
  - Add `Effort` column to the sessions table format:
    ```
    | Session | Tasks | Complexity | Domain | Effort | Rationale |
    ```
  - Add auto-assignment rule: default effort is `medium`; sessions with max task complexity 4-5 get auto-bumped to `high`
  - Document that users can override effort per-session in the manifest
  - Valid effort values: `low`, `medium`, `high`, `max`
  - Add `platform` to the Config Frontmatter template: `platform: auto  # auto | claude-code | codex (default: auto)`
  - Add effort and platform to the "Required Manifest Sections" checklist
- **Explore:**
  - How `skills/task-manifest/SKILL.md` currently defines the sessions table format — for extending it with the Effort column
  - How complexity scoring is documented — for referencing it in the effort auto-assignment rule
- **TDD Phase:** Exempt
- **Commit:** `task 6: update task-manifest skill for effort auto-assignment`
- **Test approach:** `unit`
- **Key test scenarios:**
  - Happy path: Session with max task complexity 5 -> effort auto-assigned as `high`
  - Happy path: Session with max task complexity 3 -> effort auto-assigned as `medium`
  - Edge case: User manually overrides auto-assigned effort
- **Complexity Score:** 2
- **Suggested Session:** S3

### Task 7: Review QA-Gate Skill for Platform Compatibility

- **Creates:** (none)
- **Modifies:** `skills/qa-gate/SKILL.md` (if changes needed)
- **Depends on:** (none)
- **Requirements:**
  - Review `skills/qa-gate/SKILL.md` for any Claude Code-specific assumptions
  - The QA gate spawns a subagent via the Agent tool — verify this works on both platforms (Agent tool is fire-and-forget on both, so it should)
  - The verify command is project-level (from manifest frontmatter) — verify it's passed through without platform-specific handling
  - If no changes are needed, document this finding in a comment at the top of the task and commit the no-op (so the design doc's Files Modified table is satisfied)
  - If changes are needed: update the skill to handle platform differences, keeping platform-specific logic to a minimum
- **Explore:**
  - How `skills/qa-gate/SKILL.md` dispatches the QA subagent — for confirming it uses the generic Agent tool pattern
  - Whether any verification commands reference Claude Code-specific tool names or flags
- **TDD Phase:** Exempt
- **Commit:** `task 7: review qa-gate skill for platform compatibility`
- **Test approach:** `unit`
- **Key test scenarios:**
  - Happy path: QA gate skill contains no platform-specific assumptions -> no changes needed
  - Edge case: Skill references a Claude Code-specific tool name -> update to platform-agnostic language
- **Complexity Score:** 1
- **Suggested Session:** S3

---

## Task Dependency Graph

```
T1 (spawn-session.sh)     T2 (symlinks)     T3 (codex permissions)     T6 (task-manifest skill)     T7 (qa-gate review)
         |                      |                      |                      |                           |
         |                      +----------------------+                      +---------------------------+
         |                                |                                              |
         v                               (independent)                              (independent)
   T4 (setup skill)
   T5 (session-spawn skill)
```

## Execution Layers

```
Layer 0:  S1 [T1]  ←→  S2 [T2, T3]     (parallel)
                ↓
Layer 1:  S3 [T4, T5, T6, T7]           (depends on S1)
```

## Sessions Table

| Session | Tasks | Complexity | Domain | Effort | Rationale |
|---------|-------|-----------|--------|--------|-----------|
| S1 | T1 (4+1 TDD) | 5 | Shell adapter | high | Core platform adapter, only TDD task, complexity 4 warrants high effort |
| S2 | T2 (1), T3 (2) | 3 | Codex infrastructure | medium | Independent config/structure tasks, same domain (Codex setup) |
| S3 | T4 (2), T5 (2), T6 (2), T7 (1) | 7 | Skill updates | medium | All skill markdown updates, T4/T5 depend on S1, T6/T7 grouped for domain cohesion |

## TDD Tasks

| Task | Phase | Test File | Key Scenarios |
|---|---|---|---|
| T1 | RED → GREEN → REFACTOR | `tests/test-spawn-session.sh` | Platform detection (6 scenarios), effort mapping (4 scenarios), argument construction (2 scenarios), regression (1 scenario) |

## Security Checklist

- [ ] No string interpolation into shell commands — argument arrays only (existing pattern preserved)
- [ ] `AUTOBOARD_PLATFORM` override validated against allowlist (no arbitrary values)
- [ ] Codex deny rules match Claude Code deny rules (git push, destructive commands, secrets)
- [ ] Model IDs and effort values validated before passing to CLI flags
- [ ] `--sandbox workspace-write` constrains Codex sessions to worktree scope
- [ ] `--ask-for-approval never` prevents Codex sessions from hanging on prompts
