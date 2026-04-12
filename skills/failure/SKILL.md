---
name: failure
description: Diagnose session failures, arbitrate escalations, handle permission denials, cascade dependency blocks, and retry with adjusted briefs
---

# Failure Handling

A session on your team failed. Before deciding what to do, understand what happened. You are the engineering lead — diagnose first, then act.

**Prerequisites:** A session completed with non-zero exit code or missing/failed status. You have the manifest, design doc, and quality standards in context.

---

## Step 1: Gather Evidence

Dispatch the `evidence-gatherer` helper via your provider's subagent mechanism with model `explore-model` and these inputs. On Claude Code, use the `autoboard:evidence-gatherer` agent directly. On Codex, spawn a read-only helper and tell it to read `$(cat /tmp/autoboard-plugin-dir)/agents/evidence-gatherer.md` before beginning.

- Session ID and slug
- JSONL output path: `/tmp/autoboard-{slug}-s{N}-output.jsonl`
- Status file path: `docs/autoboard/{slug}/sessions/s{N}-status.md` (in worktree `/tmp/autoboard-{slug}-s{N}/`)
- Git branch name: `autoboard/{slug}-s{N}`
- Progress file path: `/tmp/autoboard-{slug}-progress/s{N}.md`

The agent reads all four evidence sources and returns a compressed structured summary with: `error_excerpts`, `failed_phase`, `tasks_committed`, `preliminary_classification`, `suggested_retry_approach`, `has_escalation`, `escalation_detail`, `permission_denied_command`.

---

## Step 2: Classify Failure

Use the evidence summary from Step 1 to classify into one of four categories:

### 2a. Permission Denial

If `preliminary_classification` is `permission_denial` (or `error_excerpts` contain "permission denied", "auto-denied", "not allowed", "tool not permitted"), this is a permissions/sandbox issue, not a code issue.

**Do NOT retry.** Retrying with the same permissions will hit the same denial. Report to the user immediately:

```
S{N} ({focus}) failed — a tool was denied by the session runtime.
Denied command: {from evidence summary's permission_denied_command}

If this run is on Claude Code:
- add the matching Bash rule to docs/autoboard/{slug}/session-permissions.json
- Example: "Bash(docker compose *)"

If this run is on Codex:
- this denial came from the Codex launcher sandbox/approval mode, not the Claude permission manifest
- re-run with `skip-permissions: true` only if the broader sandbox is acceptable
- otherwise adjust the Codex launcher configuration before retrying
```

**Tracking:** If active, `post-comment(session, "Permission denied: {denied command}. Awaiting user fix.")` and `move-ticket(session, Failed)`.

Stop processing this session. Wait for user action.

### 2b. Escalation (Review Dispute)

If `has_escalation` is `true` (or `preliminary_classification` is `escalation`), this is NOT a failure — it is a review dispute the session could not resolve after 3 rounds. Do NOT decrement retry count.

Read `escalation_detail` from the evidence summary, then arbitrate:

1. Read the reviewer's BLOCKING concerns
2. Read the session agent's counterarguments
3. Cross-reference against the design doc, manifest, and quality standards
4. Make a call:

**If the session agent is right** (reviewer flagged a non-issue, or concern is addressed by existing architecture):

Re-spawn in the same worktree with this directive prepended to the brief:

```
[ESCALATION RESOLVED] The orchestrator reviewed the dispute from your previous attempt.

Verdict: Proceed with your original approach.
Reason: {your reasoning — e.g., "The reviewer's concern about X is addressed by Y in the design doc."}

Resume from the phase AFTER the review gate that triggered escalation — your prior work is in the worktree.
Skip the review gate that triggered escalation — it has been overridden by the orchestrator.
```

**If the reviewer is right** (the session agent missed a real issue):

Re-spawn with directive: `[ESCALATION RESOLVED]` — verdict: implement the reviewer's feedback. List the required changes from the reviewer's BLOCKING issues. Instruct the session to resume from the review gate phase and rework.

**If genuinely ambiguous** (both sides have valid points and you cannot confidently decide):

Ask the user. Present both sides: reviewer's BLOCKING concerns, session's counterarguments, your tentative lean and reasoning. Offer three options: side with reviewer (session reworks), side with session (proceed as-is), or custom resolution.

