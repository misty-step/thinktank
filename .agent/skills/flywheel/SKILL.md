---
name: flywheel
description: |
  Outer-loop shipping orchestrator. Composes /deliver, landing, /deploy,
  /monitor, and /reflect cycle per backlog item, then applies reflect
  outputs to the harness and backlog before looping.
  Use when: "flywheel", "run the outer loop", "next N items",
  "overnight queue", "cycle".
  Trigger: /flywheel.
argument-hint: "[--max-cycles N]"
---

# /flywheel

Compose cycles of: pick a backlog item → `/deliver` → land → `/deploy` →
`/monitor` → `/reflect cycle` → apply reflect's outputs → loop.

You already know how to do each of these. This skill exists only to
encode the invariants that aren't inferable from the leaf names.

## Repo-specific (thinktank)

The shipping queue lives in `backlog.d/`, with active structural debt in
`015`, `016`, `017`, `018`, `020`, and `021`. `/deliver` closes against
`./scripts/with-colima.sh dagger call check`, `/settle` lands to `master`, and
Release Please owns the actual release PR and version bump after merge.

ThinkTank is usually a library/CLI repo, so deploy and monitor are often
no-ops. That does not justify inventing cycle state, event enums, or extra
orchestration machinery. Reflect outputs should mutate backlog and harness
files, not add a second control plane around the existing benches.

## Invariants

- Flywheel composes. Phase logic lives in the leaf skill.
- State lives in leaf receipts, git, and `backlog.d/`. Flywheel has none.
- Land before deploy. Always.
- Reflect's mutations (backlog + harness branch) land before the cycle
  closes. Harness edits never touch main.

## Gotchas

- `/deliver`'s receipt is the contract — don't peer inside.
- An item can be open in `backlog.d/` but already shipped in git. Fix
  the stale entry before starting a cycle on it.
- Library repos still land + reflect when deploy/monitor no-op.
- Two `/flywheel` runs in the same worktree collide on git state. Use
  separate worktrees for parallelism.

## Non-Goals

- No cycle state machine, event enum, lock, or pick scoring.
- No USD tracking — the orchestrator runs under subscription. USD is a
  concern of systems that pay per token (e.g. ThinkTank itself).
