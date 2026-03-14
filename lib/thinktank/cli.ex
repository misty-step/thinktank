defmodule Thinktank.CLI do
  @moduledoc """
  CLI entry point for the thinktank escript.

  Parses arguments, validates input, and dispatches to the
  appropriate mode (quick or deep).
  """

  @exit_success 0
  @exit_input_error 6

  @doc """
  Escript entry point.
  """
  def main(args) do
    case parse_args(args) do
      {:help, _} ->
        print_usage()
        System.halt(@exit_success)

      {:version, _} ->
        IO.puts("thinktank #{version()}")
        System.halt(@exit_success)

      {:error, message} ->
        IO.puts(:stderr, "Error: #{message}")
        IO.puts(:stderr, "Run 'thinktank --help' for usage.")
        System.halt(@exit_input_error)

      {:ok, opts} ->
        run(opts)
    end
  end

  @doc false
  def parse_args(args) do
    {parsed, rest, invalid} =
      OptionParser.parse(args,
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
      )

    cond do
      invalid != [] ->
        [{flag, _} | _] = invalid
        {:error, "unknown flag: #{flag}"}

      parsed[:help] ->
        {:help, parsed}

      parsed[:version] ->
        {:version, parsed}

      rest == [] ->
        {:error, "instruction argument required"}

      true ->
        instruction = Enum.join(rest, " ")

        opts = %{
          instruction: instruction,
          paths: Keyword.get_values(parsed, :paths),
          mode: if(parsed[:quick], do: :quick, else: :deep),
          json: parsed[:json] || false,
          output: parsed[:output],
          models: parse_csv(parsed[:models]),
          roles: parse_csv(parsed[:roles]),
          dry_run: parsed[:dry_run] || false,
          no_synthesis: parsed[:no_synthesis] || false,
          perspectives: parsed[:perspectives] || 4
        }

        {:ok, opts}
    end
  end

  defp run(%{dry_run: true} = opts) do
    if opts.json do
      IO.puts(Jason.encode!(%{mode: "dry_run", instruction: opts.instruction, paths: opts.paths}))
    else
      IO.puts("Dry run: would dispatch #{opts.perspectives} perspectives in #{opts.mode} mode")
      IO.puts("Instruction: #{opts.instruction}")

      if opts.paths != [] do
        IO.puts("Paths: #{Enum.join(opts.paths, ", ")}")
      end
    end

    System.halt(@exit_success)
  end

  defp run(_opts) do
    IO.puts(:stderr, "Error: not yet implemented")
    System.halt(1)
  end

  defp print_usage do
    IO.puts("""
    thinktank — multi-perspective AI research tool

    USAGE
      thinktank <instruction> [options]

    ARGUMENTS
      <instruction>    Research question or task (required)

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

    EXAMPLES
      thinktank "review this auth flow" --paths ./src/auth
      thinktank "suggest project names" --quick
      thinktank "audit for security issues" --paths ./src --perspectives 5
      thinktank "compare approaches" --models claude-opus-4-6,gpt-5.4 --quick
    """)
  end

  defp parse_csv(nil), do: []
  defp parse_csv(str), do: str |> String.split(",") |> Enum.map(&String.trim/1)

  defp version, do: Application.spec(:thinktank, :vsn) |> to_string()
end
