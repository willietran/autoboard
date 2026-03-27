# Quality Standards

Languages: Bash/Shell
Frameworks: None (CLI tool, skills-only plugin)

## Security

**Principle:** Never trust data that crosses a trust boundary — validate, sanitize, and enforce access control at every system edge.

**Criteria:**
- Argument arrays for all subprocess calls — no string interpolation into shell commands
- All manifest-parsed fields (task IDs, branch names, file paths, model IDs, effort levels) validated before use
- No secrets in logs, error messages, or committed code
- Permission configs generated with default-deny posture on both platforms
- Destructive git commands blocked in session permissions on both platforms

**Common Violations:**
- String-interpolating manifest values into shell commands instead of using argument arrays
- Passing unvalidated model IDs or effort levels to CLI flags
- Permission configs that are too permissive (allow-all instead of scoped allow)

## Error Handling

**Principle:** Errors must be visible, specific, and actionable — never silently swallowed, never generic, never fire-and-forget.

**Criteria:**
- Platform detection fails with a clear error naming the expected env vars and the override mechanism
- CLI binary not found produces an actionable error (not just "command not found")
- Invalid manifest values (bad model, bad effort level, bad platform) fail fast with the valid options listed
- Output parsing errors from unexpected JSONL events are logged with the raw event, not silently dropped
- Process cleanup runs on all exit paths (normal, signal, crash) — no orphaned processes

**Common Violations:**
- `command -v codex` failing silently and falling through to wrong platform
- Unexpected JSONL event types silently ignored instead of logged
- Cleanup traps not covering all signal paths

## Test Quality

**Principle:** Tests must cover the most complex and risky code first — not the easiest code to test.

**Criteria:**
- Platform detection tested with all env var combinations (both set, neither set, override)
- Argument construction tested for each platform (correct flags, correct order)
- Effort mapping tested (especially `max` -> `xhigh` on Codex)
- Permission config generation tested for both output formats
- Output normalization tested with sample JSONL from both platforms
- Error paths tested: missing CLI, invalid config, malformed output

**Common Violations:**
- Only testing the happy path (Claude Code detection works) without testing the Codex path or error cases
- Testing argument construction for one platform but not the other
- No tests for output normalization edge cases

## Config Management

**Principle:** Every configurable value has a single, validated source — no magic numbers scattered across the codebase.

**Criteria:**
- Platform-specific defaults centralized in `spawn-session.sh` (not scattered across skills)
- Effort level mapping (`max` -> `xhigh`) defined once, not duplicated
- Model alias mapping defined once per platform
- Permission config templates maintained alongside default permissions
- All valid values for effort, platform, and sandbox mode documented in one place

**Common Violations:**
- Effort mapping duplicated in both `spawn-session.sh` and a skill
- Platform-specific flag names hardcoded in multiple places
- Magic strings for Codex flags scattered across the script

## Code Organization

**Principle:** A new contributor should find any piece of functionality by intuition — structure reveals intent.

**Criteria:**
- Platform adapter logic lives entirely in `bin/spawn-session.sh` — no platform-specific code in skills
- Dual discovery paths (`.claude-plugin/`, `.agents/skills/`) clearly documented in README
- Permission config files named consistently: `default-session-permissions.json` (Claude Code), `default-session-permissions.toml` (Codex)
- No dead code from the single-platform era left behind
- Skills remain platform-agnostic — they describe what to do, not which tool to use

**Common Violations:**
- Platform-specific `if/else` blocks scattered across multiple skills
- Codex-specific logic creeping into skills instead of staying in the shell adapter
- Orphaned Claude Code-only code paths after adding Codex support

## DRY / Code Reuse

**Principle:** Every piece of logic has exactly one authoritative source — duplication is a defect, not a convenience.

**Criteria:**
- Platform detection logic defined once and reused (not re-implemented in setup skill AND spawn script)
- Effort mapping defined once (not in spawn script AND task-manifest skill)
- Permission config generation shares validation logic across formats
- Argument construction for each platform uses a single builder function, not duplicated blocks

**Common Violations:**
- Platform detection reimplemented in multiple places
- Separate code paths for Claude Code and Codex that are 90% identical
- Effort validation duplicated in manifest parsing and shell script
