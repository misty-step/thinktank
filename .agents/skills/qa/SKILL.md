---
name: qa
description: |
  Verify ThinkTank CLI behavior and Gradient-managed harness changes. Use the
  repo-tailored `.claude/skills/qa` guidance for CLI behavior. Trigger: /qa.
argument-hint: "[paths|change]"
---

# /qa

ThinkTank QA is CLI and artifact-contract verification, not generic
docs/schema inspection. Exercise the command surface, dry-run behavior, run
artifacts, manifests, and review/replay contracts that changed.

## Gradient Use

For changes to `gradient.yaml`, `.gradient/`, generated schemas/profiles, or
Gradient-managed harness files, include:

```sh
gradient validate
```

For product or harness behavior, the backstop remains:

```sh
./scripts/with-colima.sh dagger call check
```

## Source Of Truth

Read `.claude/skills/qa/SKILL.md` for the repo-authored QA workflow. Gradient
validation is extra evidence; it is not a substitute for ThinkTank CLI checks.
