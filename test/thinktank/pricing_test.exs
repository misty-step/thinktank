defmodule Thinktank.PricingTest do
  use ExUnit.Case, async: true

  alias Thinktank.Pricing

  test "normalizes known-model usage and computes usd cost" do
    usage =
      Pricing.normalize_usage("openai/gpt-5.4-mini", %{
        "input" => 447,
        "output" => 12,
        "cacheRead" => 1024,
        "cacheWrite" => 0,
        "totalTokens" => 1483
      })

    assert usage["model"] == "openai/gpt-5.4-mini"
    assert usage["input_tokens"] == 447
    assert usage["output_tokens"] == 12
    assert usage["cache_read_tokens"] == 1024
    assert usage["cache_write_tokens"] == 0
    assert usage["total_tokens"] == 1483
    assert usage["pricing_gap"] == nil
    assert_in_delta usage["usd_cost"], 0.00046605, 1.0e-12
  end

  test "returns a pricing gap when the model is unknown" do
    usage =
      Pricing.normalize_usage("unknown/model", %{
        "input" => 10,
        "output" => 5
      })

    assert usage["usd_cost"] == nil
    assert usage["pricing_gap"] == "no price table entry for unknown/model"
  end

  test "returns a pricing gap when a token component has no configured rate" do
    usage =
      Pricing.normalize_usage("openai/gpt-5.4-mini", %{
        "input" => 10,
        "cacheWrite" => 5
      })

    assert usage["usd_cost"] == nil
    assert usage["pricing_gap"] == "missing cache_write rate for openai/gpt-5.4-mini"
  end

  test "builtin models all have price table entries" do
    assert Pricing.builtin_models_without_prices() == []
  end
end
