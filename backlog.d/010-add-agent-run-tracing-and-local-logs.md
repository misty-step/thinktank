# Add Agent Run Tracing And Local Logs

Priority: high
Status: done
Estimate: M

## Goal
Every ThinkTank run emits durable local traces and structured logs that explain slow, retried, timed-out, or failed agent executions without requiring GitHub or an external dashboard.

## Non-Goals
- Shipping a full third-party observability product integration on this branch
- Inspecting tool-level internals inside Pi beyond what the harness can observe from subprocess boundaries
- Changing review semantics, prompt strategy, or model selection except where required to expose trace data
- Replacing the existing `manifest.json` or artifact envelope contract

## Constraints / Invariants
- Local artifacts remain the source of truth for run forensics
- Trace writes must survive partial failures and degraded runs
- Logs must not write provider secrets or raw environment variable values
- Existing run artifacts and JSON envelopes remain backward compatible
- The first slice should prefer simple append-only files over new infrastructure

## Authority Order
tests > type system > code > docs > lore

## Repo Anchors
- `lib/thinktank/engine.ex` — owns run lifecycle boundaries and final status
- `lib/thinktank/executor/agentic.ex` — owns attempts, retries, and subprocess invocation
- `lib/thinktank/run_store.ex` — owns durable per-run artifacts and manifest updates
- `test/thinktank/executor/agentic_test.exs` — current executor coverage seam
- `test/thinktank/engine_test.exs` — current run-lifecycle coverage seam
- `docs/runbook.md` — operator-facing local workflow and troubleshooting

## Prior Art
- Phoenix local OTLP collector/UI for developer-first tracing
- Langfuse OTLP ingest for optional richer trace analysis later
- OpenTelemetry GenAI span conventions for naming and attributes, while the repo keeps a stable local JSON schema

## Oracle
- [x] `mix test test/thinktank/executor/agentic_test.exs test/thinktank/engine_test.exs test/thinktank/run_store_test.exs`
- [x] `mix compile --warnings-as-errors`
- [x] `mix credo --strict`
- [x] `mix dialyzer`
- [x] `DAGGER_NO_NAG=1 dagger call check`
- [x] A run writes a durable per-run trace artifact with lifecycle and subprocess timing events
- [x] A configured local log directory receives structured JSONL log entries keyed by run id
- [x] A failed or retried agent run records enough structured data to explain what happened without rereading source

## Implementation Sequence
1. Add a narrow tracing/logging module that appends normalized JSONL events to per-run artifacts and an optional rotating local log path.
2. Instrument run lifecycle boundaries in `Engine` and `Agentic` for run start/finish, agent start/finish, attempts, retries, and subprocess execution.
3. Expose trace artifacts through `RunStore` without changing the existing run envelope shape in breaking ways.
4. Add focused tests for success, retry/failure, and global log mirroring.
5. Document the local trace paths and troubleshooting workflow in the runbook and README if needed.

## Risk + Rollout
- Main risk: adding noisy or brittle logging in hot paths. Mitigation: keep the schema minimal, append-only, and covered by focused tests.
- Main privacy risk: leaking secrets through env capture. Mitigation: record env keys only and never env values.
- Rollback path: delete the trace module and the instrumentation calls; the existing manifest/artifact contract remains intact.

## What Was Built
- Added `Thinktank.TraceLog` as a local-first trace boundary that writes per-run `trace/events.jsonl` and `trace/summary.json`, plus an optional daily global JSONL mirror under `THINKTANK_LOG_DIR` or `~/.local/state/thinktank/logs/`.
- Instrumented `Engine` and `Agentic` to emit run, agent, attempt, retry, and subprocess events without widening the public CLI JSON contract.
- Registered the new trace artifacts in `RunStore` with stable content types and summary updates on completion.
- Hardened the trace path so logging failures fail open: warnings are emitted, `dropped_events` increments in the summary, and `last_trace_error` records the degraded write.
- Tightened file permissions for trace directories and files, documented operator queries and cleanup in the runbook, and documented the global mirror in the README.
- Added coverage for retry traces, timeout traces, disabled/default global log routing, private log permissions, corrupted summaries, and run lifecycle trace artifacts.

## Workarounds
- `proof` remained the slow reviewer class on this branch even after the observability work. A targeted local run completed in `206751 ms` on `2026-04-09`, while `sentry` completed in `49224 ms` on the final rerun. The new traces show that `proof` latency came from a single long first subprocess attempt, not from local retry churn.
- The final review loop used explicit reviewer overrides (`sentry`, `proof`) to avoid planner selection noise while validating the branch.
