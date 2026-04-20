# /settle in this repo — Thinktank landing notes

## Gate

```
./scripts/with-colima.sh dagger call check
```

This is the same command /ci and the native pre-push hook run. /settle
cannot declare a branch landable until this exits 0. See
`.claude/skills/ci/references/thinktank-gate.md` for the full enforced list
(format, compile warnings, credo --strict, Dialyzer, shell/YAML hygiene,
gitleaks, security gate, live OpenRouter model-ID validation, architecture
gate, escript smoke, 87% coverage floor).

## Primary branch

**`master`**, not `main`. Set `--base master` or confirm with:

```
git symbolic-ref refs/remotes/origin/HEAD
```

## Land policy

Default squash-on-land for single-ticket branches. The backlog discipline
is one ticket per branch (see `backlog.d/` numbered items), so squash is
almost always right. Merge commit only for multi-ticket branches where
reviewers need per-commit history preserved — rare.

## Release-please is load-bearing

Version bumps, CHANGELOG entries, and GitHub Releases are driven by
`release-please-config.json` and Conventional Commit messages. /settle
does NOT:

- edit `@version` in `mix.exs`
- edit `CHANGELOG.md` by hand
- create tags directly
- open the release PR (release-please does)

/settle DOES:

- ensure commit messages follow Conventional Commits so release-please can
  parse them (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `test:`,
  breaking changes via `!` or `BREAKING CHANGE:` footer)
- land the feature PR cleanly so release-please's next run picks up the
  new commits

If you find yourself about to write `chore(release): v6.4.0` in a commit,
stop — that's release-please's job.

## PR review responses

When addressing review comments, respond by pushing fixes, not by arguing
inline. The review bench (thinktank's own `review/default`) is used to
generate reviews, but landing still requires human approval per CODEOWNERS.

## CODEOWNERS

`CODEOWNERS` is checked in. Respect review requirements — /settle cannot
force-merge past a CODEOWNERS block. If a required reviewer is unavailable,
surface to the user rather than rerouting.

## Git-native mode

This repo uses GitHub PRs as the landing mechanism. Git-native verdict-ref
mode (the one /settle documents for PR-less flows) is not in use here.
Default to GitHub mode unless the user explicitly asks otherwise.

## Gotchas

- **Hook installation.** `./scripts/setup.sh` installs the hooks from
  `.githooks/`. A clone where hooks aren't installed will push without
  running the gate locally — the user may have skipped `setup.sh` and
  the first push fails in GitHub Actions. If /settle encounters that
  pattern, suggest running setup before retrying, not bypassing.
- **Never bypass hooks.** `--no-verify` on push is forbidden unless the
  user explicitly requests it. Per CLAUDE.md Red Lines, the gate is
  load-bearing.
- **Colima dependency.** Landing requires the gate to pass. The gate
  requires Colima. If Colima is down, /settle cannot verify landability —
  start it, don't skip it.
- **`THINKTANK_OPENROUTER_API_KEY` must be set** for the live model-ID
  stage. A missing key fails the gate for a reason unrelated to the diff.
