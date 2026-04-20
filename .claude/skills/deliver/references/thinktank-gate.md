# /deliver in this repo — Thinktank inner-loop notes

/deliver's clean-loop step (`/code-review + /ci + /refactor + /qa`) closes
against this repo's actual gate, not a generic `make check`. Specifics below.

## The gate

`/ci` in this repo resolves to:

```
./scripts/with-colima.sh dagger call check
```

That is the only command that determines merge-readiness. The clean loop is
not clean until that command exits 0. See
`.claude/skills/ci/references/thinktank-gate.md` for what the gate enforces.

The native pre-push hook (`.githooks/pre-push`) runs the same command, so if
`/deliver` finishes clean the `git push` in a later `/yeet` or `/settle`
should not surprise you.

## Backlog source

Backlog items live under `backlog.d/` as numbered markdown files
(`NNN-short-slug.md`). Completed items move to `backlog.d/done/`. When
/deliver is invoked without an explicit ticket, resolve the next item from
`backlog.d/README.md` or the lowest-numbered unclaimed file.

Do not invent tickets. Do not batch unrelated backlog items into a single
deliver run — one ticket, one branch, one merge-ready diff.

## /qa in the clean loop

This repo's `/qa` is already specialized — see
`.claude/skills/qa/SKILL.md`. It is a **CLI behavior verifier**, not a
browser driver. It rebuilds the escript and walks the critical-path command
table. Do not substitute browser QA here; there is no UI.

Full research/review runs in QA call live APIs and cost money. /deliver's
clean loop should stay on `--dry-run` unless the diff touches agent
dispatch, prompt rendering, synthesis, or the executor — the cases where
dry-run cannot prove correctness.

When a live run is needed, pin cheap models (Arcee Trinity Large, Gemini 3
Flash/Flashlite, GPT-5.4 Nano, Claude Haiku, Minimax M2.7). Flagship tiers
waste USD on plumbing verification.

## /refactor scope

Branch-aware `/refactor` on a feature branch compares against base. In this
repo the base is `master` (not `main`). Confirm with `git symbolic-ref
refs/remotes/origin/HEAD` before relying on a default.

The refactor bar is the same as CLAUDE.md's: deep modules, kill shallow
pass-throughs, no semantic workflow DSL creeping in. Any refactor that
introduces a new regex-over-agent-prose layer is a red-line violation —
reject and redesign.

## Receipt expectations

/deliver emits `receipt.json`. Callers (typically /flywheel) read it via
exit code + file, never by parsing stdout. Keep receipts machine-readable:
branch name, commit SHA, gate status, iterations, next action.

## Gotchas

- **Base branch is `master`.** Many /deliver heuristics default to `main`.
  This repo's primary is `master` — `git log origin/master..HEAD` is the
  diff that matters.
- **release-please owns version bumps.** Do not hand-edit `@version` in
  `mix.exs`, `CHANGELOG.md`, or `release-please-config.json` during
  /deliver. Conventional Commit messages drive the bump; release-please
  opens the release PR. A /deliver run that touches those files is doing
  the wrong job.
- **backlog.d/done/ is archive, not trash.** When closing a ticket move
  the file with `git mv`, preserving history. Don't delete.
- **Dialyzer PLT is slow on first build.** If /ci times out on a fresh
  clone it's almost always PLT building, not a real failure. Re-run.
- **Muontrap vs System.cmd.** If the executor tests flake locally with Pi
  subprocess errors, `THINKTANK_DISABLE_MUONTRAP=1` forces the plain
  `System.cmd/3` runner for debugging. Never set in CI or committed.
