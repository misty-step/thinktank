defmodule Thinktank.ProviderSpecTest do
  use ExUnit.Case, async: true

  alias Thinktank.ProviderSpec

  test "parses supported adapters without creating new atoms" do
    assert {:ok, spec} =
             ProviderSpec.from_pair("openrouter", %{
               "adapter" => "openrouter",
               "credential_env" => "THINKTANK_OPENROUTER_API_KEY"
             })

    assert spec.adapter == :openrouter
  end

  test "rejects unsupported adapters" do
    assert {:error, "provider adapter must be one of openrouter"} =
             ProviderSpec.from_pair("custom", %{
               "adapter" => "custom",
               "credential_env" => "TOKEN"
             })
  end

  test "accepts atom adapters and preserves defaults" do
    assert {:ok, spec} =
             ProviderSpec.from_pair("openrouter", %{
               "adapter" => :openrouter,
               "credential_env" => "THINKTANK_OPENROUTER_API_KEY",
               "defaults" => %{"fallback_env" => "OPENROUTER_API_KEY"}
             })

    assert spec.defaults == %{"fallback_env" => "OPENROUTER_API_KEY"}
  end

  test "rejects non-map providers and missing required fields" do
    assert {:error, "provider openrouter must be a map"} =
             ProviderSpec.from_pair("openrouter", nil)

    assert {:error, "provider adapter is required"} =
             ProviderSpec.from_pair("openrouter", %{
               "credential_env" => "THINKTANK_OPENROUTER_API_KEY"
             })

    assert {:error, "provider credential_env is required"} =
             ProviderSpec.from_pair("openrouter", %{
               "adapter" => "openrouter"
             })
  end
end
