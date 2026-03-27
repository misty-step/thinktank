defmodule Thinktank.AgentSpecTest do
  use ExUnit.Case, async: true

  alias Thinktank.AgentSpec

  test "parses explicit tools and timeout" do
    assert {:ok, spec} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "openai/gpt-5.4",
               "system_prompt" => "You are a reviewer.",
               "tools" => "read,bash,grep",
               "timeout_ms" => "12000"
             })

    assert spec.tools == ["read", "bash", "grep"]
    assert spec.timeout_ms == 12_000
  end

  test "requires core fields" do
    assert {:error, "agent provider is required"} =
             AgentSpec.from_pair("trace", %{"model" => "x", "system_prompt" => "y"})
  end

  test "filters malformed tool entries from lists" do
    assert {:ok, spec} =
             AgentSpec.from_pair("trace", %{
               "provider" => "openrouter",
               "model" => "openai/gpt-5.4",
               "system_prompt" => "You are a reviewer.",
               "tools" => ["read", 123, "grep"]
             })

    assert spec.tools == ["read", "grep"]
  end
end
