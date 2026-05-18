---
name: ci
description: |
  ThinkTank CI gate wrapper for Gradient-managed work. Use the repo-tailored
  `.agent/skills/ci` guidance as the authority. Trigger: /ci, /gates.
argument-hint: "[--audit-only|--run-only]"
---

# /ci

ThinkTank's canonical gate is:

```sh
./scripts/with-colima.sh dagger call check
```

That gate is the merge-readiness contract. It covers formatting, compile
warnings as errors, `credo --strict`, Dialyzer, shell/YAML hygiene, gitleaks,
the repo-owned security gate, harness-agent checks, live model-ID validation,
architecture checks, escript smoke, and the 87% coverage floor.

## Gradient Use

For Gradient-managed work, run:

```sh
gradient validate
```

as the Gradient profile/harness validation layer. It does not replace the
ThinkTank Dagger gate.

## Source Of Truth

Read `.agent/skills/ci/SKILL.md` before auditing or running gates. If this file
and `.agent/skills/ci/SKILL.md` disagree, the `.agent` skill wins for
ThinkTank-specific behavior.
