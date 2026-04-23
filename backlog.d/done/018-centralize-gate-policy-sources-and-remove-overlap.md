# Centralize Gate Policy Sources And Remove Overlap

Priority: medium
Status: done
Estimate: M

## What Was Built

- Added `scripts/ci/gate-policy.sh` as the shared source for gate policy constants used by architecture, security, and backlog-state gates.
- Moved artifact layout validation into `Thinktank.ArtifactLayout.validate_path_contract/1`, so the architecture gate validates the canonical registry instead of mirroring path literals in shell.
- Narrowed the security gate to security-sensitive dynamic execution and shell invocation checks, leaving runtime boundary enforcement to the architecture gate.
- Strengthened the backlog-state gate to reject unsupported active statuses and stale `## Repo Anchors` path bullets.
- Added behavior tests for the gate boundaries, artifact path contract validation, shell invocation variants, active backlog statuses, and live repo anchor checks.

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
