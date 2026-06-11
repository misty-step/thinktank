---
acceptance:
    - Operators can check model availability, tool support, pricing coverage, and latency before launching expensive benches.
    - The command reuses existing provider capability and pricing logic.
    - Results are visible in text and JSON.
evidence_required:
    - mix test
    - ./scripts/with-colima.sh dagger call check
id: 032-add-model-roster-health-command
lifecycle_stage: Intent
status: ready
title: Add Model Roster Health Command
---

# Add Model Roster Health Command

Priority: medium
Status: ready
Estimate: S

## Goal

Operators can quickly tell whether the configured agent roster is healthy
before running an important research or review bench: model availability, tool
support, pricing coverage, credential state, and policy readiness are visible
before money and time are spent.

## Non-Goals

- Replacing `benches validate`
- Benchmarking model intelligence
- Persisting provider catalogs
- Failing when provider APIs are unreachable in normal offline development

## Constraints / Invariants

- The command reuses the capability probe behind `benches validate`.
- Pricing gaps come from the existing pricing table behavior.
- Missing credentials and provider outages produce warnings, not confusing raw HTTP output.
- The output must be useful before a live run: availability, tool support, pricing known/unknown, and rough response latency are enough.

## Repo Anchors

- `lib/thinktank/bench_validation.ex`
- `lib/thinktank/pricing.ex`
- `lib/thinktank/cli.ex`
- `lib/thinktank/cli/parser.ex`
- `lib/thinktank/cli/render.ex`
- `priv/config/builtin.yml`

## Oracle

- [ ] A command such as `thinktank models health`, `thinktank rosters health`, or an extended `thinktank benches validate --health` checks the configured roster for a bench or all built-in benches.
- [ ] Text output groups healthy, warning, and failing roster entries by provider/model/agent.
- [ ] JSON output exposes availability, supported tools, pricing coverage, credential state, policy state, and probe latency.
- [ ] Tests cover healthy roster, missing credential, missing tool support, pricing gap, and provider timeout.
- [ ] README describes this as the preflight check for high-stakes bench runs.

## Notes

Capability-aware validation prevents known tool mismatches. Roster health makes the operational state of the whole bench visible before the operator spends money and waits on a degraded run.

Coordinate with `036`: policy readiness should be an artifacted preflight
state, not a one-off probe path that fragments safety evidence away from
`benches validate` and run artifacts.

The 2026-06-11 groom hit this exact failure class: live OpenRouter validation
reported `xiaomi/mimo-v2-pro` stale, and the roster had to move to the
tool-capable `xiaomi/mimo-v2.5-pro`.
