---
name: harness
description: |
  Maintain ThinkTank's repo-local agent harness and Gradient projection without
  splitting the source of truth. Trigger: /harness.
argument-hint: "[audit|repair|paths]"
---

# /harness

ThinkTank's repo-tailored harness authority is `.agent/skills`, bridged into
`.claude/skills`, `.codex/skills`, and `.pi/skills`. Gradient-native skills
under `.agents/skills` provide Gradient lifecycle support and wrappers; they
must not contradict the repo-authored skills.

When changing harness files:

```sh
gradient validate
```

When claiming merge readiness:

```sh
./scripts/with-colima.sh dagger call check
```

Keep agent files free of hardcoded model IDs, model families, and reasoning
tiers unless the runtime layer explicitly owns that choice.
