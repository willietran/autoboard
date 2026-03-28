# Autoboard
Give Autoboard an idea, go to sleep, wake up to a fully functioning app with clean code.

Autoboard is essentially the Toyota Production System applied to Agentic Engineering. You come to Autoboard with am ambitious plan, and it'll break it down into manageable chunks (to fight context rot), dispatch isolated session agents, and identify key integration layers where the orchestrator will QA your app for you to make sure it actually works and run a thorough independent audit to identify and then fix AI slop code.

This process is designed to prevent future agents from building upon a broken foundation and prevents tech debt from piling up while also protecting your agent's context window to prevent it from entering the "stupid zone" (aka context rot).


## Installation

Add the marketplace and install:

```
/plugin marketplace add willietran/autoboard
/plugin install autoboard@thelittlebyte
```

### Development

To work on autoboard itself, clone the repo and use the `--plugin-dir` flag:

```bash
alias claude="claude --plugin-dir /path/to/autoboard"
```

## Workflow

### 1. Design

```
/autoboard:brainstorm
```

Interactive design session. Explores your codebase, asks clarifying questions, proposes approaches with trade-offs. Produces a design doc and quality standards config.

### 2. Plan

```
/autoboard:task-manifest
```

Generates a task manifest from the design doc — sessions with dependency graphs, TDD phases, complexity scores, and QA gates.

### 3. Build

```
/autoboard:run <project>
```

Launches the orchestrator. Spawns parallel session agents via `claude -p` in isolated git worktrees. Each session follows a mandatory workflow:

**Explore** &rarr; **Plan** &rarr; **Plan Review** &rarr; **Implement** &rarr; **Verify** &rarr; **Code Review** &rarr; **Commit**

The feature branch is ready for PR when done.

## Features

### Orchestration
- **Parallel multi-agent scheduling** — Sessions run concurrently in dependency-aware layers; upstream work completes before downstream sessions start
- **Isolated sessions** — Each agent works in its own git worktree with scoped permissions; squash-merged as one commit
- **Resumable runs** — Detects completed sessions and picks up where it left off if the orchestrator crashes

### Quality Gates
- **Mandatory review gates** — Plan review and code review subagents run before any merge
- **TDD enforcement** — Tasks follow RED → GREEN → REFACTOR phases with test baselines that distinguish regressions from pre-existing failures
- **QA pipeline** — Build + browser tests between dependency layers to prevent building on top of stuff that never worked
- **Coherence audits** — Cross-session checks for DRY violations and architecture drift, so downstream agents don't create a spaghetti factory

### Failure & Recovery
- **Failure diagnosis** — Classifies failures (permission denial vs dependency cascade vs code bug), retries with context, escalates only when stuck
- **Fabrication detection** — QA validates agent claims; catches agents lying about infrastructure failures
- **Knowledge curation** — Prior session learnings deduplicated and briefed to next-layer agents

### Configuration
- **Configurable models** — Different models per role (sessions, reviewers, exploration)
- **Effort levels** — Control reasoning depth per session (`low`, `medium`, `high`, `max`); auto-bumped to `high` for complexity 4-5 sessions
- **13 quality dimensions** — Security, test quality, DRY, performance, and more — tuned per-project and enforced by reviewers
- **GitHub Projects** — Optional kanban board with live status updates

See [CLAUDE.md](CLAUDE.md) for full architecture details.

## Acknowledgments

Autoboard builds on ideas and patterns from [Obra:Superpowers](https://github.com/obra/superpowers) by Jesse Vincent (MIT License) — a fantastic project for giving Claude Code structured skills. The following components were adapted from Superpowers:

- **Brainstorm skill** (`skills/brainstorm/`) — interactive design session workflow
- **Receiving review skill** (`skills/receiving-review/`) — critical thinking protocol for processing review feedback
- **Code reviewer agent** (`agents/code-reviewer.md`) — independent code review with quality checks
- **Systematic debugging skill** (`skills/diagnose/`) — root cause investigation methodology

If you like what Autoboard does with session orchestration, check out Superpowers for a broader collection of Claude Code skills.

## License

MIT
