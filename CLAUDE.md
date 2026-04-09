# Autoboard

An AI engineering lead that manages a team of coding AIs so they don't cut corners.

Autoboard is a Claude Code plugin that decomposes features into parallel coding tasks, each with mandatory quality gates, then validates the integrated result with cross-task cohesion audits -- catching the problems that no individual task could see. The lead exercises judgment: it arbitrates review disputes, curates cross-layer knowledge, validates QA claims, and diagnoses failures before deciding how to respond.

**Architecture:** Skills-only plugin built on Claude Code Agent Teams. The Main Agent (Claude Code) is the lead -- the engineering lead. It reads a manifest, dispatches planning subagents, spawns implementation teammates via Agent Teams, merges results, and runs QA gates. The lead delegates all heavy work to subagents and teammates -- it stays a thin coordinator.

## How It Works

```
/autoboard:brainstorm  ->  design.md + standards.md (interactive design session)
/autoboard:standards   ->  standards.md (configure quality dimensions interactively)
/autoboard:task-manifest  ->  manifest.md (tasks, deps, QA gates)
/autoboard:run  ->  Lead orchestrates parallel teammates via Agent Teams
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

Changes to the repo are instantly reflected -- no copying needed.

## Repository Structure

Conventions -- don't enumerate every file, just know where to look:

- **`.claude-plugin/plugin.json`** -- Plugin manifest
- **`standards/dimensions/<name>.md`** -- One file per quality dimension (see `standards/README.md`)
- **`skills/<name>/SKILL.md`** -- Each skill lives in its own directory
- **`agents/<name>.md`** -- Subagent and teammate definitions
- **`docs/`** -- Reference docs and design specs

**Skills by role:**

| Role | Skills |
|---|---|
| User-facing | `brainstorm`, `standards`, `task-manifest`, `run` |
| Lead internals | `setup`, `qa-gate`, `qa-fixer`, `coherence-audit`, `coherence-fixer`, `completion`, `knowledge`, `audit` |
| Teammate/subagent | `verification`, `verification-light`, `receiving-review`, `diagnose` |

**Agent definitions:**

| Agent | Role |
|---|---|
| `autoboard-implementer` | Teammate: implements one task (Sonnet, default) |
| `autoboard-implementer-opus` | Teammate: implements one task (Opus, complexity 5) |
| `autoboard-implementer-opus-max` | Teammate: implements one task (Opus, complexity 8) |
| `autoboard-planner` | Subagent: explores codebase, writes batch plans |
| `plan-reviewer` | Subagent: reviews plans before implementation |
| `code-reviewer` | Subagent: reviews batch diffs after merge |
| `knowledge-curator` | Subagent: curates cross-layer knowledge |
| `qa-validator` | Subagent: classifies QA failures |
| `cohesion-screener` | Subagent: screens coherence findings |
| `evidence-gatherer` | Subagent: compresses failure evidence for lead |

**Runtime artifacts** (generated per-project at `docs/autoboard/<slug>/`, not checked in):
`design.md`, `standards.md`, `manifest.md`, `test-baseline.md`, `progress.md`, `decisions.md`, `architect-review.md`, `sessions/layer-{N}-knowledge.md`, `sessions/qa-L{N}.md`, `sessions/coherence-L{N}.md`

## Git Conventions

- **Never commit to or push to `main`.** All work happens on feature branches.
- Feature branch: `autoboard/<slug>` (e.g., `autoboard/user-auth`)
- Task worktrees: `/tmp/autoboard-{slug}-t{N}` -- created by lead, ephemeral
- Sequential merge: task work merges to feature branch one at a time
- One commit per task on the feature branch

---

## Architecture

**Main Agent = Lead.** It reads a manifest, dispatches planning subagents and implementation teammates via Agent Teams, merges their work, runs quality gates, and reports progress. It does NOT implement code itself.

| Lead does | Teammates/Subagents do |
|---|---|
| Parse manifest, compute dependency layers | |
| Dispatch planning subagent per batch | Explore codebase, write implementation plans |
| Dispatch plan-reviewer subagent | Review plans before code is written |
| Create worktrees, spawn teammates (one per task) | Implement one task each, verify, commit |
| Merge teammate work to feature branch | |
| Dispatch code-reviewer subagent per batch | Review merged diff against plan |
| Dispatch cohesion-audit subagent per layer | Check cross-task consistency |
| Dispatch QA subagent per layer | Run build verification and functional tests |
| Dispatch knowledge-curator per layer | Curate discoveries for next layer |
| Route failures, spawn fixer teammates | Diagnose and fix specific issues |

### Quality Gates (per layer)

Run in this order after all tasks in a layer are merged:

1. **Code review** (per batch) -- reviewer runs `git diff` itself, lead applies receiving-review
2. **Cohesion audit** (per layer) -- checks DRY, conventions, architecture across tasks
3. **Build verification** (every layer, always) -- lint, type-check, build, tests
4. **Functional QA** (when manifest defines it) -- browser/E2E tests with regression

### Model Selection

| Complexity | Name | Model | Effort |
|---|---|---|---|
| 1-3 | Rote/Guided/Considered | Sonnet | n/a |
| 5 | Tricky | Opus | high |
| 8 | Novel | Opus | max |

Planning always uses Opus. Reviews, QA, and cohesion use Sonnet.

---

## Non-Negotiable Standards

### Mandatory Review Gates

Two review gates are BLOCKING PREREQUISITES. Skipping either is a non-negotiable violation.

**Gate 1 -- Plan Review (before implementation):**
- Lead dispatches `plan-reviewer` subagent
- Lead critically evaluates feedback via receiving-review protocol
- Plan updated with accepted changes before teammates are spawned
- **NEVER spawn teammates without completing this gate**

**Gate 2 -- Code Review (after batch merge):**
- Lead dispatches `code-reviewer` subagent
- Lead critically evaluates feedback via receiving-review protocol
- Fixer teammates implement BLOCKING fixes, lead re-reviews
- **NEVER proceed to next gate without completing this gate**

**Receiving review feedback -- critical thinking protocol:**

| Thought that means STOP | Reality |
|---|---|
| "The reviewer said X, so I'll just do X" | Verify X is correct first. Reviewers can be wrong. |
| "I'll accept all suggestions to be safe" | Accepting wrong suggestions makes code worse, not better. |
| "This suggestion seems off but I'll do it anyway" | If it seems off, investigate. Trust your analysis. |
| "The plan looks good, I'll skip review" | Run the review subagent. Every time. No exceptions. |
| "Build passed, skip code review" | Run the code review subagent first. |

### Security

- **No shell injection.** All subprocess calls must use argument arrays -- never string interpolation into shell commands.
- **Validate manifest input.** Task fields parsed from markdown are untrusted. Sanitize file paths, task IDs, and branch names.
- **Preserve worktrees on failure.** Never delete a worktree until its work is successfully merged.

### Claude Code Friendliness

The codebase must be easily navigable by Claude Code.

- **Zero dead code.** No commented-out blocks, no unused functions, no orphaned imports.
- **Predictable naming.** Files, functions, and variables named so their purpose is obvious.
- **Small, focused files.** Each file has one clear responsibility.
- **Leave the codebase cleaner than you found it.**
