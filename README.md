# Autoboard

Agentic orchestrator for Claude Code and Codex. Breaks ambitious features into focused agent sessions, each with clean context and rigorous process gates. Independent sessions run in isolated git worktrees while Autoboard coordinates spawning, merging, and QA.

Give Autoboard an idea, go to sleep, wake up to a fully QA'd, tested, and thoroughly code-reviewed app.

## Installation

### Claude Code

Add the marketplace and install:

```
/plugin marketplace add willietran/autoboard
/plugin install autoboard@thelittlebyte
```

### Codex

For a home-local Codex install, register this repo as a local plugin:

```bash
mkdir -p ~/.agents/plugins ~/plugins
ln -sfn /path/to/autoboard ~/plugins/autoboard
```

Create `~/.agents/plugins/marketplace.json`:

```json
{
  "name": "local",
  "interface": {
    "displayName": "Local Plugins"
  },
  "plugins": [
    {
      "name": "autoboard",
      "source": {
        "source": "local",
        "path": "./plugins/autoboard"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL"
      },
      "category": "Coding"
    }
  ]
}
```

Autoboard's Codex manifest lives at `.codex-plugin/plugin.json`, and Codex discovers the shared skills via the committed symlinks in `.agents/skills/`.

To verify the install, open this repo in Codex and confirm the `Autoboard` plugin appears in the plugin catalog and that prompts like `/autoboard:brainstorm` are available.

### Development

For Claude Code development, point the CLI at the repo with `--plugin-dir`:

```bash
alias claude="claude --plugin-dir /path/to/autoboard"
```

For Codex development, keep `~/plugins/autoboard` as a symlink to your checkout so manifest and skill changes are reflected immediately.

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

Launches the orchestrator. Spawns parallel session agents via `claude -p` or `codex exec` in isolated git worktrees. Each session follows a mandatory workflow:

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
