# Codex Compatibility Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Codex-compatible isolated session spawning to Autoboard while preserving the current product behavior and Claude compatibility.

**Architecture:** Keep the existing skill-driven orchestration model. First prove the Codex headless launcher contract and packaging constraints, then add a Codex worker wrapper parallel to the current Claude wrapper, update all worker spawn sites to choose the wrapper from the current orchestrator runtime at launch time, and validate parity with real runtime canaries rather than text-only checks.

**Tech Stack:** Shell wrappers, Markdown skill docs, plugin metadata JSON, package metadata

---

### Task 1: Prove The Codex Headless Contract

**Files:**
- Modify: `docs/plans/2026-04-12-codex-compatibility.md`
- Test: `codex --help`

**Step 1: Write the failing checklist**

Create a checklist in the task notes for the launcher contract:

```text
- Exact non-interactive Codex invocation is not yet locked
- Prompt/input mode is not yet proven against Autoboard's brief model
- Output format expectations are not yet proven
- Plugin loading and cwd semantics are not yet proven
- Permission behavior is not yet proven
```

**Step 2: Inspect the Codex CLI contract**

Run: `codex --help`
Expected: the CLI exposes the non-interactive entrypoint and relevant flags.

**Step 3: Prove the non-interactive entrypoint**

Run a minimal Codex command outside the product wrapper with:

```bash
codex exec --help
```

Expected: a concrete command shape exists for headless runs.

**Step 4: Prove key launcher behaviors**

Check and record:

```text
- prompt argument shape
- cwd selection
- output mode
- model and reasoning/effort flags
- plugin-dir or equivalent plugin loading behavior
- approval/sandbox settings needed for isolated workers
```

Record the verified contract directly in this plan file before continuing. If a behavior is not supported, write the limitation explicitly.

**Step 5: Commit the clarified contract**

```bash
git add docs/plans/2026-04-12-codex-compatibility.md
git commit -m "docs: lock codex launcher contract"
```

### Task 2: Confirm Packaging And Permission Compatibility

**Files:**
- Modify: `package.json`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `skills/task-manifest/SKILL.md`
- Test: `.claude-plugin/marketplace.json`

**Step 1: Write the failing search**

Run: `rg -n "claude-code|Claude Code|defaultMode|dontAsk|\\.claude-plugin" package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json skills/task-manifest/SKILL.md`
Expected: Claude-shaped packaging and permission assumptions are present.

**Step 2: Determine Codex packaging requirements**

Check whether Codex requires:

```text
- separate plugin manifest conventions
- additional metadata fields
- different marketplace metadata expectations
```

If Codex does not need extra packaging metadata, record that explicitly in the plan. If it does, add the deliverable to this task before implementation.

**Step 3: Determine permission compatibility**

Verify whether Codex isolated workers can honor the current session-permissions model or need a different settings shape. If fallback behavior is required, define it explicitly here.

**Step 4: Update scoped metadata and permissions docs**

Apply only the changes justified by the compatibility findings from Steps 2 and 3.

**Step 5: Validate JSON files**

Run: `node -e "JSON.parse(require('fs').readFileSync('package.json','utf8')); JSON.parse(require('fs').readFileSync('.claude-plugin/plugin.json','utf8')); JSON.parse(require('fs').readFileSync('.claude-plugin/marketplace.json','utf8')); console.log('OK')"`
Expected: `OK`

**Step 6: Commit**

```bash
git add package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json skills/task-manifest/SKILL.md
git commit -m "docs: define codex packaging and permissions compatibility"
```

### Task 3: Add A Codex Session Spawn Wrapper

**Files:**
- Create: `bin/spawn-codex-session.sh`
- Modify: `bin/spawn-session.sh`
- Test: `bin/spawn-codex-session.sh`

**Step 1: Verify the gap exists**

Run: `test -f bin/spawn-codex-session.sh; echo $?`
Expected: `1`

**Step 2: Implement the Codex wrapper**

