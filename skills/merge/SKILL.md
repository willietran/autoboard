---
name: merge
description: Squash-merge successful session branches to the feature branch — one commit per session, with conflict resolution and worktree lifecycle management
---

# Merge Successful Sessions

Merge each successful session to the feature branch, **one at a time** (sequential — no race conditions).

**Prerequisites:** Sessions in this layer have completed. The orchestrator has read each session's status file and identified which sessions succeeded.

---

## Merge Policy

**Squash merge.** One commit per session on the feature branch. Commit message: `S{N}: {session focus}`.

For each successful session in this layer:

```bash
cd {project-root}
git merge --squash autoboard/{slug}-s{N}
git commit -m "S{N}: {session focus}"
```

Merge sessions **sequentially** — never in parallel. Order does not matter for independent sessions in the same layer, but sequential execution prevents race conditions on the feature branch.

---

## Conflict Resolution

**On conflict:** Try auto-resolve strategies:

1. Run `git merge --squash autoboard/{slug}-s{N}` — if it fails with conflicts:
2. Check `git diff --name-only --diff-filter=U` for the list of conflicting files
3. For each conflicting file, attempt resolution:
   - If the conflict is whitespace or formatting only, accept the session's version
   - If the conflict is in generated files (lock files, build artifacts), accept the session's version
   - For all other conflicts, try `git checkout --theirs {file}` only if the file was not modified by a previously merged session in this layer
4. After auto-resolve attempts, check if conflicts remain with `git diff --check`
5. If unresolvable conflicts remain:
   - **Report to the user** with the full list of conflicting files and the sessions involved
   - **Never force-merge** — do not use `--force`, `-X theirs`, or any strategy that silently discards changes
   - Preserve the session branch and worktree for investigation
   - Abort the merge: `git merge --abort`
   - Block the run until the user resolves the conflict

---

## Worktree Lifecycle

### On Successful Merge

Clean up the session worktree and branch:

```bash
git worktree remove /tmp/autoboard-{slug}-s{N}
git branch -D autoboard/{slug}-s{N}
```

### On Failure

**NEVER delete the worktree or branch on failure.** This is non-negotiable. The worktree contains the session's work and is needed for:
- User investigation of conflicts
- Retry by the failure skill
- Manual resolution

Preserve both `/tmp/autoboard-{slug}-s{N}` (worktree) and `autoboard/{slug}-s{N}` (branch) intact.

---

## Tracking

After each successful merge, if tracking is active:

- **close-ticket**(session ticket, `"Merged to feature branch"`)

(`close-ticket` includes moving to Done — no separate `move-ticket` call needed.)

If merge fails, do NOT close or move the ticket — the failure skill handles ticket updates for failed sessions.

---

## After All Merges

Once all successful sessions in this layer are merged, proceed immediately to the coherence audit. Do NOT skip to the QA gate or next layer — the coherence audit must run after merge, before anything else.
