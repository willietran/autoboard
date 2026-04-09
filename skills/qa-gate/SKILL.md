---
name: qa-gate
description: Run QA gate validation at a layer boundary. Dispatches QA subagent, validates results (fabrication detection, premature criteria, infrastructure allowlist), routes failures to qa-fixer. Re-invoke at the start of each new layer.
---

# QA Gate

Run build verification and acceptance testing at a layer boundary. The lead dispatches a QA subagent (Agent tool), then exercises its most critical judgment: validating the QA agent's claims before routing the result.

**Prerequisites:**
- A COHERENCE-REPORT must exist for this layer (from the coherence-audit skill). If you do not have one, STOP and run the coherence audit first. Cohesion runs BEFORE QA - the gate ordering is: code review -> cohesion -> build verification -> functional QA.
- All tasks in this layer must be merged to the feature branch.

---

## Gate Ordering

QA gates are dispatched by the lead after all batches in a layer are merged and reviewed. The ordering ensures all code-changing gates run before verification gates:

| Order | Gate | Scope | When |
|---|---|---|---|
| 1 | Code review | Per batch | After batch merge |
| 2 | Cohesion audit | Per layer | After all batches merged and reviewed |
| 3 | Build verification | Per layer, always | After cohesion fixes complete |
| 4 | Functional QA | Per layer, if manifest defines it | After build verification passes |

Build verification runs every layer regardless. Functional QA runs only when the manifest defines `functional: true` for the layer's QA gate.

---

## Pre-QA Environment Sync

Run the manifest's `setup` command now (if configured) to ensure the environment is current with all merged code from this layer. This is intentionally redundant with the setup step in the run skill - QA must test against a fresh environment, and the setup command is idempotent.

If the setup command fails, diagnose and fix before dispatching the QA subagent. A QA gate against a broken environment produces false failures that waste fixer attempts.

---

## Dispatch QA Subagent

**QA Prompt Integrity:** The Agent prompt below is a FIXED TEMPLATE. Fill in the `{placeholder}` fields with data from the manifest, config, and prior steps. Do NOT:
- Add skip instructions beyond what is in the manifest's `expected-skips` list
- Tell the QA agent that features "can't be tested" or "require infrastructure that isn't available"
- Preemptively excuse failures before the QA agent has attempted them
- Modify the prompt's behavioral instructions, rules, or output format

The `expected-skips` placeholder is the ONLY place skip information enters the prompt, and it comes verbatim from the manifest - not from your judgment. If you believe a criterion cannot be tested, let the QA agent discover that. Your job is to validate its claims afterward (fabrication detection), not to preempt them.

### Build Verification (every layer)

For build-only verification, dispatch a QA subagent via the **Agent tool**:

```
Agent(
  prompt: "You are a QA validator for the autoboard project.

  Your FIRST action: invoke /autoboard:verification-light via the Skill tool.

  Configuration for the verification skill:
  - Verify command: {verify command from config}
  - Setup: {setup command from config, or 'skip - no setup command configured'}

  - Test baseline file: {absolute path to docs/autoboard/{slug}/test-baseline.md}
    Read this file with the Read tool. If the file does not exist, there is no baseline.

  Your FINAL output must end with a fenced block labeled QA-REPORT that the
  lead will use to assess the gate. Use this structure:

  ~~~QA-REPORT
  ## QA Gate: Build Verification - Layer {N}

  **Result: {PASS | FAIL}**

  ### Build & Tests
  | Step | Result | Details |
  |------|--------|---------|
  | Lint | {PASS/FAIL/SKIPPED} | {e.g. eslint exit 0; or 'no linter configured'} |
  | Type check | {PASS/FAIL} | {e.g. tsc exit 0, 0 errors} |
  | Build | {PASS/FAIL} | {e.g. next build exit 0} |
  | Tests | {PASS/FAIL} | {e.g. 309/309 pass} |

  ### Coverage Summary
  - **Passed:** {N}
  - **Failed:** {N}
  ~~~

  Rules for the QA-REPORT block:
  - A QA gate has exactly TWO outcomes: PASS or FAIL. No third option.
  - Every build step must appear - never omit steps
  - The Coverage Summary counts must be accurate",

  model: <qa-model from config>
)
```

### Functional QA (when manifest defines `functional: true` for this layer)

For functional testing, dispatch a QA subagent via the **Agent tool** - this keeps browser screenshots and verbose output out of the lead's context window:

```
Agent(
  prompt: "You are a QA validator for the autoboard project.

  Your FIRST action: invoke /autoboard:verification --full via the Skill tool.

  Configuration for the verification skill:
  - qa-mode: full
  - Verify command: {verify command from config}
  - Dev server: {dev-server command from config, or 'not configured'}
  - Setup: {setup command from config, or 'skip - no setup command configured'}
  - QA setup: {qa-setup command from config, or 'skip - no qa-setup configured'}
  - Auth strategy: {auth-strategy from config, default: none}
  - Test credentials: {test-credentials from config, or 'none - no auth configured'}
  - Auth notes: {auth-notes from config, or omit if empty}

  If test credentials are provided, use them to log in when acceptance criteria
  require authenticated access. If login fails, report as criterion FAIL with
  the specific error (not infrastructure failure, unless the dev server itself is down).

  - Design doc: {path to design doc, e.g. docs/autoboard/{slug}/design.md}
  - Test baseline file: {absolute path to docs/autoboard/{slug}/test-baseline.md}
    Read this file with the Read tool. If the file does not exist, there is no baseline.

  Acceptance criteria for this QA gate:
  {paste the acceptance criteria from the manifest's QA gate marker}

  Expected skips (user-acknowledged features that will not be tested):
  {paste the expected-skips section from the manifest, or 'none'}

  Coherence audit results: {absolute path to docs/autoboard/{slug}/sessions/coherence-L{N}.md}
  Read this file for the COHERENCE-REPORT. Any BLOCKING items should already be fixed by the coherence fixer.
  If you encounter issues matching unresolved BLOCKING items, escalate as FAIL.

  Critical user flows and test scenarios - you MUST read these files with the Read tool before testing:
  - Design doc: {absolute path to design.md} - read the ## Critical User Flows section
  - Manifest: {absolute path to manifest.md} - read Key test scenarios from tasks
  These tell you WHAT to test - not just happy paths but error paths and edge cases.

  The verification skill will run build/test commands and start the dev server
  and run browser smoke tests in two phases:
  1. Acceptance testing - verify each criterion above via browser interaction.
     For each criterion, test the happy path AND at least one error/edge case
     from the critical user flows and key test scenarios above.
  2. Regression testing - use the design doc to test existing features from prior layers

  Your FINAL output must end with a fenced block labeled QA-REPORT that the
  lead will use to assess the gate. Use this structure:

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
  **Dev server:** {healthy at URL | FAIL - reason}
  **Browser tool:** {tool name | FAIL - none detected}

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
  - Every acceptance criterion must appear - never omit criteria
  - Valid statuses per criterion: PASS, FAIL, or EXPECTED SKIP
  - EXPECTED SKIP is ONLY for criteria matching the expected-skips list - user pre-approved these
  - Any criterion that should have been tested but was not is FAIL, not SKIPPED
  - If browser testing cannot run (no tool, dev server down), the result is FAIL - this is an infrastructure error
  - The Coverage Summary counts must be accurate",

  model: <qa-model from config>
)
```

---

## Save QA-REPORT

**Immediately** after receiving the QA subagent's output, extract the `~~~QA-REPORT` block.

Write it to `docs/autoboard/{slug}/sessions/qa-L{N}.md` so fixer briefs can reference it by path.

If you cannot extract the QA-REPORT block (subagent did not follow the format), save the subagent's full final output - never fall back to a generic one-liner.

---

## On QA Pass

Report results to the user and continue to next layer.

---

## On QA Fail - Validate and Route

**Do NOT blindly trust the QA agent's failure classification.** Dispatch the validator before routing. QA agents fabricate "infrastructure failure" claims to avoid reporting criterion failures.

### Step 1 - Dispatch QA Validator

Dispatch the `autoboard:qa-validator` agent via the Agent tool with model `qa-model` and these inputs:

- QA-REPORT text (the full `~~~QA-REPORT` block)
- Expected skips (from manifest's `expected-skips` list)
- Prior QA-REPORTs (from earlier runs at this same gate, if any - read from prior output)
- Manifest task list with dependencies and layer assignments
- Current layer number

The agent cross-references reports and manifest to classify each failed criterion. It returns a structured verdict.

### Step 2 - Route Based on Verdict

**PASS:** The validator determined all failures are premature criteria or expected skips. Proceed as if QA passed. Document which criteria were deferred and to which tasks/layers.

**GENUINE_FAIL:** Real code failures. Dispatch fixer immediately via `/autoboard:qa-fixer`. Do NOT ask the user. Do NOT roll back - the fixer needs the merged code. Do NOT report and stop - dispatch now.

**FABRICATION:** A prior report contradicts the QA agent's infrastructure claim. Respawn a **new QA agent** with the same QA brief plus this addendum:

> "A prior QA agent falsely claimed infrastructure failure. The lead has verified the browser tool works. Test all acceptance criteria - no infrastructure excuses."

This counts as one fixer attempt (cannot loop forever). Log the override.

**INCONCLUSIVE_FABRICATION:** The validator cannot determine fabrication from cross-referencing alone (no prior reports at this gate). Verify yourself:

1. Start the dev server
2. Navigate to the app URL with the browser tool
3. If the page loads and renders, the tool works - treat as FABRICATION above
4. If verified broken, treat as genuine infrastructure failure - report to user and **BLOCK**

Kill the dev server after verification before dispatching any new QA agent.

**PREMATURE:** All testable criteria passed; failures test later-layer functionality. Pass the gate. Document which criteria were deferred and to which tasks/layers.

**MIXED:** Route each category separately:
- Genuine failures -> dispatch fixer for those criteria only
- Premature criteria -> defer and document
- Fabrication -> log and respawn if needed
- Handle the most severe category first (genuine > fabrication > premature)

---

## Document Your Reasoning

Every QA gate decision must be documented. Record:
- Which criteria you validated and how
- Any fabrication overrides and the evidence
- Any premature criteria deferrals and which tasks they depend on
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
