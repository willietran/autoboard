# Autoboard

An AI engineering lead that manages a team of coding AIs so they don't cut corners.

Autoboard is a Claude Code plugin that decomposes features into parallel coding sessions, each with mandatory review gates, then validates the integrated result with cross-session quality audits — catching the problems that no individual session could see. The orchestrator exercises judgment: it arbitrates review disputes, curates cross-session knowledge, validates QA claims, and diagnoses failures before deciding how to respond.

**Architecture:** Skills-only plugin with a thin shell wrapper (`bin/spawn-session.sh`). The Main Agent (Claude Code) is the orchestrator — the engineering lead. It reads a manifest, spawns session agents via `claude -p` subprocesses, merges results, and runs QA gates. Sessions are full main agents with complete tool access, so they can spawn Explore subagents, plan reviewers, and code reviewers.

## How It Works

```
/autoboard:brainstorm  →  design.md + standards.md (interactive design session)
/autoboard:standards   →  standards.md (configure quality dimensions interactively)
/autoboard:task-manifest  →  manifest.md (sessions, tasks, deps, QA gates)
/autoboard:run  →  Main Agent orchestrates parallel sessions
```

## Installation

Autoboard is loaded as a local plugin via the `--plugin-dir` flag. Add this alias to `~/.zshrc`:

```bash
alias claude="claude --plugin-dir /path/to/autoboard"
```

Skills, agents, and all session materials are auto-discovered from the plugin directory. Changes to the repo are instantly reflected — no copying needed.

## Repository Structure

```
autoboard/
├── .claude-plugin/
│   └── plugin.json             # Plugin manifest
│
├── bin/
│   └── spawn-session.sh        # Thin wrapper around claude -p for spawning session agents
│
├── config/
│   └── default-session-permissions.json  # Default allow/deny rules for session agents
│
├── standards/                  # Quality standards framework
│   ├── README.md               # How the standards system works
│   └── dimensions/             # One file per quality dimension
│       ├── security.md
│       ├── error-handling.md
│       ├── type-safety.md
│       ├── dry-code-reuse.md
│       ├── test-quality.md
│       ├── config-management.md
│       ├── frontend-quality.md
│       ├── data-modeling.md
│       ├── api-design.md
│       ├── observability.md
│       ├── performance.md
│       └── code-organization.md
│
├── skills/                     # Skills (invocable via Skill tool)
│   ├── brainstorm/SKILL.md     # /autoboard:brainstorm — interactive design session
│   ├── standards/SKILL.md      # /autoboard:standards — configure quality dimensions
│   ├── task-manifest/SKILL.md  # /autoboard:task-manifest — generate manifest from design doc
│   ├── run/SKILL.md            # /autoboard:run — orchestrator (THE core file)
│   ├── session-workflow/SKILL.md  # /autoboard:session-workflow — session agent workflow + quality loading + shell safety
│   ├── verification/SKILL.md   # /autoboard:verification — unified QA (light/full/preflight modes)
│   └── receiving-review/SKILL.md  # /autoboard:receiving-review — critical thinking for review feedback
│
├── agents/                     # Subagent definitions (read-only reviewers)
│   ├── plan-reviewer.md        # autoboard:plan-reviewer — plan review with quality dimension checks
│   └── code-reviewer.md        # autoboard:code-reviewer — code review with quality dimension checks
│
└── docs/                       # Design docs, manifests, reference
    └── autoboard/<slug>/       # Per-project directory
        ├── design.md           # Design doc (from brainstorm)
        ├── standards.md         # Quality standards (from brainstorm or /standards)
        ├── manifest.md         # Task manifest (from task-manifest)
        ├── session-permissions.json  # Session agent permissions (from task-manifest, user-editable)
        ├── progress.md         # Live progress (updated by orchestrator during run)
        ├── decisions.md        # Architectural decisions (append-only)
        └── sessions/           # Session status files (written by session agents)
            ├── s1-status.md
            └── s2-status.md
```

## Git Conventions

