---
name: task-manifest
description: Generate a task manifest from a autoboard design doc. Produces a session-oriented implementation plan with dependency graph, QA gates, TDD phases, and complexity scores.
---

# Autoboard Task Manifest Generator

You are generating a task manifest from a design document. The manifest defines sessions — each session is an independent agent with its own git worktree. Tasks within a session run sequentially by one agent. Sessions run in parallel where dependencies allow.

## Input

The design doc path is provided as an argument. If a slug is provided instead of a path, resolve it to `docs/autoboard/<slug>/design.md`.

Read the design doc first. Understand the full scope before generating tasks.

## Output

Write one file: `docs/autoboard/<slug>/manifest.md`

The manifest contains:
1. Config frontmatter (model, subagent models, verify command, dev-server, retries)
2. Sessions with tasks, dependencies, and complexity scores
3. QA gates at dependency layer boundaries

## Config Frontmatter

The manifest starts with YAML frontmatter that configures the orchestrator:

```yaml
---
model: opus                    # Model for session agents
qa-model: opus                 # Model for QA subagents
explore-model: haiku           # Model for Explore subagents
plan-review-model: opus        # Model for plan reviewer subagents
code-review-model: sonnet      # Model for code reviewer subagents
verify: npm install && npx tsc --noEmit && npm run build && npm test
dev-server: npm run dev        # Command to start dev server for browser QA
setup: npm run db:migrate      # Pre-run setup (optional, idempotent). Must use non-interactive flags — runs in headless sessions too.
qa-setup: npm run seed:test-data  # Commands to prepare environment for browser QA (optional, omit if not needed)
env-template: .env.example     # Path to env template file (optional, omit if not needed)
retries: 1                     # Max automatic retries per session
tracking-provider: none         # Set to 'github' for GitHub Projects V2 live tracking
skip-permissions: false        # Set true to use --dangerously-skip-permissions (default: false)
qa-mode: build-only            # build-only (default) or full (browser + build/test)
---
```

**`qa-mode`** — ask the user via AskUserQuestion which QA mode they want:

> **QA testing level for this project:**
> 1. **Full** — Browser integration tests + build/test. QA agents navigate the app, fill forms, verify UI. Requires a browser tool (gstack browse, Playwright MCP, or agent-browser) and a dev server. Best for web apps with UI.
> 2. **Build-only** (default) — Type check, build, and test suite only. No browser testing. Appropriate for CLIs, libraries, backend-only services, or when no browser tool is available.

Default to `build-only` if the user doesn't answer. This ensures the run completes even for CLI apps or projects without browser tooling.

Infer these fields from the design doc's tech stack:

**`setup`** — include if the design doc mentions databases, migrations, seed data, or managed backends. Omit the field entirely if not needed.

**`env-template`** — include if the design doc mentions API keys, database URLs, secrets, or third-party services. Set to `.env.example`. Omit the field entirely if not needed.

For non-npm projects:
```yaml
---
verify: cargo build && cargo test
dev-server: cargo run
---
```

## Task Record Format

Each task must include:

```markdown
### Task N: <Title>

- **Creates:** `file1.ts`, `file2.ts`
- **Modifies:** (none)
- **Depends on:** Task 1, Task 2
- **Requirements:**
  - First requirement
  - Second requirement
    - Sub-detail
  - Third requirement
- **Explore:**
  - How the auth middleware validates tokens — for inserting PII redaction at the right pipeline stage
  - What regex patterns exist — for detecting PII formats
- **TDD Phase:** `RED`, `GREEN`, `REFACTOR` (or Exempt)
- **Commit:** `task N: description`
- **Test approach:** `handler-level` | `unit` | `browser`
- **Key test scenarios:**
  - Happy path: {scenario}
  - Error path: {scenario}
  - Edge case: {scenario}
- **Complexity:** N
- **Effort:** low | medium | high | max
- **Suggested Session:** SN
```

