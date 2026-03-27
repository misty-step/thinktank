defmodule Thinktank.CLI do
  @moduledoc """
  CLI entry point for ThinkTank benches.
  """

  alias Thinktank.{Config, Engine}

  @exit_codes %{
    success: 0,
    generic_error: 1,
    input_error: 7
  }

  @option_spec [
    strict: [
      help: :boolean,
      version: :boolean,
      input: :string,
      paths: :keep,
      agents: :string,
      json: :boolean,
      output: :string,
      dry_run: :boolean,
      no_synthesis: :boolean,
      trust_repo_config: :boolean,
      base: :string,
      head: :string,
      repo: :string,
      pr: :integer
    ],
    aliases: [
      h: :help,
      v: :version,
      o: :output
    ]
  ]

  @spec exit_codes() :: %{atom() => non_neg_integer()}
  def exit_codes, do: @exit_codes

  @spec main([String.t()]) :: no_return()
  def main(args) do
    exit_code =
      args
      |> parse_args()
      |> then(fn
        {:needs_stdin, parsed} -> maybe_read_stdin(parsed)
        other -> other
      end)
      |> execute()

    System.halt(exit_code)
  end

  @spec execute({:ok, map()} | {:error, String.t()} | {:help, map()} | {:version, map()}) ::
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
    @exit_codes.input_error
  end

  def execute({:ok, %{action: :benches_list} = command}) do
    with {:ok, config} <-
           Config.load(cwd: command.cwd, trust_repo_config: command.trust_repo_config) do
      Config.list_benches(config)
      |> Enum.each(fn bench ->
        IO.puts("#{bench.id}\t#{bench.description}")
      end)

      @exit_codes.success
    else
      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        @exit_codes.input_error
    end
  end

  def execute({:ok, %{action: :benches_show, bench_id: bench_id} = command}) do
    with {:ok, config} <-
           Config.load(cwd: command.cwd, trust_repo_config: command.trust_repo_config),
         {:ok, bench} <- Config.bench(config, bench_id) do
      rendered =
        %{
          id: bench.id,
          description: bench.description,
          agents: bench.agents,
          synthesizer: bench.synthesizer,
          concurrency: bench.concurrency,
          default_task: bench.default_task
        }
        |> Jason.encode!(pretty: true)

      IO.puts(rendered)
      @exit_codes.success
    else
      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        @exit_codes.input_error
    end
  end

  def execute({:ok, %{action: :benches_validate} = command}) do
    case Config.load(cwd: command.cwd, trust_repo_config: command.trust_repo_config) do
      {:ok, config} ->
        IO.puts("Validated #{length(Config.list_benches(config))} benches")
        @exit_codes.success

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        @exit_codes.input_error
    end
  end

  def execute({:ok, %{action: :run} = command}) do
    if command.dry_run do
      dry_run(command)
    else
      run_bench(command)
    end
  end

  @doc false
  @spec parse_args([String.t()]) ::
          {:ok, map()}
          | {:error, String.t()}
          | {:help, map()}
          | {:version, map()}
          | {:needs_stdin, map()}
  def parse_args(args) do
    {parsed, rest, invalid} = OptionParser.parse(args, @option_spec)

    cond do
      invalid != [] ->
        [{flag, _} | _] = invalid
        {:error, "unknown flag: #{flag}"}

      parsed[:help] ->
        {:help, %{}}

      parsed[:version] ->
        {:version, %{}}

      rest == [] ->
        {:needs_stdin, build_research_command(parsed, nil)}

      true ->
        build_command(rest, parsed)
    end
  end

  @doc false
  @spec dry_run_output(map(), map()) :: String.t()
  def dry_run_output(command, resolved) do
    Jason.encode!(%{
      action: command.action,
      bench: resolved.bench.id,
      description: resolved.bench.description,
      agents: Enum.map(resolved.agents, & &1.name),
      synthesizer: resolved.synthesizer && resolved.synthesizer.name,
      input: command.input,
      output: resolved.output_dir,
      json: command.json
    })
  end

  defp build_command(["run", bench_id | remainder], parsed) do
    with :ok <- validate_review_pr_flags(bench_id, parsed) do
      input_text = resolve_input_text(parsed[:input], remainder)

      if input_text == nil and bench_id != "review/cerberus" do
        {:needs_stdin, build_run_command(bench_id, parsed, nil)}
      else
        {:ok, build_run_command(bench_id, parsed, input_text)}
      end
    end
  end

  defp build_command(["review" | remainder], parsed) do
    with :ok <- validate_review_pr_flags("review/cerberus", parsed) do
      {:ok, build_review_command(parsed, resolve_input_text(parsed[:input], remainder))}
    end
  end

  defp build_command(["research" | remainder], parsed) do
    input_text = resolve_input_text(parsed[:input], remainder)

    if input_text == nil do
      {:needs_stdin, build_research_command(parsed, nil)}
    else
      {:ok, build_research_command(parsed, input_text)}
    end
  end

  defp build_command([group, "list"], parsed) when group in ["benches", "workflows"] do
    {:ok,
     %{
       action: :benches_list,
       cwd: File.cwd!(),
       json: parsed[:json] || false,
       trust_repo_config: parsed[:trust_repo_config] || false
     }}
  end

  defp build_command([group, "show", bench_id], parsed) when group in ["benches", "workflows"] do
    {:ok,
     %{
       action: :benches_show,
       bench_id: bench_id,
       cwd: File.cwd!(),
       json: parsed[:json] || false,
       trust_repo_config: parsed[:trust_repo_config] || false
     }}
  end

  defp build_command([group, "validate"], parsed) when group in ["benches", "workflows"] do
    {:ok,
     %{
       action: :benches_validate,
       cwd: File.cwd!(),
       json: parsed[:json] || false,
       trust_repo_config: parsed[:trust_repo_config] || false
     }}
  end

  defp build_command(rest, parsed) do
    {:ok, build_research_command(parsed, Enum.join(rest, " "))}
  end

  defp build_research_command(parsed, input_text) do
    build_common_command(parsed, "research/default", input_text)
  end

  defp build_review_command(parsed, input_text) do
    command =
      build_common_command(
        parsed,
        "review/cerberus",
        input_text || "Review the current change and report only real issues with evidence."
      )

    put_in(command.input, Map.merge(command.input, review_input(parsed)))
  end

  defp build_run_command(bench_id, parsed, input_text) do
    command = build_common_command(parsed, bench_id, input_text)

    if bench_id == "review/cerberus" do
      put_in(command.input, Map.merge(command.input, review_input(parsed)))
    else
      command
    end
  end

  defp build_common_command(parsed, bench_id, input_text) do
    %{
      action: :run,
      bench_id: bench_id,
      cwd: File.cwd!(),
      json: parsed[:json] || false,
      output: parsed[:output] && Path.expand(parsed[:output]),
      dry_run: parsed[:dry_run] || false,
      trust_repo_config: parsed[:trust_repo_config] || false,
      input: %{
        input_text: input_text,
        paths: normalize_paths(parsed[:paths]),
        agents: parse_agent_list(parsed[:agents]),
        no_synthesis: parsed[:no_synthesis] || false
      }
    }
  end

  defp review_input(parsed) do
    %{}
    |> maybe_put_value(:base, parsed[:base])
    |> maybe_put_value(:head, parsed[:head])
    |> maybe_put_value(:repo, parsed[:repo])
    |> maybe_put_value(:pr, parsed[:pr])
  end

  defp validate_review_pr_flags("review/cerberus", parsed) do
    if parsed[:pr] && !parsed[:repo] do
      {:error, "review/cerberus requires --repo when --pr is provided"}
    else
      :ok
    end
  end

  defp validate_review_pr_flags(_bench_id, _parsed), do: :ok

  defp run_bench(command) do
    agent_config_dir = agent_config_dir(command.cwd)

    case Engine.run(command.bench_id, command.input,
           cwd: command.cwd,
           trust_repo_config: command.trust_repo_config,
           output: command.output,
           agent_config_dir: agent_config_dir
         ) do
      {:ok, result} ->
        emit(command, result.envelope)

        case result.envelope.status do
          "complete" -> @exit_codes.success
          _ -> @exit_codes.generic_error
        end

      {:error, reason, output_dir} ->
        IO.puts(:stderr, "Error: #{format_reason(reason)}")

        if is_binary(output_dir) do
          IO.puts(:stderr, "Artifacts: #{output_dir}")
        end

        @exit_codes.generic_error
    end
  end

  defp dry_run(command) do
    case Engine.resolve(command.bench_id, command.input,
           cwd: command.cwd,
           trust_repo_config: command.trust_repo_config,
           output: command.output
         ) do
      {:ok, resolved} ->
        emit(command, dry_run_output(command, resolved))
        @exit_codes.success

      {:error, reason, _output_dir} ->
        IO.puts(:stderr, "Error: #{format_reason(reason)}")
        @exit_codes.input_error
    end
  end

  defp emit(%{json: true}, payload) when is_binary(payload), do: IO.puts(payload)
  defp emit(%{json: true}, payload), do: IO.puts(Jason.encode!(payload))

  defp emit(_command, payload) when is_binary(payload) do
    IO.puts(payload)
  end

  defp emit(_command, payload) do
    IO.puts("""
    Bench: #{payload.bench}
    Status: #{payload.status}

    Agents:
    #{render_agent_lines(payload.agents)}

    Artifacts:
    #{render_artifact_lines(payload.artifacts)}
    """)
  end

  defp render_agent_lines(agents) do
    Enum.map_join(agents, "\n", fn agent ->
      status = get_in(agent, ["metadata", "status"]) || "unknown"
      "- #{agent["name"]}: #{status}"
    end)
  end

  defp render_artifact_lines(artifacts) do
    Enum.map_join(artifacts, "\n", fn artifact ->
      "- #{artifact["name"]}: #{artifact["file"]}"
    end)
  end

  defp maybe_read_stdin(command) do
    input =
      IO.read(:stdio, :all)
      |> case do
        data when is_binary(data) -> String.trim(data)
        _ -> ""
      end

    if input == "" do
      {:error, "input text is required"}
    else
      {:ok, put_in(command.input.input_text, input)}
    end
  end

  defp resolve_input_text(nil, []), do: nil
  defp resolve_input_text(value, _rest) when is_binary(value), do: value
  defp resolve_input_text(nil, rest), do: Enum.join(rest, " ")

  defp normalize_paths(nil), do: []
  defp normalize_paths(path) when is_binary(path), do: [Path.expand(path)]
  defp normalize_paths(paths) when is_list(paths), do: Enum.map(paths, &Path.expand/1)

  defp parse_agent_list(nil), do: []

  defp parse_agent_list(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_agent_list(_), do: []

  defp maybe_put_value(map, _key, nil), do: map
  defp maybe_put_value(map, key, value), do: Map.put(map, key, value)

  defp agent_config_dir(cwd) do
    if trust_repo_agent_config?() do
      dir = Path.join(cwd, "agent_config")
      if File.dir?(dir), do: dir
    end
  end

  defp trust_repo_agent_config? do
    System.get_env("THINKTANK_TRUST_REPO_AGENT_CONFIG") in ["1", "true", "TRUE", "yes", "YES"]
  end

  defp format_reason(:missing_input_text), do: "input text is required"
  defp format_reason(:no_successful_agents), do: "no agents completed successfully"
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp version, do: Application.spec(:thinktank, :vsn) |> to_string()

  defp usage_text do
    """
    thinktank #{version()}

    Usage:
      thinktank run <bench> --input "..." [options]
      thinktank research "..." [options]
      thinktank review [options]
      thinktank benches list|show|validate

    Options:
      --input TEXT          Task text
      --paths PATH          Point the bench at paths in the workspace (repeatable)
      --agents LIST         Comma-separated agent override for the selected bench
      --json                Output JSON
      --output, -o DIR      Output directory
      --dry-run             Resolve the bench without launching agents
      --no-synthesis        Skip the synthesizer agent
      --trust-repo-config   Trust .thinktank/config.yml in the current repository
      --base REF            Review base ref
      --head REF            Review head ref
      --repo REPO           Review repo owner/name
      --pr N                Review pull request number

    Examples:
      thinktank research "analyze this codebase" --paths ./lib
      thinktank review --base origin/main --head HEAD
      thinktank run review/cerberus --input "Review this branch" --agents trace,guard
      thinktank benches show research/default
    """
  end
end
