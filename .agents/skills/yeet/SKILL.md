---
name: yeet
description: |
  Commit and push ThinkTank changes intentionally without bypassing hooks.
  Use `.agent/skills/yeet` as authority. Trigger: /yeet, /ship-local.
argument-hint: "[--push|--no-push]"
---

# /yeet

Group local ThinkTank changes into coherent conventional commits. Do not commit
stray Gradient scaffold churn without inspecting whether it belongs with the
work item. Never use `--no-verify` to bypass the repo gate.

Read `.agent/skills/yeet/SKILL.md` for the repo-authored workflow.
