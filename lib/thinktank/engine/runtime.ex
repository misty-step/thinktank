defmodule Thinktank.Engine.Runtime do
  @moduledoc false

  alias Thinktank.{
    ArtifactLayout,
    BenchSpec,
    Error,
    Progress,
    RunStore,
    RunTracker,
    TraceLog
  }

  alias Thinktank.Engine.Preparation
  alias Thinktank.Executor.Agentic

  @spec run(BenchSpec.t(), [map()], map() | nil, map(), map(), keyword(), map() | nil) ::
          {:ok, map()} | {:error, Error.t(), String.t()}
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
        RunTracker.finish(output_dir, "failed", %{
          "bench" => bench.id,
          "phase" => "prepare_execution",
          "error" => Error.from_reason(reason)
        })

        Progress.emit(opts, "run_completed", %{
          phase: Progress.phase_for_event("run_completed"),
          output_dir: output_dir,
          status: "failed",
          error: Error.from_reason(reason)
        })

        {:error, Error.from_reason(reason), output_dir}
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

    RunTracker.finish(output_dir, status, %{
      "bench" => bench.id,
      "successful_agents" => Enum.count(results, &(&1.status == :ok)),
      "failed_agents" => Enum.count(results, &(&1.status == :error)),
      "synthesis_status" => synthesis && synthesis.status
    })

    Progress.emit(opts, "run_completed", %{
      phase: Progress.phase_for_event("run_completed"),
      output_dir: output_dir,
      status: status
    })

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
      "failed" -> {:error, Error.from_reason(:no_successful_agents), output_dir}
      _ -> {:ok, run_result}
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
