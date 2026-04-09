# Runbook

## Bootstrap

```bash
./scripts/setup.sh
```

For live model runs, export `THINKTANK_OPENROUTER_API_KEY` or add it to `.env`.

## Local Verification

```bash
./scripts/with-colima.sh dagger call check
./scripts/with-colima.sh dagger functions
```

`./scripts/with-colima.sh dagger call check` is authoritative. It includes the
repo-specific architecture gate, live model-ID validation, and an `87%`
coverage floor.

For targeted host-native debugging, the underlying Elixir gates are still:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
scripts/ci/architecture-gate.sh
./scripts/validate-elixir-models.sh
mix test
MIX_ENV=test mix coveralls
mix escript.build
./thinktank --help
```

## Common Commands

```bash
./thinktank research "inspect this subsystem" --paths ./lib
git diff | ./thinktank research --paths ./lib
./thinktank review --base origin/master --head HEAD
./thinktank review eval ./tmp/review-run --bench review/default
```

## Troubleshooting

- `input text is required`
  Use `--input`, positional text on `research`, or pipe stdin.
- Need to explain why a run was slow, retried, or failed
  Inspect `trace/events.jsonl` and `trace/summary.json` inside the run output
  directory first. For cross-run history, check the rotating JSONL files under
  `THINKTANK_LOG_DIR` or `~/.local/state/thinktank/logs/`.
  Event records are newline-delimited JSON with fields like `event`,
  `agent_name`, `attempt`, `status`, `duration_ms`, `error`, and `timestamp`.
  Useful queries:
  `jq -c 'select(.event=="agent_finished") | {agent_name,status,duration_ms,error}' trace/events.jsonl`
  `jq -c 'select(.event=="attempt_retry_scheduled") | {agent_name,attempt,next_attempt,error}' trace/events.jsonl`
  `jq -c 'select(.event=="subprocess_finished") | {agent_name,status,duration_ms,exit_code}' trace/events.jsonl`
  `jq -c 'select(.event=="run_completed") | {status,phase,error}' trace/events.jsonl`
  `jq '{dropped_events,last_trace_error}' trace/summary.json`
  If the run failed before the output directory was initialized, inspect the
  global log for bootstrap incidents instead:
  `jq -c 'select(.event=="bootstrap_failed") | {timestamp,bench,phase,output_dir,error}' "${THINKTANK_LOG_DIR:-$HOME/.local/state/thinktank/logs}"/*.jsonl`
  Treat any non-zero `dropped_events` as trace degradation: the run may still
  succeed, but the trace is incomplete and should not be treated as authoritative
  until the underlying logging failure is understood.
  Interrupted runs now close with `status="failed"` and `phase="shutdown"` so
  operator kills and VM shutdowns do not leave the manifest and trace summary in
  a perpetual `running` state.
  Global logs rotate by UTC day in this first slice but retention is
  operator-managed. Example cleanup:
  `find "${THINKTANK_LOG_DIR:-$HOME/.local/state/thinktank/logs}" -name '*.jsonl' -mtime +14 -delete`
- Missing API key
  Set `THINKTANK_OPENROUTER_API_KEY` before live runs.
- Repo config not loading
  Pass `--trust-repo-config` or set `THINKTANK_TRUST_REPO_CONFIG=1`.
- Need deterministic artifact paths
  Pass `--output <dir>` or inspect `output_dir` from `--json`.
- Dagger local CI fails before it starts
  Ensure `.env` exists at repo root, Colima is running, and the machine uses a
  standalone `docker` CLI instead of Docker Desktop's bundled client.
  `./scripts/with-colima.sh` will stop early with the exact missing piece.
- Pi subprocess runs hang or crash under MuonTrap
  Retry with `THINKTANK_DISABLE_MUONTRAP=1` to force the plain `System.cmd/3`
  runner while debugging the environment.
