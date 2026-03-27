defmodule Thinktank.Dispatch.Deep do
  @moduledoc """
  Deep mode dispatch via Pi agent subprocesses.

  Spawns N Pi agents in parallel under Task.Supervisor, each with a
  unique perspective, model, and system prompt. Uses MuonTrap when
  available (mix/release) for OS-level kill-safety; falls back to
  System.cmd for escripts where MuonTrap's priv binary is inaccessible.

  Returns the same result tuples as `Dispatch.Quick` (with `nil` usage)
  so the caller (CLI) doesn't care which mode ran.
  """

  @type result :: {:ok, String.t(), String.t(), map() | nil} | {:error, String.t(), map()}

  @default_timeout :timer.minutes(30)
  @default_tools "read,bash,grep,find"

  @doc """
  Dispatch Pi agent subprocesses for each perspective.

  Returns a list of `{:ok, role, text, usage}` or `{:error, role, error_map}` tuples.
  Usage is `nil` for deep mode (Pi subprocesses don't report API usage).

  Options:
    - `:paths` — file paths for agent context (starting points)
    - `:runner` — `fn cmd, args, opts -> {output, exit_status}` (default: auto-detected)
    - `:agent_config_dir` — path for PI_CODING_AGENT_DIR env var
    - `:timeout` — per-agent timeout in ms (default: 30 min)
  """
  @spec dispatch([Thinktank.Perspective.t()], String.t(), keyword()) :: [result()]
  def dispatch(perspectives, instruction, opts \\ []) do
    runner = opts[:runner] || default_runner()
    timeout = opts[:timeout] || @default_timeout

    tasks =
      Enum.map(perspectives, fn perspective ->
        Task.Supervisor.async_nolink(Thinktank.AgentSupervisor, fn ->
          run_agent(perspective, instruction, opts, runner)
        end)
      end)

    tasks
    |> Task.yield_many(timeout + 5_000)
    |> Enum.zip(perspectives)
    |> Enum.map(&collect_result/1)
  end

  defp collect_result({{_task, {:ok, result}}, _perspective}), do: result

  defp collect_result({{task, nil}, perspective}) do
    Task.shutdown(task, :brutal_kill)
    {:error, perspective.role, %{category: :timeout}}
  end

  defp collect_result({{_task, {:exit, reason}}, perspective}) do
    {:error, perspective.role, %{category: :crash, message: inspect(reason)}}
  end

  defp run_agent(perspective, instruction, opts, runner) do
    prompt = build_prompt(perspective.system_prompt, instruction, opts[:paths] || [])

    # Pi hangs when Erlang ports keep stdin open — wrap via sh to close it.
    shell_cmd = build_shell_cmd(perspective.model, prompt)
    cmd_opts = build_cmd_opts(opts)

    case runner.("sh", ["-c", shell_cmd], cmd_opts) do
      {output, 0} ->
        {:ok, perspective.role, output, nil}

      {output, :timeout} ->
        {:error, perspective.role, %{category: :timeout, output: output}}

      {output, exit_code} when is_integer(exit_code) ->
        {:error, perspective.role, %{category: :crash, exit_code: exit_code, output: output}}
    end
  rescue
    e ->
      {:error, perspective.role, %{category: :crash, message: Exception.message(e)}}
  end

  defp build_shell_cmd(model, prompt) do
    escaped_prompt = prompt |> String.replace("'", "'\\''")
    escaped_model = model |> String.replace("'", "'\\''")

    "exec pi --no-session --no-skills --model '#{escaped_model}'" <>
      " --tools #{@default_tools} -p '#{escaped_prompt}' < /dev/null"
  end

  defp build_prompt(system_prompt, instruction, []) do
    "#{system_prompt}\n\n#{instruction}"
  end

  defp build_prompt(system_prompt, instruction, paths) do
    path_list = Enum.map_join(paths, "\n", &"  - #{&1}")
    "#{system_prompt}\n\n#{instruction}\n\nStarting file paths:\n#{path_list}"
  end

  defp build_cmd_opts(opts) do
    timeout = opts[:timeout] || @default_timeout
    base = [stderr_to_stdout: true, timeout: timeout]

    case opts[:agent_config_dir] do
      nil -> base
      dir -> Keyword.put(base, :env, [{"PI_CODING_AGENT_DIR", dir}])
    end
  end

  @doc false
  def default_runner do
    if muontrap_available?(), do: &muontrap_cmd/3, else: &system_cmd/3
  end

  @doc false
  def muontrap_available? do
    path = MuonTrap.muontrap_path()
    File.exists?(path)
  rescue
    _ -> false
  end

  @doc """
  Escript fallback runner. System.cmd does NOT provide OS-level kill-safety.
  On timeout, the Elixir task is killed but the OS process may survive.
  MuonTrap path (mix/release) provides true kill-safety.
  """
  def system_cmd(cmd, args, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    env = Keyword.get(opts, :env, [])
    cd = Keyword.get(opts, :cd)
    cmd_opts = [stderr_to_stdout: true, env: env] ++ if(cd, do: [cd: cd], else: [])

    task =
      Task.async(fn ->
        System.cmd(cmd, args, cmd_opts)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, exit_code}} -> {output, exit_code}
      nil -> {"", :timeout}
    end
  end

  defp muontrap_cmd(cmd, args, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    env = Keyword.get(opts, :env, [])
    cd = Keyword.get(opts, :cd)

    cmd_opts =
      [stderr_to_stdout: true, timeout: timeout, env: env] ++ if(cd, do: [cd: cd], else: [])

    MuonTrap.cmd(cmd, args, cmd_opts)
  end
end
