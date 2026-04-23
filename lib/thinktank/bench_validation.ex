defmodule Thinktank.BenchValidation do
  @moduledoc false

  alias Thinktank.{AgentSpec, BenchSpec, Config, ProviderSpec}

  @openrouter_models_url "https://openrouter.ai/api/v1/models"
  @tools_capability "tools"

  @type report :: %{
          required(:status) => String.t(),
          required(:bench_count) => non_neg_integer(),
          optional(:warnings) => [map()],
          optional(:errors) => [map()]
        }

  @typep capability_entry :: %{
           bench_id: String.t(),
           agent_name: String.t(),
           declared_tools: [String.t()],
           model: String.t(),
           provider_id: String.t()
         }

  @typep probe_key :: {String.t(), String.t()}

  @spec validate(Config.t(), keyword()) :: report()
  def validate(%Config{} = config, opts \\ []) do
    benches = Config.list_benches(config)
    entries = capability_entries(benches, config.agents)
    probe_results = probe_results(entries, config.providers, opts)

    warnings =
      probe_results
      |> Map.values()
      |> Enum.flat_map(fn
        {:warning, warning} -> [warning]
        _ -> []
      end)
      |> Enum.uniq_by(&warning_key/1)

    errors =
      entries
      |> Enum.flat_map(&missing_capability_errors(&1, probe_results))

    %{status: if(errors == [], do: "ok", else: "error"), bench_count: length(benches)}
    |> maybe_put(:warnings, warnings)
    |> maybe_put(:errors, errors)
  end

  @spec capability_entries([BenchSpec.t()], %{String.t() => AgentSpec.t()}) :: [
          capability_entry()
        ]
  defp capability_entries(benches, agents) do
    Enum.flat_map(benches, fn bench ->
      bench_agent_names(bench)
      |> Enum.flat_map(&capability_entry(bench, agents, &1))
    end)
  end

  defp capability_entry(bench, agents, name) do
    case Map.fetch(agents, name) do
      {:ok, %AgentSpec{tools: tools} = agent} when is_list(tools) and tools != [] ->
        [
          %{
            bench_id: bench.id,
            agent_name: name,
            declared_tools: Enum.uniq(tools),
            model: agent.model,
            provider_id: agent.provider
          }
        ]

      _ ->
        []
    end
  end

  defp bench_agent_names(%BenchSpec{} = bench) do
    ([bench.planner] ++ bench.agents ++ [bench.synthesizer])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @spec probe_results([capability_entry()], %{String.t() => ProviderSpec.t()}, keyword()) ::
          %{probe_key() => {:ok, [String.t()]} | {:warning, map()}}
  defp probe_results(entries, providers, opts) do
    keys =
      entries
      |> Enum.map(&probe_key/1)
      |> Enum.uniq()

    max_concurrency =
      opts
      |> Keyword.get(:max_concurrency, 6)
      |> max(1)
      |> min(max(length(keys), 1))

    task_results =
      Task.async_stream(
        keys,
        &probe_key_result(&1, providers, opts),
        max_concurrency: max_concurrency,
        ordered: true,
        timeout: Keyword.get(opts, :probe_timeout_ms, 5_000),
        on_timeout: :kill_task
      )

    Stream.zip(keys, task_results)
    |> Enum.into(%{}, fn
      {key, {:ok, result}} ->
        {key, result}

      {{provider_id, model} = key, {:exit, reason}} ->
        {key, {:warning, provider_probe_failed_warning(provider_id, model, reason)}}
    end)
  end

  @spec probe_key_result(probe_key(), %{String.t() => ProviderSpec.t()}, keyword()) ::
          {:ok, [String.t()]} | {:warning, map()}
  defp probe_key_result({provider_id, model}, providers, opts) do
    provider = Map.fetch!(providers, provider_id)
    probe = Keyword.get(opts, :capability_probe, &default_capability_probe/4)

    case probe.(provider, model, [@tools_capability], opts) do
      {:ok, supported_capabilities} ->
        {:ok, normalize_capabilities(supported_capabilities)}

      {:warning, %{} = warning} ->
        {:warning, Map.put_new(warning, :provider, provider_id)}

      {:error, reason} ->
        {:warning, provider_probe_failed_warning(provider_id, model, reason)}

      other ->
        {:warning,
         provider_probe_failed_warning(provider_id, model, {:unexpected_probe_result, other})}
    end
  end

  defp default_capability_probe(
         %ProviderSpec{adapter: :openrouter} = provider,
         model,
         _required_capabilities,
         opts
       ) do
    with {:ok, api_key} <- provider_api_key(provider, opts),
         :ok <- ensure_http_support(),
         {:ok, body} <- fetch_openrouter_endpoints(model, api_key, opts),
         {:ok, supported_capabilities} <- parse_supported_capabilities(body) do
      {:ok, supported_capabilities}
    else
      {:warning, _warning} = warning ->
        warning

      {:error, reason} ->
        {:warning, provider_probe_failed_warning(provider.id, model, reason)}
    end
  end

  defp default_capability_probe(provider, _model, _required_capabilities, _opts) do
    {:warning,
     %{
       code: "provider_capability_probe_unsupported",
       provider: provider.id,
       message:
         "skipped capability validation for provider #{provider.id} because adapter #{provider.adapter} does not expose a catalog probe"
     }}
  end

  defp provider_api_key(provider, opts) do
    env_reader = Keyword.get(opts, :env_reader, &System.get_env/1)
    fallback_env = provider.defaults["fallback_env"]

    key =
      non_empty_env(env_reader, provider.credential_env) ||
        if(is_binary(fallback_env) and fallback_env != "",
          do: non_empty_env(env_reader, fallback_env)
        )

    if is_binary(key) and key != "" do
      {:ok, key}
    else
      {:warning, missing_credentials_warning(provider)}
    end
  end

  defp missing_credentials_warning(provider) do
    fallback_env = provider.defaults["fallback_env"]

    envs =
      [provider.credential_env, fallback_env]
      |> Enum.filter(&is_binary/1)
      |> Enum.reject(&(&1 == ""))

    %{
      code: "provider_credentials_missing",
      provider: provider.id,
      credential_env: provider.credential_env,
      fallback_env: fallback_env,
      message:
        "skipped capability validation for provider #{provider.id} because #{Enum.join(envs, " and ")} #{if(length(envs) == 1, do: "is", else: "are")} unset; benches were structurally validated only"
    }
  end

  defp ensure_http_support do
    with {:ok, _} <- Application.ensure_all_started(:ssl),
         {:ok, _} <- Application.ensure_all_started(:inets) do
      :ok
    end
  end

  defp fetch_openrouter_endpoints(model, api_key, opts) do
    requester = Keyword.get(opts, :http_requester, &default_http_request/3)
    url = "#{@openrouter_models_url}/#{model}/endpoints"

    headers = [
      {~c"authorization", String.to_charlist("Bearer #{api_key}")},
      {~c"accept", ~c"application/json"}
    ]

    case requester.(url, headers, Keyword.get(opts, :probe_timeout_ms, 5_000)) do
      {:ok, {200, body}} -> {:ok, body}
      {:ok, {status, body}} -> {:error, {:unexpected_status, status, body}}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_http_result, other}}
    end
  end

  defp default_http_request(url, headers, timeout_ms) do
    request = {String.to_charlist(url), headers}
    http_opts = [timeout: timeout_ms, connect_timeout: timeout_ms]

    case :httpc.request(:get, request, http_opts, body_format: :binary) do
      {:ok, {{_http_version, status, _reason_phrase}, _response_headers, body}} ->
        {:ok, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_supported_capabilities(body) when is_binary(body) do
    with {:ok, decoded} <- Jason.decode(body),
         endpoints when is_list(endpoints) <- get_in(decoded, ["data", "endpoints"]) do
      {:ok,
       endpoints
       |> Enum.flat_map(fn endpoint ->
         endpoint
         |> Map.get("supported_parameters", [])
         |> List.wrap()
         |> Enum.filter(&is_binary/1)
       end)
       |> Enum.uniq()}
    else
      {:error, reason} ->
        {:error, {:invalid_json, Exception.message(reason)}}

      other ->
        {:error, {:unexpected_payload, other}}
    end
  end

  defp normalize_capabilities(capabilities) when is_list(capabilities) do
    capabilities
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp normalize_capabilities(_capabilities), do: []

  defp missing_capability_errors(entry, probe_results) do
    case Map.fetch!(probe_results, probe_key(entry)) do
      {:ok, supported_capabilities} ->
        build_missing_capability_errors(entry, supported_capabilities)

      {:warning, _warning} ->
        []
    end
  end

  defp build_missing_capability_errors(entry, supported_capabilities) do
    if @tools_capability in supported_capabilities do
      []
    else
      [missing_capability_error(entry, [@tools_capability])]
    end
  end

  defp missing_capability_error(entry, missing_capabilities) do
    %{
      code: "missing_provider_capability",
      bench: entry.bench_id,
      agent: entry.agent_name,
      provider: entry.provider_id,
      model: entry.model,
      declared_tools: entry.declared_tools,
      missing_capabilities: missing_capabilities,
      message:
        "bench #{entry.bench_id} agent #{entry.agent_name} declares tools #{Enum.join(entry.declared_tools, ", ")} but model #{entry.model} on provider #{entry.provider_id} does not advertise #{Enum.join(missing_capabilities, ", ")} in supported_parameters"
    }
  end

  defp provider_probe_failed_warning(provider_id, model, reason) do
    %{
      code: "provider_capability_probe_failed",
      provider: provider_id,
      model: model,
      message:
        "skipped capability validation for model #{model} on provider #{provider_id} because the catalog probe failed; benches were structurally validated only",
      details: %{reason: format_reason(reason)}
    }
  end

  defp format_reason({:unexpected_status, status, body}),
    do: "HTTP #{status}: #{truncate_body(body)}"

  defp format_reason({:invalid_json, message}), do: "invalid JSON response: #{message}"
  defp format_reason({:unexpected_payload, other}), do: "unexpected payload: #{inspect(other)}"

  defp format_reason({:unexpected_http_result, other}),
    do: "unexpected HTTP result: #{inspect(other)}"

  defp format_reason({:unexpected_probe_result, other}),
    do: "unexpected probe result: #{inspect(other)}"

  defp format_reason(reason), do: inspect(reason)

  defp truncate_body(body) when is_binary(body) and byte_size(body) > 200,
    do: binary_part(body, 0, 200) <> "..."

  defp truncate_body(body) when is_binary(body), do: body
  defp truncate_body(body), do: inspect(body)

  @spec probe_key(capability_entry()) :: probe_key()
  defp probe_key(%{provider_id: provider_id, model: model}) do
    {provider_id, model}
  end

  defp non_empty_env(reader, name) when is_binary(name) and name != "" do
    case reader.(name) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp non_empty_env(_reader, _name), do: nil

  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp warning_key(warning) do
    {Map.get(warning, :code), Map.get(warning, :provider), Map.get(warning, :model),
     Map.get(warning, :details)}
  end
end
