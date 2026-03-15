defmodule Thinktank.AgentConfigTest do
  use ExUnit.Case, async: true

  @agent_config_dir Path.join(File.cwd!(), "agent_config")

  describe "agent config directory structure" do
    test "settings.json exists with no skills configured" do
      path = Path.join(@agent_config_dir, "settings.json")
      assert File.exists?(path), "agent_config/settings.json missing"

      settings = path |> File.read!() |> Jason.decode!()
      refute Map.has_key?(settings, "skills"), "settings.json must not configure skills"
    end

    test "AGENTS.md exists with minimal research agent instructions" do
      path = Path.join(@agent_config_dir, "AGENTS.md")
      assert File.exists?(path), "agent_config/AGENTS.md missing"

      content = File.read!(path)
      assert content =~ "research agent", "AGENTS.md should describe a research agent"
    end

    test "web-search extension is present" do
      index = Path.join(@agent_config_dir, "extensions/web-search/index.ts")
      assert File.exists?(index), "web-search extension index.ts missing"
    end

    test "no heavy extensions present" do
      extensions_dir = Path.join(@agent_config_dir, "extensions")
      assert File.dir?(extensions_dir)

      heavy = ["orchestration", "subagent", "guardrails", "bootstrap", "handoff"]

      present =
        File.ls!(extensions_dir)
        |> Enum.filter(&(&1 in heavy))

      assert present == [], "heavy extensions found: #{inspect(present)}"
    end
  end
end
