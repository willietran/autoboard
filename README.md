# Autoboard

**Give it a feature. Walk away. Come back to code a senior engineer would approve.**

Autoboard is a Claude Code plugin that runs your entire build autonomously. You describe what you want, the lead breaks it into parallel coding tasks, and every task is independently reviewed, tested, and audited before anything merges. No babysitting. No reviewing every diff. No waking up to a mess.

It works because it applies the same principles Toyota used to revolutionize manufacturing: never let the builder inspect their own work, stop the line the moment something breaks, and never pass a defect downstream.

## Why You Can't Walk Away Today

You give Claude a big feature and leave it running. You come back to code that looks done but falls apart when you actually use it. Why?

- **Context rot** - As the context window fills, the agent gets dumber. Tests get skipped. Code gets sloppy. By hour two it's writing slop and doesn't know it.
- **No accountability** - The agent that wrote the code is the same one reviewing it. It will always tell you it did a good job.
- **Compounding errors** - Early code might not even work, but downstream tasks build on top of it assuming it does. By the time you notice, the whole thing is rotten from the foundation up.
- **Babysitting tax** - So you start reviewing every diff, re-running tests yourself, checking if the agent actually did what it said. Now you're doing the agent's job.

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


## How It Works

Three commands. The first two are interactive. The third runs autonomously.

```
/autoboard:brainstorm     →  Design session with you. Produces design doc + quality standards
/autoboard:task-manifest  →  Generates tasks, dependency graph, and QA gates
/autoboard:run <project>  →  You walk away here. Orchestrator handles the rest.
```

### What Happens While You're Gone

The lead breaks your feature into parallel coding tasks via Agent Teams. Each teammate works in its own git worktree with a fresh context window. A centralized planning subagent explores the codebase and writes plans for all tasks -- teammates just execute. No agent ever gets dumb from a bloated context. No agent ever reviews its own work.

The lead orchestrates each layer: **Plan** (centralized) -> **Plan Review** -> **Implement** (parallel teammates) -> **Merge** -> **Code Review** -> **Cohesion Audit** -> **Build Verification** -> **Functional QA** -> **Knowledge Curation**

Plan Review and Code Review are blocking gates run by independent reviewer agents. The lead applies a critical thinking protocol to evaluate findings -- reviews are a technical debate, not a rubber stamp.

Between each dependency layer, the lead runs automated QA (build, tests, browser smoke tests) and a 13-dimension coherence audit to catch cross-task issues like DRY violations, architecture drift, and naming inconsistencies. If anything fails, a fixer teammate resolves it before downstream work begins. No defect passes downstream.

[Anthropic's research on long-running agent harnesses](https://www.anthropic.com/engineering/harness-design-long-running-apps) independently validated this architecture. Separating generation from evaluation is the single most effective lever for preventing quality degradation.

```
Design Doc → Task Manifest
                 │
          ┌──────┴──────┐
          │  LAYER 0    │
          ├─────────────┤
          │ T1: Data    │
          │ T2: Auth    │  <- parallel
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
          │ T3: API     │
          │ T4: Logic   │  <- parallel
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
          │ T5: Dashboard│
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
| Context management | Fresh 200k context per task | Fresh teammate per task via Agent Teams in isolated worktrees |
| Plan review | Plan-checker validation loop (up to 3 iterations) | Independent plan-reviewer subagent, max 3 adversarial rounds |
| Code review | User acceptance testing | Independent code-reviewer subagent, mandatory before every commit |
| TDD | Not enforced | Per-task TDD phases where marked in manifest |
| Automated QA | Debug agents diagnose failures | Build + test + browser smoke tests between every layer |
| Cross-task coherence | STATE.md tracks decisions | 13-dimension audits at every layer boundary |
| Failure recovery | Debug agents + retry | Full fixer teammates with diagnose-first protocol |
| Knowledge curation | STATE.md + SUMMARY.md files | Deduplicated, conflict-resolved briefings between layers |
| Fabrication detection | Not addressed | Validates QA claims against allowlist, catches fake passes |

## Quality System

Quality is enforced across 13 configurable dimensions, tuned per-project during the brainstorm phase:

| Dimension | What It Checks |
|---|---|
| Code Organization | File structure, single responsibility, naming |
| DRY / Code Reuse | Duplication across tasks, shared patterns |
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

Standards are enforced by independent reviewer agents and coherence audits. Teammates cannot opt themselves out.

## The Orchestrator

The lead does not write code. It manages the agents that do. It decides which tasks to retry, whether a reviewer's concern is valid, whether a QA agent is lying about an infrastructure failure, and what knowledge the next layer of agents needs to do their job.

| Lead | Teammates / Subagents |
|---|---|
| Parses manifest, computes dependency layers | |
| Dispatches planning subagent per batch | Explore codebase, write implementation plans |
| Creates worktrees, spawns teammates | Implement one task each, verify, commit |
| Merges task work to feature branch | |
| Dispatches code reviewer, QA, cohesion audits | Review diffs, run tests, check consistency |
| Handles failures (retry, dispatch fixer, escalate) | Diagnose and fix issues within task scope |
| Curates knowledge between layers | Write discoveries, curate for next layer |

## Commands

| Command | Purpose | Produces |
|---|---|---|
| `/autoboard:brainstorm` | Interactive design session | `design.md` + `standards.md` |
| `/autoboard:standards` | Configure quality dimensions | `standards.md` |
| `/autoboard:task-manifest` | Generate implementation plan | `manifest.md` with tasks, deps, QA gates |
| `/autoboard:run <project>` | Launch orchestrator | PR-ready feature branch |

## Status

Autoboard is alpha software (v0.1.x). The architecture is stable but the surface area is still expanding. Expect rough edges.

## Acknowledgments

Autoboard builds on ideas and patterns from [Obra:Superpowers](https://github.com/obra/superpowers) by Jesse Vincent (MIT License), a fantastic project for giving Claude Code structured skills. The following components were adapted from Superpowers:

- **Brainstorm skill** (`skills/brainstorm/`): interactive design session workflow
- **Receiving review skill** (`skills/receiving-review/`): critical thinking protocol for processing review feedback
- **Code reviewer agent** (`agents/code-reviewer.md`): independent code review with quality checks
- **Systematic debugging skill** (`skills/diagnose/`): root cause investigation methodology

If you like what Autoboard does with agent orchestration, check out Superpowers for a broader collection of Claude Code skills.

## License

MIT
