# Autoboard v2: Agent Teams Rewrite

## Overview

Autoboard v2 is a Claude Code plugin that provides an engineering methodology layer on top of Agent Teams. It transforms a feature request into a dependency-aware task graph, then orchestrates a team of coding agents with mandatory quality gates -- centralized planning, code review, QA verification, and cross-task cohesion audits.

Autoboard v2 replaces the `claude -p` subprocess architecture with Claude Code's native Agent Teams. The "session" abstraction is eliminated entirely -- each task gets one teammate. The lead agent becomes a thin coordinator that delegates all heavy work to subagents and teammates.

### What Autoboard adds over vanilla Agent Teams

1. **Structured decomposition** -- brainstorm + task manifest turns a feature into a reviewed task graph with dependencies, complexity scores, and quality criteria
2. **Centralized planning with review** -- one planning subagent explores the codebase and plans all tasks in a batch; a plan-reviewer validates before any code is written
3. **Quality gates between dependency layers** -- code review, cohesion audits, build verification, and functional QA after each layer, with automated fixer dispatch on failure
4. **Standards enforcement** -- project-specific quality dimensions injected into teammate context, plus TaskCompleted hooks for automated lint/type-check
5. **Persistent knowledge** -- curated discoveries written to disk between layers so context survives across the run
6. **Fabrication detection** -- QA validation that catches agents claiming "infrastructure failure" to avoid reporting real failures

### What Agent Teams handles (Autoboard does not)

- Process lifecycle management (no PID files, reapers, orphaned processes)
- Inter-agent communication (teammates message each other directly)
- Task list management (shared task list with dependency tracking)
- Display and visibility (split panes or in-process mode)
- Teammate spawning and shutdown

## Architecture

### Roles

| Role | What it does | Model |
|---|---|---|
| **Lead** | Coordinate, merge, route decisions, dispatch subagents | Opus |
| **Planning subagent** | Explore codebase (codesight), write implementation plans for a batch of tasks | Opus |
| **Plan reviewer subagent** | Validate plan against manifest, standards, codebase patterns | Sonnet |
| **Teammate** | Implement one task from a reviewed plan, verify, commit | Sonnet (default) or Opus (complexity 5+) |
| **Code reviewer subagent** | Review merged diff for a batch against the plan and standards | Sonnet |
| **QA subagent** | Run build verification and functional E2E testing on the integrated layer | Sonnet |
| **Cohesion audit subagent** | Check cross-task consistency (DRY, conventions, architecture) after layer merge | Sonnet |
| **Knowledge curator subagent** | Read teammate knowledge files, write persistent knowledge for next layer | Sonnet |
| **Fixer teammate** | Fix QA, cohesion, or code review failures (full implement + verify cycle) | Sonnet or Opus based on failure complexity |

### Lead context budget

The lead is a thin coordinator. It never holds diffs, file contents, build output, test output, or plans in its context. It holds:

- Manifest + task dependency graph
- Task completion status (from shared task list)
- Subagent verdicts (APPROVE / REQUEST CHANGES / PASS / FAIL)
- Merge results (success / conflict)
- High-level progress (layer N of M complete)

All heavy reading happens in subagent and teammate context windows.

### Dependency layers

Layers are computed at runtime from the task dependency graph:

- Layer 1: all tasks with `depends-on: none`
- Layer 2: all tasks whose dependencies are all in Layer 1
- Layer 3: all tasks whose dependencies are all in Layers 1-2
- etc.

Layers are not declared in the manifest. The lead computes them from the `depends-on` field.

### Batch sizing

When a dependency layer exceeds `max-batch-size` (default: 5), it is split into batches. Each batch gets its own planning and code review cycle. All tasks within a layer still implement in parallel -- batching only affects planning and review scope.

For a layer with 8 tasks and max-batch-size 5:
1. Two planning subagents plan tasks 1-4 and tasks 5-8 in parallel
2. Eight teammates implement in parallel
3. Merge tasks 1-4, dispatch code reviewer on that batch's diff
4. Merge tasks 5-8, dispatch code reviewer on that batch's diff
5. Cohesion audit on the full layer
6. QA on the full layer

### Worktree strategy

