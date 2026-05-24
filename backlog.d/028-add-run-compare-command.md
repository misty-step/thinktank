---
acceptance:
    - Operators can compare two completed runs and see changed findings, coverage, cost, latency, and status.
    - Comparison uses manifest-recorded artifacts and structured contracts rather than markdown scraping.
    - JSON output is stable enough for downstream agents to consume.
evidence_required:
    - mix test
    - ./scripts/with-colima.sh dagger call check
id: 028-add-run-compare-command
lifecycle_stage: Intent
status: ready
title: Add Run Compare Command
---

# Add Run Compare Command

Priority: medium
Status: ready
Estimate: M

## Goal

Operators can ask "what changed between these two bench runs?" and get a reliable comparison of findings, coverage, status, cost, latency, and artifact differences.

## Non-Goals

- Building a web dashboard
- Diffing arbitrary markdown with heuristics
- Re-running agents as part of compare
- Adding a remote run store

## Constraints / Invariants

- Compare reads existing run directories through the same run-inspection and manifest contracts used by `runs show`.
- Structured artifacts drive semantic comparison: `research/findings.json`, review coverage, degrade policy, manifest, and trace summary.
- Markdown artifacts can be listed as changed, but they are not the source of truth for finding equivalence.
- Old runs degrade gracefully when newer structured fields are absent.

## Repo Anchors

- `lib/thinktank/run_inspector.ex`
- `lib/thinktank/run_store.ex`
- `lib/thinktank/cli.ex`
- `lib/thinktank/cli/parser.ex`
- `lib/thinktank/cli/render.ex`
- `lib/thinktank/artifact_layout.ex`

## Oracle

- [ ] `thinktank runs compare <run-a> <run-b>` works for path or run id inputs.
- [ ] Text output highlights status, coverage, cost, latency, and structured finding deltas.
- [ ] `--json` output exposes a stable comparison envelope.
- [ ] Tests cover research findings comparison, review coverage comparison, cost/status deltas, missing structured artifacts, and invalid run targets.
- [ ] README documents compare as the local way to inspect bench/model drift.

## Notes

Run inspection made liveness explicit. Run compare makes drift explicit. This is the bridge from one-off bench invocations to a tool operators can use while tuning rosters, prompts, models, and focused benches.
