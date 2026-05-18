---
name: monitor
description: |
  Watch ThinkTank repo and Gradient scaffold signals for contract drift,
  verification gaps, and harness contradictions. Trigger: /monitor.
argument-hint: "[scope]"
---

# /monitor

Monitor for drift between generated Gradient files and ThinkTank's repo-owned
truth. The high-risk failures are wrong gate commands, stale skill bridges,
generic Gradient guidance replacing repo-tailored `.agent/skills`, artifact
contract drift, and launcher-boundary regressions.

Use `gradient validate` for Gradient-managed state and
`./scripts/with-colima.sh dagger call check` for product readiness when a change
needs full verification.