**Test approach values:**
- `handler-level` — tests call the real handler/endpoint/API, exercising auth, validation, middleware, and error paths. Use for any task creating routes, endpoints, mutations, or service methods.
- `unit` — tests call functions directly. Use for pure utilities, validators, data transformations with no middleware or auth layer.
- `browser` — a QA gate signal, not a session TDD directive. The session agent still writes code-level tests (handler-level or unit) for its TDD cycle. The `browser` tag tells the QA gate to validate this task's key test scenarios via browser interaction. Use for tasks producing user-facing UI with critical flows identified in the design doc's `## Critical User Flows` section. Tasks marked `browser` cannot be `TDD: Exempt`.

**Key test scenarios** (required for all TDD tasks, strongly recommended for all others):

Each task should include specific test scenarios covering happy path, error paths, and edge cases. Derive these from the design doc's testing strategy and critical user flows.

```markdown
### Task N: <Title>
...
- **Key test scenarios:**
  - Happy path: {specific scenario and expected outcome}
  - Error path: {what breaks, expected error behavior}
  - Edge case: {boundary condition, expected handling}
```

Example:
```markdown
- **Key test scenarios:**
  - Happy path: valid email + password → account created, redirect to dashboard
  - Error path: duplicate email → "Email already registered" error, form preserved
  - Error path: weak password → validation error listing requirements
  - Edge case: email with leading/trailing whitespace → trimmed and accepted
```

## Rules

### Dependency Inference

Each task runs in an **isolated git worktree** that only contains code merged from its completed dependencies — nothing else exists.

- Honor explicit dependencies from the design doc
- Infer implicit dependencies: if Task B needs anything Task A produces to build, test, or run — files, packages, config, toolchains, project structure — B depends on A
- **The worktree test**: for each task with `Depends on: (none)`, ask: "Could this task's agent succeed in a worktree containing only the repo's current main branch?" If not, it has a missing dependency
- **Refactoring addendum**: for tasks that modify shared interfaces, also consider: "Do any tasks in other sessions consume the code being changed?" If so, those sessions depend on this one — even if they don't use its *output files*.
- Ensure topologically valid ordering (no circular deps)

### Backend Provisioning

When the tech stack includes a managed backend (Convex, Supabase, PlanetScale, Firebase, etc.), the scaffold session MUST include a task that provisions it — not just creates config files.

**Critical: session agents run non-interactively (`claude -p`).** They cannot answer prompts, select from menus, or interact with dashboards. All CLI commands in task requirements MUST use non-interactive flags. If a CLI blocks waiting for input, the session hangs forever.

**Two-phase provisioning:**

1. **Preflight (main agent)** — handles initial interactive setup. The verification preflight works with the user to provision each empty env var before sessions start. This includes backend project creation, API key generation, and any CLI commands that require user input.

2. **Session tasks** — handle non-interactive operations only. Schema pushes, migrations, seeding, verification. Check the CLI tool's `--help` for non-interactive flags and specify the exact headless command in the task requirements.

**Task requirements should:**
- Specify the exact CLI command with non-interactive flags (check `--help` for each tool)
- Push the initial schema/migrations
- Verify the backend is reachable
- Write the connection URL to `.env.local` (or equivalent)

**The `setup` frontmatter field** must also use non-interactive flags — the orchestrator runs it during preflight AND can re-run it between layers, so it must work headlessly every time.

### Explore Targets

For each task, write 2-4 purpose-driven exploration targets. Each target should explain WHAT to look for and WHY it matters for this task. Omit for scaffolding tasks on brand-new projects where there's nothing to explore. These targets are passed directly to the Explore subagent — they should be specific questions, not generic directory listings.

### TDD Inference
- **Default: TDD** for any task creating or modifying files with testable logic
- **Exempt only when**: Pure UI with no logic, config files, documentation, CLI entry points that only wire tested modules
- **When in doubt, mark TDD** — easier to exempt later than retrofit tests
- Override based on design doc specifications

### Complexity Scoring

