# Add Live Progress Surface For JSON Runs

Priority: high
Status: done
Estimate: M

## Goal
Long-running `thinktank run ... --json` executions remain machine-safe on stdout while giving operators an explicit progress surface that makes "still running" distinguishable from "hung".

## Non-Goals
- Streaming partial JSON envelopes on stdout
- Replacing the existing per-run trace artifacts
- Inventing a second workflow engine or richer semantic phase model

## Constraints / Invariants
- Stdout stays reserved for the final JSON envelope when `--json` is set
- Progress must be visible before the first agent completes
- Existing artifact contracts (`manifest.json`, `trace/events.jsonl`, `trace/summary.json`) remain backward compatible
- Operator progress should degrade safely when stderr is redirected or suppressed

## Repo Anchors
- `lib/thinktank/cli.ex`
- `lib/thinktank/engine.ex`
- `lib/thinktank/run_store.ex`
- `lib/thinktank/trace_log.ex`
- `README.md`
- `docs/runbook.md`

## Oracle
- [x] A long-running `--json` run emits progress or heartbeat updates on stderr without corrupting stdout JSON
- [x] Operators can see the selected output directory and current phase before completion
- [x] A documented fallback exists for checking progress from another shell (`trace/events.jsonl` or equivalent)
- [x] Integration coverage protects the stdout/stderr contract for `--json`

## Notes
During portfolio research on 2026-04-10, a repo-aware `research/quick` run looked hung because `--json --no-synthesis` stayed silent until final completion. The run was healthy and trace-backed, but the operator had to inspect local artifacts manually to prove that. The issue is not run finalization; it is the lack of a first-class live progress surface for agent-first callers and human operators.

## What Was Built
- Added a stderr-only JSON progress surface for `thinktank ... --json` runs, with phase transitions, immediate and periodic heartbeats, output directory disclosure, and per-agent completion events while stdout stays reserved for the final envelope.
- Centralized progress event normalization in `Thinktank.Progress`, threaded progress callbacks through the review planner, executor, and engine lifecycle, and kept the CLI responsible for the actual stderr emission boundary.
- Documented the operator workflow in `README.md` and `docs/runbook.md`, expanded unit/integration/e2e coverage for the progress contract, and added a backlog-state gate in hooks plus Dagger so top-level items cannot be marked `done` before merge.
