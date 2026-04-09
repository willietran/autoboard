---
name: knowledge
description: Curate cross-task knowledge between layers - dispatch the knowledge-curator agent, then clean up per-task files
---

# Curate Knowledge for Next Layer

After each layer completes (all quality gates passed), dispatch the knowledge curator to synthesize per-task discoveries into a single layer knowledge file.

**Prerequisites:** All merges, code review, cohesion audit, and QA for this layer have completed.

---

## Gather Task Knowledge File Paths

Glob for `/tmp/autoboard-{slug}-t*-knowledge.md` to find all per-task knowledge files from this layer's tasks. Each teammate writes one of these before completing their task.

If no per-task knowledge files exist for this layer, skip curation entirely.

---

## Dispatch Knowledge Curator

Dispatch the `knowledge-curator` agent via the Agent tool with these inputs:

- **Slug and layer number**
- **Per-task knowledge file paths** from the glob above
- **Prior layer knowledge path:** `docs/autoboard/{slug}/sessions/layer-{N-1}-knowledge.md` (or note "first layer" if Layer 1)
- **Output file path:** `docs/autoboard/{slug}/sessions/layer-{N}-knowledge.md`

The curator reads all per-task files and prior knowledge, deduplicates, filters for relevance, resolves conflicts, and writes a self-contained layer knowledge file. Max 10 entries. Only things not obvious from reading the code: utilities created or found, gotchas, surprising constraints.

---

## Clean Up Per-Task Files

After the curator writes the layer knowledge file, delete all per-task knowledge files from this layer's tasks (`/tmp/autoboard-{slug}-t*-knowledge.md` for the relevant task IDs). These are consumed -- the layer file is the canonical record.

---

## How Knowledge Gets Consumed

The planning subagent for the next layer gets `@layer-{N}-knowledge.md` in its prompt. Teammates get knowledge indirectly through the plan. The lead holds only a one-line summary, not the full file.
