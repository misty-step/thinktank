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
    assert Map.has_key?(config.benches, "research/quick")
    assert Map.has_key?(config.benches, "research/default")
    assert Map.has_key?(config.benches, "review/default")
    assert Map.has_key?(config.agents, "marshal")
    assert Map.has_key?(config.agents, "trace")
    assert config.benches["research/quick"].kind == :research
    assert config.benches["research/default"].kind == :research
    assert config.benches["research/quick"].structured_findings == false
    assert config.benches["research/default"].structured_findings == true
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

  test "agent defaults from config apply to agents that omit thinking_level" do
    tmp = unique_tmp_dir("thinktank-config-defaults")
    repo_cfg = Path.join([tmp, ".thinktank", "config.yml"])
    File.mkdir_p!(Path.dirname(repo_cfg))

    File.write!(
      repo_cfg,
      """
      defaults:
        agent:
          thinking_level: low
      agents:
        custom:
          provider: openrouter
          model: repo/model
          system_prompt: Repo override
      """
    )

    assert {:ok, config} = Config.load(cwd: tmp, trust_repo_config: true)
    assert config.agents["custom"].thinking_level == "low"
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

  test "user_config_dir honors a provided home directory" do
    assert Config.user_config_dir(user_home: "/tmp/example-home") ==
             "/tmp/example-home/.config/thinktank"
  end

  test "trusted repo config must contain a YAML mapping" do
    tmp = unique_tmp_dir("thinktank-config-non-map")
    repo_cfg = Path.join([tmp, ".thinktank", "config.yml"])
    File.mkdir_p!(Path.dirname(repo_cfg))
    File.write!(repo_cfg, "- invalid\n")

    assert Config.load(cwd: tmp, trust_repo_config: true) ==
             {:error, "config file #{repo_cfg} must contain a YAML mapping"}
  end

  test "returns an error when an agent references an unknown provider" do
    tmp = unique_tmp_dir("thinktank-config-provider-ref")
    repo_cfg = Path.join([tmp, ".thinktank", "config.yml"])
    File.mkdir_p!(Path.dirname(repo_cfg))

    File.write!(
      repo_cfg,
      """
      agents:
        trace:
          provider: missing
          model: openai/gpt-5.4
          system_prompt: Repo override
      """
    )

    assert {:error, "agent trace references unknown provider missing"} =
             Config.load(cwd: tmp, trust_repo_config: true)
  end

  test "returns an error when a planner reference is invalid" do
    tmp = unique_tmp_dir("thinktank-config-invalid-planner")
    repo_cfg = Path.join([tmp, ".thinktank", "config.yml"])
    File.mkdir_p!(Path.dirname(repo_cfg))

    File.write!(
      repo_cfg,
      """
      benches:
        demo/review:
          kind: review
          description: Invalid planner
          agents:
            - trace
          planner: 123
      """
    )

    assert {:error, "bench demo/review: bench optional string fields must be strings"} =
             Config.load(cwd: tmp, trust_repo_config: true)
  end
end
