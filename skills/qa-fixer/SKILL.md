---
name: qa-fixer
description: Dispatch fixer session agents for QA gate failures. Triages failures, groups into parallel fixers, manages round-based retry loop. Re-invoke at the start of each new layer.
---

# QA Fixer

Dispatch full session agents to fix genuine code failures identified by the QA gate. Each fixer loads `/autoboard:session-workflow` and follows the complete Explore -> Plan -> Review -> Implement -> Verify -> Code Review -> Commit lifecycle.

**Prerequisites:** A QA-REPORT with genuine code failures (not infrastructure failures, not premature criteria). The qa-gate skill has already validated the failures and routed them here.

**Ownership model:** This skill owns the entire retry loop. The orchestrator invokes it once. It manages triage, grouping, parallel dispatch, merging, gate re-runs, and retry logic internally. It returns only when the gate passes or the round limit is exhausted.

---

## Tracking: Post Dispatch Comment

Read `docs/autoboard/{slug}/github-tracking.md` to get the QA gate issue number and item ID for this layer.

If tracking is active:
- `post-comment(qa-gate, "Dispatching fixer agent(s) for QA failures.")`
- `move-ticket(qa-gate, Implementing)`

---

## Step 1: Triage Failures

Parse the QA-REPORT and categorize each failed item:

- **Build failures:** Lint, type-check, build, or test step failures from the Build & Tests table
- **Browser acceptance failures:** FAIL rows from the Acceptance Criteria table
- **Browser regression failures:** FAIL rows from the Regression Tests table

### Build-First Rule

If ANY build steps failed, dispatch a **single build fixer** as Round 0. Build failures are foundational -- many browser failures are downstream symptoms. Fix the build first, re-run the gate, then assess remaining browser failures.

If Round 0 fails (build still broken after fixer completes), retry twice more (3 total Round 0 attempts). Round 0 attempts do not count against the 5-round cap. After 3 failed Round 0 attempts, proceed to Round 1 (which starts the 5-round counter) with both build and browser failures grouped together.

If no build failures, skip to Step 2.

---

## Step 2: Group Failures

After Round 0 (or if no build failures), count remaining failed items:

- **Total <= 5:** Dispatch a single fixer with all items (no fragmentation).
- **Total > 5:** Group into batches:
  - Acceptance criteria failures: groups of max 5
  - Regression failures: groups of max 5 (separate from acceptance)
  - Respect `max-parallel` concurrency limit from the manifest

For single-fixer dispatch, use group `g1`.

---

## Step 3: Round Loop

For each round (starting at Round 0 for build-first, or Round 1 for browser-only):

### 3a. Save Round Checkpoint

```bash
ROUND_CHECKPOINT=$(git rev-parse HEAD)
```

### 3b. Create Worktrees

Create worktrees **sequentially** (avoids git lock contention). All branch from feature branch HEAD at this point:

```bash
git worktree add /tmp/autoboard-{slug}-qa-fix-L{N}-r{round}-g{group} -b autoboard/{slug}-qa-fix-L{N}-r{round}-g{group} autoboard/{slug}
for f in .env*; do [ -f "$f" ] && ln -sf "$(pwd)/$f" /tmp/autoboard-{slug}-qa-fix-L{N}-r{round}-g{group}/"$f"; done
```

### 3c. Write Briefs

Write each fixer's brief to `/tmp/autoboard-{slug}-qa-fix-L{N}-r{round}-g{group}-brief.md`. The brief uses the **same template as today** -- all existing sections preserved. Two sections are added: "Your Assignment" (after Session Brief) and "Prior Round Summary" (for rounds > 0).

