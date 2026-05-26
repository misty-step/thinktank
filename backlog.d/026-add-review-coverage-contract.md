---
acceptance:
    - Review runs expose requested, observed, missing, and degraded coverage as a stable machine-readable contract.
    - Human review output summarizes coverage before findings so missing perspectives are visible.
    - Coverage data is derived from planner selections, reviewer metadata, and run results without parsing reviewer prose.
evidence_required:
    - mix test
    - ./scripts/with-colima.sh dagger call check
id: 026-add-review-coverage-contract
lifecycle_stage: Intent
status: ready
title: Add Review Coverage Contract
---

# Add Review Coverage Contract

Priority: high
Status: in-progress
Estimate: M

## Goal

Every review run tells operators and downstream agents what review coverage was requested, what actually ran, what was missing, and whether the final findings should be trusted as complete for the requested domains.

## Non-Goals

- Replacing `review/default`
- Adding a semantic workflow engine or planner stage
- Inferring coverage from prose in `review.md`
- Blocking research benches on review-domain semantics

## Constraints / Invariants

- Coverage derives from the existing review planner contract, reviewer `review_role` metadata, and execution results.
- The contract is additive to existing JSON envelopes and artifacts.
- Domain terms stay flat and operational: `security`, `correctness`, `tests`, `architecture`, `runtime-risk`, `interfaces`, etc.
- Missing coverage must be visible in human output, not just buried in JSON.

## Repo Anchors

- `lib/thinktank/review/degrade_policy.ex`
- `lib/thinktank/review/planner.ex`
- `lib/thinktank/engine/runtime.ex`
- `lib/thinktank/run_store.ex`
- `lib/thinktank/cli/render.ex`
- `priv/config/builtin.yml`

## Oracle

- [ ] Review envelopes expose `review_coverage` with requested domains, planned reviewers, completed domains, failed domains, missing domains, and terminal coverage status.
- [ ] `review/degrade_policy.json` either becomes part of that contract or is clearly referenced by it without duplicate meanings.
- [ ] Human review output starts with a compact coverage summary when any domain is missing or degraded.
- [ ] Tests cover complete coverage, degraded coverage with synthesis escalation, failed coverage with no synthesis, and no-planner review runs.
- [ ] README documents how downstream tools should consume coverage without parsing markdown.

## Notes

Backlog `021` gave domain tags teeth by escalating or failing when invoked reviewer domains disappear. This item turns that mechanism into the broader product contract: ThinkTank reviews should be able to answer "what perspectives did I actually get?" as a first-class result.
