defmodule Thinktank.Pricing do
  @moduledoc false

  alias Thinktank.Builtin

  @per_million 1_000_000.0

  # Rates are USD per million tokens. They are derived from Pi's OpenRouter
  # session accounting for the builtin ThinkTank model roster.
  @rates %{
    "anthropic/claude-sonnet-4.6" => %{input: 3.0, output: 15.0, cache_read: 0.0},
    "mistralai/mistral-large-2512" => %{input: 0.5, output: 1.5},
    "x-ai/grok-4.1-fast" => %{input: 0.2, output: 0.5, cache_read: 0.05},
    "google/gemini-3-flash-preview" => %{input: 0.5, output: 3.0},
    "x-ai/grok-4.20" => %{input: 1.25, output: 10.0, cache_read: 0.125},
    "x-ai/grok-4.20-multi-agent" => %{input: 1.25, output: 10.0, cache_read: 0.125},
    "openai/gpt-5.4-mini" => %{input: 1.25, output: 10.0, cache_read: 0.125},
    "z-ai/glm-5-turbo" => %{input: 1.25, output: 10.0, cache_read: 0.125},
    "minimax/minimax-m2.7" => %{input: 1.25, output: 10.0},
    "inception/mercury-2" => %{input: 0.25, output: 0.75, cache_read: 0.025},
    "moonshotai/kimi-k2.5" => %{input: 0.41, output: 2.06, cache_read: 0.07},
    "xiaomi/mimo-v2-pro" => %{input: 1.25, output: 10.0},
    "openai/gpt-5.4" => %{input: 2.5, output: 15.0}
  }

  @spec rate_for(String.t()) :: map() | nil
  def rate_for(model) when is_binary(model), do: Map.get(@rates, model)

  @spec builtin_models_without_prices() :: [String.t()]
  def builtin_models_without_prices do
    Builtin.raw_config()
    |> Map.fetch!("agents")
    |> Map.values()
    |> Enum.map(& &1["model"])
    |> Enum.uniq()
    |> Enum.reject(&Map.has_key?(@rates, &1))
    |> Enum.sort()
  end

  @spec normalize_usage(String.t() | nil, map() | nil) :: map() | nil
  def normalize_usage(_model, nil), do: nil

  def normalize_usage(model, usage) when is_map(usage) do
    resolved_model = model || get_string(usage, "model") || "unknown"

    normalized = %{
      "model" => resolved_model,
      "input_tokens" => token_value(usage, ["input_tokens", "input"]),
      "output_tokens" => token_value(usage, ["output_tokens", "output"]),
      "cache_read_tokens" => token_value(usage, ["cache_read_tokens", "cacheRead"]),
      "cache_write_tokens" => token_value(usage, ["cache_write_tokens", "cacheWrite"])
    }

    normalized =
      Map.put(
        normalized,
        "total_tokens",
        total_tokens(usage, normalized)
      )

    case usage_cost(resolved_model, normalized) do
      {:ok, usd_cost} ->
        normalized
        |> Map.put("usd_cost", usd_cost)
        |> Map.put("pricing_gap", nil)

      {:error, gap} ->
        normalized
        |> Map.put("usd_cost", nil)
        |> Map.put("pricing_gap", gap)
    end
  end

  @spec usage_cost(String.t(), map()) :: {:ok, float()} | {:error, String.t()}
  def usage_cost(model, usage) when is_binary(model) and is_map(usage) do
    case rate_for(model) do
      nil ->
        {:error, "no price table entry for #{model}"}

      rates ->
        case missing_component_rate(model, usage, rates) do
          nil ->
            total =
              component_cost(usage["input_tokens"], rates[:input]) +
                component_cost(usage["output_tokens"], rates[:output]) +
                component_cost(usage["cache_read_tokens"], rates[:cache_read]) +
                component_cost(usage["cache_write_tokens"], rates[:cache_write])

            {:ok, round_usd(total)}

          component ->
            {:error, "missing #{component} rate for #{model}"}
        end
    end
  end

  defp missing_component_rate(model, usage, rates) do
    [
      {"input", usage["input_tokens"], rates[:input]},
      {"output", usage["output_tokens"], rates[:output]},
      {"cache_read", usage["cache_read_tokens"], rates[:cache_read]},
      {"cache_write", usage["cache_write_tokens"], rates[:cache_write]}
    ]
    |> Enum.find_value(fn {component, tokens, rate} ->
      if model != "unknown" and tokens > 0 and is_nil(rate), do: component
    end)
  end

  defp component_cost(_tokens, nil), do: 0.0
  defp component_cost(0, _rate), do: 0.0

  defp component_cost(tokens, rate) when is_integer(tokens) and is_number(rate) do
    tokens * rate / @per_million
  end

  defp total_tokens(usage, normalized) do
    case token_value(usage, ["total_tokens", "totalTokens"]) do
      0 ->
        normalized["input_tokens"] +
          normalized["output_tokens"] +
          normalized["cache_read_tokens"] +
          normalized["cache_write_tokens"]

      total ->
        total
    end
  end

  defp token_value(usage, keys) do
    Enum.find_value(keys, 0, fn key ->
      case Map.get(usage, key) do
        value when is_integer(value) and value >= 0 -> value
        value when is_float(value) and value >= 0 -> trunc(value)
        _ -> nil
      end
    end)
  end

  defp get_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp round_usd(value) when is_number(value), do: Float.round(value, 12)
end
