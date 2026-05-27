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
status: done
title: Add Review Coverage Contract
---

# Add Review Coverage Contract

Priority: high
Status: done
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

- [x] Review envelopes expose `review_coverage` with requested domains, planned reviewers, completed domains, failed domains, missing domains, and terminal coverage status.
- [x] `review/degrade_policy.json` either becomes part of that contract or is clearly referenced by it without duplicate meanings.
- [x] Human review output starts with a compact coverage summary when any domain is missing or degraded.
- [x] Tests cover complete coverage, degraded coverage with synthesis escalation, failed coverage with no synthesis, and no-planner review runs.
- [x] README documents how downstream tools should consume coverage without parsing markdown.

## What Was Built

- Added `Thinktank.Review.Coverage` to derive requested, completed, failed, missing, and degraded review domains from planner selections, reviewer metadata, run results, and degrade policy.
- Wrote `review/coverage.json`, exposed `review_coverage` in run envelopes and terminal trace attributes, and registered the artifact path.
- Prepended a compact `Review Coverage` section to `review.md` when coverage is degraded, partial, or failed so missing perspectives are visible before findings.
- Covered complete, degraded, failed, and no-planner review runs in tests, and documented downstream consumption in `README.md`.

## Notes

Backlog `021` gave domain tags teeth by escalating or failing when invoked reviewer domains disappear. This item turns that mechanism into the broader product contract: ThinkTank reviews should be able to answer "what perspectives did I actually get?" as a first-class result.
