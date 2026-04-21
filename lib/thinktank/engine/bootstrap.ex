defmodule Thinktank.Engine.Bootstrap do
  @moduledoc false

  alias Thinktank.{ArtifactLayout, BenchSpec, Error, RunContract, RunStore, RunTracker, TraceLog}
  alias Thinktank.Engine.Preparation

  @spec initialize_run(Path.t(), RunContract.t(), BenchSpec.t()) :: :ok | {:error, Error.t()}
  def initialize_run(output_dir, %RunContract{} = contract, %BenchSpec{} = bench) do
    case init_run(output_dir, contract, bench) do
      :ok -> write_task_artifact(output_dir, contract.input, bench, contract)
      {:error, _reason} = error -> error
    end
  end

  @spec record_run_started(Path.t(), RunContract.t(), BenchSpec.t(), map() | nil, map() | nil) ::
          :ok
  def record_run_started(output_dir, contract, bench, planner, synthesizer) do
    RunStore.append_run_note(
      output_dir,
      "run started for #{bench.id} (planner=#{(planner && planner.name) || "none"}, synthesizer=#{(synthesizer && synthesizer.name) || "none"})"
    )

    TraceLog.record_event(output_dir, "run_started", %{
      "bench" => bench.id,
      "kind" => bench.kind,
      "workspace_root" => contract.workspace_root,
      "planned_agents" => bench.agents,
      "planner" => planner && planner.name,
      "synthesizer" => synthesizer && synthesizer.name
    })
  end

  defp init_run(output_dir, contract, bench) do
    rescue_bootstrap_failure("init_run", bench, contract, fn ->
      RunStore.init_run(output_dir, contract, bench)
      RunTracker.start(output_dir, %{"bench" => bench.id})
      :ok
    end)
  end

  defp write_task_artifact(output_dir, input, bench, contract) do
    rescue_bootstrap_failure("task_artifact", bench, contract, fn ->
      task =
        [Map.get(input, "input_text"), Preparation.render_paths_hint(input)]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n\n")

      if task != "" do
        RunStore.write_text_artifact(output_dir, "task", ArtifactLayout.task_file(), task)
      end

      :ok
    end)
  end

  defp rescue_bootstrap_failure(phase, bench, contract, fun) do
    fun.()
  rescue
    error ->
      {:error, bootstrap_failure(phase, bench, contract, {:exception, error})}
  catch
    kind, reason ->
      {:error, bootstrap_failure(phase, bench, contract, {kind, reason})}
  end

  defp bootstrap_failure(phase, bench, contract, failure) do
    details = bootstrap_error_details(phase, bench, contract, failure)

    unless File.exists?(Path.join(contract.artifact_dir, ArtifactLayout.manifest_file())) do
      TraceLog.record_global_event("bootstrap_failed", details)
    end

    Error.from_reason(
      Map.merge(details, %{
        category: :bootstrap_failed,
        message: "failed to initialize run artifacts"
      })
    )
  end

  defp bootstrap_error_details(phase, bench, contract, {:exception, error}) do
    %{
      phase: phase,
      bench: bench.id,
      kind: bench.kind,
      workspace_root: contract.workspace_root,
      output_dir: contract.artifact_dir,
      input: summarize_bootstrap_input(contract.input),
      error: %{
        category: :bootstrap_failed,
        kind: "exception",
        type: inspect(error.__struct__),
        message: Exception.message(error)
      }
    }
  end

  defp bootstrap_error_details(phase, bench, contract, {kind, reason}) do
    %{
      phase: phase,
      bench: bench.id,
      kind: bench.kind,
      workspace_root: contract.workspace_root,
      output_dir: contract.artifact_dir,
      input: summarize_bootstrap_input(contract.input),
      error: %{
        category: :bootstrap_failed,
        kind: inspect(kind),
        message: inspect(reason)
      }
    }
  end

  defp summarize_bootstrap_input(input) do
    input_text = input_value(input, :input_text) || ""
    paths = input_list(input, :paths)
    agents = input_list(input, :agents)

    %{
      input_text_bytes: input_text_bytes(input_text),
      input_text_sha256: sha256_hex(input_text),
      path_count: length(paths),
      agent_count: length(agents),
      no_synthesis: input_value(input, :no_synthesis) || false
    }
  end

  defp input_text_bytes(nil), do: 0
  defp input_text_bytes(value) when is_binary(value), do: byte_size(value)
  defp input_text_bytes(value), do: value |> to_string() |> byte_size()

  defp input_value(input, key) when is_map(input) and is_atom(key) do
    Map.get(input, Atom.to_string(key)) || Map.get(input, key)
  end

  defp input_list(input, key) do
    case input_value(input, key) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp sha256_hex(value) when is_binary(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
  end
end
