defmodule Thinktank.ModelsTest do
  use ExUnit.Case, async: true

  alias Thinktank.Models

  @tiers [:cheap, :standard, :premium]

  describe "models_for_tier/1" do
    test "every tier returns a non-empty list of model ID strings" do
      for tier <- @tiers do
        models = Models.models_for_tier(tier)
        assert is_list(models) and models != [], "#{tier} tier must have models"
        assert Enum.all?(models, &is_binary/1), "#{tier} models must be strings"

        assert Enum.all?(models, &String.contains?(&1, "/")),
               "#{tier} models must be provider/name format"
      end
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
    test "router model exists in its own tier" do
      for tier <- @tiers do
        model = Models.router_model(tier)
        assert is_binary(model)
        assert model in Models.models_for_tier(tier)
      end
    end
  end

  describe "synthesis_model/1" do
    test "synthesis model exists in its own tier" do
      for tier <- @tiers do
        model = Models.synthesis_model(tier)
        assert is_binary(model)
        assert model in Models.models_for_tier(tier)
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
