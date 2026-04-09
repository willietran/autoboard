---
name: task-manifest
description: Generate a task manifest from an autoboard design doc. Produces a task-based implementation plan with dependency graph, complexity scores, and QA gates.
---

# Autoboard Task Manifest Generator

You are generating a task manifest from a design document. The manifest defines tasks - each task is implemented by one teammate in its own git worktree. Tasks run in parallel where dependencies allow. Layers are computed at runtime from the dependency graph.

## Input

The design doc path is provided as an argument. If a slug is provided instead of a path, resolve it to `docs/autoboard/<slug>/design.md`.

Read the design doc first. Understand the full scope before generating tasks.

## Output

Write one file: `docs/autoboard/<slug>/manifest.md`

The manifest contains:
1. Config section
2. Title and design doc reference
3. Tech stack table
4. Task definitions with dependency graph
5. QA gates at layer boundaries
6. Task summary table (task, complexity, depends-on, layer)
7. Security checklist

## Config Section

The manifest starts with a config section:

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
qa-mode: build

planning-model: opus
plan-review-model: sonnet
code-review-model: sonnet
qa-model: sonnet
cohesion-model: sonnet
```

**Field guidance:**

- `feature` - slug derived from the design doc title
- `branch` - always `autoboard/<feature>`
- `verify-command` - infer from tech stack (e.g., `cargo build && cargo test` for Rust)
- `setup-command` - include if the project needs dependency installation, migrations, or seed data. Omit if not needed.
- `dev-server` - include if the project has a UI or browser-testable endpoints. Omit if not needed.
- `default-teammate-model` - always `sonnet`
- `opus-threshold` - complexity score at which tasks upgrade to Opus (default: 5)
- `opus-effort-map` - maps complexity to effort for Opus tasks only. Sonnet tasks do not use effort.
- `max-batch-size` - max tasks planned together in one batch (default: 5). Larger layers are split into batches for planning and code review, but all tasks within a layer still implement in parallel.
- `qa-mode` - `build` (default) or `full` (browser testing)

**`qa-mode`** - ask the user via AskUserQuestion which QA mode they want:

> **QA testing level for this project:**
> 1. **Full** - Browser integration tests + build/test. QA agents navigate the app, fill forms, verify UI. Requires a browser tool (gstack browse, Playwright MCP, or agent-browser) and a dev server. Best for web apps with UI.
> 2. **Build-only** (default) - Type check, build, and test suite only. No browser testing. Appropriate for CLIs, libraries, backend-only services, or when no browser tool is available.

Default to `build` if the user doesn't answer.

## Task Definition Format

Each task is a self-contained unit of work for one teammate:

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

**Fields:**

| Field | Required | Purpose |
|---|---|---|
| title | Yes | What the task accomplishes |
| creates | No | Files this task creates |
| modifies | No | Files this task modifies |
| depends-on | Yes | Task IDs that must complete first, or `none` |
| requirements | Yes | What to build - specific enough for a teammate who hasn't explored the codebase |
| key-test-scenarios | Yes | What to test - drives plan quality and code review |
| complexity | Yes | Fibonacci scale: 1, 2, 3, 5, 8 |
| commit-message | Yes | Exact commit message for the task |
| model | No | Override default model for this task (e.g., `opus`) |

**Requirements** can use nested lists for detail:

```markdown
- requirements:
  - Create auth middleware using jose library for JWT verification
  - Handle three token states: valid, expired, missing
    - Valid: attach user to request context
    - Expired: return 401 with "token expired" message
    - Missing: return 401 with "authentication required" message
  - Export as default middleware for route protection
```

**Key test scenarios** should cover happy paths, error paths, and edge cases:

```markdown
- key-test-scenarios:
  - valid email + password creates account and returns session token
  - duplicate email returns "Email already registered" error
  - weak password returns validation error listing requirements
  - email with leading/trailing whitespace is trimmed and accepted
