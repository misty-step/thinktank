---
name: agent-readiness
description: |
  Assess whether ThinkTank is ready for governed agent work across repo docs,
  harness bridges, Gradient scaffold, evidence, and gates. Trigger:
  /agent-readiness.
argument-hint: "[--report]"
---

# /agent-readiness

Assess ThinkTank against the facts agents need before changing code:

- AGENTS.md, README.md, CONTRIBUTING.md, CLAUDE.md, and relevant docs are
  coherent.
- `.agent/skills` remains the repo-tailored skill root, with `.claude`,
  `.codex`, and `.pi` bridges resolving correctly.
- Gradient-native files add lifecycle/evidence support without overriding
  ThinkTank's product guidance.
- The canonical merge-readiness gate is discoverable:

```sh
./scripts/with-colima.sh dagger call check
```

- Gradient-managed scaffold validates:

```sh
gradient validate
```

File concrete backlog work for any readiness gap instead of silently weakening
the harness.
