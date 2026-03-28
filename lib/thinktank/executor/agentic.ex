defmodule Thinktank.Executor.Agentic do
  @moduledoc """
  Pi subprocess executor for tool-using agent runs.
  """

  alias Thinktank.{AgentSpec, Config, RunContract, Template}

  @allowed_tools MapSet.new(~w(read bash edit write grep find ls))
  @default_tools ["bash", "read", "grep", "find", "ls"]
  @default_timeout :timer.minutes(30)

  @type result :: %{
          agent: AgentSpec.t(),
          instance_id: String.t(),
          status: :ok | :error,
          output: String.t(),
          usage: nil,
          error: map() | nil
        }

  @spec run([AgentSpec.t()], RunContract.t(), map(), Config.t(), keyword()) :: [result()]
  def run(agents, contract, context, config, opts \\ [])

  def run([], %RunContract{}, _context, %Config{}, _opts), do: []

  def run(agents, %RunContract{} = contract, context, %Config{} = config, opts) do
    runner = Keyword.get(opts, :runner) || default_runner()
    indexed_agents = Enum.with_index(agents, 1)

    timeout =
      Enum.max(
        Enum.map(agents, fn agent ->
          attempts = max(agent.retries + 1, 1)
          agent.timeout_ms * attempts + 250 * (attempts - 1)
        end),
        fn -> @default_timeout end
      )

    concurrency =
      normalize_concurrency(Keyword.get(opts, :concurrency, length(agents)), length(agents))

    indexed_agents
    |> Task.async_stream(
      fn {agent, index} ->
        run_agent(agent, index, contract, context, config, runner, opts)
      end,
      max_concurrency: concurrency,
      timeout: timeout + 5_000,
      ordered: true,
      on_timeout: :kill_task
    )
    |> Enum.zip(indexed_agents)
    |> Enum.map(fn
      {{:ok, result}, _indexed_agent} ->
        result

      {{:exit, reason}, {agent, index}} when reason in [:timeout, {:timeout, nil}] ->
        %{
          agent: agent,
          instance_id: agent_instance_id(agent, index),
          status: :error,
          output: "",
          usage: nil,
          error: %{category: :timeout}
        }

      {{:exit, reason}, {agent, index}} ->
        %{
          agent: agent,
          instance_id: agent_instance_id(agent, index),
          status: :error,
          output: "",
          usage: nil,
          error: %{category: :crash, message: inspect(reason)}
        }
    end)
  end

  defp run_agent(agent, index, contract, context, config, runner, opts) do
    instance_id = agent_instance_id(agent, index)

    rendered_prompt =
      agent.task_prompt
      |> Template.render(
        contract.input
        |> Map.merge(context)
        |> Map.merge(%{
          "agent_name" => agent.name,
          "bench_id" => contract.bench_id,
          "workspace_root" => contract.workspace_root
        })
        |> stringify_keys()
      )

    prompt = "#{agent.system_prompt}\n\n#{rendered_prompt}"
    prompt_file = write_prompt_file(contract, instance_id, prompt)
    {cmd, args} = build_command(agent, prompt_file, tool_list(agent))

    cmd_opts =
      build_cmd_opts(agent, instance_id, contract, config.providers[agent.provider], opts)

    case attempt(agent.retries + 1, fn -> run_once(runner, cmd, args, cmd_opts) end) do
      {:ok, output} ->
        %{
          agent: agent,
          instance_id: instance_id,
          status: :ok,
          output: output,
          usage: nil,
          error: nil
        }

      {:error, %{output: output} = error} ->
        %{
          agent: agent,
          instance_id: instance_id,
          status: :error,
          output: output,
          usage: nil,
          error: Map.delete(error, :output)
        }
    end
  rescue
    error ->
      %{
        agent: agent,
        instance_id: agent_instance_id(agent, index),
        status: :error,
        output: "",
        usage: nil,
        error: %{category: :crash, message: Exception.message(error)}
      }
  end

  defp run_once(runner, cmd, args, cmd_opts) do
    case runner.(cmd, args, cmd_opts) do
      {output, 0} ->
        {:ok, output}

      {output, :timeout} ->
        {:error, %{category: :timeout, output: output}}

      {output, exit_code} ->
        {:error, %{category: :crash, exit_code: exit_code, output: output}}
    end
  end

  defp attempt(remaining, fun) when remaining > 0 do
    case fun.() do
      {:ok, _} = ok ->
        ok

      {:error, error} ->
        if remaining > 1 and retryable?(error) do
          Process.sleep(250)
          attempt(remaining - 1, fun)
        else
          {:error, error}
        end
    end
  end

  defp retryable?(%{category: :timeout}), do: false
  defp retryable?(%{category: :crash}), do: true
  defp retryable?(_), do: false

  defp build_command(agent, prompt_file, tools) do
    {"sh",
     [
       "-c",
       "exec < /dev/null; exec \"$@\"",
       "sh",
       "pi",
       "--no-session",
       "--no-skills",
       "--model",
       agent.model,
       "--thinking",
       agent.thinking_level,
       "--tools",
       Enum.join(tools, ","),
       "-p",
       "@#{prompt_file}"
     ]}
  end

  defp build_cmd_opts(agent, instance_id, contract, provider, opts) do
    provider_env = provider_env(provider)

    [
      stderr_to_stdout: true,
      timeout: agent.timeout_ms,
      env:
        [
          {"PI_CODING_AGENT_DIR",
           build_agent_home(contract, instance_id, opts[:agent_config_dir])}
        ] ++
          provider_env,
      cd: contract.workspace_root
    ]
  end

  defp provider_env(%{adapter: :openrouter} = provider) do
    fallback_env = provider.defaults["fallback_env"]

    key =
      non_empty_env(provider.credential_env) ||
        if(is_binary(fallback_env) and fallback_env != "", do: non_empty_env(fallback_env))

    if is_binary(key) and key != "" do
      [{"OPENROUTER_API_KEY", key}]
    else
      []
    end
  end

  defp provider_env(_), do: []

  defp non_empty_env(name) when is_binary(name) and name != "" do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp non_empty_env(_), do: nil

  defp tool_list(%AgentSpec{tools: tools}) when is_list(tools) and tools != [] do
    sanitize_tools(tools)
  end

  defp tool_list(_), do: @default_tools

  defp sanitize_tools(tools) do
    tools
    |> Enum.filter(&MapSet.member?(@allowed_tools, &1))
    |> Enum.uniq()
  end

  defp write_prompt_file(contract, instance_id, prompt) do
    dir = Path.join(contract.artifact_dir, "prompts")
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{instance_id}.md")
    File.write!(path, prompt)
    path
  end

  defp build_agent_home(contract, instance_id, nil) do
    dir = Path.join([contract.artifact_dir, "pi-home", instance_id])
    File.mkdir_p!(dir)
    dir
  end

  defp build_agent_home(contract, instance_id, base_dir) do
    dir = Path.join([contract.artifact_dir, "pi-home", instance_id])

    unless File.exists?(dir) do
      validate_agent_config_dir!(base_dir)
      File.mkdir_p!(Path.dirname(dir))
      File.cp_r!(base_dir, dir)
    end

    dir
  end

  defp agent_instance_id(%AgentSpec{name: name}, index) do
    suffix =
      :crypto.hash(:sha256, name)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 8)

    "#{safe_name(name)}-#{suffix}-#{index}"
  end

  defp safe_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp validate_agent_config_dir!(base_dir) do
    case File.lstat(base_dir) do
      {:ok, %File.Stat{type: :symlink}} ->
        raise ArgumentError, "agent_config must not be a symlink: #{base_dir}"

      _ ->
        :ok
    end

    base_dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(fn path ->
      case File.lstat(path) do
        {:ok, %File.Stat{type: :symlink}} ->
          raise ArgumentError, "agent_config must not contain symlinks: #{path}"

        _ ->
          :ok
      end
    end)
  end

  defp normalize_concurrency(value, agent_count) when is_integer(value) and value > 0 do
    min(value, max(agent_count, 1))
  end

  defp normalize_concurrency(_, agent_count), do: max(agent_count, 1)

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.into(%{})
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

  @doc false
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

  @doc false
  def muontrap_cmd(cmd, args, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    env = Keyword.get(opts, :env, [])
    cd = Keyword.get(opts, :cd)

    cmd_opts =
      [stderr_to_stdout: true, timeout: timeout, env: env] ++ if(cd, do: [cd: cd], else: [])

    MuonTrap.cmd(cmd, args, cmd_opts)
  end
end
