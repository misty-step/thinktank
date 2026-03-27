defmodule Thinktank.WorkflowSpec do
  @moduledoc """
  Typed workflow configuration describing the stage graph and defaults.
  """

  alias Thinktank.StageSpec
  @required_stage_order [:prepare, :route, :fanout, :emit]
  @stage_order [:prepare, :route, :fanout, :aggregate, :emit]
  @stage_rank Enum.with_index(@stage_order) |> Enum.into(%{})

  @enforce_keys [:id, :description, :stages]
  defstruct [
    :id,
    :description,
    input_schema: %{},
    default_mode: :quick,
    execution_mode: :flexible,
    stages: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          description: String.t(),
          input_schema: map(),
          default_mode: :quick | :deep,
          execution_mode: :flexible | :quick | :deep,
          stages: [StageSpec.t()]
        }

  @spec from_pair(String.t(), map()) :: {:ok, t()} | {:error, String.t()}
  def from_pair(id, %{} = raw) when is_binary(id) do
    with {:ok, description} <- require_description(raw["description"]),
         {:ok, stages} <- parse_stages(raw["stages"]),
         :ok <- validate_stage_graph(stages),
         {:ok, default_mode} <- parse_mode(Map.get(raw, "default_mode", "quick")),
         {:ok, execution_mode} <- parse_execution_mode(Map.get(raw, "execution_mode", "flexible")) do
      {:ok,
       %__MODULE__{
         id: id,
         description: description,
         input_schema: Map.get(raw, "input_schema", %{}),
         default_mode: default_mode,
         execution_mode: execution_mode,
         stages: stages
       }}
    end
  end

  def from_pair(id, _raw), do: {:error, "workflow #{id} must be a map"}

  defp require_description(desc) when is_binary(desc) and desc != "", do: {:ok, desc}
  defp require_description(_), do: {:error, "workflow description is required"}

  defp parse_stages(stages) when is_list(stages) and stages != [] do
    stages
    |> Enum.reduce_while({:ok, []}, fn raw, {:ok, acc} ->
      case StageSpec.from_map(raw) do
        {:ok, stage} -> {:cont, {:ok, acc ++ [stage]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp parse_stages(_), do: {:error, "workflow stages must be a non-empty list"}

  defp parse_mode("quick"), do: {:ok, :quick}
  defp parse_mode("deep"), do: {:ok, :deep}
  defp parse_mode(:quick), do: {:ok, :quick}
  defp parse_mode(:deep), do: {:ok, :deep}
  defp parse_mode(_), do: {:error, "workflow default_mode must be quick or deep"}

  defp parse_execution_mode("flexible"), do: {:ok, :flexible}
  defp parse_execution_mode("quick"), do: {:ok, :quick}
  defp parse_execution_mode("deep"), do: {:ok, :deep}
  defp parse_execution_mode(:flexible), do: {:ok, :flexible}
  defp parse_execution_mode(:quick), do: {:ok, :quick}
  defp parse_execution_mode(:deep), do: {:ok, :deep}

  defp parse_execution_mode(_),
    do: {:error, "workflow execution_mode must be flexible, quick, or deep"}

  defp validate_stage_graph(stages) do
    types = Enum.map(stages, & &1.type)
    missing = @required_stage_order -- Enum.uniq(types)

    cond do
      missing != [] ->
        {:error, "workflow stages must include #{Enum.join(@required_stage_order, ", ")}"}

      monotonic_stage_types?(types) ->
        :ok

      true ->
        {:error,
         "workflow stages must follow prepare -> route -> fanout -> aggregate -> emit order"}
    end
  end

  defp monotonic_stage_types?(types) do
    ranks = Enum.map(types, &Map.fetch!(@stage_rank, &1))
    ranks == Enum.sort(ranks)
  end
end