Add a new wrapper that mirrors the current session wrapper's responsibilities using the proven contract from Task 1:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Parse the same high-level arguments as spawn-session.sh
# Build a prompt from the brief plus appended artifacts
# Launch the Codex headless binary with the proven flags
# Record PID/start time and clean up the full process group on exit
```

**Step 3: Keep wrapper selection explicit**

The orchestrator selects this wrapper explicitly when it is running on Codex. Do not make the wrapper auto-detect whether the parent platform is Codex or Claude.

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

### Task 4: Define Provider Selection At Every Spawn Site

**Files:**
- Modify: `skills/session-spawn/SKILL.md`
- Modify: `skills/qa-fixer/SKILL.md`
- Modify: `skills/coherence-fixer/SKILL.md`
- Modify: `skills/failure/SKILL.md`
- Modify: `skills/setup/SKILL.md`
- Test: `skills/session-spawn/SKILL.md`

**Step 1: Write the failing search**

Run: `rg -n "spawn-session\\.sh|bin/spawn-session\\.sh|claude -p" skills/session-spawn/SKILL.md skills/qa-fixer/SKILL.md skills/coherence-fixer/SKILL.md skills/failure/SKILL.md skills/setup/SKILL.md`
Expected: hardcoded Claude launcher references are present.

**Step 2: Document one provider-selection rule**

Use this rule consistently:

```text
At each worker spawn, the current orchestrator chooses the wrapper that matches its own provider runtime.
Claude orchestrator -> spawn-session.sh
Codex orchestrator -> spawn-codex-session.sh
```

This rule must be applied to:

```text
- normal session spawns
- fixer spawns
- failure retries
- any setup/discovery text that assumes only one wrapper exists
```

**Step 3: Update every spawn site**

Change the instructions so they name the explicit wrapper-selection rule instead of relying on shell-side guessing or vague provider-aware wording.

**Step 4: Re-run the search**

Run: `rg -n "spawn-session\\.sh|bin/spawn-session\\.sh|claude -p" skills/session-spawn/SKILL.md skills/qa-fixer/SKILL.md skills/coherence-fixer/SKILL.md skills/failure/SKILL.md skills/setup/SKILL.md`
Expected: remaining matches are intentional Claude-specific references only.

**Step 5: Commit**

```bash
git add skills/session-spawn/SKILL.md skills/qa-fixer/SKILL.md skills/coherence-fixer/SKILL.md skills/failure/SKILL.md skills/setup/SKILL.md
git commit -m "refactor: make worker spawn selection explicit"
```

### Task 5: Make Session And Verification Instructions Provider-Aware

**Files:**
- Modify: `skills/run/SKILL.md`
- Modify: `skills/session-workflow/SKILL.md`
- Modify: `skills/task-manifest/SKILL.md`
- Modify: `skills/verification/SKILL.md`
- Test: `skills/session-workflow/SKILL.md`

**Step 1: Write the failing text search**

Run: `rg -n "claude -p|main Claude Code agent|Claude Code" skills/run/SKILL.md skills/session-workflow/SKILL.md skills/task-manifest/SKILL.md skills/verification/SKILL.md`
Expected: multiple Claude-specific matches

**Step 2: Update only the execution-specific language**

Use concrete wording like:

```text
Spawn the configured provider's isolated session worker.
Sessions run non-interactively in a headless worker.
```

Retain the same workflow, gates, and artifact conventions.

**Step 3: Keep session behavior unchanged**

Ensure the skills still require:

```text
- isolated worker sessions
- session-local plan review and code review
- non-interactive execution
- no orchestrator-side implementation
```

**Step 4: Re-run the text search**

Run: `rg -n "claude -p|main Claude Code agent" skills/run/SKILL.md skills/session-workflow/SKILL.md skills/task-manifest/SKILL.md skills/verification/SKILL.md`
Expected: only intentional Claude-specific references remain, if any

**Step 5: Commit**

```bash
git add skills/run/SKILL.md skills/session-workflow/SKILL.md skills/task-manifest/SKILL.md skills/verification/SKILL.md
git commit -m "refactor: align workflow docs with provider compatibility"
```

### Task 6: Update Product Metadata And Positioning

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `package.json`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Test: `README.md`

**Step 1: Write the failing search**

Run: `rg -n "Claude Code|claude-code|claude -p|\\.claude-plugin" README.md CLAUDE.md package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json`
Expected: current product language is Claude-only

**Step 2: Update user-facing wording**

Keep the same product promise, but describe Autoboard as supporting Claude and Codex instead of only Claude.

**Step 3: Keep Claude-specific docs where they still matter**

Do not delete Claude-specific development notes if they are still valid. Narrow them so they are accurate rather than universal.

**Step 4: Validate JSON files**

Run: `node -e "JSON.parse(require('fs').readFileSync('package.json','utf8')); JSON.parse(require('fs').readFileSync('.claude-plugin/plugin.json','utf8')); JSON.parse(require('fs').readFileSync('.claude-plugin/marketplace.json','utf8')); console.log('OK')"`
Expected: `OK`

**Step 5: Commit**

```bash
git add README.md CLAUDE.md package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "docs: describe codex compatibility"
```

### Task 7: Prove Runtime Parity Instead Of Structural Similarity

**Files:**
- Modify: `README.md`
- Modify: `docs/plans/2026-04-12-codex-compatibility.md`
- Test: `bin/spawn-session.sh`

**Step 1: Add the runtime validation checklist**

Document the required validation cases:

```text
1. Claude isolated session still launches
2. Codex isolated session launches from the same brief shape
3. One full isolated Codex canary session completes the workflow
4. A resumed run spawns new workers using the current orchestrator's provider
5. A small multi-session run proves orchestration behavior is unchanged
```

**Step 2: Run Claude smoke validation**

Run a minimal isolated Claude worker smoke test using the current wrapper and a minimal brief.
Expected: worker launches and returns machine-readable output.

**Step 3: Run Codex smoke validation**

Run the same minimal isolated worker smoke test through the Codex wrapper.
Expected: worker launches and returns the expected output shape.

**Step 4: Run one full Codex canary session**

Use a narrow canary brief that exercises the actual session workflow contract.
Expected: the isolated worker can load the workflow, operate in the worktree, and finish cleanly.

**Step 5: Prove resumed-run provider selection**

Simulate or document a resume scenario where the current orchestrator provider differs from an earlier one, and verify that new workers use the current orchestrator's provider.

**Step 6: Run a small orchestration canary**

Execute a minimal multi-session proof that demonstrates:

```text
- isolated workers still coordinate through artifacts
- orchestrator behavior stays the same
- QA/coherence flow is not regressed by the compatibility changes
```

**Step 7: Record unresolved runtime limitations**

If a Codex runtime limitation remains, record it explicitly in `README.md` or the plan rather than silently claiming parity.

**Step 8: Final commit**

```bash
git add README.md docs/plans/2026-04-12-codex-compatibility.md bin/spawn-session.sh bin/spawn-codex-session.sh skills package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json CLAUDE.md
git commit -m "chore: finalize codex compatibility plan"
```

Plan complete and saved to `docs/plans/2026-04-12-codex-compatibility.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
