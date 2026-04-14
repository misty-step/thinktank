# Investigation: 2026-04-10

## Scope
Validate the ThinkTank failure modes surfaced during portfolio research and write down only the issues that were actually reproduced.

## Confirmed

- `--json` runs are too quiet for long operator loops.
  A repo-aware `research/quick` run stayed silent on stdout until completion, which made a healthy long-running job look hung unless the operator tailed `trace/events.jsonl` or inspected `manifest.json`.
- The project-level architecture story has drifted.
  `AGENTS.md`, `CLAUDE.md`, and the thin-launcher ADR all describe ThinkTank as a thin Pi bench launcher, while `project.md` still presents older router/dispatch/output concepts as if they were the current system.
- Runtime hardening backlog remains open.
  CLI smoke coverage, command-plane architecture gates, and security gating are still tracked as ready backlog items (`007`, `008`, `009`).

## Not Reproduced

- Interrupted runs staying in perpetual `running` state.
  A fresh SIGTERM repro finalized correctly: the manifest was marked failed, `completed_at` was set, and the trace recorded a shutdown-shaped terminal event. Treat the older stale `/tmp/thinktank-agent-tools` directory as inconclusive historical residue, not current evidence of an active finalization bug.

## Follow-ups Opened

- `backlog.d/011-add-live-progress-surface-for-json-runs.md`
- `backlog.d/012-align-project-docs-with-thin-launcher-architecture.md`

## Takeaway
The current problem is not that ThinkTank is failing to close runs. The current problem is that the machine contract is ahead of the operator experience, and one of the top-level docs is behind the actual architecture.
