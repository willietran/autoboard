# Codex Compatibility Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Codex-compatible isolated session spawning to Autoboard while preserving the current product behavior and Claude compatibility.

**Architecture:** Keep the existing skill-driven orchestration model. Add a Codex headless worker launcher parallel to the current Claude wrapper, then make only the Claude-coupled skill and documentation references provider-aware. Do not redesign session flow, QA flow, or artifact conventions.

**Tech Stack:** Shell wrappers, Markdown skill docs, plugin metadata JSON, package metadata

---

### Task 1: Document The Provider Seam

**Files:**
- Create: `docs/plans/2026-04-12-codex-compatibility-design.md`
- Test: `git diff -- docs/plans/2026-04-12-codex-compatibility-design.md`

**Step 1: Verify the design doc exists**

Run: `test -f docs/plans/2026-04-12-codex-compatibility-design.md && echo OK`
Expected: `OK`

**Step 2: Review the approved scope**

Run: `sed -n '1,220p' docs/plans/2026-04-12-codex-compatibility-design.md`
Expected: Design states this is a compatibility project, not a redesign.

**Step 3: Commit the design artifact**

```bash
git add docs/plans/2026-04-12-codex-compatibility-design.md
git commit -m "docs: capture codex compatibility design"
```

### Task 2: Add A Codex Session Spawn Wrapper

**Files:**
- Create: `bin/spawn-codex-session.sh`
- Modify: `bin/spawn-session.sh`
- Test: `bin/spawn-codex-session.sh`

**Step 1: Write the failing compatibility checklist**

Create a short checklist in the plan notes for this task:

```text
- No Codex session wrapper exists
- Claude wrapper comments and naming imply it is the only runtime
- Process cleanup behavior must match the existing wrapper
```

**Step 2: Verify the gap exists**

Run: `test -f bin/spawn-codex-session.sh; echo $?`
Expected: `1`

**Step 3: Implement the Codex wrapper**

