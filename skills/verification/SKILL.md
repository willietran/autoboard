---
name: verification
description: Verification protocol — invoke before running verify commands. Enforces evidence-based verification with max 3 attempts. No completion claims without fresh evidence.
---

# Verification

Unified QA skill with three modes. Check the `args` passed when this skill was invoked:

- **No args (default):** Light mode — run build/test verification only. Jump to [Light Mode](#light-mode).
- **`--full`:** Full mode — build/test + dev server + browser smoke tests. Jump to [Full Mode](#full-mode).
- **`--preflight`:** Readiness check — detect tools, check env, validate dev server. Jump to [Preflight Mode](#preflight-mode).

---

## The Iron Law

No completion claims without fresh verification evidence. If you haven't run the command in this phase, you cannot claim it passes.

## Red Flags — STOP

- Using "should pass", "probably works", "seems fine"
- Expressing satisfaction before running commands
- Running commands without reading output
- Claiming success from a prior run (must be fresh in THIS phase)

## Evidence Pattern

Good: `[run tsc] -> "exit 0, 0 errors" -> [run build] -> "exit 0" -> [run test] -> "47/47 pass" -> "All verification passes"`
Bad: `"Tests should pass now"` / `"I fixed it so it works"`

---

## Light Mode

Default mode. Run the verify commands from your session brief or manifest config.

### Verification Loop (max 3 attempts)

For each attempt:

1. Run each verification step separately and read full output.
   Typical steps (run in this order):
   - Lint (e.g., `npm run lint` or `npx eslint .`) — check for a `lint` script in `package.json` or for eslint config files (`.eslintrc*`, `eslint.config.*`). For non-JS projects, check equivalents (`cargo clippy` for Rust, `ruff` for Python). If no linter is configured, skip and report "Lint: skipped (no lint configuration detected)". Lint runs independently of the manifest's `verify` command — auto-detect and run even if the verify command doesn't include it.
   - Type check (e.g., `npx tsc --noEmit`) — read stderr, check exit code
   - Build (e.g., `npm run build`) — read output, check exit code
   - Test (e.g., `npm test`) — read output, count pass/fail, check exit code

2. After ALL steps pass: state the results with evidence
   (e.g., "tsc: exit 0, no errors. build: exit 0. tests: 47/47 pass.")

3. If ANY command fails:
   - Read the full error output
   - Diagnose the root cause
   - **Check the baseline**: if this test failure existed in the baseline (captured by preflight before any sessions ran), note it as pre-existing but do not count it as a session failure
   - Fix new issues only
   - Increment attempt counter and re-run ALL commands (not just the failing one)

4. After 3 failed attempts: describe the blocker, commit what works,
   and exit with a clear failure description.

### Verify All

Run ALL commands and re-run ALL commands if you fix something. Never re-run just one.

### Report

```
Verification Results:
  Build (lint, tsc, build, test): PASS
```

Or on failure:
```
Verification Results:
  Build (lint, tsc, build, test): FAIL — {error summary}
  Attempts: 3/3 exhausted
  Blocker: {description}
```

---

## Full Mode

Runs light mode first, then browser-based smoke testing. Typically invoked by a cold-start QA subagent with no prior session context — you discover routes by exploring the rendered page, not from prior knowledge.

Check the `qa-mode` from your configuration:
- **`qa-mode: full`** — browser testing is mandatory. If it can't run, the gate FAILS.
- **`qa-mode: build-only`** — skip Step 2 and Step 3 entirely. Only run Light Mode.

### Step 1: Run Light Mode

Run the full [Light Mode](#light-mode) verification loop above. If it fails after 3 attempts, stop here — no point browser-testing a broken build. Report the light mode failure and exit.

If `qa-mode: build-only`, stop here after light mode passes. Report the build/test results and exit — no browser testing.

### Step 2: Select Browser Tool (qa-mode: full only)

**If `browser-tool` is set in the manifest** → use that tool. The user (or setup skill) already chose it. Verify it's available: for CLI tools, check the binary exists or is on PATH; for MCP tools, check the tools list. If it's not available, report **FAIL** — "browser-tool is set to '{value}' but that tool was not found."

**If `browser-tool` is not set** → auto-detect available tools. Run all checks, collect the full list:

| Tool | Detection |
|------|-----------|
| gstack browse | `test -x "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/skills/gstack/browse/dist/browse"` (project-local) or `test -x ~/.claude/skills/gstack/browse/dist/browse` (global). |
| Playwright MCP | `mcp__plugin_playwright_playwright__browser_navigate` in available tools |
| agent-browser | `which agent-browser` returns 0 |

Then select:
- Exactly 1 detected → use it.
- Multiple detected → use whichever you judge best. (The setup skill normally resolves this interactively and stores the choice, but if it wasn't stored, proceed with your judgment.)
- 0 detected → report **FAIL** — "No browser tool available. qa-mode is 'full' but no browser tool was detected. Install one or switch to qa-mode: build-only." Do NOT ask the user (QA subagents run headless — AskUserQuestion will hang). Do NOT skip browser tests and continue.

The auto-detect table covers known tools. If the user sets `browser-tool` to something not in this table, that's fine — verify it exists and learn how to use it from its docs (see [Browser tool usage](#step-3-browser-smoke-tests-qa-mode-full-only)).

### Step 3: Browser Smoke Tests (qa-mode: full only)

Browser tool was detected. Now run browser testing:

1. **Check dev server config.** If `dev-server` is not configured: report **FAIL** — "qa-mode is 'full' but no dev-server command is configured. Add dev-server to the manifest or switch to qa-mode: build-only."
2. **Run QA setup** (if `qa-setup` is configured): execute the qa-setup command to prepare the environment for browser testing (e.g., seed test data, create test users). If it fails, warn but continue — some smoke tests may still work.
3. Start the dev server (command from config) in the background, capturing stdout/stderr.
4. **Read the URL from the dev server's stdout.** The dev server will print its listen URL — read stdout/stderr for up to 60 seconds, looking for URL patterns: `http://localhost:\d+`, `http://127.0.0.1:\d+`, or `http://0.0.0.0:\d+`. Every major framework prints this:
   - Next.js: `- Local: http://localhost:3001`
   - Vite: `Local: http://localhost:5174/`
   - CRA: `Local: http://localhost:3001`
   - Fastify/Express: `Listening on http://0.0.0.0:3000`
   If `0.0.0.0` is detected, rewrite to `http://localhost:{port}` for polling.
   **This is the URL you use for all browser testing.** There is no configured URL — you use what the server tells you.
5. If no URL appears in stdout within 60 seconds: report **FAIL** — "Dev server did not print a listen URL within 60 seconds" with the server's stderr output. Kill the process. This is an infrastructure failure.
6. Poll the detected URL every 2 seconds for up to 30 seconds to confirm it responds.
7. If it never responds: report **FAIL** — "Dev server printed {url} but it never responded to requests" with stderr output. Kill the process.
8. **Auth pre-check** (only if ALL of these are true: `auth-strategy` is not `none`, test credentials are configured, AND at least one acceptance criterion requires authenticated access — e.g., references logging in, dashboard, user-specific data, or protected routes): Navigate to the login page and attempt sign-in with the test credentials. If login succeeds, continue. If login fails, report as infrastructure failure: "Test user authentication failed — auth-strategy is '{strategy}' but test credentials could not log in. Verify qa-setup created the test user correctly." Skip this step entirely if no acceptance criteria require authentication — the login flow may not exist yet in early layers.
9. If healthy — **browser testing** using the detected browser tool at the URL from step 4. Two phases:

**Phase 1: Acceptance testing** (if acceptance criteria provided)

Test each acceptance criterion from the QA gate. For each criterion:
- Navigate to the relevant page
- Perform the action described (fill forms, click buttons, submit data)
- Verify the expected outcome (content appears, page changes, data persists)
- **Test at least one error/edge case per criterion** — if critical user flows or key test scenarios were provided, use them to guide what error paths to test (e.g., submit empty form, enter invalid data, trigger network errors). If no scenarios were provided, test the obvious error case (empty input, wrong credentials, missing required fields).
- Check browser console for errors
- Take a screenshot as evidence
- Report pass/fail per criterion (including error/edge case results)

**Phase 2: Regression testing** (if design doc provided)

Read the design doc to understand all features built so far. Test existing features beyond the acceptance criteria to catch regressions:
- Navigate through key user flows from prior layers
- Verify previously working features still work
- Check for console errors, broken pages, missing content
- Report any regressions found

If neither acceptance criteria nor design doc are provided (e.g., session-level verification), fall back to exploratory testing: navigate visible pages, interact with UI elements, check for console errors.

**Browser tool usage:**

   Use the selected browser tool to perform these operations. Learn the tool's specific commands before starting:
   - **Skill-based tools** (e.g., gstack browse): invoke the tool's skill (e.g., `/browse`) via the Skill tool to load its command reference
   - **MCP tools** (e.g., Playwright MCP): the tool schemas are already in your tools list — use them directly
   - **CLI tools**: run `<tool> --help` via Bash to learn available commands

   **Required operations** (every browser tool supports these — find the tool-specific commands):
   1. Navigate to a URL
   2. Wait for page load
   3. Discover interactive elements (snapshot/inspect)
   4. Interact with elements (click, fill forms, select options)
   5. Check browser console for errors
   6. Take screenshots as evidence

10. **CLEANUP — FINALLY BLOCK (mandatory on ALL paths, including failure/error):**

   This is a **finally block** — it runs no matter what happened above. Even if tests errored, even if the browser crashed, even if every acceptance criterion failed. Do NOT skip this step for any reason.

   a. Close/stop the browser tool (ignore errors if close itself fails). Use the tool's shutdown command — e.g., `stop`, `close`, `browser_close`, or equivalent. If the tool runs a persistent daemon or server, ensure it is stopped.
   b. Kill the dev server process.

   Browser processes (Chromium) and dev servers persist if not explicitly closed, accumulating across sessions and QA gates. If this agent crashes before reaching this step (OOM, context overflow), the session wrapper's process-group cleanup is the backstop — it kills the entire process tree on exit.

### Report

Always show what ran and what was skipped:

```
Verification Results:
  Build (lint, tsc, build, test): PASS
  Dev server: healthy at {url from stdout} (detected from stdout)
  Acceptance criteria:
    ✓ User can create an account with email/password
    ✓ User can log in and see the dashboard
    ✗ Backend API calls succeed — got 500 on /api/documents
    ✓ Navigation renders correctly
    ⊘ Google OAuth login — EXPECTED SKIP (GOOGLE_CLIENT_ID not configured)
  Regression tests:
    ✓ Homepage renders
    ✓ Login flow works
    No regressions found
  Result: FAIL (1 acceptance criterion failed)
```

Or for build-only mode:
```
Verification Results:
  Build (lint, tsc, build, test): PASS
  Browser tests: N/A (qa-mode: build-only)
  Result: PASS
```

**Status meanings:**
- **PASS / FAIL** — criterion was tested, with clear result
- **EXPECTED SKIP** (⊘) — user acknowledged this feature won't work yet (missing env vars marked "skip for now" during preflight). Does NOT fail the gate.
- **SKIPPED** — criterion should have been tested but wasn't. **FAILS the gate.** There is no acceptable reason to skip a criterion that wasn't pre-approved by the user.

### What Counts as Infrastructure Failure

Only these qualify as infrastructure failure:
- No browser tool available (none detected and none configured via `browser-tool` in manifest)
- Dev server won't start (process exits or never responds to health checks)
- Missing env vars that prevent the app from running

If the browser tool launches and navigates to a page, it works. Any failure in specific interactions (form submit, click, element lookup) is a **criterion FAIL**, not infrastructure. Try different approaches before reporting failure — use alternative selectors, JavaScript evaluation, or re-snapshot after page changes.

---

## Preflight Mode

Environment readiness check. Detects what tools and configuration are available for QA. Does NOT run build/test commands.

### Step 1: Detect Browser Tools

Run the same auto-detection from [Full Mode Step 2](#step-2-select-browser-tool-qa-mode-full-only). Report ALL detected tools and their types. If `browser-tool` is already set in the manifest, note that too. Do NOT ask the user — preflight just detects and reports. The orchestrator handles tool selection and blocking if needed.

### Step 2: Check Environment Variables

Read the manifest's `env-template` field from the manifest config (frontmatter).

- **No `env-template` field in manifest:** skip env check entirely — project doesn't use env vars.
- **`env-template` field exists + `.env.local` missing + template file exists:** copy the template to `.env.local`. Tell the user to fill in real values before `/run` for full E2E QA.
- **`env-template` field exists + `.env.local` missing + template file missing:** Generate the template file NOW. Read the project's design doc (referenced in the manifest) and parse it for all environment variables the project needs — API keys, database URLs, third-party credentials, feature flags. Write the template file (e.g., `.env.example`) with empty placeholder values and a comment header. Then copy it to `.env.local`. Do NOT skip this step or defer it to a session agent.
- **`.env.local` already exists:** report it exists. Do NOT overwrite.

After creating or copying `.env.local`, ensure it's in `.gitignore`. If `.gitignore` doesn't exist, create it. If it exists but doesn't contain `.env.local`, append it. This prevents accidental commits of secrets.

Then read `.env.local` and provision empty variables. Do NOT just report a table of empty vars and ask the user to fill them — actively work through each one:

1. **Auto-generate** what you can immediately (random secrets, encryption keys, version numbers) without asking.

2. **CLI-provisionable vars** — for services with CLIs (managed backends, email providers, etc.):
   - Check the CLI's `--help` for non-interactive flags
   - If the CLI needs inputs you don't have (team slug, project name, region), ask the user
   - If the CLI needs a file that doesn't exist yet (e.g., package.json for a greenfield project), create a temporary one, run the CLI, then clean up the temp file and any generated artifacts
   - Run the command, then verify it wrote the expected values to `.env.local`
   - If it fails, diagnose the error and retry or ask the user for help

3. **Dashboard-only vars** (API keys from web UIs with no CLI) — ask the user to provide the value. Be specific about where to find it (e.g., "Go to the service's dashboard → API keys section").

4. After all vars are handled, **re-read `.env.local`** and confirm everything is set. List any that are still empty.

Session agents run non-interactively — they cannot answer prompts. All provisioning that requires interaction must happen here in preflight. Do not defer it to session tasks.

**Convex provisioning** (when NEXT_PUBLIC_CONVEX_URL or CONVEX_DEPLOYMENT is empty):

1. Ask the user for their Convex team slug and project name (or whether to create a new project)
2. If no `package.json` exists, create a temporary one: `echo '{"name":"temp","private":true}' > package.json`
3. Run: `npx convex dev --once --configure existing --team <team-slug> --project <project-slug>` (or `--configure new` for new projects)
4. Verify `.env.local` now contains `CONVEX_DEPLOYMENT` and `NEXT_PUBLIC_CONVEX_URL` (or `CONVEX_SITE_URL`)
5. Clean up: remove temp `package.json` and any `convex/_generated/` artifacts if created

### Step 3: Run Setup Command

If the manifest config includes a `setup` field, run it.

- Success → `Setup: OK ({command})`
- Failure → `Setup: FAILED — {error}`. Tell the user what went wrong.
- No setup field → `Setup: not configured (skipped)`

### Step 4: Capture Test Baseline

If the manifest includes a `verify` command, run it now and record which tests fail. This baseline lets session verification distinguish pre-existing failures from new regressions.

- Save failing test names/patterns to `docs/autoboard/{slug}/test-baseline.md`
- If all tests pass, write "All tests pass — clean baseline"
- If the verify command itself isn't runnable yet (missing deps, no project scaffolded), skip and note "No baseline — project not yet buildable"

### Step 5: Dev Server Smoke Test

Only run this if a browser tool is available (no point testing the dev server if we can't browser-test against it).

1. If `dev-server` is not configured: skip this step.
2. Start the dev server (`dev-server` command) in the background, capturing stdout/stderr.
3. **Read the URL from stdout.** Same detection as Full Mode step 4 — look for `http://localhost:\d+`, `http://127.0.0.1:\d+`, or `http://0.0.0.0:\d+` in stdout/stderr (up to 30 seconds).
4. Poll the detected URL every 2 seconds for up to 30 seconds.
5. If it responds: dev server works. Report the detected URL. Kill it.
6. If no URL detected or it never responds: report that the dev server didn't start. This is likely due to missing env vars or configuration.

### Report

```
Preflight Results:
  Browser tools detected:
    ✓ gstack browse (~/.claude/skills/gstack/browse/dist/browse)
    ✗ Playwright MCP (not in available tools)
    ✗ agent-browser (not found on PATH)
  Environment: .env.local exists but has empty variables:
    - NEXT_PUBLIC_CONVEX_URL (empty)
    - CONVEX_DEPLOY_KEY (empty)
    If these aren't filled in, sessions may not be able to fully build,
    test, or validate against the real backend.
  Setup: FAILED — npx convex dev --once exited 1 (missing CONVEX_DEPLOY_KEY)
  Test baseline: not captured (setup failed)
  Dev server: not tested (setup failed)
```

Or when fully ready with multiple tools:
```
Preflight Results:
  Browser tools detected:
    ✓ gstack browse (~/.claude/skills/gstack/browse/dist/browse)
    ✓ Playwright MCP (available)
    ✗ agent-browser (not found on PATH)
  Environment: .env.local configured (all variables set)
  Setup: OK (npx convex dev --once)
  Test baseline: clean (all tests pass)
  Dev server: healthy at {url from stdout} (detected from stdout)

Environment is ready for full E2E QA.
```

Or minimal:
```
Preflight Results:
  Browser tools detected: none
  Environment: no env-template configured (skipped)
  Setup: not configured (skipped)
  Dev server: not tested (no browser tool)

QA will run build/test commands only. Install gstack browse, Playwright MCP, or agent-browser for browser smoke tests.
```
