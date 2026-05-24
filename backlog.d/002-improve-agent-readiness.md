---
acceptance:
    - Spellbook-facing guidance names ThinkTank's Elixir stack, Pi launcher boundary, existing `.agent/skills` root, and canonical Dagger gate.
    - Spellbook skills do not contradict ThinkTank's repo-tailored CI, QA, demo, review, or implementation skills.
    - Repo-local guidance records the real package manifests and verification commands without depending on retired scaffold state.
evidence_required:
    - AGENTS.md review
    - .agent/skills/ci/SKILL.md review
    - mix test
id: 002-improve-agent-readiness
lifecycle_stage: Policy/Eval
status: ready
title: Improve Spellbook Agent Readiness
---

# Improve Spellbook Agent Readiness

Priority: medium
Status: ready
Estimate: S

## Readiness Findings

- Historical generated guidance missed Elixir, `mix.exs`, `mix.lock`, Dagger,
  and the existing `.agent/skills` shared skill root.
- Retired generated guidance should stay removed so this repo treats Spellbook
  as the work-loop layer.
- The readiness surface should describe ThinkTank's Elixir CLI, Pi launcher
  boundary, artifact contracts, and Dagger gate directly.

## Repo Anchors

- `AGENTS.md`
- `README.md`
- `project.md`
- `.agent/skills/ci/SKILL.md`
