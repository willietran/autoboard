---
name: qa-fixer
description: Dispatch a fixer session agent for QA gate failures. Creates worktree, builds fixer brief, spawns agent, merges fix, re-runs QA gate with retry logic. Re-invoke at the start of each new layer.
---

# QA Fixer

Dispatch a full session agent to fix genuine code failures identified by the QA gate. The fixer loads `/autoboard:session-workflow` and follows the complete Explore -> Plan -> Review -> Implement -> Verify -> Code Review -> Commit lifecycle.

**Prerequisites:** A QA-REPORT with genuine code failures (not infrastructure failures, not premature criteria). The qa-gate skill has already validated the failures and routed them here.

---

## Tracking: Post Dispatch Comment

Read `docs/autoboard/{slug}/github-tracking.md` to get the QA gate issue number and item ID for this layer.

If tracking is active:
- `post-comment(qa-gate, "Dispatching fixer agent for QA failures.")`
- `move-ticket(qa-gate, Implementing)`

---

## Create Worktree and Write Brief

```bash
git worktree add /tmp/autoboard-{slug}-qa-fix-L{N} -b autoboard/{slug}-qa-fix-L{N} autoboard/{slug}
# Retry attempts: git worktree add /tmp/autoboard-{slug}-qa-fix-L{N}-attempt{M} -b autoboard/{slug}-qa-fix-L{N}-attempt{M} autoboard/{slug}
for f in .env*; do [ -f "$f" ] && ln -sf "$(pwd)/$f" /tmp/autoboard-{slug}-qa-fix-L{N}/"$f"; done
```

Write brief to `/tmp/autoboard-{slug}-qa-fix-L{N}-brief.md`:

```
You are a autoboard session agent.

Your FIRST action must be to invoke /autoboard:session-workflow via the Skill tool.
This loads your full workflow and shell safety guidelines.
Do NOT write any code or make any changes before invoking this skill.

## Session Brief

Session: QA Fix — Layer {N}
Feature branch: autoboard/{slug}
Session branch: autoboard/{slug}-qa-fix-L{N}
Project directory: docs/autoboard/{slug}/
Worktree path: /tmp/autoboard-{slug}-qa-fix-L{N}
Progress directory: /tmp/autoboard-{slug}-progress/

[QA FIX] QA gate failed after Layer {N}.

QA findings (full QA-REPORT):
{paste the full QA-REPORT block verbatim — not a paraphrased summary}

{For retry attempts, also include:}
Previous QA-REPORT (from attempt {M-1}):
{paste the previous QA-REPORT so the fixer can see what was already tried}

Expected skips (user-acknowledged — do NOT try to fix these):
{paste the expected-skips section from the manifest, or 'none'}

Design doc: {path to design doc}

## Test Quality Context

{Read the design doc's ## Critical User Flows section and paste it here verbatim.
If the section does not exist, omit this block.}

{Read the manifest and extract Key test scenarios from tasks marked Test approach: browser.
If no tasks have browser test scenarios, omit this block.}

These inform your fix — if QA failures involve user flows or browser interactions,
use these scenarios to understand what the expected behavior should be.

Your job: fix the criteria that FAILED in the QA report. Do NOT attempt to
fix EXPECTED SKIP criteria — the user acknowledged those won't work yet.

Follow the full session workflow: explore what's broken, plan the fix,
get it reviewed, implement, verify, get code reviewed, commit.

Do NOT rewrite working code. Only fix what the QA report identified.

IMPORTANT: Your fix must solve the ROOT CAUSE, not paper over symptoms.
No hacky workarounds, no `as any` casts, no skipping tests, no
disabling checks. The fix must be elegant, clean, and durable — it
should be indistinguishable from code written correctly the first time.
If the root cause requires a significant refactor, do the refactor.

## Knowledge from Prior Sessions

{Paste the curated knowledge from docs/autoboard/{slug}/sessions/layer-{N}-knowledge.md
(or the latest layer knowledge file). QA fixes benefit from understanding what
patterns prior sessions established.
If no knowledge file exists: "No prior knowledge."}

## Configuration

- Verify command: {verify from frontmatter}
- Dev server: {dev-server from frontmatter}
- Explore model: {explore-model from frontmatter, default: haiku}
- Plan review model: {plan-review-model from frontmatter, default: sonnet}
- Code review model: {code-review-model from frontmatter, default: sonnet}

## Quality Standards

{Read docs/autoboard/{slug}/standards.md and paste its COMPLETE content here verbatim.
Do NOT summarize, truncate, or replace with a file path reference — session agents cannot read this file themselves.
If the file does not exist, omit this section entirely.}

## Test Baseline

{Read docs/autoboard/{slug}/test-baseline.md and paste its COMPLETE content here verbatim.
Do NOT summarize, truncate, or replace with a file path reference — session agents cannot read this file themselves.
If the file does not exist or no baseline was captured, write 'No baseline captured.'}

## Available Skills and Agents

The session workflow will tell you when to use each of these:
- /autoboard:verification — verification protocol
- /autoboard:receiving-review — critical thinking protocol for processing review feedback
- autoboard:plan-reviewer agent — plan review (model: plan-review-model above)
- autoboard:code-reviewer agent — code review (model: code-review-model above)
```

