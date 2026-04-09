---
name: qa-fixer
description: Dispatch fixer teammates for QA gate failures. Triages failures, groups into parallel fixers, manages round-based retry loop with build-first and post-merge circuit breaker. Re-invoke at the start of each new layer.
---

# QA Fixer

Dispatch fixer teammates to fix genuine code failures identified by the QA gate. Each fixer teammate must invoke `/autoboard:diagnose` before attempting any fixes.

**Prerequisites:** A QA-REPORT with genuine code failures (not infrastructure failures, not premature criteria). The qa-gate skill has already validated the failures and routed them here.

**Ownership model:** This skill owns the entire retry loop. The lead invokes it once. It manages triage, grouping, parallel dispatch, merging, gate re-runs, and retry logic internally. It returns only when the gate passes or the round limit is exhausted.

---

## Step 1: Triage Failures

Parse the QA-REPORT and categorize each failed item:

- **Build failures:** Lint, type-check, build, or test step failures from the Build & Tests table
- **Browser acceptance failures:** FAIL rows from the Acceptance Criteria table
- **Browser regression failures:** FAIL rows from the Regression Tests table

### Build-First Rule

If ANY build steps failed, dispatch a **single build fixer** as Round 0. Build failures are foundational - many browser failures are downstream symptoms. Fix the build first, re-run the gate, then assess remaining browser failures.

Round 0 runs up to 3 attempts. Each attempt dispatches a single fixer teammate for build failures only. Round 0 attempts do not count against the 5-round cap.

If all 3 Round 0 attempts fail (build still broken), proceed to Round 1 (which starts the 5-round counter) with both build and browser failures grouped together.

If no build failures, skip to Step 2.

---

## Step 2: Group Failures

After Round 0 (or if no build failures), count remaining failed items:

- **Total <= 5:** Dispatch a single fixer with all items (no fragmentation).
- **Total > 5:** Group into batches:
  - Acceptance criteria failures: groups of max 5
  - Regression failures: groups of max 5 (separate from acceptance)
  - Respect `max-batch-size` concurrency limit from the manifest

For single-fixer dispatch, use group `g1`.

---

## Step 3: Round Loop

For each round (starting at Round 0 for build-first, or Round 1 for browser-only):

### 3a. Save Round Checkpoint

```bash
ROUND_CHECKPOINT=$(git rev-parse HEAD)
```

### 3b. Create Worktrees

The lead creates worktrees **sequentially** (avoids git lock contention). All branch from feature branch HEAD at this point:

```bash
git worktree add /tmp/autoboard-{slug}-qa-fix-L{N}-r{round}-g{group} -b autoboard/{slug}-qa-fix-L{N}-r{round}-g{group} autoboard/{slug}
for f in .env*; do [ -f "$f" ] && ln -sf "$(pwd)/$f" /tmp/autoboard-{slug}-qa-fix-L{N}-r{round}-g{group}/"$f"; done
[ -d .codesight ] && ln -sf "$(pwd)/.codesight" /tmp/autoboard-{slug}-qa-fix-L{N}-r{round}-g{group}/.codesight
```

### 3c. Dispatch Fixer Teammates

Spawn fixer teammates via the Agent tool. Each fixer receives a prompt with its assignment, the QA-REPORT path, and mandatory debugging instructions.

Select the teammate model based on failure complexity:
- Build failures or straightforward test failures: sonnet
- Complex browser/integration failures or failures that persisted across rounds: opus

Each fixer teammate prompt:

```
You are an autoboard fixer teammate.

## Assignment

{For Round 0 (build-first):}
Fix build failures from QA gate Layer {N}. Focus exclusively on making the build pass.

{For Round 1+:}
You are fixer {G} of {total} parallel fixers for round {round}.
Fix ONLY these items:

{list of assigned items with their criterion number, text, and evidence from the QA-REPORT}

{For single-fixer rounds (only 1 group):}
You are the only fixer for this round. Fix all items listed below.

{For multi-fixer rounds, also include:}
Other fixers are handling:
{for each other fixer: "- Fixer {K}: {brief summary of their assigned items}"}

Understanding what others are fixing helps you avoid conflicting changes.
If your fix would also resolve items assigned to another fixer, that is fine -
the gate re-run will detect it. Do NOT modify files solely for another
fixer's items if you can avoid it.

## QA Findings

QA report: {absolute path to docs/autoboard/{slug}/sessions/qa-L{N}.md}
You MUST read this file with the Read tool for the full QA-REPORT before starting any fixes.

{For rounds > 0, also include:}
## Prior Round Summary

Round {R-1} resolved: {items}. Still failing: {items}.
{If carry-over from merge conflict:} Your items were carried over because the
prior fixer's merge conflicted. Changes merged by other fixers since then:
{diff summary from git diff $ROUND_CHECKPOINT..HEAD}

Expected skips (user-acknowledged - do NOT try to fix these):
{paste the expected-skips section from the manifest, or 'none'}

## Reference Files

Read these files with the Read tool before planning your fix:
- Design doc: {absolute path to design doc} - read the ## Critical User Flows section
- Manifest: {absolute path to manifest.md} - read Key test scenarios from tasks
- Standards: {absolute path to docs/autoboard/{slug}/standards.md}

## Mandatory Debugging Protocol (NON-NEGOTIABLE)

Before attempting ANY fix, you MUST:
1. Invoke /autoboard:diagnose via the Skill tool to reproduce the failure and trace root cause.
   This loads a structured four-phase methodology: Reproduce -> Trace -> Hypothesize -> Fix.
   Follow it completely - no shortcuts.
2. If the failure was in browser, reproduce in browser. Use the dev server and browser tool
   from your Configuration section.
3. Only after root cause is identified, plan and implement the fix.
4. After implementing, re-verify against the SAME criterion that failed (same mode -
   if it was a browser failure, test in browser). Light-mode verification (build+tests)
   is necessary but NOT sufficient - you must also confirm the specific criterion passes.
5. Only mark your task complete if the criterion now passes.

Do NOT skip reproduction. Do NOT skip systematic debugging. Do NOT verify only with
build+tests when the failure was in browser. The fix is not done until the original
failing criterion passes in the same mode it originally failed.

Your fix must solve the ROOT CAUSE, not paper over symptoms.
No hacky workarounds, no `as any` casts, no skipping tests, no
disabling checks. The fix must be elegant, clean, and durable - it
should be indistinguishable from code written correctly the first time.
If the root cause requires a significant refactor, do the refactor.

Do NOT rewrite working code. Only fix what your assignment identifies.

## Configuration

- Verify command: {verify from config}
- Dev server: {dev-server from config}
- QA Mode: {qa-mode from config}
- Worktree: /tmp/autoboard-{slug}-qa-fix-L{N}-r{round}-g{group}
- Feature branch: autoboard/{slug}
```

