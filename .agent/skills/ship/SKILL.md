---
name: ship
description: |
  Final mile. Take a merge-ready branch to shipped: squash-merge, archive
  the backlog ticket(s), sync touched docs, run /reflect, and apply its
  outputs. Assumes /settle already left the branch merge-ready — ship does
  not run CI, code-review, or refactor itself. If those are not done, run
  /settle first.
  Use when: "ship it", "merge and close out", "final mile", "land and
  reflect", "finish this ticket".
  Trigger: /ship.
argument-hint: "[branch-or-pr]"
---

# /ship

The final mile. Branch is merge-ready; `/ship` lands it, archives the
ticket(s), syncs docs, runs `/reflect`, and threads reflect's outputs back
into the repo. One command from "green" to "shipped and learned from."

## Repo-specific (thinktank)

Primary branch is `master`. Completed backlog items live under
`backlog.d/done/`, not `backlog.d/_done/`. ThinkTank feature branches are
normally named `feat/<id>`, `fix/<id>`, `chore/<id>`, `refactor/<id>`,
`docs/<id>`, `test/<id>`, or `perf/<id>`; allow an optional `-slug`
suffix, but the numeric capture is still the primary backlog ID. Release
Please owns version bumps and release PRs. `/reflect cycle` may propose
harness edits, but those must land on `reflect/<cycle-id>`, never on
`master`.

This repo does not ship `scripts/lib/backlog.sh` or `scripts/lib/verdicts.sh`.
Archive tickets with direct `git mv`, and treat existing backlog trailers as
optional metadata to preserve, not a required local helper contract.

## Stance

1. Act, do not propose. `/ship` has authority within its domain: archive,
   merge, pull, reflect, apply.
2. Pre-merge prep belongs on the shipping branch. Archive moves and doc
   syncs happen before the squash so the merge records one clean closure
   event.
3. `/ship` is not `/settle`. If merge-readiness is in doubt, refuse and
   route the operator back to `/settle`.
4. Reflect's harness edits never touch `master`. They go to
   `reflect/<cycle-id>` for human review.

## Prerequisites

Assert these first; refuse on any miss.

- On a feature branch, not `master`.
- Branch name matches
  `^(feat|fix|chore|refactor|docs|test|perf)/(\\d+)(-.+)?$`.
- Working tree clean.
- If a PR exists, `gh pr view --json mergeable,mergeStateStatus` reports
  mergeable and `gh pr checks` is green.
- `/settle` has already left the branch merge-ready. In git-native mode,
  require a recent clean `./scripts/with-colima.sh dagger call check` on
  the current `HEAD`.
- The primary backlog ID exists as a top-level `backlog.d/<id>-*.md` file,
  or the branch commits contain explicit `Closes-backlog:` /
  `Ships-backlog:` trailers. Shipping with no backlog association is a
  refuse condition.

## Process

### 1. Extract backlog IDs

Primary ID comes from the branch regex capture. Then scan branch commits for
trailers:

```sh
git log --format=%B master..HEAD \
  | git interpret-trailers --parse --no-divider
```

Collect:

- Closing set: primary ID plus every `Closes-backlog:` and
  `Ships-backlog:` value.
- Reference set: every `Refs-backlog:` value.

If the repo has no trailer practice on the branch, that is fine. Close the
primary ID and preserve any trailers only when they already exist.

### 2. Archive backlog files on the shipping branch

For each ID in the closing set, locate a top-level backlog file:

```sh
file="$(rg --files backlog.d | rg "^backlog\\.d/${id}-.*\\.md$" | head -n1)"
```

If `file` exists, move it:

```sh
git mv "$file" backlog.d/done/
```

Rules:

- Already archived in `backlog.d/done/` is fine; skip silently.
- Missing file is acceptable only when the ID came from trailers or the
  ticket was closure-only. Note it in the final report.
- If the primary ID has no file and the branch has no closing trailers,
  refuse.

### 3. Sync touched docs

Inspect the diff:

```sh
git diff master..HEAD --name-only
```

If existing docs were made stale by the shipped change, update them on the
shipping branch before merge. Do not invent new docs just to satisfy the
step. If no obvious docs need syncing, note that and continue.

### 4. Create the archive commit on the feature branch

If archiving or doc sync produced changes, commit them as one focused
closure commit:

```sh
git commit -m "chore(backlog): archive shipped tickets"
```

If branch commits already carry backlog trailers, preserve them on this
commit with `git interpret-trailers --if-exists addIfDifferent`. Do not
hand-format trailer blocks.

### 5. Squash-merge

