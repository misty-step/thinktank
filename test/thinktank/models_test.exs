defmodule Thinktank.ModelsTest do
  use ExUnit.Case, async: true

  alias Thinktank.Models

  @tiers [:cheap, :standard, :premium]

  describe "models_for_tier/1" do
    test "returns correct models for cheap tier" do
      models = Models.models_for_tier(:cheap)
      assert "qwen/qwen3.5-9b" in models
      assert "nvidia/nemotron-3-nano-30b-a3b" in models
      assert "bytedance-seed/seed-2.0-mini" in models
      assert "qwen/qwen3.5-flash-02-23" in models
      assert length(models) == 4
    end

    test "returns correct models for standard tier" do
      models = Models.models_for_tier(:standard)
      assert "deepseek/deepseek-v3.2" in models
      assert "x-ai/grok-4.1-fast" in models
      assert "inception/mercury-2" in models
      assert "google/gemini-3-flash-preview" in models
      assert "mistralai/mistral-large-2512" in models
      assert "anthropic/claude-haiku-4.5" in models
      assert length(models) == 6
    end

    test "returns correct models for premium tier" do
      models = Models.models_for_tier(:premium)
      assert "google/gemini-3.1-pro-preview" in models
      assert "openai/gpt-5.4" in models
      assert "anthropic/claude-sonnet-4.6" in models
      assert "x-ai/grok-4.20-beta" in models
      assert "anthropic/claude-opus-4.6" in models
      assert length(models) == 5
    end
  end

  describe "tier_for_model/1" do
    test "round-trips every model back to its tier" do
      for tier <- @tiers, model <- Models.models_for_tier(tier) do
        assert Models.tier_for_model(model) == tier,
               "expected #{model} to resolve to #{tier}"
      end
    end

    test "returns nil for unknown model" do
      assert Models.tier_for_model("unknown/nonexistent-model") == nil
    end
  end

  describe "router_model/1" do
    test "returns valid model ID per tier" do
      assert Models.router_model(:cheap) == "qwen/qwen3.5-flash-02-23"
      assert Models.router_model(:standard) == "google/gemini-3-flash-preview"
      assert Models.router_model(:premium) == "google/gemini-3.1-pro-preview"
    end

    test "router model exists in its tier" do
      for tier <- @tiers do
        assert Models.router_model(tier) in Models.models_for_tier(tier)
      end
    end
  end

  describe "synthesis_model/1" do
    test "returns valid model ID per tier" do
      assert Models.synthesis_model(:cheap) == "qwen/qwen3.5-flash-02-23"
      assert Models.synthesis_model(:standard) == "google/gemini-3-flash-preview"
      assert Models.synthesis_model(:premium) == "google/gemini-3.1-pro-preview"
    end

    test "synthesis model exists in its tier" do
      for tier <- @tiers do
        assert Models.synthesis_model(tier) in Models.models_for_tier(tier)
      end
    end
  end

  describe "all_model_ids/0" do
    test "contains all models from all tiers" do
      all = Models.all_model_ids()

      for tier <- @tiers, model <- Models.models_for_tier(tier) do
        assert model in all, "expected #{model} from #{tier} in all_model_ids"
      end
    end

    test "has no duplicates" do
      all = Models.all_model_ids()
      assert length(all) == length(Enum.uniq(all))
    end

    test "total count matches sum of tier counts" do
      expected = Enum.sum(for tier <- @tiers, do: length(Models.models_for_tier(tier)))
      assert length(Models.all_model_ids()) == expected
    end
  end
end
