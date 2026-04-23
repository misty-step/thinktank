# Enforce Command-Plane Architecture Gates

Priority: medium
Status: done
Estimate: L

## Goal
Command-plane refactors stay safe because module boundaries, complexity budgets, and artifact-layout contracts are enforced automatically.

## Non-Goals
- Rewriting the entire CLI or engine in one pass
- Adding a workflow DSL
- Changing prompt content as a substitute for structural fixes

## Oracle
- [x] CI runs a dedicated architecture gate covering xref cycles, compile-connected regressions, and explicit complexity/file-size thresholds
- [x] Shared artifact layout constants live in one module and are referenced from both execution and storage code
- [x] `lib/thinktank/cli.ex` and `lib/thinktank/engine.ex` are each reduced below 400 LOC with behavior preserved
- [x] Regression tests cover the parser/execution boundary and artifact layout contract

## Notes
The highest technical risk is concentrated in `Thinktank.CLI`, `Thinktank.Engine`, and `Thinktank.Executor.Agentic`, plus their implicit agreement about artifact layout.

## Progress
- Split CLI parsing and rendering into dedicated modules while keeping IO at the top-level CLI boundary.
- Split engine bootstrap, preparation, and runtime execution so `lib/thinktank/engine.ex` now stays as the thin command-plane entrypoint.
- Centralized artifact path ownership in `Thinktank.ArtifactLayout` and enforced that ownership in `scripts/ci/architecture-gate.sh`.
- Added regression coverage for the CLI-to-engine boundary and the artifact layout contract; local gates are green, but the item remains `in-progress` until it is committed and merged.
