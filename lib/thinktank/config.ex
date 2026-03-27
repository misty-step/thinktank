defmodule Thinktank.Config do
  @moduledoc """
  Loads built-in, user, and repository workflow configuration with typed validation.
  """

  alias Thinktank.{AgentSpec, Builtin, ProviderSpec, WorkflowSpec}

  defstruct [:providers, :agents, :workflows, :sources]

  @type t :: %__MODULE__{
          providers: %{String.t() => ProviderSpec.t()},
          agents: %{String.t() => AgentSpec.t()},
          workflows: %{String.t() => WorkflowSpec.t()},
          sources: map()
        }

  @spec load(keyword()) :: {:ok, t()} | {:error, String.t()}
  def load(opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    trust_repo_config = Keyword.get(opts, :trust_repo_config, trust_repo_config?())

    user_path =
      Keyword.get(opts, :user_config_path, Path.join(user_config_dir(opts), "config.yml"))

    repo_path = Keyword.get(opts, :repo_config_path, Path.join(cwd, ".thinktank/config.yml"))

    with {:ok, user_raw} <- load_yaml_if_present(user_path),
         {:ok, repo_raw} <- load_repo_yaml(repo_path, trust_repo_config) do
      repo_raw = sanitize_repo_config(repo_raw, trust_repo_config)

      raw =
        Builtin.raw_config()
        |> deep_merge(user_raw)
        |> deep_merge(repo_raw)

      build(raw, %{user: user_path, repo: repo_path})
    end
  end

  @spec workflow(t(), String.t()) :: {:ok, WorkflowSpec.t()} | {:error, String.t()}
  def workflow(%__MODULE__{workflows: workflows}, id) do
    case Map.fetch(workflows, id) do
      {:ok, workflow} -> {:ok, workflow}
      :error -> {:error, "unknown workflow: #{id}"}
    end
  end

  @spec list_workflows(t()) :: [WorkflowSpec.t()]
  def list_workflows(%__MODULE__{workflows: workflows}) do
    workflows |> Map.values() |> Enum.sort_by(& &1.id)
  end

  @spec user_config_dir(keyword()) :: String.t()
  def user_config_dir(opts \\ []) do
    home = Keyword.get(opts, :user_home, System.user_home!())
    Path.join([home, ".config", "thinktank"])
  end

  defp build(raw, sources) do
    with {:ok, providers} <- build_providers(Map.get(raw, "providers", %{})),
         {:ok, agents} <- build_agents(Map.get(raw, "agents", %{})),
         {:ok, workflows} <- build_workflows(Map.get(raw, "workflows", %{})),
         :ok <- validate_references(workflows, agents, providers) do
      {:ok,
       %__MODULE__{providers: providers, agents: agents, workflows: workflows, sources: sources}}
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

  defp build_agents(raw) when is_map(raw) do
    Enum.reduce_while(raw, {:ok, %{}}, fn {name, spec}, {:ok, acc} ->
      case AgentSpec.from_pair(name, spec) do
        {:ok, agent} -> {:cont, {:ok, Map.put(acc, name, agent)}}
        {:error, reason} -> {:halt, {:error, "agent #{name}: #{reason}"}}
      end
    end)
  end

  defp build_agents(_), do: {:error, "agents must be a map"}

  defp build_workflows(raw) when is_map(raw) do
    Enum.reduce_while(raw, {:ok, %{}}, fn {id, spec}, {:ok, acc} ->
      case WorkflowSpec.from_pair(id, spec) do
        {:ok, workflow} -> {:cont, {:ok, Map.put(acc, id, workflow)}}
        {:error, reason} -> {:halt, {:error, "workflow #{id}: #{reason}"}}
      end
    end)
  end

  defp build_workflows(_), do: {:error, "workflows must be a map"}

  defp validate_references(workflows, agents, providers) do
    with :ok <- validate_agent_providers(agents, providers) do
      Enum.reduce_while(workflows, :ok, fn {_id, workflow}, :ok ->
        case validate_stage_references(workflow.stages, agents) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
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

  defp validate_stage_references(stages, agents) do
    Enum.reduce_while(stages, :ok, fn stage, :ok ->
      case stage.kind do
        "static_agents" ->
          with :ok <- validate_named_agents_option(stage.options["agents"], agents, "agents") do
            {:cont, :ok}
          else
            {:error, reason} -> {:halt, {:error, reason}}
          end

        "cerberus_review" ->
          with :ok <- validate_panel_size(stage.options["panel_size"]),
               :ok <-
                 validate_named_agents_option(
                   stage.options["always_include"],
                   agents,
                   "always_include"
                 ),
               :ok <-
                 validate_named_agents_option(
                   stage.options["include_if_code_changed"],
                   agents,
                   "include_if_code_changed"
                 ),
               :ok <-
                 validate_named_agents_option(
                   stage.options["fallback_panel"],
                   agents,
                   "fallback_panel"
                 ) do
            {:cont, :ok}
          else
            {:error, reason} -> {:halt, {:error, reason}}
          end

        _ ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_named_agents_option(nil, _agents, _field), do: :ok

  defp validate_named_agents_option(agent_names, agents, _field) when is_list(agent_names) do
    case validate_named_agents(agent_names, agents) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_named_agents_option(_value, _agents, field),
    do: {:error, "workflow option #{field} must be a list of agent names"}

  defp validate_panel_size(nil), do: :ok
  defp validate_panel_size(value) when is_integer(value) and value > 0, do: :ok

  defp validate_panel_size(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> :ok
      _ -> {:error, "workflow option panel_size must be a positive integer"}
    end
  end

  defp validate_panel_size(_value),
    do: {:error, "workflow option panel_size must be a positive integer"}

  defp load_repo_yaml(_path, false), do: {:ok, %{}}
  defp load_repo_yaml(path, true), do: load_yaml_if_present(path)

  defp validate_named_agents(agent_names, agents) when is_list(agent_names) do
    case Enum.find(agent_names, &(not Map.has_key?(agents, &1))) do
      nil -> :ok
      missing -> {:error, "workflow references unknown agent #{missing}"}
    end
  end

  defp validate_named_agents(_, _agents), do: :ok

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

  defp sanitize_repo_config(raw, true), do: raw

  defp sanitize_repo_config(raw, false) do
    raw
    |> Map.delete("providers")
    |> Map.delete("agents")
    |> Map.delete("workflows")
  end

  defp trust_repo_config? do
    System.get_env("THINKTANK_TRUST_REPO_CONFIG") in ["1", "true", "TRUE", "yes", "YES"]
  end
end
