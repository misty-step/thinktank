---
acceptance:
    - ThinkTank can validate a portable composition file that declares agents, runners, stages, reducers, and coverage requirements.
    - Existing built-in benches remain valid and do not require migration.
    - The composition schema does not support arbitrary conditionals, loops, or executable user code.
evidence_required:
    - mix test
    - ./scripts/with-colima.sh dagger call check
id: 033-add-benchfile-composition-contract
lifecycle_stage: Intent
status: ready
title: Add Benchfile Composition Contract
---

# Add Benchfile Composition Contract

Priority: high
Status: ready
Estimate: L

## Goal

Any caller can define a portable, validated agent composition as data, then hand it to ThinkTank for launch, inspection, and artifact capture.

## Non-Goals

- Replacing existing built-in bench config
- Adding a semantic workflow engine
- Supporting arbitrary conditionals, loops, or user-authored execution code
- Parsing dependencies out of agent prose

## Constraints / Invariants

- Benchfile is a composition declaration, not a workflow DSL.
- Existing `research/default` and `review/default` keep working unchanged.
- Agent definitions must include visible provider, model, role/persona, tools, timeout, and output expectations.
- Stages may express ordered fanout and reducers, but not hidden dynamic control flow.
- Validation must be structural before any agent launches.

## Repo Anchors

- `lib/thinktank/bench_spec.ex`
- `lib/thinktank/agent_spec.ex`
- `lib/thinktank/config.ex`
- `lib/thinktank/engine.ex`
- `lib/thinktank/engine/runtime.ex`
- `lib/thinktank/run_contract.ex`
- `docs/agent-composition-vision.md`

## Oracle

- [ ] `thinktank compose validate <Benchfile.yml>` validates agents, runners, stages, reducers, coverage requirements, and forbidden dynamic constructs.
- [ ] `thinktank compose run <Benchfile.yml> --input ... --json` launches the composition through the existing run lifecycle.
- [ ] Run artifacts include `graph.json` or equivalent metadata showing stages, edges, agents, reducers, and artifact lineage.
- [ ] Existing bench commands still pass their current tests without requiring Benchfile.
- [ ] Tests cover valid composition, invalid agent reference, invalid reducer reference, forbidden loop/conditional fields, and backward-compatible built-in bench behavior.

## Notes

This is the contract half of the "agent tmux powered by Benchfile" direction. It should make arbitrary composition possible without turning ThinkTank into Kubernetes-for-agents.
