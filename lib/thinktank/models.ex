defmodule Thinktank.Models do
  @moduledoc """
  Single source of truth for model metadata across all tiers.

  Three tiers — cheap, standard, premium — each with a set of
  dispatch models plus designated router and synthesis models.
  """

  @type tier :: :cheap | :standard | :premium

  @tiers %{
    cheap: %{
      models: [
        "qwen/qwen3.5-9b",
        "nvidia/nemotron-3-nano-30b-a3b",
        "bytedance-seed/seed-2.0-mini",
        "qwen/qwen3.5-flash-02-23"
      ],
      router: "qwen/qwen3.5-flash-02-23",
      synthesis: "qwen/qwen3.5-flash-02-23"
    },
    standard: %{
      models: [
        "deepseek/deepseek-v3.2",
        "x-ai/grok-4.1-fast",
        "inception/mercury-2",
        "google/gemini-3-flash-preview",
        "mistralai/mistral-large-2512",
        "anthropic/claude-haiku-4.5"
      ],
      router: "google/gemini-3-flash-preview",
      synthesis: "google/gemini-3-flash-preview"
    },
    premium: %{
      models: [
        "google/gemini-3.1-pro-preview",
        "openai/gpt-5.4",
        "anthropic/claude-sonnet-4.6",
        "x-ai/grok-4.20-beta",
        "anthropic/claude-opus-4.6"
      ],
      router: "google/gemini-3.1-pro-preview",
      synthesis: "google/gemini-3.1-pro-preview"
    }
  }

  @spec models_for_tier(tier()) :: [String.t()]
  def models_for_tier(tier), do: @tiers[tier].models

  @spec tier_for_model(String.t()) :: tier() | nil
  def tier_for_model(model_id) do
    Enum.find_value(@tiers, fn {tier, %{models: models}} ->
      if model_id in models, do: tier
    end)
  end

  @spec router_model(tier()) :: String.t()
  def router_model(tier), do: @tiers[tier].router

  @spec synthesis_model(tier()) :: String.t()
  def synthesis_model(tier), do: @tiers[tier].synthesis

  @spec all_model_ids() :: [String.t()]
  def all_model_ids do
    @tiers |> Map.values() |> Enum.flat_map(& &1.models) |> Enum.uniq()
  end
end
