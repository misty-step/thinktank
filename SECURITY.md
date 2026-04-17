# Security Policy

## Reporting

Do not open public issues for suspected security problems.

- Prefer GitHub private vulnerability reporting or a private advisory when available.
- If that path is unavailable, contact `@misty-step` privately and include repro steps, impact, and any suggested mitigation.

## Response Expectations

- Acknowledge reports within 3 business days.
- Confirm severity and next steps after triage.
- Coordinate disclosure after a fix or mitigation is available.

## Scope

- API keys, auth files, and agent configuration are security-sensitive.
- `agent_config/auth.json`, `.env`, `*.pem`, and `*.key` must never be committed.
- Required CI security checks should include secret scanning and at least one additional security gate before merge.

## Merge Readiness

The repo's merge-readiness security gates are:

- `trufflehog` in GitHub Actions for secret scanning
- `Security Checks` in GitHub Actions, backed by `dagger call security`
- `mix hex.audit` inside `Quality Checks`

For local reproduction, run:

```bash
./scripts/with-colima.sh dagger call security
./scripts/with-colima.sh dagger call check
```

## Verification Notes

- 2026-04-17: `gh api repos/misty-step/thinktank/branches/master/protection`
  reported `required_signatures.enabled=false` on `master`. Signed commits are
  not currently enforced by GitHub branch protection.
