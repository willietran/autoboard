# Autoboard Ecosystem

## User Commands

- `/autoboard:brainstorm` — Interactive design session producing design doc + standards
- `/autoboard:standards` — Configure quality dimensions interactively
- `/autoboard:task-manifest` — Generate task manifest from design doc
- `/autoboard:run` — Launch orchestrator

## Orchestrator Phases (internal, called by run)

- `setup` — Project resolution, manifest parsing, preflight checks
- `session-spawn` — Build briefs, create worktrees, spawn session agents
- `merge` — Squash merge sessions to feature branch
- `coherence-audit` — Cross-session quality audit (wraps `/autoboard:audit`)
- `coherence-fixer` — Fix blocking coherence issues
- `qa-gate` — Acceptance testing and regression checks
- `qa-fixer` — Fix QA gate failures
- `knowledge` — Curate cross-session knowledge between layers
- `failure` — Diagnose and handle failures
- `completion` — Final cleanup and reporting

## Session Agent Skills

- `session-workflow` — Full session lifecycle (Explore, Plan, Review, Implement, Verify, Code Review, Commit)
- `verification` — Build/test verification protocol (preflight, light, full modes)
- `receiving-review` — Critical thinking protocol for review feedback

## Tracking Providers

- `tracking-github` — GitHub Projects V2 progress tracking

## Review Agents

- `autoboard:plan-reviewer` — Plan review with quality dimension checks
- `autoboard:code-reviewer` — Code review with quality dimension checks
