---
name: coherence-audit
description: Run a cross-session coherence audit after merging a layer. Wraps /autoboard:audit with dimension selection and COHERENCE-REPORT processing. Re-invoke at the start of each new layer.
---

# Coherence Audit

Run a coherence audit after every layer's merges. This catches cross-session AND cross-codebase quality issues (DRY violations, orphaned code, convention drift, security gaps) before they compound.

The QA gate and knowledge curation both depend on the COHERENCE-REPORT. No report = no proceeding.

---

## Determine Applicable Dimensions

Scan the layer's diff to decide which conditional dimensions to check:

```bash
git diff $CHECKPOINT..HEAD --stat
```

Use your judgment based on what changed. Glob patterns are guidance, not programmatic filters — when in doubt, include the dimension.

**Always include (every layer):** `code-organization`, `dry-code-reuse`, `error-handling`, `security`, `test-quality`

**Include if layer touched that area:**
- API routes modified (`**/api/**`, `**/routes/**`, `**/handlers/**`) → include `api-design`
- Frontend files modified (`*.tsx`, `*.jsx`, `**/components/**`, `**/pages/**`) → include `frontend-quality`
- Type definitions modified (`**/types/**`, `**/schema/**`, `**/models/**`) → include `type-safety`
- Data models/migrations modified (`**/migrations/**`, `**/schema/**`, `**/prisma/**`, `**/drizzle/**`) → include `data-modeling`
- Server/query code modified (`**/api/**`, `**/routes/**`, `**/queries/**`, `**/db/**`) → include `performance`
- Request handling modified (`**/api/**`, `**/routes/**`, `**/handlers/**`, `**/middleware/**`) → include `observability`
- Config files modified (`**/.env*`, `**/config/**`, `**/settings/**`) → include `config-management`

**Never in checkpoint mode:** `developer-infrastructure` (deferred to completion-only full-spectrum audit)

A 1-session layer still gets all core dimensions. Conditional dimensions are still evaluated based on the diff — not the layer size. Single-session layers can have cross-LAYER drift against code from prior layers.

---

## Run the Audit

Invoke the audit skill in checkpoint mode via the Skill tool:

```
/autoboard:audit --checkpoint $CHECKPOINT --dimensions {selected dimensions}
```

The audit skill spawns parallel dimension agents (one per dimension), each scoped to the layer's diff but cross-referencing the full codebase. It produces a `~~~COHERENCE-REPORT` block.

---

## Process COHERENCE-REPORT

**You are not done.** The COHERENCE-REPORT is an intermediate result, not a deliverable. Act on it immediately — do not stop, do not summarize to the user and wait, do not end your turn.

### No BLOCKING Issues

Proceed to QA gate or knowledge curation. No tracking action needed — coherence issues are not pre-created, so there is nothing to close.

### BLOCKING Issues Found

Route to the coherence-fixer. The run skeleton handles this routing — your job is to signal the result.

Do NOT attempt to fix issues yourself — the fixer needs the full session workflow. Do NOT report the findings to the user and stop — the fixer must be dispatched now.

**Tracking (if active):** Create an on-demand issue for the fixer:

1. Create the issue:
   ```
   create-ticket("Coherence Fix: Layer {N}", COHERENCE-REPORT contents)
   ```
2. Add to the project and set status to Implementing:
   ```
   move-ticket(coherence-issue, Implementing)
   ```
3. Note the issue number and item ID — the coherence-fixer skill needs these for the fixer brief's `## Tracking` section.

**Key design decision:** Coherence audit issues are NOT pre-created during setup. They are created on-demand only when BLOCKING findings trigger a fixer. Most layers pass cleanly — pre-creating issues would just create noise that gets immediately closed.

---

## Anti-Patterns

| Thought that means STOP | Reality |
|---|---|
| "Sessions merged, I'll move on to QA" | The coherence audit must run after merge, before anything else. |
| "This layer is simple, coherence audit isn't needed" | Every layer gets audited. Complexity is not the criterion. |
| "I'll do the coherence audit retroactively" | Retroactive audits don't block. The audit must block before QA. |
| "QA will catch cross-session issues" | QA tests functionality. Coherence catches architecture drift — different concern. |
| "I already checked the merges look clean" | Your eyeball check is not a structured multi-dimension audit. Run the skill. |
| "The audit found issues, let me report them" | Reports are intermediate results, not deliverables. Dispatch the fixer immediately. |
