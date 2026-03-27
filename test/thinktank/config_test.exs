defmodule Thinktank.ConfigTest do
  use ExUnit.Case, async: true

  alias Thinktank.Config

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  describe "load/1" do
    test "loads built-in workflows and providers" do
      assert {:ok, config} = Config.load(cwd: File.cwd!(), user_config_path: "/tmp/does-not-exist.yml")

      assert Map.has_key?(config.providers, "openrouter")
      assert Map.has_key?(config.workflows, "research/default")
      assert Map.has_key?(config.workflows, "review/cerberus")
      assert Map.has_key?(config.agents, "trace")
    end

    test "repo config overrides user config and adds custom workflows" do
      tmp = unique_tmp_dir("thinktank-config")
      user_home = unique_tmp_dir("thinktank-user")
      user_cfg = Path.join([user_home, ".config", "thinktank", "config.yml"])
      repo_cfg = Path.join([tmp, ".thinktank", "config.yml"])

      File.mkdir_p!(Path.dirname(user_cfg))
      File.mkdir_p!(Path.dirname(repo_cfg))

      File.write!(
        user_cfg,
        """
        agents:
          trace:
            provider: openrouter
            model: user/model
            system_prompt: User override
        """
      )

      File.write!(
        repo_cfg,
        """
        agents:
          trace:
            provider: openrouter
            model: repo/model
            system_prompt: Repo override
        workflows:
          demo/static:
            description: Demo static workflow
            default_mode: quick
            input_schema:
              required:
                - input_text
            stages:
              - type: prepare
                kind: research_input
              - type: route
                kind: static_agents
                agents:
                  - trace
              - type: fanout
                kind: agents
              - type: aggregate
                kind: research_synthesis
              - type: emit
                kind: artifacts
        """
      )

      assert {:ok, config} = Config.load(cwd: tmp, user_home: user_home)
      assert config.agents["trace"].model == "repo/model"
      assert Map.has_key?(config.workflows, "demo/static")
    end

    test "returns an error when a static workflow references an unknown agent" do
      tmp = unique_tmp_dir("thinktank-invalid")
      repo_cfg = Path.join([tmp, ".thinktank", "config.yml"])
      File.mkdir_p!(Path.dirname(repo_cfg))

      File.write!(
        repo_cfg,
        """
        workflows:
          demo/invalid:
            description: Invalid workflow
            default_mode: quick
            stages:
              - type: prepare
                kind: research_input
              - type: route
                kind: static_agents
                agents:
                  - ghost
              - type: fanout
                kind: agents
              - type: emit
                kind: artifacts
        """
      )

      assert {:error, "workflow references unknown agent ghost"} = Config.load(cwd: tmp)
    end
  end
end
