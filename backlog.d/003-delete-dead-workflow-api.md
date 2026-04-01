# Delete Dead Workflow API

Priority: low
Status: done
Estimate: S

## Goal
Remove unreferenced `Config.workflow/2` and `Config.list_workflows/1` — legacy aliases to bench functions that add surface area without value.

## Non-Goals
- Refactoring Config module beyond deletion

## Oracle
- [x] `Config.workflow/2` and `Config.list_workflows/1` do not exist
- [x] `mix compile --warnings-as-errors` clean
- [x] `mix test` passes
- [x] No references to "workflow" remain in Config module

## What Was Built
- Deleted the dead `workflow/2` and `list_workflows/1` aliases from `Thinktank.Config`, leaving `bench/2` and `list_benches/1` as the only public lookup surface.
- Added a focused regression test that asserts the bench APIs remain exported while the legacy workflow aliases do not.
- Verified there are no remaining `Config.workflow(...)` or `Config.list_workflows(...)` call sites under `lib/` or `test/`.

## Notes
Archaeologist flagged these as dead code — public functions with zero callers or tests. Leftover from a "workflows" → "benches" rename.
