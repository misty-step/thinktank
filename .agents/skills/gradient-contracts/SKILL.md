---
name: gradient-contracts
description: |
  Change Gradient-managed profile, schema, evidence, policy, or harness
  projection files inside ThinkTank without disturbing repo-owned product
  contracts. Trigger: /gradient-contracts.
argument-hint: "[path|change]"
---

# /gradient-contracts

Use this only for Gradient-managed files in ThinkTank: `gradient.yaml`,
`.gradient/`, generated schemas/profiles/evals/standards, and Gradient-native
skill or agent wrappers.

Rules:

- Preserve ThinkTank's Elixir/Pi launcher boundary from AGENTS.md.
- Do not replace `.agent/skills` as the repo-tailored source of truth.
- Keep Gradient lifecycle evidence additive to the repo gate.
- Run `gradient validate` after changes.
- Use `./scripts/with-colima.sh dagger call check` when the change affects
  product behavior, hooks, scripts, or merge readiness.
