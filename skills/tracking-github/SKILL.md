---
name: tracking-github
description: GitHub Projects V2 tracking provider — invoke to load setup commands (orchestrators) or progress reporting (session agents)
---

# GitHub Tracking Provider

GitHub Projects V2 integration for live progress tracking. This skill serves two audiences: the orchestrator (setup, action commands, recovery) and session agents (phase transitions, task completion, error reporting).

---

## For Orchestrators

### Setup

Create a GitHub Projects V2 board with phase columns and one issue per trackable unit.

**Prerequisites:** `github-project: true` or `tracking-provider: github` in manifest frontmatter.

**Resume:** If `docs/autoboard/{slug}/github-tracking.md` already exists, read it to recover all IDs and skip creation entirely.

**Steps:**

1. Verify `gh auth status` — if not authenticated, warn the user and disable tracking for the run

2. Create the project and link it to the repo:
   ```bash
   gh project create --title "{Project Title}" --owner {OWNER} --format json
   gh project link {NUMBER} --owner {OWNER} --repo {OWNER}/{REPO}
   ```

3. Configure the Status field with autoboard phase columns.

   **Do NOT create a separate field.** Modify the existing Status field — the board view uses it by default. Creating a separate "Phase" field will NOT work (the board ignores it).

   a. Get the Status field ID:
   ```bash
   gh project field-list {NUMBER} --owner {OWNER} --format json | jq '.fields[] | select(.name == "Status") | .id'
   ```

   b. Replace its default options (Todo/In Progress/Done) with autoboard phases via GraphQL:
   ```bash
   gh api graphql -f query='
     mutation {
       updateProjectV2Field(input: {
         fieldId: "{STATUS_FIELD_ID}"
         singleSelectOptions: [
           {name: "Backlog", color: GRAY, description: ""},
           {name: "Exploring", color: BLUE, description: ""},
           {name: "Planning", color: PURPLE, description: ""},
           {name: "Implementing", color: YELLOW, description: ""},
           {name: "Verifying", color: ORANGE, description: ""},
           {name: "Code Review", color: PINK, description: ""},
           {name: "Done", color: GREEN, description: ""},
           {name: "Failed", color: RED, description: ""}
         ]
       }) {
         projectV2Field {
           ... on ProjectV2SingleSelectField {
             id
             options { id name color }
           }
         }
       }
     }'
   ```

   c. Parse the response to get option IDs for each phase — you need these for all `move-ticket` actions.

4. Create issues:
   - One per session (title: `S{N}: {focus}`, body: deps + task checklist)
   - One per QA gate (title: `QA Gate: Layer {N}`, body: acceptance criteria)
   - Do NOT pre-create coherence audit issues — those are created on-demand by the coherence-fixer skill only when BLOCKING findings are found

5. Add all issues to the project, set initial status to Backlog

6. Write `docs/autoboard/{slug}/github-tracking.md` with all IDs:
   - Project Node ID, Owner, Project Number, Status Field ID
   - Phase option IDs (one per column — from step 3c)
   - Session issue numbers + Item IDs
   - QA gate issue numbers + Item IDs
   - This file must contain everything needed to resume without re-creating the project

7. Show the project board URL to the user. Open it: `gh project view {NUMBER} --owner {OWNER} -w`
   Note: The default view is Table layout. Tell the user to switch to Board layout (click the layout dropdown next to the view name) to see the kanban columns.

**General CLI guidance:** The GitHub Projects V2 API and CLI evolve. Use `--format json` and `jq` (not python) for JSON parsing. If a command above doesn't work, introspect: `gh project --help`, `gh project field-list --help`, or GraphQL `__type` queries.

**Error handling:** All GitHub operations are non-blocking. If any `gh` command fails during setup, log the failure, disable tracking for the rest of the run, and continue. Never retry, never block execution.

### Action Commands

Sub-skills reference these actions by name. Translate each action using the commands below.

**`move-ticket(ticket, phase)`** — Change a ticket's status column:
```bash
gh project item-edit --id {ITEM_ID} --project-id {PROJECT_NODE_ID} --field-id {STATUS_FIELD_ID} --single-select-option-id {PHASE_OPTION_ID}
```

**`post-comment(ticket, body)`** — Post text to a ticket:
```bash
gh issue comment {ISSUE_NUMBER} --repo {REPO} --body "{body}"
```

**`close-ticket(ticket, comment)`** — Close with final comment and move to Done:
```bash
gh issue close {ISSUE_NUMBER} --repo {REPO} --comment "{comment}"
gh project item-edit --id {ITEM_ID} --project-id {PROJECT_NODE_ID} --field-id {STATUS_FIELD_ID} --single-select-option-id {DONE_OPTION_ID}
```

