# /deps in this repo — Thinktank dependency notes

## Ecosystem

**Elixir / Hex**, not npm/pip/cargo/go. `/deps` defaults to the package
manager it detects; in this repo that's `mix`.

Lockfile: `mix.lock`. Manifest: `mix.exs`. Hex registry:
https://hex.pm — tooling commands below.

## Current dependencies (mix.exs)

Runtime:
- `jason ~> 1.4` — JSON encode/decode. Load-bearing: contract/manifest
  artifacts are JSON.
- `yaml_elixir ~> 2.11` — reads user/repo config YAML.
- `muontrap ~> 1.6` — Pi subprocess launcher. Load-bearing: this is the
  core of `lib/thinktank/executor/agentic.ex`. A bad muontrap upgrade
  breaks every agent launch.

Dev/test:
- `credo ~> 1.7` (dev+test, `runtime: false`) — strict linter. Gate runs
  `mix credo --strict`.
- `dialyxir ~> 1.4` (dev+test, `runtime: false`) — static analysis. Gate
  runs `mix dialyzer`.
- `excoveralls ~> 0.18` (test) — coverage. Gate enforces 87% via
  `coveralls.json`.

Production Elixir target: `~> 1.17` (from mix.exs). Don't introduce
packages that require a newer minor without bumping the Elixir version
requirement in lock-step.

## Reachability / blast radius

- `muontrap` — ripped-through executor. Any upgrade needs a full local
  `dagger call check` + manual smoke of a research run (not just dry-run).
  Escript must be rebuilt (`mix escript.build`) before smoke.
- `jason` — touches every artifact write path (`run_store.ex`,
  `run_contract.ex`, manifest emission). Same smoke requirement.
- `yaml_elixir` — config loading only. Lower blast radius; config-only
  smoke (`./thinktank benches validate`) is usually enough.
- `credo`, `dialyxir`, `excoveralls` — dev-only. Upgrade freely, verify
  the gate still passes.

## Useful commands

```
mix deps.get
mix deps.update --all          # full upgrade — one curated PR only, never habitual
mix deps.update <package>      # targeted
mix hex.outdated                # what's behind
mix hex.audit                   # retired or flagged packages
mix deps.clean --unused
```

## Dialyzer PLT

Upgrading deps invalidates the PLT. First post-upgrade `mix dialyzer` run
will be slow (several minutes). This is not a failure — do not retry
thinking it hung. The Dagger gate caches the PLT between runs; local
runs rebuild it.

## Release hygiene

release-please generates the release PR from Conventional Commits. A
deps upgrade should be a single `chore(deps):` commit (or several, if you
split by scope) — not an unlabeled commit. `chore(deps): bump jason to
1.5.0` is good; `update packages` is noise release-please drops.

## Gotchas

- **Curated PR, not dependabot.** Per /deps doctrine and this repo's
  preference for deliberate upgrades, do one PR with reachability analysis
  for each non-trivial bump. Do not ship 47 one-line version bumps.
- **No unused deps.** Run `mix deps.clean --unused` and check the diff
  before shipping. This repo's deps list is small on purpose.
- **Don't add deps to solve one-off problems.** CLAUDE.md: "prefer
  deletion over new harness layers." A new dependency to shave one
  function is the wrong trade.
- **No npm/node deps.** If you find yourself reaching for a Node package,
  you're in the wrong layer — Pi is the reasoning plane, Elixir is the
  launcher plane.
- **Security advisories.** `mix hex.audit` is the primary path; gitleaks
  runs in the gate for secret scanning, not dep vulnerabilities.
