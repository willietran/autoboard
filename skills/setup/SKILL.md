---
name: setup
description: Resolve project, parse manifest, run preflight checks, and display execution plan. Invoked once at the start of every run.
---

# Setup

**You are the orchestrator running `/autoboard:run`.** This is your setup phase — not a delegated task. When these steps complete, you continue executing `/autoboard:run` Step 2. There is no handoff — you ARE the orchestrator.

---

## Step 1: Resolve Project

Resolve the project path from the argument:
- If a slug is provided: `docs/autoboard/<slug>/`
- If a full path is provided: use it directly

Verify git prerequisites:
1. Run `git rev-parse --git-dir` — if it fails, initialize: `git init && git add -A && git commit -m "Initial commit"`
2. Run `git log -1` — if it fails (no commits): `git add -A && git commit -m "Initial commit"`

Ensure you're on the feature branch:
```bash
git checkout autoboard/<slug>
```
If it doesn't exist, something went wrong during brainstorm — create it:
```bash
git checkout -b autoboard/<slug>
```

Check for required files:
1. `manifest.md` exists — proceed to Step 2
2. `design.md` exists but no `manifest.md` — tell the user to run `/autoboard:task-manifest <slug>` first
3. Neither exists — tell the user to run `/autoboard:brainstorm` first

---

## Step 2: Parse Manifest

Read `manifest.md`. Extract:

### Config Frontmatter

The manifest starts with YAML frontmatter:
```yaml
---
model: opus                    # Model for session agents
qa-model: sonnet               # Model for QA subagents
explore-model: haiku           # Model for Explore subagents
plan-review-model: sonnet      # Model for plan reviewer subagents
code-review-model: sonnet      # Model for code reviewer subagents
verify: npm install && npx tsc --noEmit && npm run build && npm test
dev-server: npm run dev        # Command to start dev server for browser QA
setup: npm run db:migrate      # Pre-run setup commands (optional, must be idempotent — runs before each layer)
qa-setup: npm run seed:test-data  # Commands to prepare environment for browser QA (optional)
env-template: .env.example     # Path to env template file (optional)
retries: 5                     # Max retries per session (default: 5, per-session not global)
tracking-provider: github      # Tracking provider: 'github' or 'none' (default: none)
github-project: false          # Legacy field — equivalent to tracking-provider: github
qa-mode: build-only            # build-only (default) or full (browser + build/test)
max-parallel: 4                # Max concurrent sessions per layer (default: 4)
skip-permissions: false        # Skip session permission scoping (default: false)
---
```

For backward compatibility: `github-project: true` is treated as `tracking-provider: github`.

### Sessions

Each session is marked with `## Session S<N>: <focus>` and contains:
- `**Depends on:**` — list of session IDs this session requires
- `**Tasks:**` — task list with complexity scores and TDD phases

### QA Gates

QA gates are marked between horizontal rules:
```markdown
---
**QA Gate** — <description>. Run: <what to validate>.
---
```

### Layer Graph

Build a dependency layer graph from sessions and QA gates:
- **Layer 0:** Sessions with no dependencies
- **Layer 1:** Sessions whose dependencies are all in Layer 0
- **Layer N:** Sessions whose dependencies are all in Layers 0..N-1
- **QA gates** are layer boundaries — all sessions before a QA gate must complete before sessions after it can start

---

## Step 3: Preflight Checks

Now that the manifest is parsed and config is available, run preflight checks.

Invoke `/autoboard:verification --preflight` via the Skill tool to run environment readiness checks. This detects browser tools, checks env vars, creates `.env.local` from templates if needed, and smoke-tests the dev server.

After preflight reports, resolve any issues before proceeding:

1. **Auto-generatable values** — generate them immediately (e.g., `openssl rand -base64 32` for encryption keys).
2. **Empty env vars requiring interactive provisioning** — fill them now. You have full interactive access; session agents don't. Either provision directly or ask the user to run the interactive command.
3. **Setup command failure** — diagnose and fix before proceeding.

### Env var triage

After resolving auto-generatable and interactively-provisionable vars, if any env vars are still empty, ask the user to triage each one:

> **Empty environment variables detected:**
> - `GOOGLE_CLIENT_ID` (empty)
> - `GOOGLE_CLIENT_SECRET` (empty)
> - `STRIPE_SECRET_KEY` (empty)
>
> For each, tell me:
> 1. **Fill it now** — I'll help you provision it
> 2. **Skip for now** — features depending on this won't be QA-tested (I'll mark related criteria as expected skips)
> 3. **Not needed** — this var isn't used by the current project

For vars marked "skip for now", append an `expected-skips` section to the manifest:
```yaml
expected-skips:
  - var: GOOGLE_CLIENT_ID
    features: ["Google OAuth login", "Google profile sync"]
  - var: STRIPE_SECRET_KEY
    features: ["Payment processing", "Subscription management"]
```

QA acceptance criteria that depend on these features will be marked `EXPECTED SKIP` — they don't fail the gate. All other criteria must still pass.

### Auth provider detection

Only run this if `qa-mode: full` — auth detection only matters for browser smoke tests. If `qa-mode: build-only`, skip entirely.

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

**If no auth detected:** Skip. No frontmatter changes needed.

**If auth detected, ask the user** via AskUserQuestion:

> **Auth provider detected: {provider}**
>
> Browser smoke tests need to log in. Email verification blocks agents (they can't check inboxes).
>
> How should test users be created?
> 1. **Admin API** — set up `qa-setup` to create a pre-confirmed test user via the provider's admin API
> 2. **Auto-confirm enabled** — email confirmation is disabled in dev, no special handling needed
> 3. **Pre-verified credentials** — you'll provide a test email/password that already works
> 4. **Custom** — describe your approach

**Process the user's choice:**

- **Admin API:** Ask for test email and password. Update `qa-setup` in the manifest to include a script that creates a pre-confirmed user via the provider's admin API (e.g., Supabase: `auth.admin.createUser({ email, password, email_confirm: true })`). Add `auth-strategy: admin-api` and `test-credentials` to the manifest frontmatter.
- **Auto-confirm:** Ask for test email and password. Add `auth-strategy: auto-confirm` and `test-credentials` to the manifest frontmatter.
- **Pre-verified:** Ask for the credentials. Add `auth-strategy: pre-verified` and `test-credentials` to the manifest frontmatter.
- **Custom:** Record the user's description. Add `auth-strategy: custom` and `auth-notes` to the manifest frontmatter. The user is responsible for ensuring `qa-setup` handles it.

Update the manifest file with the new frontmatter fields.

### qa-mode validation

If `qa-mode: full` in the manifest, validate prerequisites:

```
qa-mode: full requires:
  ✓ Browser tool (Playwright MCP or agent-browser) — {detected/MISSING}
  ✓ Dev server configured — {configured/MISSING}
  ✓ All non-skipped env vars filled in — {N empty}

If any prerequisites are missing, QA gates will FAIL with an infrastructure
error that no fixer agent can resolve. The entire run will be BLOCKED at the
first QA gate until you resolve it. No sessions after that gate will execute.
```

If prerequisites are missing, ask the user: proceed with `full` (accepting the risk of blocking) or switch to `build-only`?

### Task overlap cleanup

If resolving any of the above overlaps with a task in the manifest (e.g., T1 was supposed to "provision Convex backend" but you just did it), update the manifest to remove or simplify that task so the session agent doesn't redo the work.

---

## Step 4: Display Execution Plan

Report the execution plan to the user:
```
Execution Plan:
  Layer 0: S1, S2, S3 (parallel)
  QA Gate: Foundation validation
  Layer 1: S4, S5 (parallel, depend on Layer 0)
  QA Gate: Integration validation
  Layer 2: S6 (depends on Layer 1)
  Final QA

  Total: 6 sessions, 3 layers, 2 QA gates
  Model: opus | QA: sonnet | Explore: haiku | Plan Review: sonnet | Code Review: sonnet
```

Setup is complete. You now have the parsed manifest, layer graph, and config. Continue executing `/autoboard:run` — your next step is Step 2 (Load Tracking Provider). Do not stop, do not "return to orchestrator" — you are the orchestrator.
