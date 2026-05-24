---
acceptance:
    - Runs record per-agent tool authority, sandbox expectations, credential scope, and approval requirements.
    - Unsafe or underspecified runner policy fails validation before launch.
    - Policy evidence is visible in run artifacts and static reports.
evidence_required:
    - mix test
    - ./scripts/with-colima.sh dagger call check
id: 036-add-runner-permission-policy
lifecycle_stage: Intent
status: ready
title: Add Runner Permission Policy
---

# Add Runner Permission Policy

Priority: high
Status: ready
Estimate: M

## Goal

ThinkTank can prove what each agent was allowed to do because runner permissions, sandbox expectations, credentials, and approval requirements are validated and persisted as run evidence.

## Non-Goals

- Implementing a full enterprise policy engine
- Delegating approval decisions to the model
- Blocking all local experimentation when credentials are absent
- Replacing OS/container sandboxing

## Constraints / Invariants

- Policy is computed and enforced by ThinkTank, not by agent self-reporting.
- Tool risk should consider read/write access, reversibility, credential scope, and external side effects.
- Missing sandbox or permission metadata should fail high-risk compositions before launch.
- Policy artifacts must be local and public-safe.

## Repo Anchors

- `lib/thinktank/bench_validation.ex`
- `lib/thinktank/executor/agentic.ex`
- `lib/thinktank/run_contract.ex`
- `lib/thinktank/run_store.ex`
- `lib/thinktank/artifact_layout.ex`
- `docs/agent-composition-vision.md`

## Oracle

- [ ] Agent/runner config accepts permission policy metadata for tools, credentials, sandbox mode, and approval requirements.
- [ ] Validation fails when a high-risk tool or runner has no explicit policy.
- [ ] Run artifacts record effective policy per agent and any validation warnings.
- [ ] Static report or text output highlights unsafe, degraded, or policy-skipped states.
- [ ] Tests cover read-only agent, write-capable agent, missing policy, credential-scope warning, and public-safe redaction.

## Notes

Harness best practice is moving from per-action prompt approval toward explicit bounded sessions. This item makes ThinkTank's boundary auditable before the project adds richer arbitrary composition.
