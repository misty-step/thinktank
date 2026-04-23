defmodule Thinktank.CLI do
  @moduledoc """
  CLI entry point for ThinkTank benches.
  """

  alias Thinktank.CLI.Parser
  alias Thinktank.CLI.Render
  alias Thinktank.Config
  alias Thinktank.Engine
  alias Thinktank.Error
  alias Thinktank.ProgressReporter
  alias Thinktank.Review.Eval
  alias Thinktank.RunInspector

  @exit_codes %{
    success: 0,
    generic_error: 1,
    input_error: 7
  }

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
    IO.puts(Render.usage_text(version()))
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
        config
        |> Config.list_benches()
        |> emit_benches_list(command)

        @exit_codes.success

      {:error, reason} ->
        emit_error(command, normalize_error(reason), nil)
        @exit_codes.input_error
    end
  end

  def execute({:ok, %{action: :benches_show, bench_id: bench_id} = command}) do
    with {:ok, config} <- load_config(command),
         {:ok, bench} <- Config.bench(config, bench_id),
         {:ok, agents_payload} <- Render.resolve_agents_payload(bench, config, command.full) do
      payload = %{
        id: bench.id,
        description: bench.description,
        kind: bench.kind,
        agents: agents_payload,
        planner: bench.planner,
        synthesizer: bench.synthesizer,
        concurrency: bench.concurrency,
        default_task: bench.default_task
      }

      emit_benches_show(payload, command)
      @exit_codes.success
    else
      {:error, reason} ->
        emit_error(command, normalize_error(reason), nil)
        @exit_codes.input_error
    end
  end

  def execute({:ok, %{action: :benches_validate} = command}) do
    case load_config(command) do
      {:ok, config} ->
        config
        |> Config.list_benches()
        |> emit_benches_validate(command)

        @exit_codes.success

      {:error, reason} ->
        emit_error(command, normalize_error(reason), nil)
        @exit_codes.input_error
    end
  end

  def execute({:ok, %{action: :runs_list} = command}) do
    case command |> runs_list_opts() |> RunInspector.list() do
      {:ok, runs} ->
        emit_runs_list(runs, command)
        @exit_codes.success

      {:error, reason} ->
        emit_runs_error(command, reason)
    end
  end

  def execute({:ok, %{action: :runs_show, target: target} = command}) do
    case RunInspector.show(target) do
      {:ok, run} ->
        emit_run(run, command)
        @exit_codes.success

      {:error, reason} ->
        emit_runs_error(command, reason)
    end
  end

  def execute({:ok, %{action: :runs_wait, target: target} = command}) do
    case RunInspector.wait(target, runs_wait_opts(command)) do
      {:ok, run} ->
        emit_run(run, command)

        case run.status do
          "complete" -> @exit_codes.success
          _ -> @exit_codes.generic_error
        end

      {:error, reason} ->
        emit_runs_error(command, reason)
    end
  end

  def execute({:ok, %{action: :run} = command}) do
    if command.dry_run, do: dry_run(command), else: run_bench(command)
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
        emit_error(command, normalize_error(reason), nil)
        @exit_codes.input_error
    end
  end

  @doc false
  def parse_args(args), do: Parser.parse_args(args)

  @doc false
  @spec dry_run_output(map(), map()) :: String.t()
  def dry_run_output(command, resolved), do: Render.dry_run_output(command, resolved)

  @doc false
  @spec read_stdin(map(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def read_stdin(command, opts \\ []), do: Parser.read_stdin(command, opts)

  @doc false
  def render_run_payload(payload), do: Render.render_run_payload(payload)

  defp run_bench(command) do
    agent_config_dir = agent_config_dir(command.cwd)

    base_opts =
      [cwd: command.cwd, output: command.output]
      |> maybe_put_opt(:trust_repo_config, command.trust_repo_config)
      |> maybe_put_opt(:config, Map.get(command, :config))

    run_opts = Keyword.put(base_opts, :agent_config_dir, agent_config_dir)

    case Engine.resolve(command.bench_id, command.input, base_opts) do
      {:ok, resolved} ->
        progress = maybe_start_progress(command, resolved)

        result =
          try do
            run_opts
            |> maybe_put_opt(:progress_callback, progress && ProgressReporter.callback(progress))
            |> then(&Engine.run_resolved(resolved, &1))
          after
            ProgressReporter.stop(progress)
          end

        case result do
          {:ok, run_result} ->
            emit(command, Render.contract_payload(run_result.envelope))

            case run_result.envelope.status do
              "complete" -> @exit_codes.success
              _ -> @exit_codes.generic_error
            end

          {:error, reason, output_dir} ->
            emit_error(command, normalize_error(reason), output_dir)
            @exit_codes.generic_error
        end

      {:error, reason, output_dir} ->
        emit_error(command, normalize_error(reason), output_dir)
        @exit_codes.generic_error
    end
  end

  defp dry_run(command) do
    resolve_opts =
      [cwd: command.cwd, output: command.output]
      |> maybe_put_opt(:trust_repo_config, command.trust_repo_config)
      |> maybe_put_opt(:config, Map.get(command, :config))

    case Engine.resolve(command.bench_id, command.input, resolve_opts) do
      {:ok, resolved} ->
        emit(command, Render.dry_run_output(command, resolved))
        @exit_codes.success

      {:error, reason, output_dir} ->
        emit_error(command, normalize_error(reason), output_dir)
        @exit_codes.input_error
    end
  end

  defp maybe_start_progress(%{json: true}, resolved) do
    ProgressReporter.start(
      bench: resolved.bench.id,
      output_dir: resolved.output_dir,
      emit: &emit_progress_event/1
    )
  end

  defp maybe_start_progress(_command, _resolved), do: nil

  defp emit_progress_event(payload) do
    IO.puts(:stderr, Jason.encode!(payload))
  end

  defp emit_benches_list(benches, %{json: true}) do
    benches
    |> Render.benches_list_json()
    |> IO.puts()
  end

  defp emit_benches_list(benches, _command) do
    benches
    |> Render.benches_list_text()
    |> IO.puts()
  end

  defp emit_benches_validate(benches, %{json: true}) do
    benches
    |> Render.benches_validate_json()
    |> IO.puts()
  end

  defp emit_benches_validate(benches, _command) do
    benches
    |> Render.benches_validate_text()
    |> IO.puts()
  end

  defp emit_benches_show(payload, %{json: true}) do
    payload
    |> Render.benches_show_json()
    |> IO.puts()
  end

  defp emit_benches_show(payload, _command) do
    payload
    |> Render.benches_show_text()
    |> IO.puts()
  end

  defp runs_wait_opts(command) do
    case Map.get(command, :timeout_ms) do
      nil -> []
      timeout_ms -> [timeout_ms: timeout_ms]
    end
  end

  defp runs_list_opts(command) do
    command
    |> Map.take([:limit])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp emit_runs_error(command, reason) do
    error = normalize_error(reason)
    emit_error(command, error, runs_error_output_dir(error))
    runs_error_exit_code(error)
  end

  defp runs_error_output_dir(%Error{details: %{output_dir: output_dir}})
       when is_binary(output_dir),
       do: output_dir

  defp runs_error_output_dir(_error), do: nil

  defp runs_error_exit_code(%Error{} = error) do
    if RunInspector.input_error?(error),
      do: @exit_codes.input_error,
      else: @exit_codes.generic_error
  end

  defp emit_runs_list(runs, %{json: true}) do
    runs
    |> Render.runs_list_json()
    |> IO.puts()
  end

  defp emit_runs_list(runs, _command) do
    runs
    |> Render.runs_list_text()
    |> IO.puts()
  end

  defp emit_run(run, %{json: true}) do
    run
    |> Render.run_json()
    |> IO.puts()
  end

  defp emit_run(run, _command) do
    run
    |> Render.run_text()
    |> IO.puts()
  end

  defp normalize_error(%Error{} = error), do: error
  defp normalize_error(reason), do: Error.from_reason(reason)

  defp emit_error(%{json: true}, %Error{} = error, output_dir) do
    IO.puts(:stderr, Jason.encode!(Render.error_payload(error, output_dir)))
  end

  defp emit_error(_command, %Error{} = error, output_dir) do
    error
    |> Render.error_lines(output_dir)
    |> Enum.each(&IO.puts(:stderr, &1))
  end

  defp emit(%{json: true}, payload) when is_binary(payload), do: IO.puts(payload)
  defp emit(%{json: true}, payload), do: IO.puts(Jason.encode!(payload))
  defp emit(_command, payload) when is_binary(payload), do: IO.puts(payload)
  defp emit(_command, payload), do: IO.puts(Render.render_run_payload(payload))

  defp emit_eval(%{json: true}, payload), do: IO.puts(Jason.encode!(payload))

  defp emit_eval(_command, payload) do
    payload
    |> Render.eval_text()
    |> IO.puts()
  end

  defp load_config(command) do
    Config.load(cwd: command.cwd, trust_repo_config: Map.get(command, :trust_repo_config))
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp agent_config_dir(cwd) do
    if Config.trust_repo_agent_config?() do
      dir = Path.join(cwd, "agent_config")
      if File.dir?(dir), do: dir
    end
  end

  defp version, do: Application.spec(:thinktank, :vsn) |> to_string()
end
