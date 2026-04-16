# Add CLI E2E Smoke Suite

Priority: high
Status: done
Estimate: M

## Goal
Core ThinkTank flows are verified through the built escript in temporary workspaces so contract regressions are caught at the real user entrypoint.

## Non-Goals
- Running live OpenRouter calls in every CI job
- Visual regression testing
- Replacing focused unit or integration tests

## Oracle
- [x] CI runs at least one escript-backed smoke path for `research` or `review eval`
- [x] Smoke tests assert exit codes plus generated artifacts such as `contract.json`, `manifest.json`, and summary output
- [x] Smoke coverage includes one stdin-fed command and one saved-contract replay
- [x] The smoke suite completes in under 60 seconds locally

## Notes
Current tests cover module-level contracts well, but they stop short of the built binary path. This item closes the last-mile verification gap.

## What Was Built
- `test/thinktank/e2e/smoke_test.exs` — two `:e2e`-tagged tests: stdin-fed `research --json --no-synthesis` and `review eval` saved-contract replay. Both run against the built `./thinktank` binary with a fake `pi` on `$PATH`, asserting exit codes, JSON envelope shape, `contract.json` and `manifest.json` contents, and absence of live-API markers on stdout/stderr.
- `test/support/fake_pi.ex` — shared `Thinktank.Test.FakePi` module (`with_fake_pi/2` + `subprocess_env/2`) that writes an executable fake `pi` script, mutates `PATH`, and yields a hermetic subprocess env (scrubs `OPENROUTER_API_KEY` and `THINKTANK_OPENROUTER_API_KEY`, disables muontrap). Now consumed by the existing integration test as well.
- `test/support/workspace.ex` — `Thinktank.Test.Workspace` with `unique_tmp_dir/1` (auto-cleanup via `on_exit`), `git!/2`, and `init_git_repo!/1`. Replaces duplicated helpers across two test modules.
- `mix.exs` — added `elixirc_paths/1` so `test/support` is compiled only under `MIX_ENV=test`.
- `test/test_helper.exs` — `ExUnit.configure(exclude: [:e2e])` keeps the default `mix test` fast; smoke suite opts in via `--include e2e` or the Dagger gate.
- `ci/src/thinktank_ci/main.py` — new `e2e_smoke` Dagger function that runs `mix escript.build` then executes the suite inside the `escript` cache lane; registered as a required `e2e-smoke` gate in `check/1`.
- `lib/thinktank/cli.ex` — `IO.read(:stdio, :all)` → `:eof`. Surfaced by the smoke suite: the Elixir 1.19 deprecation warning for `:all` was leaking onto stdout and corrupting `--json` envelopes for piped-stdin invocations. Fixed at the root.

### Workarounds / Deviations
- Stdin is piped to the escript via `/bin/sh -c '... < stdin_file'` rather than `Port.open`. `System.cmd` does not accept stdin input, and `Port.open` cannot half-close stdin — sending `{port, :close}` closes the whole port and the escript's `IO.read(:stdio, :eof)` never unblocks. Shell redirection gives the child a real piped, EOF-terminated stdin matching production. Stdin scratch file lives in a sibling tmp dir, not inside the workspace-under-test.
- Stderr is captured separately (redirected to a file) so JSON decoding only sees stdout. Stderr is independently scanned for `openrouter.ai` / `https://api.` sentinels as a defense-in-depth network-leak check.