Complexity measures **cognitive difficulty** - how hard you have to think, not how much work there is. A 200-line CRUD endpoint following an established pattern is low complexity. A 30-line race condition fix is high complexity.

**Fibonacci scale (1, 2, 3, 5, 8):**

| Score | Name | Anchor Example | What makes it this level |
|-------|------|---------------|--------------------------|
| 1 | **Rote** | Add a new field to an existing CRUD endpoint following the exact pattern of 5 existing fields | Zero novel decisions. Copy-paste-modify. |
| 2 | **Guided** | Implement a new API endpoint similar to existing ones, but with a custom validation rule | One or two novel decisions within a known pattern. |
| 3 | **Considered** | Build auth middleware integrating with an external provider, handling token refresh and error states | Multiple interacting concerns, but well-documented problem space. |
| 5 | **Tricky** | Fix a race condition between concurrent DB writes, or design a state machine for a multi-step workflow | Requires holding multiple interacting states in your head. Non-obvious failure modes. |
| 8 | **Novel** | Implement a custom conflict resolution algorithm for real-time collaborative editing | Requires inventing an approach. No established pattern to follow. |

**Key discriminator:** "If I gave this task to a competent developer with full codebase access, how long would they spend *thinking* before they started typing?" Rote = seconds. Guided = minutes. Considered = an hour. Tricky = half a day. Novel = days.

**Baseline anchoring:** Every manifest must identify one task as the **baseline** (complexity 2). This should be the most "standard" task - an endpoint, a component, a migration that follows an established pattern. All other tasks are scored *relative to this baseline*. Ask: "Is this task twice as hard to think about as the baseline? That's a 3. Does it have genuinely non-obvious failure modes? That's a 5."

**Distribution check:** After scoring all tasks, verify the distribution. If more than 40% of tasks score 5 or 8, re-examine each one against the baseline. Most real projects are 60-70% complexity 1-3 with a few genuinely hard ones. A top-heavy distribution signals the scorer is conflating effort with complexity.

### Effort Derivation

Effort is **derived from complexity**, not scored independently. The `--effort` flag controls the session agent's reasoning depth - cognitive difficulty is the right input, not volume of work.

| Complexity | Effort | With TDD |
|------------|--------|----------|
| 1 (Rote) | `low` | `medium` |
| 2 (Guided) | `medium` | `medium` |
| 3 (Considered) | `medium` | `medium` |
| 5 (Tricky) | `high` | `high` |
| 8 (Novel) | `max` | `max` |

**TDD bump:** TDD bumps effort only for Rote tasks (low -> medium) because TDD adds test-design thinking to otherwise zero-decision work. For complexity >= 2, TDD adds volume but not cognitive load - effort stays the same.

**Distribution:** `medium` is the workhorse tier for the majority of tasks. `high` is uncommon (only Tricky tasks). `max` is rare (only Novel tasks).

**Session effort** = max(derived effort) across all tasks in the session. This is what gets passed to the `--effort` flag.

### Session Grouping

One session = one agent = one worktree = sequential execution. There is no parallelism within a session. Group tasks that benefit from shared exploration context, not tasks that happen to be in the same dependency layer.

**Optimize for session quality first, parallelism second.** An agent with strong domain context makes better decisions, writes fewer defects, and produces better plan/code reviews. A cold-starting agent re-explores code its predecessor already understood. When grouping trades parallelism for context quality, prefer context quality — wall-clock speed is a secondary benefit, not the primary optimization target.

#### Grouping Criteria (in priority order)

1. **Correctness constraints**: Tasks with overlapping creates/modifies MUST share a session or have serialized sessions. Tasks within a session must be topologically ordered by their dependencies.

2. **Architectural domain cohesion**: Group by the set of abstractions a developer holds in their head to work in that area. The test: if Task B's `Explore` targets reference files that Task A creates, they belong together. Examples:
   - **Greenfield**: "data layer" (types + schema + queries), "auth" (crypto + tokens + middleware), "API routes for resource X", "UI for feature Y"
   - **Modifying existing code**: group by the existing module boundary, not by the new feature's layers. For refactoring a shared module, group the extraction + all consumers that need updating into one session (or make consumers depend on the extraction session). For migration tasks, group by phase — schema migration → code update → backfill → cleanup.

