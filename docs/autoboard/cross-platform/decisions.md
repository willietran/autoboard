# Architectural Decisions

## D1: Single codebase with platform adapters (not separate packages)

**Decision:** One Autoboard repo serves both Claude Code and Codex. Platform-specific behavior lives in `spawn-session.sh` and permission config generation. Skills, agents, dimensions, and orchestration logic are shared.

**Why:** Both platforms use `SKILL.md` with YAML frontmatter — the skill format is already identical. The platform-specific surface is small (CLI flags, permission format, output parsing). Separate packages would mean maintaining two copies of ~22 skills and 13 quality dimensions.

**Trade-off:** Dual discovery paths (`.claude-plugin/` + `.agents/skills/`) add some structural complexity. Symlinks or a build step needed.

## D2: Shell layer abstraction (not full abstraction module)

**Decision:** `spawn-session.sh` is the sole platform adapter. No abstract interfaces, no adapter pattern, no dedicated abstraction module.

**Why:** Autoboard is a skills-only plugin — there's no application code to abstract. The "module" would just be another shell script. Two implementations of "which CLI flags do I pass" doesn't warrant an abstraction layer. If a third platform appears, adding a branch to `spawn-session.sh` is ~30 minutes of work.

## D3: Auto-detect platform from environment variables

**Decision:** Detect platform via `CLAUDE_CODE=1` or `CODEX_CI=1` env vars. Override via `AUTOBOARD_PLATFORM` env var for edge cases.

**Why:** If you're running Autoboard from Codex, the answer is obviously Codex. Users shouldn't have to configure what's already known. The env var override handles CI pipelines and testing.

## D4: Explicit model names (not abstract tiers)

**Decision:** Users write actual model IDs (`claude-sonnet-4-6`, `gpt-5.4`) in the manifest. No abstract tier mapping (`high`/`mid`/`fast`).

**Why:** Model ecosystems change rapidly. Abstract tiers would need constant updating and create confusion about which model is actually running. Explicit IDs are unambiguous.

## D5: Categorical effort levels with auto-assignment from complexity

**Decision:** Effort uses categorical labels (`low`, `medium`, `high`, `max`). Default is `medium`. Auto-bumped to `high` for sessions with max task complexity 4-5. Users can override.

**Why:** Both platforms use categorical labels in their documented APIs. `medium` is the recommended default on both. Numeric scales (0-100) are undocumented internal details. The complexity-based auto-bump targets deep reasoning at genuinely hard problems without requiring user configuration.

## D6: Fire-and-forget subagent lifecycle (not multi-turn)

**Decision:** Use single-dispatch subagents on both platforms. On Codex, spawn -> wait -> close per review round (not persistent subagents across rounds).

**Why:** Review rounds pass the complete updated artifact each time — no context is lost from fresh agents. Keeping subagents alive adds timeout/cleanup/error complexity for marginal benefit. Consistent behavior across platforms means fewer bugs.

## D7: No desktop app special handling

**Decision:** Desktop apps are just a UI surface for the same agent engine. No platform-specific code for desktop vs CLI.

**Why:** Both desktop apps share config, plugins, skills, and the CLI binary with their respective CLIs. Session spawning goes through `Bash` tool -> `spawn-session.sh` -> CLI binary. The desktop app is transparent to Autoboard.

## D8: No JSONL output normalization needed

**Decision:** The orchestrator does not parse session JSONL streams. It uses exit code + status file + git log for session control. No output normalization layer needed.

**Why:** Investigation of the orchestrator's session consumption pattern revealed it uses a wait-and-check approach (exit code, `s{N}-status.md`, `git log`), not real-time stream parsing. The JSONL output is a transcript dump for debugging only. Both platforms' JSONL flags serve the same purpose — transcript capture — so different event schemas are irrelevant.

**Trade-off:** None. This simplifies the design by eliminating an entire adapter layer.

## D9: Relative symlinks for Codex skill discovery

**Decision:** `.agents/skills/` contains relative symlinks to `skills/` (e.g., `.agents/skills/brainstorm` -> `../../skills/brainstorm`). Committed to git.

**Why:** Codex discovers skills by scanning `.agents/skills/` from cwd up to repo root. Relative symlinks within the repo tree resolve correctly in both the main repo and git worktrees. No build step, no file duplication, no drift between platforms.

**Trade-off:** Symlinks don't work on Windows. Windows is out of scope (see design doc).

## D10: Ignore platform instruction files

**Decision:** Don't manage `CLAUDE.md` or `AGENTS.md`. Existing files in the repo are inherited by worktrees automatically. Session briefs carry all Autoboard-specific context.

**Why:** Both CLIs auto-load their instruction files from the working directory. Worktrees are copies of the repo. No duplication or generation needed.
