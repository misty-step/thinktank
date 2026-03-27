defmodule Thinktank.Executor.Direct do
  @moduledoc """
  Direct API executor for lightweight parallel agent runs.
  """

  alias Thinktank.{AgentSpec, Config, OpenRouter, RunContract, Template}
  alias Thinktank.Review.Verdict

  @type result :: %{
          agent: AgentSpec.t(),
          status: :ok | :error,
          output: String.t(),
          usage: map() | nil,
          error: map() | nil
        }

  @spec run([AgentSpec.t()], RunContract.t(), map(), Config.t(), keyword()) :: [result()]
  def run(agents, %RunContract{} = contract, context, %Config{} = config, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, max(length(agents), 1))
    openrouter_opts = Keyword.get(opts, :openrouter_opts, [])

    agents
    |> Task.async_stream(
      fn agent -> run_agent(agent, contract, context, config, openrouter_opts) end,
      max_concurrency: concurrency,
      timeout: Enum.max(Enum.map(agents, & &1.timeout_ms), fn -> :timer.minutes(5) end),
      on_timeout: :kill_task
    )
    |> Enum.zip(agents)
    |> Enum.map(fn
      {{:ok, result}, _agent} ->
        result

      {{:exit, :timeout}, agent} ->
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

  defp run_agent(agent, contract, context, config, openrouter_opts) do
    prompt = build_prompt(agent, contract, context)
    provider = config.providers[agent.provider]
    provider_opts = provider_opts(provider)

    attempt(agent.retries + 1, fn ->
      case provider.adapter do
        :openrouter ->
          case call_openrouter(agent, contract, prompt, provider_opts ++ openrouter_opts) do
            {:ok, text, usage} ->
              {:ok, %{agent: agent, status: :ok, output: text || "", usage: usage, error: nil}}

            {:error, error} ->
              {:error, error}
          end

        other ->
          {:error,
           %{category: :unsupported_provider, message: "unsupported provider adapter #{other}"}}
      end
    end)
    |> case do
      {:ok, result} ->
        result

      {:error, error} ->
        %{agent: agent, status: :error, output: "", usage: nil, error: error}
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

  defp retryable?(%{category: category}) when category in [:transport, :rate_limit], do: true
  defp retryable?(%{category: :api_error, status: status}) when status >= 500, do: true
  defp retryable?(_), do: false

  defp build_prompt(agent, %RunContract{} = contract, context) do
    vars =
      contract.input
      |> Map.merge(context)
      |> Map.merge(%{
        "agent_name" => agent.name,
        "workflow_id" => contract.workflow_id,
        "workspace_root" => contract.workspace_root
      })

    Template.render(agent.prompt, stringify_keys(vars))
  end

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.into(%{})
  end

  defp provider_opts(provider) do
    fallback_env = provider.defaults["fallback_env"]

    key =
      System.get_env(provider.credential_env) ||
        if(is_binary(fallback_env) and fallback_env != "", do: System.get_env(fallback_env))

    if is_binary(key) and key != "", do: [api_key: key], else: []
  end

  defp call_openrouter(agent, contract, prompt, opts) do
    if structured_review?(agent, contract) do
      case OpenRouter.chat_structured(
             agent.model,
             agent.system_prompt,
             prompt,
             Verdict.json_schema(),
             opts
           ) do
        {:ok, map, usage} -> {:ok, Jason.encode!(map, pretty: true), usage}
        {:error, error} -> {:error, error}
      end
    else
      OpenRouter.chat(agent.model, agent.system_prompt, prompt, opts)
    end
  end

  defp structured_review?(%AgentSpec{tool_profile: "review"}, %RunContract{
         workflow_id: "review/cerberus"
       }),
       do: true

  defp structured_review?(_, _), do: false
end
