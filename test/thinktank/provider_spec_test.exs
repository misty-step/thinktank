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
end
