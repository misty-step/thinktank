# ADR 0001: Keep ThinkTank As A Thin Pi Bench Launcher

- Status: Accepted
- Date: 2026-04-08

## Context

ThinkTank exists to launch named Pi agents against a workspace, capture raw outputs, and record artifacts. The codebase already rejects semantic workflow layers, prose parsing, and non-agentic side paths.

## Decision

Keep the product boundary thin:

- ThinkTank owns bench resolution, launch orchestration, isolation, timeouts, and artifacts.
- Pi agents own exploration, reasoning, and git inspection.
- CLI and JSON surfaces are the product contract.
- New features must strengthen that contract instead of adding semantic orchestration layers.

## Consequences

- Contract stability, docs, tests, and artifact discoverability are higher leverage than new execution modes.
- Complex review/research logic should stay in prompts and benches, not in Elixir workflow code.
- Refactors should favor smaller command-plane modules and stronger verification, not broader orchestration.
