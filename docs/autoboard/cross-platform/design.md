# Cross-Platform Compatibility

Make Autoboard work with both Claude Code and Codex CLI — same codebase, same skills, platform-specific adapters where needed. Users install one plugin, it detects the platform and adapts automatically.

## Scope

Full feature parity. Everything Autoboard does today on Claude Code works on Codex: session spawning, QA gates, coherence audits, review gates, knowledge curation, failure recovery, GitHub tracking. No features deferred.

**Out of scope:**
- **Windows** — Codex supports Windows via WSL, but Autoboard's shell scripts and symlinks assume macOS/Linux. Windows support is a future concern.
- **Cross-platform manifests** — A manifest written for Claude Code (with `model: claude-sonnet-4-6`) won't work on Codex and vice versa. Model IDs are platform-specific. Users targeting both platforms maintain separate manifests or use platform-appropriate model IDs.

**Sources:** Codex CLI flags and capabilities referenced in this document are from the [Codex CLI Reference](https://developers.openai.com/codex/cli/reference), [Codex Configuration Reference](https://developers.openai.com/codex/config-reference), and [Codex Skills](https://developers.openai.com/codex/skills) documentation (verified March 2026).

## Platform Capabilities Mapping

Both platforms have the features Autoboard depends on:

| Autoboard Needs | Claude Code | Codex CLI |
|---|---|---|
| Headless subprocess | `claude -p` | `codex exec --json` |
| Subagents | `Agent` tool (fire-and-forget) | `SpawnAgent`/`WaitAgent` (richer lifecycle) |
| Skills/plugins | `.claude-plugin/` + `SKILL.md` | `.agents/skills/` + `SKILL.md` (same format) |
| Headless permissions | `--permission-mode dontAsk --settings <file>` | `--ask-for-approval never --sandbox <mode>` |
| MCP servers | Via settings/plugin | Via `config.toml` `[mcp_servers]` |
| JSON output | `--output-format stream-json` | `--json` (JSONL stream) |
| Project instructions | `CLAUDE.md` | `AGENTS.md` |
| Config format | `settings.json` (JSON) | `config.toml` (TOML) |
| Effort control | `--effort low\|medium\|high\|max` | `-c model_reasoning_effort="low\|medium\|high\|xhigh"` |
| Env detection | `CLAUDECODE=1` | `CODEX_CI=1` |

## Architecture

### Abstraction Strategy

**Shell layer only, with a touch of skill-level adaptation.** The platform-specific surface is concentrated in a few places — no full abstraction module needed.

| What Changes | Where It Lives |
|---|---|
| CLI binary, flags, output parsing | `bin/spawn-session.sh` |
| Permission config generation | Helper function in `spawn-session.sh` or sibling script |
| Platform detection | One function in `spawn-session.sh` |
| Model ID passthrough | Model alias mapping in `spawn-session.sh` |
| Effort level mapping | `max` maps to `xhigh` on Codex; otherwise passthrough |

**What does NOT change:**
- Skills — platform-agnostic markdown instructions, shared between platforms
- Agent definitions — same `plan-reviewer.md` and `code-reviewer.md`
- Quality dimensions — language/framework-specific, not platform-specific
- Manifest format — YAML frontmatter + markdown, fully portable
- Orchestration logic — dependency layers, QA gates, merge strategy
- Git conventions — feature/session branches, squash merge

### Platform Detection

The platform is detected from the runtime environment — if you invoke `/autoboard:run` from Claude Code, it uses Claude Code. From Codex, it uses Codex. No user configuration needed for the normal case.

```bash
detect_platform() {
  # Explicit override — validate against allowlist
  if [ -n "$AUTOBOARD_PLATFORM" ]; then
    case "$AUTOBOARD_PLATFORM" in
      claude-code|codex) echo "$AUTOBOARD_PLATFORM" ;;
      *) echo "ERROR: Invalid AUTOBOARD_PLATFORM='$AUTOBOARD_PLATFORM'. Valid: claude-code, codex" >&2; exit 1 ;;
    esac
  elif [ "$CLAUDECODE" = "1" ] && [ -n "$CODEX_CI" ]; then
    echo "WARNING: Both CLAUDECODE and CODEX_CI set. Using claude-code. Override with AUTOBOARD_PLATFORM." >&2
    echo "claude-code"
  elif [ "$CLAUDECODE" = "1" ]; then
    echo "claude-code"
  elif [ -n "$CODEX_CI" ]; then
    echo "codex"
  else
    echo "ERROR: Not running inside a supported CLI. Expected CLAUDECODE=1 or CODEX_CI=1. Override with AUTOBOARD_PLATFORM=claude-code|codex" >&2
    exit 1
  fi
}
```

`AUTOBOARD_PLATFORM` env var is an escape hatch for CI pipelines, testing, or setups where both CLIs are present and auto-detection picks the wrong one. The override is validated against an allowlist — invalid values fail immediately.

### Plugin Discovery

Single repo, dual discovery paths. Both platforms use `SKILL.md` with YAML frontmatter — the files themselves are identical.

```
autoboard/
  .claude-plugin/          # Claude Code plugin discovery
    plugin.json
  .agents/                 # Codex plugin discovery
    skills/                # Symlinks or copies pointing to skills/
  skills/                  # Canonical skill source (shared)
    brainstorm/SKILL.md
    run/SKILL.md
    ...
  agents/                  # Shared agent definitions
  bin/
    spawn-session.sh       # Platform adapter
  config/
    default-session-permissions.json    # Claude Code format
    default-session-permissions.toml    # Codex format
  standards/dimensions/    # Shared quality dimensions
```

**Codex skill discovery:** Codex scans `.agents/skills/` from the current working directory up to the repo root. The `.agents/skills/` directory contains relative symlinks to the canonical `skills/` directory (e.g., `.agents/skills/brainstorm` -> `../../skills/brainstorm`). These symlinks are committed to git and replicate correctly in worktrees since both the symlink and its target are within the repo tree.

**Claude Code skill discovery:** Sessions get skills via `--plugin-dir "$PLUGIN_DIR"` which points to the Autoboard plugin root. This is Claude Code-specific and not needed for Codex (where skills are discovered from the repo directory).

**No build step needed.** Symlinks are created once during initial setup and committed.

## Session Spawning

### `spawn-session.sh` Changes

The shell script is the primary platform adapter. It translates Autoboard's abstract session config into platform-specific CLI invocations.

**Claude Code invocation (current):**
```bash
claude -p "$PROMPT" \
  --model "$MODEL_ID" \
  --plugin-dir "$PLUGIN_DIR" \
  --output-format stream-json \
  --effort "$EFFORT" \
  --verbose \
  --permission-mode dontAsk --settings "$SETTINGS_FILE"
```

**Codex invocation (new):**
```bash
codex exec "$PROMPT" \
  --json \
  -c model="$MODEL_ID" \
  -c model_reasoning_effort="$EFFORT" \
  --ask-for-approval never \
  --sandbox workspace-write
```

### New CLI Arguments

```
spawn-session.sh <brief-file> --model <model> --cwd <worktree-path>
  [--effort <low|medium|high|max>]     # NEW: effort level
  [--skip-permissions]
  [--settings <file>]
  [--standards <file>]
  [--test-baseline <file>]
```

### Model Configuration

Users specify actual model IDs in the manifest — no abstract tiers. Each platform has its own model ecosystem:

```yaml
# Claude Code project
model: claude-sonnet-4-6
qa-model: claude-sonnet-4-6
explore-model: claude-haiku-4-5-20251001

# Codex project
model: gpt-5.4
qa-model: gpt-4.1
explore-model: gpt-4.1-mini
```

The shell script passes model IDs through directly. Claude Code's existing alias mapping (`opus` -> `claude-opus-4-6`) is preserved for convenience but is Claude Code-specific.

### Effort Configuration

Categorical labels in the manifest, mapped per-platform by the shell script:

| Manifest Value | Claude Code | Codex |
|---|---|---|
| `low` | `--effort low` | `-c model_reasoning_effort="low"` |
| `medium` | (default, omitted) | (default, omitted) |
| `high` | `--effort high` | `-c model_reasoning_effort="high"` |
| `max` | `--effort max` | `-c model_reasoning_effort="xhigh"` |

**Auto-assignment rule:** Task-manifest defaults effort to `medium`. Sessions with max task complexity 4-5 get auto-bumped to `high`. Users can override per-session.

### Permission Scoping

Each platform has a different permission model. The orchestrator generates platform-appropriate permission configs:

**Claude Code:** `session-permissions.json` (JSON allow/deny rules for `--permission-mode dontAsk`)
```json
{
  "permissions": {
    "allow": ["Read", "Edit", "Write", "Bash(*)"],
    "deny": ["Bash(git push*)"]
  }
}
```

**Codex:** Permission scoping via `--sandbox` mode and `-c` config overrides
- `--sandbox workspace-write` scopes file writes to the worktree
- `--ask-for-approval never` prevents interactive prompts
- Destructive command blocking via Starlark `.rules` files (if needed)

### Output Handling

**No output normalization needed.** The orchestrator does NOT parse JSONL streams from sessions. It uses a wait-and-check pattern:

1. **Exit code** — Background Bash process notifies on completion; exit code is the primary success/failure signal
2. **Session status file** — Session agent writes `docs/autoboard/{slug}/sessions/s{N}-status.md` with structured status (success/failure, tasks completed, test results, knowledge)
3. **Git log** — `git log autoboard/{slug}-s{N}` confirms work landed on the session branch
4. **Progress file** — `/tmp/autoboard-{slug}-progress/s{N}.md` has per-phase detail

The JSONL output (`/tmp/autoboard-{slug}-s{N}-output.jsonl`) is a transcript dump for debugging and failure investigation only — the orchestrator reads its tail when diagnosing failures but never parses it for control flow.

Both platforms' JSONL flags (`--output-format stream-json` for Claude Code, `--json` for Codex) serve the same purpose: capturing the raw session transcript. The different event schemas don't matter since the orchestrator doesn't parse them.

### Process Lifecycle

The existing process group management (perl `setpgrp`, PID files, signal traps) is platform-agnostic — it manages the spawned process regardless of which CLI binary it is. One rename: `CLAUDE_PID` -> `SESSION_PID` for clarity when debugging Codex sessions.

## Subagent Lifecycle

**Lowest common denominator: fire-and-forget on both platforms.**

Claude Code's `Agent` tool dispatches a subagent with a prompt and gets a result back. Codex has richer multi-turn subagent management (`SpawnAgent` -> `SendMessage` -> `WaitAgent` -> `CloseAgent`).

For Autoboard's review gates, each review round dispatches a fresh subagent with the complete updated artifact. There's no context loss from fresh agents since the full plan/code is passed each time. Keeping subagents alive across rounds adds error handling complexity for marginal benefit.

Skills that reference the `Agent` tool may need conditional language for Codex users, but in practice the AI agent figures out which tools are available from its environment. The skill instructions say "dispatch a subagent to review the plan" — the agent uses whatever tool is available.

## Desktop App Compatibility

**No special handling needed.** Both platforms' desktop apps run the same agent engine as the CLI:

- Claude Code desktop shares `~/.claude/` config, plugins, and skills with the CLI
- Codex desktop shares `~/.codex/` config, skills, and MCP settings with the CLI

Autoboard's session spawning uses the `Bash` tool to invoke `bin/spawn-session.sh`, which calls the CLI binary (`claude` or `codex`). As long as the CLI binary is on PATH — which it is when the platform is installed — sessions spawn correctly regardless of whether the orchestrator runs in the desktop app, CLI, or IDE extension.

**Verification items:**
- Confirm `CLAUDECODE=1` / `CODEX_CI=1` env vars are set from desktop app context
- Confirm CLI binary is on PATH from desktop app context
- Test end-to-end session spawning from each desktop app

## Project Instruction Files

**No management needed.** Both CLIs auto-load their respective instruction files (`CLAUDE.md` / `AGENTS.md`) from the working directory. Since worktrees are copies of the repo, any existing instruction file is already present. Session briefs (passed via `-p` / `exec`) carry all Autoboard-specific context.

## Manifest Format Changes

The manifest frontmatter gains two new optional fields:

```yaml
---
model: claude-sonnet-4-6
qa-model: claude-sonnet-4-6
explore-model: claude-haiku-4-5-20251001
plan-review-model: claude-sonnet-4-6
code-review-model: claude-sonnet-4-6
verify: npm install && npm run build && npm run typecheck && npm test
dev-server: npm run dev
setup: npm run db:migrate
qa-mode: build-only
platform: auto                    # NEW: auto | claude-code | codex (default: auto)
retries: 5
tracking-provider: github
max-parallel: 4
---
```

Per-session effort is set in the sessions table:

```markdown
| Session | Tasks | Complexity | Domain | Effort | Rationale |
|---------|-------|-----------|--------|--------|-----------|
| S1 | T1 (5) | 5 | Auth | high | Complex JWT rotation logic |
| S2 | T1 (2), T2 (2) | 4 | Config | medium | Straightforward setup |
```

## Files Modified

| File | Change |
|---|---|
| `bin/spawn-session.sh` | Platform detection, Codex CLI invocation, effort flag, `SESSION_PID` rename |
| `skills/setup/SKILL.md` | Platform detection in preflight checks (calls `spawn-session.sh`'s `detect_platform`, does NOT reimplement) |
| `skills/session-spawn/SKILL.md` | Pass effort level to spawn-session.sh |
| `skills/task-manifest/SKILL.md` | Auto-assign effort from complexity, add effort column to sessions table |
| `skills/qa-gate/SKILL.md` | Platform-aware verification command (if any differ) |
| `config/default-session-permissions.toml` | NEW: Codex-format permission defaults |
| `.agents/skills/` | NEW: Codex plugin discovery path (symlinks to skills/) |

## Quality & Testing Strategy

### Testable Components

**`bin/spawn-session.sh`** — The primary platform adapter. Key test scenarios:
- Platform detection: `CLAUDECODE=1` set -> detects claude-code; `CODEX_CI=1` set -> detects codex; both set -> claude-code wins; neither set -> error; `AUTOBOARD_PLATFORM` override -> uses override
- Model passthrough: alias mapping for Claude Code; direct passthrough for Codex
- Effort mapping: `max` -> `xhigh` on Codex; `medium` omitted (default); other values passed through
- Argument construction: correct flags for each platform; permission flags; `--plugin-dir` for Claude Code vs repo-based discovery for Codex
- Error cases: CLI binary not found; brief file missing; invalid model; invalid effort level; invalid `AUTOBOARD_PLATFORM` value; both env vars set simultaneously

**Permission config generation** — Key test scenarios:
- Claude Code JSON format generated correctly from manifest
- Codex sandbox/approval config generated correctly
- Default permissions used when no project-specific config exists
- Deny rules for destructive commands present on both platforms

**Skill discovery setup** — Key test scenarios:
- `.agents/skills/` symlinks resolve correctly
- Both discovery paths point to the same canonical skill files
- Skill loading works from both Claude Code and Codex

### TDD Candidates

- `spawn-session.sh` platform detection function (unit-testable with env var manipulation)
- `spawn-session.sh` argument builder (unit-testable per platform)
- Permission config generator (input manifest -> platform-specific output)
- Effort level mapping (categorical -> platform-specific flag values)

### What Cannot Be Unit Tested

- End-to-end session spawning (requires actual CLI binary + API keys)
- Desktop app PATH/env detection (requires actual desktop app running)
- MCP server passthrough (requires actual MCP servers)

These require manual integration testing or CI with both CLIs installed.

## Critical User Flows

### Flow 1: Codex User Runs Autoboard End-to-End
1. User installs Autoboard (Codex discovers via `.agents/skills/`)
2. User runs `/autoboard:brainstorm` from Codex -> design doc generated
3. User runs `/autoboard:run <slug>` from Codex -> orchestrator starts
4. Setup detects Codex platform via `CODEX_CI` env var
5. Sessions spawn via `codex exec --json` with correct flags
6. Sessions complete, merge, QA gates run
7. **Error case:** `codex` binary not on PATH -> clear error message
8. **Error case:** Codex API key not configured -> session fails with auth error, orchestrator diagnoses via failure skill

### Flow 2: Claude Code User (Regression)
1. Existing Autoboard workflow unchanged
2. Platform detection picks Claude Code via `CLAUDECODE=1`
3. All current flags and behavior preserved
4. **Error case:** Neither env var set (weird environment) -> clear error, suggest `AUTOBOARD_PLATFORM` override

### Flow 3: Platform Override
1. User sets `AUTOBOARD_PLATFORM=codex` in CI environment
2. Detection uses override regardless of env vars
3. Sessions spawn with Codex invocation
4. **Error case:** Override set to invalid value -> clear error listing valid options

### Flow 4: Effort Level Configuration
1. Task-manifest auto-assigns effort from complexity (4-5 -> high, else medium)
2. User overrides specific session to `max` in manifest
3. `spawn-session.sh` maps `max` to `xhigh` for Codex, passes `max` for Claude Code
4. **Error case:** Invalid effort level -> clear error listing valid values
