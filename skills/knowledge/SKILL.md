---
name: knowledge
description: Curate cross-session knowledge between layers — deduplicate, filter by relevance, resolve conflicts, and brief next-layer sessions
---

# Curate Knowledge for Next Layer

Synthesize what this layer built and brief the next layer with what they need to know. Do NOT pass session status files through verbatim — you are the engineering lead, curate what your reports need to know.

**Prerequisites:** All merges and the coherence audit for this layer have completed. You must have run the coherence audit. If the audit found no issues, that is fine — proceed with knowledge curation using session status files. If the audit found issues, incorporate them into the knowledge brief (what was fixed, what patterns to avoid).

---

## Step 1: Gather Raw Knowledge

1. Read the `## Knowledge` section from EACH completed session's status file in this layer:
   - Path: `docs/autoboard/{slug}/sessions/s{N}-status.md`
   - Extract only the Knowledge section — ignore other status fields
2. Read the curated knowledge from the previous layer (if any):
   - Path: `docs/autoboard/{slug}/sessions/layer-{N-1}-knowledge.md`
   - If this is Layer 0 (first layer), there is no prior knowledge — skip this step

---

## Step 2: Synthesize

Apply these transformations to produce a curated brief:

### Deduplication

If multiple sessions discovered the same pattern, utility, or convention, mention it once with the canonical location. Do not repeat the same discovery from each session's perspective.

### Relevance Filtering

For each next-layer session, check which prior sessions it depends on (from the manifest's `depends` field). Prioritize knowledge from direct dependencies. Include knowledge from non-dependencies only if it is broadly relevant (shared utilities, project-wide conventions, new test patterns).

### Cross-Session Conflict Detection

If sessions established conflicting patterns (different error handling, naming conventions, file organization), flag the conflict and declare which pattern the next layer should follow:

```
**Convention conflict detected:**
- S1 used `ConvexError` for API errors (`convex/tasks.ts:45`)
- S2 used raw `throw new Error()` (`convex/users.ts:23`)
- **Resolution:** Use S1's pattern (`ConvexError` with reason string). S2's approach will be corrected by the coherence fixer.
```

Do not leave conflicts unresolved — pick the better pattern and state it clearly.

### Test Quality Patterns

If the layer's coherence audit flagged test quality issues (or the fixer resolved them), capture what was learned:

```
**Test quality patterns established:**
- {What test patterns were established — e.g., "All API handler tests include error path tests for 400 and 500 responses"}
- {What anti-patterns were caught and fixed — e.g., "Happy-path-only tests for form validation were flagged; error path tests added for empty fields, invalid email, duplicate entries"}
- {TDD discipline notes — e.g., "Browser test scenarios from the manifest must be covered in handler-level tests, not just asserted via browser"}
```

Even if no test quality issues were flagged, note any test patterns that sessions established that the next layer should follow. Consistency in test style prevents future coherence issues.

### Orchestrator-Added Context

Add brief notes connecting the dots between sessions when it helps the next layer understand how pieces fit together:

```
S1 created `lib/auth.ts` with `authenticatedQuery()` and `authenticatedMutation()`.
S4 MUST use these for all protected routes — do not create a separate auth wrapper.
```

---

## Step 3: Write Curated Knowledge

Write the synthesized knowledge to:

```
docs/autoboard/{slug}/sessions/layer-{N}-knowledge.md
```

This file is what the session-spawn skill pastes into next-layer session briefs under `## Knowledge from Prior Sessions`.

---

## Step 4: Record Architectural Decisions

If any sessions noted architectural decisions in their status files, append them to the decisions log:

```
docs/autoboard/{slug}/decisions.md
```

Format:
```markdown
## Layer {N} Complete ({ISO date})
- {decision from session status}
```

---

## What This Enables

The session-spawn skill reads `layer-{N}-knowledge.md` and pastes it into each next-layer session's brief. This means next-layer sessions start with:
- Awareness of what was built (without reading all prior code)
- Clear conventions to follow (no conflicting patterns)
- Knowledge of shared utilities they should use (no reinvention)
