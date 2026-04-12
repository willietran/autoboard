# Autoboard

An AI engineering lead that manages a team of coding AIs so they don't cut corners.

Autoboard is a Codex plugin that decomposes features into parallel coding sessions, each with mandatory review gates, then validates the integrated result with cross-session quality audits — catching the problems that no individual session could see. The orchestrator exercises judgment: it arbitrates review disputes, curates cross-session knowledge, validates QA claims, and diagnoses failures before deciding how to respond.

**Architecture:** Skills-only plugin with a thin shell wrapper (`bin/spawn-session.sh`). The Main Agent (Codex) is the orchestrator — the engineering lead. It reads a manifest, spawns session agents via `Codex -p` subprocesses, merges results, and runs QA gates. Sessions are full main agents with complete tool access, so they can spawn Explore subagents, plan reviewers, and code reviewers.

## How It Works

```
/autoboard:brainstorm  →  design.md + standards.md (interactive design session)
/autoboard:standards   →  standards.md (configure quality dimensions interactively)
/autoboard:task-manifest  →  manifest.md (sessions, tasks, deps, QA gates)
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
alias Codex="Codex --plugin-dir /path/to/autoboard"
```

Changes to the repo are instantly reflected — no copying needed.

## Repository Structure

Conventions — don't enumerate every file, just know where to look:

- **`.Codex-plugin/plugin.json`** — Plugin manifest
- **`bin/spawn-session.sh`** — Thin wrapper around `Codex -p` for spawning session agents
- **`config/default-session-permissions.json`** — Default allow/deny rules for session agents
- **`standards/dimensions/<name>.md`** — One file per quality dimension (see `standards/README.md`)
- **`skills/<name>/SKILL.md`** — Each skill lives in its own directory
- **`agents/<name>.md`** — Subagent definitions (plan-reviewer, code-reviewer)
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
- Feature branch: `autoboard/<slug>` (e.g., `autoboard/user-auth`)
- Session branches: `autoboard/<slug>-s<N>` (e.g., `autoboard/user-auth-s1`) — created by orchestrator via manual worktrees, ephemeral
- One-tier squash merge: session branches squash-merge → feature branch
- One commit per session on the feature branch

---

## Architecture

**Main Agent = Orchestrator.** It reads a manifest, spawns session agents via `Codex -p`, merges their work, runs QA gates, and reports progress. It does NOT implement code itself. Sessions use `Codex -p` (not the Agent tool) because session agents need to spawn their own subagents — a platform constraint.

| Orchestrator does | Session Agent does |
|---|---|
| Parse manifest, build dependency graph | Explore codebase, plan implementation |
| Create worktrees, spawn `Codex -p` sessions | Execute tasks (TDD, implementation, tests) |
| Merge session branches to feature branch | Spawn plan-reviewer and code-reviewer subagents |
| Run QA gates between layers | Run build verification within worktree |
| Handle failures (retry once, then ask user) | Diagnose and fix issues within session scope |
| Report progress, update progress.md | Write session status files and knowledge |

### Session Lifecycle

Each session agent executes this workflow (via `/autoboard:session-workflow`):

1. **Explore** — Spawn Explore subagents to understand relevant code
2. **Plan** — Write implementation plan
3. **Plan Review** — Spawn plan-reviewer subagent; max 3 rounds
4. **Implement** — Execute plan task-by-task (TDD where marked: RED → GREEN → REFACTOR)
5. **Verify** — Run full build pipeline
6. **Code Review** — Spawn code-reviewer subagent; max 3 rounds
7. **Commit** — Commit each task, write session status file

### QA Gates

QA gates run between dependency layers to catch compound errors. The orchestrator spawns a QA subagent that invokes `/autoboard:verification --full` — build validation + browser smoke tests (gstack browse, Playwright MCP, or similar). Falls back to build-only if no browser tool is installed. QA runs as a subagent to keep browser output out of the orchestrator's window.

---

## Non-Negotiable Standards

### Mandatory Review Gates

Two review gates are BLOCKING PREREQUISITES in every session. Skipping either is a non-negotiable violation.

**Gate 1 — Plan Review (before implementation):**
- Dispatch the `autoboard:plan-reviewer` agent
- Critically evaluate feedback — do NOT blindly agree
- Update the plan with accepted changes before writing any code
- **NEVER start implementation without completing this gate**

**Gate 2 — Code Review (before final commit):**
- Dispatch the `autoboard:code-reviewer` agent
- Critically evaluate feedback — verify each suggestion technically
- Implement fixes, re-run verification
- **NEVER finalize a commit without completing this gate**

**Receiving review feedback — critical thinking protocol:**

| Thought that means STOP | Reality |
|---|---|
| "The reviewer said X, so I'll just do X" | Verify X is correct first. Reviewers can be wrong. |
| "I'll accept all suggestions to be safe" | Accepting wrong suggestions makes code worse, not better. |
| "This suggestion seems off but I'll do it anyway" | If it seems off, investigate. Trust your analysis. |
| "The plan looks good, I'll skip review" | Run the review subagent. Every time. No exceptions. |
| "All tests pass, time to commit" | Run the code review subagent first. |

### Security

- **No shell injection.** All subprocess calls must use argument arrays — never string interpolation into shell commands.
- **Validate manifest input.** Task fields parsed from markdown are untrusted. Sanitize file paths, task IDs, and branch names.
- **Preserve session branches on failure.** Never delete a session branch until its work is successfully merged.
- **Scoped session permissions.** Sessions run in `dontAsk` mode with project-specific allow/deny rules. Generated by `/autoboard:task-manifest` at `docs/autoboard/{slug}/session-permissions.json`. Fallback: `config/default-session-permissions.json`. Opt out: `skip-permissions: true` in manifest.

### Codex Friendliness

The codebase must be easily navigable by Codex.

- **Zero dead code.** No commented-out blocks, no unused functions, no orphaned imports.
- **Predictable naming.** Files, functions, and variables named so their purpose is obvious.
- **Small, focused files.** Each file has one clear responsibility.
- **Leave the codebase cleaner than you found it.**
