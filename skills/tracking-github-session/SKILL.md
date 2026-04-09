---
name: tracking-github-session
description: GitHub Projects V2 progress reporting for session agents - phase transitions, task completion, and error reporting
---

# GitHub Tracking - Session Agent

When your session brief includes a `## Tracking` section with `Provider: github`, follow these instructions to report progress. Load this skill via `/autoboard:tracking-github-session` when you see that section.

### Phase Transitions

Move your ticket and post a comment at each phase change:

```bash
gh project item-edit --id {ITEM_ID} --project-id {PROJECT_NODE_ID} --field-id {STATUS_FIELD_ID} --single-select-option-id {PHASE_OPTION_ID}
```

```bash
gh issue comment {ISSUE_NUMBER} --repo {REPO} --body "Phase: **{Phase}** - {brief description of what's happening}"
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
