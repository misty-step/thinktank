defmodule Thinktank.Executor.AgenticTest do
  use ExUnit.Case, async: false

  alias Thinktank.{AgentSpec, Config, ProviderSpec, RunContract}
  alias Thinktank.Executor.Agentic

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  test "falls back to the default runner when runner option is nil" do
    tmp = unique_tmp_dir("thinktank-agentic")
    pi_path = Path.join(tmp, "pi")

    File.write!(
      pi_path,
      """
      #!/bin/sh
      echo "stub reviewer output"
      """
    )

    File.chmod!(pi_path, 0o755)

    original_path = System.get_env("PATH")
    System.put_env("PATH", "#{tmp}:#{original_path}")

    on_exit(fn -> System.put_env("PATH", original_path) end)

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      prompt: "{{input_text}}",
      tool_profile: "review",
      timeout_ms: 5_000
    }

    contract = %RunContract{
      workflow_id: "review/cerberus",
      workspace_root: tmp,
      input: %{input_text: "Review this"},
      artifact_dir: Path.join(tmp, "out"),
      adapter_context: %{},
      mode: :deep
    }

    config = %Config{
      providers: %{
        "openrouter" => %ProviderSpec{
          id: "openrouter",
          adapter: :openrouter,
          credential_env: "THINKTANK_OPENROUTER_API_KEY",
          defaults: %{}
        }
      },
      agents: %{},
      workflows: %{},
      sources: %{}
    }

    [result] = Agentic.run([agent], contract, %{}, config, runner: nil)

    assert result.status == :ok
    assert result.output =~ "stub reviewer output"
  end
end
