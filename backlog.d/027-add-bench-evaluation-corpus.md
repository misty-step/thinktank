---
acceptance:
    - ThinkTank has a frozen review and research evaluation corpus with expected coverage and finding classes.
    - The corpus can be replayed locally through existing bench commands.
    - Evaluation results report quality, coverage, latency, and cost signals without requiring live PR context.
evidence_required:
    - mix test
    - thinktank review eval
    - ./scripts/with-colima.sh dagger call check
id: 027-add-bench-evaluation-corpus
lifecycle_stage: Intent
status: ready
title: Add Bench Evaluation Corpus
---

# Add Bench Evaluation Corpus

Priority: high
Status: ready
Estimate: L

## Goal

ThinkTank can measure whether benches are getting better or worse because representative review and research cases are frozen, replayable, and scored against expected coverage and finding classes.

## Non-Goals

- Training models
- Ranking every provider in the market
- Replacing human review judgment with a single scalar score
- Adding a new execution path around Pi

## Constraints / Invariants

- Corpus cases replay through existing `thinktank review eval` and bench launch paths.
- Expected outcomes are stated as finding classes, evidence expectations, coverage expectations, and unacceptable misses, not brittle prose snapshots.
- Cost and latency are reported beside quality; cheap incomplete runs should not look like wins.
- Fixtures must be safe to keep in the repo or clearly generated from public-safe artifacts.

## Repo Anchors

- `lib/thinktank/review/eval.ex`
- `test/thinktank/review/eval_test.exs`
- `priv/config/builtin.yml`
- `backlog.d/done/023-add-structured-research-findings-contract.md`
- `.agent/skills/` Spellbook-tailored workflow guidance

## Oracle

- [ ] At least three frozen review cases exist: security-sensitive diff, test-only regression, and architecture/runtime-risk change.
- [ ] At least two frozen research cases exist with expected thesis/finding/evidence shape.
- [ ] Evaluation output reports pass/fail by expected finding class and requested review domain.
- [ ] Evaluation output includes cost, latency, and degraded/partial status so quality is not separated from operational reality.
- [ ] README or docs explain how to add a new corpus case from a real run artifact.

## Notes

The ultimate product is not "many agents ran." It is "this bench reliably catches the classes of problems it claims to catch." A corpus gives ThinkTank the feedback loop needed to tune benches, models, prompts, and coverage policy without relying on anecdote.
