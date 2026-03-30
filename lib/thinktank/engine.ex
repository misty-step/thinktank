defmodule Thinktank.Engine do
  @moduledoc """
  Bench launcher for Pi agents.
  """

  alias Thinktank.{
    AgentSpec,
    BenchSpec,
    Config,
    RunContract,
    RunStore
  }

  alias Thinktank.Executor.Agentic
  alias Thinktank.Review.{Context, Planner}

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
          {:ok, resolved_run()} | {:error, term(), String.t() | nil}
  def resolve(bench_id, input, opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    provided_config = Keyword.get(opts, :config)

    config_opts =
      [cwd: cwd] |> maybe_put_opt(:trust_repo_config, Keyword.get(opts, :trust_repo_config))

    with {:ok, config} <- resolve_config(provided_config, config_opts),
         {:ok, bench} <- Config.bench(config, bench_id),
         {:ok, input} <- normalize_input(bench, input),
         {:ok, agents} <- resolve_agents(bench, config, input),
         {:ok, planner} <- resolve_planner(bench, config),
         {:ok, synthesizer} <- resolve_synthesizer(bench, config) do
      output_dir = Keyword.get(opts, :output, generate_output_dir(bench_id))

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
      {:error, reason} -> {:error, reason, nil}
      reason -> {:error, reason, nil}
    end
  end

  @spec run(String.t(), map(), keyword()) ::
          {:ok, run_result()} | {:error, term(), String.t() | nil}
  def run(bench_id, input, opts \\ []) do
    case resolve(bench_id, input, opts) do
      {:ok,
       %{
         config: config,
         bench: bench,
         contract: contract,
         output_dir: output_dir,
         agents: agents,
         planner: planner,
         synthesizer: synthesizer
       }} ->
        RunStore.init_run(output_dir, contract, bench)
        write_task_artifact(output_dir, contract.input)

        {planned_agents, context} =
          prepare_execution(bench, agents, planner, contract, config, opts, output_dir)

        RunStore.set_planned_agents(output_dir, Enum.map(planned_agents, & &1.name))

        results =
          Agentic.run(planned_agents, contract, context, config,
            concurrency: bench.concurrency || length(planned_agents),
            agent_config_dir: opts[:agent_config_dir],
            runner: opts[:runner]
          )

        Enum.each(results, &record_result(output_dir, &1))

        synthesis =
          maybe_run_synthesizer(
            synthesizer,
            results,
            bench,
            contract,
            config,
            context,
            opts,
            output_dir
          )

        status = derive_status(results, synthesis)
        RunStore.complete_run(output_dir, status)

        run_result = %{
          contract: contract,
          bench: bench,
          output_dir: output_dir,
          envelope: RunStore.result_envelope(output_dir),
          agents: planned_agents,
          planner: planner,
          synthesizer: synthesizer,
          results: results,
          synthesis: synthesis
        }

        case status do
          "failed" -> {:error, :no_successful_agents, output_dir}
          _ -> {:ok, run_result}
        end

      {:error, reason, output_dir} ->
        {:error, reason, output_dir}
    end
  end

  @spec generate_output_dir(String.t()) :: String.t()
  def generate_output_dir(bench_id) do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d-%H%M%S")
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    bench_slug =
      bench_id |> String.replace("/", "-") |> String.replace(~r/[^a-zA-Z0-9-]/, "")

    Path.join(System.tmp_dir!(), "thinktank-#{bench_slug}-#{timestamp}-#{suffix}")
  end

  defp maybe_run_synthesizer(
         nil,
         _results,
         _bench,
         _contract,
         _config,
         _context,
         _opts,
         _output_dir
       ),
       do: nil

  defp maybe_run_synthesizer(
         _synthesizer,
         _results,
         _bench,
         %{input: %{"no_synthesis" => true}},
         _config,
         _context,
         _opts,
         _output_dir
       ),
       do: nil

  defp maybe_run_synthesizer(
         synthesizer,
         results,
         bench,
         contract,
         config,
         context,
         opts,
         output_dir
       ) do
    if Enum.any?(results, &(&1.status == :ok and String.trim(&1.output) != "")) do
      synth_context =
        Map.merge(context, %{
          "agent_outputs" => render_agent_outputs(results)
        })

      [result] =
        Agentic.run([synthesizer], contract, synth_context, config,
          concurrency: 1,
          agent_config_dir: opts[:agent_config_dir],
          runner: opts[:runner]
        )

      record_result(output_dir, result)

      if result.status == :ok do
        write_summary_artifacts(output_dir, bench, result.output)
      end

      result
    end
  end

  defp write_summary_artifacts(output_dir, %BenchSpec{kind: kind}, content) do
    RunStore.write_text_artifact(output_dir, "summary", "summary.md", content)

    case kind do
      :review ->
        RunStore.write_text_artifact(output_dir, "review", "review.md", content)

      :research ->
        RunStore.write_text_artifact(output_dir, "synthesis", "synthesis.md", content)

      _ ->
        :ok
    end
  end

  defp write_task_artifact(output_dir, input) do
    task =
      [Map.get(input, "input_text"), render_paths_hint(input)]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n\n")

    if task != "" do
      RunStore.write_text_artifact(output_dir, "task", "task.md", task)
    end
  end

  defp record_result(output_dir, result) do
    output =
      case result.status do
        :ok ->
          result.output

        :error ->
          result.output <> if(result.error, do: "\n\nERROR: #{inspect(result.error)}", else: "")
      end

    RunStore.record_agent_result(output_dir, result.agent.name, output, %{
      instance_id: result.instance_id,
      status: result.status,
      model: result.agent.model,
      provider: result.agent.provider,
      usage: result.usage,
      error: result.error
    })
  end

  defp derive_status(results, synthesis) do
    successful = Enum.count(results, &(&1.status == :ok and String.trim(&1.output) != ""))
    degraded = Enum.any?(results, &(&1.status == :error)) or match?(%{status: :error}, synthesis)

    cond do
      successful == 0 -> "failed"
      degraded -> "degraded"
      true -> "complete"
    end
  end

  defp normalize_input(%BenchSpec{default_task: default_task}, input) when is_map(input) do
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

  defp normalize_input(_bench, _input), do: {:error, "input must be a map"}

  defp prepare_execution(
         %BenchSpec{kind: :review},
         agents,
         planner,
         contract,
         config,
         opts,
         output_dir
       ) do
    review_context = Context.capture(contract.workspace_root, contract.input)
    planning = plan_review(agents, planner, contract, review_context, config, opts)
    planned_agents = Planner.apply_plan(planning.plan, agents)
    write_review_artifacts(output_dir, review_context, planning)

    context = %{
      "paths_hint" => render_paths_hint(contract.input),
      "review_context" => Context.render(review_context),
      "review_plan" => Planner.render(planning.plan),
      "synthesis_brief" => planning.plan["synthesis_brief"] || ""
    }

    {planned_agents, context}
  end

  defp prepare_execution(_bench, agents, _planner, contract, _config, _opts, _output_dir) do
    {agents, %{"paths_hint" => render_paths_hint(contract.input)}}
  end

  defp plan_review(
         agents,
         planner,
         contract,
         review_context,
         config,
         opts
       ) do
    selected_agents = Map.get(contract.input, "agents", [])

    if selected_agents != [] do
      Planner.manual(agents)
    else
      Planner.create(planner, agents, contract, review_context, config,
        agent_config_dir: opts[:agent_config_dir],
        runner: opts[:runner]
      )
    end
  end

  defp write_review_artifacts(output_dir, review_context, %{plan: plan} = planning) do
    RunStore.write_json_artifact(
      output_dir,
      "review-context",
      "review/context.json",
      review_context
    )

    RunStore.write_text_artifact(
      output_dir,
      "review-context-summary",
      "review/context.md",
      Context.render(review_context)
    )

    RunStore.write_json_artifact(output_dir, "review-plan", "review/plan.json", plan)

    RunStore.write_text_artifact(
      output_dir,
      "review-plan-summary",
      "review/plan.md",
      Planner.render(plan)
    )

    maybe_write_planner_artifact(output_dir, planning)
  end

  defp resolve_agents(%BenchSpec{agents: bench_agents}, %Config{agents: agents}, input) do
    names =
      case Map.get(input, "agents", []) do
        [] -> bench_agents
        selected when is_list(selected) -> selected
        _ -> bench_agents
      end

    fetch_agents(agents, names)
  end

  defp resolve_planner(%BenchSpec{planner: nil}, _config), do: {:ok, nil}

  defp resolve_planner(%BenchSpec{planner: name}, %Config{agents: agents}) do
    case Map.fetch(agents, name) do
      {:ok, agent} -> {:ok, agent}
      :error -> {:error, "unknown planner: #{name}"}
    end
  end

  defp resolve_synthesizer(%BenchSpec{synthesizer: nil}, _config), do: {:ok, nil}

  defp resolve_synthesizer(%BenchSpec{synthesizer: name}, %Config{agents: agents}) do
    case Map.fetch(agents, name) do
      {:ok, agent} -> {:ok, agent}
      :error -> {:error, "unknown synthesizer: #{name}"}
    end
  end

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

  defp render_agent_outputs(results) do
    Enum.map_join(results, "\n\n", fn result ->
      status = if result.status == :ok, do: "ok", else: "error"

      """
      ## #{result.agent.name}
      status: #{status}
      model: #{result.agent.model}

      #{result.output}
      """
      |> String.trim()
    end)
  end

  defp render_paths_hint(input) when is_map(input) do
    input
    |> Map.get("paths", [])
    |> render_paths_hint()
  end

  defp render_paths_hint(paths) when is_list(paths) and paths != [] do
    Enum.map_join(paths, "\n", &"- #{&1}")
  end

  defp render_paths_hint(_), do: "- none specified"

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

    RunStore.write_text_artifact(output_dir, "review-planner", "review/planner.md", output)
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

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp resolve_config(%Config{} = config, _opts), do: {:ok, config}
  defp resolve_config(nil, opts), do: Config.load(opts)

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.into(%{})
  end
end
