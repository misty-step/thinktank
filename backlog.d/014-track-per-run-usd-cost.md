# Track Per-Run USD Cost

Priority: medium
Status: in-progress
Estimate: S

## Goal
Every ThinkTank run records the USD cost of the model calls it made, so operators can see what a run actually cost and compare bench configurations on price.

## Non-Goals
- Billing, invoicing, or quota enforcement
- Real-time cost streaming during a run
- Cross-run aggregation dashboards — artifacts are the contract; rollups are a separate concern

## Constraints / Invariants
- Cost is derived from Pi's reported token usage × a per-model price table; ThinkTank does not estimate or guess
- If any agent in a run has an unknown price, the run-level total records `usd_cost: null` with `pricing_gaps: [<model>, …]` rather than a wrong number
- Cost accounting never gates run completion — a pricing lookup failure logs a warning, it does not fail the run
- The thin-launcher boundary holds: ThinkTank records what Pi reports; Pi owns the token counts

## Repo Anchors
- `lib/thinktank/run_store.ex`
- `lib/thinktank/run_contract.ex`
- `lib/thinktank/executor/agentic.ex`
- `lib/thinktank/engine.ex`

## Oracle
- [ ] Per-agent `usage` record includes `input_tokens`, `output_tokens`, `model`, and `usd_cost` (or `null` with a pricing gap note)
- [ ] Run-level manifest aggregates agent costs into `usd_cost_total` plus a per-model breakdown
- [ ] Unknown-model price resolves to `null` + warning, never a zero or fabricated number
- [ ] Price table lives in code (not config) and is covered by tests that fail when a model in `builtin.ex` has no price
- [ ] `thinktank runs show <id>` (or equivalent) surfaces the cost line when artifacts are inspected

## Motivation
`/flywheel` (the orchestrator) runs under a Claude Max / OpenAI Pro subscription — no per-token billing at the cycle level. ThinkTank is the opposite: every bench run hits paid APIs. Cost belongs where the money is actually spent, not in the orchestrator. This item moves USD tracking to its correct home.
