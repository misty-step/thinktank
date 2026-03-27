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

  test "uses an isolated pi home per agent run" do
    tmp = unique_tmp_dir("thinktank-agentic-home")
    test_pid = self()

    agent = %AgentSpec{
      name: "Trace Guard",
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

    runner = fn _cmd, _args, opts ->
      env = Keyword.fetch!(opts, :env)
      pi_home = env |> Enum.into(%{}) |> Map.fetch!("PI_CODING_AGENT_DIR")
      send(test_pid, {:pi_home, pi_home})
      {"stub reviewer output", 0}
    end

    [result] = Agentic.run([agent], contract, %{}, config, runner: runner)

    assert result.status == :ok

    assert_receive {:pi_home, pi_home}
    assert pi_home == Path.join(contract.artifact_dir, "pi-home/trace-guard")
    assert File.dir?(pi_home)
  end

  test "passes pi arguments without interpolating tools into shell code" do
    tmp = unique_tmp_dir("thinktank-agentic-args")
    test_pid = self()

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      prompt: "{{input_text}}",
      tools: ["read", "$(touch /tmp/pwned)"],
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

    runner = fn cmd, args, _opts ->
      send(test_pid, {:command, cmd, args})
      {"ok", 0}
    end

    [result] = Agentic.run([agent], contract, %{}, config, runner: runner)

    assert result.status == :ok

    assert_receive {:command, "sh", args}
    assert Enum.at(args, 1) == "exec < /dev/null; exec \"$@\""
    assert Enum.member?(args, "pi")
    assert Enum.member?(args, "--tools")
    assert Enum.member?(args, "read,$(touch /tmp/pwned)")
  end

  test "honors fanout concurrency" do
    tmp = unique_tmp_dir("thinktank-agentic-concurrency")
    test_pid = self()
    tracker = :ets.new(:agentic_concurrency, [:public, :set])
    :ets.insert(tracker, {:running, 0})
    :ets.insert(tracker, {:max, 0})

    agents =
      for name <- ~w(trace guard atlas) do
        %AgentSpec{
          name: name,
          provider: "openrouter",
          model: "openai/gpt-5.4",
          system_prompt: "You are a reviewer.",
          prompt: "{{input_text}}",
          tool_profile: "review",
          timeout_ms: 5_000
        }
      end

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

    runner = fn _cmd, _args, _opts ->
      running = :ets.update_counter(tracker, :running, {2, 1})
      update_max(tracker, running)
      send(test_pid, :started)
      Process.sleep(50)
      :ets.update_counter(tracker, :running, {2, -1})
      {"stub reviewer output", 0}
    end

    results = Agentic.run(agents, contract, %{}, config, runner: runner, concurrency: 1)

    assert Enum.all?(results, &(&1.status == :ok))
    assert_receive :started
    assert :ets.lookup_element(tracker, :max, 2) == 1
  end

  defp update_max(table, running) do
    current = :ets.lookup_element(table, :max, 2)
    if running > current, do: :ets.insert(table, {:max, running})
  end
end
