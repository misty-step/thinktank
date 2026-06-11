---
acceptance:
    - Agent execution is routed through a small adapter boundary while preserving current Pi CLI behavior by default.
    - A version-pinned RPC spike can be evaluated without changing bench semantics.
    - Adapter outputs map into the existing run result, trace, retry, timeout, and artifact contract.
evidence_required:
    - mix test
    - ./scripts/with-colima.sh dagger call check
id: 034-add-pi-family-runner-adapter
lifecycle_stage: Intent
status: ready
title: Add Pi-Family Runner Adapter
---

# Add Pi-Family Runner Adapter

Priority: medium
Status: ready
Estimate: M

## Goal

ThinkTank can treat the existing Pi CLI subprocess path as an explicit runner
adapter contract, then evaluate Pi RPC or experimental Oh My Pi RPC behind the
same result, trace, timeout, retry, artifact, and policy surfaces.

## Non-Goals

- Replacing ThinkTank with Oh My Pi
- Importing OMP's TUI, memory, editor, browser, or tool stack
- Adding a direct model API path that bypasses Pi-family agents
- Exposing transport flags before the adapter contract is stable

## Constraints / Invariants

- Default behavior remains the current Pi CLI subprocess path.
- Runner choice is config-driven for the spike, not a broad new CLI surface.
- All adapters must return the same result shape consumed by `RunStore`, `TraceLog`, and synthesis.
- RPC support must be version-pinned and fail closed when the protocol shape is unknown.
- Cost/usage gaps must be explicit if an adapter cannot supply equivalent metadata.
- Runner adapters inherit the permission and credential policy from `036`; no new adapter launches without policy evidence.

## Repo Anchors

- `lib/thinktank/executor/agentic.ex`
- `lib/thinktank/provider_spec.ex`
- `lib/thinktank/engine/runtime.ex`
- `lib/thinktank/run_store.ex`
- `test/thinktank/executor/agentic_test.exs`
- `docs/agent-composition-vision.md`

## Oracle

- [ ] Execution command construction is isolated behind a runner adapter module or protocol with Pi CLI as the only production adapter.
- [ ] Existing Pi CLI behavior is covered by unchanged or strengthened tests.
- [ ] A fake experimental RPC adapter test proves JSONL ready/prompt/event/response handling without live provider calls or broad CLI exposure.
- [ ] Adapter failures map to existing timeout/crash/run-error categories with trace events.
- [ ] Documentation states OMP/Pi RPC is an adapter/eval target, not a replacement architecture.

## Notes

OMP's `omp --mode rpc` and SDK are useful because they prove richer Pi-family
execution surfaces exist. The groomed sequencing is Pi CLI adapter first,
policy evidence second, RPC spike third.
