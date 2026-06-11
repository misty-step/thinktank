---
acceptance:
    - Operators can promote real terminal runs into versioned eval cases.
    - Eval replay, run comparison, and static reports form one improvement loop.
    - Promotion is public-safe and does not copy raw secrets or private local state.
evidence_required:
    - mix test
    - thinktank review eval
    - ./scripts/with-colima.sh dagger call check
id: 038-add-bench-lab-promotion-loop
lifecycle_stage: Intent
status: ready
title: Add Bench Lab Promotion Loop
---

# Add Bench Lab Promotion Loop

Priority: medium
Status: ready
Estimate: L

## Goal

Operators can turn important real ThinkTank runs into replayable eval cases,
compare candidate bench/model/runner changes against the baseline, and publish
a static evidence packet without stitching together ad-hoc scripts.

## Non-Goals

- Training or fine-tuning models
- Adding a remote dashboard or hosted run store
- Replacing `review eval`, `runs compare`, or static reports with a separate product surface
- Copying raw private prompts, credentials, or workspace paths into public fixtures

## Constraints / Invariants

- Promotion consumes terminal run artifacts only: `contract.json`,
  `manifest.json`, trace summary, review coverage, degrade policy, structured
  research findings, and selected public-safe excerpts.
- Corpus cases state expected finding classes, coverage requirements, and
  unacceptable misses, not brittle markdown snapshots.
- Compare and report outputs stay derived from canonical artifacts.
- Redaction is explicit; missing redaction policy blocks promotion.

## Repo Anchors

- `lib/thinktank/review/eval.ex`
- `lib/thinktank/run_inspector.ex`
- `lib/thinktank/run_store.ex`
- `lib/thinktank/artifact_layout.ex`
- `lib/thinktank/cli.ex`
- `docs/agent-composition-vision.md`
- `backlog.d/027-add-bench-evaluation-corpus.md`
- `backlog.d/028-add-run-compare-command.md`
- `backlog.d/029-add-static-run-report-artifact.md`

## Children

1. Extend `027` with a corpus case schema that can represent promoted real runs.
2. Add a `thinktank eval promote <run>` or equivalent command that writes a public-safe case skeleton from terminal artifacts.
3. Use `028` comparison output to compare baseline and candidate eval runs.
4. Use `029` static reports to publish the baseline, candidate, and delta evidence packet.
5. Document the bench-lab loop in `README.md` without introducing a daemon or dashboard.

## Oracle

- [ ] A terminal review run can be promoted into a corpus case with expected coverage and finding-class placeholders.
- [ ] A terminal research run can be promoted into a corpus case with thesis/finding/evidence placeholders.
- [ ] Promotion refuses non-terminal runs and runs with missing redaction policy.
- [ ] Eval replay records cost, latency, coverage, status, and artifact pointers for baseline and candidate runs.
- [ ] `runs compare` and the static report can link baseline, candidate, and delta artifacts.

## Notes

This is the Phase 5 "Bench Lab" loop from `docs/agent-composition-vision.md`.
The active backlog already contains the pieces (`027`, `028`, `029`, `030`);
this epic keeps the product outcome explicit so those pieces converge into a
repeatable improvement workflow rather than a pile of commands.
