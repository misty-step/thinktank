---
name: settle
description: |
  Unblock and polish a ThinkTank branch through review, gate, QA, and
  simplification. Use `.agent/skills/settle` as authority. Trigger: /settle.
argument-hint: "[PR|branch|work-item]"
---

# /settle

Settle ThinkTank work by resolving concrete failures, review findings, and gate
issues without lowering quality thresholds. Use the Dagger gate for product
readiness and `gradient validate` for Gradient-managed scaffold changes.

Read `.agent/skills/settle/SKILL.md` for landing policy and branch handling.
