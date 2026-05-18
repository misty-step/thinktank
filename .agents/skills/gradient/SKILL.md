---
name: gradient
description: |
  Use Gradient itself: discover install state, initialize or upgrade
  repositories, operate the Work/Fleet/Context/Evidence/Policy loop, and know
  when repository work should flow through Gradient. Trigger: /gradient.
argument-hint: "[status|init|work|capture|eval|close|upgrade]"
---

# /gradient

Gradient is the local agent control plane. In any initialized repository, use
Gradient as the first-class interface for governed agent work instead of
inventing parallel backlog, evidence, harness, or eval flows.

## When To Use

Use this skill when you need to:

- check whether Gradient is installed and active;
- initialize a repository with Gradient;
- update an already initialized repository from the Gradient core checkout;
- inspect or claim local work;
- capture evidence for completed work;
- run Gradient evals and validation gates;
- close work into `backlog.d/_done`;
- explain the Gradient lifecycle to another agent or operator.

## Lifecycle

Gradient preserves one lifecycle:

```text
Intent -> Work Graph -> Fleet Run -> Evidence -> Policy/Eval -> Feedback
```

Every command should strengthen one part of that lifecycle. Do not bypass it by
manually moving work, inventing one-off run logs, or treating test output as a
substitute for an evidence packet.

## Command Map

Discovery:

```sh
gradient status
gradient status --check
gradient config
```

Initialize or update a repository:

```sh
gradient init --profile solo-frontier /path/to/repo
gradient upgrade --dry-run /path/to/repo
gradient upgrade --apply /path/to/repo
```

Resolve and verify the active harness:

```sh
gradient resolve
gradient validate
gradient eval
```

Operate local work:

```sh
gradient work list --status all
gradient work next
gradient work show <id|path>
gradient work claim <id|path> <owner>
```

Capture and close work:

```sh
gradient capture backlog.d/<work-item>.md
gradient report --latest
gradient close backlog.d/<work-item>.md
```

Feedback intake:

```sh
gradient feedback report \
  --module Work \
  --classification work-adapter \
  --severity high \
  --summary "short public-safe summary" \
  --expected "expected behavior" \
  --actual "actual behavior" \
  --evidence "public-safe evidence" \
  --route backlog
```

## Operating Rules

- In initialized repositories, prefer `gradient` over repo-local ad hoc
  harness, backlog, evidence, trace, or eval commands when Gradient has an
  equivalent command.
- Keep repo-owned state repo-owned: `gradient.yaml`, `backlog.d`, private
  source config, evidence, policy, feedback, and run artifacts are not blindly
  overwritten by upgrades.
- Keep Gradient-managed state managed: scripts, schemas, profiles, standards,
  evals, Go module files, and native harness primitives should be refreshed
  through `gradient upgrade`.
- Run `gradient validate` after changing profiles, schemas, harness primitives,
  work items, evidence, policies, or module contracts.
- Run `gradient eval` before claiming a Gradient behavior change is ready.
- Capture evidence with `gradient capture` before closing work.

## Harness Notes

The native HARNESS makes this skill available everywhere Gradient initializes:

- canonical skill root: `.agents/skills/gradient`;
- Claude bridge: `.claude/skills/gradient`;
- Codex bridge: `.codex/skills/gradient`;
- Pi bridge: `.pi/skills/gradient`.

If an agent can read the repository harness, it should be able to discover that
Gradient exists, which commands to run, and how Gradient expects work to move
through the lifecycle.