3. **Parallelism is secondary to domain cohesion**: When tasks share a domain, group them even if it sacrifices some parallelism. Only keep parallel tasks in separate sessions when they are in **different** domains. The decision test: if merging two parallel sessions doesn't increase the total number of dependency layers (because downstream tasks already wait for the later one), the parallelism loss is cosmetic — merge and get better context. Maximize file independence between parallel sessions that remain separate to avoid file-conflict serialization at runtime.

4. **Session size caps** — hard limits to keep agents within ≤55% of context window:
   - **Total complexity ≤ 8** (raw Fibonacci scores, no modifiers). This keeps sessions at ≤55% context utilization. A session MAY reach 10 when all tasks share a tight domain and the manifest explicitly notes it as a high-context session with justification — but never above 10.
   - **Max 4 tasks per session** (5+ only when all tasks are complexity ≤2 in one narrow domain)
   - **Max 1 task with complexity ≥5 per session**
   - **Max 3 TDD tasks per session** (TDD doubles exploration/verification cycles)

5. **Dependency chain grouping**: Strict chains (A→B→C with no fan-out from intermediate nodes) belong in one session ONLY when all tasks share the same domain AND similar complexity levels. Split chains at:
   - **Complexity boundaries** (going from 1-2 to 5+ is a natural split)
   - **Domain transitions** (scaffolding → business logic → API wiring)
   - **Multi-consumer enablers** (tasks that unblock 3+ downstream tasks) should be fast standalone sessions so dependents can start ASAP — e.g., shared types, scaffolding, config
   - **Single-consumer enablers** (tasks that only unblock one downstream task) should merge with their consumer — the agent gets context from building the enabler, and no other task is waiting — e.g., crypto utils that only feed into auth

6. **Failure blast radius**: If a session fails at task N, tasks N+1... in that session are lost work. Group tasks where this loss is proportionate. Don't put a complexity-1 task before a complexity-5 task in the same session if the complex task's failure would waste the simple task's clean completion.

#### Anti-Patterns

| Do NOT | Why | Instead |
|--------|-----|---------|
| 1:1 task-to-session mapping | N worktrees + N merges + N cold-starts, no context reuse | Group by domain |
| Group by dependency layer | A layer may contain auth + UI + data tasks that share nothing | Group by architectural domain |
| Merge unrelated parallel tasks | Agent wastes context switching domains | Keep separate sessions |
| Split strict same-domain dep chains | Re-explores everything the previous session already explored | One session for the chain |
| Ignore file conflicts between parallel sessions | Runtime merge conflicts force serialization | Colocate or add dependency |
| Over-index on parallelism | Keeps domain-cohesive tasks separate when the critical path doesn't change. Agents cold-start and re-explore | Merge same-domain tasks; accept minor parallelism loss for better context |

#### Session Table Format

The sessions table must show task complexities (Fibonacci), effort, domain label, and rationale:

```markdown
| Session | Tasks | Complexity | Domain | Effort | Rationale |
|---------|-------|-----------|--------|--------|-----------|
| S1 | T1 (2), T2 (3) | 5 | Data layer | medium | Sequential chain, shared schema context |
| S2 | T3 (1) | 1 | Auth | medium | Rote endpoint, TDD bumps low->medium |
| S3 | T4 (5) | 5 | Payments | high | Race condition in concurrent writes |
```

**Session effort:** max(derived effort) across all tasks in the session. Derived effort uses the complexity-to-effort mapping above. Users can override per-session. Valid effort values: `low`, `medium`, `high`, `max`.

### Architectural Foundations

After drafting all tasks, scan for cross-session shared needs:

1. **Shared utility detection.** Compare Creates/Modifies fields across sessions. If 2+ sessions in different layers will create similar functionality (auth wrappers, error handlers, validation helpers, API clients, shared UI components), extract a foundation task in an earlier-layer session. The foundation task's Creates field lists the utility's file path; its Requirements specify the public API. Downstream tasks depend on this session and reference the utility by path — they do NOT recreate it.

2. **Convention seeding.** The first session in Layer 0 that touches a concern area (error handling, API responses, file organization) must include in its task Requirements: the specific pattern to follow. Example: "All mutation handlers use the `authenticatedMutation` wrapper from `convex/lib/auth.ts` — do not use raw `mutation()` with manual auth checks." Downstream sessions' Explore targets include: "Check the patterns established by S{N} for {concern area}."

3. **Security parity.** If any task requires auth middleware, rate limiting, or input validation, check all tasks creating similar endpoints/routes. Add to each affected task's Requirements: "Apply the same {security pattern} as T{N} — see S{M} for the established pattern."

### QA Gate Placement

QA gates are checkpoints where the orchestrator validates that the merged work is correct before proceeding. They are NOT sessions — the orchestrator runs them directly (build validation + browser smoke tests).

#### When to place QA gates

- **Flat dependency graph** (all sessions independent): No mid-pipeline gates needed. The orchestrator runs a final QA after all sessions merge.
- **Layered dependency graph** (later sessions depend on earlier ones): Place QA gates at layer boundaries — after a group of sessions completes and before the next group starts.

#### Gate rules

1. **Layer-boundary gates**: After each dependency layer where integration risk is high, insert a QA gate. Not every layer boundary needs one — use judgment about where compound errors are most likely.

2. **Blocking pattern**: Sessions after a QA gate cannot start until the gate passes. This is enforced by the dependency graph — sessions in Layer N+1 depend on sessions in Layer N, and the QA gate sits between them.

3. **Final QA**: The orchestrator always runs a final QA gate after all sessions complete, regardless of whether the manifest marks one.

4. **Don't over-gate.** A 6-session project with 2 dependency layers needs at most 1 mid-pipeline gate + 1 final gate. Don't add gates between every pair of sessions.

#### QA gate format in manifest

Place QA gates as horizontal rule markers between session definitions. Each gate includes **acceptance criteria** — testable conditions that the QA agent must verify via browser interaction. Derive these from what the preceding layers build.

```markdown
## Session S1: Monorepo scaffold
...

## Session S2: Domain types
**Depends on:** S1
...

---
**QA Gate** — Foundation layer complete.
Acceptance criteria:
- App builds and all tests pass
- User can create an account with email/password
- User can log in and see the dashboard
- Backend API calls succeed (no 500 errors in console)
---

## Session S3: Database layer
**Depends on:** S2
...
```

#### Acceptance criteria rules

1. **Every user-facing feature** in the preceding layers must have at least one criterion
2. **Test COMPLETE FLOWS, not isolated actions:**
   - BAD: "User can sign up" (tests one step, misses what happens after)
   - GOOD: "User can sign up with email/password → is redirected to the dashboard → dashboard renders with the correct layout and content"
3. **Include at least one "golden path"** that walks through the primary use case end-to-end across multiple features
4. **Include negative cases** for security-critical flows (invalid login rejects, unauthorized access redirects, rate limiting)
5. If `qa-mode` is `build-only`, acceptance criteria are still written but are verified via test output, not browser interaction
6. For sessions that modify existing interfaces, criteria must verify existing consumers still work — not just that new functionality was added

7. **Criteria must be testable at the gate boundary.** If a feature's UI is built in a later layer, don't write browser-interaction criteria for it at this gate. Test the backend via unit/integration test output instead. Defer UI-interaction criteria to the gate after the UI layer.

The QA agent also regression-tests existing features using the design doc — acceptance criteria only cover what's new in this layer.

#### Example: Layered graph with gates

