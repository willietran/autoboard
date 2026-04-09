---
name: setup
description: Resolve project, parse manifest, run preflight checks, and display execution plan. Invoked once at the start of every run.
---

# Setup

**You are the lead running `/autoboard:run`.** This is your setup phase - not a delegated task. When these steps complete, you continue executing `/autoboard:run` Step 2. There is no handoff - you ARE the lead.

---

## Step 1: Resolve Project and Verify Environment

Resolve the project path from the argument:
- If a slug is provided: `docs/autoboard/<slug>/`
- If a full path is provided: use it directly

**Agent Teams flag check:**
```bash
[[ "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" == "1" ]] && echo "OK: Agent Teams enabled" || echo "FAIL: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS must be set to 1"
```
If not set, stop and tell the user to set the flag before running autoboard.

**Git prerequisites:**
1. Run `git rev-parse --git-dir` - if it fails, initialize: `git init && git add -A && git commit -m "Initial commit"`
2. Run `git log -1` - if it fails (no commits): `git add -A && git commit -m "Initial commit"`

**Feature branch checkout:**
```bash
git checkout autoboard/<slug>
```
If it doesn't exist, something went wrong during brainstorm - create it:
```bash
git checkout -b autoboard/<slug>
```

**Required files:**
1. `manifest.md` exists - proceed to Step 2
2. `design.md` exists but no `manifest.md` - tell the user to run `/autoboard:task-manifest <slug>` first
3. Neither exists - tell the user to run `/autoboard:brainstorm` first

---

## Step 2: Parse Manifest

Read `manifest.md`. Extract:

### Config Section

The manifest contains a `## Config` section with key-value pairs. Parse all fields:

**Required:** `feature`, `branch`, `verify-command`

**Optional with defaults:**
| Field | Default |
|---|---|
| `setup-command` | none |
| `dev-server` | none |
| `default-teammate-model` | sonnet |
| `opus-threshold` | 5 |
| `opus-effort-map` | `5: high`, `8: max` |
| `max-batch-size` | 5 |
| `qa-mode` | build |
| `planning-model` | opus |
| `plan-review-model` | sonnet |
| `code-review-model` | sonnet |
| `qa-model` | sonnet |
| `cohesion-model` | sonnet |

### Tasks

Each task is marked with `### T<N>: <title>` and contains fields: `creates`, `modifies`, `depends-on` (task IDs or `none`), `requirements`, `key-test-scenarios`, `complexity` (1/2/3/5/8), `commit-message`, and optional `model` override.

### Dependency Layers

Compute layers from the `depends-on` fields:
- **Layer 1:** All tasks with `depends-on: none`
- **Layer 2:** All tasks whose dependencies are all in Layer 1
- **Layer 3:** All tasks whose dependencies are all in Layers 1-2
- etc.

### Batch Sizing

When a layer exceeds `max-batch-size`, split it into batches. Each batch gets its own planning and code review cycle. All tasks within a layer still implement in parallel - batching only affects planning and review scope.

### QA Gates

QA gates are marked with `### After Layer <N>` or `### Final` under `## QA Gates`. Build verification runs after every layer regardless. Lines with `functional: true` indicate browser/E2E testing should run for that gate. Extract the criteria list for each gate.

---

## Step 3: Preflight Checks

### Verification preflight

Invoke `/autoboard:verification --preflight` via the Skill tool to run environment readiness checks. This detects browser tools, checks env vars, creates `.env.local` from templates if needed, and smoke-tests the dev server.

After preflight reports, resolve any issues before proceeding:

1. **Auto-generatable values** - generate them immediately (e.g., `openssl rand -base64 32` for encryption keys).
2. **Empty env vars requiring interactive provisioning** - fill them now. You have full interactive access; teammates don't. Either provision directly or ask the user to run the interactive command.
3. **Setup command failure** - diagnose and fix before proceeding.

### Env var triage

After resolving auto-generatable and interactively-provisionable vars, if any env vars are still empty, ask the user to triage each one:

> **Empty environment variables detected:**
> - `GOOGLE_CLIENT_ID` (empty)
> - `GOOGLE_CLIENT_SECRET` (empty)
>
> For each, tell me:
> 1. **Fill it now** - I'll help you provision it
> 2. **Skip for now** - features depending on this won't be QA-tested (I'll mark related criteria as expected skips)
> 3. **Not needed** - this var isn't used by the current project

For vars marked "skip for now", append an `expected-skips` section to the manifest config:
```
expected-skips:
  - var: GOOGLE_CLIENT_ID
    features: Google OAuth login, Google profile sync
  - var: STRIPE_SECRET_KEY
    features: Payment processing, Subscription management
```

