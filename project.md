# Project: thinktank

## Current Boundary

ThinkTank is a thin Pi bench launcher for research and code review.

It defines named Pi agents in config, groups them into benches, launches them
against the current workspace, and records raw artifacts plus run metadata. It
does not own semantic workflow logic, direct multi-LLM dispatch, or post-hoc
parsing of agent prose.

## North Star

Be the dependable command-plane that other agents and engineers can call when
they need a repeatable research or review bench with inspectable artifacts.

## What ThinkTank Is

- A CLI and JSON contract for launching named Pi benches.
- A thin runtime that owns resolution, isolation, concurrency, retries,
  timeouts, and artifact persistence.
- A durable artifact writer for prompts, raw outputs, traces, scratchpads,
  partial results, and per-run cost metadata.
- A local-first tool: workspace context comes from `cwd` plus light orientation
  flags like `--paths`, `--base`, `--head`, `--repo`, and `--pr`.

## What ThinkTank Is Not

- Not a router that invents perspectives on the fly.
- Not a quick/deep dispatch split with a parallel non-Pi execution path.
- Not a semantic workflow engine or stage graph DSL.
- Not a prose parser that recovers structure from agent output after the fact.

## Principles

- **Workspace is context.** Run ThinkTank in the repo you want agents to inspect.
- **Thin launcher boundary.** ThinkTank owns launch and artifacts; Pi owns
  exploration, reasoning, and git inspection.
- **Artifact contract over orchestration.** Durable files and stable envelopes
  matter more than adding semantic harness layers.
- **Local resilience.** Traces, scratchpads, partial summaries, and cost
  accounting should survive timeout, interruption, and retry.
- **Convention over bespoke logic.** Prefer benches, prompts, and config over
  new execution concepts.

## Architecture Map

| Surface | Module | Responsibility |
|---|---|---|
| CLI | `lib/thinktank/cli.ex` | Commands, dry-run, text/JSON output |
| Engine | `lib/thinktank/engine.ex` | Bench resolution and launch orchestration |
| Builtins | `lib/thinktank/builtin.ex` | Built-in agents and benches |
| Config | `lib/thinktank/config.ex` | Built-in, user, and repo config loading |
| Executor | `lib/thinktank/executor/agentic.ex` | Pi subprocess execution and retry |
| Store | `lib/thinktank/run_store.ex` | Manifest, artifacts, scratchpads, partial summaries |
| Contract | `lib/thinktank/run_contract.ex` | Persisted run contract |
| Trace | `lib/thinktank/trace_log.ex` | Structured per-run and global trace logs |
| Review context | `lib/thinktank/review/context.ex` | Lightweight review context artifacts |
| Review planner | `lib/thinktank/review/planner.ex` | Optional reviewer subset planning |
| Pricing | `lib/thinktank/pricing.ex` | Code-owned per-model USD pricing table |

## Domain Glossary

| Term | Definition |
|---|---|
| Agent | A named Pi configuration with provider, model, prompts, and tools |
| Bench | A named set of agents plus optional planner and synthesizer |
| Planner | Optional agent that selects or narrows reviewers before execution |
| Synthesizer | Optional agent that writes a final research or review artifact |
| Run contract | Persisted input and execution context for one run |
| Manifest | Artifact index and run metadata for one run |
| Scratchpad | Durable append-only run or agent journal written during execution |
| Pricing gap | A model or token class whose USD rate is intentionally unknown |

## Quality Bar

- `mix test`
- `mix compile --warnings-as-errors`
- `./scripts/with-colima.sh dagger call check`
- Conventional commit messages

## Historical Note

Earlier project language referred to router/dispatch/quick/deep/output modules
as the active system. Treat that as historical context from a different design
direction, not as the current architecture.

Go v4 code lives on the
[`v4-archive`](https://github.com/misty-step/thinktank/tree/v4-archive) branch
(`v4.0.0`).

---
*Last updated: 2026-04-17*