### Tracking Section

If tracking is active, append the `## Tracking` section using the **QA gate issue number and item ID** (not a separate fixer issue — the fixer posts progress to the QA gate issue). Use the `session-brief-section` action from the loaded tracking provider — same format as session briefs but with the QA gate's IDs.

The fixer is a full session agent and will move through Exploring -> Planning -> Implementing -> Verifying -> Code Review phases on the tracking board.

If tracking is disabled, omit the Tracking section entirely.

---

## Spawn and Process

```bash
bin/spawn-session.sh /tmp/autoboard-{slug}-qa-fix-L{N}-brief.md \
  --model {model from frontmatter} \
  --cwd /tmp/autoboard-{slug}-qa-fix-L{N} \
  --settings "$PERM_FILE" \
  > /tmp/autoboard-{slug}-qa-fix-L{N}-output.jsonl 2>&1
```

If `skip-permissions: true` in manifest, use `--skip-permissions` instead of `--settings`. **Pause future layers** until the fixer completes and the re-run QA gate passes.

After the fixer completes:

1. **Read session status file** from `docs/autoboard/{slug}/sessions/` in the fixer worktree
2. **Tracking (if active):** `post-comment(qa-gate, "Fixer attempt {M} complete. {summary}")`
3. **Merge fix** to the feature branch (squash merge — see merge skill)
4. **Re-run QA gate** with the same acceptance criteria — invoke the qa-gate skill again
5. **QA passes:** `close-ticket(qa-gate)`, `move-ticket(qa-gate, Done)`, proceed to next layer
6. **QA fails again:** Compare the new failures against the previous failures, dispatch another fixer (see Retry Logic)

---

## Retry Logic

### Progress Detection

Compare the set of failed criterion names between consecutive QA-REPORTs:
- **Progress** (failures changed — previous issues fixed, even if new ones surfaced): reset the consecutive-failure counter to 0. Log: "Fixer made progress — previous failures resolved, new failures found. Counter reset."
- **No progress** (same criteria still failing): increment the consecutive-failure counter. Log: "Fixer did not resolve the assigned failures. Attempt {M} of 5."

### Limits

- **Up to 5 consecutive non-progress attempts.** If 5 fixers in a row fail to resolve their assigned failures, escalate to the user.
- **Hard cap: 15 total fixer attempts per gate**, regardless of progress. This prevents infinite fix-break cycles where each fix introduces exactly one new failure.

Each fixer must explore the codebase and create a fix plan before implementing — no blind retries. Each attempt gets a new worktree (`-qa-fix-L{N}-attempt{M}`).

### On Limit Reached

**Tracking (if active):**
```
post-comment(qa-gate, "QA fixer limit reached after {M} attempts. Escalating to user.")
move-ticket(qa-gate, Failed)
```

Escalate to the user — report all QA reports and what was attempted:

```
QA gate failed — fixer limit reached ({reason: "5 consecutive non-progress attempts" or "15 total attempts"}).
The gate must pass before proceeding.

Attempts summary:
{for each attempt: attempt number, which criteria it targeted, whether it made progress}

Options:
1. I can retry with different instructions you provide
2. You investigate manually in the worktree at {path}
3. Stop the run (all worktrees preserved)
```

No "skip gate" option. The gate must pass or the run stops.
