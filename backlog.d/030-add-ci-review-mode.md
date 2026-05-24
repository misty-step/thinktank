---
acceptance:
    - ThinkTank has a CI-oriented review invocation with deterministic exit semantics.
    - CI mode emits machine-readable blocking findings and coverage status.
    - CI mode remains a Pi-backed bench launch and does not bypass the thin launcher boundary.
evidence_required:
    - mix test
    - ./scripts/with-colima.sh dagger call check
id: 030-add-ci-review-mode
lifecycle_stage: Intent
status: ready
title: Add CI Review Mode
---

# Add CI Review Mode

Priority: high
Status: ready
Estimate: M

## Goal

Repositories can call ThinkTank from CI for governed review because `thinktank review --ci` has clear exit codes, coverage requirements, artifact output, and a compact JSON contract for blocking findings.

## Non-Goals

- Making ThinkTank the only CI gate
- Auto-fixing code
- Posting to GitHub directly in this item
- Adding a direct model API path outside Pi

## Constraints / Invariants

- CI mode is an option over existing review benches, not a new bench runtime.
- Exit behavior is explicit: complete with no blocking findings succeeds; missing required coverage, failed runs, and blocking findings fail.
- The artifact bundle remains the durable evidence packet.
- The mode must work without repo-specific prompt hacks.

## Repo Anchors

- `lib/thinktank/cli.ex`
- `lib/thinktank/cli/parser.ex`
- `lib/thinktank/cli/render.ex`
- `lib/thinktank/engine/runtime.ex`
- `lib/thinktank/review/eval.ex`
- `scripts/ci/`

## Oracle

- [ ] `thinktank review --ci --json` emits a compact envelope with status, blocking finding count, coverage status, output directory, and artifact pointers.
- [ ] CI mode exits `0` only when the run is complete enough for the configured coverage and has no blocking findings.
- [ ] Missing required domains fail clearly instead of producing a pass with degraded coverage.
- [ ] Tests cover pass, blocking finding, degraded coverage, failed run, and partial run semantics.
- [ ] README documents how another repo should wire CI mode without parsing markdown.

## Notes

The visionary wedge is not another CI product. It is a local, artifacted review command that CI can trust because ThinkTank already owns launch, coverage, status, and evidence.
