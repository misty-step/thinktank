---
acceptance:
    - Operators can attach to a running composition and inspect per-agent or per-stage status.
    - Operator feedback is recorded as durable run events and can be included in synthesis context.
    - Attach/feedback/abort controls work from the existing run store and trace lifecycle.
evidence_required:
    - mix test
    - ./scripts/with-colima.sh dagger call check
id: 035-add-live-agent-room
lifecycle_stage: Intent
status: ready
title: Add Live Agent Room
---

# Add Live Agent Room

Priority: medium
Status: ready
Estimate: L

## Goal

ThinkTank becomes usable as an "agent tmux" for live runs: operators can watch
agent status and streams, append durable feedback events, and synthesize from
final evidence while abort/retry controls wait for explicit runner policy.

## Non-Goals

- Building a remote dashboard
- Replacing local artifacts with UI state
- Letting feedback mutate history invisibly
- Allowing agents to decide their own approval requirements
- Adding abort/retry controls before runner permission policy exists

## Constraints / Invariants

- The first interface can be CLI-first; a TUI is optional after the data model works.
- Feedback is a typed event stored under the run directory.
- Every feedback event records target, author, timestamp, message, and whether it was included in downstream synthesis.
- Abort/retry controls are a follow-up after `036` can prove permission and approval policy for the target runner.

## Repo Anchors

- `lib/thinktank/run_inspector.ex`
- `lib/thinktank/run_store.ex`
- `lib/thinktank/trace_log.ex`
- `lib/thinktank/engine/runtime.ex`
- `lib/thinktank/cli.ex`
- `docs/agent-composition-vision.md`

## Oracle

- [ ] `thinktank runs attach <run>` or `thinktank compose attach <run>` shows agent status and stream locations from durable artifacts.
- [ ] `thinktank runs feedback <run> --to <agent-or-run> --message ...` appends a feedback event and exposes it to allowed downstream synthesis.
- [ ] Feedback events are immutable trace/run artifacts and terminal-run feedback is rejected clearly.
- [ ] Tests prove status attachment, feedback persistence, synthesis context inclusion, invalid target handling, and terminal-run rejection.
- [ ] README documents that feedback is a run artifact, not an untracked chat message.

## Notes

This is the operator half of the vision. The first slice is read-only attach
plus durable feedback. Abort/retry belongs after `036` and the flat composition
contract have explicit agent identities and approval requirements.
