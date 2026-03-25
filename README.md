# Autoboard

AI-driven development orchestrator for Claude Code. Breaks ambitious features into focused agent sessions, each with clean context and rigorous process gates. Independent sessions run in isolated git worktrees; Claude Code coordinates spawning, merging, and QA.

## Installation

```bash
claude plugin add @thelittlebyte/autoboard
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

## How It Works

- **Session agents** work in isolated git worktrees with dependency-aware scheduling
- **Squash merges** bring each session's work onto the feature branch
- **Review gates** ensure every plan and implementation gets independent review before proceeding
- **QA gates** run build validation and Playwright smoke tests between dependency layers
- **Configurable quality standards** let you tune which dimensions matter for your project
- **GitHub Projects integration** (optional) creates a kanban board with live status updates

See [CLAUDE.md](CLAUDE.md) for full architecture details.

## Acknowledgments

Autoboard builds on ideas and patterns from [Obra:Superpowers](https://github.com/obra/superpowers) by Jesse Vincent (MIT License) — a fantastic project for giving Claude Code structured skills. The following components were adapted from Superpowers:

- **Brainstorm skill** (`skills/brainstorm/`) — interactive design session workflow
- **Receiving review skill** (`skills/receiving-review/`) — critical thinking protocol for processing review feedback
- **Code reviewer agent** (`agents/code-reviewer.md`) — independent code review with quality checks

If you like what Autoboard does with session orchestration, check out Superpowers for a broader collection of Claude Code skills.

## License

MIT
