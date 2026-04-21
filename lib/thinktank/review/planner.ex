defmodule Thinktank.Review.Planner do
  @moduledoc false

  alias Thinktank.{AgentSpec, Config, RunContract}
  alias Thinktank.Executor.Agentic

  @type plan :: map()
  @type outcome :: %{
          plan: plan(),
          planner_result: Agentic.result() | nil,
          fallback_reason: String.t() | nil
        }

  @spec manual([AgentSpec.t()]) :: outcome()
  def manual(agents) do
    %{plan: default_plan(agents, "manual"), planner_result: nil, fallback_reason: nil}
  end

  @spec create(
          AgentSpec.t() | nil,
          [AgentSpec.t()],
          RunContract.t(),
          map(),
          Config.t(),
          keyword()
        ) ::
          outcome()
  def create(nil, agents, _contract, _review_context, _config, _opts) do
    %{plan: default_plan(agents, "fallback"), planner_result: nil, fallback_reason: nil}
  end

  def create(planner, agents, contract, review_context, config, opts) do
    context = %{
      "paths_hint" => render_paths_hint(contract.input),
      "review_context" => render_json(review_context),
      "review_roster" => render_roster(agents)
    }

    [planner_result] =
      Agentic.run([planner], contract, context, config,
        concurrency: 1,
        agent_config_dir: opts[:agent_config_dir],
        progress_callback: opts[:progress_callback],
        progress_phase: opts[:progress_phase],
        runner: opts[:runner]
      )

    {plan, fallback_reason} =
      case planner_result.status do
        :ok ->
          case parse_plan(planner_result.output, agents) do
            {:ok, parsed} ->
              {parsed, nil}

            {:error, reason} ->
              fallback_reason = "planner output rejected: #{reason}"
              {default_plan(agents, "fallback", [fallback_reason]), fallback_reason}
          end

        :error ->
          fallback_reason = "planner failed: #{format_error(planner_result.error)}"
          {default_plan(agents, "fallback", [fallback_reason]), fallback_reason}
      end

    %{plan: plan, planner_result: planner_result, fallback_reason: fallback_reason}
  end

  @spec apply_plan(plan(), [AgentSpec.t()]) :: [AgentSpec.t()]
  def apply_plan(plan, agents) do
    indexed_agents =
      agents
      |> Enum.map(&{&1.name, &1})
      |> Map.new()

    selected =
      plan
      |> Map.get("selected_agents", [])
      |> Enum.map(&planned_agent(&1, indexed_agents))
      |> Enum.reject(&is_nil/1)

    if selected == [] do
      Enum.map(agents, &attach_brief(&1, default_brief(&1)))
    else
      selected
    end
  end

  @spec render(plan()) :: String.t()
  def render(plan) do
    reviewers =
      case Map.get(plan, "selected_agents", []) do
        [] ->
          "- none"

        selected ->
          Enum.map_join(selected, "\n", fn agent ->
            name = agent["name"] || "unknown"
            brief = agent["brief"] || ""
            "- #{name}: #{brief}"
          end)
      end

    warnings =
      case Map.get(plan, "warnings", []) do
        [] -> "- none"
        items -> Enum.map_join(items, "\n", &"- #{&1}")
      end

    """
    Review plan:
    - Source: #{Map.get(plan, "source", "unknown")}
    - Summary: #{Map.get(plan, "summary", "No planner summary provided.")}
    - Synth brief:
      #{Map.get(plan, "synthesis_brief", "Use reviewer evidence and suppress overlap.")}

    Selected reviewers:
    #{reviewers}

    Warnings:
    #{warnings}
    """
    |> String.trim()
  end

  defp parse_plan(raw_output, agents) when is_binary(raw_output) do
    allowed = MapSet.new(Enum.map(agents, & &1.name))

    with {:ok, decoded} <- decode_plan(raw_output),
         :ok <-
           validate_allowed_keys(
             decoded,
             ~w(summary selected_agents synthesis_brief warnings),
             "plan"
           ),
         {:ok, summary} <- parse_required_string(decoded, "summary"),
         {:ok, selected} <- parse_selected_agents(decoded["selected_agents"], allowed),
         true <- selected != [] or {:error, "planner selected no reviewers"},
         {:ok, synthesis_brief} <- parse_required_string(decoded, "synthesis_brief"),
         {:ok, warnings} <- parse_warnings(decoded["warnings"]) do
      {:ok,
       %{
         "version" => 1,
         "source" => "planner",
         "summary" => summary,
         "selected_agents" => selected,
         "synthesis_brief" => synthesis_brief,
         "warnings" => warnings
       }}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_plan(raw_output) do
    trimmed = String.trim(raw_output)

    case trimmed do
      "" ->
        {:error, "planner output must be a JSON object"}

      _ ->
        case Jason.decode(trimmed) do
          {:ok, %{} = decoded} -> {:ok, decoded}
          {:ok, _} -> {:error, "planner output must decode to a JSON object"}
          {:error, _} -> {:error, "planner output must be valid JSON"}
        end
    end
  end

  defp parse_selected_agents(selected_agents, allowed) when is_list(selected_agents) do
    selected_agents
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn entry, {:ok, acc, seen} ->
      case parse_selected_agent(entry, allowed, seen) do
        {:ok, parsed_entry, next_seen} ->
          {:cont, {:ok, [parsed_entry | acc], next_seen}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, parsed, _seen} -> {:ok, Enum.reverse(parsed)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_selected_agents(_, _allowed), do: {:error, "selected_agents must be a list"}

  defp parse_selected_agent(%{} = entry, allowed, seen) do
    with :ok <- validate_allowed_keys(entry, ~w(name brief), "selected_agents entry"),
         {:ok, name} <- parse_required_string(entry, "name"),
         true <-
           MapSet.member?(allowed, name) or {:error, "selected agent is not in roster: #{name}"},
         true <-
           not MapSet.member?(seen, name) or
             {:error, "selected_agents must not contain duplicates: #{name}"},
         {:ok, brief} <- parse_required_string(entry, "brief") do
      {:ok, %{"name" => name, "brief" => brief}, MapSet.put(seen, name)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_selected_agent(_, _allowed, _seen),
    do: {:error, "selected_agents entries must be objects"}

  defp parse_warnings(warnings) when is_list(warnings) do
    warnings
    |> Enum.reduce_while({:ok, []}, fn warning, {:ok, acc} ->
      case trimmed_string(warning) do
        nil ->
          {:halt, {:error, "warnings entries must be non-empty strings"}}

        value ->
          {:cont, {:ok, [value | acc]}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_warnings(_), do: {:error, "warnings must be a list"}

  defp parse_required_string(map, key) do
    case trimmed_string(map[key]) do
      nil -> {:error, "#{key} must be a non-empty string"}
      value -> {:ok, value}
    end
  end

  defp validate_allowed_keys(map, allowed_keys, label) do
    allowed = MapSet.new(allowed_keys)

    unsupported =
      map
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(allowed, &1))
      |> Enum.sort()

    if unsupported == [] do
      :ok
    else
      {:error, "#{label} has unsupported keys: #{Enum.join(unsupported, ", ")}"}
    end
  end

  defp default_plan(agents, source, warnings \\ []) do
    %{
      "version" => 1,
      "source" => source,
      "summary" => "Use the bench defaults for this review run.",
      "selected_agents" =>
        Enum.map(agents, fn agent ->
          %{
            "name" => agent.name,
            "brief" => default_brief(agent)
          }
        end),
      "synthesis_brief" => "Prioritize grounded findings and collapse duplicates.",
      "warnings" => warnings
    }
  end

  defp render_roster(agents) do
    Enum.map_join(agents, "\n", fn agent ->
      role = get_in(agent.metadata, ["review_role"]) || "reviewer"
      summary = first_sentence(agent.system_prompt)
      "- #{agent.name} (#{role}, #{agent.model}): #{summary}"
    end)
  end

  defp attach_brief(agent, brief) do
    %{agent | metadata: Map.put(agent.metadata, "review_brief", brief)}
  end

  defp planned_agent(agent_plan, indexed_agents) do
    case {trimmed_string(agent_plan["name"]), trimmed_string(agent_plan["brief"])} do
      {nil, _brief} ->
        nil

      {name, brief} ->
        case Map.get(indexed_agents, name) do
          nil -> nil
          agent -> attach_brief(agent, brief || default_brief(agent))
        end
    end
  end

  defp default_brief(%AgentSpec{} = agent) do
    role = get_in(agent.metadata, ["review_role"]) || "review"
    "Focus on the highest-signal #{role} risks in the change and report only grounded issues."
  end

  defp first_sentence(text) when is_binary(text) do
    text
    |> String.split(~r/(?<=[.!?])\s+/, parts: 2)
    |> List.first()
    |> to_string()
    |> String.trim()
  end

  defp first_sentence(_), do: ""

  defp format_error(nil), do: "unknown error"
  defp format_error(error) when is_map(error), do: inspect(error)

  defp render_paths_hint(input) when is_map(input) do
    case Map.get(input, "paths", []) do
      [] -> "- none specified"
      paths -> Enum.map_join(paths, "\n", &"- #{&1}")
    end
  end

  defp render_json(value), do: Jason.encode!(value, pretty: true)

  defp trimmed_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp trimmed_string(_), do: nil
end
