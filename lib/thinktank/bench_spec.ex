defmodule Thinktank.BenchSpec do
  @moduledoc """
  Typed bench configuration describing a named set of Pi agents to launch.
  """

  @enforce_keys [:id, :description, :agents]
  defstruct [
    :id,
    :description,
    agents: [],
    synthesizer: nil,
    concurrency: nil,
    default_task: nil
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          description: String.t(),
          agents: [String.t()],
          synthesizer: String.t() | nil,
          concurrency: pos_integer() | nil,
          default_task: String.t() | nil
        }

  @spec from_pair(String.t(), map()) :: {:ok, t()} | {:error, String.t()}
  def from_pair(id, %{} = raw) when is_binary(id) do
    with {:ok, description} <- require_string(raw, "description"),
         {:ok, agents} <- require_agent_names(raw["agents"]),
         {:ok, synthesizer} <- optional_string(raw["synthesizer"]),
         {:ok, concurrency} <- parse_concurrency(raw["concurrency"]),
         {:ok, default_task} <- optional_string(raw["default_task"]) do
      {:ok,
       %__MODULE__{
         id: id,
         description: description,
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
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "bench #{key} is required"}
    end
  end

  defp require_agent_names(agent_names) when is_list(agent_names) do
    names =
      agent_names
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if names == [] do
      {:error, "bench agents must be a non-empty list of agent names"}
    else
      {:ok, names}
    end
  end

  defp require_agent_names(_),
    do: {:error, "bench agents must be a non-empty list of agent names"}

  defp optional_string(nil), do: {:ok, nil}
  defp optional_string(value) when is_binary(value) and value != "", do: {:ok, value}
  defp optional_string(""), do: {:ok, nil}
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
end
