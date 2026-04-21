defmodule Thinktank.RunSession do
  @moduledoc false

  require Logger

  alias Thinktank.{ArtifactLayout, Error, Progress, RunStore, RunTracker}
  alias Thinktank.Engine.{Bootstrap, Runtime}

  @spec execute(Thinktank.Engine.resolved_run(), keyword()) ::
          {:ok, Thinktank.Engine.run_result()} | {:error, Error.t(), String.t() | nil}
  def execute(
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

    case Bootstrap.initialize_run(output_dir, contract, bench, opts) do
      :ok ->
        Bootstrap.record_run_started(output_dir, contract, bench, planner, synthesizer)

        case Runtime.run(bench, agents, planner, contract, config, opts, synthesizer) do
          {:ok, run_result, status, terminal_attrs} ->
            finalize_success(output_dir, status, terminal_attrs, opts, run_result)

          {:error, error, _runtime_output_dir, status, terminal_attrs} ->
            finalize_error(output_dir, status, terminal_attrs, error, opts)
        end

      {:error, %Error{} = error} ->
        finalize_error(
          output_dir,
          "failed",
          bootstrap_terminal_attrs(bench.id, error),
          error,
          opts
        )
    end
  end

  defp finalize_success(output_dir, status, terminal_attrs, opts, run_result) do
    finalize_run(output_dir, status, terminal_attrs)

    finalized_result = Map.put(run_result, :envelope, RunStore.result_envelope(output_dir))

    Progress.emit(opts, "run_completed", %{
      phase: Progress.phase_for_event("run_completed"),
      output_dir: output_dir,
      status: status
    })

    {:ok, finalized_result}
  end

  defp finalize_error(output_dir, status, terminal_attrs, error, opts) do
    finalize_run(output_dir, status, terminal_attrs)

    Progress.emit(opts, "run_completed", %{
      phase: Progress.phase_for_event("run_completed"),
      output_dir: output_dir,
      status: status,
      error: error
    })

    {:error, error, output_dir}
  end

  defp finalize_run(output_dir, status, terminal_attrs) do
    if File.exists?(Path.join(output_dir, ArtifactLayout.manifest_file())) do
      try do
        RunTracker.finish(output_dir, status, terminal_attrs)
      rescue
        error ->
          Logger.warning(
            "run finalization failed for #{Path.expand(output_dir)}: #{Exception.message(error)}"
          )

          :ok
      catch
        kind, reason ->
          Logger.warning(
            "run finalization failed for #{Path.expand(output_dir)}: #{inspect({kind, reason})}"
          )

          :ok
      end
    else
      :ok
    end
  end

  defp bootstrap_terminal_attrs(bench_id, %Error{} = error) do
    phase =
      case error.details[:phase] do
        value when is_binary(value) -> value
        _ -> "bootstrap"
      end

    %{
      "bench" => bench_id,
      "phase" => phase,
      "error" => error
    }
  end
end

defmodule Thinktank.Engine.Runtime do
  @moduledoc false

  alias Thinktank.{
    ArtifactLayout,
    BenchSpec,
    Error,
    Progress,
    RunStore,
    TraceLog
  }

  alias Thinktank.Engine.Preparation
  alias Thinktank.Executor.Agentic

  @type terminal_attrs :: map()

  @spec run(BenchSpec.t(), [map()], map() | nil, map(), map(), keyword(), map() | nil) ::
          {:ok, map(), String.t(), terminal_attrs()}
          | {:error, Error.t(), String.t(), String.t(), terminal_attrs()}
  def run(bench, agents, planner, contract, config, opts, synthesizer) do
    output_dir = contract.artifact_dir
    phase = Preparation.preparation_phase(bench, planner)

    Progress.emit(opts, "prepare_started", %{
      phase: phase,
      output_dir: output_dir,
      planner: planner && planner.name
    })

    case Preparation.prepare_execution(
           bench,
           agents,
           planner,
           contract,
           config,
           Keyword.put(opts, :progress_phase, phase),
           output_dir
         ) do
      {:ok, planned_agents, context} ->
        execute_bench(
          planned_agents,
          context,
          bench,
          contract,
          config,
          synthesizer,
          planner,
          opts
        )

      {:error, reason} ->
        error = Error.from_reason(reason)
        terminal_attrs = %{"bench" => bench.id, "phase" => "prepare_execution", "error" => error}
        {:error, error, output_dir, "failed", terminal_attrs}
    end
  end

  defp execute_bench(
         planned_agents,
         context,
         bench,
         contract,
         config,
         synthesizer,
         planner,
         opts
       ) do
    output_dir = contract.artifact_dir

    RunStore.set_planned_agents(output_dir, Enum.map(planned_agents, & &1.name))

    RunStore.append_run_note(
      output_dir,
      "planned agents selected: #{Enum.map_join(planned_agents, ", ", & &1.name)}"
    )

    TraceLog.record_event(output_dir, "planned_agents_selected", %{
      "bench" => bench.id,
      "agent_names" => Enum.map(planned_agents, & &1.name),
      "agent_count" => length(planned_agents)
    })

    Progress.emit(opts, "agents_started", %{
      phase: Progress.phase_for_event("agents_started"),
      output_dir: output_dir,
      planned_agents: Enum.map(planned_agents, & &1.name),
      total_agents: length(planned_agents)
    })

    results =
      Agentic.run(planned_agents, contract, context, config,
        concurrency: bench.concurrency || length(planned_agents),
        agent_config_dir: opts[:agent_config_dir],
        progress_phase: Progress.phase_for_event("agents_started"),
        progress_callback: opts[:progress_callback],
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

    terminal_attrs = %{
      "bench" => bench.id,
      "successful_agents" => Enum.count(results, &(&1.status == :ok)),
      "failed_agents" => Enum.count(results, &(&1.status == :error)),
      "synthesis_status" => synthesis && synthesis.status
    }

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
      "failed" ->
        {:error, Error.from_reason(:no_successful_agents), output_dir, status, terminal_attrs}

      _ ->
        {:ok, run_result, status, terminal_attrs}
    end
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
      RunStore.append_run_note(output_dir, "synthesis started with #{synthesizer.name}")

      Progress.emit(opts, "synthesis_started", %{
        phase: Progress.phase_for_event("synthesis_started"),
        output_dir: output_dir,
        synthesizer: synthesizer.name
      })

      synth_context =
        Map.merge(context, %{
          "agent_outputs" => render_agent_outputs(results)
        })

      [result] =
        Agentic.run([synthesizer], contract, synth_context, config,
          concurrency: 1,
          agent_config_dir: opts[:agent_config_dir],
          progress_phase: Progress.phase_for_event("synthesis_started"),
          progress_callback: opts[:progress_callback],
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
    Enum.each(ArtifactLayout.summary_artifacts(kind), fn {name, file} ->
      RunStore.write_text_artifact(output_dir, name, file, content)
    end)
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
      started_at: result.started_at,
      completed_at: result.completed_at,
      duration_ms: result.duration_ms,
      usage: result.usage,
      error: result.error
    })
  end

  defp derive_status(results, synthesis) do
    successful = successful_result_count(results)

    cond do
      partial_status?(results, synthesis, successful) -> "partial"
      successful == 0 -> "failed"
      degraded_status?(results, synthesis) -> "degraded"
      true -> "complete"
    end
  end

  defp successful_result_count(results) do
    Enum.count(results, &(&1.status == :ok and String.trim(&1.output) != ""))
  end

  defp partial_status?(results, synthesis, successful) do
    timeout_status?(results, synthesis) or synthesis_unavailable?(synthesis, successful)
  end

  defp timeout_status?(results, synthesis) do
    Enum.any?(results, &timeout_result?/1) or
      match?(%{status: :error, error: %{category: :timeout}}, synthesis)
  end

  defp synthesis_unavailable?(synthesis, successful) do
    successful > 0 and match?(%{status: :error}, synthesis)
  end

  defp degraded_status?(results, synthesis) do
    Enum.any?(results, &(&1.status == :error)) or match?(%{status: :error}, synthesis)
  end

  defp timeout_result?(%{status: :error, error: %{category: :timeout}}), do: true
  defp timeout_result?(_result), do: false

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
end
