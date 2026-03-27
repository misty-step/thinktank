defmodule Thinktank.StageSpec do
  @moduledoc """
  Typed stage definition for workflow execution.
  """

  @valid_types ~w(prepare route fanout aggregate emit)

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
         {:ok, kind} <- require_kind(raw["kind"]) do
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
    if atom_string in @valid_types, do: {:ok, type}, else: {:error, "stage type must be one of #{@valid_types |> Enum.join(", ")}"}
  end

  defp parse_type(_), do: {:error, "stage type must be one of #{@valid_types |> Enum.join(", ")}"}

  defp require_kind(kind) when is_binary(kind) and kind != "", do: {:ok, kind}
  defp require_kind(_), do: {:error, "stage kind is required"}

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
