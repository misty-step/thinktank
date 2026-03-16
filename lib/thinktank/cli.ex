defmodule Thinktank.CLI do
  @moduledoc """
  CLI entry point for the thinktank escript.

  Parses arguments, validates input, and dispatches to the
  appropriate mode (quick or deep). Agent-friendly: structured
  JSON output, meaningful exit codes, no interactive prompts.
  """

  alias Thinktank.{Dispatch.Deep, Dispatch.Quick, Models, Output, Router, Synthesis}

  @exit_codes %{
    success: 0,
    generic_error: 1,
    auth_error: 2,
    rate_limit: 3,
    invalid_request: 4,
    server_error: 5,
    network_error: 6,
    input_error: 7,
    content_filtered: 8,
    insufficient_credits: 9,
    cancelled: 10
  }

  @option_spec [
    strict: [
      help: :boolean,
      version: :boolean,
      paths: :keep,
      quick: :boolean,
      deep: :boolean,
      json: :boolean,
      output: :string,
      models: :string,
      roles: :string,
      dry_run: :boolean,
      no_synthesis: :boolean,
      perspectives: :integer,
      tier: :string
    ],
    aliases: [
      h: :help,
      v: :version,
      q: :quick,
      d: :deep,
      o: :output,
      n: :perspectives,
      t: :tier
    ]
  ]

  @spec exit_codes() :: %{atom() => non_neg_integer()}
  def exit_codes, do: @exit_codes

  @doc """
  Escript entry point. Parses args, executes, and halts.
  """
  @spec main([String.t()]) :: no_return()
  def main(args) do
    exit_code =
      args
      |> parse_args()
      |> then(fn
        {:needs_stdin, parsed} -> try_stdin(parsed)
        other -> other
      end)
      |> execute()

    System.halt(exit_code)
  end

  @doc """
  Execute a parsed command. Returns an exit code without halting.

  Testable core — `main/1` is the only function that calls `System.halt/1`.
  """
  @spec execute({:ok, map()} | {:error, String.t()} | {:help, keyword()} | {:version, keyword()}) ::
          non_neg_integer()
  def execute({:help, _}) do
    IO.puts(usage_text())
    @exit_codes.success
  end

  def execute({:version, _}) do
    IO.puts("thinktank #{version()}")
    @exit_codes.success
  end

  def execute({:error, message}) do
    IO.puts(:stderr, "Error: #{message}")
    IO.puts(:stderr, "Run 'thinktank --help' for usage.")
    @exit_codes.input_error
  end

  def execute({:ok, opts}) do
    run(opts)
  end

  @doc false
  @spec parse_args([String.t()]) ::
          {:ok, map()}
          | {:error, String.t()}
          | {:help, keyword()}
          | {:version, keyword()}
          | {:needs_stdin, keyword()}
  def parse_args(args) do
    {parsed, rest, invalid} = OptionParser.parse(args, @option_spec)

    cond do
      invalid != [] ->
        [{flag, _} | _] = invalid
        {:error, "unknown flag: #{flag}"}

      parsed[:help] ->
        {:help, parsed}

      parsed[:version] ->
        {:version, parsed}

      rest == [] ->
        {:needs_stdin, parsed}

      true ->
        case parse_tier(parsed[:tier]) do
          {:ok, tier} -> {:ok, build_opts(Enum.join(rest, " "), parsed, tier)}
          {:error, _} = err -> err
        end
    end
  end

  @doc """
  Returns the JSON string for dry-run output.
  """
  @spec dry_run_output(map()) :: String.t()
  def dry_run_output(opts) do
    Jason.encode!(%{
      mode: "dry_run",
      instruction: opts.instruction,
      paths: opts.paths,
      perspectives: opts.perspectives,
      dispatch_mode: to_string(opts.mode),
      tier: to_string(opts.tier),
      models: opts.models,
      roles: opts.roles,
      no_synthesis: opts.no_synthesis
    })
  end

  defp try_stdin(parsed) do
    with true <- stdin_piped?(),
         data when is_binary(data) <- IO.read(:stdio, :eof),
         trimmed = String.trim(data),
         false <- trimmed == "",
         {:ok, tier} <- parse_tier(parsed[:tier]) do
      {:ok, build_opts(trimmed, parsed, tier)}
    else
      {:error, _} = err -> err
      _ -> {:error, "instruction argument required"}
    end
  end

  defp build_opts(instruction, parsed, tier) do
    %{
      instruction: instruction,
      paths: parsed |> Keyword.get_values(:paths) |> Enum.map(&Path.expand/1),
      mode: if(parsed[:quick], do: :quick, else: :deep),
      json: parsed[:json] || false,
      output: if(parsed[:output], do: Path.expand(parsed[:output])),
      models: parse_csv(parsed[:models]),
      roles: parse_csv(parsed[:roles]),
      dry_run: parsed[:dry_run] || false,
      no_synthesis: parsed[:no_synthesis] || false,
      perspectives: parsed[:perspectives] || 4,
      tier: tier
    }
  end

  defp run(%{dry_run: true} = opts) do
    if opts.json do
      IO.puts(dry_run_output(opts))
    else
      IO.puts("Dry run: would dispatch #{opts.perspectives} perspectives in #{opts.mode} mode")
      IO.puts("Instruction: #{opts.instruction}")

      if opts.paths != [] do
        IO.puts("Paths: #{Enum.join(opts.paths, ", ")}")
      end
    end

    @exit_codes.success
  end

  defp run(%{mode: :quick} = opts) do
    dispatch_and_finalize(opts, fn perspectives, instruction, paths ->
      Quick.dispatch(perspectives, instruction, paths: paths)
    end)
  end

  defp run(%{mode: :deep} = opts) do
    dispatch_and_finalize(opts, fn perspectives, instruction, paths ->
      deep_opts = [paths: paths, agent_config_dir: agent_config_dir()]
      Deep.dispatch(perspectives, instruction, deep_opts)
    end)
  end

  defp dispatch_and_finalize(opts, dispatch_fn) do
    case resolve_perspectives(opts) do
      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        @exit_codes.input_error

      {:ok, perspectives, router_usage} ->
        output_dir = opts.output || generate_output_dir()
        Output.init_run(output_dir, perspectives, router_usage)

        results = dispatch_fn.(perspectives, opts.instruction, opts.paths)
        successes = for {:ok, role, text, usage} <- results, do: {role, text, usage}

        for {role, text, usage} <- successes do
          Output.write_perspective(output_dir, role, text, usage)
        end

        synthesis_successes = for {role, text, _usage} <- successes, do: {role, text}
        maybe_synthesize(opts, synthesis_successes, output_dir)
        Output.complete_run(output_dir)
        emit_result(opts, output_dir)
        exit_code_for_results(successes)
    end
  end

  defp maybe_synthesize(opts, successes, output_dir) do
    if opts.no_synthesis or successes == [],
      do: :noop,
      else: do_synthesize(opts, successes, output_dir)
  end

  defp do_synthesize(opts, successes, output_dir) do
    case Synthesis.synthesize(successes, opts.instruction, tier: opts.tier) do
      {:ok, text, usage} -> Output.write_synthesis(output_dir, text, usage)
      {:error, _} -> IO.puts(:stderr, "Warning: synthesis failed after retries")
    end
  end

  defp emit_result(opts, output_dir) do
    if opts.json do
      IO.puts(Jason.encode!(Output.result_envelope(output_dir)))
    else
      IO.puts("Output: #{output_dir}")
    end
  end

  defp exit_code_for_results([]) do
    IO.puts(:stderr, "Error: all perspective dispatches failed")
    @exit_codes.generic_error
  end

  defp exit_code_for_results(_successes), do: @exit_codes.success

  defp resolve_perspectives(opts) do
    models = if opts.models != [], do: opts.models, else: Models.models_for_tier(opts.tier)

    if opts.roles != [] do
      {:ok, Router.manual_perspectives(opts.roles, models), nil}
    else
      Router.generate_perspectives(opts.instruction, opts.paths,
        available_models: models,
        perspectives: opts.perspectives,
        tier: opts.tier
      )
    end
  end

  @doc """
  Generate a unique timestamped output directory path.
  """
  @spec generate_output_dir() :: String.t()
  def generate_output_dir do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d-%H%M%S")
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    Path.join(System.tmp_dir!(), "thinktank-#{timestamp}-#{suffix}")
  end

  @doc """
  Returns the usage help text.
  """
  @spec usage_text() :: String.t()
  def usage_text do
    """
    thinktank — multi-perspective AI research tool

    USAGE
      thinktank <instruction> [options]
      echo "instruction" | thinktank [options]

    ARGUMENTS
      <instruction>    Research question or task (required, or pipe via stdin)

    OPTIONS
      --paths PATH     Files/dirs for agent context (repeatable)
      --quick, -q      Quick mode: parallel API calls, no tools
      --deep, -d       Deep mode: Pi agent subprocesses (default)
      --tier, -t TIER  Model tier: cheap, standard, premium (default: standard)
      --json           Output structured JSON to stdout
      --output, -o     Output directory (default: auto-generated)
      --models LIST    Comma-separated model list (overrides tier)
      --roles LIST     Comma-separated roles (bypasses router)
      --perspectives N Number of perspectives (default: 4)
      --dry-run        Show plan without executing
      --no-synthesis   Skip synthesis step
      --help, -h       Show this help
      --version, -v    Show version

    EXIT CODES
      0   Success
      1   Generic error
      2   Authentication error
      3   Rate limit exceeded
      4   Invalid request
      5   Server error
      6   Network error
      7   Input error
      8   Content filtered
      9   Insufficient credits
      10  Cancelled

    EXAMPLES
      thinktank "review this auth flow" --paths ./src/auth
      thinktank "suggest project names" --quick --tier cheap
      thinktank "audit for security issues" --tier premium --perspectives 5
      echo "compare approaches" | thinktank --quick
    """
  end

  defp parse_tier(nil), do: {:ok, :standard}
  defp parse_tier("cheap"), do: {:ok, :cheap}
  defp parse_tier("standard"), do: {:ok, :standard}
  defp parse_tier("premium"), do: {:ok, :premium}

  defp parse_tier(other),
    do: {:error, "invalid tier: #{other} (must be cheap, standard, or premium)"}

  defp parse_csv(nil), do: []
  defp parse_csv(str), do: str |> String.split(",") |> Enum.map(&String.trim/1)

  defp version, do: Application.spec(:thinktank, :vsn) |> to_string()

  @doc """
  Resolve agent config directory for deep mode Pi agents.

  Checks `THINKTANK_AGENT_CONFIG` env var first, then `CWD/agent_config`.
  Returns `nil` when no config directory is found.
  """
  @spec agent_config_dir() :: String.t() | nil
  def agent_config_dir do
    case System.get_env("THINKTANK_AGENT_CONFIG") do
      nil ->
        dir = Path.join(File.cwd!(), "agent_config")
        if File.dir?(dir), do: dir

      dir ->
        dir
    end
  end

  defp stdin_piped? do
    # :io.columns/1 returns {:error, :enotsup} when stdin is not a terminal
    match?({:error, _}, :io.columns(:standard_io))
  rescue
    _ -> false
  end
end
