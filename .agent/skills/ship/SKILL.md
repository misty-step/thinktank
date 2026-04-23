---
name: ship
description: |
  Final mile. Take the current candidate to shipped by running /ci,
  /code-review, and /refactor in parallel; fix and repeat until clean,
  green, and lean; squash-merge; run /reflect; apply the learning; finish.
  Use when: "ship it", "merge and close out", "final mile", "land and
  reflect", "finish this ticket".
  Trigger: /ship.
argument-hint: "[branch-or-pr]"
---

# /ship

`/ship` owns the last mile from candidate work to landed work. It is not a
preflight auditor. Normalize the current git state, run the verification triad,
fix what it finds, squash-merge, reflect, apply learning, and stop only when the
work is shipped or a real blocker remains.

## Repo-Specific

Primary branch is `master`. Release Please owns version bumps and release PRs.
Completed backlog items live under `backlog.d/done/`, but backlog association is
optional context, not permission to ship. Reflect harness edits belong on
`reflect/<cycle-id>`, never on `master`.

This repo does not ship `scripts/lib/backlog.sh` or `scripts/lib/verdicts.sh`.
Use direct git commands when archiving backlog files.

## Stance

1. Act. `/ship` should land complete work, not return a checklist.
2. The mandatory loop is `/ci`, `/code-review`, and `/refactor` in parallel.
3. Any fix from the loop lands on the shipping candidate, then the full triad
   reruns.
4. Continue until CI is green, review is clean, and refactor finds no worthwhile
   simplification.
5. Squash-merge only after the candidate is clean, green, and lean.
6. Run `/reflect cycle` after merge, then apply backlog learning on `master` and
   harness learning on `reflect/<cycle-id>`.

## Start State

Accept the work as it is:

- A named feature branch.
- A detached `HEAD`.
- A dirty worktree.
- A PR branch.
- A local-only branch.

Normalize enough to make the rest of the workflow executable:

- If a merge, rebase, cherry-pick, or revert is in progress, stop and surface
  the active operation.
- If `HEAD` is detached, create a local shipping branch such as
  `ship/<short-sha>-<timestamp>`.
- If the worktree is dirty, inspect the diff. If the dirty changes are part of
  the candidate, include them in the triad and commit them before merge. If they
  are clearly unrelated, preserve them on a separate WIP branch or stash with a
  descriptive message before continuing.
- If there is no upstream branch or PR, use git-native squash merge.
- If a PR exists, prefer GitHub squash merge after the triad is green. Do not let
  stale PR check state replace the local triad.

## Triad Loop

Dispatch three subagents in parallel with the candidate ref, base
`origin/master` when available, changed files, current `HEAD`, and a note about
any dirty worktree content:

| Subagent | Skill | Done Means |
|---|---|---|
| Green | `/ci` | `./scripts/with-colima.sh dagger call check` passes on the candidate |
| Clean | `/code-review` | no blocking findings remain |
| Lean | `/refactor` | no high-value simplification remains, or a bounded simplification landed |

Rules:

- Subagents must not merge, push, or rewrite history.
- If a subagent changes files, it owns a narrow file set and reports the exact
  paths it changed.
- After any code, doc, backlog, or harness-adjacent change, rerun all three
  subagents.
- Loop cap is three full passes. If the third pass still has a blocker, stop
  with the exact failing command, finding, or simplification request.
- The final report must name the command or artifact that exercised each changed
  executable path. Mark any materially changed executable path as unverified if
  no direct command exercised it.

## Candidate Cleanup

Before merge:

- Format and commit any accepted dirty changes or triad fixes.
- Sync existing docs only when the diff made them stale.
- Archive completed backlog files when there is an obvious shipped backlog ID
  from branch name, trailers, PR title/body, or touched backlog files. Missing
  backlog metadata is not a stop condition.
- Preserve existing `Closes-backlog:`, `Ships-backlog:`, and `Refs-backlog:`
  trailers with `git interpret-trailers`. Do not invent trailers solely to
  satisfy `/ship`.

## Squash Merge

Prefer GitHub mode when `gh pr view` succeeds for the candidate:

```sh
body="$(git log --format=%B origin/master..HEAD \
  | git interpret-trailers --parse --no-divider \
  | rg '^(Closes-backlog|Ships-backlog|Refs-backlog):' \
  | sort -u)"
if [ -n "$body" ]; then
  gh pr merge --squash --body "$body"
else
  gh pr merge --squash
fi
```

Use git-native fallback when there is no PR or GitHub is unavailable:

```sh
git fetch origin master
git checkout -B master origin/master
git merge --squash <candidate-branch>
git commit
```

If local `master` has local-only commits, preserve them before rebuilding
`master` from `origin/master`:

```sh
git branch backup/master-before-ship-<short-sha> master
```

After merge:

```sh
git checkout master
git pull --ff-only
```

Verify the squash commit contains any trailers that existed before merge.

## Reflect And Apply

Run `/reflect cycle` with:

- Pre-merge candidate ref.
- Merged `master` SHA.
- Closed backlog IDs, if known.
- Reference-only backlog IDs, if known.
- Triad evidence and any residual risk.

Apply reflect outputs:

- Backlog mutations land on `master` in a focused commit:
  `chore(backlog): apply reflect outputs from shipping <id-or-sha>`.
- Harness changes land on `reflect/<cycle-id>`, get committed there, and then
  checkout returns to `master`.
- Retro notes are captured in the reflect artifact or final report.

## Real Stop Conditions

Stop only when continuing would be unsafe or dishonest:

- A merge, rebase, cherry-pick, or revert is already in progress.
- The worktree has unresolved conflicts.
- The candidate cannot be identified or preserved as a branch.
- CI, review, or refactor still has a blocker after three full triad passes.
- Squash merge fails in a way that requires human credentials, permissions, or
  conflict resolution.
- Reflect cannot run or cannot write its required outputs.

## Output

```text
/ship complete

Merged:     <sha> on master (PR #<n> or git-native)
Candidate:  <branch-or-ref>
Closed:     <ids or none>
Referenced: <ids or none>
Docs:       <docs touched or none required>
Triad:      ci=<evidence>, review=<evidence>, refactor=<evidence>
Reflect:    <backlog mutations>, <harness branch>, <retro captured>
Residual:   <risks or none>
```

On stop, emit the blocker, the evidence, and the smallest action needed to
resume shipping.
