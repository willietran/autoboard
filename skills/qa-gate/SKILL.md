---
name: qa-gate
description: Run QA gate validation at a layer boundary. Spawns QA subagent, validates results (fabrication detection, premature criteria, infrastructure allowlist), routes failures to qa-fixer. Re-invoke at the start of each new layer.
---

# QA Gate

Run acceptance testing and regression checks at a layer boundary. The orchestrator spawns a QA subagent (Agent tool), then exercises its most critical judgment: validating the QA agent's claims before routing the result.

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

**QA Prompt Integrity:** The Agent prompt below is a FIXED TEMPLATE. Fill in the `{placeholder}` fields with data from the manifest, config, and prior steps. Do NOT:
- Add skip instructions beyond what's in the manifest's `expected-skips` list
- Tell the QA agent that features "can't be tested" or "require infrastructure that isn't available"
- Preemptively excuse failures before the QA agent has attempted them
- Modify the prompt's behavioral instructions, rules, or output format

The `expected-skips` placeholder is the ONLY place skip information enters the prompt, and it comes verbatim from the manifest — not from your judgment. If you believe a criterion can't be tested, let the QA agent discover that. Your job is to validate its claims afterward (fabrication detection), not to preempt them.

Spawn a QA subagent via the **Agent tool** (NOT a CLI subprocess) — this keeps browser screenshots and verbose output out of the orchestrator's context window:

```
Agent(
  prompt: "You are a QA validator for the autoboard project.

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
  - Test baseline:
    {Read docs/autoboard/{slug}/test-baseline.md and paste its COMPLETE content here verbatim.
    Do NOT replace with a file path reference.
    If the file does not exist or no baseline was captured, write 'no baseline captured'.}

  Acceptance criteria for this QA gate:
  {paste the acceptance criteria from the manifest's QA gate marker}

  Expected skips (user-acknowledged features that won't be tested):
  {paste the expected-skips section from the manifest, or 'none'}

  Coherence audit results (from the layer coherence audit):
  {paste the COHERENCE-REPORT block from the layer coherence audit.
  Any BLOCKING items listed should already be fixed by the coherence fixer.
  If you encounter issues that match unresolved BLOCKING items from this report, escalate as FAIL.}

  Critical user flows (from design doc):
  {Read the design doc's ## Critical User Flows section and paste it here verbatim.
  If the section does not exist, omit this block.
  These are end-to-end flows you MUST test, including error paths.}

  Key test scenarios for browser testing:
  {Extract Key test scenarios from all manifest tasks marked Test approach: browser.
  For each, include the task title and its scenarios.
  If no tasks are marked browser, omit this block.
  These scenarios tell you WHAT to test — not just happy paths but error paths and edge cases.}

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
  - The Coverage Summary counts must be accurate",

  model: <qa-model from frontmatter>
)
```

---

## Post QA-REPORT as Comment

**Immediately** after receiving the QA subagent's output, extract the `~~~QA-REPORT` block and post it.

If tracking is active: `post-comment(qa-gate, "{QA-REPORT contents}")`

If you cannot extract the QA-REPORT block (subagent didn't follow the format), post the subagent's full final output — never fall back to a generic one-liner.

---

## On QA Pass

Report results to the user and continue to next layer.

If tracking is active: `close-ticket(qa-gate, "{QA-REPORT contents}")`, `move-ticket(qa-gate, Done)`

---

## On QA Fail — Validation Pipeline

**Do NOT blindly trust the QA agent's failure classification.** The orchestrator must validate every failure claim before routing. QA agents have been known to fabricate "infrastructure failure" claims to avoid reporting criterion failures.

### Step 1 — Parse the QA-REPORT

Extract which criteria failed and the reason given for each failure.

### Step 2 — Apply the Infrastructure Failure Allowlist

**ONLY** these qualify as genuine infrastructure failures:
- Browser tool not detected (no Playwright MCP in available tools, `which agent-browser` returns non-zero)
- Dev server process exited or never responded to health checks
- Missing env vars that prevent the app from starting at all

Any other claimed infrastructure reason is suspect and requires verification.

### Step 3 — Fabrication Detection

If the claimed failure reason is NOT on the allowlist, verify it yourself. Do not trust the QA agent's classification.

**Browser tool claims** (e.g., "can't handle React", "incompatible with framework X", "unable to trigger events"):
- Start the dev server yourself
- Navigate to the app URL with the browser tool
- If the page loads and renders, the tool works — the claim is fabricated

**Cross-reference prior runs:** If a prior QA-REPORT at the same gate shows browser testing worked (pages navigated, forms submitted, criteria tested), that's additional evidence the claim is fabricated. No need to re-verify yourself in this case.

### Step 4 — Route Based on Verified Result

**Verified fabrication** — the orchestrator confirmed the tool works (or prior run proves it):

Log the override in a tracking comment: "Orchestrator verified browser tool is functional — QA agent's infrastructure claim was fabricated. Retasking."

Respawn a **new QA agent** with the same QA brief plus this addendum:
> "A prior QA agent falsely claimed infrastructure failure. The orchestrator has verified the browser tool works. Test all acceptance criteria — no infrastructure excuses."

This counts as one of the 5 fixer attempts (cannot loop forever). Kill the dev server you started for verification before spawning.

**Genuine infrastructure failure** (on the allowlist, or orchestrator's own verification confirmed it):

This is NOT a code issue. No fixer can help. Report the failure to the user with the exact missing prerequisite and how to fix it. The run is **BLOCKED** at this gate until the user resolves the infrastructure issue. No sessions after this gate will execute.

If tracking is active: `post-comment(qa-gate, "{failure details}")`, `move-ticket(qa-gate, Failed)`

### Step 5 — Premature Criteria Assessment

**Before dispatching a fixer, assess whether the failures are real.** You have the manifest, the session/layer structure, and the QA results. Use your judgment:

- Do the failed criteria test functionality from sessions that haven't run yet? If criteria test UI pages from sessions in later layers, those aren't code failures — the manifest criteria were premature.
- Defer premature criteria to the next gate after the relevant sessions complete. Log what you deferred and why.
- If ALL testable criteria passed and the failures are all premature criteria, **pass the gate**. Document your reasoning.
- If some failures are genuine code issues, dispatch a fixer for those only.

### Step 6 — Route Genuine Code Failures

**Acceptance criteria failure or regression** (genuine code failure after your assessment):

Auto-dispatch a fixer agent immediately via the qa-fixer skill. Do NOT roll back — the fixer needs the merged code. Do NOT ask the user for permission — just fix it. Do NOT report the failures and stop — dispatch the fixer now.

If tracking is active: `post-comment(qa-gate, "Dispatching fixer agent for the failures above.")`, `move-ticket(qa-gate, Implementing)`

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
