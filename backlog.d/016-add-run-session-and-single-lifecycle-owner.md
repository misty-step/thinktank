# Add Run Session And Single Lifecycle Owner

Priority: high
Status: ready
Estimate: L

## Goal
Bench runs become easy to reason about because one deep module owns lifecycle sequencing, terminal status, trace emission, and finalization from bootstrap through shutdown.

## Non-Goals
- Changing the user-facing bench model or prompt content
- Reworking review planning in the same change
- Removing durable artifacts or shutdown recovery

## Constraints / Invariants
- `Thinktank.CLI` stays command/IO only and `Thinktank.Engine` stays bench resolution plus one execute call
- Terminal status and `run_completed` are written exactly once per run and derive from one code path
- `RunStore` remains storage-focused; it must not own lifecycle decisions
- Success, degraded, partial, failed, and shutdown paths keep the current external contract

## Repo Anchors
- `lib/thinktank/engine.ex`
- `lib/thinktank/engine/bootstrap.ex`
- `lib/thinktank/engine/runtime.ex`
- `lib/thinktank/run_tracker.ex`
- `lib/thinktank/run_store.ex`
- `lib/thinktank/trace_log.ex`

## Oracle
- [ ] A single lifecycle entrypoint such as `Thinktank.RunSession.execute/2` owns start -> prepare -> execute -> synthesize -> finalize sequencing
- [ ] Manifest status updates, `run_completed` trace emission, and shutdown finalization no longer depend on cross-module call ordering
- [ ] `Thinktank.Engine` delegates execution to the lifecycle owner instead of coordinating bootstrap/runtime/finalization itself
- [ ] Automated coverage proves complete, degraded, partial, failed, and shutdown termination through the new lifecycle owner

## Notes
Today the run lifecycle is split across bootstrap, runtime, tracker, store, and trace modules. That makes correctness depend on temporal discipline between modules instead of one deep API.