```
S1[T1, T2], S2[T3] (parallel sessions)
    ↓
--- QA Gate: Foundation validation ---
    Acceptance: signup works, login works, dashboard renders
    ↓
S3[T4], S4[T5] (parallel sessions, depend on S1+S2)
    ↓
--- QA Gate: Integration validation ---
    Acceptance: documents CRUD works, annotations save, search returns results
    ↓
S5[T6, T7] (depends on S3+S4)
    ↓
--- Final QA (always, run by orchestrator) ---
    Acceptance: all features from design doc work end-to-end
```

### Required Manifest Sections

The manifest must include:
1. Config frontmatter (model, verify, dev-server, retries)
2. Title + design doc reference
3. Tech stack table
4. Testing strategy
5. TDD discipline summary
6. Session definitions with task entries
7. Task dependency graph (ASCII art)
8. Execution layers (which sessions run in parallel, which are sequenced)
9. QA gates at appropriate layer boundaries
10. TDD tasks table
11. Security checklist
12. Sessions table (task assignments, complexity totals, domains, rationale)

### Quality Contract
- All tasks inherit quality standards injected via the agent brief: code elegance, DRY, security, performance, TDD discipline, code organization, testing thoroughness, debugging ease, and cleanup culture
- TDD tasks must follow strict RED → GREEN → REFACTOR with verification at each step
- All tasks must pass the verification command before merge
- Review gates (plan review + code review) are mandatory and blocking
- No need to repeat the contract per-task — it is injected automatically

### Session Permissions

Generate `docs/autoboard/{slug}/session-permissions.json` alongside the manifest. This file controls what tools **spawned session agents** can use — it does NOT affect your main Claude Code agent or the orchestrator. Sessions run in `dontAsk` mode, so unlisted tools are auto-denied (no hanging on permission prompts).

**Generation logic:**

