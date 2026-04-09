---
name: standards
description: Configure quality standards for a autoboard project -- view, edit, or regenerate the standards.md file that gets injected into teammate prompts. Use when starting a project, adjusting quality settings, or reviewing what standards are active.
---

# Quality Standards Configuration

Interactively configure the quality standards that teammates follow during implementation.

## HARD GATE

**This skill only modifies `standards.md`.** It does not implement code or generate designs.

## When to Use

- Starting a new project and want to customize quality settings beyond the brainstorm defaults
- Adjusting quality dimensions mid-project (adding, removing, or customizing)
- Reviewing what standards are currently active and what they enforce
- Creating custom dimensions for project-specific quality concerns

## Process Flow

### 1. Find the Project

- If a `<slug>` is provided, look for `docs/autoboard/<slug>/standards.md`
- If no slug, check for the most recent autoboard project or ask the user which project
- If no `standards.md` exists yet, offer to generate one by pulling from dimension templates in `standards/dimensions/`

### 2. Show Current Standards

Display the contents of `standards.md` in a readable format, summarizing which dimensions are included.

### 3. Interactive Configuration

Ask the user what they'd like to adjust. Common operations:

**Add a dimension:**
- Read the dimension template from `standards/dimensions/{name}.md`
- Extract the Principle, Criteria, Common Violations, and Language-Specific Guidance for the project's languages
- Append the new section to `standards.md`

**Remove a dimension:**
- Delete the dimension's section from `standards.md`
- Explain what won't be checked as a result

**Explore a dimension:**
- "What does type-safety check for?"
- Read and present the full dimension template conversationally

**Customize a dimension:**
- "I want stricter DRY rules" or "Relax test-quality for the prototype phase"
- Edit the dimension's section directly in `standards.md`

**Add a custom dimension:**
- "I want a dimension for accessibility"
- Write a new section in `standards.md` following the standard structure (Principle, Criteria, Common Violations)

### 4. Save and Confirm

After each change:
1. Update `standards.md`
2. Show the updated configuration
3. Ask if there's anything else to adjust

## Key Principles

- **One change at a time** — don't overwhelm with all options at once
- **Explain trade-offs** — when removing a dimension, explain what won't be checked
- **No judgment** — removing dimensions is legitimate, not a quality failure
- **Show examples** — when exploring a dimension, show concrete criteria so the user knows what they're opting into/out of
