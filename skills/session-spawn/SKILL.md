---
name: session-spawn
description: Create worktrees, build session briefs, and spawn session agents for a layer. Re-invoke at the start of each new layer to keep instructions fresh.
---

# Session Spawn

For each session in the current layer, create a worktree, build a session brief, and spawn the agent via `bin/spawn-session.sh`.

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

Symlink gitignored environment files into the worktree (git worktrees don't include gitignored files):
```bash
for f in .env*; do [ -f "$f" ] && ln -sf "$(pwd)/$f" /tmp/autoboard-{slug}-s{N}/"$f"; done
```

### Progress Directory

Create the shared progress directory:
```bash
mkdir -p /tmp/autoboard-{slug}-progress
```

---

## Resolve Session Permissions

Determine the permissions file path. These permissions apply only to **spawned session agents**, not the orchestrator or your main Claude Code agent. Sessions run in `dontAsk` mode (auto-deny unlisted tools — no hanging on permission prompts in headless mode):

```bash
PERM_FILE="docs/autoboard/{slug}/session-permissions.json"
if [[ ! -f "$PERM_FILE" ]]; then
  PERM_FILE="$PLUGIN_DIR/config/default-session-permissions.json"
fi
```

Read `$PLUGIN_DIR` from the temp file written by setup:
```bash
PLUGIN_DIR="$(cat /tmp/autoboard-plugin-dir)"
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
Feature branch: {branch}
Session branch: autoboard/{slug}-s{N}
Project directory: docs/autoboard/{slug}/
Worktree path: /tmp/autoboard-{slug}-s{N}
Progress directory: /tmp/autoboard-{slug}-progress/

## Tasks

{Copy each task's full record from the manifest: title, creates, modifies, depends on, requirements, explore targets, TDD phase, test approach, key test scenarios, complexity, commit message}

## Knowledge from Prior Sessions

Knowledge file: {absolute path to docs/autoboard/{slug}/sessions/layer-{N-1}-knowledge.md}
Read this file with the Read tool during your Explore phase for curated cross-session knowledge.
If Layer 0 or file doesn't exist: no prior knowledge.

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
- autoboard:plan-reviewer agent — plan review (model: plan-review-model above)
- autoboard:code-reviewer agent — code review (model: code-review-model above)
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
"$(cat /tmp/autoboard-plugin-dir)/bin/spawn-session.sh" /tmp/autoboard-{slug}-s{N}-brief.md \
  --model {model from frontmatter} \
  --effort {effort from sessions table} \
  --cwd /tmp/autoboard-{slug}-s{N} \
  --settings "$PERM_FILE" \
  --standards "docs/autoboard/{slug}/standards.md" \
  --test-baseline "docs/autoboard/{slug}/test-baseline.md" \
  > /tmp/autoboard-{slug}-s{N}-output.jsonl 2>&1
```

**Effort level:** Read the `Effort` column from the sessions table in the manifest and pass `--effort {level}` to the spawn script. The shell script handles the mapping — `medium` is the default and gets omitted from the `claude` invocation.

If the manifest has `skip-permissions: true`, use `--skip-permissions` instead of `--settings`:
```bash
"$(cat /tmp/autoboard-plugin-dir)/bin/spawn-session.sh" /tmp/autoboard-{slug}-s{N}-brief.md \
  --model {model from frontmatter} \
  --effort {effort from sessions table} \
  --cwd /tmp/autoboard-{slug}-s{N} \
  --skip-permissions \
  --standards "docs/autoboard/{slug}/standards.md" \
  --test-baseline "docs/autoboard/{slug}/test-baseline.md" \
  > /tmp/autoboard-{slug}-s{N}-output.jsonl 2>&1
```

Run each with Bash `run_in_background: true`. The shell wrapper (`bin/spawn-session.sh`) handles `--plugin-dir`, model ID mapping, effort level mapping, `--output-format stream-json`, mechanical injection of standards/test-baseline files into the prompt, and passes `--permission-mode dontAsk --settings <file>` to `claude` for scoped permissions.

**Do NOT paste standards or test-baseline content into the brief.** The shell script appends these files mechanically via `--standards` and `--test-baseline` flags. If the files don't exist, the script silently skips them.

Each session runs as a `claude -p` subprocess — a **full main agent** with complete tool access, including the Agent tool. This means sessions CAN spawn Explore subagents (haiku), plan-reviewer, and code-reviewer subagents.

### PID File

The spawn script automatically writes a PID file to `/tmp/autoboard-pids/s-{PID}.pid` with the PID and start time. The orchestrator's stale process reaper (in the run skeleton) uses these files to clean up orphaned processes from prior crashed runs.

---

## Concurrency Limiting

Spawn at most `max-parallel` sessions at a time (default: **4**, configurable in manifest frontmatter). Each session spawns MCP servers, subagents, and potentially dev servers — unbounded parallelism causes resource exhaustion. If a layer has more sessions than `max-parallel`:
1. Spawn the first `max-parallel` sessions as background Bash commands
2. Wait for any session to complete
3. Spawn the next session (maintain `max-parallel` concurrent)
4. Repeat until all sessions in the layer are done
