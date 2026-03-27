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
  def run(agents, %RunContract{} = contract, context, %Config{} = config, opts \\ []) do
    runner = Keyword.get(opts, :runner, Thinktank.Dispatch.Deep.default_runner())
    timeout = Enum.max(Enum.map(agents, & &1.timeout_ms), fn -> :timer.minutes(30) end)

    tasks =
      Enum.map(agents, fn agent ->
        Task.Supervisor.async_nolink(Thinktank.AgentSupervisor, fn ->
          run_agent(agent, contract, context, config, runner, opts)
        end)
      end)

    tasks
    |> Task.yield_many(timeout + 5_000)
    |> Enum.zip(agents)
    |> Enum.map(fn
      {{_task, {:ok, result}}, _agent} ->
        result

      {{task, nil}, agent} ->
        Task.shutdown(task, :brutal_kill)
        %{agent: agent, status: :error, output: "", usage: nil, error: %{category: :timeout}}

      {{_task, {:exit, reason}}, agent} ->
        %{
          agent: agent,
          status: :error,
          output: "",
          usage: nil,
          error: %{category: :crash, message: inspect(reason)}
        }
    end)
  end

  defp run_agent(agent, contract, context, config, runner, opts) do
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

    shell_cmd = build_shell_cmd(agent, prompt, tool_list(agent))
    cmd_opts = build_cmd_opts(agent, config.providers[agent.provider], opts)

    case runner.("sh", ["-c", shell_cmd], cmd_opts) do
      {output, 0} ->
        %{agent: agent, status: :ok, output: output, usage: nil, error: nil}

      {output, :timeout} ->
        %{agent: agent, status: :error, output: output, usage: nil, error: %{category: :timeout}}

      {output, exit_code} ->
        %{
          agent: agent,
          status: :error,
          output: output,
          usage: nil,
          error: %{category: :crash, exit_code: exit_code}
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

  defp build_shell_cmd(agent, prompt, tools) do
    escaped_prompt = prompt |> String.replace("'", "'\\''")
    escaped_model = agent.model |> String.replace("'", "'\\''")

    "exec pi --no-session --no-skills --model '#{escaped_model}'" <>
      " --tools #{Enum.join(tools, ",")} -p '#{escaped_prompt}' < /dev/null"
  end

  defp build_cmd_opts(agent, provider, opts) do
    base_env = maybe_agent_config_env(opts[:agent_config_dir] || Thinktank.CLI.agent_config_dir())
    provider_env = provider_env(provider)

    timeout = agent.timeout_ms

    [stderr_to_stdout: true, timeout: timeout, env: base_env ++ provider_env]
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
  defp tool_list(%AgentSpec{tool_profile: "research"}), do: ["read", "grep", "find", "bash"]
  defp tool_list(%AgentSpec{tool_profile: "review"}), do: ["read", "grep", "find", "ls"]
  defp tool_list(_), do: ["read", "grep", "find"]

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.into(%{})
  end
end
