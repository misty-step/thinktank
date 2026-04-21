# Add Run Session And Single Lifecycle Owner

Priority: high
Status: done
Estimate: L

## What Was Built
- Introduced a single lifecycle owner, `Thinktank.RunSession.execute/2`, that now owns bootstrap, execute, terminal status emission, and finalization sequencing for bench runs.
- Reduced `Thinktank.Engine` to resolution plus one execute call, narrowed `Thinktank.Engine.Runtime` to execution/status derivation, and removed bootstrap-local finalization so terminal state comes from one path.
- Hardened finalization so post-bootstrap terminal writes stay fail-open, and made shutdown finalization authoritative by refusing to overwrite runs that `RunTracker` has already finalized and unregistered.
- Added lifecycle coverage for complete, degraded, partial, failed, bootstrap-after-init failure, and shutdown-in-flight termination through the centralized owner.

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
