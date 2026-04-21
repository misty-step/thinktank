# Fix Review Eval And Finished Review Contract

Priority: high
Status: done
Estimate: M

## What Was Built
- Taught `Thinktank.Review.Eval` to normalize replay targets across three explicit source shapes: direct `contract.json` paths, directories of saved contracts, and finished review run directories rooted at a ThinkTank output path.
- Added terminal-state detection from `manifest.json` / `trace/summary.json` so live review directories return a typed `review_eval_in_progress` error instead of falling through to misleading missing-artifact failures.
- Expanded eval coverage to lock finished terminal states, asymmetric manifest/trace state handling, and the saved-contract-directory fallback boundary.
- Updated `README.md` so replay-source normalization and "wait for terminal run state before replaying" are part of the operator-facing contract.

## Goal
Completed review work can be consumed reliably because `thinktank review eval` normalizes replay sources and finished review run directories into one contract, while live runs surface an explicit in-progress state instead of looking broken.

## Non-Goals
- Replacing the existing review bench or reviewer selection logic
- Inventing a richer workflow engine or new semantic phase model
- Inferring completion from `agents/`, `review.md`, or `summary.md` appearing early
- Reworking the stderr progress surface added in `011`

## Constraints / Invariants
- `thinktank review eval` stays a replay/consumption tool, not a live status streamer
- It must accept a direct `contract.json`, a directory of saved contracts, or a finished `thinktank review --output <dir>` run directory
- Mid-run directories may stay sparse for minutes; completion must come from terminal run state, not artifact timing
- `--json` stdout stays machine-safe and remains the final envelope boundary
- The thin-launcher line stays intact: ThinkTank launches, records, and reports; Pi does the reasoning

## Repo Anchors
- `lib/thinktank/cli.ex`
- `lib/thinktank/review/eval.ex`
- `lib/thinktank/run_store.ex`
- `lib/thinktank/trace_log.ex`
- `README.md`
- `lib/thinktank/engine/runtime.ex`

## Oracle
- [ ] A direct `contract.json` path still replays successfully through `thinktank review eval`
- [ ] A completed review run directory from `thinktank review --base <ref> --head <ref> --output <dir> --json` can be consumed by `thinktank review eval <dir>` without crashing
- [ ] A live or incomplete review run directory fails with an explicit in-progress signal instead of nil crashes or misleading missing-artifact diagnoses
- [ ] README and CLI-facing guidance explain replay-source normalization and state that callers should watch stderr progress or terminal trace state to decide whether a run is finished
- [ ] Automated coverage proves all three source types: saved contract, finished run dir, and live run dir

## Notes
Observed on 2026-04-18 while reviewing `memory-engine`.

Two separate failures surfaced:
- `thinktank review eval /tmp/memory-engine-tt-review-09 --bench review/default` crashed with `IO.chardata_to_string(nil)` from `lib/thinktank/review/eval.ex:45`
- A healthy live run looked broken because the output directory stayed sparse for a long time, even though stderr progress and `trace/events.jsonl` showed the run was still alive

The old `memory-engine-tt-review-09` run was actually complete and had synthesized output in `review.md` and `summary.md`; the problem was not "missing synthesis" but a combination of broken post-run eval and a misleading artifact-timing contract.

The root need is reliable consumption of completed review work, not a richer workflow. Keep the command narrow, but make its accepted source types and finished-vs-live behavior explicit.
