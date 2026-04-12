---
name: qa-gate
description: Run QA gate validation at a layer boundary. Spawns QA subagent, validates results (fabrication detection, premature criteria, infrastructure allowlist), routes failures to qa-fixer. Re-invoke at the start of each new layer.
---

# QA Gate

Run acceptance testing and regression checks at a layer boundary. The orchestrator spawns a QA helper, then exercises its most critical judgment: validating the QA agent's claims before routing the result.

**Prerequisites:**
- A COHERENCE-REPORT must exist for this layer (from the coherence-audit skill). If you do not have one, STOP and run the coherence audit first. The QA brief requires the COHERENCE-REPORT.
- All sessions in this layer must be merged to the feature branch.

---

## Tracking: Move to Verifying

**First action** before any QA work. Read `docs/autoboard/{slug}/github-tracking.md` to get the QA gate issue number and item ID for this layer.

If tracking is active: `move-ticket(qa-gate, Verifying)`

---

## Pre-QA Environment Sync

Run the manifest's `setup` command now (if configured) to ensure the environment is current with all merged code from this layer. This is intentionally redundant with step 4b in the run skeleton — QA must test against a fresh environment, and the setup command is idempotent.

If the setup command fails, diagnose and fix before spawning the QA agent. A QA gate against a broken environment produces false failures that waste fixer attempts.

---

## Spawn QA Subagent

**QA Prompt Integrity:** The QA helper prompt below is a FIXED TEMPLATE. Fill in the `{placeholder}` fields with data from the manifest, config, and prior steps. Do NOT:
- Add skip instructions beyond what's in the manifest's `expected-skips` list
- Tell the QA agent that features "can't be tested" or "require infrastructure that isn't available"
- Preemptively excuse failures before the QA agent has attempted them
- Modify the prompt's behavioral instructions, rules, or output format

The `expected-skips` placeholder is the ONLY place skip information enters the prompt, and it comes verbatim from the manifest — not from your judgment. If you believe a criterion can't be tested, let the QA agent discover that. Your job is to validate its claims afterward (fabrication detection), not to preempt them.

Spawn a QA helper via your provider's subagent mechanism (NOT an isolated session worker) — this keeps browser screenshots and verbose output out of the orchestrator's context window. Use model `qa-model` from the manifest. The message body should be:

```
You are a QA validator for the autoboard project.

Your FIRST action: invoke /autoboard:verification --full via the Skill tool.

Configuration for the verification skill:
- qa-mode: {qa-mode from frontmatter — 'full' or 'build-only'}
- Verify command: {verify command from frontmatter}
- Dev server: {dev-server command from frontmatter, or 'not configured'}
- Setup: {setup command from frontmatter, or 'skip — no setup command configured'}
- QA setup: {qa-setup command from frontmatter, or 'skip — no qa-setup configured'}
- Auth strategy: {auth-strategy from frontmatter, default: none}
- Test credentials: {test-credentials from frontmatter, or 'none — no auth configured'}
- Auth notes: {auth-notes from frontmatter, or omit if empty}

If test credentials are provided, use them to log in when acceptance criteria
require authenticated access. If login fails, report as criterion FAIL with
the specific error (not infrastructure failure, unless the dev server itself is down).

- Design doc: {path to design doc, e.g. docs/autoboard/{slug}/design.md}
- Test baseline file: {absolute path to docs/autoboard/{slug}/test-baseline.md}
  Read this file with the Read tool. If the file does not exist, there is no baseline.

Acceptance criteria for this QA gate:
{paste the acceptance criteria from the manifest's QA gate marker}

Expected skips (user-acknowledged features that won't be tested):
{paste the expected-skips section from the manifest, or 'none'}

Coherence audit results: {absolute path to docs/autoboard/{slug}/sessions/coherence-L{N}.md}
Read this file for the COHERENCE-REPORT. Any BLOCKING items should already be fixed by the coherence fixer.
If you encounter issues matching unresolved BLOCKING items, escalate as FAIL.

Critical user flows and test scenarios -- you MUST read these files with the Read tool before testing:
- Design doc: {absolute path to design.md} -- read the ## Critical User Flows section
- Manifest: {absolute path to manifest.md} -- read Key test scenarios from browser-marked tasks
These tell you WHAT to test -- not just happy paths but error paths and edge cases.

The verification skill will run build/test commands and, if qa-mode is full,
start the dev server and run browser smoke tests in two phases:
1. Acceptance testing — verify each criterion above via browser interaction.
   For each criterion, test the happy path AND at least one error/edge case
   from the critical user flows and key test scenarios above.
2. Regression testing — use the design doc to test existing features from prior layers

Your FINAL output must end with a fenced block labeled QA-REPORT that the
orchestrator will post verbatim as a GitHub issue comment. Use this structure:

~~~QA-REPORT
## QA Gate: {description}

**Result: {PASS | FAIL}**

### Build & Tests
| Step | Result | Details |
|------|--------|---------|
| Lint | {PASS/FAIL/SKIPPED} | {e.g. eslint exit 0; or 'no linter configured'} |
| Type check | {PASS/FAIL} | {e.g. tsc exit 0, 0 errors} |
| Build | {PASS/FAIL} | {e.g. next build exit 0} |
| Tests | {PASS/FAIL} | {e.g. 309/309 pass} |

### Browser Testing
{Omit this section entirely if qa-mode is build-only}
**Dev server:** {healthy at URL | FAIL — reason}
**Browser tool:** {tool name | FAIL — none detected}

#### Acceptance Criteria
| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | {criterion text} | {PASS/FAIL/EXPECTED SKIP} | {screenshot ref, error msg, or skip reason} |

#### Regression Tests
| Feature | Result | Notes |
|---------|--------|-------|
| {feature} | {PASS/FAIL/EXPECTED SKIP} | {details} |

### Coverage Summary
- **Passed:** {N}
- **Failed:** {N}
- **Expected skips:** {N} (user-acknowledged)
~~~

Rules for the QA-REPORT block:
- A QA gate has exactly TWO outcomes: PASS or FAIL. No third option.
- Every acceptance criterion must appear — never omit criteria
- Valid statuses per criterion: PASS, FAIL, or EXPECTED SKIP
- EXPECTED SKIP is ONLY for criteria matching the expected-skips list — user pre-approved these
- Any criterion that should have been tested but wasn't is FAIL, not SKIPPED
- If qa-mode is full and browser testing can't run (no tool, dev server down), the result is FAIL — this is an infrastructure error
- If qa-mode is build-only, omit the Browser Testing section entirely — acceptance criteria are verified via test output only
- The Coverage Summary counts must be accurate
```

