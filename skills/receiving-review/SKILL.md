---
name: receiving-review
description: Critical thinking protocol for processing review feedback — invoke when receiving plan review, code review, or audit feedback, before responding to reviewer suggestions.
---

<!-- Adapted from Obra:Superpowers receiving-code-review, MIT License -->

# Receiving Review Feedback

**Default: fix everything.** The only valid escape is proven harm.

AI agents can fix a DRY violation in 30 seconds, export an interface in 10, add a test in 2 minutes. The cost of completeness is near-zero. The cost of leaving issues is compounding — every unfixed finding is a pattern the next task copies, a convention it drifts from, a shortcut it repeats. Do not evaluate whether feedback is "worth fixing." Evaluate whether fixing it would cause harm.

## The Process

### 1. READ
Read the full review before responding to any single item. Understand the reviewer's overall perspective and priorities.

### 2. UNDERSTAND
For each item, make sure you understand what the reviewer is actually asking for. If unclear, ask a clarifying question before acting.

### 3. VERIFY and DECIDE

For each finding, run the decision tree:

```
  VERIFY: Is the finding factually accurate?
    → NO → PUSH BACK with evidence (cite actual code)
    → YES or UNCERTAIN → continue

  HARM CHECK: Would the fix cause demonstrable harm?
    a. Break existing functionality? → PUSH BACK (cite what breaks)
    b. Conflict with a documented design decision? → PUSH BACK (cite the doc + passage)
    c. Destabilize code outside this task's scope? → PUSH BACK (cite the risk)
    d. Duplicate work explicitly assigned to another task in manifest? → DEFER (cite task ID)
    → None of the above → FIX IT
```

No severity evaluation. No "is this worth my time." If you can't point to concrete harm, you fix.

### 4. IMPLEMENT
Fix accepted items one at a time. Verify after each change. Do not batch multiple fixes without verifying each one individually.

## Exhaustive Pushback Criteria

If it's not on this list, it's not a valid pushback:

1. **Factually wrong** — The code doesn't do what the reviewer claims. Cite the actual code that disproves the finding.
2. **Fix breaks something** — The fix would cause a test failure, runtime error, or regression. Identify what breaks.
3. **Conflicts with design doc** — A documented architectural decision (design doc, CLAUDE.md — not assumed) explicitly chose this approach. Cite the document and passage.
4. **Destabilizes other tasks** — The fix requires changing files that other in-flight tasks depend on, risking merge conflicts or broken assumptions. Cite which tasks and why.
5. **Assigned elsewhere** — Another task in the manifest is explicitly tasked with this exact area. Cite the task ID and task.

## Forbidden Dismissals

These rationalizations are never valid:

- "Low risk" / "low impact" — Not a harm argument. Fix it.
- "Technically works" / "not build-breaking" — Not a harm argument. Fix it.
- "Out of scope for my task" — Codebase quality is always in scope. Fix it.
- "Pre-existing issue" — If you're touching this area, improve it. Fix it.
- "Won't change during this project" — You don't know that. Fix it.
- "Thin wrapper / pure constants" — Not exempt from quality standards. Fix it.
- "Cosmetic / style preference" — Code organization affects agent navigability. Fix it.
- "Future tasks will handle this" — Unless assigned in the manifest, wishful thinking. Fix it.
- "This is theoretical / no practical risk" — Agent navigability IS practical. Fix it.

## Legitimate Context the Reviewer May Lack

Reviewers (plan reviewers, code reviewers, audit agents) don't see everything. Session agents have valid pushback when the reviewer doesn't know about:

- Design doc decisions and their rationale
- Cross-task dependencies in the manifest
- Architectural constraints from the brainstorm/planning phase
- Future task assignments that cover this area

This context powers pushback through the proven-harm criteria above. Frame it as "this fix would cause harm because..." — not "this isn't worth fixing because..."

## Forbidden Responses

- "You're absolutely right!" — Do not perform enthusiasm. Just state your assessment.
- "Great catch!" — Same. Evaluate, don't flatter.
- Blanket agreement without verification — Never accept feedback without checking it against the code first.
- Implementing all suggestions in one batch without individual testing.
