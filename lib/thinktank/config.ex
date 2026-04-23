defmodule Thinktank.Config do
  @moduledoc """
  Loads built-in, user, and repository bench configuration with typed validation.
  """

  alias Thinktank.{AgentSpec, BenchSpec, Builtin, ProviderSpec}

  defstruct [:providers, :agents, :benches, :sources]

  @type t :: %__MODULE__{
          providers: %{String.t() => ProviderSpec.t()},
          agents: %{String.t() => AgentSpec.t()},
          benches: %{String.t() => BenchSpec.t()},
          sources: map()
        }

  @spec load(keyword()) :: {:ok, t()} | {:error, String.t()}
  def load(opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    trust_repo_config =
      case Keyword.get(opts, :trust_repo_config) do
        nil -> trust_repo_config?()
        value -> value
      end

    user_path =
      Keyword.get(opts, :user_config_path, Path.join(user_config_dir(opts), "config.yml"))

    repo_path = Keyword.get(opts, :repo_config_path, Path.join(cwd, ".thinktank/config.yml"))

    with {:ok, user_raw} <- load_yaml_if_present(user_path),
         {:ok, repo_raw} <- load_repo_yaml(repo_path, trust_repo_config) do
      raw =
        Builtin.raw_config()
        |> deep_merge(user_raw)
        |> deep_merge(repo_raw)

      build(raw, %{user: user_path, repo: repo_path})
    end
  end

  @spec bench(t(), String.t()) :: {:ok, BenchSpec.t()} | {:error, String.t()}
  def bench(%__MODULE__{benches: benches}, id) do
    case Map.fetch(benches, id) do
      {:ok, bench} -> {:ok, bench}
      :error -> {:error, "unknown bench: #{id}"}
    end
  end

  @spec list_benches(t()) :: [BenchSpec.t()]
  def list_benches(%__MODULE__{benches: benches}) do
    benches |> Map.values() |> Enum.sort_by(& &1.id)
  end

  @spec user_config_dir(keyword()) :: String.t()
  def user_config_dir(opts \\ []) do
    home = Keyword.get(opts, :user_home, System.user_home!())
    Path.join([home, ".config", "thinktank"])
  end

  @spec trust_repo_agent_config?() :: boolean()
  def trust_repo_agent_config? do
    System.get_env("THINKTANK_TRUST_REPO_AGENT_CONFIG") in ["1", "true", "TRUE", "yes", "YES"]
  end

  defp build(raw, sources) do
    agent_defaults = get_in(raw, ["defaults", "agent"])

    with {:ok, providers} <- build_providers(Map.get(raw, "providers", %{})),
         {:ok, agents} <- build_agents(Map.get(raw, "agents", %{}), agent_defaults),
         {:ok, benches} <- build_benches(Map.get(raw, "benches", %{})),
         :ok <- validate_references(benches, agents, providers) do
      {:ok, %__MODULE__{providers: providers, agents: agents, benches: benches, sources: sources}}
    end
  end

  defp build_providers(raw) when is_map(raw) do
    Enum.reduce_while(raw, {:ok, %{}}, fn {id, spec}, {:ok, acc} ->
      case ProviderSpec.from_pair(id, spec) do
        {:ok, provider} -> {:cont, {:ok, Map.put(acc, id, provider)}}
        {:error, reason} -> {:halt, {:error, "provider #{id}: #{reason}"}}
      end
    end)
  end

  defp build_providers(_), do: {:error, "providers must be a map"}

  defp build_agents(raw, defaults) when is_map(raw) do
    Enum.reduce_while(raw, {:ok, %{}}, fn {name, spec}, {:ok, acc} ->
      case AgentSpec.from_pair(name, spec, defaults || %{}) do
        {:ok, agent} -> {:cont, {:ok, Map.put(acc, name, agent)}}
        {:error, reason} -> {:halt, {:error, "agent #{name}: #{reason}"}}
      end
    end)
  end

  defp build_agents(_raw, _defaults), do: {:error, "agents must be a map"}

  defp build_benches(raw) when is_map(raw) do
    Enum.reduce_while(raw, {:ok, %{}}, fn {id, spec}, {:ok, acc} ->
      case BenchSpec.from_pair(id, spec) do
        {:ok, bench} -> {:cont, {:ok, Map.put(acc, id, bench)}}
        {:error, reason} -> {:halt, {:error, "bench #{id}: #{reason}"}}
      end
    end)
  end

  defp build_benches(_), do: {:error, "benches must be a map"}

  defp validate_references(benches, agents, providers) do
    with :ok <- validate_agent_providers(agents, providers) do
      validate_bench_references(benches, agents)
    end
  end

  defp validate_agent_providers(agents, providers) do
    Enum.reduce_while(agents, :ok, fn {name, agent}, :ok ->
      if Map.has_key?(providers, agent.provider) do
        {:cont, :ok}
      else
        {:halt, {:error, "agent #{name} references unknown provider #{agent.provider}"}}
      end
    end)
  end

  defp validate_bench_references(benches, agents) do
    Enum.reduce_while(benches, :ok, fn {_id, bench}, :ok ->
      case bench_reference_error(bench, agents) do
        nil -> {:cont, :ok}
        reason -> {:halt, {:error, "bench #{bench.id}: #{reason}"}}
      end
    end)
  end

  defp bench_reference_error(bench, agents) do
    case validate_named_agents(bench.agents, agents) do
      :ok ->
        with :ok <- validate_optional_agent(bench.planner, agents, "planner"),
             :ok <- validate_optional_agent(bench.synthesizer, agents, "synthesizer") do
          nil
        else
          {:error, reason} -> reason
        end

      {:error, reason} ->
        reason
    end
  end

  defp validate_named_agents(agent_names, agents) when is_list(agent_names) do
    case Enum.find(agent_names, &(not Map.has_key?(agents, &1))) do
      nil -> :ok
      missing -> {:error, "bench references unknown agent #{missing}"}
    end
  end

  defp validate_named_agents(_, _agents),
    do: {:error, "bench agents must be a list of agent names"}

  defp validate_optional_agent(nil, _agents, _field), do: :ok

  defp validate_optional_agent(agent_name, agents, _field) when is_binary(agent_name) do
    if Map.has_key?(agents, agent_name) do
      :ok
    else
      {:error, "bench references unknown agent #{agent_name}"}
    end
  end

  defp validate_optional_agent(_, _agents, field),
    do: {:error, "bench #{field} must be an agent name"}

  defp load_repo_yaml(_path, false), do: {:ok, %{}}
  defp load_repo_yaml(path, true), do: load_yaml_if_present(path)

  defp load_yaml_if_present(path) do
    if File.exists?(path) do
      case YamlElixir.read_from_file(path) do
        {:ok, %{} = yaml} -> {:ok, yaml}
        {:ok, nil} -> {:ok, %{}}
        {:ok, _other} -> {:error, "config file #{path} must contain a YAML mapping"}
        {:error, reason} -> {:error, "failed to read config file #{path}: #{inspect(reason)}"}
      end
    else
      {:ok, %{}}
    end
  end

  defp deep_merge(%{} = left, %{} = right) do
    Map.merge(left, right, fn _key, lval, rval ->
      if is_map(lval) and is_map(rval), do: deep_merge(lval, rval), else: rval
    end)
  end

  defp trust_repo_config? do
    System.get_env("THINKTANK_TRUST_REPO_CONFIG") in ["1", "true", "TRUE", "yes", "YES"]
  end
end
