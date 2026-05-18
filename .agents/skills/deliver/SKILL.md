---
name: deliver
description: |
  Take one ThinkTank backlog item to merge-ready code and evidence, stopping
  short of push, merge, or deploy. Use `.agent/skills/deliver` as authority.
  Trigger: /deliver.
argument-hint: "backlog.d/<item>.md"
---

# /deliver

Deliver one shaped ThinkTank backlog item. Preserve the Elixir/Pi launcher
boundary, add focused tests, run targeted checks during development, and finish
with the repo gate when feasible:

```sh
./scripts/with-colima.sh dagger call check
```

For Gradient scaffold/profile changes, include:

```sh
gradient validate
```

Read `.agent/skills/deliver/SKILL.md` for the composed repo workflow.