Spawn at most `max-batch-size` fixers concurrently. If more groups exist than `max-batch-size`, spawn the next when one completes.

### 3d. Wait for Completion

Teammates notify automatically when they complete their tasks. Do NOT poll or sleep.

### 3e. Merge Fixers

**Pause future layers** until all fixers complete and the re-run QA gate passes.

After all fixers in the round complete:

1. **Merge each fixer** to the feature branch sequentially (squash merge). Commit message: `QA Fix L{N} r{round} g{group}: {brief description}`
2. **If a fixer merge conflicts** with a prior fixer's merge in the same round: abort the merge, skip this fixer, carry over its items to the next round with diff context

### 3f. Post-Merge Verification (Circuit Breaker)

After all merges in the round, run the verify command:

```bash
{verify command from config}
```

If verification **passes**: proceed to gate re-run (Step 3g).

If verification **fails** (merge produced broken code):
- Roll back to `ROUND_CHECKPOINT`: `git reset --hard $ROUND_CHECKPOINT`
- Next round dispatches a **single fixer** for all remaining items (circuit breaker - parallel merges caused conflicts, fall back to serial)
- Log: "Circuit breaker: post-merge verify failed. Falling back to single fixer for round {round+1}."

### 3g. Re-run QA Gate

Re-run the QA gate with the same acceptance criteria - invoke the qa-gate skill again.

- **All criteria pass:** QA gate is clean. Done. Proceed to 3h.
- **Criteria still fail:** Proceed to Step 4 (Retry Logic).

### 3h. On Pass

Clean up all fixer worktrees and branches from this gate. Return to the lead.

---

## Step 4: Retry Logic

### Progress Detection

Compare the set of failed criterion names between consecutive QA-REPORTs:
- **Progress** (failures changed - previous issues fixed, even if new ones surfaced): Reset the consecutive-failure counter to 0. Log: "Round {R}: resolved {criteria}. New failures: {criteria}. Dispatching next round."
- **No progress** (same criteria still failing with same evidence): Increment the consecutive-failure counter. Log: "Round {R}: no progress on {criteria}. {remaining} rounds left."

### Limits

- **Max 5 rounds.** Every round counts regardless of progress. This prevents infinite fix-break cycles.
- **Max 3 consecutive non-progress rounds.** If 3 rounds in a row fail to resolve any items, escalate early.
- **Never ask the user** during the loop. Dispatch fixers automatically until the gate passes or limits are reached.

Each fixer must invoke `/autoboard:diagnose` and trace root cause before implementing - no blind retries.

### Carry-Over Items

When items carry over to the next round (from failures or merge conflicts), the next round's prompt includes:
- The updated QA-REPORT from the latest gate re-run
- A "## Prior Round Summary" showing what was resolved and what remains
- For merge-conflict carry-overs: the diff of what other fixers merged (`git diff $ROUND_CHECKPOINT..HEAD`)

Re-triage and re-group the remaining items for the next round (Step 2). The grouping may change - fewer items may mean a single fixer suffices.

### On Limit Reached

Escalate to the user - report all QA reports and what was attempted:

```
QA gate failed - fixer limit reached ({M} rounds exhausted).
The gate must pass before proceeding.

Round summary:
{for each round: round number, fixers dispatched, items targeted, items resolved, items still failing}

Options:
1. I can retry with different instructions you provide
2. You investigate manually in the worktree at {path}
3. Stop the run (all worktrees preserved)
```

No "skip gate" option. The gate must pass or the run stops.
