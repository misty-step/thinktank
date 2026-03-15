# Repository Guidelines

See [CLAUDE.md](CLAUDE.md) for architecture, commands, and conventions.

## Elixir Style
- `mix format` output only
- Pattern match over conditionals; `with` chains for multi-step error handling
- Prefer deep modules with small public APIs
- Tests live beside code as `*_test.exs` under `test/`
- Table-driven tests via `for` comprehensions

## Commit & PR
- Conventional Commits required (`feat:`, `fix:`, `docs:`, `chore:`)
- No secrets in repo — use env vars only
