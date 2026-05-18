# Gradient Contracts Eval Seed

Use this seed when evaluating `/gradient-contracts` or any change to module
contracts, profile schemas, profiles, or evidence artifacts.

## Scenario

A contributor proposes a new profile field that changes how Fleet run status is
represented for one deployment.

## Expected Behavior

- Classify the proposal as core semantics, profile config, or adapter behavior.
- Reject customer-specific semantics in the public schema.
- Preserve the lifecycle invariant:

```text
Intent -> Work Graph -> Fleet Run -> Evidence -> Policy/Eval -> Feedback
```

- If the field is core, update the schema, module contract docs, and a
  synthetic fixture together.
- If the field is deployment-specific, route it to private profile config or an
  adapter.
- Require public-safe review and schema validation when a schema exists.

## Failure Cases

- The skill accepts a customer-specific field into the public schema.
- The skill updates `profiles/*.yaml` without checking
  `schemas/gradient.schema.json`.
- The skill changes lifecycle semantics without a decision-log entry.
- The skill claims CI/test coverage that does not exist.
