---
acceptance:
    - Gradient-generated guidance names ThinkTank's Elixir stack, Pi launcher boundary, existing `.agent/skills` root, and canonical Dagger gate.
    - Gradient-native skills do not contradict ThinkTank's repo-tailored CI, QA, demo, review, or implementation skills.
    - The Gradient repo-scan records the real package manifests and verification commands.
evidence_required:
    - AGENTS.gradient.md review
    - .gradient/init/repo-scan.json review
    - generated repo-guide review
    - gradient readiness
    - gradient validate
id: 002-improve-agent-readiness
lifecycle_stage: Policy/Eval
status: ready
title: Improve agent readiness from Gradient init scan
---

# Improve Agent Readiness

Priority: medium
Status: ready
Estimate: S

## Init Scan Findings

- Initial Gradient init missed Elixir, `mix.exs`, `mix.lock`, Dagger, and the
  existing `.agent/skills` shared skill root.
- Initial generated CI, QA, demo, implementation, and review guidance described
  Gradient's own docs/schema repository instead of ThinkTank's Elixir CLI.
- The scaffold validated structurally even though the agent-facing content was
  semantically wrong for this repository.

## Repo Anchors

- `AGENTS.gradient.md`
- `gradient.yaml`
- `.gradient/init/repo-scan.json`
- `.agents/agents/repo-guide.md`
- `.agent/skills/ci/SKILL.md`
