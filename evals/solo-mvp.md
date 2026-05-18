# Solo MVP Evals

These are the current structural evals run by:

```sh
./scripts/gradient.sh eval
```

## Public-Safe Fixture Scan

Checks `backlog.d`, `.gradient`, `examples`, and `schemas` for common token and
private-key patterns. This protects the public-safe boundary.

## Evidence Completeness

Every evidence packet must include artifacts for:

- work item;
- fleet run;
- context bundle;
- policy outcome.

This prevents a local run from being promoted on narration alone.

## Context Provenance

Every context item must carry:

- source URI;
- freshness;
- permission label;
- citation.

This keeps Context separate from Harness: skills and tools execute work, while
Context explains why retrieved knowledge is trustworthy.

## Policy Verdicts

At least one policy outcome must be usable: `pass` or `needs_review`. Future
red fixtures should prove `blocked` outcomes for missing evidence and
public-safe violations.
