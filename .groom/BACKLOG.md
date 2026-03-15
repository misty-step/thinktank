# Backlog Ideas

Last groomed: 2026-03-14

## High Potential (promote next session if capacity)

- **Cost tracking from API responses** — Capture prompt_tokens/completion_tokens from OpenRouter responses. Per-run cost summaries. Source: LLM infrastructure audit.
- **Perspective caching** — Same instruction pattern → reuse router perspectives. Skip router call for repeated queries. Source: architecture design.
- **Config file support** — `~/.thinktankrc` or `~/.config/thinktank/config.toml` for default model lists, router model, output preferences. Source: #215 (closed).
- **Burrito distribution** — Package Elixir app as standalone binary (no Erlang runtime needed). Source: Elixir research.
- **Dry-run mode with cost estimate** — Show planned perspectives, estimated tokens, projected cost before executing. Source: agent-first UX.

## Someday / Maybe

- **Shell completion** — Tab completion for CLI args. Non-trivial with escript. Source: v4 deferred.
- **Model-perspective affinity heuristics** — Simple table mapping perspective types (code → DeepSeek, reasoning → Claude) to preferred models. Source: router research.
- **Agent-to-agent debate rounds** — Multi-round refinement. Research (ICLR 2025) says marginal gains vs high latency. Source: multi-agent architecture research.
- **Result diffing** — Compare outputs across runs to track how analysis changes. Source: v4 deferred.
- **Streaming output** — Stream perspective results to stdout as they complete (NDJSON). Source: harness audit.
- **Pi RPC mode integration** — Use pi's RPC mode instead of print mode for richer subprocess control. Source: pi SDK research.

## Research Prompts

- **Optimal council size** — Is 3-5 perspectives the right default, or does quality plateau earlier/later? Need empirical testing.
- **Synthesis model selection** — Does the synthesis step always need the strongest model, or is a smaller model sufficient? Cost/quality tradeoff to measure.
- **Context-aware file relevance** — For quick mode with --paths, can we use lightweight heuristics (TF-IDF on instruction vs file content) to rank files? Worth prototyping.

## Archived This Session

- ~~Models subcommand~~ — absorbed by router (dynamic model selection)
- ~~Dynamic help text~~ — Go-specific, not relevant to Elixir CLI
- ~~Docstring coverage~~ — Go repo
- ~~Consolidate documentation~~ — Go repo
- ~~Split CliConfig~~ — Go repo
- ~~Enhanced error messages~~ — exit codes carry forward into new CLI design
- ~~Retry tracking in rate limiter~~ — rate limiting handled by pi/OpenRouter
- ~~CI merge-gate skip detection~~ — Go CI
- ~~Dependabot label config~~ — Go repo
