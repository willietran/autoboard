# Quality Standards

Template library for autoboard's quality dimensions. Each dimension file defines criteria that session agents and reviewers enforce.

## How It Works

1. **Brainstorm** generates a `standards.md` for each project by pulling relevant dimensions from this template library
2. **Orchestrator** injects `standards.md` verbatim into each session agent's prompt
3. **Session agents** follow the standards during implementation
4. **Session agents** inline the standards into reviewer prompts when dispatching plan-reviewer and code-reviewer subagents
5. **Reviewers** check plans and code against the standards in their prompt

No YAML config, no path resolution at runtime. Every hop is explicit content injection.

## Dimension File Structure

Each file in `dimensions/` is a template with:

- **Principle** — One-sentence language-agnostic rule
- **Criteria** — Specific, checkable rubric items
- **Common Violations** — What to flag (drawn from real failures)
- **Language-Specific Guidance** — Examples for Python, TypeScript, Go, etc.
- **Opt-Out Justification** — When it's legitimate to skip this dimension

## Adding a New Dimension

1. Create a new file in `dimensions/` following the structure above
2. The brainstorm skill will automatically detect and include relevant dimensions when generating `standards.md`

## Customizing Standards

Users edit `standards.md` directly — it's plain markdown. Use `/autoboard:standards` to interactively add, remove, or modify dimensions.
