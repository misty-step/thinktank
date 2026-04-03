defmodule Thinktank.ConfigTest do
  use ExUnit.Case, async: true

  alias Thinktank.Config

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  test "loads built-in benches and providers" do
    missing_path = Path.join(unique_tmp_dir("thinktank-config-missing"), "config.yml")

    assert {:ok, config} =
             Config.load(cwd: File.cwd!(), user_config_path: missing_path)

    assert Map.has_key?(config.providers, "openrouter")
    assert Map.has_key?(config.benches, "research/default")
    assert Map.has_key?(config.benches, "review/default")
    assert Map.has_key?(config.agents, "marshal")
    assert Map.has_key?(config.agents, "trace")
    assert config.benches["research/default"].kind == :research
    assert config.benches["review/default"].kind == :review
    assert config.benches["review/default"].planner == "marshal"
  end

  test "repo config overrides user config and adds benches when trusted" do
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
      benches:
        demo/custom:
          kind: review
          description: Demo custom bench
          agents:
            - trace
      """
    )

    assert {:ok, config} = Config.load(cwd: tmp, user_home: user_home, trust_repo_config: true)
    assert config.agents["trace"].model == "repo/model"
    assert Map.has_key?(config.benches, "demo/custom")
    assert config.benches["demo/custom"].kind == :review
  end

  test "untrusted repo config is skipped before parsing" do
    tmp = unique_tmp_dir("thinktank-untrusted-malformed")
    repo_cfg = Path.join([tmp, ".thinktank", "config.yml"])
    File.mkdir_p!(Path.dirname(repo_cfg))
    File.write!(repo_cfg, ":\n  - broken")

    assert {:ok, config} = Config.load(cwd: tmp)
    assert Map.has_key?(config.benches, "research/default")
  end

  test "returns an error when a bench references an unknown agent" do
    tmp = unique_tmp_dir("thinktank-invalid")
    repo_cfg = Path.join([tmp, ".thinktank", "config.yml"])
    File.mkdir_p!(Path.dirname(repo_cfg))

    File.write!(
      repo_cfg,
      """
      benches:
        demo/invalid:
          description: Invalid bench
          agents:
            - ghost
      """
    )

    assert {:error, "bench demo/invalid: bench references unknown agent ghost"} =
             Config.load(cwd: tmp, trust_repo_config: true)
  end

  test "does not expose legacy workflow aliases" do
    assert Code.ensure_loaded?(Config)
    assert function_exported?(Config, :bench, 2)
    assert function_exported?(Config, :list_benches, 1)
    refute function_exported?(Config, :workflow, 2)
    refute function_exported?(Config, :list_workflows, 1)
  end
end
