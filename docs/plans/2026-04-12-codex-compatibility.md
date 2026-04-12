# Codex Compatibility Implementation Plan

**Goal:** Make Autoboard run on Codex with the same operating model it already has on Claude Code:

- brainstorm -> task-manifest -> run
- walk-away autonomy
- isolated headless session workers
- mandatory review gates
- QA/coherence/fixer loops
- no regression in Claude behavior

This is a compatibility implementation, not a product redesign.

## Confirmed Codex Contract

The implementation should build around the behavior we actually verified:

- Codex headless workers run via `codex exec --json`
- `codex exec` supports `--ephemeral`, `-C`, `--full-auto`, `--dangerously-bypass-approvals-and-sandbox`, and `-c model_reasoning_effort=...`
- The orchestrator knows its current provider from runtime context; shell wrappers should not try to infer it from ambient environment variables
- Codex distribution uses `.codex-plugin/plugin.json`
- Repository-local Codex workers can discover the Autoboard skills through `.agents/skills/`
- Codex plugins package skills/apps/MCP metadata, but not a plugin-scoped custom agent system

## Task 1: Prove and Capture the Codex Worker Contract

Validate the Codex CLI behavior before wiring the compatibility layer:

- confirm `codex exec --json` works with stdin prompt input
- confirm `-C` selects the worktree correctly
- confirm reasoning effort can be overridden
- confirm the wrapper can emit machine-readable JSONL and exit cleanly

Record the contract in the design and plan docs so the implementation is anchored to observed behavior, not assumptions.

Validation:
- real `codex exec --json` smoke test returning a deterministic final message

## Task 2: Add the Codex Session Launcher and Spawn-Site Selection

Implement the narrow runtime seam:

- add `bin/spawn-codex-session.sh` with the same interface as `bin/spawn-session.sh`
- keep `bin/spawn-session.sh` as the Claude launcher
- add the repository-local Codex skill fallback so headless Codex workers launched inside a worktree can resolve Autoboard skills
- update `/autoboard:setup` so the current orchestrator writes the active provider and selected launcher path to temp files for the current run
- update all isolated-worker spawn sites to use the selected launcher path instead of assuming Claude:
  - `skills/session-spawn/SKILL.md`
  - `skills/qa-fixer/SKILL.md`
  - `skills/coherence-fixer/SKILL.md`
  - `skills/failure/SKILL.md`
  - any other skill that launches a full session worker

## Task 3: Make Skill Flows Provider-Aware Without Changing Behavior

Update the skill instructions so they still describe the same workflow while no longer assuming Claude-only tooling:

- session workers are isolated headless workers, not specifically `claude -p`
- Claude uses its packaged reviewer agents directly
- Codex uses built-in helper subagents plus the existing reviewer markdown files in `agents/` as rubrics
- QA/coherence/knowledge/task-manifest review flows dispatch helpers via the current provider’s subagent mechanism
- top-level packaging/docs/metadata describe official Codex packaging via `.codex-plugin/plugin.json` while keeping `--plugin-dir` framed as a local Claude development route

Primary files:
- `skills/session-workflow/SKILL.md`
- `skills/task-manifest/SKILL.md`
- `skills/qa-gate/SKILL.md`
- `skills/coherence-audit/SKILL.md`
- `skills/knowledge/SKILL.md`
- `skills/brainstorm/SKILL.md`
- `skills/audit/SKILL.md`
- `README.md`
- `CLAUDE.md`
- `package.json`
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `.codex-plugin/plugin.json`
- `.agents/skills`

## Task 4: Validate Runtime Parity

Run concrete validation, not just structural checks:

- shell syntax check for both launcher scripts
- Codex wrapper smoke test through `bin/spawn-codex-session.sh`
- Claude wrapper smoke test through `bin/spawn-session.sh`
- JSON validation for all package manifests
- spot-check the updated docs/skills for stale Claude-only instructions at the critical spawn/review paths

Expected result:
- Autoboard has an official Codex package manifest
- headless Codex workers launched inside the repo/worktree can resolve the Autoboard skills
- the orchestrator can spawn isolated Codex workers without changing the workflow
- reviewer/QA/coherence instructions are provider-aware
- Claude still runs through the existing launcher path
