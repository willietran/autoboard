---
name: coherence-fixer
description: Dispatch fixer teammates for coherence issues that survived screening. Groups by dimension, spawns parallel fixers via Agent tool, manages round-based retry loop with post-merge circuit breaker. Re-invoke at the start of each new layer.
---

# Coherence Fixer

Dispatch fixer teammates to fix coherence issues that survived screener evaluation. Each fixer teammate must invoke `/autoboard:diagnose` before attempting any fixes.

**Prerequisites:** A COHERENCE-REPORT with findings that survived screening (BLOCKING, INFO, or both).

**Ownership model:** This skill owns the entire retry loop. The lead invokes it once. It manages grouping, parallel dispatch, merging, audit re-runs, and retry logic internally. It returns only when the audit is clean or the round limit is exhausted.

---

## Step 1: Group by Dimension

Parse the COHERENCE-REPORT and group findings by their source dimension.

### Grouping Rules

- **Each dimension's findings go to the same fixer.** Findings within a dimension share context and fixing approach.
- **If a dimension has > 8 findings:** Sub-split that dimension into groups of max 8.
- **Small dimensions (1-2 findings):** Combine with other small dimensions from the same conceptual group:
  - Structure: `code-organization`, `dry-code-reuse`, `config-management`
  - Safety: `security`, `error-handling`, `type-safety`
  - Quality: `test-quality`, `frontend-quality`, `api-design`
  - Runtime: `performance`, `observability`, `data-modeling`
- **Never combine across conceptual groups.** Security findings and test-quality findings go to separate fixers.
- **If total findings <= 5 from a single dimension:** Dispatch a single fixer (no fragmentation).
- Respect `max-batch-size` concurrency limit from the manifest.

For single-fixer dispatch, use group `g1`.

---

## Step 2: Round Loop

For each round (starting at Round 0):

### 2a. Save Round Checkpoint

```bash
ROUND_CHECKPOINT=$(git rev-parse HEAD)
```

### 2b. Create Worktrees

The lead creates worktrees **sequentially** (avoids git lock contention). All branch from feature branch HEAD at this point:

```bash
git worktree add /tmp/autoboard-{slug}-coherence-fix-L{N}-r{round}-g{group} -b autoboard/{slug}-coherence-fix-L{N}-r{round}-g{group} autoboard/{slug}
for f in .env*; do [ -f "$f" ] && ln -sf "$(pwd)/$f" /tmp/autoboard-{slug}-coherence-fix-L{N}-r{round}-g{group}/"$f"; done
[ -d .codesight ] && ln -sf "$(pwd)/.codesight" /tmp/autoboard-{slug}-coherence-fix-L{N}-r{round}-g{group}/.codesight
```

### 2c. Dispatch Fixer Teammates

Spawn fixer teammates via the Agent tool. Each fixer receives a prompt with its assignment, the COHERENCE-REPORT path, and mandatory debugging instructions.

Select the teammate model based on finding complexity:
- Straightforward convention or naming fixes: sonnet
- Complex architectural or cross-cutting findings, or findings that persisted across rounds: opus

Each fixer teammate prompt:

```
You are an autoboard fixer teammate.

## Assignment

You are fixer {G} of {total} parallel fixers for round {round}.
Your dimension(s): {dimension name(s)}
Fix ONLY these items:

{list of assigned findings with their dimension, severity, description, file locations, and evidence}

{For single-fixer rounds (only 1 group):}
You are the only fixer for this round. Fix all items listed below.

{For multi-fixer rounds, also include:}
Other fixers are handling:
{for each other fixer: "- Fixer {K}: {dimension(s)} - {brief summary of findings}"}

Understanding what others are fixing helps you avoid conflicting changes.
If your fix would also resolve items assigned to another fixer, that is fine -
the audit re-run will detect it. Do NOT modify files solely for another
fixer's items if you can avoid it.

## Coherence Findings

Coherence report: {absolute path to docs/autoboard/{slug}/sessions/coherence-L{N}.md}
You MUST read this file with the Read tool for the full COHERENCE-REPORT before starting any fixes.

{For rounds > 0, also include:}
## Prior Round Summary

Round {R-1} resolved: {items}. Still failing: {items}.
{If carry-over from merge conflict:} Your items were carried over because the
prior fixer's merge conflicted. Changes merged by other fixers since then:
{diff summary from git diff $ROUND_CHECKPOINT..HEAD}

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
2. Only after root cause is identified, plan and implement the fix.
3. After implementing, run full verification to confirm the fix.
4. Only mark your task complete if verification passes.

Do NOT skip reproduction. Do NOT skip systematic debugging.

Your fix must solve the ROOT CAUSE, not paper over symptoms.
No hacky workarounds, no `as any` casts, no skipping tests, no
disabling checks. The fix must be elegant, clean, and durable - it
should be indistinguishable from code written correctly the first time.
If the root cause requires a significant refactor, do the refactor.

Do NOT rewrite working code. Only fix what your assignment identifies.

## Configuration

- Verify command: {verify from config}
- Dev server: {dev-server from config}
- Worktree: /tmp/autoboard-{slug}-coherence-fix-L{N}-r{round}-g{group}
- Feature branch: autoboard/{slug}
```

