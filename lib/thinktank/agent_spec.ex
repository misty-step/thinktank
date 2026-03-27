defmodule Thinktank.AgentSpec do
  @moduledoc """
  Typed agent configuration for routed or user-defined workflow agents.
  """

  @enforce_keys [:name, :provider, :model, :system_prompt]
  defstruct [
    :name,
    :provider,
    :model,
    :system_prompt,
    prompt: "{{input_text}}",
    tool_profile: "default",
    output_format: "text",
    thinking_level: "medium",
    retries: 0,
    timeout_ms: :timer.minutes(5),
    tools: nil,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          provider: String.t(),
          model: String.t(),
          system_prompt: String.t(),
          prompt: String.t(),
          tool_profile: String.t(),
          output_format: String.t(),
          thinking_level: String.t(),
          retries: non_neg_integer(),
          timeout_ms: non_neg_integer(),
          tools: [String.t()] | nil,
          metadata: map()
        }

  @spec from_pair(String.t(), map()) :: {:ok, t()} | {:error, String.t()}
  def from_pair(name, %{} = raw) when is_binary(name) do
    with {:ok, provider} <- require_string(raw, "provider"),
         {:ok, model} <- require_string(raw, "model"),
         :ok <- validate_model(model),
         {:ok, system_prompt} <- require_string(raw, "system_prompt"),
         {:ok, output_format} <- parse_output_format(raw["output_format"]),
         {:ok, retries} <- parse_non_neg_int("retries", raw["retries"], 0),
         {:ok, timeout_ms} <-
           parse_non_neg_int("timeout_ms", raw["timeout_ms"] || raw["timeout"], :timer.minutes(5)) do
      {:ok,
       %__MODULE__{
         name: name,
         provider: provider,
         model: model,
         system_prompt: system_prompt,
         prompt: string_or_default(raw["prompt"], "{{input_text}}"),
         tool_profile: string_or_default(raw["tool_profile"], "default"),
         output_format: output_format,
         thinking_level: string_or_default(raw["thinking_level"], "medium"),
         retries: retries,
         timeout_ms: timeout_ms,
         tools: parse_tools(raw["tools"]),
         metadata: Map.get(raw, "metadata", %{})
       }}
    end
  end

  def from_pair(name, _raw), do: {:error, "agent #{name} must be a map"}

  defp require_string(raw, key) do
    case raw[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "agent #{key} is required"}
    end
  end

  defp string_or_default(value, _default) when is_binary(value) and value != "", do: value
  defp string_or_default(_, default), do: default

  defp validate_model(model) do
    if String.match?(model, ~r/\s/) do
      {:error, "agent model must not contain whitespace"}
    else
      :ok
    end
  end

  defp parse_non_neg_int(_field, nil, default), do: {:ok, default}

  defp parse_non_neg_int(_field, value, _default) when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp parse_non_neg_int(field, value, _default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> {:error, "agent #{field} must be a non-negative integer"}
    end
  end

  defp parse_non_neg_int(field, _value, _default),
    do: {:error, "agent #{field} must be a non-negative integer"}

  defp parse_tools(nil), do: nil
  defp parse_tools(tools) when is_list(tools), do: Enum.filter(tools, &is_binary/1)

  defp parse_tools(tools) when is_binary(tools),
    do: tools |> String.split(",") |> Enum.map(&String.trim/1)

  defp parse_tools(_), do: nil

  defp parse_output_format(nil), do: {:ok, "text"}
  defp parse_output_format("text"), do: {:ok, "text"}
  defp parse_output_format("structured_verdict"), do: {:ok, "structured_verdict"}

  defp parse_output_format(_),
    do: {:error, "agent output_format must be text or structured_verdict"}
end
