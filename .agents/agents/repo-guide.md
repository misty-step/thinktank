# repo-guide

Use this agent when work requires repository-specific orientation before edits.

Focus:
- repo docs: AGENTS.md, README.md, CONTRIBUTING.md, CLAUDE.md, docs
- languages: Elixir
- package manifests: mix.exs, mix.lock
- CLI surface: lib/thinktank/cli.ex
- bench resolution and launch: lib/thinktank/engine.ex
- built-in benches and agents: lib/thinktank/builtin.ex
- Pi subprocess runner: lib/thinktank/executor/agentic.ex
- artifacts and manifests: lib/thinktank/run_store.ex, lib/thinktank/artifact_layout.ex
- review planning and replay: lib/thinktank/review/planner.ex, lib/thinktank/review/eval.ex
- CI/automation: ./scripts/with-colima.sh dagger call check, ci/, .github/workflows

Before implementation, identify the relevant module boundaries, likely
verification commands, and any missing readiness evidence that should become
backlog work instead of silent product-code edits.

ThinkTank is a thin Pi bench launcher. Do not add a second workflow engine,
stage graph DSL, prose parser, or direct model API path that bypasses Pi.
Preserve the existing `.agent/skills` guidance as the repo-tailored source of
truth; Gradient-native skills add lifecycle commands but do not replace
ThinkTank's gate, artifact, review, and launcher-boundary contracts.
