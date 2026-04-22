# Add Run Inspection And Explicit Run State Commands

Priority: high
Status: done
Estimate: M

## Goal
Operators can inspect, tail, and wait on research and review runs through first-class CLI commands because ThinkTank exposes explicit machine-readable run state instead of making users infer liveness from sparse artifacts.

## Non-Goals
- Building a web dashboard or TUI
- Replacing `trace/events.jsonl` with a second live-status system
- Adding semantic workflow phases or orchestration layers
- Changing the raw artifact contract for existing runs beyond additive state fields

## Constraints / Invariants
- Run state must derive from the canonical lifecycle owner and trace/manifest contract, not from guessing based on `review.md`, `summary.md`, or file timing
- The commands must work for both research and review runs
- `--json` output stays machine-safe and additive
- Existing run directories remain consumable; old runs degrade gracefully when newer state fields are absent
- This item should build on, not bypass, `015` and `016`

## Repo Anchors
- `lib/thinktank/cli.ex`
- `lib/thinktank/cli/parser.ex`
- `lib/thinktank/cli/render.ex`
- `lib/thinktank/run_tracker.ex`
- `lib/thinktank/run_store.ex`
- `lib/thinktank/trace_log.ex`
- `README.md`

## Oracle
- [x] `thinktank runs list` shows recent local runs with bench, status, start time, and output directory
- [x] `thinktank runs show <path-or-id>` reports a typed state (`running`, `complete`, `degraded`, `partial`, `failed`) without requiring manual trace-file inspection
- [x] `thinktank runs wait <path-or-id>` blocks until terminal state and exits deterministically based on the final run status
- [x] JSON output for the new commands is additive and documented in `README.md`
- [x] Automated coverage proves the commands against complete, degraded, partial, failed, and still-running runs

## Notes
Today the README tells operators to tail `trace/events.jsonl` directly to inspect a live run. That is a useful escape hatch, but not a good product default. Research and review both feel less trustworthy when completion and liveness are implicit.

This item is the UX layer on top of the contract work in `015` and `016`: once run-state is explicit and lifecycle ownership is centralized, ThinkTank should surface that state directly instead of forcing users to reason from artifacts.

## What Was Built
- Added `thinktank runs list`, `thinktank runs show <path-or-id>`, and `thinktank runs wait <path-or-id>` on top of the existing manifest/trace contract instead of inventing a second state system.
- Added `Thinktank.RunInspector` to discover recent local runs, resolve a run by path or id, read typed state from durable artifacts, and wait until terminal state.
- Extended the CLI help text and JSON/text renderers so run inspection stays machine-safe under `--json` and readable in plain text.
- Documented the new inspection flow in `README.md`, keeping raw trace tailing as an escape hatch rather than the primary UX.
- Added coverage for complete, degraded, partial, failed, and still-running runs, plus CLI parsing and exit-code behavior for the new commands.
