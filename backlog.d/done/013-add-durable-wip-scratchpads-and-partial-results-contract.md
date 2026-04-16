# Add Durable WIP Scratchpads And Partial-Result Contract

Priority: high
Status: done
Estimate: M

## Goal
Long-running ThinkTank runs remain useful when stopped early: every run and every spawned agent writes durable work-in-progress artifacts that survive timeout, interruption, or crash, and the CLI can finalize those runs as `partial` instead of leaving the operator with only a silent wait and a trace log.

## Non-Goals
- Turning ThinkTank into a semantic workflow engine
- Streaming full partial JSON envelopes on stdout
- Replacing the existing completed-run artifact contract
- Inventing agent-specific scratchpad semantics beyond durable append-only notes

## Constraints / Invariants
- `partial` must never be presented as `complete`
- Stdout remains reserved for the final JSON envelope when `--json` is set
- Existing completed-run artifact paths remain backward compatible
- Artifact paths stay stable for the lifetime of the run
- WIP persistence is append-oriented and crash-safe; timeout should bound wait time, not erase useful artifacts
- Scratchpads follow the same security and redaction posture as existing artifacts
- The thin-launcher boundary remains intact: launch, sandbox, timeout, and record in ThinkTank; reasoning stays in Pi

## Repo Anchors
- `lib/thinktank/cli.ex`
- `lib/thinktank/engine.ex`
- `lib/thinktank/executor/agentic.ex`
- `lib/thinktank/run_store.ex`
- `lib/thinktank/trace_log.ex`
- `README.md`
- `test/thinktank/e2e/smoke_test.exs`

## Oracle
- [ ] Every run creates a run-level scratchpad at start with at least `status`, `mode`, `started_at`, prompt/task metadata, and `output_dir`
- [ ] Every spawned agent creates its own scratchpad at start and appends incremental findings or status notes during execution
- [ ] Scratchpad content survives cancellation, timeout, or process crash
- [ ] When a run ends early, the final envelope and manifest mark it `partial` and point to the available scratchpads/artifacts
- [ ] Research benches and review benches both support the partial-result contract
- [ ] If synthesis is unavailable, ThinkTank can still emit a best-effort partial summary from the artifacts that exist and label it `partial`
- [ ] Integration coverage protects the stdout/stderr/final-envelope contract for `--json` runs with partial completion

## Notes
This is adjacent to `011-add-live-progress-surface-for-json-runs.md` but not the same problem. `011` is about live visibility during a healthy long-running run. This item is about preserving useful bench output when the caller times out, interrupts the run, or decides the wait is no longer worth it.

The operator expectation that emerged during architecture research is clear: for research and code-review benches, ThinkTank should start writing useful run-level and agent-level scratchpads early enough that an interrupted run still leaves behind actionable artifacts instead of only a trace and some rendered prompts.

## What Was Built
- Added durable run-level and per-agent scratchpads plus per-agent stream artifacts that are created early and updated throughout execution.
- Added first-class `partial` finalization with best-effort summary synthesis for timed-out, interrupted, and synthesis-incomplete runs.
- Extended the JSON/text run contract, shutdown finalization, README, and automated tests to treat partial results as durable operator-facing artifacts instead of generic failures.
