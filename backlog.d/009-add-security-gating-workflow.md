# Add Security Gating Workflow

Priority: medium
Status: ready
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