```

## Rules

### Dependency Inference

Each task runs in an **isolated git worktree** that only contains code merged from its completed dependencies - nothing else exists.

- Honor explicit dependencies from the design doc
- Infer implicit dependencies: if Task B needs anything Task A produces to build, test, or run - files, packages, config, toolchains, project structure - B depends on A
- **The worktree test**: for each task with `depends-on: none`, ask: "Could this task's teammate succeed in a worktree containing only the repo's current main branch?" If not, it has a missing dependency
- **Refactoring addendum**: for tasks that modify shared interfaces, also consider: "Do any other tasks consume the code being changed?" If so, those tasks depend on this one - even if they don't use its output files.
- Ensure topologically valid ordering (no circular deps)

### Layers

Layers are computed from the dependency graph:

- Layer 1: all tasks with `depends-on: none`
- Layer 2: all tasks whose dependencies are all in Layer 1
- Layer 3: all tasks whose dependencies are all in Layers 1-2
- etc.

Layers are NOT declared in the manifest. The lead computes them at runtime. However, you must compute them yourself when writing the manifest in order to:
1. Place QA gates at correct layer boundaries
2. Fill in the "layer" column of the task summary table
3. Verify the dependency graph produces a reasonable number of layers

### Batch Sizing

When a layer exceeds `max-batch-size`, it is split into batches. Each batch gets its own planning and code review cycle. All tasks within a layer still implement in parallel - batching only affects planning and review scope. The `max-batch-size` config controls this.

### Backend Provisioning

When the tech stack includes a managed backend (Convex, Supabase, PlanetScale, Firebase, etc.), a Layer 1 task MUST provision it - not just create config files.

**Critical: teammates run non-interactively.** They cannot answer prompts, select from menus, or interact with dashboards. All CLI commands in task requirements MUST use non-interactive flags. If a CLI blocks waiting for input, the teammate hangs forever.

**Two-phase provisioning:**

1. **Preflight (lead agent)** - handles initial interactive setup. The verification preflight works with the user to provision each empty env var before teammates start. This includes backend project creation, API key generation, and any CLI commands that require user input.

2. **Teammate tasks** - handle non-interactive operations only. Schema pushes, migrations, seeding, verification. Check the CLI tool's `--help` for non-interactive flags and specify the exact headless command in the task requirements.

**Task requirements should:**
- Specify the exact CLI command with non-interactive flags (check `--help` for each tool)
- Push the initial schema/migrations
- Verify the backend is reachable
- Write the connection URL to `.env.local` (or equivalent)

**The `setup-command` config field** must also use non-interactive flags - the lead runs it during setup AND re-runs it before every layer, so it must work headlessly every time.

### Complexity Scoring

Complexity measures **cognitive difficulty** - how hard you have to think, not how much work there is. A 200-line CRUD endpoint following an established pattern is low complexity. A 30-line race condition fix is high complexity.

**Fibonacci scale (1, 2, 3, 5, 8):**

| Score | Name | Model | Effort | Anchor Example |
|---|---|---|---|---|
| 1 | Rote | Sonnet | n/a | Add a new field to an existing CRUD endpoint following the exact pattern of 5 existing fields |
| 2 | Guided | Sonnet | n/a | Implement a new API endpoint similar to existing ones, but with a custom validation rule |
| 3 | Considered | Sonnet | n/a | Build auth middleware integrating with an external provider, handling token refresh and error states |
| 5 | Tricky | Opus | high | Fix a race condition between concurrent DB writes, or design a state machine for a multi-step workflow |
| 8 | Novel | Opus | max | Implement a custom conflict resolution algorithm for real-time collaborative editing |

Tasks at complexity 1-3 use Sonnet with no effort flag. Tasks at complexity 5+ use Opus with effort from the `opus-effort-map` config. This is why effort only matters for Opus tasks - Sonnet doesn't use it.

**Key discriminator:** "If I gave this task to a competent developer with full codebase access, how long would they spend *thinking* before they started typing?" Rote = seconds. Guided = minutes. Considered = an hour. Tricky = half a day. Novel = days.

**Baseline anchoring:** Every manifest must identify one task as the **baseline** (complexity 2). This should be the most "standard" task - an endpoint, a component, a migration that follows an established pattern. All other tasks are scored *relative to this baseline*. Ask: "Is this task twice as hard to think about as the baseline? That's a 3. Does it have genuinely non-obvious failure modes? That's a 5."

**Distribution check:** After scoring all tasks, verify the distribution. If more than 40% of tasks score 5 or 8, re-examine each one against the baseline. Most real projects are 60-70% complexity 1-3 with a few genuinely hard ones. A top-heavy distribution signals the scorer is treating volume of work as cognitive difficulty.

### Architectural Foundations

After drafting all tasks, scan for cross-task shared needs:

1. **Shared utility detection.** Compare creates/modifies fields across tasks. If 2+ tasks in different layers will create similar functionality (auth wrappers, error handlers, validation helpers, API clients, shared UI components), extract a foundation task in an earlier layer. The foundation task's creates field lists the utility's file path; its requirements specify the public API. Downstream tasks depend on it and reference the utility by path - they do NOT recreate it.

2. **Convention seeding.** The first task that touches a concern area (error handling, API responses, file organization) must include in its requirements: the specific pattern to follow. Example: "All mutation handlers use the `authenticatedMutation` wrapper from `convex/lib/auth.ts` - do not use raw `mutation()` with manual auth checks." Downstream tasks that touch the same area include a dependency on this task.

3. **Security parity.** If any task requires auth middleware, rate limiting, or input validation, check all tasks creating similar endpoints/routes. Add to each affected task's requirements: "Apply the same {security pattern} as T{N}."

### QA Gate Placement

QA gates run between dependency layers. Build verification (lint, type-check, build, tests) runs after every layer regardless. QA gates define additional criteria and optionally enable functional testing.

#### When to place QA gates

- **Flat dependency graph** (all tasks independent): No mid-pipeline gates needed. The lead runs a final QA after all tasks complete.
- **Layered dependency graph**: Place QA gates at layer boundaries where integration risk is high. Not every layer boundary needs one - use judgment about where compound errors are most likely.

#### Gate rules

1. **Layer-boundary gates**: After each dependency layer where integration risk is high, insert a QA gate.
2. **Blocking**: Tasks in Layer N+1 cannot start until the QA gate after Layer N passes.
3. **Final QA**: The lead always runs a final QA gate after all layers complete, regardless of whether the manifest marks one.
4. **Don't over-gate.** A 10-task project with 3 layers needs at most 2 mid-pipeline gates + 1 final gate.

#### QA gate format

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

Layers without `functional: true` get build verification only. Layers with `functional: true` also get browser/E2E tests.

#### Acceptance criteria rules

1. **Every user-facing feature** in the preceding layers must have at least one criterion
2. **Test COMPLETE FLOWS, not isolated actions:**
   - BAD: "User can sign up" (tests one step, misses what happens after)
   - GOOD: "User can sign up with email/password, is redirected to the dashboard, dashboard renders with correct layout"
3. **Include at least one "golden path"** that walks through the primary use case end-to-end across multiple features
4. **Include negative cases** for security-critical flows (invalid login rejects, unauthorized access redirects)
5. If `qa-mode` is `build`, acceptance criteria are still written but verified via test output, not browser interaction
6. For tasks that modify existing interfaces, criteria must verify existing consumers still work
7. **Criteria must be testable at the gate boundary.** If a feature's UI is built in a later layer, don't write browser-interaction criteria for it at this gate. Defer UI-interaction criteria to the gate after the UI layer.

### Task Summary Table

After all task definitions and QA gates, include a summary table:

```markdown
## Task Summary

