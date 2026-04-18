defmodule Thinktank.Engine do
  @moduledoc """
  Bench launcher for Pi agents.
  """

  alias Thinktank.{AgentSpec, BenchSpec, Config, Error, Progress, RunContract}
  alias Thinktank.Engine.{Bootstrap, Preparation, Runtime}
  alias Thinktank.Executor.Agentic

  @type run_result :: %{
          contract: RunContract.t(),
          bench: BenchSpec.t(),
          output_dir: String.t(),
          envelope: map(),
          agents: [AgentSpec.t()],
          planner: AgentSpec.t() | nil,
          synthesizer: AgentSpec.t() | nil,
          results: [Agentic.result()],
          synthesis: Agentic.result() | nil
        }

  @type resolved_run :: %{
          contract: RunContract.t(),
          bench: BenchSpec.t(),
          config: Config.t(),
          output_dir: String.t(),
          agents: [AgentSpec.t()],
          planner: AgentSpec.t() | nil,
          synthesizer: AgentSpec.t() | nil
        }

  @spec resolve(String.t(), map(), keyword()) ::
          {:ok, resolved_run()} | {:error, Error.t(), String.t() | nil}
  def resolve(bench_id, input, opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    provided_config = Keyword.get(opts, :config)

    config_opts =
      [cwd: cwd]
      |> maybe_put_opt(:trust_repo_config, Keyword.get(opts, :trust_repo_config))

    with {:ok, config} <- Preparation.resolve_config(provided_config, config_opts),
         {:ok, bench} <- Config.bench(config, bench_id),
         {:ok, input} <- Preparation.normalize_input(bench, input),
         {:ok, agents} <- Preparation.resolve_agents(bench, config, input),
         {:ok, planner} <- Preparation.resolve_planner(bench, config),
         {:ok, synthesizer} <- Preparation.resolve_synthesizer(bench, config) do
      output_dir = Keyword.get(opts, :output) || generate_output_dir(bench_id)

      contract = %RunContract{
        bench_id: bench_id,
        workspace_root: cwd,
        input: input,
        artifact_dir: output_dir,
        adapter_context: Keyword.get(opts, :adapter_context, %{})
      }

      {:ok,
       %{
         config: config,
         bench: bench,
         contract: contract,
         output_dir: output_dir,
         agents: agents,
         planner: planner,
         synthesizer: synthesizer
       }}
    else
      {:error, reason} -> {:error, normalize_error(reason), nil}
    end
  end

  @spec run(String.t(), map(), keyword()) ::
          {:ok, run_result()} | {:error, Error.t(), String.t() | nil}
  def run(bench_id, input, opts \\ []) do
    case resolve(bench_id, input, opts) do
      {:ok, resolved} ->
        run_resolved(resolved, opts)

      {:error, reason, output_dir} ->
        {:error, reason, output_dir}
    end
  end

  @spec generate_output_dir(String.t()) :: String.t()
  def generate_output_dir(bench_id) do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d-%H%M%S")
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    bench_slug =
      bench_id
      |> String.replace("/", "-")
      |> String.replace(~r/[^a-zA-Z0-9-]/, "")

    Path.join(System.tmp_dir!(), "thinktank-#{bench_slug}-#{timestamp}-#{suffix}")
  end

  @spec run_resolved(resolved_run(), keyword()) ::
          {:ok, run_result()} | {:error, Error.t(), String.t() | nil}
  def run_resolved(
        %{
          config: config,
          bench: bench,
          contract: contract,
          output_dir: output_dir,
          agents: agents,
          planner: planner,
          synthesizer: synthesizer
        },
        opts \\ []
      ) do
    Progress.emit(opts, "bootstrap_started", %{
      phase: Progress.phase_for_event("bootstrap_started"),
      output_dir: output_dir,
      trace_events: Progress.trace_events_path(output_dir),
      planned_agents: Enum.map(agents, & &1.name),
      total_agents: length(agents),
      planner: planner && planner.name,
      synthesizer: synthesizer && synthesizer.name
    })

    case Bootstrap.initialize_run(output_dir, contract, bench) do
      :ok ->
        Bootstrap.record_run_started(output_dir, contract, bench, planner, synthesizer)
        Runtime.run(bench, agents, planner, contract, config, opts, synthesizer)

      {:error, reason} ->
        error = normalize_error(reason)

        Progress.emit(opts, "run_completed", %{
          phase: Progress.phase_for_event("run_completed"),
          output_dir: output_dir,
          status: "failed",
          error: error
        })

        {:error, error, output_dir}
    end
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_error(%Error{} = error), do: error
  defp normalize_error(reason), do: Error.from_reason(reason)
end
