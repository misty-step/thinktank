# Add Security Gating Workflow

Priority: medium
Status: done
Estimate: M

## Goal
Security regressions are blocked automatically before merge, with ownership and reporting paths visible in-repo.

## Non-Goals
- Production runtime protection outside this CLI's scope
- Replacing existing secret-scanning hooks
- Moving security policy into off-repo dashboards

## Oracle
- [ ] CI includes an additional required security status check beyond secret scanning and `mix hex.audit`
- [ ] The workflow runs a static-analysis or dependency-policy step that fails on actionable findings
- [ ] `SECURITY.md` documents the required security checks for merge readiness
- [ ] A follow-up verification note records whether signed-commit enforcement is enabled on `master`

## Notes
This repo now has baseline ownership and reporting docs. The next step is enforceable automated security gating.

## What Was Built
- Added a repo-owned `scripts/ci/security-gate.sh` static-analysis gate plus ExUnit coverage for the expected runtime boundary violations.
- Extended the Dagger module with `security` and included that gate in the canonical `check` pipeline.
- Added a dedicated `Security Checks` GitHub Actions job and documented merge-readiness security checks plus the verified `required_signatures=false` note for `master` in `SECURITY.md`.
