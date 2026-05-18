---
name: refactor
description: |
  Simplify ThinkTank code, harness, or Gradient scaffold while preserving the
  thin Pi-launcher boundary. Use `.agent/skills/refactor` as authority.
  Trigger: /refactor.
argument-hint: "[--base <branch>] [--scope <path>] [--report-only] [--apply]"
---

# /refactor

Refactor only when it removes real complexity or clarifies a ThinkTank module
boundary. Do not introduce semantic workflow machinery, prose parsing, or a
second direct-API path around Pi.

Use `gradient validate` for Gradient-managed scaffold changes. Use
`./scripts/with-colima.sh dagger call check` for merge readiness.

Read `.agent/skills/refactor/SKILL.md` for the repo-authored workflow.