- **Never commit to or push to `main`.** All work happens on feature branches.
- Feature branch: `autoboard/<slug>` (e.g., `autoboard/user-auth`)
- Session branches: `autoboard/<slug>-s<N>` (e.g., `autoboard/user-auth-s1`) — created by orchestrator via manual worktrees, ephemeral
- One-tier squash merge: session branches squash-merge → feature branch
- One commit per session on the feature branch

---

## Architectural Philosophy

### Why Sessions Matter

AI coding agents degrade past 40-60% context window utilization — quality drops, hallucinations increase, and defects compound. AI-generated code produces more bugs than human code; without context isolation, each session builds on potentially broken foundations. Autoboard decomposes ambitious features into focused sessions, each with clean context and structured process gates.

### Core Principle: Main Agent as Orchestrator

Autoboard is a **Claude Code plugin** — skills, agent definitions, and a thin shell wrapper (`bin/spawn-session.sh`).

**The Main Agent is the orchestrator.** It reads a manifest, spawns session agents via `claude -p` subprocesses, merges their work, runs QA gates, and reports progress. It does NOT implement code itself.

**Why `claude -p` instead of the Agent tool?** Claude Code subagents cannot spawn other subagents — a platform constraint. Session agents need to spawn Explore subagents (haiku), plan reviewers, and code reviewers. By using `claude -p`, each session runs as a full main agent with complete tool access.

**Push complexity to the session agents, not the orchestrator.** The orchestrator handles only what agents cannot do for themselves:

| Orchestrator (Main Agent) does | Session Agent does |
|---|---|
| Parse manifest, build dependency graph | Explore codebase, plan implementation |
| Create worktrees, spawn `claude -p` sessions | Execute tasks (TDD, implementation, tests) |
| Merge session branches to feature branch | Spawn plan-reviewer and code-reviewer subagents |
| Run QA gates (build validation + browser smoke tests) | Run build verification within worktree |
| Handle failures (retry once, then ask user) | Diagnose and fix issues within session scope |
| Report progress to user, update progress.md | Write session status files, progress updates, and knowledge |
| Checkpoint before layers, rollback on QA failure | Commit to session branch |

### The Session Lifecycle

Each session agent autonomously executes this workflow (loaded via `/autoboard:session-workflow`):

1. **Explore** — Spawn Explore subagents to understand relevant code
2. **Plan** — Write implementation plan
3. **Plan Review** — Spawn independent plan-reviewer subagent; max 3 rounds
4. **Implement** — Execute plan task-by-task (TDD where marked: RED → GREEN → REFACTOR)
5. **Verify** — Run full build pipeline (configurable per-project)
6. **Code Review** — Spawn independent code-reviewer subagent; max 3 rounds
7. **Commit** — Commit each task, write session status file

### QA Gates

QA gates are checkpoints defined in the manifest at dependency layer boundaries. The orchestrator runs them between layers to catch compound errors before they propagate.

At each QA gate, the orchestrator spawns a QA subagent that invokes `/autoboard:verification --full`. This runs build validation, starts the dev server, and runs browser smoke tests using whatever browser tool is available (Playwright MCP, Vercel agent-browser, etc.). If no browser tool is installed, it falls back to build-only validation.

QA runs as a **subagent** to keep browser output out of the orchestrator's window.

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

- **No shell injection.** All subprocess calls in commands must use argument arrays — never string interpolation into shell commands.
- **Validate manifest input.** Task fields parsed from markdown are untrusted. Sanitize file paths, task IDs, and branch names.
- **Never commit to or push to `main`.** All git operations target session/feature branches only.
- **Preserve session branches on failure.** Never delete a session branch until its work is successfully merged.
- **Scoped session permissions.** Sessions run in `dontAsk` mode with project-specific allow/deny rules. Generated by `/autoboard:task-manifest` at `docs/autoboard/{slug}/session-permissions.json`. Fallback: `config/default-session-permissions.json`. Opt out: `skip-permissions: true` in manifest.

### Claude Code Friendliness

The codebase must be easily navigable by Claude Code.

- **Zero dead code.** No commented-out blocks, no unused functions, no orphaned imports.
- **Predictable naming.** Files, functions, and variables named so their purpose is obvious.
- **Small, focused files.** Each file has one clear responsibility.
- **Leave the codebase cleaner than you found it.**
