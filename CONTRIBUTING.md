# Contributing

ThinkTank is a thin Pi bench launcher. Keep changes small, contract-focused, and easy for agents to consume.

## Setup

```bash
./scripts/setup.sh
```

Local tooling expects `mix`, `python3`, and either Docker+`dagger` or a host
Elixir toolchain. Add `THINKTANK_OPENROUTER_API_KEY` to `.env` or your shell
before running live model calls.

## Local Gates

Run the canonical local gate before opening a PR:

```bash
dagger call check
```

`dagger call check` enforces the repo's full local policy: formatting, compile
warnings as errors, `credo --strict`, Dialyzer, shell/YAML hygiene, gitleaks,
live model-ID validation, the architecture gate, escript smoke, and an `87%`
coverage floor.

For targeted debugging, the underlying host-native checks are:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
scripts/ci/architecture-gate.sh
./scripts/validate-elixir-models.sh
mix test
mix escript.build
```

## Workflow

- Start from a backlog item or a clearly stated outcome.
- Preserve the thin-launcher boundary: no semantic workflow DSLs, prose parsers, or second execution paths.
- Prefer the local-first path: `./scripts/setup.sh`, native Git hooks in `.githooks/`, and `dagger call check` before any remote CI.
- Update `README.md`, `CLAUDE.md`, `AGENTS.md`, or `project.md` when behavior or operator expectations change.
- Add or adjust tests for behavioral changes. Prefer integration coverage for CLI contracts.

## Pull Requests

- Explain the user-visible or agent-visible outcome.
- Call out any contract changes to JSON output, artifacts, flags, or config shape.
- Include the verification commands you ran.
