# /ci in this repo — Thinktank gate notes

The load-bearing CI command in this repo is a single invocation:

```
./scripts/with-colima.sh dagger call check
```

Everything else is either a pre-stage of that, a host-native fallback, or
diagnostic. Never treat `mix test` alone as "CI passed" — the merge-readiness
bar is the Dagger gate, which enforces additional checks `mix test` does not.

## What `dagger call check` actually runs

Enforced by the containerized gate (see `dagger.json` and the Dagger pipeline
module under `ci/`):

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix credo --strict`
- `mix dialyzer` (with plt cached by Dagger)
- shell + YAML hygiene
- gitleaks
- repo-owned security gate
- **live OpenRouter model-ID validation** — hits the OpenRouter catalog to
  confirm every agent's declared `model:` is still served. Failures here
  are real: the catalog rotates frequently. Fix by updating the model ID
  in `agent_config/` / `lib/thinktank/builtin.ex`, not by bypassing.
- architecture gate (enforces command-plane / launcher boundary — see
  `CLAUDE.md` non-goals)
- escript smoke (`mix escript.build` + run)
- `mix coveralls` with an **87% coverage floor** (configured in
  `coveralls.json`)

The native pre-push hook (`.githooks/pre-push`) runs the same command. If the
hook fires, CI will fire. If the hook passes, CI almost always passes.

## Host-native fallback (debugging only)

When Colima/Docker/Dagger is unavailable or you need faster feedback on a
single check:

```
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
MIX_ENV=test mix coveralls            # coverage debugging
mix dialyzer                          # slow first run, fast thereafter
```

These are the pieces; `dagger call check` is the gate. Do not claim CI is
green based on host-native output alone.

## Diagnostic: listing individual Dagger functions

```
./scripts/with-colima.sh dagger functions
```

Use when you want to rerun only one stage of the gate (e.g. just Dialyzer
after a PLT change) rather than the full pipeline.

## Gotchas

- **Colima must be running.** `./scripts/with-colima.sh` starts it if needed
  and exports the correct docker socket. Do not point Docker Desktop at
  Dagger — the wrapper actively rejects that path to keep one runtime.
- **`.env` seeding.** A fresh worktree without `.env` gets one copied from
  `.env.example` by the wrapper. If a gate fails with a missing env var on
  a fresh checkout, that's the root cause.
- **`THINKTANK_OPENROUTER_API_KEY` is required for the live model-ID check.**
  Export it before running `dagger call check` locally, or the catalog
  validation stage will fail for a reason unrelated to your diff.
- **Coverage floor is 87%, not 80%.** If a refactor drops coverage below
  87%, that's a gate failure, not a warning. Add the tests.
- **`THINKTANK_DISABLE_MUONTRAP=1`** forces the plain `System.cmd/3` runner
  instead of muontrap for Pi subprocesses — useful only for local debugging
  when muontrap is being flaky. Never set in CI.
- **Architecture gate failures are load-bearing.** If the gate rejects a
  change for crossing the command-plane boundary, that's CLAUDE.md's
  non-goals (no semantic workflow DSL, no regex recovery, no stage graph)
  firing. Fix the architecture, don't silence the gate.

## Invariants (do not lower)

Per CLAUDE.md and AGENTS.md "Red Lines":

- 87% coverage threshold stays at 87%.
- `credo --strict` stays strict.
- Compile warnings stay as errors.
- `dagger call check` is the single source of truth for merge-readiness.
  Split-brain gates (different checks locally vs in CI) are forbidden.