1. Start with the allow list (always included):
   - Tools: `Read`, `Edit`, `Write`, `Glob`, `Grep`, `Agent`, `Skill`, `NotebookEdit`, `WebFetch`, `WebSearch`, `ToolSearch`, `mcp__*`
   - Task management: `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`, `TaskOutput`, `TaskStop`
   - Planning: `EnterPlanMode`, `ExitPlanMode`
   - Language server: `LSP`
   - Bash: `Bash(*)` — allow all shell commands (deny list catches dangerous ones; granular Bash patterns don't work because agents chain commands with `&&`, `cd`, pipes)

2. No per-project Bash customization needed — `Bash(*)` covers everything.

4. Apply the standard deny list (always included):
   - `Bash(git push*)` — only the orchestrator pushes
   - `Bash(git reset --hard*)` — destroys uncommitted work
   - `Bash(git checkout .)` — discards all changes
   - `Bash(git restore .)` — discards all changes
   - `Bash(git clean *)` — deletes untracked files
   - `Bash(sudo *)` — no system-level access
   - `Bash(rm -rf /)`, `Bash(rm -rf ~)`, `Bash(rm -rf /*)` — catastrophic deletion
   - `Read(./.env)`, `Read(./.env.*)`, `Read(./secrets/**)` — protect secrets

5. Write as `docs/autoboard/{slug}/session-permissions.json` with `"defaultMode": "dontAsk"` as a **top-level key** (NOT nested inside `"permissions"`). Claude Code requires `defaultMode` at the root of the settings object.

Users can edit this file after generation to add or remove rules.

### Environment Template

If the manifest's `env-template` field is set (e.g., `env-template: .env.example`), generate the template file alongside the manifest. This ensures the preflight can copy it to `.env.local` for the user to fill in.

Parse the design doc for environment variables needed by the project — API keys, database URLs, third-party service credentials, feature flags. Write them as empty placeholder values:

```
# Generated by autoboard task-manifest — fill in real values before /run
# See design doc for details on each variable

DATABASE_URL=
API_KEY=
```

Rules:
- Only generate if `env-template` is set in the manifest frontmatter
- Parse variable names from the design doc's tech stack, API integrations, and service dependencies
- Use empty values (not example values) — the user fills in real credentials
- Add a comment header explaining the file's purpose
- If the template file already exists, do NOT overwrite it

## Architect Review Loop

After generating the manifest:
1. Dispatch the `autoboard:plan-reviewer` agent via the Agent tool (max 3 rounds). Include the manifest content and design doc path in the prompt, and instruct the reviewer to focus on these manifest-specific criteria:
   - **QA acceptance criteria thoroughness** — do criteria test complete flows (signup -> redirect -> dashboard), not isolated actions ("user can sign up")? Do they include negative cases for security-critical flows? Does every user-facing feature from the design doc have at least one criterion?
   - **Dependency correctness** — apply the worktree test to every task. Would this task's agent succeed in a worktree containing only the repo's current main branch plus its completed dependencies? Are implicit dependencies captured (shared types, config, toolchains)?
   - **Session sizing** — are complexity caps respected (raw Fibonacci sum <= 8, max 4 tasks, max 1 task with complexity >= 5, max 3 TDD tasks)? Is effort correctly derived from complexity (1->low, 2/3->medium, 5->high, 8->max, with TDD bumping only Rote tasks low->medium)? Does the complexity distribution pass the 40% check (no more than 40% of tasks at 5+)?
   - **Session grouping quality** — domain cohesion over parallelism? No 1:1 task-to-session anti-pattern? Cross-session file independence (no overlapping creates/modifies without serialization)?
   - **QA gate placement** — gates at the right layer boundaries? Not over-gated? Acceptance criteria testable at the gate boundary (not testing UI before the UI layer ships)?
   - **Architectural foundations** — shared utilities extracted to early-layer foundation tasks? Convention seeding in first sessions? Security parity across similar endpoints?
   - **Test scenario coverage** — key test scenarios cover error paths and edge cases, not just happy paths? Browser-tagged tasks are non-exempt from TDD? Scenarios reference the design doc's critical user flows?
   - **Explore target quality** — are explore targets purpose-driven questions, not generic directory listings? Do they explain what to look for and why?
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

Then ask about GitHub Projects tracking (via AskUserQuestion). Present Yes and No as equal options — do NOT mark either as recommended:
> Would you like to track progress on a GitHub Project board?
> This creates a kanban board with live status updates as sessions run.
> Requires the GitHub CLI (`gh`) to be installed and authenticated.

If yes:
1. Run `gh auth status` to check if the CLI is available and authenticated
2. If `gh` is not found or not authenticated: warn the user and leave `tracking-provider: none`. They can set it to `github` after installing/authenticating `gh`.
3. If `gh` is available and authenticated:
   a. Check for a remote: `gh repo view --json nameWithOwner -q .nameWithOwner`
   b. If no remote exists, create one and push:
      ```bash
      gh repo create {project-name} --private --source=. --push
      ```
      Use the project directory name as the repo name. Create as private by default.
   c. If a remote exists but the current branch hasn't been pushed: `git push -u origin HEAD`
   d. Update `tracking-provider` to `github` in the manifest

If no (or default): leave `tracking-provider: none`, no further action.

**Generate environment template** — If the manifest's `env-template` field is set (e.g., `env-template: .env.example`) AND the template file does NOT already exist, generate it NOW before running preflight. Parse the design doc for all environment variables the project needs (API keys, database URLs, third-party credentials, feature flags) and write them as empty placeholders. See [Environment Template](#environment-template) for format and rules. This is YOUR job — do NOT defer to T1 or any session.

Then run a preflight check by invoking `/autoboard:verification --preflight` via the Skill tool. This reads the just-written `manifest.md` for config (env-template, dev-server, etc.), detects available browser tools, and copies `.env.example` to `.env.local` if needed. At this stage, preflight is advisory — it tells the user what to set up but doesn't block.

Then prompt:
> Manifest written to `docs/autoboard/<slug>/manifest.md`.
>
> Next step: Run `/autoboard:run <slug>` to start the build. It will walk you through env var setup before launching sessions.
