# thinktank

Workflow engine for multi-agent research and code review. ThinkTank loads typed workflow and agent configuration, routes work across multiple models, runs agents via direct API fanout or Pi subprocesses, and writes structured run artifacts.

Built with Elixir/OTP. This is v5 — an Elixir rewrite of the [Go v4 codebase](https://github.com/misty-step/thinktank/tree/v4-archive).

## Quick Start

```bash
# Install Elixir (1.17+) and Erlang/OTP (26+)
# macOS: brew install elixir

# Clone and build
git clone https://github.com/misty-step/thinktank.git
cd thinktank
mix deps.get
mix escript.build

# Set API key
export OPENROUTER_API_KEY="your-key"  # https://openrouter.ai/keys

# Run
./thinktank research "analyze this codebase" --paths ./src --quick
```

## Usage

```bash
thinktank run <workflow> --input "..." [options]
thinktank research "..." [options]
thinktank review [options]
thinktank workflows list|show|validate
```

### Options

| Flag | Description |
|------|-------------|
| `--input TEXT` | Workflow input text |
| `--paths PATH` | Files/dirs for workflow context (repeatable) |
| `--quick, -q` | Direct API fanout executor |
| `--deep, -d` | Pi subprocess executor |
| `--json` | Output structured JSON to stdout |
| `--output, -o` | Output directory (default: auto-generated) |
| `--models LIST` | Comma-separated model overrides for research routing |
| `--roles LIST` | Comma-separated research roles (bypasses router) |
| `--perspectives N` | Number of research perspectives |
| `--base REF` | Review workflow base ref |
| `--head REF` | Review workflow head ref |
| `--repo REPO` | GitHub repo for PR review mode |
| `--pr N` | GitHub PR number for PR review mode |
| `--dry-run` | Print the resolved workflow contract without executing |

### Examples

```bash
# Quick parallel research
thinktank research "review this auth flow" --paths ./src/auth --quick

# Deep research run with Pi agents
thinktank research "audit for security issues" --paths ./src --perspectives 5 --deep

# Native review workflow against the current branch diff
thinktank review --base origin/main --head HEAD

# Explicit workflow invocation
thinktank run research/default --input "compare approaches" --models openai/gpt-5.4,anthropic/claude-sonnet-4.6 --quick

# Show workflow shape
thinktank workflows show review/cerberus
```

## Configuration

ThinkTank loads configuration with this precedence:

1. built-in defaults
2. `~/.config/thinktank/config.yml`
3. `.thinktank/config.yml` in the current repository
4. CLI flags

Built-in workflows:

- `research/default`
- `review/cerberus`

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Generic error |
| 2 | Authentication error |
| 3 | Rate limit exceeded |
| 4 | Invalid request |
| 5 | Server error |
| 6 | Network error |
| 7 | Input error |
| 8 | Content filtered |
| 9 | Insufficient credits |
| 10 | Cancelled |

## Development

```bash
mix test                          # Run tests
mix format                        # Format code
mix compile --warnings-as-errors  # Strict compilation
mix escript.build                 # Build CLI binary
```

### Pre-commit Hooks

```bash
pre-commit install
```

Hooks: gitleaks, trailing-whitespace, mix-format, validate-elixir-models.

## License

[MIT](LICENSE)