- Lead creates worktrees before spawning teammates
- One worktree per task: `/tmp/autoboard-{slug}-t{N}`
- On successful merge: worktree cleaned up
- On failure: worktree preserved for fixer teammates

## Manifest Format

### Task definition

```markdown
### T1: Create user schema and types
- creates: src/lib/schemas/user.ts, src/lib/types/user.ts
- modifies: src/lib/schemas/index.ts
- depends-on: none
- requirements: Define User, UserRole, UserPreferences types with Zod schemas. Export from barrel file.
- key-test-scenarios: validation rejects invalid email, role enum enforced, preferences optional with defaults
- complexity: 2
- commit-message: Add user schema and types
```

**Fields per task:**

| Field | Required | Purpose |
|---|---|---|
| title | Yes | What the task accomplishes |
| creates | No | Files this task creates |
| modifies | No | Files this task modifies |
| depends-on | Yes | Task IDs that must complete first, or `none` |
| requirements | Yes | What to build |
| key-test-scenarios | Yes | What to test (drives plan quality and code review) |
| complexity | Yes | Fibonacci scale: 1, 2, 3, 5, 8 |
| commit-message | Yes | Exact commit message for the task |
| model | No | Override default model for this task |

### Complexity scale

Complexity measures cognitive difficulty, not volume of work.

| Score | Name | Model | Effort | Anchor |
|---|---|---|---|---|
| 1 | Rote | Sonnet | n/a | Copy-paste-modify, zero novel decisions |
| 2 | Guided | Sonnet | n/a | Known pattern, one or two novel decisions |
| 3 | Considered | Sonnet | n/a | Multiple concerns, well-documented problem space |
| 5 | Tricky | Opus | high | Non-obvious failure modes, multiple interacting states |
| 8 | Novel | Opus | max | Inventing an approach, no established pattern |

Baseline anchoring: every manifest identifies one task as the baseline (complexity 2). All other tasks scored relative to it.

Distribution check: if more than 40% of tasks score 5 or 8, re-examine against the baseline.

### Config section

```markdown
## Config
feature: user-auth
branch: autoboard/user-auth
verify-command: npm run lint && npm run typecheck && npm run build && npm run test
setup-command: npm install
dev-server: npm run dev

default-teammate-model: sonnet
opus-threshold: 5
opus-effort-map:
  5: high
  8: max

max-batch-size: 5
qa-mode: build  # or "full" for browser testing

planning-model: opus
plan-review-model: sonnet
code-review-model: sonnet
qa-model: sonnet
cohesion-model: sonnet
```

### QA Gates section

```markdown
## QA Gates

### After Layer 1
- All schemas validate with test data
- Build passes with zero type errors

### After Layer 2
- functional: true
- API endpoints return correct status codes
- Auth middleware rejects unauthenticated requests

### After Layer 3
- functional: true
- User registration flow works end-to-end
- Login redirects to dashboard

### Final
- functional: true
- Full acceptance criteria from design doc
- All prior QA gate criteria still pass (regression)
```

Build verification (lint, type-check, build, tests) runs after every layer regardless. The QA Gates section defines additional functional testing criteria. Layers marked `functional: true` run browser/E2E tests.

Note: layer numbers in QA gates are deterministic because the task-manifest skill computes layers from the dependency graph when it writes the manifest. The skill writes both tasks and QA gates together, so layer numbering is consistent.

## Teammate Subagent Definition

The `autoboard-implementer` subagent definition enforces quality without micromanaging.

