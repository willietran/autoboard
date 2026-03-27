---
name: receiving-review
description: Critical thinking protocol for processing review feedback — invoke when receiving plan review, code review, or audit feedback, before responding to reviewer suggestions.
---

<!-- Adapted from Obra:Superpowers receiving-code-review, MIT License -->

# Receiving Review Feedback

When you receive review feedback, process it methodically. Do not rush to agree. Do not perform agreement. Think critically about every item.

## The Pattern: READ -> UNDERSTAND -> VERIFY -> EVALUATE -> RESPOND -> IMPLEMENT

### 1. READ
Read the full review before responding to any single item. Understand the reviewer's overall perspective and priorities.

### 2. UNDERSTAND
For each item, make sure you understand what the reviewer is actually asking for. If unclear, ask a clarifying question before acting.

### 3. VERIFY
Check the reviewer's claims against the actual code. Reviewers make mistakes too -- wrong line numbers, outdated context, misread logic. Verify before accepting.

### 4. EVALUATE
For each item, decide independently:
- Is the feedback correct and actionable?
- Is it based on accurate understanding of the code?
- Does the suggested fix introduce new problems?
- Is the severity (BLOCKING vs NIT) appropriate?

### 5. RESPOND
- If you agree: state briefly why and move to implement.
- If you disagree: push back with specific technical reasoning. Reference the code, the spec, or the constraint that makes the suggestion wrong or inapplicable.

### 6. IMPLEMENT
Implement accepted changes one item at a time. Test after each change. Do not batch multiple fixes without verifying each one individually.

## Forbidden Responses

- "You're absolutely right!" -- Do not perform enthusiasm. Just state your assessment.
- "Great catch!" -- Same. Evaluate, don't flatter.
- Blanket agreement without verification -- Never accept feedback without checking it against the code first.
- Implementing all suggestions in one batch without individual testing.
- "This is pre-existing, downgrade to INFO" -- without proving the pre-existing issue isn't agent-degrading or amplified by new code copying the pattern.

## When to Push Back

- The reviewer misread the code or missed relevant context.
- The suggested fix would break something else.
- The concern is theoretical with no practical risk in this context.
- The feedback conflicts with project conventions or constraints.
- The fix is out of scope for the current task.

**Scope caveat:** "Out of scope" and "pre-existing" apply to session-scoped reviews (code review, plan review). They do NOT apply to codebase-scoped reviews (coherence audits, full audits). See the next section.

State your reasoning clearly and concisely. Cite specific lines, tests, or constraints. Let the technical argument stand on its own.

## Audit and Coherence Feedback — Different Rules

Coherence audits and full audits evaluate **codebase health**, not session blame. They ask "does this degrade the codebase?" — not "who introduced this?" This changes how you evaluate their findings.

### "Pre-existing" is not a dismissal

When an audit flags a DRY violation, convention drift, or competing implementation, the question is NOT "was this here before my session?" The question is: **will this confuse or mislead the next AI session that touches this code?**

If new code copies or amplifies a pre-existing bad pattern, the finding stands. The audit caught it because new code made it worse — more files with the same duplication, more places future sessions will copy from. "The architect deferred it" or "the existing code does this too" is not a defense when the audit's blocking threshold says agent-degrading issues are BLOCKING.

To downgrade a pre-existing finding, you must demonstrate one of:
- The pattern is NOT agent-degrading — future sessions won't be confused by it
- The finding is factually wrong — the code doesn't actually duplicate what the audit claims
- The "duplication" serves a genuine technical purpose (e.g., intentionally different implementations behind a similar interface)

### Agent-degrading stays BLOCKING

These categories are BLOCKING regardless of when they were introduced:
- **DRY violations** — duplicated logic, constants, or patterns across files
- **Convention drift** — new code following a different pattern than established code
- **Competing implementations** — multiple utilities/helpers doing the same thing
- **Unclear module boundaries** — same responsibility split across unrelated files

The test: "If a new AI session reads this code, will it know which pattern to follow?" If the answer is no, it's BLOCKING.

### What you CAN still push back on

Audit findings are not infallible. Push back when:
- The finding is factually incorrect (the code doesn't do what the audit claims)
- The "duplication" is superficial — similar syntax but genuinely different logic
- The fix would require changes outside the layer's scope that risk destabilizing unrelated code
- A defense-in-depth suggestion is presented as a security gap, but the existing protection chain is documented and sound