QA acceptance criteria that depend on these features will be marked `EXPECTED SKIP` - they don't fail the gate.

### Auth provider detection

Only run this if `qa-mode: full` - auth detection only matters for browser/E2E tests. If `qa-mode: build`, skip entirely.

**Scan for auth providers.** Use Grep/Glob to detect auth setup in the project:

| Provider | Detection signals |
|---|---|
| Supabase | `@supabase/supabase-js` in package.json, `supabase/config.toml` |
| Firebase | `firebase/auth` in package.json |
| Clerk | `@clerk/nextjs` or `@clerk/clerk-react` in package.json |
| Auth0 | `@auth0/nextjs-auth0` or `@auth0/auth0-react` in package.json |
| NextAuth/Auth.js | `next-auth` in package.json |
| Lucia | `lucia` in package.json |
| Custom | `bcrypt`/`argon2` in package.json with signup/login route files |

**If no auth detected:** Skip. No config changes needed.

**If auth detected, ask the user:**

> **Auth provider detected: {provider}**
>
> Browser smoke tests need to log in. Email verification blocks agents (they can't check inboxes).
>
> How should test users be created?
> 1. **Admin API** - set up `setup-command` to create a pre-confirmed test user via the provider's admin API
> 2. **Auto-confirm enabled** - email confirmation is disabled in dev, no special handling needed
> 3. **Pre-verified credentials** - you'll provide a test email/password that already works
> 4. **Custom** - describe your approach

Process the user's choice and update the manifest config with `auth-strategy` and `test-credentials` (or `auth-notes` for custom).

### qa-mode validation

If `qa-mode: full` in the manifest, validate prerequisites:

```
qa-mode: full requires:
  Browser tool (gstack browse, Playwright MCP, or agent-browser) - {detected/MISSING}
  Dev server configured - {configured/MISSING}
  All non-skipped env vars filled in - {N empty}

If any prerequisites are missing, QA gates will FAIL with an infrastructure
error that no fixer agent can resolve. The entire run will be BLOCKED at the
first functional QA gate until you resolve it.
```

If prerequisites are missing, ask the user: proceed with `full` (accepting the risk of blocking) or switch to `build`?

### Browser tool selection

Only run this if `qa-mode: full`. Read the preflight results for detected browser tools.

- **`browser-tool` already set in manifest:** Skip.
- **0 detected:** Already handled by qa-mode validation (MISSING).
- **1 detected:** Set `browser-tool: <tool-id>` in the manifest config automatically.
- **>1 detected:** Ask the user which tool QA gates should use.

### Test baseline capture

Run the verify command and capture any pre-existing test failures as the baseline:

```bash
# Run from the project root on the feature branch
<verify-command> 2>&1 | tail -100 > /tmp/autoboard-<slug>-baseline-output.txt
echo $? > /tmp/autoboard-<slug>-baseline-exit.txt
```

If the verify command fails, write the failing test names and error summary to `docs/autoboard/<slug>/test-baseline.md`. This file tells teammates and QA subagents which failures existed before autoboard started, so they don't waste time fixing pre-existing issues.

If the verify command passes, write `No pre-existing test failures.` to `test-baseline.md`.

### Task overlap cleanup

If resolving any of the above overlaps with a task in the manifest (e.g., T1 was supposed to "provision backend" but you just did it), update the manifest to remove or simplify that task so a teammate doesn't redo the work.

---

## Step 4: Display Execution Plan

Report the execution plan to the user:
```
Execution Plan:
  Layer 1: T1, T2, T3, T4 (4 tasks, parallel)
    Batch 1: T1, T2, T3 (3 tasks)
    Batch 2: T4 (1 task)
  QA Gate: After Layer 1 (build-only)
  Layer 2: T5, T6 (2 tasks, parallel)
  QA Gate: After Layer 2 (functional)
  Layer 3: T7 (1 task)
  Final QA (functional)

  Total: 7 tasks, 3 layers, 2 mid-layer QA gates
  Models: Planning=opus | Teammates=sonnet (opus for complexity 5+)
  Max batch size: 5
```

Show batches only for layers that exceed `max-batch-size`. Show "(build-only)" or "(functional)" based on whether the QA gate has `functional: true`.

Setup is complete. You now have the parsed manifest, dependency layers, batch assignments, and config. Continue executing `/autoboard:run` - your next step is Step 2 (layer execution). Do not stop, do not "return to lead" - you are the lead.
