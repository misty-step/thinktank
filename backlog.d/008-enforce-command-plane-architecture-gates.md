# Enforce Command-Plane Architecture Gates

Priority: medium
Status: ready
Estimate: L

## Goal
Command-plane refactors stay safe because module boundaries, complexity budgets, and artifact-layout contracts are enforced automatically.

## Non-Goals
- Rewriting the entire CLI or engine in one pass
- Adding a workflow DSL
- Changing prompt content as a substitute for structural fixes

## Oracle
- [ ] CI runs a dedicated architecture gate covering xref cycles, compile-connected regressions, and explicit complexity/file-size thresholds
- [ ] Shared artifact layout constants live in one module and are referenced from both execution and storage code
- [ ] `lib/thinktank/cli.ex` and `lib/thinktank/engine.ex` are each reduced below 400 LOC with behavior preserved
- [ ] Regression tests cover the parser/execution boundary and artifact layout contract

## Notes
The highest technical risk is concentrated in `Thinktank.CLI`, `Thinktank.Engine`, and `Thinktank.Executor.Agentic`, plus their implicit agreement about artifact layout.
