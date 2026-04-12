# Autoboard Codex Compatibility Design

**Date:** 2026-04-12
**Status:** Approved
**Branch:** `autoboard/codex-compatibility`

## Goal

Make Autoboard work on Codex with the same product behavior it has on Claude today:

- brainstorm -> standards -> task-manifest -> run
- walk-away execution
- isolated session contexts that do not pollute the orchestrator
- mandatory plan review and code review gates
- QA, coherence audit, and fixer loops
- no regression in Claude behavior

This is a compatibility project, not a redesign.

## Codex Packaging Contract

The implementation in this branch should reflect the discovered Codex contract at a high level:

- Codex headless runs use `codex exec --json`
- Codex distribution uses `.codex-plugin/plugin.json`
- Repository-local Codex workers can discover the same skills through `.agents/skills/`
- Codex plugins package skills/apps/MCP metadata, but reviewer prompts still live in `agents/*.md`
- provider selection happens at spawn time by the orchestrator

These details inform the compatibility seam. They do not change Autoboard's product behavior.

## User-Facing Success Criteria

On Codex, the user should be able to:

1. Run the same Autoboard workflow they run on Claude now.
2. Hand off implementation to isolated session workers instead of the main context.
3. Rely on the same quality bar: clean code, no AI slop, real verification, coherence checks, and automatic fixes.
4. Come back later to a working app rather than a partially coordinated set of tasks.

On Claude, nothing about the product's operating model should change.

## Current Architecture

Autoboard already uses two execution patterns:

- The orchestrator spawns headless worker sessions and fixer sessions via provider-specific shell launchers.
- Inside those headless worker sessions, the session agent can spawn its own helper subagents for Explore, plan review, and code review.
- QA and coherence audit remain orchestrator-owned subagent work today.

That architecture is correct for the product and should remain intact.

## Problem Statement

The codebase currently assumes Claude-specific execution details in multiple places:

- wording that describes Autoboard as Claude-only
- shell wrappers that invoke `claude -p`
- skill instructions that explicitly assume Claude subprocesses
- package metadata keyed to Claude branding

Those assumptions prevent Codex from being used as the isolated headless worker runtime without changing the product behavior.

## Design Principles

### 1. Preserve operating model

Do not change how Autoboard works conceptually. Sessions remain isolated workers. The orchestrator remains an engineering lead, not the implementation workspace.

### 2. Keep compatibility changes narrow

Do not introduce a large runtime abstraction or rewrite the orchestration model. Make the minimum provider-aware changes needed for Codex support.

### 3. Preserve context isolation

The orchestrator's context must stay lean. Implementation, review debates, QA noise, and fixer churn belong in isolated workers or existing orchestrator-owned helpers, not in the main context window.

### 4. Break nothing for Claude

Claude remains a first-class runtime. Existing workflows, artifacts, and conventions keep working.

## Proposed Design

### Provider-aware isolated session launcher

Keep the current headless session model and add a Codex-equivalent launcher alongside the existing Claude launcher.

The launcher layer should support:

- spawning an isolated session worker in a worktree
- passing provider-specific model and effort flags
- appending standards, baseline, and knowledge material to the prompt
- capturing machine-readable output
- applying permission settings where supported
- cleaning up process groups and stale workers

The Claude path stays as-is. The Codex path mirrors it closely enough that the higher-level skills do not need a behavioral rewrite.

Provider selection should happen at worker launch time, not once per project run. The current orchestrator knows which platform it is running on from its own runtime context, so it should choose the matching wrapper explicitly whenever it spawns a new worker. Shell wrappers should not try to infer the provider from ambient environment variables.

### Skill-level provider awareness

Keep skills as the control plane. Update only the instructions that currently hardcode Claude-specific assumptions.

Examples:

- "spawn `claude -p`" becomes "spawn the configured provider's isolated worker"
- session workflow wording stops assuming Claude by name
- user-facing docs describe Claude and Codex compatibility without changing the workflow

This also means resumed runs can legitimately mix providers over time. A run that started on Claude may later resume on Codex, and any newly spawned workers should use the provider of the current orchestrator invocation.

### No major change to QA/coherence model

QA and coherence audit should keep running where they run today unless a strict Codex-specific limitation forces a small compatibility patch. This avoids unnecessary product churn.

## Non-Goals

- redesigning Autoboard around native Codex subagents
- changing the manifest format in a major way
- changing branch/worktree conventions
- changing the review-gate model
- weakening context isolation in favor of convenience

## Expected Code Areas

Primary compatibility touchpoints:

- `bin/spawn-session.sh`
- `bin/spawn-codex-session.sh`
- `skills/setup/SKILL.md`
- `skills/session-spawn/SKILL.md`
- `skills/run/SKILL.md`
- `skills/session-workflow/SKILL.md`
- `skills/qa-gate/SKILL.md`
- `skills/qa-fixer/SKILL.md`
- `skills/coherence-audit/SKILL.md`
- `skills/coherence-fixer/SKILL.md`
- `skills/failure/SKILL.md`
- `skills/knowledge/SKILL.md`
- `skills/task-manifest/SKILL.md`
- `skills/verification/SKILL.md`
- `README.md`
- `CLAUDE.md`
- `package.json`
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `.codex-plugin/plugin.json`

## Risks

### Codex headless CLI differences

Codex may differ from Claude in flag shape, permission handling, output streaming, or model identifiers. The implementation should isolate those differences to the launcher and the few skill instructions that mention them.

Automatic provider detection from shell environment is not a reliable foundation. The orchestrator should pass provider choice explicitly by selecting the correct launcher path rather than asking shell scripts to guess.

### Packaging and metadata expectations

Codex may need slightly different plugin metadata or additional documentation. This should be validated during implementation without forcing a Claude regression.

### Over-refactoring

The main risk is doing too much. The implementation should stay focused on compatibility seams, not architecture cleanup.

## Validation Plan

Codex parity is complete only when all of the following are true:

1. A Codex headless session can run the existing session brief model in an isolated worktree.
2. A full session workflow can complete with plan review, implementation, verification, and code review in the isolated worker.
3. A small multi-session run can merge session work, run QA and coherence, and keep the orchestrator context lean.
4. Claude can still run the same flow without changes in behavior.

## Recommendation

Implement the smallest provider-aware compatibility seam possible:

- keep the product behavior the same
- add a Codex session launcher
- update Claude-hardcoded wording and spawn instructions
- verify parity through end-to-end runs

That gives Autoboard Codex compatibility without turning this into a redesign project.
