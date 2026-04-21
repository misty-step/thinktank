defmodule Thinktank.Engine.Preparation do
  @moduledoc false

  alias Thinktank.{ArtifactLayout, BenchSpec, Config, RunStore, TraceLog}
  alias Thinktank.Review.{Context, Planner}

  @spec normalize_input(BenchSpec.t(), map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def normalize_input(%BenchSpec{default_task: default_task}, input) when is_map(input) do
    normalized =
      input
      |> stringify_keys()
      |> maybe_put("input_text", default_task)

    if valid_input_text?(normalized["input_text"]) do
      {:ok, normalized}
    else
      {:error, :missing_input_text}
    end
  end

  def normalize_input(_bench, _input), do: {:error, "input must be a map"}

  @spec prepare_execution(
          BenchSpec.t(),
          [map()],
          map() | nil,
          map(),
          Config.t(),
          keyword(),
          Path.t()
        ) ::
          {:ok, [map()], map()} | {:error, term()}
  def prepare_execution(
        %BenchSpec{kind: :review},
        agents,
        planner,
        contract,
        config,
        opts,
        output_dir
      ) do
    case Context.capture(contract.workspace_root, contract.input) do
      {:ok, review_context} ->
        planning = plan_review(agents, planner, contract, review_context, config, opts)
        planned_agents = Planner.apply_plan(planning.plan, agents)
        write_review_artifacts(output_dir, review_context, planning)

        context = %{
          "paths_hint" => render_paths_hint(contract.input),
          "review_context" => render_json(review_context),
          "review_plan" => render_json(planning.plan),
          "synthesis_brief" => planning.plan["synthesis_brief"] || ""
        }

        {:ok, planned_agents, context}

      {:error, _reason} = error ->
        error
    end
  end

  def prepare_execution(_bench, agents, _planner, contract, _config, _opts, _output_dir) do
    {:ok, agents, %{"paths_hint" => render_paths_hint(contract.input)}}
  end

  @spec resolve_agents(BenchSpec.t(), Config.t(), map()) :: {:ok, [map()]} | {:error, String.t()}
  def resolve_agents(%BenchSpec{agents: bench_agents}, %Config{agents: agents}, input) do
    names =
      case Map.get(input, "agents", []) do
        [] -> bench_agents
        selected when is_list(selected) -> selected
        _ -> bench_agents
      end

    fetch_agents(agents, names)
  end

  @spec resolve_planner(BenchSpec.t(), Config.t()) :: {:ok, map() | nil} | {:error, String.t()}
  def resolve_planner(%BenchSpec{planner: nil}, _config), do: {:ok, nil}

  def resolve_planner(%BenchSpec{planner: name}, %Config{agents: agents}) do
    case Map.fetch(agents, name) do
      {:ok, agent} -> {:ok, agent}
      :error -> {:error, "unknown planner: #{name}"}
    end
  end

  @spec resolve_synthesizer(BenchSpec.t(), Config.t()) ::
          {:ok, map() | nil} | {:error, String.t()}
  def resolve_synthesizer(%BenchSpec{synthesizer: nil}, _config), do: {:ok, nil}

  def resolve_synthesizer(%BenchSpec{synthesizer: name}, %Config{agents: agents}) do
    case Map.fetch(agents, name) do
      {:ok, agent} -> {:ok, agent}
      :error -> {:error, "unknown synthesizer: #{name}"}
    end
  end

  @spec preparation_phase(BenchSpec.t(), map() | nil) :: String.t()
  def preparation_phase(%BenchSpec{kind: :review}, planner) when not is_nil(planner),
    do: "planning"

  def preparation_phase(%BenchSpec{kind: :review}, _planner), do: "preparing_review"
  def preparation_phase(_bench, _planner), do: "preparing_run"

  @spec resolve_config(Config.t() | nil, keyword()) :: {:ok, Config.t()} | {:error, term()}
  def resolve_config(%Config{} = config, _opts), do: {:ok, config}
  def resolve_config(nil, opts), do: Config.load(opts)

  @spec render_paths_hint(map() | [String.t()]) :: String.t()
  def render_paths_hint(input) when is_map(input) do
    input
    |> Map.get("paths", [])
    |> render_paths_hint()
  end

  def render_paths_hint(paths) when is_list(paths) and paths != [] do
    Enum.map_join(paths, "\n", &"- #{&1}")
  end

  def render_paths_hint(_), do: "- none specified"

  defp plan_review(agents, planner, contract, review_context, config, opts) do
    selected_agents = Map.get(contract.input, "agents", [])

    if selected_agents != [] do
      Planner.manual(agents)
    else
      Planner.create(planner, agents, contract, review_context, config,
        agent_config_dir: opts[:agent_config_dir],
        progress_callback: opts[:progress_callback],
        progress_phase: opts[:progress_phase],
        runner: opts[:runner]
      )
    end
  end

  defp write_review_artifacts(output_dir, review_context, %{plan: plan} = planning) do
    maybe_record_planner_fallback(output_dir, planning)

    RunStore.write_json_artifact(
      output_dir,
      "review-context",
      ArtifactLayout.review_context_json_file(),
      review_context
    )

    write_optional_text_artifact(
      output_dir,
      "review-context-summary",
      ArtifactLayout.review_context_text_file(),
      Context.render(review_context)
    )

    RunStore.write_json_artifact(
      output_dir,
      "review-plan",
      ArtifactLayout.review_plan_json_file(),
      plan
    )

    write_optional_text_artifact(
      output_dir,
      "review-plan-summary",
      ArtifactLayout.review_plan_text_file(),
      Planner.render(plan)
    )

    maybe_write_planner_artifact(output_dir, planning)
  end

  defp maybe_write_planner_artifact(_output_dir, %{planner_result: nil}), do: :ok

  defp maybe_write_planner_artifact(output_dir, %{planner_result: planner_result}) do
    output =
      case planner_result.status do
        :ok ->
          planner_result.output

        :error ->
          planner_result.output <>
            if(planner_result.error, do: "\n\nERROR: #{inspect(planner_result.error)}", else: "")
      end

    write_optional_text_artifact(
      output_dir,
      "review-planner",
      ArtifactLayout.review_planner_file(),
      output
    )
  end

  defp maybe_record_planner_fallback(_output_dir, %{fallback_reason: nil}), do: :ok

  defp maybe_record_planner_fallback(output_dir, %{plan: %{"source" => "fallback"}} = planning) do
    TraceLog.record_event(output_dir, "review_planner_fallback", %{
      "reason" => planning.fallback_reason,
      "warnings" => Map.get(planning.plan, "warnings", []),
      "planner_status" => planner_status(planning.planner_result)
    })
  end

  defp maybe_record_planner_fallback(_output_dir, _planning), do: :ok

  defp write_optional_text_artifact(output_dir, name, filename, content) do
    RunStore.write_text_artifact(output_dir, name, filename, content)
  rescue
    error ->
      TraceLog.record_event(output_dir, "review_optional_artifact_write_failed", %{
        "artifact_name" => name,
        "artifact_file" => filename,
        "error" => Exception.message(error)
      })

      :ok
  end

  defp planner_status(nil), do: "none"
  defp planner_status(%{status: status}), do: to_string(status)

  defp render_json(value), do: Jason.encode!(value, pretty: true)

  defp fetch_agents(agents, names) do
    names
    |> Enum.reduce_while({:ok, []}, fn name, {:ok, acc} ->
      case Map.fetch(agents, name) do
        {:ok, agent} -> {:cont, {:ok, [agent | acc]}}
        :error -> {:halt, {:error, "unknown agent: #{name}"}}
      end
    end)
    |> case do
      {:ok, fetched_agents} -> {:ok, Enum.reverse(fetched_agents)}
      error -> error
    end
  end

  defp valid_input_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp valid_input_text?(_), do: false

  defp maybe_put(map, _key, nil), do: map

  defp maybe_put(map, key, value) do
    case Map.get(map, key) do
      existing when is_binary(existing) ->
        if String.trim(existing) == "", do: Map.put(map, key, value), else: map

      nil ->
        Map.put(map, key, value)

      _ ->
        map
    end
  end

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.into(%{})
  end
end
