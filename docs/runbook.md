# Runbook

## Bootstrap

```bash
./scripts/setup.sh
```

For live model runs, export `THINKTANK_OPENROUTER_API_KEY` or add it to `.env`.

## Local Verification

```bash
dagger call check
dagger functions
```

`dagger call check` is authoritative. It includes the repo-specific
architecture gate, live model-ID validation, and an `87%` coverage floor.

For targeted host-native debugging, the underlying Elixir gates are still:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
scripts/ci/architecture-gate.sh
./scripts/validate-elixir-models.sh
mix test
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
- Missing API key
  Set `THINKTANK_OPENROUTER_API_KEY` before live runs.
- Repo config not loading
  Pass `--trust-repo-config` or set `THINKTANK_TRUST_REPO_CONFIG=1`.
- Need deterministic artifact paths
  Pass `--output <dir>` or inspect `output_dir` from `--json`.
- Dagger local CI fails before it starts
  Ensure `.env` exists at repo root and Docker/Colima is running.
- Pi subprocess runs hang or crash under MuonTrap
  Retry with `THINKTANK_DISABLE_MUONTRAP=1` to force the plain `System.cmd/3`
  runner while debugging the environment.
