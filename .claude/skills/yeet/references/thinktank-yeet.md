# /yeet in this repo — Thinktank push notes

/yeet's push step hits the native pre-push hook at `.githooks/pre-push`,
which runs:

```
./scripts/with-colima.sh dagger call check
```

This is the full merge-readiness gate (format, compile warnings,
credo --strict, Dialyzer, shell/YAML hygiene, gitleaks, security gate,
live OpenRouter model-ID validation, architecture gate, escript smoke,
87% coverage floor). See
`.claude/skills/ci/references/thinktank-gate.md` for the enforced list.

If the hook fails, /yeet must NOT pass `--no-verify`. The failure is the
signal. Run `dagger call check` locally, read the output, fix the
underlying issue, re-commit (NEW commit, not amend), then push again.

## Primary branch

**`master`**, not `main`. Confirm before any merge-base reasoning with:

```
git symbolic-ref refs/remotes/origin/HEAD
```

## Commit slicing

Conventional Commits are load-bearing here because release-please parses
them to cut releases. Use the standard prefixes: `feat:`, `fix:`,
`chore:`, `refactor:`, `docs:`, `test:`, `ci:`, `build:`, `perf:`. Scope
is optional; breaking changes via `!` (e.g. `feat!:`) or a
`BREAKING CHANGE:` footer.

When slicing a diff into multiple commits, each commit's prefix must
describe that commit, not the branch as a whole. A `refactor:` commit
followed by a `feat:` commit is fine; a `feat:` commit that secretly
contains a cross-cutting refactor lies to release-please.

## Backlog moves

When /yeet's tidy pass notices a finished backlog item in `backlog.d/`,
it moves the file to `backlog.d/done/` with `git mv` in a `chore(backlog):`
commit. Do not delete backlog files — they archive.

## What belongs, what doesn't

Per CLAUDE.md non-goals, the following do NOT belong on master and should
be split off, stashed, or dropped during /yeet's tidy pass:

- any new "semantic workflow DSL" / stage graph / prose parser — those
  are the repo's declared non-goals and will fail the architecture gate
  at the push hook
- precomputed diff bundles as primary review context
- additional prompt prose working around a weak model (that's a model
  swap, not a harness change)

If the diff contains one of the above, surface it before committing — the
push will fail the architecture gate anyway.

## Files that should never be committed

- `.env` (copied from `.env.example` by `with-colima.sh`)
- `erl_crash.dump` (checked in historically; flag if it regrows)
- `thinktank.log` (local run log)
- `_build/`, `cover/`, `deps/` (git-ignored, but flag stray entries)
- any `/tmp/thinktank-*` artifact directories
- worktree directory names that look like feature slugs (e.g. the stray
  `silver-spinning-quartz/`, `zealous-hiking-dahlia/` at repo root are
  worktrees or leftover scratch — investigate before yeeting, do not
  blindly commit)

Stage explicitly by path. Never `git add -A` or `git add .` — the repo
has enough stray local state that a blind add will catch something wrong.

## Gotchas

- **Colima must be running locally** for the pre-push hook. If it's down
  the hook fails for an environmental reason, not a code reason —
  `./scripts/with-colima.sh` starts it.
- **`THINKTANK_OPENROUTER_API_KEY` must be set** for the live model-ID
  validation stage of the hook.
- **Hooks may not be installed.** Fresh clones need `./scripts/setup.sh`
  to install hooks from `.githooks/`. Without that, the push hits GitHub
  without a local gate run, and CI will be the first signal.
- **Never amend to "fix" a hook failure.** Per the user's global
  instructions, hook failure means the commit did not land — so `--amend`
  would modify the previous commit. Make a NEW commit instead.
