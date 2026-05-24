---
acceptance:
    - ThinkTank can load named bench packs from repo-local or user-local config.
    - Bench packs preserve existing bench semantics and validation.
    - Built-in benches remain the default and no workflow DSL is introduced.
evidence_required:
    - mix test
    - ./scripts/with-colima.sh dagger call check
id: 031-support-bench-packs
lifecycle_stage: Intent
status: ready
title: Support Bench Packs
---

# Support Bench Packs

Priority: medium
Status: ready
Estimate: L

## Goal

Teams can share coherent sets of benches, agents, and defaults as named packs while ThinkTank stays a thin launcher over plain bench definitions.

## Non-Goals

- A plugin marketplace
- A stage graph language
- Dynamic planner-authored bench creation
- Runtime code loading from untrusted packages

## Constraints / Invariants

- Bench packs are config bundles, not executable extensions.
- Existing config precedence remains understandable: built-ins, user config, trusted repo config, then selected pack overlays if enabled.
- `benches validate` must validate selected packs exactly like built-ins.
- Pack names and source paths must be visible in `benches list` / `benches show`.

## Repo Anchors

- `lib/thinktank/config.ex`
- `lib/thinktank/bench_spec.ex`
- `lib/thinktank/agent_spec.ex`
- `lib/thinktank/bench_validation.ex`
- `priv/config/builtin.yml`
- `README.md`

## Oracle

- [ ] A user-local or repo-local pack can add focused benches without editing built-in config.
- [ ] `thinktank benches list` shows pack provenance for pack-provided benches.
- [ ] `thinktank benches validate` covers selected pack benches and reports pack-source errors clearly.
- [ ] Tests cover pack loading, precedence, invalid pack config, and trusted repo-config behavior.
- [ ] README explains bench packs as reusable config, not a workflow engine.

## Notes

Focused built-ins are the first product step. Bench packs are the scaling step: security pack, release-risk pack, incident pack, language-specific review pack, without adding new execution concepts.
