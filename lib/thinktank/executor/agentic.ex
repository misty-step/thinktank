defmodule Thinktank.Executor.Agentic do
  @moduledoc """
  Pi subprocess executor for tool-using agent runs.
  """

  alias Thinktank.{AgentSpec, Config, RunContract, Template}

  @type result :: %{
          agent: AgentSpec.t(),
          status: :ok | :error,
          output: String.t(),
          usage: map() | nil,
          error: map() | nil
        }

  @spec run([AgentSpec.t()], RunContract.t(), map(), Config.t(), keyword()) :: [result()]
  def run(agents, contract, context, config, opts \\ [])

  def run([], %RunContract{}, _context, %Config{}, _opts), do: []

  def run(agents, %RunContract{} = contract, context, %Config{} = config, opts) do
    runner = Keyword.get(opts, :runner) || default_runner()
    timeout = Enum.max(Enum.map(agents, & &1.timeout_ms), fn -> :timer.minutes(30) end)

    concurrency =
      Keyword.get(opts, :concurrency, length(agents)) |> normalize_concurrency(length(agents))

    agents
    |> Enum.with_index(1)
    |> Task.async_stream(
      fn {agent, index} ->
        run_agent(agent, index, contract, context, config, runner, opts)
      end,
      max_concurrency: concurrency,
      timeout: timeout + 5_000,
      ordered: true,
      on_timeout: :kill_task
    )
    |> Enum.zip(agents)
    |> Enum.map(fn
      {{:ok, result}, _agent} ->
        result

      {{:exit, reason}, agent} when reason in [:timeout, {:timeout, nil}] ->
        %{agent: agent, status: :error, output: "", usage: nil, error: %{category: :timeout}}

      {{:exit, reason}, agent} ->
        %{
          agent: agent,
          status: :error,
          output: "",
          usage: nil,
          error: %{category: :crash, message: inspect(reason)}
        }
    end)
  end

  defp run_agent(agent, index, contract, context, config, runner, opts) do
    rendered_prompt =
      agent.prompt
      |> Template.render(
        contract.input
        |> Map.merge(context)
        |> Map.merge(%{
          "agent_name" => agent.name,
          "workflow_id" => contract.workflow_id,
          "workspace_root" => contract.workspace_root
        })
        |> stringify_keys()
      )

    prompt = "#{agent.system_prompt}\n\n#{rendered_prompt}"

    prompt_file = write_prompt_file(contract, agent, index, prompt)
    {cmd, args} = build_command(agent, prompt_file, tool_list(agent))
    cmd_opts = build_cmd_opts(agent, index, contract, config.providers[agent.provider], opts)

    case attempt(agent.retries + 1, fn -> run_once(runner, cmd, args, cmd_opts) end) do
      {:ok, output} ->
        %{agent: agent, status: :ok, output: output, usage: nil, error: nil}

      {:error, %{output: output} = error} ->
        %{
          agent: agent,
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

  defp retryable?(%{category: category}) when category in [:timeout, :crash], do: true
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
       "--tools",
       Enum.join(tools, ","),
       "-p",
       "@#{prompt_file}"
     ]}
  end

  defp build_cmd_opts(agent, index, contract, provider, opts) do
    base_env =
      maybe_agent_config_env(build_agent_home(contract, agent, index, opts[:agent_config_dir]))

    provider_env = provider_env(provider)

    timeout = agent.timeout_ms

    [
      stderr_to_stdout: true,
      timeout: timeout,
      env: base_env ++ provider_env,
      cd: contract.workspace_root
    ]
  end

  defp maybe_agent_config_env(nil), do: []
  defp maybe_agent_config_env(dir), do: [{"PI_CODING_AGENT_DIR", dir}]

  defp provider_env(%{adapter: :openrouter} = provider) do
    fallback_env = provider.defaults["fallback_env"]

    key =
      System.get_env(provider.credential_env) ||
        if(is_binary(fallback_env) and fallback_env != "", do: System.get_env(fallback_env))

    if is_binary(key) and key != "" do
      [{"OPENROUTER_API_KEY", key}]
    else
      []
    end
  end

  defp provider_env(_), do: []

  defp tool_list(%AgentSpec{tools: tools}) when is_list(tools) and tools != [], do: tools
  defp tool_list(%AgentSpec{tool_profile: "research"}), do: ["read", "grep", "find", "ls"]
  defp tool_list(%AgentSpec{tool_profile: "review"}), do: ["read", "grep", "find", "ls"]
  defp tool_list(_), do: ["read", "grep", "find"]

  defp write_prompt_file(contract, agent, index, prompt) do
    dir = Path.join(contract.artifact_dir, "prompts")
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{agent_slug(agent, index)}.md")
    File.write!(path, prompt)
    path
  end

  defp build_agent_home(contract, agent, index, nil) do
    dir = Path.join([contract.artifact_dir, "pi-home", agent_slug(agent, index)])
    File.mkdir_p!(dir)
    dir
  end

  defp build_agent_home(contract, agent, index, base_dir) do
    dir = Path.join([contract.artifact_dir, "pi-home", agent_slug(agent, index)])

    unless File.exists?(dir) do
      validate_agent_config_dir!(base_dir)
      File.mkdir_p!(Path.dirname(dir))
      File.cp_r!(base_dir, dir)
    end

    dir
  end

  defp agent_slug(%AgentSpec{name: name}, index) do
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
    script = :escript.script_name() |> List.to_string()

    cond do
      script == "" ->
        Thinktank.Dispatch.Deep.default_runner()

      script == "mix" ->
        Thinktank.Dispatch.Deep.default_runner()

      Path.basename(script) == "mix" ->
        Thinktank.Dispatch.Deep.default_runner()

      true ->
        &Thinktank.Dispatch.Deep.system_cmd/3
    end
  end
end
