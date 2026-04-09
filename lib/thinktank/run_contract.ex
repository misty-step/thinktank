defmodule Thinktank.RunContract do
  @moduledoc """
  Provider-agnostic execution contract for a bench run.
  """

  @enforce_keys [:bench_id, :workspace_root, :input, :artifact_dir]
  defstruct [:bench_id, :workspace_root, :input, :artifact_dir, adapter_context: %{}]

  @type t :: %__MODULE__{
          bench_id: String.t(),
          workspace_root: String.t(),
          input: map(),
          artifact_dir: String.t(),
          adapter_context: map()
        }

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = contract) do
    %{
      "bench_id" => contract.bench_id,
      "workspace_root" => contract.workspace_root,
      "input" => contract.input,
      "artifact_dir" => contract.artifact_dir,
      "adapter_context" => contract.adapter_context || %{}
    }
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with {:ok, bench_id} <- fetch_string(map, "bench_id"),
         {:ok, workspace_root} <- fetch_string(map, "workspace_root"),
         {:ok, artifact_dir} <- fetch_string(map, "artifact_dir"),
         {:ok, input} <- fetch_map(map, "input"),
         {:ok, adapter_context} <- fetch_optional_map(map, "adapter_context") do
      {:ok,
       %__MODULE__{
         bench_id: bench_id,
         workspace_root: workspace_root,
         input: input,
         artifact_dir: artifact_dir,
         adapter_context: adapter_context
       }}
    end
  end

  def from_map(_), do: {:error, "run contract must be a map"}

  defp fetch_string(map, key) do
    case fetch_value(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "missing #{key}"}
    end
  end

  defp fetch_map(map, key) do
    case fetch_value(map, key) do
      value when is_map(value) -> {:ok, value}
      _ -> {:error, "#{key} must be a map"}
    end
  end

  defp fetch_optional_map(map, key) do
    case fetch_value(map, key) do
      nil -> {:ok, %{}}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, "#{key} must be a map"}
    end
  end

  defp fetch_value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> fetch_atom_key(map, key)
    end
  end

  defp fetch_atom_key(map, key) do
    key
    |> String.to_existing_atom()
    |> then(&Map.get(map, &1))
  rescue
    ArgumentError -> nil
  end
end
