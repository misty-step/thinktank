---
name: flywheel
description: |
  Outer-loop Gradient work cycle. Pick, shape, implement, settle, ship, monitor,
  and feed learnings back into docs, schemas, profiles, or harness. Trigger:
  /flywheel.
argument-hint: "[--max-cycles N]"
---

# /flywheel

Use `/flywheel` when running repeated Gradient improvement cycles. This repo has
no backlog runner yet, so the cycle starts from an explicit user request or a
tracked docs/schema debt item.

This repo now has `backlog.d` as the Work adapter v0, but no closure
detector beyond the tracer-bullet fixture. Until a detector exists, preserve
work references manually and mark closure mechanics unverified.

## Composition

`pick -> /shape -> /implement -> /yeet -> /settle -> /ship -> /monitor -> loop`

`/ship` owns final closure and reflection. `/flywheel` consumes the result; it
does not archive tickets or invoke `/reflect` directly.

## Repo-Specific Loop

- Pick work that strengthens one lifecycle stage.
- Shape a context packet with public-safe boundaries.
- Implement docs/YAML/JSON Schema/harness changes.
- Settle through the manual gate.
- Ship to `master` only after evidence is recorded.
- Monitor drift in docs, schemas, profiles, harness, and validation debt.

## Known Gap

The tracker and closure detector gap is P0 harness/product debt because it
prevents `/ship`, `/groom`, `/settle`, `/flywheel`, and `/implement` from
mechanically proving work closure.
