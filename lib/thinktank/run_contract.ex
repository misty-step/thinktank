defmodule Thinktank.RunContract do
  @moduledoc """
  Provider-agnostic execution contract for a workflow run.
  """

  @enforce_keys [:workflow_id, :workspace_root, :input, :artifact_dir, :mode]
  defstruct [:workflow_id, :workspace_root, :input, :artifact_dir, :adapter_context, :mode]

  @type t :: %__MODULE__{
          workflow_id: String.t(),
          workspace_root: String.t(),
          input: map(),
          artifact_dir: String.t(),
          adapter_context: map(),
          mode: :quick | :deep
        }

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = contract) do
    %{
      "workflow_id" => contract.workflow_id,
      "workspace_root" => contract.workspace_root,
      "input" => contract.input,
      "artifact_dir" => contract.artifact_dir,
      "adapter_context" => contract.adapter_context || %{},
      "mode" => Atom.to_string(contract.mode)
    }
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with {:ok, workflow_id} <- fetch_string(map, "workflow_id"),
         {:ok, workspace_root} <- fetch_string(map, "workspace_root"),
         {:ok, artifact_dir} <- fetch_string(map, "artifact_dir"),
         {:ok, input} <- fetch_map(map, "input"),
         {:ok, adapter_context} <- fetch_optional_map(map, "adapter_context"),
         {:ok, mode} <- fetch_mode(map, "mode") do
      {:ok,
       %__MODULE__{
         workflow_id: workflow_id,
         workspace_root: workspace_root,
         input: input,
         artifact_dir: artifact_dir,
         adapter_context: adapter_context,
         mode: mode
       }}
    end
  end

  def from_map(_), do: {:error, "run contract must be a map"}

  defp fetch_string(map, key) do
    case Map.get(map, key) || Map.get(map, String.to_atom(key)) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "missing #{key}"}
    end
  end

  defp fetch_map(map, key) do
    case Map.get(map, key) || Map.get(map, String.to_atom(key)) do
      value when is_map(value) -> {:ok, value}
      _ -> {:error, "#{key} must be a map"}
    end
  end

  defp fetch_optional_map(map, key) do
    case Map.get(map, key) || Map.get(map, String.to_atom(key)) do
      nil -> {:ok, %{}}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, "#{key} must be a map"}
    end
  end

  defp fetch_mode(map, key) do
    case Map.get(map, key) || Map.get(map, String.to_atom(key)) do
      :quick -> {:ok, :quick}
      :deep -> {:ok, :deep}
      "quick" -> {:ok, :quick}
      "deep" -> {:ok, :deep}
      _ -> {:error, "mode must be quick or deep"}
    end
  end
end
