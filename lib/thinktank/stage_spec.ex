defmodule Thinktank.StageSpec do
  @moduledoc """
  Typed stage definition for workflow execution.
  """

  @valid_types ~w(prepare route fanout aggregate emit)
  @valid_kinds %{
    prepare: MapSet.new(["research_input", "review_diff"]),
    route: MapSet.new(["research_router", "cerberus_review", "static_agents"]),
    fanout: MapSet.new(["agents"]),
    aggregate: MapSet.new(["research_synthesis", "cerberus_verdict"]),
    emit: MapSet.new(["artifacts"])
  }

  @enforce_keys [:name, :type, :kind]
  defstruct [:name, :type, :kind, when: true, retry: 0, concurrency: nil, options: %{}]

  @type t :: %__MODULE__{
          name: String.t(),
          type: atom(),
          kind: String.t(),
          when: boolean() | String.t(),
          retry: non_neg_integer(),
          concurrency: pos_integer() | nil,
          options: map()
        }

  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(%{} = raw) do
    with {:ok, type} <- parse_type(raw["type"]),
         {:ok, kind} <- parse_kind(type, raw["kind"]) do
      {:ok,
       %__MODULE__{
         name: stage_name(raw, kind),
         type: type,
         kind: kind,
         when: Map.get(raw, "when", true),
         retry: non_neg_int(raw["retry"], 0),
         concurrency: pos_int_or_nil(raw["concurrency"]),
         options: Map.drop(raw, ["name", "type", "kind", "when", "retry", "concurrency"])
       }}
    end
  end

  def from_map(_), do: {:error, "stage must be a map"}

  defp stage_name(raw, kind) do
    case raw["name"] do
      value when is_binary(value) and value != "" -> value
      _ -> kind
    end
  end

  defp parse_type(type) when type in @valid_types, do: {:ok, String.to_atom(type)}

  defp parse_type(type) when is_atom(type) do
    atom_string = Atom.to_string(type)

    if atom_string in @valid_types,
      do: {:ok, type},
      else: {:error, "stage type must be one of #{@valid_types |> Enum.join(", ")}"}
  end

  defp parse_type(_), do: {:error, "stage type must be one of #{@valid_types |> Enum.join(", ")}"}

  defp parse_kind(_type, kind) when not (is_binary(kind) and kind != ""),
    do: {:error, "stage kind is required"}

  defp parse_kind(type, kind) do
    if MapSet.member?(Map.fetch!(@valid_kinds, type), kind) do
      {:ok, kind}
    else
      {:error,
       "stage kind #{kind} is invalid for #{type}; expected one of #{supported_kinds(type) |> Enum.join(", ")}"}
    end
  end

  defp supported_kinds(type) do
    type
    |> then(&Map.fetch!(@valid_kinds, &1))
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp non_neg_int(value, _default) when is_integer(value) and value >= 0, do: value

  defp non_neg_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> default
    end
  end

  defp non_neg_int(_, default), do: default

  defp pos_int_or_nil(value) when is_integer(value) and value > 0, do: value

  defp pos_int_or_nil(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp pos_int_or_nil(_), do: nil
end
