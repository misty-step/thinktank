---
acceptance:
    - Completed runs can produce a readable static report from existing artifacts.
    - The report links to canonical artifacts and summarizes status, coverage, findings, cost, and trace metadata.
    - Report generation does not introduce a server, dashboard, or second source of truth.
evidence_required:
    - mix test
    - ./scripts/with-colima.sh dagger call check
id: 029-add-static-run-report-artifact
lifecycle_stage: Intent
status: ready
title: Add Static Run Report Artifact
---

# Add Static Run Report Artifact

Priority: medium
Status: ready
Estimate: M

## Goal

Each important run can produce a local, readable report that makes the artifact bundle easy to inspect without weakening the underlying machine contracts.

## Non-Goals

- A web dashboard or long-running server
- Replacing `manifest.json`, `trace/events.jsonl`, `review.md`, or `research/findings.json`
- Rendering hidden model reasoning or private logs
- Adding remote publishing

## Constraints / Invariants

- The report is generated from manifest-recorded artifacts and typed contracts.
- The report is optional and additive; existing run behavior remains unchanged.
- The report must make degraded, partial, failed, and missing-coverage states visually obvious.
- Public-safe redaction rules must match the existing artifact policy.

## Repo Anchors

- `lib/thinktank/run_store.ex`
- `lib/thinktank/run_inspector.ex`
- `lib/thinktank/artifact_layout.ex`
- `lib/thinktank/cli/render.ex`
- `README.md`

## Oracle

- [ ] A command or flag emits `report.html` or `report.md` under the run directory from existing artifacts.
- [ ] The report summarizes run status, bench, task, paths, coverage, structured findings or review summary, cost, pricing gaps, and artifact links.
- [ ] Degraded, partial, failed, and missing-coverage runs show a prominent warning section.
- [ ] Tests verify report generation for research and review runs without depending on live providers.
- [ ] README positions the report as an inspection artifact, not a dashboard.

## Notes

ThinkTank already writes the evidence. This item makes the evidence legible to humans reviewing a run after the fact, while keeping JSON and manifest files as the source of truth.
