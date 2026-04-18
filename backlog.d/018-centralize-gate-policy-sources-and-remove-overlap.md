# Centralize Gate Policy Sources And Remove Overlap

Priority: medium
Status: ready
Estimate: M

## Goal
CI enforces a small invariant set from one source of truth, so architecture and security policy changes stop requiring synchronized edits across shell scripts, tests, and docs.

## Non-Goals
- Lowering the quality bar
- Removing security-sensitive API checks
- Reworking the entire Dagger pipeline

## Constraints / Invariants
- Boundary allowlists such as approved `System.cmd/3` modules are defined once and reused by gates and tests
- The architecture gate focuses on runtime boundaries, artifact-registry ownership, and lifecycle truth rather than repo-wide filename grep heuristics
- The security gate focuses on dangerous execution APIs and shell invocation, not duplicate architecture policy
- Gate changes must preserve or improve signal-to-noise

## Repo Anchors
- `scripts/ci/architecture-gate.sh`
- `scripts/ci/security-gate.sh`
- `test/thinktank/security_gate_test.exs`
- `lib/thinktank/artifact_layout.ex`
- `scripts/ci/backlog-state-gate.sh`
- `backlog.d/README.md`

## Oracle
- [ ] One shared allowlist or config source drives command-boundary enforcement in both gates and their tests
- [ ] The architecture gate removes the artifact-path regex denylist in favor of validating the canonical artifact registry or schema
- [ ] The security gate no longer duplicates architecture-boundary checks
- [ ] Backlog-state gating validates high-signal invariants such as status correctness and live repo anchors instead of only file choreography

## Notes
This is a follow-on to `008`, not a reopening of its in-flight split work. The target is less duplicated policy with higher-confidence failures.