```markdown
---
name: autoboard-implementer
description: Implements a single task from a reviewed plan. Use for autoboard task execution.
tools: Read, Edit, Write, Glob, Grep, Bash, Agent, Skill, NotebookEdit, LSP, WebFetch, WebSearch, ToolSearch
model: sonnet
---

You are an autoboard implementation agent. You receive a reviewed implementation
plan and quality standards directly in your prompt. Your job is to implement
one task from that plan.

## Workflow

1. Review the plan and standards provided above
2. Implement your assigned task following the plan's guidance
   - Follow the patterns and conventions the plan specifies
   - Use TDD when the plan calls for it (write test first, verify it fails,
     implement, verify it passes)
   - If the plan doesn't cover something you encounter,
     message the lead before deviating
3. Verify your work: run the full verify command
   - If verification fails, diagnose and fix (max 3 attempts)
   - If you cannot fix after 3 attempts, stop and report the blocker
4. Write your discoveries to /tmp/autoboard-{slug}-t{N}-knowledge.md:
   - Utilities you created or found (file paths, signatures)
   - Gotchas that cost you time
   - Anything the next developer would want to know
   - Only include things NOT obvious from reading the code
   - Max 5 entries, each one sentence
5. Commit your work with the exact commit message from your task

## Quality Rules

- MUST review the plan and standards before writing any code
- MUST run full verification before marking your task complete
- MUST follow patterns specified in the plan -- the planner explored the
  codebase, you didn't
- NO sloppy code: no debug artifacts, no commented-out code, no unused
  imports, no TODOs
- NO skipping tests: if the plan specifies test scenarios, implement them all
- NO inventing scope: implement exactly what the plan says, nothing more
- If something in the plan seems wrong, message the lead before deviating

## Shell Safety
- Use --yes with npx (no interactive prompts)
- Set CI=1 for test runners (no watch mode)
- Use npm ci not npm install (reproducible installs in worktrees)
- Kill hung commands after 60s rather than waiting indefinitely
```

### Context injection

The lead includes plan and standards content directly in each teammate's spawn prompt using `@` references. Teammates cannot skip reading them because the content is already in their context.

Spawn prompt structure:
```
Implement task T3: Create auth middleware.

## Your Plan
@/tmp/autoboard-user-auth-layer-1-batch-1-plan.md

## Quality Standards
@docs/autoboard/user-auth/standards.md

## Task Details
- creates: src/middleware/auth.ts
- key-test-scenarios: rejects expired tokens, rejects missing tokens, passes valid tokens
- verify-command: npm run lint && npm run typecheck && npm run build && npm run test
- commit-message: Add auth middleware with token validation
- worktree: /tmp/autoboard-user-auth-t3
```

### TaskCompleted hook

Automated verification gate with zero token cost:

```bash
#!/bin/bash
# Exit code 2 blocks task completion and sends output to teammate
# Note: the exact env vars available in TaskCompleted hooks need to be
# verified against Agent Teams documentation. The verify command and
# worktree path may need to be resolved from task metadata or the
# manifest config at implementation time.
npm run lint && npm run typecheck && npm run build && npm run test
exit_code=$?
if [ $exit_code -ne 0 ]; then
  echo "Verification failed. Fix issues before completing this task."
  exit 2
fi
```

## Planning Subagent

The planning subagent explores the codebase and writes implementation plans for a batch of tasks. It is the only agent that needs broad codebase understanding.

### What the plan includes (context transfer)

- Which files to modify and why
- Existing patterns to follow ("the other API routes use `createRoute()` from `src/lib/router.ts`")
- Gotchas discovered ("the `User` type is re-exported from `index.ts`, update the barrel file")
- Test strategy and key scenarios per task
- Constraints and dependencies within tasks

### What the plan does NOT include (no micromanagement)

- Exact code to write
- Line-by-line implementation steps
- Exact function signatures (unless matching an existing pattern)
- Step-by-step TDD instructions

