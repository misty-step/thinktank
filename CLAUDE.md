# CLAUDE

## Purpose

Agent-first research tool for multi-perspective AI analysis. Routes questions through an LLM-powered perspective router, dispatches agents in quick (parallel API) or deep (Pi subprocess) mode, produces kill-safe structured artifacts.

## Architecture Map

```
lib/thinktank/cli.ex            → Escript entry, arg parsing, dispatch
lib/thinktank/router.ex         → LLM-powered perspective generation
lib/thinktank/perspective.ex    → Perspective struct (role + model + prompt)
lib/thinktank/dispatch/quick.ex → Parallel OpenRouter API calls
lib/thinktank/dispatch/deep.ex  → Pi subprocess orchestration via MuonTrap
lib/thinktank/openrouter.ex     → OpenRouter HTTP client (Req)
lib/thinktank/synthesis.ex      → Structured fan-in with retry
lib/thinktank/output.ex         → Kill-safe artifact writer + manifest
lib/thinktank/application.ex    → OTP supervision tree
```

**Start here:** `lib/thinktank/cli.ex` — the `main/1` function shows the full execution flow.

## Run & Test

```bash
# Build escript
mix escript.build

# Run
./thinktank "research question" --paths ./src --quick --dry-run

# Test
mix test

# Format: auto-fix locally, check in CI
mix format                    # Apply formatting
mix format --check-formatted  # Verify (CI gate)

# Compile with warnings-as-errors
mix compile --warnings-as-errors

# Dialyzer (when available)
mix dialyzer
```

**Required env:** `OPENROUTER_API_KEY` or `THINKTANK_OPENROUTER_API_KEY`

### Legacy Go (archiving — see #250)

```bash
go build ./... && go test -race ./...
golangci-lint run ./...
./scripts/check-coverage.sh   # 79% minimum
govulncheck -scan=module
```

## Quality & Pitfalls

### Definition of Done
- `mix test` passes
- `mix format --check-formatted` clean
- `mix compile --warnings-as-errors` clean
- Conventional commit message

### Critical Invariants
- **No error suppression**: Handle every `{:error, _}` explicitly
- **TDD**: Write tests first, then implement
- **Run `mix format` before push**
- **Kill-safe output**: Atomic manifest writes (tmp + rename) in `Output`
- **Defensive deserialization**: Type guards and nil filtering for LLM structured output

### Model IDs — Mechanical Enforcement
- **Default models live in** `lib/thinktank/cli.ex` `@default_models`
- **Go registry**: `internal/models/models.go` — legacy source of truth until #250 archives Go
- **Pre-commit hook**: `scripts/validate-elixir-models.sh` rejects Elixir commits with model IDs not in Go registry
- **If models are stale**: WebSearch OpenRouter models page, update `lib/thinktank/cli.ex` and `internal/models/models.go`, then use the ID

### Pre-commit Hooks
```bash
pre-commit install  # One-time setup
```
Hooks: gitleaks, trailing-whitespace, mix-format, validate-elixir-models.
Legacy (until #250): go-fmt, go-vet.

## References

- [README.md](README.md) — Usage, CLI flags, model list
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — License policy, detailed setup
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — Common issues
- [.groom/BACKLOG.md](.groom/BACKLOG.md) — Prioritized backlog
- [.groom/plan-*.md](.groom/) — Sprint plans
