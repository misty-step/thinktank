---
name: groom
description: |
  Shape ThinkTank backlog around thin-launcher debt and command-plane
  simplification. Use `.agent/skills/groom` as authority. Trigger: /groom.
argument-hint: "[topic|backlog item]"
---

# /groom

Groom backlog items in `backlog.d/` with ThinkTank's boundaries in mind:
launcher thinness, Pi execution, artifact contracts, review replay, and gate
policy. Gradient can track work and evidence, but it should not turn ThinkTank
into a separate workflow engine.

Read `.agent/skills/groom/SKILL.md` for the repo-authored backlog workflow.
