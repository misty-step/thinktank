---
name: code-review
description: |
  Review ThinkTank changes for launcher-boundary regressions, artifact contract
  drift, review bench behavior, and Gradient harness consistency. Trigger:
  /code-review, /review, /critique.
argument-hint: "[branch|diff|files]"
---

# /code-review

ThinkTank review is code and harness review for a thin Pi-backed bench
launcher. Prioritize bugs, behavioral regressions, artifact contract drift,
missing tests, and any move toward a second workflow engine or direct model API
path that bypasses Pi.

## Required Checks

1. CLI and engine boundaries: `lib/thinktank/cli.ex`,
   `lib/thinktank/engine.ex`, and `lib/thinktank/builtin.ex` stay thin and
   explicit.
2. Runtime boundary: agent execution still flows through
   `lib/thinktank/executor/agentic.ex` and Pi.
3. Artifacts: `run_store`, `artifact_layout`, and `trace_log` preserve durable
   local contracts.
4. Review planning/replay: `review/planner.ex` and `review/eval.ex` keep
   structured contracts instead of prose parsing.
5. Gates: use `./scripts/with-colima.sh dagger call check` for merge
   readiness, with `gradient validate` for Gradient-managed scaffold changes.

## Source Of Truth

Read `.agent/skills/code-review/SKILL.md` before reviewing. If this generated
Gradient-native wrapper disagrees with the repo-authored skill, the `.agent`
skill wins for ThinkTank-specific review behavior.