**`create-ticket(title, body)`** — Create a new issue and add it to the project:
```bash
gh issue create --title "{title}" --body "{body}" --repo {REPO}
gh project item-add --project-id {PROJECT_NODE_ID} --url {ISSUE_URL}
```
Used for on-demand issues (coherence fixes, etc.) that are not pre-created during setup.

**`recover-ids`** — Read stored IDs for resume:
```
Read docs/autoboard/{slug}/github-tracking.md
```
Parse all IDs from the tracking file. No `gh` commands needed.

**`session-brief-section(ids)`** — Generate the `## Tracking` section for session/fixer briefs. See "Session Brief Template" below.

### Recovery

On resume, read `docs/autoboard/{slug}/github-tracking.md` to recover all IDs. This file contains every ID needed to operate without re-querying GitHub:
- Project Node ID, Status Field ID, phase option IDs
- Session issue numbers and Item IDs
- QA gate issue numbers and Item IDs

Cross-reference with session status files to determine which sessions completed and which need retry.

### Session Brief Template

When building a session or fixer brief, include this `## Tracking` section with IDs filled in from the tracking file:

```
## Tracking

- Provider: github
- Repo: {REPO}
- Issue number: {ISSUE_NUMBER}
- Project Node ID: {PROJECT_NODE_ID}
- Item ID: {ITEM_ID}
- Status Field ID: {STATUS_FIELD_ID}
- Phase Option IDs:
  - Exploring: {EXPLORING_OPTION_ID}
  - Planning: {PLANNING_OPTION_ID}
  - Implementing: {IMPLEMENTING_OPTION_ID}
  - Verifying: {VERIFYING_OPTION_ID}
  - Code Review: {CODE_REVIEW_OPTION_ID}
  - Done: {DONE_OPTION_ID}
  - Failed: {FAILED_OPTION_ID}

To move your ticket on the board:
  gh project item-edit --id {ITEM_ID} --project-id {PROJECT_NODE_ID} --field-id {STATUS_FIELD_ID} --single-select-option-id {PHASE_OPTION_ID}

To post a comment:
  gh issue comment {ISSUE_NUMBER} --repo {REPO} --body "..."

Tracking is NON-BLOCKING. If gh commands fail, ignore and continue working.
```

If tracking is disabled, omit the `## Tracking` section entirely.

---

## For Session Agents

When your session brief includes a `## Tracking` section with `Provider: github`, follow these instructions to report progress. Load this skill via `/autoboard:tracking-github` when you see that section.

### Phase Transitions

Move your ticket and post a comment at each phase change:

```bash
gh project item-edit --id {ITEM_ID} --project-id {PROJECT_NODE_ID} --field-id {STATUS_FIELD_ID} --single-select-option-id {PHASE_OPTION_ID}
```

```bash
gh issue comment {ISSUE_NUMBER} --repo {REPO} --body "Phase: **{Phase}** — {brief description of what's happening}"
```

### Task Completion

Post a comment when each task is done:

```bash
gh issue comment {ISSUE_NUMBER} --repo {REPO} --body "Completed T{N}: {title}"
```

### Error/Blocker

Post the error and move to Failed:

```bash
gh issue comment {ISSUE_NUMBER} --repo {REPO} --body "BLOCKED in {phase}: {error description}"
gh project item-edit --id {ITEM_ID} --project-id {PROJECT_NODE_ID} --field-id {STATUS_FIELD_ID} --single-select-option-id {FAILED_OPTION_ID}
```

### Session Complete

Post a summary comment when the session finishes successfully:

```bash
gh issue comment {ISSUE_NUMBER} --repo {REPO} --body "## Session Complete

**Status:** success
**Tasks completed:** T1, T2, T3
**Tests:** {pass count} pass, {fail count} fail

### Summary
{2-3 sentence summary of what was built/changed}

### Knowledge
{Key discoveries or patterns for future sessions}"
```

### Session Failure

Post failure context if the session fails at any phase:

```bash
gh issue comment {ISSUE_NUMBER} --repo {REPO} --body "## Session Failed

**Failed in phase:** {phase}
**Error:** {error description}
**Tasks completed before failure:** {list}

### What went wrong
{Brief explanation of the failure}"
```

### Non-blocking Rule

All tracking updates are best-effort. If a `gh` command fails, log it and continue. Never retry, never delay work. Your session status file remains the primary record; GitHub is supplementary visibility.
