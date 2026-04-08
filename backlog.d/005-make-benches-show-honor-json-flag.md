# Make Benches Show Honor JSON Flag

Priority: medium
Status: done
Estimate: S

## Goal
`thinktank benches show` respects the global `--json` contract: JSON only when
`--json` is set, otherwise a human-readable text view.

## Non-Goals
- Changing the JSON schema for `benches show --json`
- Adding new bench metadata fields
- Removing the `workflows show` compatibility alias

## Oracle
- [x] `thinktank benches show research/default --json` still emits the current
      machine-readable JSON payload
- [x] `thinktank benches show research/default` emits human-readable text and is
      not valid JSON
- [x] `thinktank benches show review/default --full` emits human-readable agent
      details instead of raw JSON
- [x] `mix test` passes

## Notes
The current CLI prints JSON for `benches show` even without `--json`, which
contradicts the documented global output contract and the behavior of other
bench-management commands.

## What Was Built
- `Thinktank.CLI` now routes `benches show` through `emit_benches_show/2`, so
  JSON is emitted only when `--json` is set and text output is the default.
- Non-JSON `--full` output now renders full agent details, including
  `system_prompt`, instead of silently dropping part of the full spec.
- CLI coverage now locks three show contracts: `--full --json`, `--json`
  without `--full`, and both text-mode paths.
