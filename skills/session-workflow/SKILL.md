---
name: session-workflow
description: Session agent workflow — Explore, Plan, Plan Review, Implement, Verify, Code Review, Commit. Invoke FIRST before any work in a autoboard session.
---

# Session Workflow

You are a session agent spawned by autoboard as a `claude -p` subprocess with full tool access. Your dependency sessions' changes are already merged into your branch.

## Worktree Navigation

Your session brief contains a worktree path. Your FIRST action after loading this skill:
1. `cd` to the worktree path
2. Verify: `pwd` and `git branch --show-current` match expected values

ALL subsequent work happens in that directory. Never navigate outside your worktree.

## Progress Reporting

Your session brief contains a `Progress directory` path. After each phase transition and task completion, write your current status to that directory as `s{N}.md`:

```markdown
# S{N}: {focus}
Phase: {current phase}
Tasks:
- [x] T1: {title} — done
- [ ] T2: {title} — in progress
- [ ] T3: {title} — pending
```

Update this file after: entering each phase, completing each task, encountering errors.

## Tracking

If your session brief includes a `## Tracking` section, read the `Provider` field and invoke the `/autoboard:tracking-{provider}` skill (e.g., `/autoboard:tracking-github`). Follow the "For Session Agents" section of the loaded provider skill. If your brief does NOT have a Tracking section, skip this.

## Your Tasks

Your session brief (in your prompt) contains your tasks. Each task has fields: creates, modifies, depends on, requirements, TDD phase, test approach, key test scenarios, and commit message.

## Protocols

### Decisions Protocol

When you make an architectural choice during implementation, append to `decisions.md` in the project directory:

```markdown
## [S{n}] {Decision title}
**Why:** {Reasoning}
**Trade-off:** {What was traded off}
```

### Resume Protocol

If your session brief indicates this is a retry (prior attempt failed):

1. Explore the worktree — check git log, test status, file state
2. Identify which tasks are already completed (passing tests, committed)
3. Continue from the first incomplete task
4. Do NOT redo completed work

---

## Phase 1: Explore

**Update progress file:** Write `Phase: Exploring` to your progress file before starting.
**Tracking:** If tracking is active, move your ticket to "Exploring" and post a phase comment.

Exploration happens in two steps. Use Claude Code's built-in Explore subagent for both. When spawning Explore subagents, use the `explore-model` from your session brief's Configuration section (default: haiku).

**Step 1: Explore prior sessions' work.** If your session brief includes `## Knowledge from Prior Sessions` (i.e., you are not in Layer 0):
- Read the knowledge entries to understand what utilities, patterns, and conventions already exist
- Explore the file paths mentioned — verify they exist and understand their APIs
- **Action on overlap:** If a prior session already built something your tasks plan to create, use the existing implementation. Adjust your plan: convert Creates entries to Modifies (if you need to extend it) or remove them (if you can use it as-is). Do NOT rebuild what already exists.

**Step 2: Explore task-specific targets.** Explore the codebase areas specified in the session brief's explore targets. Direct what to investigate — the Explore subagent handles the mechanics.

No implementation before understanding.

| Thought that means STOP | Reality |
|---|---|
| "I already know this codebase" | You have fresh context. Explore to ground your understanding in what actually exists. |
| "Exploring wastes time, I'll start coding" | Coding without understanding wastes 10x more time fixing wrong assumptions. |
| "The manifest describes what I need" | The manifest describes intent. The codebase describes reality. Verify. |

## Phase 2: Plan

**Update progress file:** Write `Phase: Planning` to your progress file.
**Tracking:** If tracking is active, move your ticket to "Planning" and post a phase comment.

Write your implementation plan as a markdown file.

**Do NOT use plan mode tools (e.g., EnterPlanMode, ExitPlanMode)** — these require interactive confirmation and do not work in headless mode.

The plan must include:
- Exact file paths and what changes in each
- Test strategy per task — reference the task's **Key test scenarios** from the manifest. Your tests must cover the specified scenarios (happy path, error paths, edge cases), not just the happy path. If a task has no key test scenarios, derive them from the requirements.
- Dependency order between tasks
- Risk areas and mitigation

