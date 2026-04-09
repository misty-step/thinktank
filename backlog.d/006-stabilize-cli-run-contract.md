# Stabilize CLI Run Contract

Priority: high
Status: done
Estimate: M

## Goal
Agents and humans can discover a stable ThinkTank run contract, including input modes and artifact locations, without reading source code.

## Non-Goals
- Adding an HTTP API
- Building a semantic workflow layer
- Changing bench execution semantics beyond contract clarity

## Oracle
- [x] `README.md` and `--help` document `--input`, positional input, and stdin-fed input consistently
- [x] `thinktank run ... --json` and `thinktank review eval ... --json` emit fixed top-level keys for `status`, `output_dir`, `artifacts`, and typed errors
- [x] Non-JSON terminal output includes the selected output directory for completed runs and evals
- [x] Integration coverage proves an agent can discover input mode and artifact location without source reading

## What Was Built
- `thinktank --help` now states the three supported input modes explicitly, matching the README contract.
- `thinktank run` JSON responses now always include a top-level `error` field, with a typed contract error on degraded runs and `null` on complete runs.
- Non-JSON `thinktank run` output now prints the selected root output directory before artifact listings.
- `thinktank review eval` now emits aggregate `artifacts` and typed top-level and per-case `error` objects, derived from actual case output directories.
- Contract coverage now includes stdin-fed `research`, exact JSON key sets for `run` and `review eval`, degraded-run error behavior, mixed-case degraded eval behavior, README/help input wording, and text-mode output-dir visibility.

## Notes
The building blocks already exist in `Thinktank.RunStore` and `Thinktank.Error`. The gap is surface consistency across docs, human output, and machine-readable envelopes.
