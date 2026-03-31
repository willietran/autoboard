# Autoboard

**Give it a feature. Walk away. Come back to code a senior engineer would approve.**

Autoboard is a Claude Code plugin that runs your entire build autonomously. You describe what you want, the orchestrator breaks it into parallel coding sessions, and every session is independently reviewed, tested, and audited before anything merges. No babysitting. No reviewing every diff. No waking up to a mess.

It works because it applies the same principles Toyota used to revolutionize manufacturing: never let the builder inspect their own work, stop the line the moment something breaks, and never pass a defect downstream.

## Why You Can't Walk Away Today

You give Claude a big feature and leave it running. You come back to code that looks done but falls apart when you actually use it. Why?

- **Context rot** - As the context window fills, the agent gets dumber. Tests get skipped. Code gets sloppy. By hour two it's writing slop and doesn't know it.
- **No accountability** - The agent that wrote the code is the same one reviewing it. It will always tell you it did a good job.
- **Compounding errors** - Early code might not even work, but downstream tasks build on top of it assuming it does. By the time you notice, the whole thing is rotten from the foundation up.
- **Babysitting tax** - So you start reviewing every diff, re-running tests yourself, checking if the agent actually did what it said. Now you're doing the agent's job.

## Installation

### Claude Code

Add the marketplace and install:

```
/plugin marketplace add willietran/autoboard
/plugin install autoboard@thelittlebyte
```

### Codex

Tell Codex:

> Fetch and follow instructions from https://raw.githubusercontent.com/willietran/autoboard/main/.codex/INSTALL.md

### Development

**Claude Code:** Clone the repo and use `--plugin-dir`:

```bash
alias claude="claude --plugin-dir /path/to/autoboard"
```

**Codex:** Symlink your checkout for live changes:
```bash
ln -sfn /path/to/autoboard/skills ~/.agents/skills/autoboard
```

## How It Works

Three commands. The first two are interactive. The third runs autonomously.

```
/autoboard:brainstorm     →  Design session with you. Produces design doc + quality standards
/autoboard:task-manifest  →  Generates sessions, dependency graph, and QA gates
/autoboard:run <project>  →  You walk away here. Orchestrator handles the rest.
```

### What Happens While You're Gone

The orchestrator breaks your feature into parallel coding sessions, each running in its own git worktree with a fresh context window. No agent ever gets dumb from a bloated context. No agent ever reviews its own work.

Every session follows the same enforced workflow:

**Explore** &rarr; **Plan** &rarr; **Plan Review** &rarr; **Implement** &rarr; **Verify** &rarr; **Code Review** &rarr; **Commit**

Plan Review and Code Review are blocking gates run by independent reviewer agents. The session agent is required to push back on bad feedback rather than blindly accepting. Reviews are a technical debate, not a rubber stamp.

Between each layer of sessions, the orchestrator runs automated QA (build, tests, browser smoke tests) and a 13-dimension coherence audit to catch cross-session issues like DRY violations, architecture drift, and naming inconsistencies. If anything fails, a fixer agent resolves it before downstream work begins. No defect passes downstream.

