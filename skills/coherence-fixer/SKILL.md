---
name: coherence-fixer
description: Dispatch fixer session agents for coherence issues that survived pre-screening. Groups by dimension, spawns parallel fixers, manages round-based retry loop. Re-invoke at the start of each new layer.
---

# Coherence Fixer

Dispatch full session agents to fix coherence issues that survived orchestrator pre-screening. Each fixer loads `/autoboard:session-workflow` and follows the complete Explore -> Plan -> Review -> Implement -> Verify -> Code Review -> Commit lifecycle.

**Prerequisites:** A COHERENCE-REPORT with findings that survived orchestrator pre-screening (BLOCKING, INFO, or both). If tracking is active, the coherence-audit skill has already created an on-demand issue -- use its issue number and item ID.

**Ownership model:** This skill owns the entire retry loop. The orchestrator invokes it once. It manages grouping, parallel dispatch, merging, audit re-runs, and retry logic internally. It returns only when the audit is clean or the round limit is exhausted.

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
- Respect `max-parallel` concurrency limit from the manifest.

For single-fixer dispatch, use group `g1`.

---

## Step 2: Round Loop

For each round (starting at Round 0):

### 2a. Save Round Checkpoint

```bash
ROUND_CHECKPOINT=$(git rev-parse HEAD)
```

### 2b. Create Worktrees

Create worktrees **sequentially** (avoids git lock contention). All branch from feature branch HEAD at this point:

```bash
git worktree add /tmp/autoboard-{slug}-coherence-fix-L{N}-r{round}-g{group} -b autoboard/{slug}-coherence-fix-L{N}-r{round}-g{group} autoboard/{slug}
for f in .env*; do [ -f "$f" ] && ln -sf "$(pwd)/$f" /tmp/autoboard-{slug}-coherence-fix-L{N}-r{round}-g{group}/"$f"; done
```

### 2c. Write Briefs

Write each fixer's brief to `/tmp/autoboard-{slug}-coherence-fix-L{N}-r{round}-g{group}-brief.md`. The brief uses the **same template as today** -- all existing sections preserved. Two sections are added: "Your Assignment" (after Session Brief) and "Prior Round Summary" (for rounds > 0).

```
You are a autoboard session agent.

Your FIRST action must be to invoke /autoboard:session-workflow via the Skill tool.
This loads your full workflow and shell safety guidelines.
Do NOT write any code or make any changes before invoking this skill.

## Session Brief

Session: Coherence Fix -- Layer {N}, Round {round}, Group {group}
Feature branch: autoboard/{slug}
Session branch: autoboard/{slug}-coherence-fix-L{N}-r{round}-g{group}
Project directory: docs/autoboard/{slug}/
Worktree path: /tmp/autoboard-{slug}-coherence-fix-L{N}-r{round}-g{group}
Progress directory: /tmp/autoboard-{slug}-progress/

[COHERENCE FIX] Layer coherence audit found issues after Layer {N}.

## Your Assignment

You are fixer {G} of {N} parallel fixers for round {round}.
Your dimension(s): {dimension name(s)}
Fix ONLY these items:

{list of assigned findings with their dimension, severity, description, file locations, and evidence}

The full COHERENCE-REPORT is below for context. Other fixers are handling:
{for each other fixer: "- Fixer {K}: {dimension(s)} -- {brief summary of findings}"}

Understanding what others are fixing helps you avoid conflicting changes.
If your fix would also resolve items assigned to another fixer, that is fine --
the audit re-run will detect it. Do NOT modify files solely for another
fixer's items if you can avoid it.

{For single-fixer rounds (only 1 group), simplify to:}
You are the only fixer for this round. Fix all items listed below.

## Coherence Findings

Coherence findings (full COHERENCE-REPORT):
{paste the full COHERENCE-REPORT block verbatim -- not a paraphrased summary}

{For rounds > 0, also include:}
## Prior Round Summary

Round {R-1} resolved: {items}. Still failing: {items}.
{If carry-over from merge conflict:} Your items were carried over because the
prior fixer's merge conflicted. Changes merged by other fixers since then:
{diff summary from git diff ROUND_CHECKPOINT..HEAD}

## Knowledge from Prior Sessions

{Paste the curated knowledge from docs/autoboard/{slug}/sessions/layer-{N}-knowledge.md
(or the latest layer knowledge file). Coherence issues are cross-session by nature --
the fixer benefits from understanding what patterns prior sessions established.
If no knowledge file exists: "No prior knowledge."}

Design doc: {path to design doc}

## Test Quality Context

{Read the design doc's ## Critical User Flows section and paste it here verbatim.
If the section does not exist, omit this block.}

{Read the manifest and extract all Key test scenarios fields from task records.
If no tasks have Key test scenarios, omit this block.}

These inform test quality remediation -- if the BLOCKING findings include test quality issues,
the fix should ensure tests cover these scenarios.

Your job: fix all items in your assignment that survived orchestrator pre-screening -- BLOCKING and INFO alike. Address BLOCKING items first. Apply the receiving-review decision tree to each finding: fix unless the fix would cause demonstrable harm (breaks something, conflicts with design doc, destabilizes other sessions).

Follow the full session workflow: explore what's broken, plan the fix,
get it reviewed, implement, verify, get code reviewed, commit.

IMPORTANT: Your fix must solve the ROOT CAUSE, not paper over symptoms.
No hacky workarounds, no `as any` casts, no skipping tests, no
disabling checks. The fix must be elegant, clean, and durable -- it
should be indistinguishable from code written correctly the first time.
If the root cause requires a significant refactor, do the refactor.

## Configuration

- Verify command: {verify from frontmatter}
- Dev server: {dev-server from frontmatter}
- Explore model: {explore-model from frontmatter, default: haiku}
- Plan review model: {plan-review-model from frontmatter, default: sonnet}
- Code review model: {code-review-model from frontmatter, default: sonnet}

## Available Skills and Agents

The session workflow will tell you when to use each of these:
- /autoboard:verification -- verification protocol
- /autoboard:receiving-review -- critical thinking protocol for processing review feedback
- autoboard:plan-reviewer agent -- plan review (model: plan-review-model above)
- autoboard:code-reviewer agent -- code review (model: code-review-model above)
```

