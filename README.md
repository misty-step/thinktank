# thinktank

Multi-perspective AI research tool. Routes questions through an LLM-powered perspective router, dispatches agents in parallel (quick mode) or via Pi subprocesses (deep mode), and synthesizes results into structured artifacts.

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
./thinktank "analyze this codebase" --paths ./src --quick
```

## Usage

```bash
thinktank <instruction> [options]
echo "instruction" | thinktank [options]
```

### Options

| Flag | Description |
|------|-------------|
| `--paths PATH` | Files/dirs for agent context (repeatable) |
| `--quick, -q` | Quick mode: parallel API calls, no tools |
| `--deep, -d` | Deep mode: Pi agent subprocesses (default) |
| `--json` | Output structured JSON to stdout |
| `--output, -o` | Output directory (default: auto-generated) |
| `--models LIST` | Comma-separated model list (overrides router) |
| `--roles LIST` | Comma-separated roles (bypasses router) |
| `--perspectives N` | Number of perspectives (default: 4) |
| `--dry-run` | Show plan without executing |
| `--no-synthesis` | Skip synthesis step |

### Examples

```bash
# Quick parallel analysis
thinktank "review this auth flow" --paths ./src/auth --quick

# Deep mode with Pi agents
thinktank "audit for security issues" --paths ./src --perspectives 5

# Pipe instruction via stdin
echo "compare approaches" | thinktank --models anthropic/claude-sonnet-4.6,openai/gpt-5.4 --quick

# Dry run to preview
thinktank "suggest improvements" --paths ./lib --dry-run
```

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
