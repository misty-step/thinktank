defmodule Thinktank.Dispatch.DeepTest do
  use ExUnit.Case, async: true

  alias Thinktank.Dispatch.Deep
  alias Thinktank.Perspective

  defp perspective(role, model) do
    %Perspective{
      role: role,
      model: model,
      system_prompt: "You are a #{role}."
    }
  end

  describe "dispatch/3 — parallel subprocess spawning" do
    test "spawns one subprocess per perspective and returns results" do
      perspectives = [
        perspective("analyst-1", "model-a"),
        perspective("analyst-2", "model-b"),
        perspective("analyst-3", "model-c")
      ]

      test_pid = self()

      runner = fn cmd, args, opts ->
        send(test_pid, {:spawned, cmd, args, opts})
        {"output from agent", 0}
      end

      results = Deep.dispatch(perspectives, "test instruction", runner: runner)

      assert length(results) == 3

      # Verify 3 subprocesses were spawned
      spawns = flush_tagged(:spawned)
      assert length(spawns) == 3
    end

    test "returns {:ok, role, text} for successful agents" do
      perspectives = [perspective("security", "model-a")]

      runner = fn _cmd, _args, _opts -> {"## Security Analysis\nAll clear.", 0} end

      [result] = Deep.dispatch(perspectives, "audit this", runner: runner)
      assert {:ok, "security", "## Security Analysis\nAll clear."} = result
    end

    test "returns {:error, role, error_map} for crashed agents" do
      perspectives = [perspective("analyst", "model-a")]

      runner = fn _cmd, _args, _opts -> {"something went wrong", 1} end

      [result] = Deep.dispatch(perspectives, "investigate", runner: runner)
      assert {:error, "analyst", error} = result
      assert error.category == :crash
      assert error.exit_code == 1
    end

    test "collects errors alongside successes — other agents continue" do
      perspectives = [
        perspective("good-1", "model-a"),
        perspective("bad-1", "model-b"),
        perspective("good-2", "model-c")
      ]

      runner = fn _cmd, args, _opts ->
        if "--model" in args do
          model_idx = Enum.find_index(args, &(&1 == "--model"))
          model = Enum.at(args, model_idx + 1)

          if model == "model-b" do
            {"crash", 137}
          else
            {"ok", 0}
          end
        else
          {"ok", 0}
        end
      end

      results = Deep.dispatch(perspectives, "test", runner: runner)

      assert length(results) == 3
      oks = Enum.filter(results, &match?({:ok, _, _}, &1))
      errors = Enum.filter(results, &match?({:error, _, _}, &1))
      assert length(oks) == 2
      assert length(errors) == 1

      [{:error, role, err}] = errors
      assert role == "bad-1"
      assert err.category == :crash
      assert err.exit_code == 137
    end

    test "handles runner exceptions gracefully" do
      perspectives = [perspective("crasher", "model-a")]

      runner = fn _cmd, _args, _opts -> raise "boom" end

      [result] = Deep.dispatch(perspectives, "test", runner: runner)
      assert {:error, "crasher", error} = result
      assert error.category == :crash
    end
  end

  describe "dispatch/3 — timeout handling" do
    test "returns timeout error for slow agents" do
      perspectives = [perspective("slow", "model-a")]

      runner = fn _cmd, _args, _opts -> {"partial output", :timeout} end

      [result] = Deep.dispatch(perspectives, "test", runner: runner)
      assert {:error, "slow", error} = result
      assert error.category == :timeout
    end
  end

  describe "dispatch/3 — command arguments" do
    test "passes correct pi args with model and tools" do
      perspectives = [perspective("analyst", "anthropic/claude-opus-4-6")]
      test_pid = self()

      runner = fn cmd, args, opts ->
        send(test_pid, {:call, cmd, args, opts})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "review code", runner: runner)

      assert_receive {:call, "pi", args, _opts}
      assert "--no-session" in args
      assert "--no-skills" in args
      assert "--model" in args

      model_idx = Enum.find_index(args, &(&1 == "--model"))
      assert Enum.at(args, model_idx + 1) == "anthropic/claude-opus-4-6"

      assert "--tools" in args
      tools_idx = Enum.find_index(args, &(&1 == "--tools"))
      assert Enum.at(args, tools_idx + 1) == "read,bash,grep,find"
    end

    test "includes instruction and system prompt in the prompt argument" do
      perspectives = [
        %Perspective{
          role: "security",
          model: "test-model",
          system_prompt: "You are a security expert focused on auth."
        }
      ]

      test_pid = self()

      runner = fn _cmd, args, _opts ->
        send(test_pid, {:args, args})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "audit the auth module", runner: runner)

      assert_receive {:args, args}
      prompt_idx = Enum.find_index(args, &(&1 == "-p"))
      prompt = Enum.at(args, prompt_idx + 1)

      assert prompt =~ "You are a security expert focused on auth."
      assert prompt =~ "audit the auth module"
    end

    test "includes file paths in the prompt when provided" do
      perspectives = [perspective("analyst", "test-model")]
      test_pid = self()

      runner = fn _cmd, args, _opts ->
        send(test_pid, {:args, args})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "review", runner: runner, paths: ["/src/auth.ex", "/src/router.ex"])

      assert_receive {:args, args}
      prompt_idx = Enum.find_index(args, &(&1 == "-p"))
      prompt = Enum.at(args, prompt_idx + 1)

      assert prompt =~ "/src/auth.ex"
      assert prompt =~ "/src/router.ex"
    end

    test "sets PI_CODING_AGENT_DIR env when agent_config_dir provided" do
      perspectives = [perspective("analyst", "test-model")]
      test_pid = self()

      runner = fn _cmd, _args, opts ->
        send(test_pid, {:opts, opts})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "test",
        runner: runner,
        agent_config_dir: "/path/to/config"
      )

      assert_receive {:opts, opts}
      env = Keyword.get(opts, :env, [])
      assert {"PI_CODING_AGENT_DIR", "/path/to/config"} in env
    end

    test "omits PI_CODING_AGENT_DIR when no config dir" do
      perspectives = [perspective("analyst", "test-model")]
      test_pid = self()

      runner = fn _cmd, _args, opts ->
        send(test_pid, {:opts, opts})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "test", runner: runner)

      assert_receive {:opts, opts}
      env = Keyword.get(opts, :env, [])
      refute Enum.any?(env, fn {k, _v} -> k == "PI_CODING_AGENT_DIR" end)
    end
  end

  describe "dispatch/3 — each agent gets unique perspective" do
    test "each agent receives its own system prompt and model" do
      perspectives = [
        %Perspective{
          role: "security",
          model: "model-a",
          system_prompt: "You are a security expert."
        },
        %Perspective{
          role: "performance",
          model: "model-b",
          system_prompt: "You are a performance analyst."
        },
        %Perspective{
          role: "architecture",
          model: "model-c",
          system_prompt: "You are a software architect."
        }
      ]

      test_pid = self()

      runner = fn _cmd, args, _opts ->
        model_idx = Enum.find_index(args, &(&1 == "--model"))
        model = Enum.at(args, model_idx + 1)
        prompt_idx = Enum.find_index(args, &(&1 == "-p"))
        prompt = Enum.at(args, prompt_idx + 1)
        send(test_pid, {:agent, model, prompt})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "analyze", runner: runner)

      agents = flush_tagged(:agent)
      assert length(agents) == 3

      models = Enum.map(agents, fn {model, _prompt} -> model end)
      assert "model-a" in models
      assert "model-b" in models
      assert "model-c" in models

      prompts = Enum.map(agents, fn {_model, prompt} -> prompt end)
      assert Enum.any?(prompts, &(&1 =~ "security expert"))
      assert Enum.any?(prompts, &(&1 =~ "performance analyst"))
      assert Enum.any?(prompts, &(&1 =~ "software architect"))
    end
  end

  # Flush all messages with a given tag, collecting the payloads
  defp flush_tagged(tag), do: flush_tagged(tag, [])

  defp flush_tagged(tag, acc) do
    receive do
      {^tag, a, b, c} -> flush_tagged(tag, [{a, b, c} | acc])
      {^tag, a, b} -> flush_tagged(tag, [{a, b} | acc])
      {^tag, rest} -> flush_tagged(tag, [rest | acc])
    after
      500 -> Enum.reverse(acc)
    end
  end
end
