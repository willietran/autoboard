# Autoboard

An AI engineering lead that manages a team of coding AIs so they don't cut corners.

Autoboard is a Claude Code and Codex plugin that decomposes features into parallel coding sessions, each with mandatory review gates, then validates the integrated result with cross-session quality audits. The orchestrator arbitrates review disputes, curates cross-session knowledge, validates QA claims, and diagnoses failures before deciding how to respond.

**Architecture:** Skills-only plugin with provider-specific packaging (`.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`) and thin provider-specific launchers (`bin/spawn-session.sh` for Claude Code, `bin/spawn-codex-session.sh` for Codex). The Main Agent is the orchestrator. It reads a manifest, spawns session agents through the current provider's headless worker path, merges results, and runs QA gates. Sessions are full main agents with complete tool access, so they can spawn Explore subagents, plan reviewers, and code reviewers.

## How It Works

```
/autoboard:brainstorm  →  design.md + standards.md
/autoboard:standards   →  standards.md
/autoboard:task-manifest  →  manifest.md
/autoboard:run  →  Main Agent orchestrates parallel sessions
```

## Installation

Add the marketplace and install:

```
/plugin marketplace add willietran/autoboard
/plugin install autoboard@thelittlebyte
```

### Development

For working on autoboard itself, use the `--plugin-dir` flag:

```bash
alias claude="claude --plugin-dir /path/to/autoboard"
```

Changes to the repo are instantly reflected.

## Repository Structure

- **`.claude-plugin/plugin.json`** — Claude plugin manifest
- **`.codex-plugin/plugin.json`** — Codex plugin manifest
- **`bin/spawn-session.sh`** — Claude launcher for isolated session agents
- **`bin/spawn-codex-session.sh`** — Codex launcher for isolated session agents
- **`config/default-session-permissions.json`** — Default allow/deny rules for Claude session agents
- **`standards/dimensions/<name>.md`** — One file per quality dimension
- **`skills/<name>/SKILL.md`** — Each skill lives in its own directory
- **`agents/<name>.md`** — Reviewer/helper rubrics
- **`docs/`** — Reference docs and design specs

**Skills by role:**

| Role | Skills |
|---|---|
| User-facing | `brainstorm`, `standards`, `task-manifest`, `run` |
| Orchestrator internals | `setup`, `session-spawn`, `merge`, `qa-gate`, `qa-fixer`, `coherence-audit`, `coherence-fixer`, `completion`, `failure`, `knowledge`, `tracking-github`, `audit` |
| Session agent | `session-workflow`, `verification`, `receiving-review`, `diagnose` |

**Runtime artifacts** (generated per-project at `docs/autoboard/<slug>/`, not checked in):
`design.md`, `standards.md`, `manifest.md`, `session-permissions.json`, `progress.md`, `decisions.md`, `sessions/s<N>-status.md`

## Git Conventions

- **Never commit to or push to `main`.** All work happens on feature branches.
- Feature branch: `autoboard/<slug>`
- Session branches: `autoboard/<slug>-s<N>`
- One-tier squash merge: session branches squash-merge → feature branch
- One commit per session on the feature branch

## Architecture

**Main Agent = Orchestrator.** It reads a manifest, spawns session agents through the current provider's headless worker path, merges their work, runs QA gates, and reports progress. It does NOT implement code itself. Sessions use isolated headless workers instead of orchestrator-owned subagents because they need to spawn their own helpers without polluting the main context.

| Orchestrator does | Session Agent does |
|---|---|
| Parse manifest, build dependency graph | Explore codebase, plan implementation |
| Create worktrees, spawn isolated sessions | Execute tasks (TDD, implementation, tests) |
| Merge session branches to feature branch | Spawn plan-reviewer and code-reviewer helpers |
| Run QA gates between layers | Run build verification within worktree |
| Handle failures (retry, escalate) | Diagnose and fix issues within session scope |
| Report progress, update progress.md | Write session status files and knowledge |

### Session Lifecycle

Each session agent executes this workflow:

1. **Explore**
2. **Plan**
3. **Plan Review**
4. **Implement**
5. **Verify**
6. **Code Review**
7. **Commit**

### QA Gates

QA gates run between dependency layers to catch compound errors. The orchestrator spawns a QA subagent that invokes `/autoboard:verification --full` and keeps heavy output out of the orchestrator's window.

## Non-Negotiable Standards

### Mandatory Review Gates

Two review gates are blocking prerequisites in every session.

**Gate 1 — Plan Review**
- Dispatch an independent plan-review helper through the current provider
- Critically evaluate feedback
- Update the plan before implementation

**Gate 2 — Code Review**
- Dispatch an independent code-review helper through the current provider
- Critically evaluate feedback
- Implement fixes and re-run verification before final commit

### Security

- **No shell injection.** All subprocess calls must use argument arrays.
- **Validate manifest input.** Sanitize file paths, task IDs, and branch names.
- **Preserve session branches on failure.** Never delete a session branch until its work is successfully merged.
- **Scoped session permissions.** Claude sessions use `session-permissions.json` in `dontAsk` mode. Codex does not support that manifest path yet, so Codex runs currently require `skip-permissions: true` in the manifest.

### Agent Friendliness

The codebase must be easily navigable by Claude Code and Codex.

- **Zero dead code.**
- **Predictable naming.**
- **Small, focused files.**
- **Leave the codebase cleaner than you found it.**
