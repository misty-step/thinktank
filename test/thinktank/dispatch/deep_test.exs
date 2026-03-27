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

  defp pi_args(["-c", "exec < /dev/null; exec \"$@\"", "sh", "pi" | rest]), do: rest

  defp prompt_arg(args) do
    [_, prompt] =
      Enum.chunk_every(args, 2, 1, :discard) |> Enum.find(fn [flag, _value] -> flag == "-p" end)

    prompt
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

      spawns = flush_tagged(:spawned)
      assert length(spawns) == 3

      # All spawns go through sh
      Enum.each(spawns, fn {cmd, _args, _opts} -> assert cmd == "sh" end)
    end

    test "returns {:ok, role, text} for successful agents" do
      perspectives = [perspective("security", "model-a")]

      runner = fn _cmd, _args, _opts -> {"## Security Analysis\nAll clear.", 0} end

      [result] = Deep.dispatch(perspectives, "audit this", runner: runner)
      assert {:ok, "security", "## Security Analysis\nAll clear.", nil} = result
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
        if Enum.member?(pi_args(args), "model-b") do
          {"crash", 137}
        else
          {"ok", 0}
        end
      end

      results = Deep.dispatch(perspectives, "test", runner: runner)

      assert length(results) == 3
      oks = Enum.filter(results, &match?({:ok, _, _, _}, &1))
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
    test "returns timeout error with partial output for slow agents" do
      perspectives = [perspective("slow", "model-a")]

      runner = fn _cmd, _args, _opts -> {"partial output before timeout", :timeout} end

      [result] = Deep.dispatch(perspectives, "test", runner: runner)
      assert {:error, "slow", error} = result
      assert error.category == :timeout
      assert error.output == "partial output before timeout"
    end
  end

  describe "dispatch/3 — command arguments" do
    test "wraps pi via sh -c with correct flags" do
      perspectives = [perspective("analyst", "anthropic/claude-opus-4-6")]
      test_pid = self()

      runner = fn cmd, args, opts ->
        send(test_pid, {:call, cmd, args, opts})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "review code", runner: runner)

      assert_receive {:call, "sh", args, _opts}
      assert Enum.take(args, 4) == ["-c", "exec < /dev/null; exec \"$@\"", "sh", "pi"]

      assert pi_args(args) == [
               "--no-session",
               "--no-skills",
               "--model",
               "anthropic/claude-opus-4-6",
               "--tools",
               "read,grep,find,ls",
               "-p",
               "You are a analyst.\n\nreview code"
             ]
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
      prompt = args |> pi_args() |> prompt_arg()
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

      Deep.dispatch(perspectives, "review",
        runner: runner,
        paths: ["/src/auth.ex", "/src/router.ex"]
      )

      assert_receive {:args, args}
      prompt = args |> pi_args() |> prompt_arg()
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

    test "forwards timeout to runner cmd_opts" do
      perspectives = [perspective("analyst", "test-model")]
      test_pid = self()

      runner = fn _cmd, _args, opts ->
        send(test_pid, {:opts, opts})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "test", runner: runner, timeout: 60_000)

      assert_receive {:opts, opts}
      assert Keyword.get(opts, :timeout) == 60_000
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
        send(test_pid, {:agent, pi_args(args)})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "analyze", runner: runner)

      agents = flush_tagged(:agent)
      assert length(agents) == 3

      assert Enum.any?(
               agents,
               &(Enum.member?(&1, "model-a") and prompt_arg(&1) =~ "security expert")
             )

      assert Enum.any?(
               agents,
               &(Enum.member?(&1, "model-b") and prompt_arg(&1) =~ "performance analyst")
             )

      assert Enum.any?(
               agents,
               &(Enum.member?(&1, "model-c") and prompt_arg(&1) =~ "software architect")
             )
    end
  end

  describe "build_command/2 — prompt argument preservation" do
    test "preserves single quotes in prompts without shell escaping" do
      perspectives = [
        %Perspective{
          role: "test",
          model: "test-model",
          system_prompt: "You're an expert."
        }
      ]

      test_pid = self()

      runner = fn _cmd, args, _opts ->
        send(test_pid, {:args, args})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "what's the issue?", runner: runner)

      assert_receive {:args, args}
      prompt = args |> pi_args() |> prompt_arg()
      assert prompt =~ "You're an expert."
      assert prompt =~ "what's the issue?"
    end

    test "passes through backticks in prompt" do
      perspectives = [
        %Perspective{role: "test", model: "m", system_prompt: "Check `main` function."}
      ]

      test_pid = self()

      runner = fn _cmd, args, _opts ->
        send(test_pid, {:args, args})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "review `lib/app.ex`", runner: runner)

      assert_receive {:args, args}
      prompt = args |> pi_args() |> prompt_arg()
      assert prompt =~ "`main`"
      assert prompt =~ "`lib/app.ex`"
    end

    test "passes through dollar signs (single-quoted)" do
      perspectives = [
        %Perspective{role: "test", model: "m", system_prompt: "Check $HOME variable."}
      ]

      test_pid = self()

      runner = fn _cmd, args, _opts ->
        send(test_pid, {:args, args})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "expand $PATH", runner: runner)

      assert_receive {:args, args}
      prompt = args |> pi_args() |> prompt_arg()
      assert prompt =~ "$HOME"
      assert prompt =~ "$PATH"
    end

    test "preserves newlines in prompt" do
      system = "Line one.\nLine two.\nLine three."

      perspectives = [
        %Perspective{role: "test", model: "m", system_prompt: system}
      ]

      test_pid = self()

      runner = fn _cmd, args, _opts ->
        send(test_pid, {:args, args})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "go", runner: runner)

      assert_receive {:args, args}
      prompt = args |> pi_args() |> prompt_arg()
      assert prompt =~ "Line one.\nLine two.\nLine three."
    end

    test "handles empty prompt" do
      perspectives = [
        %Perspective{role: "test", model: "m", system_prompt: ""}
      ]

      test_pid = self()

      runner = fn _cmd, args, _opts ->
        send(test_pid, {:args, args})
        {"done", 0}
      end

      Deep.dispatch(perspectives, "", runner: runner)

      assert_receive {:args, args}
      assert Enum.member?(pi_args(args), "m")
      assert prompt_arg(pi_args(args)) == "\n\n"
    end
  end

  describe "muontrap_available?/0" do
    test "returns a boolean" do
      result = Deep.muontrap_available?()
      assert is_boolean(result)
    end
  end

  describe "default_runner/0" do
    test "returns a function" do
      runner = Deep.default_runner()
      assert is_function(runner, 3)
    end
  end

  describe "system_cmd/3 — escript fallback runner" do
    test "returns {output, 0} for successful commands" do
      {output, exit_code} = Deep.system_cmd("echo", ["hello"], [])
      assert exit_code == 0
      assert String.trim(output) == "hello"
    end

    test "returns non-zero exit code for failed commands" do
      {_output, exit_code} = Deep.system_cmd("sh", ["-c", "exit 42"], [])
      assert exit_code == 42
    end

    test "forwards env to subprocess" do
      {output, 0} = Deep.system_cmd("sh", ["-c", "echo $TEST_VAR"], env: [{"TEST_VAR", "works"}])
      assert String.trim(output) == "works"
    end

    test "returns timeout tuple when command exceeds timeout" do
      {_output, status} = Deep.system_cmd("sleep", ["10"], timeout: 100)
      assert status == :timeout
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