```
You are a autoboard session agent.

Your FIRST action must be to invoke /autoboard:session-workflow via the Skill tool.
This loads your full workflow and shell safety guidelines.
Do NOT write any code or make any changes before invoking this skill.

## Session Brief

Session: QA Fix -- Layer {N}, Round {round}, Group {group}
Feature branch: autoboard/{slug}
Session branch: autoboard/{slug}-qa-fix-L{N}-r{round}-g{group}
Project directory: docs/autoboard/{slug}/
Worktree path: /tmp/autoboard-{slug}-qa-fix-L{N}-r{round}-g{group}
Progress directory: /tmp/autoboard-{slug}-progress/

[QA FIX] QA gate failed after Layer {N}.

## Your Assignment

You are fixer {G} of {N} parallel fixers for round {round}.
Fix ONLY these items:

{list of assigned items with their criterion number, text, and evidence from the QA-REPORT}

Read the full QA-REPORT from the file path in the QA Findings section below. Other fixers are handling:
{for each other fixer: "- Fixer {K}: {brief summary of their assigned items}"}

Understanding what others are fixing helps you avoid conflicting changes.
If your fix would also resolve items assigned to another fixer, that is fine --
the gate re-run will detect it. Do NOT modify files solely for another
fixer's items if you can avoid it.

{For single-fixer rounds (only 1 group), simplify to:}
You are the only fixer for this round. Fix all items listed below.

## QA Findings

QA report: {absolute path to docs/autoboard/{slug}/sessions/qa-L{N}.md}
Read this file for the full QA-REPORT.

{For rounds > 0, also include:}
## Prior Round Summary

Round {R-1} resolved: {items}. Still failing: {items}.
{If carry-over from merge conflict:} Your items were carried over because the
prior fixer's merge conflicted. Changes merged by other fixers since then:
{diff summary from git diff ROUND_CHECKPOINT..HEAD}

Expected skips (user-acknowledged -- do NOT try to fix these):
{paste the expected-skips section from the manifest, or 'none'}

## Reference Files

Design doc: {absolute path to design doc} (read ## Critical User Flows section for test context)
Manifest: {absolute path to manifest.md} (read Key test scenarios from browser-marked tasks for test context)

These inform your fix -- if QA failures involve user flows or browser interactions,
read these files to understand what the expected behavior should be.

Your job: fix the criteria that FAILED in your assignment. Do NOT attempt to
fix EXPECTED SKIP criteria -- the user acknowledged those won't work yet.

Do NOT rewrite working code. Only fix what your assignment identifies.

## Mandatory Debugging Protocol (NON-NEGOTIABLE)

Before attempting ANY fix, you MUST:
1. Reproduce the exact failing criterion -- if QA failed in browser, reproduce in browser.
   Use the dev server and browser tool from your Configuration section.
2. Invoke /autoboard:diagnose via the Skill tool to trace root cause.
   This loads a structured four-phase methodology: Reproduce -> Trace -> Hypothesize -> Fix.
   Follow it completely -- no shortcuts.
3. Only after root cause is identified, plan and implement the fix.
4. After implementing, re-verify against the SAME criterion that failed (same mode --
   if it was a browser failure, test in browser). Light-mode verification (build+tests)
   is necessary but NOT sufficient -- you must also confirm the specific criterion passes.
5. Only commit if the criterion now passes.

Do NOT skip reproduction. Do NOT skip systematic debugging. Do NOT verify only with
build+tests when the failure was in browser. The fix is not done until the original
failing criterion passes in the same mode it originally failed.

Your fix must solve the ROOT CAUSE, not paper over symptoms.
No hacky workarounds, no `as any` casts, no skipping tests, no
disabling checks. The fix must be elegant, clean, and durable -- it
should be indistinguishable from code written correctly the first time.
If the root cause requires a significant refactor, do the refactor.

Knowledge from prior sessions: {absolute path to layer-{N}-knowledge.md} (read with Read tool, or "No prior knowledge" if file doesn't exist)

## Configuration

- Verify command: {verify from frontmatter}
- Dev server: {dev-server from frontmatter}
- QA mode: {qa-mode from frontmatter}
- Explore model: {explore-model from frontmatter, default: haiku}
- Plan review model: {plan-review-model from frontmatter, default: sonnet}
- Code review model: {code-review-model from frontmatter, default: sonnet}

## Available Skills and Agents

The session workflow will tell you when to use each of these:
- /autoboard:diagnose -- mandatory before attempting fixes (root cause investigation)
- /autoboard:verification-light -- verification protocol
- /autoboard:receiving-review -- critical thinking protocol for processing review feedback
- autoboard:plan-reviewer agent -- plan review (model: plan-review-model above)
- autoboard:code-reviewer agent -- code review (model: code-review-model above)
```

#### Tracking Section

If tracking is active, append the `## Tracking` section using the **QA gate issue number and item ID** (not a separate fixer issue -- the fixer posts progress to the QA gate issue). Use the `session-brief-section` action from the loaded tracking provider -- same format as session briefs but with the QA gate's IDs.

The fixer is a full session agent and will move through Exploring -> Planning -> Implementing -> Verifying -> Code Review phases on the tracking board.

If tracking is disabled, omit the Tracking section entirely.

### 3d. Spawn Fixers

Spawn all fixers in this round as **parallel background Bash commands**:

```bash
"$(cat /tmp/autoboard-plugin-dir)/bin/spawn-session.sh" /tmp/autoboard-{slug}-qa-fix-L{N}-r{round}-g{group}-brief.md \
  --model {model from frontmatter} \
  --cwd /tmp/autoboard-{slug}-qa-fix-L{N}-r{round}-g{group} \
  --settings "$PERM_FILE" \
  --standards "docs/autoboard/{slug}/standards.md" \
  --test-baseline "docs/autoboard/{slug}/test-baseline.md" \
  > /tmp/autoboard-{slug}-qa-fix-L{N}-r{round}-g{group}-output.jsonl 2>&1
```

If `skip-permissions: true` in manifest, use `--skip-permissions` instead of `--settings`.

Run each with Bash `run_in_background: true`. Spawn at most `max-parallel` fixers concurrently. If more groups exist than `max-parallel`, use the same sliding window as session-spawn (spawn next when one completes).

### 3e. Wait for Completion

Background Bash commands notify automatically when they complete. Do NOT poll or sleep.

### 3f. Merge Fixers

**Pause future layers** until all fixers complete and the re-run QA gate passes.

After all fixers in the round complete:

1. **Read session status files** from `docs/autoboard/{slug}/sessions/` in each fixer worktree
2. **Merge each fixer** to the feature branch sequentially (squash merge -- see merge skill). Commit message: `QA Fix L{N} r{round} g{group}: {brief description}`
3. **If a fixer merge conflicts** with a prior fixer's merge in the same round: abort the merge, skip this fixer, carry over its items to the next round with diff context
4. **Tracking (if active):** `post-comment(qa-gate, "Round {round} complete. {M} of {N} fixers merged. {summary}")`

### 3g. Post-Merge Verification (Circuit Breaker)

After all merges in the round, run the verify command:

```bash
{verify command from frontmatter}
```

If verification **passes**: proceed to gate re-run (Step 3h).

If verification **fails** (merge produced broken code):
- Roll back to `ROUND_CHECKPOINT`: `git reset --hard $ROUND_CHECKPOINT`
- Next round dispatches a **single fixer** for all remaining items (circuit breaker -- parallel merges caused conflicts, fall back to serial)
- Log: "Circuit breaker: post-merge verify failed. Falling back to single fixer for round {round+1}."

### 3h. Re-run QA Gate

Re-run the QA gate with the same acceptance criteria -- invoke the qa-gate skill again.

- **All criteria pass:** QA gate is clean. Done. Proceed to 3i.
- **Criteria still fail:** Proceed to Step 4 (Retry Logic).

### 3i. On Pass

**Tracking (if active):**
- `close-ticket(qa-gate)`
- `move-ticket(qa-gate, Done)`

Clean up all fixer worktrees and branches from this gate. Return to the orchestrator.

---

## Step 4: Retry Logic

### Progress Detection

Compare the set of failed criterion names between consecutive QA-REPORTs:
- **Progress** (failures changed -- previous issues fixed, even if new ones surfaced): Reset the consecutive-failure counter to 0. Log: "Round {R}: resolved {criteria}. New failures: {criteria}. Dispatching next round."
- **No progress** (same criteria still failing with same evidence): Increment the consecutive-failure counter. Log: "Round {R}: no progress on {criteria}. {remaining} rounds left."

### Limits

- **Max 5 rounds.** Every round counts regardless of progress. This prevents infinite fix-break cycles.
- **Max 3 consecutive non-progress rounds.** If 3 rounds in a row fail to resolve any items, escalate early.
- **Never ask the user** during the loop. Dispatch fixers automatically until the gate passes or limits are reached.

Each fixer must invoke `/autoboard:diagnose` and trace root cause before implementing -- no blind retries.

### Carry-Over Items

When items carry over to the next round (from failures or merge conflicts), the next round's brief includes:
- The updated QA-REPORT from the latest gate re-run
- A "## Prior Round Summary" showing what was resolved and what remains
- For merge-conflict carry-overs: the diff of what other fixers merged (`git diff $ROUND_CHECKPOINT..HEAD`)

Re-triage and re-group the remaining items for the next round (Step 2). The grouping may change -- fewer items may mean a single fixer suffices.

### On Limit Reached

**Tracking (if active):**
```
post-comment(qa-gate, "QA fixer limit reached after {M} rounds. Escalating to user.")
move-ticket(qa-gate, Failed)
```

Escalate to the user -- report all QA reports and what was attempted:

```
QA gate failed -- fixer limit reached ({M} rounds exhausted).
The gate must pass before proceeding.

Round summary:
{for each round: round number, fixers dispatched, items targeted, items resolved, items still failing}

Options:
1. I can retry with different instructions you provide
2. You investigate manually in the worktree at {path}
3. Stop the run (all worktrees preserved)
```

No "skip gate" option. The gate must pass or the run stops.
