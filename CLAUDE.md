# CLAUDE

## Purpose

ThinkTank is a thin Pi bench launcher.

It defines Pi agents, groups them into benches, launches them against the
current workspace, and records raw artifacts. It should not grow a semantic
workflow DSL, a prose-parsing layer, or a second non-agentic execution path.

## Architecture Map

```text
lib/thinktank/cli.ex                → CLI dispatch and exit-code translation
lib/thinktank/cli/parser.ex         → argv parsing and command shaping
lib/thinktank/cli/render.ex         → human + JSON output rendering
lib/thinktank/engine.ex             → bench resolution and launch entrypoint
lib/thinktank/engine/preparation.ex → config / agent / planner / synthesizer resolution
lib/thinktank/engine/bootstrap.ex   → run initialization and start-of-run recording
lib/thinktank/engine/runtime.ex     → agent execution and synthesis orchestration
lib/thinktank/artifact_layout.ex    → canonical artifact path constants
lib/thinktank/builtin.ex            → built-in agents and benches
lib/thinktank/config.ex             → built-in + user + repo config loading
lib/thinktank/bench_spec.ex         → typed bench config
lib/thinktank/agent_spec.ex         → typed agent config
lib/thinktank/executor/agentic.ex   → Pi subprocess launcher
lib/thinktank/run_store.ex          → raw artifacts and manifest
lib/thinktank/run_contract.ex       → persisted run contract
```

Start with `lib/thinktank/cli.ex` and `lib/thinktank/engine.ex`.

## Non-Goals

- No semantic stage graphs
- No quick/deep split
- No regex recovery of agent structure
- No precomputed diff bundles as the primary review context

## Quality Bar

- `mix test` passes
- `mix format` clean
- `mix compile --warnings-as-errors` clean
- Prefer deletion over new harness layers

## Design Rules

- ThinkTank owns launch, isolation, timeout, concurrency, and artifacts.
- Pi agents own reasoning, repo exploration, and git inspection.
- Context should usually be implicit from `cwd` plus light orientation flags.
- If a fix requires more prompt prose to stop the same class of mistake,
  redesign the harness boundary instead.

## References

- [README.md](README.md)
- [lib/thinktank/builtin.ex](lib/thinktank/builtin.ex)
- [lib/thinktank/engine.ex](lib/thinktank/engine.ex)