**Tracking:** If active, `post-comment(session, "Escalation: {verdict and reasoning}")`.

### 2c. Dependency Cascade

If an upstream session failed (any session this one depends on per the manifest's `depends` field), do NOT attempt to run this session.

Mark it as **blocked** and report:

```
S{upstream} failed, which blocks S{this} (and any other dependents: S{list}).
Fixing S{upstream} first.
```

Do not retry blocked sessions. They become unblocked only when their upstream dependency succeeds. After the upstream is fixed and merged, the blocked sessions run in the next iteration of the layer loop.

### 2d. Code/Task Failure

All other failures. Proceed to Step 3 for diagnosis and retry.

---

## Step 3: Diagnose and Retry

**Diagnose.** What went wrong and will retrying with the same brief produce a different result? This is the critical question. If the answer is no, you must change something before retrying.

**Principles:**

1. **Transient failure** (crash, timeout, OOM, network blip — session was making progress): Retry in the same worktree. Resume protocol picks up where it left off.
2. **Session was stuck** (failed verification repeatedly, same error loop): Write a new brief with your diagnosis, the fix you think is needed, and knowledge from other sessions. You have context the session didn't — the design doc, other sessions' knowledge, the manifest's intent. Use it.
3. **Session misunderstood the task** (wrong approach vs design doc): Rewrite brief with clarified requirements. Quote the design doc verbatim if needed.
4. **Task too big** (ran out of context, got lost): Split remaining work into a new session with tighter scope. New sessions get a fresh retry budget.
5. **Cannot tell:** Retry once with error context. If same symptoms repeat, escalate to user.

**Every retry must be meaningfully different from the previous attempt.** If you cannot articulate what you are changing and why, do not retry — escalate instead.

**Retry budget:** Each session gets up to `retries` attempts (from manifest frontmatter, default: 5). The budget is per-session, not global — there is no cap on total retries across the project. If 3 sessions each need 4 retries to get to green, that's 12 retries and that's fine. The budget exists to prevent one session from looping forever, not to limit the project. If the orchestrator splits a session into two new sessions, each gets a fresh budget.

**Retry mechanics:** Reuse the existing worktree (it has partial work). Write a new brief to `/tmp/autoboard-{slug}-s{N}-brief.md` with your diagnosis and adjusted instructions prepended. Spawn via the same shell wrapper:

```bash
"$(cat /tmp/autoboard-session-spawn-script)" /tmp/autoboard-{slug}-s{N}-brief.md \
  --model {model} \
  --effort {effort from sessions table} \
  --cwd /tmp/autoboard-{slug}-s{N} \
  --settings "$PERM_FILE" \
  --standards "docs/autoboard/{slug}/standards.md" \
  --test-baseline "docs/autoboard/{slug}/test-baseline.md" \
  --knowledge "docs/autoboard/{slug}/sessions/layer-{N-1}-knowledge.md" \
  --codesight ".codesight/wiki/index.md" \
  > /tmp/autoboard-{slug}-s{N}-output-retry{M}.jsonl 2>&1
```

If `skip-permissions: true` in manifest, use `--skip-permissions` instead of `--settings`.

**Tracking:** If active, `post-comment(session, "Session failed in {phase}. Diagnosis: {your assessment}. Retrying with adjusted brief.")` and `move-ticket(session, Failed)`.

---

## Step 4: Escalate to User

When retries are exhausted or you have determined that retrying will not help, report to the user with your diagnosis — not just the raw error:

```
S{N} ({focus}) failed.

**Phase:** {where it failed}
**What worked:** {tasks committed before failure, if any}
**What went wrong:** {your diagnosis — not just the error message, but why you think it happened}
**What I tried:** {how you adjusted the brief on retries, and why it didn't help}

The session worktree is preserved at /tmp/autoboard-{slug}-s{N}.

Options:
1. Retry with different instructions — tell me what to change
2. I'll investigate the worktree and diagnose further
3. Skip this session and continue (blocks dependent sessions: {list})
4. Split this session's remaining tasks into a new session
```

**Tracking:** If active, `post-comment(session, "Retries exhausted. Escalated to user.")`.
