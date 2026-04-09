# Autoboard Ecosystem

## User Commands

- `/autoboard:brainstorm` -- Interactive design session producing design doc + standards
- `/autoboard:standards` -- Configure quality dimensions interactively
- `/autoboard:task-manifest` -- Generate task manifest from design doc
- `/autoboard:run` -- Launch orchestrator

## Lead Phases (internal, called by run)

- `setup` -- Project resolution, manifest parsing, preflight checks
- `coherence-audit` -- Cross-task quality audit (wraps `/autoboard:audit`)
- `coherence-fixer` -- Fix blocking coherence issues
- `qa-gate` -- Acceptance testing and regression checks
- `qa-fixer` -- Fix QA gate failures
- `knowledge` -- Curate cross-layer knowledge between layers
- `completion` -- Final cleanup and reporting

## Teammate/Subagent Skills

- `verification` -- Build/test verification protocol (preflight, light, full modes)
- `verification-light` -- Build/test only verification for teammates
- `receiving-review` -- Critical thinking protocol for review feedback
- `diagnose` -- Root cause investigation protocol

## Agents

### Teammates (spawned via Agent Teams)

- `autoboard-implementer` -- Default teammate (Sonnet, complexity 1-3)
- `autoboard-implementer-opus` -- Opus teammate (complexity 5, effort high)
- `autoboard-implementer-opus-max` -- Opus teammate (complexity 8, effort max)

### Subagents (dispatched via Agent tool)

- `autoboard-planner` -- Explore codebase, write batch implementation plans
- `plan-reviewer` -- Plan review with quality dimension checks
- `code-reviewer` -- Code review with quality dimension checks
- `evidence-gatherer` -- Compress failure evidence for lead classification
- `qa-validator` -- Validate QA-REPORT failures (fabrication, premature, genuine)
- `cohesion-screener` -- Pre-screen coherence findings via receiving-review decision tree
- `knowledge-curator` -- Synthesize cross-layer knowledge between layers
