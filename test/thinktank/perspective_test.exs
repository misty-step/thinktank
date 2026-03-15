defmodule Thinktank.PerspectiveTest do
  use ExUnit.Case, async: true

  alias Thinktank.Perspective

  describe "from_map/1" do
    test "builds struct from complete map" do
      map = %{
        "role" => "security auditor",
        "model" => "anthropic/claude-sonnet-4-6",
        "system_prompt" => "You are a security auditor.",
        "priority" => 1
      }

      assert %Perspective{
               role: "security auditor",
               model: "anthropic/claude-sonnet-4-6",
               system_prompt: "You are a security auditor.",
               priority: 1
             } = Perspective.from_map(map)
    end

    test "returns nil for malformed map" do
      assert nil == Perspective.from_map(%{"missing" => "keys"})
    end

    test "returns nil when values have wrong types" do
      assert nil ==
               Perspective.from_map(%{
                 "role" => 123,
                 "model" => "some/model",
                 "system_prompt" => "ok"
               })
    end

    test "defaults priority to 0" do
      map = %{
        "role" => "analyst",
        "model" => "openai/gpt-4o",
        "system_prompt" => "Analyze."
      }

      assert %Perspective{priority: 0} = Perspective.from_map(map)
    end
  end
end
