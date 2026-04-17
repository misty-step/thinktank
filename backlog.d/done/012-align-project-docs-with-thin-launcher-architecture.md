# Align Project Docs With Thin Launcher Architecture

Priority: medium
Status: done
Estimate: S

## Goal
The project-level docs describe the current ThinkTank architecture truthfully: a thin Pi bench launcher with durable artifacts and no parallel direct-API workflow surface.

## Non-Goals
- Changing runtime behavior, model policy, or bench semantics
- Rewriting README or ADR history beyond what is needed to remove drift
- Reintroducing older router/dispatch abstractions as supported surfaces

## Constraints / Invariants
- `AGENTS.md`, `CLAUDE.md`, ADRs, README, and `project.md` must tell the same boundary story
- Module references in docs must map to active code paths
- Historical context can remain, but it must be marked as historical rather than current architecture

## Repo Anchors
- `project.md`
- `AGENTS.md`
- `CLAUDE.md`
- `README.md`
- `docs/adr/0001-thin-pi-bench-launcher.md`

## Oracle
- [ ] `project.md` no longer describes stale router/dispatch/output architecture as the active system
- [ ] The current public boundary matches the thin-launcher doctrine documented elsewhere in the repo
- [ ] A newcomer reading only the top-level docs gets the right mental model of what ThinkTank is and is not

## Notes
On 2026-04-10, the repo docs were internally inconsistent. `AGENTS.md`, `CLAUDE.md`, and the thin-launcher ADR describe ThinkTank as a Pi bench launcher, while `project.md` still presents older OpenRouter/router/dispatch/output concepts as the active architecture. That drift weakens design judgment exactly where this repo depends on disciplined boundaries.

## What Was Built
- Rewrote `project.md` so it describes the current product boundary as a thin Pi bench launcher instead of the older router/dispatch architecture.
- Updated the top-level README artifact contract to mention the current per-run cost metadata and inspection surface.
- Left the thin-launcher ADR and operator docs aligned around the same boundary: ThinkTank owns launch and artifacts; Pi owns exploration and reasoning.