#### Tracking Section

If tracking is active, append the `## Tracking` section using the coherence fix issue number and item ID from the coherence-audit skill. Use the `session-brief-section` action from the loaded tracking provider -- same format as session briefs.

The fixer is a full session agent and will move through Exploring -> Planning -> Implementing -> Verifying -> Code Review phases on the tracking board.

If tracking is disabled, omit the Tracking section entirely.

### 2d. Spawn Fixers

Spawn all fixers in this round as **parallel background Bash commands**:

```bash
bin/spawn-session.sh /tmp/autoboard-{slug}-coherence-fix-L{N}-r{round}-g{group}-brief.md \
  --model {model from frontmatter} \
  --cwd /tmp/autoboard-{slug}-coherence-fix-L{N}-r{round}-g{group} \
  --settings "$PERM_FILE" \
  --standards "docs/autoboard/{slug}/standards.md" \
  --test-baseline "docs/autoboard/{slug}/test-baseline.md" \
  > /tmp/autoboard-{slug}-coherence-fix-L{N}-r{round}-g{group}-output.jsonl 2>&1
```

If `skip-permissions: true` in manifest, use `--skip-permissions` instead of `--settings`.

Run each with Bash `run_in_background: true`. Spawn at most `max-parallel` fixers concurrently. If more groups exist than `max-parallel`, use the same sliding window as session-spawn (spawn next when one completes).

### 2e. Wait for Completion

Background Bash commands notify automatically when they complete. Do NOT poll or sleep.

### 2f. Merge Fixers

**Pause future layers** until all fixers complete and the re-audit passes.

After all fixers in the round complete:

1. **Read session status files** from `docs/autoboard/{slug}/sessions/` in each fixer worktree
2. **Merge each fixer** to the feature branch sequentially (squash merge -- see merge skill). Commit message: `Coherence Fix L{N} r{round} g{group}: {dimension(s)}`
3. **If a fixer merge conflicts** with a prior fixer's merge in the same round: abort the merge, skip this fixer, carry over its items to the next round with diff context
4. **Tracking (if active):** `post-comment(coherence-issue, "Round {round} complete. {M} of {N} fixers merged. {summary}")`

### 2g. Post-Merge Verification (Circuit Breaker)

After all merges in the round, run the verify command:

```bash
{verify command from frontmatter}
```

If verification **passes**: proceed to audit re-run (Step 2h).

If verification **fails** (merge produced broken code):
- Roll back to `ROUND_CHECKPOINT`: `git reset --hard $ROUND_CHECKPOINT`
- Next round dispatches a **single fixer** for all remaining items (circuit breaker -- parallel merges caused conflicts, fall back to serial)
- Log: "Circuit breaker: post-merge verify failed. Falling back to single fixer for round {round+1}."

### 2h. Re-run Coherence Audit

Re-run the coherence audit with the same checkpoint and same dimensions.

- **No findings survive re-screening:** Audit is clean. Done. Proceed to 2i.
- **Findings remain:** Proceed to Step 3 (Retry Logic).

### 2i. On Pass

**Tracking (if active):**
- `close-ticket(coherence-issue)`
- `move-ticket(coherence-issue, Done)`

Clean up all fixer worktrees and branches from this gate. Return to the orchestrator.

---

## Step 3: Retry Logic

### Progress Detection

Compare consecutive COHERENCE-REPORTs to detect progress:
- **Progress** (findings changed -- previous issues fixed, even if new ones surfaced): Reset the consecutive-failure counter to 0. Log: "Round {R}: resolved {findings}. New findings: {findings}. Dispatching next round."
- **No progress** (same findings persist unchanged): Increment the consecutive-failure counter. Log: "Round {R}: no progress on {findings}. {remaining} rounds left."

### Limits

- **Max 5 rounds.** Every round counts regardless of progress. This prevents infinite fix-break cycles.
- **Max 3 consecutive non-progress rounds.** If 3 rounds in a row fail to resolve any items, escalate early.
- **Never ask the user** during the loop. Dispatch fixers automatically until the audit is clean or limits are reached.

Each fixer must explore the codebase and create a fix plan before implementing -- no blind retries.

### Carry-Over Items

When items carry over to the next round (from failures or merge conflicts), the next round's brief includes:
- The updated COHERENCE-REPORT from the latest audit re-run
- A "## Prior Round Summary" showing what was resolved and what remains
- For merge-conflict carry-overs: the diff of what other fixers merged (`git diff $ROUND_CHECKPOINT..HEAD`)

Re-group the remaining items for the next round (Step 1). The grouping may change -- fewer items may mean a single fixer suffices.

### On Limit Reached

**Tracking (if active):**
```
post-comment(coherence-issue, "Coherence fixer limit reached after {M} rounds. Escalating to user.")
move-ticket(coherence-issue, Failed)
```

Escalate to the user -- report the persistent findings and what was attempted:

```
Coherence audit failed -- fixer limit reached ({M} rounds exhausted).
The audit must pass before proceeding to QA.

Round summary:
{for each round: round number, fixers dispatched, dimensions targeted, findings resolved, findings still open}

Options:
1. I can retry with different instructions you provide
2. You investigate manually in the worktree at {path}
3. Stop the run (all worktrees preserved)
```

Do NOT continue to the QA gate with unresolved coherence issues.