[Anthropic's research on long-running agent harnesses](https://www.anthropic.com/engineering/harness-design-long-running-apps) independently validated this architecture. Separating generation from evaluation is the single most effective lever for preventing quality degradation.

```
Design Doc → Task Manifest
                 │
          ┌──────┴──────┐
          │  LAYER 0    │
          ├─────────────┤
          │ S1: Data    │
          │ S2: Auth    │  ← parallel
          └──────┬──────┘
                 │
     ┌───────────┴───────────┐
     │ QA Gate + Coherence   │
     │ Audit                 │
     └───────────┬───────────┘
                 │
          ┌──────┴──────┐
          │  LAYER 1    │
          ├─────────────┤
          │ S3: API     │
          │ S4: Logic   │  ← parallel
          └──────┬──────┘
                 │
     ┌───────────┴───────────┐
     │ QA Gate + Coherence   │
     │ Audit                 │
     └───────────┬───────────┘
                 │
          ┌──────┴──────┐
          │  LAYER 2    │
          ├─────────────┤
          │ S5: Dashboard│
          └──────┬──────┘
                 │
     ┌───────────┴───────────┐
     │ Final QA + Coherence  │
     │ Audit                 │
     └───────────┬───────────┘
                 │
                 ▼
        PR-Ready Branch
```

### Fabrication Detection

QA agents lie. They claim "infrastructure failure" when they can't figure out how to test something, manufacturing a pass instead of reporting a real failure. The orchestrator validates every QA claim against an allowlist of known infrastructure issues and cross-references prior runs. Fabricated claims get caught. The QA runs again.

## Comparison

| Capability | GSD | Autoboard |
|---|---|---|
| Can you walk away? | No. ~15 commands to drive each phase | Yes. 3 commands, then autonomous |
| Context management | Fresh 200k context per task | Fresh `claude -p` per session in isolated worktrees |
| Plan review | Plan-checker validation loop (up to 3 iterations) | Independent plan-reviewer subagent, max 3 adversarial rounds |
| Code review | User acceptance testing | Independent code-reviewer subagent, mandatory before every commit |
| TDD | Not enforced | Per-task TDD phases where marked in manifest |
| Automated QA | Debug agents diagnose failures | Build + test + browser smoke tests between every layer |
| Cross-session coherence | STATE.md tracks decisions | 13-dimension audits at every layer boundary |
| Failure recovery | Debug agents + retry | Full fixer agents with complete 7-phase session workflow |
| Knowledge curation | STATE.md + SUMMARY.md files | Deduplicated, conflict-resolved briefings between layers |
| Fabrication detection | Not addressed | Validates QA claims against allowlist, catches fake passes |

## Quality System

Quality is enforced across 13 configurable dimensions, tuned per-project during the brainstorm phase:

| Dimension | What It Checks |
|---|---|
| Code Organization | File structure, single responsibility, naming |
| DRY / Code Reuse | Duplication across sessions, shared patterns |
| Error Handling | Consistent error patterns, recovery paths |
| Security | Input validation, injection prevention, secret management |
| Test Quality | Coverage, edge cases, error paths (not just happy path) |
| API Design | Consistent endpoints, status codes, pagination |
| Frontend Quality | Loading/error/empty states, component patterns |
| Type Safety | Strict types, no escape hatches, runtime validation |
| Data Modeling | Schema design, indexes, migration strategy |
| Performance | N+1 queries, unbounded results, unnecessary re-renders |
| Observability | Logging, health checks, error reporting |
| Config Management | Environment handling, secrets separation |
| Developer Infrastructure | Build tooling, scripts, local setup |

Standards are enforced by independent reviewer agents and coherence audits. Session agents cannot opt themselves out.

## The Orchestrator

The orchestrator does not write code. It manages the agents that do. It decides which sessions to retry, whether a reviewer's concern is valid, whether a QA agent is lying about an infrastructure failure, and what knowledge the next layer of agents needs to do their job.

| Orchestrator | Session agents |
|---|---|
| Parses manifest, builds dependency graph | Explore codebase, plan implementation |
| Creates worktrees, spawns sessions | Execute tasks (TDD, implementation, tests) |
| Merges session branches to feature branch | Spawn independent plan and code reviewers |
| Runs QA gates and coherence audits | Run build verification within worktree |
| Handles failures (retry, dispatch fixer, escalate) | Diagnose and fix issues within session scope |
| Curates knowledge, updates progress | Write session status files and learnings |

## Commands

| Command | Purpose | Produces |
|---|---|---|
| `/autoboard:brainstorm` | Interactive design session | `design.md` + `standards.md` |
| `/autoboard:standards` | Configure quality dimensions | `standards.md` |
| `/autoboard:task-manifest` | Generate implementation plan | `manifest.md` with sessions, deps, QA gates |
| `/autoboard:run <project>` | Launch orchestrator | PR-ready feature branch |

## Status

Autoboard is alpha software (v0.1.x). The architecture is stable but the surface area is still expanding. Expect rough edges.

## Acknowledgments

Autoboard builds on ideas and patterns from [Obra:Superpowers](https://github.com/obra/superpowers) by Jesse Vincent (MIT License), a fantastic project for giving Claude Code structured skills. The following components were adapted from Superpowers:

- **Brainstorm skill** (`skills/brainstorm/`): interactive design session workflow
- **Receiving review skill** (`skills/receiving-review/`): critical thinking protocol for processing review feedback
- **Code reviewer agent** (`agents/code-reviewer.md`): independent code review with quality checks
- **Systematic debugging skill** (`skills/diagnose/`): root cause investigation methodology

If you like what Autoboard does with session orchestration, check out Superpowers for a broader collection of Claude Code skills.

## License

MIT
