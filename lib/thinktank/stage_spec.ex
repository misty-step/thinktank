defmodule Thinktank.StageSpec do
  @moduledoc """
  Typed stage definition for the constrained built-in workflow stage registry.
  """

  alias Thinktank.StageRegistry

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
         {:ok, kind} <- parse_kind(type, raw["kind"]),
         {:ok, when_value} <- parse_when(Map.get(raw, "when", true)),
         {:ok, retry} <- parse_non_neg_int("retry", raw["retry"], 0),
         {:ok, concurrency} <- parse_pos_int_or_nil("concurrency", raw["concurrency"]) do
      {:ok,
       %__MODULE__{
         name: stage_name(raw, kind),
         type: type,
         kind: kind,
         when: when_value,
         retry: retry,
         concurrency: concurrency,
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
    if kind in supported_kinds(type) do
      {:ok, kind}
    else
      {:error,
       "stage kind #{kind} is invalid for #{type}; expected one of #{supported_kinds(type) |> Enum.join(", ")}"}
    end
  end

  defp supported_kinds(type), do: StageRegistry.supported_kinds(type)

  defp parse_when(value) when is_boolean(value) or is_nil(value), do: {:ok, value}
  defp parse_when(value) when is_binary(value) and value != "", do: {:ok, value}

  defp parse_when(_),
    do: {:error, "stage when must be true, false, null, or a context path string"}

  defp parse_non_neg_int(_field, nil, default), do: {:ok, default}

  defp parse_non_neg_int(_field, value, _default) when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp parse_non_neg_int(field, value, _default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> {:error, "stage #{field} must be a non-negative integer"}
    end
  end

  defp parse_non_neg_int(field, _value, _default),
    do: {:error, "stage #{field} must be a non-negative integer"}

  defp parse_pos_int_or_nil(_field, nil), do: {:ok, nil}
  defp parse_pos_int_or_nil(_field, value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_pos_int_or_nil(field, value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, "stage #{field} must be a positive integer"}
    end
  end

  defp parse_pos_int_or_nil(field, _value),
    do: {:error, "stage #{field} must be a positive integer"}
end
