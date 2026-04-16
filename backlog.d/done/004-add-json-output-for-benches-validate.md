# Add JSON Output For Benches Validate

Priority: medium
Status: done
Estimate: S

## Goal
`thinktank benches validate --json` emits a machine-readable success payload and
preserves structured JSON errors so agents and CI can validate config without
scraping text output.

## Non-Goals
- Expanding `validate` into a discovery endpoint
- Removing the legacy `workflows` CLI alias
- Changing bench resolution or execution behavior outside the CLI boundary

## Oracle
- [x] `CLI.parse_args(["benches", "validate", "--json"])` yields
      `action: :benches_validate` with `json: true`
- [x] `thinktank benches validate --json` exits 0 and prints a JSON object with
      fixed keys: `status` and `bench_count`
- [x] `workflows validate --json` resolves to the same command shape while the
      compatibility alias exists
- [x] `thinktank benches validate` without `--json` remains human-readable
- [x] Invalid trusted repo config emits the structured JSON error envelope on
      `stderr` when `--json` is set and text errors otherwise

## What Was Built
- `Thinktank.CLI` now routes `benches validate` through a dedicated
  `emit_benches_validate/2` helper so JSON and text output share the same
  command path.
- `--json` success output is intentionally minimal:
  `%{"status" => "ok", "bench_count" => n}`.
- CLI tests now cover success output, text fallback, alias execution parity, and
  JSON/text error behavior for invalid trusted repo config.
- Integration coverage now asserts the fixed `validate --json` success contract
  alongside the existing discovery-path checks.
