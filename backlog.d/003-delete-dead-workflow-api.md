# Delete Dead Workflow API

Priority: low
Status: in-progress
Estimate: S

## Goal
Remove unreferenced `Config.workflow/2` and `Config.list_workflows/1` — legacy aliases to bench functions that add surface area without value.

## Non-Goals
- Refactoring Config module beyond deletion

## Oracle
- [ ] `Config.workflow/2` and `Config.list_workflows/1` do not exist
- [ ] `mix compile --warnings-as-errors` clean
- [ ] `mix test` passes
- [ ] No references to "workflow" remain in Config module

## Notes
Archaeologist flagged these as dead code — public functions with zero callers or tests. Leftover from a "workflows" → "benches" rename.