The plan transfers contextual knowledge from the planner (who explored) to the teammate (who didn't). It specifies the what and the why, not the how. Like a tech lead writing a brief for a senior engineer.

### Plan file location

Plans are stored on disk at `/tmp/autoboard-{slug}-layer-{N}-batch-{B}-plan.md`. Outside the worktree to prevent accidental commits.

## Quality Gates

Three gates run between dependency layers, plus build verification after every layer. All dispatched as subagents -- heavy work stays out of the lead's context.

### Gate ordering

| Order | Gate | Scope | When |
|---|---|---|---|
| 1 | Code review | Per batch | After batch merge |
| 2 | Cohesion audit | Per layer | After all batches merged and reviewed |
| 3 | Build verification | Per layer, always | After cohesion fixes complete |
| 4 | Functional QA | Per layer, if manifest defines it | After build verification passes |

All code-changing gates (code review, cohesion) run before verification gates (build, functional QA). This ensures QA is the final seal of approval after all fixes are applied.

### Code review (per batch)

The lead dispatches the code-reviewer subagent after merging each batch.

The reviewer:
- Runs `git diff` itself (diff stays out of lead's context)
- Reads the plan file and standards file itself
- Outputs APPROVE or REQUEST CHANGES with BLOCKING/NIT severity

The lead applies the receiving-review protocol to evaluate findings before routing.

If BLOCKING issues: lead spawns fixer teammates, fixers implement fixes, lead re-runs code review. Max 3 rounds.

### Cohesion audit (per layer)

After all batches in a layer are merged and code-reviewed, the lead dispatches the cohesion-audit subagent.

Dimensions selected based on files touched:
- Always: DRY/code-reuse, error-handling, naming conventions, type safety
- Conditional: API design, frontend quality, data modeling, performance

If findings survive screening (via cohesion-screener subagent applying the receiving-review decision tree): lead dispatches fixer teammates. Max 5 rounds.

Fewer cohesion issues expected in v2 because the planning subagent enforces consistent patterns across tasks in the same batch.

### Build verification (every layer)

Always runs after cohesion fixes complete. Dispatches QA subagent that runs the full verify command (lint, type-check, build, tests).

If fail: dispatch fixer teammates. Max 5 rounds.

This is the "are we building on broken code?" gate. No layer proceeds without passing.

### Functional QA (per manifest QA gate)

Runs when the manifest defines a QA gate with `functional: true` for this layer.

The QA subagent runs:
- Browser smoke tests or E2E tests
- Layer-specific acceptance criteria from the manifest
- Regression criteria from ALL prior QA gates

If fail: lead dispatches QA validator to classify each failure:
- **GENUINE_FAIL** -- real code problem, dispatch fixer teammates
- **FABRICATION** -- agent claimed infrastructure failure to dodge reporting, re-run QA with override
- **PREMATURE** -- criterion tests functionality not yet implemented, defer

Fixer loop: max 5 rounds, escalate to user if no progress after 3 rounds.

### Final QA (after all layers)

Full build verification + functional E2E testing against all acceptance criteria from the design doc + all prior QA gate criteria (full regression suite).

## Knowledge Persistence

Knowledge flows forward between layers through files on disk.

### Per-task knowledge (written by teammates)

Each teammate writes `/tmp/autoboard-{slug}-t{N}-knowledge.md` before completing their task. Contains only things not obvious from reading the code:
- Utilities created or found (file paths, function signatures)
- Gotchas that cost time
- Surprising constraints

Max 5 entries per task, each one sentence. Required -- teammates cannot mark their task complete without writing this file.

### Per-layer knowledge (curated by knowledge-curator subagent)

After each layer, the lead dispatches the knowledge-curator subagent:
1. Reads all `/tmp/autoboard-{slug}-t*-knowledge.md` files from the layer's tasks
2. Reads prior layer's knowledge file (if exists)
3. Writes `docs/autoboard/{slug}/sessions/layer-{N}-knowledge.md`

The curated file is self-contained, not accumulated. Each layer's file contains what matters for future layers. Old knowledge that's now obvious from the code gets dropped. Max 10 entries total.

After the curator writes the layer knowledge file, per-task knowledge files (`/tmp/autoboard-{slug}-t*-knowledge.md`) from that layer are cleaned up.

### How knowledge gets consumed

- The planning subagent for the next layer gets `@layer-N-knowledge.md` in its prompt
- Teammates get knowledge indirectly through the plan (planner references established patterns)
- The lead holds a one-line summary, not the full file

## Orchestrator Flow (Run Skill)

### Step 1: Setup

- Read manifest, validate structure
- Compute dependency layers from task graph
- Group tasks into batches (max-batch-size per layer)
- Run setup command (npm install, etc.)
- Ensure Agent Teams experimental flag is enabled
- Display execution plan: layers, batches, task count, estimated model usage

### Step 2: Per layer (fully autonomous)

**2a. Run setup command** (idempotent, every layer)

**2b. Per batch** (sequential batches, parallel tasks within):

- **PLAN** -- Dispatch planning subagent (Opus). Gets: manifest tasks for batch, standards, layer knowledge, codesight. Produces: plan file on disk.
- **PLAN REVIEW** -- Dispatch plan-reviewer subagent (Sonnet). Gets: plan file path, manifest path, standards path. Max 3 rounds. Lead applies receiving-review.
- **IMPLEMENT** -- Create worktrees, spawn teammates (one per task, parallel). Each gets: @plan, @standards, task details, verify command. Model + effort from complexity. TaskCompleted hook enforces verification.
- **MERGE** -- Sequential merge per task to feature branch. Conflict: lead resolves or escalates.
- **CODE REVIEW** -- Dispatch code-reviewer subagent (Sonnet). Reviews diff from batch checkpoint. Lead applies receiving-review. If BLOCKING: spawn fixers, re-review (max 3 rounds).

**2c. After all batches in layer:**

- **COHESION AUDIT** -- Dispatch cohesion-audit subagent. If findings survive screening: spawn fixers (max 5 rounds).
- **BUILD VERIFICATION** -- Dispatch QA subagent, build only. Always runs. If fail: spawn fixers (max 5 rounds).
- **FUNCTIONAL QA** -- Only if manifest defines QA gate for this layer. Dispatch QA subagent, functional. Includes regression. If fail: classify and route fixers.
- **KNOWLEDGE** -- Dispatch knowledge-curator subagent. Reads task knowledge files + prior layer knowledge. Writes layer-N-knowledge.md.

### Step 3: Completion

- Dispatch full-spectrum coherence audit (all quality dimensions, no exclusions)
- If findings survive screening: spawn fixers (max 5 rounds)
- Dispatch final QA subagent (full build + functional E2E + all acceptance criteria + full regression)
- If pass: clean up worktrees, report results, offer PR creation
- If fail: fixer loop (max 5 rounds), then escalate

### Stopping points (lead asks user)

- Unresolvable merge conflicts
- Fixer rounds exhausted (3 for code review, 5 for QA/cohesion)
- No other pauses -- fully autonomous between layers

## What Gets Deleted

| Deleted | Replaced by |
|---|---|
| `bin/spawn-session.sh` | Agent Teams spawning |
| `skills/session-spawn/` | Lead spawns teammates directly |
| `skills/session-workflow/` (288 lines) | `autoboard-implementer` subagent (~40 lines) |
| `skills/tracking-github/` | Agent Teams shared task list |
| `skills/tracking-github-session/` | Agent Teams shared task list |
| `skills/merge/` | Lead handles git merge directly |
| `skills/failure/` | Lead handles retries and escalation |
| `config/default-session-permissions.json` | Agent Teams permission inheritance |
| Session status files | Task completion in Agent Teams |
| PID files and reaper logic | Agent Teams process management |
| Progress files | Shared task list visibility |

## What Stays (Adapted)

| Component | Changes |
|---|---|
| `skills/brainstorm/` | Unchanged |
| `skills/task-manifest/` | Generates tasks (not sessions) with dependencies |
| `skills/standards/` | Unchanged |
| `skills/run/` | Rewritten around Agent Teams |
| `skills/setup/` | Simplified |
| `skills/qa-gate/` | Adapted -- functional QA at every testable layer |
| `skills/qa-fixer/` | Fixer teammates instead of fixer sessions |
| `skills/coherence-audit/` | Unchanged mechanism |
| `skills/coherence-fixer/` | Fixer teammates instead of fixer sessions |
| `skills/completion/` | Final QA gate |
| `skills/verification/` | Used by QA subagent |
| `skills/verification-light/` | Used by teammates |
| `skills/receiving-review/` | Used by lead when evaluating review findings |
| `skills/diagnose/` | Available to fixer teammates |
| `agents/plan-reviewer.md` | Unchanged |
| `agents/code-reviewer.md` | Adapted -- reviews batch diff, not session diff |

## New Additions

| Component | Purpose |
|---|---|
| `agents/autoboard-implementer.md` | Teammate subagent definition |
| `agents/autoboard-planner.md` | Planning subagent definition |
| `agents/knowledge-curator.md` | Curates cross-layer knowledge |
| `agents/qa-validator.md` | Classifies QA failures (genuine/fabrication/premature) |
| `agents/cohesion-screener.md` | Screens cohesion findings via receiving-review decision tree |

## Gaps from V1 to Preserve

These V1 behaviors must be carried into V2. Identified via audit of the full V1 codebase.

### Worktree Setup Protocol

Before creating worktrees for any layer:
1. **Commit docs to feature branch.** Knowledge files, progress updates, and manifest changes must be committed to HEAD before worktree creation -- worktrees branch from HEAD and uncommitted files won't exist in them.
2. **Symlink .env files.** Git worktrees don't include gitignored files. After creating each worktree, symlink `.env*` files and `.codesight` directory from the main repo.

### Shell Safety for Teammates

The implementer subagent definition must include:
- Use `--yes` with npx to prevent interactive prompts
- Set `CI=1` for test runners to disable watch mode
- Use `-m` for git commit messages (no editor)
- Use `npm ci` not `npm install` in worktrees (reproducible installs)
- Kill hung commands after timeout rather than waiting indefinitely

### Test Baseline Capture

During setup (Step 1), run the verify command and capture any pre-existing test failures as the baseline. Store at `docs/autoboard/{slug}/test-baseline.md`. Teammates and QA subagents compare their failures against this baseline to distinguish pre-existing issues from new regressions. Without this, teammates waste time fixing tests that were already broken.

### Merge Conflict Resolution

The lead needs a specific auto-resolve protocol for merges:
1. Whitespace/formatting-only conflicts -- accept the teammate's version
2. Generated files (lock files, build artifacts) -- accept the teammate's version
3. Other conflicts -- accept the teammate's version only if the file wasn't modified by a previously-merged teammate in this layer
4. If conflicts remain after auto-resolve -- abort merge, preserve worktree, escalate to user

### Failure Classification

When a teammate fails (non-zero exit, context exhaustion, timeout), the lead must classify before acting:

| Category | Action |
|---|---|
| **Permission denial** | Do NOT retry (same denial will happen). Report denied command, suggest adding to permissions. |
| **Review escalation** | Do NOT count against retry budget. Lead arbitrates: read both sides, cross-reference design doc, make a call. |
| **Dependency cascade** | Mark downstream tasks as blocked. Do not attempt until upstream succeeds. |
| **Code/task failure** | Dispatch evidence-gatherer subagent to read failure output (keeps evidence out of lead context), then spawn fixer teammate with diagnosis. |

The evidence-gatherer subagent reads teammate output and returns a compressed summary -- the lead never reads raw failure output directly.

### Fixer Discipline

Fixer teammates must:
1. **Diagnose before fixing.** Invoke `/autoboard:diagnose` to reproduce the failure and identify root cause before writing any code.
2. **Build-first rule.** If any build steps failed, fix build issues first (Round 0) before addressing functional/browser failures. Build failures are often the root cause of downstream failures.
3. **Post-merge circuit breaker.** After merging a fixer's work, run the verify command. If it fails (merge produced broken code), roll back to checkpoint before attempting the next fixer round.

### Full-Spectrum Coherence at Completion

The completion step (Step 3) must include a full-spectrum coherence audit (all quality dimensions, no exclusions) BEFORE the final QA gate. Per-layer audits only check dimensions relevant to files touched. The completion audit checks everything to catch cross-layer architecture drift.

### Auth and Browser Setup

For `qa-mode: full`, the setup step must:
1. Detect available browser tools (gstack browse, Playwright MCP, etc.)
2. Detect auth provider (Supabase, Firebase, Clerk, etc.) and configure test credentials
3. Validate prerequisites: browser tool detected, dev server configured, env vars filled
4. Store `auth-strategy` and `test-credentials` in manifest config

Without this, functional QA subagents can't log in or interact with authenticated pages.

### Agent Teams Uncertainties

These assumptions need verification during implementation:
1. **Worktree isolation for teammates** -- whether `isolation: worktree` in the subagent definition carries over when used as a teammate type. If not, the lead must create worktrees manually (via Bash) and pass the path to teammates.
2. **Model/effort override per teammate** -- the docs don't show a structured API for this. May need multiple subagent definitions (e.g., `autoboard-implementer-opus-high`, `autoboard-implementer-sonnet`) or rely on natural language at spawn time.
3. **Subagent spawning from teammates** -- teammates are full Claude Code sessions and likely can use the Agent tool, but this is unconfirmed. If not, teammates cannot dispatch Explore subagents, which is fine since they get context from the plan.
4. **TaskCompleted hook environment** -- the hook receives JSON via stdin (task_id, task_subject, etc.) but the exact mechanism for knowing the worktree path and verify command needs to be determined.