GitHub mode is preferred when `gh pr view` succeeds for the branch.

If backlog trailers exist on the branch, pass them explicitly in the squash
body so GitHub does not drop them:

```sh
body="$(git log --format=%B master..HEAD \
  | git interpret-trailers --parse --no-divider \
  | rg '^(Closes-backlog|Ships-backlog|Refs-backlog):' \
  | sort -u)"
gh pr merge --squash --body "$body"
```

If there are no trailers, merge with the repo's normal squash subject/body
convention.

Git-native fallback:

```sh
git checkout master
git merge --squash <branch>
git commit
```

### 6. Pull `master` and verify closure

After merge:

```sh
git checkout master
git pull --ff-only
```

Verify:

- Every closable backlog file now lives under `backlog.d/done/`.
- If trailers were present before merge, they survived into the squash
  commit.

If trailer preservation failed, stop and surface it. Do not pretend the
closeout is complete.

### 7. Invoke `/reflect cycle`

Run `/reflect cycle` scoped to the shipped work and pass:

- Pre-merge branch name
- Merged `master` SHA
- Closing backlog IDs
- Reference-only backlog IDs

Capture:

- Backlog mutations
- Harness-tuning proposals
- Retro notes and coaching output

### 8. Apply reflect's backlog mutations on `master`

If reflect proposes new tickets or edits to open tickets, apply them on
`master` and commit:

```text
chore(backlog): apply reflect outputs from shipping <primary-id>
```

If reflect proposes no backlog mutations, skip this step.

### 9. Apply harness outputs to `reflect/<cycle-id>`

Reflect's harness edits never land on `master`. Create or update the branch
named by the reflect cycle contract:

```sh
git checkout -B reflect/<cycle-id> master
```

Apply only the harness changes there, commit them, push the branch, then
return to `master`.

### 10. Final report

Emit one plain-text block covering:

- Merged SHA on `master` and PR number if GitHub mode
- Closed backlog IDs
- Reference-only backlog IDs
- Docs touched, or `none required`
- Reflect outputs by category: backlog mutations, harness proposals, retro
- Harness branch name
- Residual risks or follow-ups

## Refuse Conditions

Stop and surface the reason instead of shipping when:

- Branch name does not yield a primary backlog ID.
- Working tree is dirty.
- Current branch is `master`.
- PR is conflicted, blocked, or has failing checks.
- `/settle` clearly has not been run yet.
- Primary backlog ID has no top-level backlog file and the branch carries no
  closing trailers.
- Rebase, merge, or cherry-pick is already in progress.
- The branch was already shipped and deleted upstream.

## Trailer Conventions

When trailers exist, preserve these keys exactly:

- `Closes-backlog: <id>`
- `Ships-backlog: <id>`
- `Refs-backlog: <id>`

IDs are bare numeric strings such as `023`. Inject trailers with
`git interpret-trailers`, never by hand.

## GitHub Mode vs Git-Native Mode

| Mode | Detection | Merge command |
|---|---|---|
| GitHub | `gh` available and `gh pr view` succeeds | `gh pr merge --squash` |
| Git-native | no PR, no `gh`, or no GitHub remote | `git merge --squash <branch>` |

GitHub mode is preferred because the PR timeline records the merge.

## Interactions

- Upstream: `/settle` leaves the branch merge-ready.
- Invokes: `/reflect cycle`.
- Invoked by: `/flywheel` as the landing and reflection stage.
- Complements `/yeet`: `/yeet` ships the worktree to the remote; `/ship`
  ships the settled branch to `master`.

## Gotchas

- ThinkTank archives to `backlog.d/done/`, not `_done/`.
- ThinkTank branch names are usually `feat/023`, not `feat/023-slug`.
- This repo does not provide backlog or verdict helper scripts. Use direct
  `git mv` and explicit PR or CI checks.
- GitHub's default squash body can drop trailers. Pass an explicit body when
  trailers matter.
- Archive before merge, not after. Splitting closure across two commits makes
  backlog history harder to trust.
- Reflect harness edits belong on `reflect/<cycle-id>`, never on `master`.
- Re-running `/ship` on an already merged branch should exit early, not try
  to archive or reflect twice.

## Output

```text
/ship complete

Merged:     <sha> on master (PR #<n>)
Closed:     023
Referenced: none
Docs:       AGENTS.md (synced)
Reflect:    1 backlog mutation applied, 2 harness proposals on
            reflect/<cycle-id>, retro captured
Residual:   none
```

On refuse, emit the reason and the action needed to re-enable shipping.
