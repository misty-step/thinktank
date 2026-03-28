defmodule Thinktank.Executor.AgenticTest do
  use ExUnit.Case, async: false

  alias Thinktank.{AgentSpec, Config, ProviderSpec, RunContract}
  alias Thinktank.Executor.Agentic

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp config do
    %Config{
      providers: %{
        "openrouter" => %ProviderSpec{
          id: "openrouter",
          adapter: :openrouter,
          credential_env: "THINKTANK_OPENROUTER_API_KEY",
          defaults: %{}
        }
      },
      agents: %{},
      benches: %{},
      sources: %{}
    }
  end

  defp contract(tmp) do
    %RunContract{
      bench_id: "review/cerberus",
      workspace_root: tmp,
      input: %{"input_text" => "Review this"},
      artifact_dir: Path.join(tmp, "out"),
      adapter_context: %{}
    }
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
      task_prompt: "{{input_text}}",
      timeout_ms: 5_000
    }

    [result] = Agentic.run([agent], contract(tmp), %{}, config(), runner: nil)

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
      task_prompt: "{{input_text}}",
      timeout_ms: 5_000
    }

    runner = fn _cmd, _args, opts ->
      env = opts |> Keyword.fetch!(:env) |> Enum.into(%{})
      send(test_pid, {:pi_home, Map.fetch!(env, "PI_CODING_AGENT_DIR")})
      {"stub reviewer output", 0}
    end

    [result] = Agentic.run([agent], contract(tmp), %{}, config(), runner: runner)

    assert result.status == :ok
    assert_receive {:pi_home, pi_home}
    assert pi_home =~ Path.join(contract(tmp).artifact_dir, "pi-home/trace-guard-")
    assert File.dir?(pi_home)
  end

  test "rejects trusted agent config trees that contain symlinks" do
    tmp = unique_tmp_dir("thinktank-agentic-symlink")
    base_dir = Path.join(tmp, "agent-config")
    File.rm_rf!(base_dir)
    File.mkdir_p!(base_dir)
    File.write!(Path.join(base_dir, "settings.json"), "{}")
    File.ln_s!("/tmp", Path.join(base_dir, "outside"))

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      task_prompt: "{{input_text}}",
      timeout_ms: 5_000
    }

    [result] = Agentic.run([agent], contract(tmp), %{}, config(), agent_config_dir: base_dir)

    assert result.status == :error
    assert result.error.category == :crash
    assert result.error.message =~ "must not contain symlinks"
  end

  test "rejects a trusted agent config root that is itself a symlink" do
    tmp = unique_tmp_dir("thinktank-agentic-root-symlink")
    target_dir = Path.join(tmp, "target-config")
    base_dir = Path.join(tmp, "agent-config")
    File.mkdir_p!(target_dir)
    File.write!(Path.join(target_dir, "settings.json"), "{}")
    File.ln_s!(target_dir, base_dir)

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      task_prompt: "{{input_text}}",
      timeout_ms: 5_000
    }

    [result] = Agentic.run([agent], contract(tmp), %{}, config(), agent_config_dir: base_dir)

    assert result.status == :error
    assert result.error.category == :crash
    assert result.error.message =~ "must not be a symlink"
  end

  test "passes pi arguments without interpolating tools into shell code" do
    tmp = unique_tmp_dir("thinktank-agentic-args")
    test_pid = self()
    pwned = Path.join(tmp, "pwned")

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      task_prompt: "{{input_text}}",
      tools: ["read", "$(touch #{pwned})"],
      timeout_ms: 5_000
    }

    runner = fn cmd, args, _opts ->
      send(test_pid, {:cmd, cmd, args})
      {"ok", 0}
    end

    [result] = Agentic.run([agent], contract(tmp), %{}, config(), runner: runner)
    assert result.status == :ok

    assert_receive {:cmd, "sh", args}
    tools = args |> Enum.drop_while(&(&1 != "--tools")) |> Enum.at(1)
    assert tools == "read"
    refute File.exists?(pwned)
  end

  test "does not widen an explicit tool list when every tool is filtered out" do
    tmp = unique_tmp_dir("thinktank-agentic-tools")
    test_pid = self()
    pwned = Path.join(tmp, "pwned")

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      task_prompt: "{{input_text}}",
      tools: ["nope", "$(touch #{pwned})"],
      timeout_ms: 5_000
    }

    runner = fn _cmd, args, _opts ->
      send(test_pid, {:cmd_args, args})
      {"ok", 0}
    end

    [result] = Agentic.run([agent], contract(tmp), %{}, config(), runner: runner)
    assert result.status == :ok

    assert_receive {:cmd_args, args}
    tools = args |> Enum.drop_while(&(&1 != "--tools")) |> Enum.at(1)
    assert tools == ""
    refute File.exists?(pwned)
  end

  test "preserves instance ids when the outer task exits" do
    tmp = unique_tmp_dir("thinktank-agentic-task-exit")
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      task_prompt: "{{input_text}}",
      timeout_ms: 5_000
    }

    runner = fn _cmd, _args, _opts -> exit(:boom) end

    [result] = Agentic.run([agent], contract(tmp), %{}, config(), runner: runner)

    assert result.status == :error
    assert result.error.category == :crash
    assert result.instance_id =~ "trace-"
  end

  test "falls back to fallback_env when the primary credential env is blank" do
    tmp = unique_tmp_dir("thinktank-agentic-fallback-env")
    test_pid = self()

    config =
      %{
        config()
        | providers: %{
            "openrouter" => %ProviderSpec{
              id: "openrouter",
              adapter: :openrouter,
              credential_env: "THINKTANK_OPENROUTER_API_KEY",
              defaults: %{"fallback_env" => "THINKTANK_FALLBACK_OPENROUTER_API_KEY"}
            }
          }
      }

    System.put_env("THINKTANK_OPENROUTER_API_KEY", "")
    System.put_env("THINKTANK_FALLBACK_OPENROUTER_API_KEY", "fallback-secret")

    on_exit(fn ->
      System.delete_env("THINKTANK_OPENROUTER_API_KEY")
      System.delete_env("THINKTANK_FALLBACK_OPENROUTER_API_KEY")
    end)

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      task_prompt: "{{input_text}}",
      timeout_ms: 5_000
    }

    runner = fn _cmd, _args, opts ->
      env = opts |> Keyword.fetch!(:env) |> Enum.into(%{})
      send(test_pid, {:openrouter_key, env["OPENROUTER_API_KEY"]})
      {"ok", 0}
    end

    [result] = Agentic.run([agent], contract(tmp), %{}, config, runner: runner)
    assert result.status == :ok

    assert_receive {:openrouter_key, "fallback-secret"}
  end
end
