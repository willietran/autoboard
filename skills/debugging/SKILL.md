---
name: debugging
description: Systematic root cause investigation before attempting fixes. Enforces reproduce-first, trace-backward, single-hypothesis discipline. Adapted from Obra Superpowers (MIT License).
---

<!-- Adapted from Obra:Superpowers systematic-debugging skill (MIT License) -->
<!-- https://github.com/obra/superpowers -->

# Systematic Debugging

You have a bug to fix. Before you touch any code, you will investigate systematically. No guessing. No "I think I know what's wrong." No patching symptoms.

**The rule:** No fix without root cause investigation first. This is NON-NEGOTIABLE.

---

## Phase 1: Reproduce the Failure (NON-NEGOTIABLE)

Before investigating, reproduce the exact failure. If you cannot reproduce it, you cannot fix it.

- **If the failure was in browser** (QA acceptance criterion): start the dev server, open the browser tool, and reproduce the exact failing interaction step by step.
- **If the failure was in tests**: run the specific failing test and confirm it fails with the same error.
- **If the failure was in build/type-check**: run the build command and confirm the same error.

**Document the reproduction:** Write down the exact steps, the exact error message, and the exact location. This is your baseline — after fixing, you will repeat these exact steps to confirm the fix.

**Verification:** You must have a documented reproduction before proceeding to Phase 2. If you cannot reproduce the failure after 3 attempts, escalate — the issue may be environmental or intermittent, which requires a different approach.

| Thought that means STOP | Reality |
|---|---|
| "I can see the bug in the code, no need to reproduce" | You're guessing. Reproduce it. The bug you see might not be the bug that failed. |
| "The QA report already describes the failure" | The QA report describes symptoms. You need to observe the failure yourself to trace it. |
| "Reproduction will take too long" | Skipping reproduction wastes MORE time — you'll fix the wrong thing and cycle back. |
| "I'll reproduce after I fix it to verify" | You need the baseline BEFORE fixing. Otherwise you can't confirm the fix changed anything. |

---

## Phase 2: Root Cause Investigation (NON-NEGOTIABLE)

Trace backward from the symptom to the root cause. Do NOT trace forward from a guess.

### The Five-Step Trace

1. **Observe the symptom** — Document the exact error, its location, and what the code was trying to do.

2. **Find the immediate cause** — What code directly produces the error? Read it. Understand what values it received and why they're wrong.

3. **Ask "what called this?"** — Map the call chain backward. What function passed the wrong value? What called that function?

4. **Keep tracing** — Continue asking "what called this?" while examining values passed between functions. At each step, verify your understanding by reading the actual code — do not assume.

5. **Find the original trigger** — The root cause is often far from the symptom: initialization code, configuration, data transformation, or test setup. Not the function that threw the error.

### Instrumentation

When the call chain is unclear, add temporary instrumentation:

- `console.error()` or equivalent at component boundaries with context (variable values, paths, stack traces)
- Check input/output at each layer of the call chain
- Remove all instrumentation before committing

### Cross-Component Tracing

For bugs that cross component boundaries (frontend ↔ API ↔ database):

- Instrument EACH boundary independently
- Verify data shape at each crossing point
- The bug is often at a boundary where assumptions diverge

**Verification:** You must have a specific root cause identified — not "something is wrong with X" but "function Y on line Z receives null because function W on line V doesn't handle the empty-array case from query Q." If you can't state the root cause at this specificity, keep tracing.

| Thought that means STOP | Reality |
|---|---|
| "I think I know what's wrong" | "Think" is not evidence. Trace to the root cause. State it specifically. |
| "It's probably this function" | "Probably" means you haven't verified. Read the code. Check the values. |
| "The error message tells me what to fix" | Error messages describe symptoms, not causes. The fix location is often elsewhere. |
| "I'll investigate more after I try a quick fix" | Quick fixes that miss the root cause waste time and create technical debt. Investigate first. |

---

## Phase 3: Hypothesis Testing

Form ONE specific hypothesis about the root cause. Test it with a minimal, targeted change.

1. **State the hypothesis clearly:** "The root cause is [specific thing] because [evidence from Phase 2]."
2. **Design a minimal test:** What is the smallest change that would confirm or refute this hypothesis?
3. **Make the change and test:** Run the reproduction steps from Phase 1. Did the failure change?
4. **Evaluate:**
   - Hypothesis confirmed → proceed to Phase 4
   - Hypothesis refuted → form a NEW hypothesis based on what you learned. Return to step 1.

**Rules:**
- ONE change at a time. Never attempt multiple simultaneous changes — you can't isolate which one had an effect.
- Each hypothesis must be based on evidence, not intuition. Reference specific code, values, or behaviors observed in Phase 2.
- **After 3 failed hypotheses:** Stop. The problem is likely architectural, not a simple bug. Step back and reconsider the approach — the code may need a structural change, not a patch.

| Thought that means STOP | Reality |
|---|---|
| "I'll try a few things and see what sticks" | This is random debugging. Form a hypothesis first. |
| "Let me change A, B, and C together" | One change at a time. You can't learn from multiple simultaneous changes. |
| "My third hypothesis failed but I have another idea" | Three failed hypotheses = architectural issue. Reconsider the structure before patching more. |

---

## Phase 4: Targeted Fix

Root cause confirmed. Now fix it properly.

1. **Write a failing test first** — Create a test that reproduces the root cause. Run it. Confirm it fails. This is your regression guard.

2. **Implement a single, targeted fix** — Address the root cause directly. The fix should be:
   - **Minimal** — change only what's necessary
   - **Clean** — indistinguishable from code written correctly the first time
   - **Durable** — fixes the category of bug, not just this instance

3. **Verify against original failure** — Re-run the EXACT reproduction steps from Phase 1:
   - The specific failing test/criterion must now PASS
   - All existing tests must still PASS
   - If the failure was in browser, verify in browser — build+test alone is NOT sufficient

4. **Remove instrumentation** — Delete any temporary `console.error()` or debug logging added during investigation.

**The fix is not done until the original failing criterion passes in the same mode it failed.** Build+test verification is necessary but not sufficient when the failure was a browser acceptance criterion.

| Thought that means STOP | Reality |
|---|---|
| "Tests pass, so the fix works" | If the original failure was in browser, you must also verify in browser. Tests and browser test different things. |
| "I fixed it, time to commit" | Did you re-run the exact reproduction steps from Phase 1? If not, you haven't verified. |
| "The fix is too big, I'll do a quick workaround" | If the root cause requires a refactor, do the refactor. Workarounds create debt that future sessions inherit. |

---

## Summary: The Debugging Loop

```
REPRODUCE → TRACE → HYPOTHESIZE → TEST → FIX → VERIFY
     ↑                    ↑                        |
     |                    └── hypothesis refuted ───┘
     |
     └── verification failed (fix didn't work) ────┘
```

Every exit from this loop requires evidence: reproduction evidence, trace evidence, hypothesis evidence, and verification evidence. "I think it's fixed" is never acceptable — "the criterion that failed now passes when I repeat the exact reproduction steps" is the only acceptable exit.