| Thought that means STOP | Reality |
|---|---|
| "This is simple, I don't need a plan" | Simple tasks have the most unexamined assumptions. Plan anyway. |
| "I'll figure it out as I go" | Improvisation compounds errors. Write the plan. |
| "The manifest IS the plan" | The manifest describes WHAT. The plan describes HOW, with exact files and verification steps. |

## Phase 3: Plan Review (BLOCKING GATE)

**Update progress file:** Write `Phase: Plan Review` to your progress file.
**Tracking:** If tracking is active, post a comment that plan review is starting (keep ticket on "Planning").

**MANDATORY FIRST ACTION:** Invoke the `/autoboard:receiving-review` skill BEFORE dispatching the reviewer or evaluating any feedback. Do NOT skip this — the skill contains the authoritative decision tree for evaluating findings. Any evaluation performed without loading this skill first is invalid. **After it loads**, immediately dispatch the plan reviewer below — do not stop here.

Dispatch the `autoboard:plan-reviewer` subagent with the `plan-review-model` from your session brief's Configuration section (default: sonnet). Send it the implementation plan and task context from the manifest.

Max 3 review rounds. Push back on incorrect suggestions with specific proven-harm reasoning per the receiving-review decision tree.

**Do NOT proceed to implementation with unresolved BLOCKING issues.**

**If 3 rounds complete with unresolved BLOCKING issues:** Escalate to the orchestrator. Do NOT silently proceed with unresolved issues. Do NOT hang waiting for user input.

Write your session status file with `Status: escalation` and an `## Escalation` section:

```markdown
# Session S{N}: {focus}

**Status:** escalation
**Phase:** Plan Review
**Review rounds completed:** 3
**Tasks completed:** none

## Escalation

### Reviewer's Position
{Paste the BLOCKING issues the reviewer flagged in the final round, verbatim}

### Session's Position
{Your technical counterarguments — why you believe the reviewer is wrong or the issue is not blocking}

### Recommended Resolution
{What you think the right call is, with reasoning}

## Knowledge
{Any knowledge discovered during exploration, even if implementation didn't complete}
```

Then exit. The orchestrator will read both sides and arbitrate.

| Thought that means STOP | Reality |
|---|---|
| "The plan looks good, I'll skip review" | Run the review subagent. Every time. No exceptions. |
| "This is a simple change, no review needed" | Simple changes have the most unexamined assumptions. |
| "I'll save time by starting implementation now" | Fixing a bad plan costs 10x more than reviewing it. |
| "The reviewer will probably just approve it" | Then the review takes 30 seconds. Do it. |

After review approval, write the approved plan to the artifacts path given in your prompt.

## Phase 4: Implement

**Update progress file:** Write `Phase: Implementing` and your task checklist to your progress file. Update after each task completion.
**Tracking:** If tracking is active, move your ticket to "Implementing" and post a phase comment. Post a comment on each task completion.

Execute tasks from the reviewed plan. Follow the Quality Standards (loaded at session start) throughout.

### TDD Tasks (RED -> GREEN -> REFACTOR)

1. Write the failing test first. Run it. Watch it fail. **(RED)**
2. Write the minimum implementation to make it pass. **(GREEN)**
3. Refactor if needed, keeping tests green. **(REFACTOR)**

### Non-TDD Tasks

Implement the change, then write tests covering the new behavior.

### Task Parallelization

Independent tasks MAY be executed via parallel subagents at your discretion. **Constraint:** parallel tasks must NOT write to the same files — they share a single worktree filesystem.

| Thought that means STOP | Reality |
|---|---|
| "I'll write the code first, then add tests" | Delete the code. Write the test. No exceptions. |
| "This is too simple to need TDD" | Simple code has simple tests. Write them. |
| "The test is obvious, I'll skip the RED step" | If you didn't see it fail, you don't know it tests what you think. |
| "I'll add tests at the end" | Tests written after implementation are confirmation bias. |

**Execution discipline:**
- Follow the plan step by step. Do not skip ahead or reorder.
- Run every verification command specified in the plan. Do not assume it passes.
- Stop immediately when blocked — missing dependency, unclear requirement, repeated test failure. Describe the blocker clearly.

## Phase 5: Verify

**Update progress file:** Write `Phase: Verifying` to your progress file.
**Tracking:** If tracking is active, move your ticket to "Verifying" and post a phase comment.