Add a new wrapper that mirrors the current session wrapper's responsibilities:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Parse the same high-level arguments as spawn-session.sh
# Build a prompt from the brief plus appended artifacts
# Launch the Codex headless binary with provider-specific flags
# Record PID/start time and clean up the full process group on exit
```

The orchestrator should select this wrapper explicitly when it is running on Codex. Do not make the wrapper auto-detect whether the parent platform is Codex or Claude.

**Step 4: Narrow the Claude wrapper wording**

Keep `bin/spawn-session.sh` behavior intact, but update comments and usage text so it is clearly the Claude launcher rather than the only launcher.

**Step 5: Run shell validation**

Run: `bash -n bin/spawn-session.sh bin/spawn-codex-session.sh`
Expected: no output, exit `0`

**Step 6: Commit**

```bash
git add bin/spawn-session.sh bin/spawn-codex-session.sh
git commit -m "feat: add codex session launcher"
```

### Task 3: Make Session Spawn Instructions Provider-Aware

**Files:**
- Modify: `skills/session-spawn/SKILL.md`
- Modify: `skills/run/SKILL.md`
- Modify: `skills/session-workflow/SKILL.md`
- Modify: `skills/task-manifest/SKILL.md`
- Test: `skills/session-spawn/SKILL.md`

**Step 1: Write the failing text search**

Run: `rg -n "claude -p|main Claude Code agent|Claude Code" skills/session-spawn/SKILL.md skills/run/SKILL.md skills/session-workflow/SKILL.md skills/task-manifest/SKILL.md`
Expected: multiple Claude-specific matches

**Step 2: Update only the execution-specific language**

Use concrete wording like:

```text
Spawn the configured provider's isolated session worker.
Sessions run non-interactively in a headless worker.
```

Retain the same workflow, gates, and artifact conventions.

Add one explicit rule to the instructions: provider is resolved by the current orchestrator invocation at spawn time, so resumed runs may launch new workers with a different provider than earlier workers.

**Step 3: Keep session behavior unchanged**

Ensure the skills still require:

```text
- isolated worker sessions
- session-local plan review and code review
- non-interactive execution
- no orchestrator-side implementation
```

**Step 4: Re-run the text search**

Run: `rg -n "claude -p|main Claude Code agent" skills/session-spawn/SKILL.md skills/run/SKILL.md skills/session-workflow/SKILL.md skills/task-manifest/SKILL.md`
Expected: only intentional Claude-specific references remain, if any

**Step 5: Commit**

```bash
git add skills/session-spawn/SKILL.md skills/run/SKILL.md skills/session-workflow/SKILL.md skills/task-manifest/SKILL.md
git commit -m "refactor: make session skills provider aware"
```

### Task 4: Update Fixer And Verification Paths

**Files:**
- Modify: `skills/qa-fixer/SKILL.md`
- Modify: `skills/coherence-fixer/SKILL.md`
- Modify: `skills/failure/SKILL.md`
- Modify: `skills/verification/SKILL.md`
- Test: `skills/qa-fixer/SKILL.md`

**Step 1: Write the failing search**

Run: `rg -n "spawn-session\\.sh|claude -p|Claude Code" skills/qa-fixer/SKILL.md skills/coherence-fixer/SKILL.md skills/failure/SKILL.md skills/verification/SKILL.md`
Expected: Claude-coupled references are present

**Step 2: Update fixer spawn instructions**

Replace hardcoded assumptions with provider-aware launcher language, while keeping the same fixer loop and worktree behavior.

Keep provider selection launch-time and explicit. Fixer skills should invoke the correct wrapper chosen by the current orchestrator, not rely on shell-side provider guessing.

**Step 3: Update verification wording carefully**

Keep non-interactive session constraints, but describe them as applying to headless worker sessions rather than Claude-only sessions.

**Step 4: Re-run the search**

Run: `rg -n "spawn-session\\.sh|claude -p|main Claude Code agent" skills/qa-fixer/SKILL.md skills/coherence-fixer/SKILL.md skills/failure/SKILL.md skills/verification/SKILL.md`
Expected: only intentional provider-specific references remain

**Step 5: Commit**

```bash
git add skills/qa-fixer/SKILL.md skills/coherence-fixer/SKILL.md skills/failure/SKILL.md skills/verification/SKILL.md
git commit -m "refactor: align fixer flows with provider compatibility"
```

### Task 5: Update Product And Package Metadata

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `package.json`
- Modify: `.claude-plugin/plugin.json`
- Test: `README.md`

**Step 1: Write the failing search**

Run: `rg -n "Claude Code|claude-code|claude -p|\\.claude-plugin" README.md CLAUDE.md package.json .claude-plugin/plugin.json`
Expected: current product language is Claude-only

**Step 2: Update user-facing wording**

Keep the same product promise, but describe Autoboard as supporting Claude and Codex instead of only Claude.

**Step 3: Keep Claude-specific docs where they still matter**

Do not delete Claude-specific development notes if they are still valid. Narrow them so they are accurate rather than universal.

**Step 4: Validate JSON files**

Run: `node -e "JSON.parse(require('fs').readFileSync('package.json','utf8')); JSON.parse(require('fs').readFileSync('.claude-plugin/plugin.json','utf8')); console.log('OK')"`
Expected: `OK`

**Step 5: Commit**

```bash
git add README.md CLAUDE.md package.json .claude-plugin/plugin.json
git commit -m "docs: describe codex compatibility"
```

### Task 6: Prove Claude And Codex Parity Paths

**Files:**
- Modify: `README.md`
- Modify: `docs/plans/2026-04-12-codex-compatibility.md`
- Test: `bin/spawn-session.sh`

**Step 1: Add a parity checklist**

Document the required validation cases:

```text
1. Claude isolated session still launches
2. Codex isolated session launches from the same brief shape
3. Session workflow remains non-interactive
4. Orchestrator-facing behavior is unchanged
5. New workers use the current orchestrator's provider on each spawn
```

**Step 2: Run structural verification**

Run: `bash -n bin/spawn-session.sh bin/spawn-codex-session.sh && rg -n "configured provider|isolated worker|Codex" README.md CLAUDE.md skills bin`
Expected: shell scripts parse and provider-aware wording is present

**Step 3: Record any unresolved runtime unknowns**

If the Codex CLI has flag or packaging uncertainties, record them explicitly in `README.md` or a short implementation note rather than silently guessing.

**Step 4: Final commit**

```bash
git add README.md docs/plans/2026-04-12-codex-compatibility.md bin/spawn-session.sh bin/spawn-codex-session.sh skills package.json .claude-plugin/plugin.json CLAUDE.md
git commit -m "chore: finalize codex compatibility plan"
```

Plan complete and saved to `docs/plans/2026-04-12-codex-compatibility.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
