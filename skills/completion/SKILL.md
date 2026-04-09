---
name: completion
description: Run full-spectrum coherence audit, final QA gate with full regression, clean up worktrees, report results, and offer PR creation
---

# Completion

All layers are done. Run a full-spectrum coherence audit, final QA gate, clean up, and report results.

**Prerequisites:** All layers have completed -- tasks merged, coherence audits passed, knowledge curated. You have the manifest, design doc, and all prior QA-REPORTs in context.

---

## Step 1: Full-Spectrum Coherence Audit (NON-NEGOTIABLE)

Before the final QA gate, run a full-spectrum coherence audit across ALL 13 quality dimensions -- no file-pattern filtering, no exclusions. This catches compound issues and cross-layer drift that per-layer audits missed. Per-layer audits use filtered dimension subsets -- this is all 13, unfiltered. Different scope, different purpose.

**Do NOT skip this step.** Do NOT substitute with an Explore agent or manual review. Do NOT proceed to the final QA gate without completing this audit. The audit is a prerequisite for the final QA gate -- not optional, not skippable, not replaceable.

Dispatch `/autoboard:coherence-audit` via the Skill tool with the full-spectrum flag -- all quality dimensions, no exclusions.

Use the earliest checkpoint SHA from the run (the commit before Layer 1's merges) to scope the audit to the entire feature's changes.

**Verification:** You must have a `~~~COHERENCE-REPORT` block after this step. If you do not have one, you did not run the audit correctly. Go back and run it.

If BLOCKING issues are found, dispatch `/autoboard:coherence-fixer` -- same retry logic as layer coherence audits (up to 5 rounds, 3 consecutive non-progress cap). The fixer spawns fixer teammates, retries in rounds. All BLOCKING issues must be resolved before proceeding to the final QA gate. If round limit reached, escalate to the user. Do NOT skip the audit and proceed to QA.

If no BLOCKING issues, proceed immediately to Step 2. Do not stop here -- the audit is an intermediate step, not a deliverable.

| Thought that means STOP | Reality |
|---|---|
| "Per-layer audits already caught everything" | Per-layer audits use filtered dimensions. This is all 13, unfiltered -- different scope. Compound cross-layer issues only surface here. |
| "I'll skip the audit since QA will catch issues" | QA tests functionality. Audits catch architecture drift, DRY violations, convention divergence. Different concerns. |
| "This is a small feature, full audit is overkill" | Compound issues scale with layers, not feature size. Every completion gets audited. No exceptions. |
| "I'll go straight to QA to save time" | A skipped audit means cross-layer issues ship. The audit is a prerequisite, not optional. |
| "The final QA gate is the real quality check" | QA verifies behavior. The audit verifies structure. Both are required. One does not substitute for the other. |
| "I already reviewed the merge diffs" | Reviewing diffs is not a structured 13-dimension audit with parallel agents. Invoke the skill. |

---

## Step 2: Final QA Gate

Always run a final QA gate, even if the last layer already had one. Invoke `/autoboard:qa-gate` via the Skill tool with these additions to the QA subagent brief:

- Include the **full design doc** as reference (not just the last layer's criteria)
- Include **all acceptance criteria from all prior QA gates** (cumulative -- full regression, every prior layer's criteria must still pass)
- Include the `expected-skips` list from the manifest
- Add this directive: `"This is the final QA gate before the feature ships. Run full build verification + functional E2E + all acceptance criteria from the design doc + all prior QA gate criteria (full regression). Nothing ships without verification."`

The same PASS/FAIL rules apply. If the final QA fails, invoke `/autoboard:qa-fixer` -- the fixer spawns fixer teammates (up to 5 rounds, 3 consecutive non-progress cap) before escalating to the user.

---

## Step 3: Clean Up Worktrees

Remove worktrees for successfully completed tasks:

```bash
git worktree list
```

For each remaining worktree belonging to this project (`/tmp/autoboard-{slug}-*`):
- If the task was **successfully merged**: remove the worktree and delete the task branch
- If the task **failed**: preserve the worktree and branch for investigation -- NEVER delete failed worktrees

Also clean up coherence-fix and qa-fix worktrees that completed successfully.

---

## Step 4: Report Results

```
All tasks complete!

Tasks: {count} completed, {count} retried, {count} failed
Layers: {count}
QA Gates: {count} passed
Feature branch: {branch}

{Task summary table:}
| Task | Description | Layer | Status |
|------|-------------|-------|--------|
| T1 | ... | 1 | done |
| T2 | ... | 1 | done |
| T3 | ... | 2 | done (retry) |

Feature branch {branch} is ready. Want me to create a PR?
```