Invoke the `/autoboard:verification` skill to load the verification protocol. **After verification returns**, continue executing the steps below — do not stop here. Verification loading is not a turn boundary.

Run the verification command from your session brief. Typically:

1. Package install (e.g., `npm install`, `pip install`)
2. Type checking (e.g., `npx tsc --noEmit`, `mypy`)
3. Build (e.g., `npm run build`)
4. Test (e.g., `npm test`, `pytest`)

All steps must pass. If any fails, diagnose, fix, and re-run ALL commands. Max 3 attempts.

| Thought that means STOP | Reality |
|---|---|
| "Tests should pass, I'll skip verification" | "Should" is not evidence. Run the commands. |
| "I just ran tests during implementation" | Those were per-task. This is full-suite. Run them again. |
| "Only my files changed, nothing else could break" | Integration effects are invisible until you test. Run all commands. |
| "I'll verify after code review" | Code review assumes verified code. Verify first. |

**After all verification steps pass**, proceed immediately to Phase 6. Do not stop after verification.

## Phase 6: Code Review (BLOCKING GATE)

**Update progress file:** Write `Phase: Code Review` to your progress file.
**Tracking:** If tracking is active, move your ticket to "Code Review" and post a phase comment.

**MANDATORY FIRST ACTION:** Invoke the `/autoboard:receiving-review` skill BEFORE dispatching the reviewer or evaluating any feedback. Do NOT skip this — the skill contains the authoritative decision tree for evaluating findings. Any evaluation performed without loading this skill first is invalid. **After it loads**, immediately dispatch the code reviewer below — do not stop here.

Dispatch the `autoboard:code-reviewer` subagent with the `code-review-model` from your session brief's Configuration section (default: sonnet). Send it the full diff (`git diff` output), the approved plan, and relevant context.

Max 3 review rounds. Push back on incorrect suggestions with specific proven-harm reasoning per the receiving-review decision tree. After implementing fixes, re-run verification (Phase 5) before resubmitting to the reviewer.

**If 3 rounds complete with unresolved BLOCKING issues:** Escalate to the orchestrator. Do NOT silently proceed with unresolved issues. Do NOT hang waiting for user input.

Write your session status file with `Status: escalation` and an `## Escalation` section:

```markdown
# Session S{N}: {focus}

**Status:** escalation
**Phase:** Code Review
**Review rounds completed:** 3
**Tasks completed:** {list of committed tasks}

## Escalation

### Reviewer's Position
{Paste the BLOCKING issues the reviewer flagged in the final round, verbatim}

### Session's Position
{Your technical counterarguments — why you believe the reviewer is wrong or the issue is not blocking}

### Recommended Resolution
{What you think the right call is, with reasoning}

## Knowledge
{Key discoveries or patterns for future sessions}
```

Then exit. The orchestrator will read both sides and arbitrate.

| Thought that means STOP | Reality |
|---|---|
| "All tests pass, time to commit" | Run the code review subagent first. Every time. |
| "The code is clean, review is a formality" | You wrote it — you can't see your own blind spots. |
| "I'll save time and skip this round" | Time saved here is bugs shipped later. |
| "The reviewer will probably just approve it" | Then the review takes 30 seconds. Do it. |

## Phase 7: Commit

**Update progress file:** Write `Phase: Committing` to your progress file.
**Tracking:** If tracking is active, post a summary comment on your issue (see the loaded tracking provider skill). The orchestrator handles moving your ticket to "Done" after merge.

Commit each task with its exact commit message from the manifest. Do not modify commit messages.

Write a session status file to `docs/autoboard/<slug>/sessions/s{N}-status.md` (the project directory path is in your session brief):

```markdown
# Session S{N}: {focus}

**Status:** success | failure
**Branch:** {session-branch}
**Tasks completed:** T1, T2, T3
**Tests:** {pass count} pass, {fail count} fail

## Knowledge
- **Shared utilities created:** {file paths, function signatures, and usage examples — e.g., "`convex/lib/auth.ts` exports `authenticatedQuery(handler)` and `authenticatedMutation(handler)` — wraps handlers with automatic userId injection. Use instead of raw `query()` + manual `requireAuth()`."}
- **Patterns established:** {conventions downstream sessions should follow — e.g., "All API error responses use `ConvexError` with a reason string — do not throw raw Error objects."}
- **Existing patterns discovered:** {things already in the codebase that weren't obvious from the manifest — e.g., "The project uses barrel exports in each feature directory — add an index.ts when creating a new feature folder."}
- **Gotchas:** {things that caused wasted time — e.g., "Convex validators don't support optional fields with defaults — must handle undefined explicitly in handler logic."}

## Failure Context (if failed)
- **Phase:** {where it failed}
- **Error:** {error message}
```

