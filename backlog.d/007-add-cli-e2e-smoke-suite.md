# Add CLI E2E Smoke Suite

Priority: high
Status: in-progress
Estimate: M

## Goal
Core ThinkTank flows are verified through the built escript in temporary workspaces so contract regressions are caught at the real user entrypoint.

## Non-Goals
- Running live OpenRouter calls in every CI job
- Visual regression testing
- Replacing focused unit or integration tests

## Oracle
- [ ] CI runs at least one escript-backed smoke path for `research` or `review eval`
- [ ] Smoke tests assert exit codes plus generated artifacts such as `contract.json`, `manifest.json`, and summary output
- [ ] Smoke coverage includes one stdin-fed command and one saved-contract replay
- [ ] The smoke suite completes in under 60 seconds locally

## Notes
Current tests cover module-level contracts well, but they stop short of the built binary path. This item closes the last-mile verification gap.
