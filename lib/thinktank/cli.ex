defmodule Thinktank.CLI do
  @moduledoc """
  CLI entry point for the thinktank escript.

  Parses arguments, validates input, and dispatches to the
  appropriate mode (quick or deep). Agent-friendly: structured
  JSON output, meaningful exit codes, no interactive prompts.
  """

  alias Thinktank.{Dispatch.Quick, Output, Router}

  @default_models [
    "anthropic/claude-sonnet-4",
    "google/gemini-2.5-flash",
    "openai/gpt-4.1",
    "deepseek/deepseek-chat-v3-0324:free"
  ]

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
      perspectives: :integer
    ],
    aliases: [
      h: :help,
      v: :version,
      q: :quick,
      d: :deep,
      o: :output,
      n: :perspectives
    ]
  ]

  def exit_codes, do: @exit_codes

  @doc """
  Escript entry point.
  """
  def main(args) do
    result =
      case parse_args(args) do
        {:needs_stdin, parsed} -> try_stdin(parsed)
        other -> other
      end

    case result do
      {:help, _} ->
        print_usage()
        System.halt(@exit_codes.success)

      {:version, _} ->
        IO.puts("thinktank #{version()}")
        System.halt(@exit_codes.success)

      {:error, message} ->
        IO.puts(:stderr, "Error: #{message}")
        IO.puts(:stderr, "Run 'thinktank --help' for usage.")
        System.halt(@exit_codes.input_error)

      {:ok, opts} ->
        run(opts)
    end
  end

  @doc false
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
        {:ok, build_opts(Enum.join(rest, " "), parsed)}
    end
  end

  @doc """
  Returns the JSON string for dry-run output.
  """
  def dry_run_output(opts) do
    Jason.encode!(%{
      mode: "dry_run",
      instruction: opts.instruction,
      paths: opts.paths,
      perspectives: opts.perspectives,
      dispatch_mode: to_string(opts.mode),
      models: opts.models,
      roles: opts.roles,
      no_synthesis: opts.no_synthesis
    })
  end

  defp try_stdin(parsed) do
    if stdin_piped?() do
      case IO.read(:stdio, :eof) do
        data when is_binary(data) ->
          trimmed = String.trim(data)

          if trimmed == "" do
            {:error, "instruction argument required"}
          else
            {:ok, build_opts(trimmed, parsed)}
          end

        _ ->
          {:error, "instruction argument required"}
      end
    else
      {:error, "instruction argument required"}
    end
  end

  defp build_opts(instruction, parsed) do
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
      perspectives: parsed[:perspectives] || 4
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

    System.halt(@exit_codes.success)
  end

  defp run(%{mode: :quick} = opts) do
    case resolve_perspectives(opts) do
      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(@exit_codes.input_error)

      {:ok, perspectives} ->
        output_dir = opts.output || generate_output_dir()
        roles = Enum.map(perspectives, & &1.role)
        Output.init_run(output_dir, roles)

        results = Quick.dispatch(perspectives, opts.instruction, paths: opts.paths)

        for {:ok, role, text} <- results do
          Output.write_perspective(output_dir, role, text)
        end

        Output.complete_run(output_dir)

        if opts.json do
          IO.puts(Jason.encode!(Output.result_envelope(output_dir)))
        else
          IO.puts("Output: #{output_dir}")
        end

        System.halt(@exit_codes.success)
    end
  end

  defp run(_opts) do
    IO.puts(:stderr, "Error: deep mode not yet implemented")
    System.halt(@exit_codes.generic_error)
  end

  defp resolve_perspectives(opts) do
    models = if opts.models != [], do: opts.models, else: @default_models

    if opts.roles != [] do
      {:ok, Router.manual_perspectives(opts.roles, models)}
    else
      Router.generate_perspectives(opts.instruction, opts.paths,
        available_models: models,
        perspectives: opts.perspectives
      )
    end
  end

  defp generate_output_dir do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d-%H%M%S")
    Path.join(System.tmp_dir!(), "thinktank-#{timestamp}")
  end

  defp print_usage do
    IO.puts("""
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
      --json           Output structured JSON to stdout
      --output, -o     Output directory (default: auto-generated)
      --models LIST    Comma-separated model list (overrides router)
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
      thinktank "suggest project names" --quick
      thinktank "audit for security issues" --paths ./src --perspectives 5
      echo "compare approaches" | thinktank --models claude-opus-4-6,gpt-5.4 --quick
    """)
  end

  defp parse_csv(nil), do: []
  defp parse_csv(str), do: str |> String.split(",") |> Enum.map(&String.trim/1)

  defp version, do: Application.spec(:thinktank, :vsn) |> to_string()

  defp stdin_piped? do
    # :io.columns/1 returns {:error, :enotsup} when stdin is not a terminal
    match?({:error, _}, :io.columns(:standard_io))
  rescue
    _ -> false
  end
end
