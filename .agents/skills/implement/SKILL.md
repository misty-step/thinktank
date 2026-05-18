---
name: implement
description: |
  Implement ThinkTank backlog work in Elixir with tests and repo gate evidence.
  Use the repo-tailored `.agent/skills/implement` guidance as authority.
  Trigger: /implement, /build.
argument-hint: "[context-packet-path|task]"
---

# /implement

Implementation in ThinkTank is Elixir product and harness work. Keep changes
small, test behavior rather than internals, and preserve the thin-launcher
boundary: workspace, launch, sandbox, timeout, artifacts, and records belong in
Elixir; model execution goes through Pi.

## Verification

Use targeted commands while developing:

```sh
mix test
mix compile --warnings-as-errors
mix escript.build
```

Before merge readiness, use:

```sh
./scripts/with-colima.sh dagger call check
```

For Gradient-managed profile or scaffold changes, also run:

```sh
gradient validate
```

## Source Of Truth

Read `.agent/skills/implement/SKILL.md` for the full repo-authored TDD workflow.
Do not use generic Gradient docs/schema implementation guidance for ThinkTank
product changes.
