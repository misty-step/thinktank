---
acceptance:
    - Marshal plans can record explicitly required review domains.
    - The runtime enforces required-domain gaps through the existing review coverage and degrade-policy artifacts.
    - Optional reviewer failures do not masquerade as missing required coverage.
evidence_required:
    - mix test
id: 021-domain-tagged-degrade-policy
lifecycle_stage: Intent
status: ready
title: Add Marshal-Explicit Review Domain Requirements
---

# Add Marshal-Explicit Review Domain Requirements

Priority: high
Status: ready
Estimate: M

## Goal

When marshal decides a review requires a domain such as `security`,
`correctness`, or `tests`, that requirement is recorded as structured plan
data and the runtime enforces missing required coverage through the existing
review coverage and degrade-policy artifacts.

## Non-Goals

- Rewriting the reviewer roster or marshal planner
- Adding a new planner stage between marshal and reviewer dispatch
- Building a dependency graph across domain tags
- Gating non-review benches (research/default etc.) on domain coverage
- Replacing the existing `review/degrade_policy.json` and `review/coverage.json` contracts

## Constraints / Invariants

- Existing fail/escalate behavior stays intact; this item teaches it which
  domains were required, rather than treating every planned reviewer domain as
  equally required.
- Required domains must be drawn from configured reviewer `review_role`
  metadata so typos fail plan validation.
- A non-required reviewer failure may still degrade the run, but it must not
  claim a marshal-required domain gap.
- The JSON envelope remains consumable without markdown or synthesis parsing.

## Repo Anchors

- `lib/thinktank/builtin.ex` — reviewer `review_role` metadata already encodes domain tags (`security`, `correctness`, `tests`, `interfaces`, ...); this item is the thing that gives those tags teeth
- `lib/thinktank/review/planner.ex` — plan schema validation currently accepts selected agents, synthesis brief, summary, and warnings but not required domains
- `lib/thinktank/engine/runtime.ex` — synthesis orchestration path; degrade decisions land here
- `lib/thinktank/review/degrade_policy.ex` — existing baseline evaluates planned/failed reviewer domains and writes missing-domain outcomes
- `lib/thinktank/review/coverage.ex` — existing coverage artifact exposes requested, completed, failed, and missing domains
- `lib/thinktank/prompts/review.ex` — marshal prompt needs to request required domain data as JSON

## Oracle

- [ ] Marshal plan JSON accepts and validates a `required_domains` list whose values match configured reviewer roles.
- [ ] `review/plan.json` records required domains and the plan source so downstream consumers can distinguish required coverage from optional reviewer selection.
- [ ] `DegradePolicy.evaluate/4` compares missing coverage against required domains when they exist, falling back to planned reviewer domains only for manual/fallback plans.
- [ ] `review/degrade_policy.json`, `review/coverage.json`, and the `--json` payload expose the chosen outcome without markdown parsing.
- [ ] Tests cover required security domain failure, optional reviewer failure, invalid required domain, and fallback/manual plans.

## Notes

The baseline domain degrade policy has already landed on `master`:
`lib/thinktank/review/degrade_policy.ex` writes a typed policy, `coverage.ex`
summarizes missing domains, and `engine_test.exs` covers fail/escalate paths.
This ticket now tracks the residual correctness gap: marshal intent is not yet
structured as required-domain data, so the runtime cannot tell required and
optional reviewer domains apart.
