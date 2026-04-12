---
name: knowledge
description: Curate cross-session knowledge between layers — deduplicate, filter by relevance, resolve conflicts, and brief next-layer sessions
---

# Curate Knowledge for Next Layer

Synthesize what this layer built and brief the next layer with what they need to know. Do NOT pass session status files through verbatim — you are the engineering lead, curate what your reports need to know.

**Prerequisites:** All merges and the coherence audit for this layer have completed. You must have run the coherence audit. If the audit found no issues, that is fine — proceed with knowledge curation using session status files. If the audit found issues, incorporate them into the knowledge brief (what was fixed, what patterns to avoid).

---

## Dispatch Knowledge Curator

Dispatch the knowledge curator via your provider's subagent mechanism with model `explore-model` and these inputs. On Claude Code, use the `autoboard:knowledge-curator` agent directly. On Codex, spawn a read-only helper and tell it to read `$(cat /tmp/autoboard-{slug}-plugin-dir)/agents/knowledge-curator.md` before beginning:

- Session status file paths: `docs/autoboard/{slug}/sessions/s{N}-status.md` for each completed session in this layer
- Prior layer knowledge path: `docs/autoboard/{slug}/sessions/layer-{N-1}-knowledge.md` (or note "first layer" if Layer 0)
- Manifest path: `docs/autoboard/{slug}/manifest.md`
- Design doc path: `docs/autoboard/{slug}/design.md`
- Output file path: `docs/autoboard/{slug}/sessions/layer-{N}-knowledge.md`
- Decisions file path: `docs/autoboard/{slug}/decisions.md`

The agent reads all session status files and prior knowledge, synthesizes with deduplication, conflict detection, and resolution, then writes the curated knowledge file and appends to the decisions log.

It returns: `conflict_summary_with_resolutions` for your review.

---

## Validate Curator Output

Review the `conflict_summary_with_resolutions`. For each conflict resolution:
- Does the chosen pattern align with the design doc?
- Does the resolution correctly identify which session's pattern to follow?
- Are there conflicts the curator missed that you noticed during the run?

If any resolution is wrong, correct it by editing the relevant section in the knowledge file at `docs/autoboard/{slug}/sessions/layer-{N}-knowledge.md`. You have context the curator lacked (design doc intent, escalation outcomes, manifest-wide dependency knowledge).

Verify the knowledge file exists at `docs/autoboard/{slug}/sessions/layer-{N}-knowledge.md`.

---

## What This Enables

The spawn script injects `layer-{N}-knowledge.md` into each next-layer session's prompt via the `--knowledge` flag. This means next-layer sessions start with:
- Awareness of what was built (without reading all prior code)
- Clear conventions to follow (no conflicting patterns)
- Knowledge of shared utilities they should use (no reinvention)