Spawn at most `max-batch-size` fixers concurrently. If more groups exist than `max-batch-size`, spawn the next when one completes.

### 2d. Wait for Completion

Teammates notify automatically when they complete their tasks. Do NOT poll or sleep.

### 2e. Merge Fixers

**Pause future layers** until all fixers complete and the re-audit passes.

After all fixers in the round complete:

1. **Merge each fixer** to the feature branch sequentially (squash merge). Commit message: `Coherence Fix L{N} r{round} g{group}: {dimension(s)}`
2. **If a fixer merge conflicts** with a prior fixer's merge in the same round: abort the merge, skip this fixer, carry over its items to the next round with diff context

### 2f. Post-Merge Verification (Circuit Breaker)

After all merges in the round, run the verify command:

```bash
{verify command from config}
```

If verification **passes**: proceed to audit re-run (Step 2g).

If verification **fails** (merge produced broken code):
- Roll back to `ROUND_CHECKPOINT`: `git reset --hard $ROUND_CHECKPOINT`
- Next round dispatches a **single fixer** for all remaining items (circuit breaker - parallel merges caused conflicts, fall back to serial)
- Log: "Circuit breaker: post-merge verify failed. Falling back to single fixer for round {round+1}."

### 2g. Re-run Coherence Audit

Re-run the coherence audit with the same checkpoint and same dimensions.

- **No findings survive re-screening:** Audit is clean. Done. Proceed to 2h.
- **Findings remain:** Proceed to Step 3 (Retry Logic).

### 2h. On Pass

Clean up all fixer worktrees and branches from this gate. Return to the lead.

---

## Step 3: Retry Logic

### Progress Detection

Compare consecutive COHERENCE-REPORTs to detect progress:
- **Progress** (findings changed - previous issues fixed, even if new ones surfaced): Reset the consecutive-failure counter to 0. Log: "Round {R}: resolved {findings}. New findings: {findings}. Dispatching next round."
- **No progress** (same findings persist unchanged): Increment the consecutive-failure counter. Log: "Round {R}: no progress on {findings}. {remaining} rounds left."

### Limits

- **Max 5 rounds.** Every round counts regardless of progress. This prevents infinite fix-break cycles.
- **Max 3 consecutive non-progress rounds.** If 3 rounds in a row fail to resolve any items, escalate early.
- **Never ask the user** during the loop. Dispatch fixers automatically until the audit is clean or limits are reached.

Each fixer must invoke `/autoboard:diagnose` and trace root cause before implementing - no blind retries.

### Carry-Over Items

When items carry over to the next round (from failures or merge conflicts), the next round's prompt includes:
- The updated COHERENCE-REPORT from the latest audit re-run
- A "## Prior Round Summary" showing what was resolved and what remains
- For merge-conflict carry-overs: the diff of what other fixers merged (`git diff $ROUND_CHECKPOINT..HEAD`)

Re-group the remaining items for the next round (Step 1). The grouping may change - fewer items may mean a single fixer suffices.

### On Limit Reached

Escalate to the user - report the persistent findings and what was attempted:

```
Coherence audit failed - fixer limit reached ({M} rounds exhausted).
The audit must pass before proceeding to QA.

Round summary:
{for each round: round number, fixers dispatched, dimensions targeted, findings resolved, findings still open}

Options:
1. I can retry with different instructions you provide
2. You investigate manually in the worktree at {path}
3. Stop the run (all worktrees preserved)
```

Do NOT continue to the QA gate with unresolved coherence issues.