| Task | Title | Complexity | Depends On | Layer |
|---|---|---|---|---|
| T1 | Create user schema and types | 2 (baseline) | none | 1 |
| T2 | Set up auth provider | 3 | none | 1 |
| T3 | Build auth middleware | 3 | T1, T2 | 2 |
| T4 | Create user API endpoints | 2 | T3 | 3 |
| T5 | Build registration flow | 5 | T3 | 3 |
| T6 | Build login page | 2 | T3 | 3 |
```

Mark the baseline task. This table gives a quick overview of the dependency graph and layer distribution.

### Security Checklist

Include a security checklist at the end of the manifest. Derive items from the design doc's security requirements and the tasks that handle auth, user input, or sensitive data:

```markdown
## Security Checklist
- [ ] Auth middleware applied to all protected routes (T3)
- [ ] Input validation on all user-facing endpoints (T4, T5)
- [ ] Password hashing uses bcrypt/argon2, never plain text (T2)
- [ ] Session tokens have expiration and refresh logic (T3)
- [ ] Rate limiting on auth endpoints (T5)
```

## Architect Review Loop

After generating the manifest:
1. Dispatch the `autoboard:plan-reviewer` agent via the Agent tool (max 3 rounds). Include the manifest content and design doc path in the prompt, and instruct the reviewer to focus on these manifest-specific criteria:
   - **Dependency correctness** - apply the worktree test to every task. Would this task's teammate succeed in a worktree containing only the repo's current main branch plus its completed dependencies? Are implicit dependencies captured (shared types, config, toolchains)?
   - **Complexity calibration** - is the baseline well-chosen? Does the distribution pass the 40% check (no more than 40% of tasks at 5+)? Are Opus tasks genuinely tricky/novel?
   - **QA gate placement** - gates at the right layer boundaries? Not over-gated? Acceptance criteria testable at the gate boundary (not testing UI before the UI layer ships)?
   - **Architectural foundations** - shared utilities extracted to early-layer foundation tasks? Convention seeding in first tasks? Security parity across similar endpoints?
   - **Test scenario coverage** - key test scenarios cover error paths and edge cases, not just happy paths?
   - **Task granularity** - are tasks right-sized? No mega-tasks that should be split? No trivial tasks that should be merged?
   - **QA acceptance criteria thoroughness** - do criteria test complete flows, not isolated actions? Do they include negative cases for security-critical flows? Does every user-facing feature have at least one criterion?
2. After each review round, invoke `/autoboard:receiving-review` via the Skill tool BEFORE evaluating the plan-reviewer's findings. Apply its decision tree and forbidden dismissals to each finding.
3. Update manifest with accepted changes
4. Write audit trail to `docs/autoboard/<slug>/architect-review.md`

## Terminal State

Show the user a summary:
- Total task count
- Number of dependency layers
- Number of QA gates
- High-complexity callouts (score >= 5)
- Any security concerns

Then run a preflight check by invoking `/autoboard:verification --preflight` via the Skill tool. This reads the just-written `manifest.md` for config, detects available browser tools, and validates prerequisites. At this stage, preflight is advisory - it tells the user what to set up but doesn't block.

Then prompt:
> Manifest written to `docs/autoboard/<slug>/manifest.md`.
>
> Next step: Run `/autoboard:run <slug>` to start the build.
