---
acceptance:
    - ThinkTank can validate a portable composition file that declares agents, runners, one fanout group, one reducer, and coverage requirements.
    - Existing built-in benches remain valid and do not require migration.
    - The composition schema does not support arbitrary conditionals, loops, or executable user code.
evidence_required:
    - mix test
    - ./scripts/with-colima.sh dagger call check
id: 033-add-benchfile-composition-contract
lifecycle_stage: Intent
status: ready
title: Add Flat Benchfile Composition Contract
---

# Add Flat Benchfile Composition Contract

Priority: high
Status: ready
Estimate: L

## Goal

Any caller can define a portable, validated flat agent composition as data,
then hand it to ThinkTank for launch, inspection, and artifact capture without
adding ordered stage graphs or semantic workflow logic.

## Non-Goals

- Replacing existing built-in bench config
- Adding a semantic workflow engine
- Supporting ordered multi-stage graphs, arbitrary conditionals, loops, or user-authored execution code
- Parsing dependencies out of agent prose

## Constraints / Invariants

- Benchfile is a composition declaration, not a workflow DSL.
- Existing `research/default` and `review/default` keep working unchanged.
- Agent definitions must include visible provider, model, role/persona, tools, timeout, and output expectations.
- The first contract supports one explicit fanout group plus at most one final reducer/synthesizer; graph metadata is lineage, not an executable stage graph.
- Validation must be structural before any agent launches.
- Runner permission policy from `036` must exist before high-risk compositions can launch.

## Repo Anchors

- `lib/thinktank/bench_spec.ex`
- `lib/thinktank/agent_spec.ex`
- `lib/thinktank/config.ex`
- `lib/thinktank/engine.ex`
- `lib/thinktank/engine/runtime.ex`
- `lib/thinktank/run_contract.ex`
- `docs/agent-composition-vision.md`

## Oracle

- [ ] `thinktank compose validate <Benchfile.yml>` validates agents, runners, one fanout group, one reducer, coverage requirements, and forbidden dynamic constructs.
- [ ] `thinktank compose run <Benchfile.yml> --input ... --json` launches the composition through the existing run lifecycle.
- [ ] Run artifacts include `graph.json` or equivalent metadata showing fanout agents, reducer, artifact lineage, and policy evidence without ordered stage semantics.
- [ ] Existing bench commands still pass their current tests without requiring Benchfile.
- [ ] Tests cover valid flat composition, invalid agent reference, invalid reducer reference, forbidden stage/loop/conditional fields, and backward-compatible built-in bench behavior.

## Notes

This is the contract half of the "agent tmux powered by Benchfile" direction,
but the first deliverable is deliberately flat. Do not pick this before the
Phase 1 evidence loop (`027`, `028`, `029`, `030`) and runner policy (`036`)
are strong enough to keep richer composition auditable.
