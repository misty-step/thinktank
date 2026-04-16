# AGENTS.md

Map, not manual.

## What ThinkTank Is

ThinkTank is a thin Pi bench launcher for research and review.

- Agents are configured in code or YAML
- Benches are named sets of agents
- ThinkTank launches Pi, captures raw outputs, and records artifacts

## What ThinkTank Is Not

- Not a semantic workflow engine
- Not a stage graph DSL
- Not a prose parser
- Not a second direct-API path that bypasses Pi

## Architecture

- `lib/thinktank/cli.ex` — CLI surface
- `lib/thinktank/engine.ex` — bench resolution and launch
- `lib/thinktank/builtin.ex` — built-in agents and benches
- `lib/thinktank/executor/agentic.ex` — Pi subprocess runner
- `lib/thinktank/run_store.ex` — manifests and artifacts

## Doctrine

- Workspace is context
- Launch, sandbox, timeout, and record in Elixir
- Explore and reason in Pi
- Prefer general tools over bespoke harness logic
- Prefer deletion over additional orchestration layers

## Local Gates

- Use `./scripts/with-colima.sh dagger call check` as the canonical local merge-readiness gate.
- `./scripts/with-colima.sh dagger call check` now enforces formatting, compile warnings, `credo --strict`, Dialyzer, shell/YAML hygiene, gitleaks, live model-ID validation, the architecture gate, escript smoke, and an `87%` coverage floor.
- Use `mix test` and `mix compile --warnings-as-errors` as targeted fallback or debugging gates when you need a host-native Elixir check.
- Native Git hooks live in `.githooks/` and are installed by `./scripts/setup.sh`.

## Smell Tests

- Regex over agent prose: wrong layer
- Semantic phases and handoffs: probably wrong layer
- Precomputed review bundles: probably wrong layer
- Extra prompt prose to compensate for weak models: probably wrong layer

## Shared Skills

Agent-agnostic skills live under `.agent/skills/` and are readable by both
Claude Code and Codex. Follow a skill's `SKILL.md` when its trigger matches.

- `.agent/skills/model-research/` — monthly OpenRouter-focused model scan
  with Thinktank-fit recommendations. Trigger: "latest models",
  "model research", "should we swap X", unfamiliar model names.

## References

- `README.md`
- `CLAUDE.md`
