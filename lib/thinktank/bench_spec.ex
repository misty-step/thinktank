defmodule Thinktank.BenchSpec do
  @moduledoc """
  Typed bench configuration describing a named set of Pi agents to launch.
  """

  @enforce_keys [:id, :description, :agents]
  defstruct [
    :id,
    :description,
    kind: :default,
    agents: [],
    synthesizer: nil,
    concurrency: nil,
    default_task: nil
  ]

  @type kind :: :default | :research | :review

  @type t :: %__MODULE__{
          id: String.t(),
          description: String.t(),
          kind: kind(),
          agents: [String.t()],
          synthesizer: String.t() | nil,
          concurrency: pos_integer() | nil,
          default_task: String.t() | nil
        }

  @spec from_pair(String.t(), map()) :: {:ok, t()} | {:error, String.t()}
  def from_pair(id, %{} = raw) when is_binary(id) do
    with {:ok, description} <- require_string(raw, "description"),
         {:ok, kind} <- parse_kind(raw["kind"]),
         {:ok, agents} <- require_agent_names(raw["agents"]),
         {:ok, synthesizer} <- optional_string(raw["synthesizer"]),
         {:ok, concurrency} <- parse_concurrency(raw["concurrency"]),
         {:ok, default_task} <- optional_string(raw["default_task"]) do
      {:ok,
       %__MODULE__{
         id: id,
         description: description,
         kind: kind,
         agents: agents,
         synthesizer: synthesizer,
         concurrency: concurrency,
         default_task: default_task
       }}
    end
  end

  def from_pair(id, _raw), do: {:error, "bench #{id} must be a map"}

  defp require_string(raw, key) do
    case raw[key] do
      value when is_binary(value) ->
        present_string(value, "bench #{key} is required")

      _ ->
        {:error, "bench #{key} is required"}
    end
  end

  defp require_agent_names(agent_names) when is_list(agent_names) do
    case collect_agent_names(agent_names) do
      {:ok, []} -> {:error, "bench agents must be a non-empty list of agent names"}
      {:ok, names} -> {:ok, names}
      :invalid -> {:error, "bench agents must be a non-empty list of agent names"}
    end
  end

  defp require_agent_names(_),
    do: {:error, "bench agents must be a non-empty list of agent names"}

  defp parse_kind(nil), do: {:ok, :default}
  defp parse_kind(""), do: {:ok, :default}
  defp parse_kind("default"), do: {:ok, :default}
  defp parse_kind("research"), do: {:ok, :research}
  defp parse_kind("review"), do: {:ok, :review}
  defp parse_kind(_), do: {:error, "bench kind must be one of: default, research, review"}

  defp optional_string(nil), do: {:ok, nil}

  defp optional_string(value) when is_binary(value),
    do: present_string(value, invalid_optional_string())

  defp optional_string(_), do: {:error, "bench optional string fields must be strings"}

  defp parse_concurrency(nil), do: {:ok, nil}
  defp parse_concurrency(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_concurrency(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, "bench concurrency must be a positive integer"}
    end
  end

  defp parse_concurrency(_), do: {:error, "bench concurrency must be a positive integer"}

  defp present_string(value, error) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: error, else: {:ok, trimmed}
  end

  defp present_string(_value, error), do: error

  defp invalid_optional_string, do: {:error, "bench optional string fields must be strings"}

  defp collect_agent_names(agent_names) do
    agent_names
    |> Enum.reduce_while([], fn entry, acc ->
      case present_string(entry, :invalid) do
        {:ok, name} -> {:cont, [name | acc]}
        :invalid -> {:halt, :invalid}
      end
    end)
    |> case do
      :invalid -> :invalid
      names -> {:ok, Enum.reverse(names)}
    end
  end
end
