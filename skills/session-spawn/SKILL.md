---
name: session-spawn
description: Create worktrees, build session briefs, and spawn session agents for a layer. Re-invoke at the start of each new layer to keep instructions fresh.
---

# Session Spawn

For each session in the current layer, create a worktree, build a session brief, and spawn the agent via the current provider's isolated session launcher.

---

## Create Worktrees

Create a manual git worktree for each session:
```bash
git worktree add /tmp/autoboard-{slug}-s{N} -b autoboard/{slug}-s{N} {feature-branch}
```

If the worktree already exists (prior crashed run), check if the branch has useful commits before recreating:
```bash
git log autoboard/{slug}-s{N} --oneline 2>/dev/null
```
If commits exist, this is a resume — reuse the worktree. Otherwise, remove and recreate:
```bash
git worktree remove /tmp/autoboard-{slug}-s{N} --force 2>/dev/null
git branch -D autoboard/{slug}-s{N} 2>/dev/null
git worktree add /tmp/autoboard-{slug}-s{N} -b autoboard/{slug}-s{N} {feature-branch}
```

### Environment Symlinking

Symlink gitignored environment files and codesight context into the worktree (git worktrees don't include gitignored files):
```bash
for f in .env*; do [ -f "$f" ] && ln -sf "$(pwd)/$f" /tmp/autoboard-{slug}-s{N}/"$f"; done
[ -d .codesight ] && ln -sf "$(pwd)/.codesight" /tmp/autoboard-{slug}-s{N}/.codesight
```

### Progress Directory

Create the shared progress directory:
```bash
mkdir -p /tmp/autoboard-{slug}-progress
```

---

## Resolve Session Permissions

Determine the permissions file path. These permissions apply only to **spawned session agents**, not the orchestrator or your main Claude Code agent. Claude sessions run in `dontAsk` mode (auto-deny unlisted tools — no hanging on permission prompts in headless mode). Codex sessions currently use the nearest documented non-interactive sandbox mode instead of translating this file one-for-one:

```bash
PERM_FILE="docs/autoboard/{slug}/session-permissions.json"
if [[ ! -f "$PERM_FILE" ]]; then
  PERM_FILE="$PLUGIN_DIR/config/default-session-permissions.json"
fi
```

Read `$PLUGIN_DIR` from the temp file written by setup:
```bash
PLUGIN_DIR="$(cat /tmp/autoboard-plugin-dir)"
SESSION_SPAWN_SCRIPT="$(cat /tmp/autoboard-session-spawn-script)"
AUTOBOARD_PROVIDER="$(cat /tmp/autoboard-provider)"
```

Store `$PERM_FILE` -- you'll pass it to the spawn script via `--settings` when launching sessions.

If the manifest has `skip-permissions: true`, skip this step — the spawn script handles it with `--dangerously-skip-permissions`.

---

## Write Session Briefs

Write each session's brief to `/tmp/autoboard-{slug}-s{N}-brief.md`:

```
You are a autoboard session agent.

Your FIRST action must be to invoke /autoboard:session-workflow via the Skill tool.
This loads your full workflow and shell safety guidelines.
Do NOT write any code or make any changes before invoking this skill.

## Session Brief

Session: S{N} — {focus}
Provider: {value of /tmp/autoboard-provider}
Feature branch: {branch}
Session branch: autoboard/{slug}-s{N}
Project directory: docs/autoboard/{slug}/
Worktree path: /tmp/autoboard-{slug}-s{N}
Progress directory: /tmp/autoboard-{slug}-progress/
Plugin directory: {value of /tmp/autoboard-plugin-dir}
Codex repo-local skills: {worktree path}/.agents/skills

## Workflow Tier: {tier from sessions table}

{Include the matching block below. Only include ONE block per brief.}

--- If tier is light ---
Explore: Subagents unrestricted (haiku, separate context). After exploration, read only files in your creates/modifies lists and files Explore agents specifically recommend. Skip files already covered in your Knowledge section.
Plan: Inline plan in your progress file. Max 15 lines.
Plan Review: SKIP. Proceed directly to implementation.
Code Review: SKIP. Run the Self-Review Checklist below before committing.
--- End light ---

--- If tier is standard ---
Plan Review: 1 round max. Dispatch with directive: "Single-round review. APPROVE or return BLOCKING issues only. No NITs, no suggestions."
Code Review: 1 round max. Same single-round directive.
--- End standard ---

--- If tier is thorough ---
Full workflow. All phases run with full rigor, up to 3 review rounds each.
--- End thorough ---

## Context Discipline (BLOCKING)

Violating these rules will exhaust your context window and prevent task completion. The orchestrator considers context exhaustion a session failure. These are not suggestions.

1. NEVER re-read the manifest. Your tasks are in this brief.
2. Max 2 reads per file: initial read + post-edit verification.
3. NEVER read a file you just wrote. You know what's in it.
4. During TDD RED/GREEN: run ONLY the specific test file, not the full suite. Full suite runs only in REFACTOR verification and Phase 5.
5. Use Edit, not Write, for all modifications to existing files.
6. NEVER re-Write a file. Use Edit for subsequent changes.

{Include the self-review checklist below ONLY for light tier. Omit for standard and thorough.}

## Self-Review Checklist (replaces Code Review for light tier)

Before committing, run `git diff {feature-branch}...HEAD` and verify each item below. For each item, cite the specific file:line that confirms compliance. If you cannot cite evidence, the item FAILS - fix it before committing.

1. No dead code, unused imports, or debug artifacts
2. Error paths handled, not just happy path
3. Tests cover ALL key test scenarios from task records
4. Naming follows existing codebase conventions
5. No files modified outside your task scope
6. Quality standards satisfied (check your brief's standards section)
7. All tests pass (run full verify command, paste result)

## Tasks

{Copy each task's full record from the manifest: title, creates, modifies, depends on, requirements, explore targets, TDD phase, test approach, key test scenarios, complexity, commit message}

## Configuration

- Verify command: {verify from frontmatter}
- Dev server: {dev-server from frontmatter}
- Explore model: {explore-model from frontmatter, default: haiku}
- Plan review model: {plan-review-model from frontmatter, default: sonnet}
- Code review model: {code-review-model from frontmatter, default: sonnet}
- Auth strategy: {auth-strategy from frontmatter, default: none}
- Test credentials: {test-credentials from frontmatter, or 'none configured'}

## Available Skills and Agents

The session workflow will tell you when to use each of these:
- /autoboard:verification-light — verification protocol
- /autoboard:receiving-review — critical thinking protocol for processing review feedback
- Reviewer rubrics: `{plugin-dir}/agents/plan-reviewer.md` and `{plugin-dir}/agents/code-reviewer.md`
```

### Tracking Section

If tracking is active (tracking provider was loaded), append the provider's session brief template to each brief. Use the `session-brief-section` action from the loaded tracking provider.

For GitHub tracking, this appends a `## Tracking` section with `Provider: github`, issue IDs, item IDs, and command examples. See the tracking-github skill's "Session Brief Template" for the exact format.

If tracking is disabled, omit the Tracking section entirely.

### Resume Detection

If this is a **resume** (prior commits exist on the session branch), prepend to the brief:
```
[RESUME] This session has prior work. Check git log on your session branch before starting.
Do NOT redo completed tasks. Continue from the first incomplete task.
```

---

## Spawn via Shell Wrapper

Spawn all sessions in the layer as **parallel background Bash commands** in a single message:

```bash
"$SESSION_SPAWN_SCRIPT" /tmp/autoboard-{slug}-s{N}-brief.md \
  --model {model from frontmatter} \
  --effort {effort from sessions table} \
  --cwd /tmp/autoboard-{slug}-s{N} \
  --settings "$PERM_FILE" \
  --standards "docs/autoboard/{slug}/standards.md" \
  --test-baseline "docs/autoboard/{slug}/test-baseline.md" \
  --knowledge "docs/autoboard/{slug}/sessions/layer-{N-1}-knowledge.md" \
  --codesight ".codesight/wiki/index.md" \
  > /tmp/autoboard-{slug}-s{N}-output.jsonl 2>&1
```

**Effort level:** Read the `Effort` column from the sessions table in the manifest and pass `--effort {level}` to the spawn script. The shell script handles the provider-specific mapping. `medium` uses the provider default.

If the manifest has `skip-permissions: true`, use `--skip-permissions` instead of `--settings`:
```bash
"$SESSION_SPAWN_SCRIPT" /tmp/autoboard-{slug}-s{N}-brief.md \
  --model {model from frontmatter} \
  --effort {effort from sessions table} \
  --cwd /tmp/autoboard-{slug}-s{N} \
  --skip-permissions \
  --standards "docs/autoboard/{slug}/standards.md" \
  --test-baseline "docs/autoboard/{slug}/test-baseline.md" \
  --knowledge "docs/autoboard/{slug}/sessions/layer-{N-1}-knowledge.md" \
  --codesight ".codesight/wiki/index.md" \
  > /tmp/autoboard-{slug}-s{N}-output.jsonl 2>&1
```

Run each with Bash `run_in_background: true`. The selected shell wrapper handles provider-specific model/effort mapping, machine-readable output, and mechanical injection of standards/test-baseline/knowledge/codesight files into the prompt. The Claude launcher applies the permissions file directly. The Codex launcher uses the nearest documented non-interactive mode and may ignore `--settings` until Codex exposes an equivalent per-command permission manifest.

**Do NOT paste standards, test-baseline, knowledge, or codesight content into the brief.** The shell script appends these files mechanically via `--standards`, `--test-baseline`, `--knowledge`, and `--codesight` flags. If the files don't exist, the script silently skips them.

Each session runs as an isolated headless worker — a **full main agent** with complete tool access. That means sessions CAN spawn exploration helpers plus plan/code reviewers inside their own context instead of polluting the orchestrator.

### PID File

The spawn script automatically writes a PID file to `/tmp/autoboard-pids/s-{PID}.pid` with the PID and start time. The orchestrator's stale process reaper (in the run skeleton) uses these files to clean up orphaned processes from prior crashed runs.

---

## Concurrency Limiting

Spawn at most `max-parallel` sessions at a time (default: **4**, configurable in manifest frontmatter). Each session spawns MCP servers, subagents, and potentially dev servers — unbounded parallelism causes resource exhaustion. If a layer has more sessions than `max-parallel`:
1. Spawn the first `max-parallel` sessions as background Bash commands
2. Wait for any session to complete
3. Spawn the next session (maintain `max-parallel` concurrent)
4. Repeat until all sessions in the layer are done
