---
name: coherence-fixer
description: Dispatch a fixer session agent for blocking coherence issues. Creates worktree, builds fixer brief, spawns agent, merges fix, re-audits with retry logic. Re-invoke at the start of each new layer.
---

# Coherence Fixer

Dispatch a full session agent to fix BLOCKING coherence issues. The fixer loads `/autoboard:session-workflow` and follows the complete Explore → Plan → Review → Implement → Verify → Code Review → Commit lifecycle.

**Prerequisites:** A COHERENCE-REPORT with BLOCKING issues from the coherence-audit skill. If tracking is active, the coherence-audit skill has already created an on-demand issue — use its issue number and item ID.

---

## Create Worktree and Write Brief

```bash
git worktree add /tmp/autoboard-{slug}-coherence-fix-L{N} -b autoboard/{slug}-coherence-fix-L{N} autoboard/{slug}
# Retry attempts: git worktree add /tmp/autoboard-{slug}-coherence-fix-L{N}-attempt{M} -b autoboard/{slug}-coherence-fix-L{N}-attempt{M} autoboard/{slug}
for f in .env*; do [ -f "$f" ] && ln -sf "$(pwd)/$f" /tmp/autoboard-{slug}-coherence-fix-L{N}/"$f"; done
```

Write brief to `/tmp/autoboard-{slug}-coherence-fix-L{N}-brief.md`:

```
You are a autoboard session agent.

Your FIRST action must be to invoke the /autoboard:session-workflow skill.
This loads your full workflow and shell safety guidelines.
Do NOT write any code or make any changes before invoking this skill.

## Session Brief

Session: Coherence Fix — Layer {N}
Feature branch: autoboard/{slug}
Session branch: autoboard/{slug}-coherence-fix-L{N}
Project directory: docs/autoboard/{slug}/
Worktree path: /tmp/autoboard-{slug}-coherence-fix-L{N}
Progress directory: /tmp/autoboard-{slug}-progress/

[COHERENCE FIX] Layer coherence audit found blocking issues after Layer {N}.

Coherence findings (full COHERENCE-REPORT):
{paste the full COHERENCE-REPORT block verbatim — not a paraphrased summary}

{For retry attempts, also include:}
Previous COHERENCE-REPORT (from attempt {M-1}):
{paste the previous COHERENCE-REPORT so the fixer can see what was already tried}

## Knowledge from Prior Sessions

{Paste the curated knowledge from docs/autoboard/{slug}/sessions/layer-{N}-knowledge.md
(or the latest layer knowledge file). Coherence issues are cross-session by nature —
the fixer benefits from understanding what patterns prior sessions established.
If no knowledge file exists: "No prior knowledge."}

Design doc: {path to design doc}

## Test Quality Context

{Read the design doc's ## Critical User Flows section and paste it here verbatim.
If the section does not exist, omit this block.}

{Read the manifest and extract all Key test scenarios fields from task records.
If no tasks have Key test scenarios, omit this block.}

These inform test quality remediation — if the BLOCKING findings include test quality issues,
the fix should ensure tests cover these scenarios.

Your job: fix the BLOCKING items in the coherence report. INFO items are informational only — do NOT fix them.

Follow the full session workflow: explore what's broken, plan the fix,
get it reviewed, implement, verify, get code reviewed, commit.

IMPORTANT: Your fix must solve the ROOT CAUSE, not paper over symptoms.
No hacky workarounds, no `as any` casts, no skipping tests, no
disabling checks. The fix must be elegant, clean, and durable — it
should be indistinguishable from code written correctly the first time.
If the root cause requires a significant refactor, do the refactor.

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

If tracking is active, append the `## Tracking` section using the coherence fix issue number and item ID from the coherence-audit skill. Use the `session-brief-section` action from the loaded tracking provider — same format as session briefs.

The fixer is a full session agent and will move through Exploring → Planning → Implementing → Verifying → Code Review phases on the tracking board.

If tracking is disabled, omit the Tracking section entirely.

---

## Spawn and Process

```bash
bin/spawn-session.sh /tmp/autoboard-{slug}-coherence-fix-L{N}-brief.md \
  --model {model from frontmatter} \
  --cwd /tmp/autoboard-{slug}-coherence-fix-L{N} \
  --settings "$PERM_FILE" \
  > /tmp/autoboard-{slug}-coherence-fix-L{N}-output.jsonl 2>&1
```

If `skip-permissions: true` in manifest, use `--skip-permissions` instead of `--settings`. **Pause future layers** until the fixer completes and the re-audit passes.

After the fixer completes:

1. **Read session status file** from `docs/autoboard/{slug}/sessions/` in the fixer worktree
2. **Tracking (if active):** `post-comment(coherence-issue, "Fixer attempt {M} complete. {summary}")`
3. **Merge fix** to the feature branch (squash merge — see merge skill)
4. **Re-run coherence audit** with the same checkpoint and same dimensions
5. **No BLOCKING issues:** `close-ticket` + `move-ticket(Done)`, proceed to QA gate or next layer
6. **Still BLOCKING:** Compare findings between consecutive COHERENCE-REPORTs, dispatch another fixer (see Retry Logic)

---

## Retry Logic

### Progress Detection

Compare consecutive COHERENCE-REPORTs to detect progress:
- **Progress** (findings changed — previous issues fixed, even if new ones surfaced): reset the consecutive-failure counter to 0
- **No progress** (same findings persist unchanged): increment the consecutive-failure counter

### Limits

- **Up to 5 consecutive non-progress attempts.** If 5 fixers in a row fail to resolve their assigned findings, escalate to the user.
- **Hard cap: 15 total fixer attempts per audit**, regardless of progress. This prevents infinite fix-break cycles.

Each fixer must explore the codebase and create a fix plan before implementing — no blind retries. Each attempt gets a new worktree (`-coherence-fix-L{N}-attempt{M}`).

### On Limit Reached

**Tracking (if active):**
```
post-comment(coherence-issue, "Coherence fixer limit reached after {M} attempts. Escalating to user.")
move-ticket(coherence-issue, Failed)
```

Escalate to the user — report the persistent findings and what was attempted. Do NOT continue to the QA gate with unresolved BLOCKING coherence issues.
