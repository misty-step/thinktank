defmodule Thinktank.Executor.AgenticTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Thinktank.{AgentSpec, Config, ProviderSpec, RunContract}
  alias Thinktank.Executor.Agentic

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end

  defp read_jsonl(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  defp write_session_usage(pi_home, session_name, usage) do
    path = Path.join([pi_home, "sessions", "2026", "#{session_name}.jsonl"])
    File.mkdir_p!(Path.dirname(path))

    File.write!(
      path,
      Jason.encode!(%{
        "type" => "message",
        "message" => %{"role" => "assistant", "usage" => usage}
      }) <> "\n"
    )
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
      bench_id: "review/default",
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
      thinking_level: "high",
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
      thinking_level: "high",
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

  test "records timing metadata for successful runs" do
    tmp = unique_tmp_dir("thinktank-agentic-timing")

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      thinking_level: "high",
      task_prompt: "{{input_text}}",
      timeout_ms: 5_000
    }

    runner = fn _cmd, _args, _opts ->
      Process.sleep(10)
      {"timed output", 0}
    end

    [result] = Agentic.run([agent], contract(tmp), %{}, config(), runner: runner)

    assert result.status == :ok
    assert result.output == "timed output"
    assert is_binary(result.started_at)
    assert is_binary(result.completed_at)
    assert is_integer(result.duration_ms)
    assert result.duration_ms >= 0
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
      thinking_level: "high",
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
      thinking_level: "high",
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
      thinking_level: "high",
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
      thinking_level: "high",
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
      thinking_level: "high",
      task_prompt: "{{input_text}}",
      timeout_ms: 5_000
    }

    runner = fn _cmd, _args, _opts -> exit(:boom) end

    capture_log(fn ->
      send(
        self(),
        {:agentic_result, Agentic.run([agent], contract(tmp), %{}, config(), runner: runner)}
      )
    end)

    assert_receive {:agentic_result, [result]}

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
      thinking_level: "high",
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

  test "renders agent metadata into the prompt context" do
    tmp = unique_tmp_dir("thinktank-agentic-metadata")
    test_pid = self()

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      thinking_level: "high",
      task_prompt: "Role={{review_role}}\nBrief={{review_brief}}",
      timeout_ms: 5_000,
      metadata: %{"review_role" => "correctness", "review_brief" => "Focus on regressions."}
    }

    runner = fn _cmd, args, _opts ->
      prompt =
        args
        |> Enum.drop_while(&(&1 != "-p"))
        |> Enum.at(1)
        |> String.trim_leading("@")
        |> File.read!()

      send(test_pid, {:prompt, prompt})
      {"ok", 0}
    end

    [result] = Agentic.run([agent], contract(tmp), %{}, config(), runner: runner)

    assert result.status == :ok
    assert_receive {:prompt, prompt}
    assert prompt =~ "Role=correctness"
    assert prompt =~ "Brief=Focus on regressions."
  end

  test "writes durable trace events and mirrors them to the configured global log" do
    tmp = unique_tmp_dir("thinktank-agentic-trace")
    log_dir = unique_tmp_dir("thinktank-agentic-logs")
    previous_log_dir = System.get_env("THINKTANK_LOG_DIR")
    previous_key = System.get_env("THINKTANK_OPENROUTER_API_KEY")
    System.put_env("THINKTANK_LOG_DIR", log_dir)
    System.put_env("THINKTANK_OPENROUTER_API_KEY", "super-secret-value")

    on_exit(fn ->
      if is_nil(previous_log_dir) do
        System.delete_env("THINKTANK_LOG_DIR")
      else
        System.put_env("THINKTANK_LOG_DIR", previous_log_dir)
      end

      if is_nil(previous_key) do
        System.delete_env("THINKTANK_OPENROUTER_API_KEY")
      else
        System.put_env("THINKTANK_OPENROUTER_API_KEY", previous_key)
      end
    end)

    counter = :atomics.new(1, [])

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      thinking_level: "high",
      task_prompt: "{{input_text}}",
      timeout_ms: 5_000,
      retries: 1
    }

    runner = fn _cmd, _args, _opts ->
      attempt = :atomics.add_get(counter, 1, 1)

      case attempt do
        1 -> {"first attempt failed", 1}
        _ -> {"second attempt ok", 0}
      end
    end

    contract = contract(tmp)
    [result] = Agentic.run([agent], contract, %{}, config(), runner: runner)

    assert result.status == :ok

    events = read_jsonl(Path.join(contract.artifact_dir, "trace/events.jsonl"))
    event_names = Enum.map(events, & &1["event"])

    assert "agent_started" in event_names
    assert "prompt_written" in event_names
    assert Enum.count(events, &(&1["event"] == "attempt_started")) == 2
    assert Enum.count(events, &(&1["event"] == "subprocess_started")) == 2

    assert Enum.any?(events, fn event ->
             event["event"] == "attempt_retry_scheduled" and event["attempt"] == 1 and
               event["next_attempt"] == 2
           end)

    assert Enum.any?(events, fn event ->
             event["event"] == "agent_finished" and event["status"] == "ok" and
               event["attempts"] == 2
           end)

    assert Enum.all?(Enum.filter(events, &(&1["event"] == "subprocess_started")), fn event ->
             "PI_CODING_AGENT_DIR" in event["env_keys"]
           end)

    [global_log] = Path.wildcard(Path.join(log_dir, "**/*.jsonl"))
    global_events = read_jsonl(global_log)

    assert Enum.any?(global_events, &(&1["run_id"] == Path.basename(contract.artifact_dir)))
    refute File.read!(global_log) =~ "super-secret-value"
  end

  test "aggregates session usage across retries into the final result" do
    tmp = unique_tmp_dir("thinktank-agentic-usage")
    counter = :atomics.new(1, [])

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4-mini",
      system_prompt: "You are a reviewer.",
      thinking_level: "high",
      task_prompt: "{{input_text}}",
      timeout_ms: 5_000,
      retries: 1
    }

    runner = fn _cmd, _args, opts ->
      env = opts |> Keyword.fetch!(:env) |> Enum.into(%{})
      pi_home = Map.fetch!(env, "PI_CODING_AGENT_DIR")
      attempt = :atomics.add_get(counter, 1, 1)

      write_session_usage(pi_home, "attempt-#{attempt}", %{
        "input" => 100 * attempt,
        "output" => 10 * attempt,
        "cacheRead" => 20 * attempt
      })

      case attempt do
        1 -> {"first attempt failed", 1}
        _ -> {"second attempt ok", 0}
      end
    end

    [result] = Agentic.run([agent], contract(tmp), %{}, config(), runner: runner)

    assert result.status == :ok
    assert result.usage["model"] == "openai/gpt-5.4-mini"
    assert result.usage["input_tokens"] == 300
    assert result.usage["output_tokens"] == 30
    assert result.usage["cache_read_tokens"] == 60
    assert result.usage["cache_write_tokens"] == 0
    assert result.usage["total_tokens"] == 390
    assert result.usage["pricing_gap"] == nil
    assert_in_delta result.usage["usd_cost"], 0.0003645, 1.0e-12
  end

  test "timeout subprocess traces use a nil exit_code" do
    tmp = unique_tmp_dir("thinktank-agentic-timeout-trace")

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      thinking_level: "high",
      task_prompt: "{{input_text}}",
      timeout_ms: 5_000
    }

    contract = contract(tmp)
    runner = fn _cmd, _args, _opts -> {"timed out", :timeout} end

    [result] = Agentic.run([agent], contract, %{}, config(), runner: runner)

    assert result.status == :error

    events = read_jsonl(Path.join(contract.artifact_dir, "trace/events.jsonl"))

    assert Enum.any?(events, fn event ->
             event["event"] == "subprocess_finished" and event["status"] == "timeout" and
               is_nil(event["exit_code"])
           end)
  end

  test "records a timeout trace event when the outer task times out" do
    tmp = unique_tmp_dir("thinktank-agentic-task-timeout")

    agent = %AgentSpec{
      name: "trace",
      provider: "openrouter",
      model: "openai/gpt-5.4",
      system_prompt: "You are a reviewer.",
      thinking_level: "high",
      task_prompt: "{{input_text}}",
      timeout_ms: 10
    }

    contract = contract(tmp)

    runner = fn _cmd, _args, _opts ->
      Process.sleep(6_000)
      {"too late", 0}
    end

    [result] = Agentic.run([agent], contract, %{}, config(), runner: runner)

    assert result.status == :error
    assert result.error.category == :timeout

    events = read_jsonl(Path.join(contract.artifact_dir, "trace/events.jsonl"))

    assert Enum.any?(events, fn event ->
             event["event"] == "agent_finished" and event["status"] == "error" and
               event["error"]["category"] == "timeout"
           end)
  end
end
