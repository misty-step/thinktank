defmodule Thinktank.Engine do
  @moduledoc """
  Workflow engine for constrained stage-graph execution.
  """

  alias Thinktank.{
    AgentSpec,
    Config,
    RunContract,
    RunStore,
    StageRegistry,
    StageSpec,
    WorkflowSpec
  }

  @type run_result :: %{
          contract: RunContract.t(),
          workflow: WorkflowSpec.t(),
          output_dir: String.t(),
          envelope: map(),
          context: map()
        }

  @spec run(String.t(), map(), keyword()) ::
          {:ok, run_result()} | {:error, term(), String.t() | nil}
  def run(workflow_id, input, opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    with {:ok, config} <- Config.load(cwd: cwd),
         {:ok, workflow} <- Config.workflow(config, workflow_id),
         :ok <- validate_input(workflow, input),
         {:ok, mode} <- resolve_mode(workflow, Keyword.get(opts, :mode)) do
      output_dir = Keyword.get(opts, :output, generate_output_dir(workflow_id))

      contract = %RunContract{
        workflow_id: workflow_id,
        workspace_root: cwd,
        input: input,
        artifact_dir: output_dir,
        adapter_context: Keyword.get(opts, :adapter_context, %{}),
        mode: mode
      }

      RunStore.init_run(output_dir, contract, workflow)

      case execute_stages(workflow.stages, %{}, contract, config, 0, opts) do
        {:ok, context} ->
          RunStore.complete_run(output_dir, "complete")

          {:ok,
           %{
             contract: contract,
             workflow: workflow,
             output_dir: output_dir,
             envelope: RunStore.result_envelope(output_dir),
             context: context
           }}

        {:error, reason} ->
          RunStore.write_json_artifact(output_dir, "failure", "artifacts/failure.json", %{
            error: inspect(reason)
          })

          RunStore.complete_run(output_dir, "failed")
          {:error, reason, output_dir}
      end
    else
      {:error, reason} -> {:error, reason, nil}
      reason -> {:error, reason, nil}
    end
  end

  @spec generate_output_dir(String.t()) :: String.t()
  def generate_output_dir(workflow_id) do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d-%H%M%S")
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    workflow_slug =
      workflow_id |> String.replace("/", "-") |> String.replace(~r/[^a-zA-Z0-9-]/, "")

    Path.join(System.tmp_dir!(), "thinktank-#{workflow_slug}-#{timestamp}-#{suffix}")
  end

  defp execute_stages([], context, _contract, _config, _index, _opts), do: {:ok, context}

  defp execute_stages([stage | rest], context, contract, config, index, opts) do
    if should_run?(stage, context) do
      case run_stage_with_retry(stage, context, contract, config, opts) do
        {:ok, outputs, final_attempts} ->
          merged = Map.merge(context, outputs)

          RunStore.record_stage(
            contract.artifact_dir,
            stage.name,
            "complete",
            final_attempts,
            stage_snapshot(outputs)
          )

          execute_stages(rest, merged, contract, config, index + 1, opts)

        {:error, reason, final_attempts} ->
          RunStore.record_stage(
            contract.artifact_dir,
            stage.name,
            "failed",
            final_attempts,
            %{error: inspect(reason)}
          )

          {:error, {:stage_failed, stage.name, reason}}
      end
    else
      RunStore.record_stage(contract.artifact_dir, stage.name, "skipped", 0, %{})
      execute_stages(rest, context, contract, config, index + 1, opts)
    end
  end

  defp run_stage_with_retry(stage, context, contract, config, opts, attempt \\ 1)

  defp run_stage_with_retry(stage, context, contract, config, opts, attempt) do
    case StageRegistry.run(stage, context, contract, config, opts) do
      {:ok, outputs} ->
        {:ok, outputs, attempt}

      {:error, reason} ->
        if attempt <= stage.retry do
          run_stage_with_retry(stage, context, contract, config, opts, attempt + 1)
        else
          {:error, reason, attempt}
        end
    end
  end

  @doc false
  @spec should_run?(StageSpec.t(), map()) :: boolean()
  def should_run?(%StageSpec{when: true}, _context), do: true
  def should_run?(%StageSpec{when: false}, _context), do: false
  def should_run?(%StageSpec{when: nil}, _context), do: true

  def should_run?(%StageSpec{when: path}, context) when is_binary(path) do
    case resolve_context_path(context, path) do
      nil -> false
      false -> false
      "" -> false
      [] -> false
      _ -> true
    end
  end

  defp validate_input(%WorkflowSpec{input_schema: %{"required" => required}}, input)
       when is_list(required) do
    missing = Enum.filter(required, &missing_input_key?(input, &1))
    if missing == [], do: :ok, else: {:error, {:missing_input_keys, missing}}
  end

  defp validate_input(_workflow, _input), do: :ok

  defp resolve_mode(%WorkflowSpec{default_mode: default_mode, execution_mode: :flexible}, nil),
    do: {:ok, default_mode}

  defp resolve_mode(%WorkflowSpec{execution_mode: :flexible}, requested)
       when requested in [:quick, :deep],
       do: {:ok, requested}

  defp resolve_mode(
         %WorkflowSpec{id: id, default_mode: default_mode, execution_mode: required_mode},
         nil
       )
       when required_mode in [:quick, :deep] do
    if default_mode == required_mode do
      {:ok, default_mode}
    else
      {:error, {:invalid_workflow_mode_config, id, default_mode, required_mode}}
    end
  end

  defp resolve_mode(%WorkflowSpec{id: id, execution_mode: required_mode}, requested)
       when required_mode in [:quick, :deep] and requested in [:quick, :deep] do
    if requested == required_mode do
      {:ok, requested}
    else
      {:error, {:mode_not_allowed, id, requested, required_mode}}
    end
  end

  @doc false
  @spec resolve_context_path(map(), String.t()) :: term() | nil
  def resolve_context_path(context, path) do
    Enum.reduce_while(String.split(path, "."), context, fn segment, current ->
      atom_value = fetch_existing_atom_key(current, segment)

      cond do
        not is_nil(atom_value) ->
          {:cont, atom_value}

        is_map(current) and Map.has_key?(current, segment) ->
          {:cont, Map.get(current, segment)}

        true ->
          {:halt, nil}
      end
    end)
  end

  defp fetch_existing_atom_key(current, segment) when is_map(current) do
    atom_key =
      try do
        String.to_existing_atom(segment)
      rescue
        ArgumentError -> nil
      end

    if atom_key && Map.has_key?(current, atom_key), do: Map.get(current, atom_key)
  end

  defp fetch_existing_atom_key(_current, _segment), do: nil

  defp missing_input_key?(input, key) do
    atom_value = fetch_existing_atom_key(input, key)
    atom_value in [nil, ""] and Map.get(input, key) in [nil, ""]
  end

  defp stage_snapshot(outputs) do
    outputs
    |> Map.drop([
      :diff_text,
      :review_bundle,
      :context_block,
      :context_files,
      :agent_results,
      :parsed_reviews,
      :review_summary,
      :synthesis
    ])
    |> normalize_snapshot()
  end

  defp normalize_snapshot(%AgentSpec{name: name, model: model, provider: provider}) do
    %{name: name, model: model, provider: provider}
  end

  defp normalize_snapshot(%{} = map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), normalize_snapshot(value)} end)
    |> Enum.into(%{})
  end

  defp normalize_snapshot(list) when is_list(list), do: Enum.map(list, &normalize_snapshot/1)
  defp normalize_snapshot(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_snapshot(value), do: value
end
