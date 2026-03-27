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

## Smell Tests

- Regex over agent prose: wrong layer
- Semantic phases and handoffs: probably wrong layer
- Precomputed review bundles: probably wrong layer
- Extra prompt prose to compensate for weak models: probably wrong layer

## References

- `README.md`
- `CLAUDE.md`
