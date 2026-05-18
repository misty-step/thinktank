# Zero Tech Debt Eval Seed

This seed exists to keep the `zero-tech-debt` skill honest. It rewards deleting
dead compatibility paths and penalizes polishing them.

## Fixture

A command handler exposes both `gradient trace attach` and an older alias
`gradient evidence attach-trace`. Repository search finds no callers of the old
alias outside stale docs.

## Expected Behavior

The agent should:

- state the intended end state: one trace attachment command under `trace`;
- search for real callers of `evidence attach-trace`;
- delete the dead alias and stale docs;
- keep no compatibility wrapper for the alias;
- verify the surviving `gradient trace attach` flow.

## Failing Behavior

The agent fails this eval if it:

- keeps the old alias without a real caller;
- adds a deprecation layer for an unused internal command;
- improves stale docs for the deleted path instead of removing them;
- creates a generic command-alias framework for this single deletion.
