defmodule Thinktank.Dispatch.Deep do
  @moduledoc """
  Deep mode dispatch via Pi agent subprocesses.

  Spawns N Pi agents in parallel under Task.Supervisor, each with a
  unique perspective, model, and system prompt. MuonTrap wraps each
  subprocess: if the parent dies (SIGTERM, crash), all children are
  killed at the OS level.

  Returns the same result tuples as `Dispatch.Quick` so the caller
  (CLI) doesn't care which mode ran.
  """

  @type result :: {:ok, String.t(), String.t()} | {:error, String.t(), map()}

  @default_timeout :timer.minutes(30)
  @default_tools "read,bash,grep,find"

  @doc """
  Dispatch Pi agent subprocesses for each perspective.

  Returns a list of `{:ok, role, text}` or `{:error, role, error_map}` tuples.

  Options:
    - `:paths` — file paths for agent context (starting points)
    - `:runner` — `fn cmd, args, opts -> {output, exit_status}` (default: `&MuonTrap.cmd/3`)
    - `:agent_config_dir` — path for PI_CODING_AGENT_DIR env var
    - `:timeout` — per-agent timeout in ms (default: 30 min)
  """
  @spec dispatch([Thinktank.Perspective.t()], String.t(), keyword()) :: [result()]
  def dispatch(perspectives, instruction, opts \\ []) do
    runner = opts[:runner] || (&MuonTrap.cmd/3)
    timeout = opts[:timeout] || @default_timeout

    tasks =
      Enum.map(perspectives, fn perspective ->
        Task.Supervisor.async_nolink(Thinktank.AgentSupervisor, fn ->
          run_agent(perspective, instruction, opts, runner)
        end)
      end)

    # Grace period: let MuonTrap's timeout fire first for cleaner error reporting
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

    args = [
      "--no-session",
      "--no-skills",
      "--model",
      perspective.model,
      "--tools",
      @default_tools,
      "-p",
      prompt
    ]

    cmd_opts = build_cmd_opts(opts)

    case runner.("pi", args, cmd_opts) do
      {output, 0} ->
        {:ok, perspective.role, output}

      {output, :timeout} ->
        {:error, perspective.role, %{category: :timeout, output: output}}

      {output, exit_code} when is_integer(exit_code) ->
        {:error, perspective.role, %{category: :crash, exit_code: exit_code, output: output}}
    end
  rescue
    e ->
      {:error, perspective.role, %{category: :crash, message: Exception.message(e)}}
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
end
