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

ThinkTank becomes usable as an "agent tmux" for live compositions: operators can watch agents, give bounded feedback, abort or retry work, and synthesize from the final evidence.

## Non-Goals

- Building a remote dashboard
- Replacing local artifacts with UI state
- Letting feedback mutate history invisibly
- Allowing agents to decide their own approval requirements

## Constraints / Invariants

- The first interface can be CLI-first; a TUI is optional after the data model works.
- Feedback is a typed event stored under the run directory.
- Every feedback event records target, author, timestamp, message, and whether it was included in downstream synthesis.
- Abort/retry controls must use the same lifecycle owner as normal run finalization.

## Repo Anchors

- `lib/thinktank/run_inspector.ex`
- `lib/thinktank/run_store.ex`
- `lib/thinktank/trace_log.ex`
- `lib/thinktank/engine/runtime.ex`
- `lib/thinktank/cli.ex`
- `docs/agent-composition-vision.md`

## Oracle

- [ ] `thinktank compose attach <run>` or equivalent shows stage/agent status from durable artifacts.
- [ ] `thinktank compose feedback <run> --to <agent-or-stage> --message ...` appends a feedback event and exposes it to allowed downstream synthesis.
- [ ] Abort or retry operations record trace events and terminal status consistently.
- [ ] Tests prove feedback persistence, synthesis context inclusion, invalid target handling, and terminal-run rejection.
- [ ] README documents that feedback is a run artifact, not an untracked chat message.

## Notes

This is the operator half of the vision. It should come after the composition contract has explicit stage and agent identities to target.