## Rules

- Your FIRST action after loading this skill: `cd` to the worktree path from your session brief.
- ALL code changes happen in your worktree. Never modify files outside your worktree directory.
- Write progress updates to the shared progress directory after each phase and task completion.
- Do not touch files unrelated to your tasks.

---

# Quality Standards

Every task must satisfy the project's active quality standards. Violations are blocking issues in code review.

## Quality Standards

Quality standards for your project are included in your session brief under the `## Quality Standards` section. Follow them throughout implementation — use the Criteria checklists as implementation guidance, and the Common Violations lists as a "don't do this" reference.

If no Quality Standards section is present in your brief, no project-specific standards apply.

**Passing standards to reviewers:** When you dispatch plan-reviewer or code-reviewer subagents, include the full Quality Standards content from your brief in the reviewer's prompt. Reviewers do NOT inherit your context — they only see what you pass them.

## TDD Discipline

For tasks marked TDD (non-Exempt), follow the strict RED -> GREEN -> REFACTOR cycle:

1. **RED**: Write a failing test that describes the desired behavior.
2. **Verify RED**: Run the test suite. Confirm the new test fails with the expected reason. Do NOT proceed if it passes — the test is wrong.
3. **GREEN**: Write the minimum implementation to make the test pass.
4. **Verify GREEN**: Run the test suite. Confirm all tests pass — new and existing.
5. **REFACTOR**: Clean up implementation and tests. Improve naming, extract duplication, simplify.
6. **Verify REFACTOR**: Run the test suite again. Confirm nothing broke.

**Skipping RED verification or writing implementation before tests is a BLOCKING violation.**

## Cleanup Culture

- **Leave the codebase cleaner than you found it.** If you touch a file and notice mess — stale comments, unused variables, poor organization — fix it. Don't punt cleanup to a future task.
- **Zero dead code in files you create or modify for your tasks**: No commented-out blocks, no unused functions, no orphaned imports, no stale TODOs. Do not clean up files unrelated to your tasks — another session may depend on code that looks unused from your perspective.
- **Remove failed attempts**: During debugging, when you fix a bug, remove every failed attempt before committing. The commit should contain only the working solution.
- **No debug artifacts**: Console.log statements, temporary test values, and debugging scaffolding must be removed before committing.

## Verification

All verification commands defined in your task's plan must pass before proceeding to code review. Run them, confirm they pass, and include the evidence. Never claim success without proof. Do not proceed to code review without passing verification.

---

# Shell Safety

These patterns cause agent failures and wasted retries. Avoid them.

## Never use interactive CLI tools without suppression

Many scaffolding tools (`create-next-app`, `create-vite`, etc.) prompt for input by default.
Always pass non-interactive flags or pipe input:
- Use `--yes` with `npx` to skip "Ok to proceed?" prompts (e.g., `npx --yes create-next-app@latest my-app --use-npm`)
- Use `yes "" | <command>` as a last resort for tools with no non-interactive flag
- Set `CI=1` or `NONINTERACTIVE=1` to suppress interactive behavior

## Use `npm ci`, not `npm install`

`npm install` modifies the lockfile and is non-deterministic. `npm ci` installs exactly
what's in the lockfile. Always use `npm ci` for reproducible builds.

## Don't run commands that block on stdin

If a command hangs with no output, it's probably waiting for input. Kill it and find the
non-interactive equivalent. Common culprits:
- Test runners in watch mode (fix: `CI=1 npm test`)
- Package managers asking for confirmation
- Git operations that open an editor (fix: use `-m` flags)

## Run verification commands in order

Type-check -> build -> test. If type-check fails, don't run build. If build fails, don't run tests.
Read error output carefully before retrying — don't re-run the same failing command.
