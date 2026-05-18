---
name: diagnose
description: |
  Diagnose ThinkTank trace, artifact, runtime, model-validation, and Gradient
  scaffold failures using real evidence. Use `.agent/skills/diagnose` as
  authority. Trigger: /diagnose.
argument-hint: "<symptom or failing artifact>"
---

# /diagnose

Start from a live failure, trace it through the relevant ThinkTank module, and
fix the root cause when scoped. For Gradient-managed files, also check
`gradient validate`; for product readiness, use the Dagger gate.

Read `.agent/skills/diagnose/SKILL.md` for the full repo-authored protocol.
