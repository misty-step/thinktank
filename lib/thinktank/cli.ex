defmodule Thinktank.CLI do
  @moduledoc """
  CLI entry point for ThinkTank benches.
  """

  alias Thinktank.{AgentSpec, BenchSpec, Config, Engine, Error}
  alias Thinktank.Review.Eval

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
      bench: :string,
      json: :boolean,
      full: :boolean,
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
        {:needs_stdin, parsed} -> read_stdin(parsed)
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
    case load_config(command) do
      {:ok, config} ->
        benches = Config.list_benches(config)

        if command.json do
          benches
          |> Enum.map(fn bench ->
            %{
              id: bench.id,
              description: bench.description,
              kind: Atom.to_string(bench.kind),
              agent_count: length(bench.agents)
            }
          end)
          |> Jason.encode!()
          |> IO.puts()
        else
          Enum.each(benches, fn bench ->
            IO.puts("#{bench.id}\t#{bench.description}")
          end)
        end

        @exit_codes.success

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        @exit_codes.input_error
    end
  end

  def execute({:ok, %{action: :benches_show, bench_id: bench_id} = command}) do
    with {:ok, config} <- load_config(command),
         {:ok, bench} <- Config.bench(config, bench_id) do
      agents_payload =
        if command.full do
          Enum.map(bench.agents, fn name ->
            case Map.get(config.agents, name) do
              nil ->
                %{name: name, error: "unknown agent"}

              %AgentSpec{} = agent ->
                %{
                  name: agent.name,
                  model: agent.model,
                  provider: agent.provider,
                  tools: agent.tools,
                  system_prompt: agent.system_prompt,
                  thinking_level: agent.thinking_level,
                  timeout_ms: agent.timeout_ms
                }
            end
          end)
        else
          bench.agents
        end

      rendered =
        %{
          id: bench.id,
          description: bench.description,
          kind: bench.kind,
          agents: agents_payload,
          planner: bench.planner,
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
    case load_config(command) do
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

  def execute({:ok, %{action: :review_eval} = command}) do
    eval_opts =
      [bench_id: command.bench_id, output: command.output]
      |> maybe_put_opt(:trust_repo_config, command.trust_repo_config)

    case Eval.run(command.target, eval_opts) do
      {:ok, result} ->
        emit_eval(command, result)

        case result.status do
          "complete" -> @exit_codes.success
          _ -> @exit_codes.generic_error
        end

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{format_reason(reason)}")
        @exit_codes.input_error
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
        build_fixed_bench_command(
          "research/default",
          parsed,
          resolve_input_text(parsed[:input], [])
        )

      true ->
        build_command(rest, parsed)
    end
  end

  @doc false
  @spec dry_run_output(map(), map()) :: String.t()
  def dry_run_output(command, resolved) do
    payload = %{
      action: command.action,
      bench: resolved.bench.id,
      description: resolved.bench.description,
      agents: Enum.map(resolved.agents, & &1.name),
      planner: resolved.planner && resolved.planner.name,
      synthesizer: resolved.synthesizer && resolved.synthesizer.name,
      input: command.input,
      output: resolved.output_dir,
      json: command.json
    }

    if command.json do
      Jason.encode!(payload)
    else
      """
      Bench: #{payload.bench}
      Description: #{payload.description}
      Agents: #{Enum.join(payload.agents, ", ")}
      Planner: #{payload.planner || "none"}
      Synthesizer: #{payload.synthesizer || "none"}
      Input: #{payload.input.input_text}
      Output: #{payload.output}
      """
      |> String.trim()
    end
  end

  defp build_command(["run", bench_id | remainder], parsed) do
    with {:ok, config, bench} <- resolve_bench(bench_id, parsed),
         :ok <- validate_review_pr_flags(bench, parsed) do
      input_text = resolve_input_text(parsed[:input], remainder)

      if input_text == nil and needs_stdin?(bench) do
        {:needs_stdin, build_run_command(bench, parsed, nil, config)}
      else
        {:ok, build_run_command(bench, parsed, input_text, config)}
      end
    end
  end

  defp build_command(["review", "eval", target], parsed) do
    {:ok,
     %{
       action: :review_eval,
       target: Path.expand(target),
       bench_id: parsed[:bench],
       cwd: File.cwd!(),
       json: parsed[:json] || false,
       output: parsed[:output] && Path.expand(parsed[:output]),
       trust_repo_config: parsed[:trust_repo_config]
     }}
  end

  defp build_command(["review", "eval"], _parsed), do: {:error, "review eval requires a path"}

  defp build_command(["review" | remainder], parsed) do
    with {:ok, config, bench} <- resolve_bench("review/default", parsed),
         :ok <- validate_review_pr_flags(bench, parsed) do
      input_text = resolve_input_text(parsed[:input], remainder)

      if input_text == nil and needs_stdin?(bench) do
        {:needs_stdin, build_review_command(bench, parsed, nil, config)}
      else
        {:ok, build_review_command(bench, parsed, input_text, config)}
      end
    end
  end

  defp build_command(["research" | remainder], parsed) do
    input_text = resolve_input_text(parsed[:input], remainder)
    build_fixed_bench_command("research/default", parsed, input_text)
  end

  defp build_command(["run"], _parsed), do: {:error, "run requires a bench id"}

  defp build_command([group, "list"], parsed) when group in ["benches", "workflows"] do
    {:ok,
     %{
       action: :benches_list,
       cwd: File.cwd!(),
       json: parsed[:json] || false,
       trust_repo_config: parsed[:trust_repo_config]
     }}
  end

  defp build_command([group, "show", bench_id], parsed) when group in ["benches", "workflows"] do
    {:ok,
     %{
       action: :benches_show,
       bench_id: bench_id,
       cwd: File.cwd!(),
       json: parsed[:json] || false,
       full: parsed[:full] || false,
       trust_repo_config: parsed[:trust_repo_config]
     }}
  end

  defp build_command([group, "validate"], parsed) when group in ["benches", "workflows"] do
    {:ok,
     %{
       action: :benches_validate,
       cwd: File.cwd!(),
       json: parsed[:json] || false,
       trust_repo_config: parsed[:trust_repo_config]
     }}
  end

  defp build_command([group | _rest], _parsed) when group in ["benches", "workflows"] do
    {:error, "#{group} expects list, show <bench>, or validate"}
  end

  defp build_command(rest, parsed) do
    build_fixed_bench_command("research/default", parsed, Enum.join(rest, " "))
  end

  defp build_fixed_bench_command(bench_id, parsed, input_text) do
    with {:ok, config, bench} <- resolve_bench(bench_id, parsed),
         :ok <- validate_review_pr_flags(bench, parsed) do
      if input_text == nil and needs_stdin?(bench) do
        {:needs_stdin, build_run_command(bench, parsed, nil, config)}
      else
        {:ok, build_run_command(bench, parsed, input_text, config)}
      end
    end
  end

  defp build_review_command(bench, parsed, input_text, config) do
    build_run_command(bench, parsed, input_text, config)
  end

  defp build_run_command(%BenchSpec{} = bench, parsed, input_text, config) do
    command = build_common_command(parsed, bench.id, input_text || bench.default_task)
    command = Map.put(command, :config, config)

    if review_bench?(bench) do
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
      trust_repo_config: parsed[:trust_repo_config],
      input: %{
        input_text: input_text,
        paths: normalize_paths(Keyword.get_values(parsed, :paths)),
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

  defp validate_review_pr_flags(%BenchSpec{id: bench_id} = bench, parsed) do
    parsed = if is_map(parsed), do: parsed, else: Map.new(parsed)

    cond do
      !review_bench?(bench) ->
        :ok

      parsed[:pr] && !parsed[:repo] ->
        {:error, "#{bench_id} requires --repo when --pr is provided"}

      true ->
        :ok
    end
  end

  defp run_bench(command) do
    agent_config_dir = agent_config_dir(command.cwd)

    run_opts =
      [
        cwd: command.cwd,
        output: command.output,
        agent_config_dir: agent_config_dir
      ]
      |> maybe_put_opt(:trust_repo_config, command.trust_repo_config)
      |> maybe_put_opt(:config, Map.get(command, :config))

    case Engine.run(command.bench_id, command.input, run_opts) do
      {:ok, result} ->
        emit(command, result.envelope)

        case result.envelope.status do
          "complete" -> @exit_codes.success
          _ -> @exit_codes.generic_error
        end

      {:error, reason, output_dir} ->
        error = if is_struct(reason, Error), do: reason, else: Error.from_reason(reason)
        emit_error(command, error, output_dir)
        @exit_codes.generic_error
    end
  end

  defp dry_run(command) do
    resolve_opts =
      [
        cwd: command.cwd,
        output: command.output
      ]
      |> maybe_put_opt(:trust_repo_config, command.trust_repo_config)
      |> maybe_put_opt(:config, Map.get(command, :config))

    case Engine.resolve(command.bench_id, command.input, resolve_opts) do
      {:ok, resolved} ->
        emit(command, dry_run_output(command, resolved))
        @exit_codes.success

      {:error, reason, _output_dir} ->
        error = if is_struct(reason, Error), do: reason, else: Error.from_reason(reason)
        emit_error(command, error, nil)
        @exit_codes.input_error
    end
  end

  defp emit_error(%{json: true}, %Error{} = error, output_dir) do
    payload = %{error: error, output_dir: output_dir}
    IO.puts(:stderr, Jason.encode!(payload))
  end

  defp emit_error(_command, %Error{} = error, output_dir) do
    IO.puts(:stderr, "Error: #{error.message}")

    if is_binary(output_dir) do
      IO.puts(:stderr, "Artifacts: #{output_dir}")
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

  defp emit_eval(%{json: true}, payload), do: IO.puts(Jason.encode!(payload))

  defp emit_eval(_command, payload) do
    IO.puts("""
    Review eval: #{payload.target}
    Status: #{payload.status}
    Output: #{payload.output_dir}

    Cases:
    #{render_eval_case_lines(payload.cases)}
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

  defp render_eval_case_lines(cases) do
    Enum.map_join(cases, "\n", fn case_result ->
      "- #{case_result.case_id}: #{case_result.status} (#{case_result.bench})"
    end)
  end

  defp resolve_bench(bench_id, parsed) do
    with {:ok, config} <-
           load_config(%{cwd: File.cwd!(), trust_repo_config: parsed[:trust_repo_config]}) do
      case Config.bench(config, bench_id) do
        {:ok, bench} -> {:ok, config, bench}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp load_config(command) do
    [cwd: command.cwd]
    |> maybe_put_opt(:trust_repo_config, Map.get(command, :trust_repo_config))
    |> Config.load()
  end

  defp needs_stdin?(%BenchSpec{default_task: default_task}), do: is_nil(default_task)

  defp review_bench?(%BenchSpec{kind: :review}), do: true
  defp review_bench?(_), do: false

  @doc false
  @spec read_stdin(map(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def read_stdin(command, opts \\ []) do
    if stdin_piped?(opts) do
      input =
        opts
        |> Keyword.get(:reader, &IO.read/2)
        |> then(& &1.(:stdio, :all))
        |> case do
          data when is_binary(data) -> String.trim(data)
          _ -> ""
        end

      if input == "" do
        {:error, "input text is required"}
      else
        {:ok, put_in(command.input.input_text, input)}
      end
    else
      {:error, "input text is required"}
    end
  end

  defp resolve_input_text(nil, []), do: nil
  defp resolve_input_text(value, _rest) when is_binary(value), do: value
  defp resolve_input_text(nil, rest), do: Enum.join(rest, " ")

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
  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp agent_config_dir(cwd) do
    if Config.trust_repo_agent_config?() do
      dir = Path.join(cwd, "agent_config")
      if File.dir?(dir), do: dir
    end
  end

  defp stdin_piped?(opts) do
    case Keyword.get(opts, :stdin_piped?, &stdin_piped?/0) do
      fun when is_function(fun, 0) -> fun.()
      value -> value
    end
  end

  defp stdin_piped? do
    match?({:error, _}, :io.columns(:standard_io))
  rescue
    _ -> false
  end

  defp format_reason(%Error{message: message}), do: message
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
      thinktank review eval <contract-or-dir> [--bench <bench>]
      thinktank benches list|show|validate

    Options:
      --input TEXT          Task text
      --paths PATH          Point the bench at paths in the workspace (repeatable)
      --agents LIST         Comma-separated agent override for the selected bench
      --json                Output JSON
      --full                Include full agent specs in benches show
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
      thinktank review eval ./tmp/review-run --bench review/default
      thinktank run review/default --input "Review this branch" --agents trace,guard
      thinktank benches show research/default
    """
  end
end