---

## Save and Post QA-REPORT

**Immediately** after receiving the QA subagent's output, extract the `~~~QA-REPORT` block.

Write it to `docs/autoboard/{slug}/sessions/qa-L{N}.md` so fixer briefs can reference it by path.

If tracking is active: `post-comment(qa-gate, "{QA-REPORT contents}")`

If you cannot extract the QA-REPORT block (subagent didn't follow the format), post the subagent's full final output -- never fall back to a generic one-liner.

---

## On QA Pass

Report results to the user and continue to next layer.

If tracking is active: `close-ticket(qa-gate, "{QA-REPORT contents}")`, `move-ticket(qa-gate, Done)`

---

## On QA Fail — Validate and Route

**Do NOT blindly trust the QA agent's failure classification.** Dispatch the validator before routing. QA agents fabricate "infrastructure failure" claims to avoid reporting criterion failures.

### Step 1 — Dispatch QA Validator

Dispatch the QA validator via your provider's subagent mechanism with model `qa-model` and these inputs. On Claude Code, use the `autoboard:qa-validator` agent directly. On Codex, spawn a read-only helper and tell it to read `$(cat /tmp/autoboard-{slug}-plugin-dir)/agents/qa-validator.md` before validating:

- QA-REPORT text (the full `~~~QA-REPORT` block)
- Expected skips (from manifest's `expected-skips` list)
- Prior QA-REPORTs (from earlier runs at this same gate, if any - read from tracking comments or prior output)
- Manifest session list with dependencies and layer assignments
- Current layer number

The agent cross-references reports and manifest to classify each failed criterion. It returns a structured verdict.

### Step 2 — Route Based on Verdict

**PASS:** The validator determined all failures are premature criteria or expected skips. Proceed as if QA passed. Document which criteria were deferred and to which sessions/layers.

**GENUINE_FAIL:** Real code failures. Dispatch fixer immediately via `/autoboard:qa-fixer`. Do NOT ask the user. Do NOT roll back - the fixer needs the merged code. Do NOT report and stop - dispatch now.

If tracking is active: `post-comment(qa-gate, "Dispatching fixer for: {genuine_failures list}")`, `move-ticket(qa-gate, Implementing)`

**FABRICATION:** A prior report contradicts the QA agent's infrastructure claim. Respawn a **new QA agent** with the same QA brief plus this addendum:

> "A prior QA agent falsely claimed infrastructure failure. The orchestrator has verified the browser tool works. Test all acceptance criteria - no infrastructure excuses."

This counts as one fixer attempt (cannot loop forever). Log the override in a tracking comment.

**INCONCLUSIVE_FABRICATION:** The validator cannot determine fabrication from cross-referencing alone (no prior reports at this gate). Verify yourself:

1. Start the dev server
2. Navigate to the app URL with the browser tool
3. If the page loads and renders, the tool works - treat as FABRICATION above
4. If verified broken, treat as genuine infrastructure failure - report to user and **BLOCK**

Kill the dev server after verification before spawning any new QA agent.

**PREMATURE:** All testable criteria passed; failures test later-layer functionality. Pass the gate. Document which criteria were deferred and to which sessions/layers.

**MIXED:** Route each category separately:
- Genuine failures -> dispatch fixer for those criteria only
- Premature criteria -> defer and document
- Fabrication -> log and respawn if needed
- Handle the most severe category first (genuine > fabrication > premature)

---

## Document Your Reasoning

Every QA gate decision must be documented. Post a comment explaining:
- Which criteria you validated and how
- Any fabrication overrides and the evidence
- Any premature criteria deferrals and which sessions they depend on
- Why you passed, failed, or dispatched a fixer

The goal is correct outcomes, not mechanical rule-following.

---

## Anti-Patterns

| Thought that means STOP | Reality |
|---|---|
| "The backend isn't working, I'll tell QA to skip those tests" | Run the setup command first. If a backend was provisioned, it should work. Diagnose, don't skip. |
| "These features require a deployed backend" | Did you run the setup command? Was a backend provisioned during preflight? Check before assuming. |
| "I'll add a note telling QA to expect some failures" | Do NOT inject expectations into the QA prompt. The QA agent tests independently. You validate after. |
| "QA will fail anyway, might as well skip the gate" | Never skip. Run it, get the report, diagnose from evidence. |
