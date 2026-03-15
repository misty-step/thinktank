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
