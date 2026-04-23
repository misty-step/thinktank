# Backlog

Active items live at the top level of `backlog.d/`. Completed items are moved
to `backlog.d/done/` once their oracle is green and they are merged. Each file
carries its own `Status:` field as the source of truth; this index is a
human-readable overview.

Status conventions:
- **in-progress** — actively being built on a branch or worktree
- **ready** — shaped and unblocked; pick next
- **done** — merged; lives under `done/`

## In Progress

| # | Title | Priority | Estimate |
|---|-------|----------|----------|
| [008](008-enforce-command-plane-architecture-gates.md) | Enforce Command-Plane Architecture Gates | medium | L |

## Active (ready to pick)

| # | Title | Priority | Estimate |
|---|-------|----------|----------|
| [024](024-add-first-class-focused-review-benches.md) | Add First-Class Focused Review Benches | medium | M |
| [018](018-centralize-gate-policy-sources-and-remove-overlap.md) | Centralize Gate Policy Sources And Remove Overlap | medium | M |
| [020](020-capability-aware-benches-validate.md) | Capability-Aware Benches Validate | medium | M |
| [021](021-domain-tagged-degrade-policy.md) | Domain-Tagged Degrade Policy | medium | L |

## Done

See [done/](done/) for full write-ups including "What Was Built" notes.

| # | Title |
|---|-------|
| [001](done/001-agent-integration-contracts.md) | Agent Integration Contracts |
| [002](done/002-extract-prompt-library.md) | Extract Prompt Library |
| [003](done/003-delete-dead-workflow-api.md) | Delete Dead Workflow API |
| [004](done/004-add-json-output-for-benches-validate.md) | Add JSON Output For Benches Validate |
| [005](done/005-make-benches-show-honor-json-flag.md) | Make Benches Show Honor JSON Flag |
| [006](done/006-stabilize-cli-run-contract.md) | Stabilize CLI Run Contract |
| [007](done/007-add-cli-e2e-smoke-suite.md) | Add CLI E2E Smoke Suite |
| [009](done/009-add-security-gating-workflow.md) | Add Security Gating Workflow |
| [010](done/010-add-agent-run-tracing-and-local-logs.md) | Add Agent Run Tracing And Local Logs |
| [011](done/011-add-live-progress-surface-for-json-runs.md) | Add Live Progress Surface For JSON Runs |
| [012](done/012-align-project-docs-with-thin-launcher-architecture.md) | Align Project Docs With Thin Launcher Architecture |
| [013](done/013-add-durable-wip-scratchpads-and-partial-results-contract.md) | Add Durable WIP Scratchpads And Partial-Result Contract |
| [014](done/014-track-per-run-usd-cost.md) | Track Per-Run USD Cost |
| [015](done/015-fix-review-eval-and-finished-review-contract.md) | Fix Review Eval And Finished Review Contract |
| [016](done/016-add-run-session-and-single-lifecycle-owner.md) | Add Run Session And Single Lifecycle Owner |
| [017](done/017-reduce-review-control-plane-to-structured-contracts.md) | Reduce Review Control Plane To Structured Contracts |
| [019](done/019-fix-default-review-bench-guard-agent-incompatibility.md) | Fix Default Review Bench Guard Agent Incompatibility |
| [022](done/022-add-run-inspection-and-explicit-run-state-commands.md) | Add Run Inspection And Explicit Run State Commands |
| [023](done/023-add-structured-research-findings-contract.md) | Add Structured Research Findings Contract |

## Workflow

- When starting work on an item, change its `Status:` to `in-progress` and move
  it to the **In Progress** row above (delete the `_None._` placeholder).
- Top-level items must never be `Status: done`; that state only belongs under
  `backlog.d/done/`.
- When merged, change `Status:` to `done`, fill in a `## What Was Built`
  section, `git mv` the file into `done/`, and update this index.
- New items are shaped via `/shape` or `/groom` and land here with
  `Status: ready` and a priority.
