---
name: ship
description: |
  Final-mile ThinkTank landing workflow. Use `.agent/skills/ship` as authority.
  Trigger: /ship.
argument-hint: "[work-item|branch]"
---

# /ship

Shipping ThinkTank means the branch is clean, reviewed, simplified, and green
against the canonical Dagger gate. Gradient validation is required when
Gradient-managed scaffold, profile, schema, evidence, or policy files changed.

Read `.agent/skills/ship/SKILL.md` before merging or moving backlog items.
